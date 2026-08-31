### Task 3: The diagnostics backlog — silent inertness becomes `Invalid_argument`

Five items, all of the same shape: something an application can write that today does nothing and says nothing. Each is a typo with no feedback, and each gets more expensive to add once more containers read parent-held attrs (Tasks 6, 7 and 8 all add one).

**Files:**
- Modify: `vtree/attr.mli`, `vtree/kind.ml`, `vtree/kind.mli`, `vtree/node.ml`, `vtree/node.mli`, `vtree/defaults.ml`, `src/patcher.ml`, `src/widgets/w_stack.ml`, `src/widgets/w_entry.ml`, `src/live_tree.ml`, `test/test_widgets.ml`, `test/live/live_containers.ml`, `test/live/live_controls.ml`
- Create: nothing

**The five:**

1. **`Attr.grid_cell` and `Attr.page_title` outside their container are silently inert.** A `Node.grid_cell` on a box child, a `Node.page_title` on a button in a header bar — nothing reads them, nothing complains.
2. **`Node.stack ~visible_child` naming a page that never exists is silently inert forever.** Right for a page that arrives on a later frame, wrong for a typo, and indistinguishable today.
3. **`min > max` content bounds on `Node.scrolled_window`** are not rejected. GTK calls it a programming error and has no runtime check of its own.
4. **`Kind.entry_props` has no `max_length`.** Absent from spec §7's signature too, so never-scoped rather than dropped — but `GtkEntry:max-length` is the usual companion to a controlled `text`, and stavekeeper's `dialog.ml` fields would use it.
5. **The same-frame stack name *swap* raises the wrong error.** Two stacks exchanging names in one frame gives `two Node.stacks are named "b" in one tree`, because `note_interest`'s rename arm does `Hashtbl.remove old; register new` per child left to right and the second stack still holds the new name.

**Interfaces:**
- Produces:
  ```ocaml
  (* Node *)
  val entry : ... -> ?max_length:int -> ... -> unit -> t   (* -1 = unlimited, GTK's own *)
  ```
- Changed: nothing's type. Four behaviours become loud.

**Ruling on (1): a container-placement attr is rejected by the *parent*, at the point the parent reads its children.** Not by `Attr_apply` (which sees a child without knowing its parent), and not by the constructor (which cannot know either). `Patcher`'s list and single child helpers already prefix the child's node path onto container rejections; add one check there, driven by a small table:

```ocaml
(* Which parent-held attrs each container reads off its children. A child carrying one the
   container does not read is a typo -- [Attr.grid_cell] on a box child, [Attr.page_title]
   on a notebook page (it is [Attr.tab_label] there) -- and there is no other diagnostic
   for it: nothing applies these to the child, so a wrong one is simply never read.

   The empty list is the common case and is deliberate: a container that reads none of
   them rejects all of them. *)
let placement_attrs_read_by : Kind.t -> Attr.Name.t list = function
  | Grid _ -> [ Grid_cell ]
  | Stack _ -> [ Page_title ]
  | Overlay _ -> [ Measure_overlay ]
  | _ -> []
;;
```
and the check runs per child at mount and at patch: if the child carries a placement name not in the parent's list, `Invalid_argument` naming the child's path, the attr, and the parent's impl name. `Measure_overlay` joins the table because it is the same family; the M1 backlog only named two.

Tasks 6–8 extend this table (`List_box -> [Row_selectable; Row_activatable]`, `Notebook -> [Tab_label]`), which is why it lands now with a comment saying so.

**Ruling on (2): a `~visible_child` that names no page is `Invalid_argument` from the fixup pass, not from `w_stack.select`.** `select` is called per frame and correctly leaves an absent name alone — the frame that adds the page runs it again. What is missing is a way to tell "not yet" from "never". The fixup already runs after the whole tree exists, so at that point *every* page this frame renders is present: a name absent then is absent in the rendered tree, which is a typo, not a race. Change `select` to raise when the name is absent, and confirm against `live_containers.ml`'s add-and-select-in-one-pass case that the fixup ordering really does make that true. **If it does not** — if there is any legitimate frame where a stack's chosen page is not yet added — stop and report: the item is then not a diagnostic but a design question, and the fallback is to leave it inert and move it to the M2 backlog with the counter-example written down.

- [ ] **Step 1: Write the failing tests**

