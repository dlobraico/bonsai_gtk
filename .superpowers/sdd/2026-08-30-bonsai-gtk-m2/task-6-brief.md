### Task 6: ListBox — keyed rows, a key in every handler, and `Child_keys`

The forcing case for everything Tasks 4 and 5 built, and the widget stavekeeper's `sidebar.ml` and `layer_panel.ml` are made of.

**Files:**
- Modify: `vtree/attr.ml(i)`, `vtree/kind.ml(i)`, `vtree/node.ml(i)`, `vtree/defaults.ml`, `vtree/events.ml`, `vtree/selection_mode.ml` (create), `vtree/bonsai_gtk_vtree.ml`, `src/patcher.ml`, `src/widgets/registry.ml`, `src/live_tree.ml`, `src/bonsai_gtk.ml(i)`, `test_lib/bonsai_gtk_test.ml(i)`, `test/test_widgets.ml`, `test/handle/test_handle.ml`, `test/live/dune`
- Create: `vtree/selection_mode.ml`, `src/child_keys.ml`, `src/child_keys.mli`, `src/widgets/w_list_box.ml`, `test/live/live_lists.ml`, `test/live/expected_lists.txt`

**Interfaces:**
- Produces:
  ```ocaml
  (* vtree/selection_mode.ml *)
  type t = None_ | Single | Browse | Multiple [@@deriving sexp_of, equal, compare]

  (* Node *)
  val list_box
    :  ?key:Key.t -> ?attrs:Attr.t list
    -> ?selection_mode:Selection_mode.t
    -> ?activate_on_single_click:bool
    -> ?show_separators:bool
    -> ?placeholder:t
    -> selected:Key.t list
    -> t list
    -> t

  (* Attr — on the list box *)
  val on_row_activated : Key.t Handler.t -> t
  val on_selected_rows_changed : Key.t list Handler.t -> t
  (* Attr — on a child of a list box *)
  val row_selectable : bool -> t
  val row_activatable : bool -> t

  (* Child_keys *)
  type t
  val create : unit -> t
  val set : t -> Widget.t -> Key.t -> unit
  val remove : t -> Widget.t -> unit
  val find : t -> Widget.t -> Key.t option
  val find_exn : t -> Widget.t -> what:string -> Key.t

  (* Bonsai_gtk_test.Action *)
  | Activate_row of string * Key.t
  | Set_selection of string * Key.t list
  ```
- Consumes: `W.List_box.{new_,insert,remove,select_row,unselect_row,unselect_all,get_selected_rows,set_selection_mode,set_activate_on_single_click,set_show_separators,set_placeholder,on_row_activated,on_selected_rows_changed}`, `W.List_box_row.{new_,set_child,set_selectable,set_activatable,get_index}`, `Gtk_enums.selectionmode`.

**Five design rulings, all of which a reviewer should be able to argue with:**

1. **Rows are auto-wrapped, and children require a key.** `Node.list_box` takes ordinary child nodes; the impl creates a `GtkListBoxRow` per child, sets the child into it, and keeps the wrapper. The alternative — a `Node.list_box_row` the application builds — puts a widget in the tree whose only job is to exist, and makes "did you remember to wrap it" a new class of mistake. Per-row settings ride as attrs on the child (`Attr.row_selectable`, `Attr.row_activatable`), read by `list_ops.insert` and `updated`, exactly as `Attr.page_title` and `Attr.grid_cell` already are. And **every child must carry `~key`**, on the same rule and with the same message shape as a stack page: the key is the row's identity, it is what every handler receives, and there is nothing else to hand back. Stavekeeper's header rows get a synthetic key (`"header-instruments"`), which is better than the index they use today.

2. **Handlers receive keys, never rows or indices.** `on_row_activated` is a `Payload` spec: GTK hands the callback a `GtkListBoxRow`, the `connect` closure maps it to a key through `Child_keys`, and `fire` hands the key to the application. This is the *entire* reason `Payload` exists, and it is what deletes the parallel arrays in `sidebar.ml:150,205` and `layer_panel.ml:90`.

3. **Selection is controlled, and applied from the fixup queue.** `~selected:Key.t list` is the model's selection; the widget is written only when it differs from what the widget currently holds. It cannot live in `reassert` for the same reason a stack's visible child cannot: `reassert` runs before the children are patched, so the frame that adds a row and selects it would have nothing to select. `Patcher.enqueue_fixups` (Task 2) gains an arm.

