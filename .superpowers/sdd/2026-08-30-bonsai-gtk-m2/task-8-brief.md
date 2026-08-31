### Task 8: Notebook — the first container with a real reorder

Third and last of the keyed containers, and the one Task 2's `Unordered` marker was designed against: `GtkNotebook` has `reorder_child`, so it takes `move = Some` and its children genuinely move.

**Files:**
- Modify: `vtree/attr.ml(i)`, `vtree/kind.ml(i)`, `vtree/node.ml(i)`, `vtree/defaults.ml`, `vtree/events.ml`, `src/patcher.ml`, `src/widgets/registry.ml`, `src/live_tree.ml`, `test_lib/bonsai_gtk_test.ml(i)`, `test/test_widgets.ml`, `test/handle/test_handle.ml`, `test/live/live_lists.ml`
- Create: `src/widgets/w_notebook.ml`

**Interfaces:**
- Produces:
  ```ocaml
  val notebook
    :  ?key:Key.t -> ?attrs:Attr.t list
    -> ?scrollable:bool
    -> ?show_tabs:bool
    -> ?show_border:bool
    -> current_page:Key.t
    -> t list
    -> t

  val tab_label : string -> Attr.t     (* on a notebook child *)
  val on_page_changed : Key.t Handler.t -> Attr.t
  ```
- Consumes: `W.Notebook.{new_,insert_page,remove_page,page_num,get_n_pages,get_nth_page,set_current_page,get_current_page,set_tab_label_text,reorder_child,set_scrollable,set_show_tabs,set_show_border,on_switch_page}`.

**Four things this widget does differently from the other two, each because GTK does:**

1. **Pages are addressed by *index*, not by widget.** `remove_page` takes an int; `insert_page` takes an int and returns one; `reorder_child` takes a widget and an int. So every operation begins with `page_num nb child`, which is GTK's own answer and is the right one here — a notebook interposes nothing, its children *are* the pages' content widgets. `Child_keys` is keyed on the content widget rather than on a wrapper, which is the one place the three containers differ.

2. **`insert_page` returns the new index and takes the tab label as an option, fourth-argument-last.** `ignore (W.Notebook.insert_page nb child (Some label) index : int)`. Getting the argument order wrong typechecks in exactly one wrong way (`Widget.t option` and `int` are distinct, so it does not — good) and the `int` result is easy to forget.

3. **The tab label is a *widget* GTK owns**, and `set_tab_label_text` builds a `GtkLabel` for it. `Attr.tab_label` is therefore a `string`, not a node: a node would mean a second child list, a second patch path and a second lifetime for something that is always a label. An application that wants a tab with an icon has `Node.native`; say so on the attr.

4. **`current_page` is controlled and, like the others, applied from the fixup queue.** `on_switch_page`'s callback carries `~page:Widget.t ~page_num:int` — the *content widget*, not a `Notebook_page.t` — so `Child_keys` maps it and the handler gets a key. Note that GTK emits `switch-page` during `insert_page` of the first page, which happens inside the patch: the `in_patch` guard swallows it, and the live test asserts that (`scheduled` unchanged across a mount).

**And one it does the same:** a page whose `~key` is missing is rejected by the constructor, and `~current_page` naming no page **raises**, unlike a list box's selection and like a stack's `~visible_child`. The rule is now statable in one sentence, and `Node.notebook`, `Node.stack` and `Node.list_box` should each carry it: *a container that shows exactly one of its children raises when told to show one that does not exist; a container with a plural selection ignores the keys it cannot find.* Put that sentence in all three docs, identically.

- [ ] **Step 1: Write the failing tests**

`test/test_widgets.ml` — constructors, the `~tab_label` attr on children, defaults.

`test/handle/test_handle.ml` — a two-page notebook whose `current_page` is model state, with `Set_page` driving it.

`test/live/live_lists.ml` — append:

```ocaml
  (* 1. Pages, tab labels, and which is current. *)
  (* 2. A real reorder. This is the first container in the library where [Move] does
        something: the same three pages in a new order, asserting both that the tab order
        changed in the dump *and* that the page widgets are the same GObjects. The overlay
        case in live_containers.ml is the mirror image -- same GObjects, order unchanged --
        and between them they say what [list_ops.move = None] means. *)
  (* 3. The declined page change: the user clicks tab 3, the model re-renders page 1. *)
  (* 4. Add a page and make it current in one frame. *)
  (* 5. Remove the current page. GTK picks a neighbour; the model still says the old key;
        the fixup then raises, because ~current_page names no page -- which is the
        documented behaviour and is the *application's* bug (it removed a page without
        moving its selection). Assert the raise and its message. *)
  (* 6. Mounting a notebook fires no handler, though GTK emits switch-page while pages are
        being inserted. *)
```

Case 5 deserves a moment's thought before it is written: is raising right? A model that removes the current page without choosing a new one has an inconsistent view, and every frame after it renders the same inconsistency, so a silent ignore would leave the notebook showing whatever GTK picked while the model believed something else — the divergence spec §6.5 exists to prevent. Raising is loud and points at the render. **If the implementer disagrees after writing it, say so in the report**; it is a genuine judgement call and the alternative (clamp to GTK's choice and let the model see it through `on_page_changed`) is defensible.

- [ ] **Step 2–6: implement.** `w_notebook.ml`, following `w_list_box.ml`'s shape with the four differences above. `list_ops.move = Some (fun parent ~child ~after -> W.Notebook.reorder_child (cast parent) child (index_after parent after))` where `index_after` is `0` for `None` and `page_num parent w + 1` otherwise — note that `reorder_child`'s index is the *destination* index in the list with the child still in it, so check GTK's semantics against the live test rather than trusting this line.

- [ ] **Step 7: `placement_attrs_read_by`** gains `| Notebook _ -> [ Tab_label ]`.

- [ ] **Step 8: `Live_tree`** — a `"GtkNotebook"` arm printing `pages`, `current-page`, and `show-tabs`/`show-border`/`scrollable` when not default. The tab labels appear in the dump anyway, as the `GtkLabel` children GTK made.

- [ ] **Step 9: Run, read, promote, gate, commit**

```bash
./scripts/ci.sh
dune fmt 2>/dev/null; git add vtree src test test_lib
GIT_EDITOR=true git commit -F - <<'MSG'
Notebook: keyed pages, and the first container whose children really move

GtkNotebook has reorder_child, so it takes [list_ops.move = Some] and
Reconcile emits Move ops for it -- the case Task 2's unordered marker was
designed against. Its pages are addressed by index rather than by widget, which
is why every operation starts at page_num, and its Child_keys table is keyed on
the page's content widget rather than on a wrapper this impl made.

~current_page is controlled and applied from the fixup pass, and names a page
that must exist: a container showing exactly one of its children raises when
told to show one that is not there, where a container with a plural selection
ignores keys it cannot find. Stack, Notebook and ListBox now each say that in
their own docs.

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01Sg3Ci8U8kUKR8C3PL1pNSs
MSG
```

**Review focus:** that `reorder_child`'s index semantics were checked against GTK rather than assumed; that the reorder test asserts *both* the new order and the same GObjects; that the `in_patch` guard really does swallow the `switch-page` GTK emits during a mount (case 6 is the proof); that the one-sentence show-exactly-one/plural-selection rule appears verbatim in all three constructors' docs.

---