`test/test_widgets.ml` — the constructor-level ones:

```ocaml
let%expect_test "a scrolled window with min above max is rejected at the constructor" =
  Expect_test_helpers_core.require_does_raise (fun () ->
    Node.scrolled_window ~min_content_width:400 ~max_content_width:200 (Node.label "x"));
  [%expect {| |}];
  (* -1 is "no bound" on either side and never conflicts. *)
  print_s
    [%sexp
      (Node.scrolled_window ~min_content_width:400 (Node.label "x") : Node.t)];
  [%expect {| |}]
;;

let%expect_test "entry max_length reaches the kind and defaults away" =
  print_s [%sexp (Node.entry ~text:"a" () : Node.t)];
  [%expect {| |}];
  print_s [%sexp (Node.entry ~text:"a" ~max_length:8 () : Node.t)];
  [%expect {| |}]
;;
```

`test/live/live_containers.ml` — the three runtime ones, each as a `require_raises`-style print (these are plain executables, so catch and print rather than using expect helpers):

```ocaml
let raises name f =
  match f () with
  | () -> printf "%s: NO RAISE\n" name
  | exception Invalid_argument m -> printf "%s: %s\n" name m
;;

raises "grid_cell on a box child" (fun () ->
  ignore
    (P.mount ctx ~path:"root" ~is_root:true
       (Node.window ~title:"w"
          (Node.box ~orientation:Vertical
             [ Node.label ~attrs:[ Attr.grid_cell ~column:0 ~row:0 () ] "misplaced" ]))
     : P.live));
raises "page_title outside a stack" (fun () -> ...);
raises "visible_child names no page" (fun () ->
  let live = P.mount ctx ~path:"root" ~is_root:true
    (Node.window ~title:"w"
       (Node.stack ~name:"nav" ~visible_child:"typo"
          [ Node.label ~key:"home" "home" ]))
  in
  P.run_fixups ctx;
  P.destroy ctx live);
```

Note the third one's shape: the raise comes from `run_fixups`, not from `mount`, and the test has to call it — which is exactly what `patcher.mli` already tells a hand-driven test to do.

- [ ] **Step 2: Run to verify failure** — `dune build @test/runtest` → unknown labelled argument `~max_length`; and the live test prints three `NO RAISE` lines.

- [ ] **Step 3: `Node.scrolled_window`'s bounds check**

In `vtree/node.ml`, before `make`:

```ocaml
  (* GTK calls a min above a max a programming error and checks nothing at runtime: the
     scrolled window silently sizes itself to whichever the layout reaches first, which
     looks like a layout bug a long way from its cause. [-1] is "no bound" on either side
     and never conflicts with anything. *)
  let check_bounds what ~min ~max =
    if min <> -1 && max <> -1 && min > max
    then
      invalid_argf
        "Node.scrolled_window: min_content_%s (%d) is above max_content_%s (%d)"
        what min what max ()
  in
  check_bounds "width" ~min:min_content_width ~max:max_content_width;
  check_bounds "height" ~min:min_content_height ~max:max_content_height;
```

This is the first constructor in `Node` that raises. Say so in `node.mli`'s doc for `scrolled_window` and in a note at the top of the file: constructors are otherwise total, and this one is the exception because the mistake is unrecoverable later.

- [ ] **Step 4: `entry_props.max_length`**

`vtree/defaults.ml`: `module Entry = struct … let max_length = 0 end`. **GTK's own default is `0`, meaning unlimited** — not `-1`. Check `.ocgtk-src/…/entry.mli` for `set_max_length`/`get_max_length` and confirm before writing the default; the plan asserts `0` from GTK's documented `GtkEntry:max-length`, and the defaults file's whole purpose is that this number is written once.

`Kind.entry_props` gains `max_length : int [@sexp_drop_if Int.equal Defaults.Entry.max_length]`; `Node.entry` gains `?max_length`; `w_entry.ml`'s `create` writes it when it differs from the default and `update` when it differs from `old`. It is **not** controlled: it is a constraint on the widget, not a value the user changes. `Live_tree.dump`'s `GtkEntry` arm gains `int_prop "max-length" … ~default:0`.

`Node.password_entry` and `Node.search_entry` do **not** get it: `GtkPasswordEntry` and `GtkSearchEntry` have no `max-length` property of their own (they are not `GtkEntry` subclasses in GTK4), and `GtkEditable` has no `set_max_length`. Verify in the checkout; if `Editable` does have it, add it to all three and say so in the report.