4. **A key in `~selected` that no row carries is ignored, not an error.** Unlike a stack's `~visible_child` (Task 3), a selection is plural and a model that keeps a selected id through a filter change is doing something reasonable — the row comes back when the filter does. Selecting nothing is a legitimate state; selecting a row that is not there is not expressible. So: select the ones present, ignore the rest, and say so in `Node.list_box`'s doc. **This asymmetry with `~visible_child` is deliberate and must be documented on both**, or the next reader will "fix" one of them.

5. **`selection_mode` and `~selected` can disagree, and GTK arbitrates.** Handing three keys to a `Single` list box means GTK keeps the last one selected. Do not pre-clamp in the impl: the model then diverges from the widget on the very next frame's comparison, and the reassert loop writes forever. Write what was asked, read back what GTK kept, compare on the read-back value. Note it on `Node.list_box`.

**`Child_keys`** is one ephemeron table per container module, keyed on the *wrapper* widget:

```ocaml
(** Which node key a container's live wrapper widget came from.

    [GtkListBox], [GtkFlowBox] and [GtkNotebook] all hand a signal callback a {i widget} —
    a row, a child, a page's content — and every one of the questions an application asks
    about it ("which item was activated", "which are selected") is a question about the
    node it came from. The node is gone by then, so the answer is recorded when the
    wrapper is created and looked up when the signal fires.

    Weakly keyed, so a destroyed row takes its entry with it rather than pinning the
    GObject alive. [Gobject.same] is the equality: two OCaml values wrapping one GObject
    are never [==], and using [==] here would silently never find anything. The pattern
    (and the reason) is [src/widgets/w_search_entry.ml]'s [Echo] table.

    One table per container module rather than one per container instance: the keys are
    unique per container but the {i widgets} are unique globally, so a shared table is
    correct and saves a lookup. *)
```

built on `Stdlib.Ephemeron.K1.Make (struct type t = Widget.t let equal = Gobject.same let hash = Stdlib.Hashtbl.hash end)`.

`find_exn ~what` raises `Invalid_argument` naming `what` (`"list box row"`) — reachable only if a container hands back a widget it never registered, which is a library bug, and a silent `None` there would show up as a handler that mysteriously never fires.

- [ ] **Step 1: Write the failing tests**

`test/test_widgets.ml`:

```ocaml
let%expect_test "list box constructors and defaults" =
  print_s
    [%sexp
      (Node.list_box
         ~selected:[]
         [ Node.label ~key:"a" "Alpha"; Node.label ~key:"b" "Beta" ]
       : Node.t)];
  [%expect {| |}];
  print_s
    [%sexp
      (Node.list_box
         ~selection_mode:Browse
         ~activate_on_single_click:true
         ~show_separators:true
         ~placeholder:(Node.label "nothing here")
         ~selected:[ "b" ]
         [ Node.label ~key:"a" ~attrs:[ Attr.row_selectable false ] "Header"
         ; Node.label ~key:"b" "Beta"
         ]
       : Node.t)];
  [%expect {| |}]
;;

let%expect_test "a list box child without a key is rejected at the constructor" =
  Expect_test_helpers_core.require_does_raise (fun () ->
    Node.list_box ~selected:[] [ Node.label "unkeyed" ]);
  [%expect {| |}]
;;
```

Note this last one: unlike a stack page (whose missing key is caught by the impl at mount, because M1 put the check there), a list box's key requirement is checkable in the constructor and should be — the earlier the better, and `Node.list_box` already has the children in hand. **Do the same for `Node.stack` while here**, so the two behave alike; that is a one-line change to `Node.stack` and a message improvement, and it makes `w_stack.page_name`'s raise unreachable-but-kept as a belt-and-braces (say so in its comment).

`test/handle/test_handle.ml` — the sidebar, in miniature:

```ocaml
let filter_list (graph @ local) =
  let chosen, set_chosen = Bonsai.state "all" graph in
  let%arr chosen and set_chosen in
  Node.window ~title:"Sidebar"
    (Node.box ~orientation:Vertical
       [ Node.list_box
           ~attrs:[ Attr.test_id "rail"; Attr.on_row_activated set_chosen ]
           ~selection_mode:Single
           ~selected:[ chosen ]
           [ Node.label ~key:"hdr" ~attrs:[ Attr.row_selectable false; Attr.row_activatable false ] "FILTERS"
           ; Node.label ~key:"all" "All pieces"
           ; Node.label ~key:"recent" "Recent"
           ]
       ; Node.label ~attrs:[ Attr.test_id "chosen" ] chosen
       ])
;;

let%expect_test "activating a row hands the model the row's key" =
  let handle = Bonsai_gtk_test.create filter_list in
  Bonsai_gtk_test.Handle.show handle;
  [%expect {| |}];
  Bonsai_gtk_test.Handle.do_actions handle [ Activate_row ("rail", "recent") ];
  Bonsai_gtk_test.Handle.show_diff handle;
  [%expect {| |}]
;;
```

`test/live/live_lists.ml` — the GTK half. This file grows through Tasks 6–8. The claims it must pin for the list box:

```ocaml
  (* 1. The rows GTK holds, in order, with the wrapper's own props. *)
  let live = P.mount ctx ~path:"root" ~is_root:true (view ~selected:[ "b" ] ~rows:[ "a"; "b"; "c" ]) in
  P.run_fixups ctx;
  print_s (Live_tree.dump live.widget);

  (* 2. A keyed reorder moves the same GObjects. Take handles first, patch, compare with
        [Gobject.same] -- the dump alone cannot say this, because two rows holding the same
        label print identically. *)
  let rows_before = row_widgets live in
  let live = patch (view ~selected:[ "b" ] ~rows:[ "c"; "a"; "b" ]) in
  printf "same GObjects after reorder: %b\n" (rows_match rows_before (row_widgets live));
  print_s (Live_tree.dump live.widget);

  (* 3. The declined selection. The user clicks row "c"; the model keeps "b"; the frame
        that renders the *same* selection must put the widget back. This is spec §6.5 for
        a container, and the reason selection is a fixup rather than an [update]. *)
  select_row_by_hand live "c";
  printf "after the user clicked: %s\n" (selected_keys live);
  let live = patch (view ~selected:[ "b" ] ~rows:[ "c"; "a"; "b" ]) in
  printf "after the declining frame: %s\n" (selected_keys live);

  (* 4. Add a row and select it in one frame. The row does not exist when [reassert] would
        have run, which is why this is a fixup; without the fixup this prints nothing
        selected. *)
  let live = patch (view ~selected:[ "d" ] ~rows:[ "c"; "a"; "b"; "d" ]) in
  printf "add-and-select: %s\n" (selected_keys live);

  (* 5. Removing the selected row. GTK drops the selection; the model still says "d", and
        the next frame must not resurrect a row that is gone. Nothing selected, no raise. *)
  let live = patch (view ~selected:[ "d" ] ~rows:[ "c"; "a"; "b" ]) in
  printf "selected row removed: %s\n" (selected_keys live);

  (* 6. A key in ~selected that no row carries is ignored (ruling 4), not an error. *)
  let live = patch (view ~selected:[ "a"; "ghost" ] ~rows:[ "c"; "a"; "b" ]) in
  printf "selection with a ghost key: %s\n" (selected_keys live);

  (* 7. Teardown does not fire a handler. GTK emits [selected-rows-changed] as rows go
        away; [scheduled] must not move across the destroy. *)
  let before = !scheduled in
  P.destroy ctx live;
  printf "handlers fired during teardown: %d\n" (!scheduled - before);
```

Cases 3, 4, 5 and 7 are the ones that would pass with a wrong implementation if they were left out. Write them first.

- [ ] **Step 2: Run to verify failure.**

- [ ] **Step 3: `vtree/selection_mode.ml`**

```ocaml
(** How many rows or children may be selected at once.

    [None_] rather than [None]: a constructor called [None] would shadow [Option.None] in
    every match in the file that handles it, which is the same reason
    {!Bonsai_gtk_vtree.Reveal_transition} and {!Stack_transition} spell theirs [None_].

    [Browse] is [Single] with "exactly one" instead of "at most one": GTK keeps a row
    selected at all times and will not let the user deselect. A model that renders
    [~selected:[]] to a [Browse] list box is asking for something GTK does not do; see
    {!Bonsai_gtk_vtree.Node.list_box}. *)
type t = None_ | Single | Browse | Multiple [@@deriving sexp_of, equal, compare]
```

- [ ] **Step 4: `vtree/attr.ml(i)` and the placement table**

Four names, adjacent: `On_row_activated`, `On_selected_rows_changed`, `Row_selectable`, `Row_activatable`. The last two are placement attrs, so `Attr_apply.set`/`unset` get inert arms (with the comment the existing placement attrs have), `Events.for_kind` never mentions them (they are not events), and **`Patcher.placement_attrs_read_by` (Task 3) gains `| List_box _ -> [ Row_selectable; Row_activatable ]`** — which is what makes `Attr.row_selectable` on a box child an error rather than a mystery.

- [ ] **Step 5: `src/child_keys.ml(i)`** — as specified above. Forty lines, half of them the doc comment.