- [ ] **Step 5: The placement-attr table, in `src/patcher.ml`**

Add `placement_attrs_read_by` as above, and call the check from wherever the patcher already validates a child against its parent (the same helper that raises for a grid child with no `Attr.grid_cell`). Message shape, matching the existing ones:

```
root/0/1: Attr.grid_cell is not read by Box (a placement attribute is read by the
container, and this one holds children for Grid)
```

The parenthetical naming *which* container does read it is the useful half — a misplaced `grid_cell` is nearly always a child that ended up in the wrong parent.

- [ ] **Step 6: `w_stack.select` raises on an absent name**

```ocaml
let select (w : Widget.t) ~visible_child =
  let s : W.Stack.t = cast w in
  match W.Stack.get_child_by_name s visible_child with
  | None ->
    (* Not a race. This runs from the fixup pass, after the whole tree is built, so every
       page this frame renders is already added; a name absent here is absent from the
       rendered tree. The patcher prefixes the stack's node path. *)
    invalid_argf
      "Node.stack ~visible_child:%S names no page (pages are keyed by ~key; this stack \
       has %s)"
      visible_child
      (String.concat ~sep:", " (page_names s))
      ()
  | Some _ ->
    if not (Option.equal String.equal (W.Stack.get_visible_child_name s) (Some visible_child))
    then W.Stack.set_visible_child_name s visible_child
;;
```

`page_names` enumerates the stack's children via `Widget.get_first_child`/`get_next_sibling` and `W.Stack.get_page` → `Stack_page.get_name`. Listing them is what turns the message from an accusation into a fix.

**Before writing this, run the existing `live_containers.ml` add-and-select-in-one-pass case with the raise in place.** If it raises, the premise is wrong; stop and report per the ruling above.

- [ ] **Step 7: The same-frame name swap**

`note_interest`'s rename arm processes children left to right, so a swap hits `register_stack "b"` while the other stack still holds `"b"`. Fix by splitting the pass: first remove every registration this frame's stack nodes are giving up, then add every one they are taking. Two loops over the same child list rather than one:

```ocaml
(* Two passes, because a *swap* is legal and a one-pass walk cannot see it: renaming
   [a -> b] while [b -> a] renames in the same frame hits [register "b"] while the other
   stack still holds it. Removals first, additions second; a genuine collision then still
   raises on the addition, from the second pass, with the same message. *)
```

Add the test to `live_containers.ml` beside the existing rename cases: two keyed stacks whose `~name`s trade, asserting no raise and that a switcher naming each still resolves to the right one after `run_fixups`.

- [ ] **Step 8: Run, read, promote, gate**

```
dune build @test/runtest && dune promote
BONSAI_GTK_LIVE_TESTS=1 xvfb-run -a dune build @test/live/runtest && dune promote
./scripts/ci.sh
```

`expected_controls.txt` will diff by one line (the entry's `max-length`) only if a test sets it; if it diffs otherwise, the default is wrong.

- [ ] **Step 9: Commit**

```bash
dune fmt 2>/dev/null; git add vtree src test
GIT_EDITOR=true git commit -F - <<'MSG'
Four silently-inert mistakes become Invalid_argument, and Entry gets max_length

A placement attribute on a child whose container does not read it
(Attr.grid_cell on a box child, Attr.page_title outside a stack) is now
rejected by the container at mount and at patch, naming the container that
*does* read it. A Node.stack ~visible_child naming no page raises from the
fixup pass, which runs after the whole tree exists -- so "not yet" and "never"
are distinguishable there and nowhere earlier. Node.scrolled_window rejects a
min content bound above its max, which GTK calls a programming error and does
not check.

Two stacks swapping names in one frame no longer collide: the rename pass drops
every registration before it takes any.

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01Sg3Ci8U8kUKR8C3PL1pNSs
MSG
```

**Review focus:** that the `visible_child` raise really cannot fire on a legitimate frame — the add-and-select case is the proof and it must be in the suite, not just run once; that the placement table's `_ -> []` arm is a wildcard on purpose (it is: every container that reads none rejects all) and is commented as such; that `max_length`'s default matches GTK's, read from the binding rather than from this plan; that the two-pass rename still raises on a real collision.

---