- [ ] **Step 6: `src/widgets/w_list_box.ml`**

The three parts worth writing out here, because each has a trap:

```ocaml
(* One table for every list box in the process. Keyed on the [GtkListBoxRow] wrapper this
   impl creates, never on the application's child widget: two list boxes may render the
   same child node, and the wrapper is what GTK hands back. *)
let row_keys = Child_keys.create ()

let row_key (node : Node.t) =
  match node.key with
  | Some key -> key
  | None ->
    (* Unreachable: [Node.list_box] rejects an unkeyed child. Kept because the patcher can
       reach [insert] from a path the constructor did not build (a [Node.native] payload
       assembling children, a future constructor), and a silent [""] key would make every
       row answer to the same name. *)
    invalid_arg "list box child has no ~key (a row's key is the identity handlers receive)"
;;

let wrap ~(node : Node.t) (child : Widget.t) =
  let row = W.List_box_row.new_ () in
  W.List_box_row.set_child row (Some child);
  (* Per-row settings are the *parent's*, read off the child node's attrs. A header row is
     [~attrs:[ Attr.row_selectable false; Attr.row_activatable false ]] -- which is exactly
     what stavekeeper's sidebar.ml:21-22 does by hand. *)
  Option.iter (row_flag node Row_selectable) ~f:(W.List_box_row.set_selectable row);
  Option.iter (row_flag node Row_activatable) ~f:(W.List_box_row.set_activatable row);
  Child_keys.set row_keys (row :> Widget.t) (row_key node);
  row
;;
```

`list_ops`:

```ocaml
  ; children =
      Widget_impl.List
        { insert =
            (fun parent ~after ~node child ->
              let row = wrap ~node child in
              (* [GtkListBox] has no insert-after; it has insert-at-index. The patcher's
                 [after] is a *widget*, so turn it back into an index with the wrapper's
                 own [get_index] -- which is GTK's answer, not the patcher's, and is
                 correct here precisely because the list box interposes nothing else: its
                 children are exactly the wrappers this impl made. [None] is index 0. *)
              let index =
                match after with
                | None -> 0
                | Some w -> W.List_box_row.get_index (cast w) + 1
              in
              W.List_box.insert (cast parent) (row :> Widget.t) index)
        ; move =
            Some
              (fun parent ~child ~after ->
                (* No [reorder_child_after]: remove and re-insert. The row survives (this
                   holds a reference through [child]), so keyed identity is preserved --
                   which is the whole claim, and [live_lists.ml] case 2 is what checks it.
                   [remove] can drop the selection; the selection fixup runs after every
                   pass and puts it back. *)
                ...)
        ; remove =
            (fun parent child ->
              Child_keys.remove row_keys child;
              W.List_box.remove (cast parent) child)
        ; updated =
            (fun _parent ~old ~node row ->
              (* The key cannot change -- a changed key is a different child to the
                 reconciler -- so only the two row flags are re-read. *)
              ...)
        }
```

**Careful:** the patcher's `remove`/`move` are handed the widget *it* recorded as the child, which for this container is the wrapper, not the application's child widget. Confirm that `list_ops.insert` returning nothing means the patcher keeps `l.widget` (the child's own widget) in `cur`, not the wrapper — if so, `after`, `move` and `remove` will all be handed the *inner* widget and every line above is wrong. **This is the single most likely way this task goes sideways.** Read `Patcher.patch_children`'s `List` arm before writing a line of `w_list_box.ml`, and if the patcher tracks inner widgets, the fix is to map inner → wrapper through a second `Child_keys`-shaped table (or through `Widget.get_parent`, which for a wrapped child *is* the row). Prefer `get_parent`: it is one call, it cannot go stale, and it is exactly what GTK guarantees. Write down which it turned out to be.

The two specs:

```ocaml
let row_activated : Signals.spec =
  Payload
    { attr = Attr.Name.On_row_activated
    ; connect =
        (fun w ~callback ->
          Signals.connected
            w
            (W.List_box.on_row_activated (cast w) ~callback:(fun ~row ->
               callback (Child_keys.find_exn row_keys (row :> Widget.t) ~what:"list box row"))))
    ; fire =
        (fun _w attr key ->
          match (attr : Attr.Private.t) with
          | On_row_activated handler -> (), Some (handler key)
          | _ -> (), None)
    ; declined = ()
    }
;;

(* [selected-rows-changed] carries nothing, so this one is a [Read_back] -- the selection
   *is* readable off the widget. It still goes through [Child_keys], to answer in the
   application's terms rather than GTK's. *)
let selected_rows_changed : Signals.spec =
  Read_back
    { attr = Attr.Name.On_selected_rows_changed
    ; connect = (fun w ~callback -> Signals.connected w (W.List_box.on_selected_rows_changed (cast w) ~callback))
    ; fire =
        (fun w attr ->
          match (attr : Attr.Private.t) with
          | On_selected_rows_changed handler -> Some (handler (selected_keys w))
          | _ -> None)
    }
;;
```

`selected_keys` maps `get_selected_rows` through `Child_keys.find` and drops the `None`s — a row GTK reports that this impl did not register cannot happen, but dropping is the right response if it ever does, because raising from inside a signal is worse than under-reporting.

The selection application, called from the fixup:

```ocaml
(* Controlled, on spec §6.5's rule and compared against the widget rather than the
   previous node -- so the frame on which the model *declines* a click puts the selection
   back. From the fixup pass rather than [reassert] because the rows do not exist when
   [reassert] runs; see [Widget_impl.reassert]'s own note about [Stack].

   Keys naming no row are ignored rather than rejected: a model that holds a selected id
   across a filter change is doing something reasonable, and the row comes back when the
   filter does. This is deliberately *unlike* [Node.stack ~visible_child], which raises --
   a stack shows exactly one page and a name that never resolves is a typo with no other
   symptom. Both are documented on their constructors. *)
let apply_selection (w : Widget.t) ~selected =
  let current = selected_keys w in
  if not (List.equal String.equal (List.sort ~compare:String.compare current)
            (List.sort ~compare:String.compare selected))
  then (
    let lb : W.List_box.t = cast w in
    W.List_box.unselect_all lb;
    List.iter selected ~f:(fun key ->
      Option.iter (row_by_key w key) ~f:(fun row -> W.List_box.select_row lb (Some row))))
;;
```

Sorting both sides before comparing is deliberate: GTK reports selected rows in *widget* order and the model lists them in whatever order it built. Two orderings of one selection must not look like a change, or the fixup writes every frame and the user can never keep a multi-selection.

- [ ] **Step 7: `src/patcher.ml`** — `enqueue_fixups` gains `| List_box p -> Queue.enqueue ctx.fixups (fun () -> W_list_box.apply_selection widget ~selected:p.selected)`.

- [ ] **Step 8: `src/live_tree.ml`** — a `"GtkListBox"` arm printing `selection-mode` (when not `NONE`), `activate-on-single-click` (when true — GTK's own default is true, so print it when *false*; check), `show-separators`, and the count of selected rows; and a `"GtkListBoxRow"` arm printing `selected`, and `selectable`/`activatable` when false. **Do not print the row's key**: `Live_tree` dumps GTK, and the key is the vtree's. A golden that showed keys would go green on an implementation that put them in the wrong rows.

Instead, `live_lists.ml` prints `selected_keys` itself, which is a read through `Child_keys` and therefore does exercise the mapping.

- [ ] **Step 9: `test_lib`** — `Activate_row of string * Key.t` and `Set_selection of string * Key.t list`, both firing the named node's handler with exactly the key(s) given; neither consults the node's own `~selected`, for the reason `Set_text` documents.

- [ ] **Step 10: Run, read, promote, gate, commit**

```bash
./scripts/ci.sh
dune fmt 2>/dev/null; git add vtree src test test_lib
GIT_EDITOR=true git commit -F - <<'MSG'
ListBox: rows keyed by the node's key, and every handler speaks in keys

Children are auto-wrapped in GtkListBoxRows the impl owns, and every child must
carry ~key: the key is the row's identity and it is what on_row_activated and
on_selected_rows_changed hand back. Child_keys is the weak map from a live
wrapper to its key that makes that possible; it is what Signals' new Payload
spec exists for, and it is what deletes the parallel row arrays a GTK app needs
because row-activated only offers an index.

Selection is controlled and applied from the fixup pass, so the frame on which
a model declines a click puts the selection back, and a frame that adds a row
can select it. A key naming no row is ignored -- unlike a stack's
~visible_child, which raises; both asymmetries are documented on both
constructors.

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01Sg3Ci8U8kUKR8C3PL1pNSs
MSG
```

**Review focus:** whether the patcher tracks the wrapper or the inner widget, and that whichever it is, `insert`/`move`/`remove`/`updated`/`after` all agree — this is the task's main hazard; that `apply_selection` sorts before comparing; that removing a selected row does not raise and does not resurrect it; that teardown fires no handler (case 7); that `Live_tree` prints no keys; that the ignored-ghost-key asymmetry with `~visible_child` is documented on *both* constructors, not one.

---

