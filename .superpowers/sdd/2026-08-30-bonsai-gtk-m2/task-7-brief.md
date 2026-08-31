### Task 7: FlowBox — the same machinery, a grid of cards

Deliberately the task after ListBox and deliberately smaller: it reuses `Child_keys`, the auto-wrapping, the keyed-children rule and the selection fixup wholesale. What is new is the geometry props and the fact that stavekeeper reconfigures them at runtime (`library_window.ml:226-239` switches one FlowBox between a grid and a list view), which is exactly what a declarative prop diff is for.

**Files:**
- Modify: `vtree/attr.ml(i)`, `vtree/kind.ml(i)`, `vtree/node.ml(i)`, `vtree/defaults.ml`, `vtree/events.ml`, `src/patcher.ml`, `src/widgets/registry.ml`, `src/live_tree.ml`, `test_lib/bonsai_gtk_test.ml(i)`, `test/test_widgets.ml`, `test/handle/test_handle.ml`, `test/live/live_lists.ml`
- Create: `src/widgets/w_flow_box.ml`

**Interfaces:**
- Produces:
  ```ocaml
  val flow_box
    :  ?key:Key.t -> ?attrs:Attr.t list
    -> ?selection_mode:Selection_mode.t
    -> ?activate_on_single_click:bool
    -> ?min_children_per_line:int
    -> ?max_children_per_line:int
    -> ?row_spacing:int
    -> ?column_spacing:int
    -> ?homogeneous:bool
    -> selected:Key.t list
    -> t list
    -> t

  val on_child_activated : Key.t Handler.t -> Attr.t
  val on_selected_children_changed : Key.t list Handler.t -> Attr.t
  ```
- Consumes: `W.Flow_box.{new_,insert,remove,select_child,unselect_all,get_selected_children,get_child_at_index,set_selection_mode,set_activate_on_single_click,set_min_children_per_line,set_max_children_per_line,set_row_spacing,set_column_spacing,set_homogeneous,on_child_activated,on_selected_children_changed}`, `W.Flow_box_child.{new_,set_child,get_index}`.

**Defaults** (`vtree/defaults.ml`, read from the GTK docs and confirmed against a live widget in Step 5, not from this table alone):

```ocaml
module Flow_box = struct
  let selection_mode = Selection_mode.Single
  let activate_on_single_click = true
  let min_children_per_line = 0
  let max_children_per_line = 7
  let row_spacing = 0
  let column_spacing = 0
  let homogeneous = false
end
```

`max_children_per_line`'s GTK default of 7 is the one worth checking: it is a real value, not "unlimited", and an application that never sets it gets seven per line whatever its width. Confirm by dumping a fresh `GtkFlowBox` in the live test and printing `get_max_children_per_line` before promoting.

**One deliberate difference from ListBox:** `activate_on_single_click` is defaulted to GTK's `true`, and `Node.flow_box`'s doc calls out that stavekeeper sets it to `false` on purpose (`library_window.ml:216`) so that a single click selects and a double click opens. That is the interaction a grid of cards wants and it is not the default.

- [ ] **Step 1: Write the failing tests**

`test/test_widgets.ml` — constructor and defaults, plus the unkeyed-child rejection (same rule as ListBox).

`test/handle/test_handle.ml` — the library grid in miniature: a flow box of keyed cards, `on_child_activated` opening one and `on_selected_children_changed` driving a "1 selected" label and a button's `sensitive` attr. That last part is the thing stavekeeper does with mutation (`library_window.ml:272-273,612-615`) and is worth showing declaratively in a test, because it is the argument for the port.

`test/live/live_lists.ml` — append. The claims:

```ocaml
  (* 1. Geometry, and the runtime reconfiguration stavekeeper does by hand: the same flow
        box rendered as a grid and then as a list. Every one of the five props changes in
        one patch, which is what [Widget_impl.batch] is for. *)
  (* 2. Keyed reorder preserves GObjects, as for the list box. *)
  (* 3. The declined selection, and add-and-select in one frame. *)
  (* 4. Removing the selected child. GTK's [remove] does *not* emit
        [selected-children-changed] -- a documented quirk that cost stavekeeper a real
        dangling-widget crash (library_window.ml:76-97) -- so the model's selection and the
        widget's can silently diverge. Assert what this library does: the next frame's
        selection fixup compares against the widget and puts the model's answer back, so
        the divergence lasts less than a frame and nothing reads it in between. *)
```

Case 4 is the one to write first and the one to describe in the impl's comments: it is a real GTK sharp edge, the reason the imperative app has a crash comment, and the strongest single argument for the declarative version.

- [ ] **Step 2–5: implement** — `w_flow_box.ml` is `w_list_box.ml` with a different set of props and `Flow_box_child` for `List_box_row`. Its own `Child_keys.create ()` table (one per module, per `Child_keys`'s doc). `insert` uses `W.Flow_box.insert` with an index derived from `after` the same way, with the same caveat about which widget the patcher tracks — resolved in Task 6, so quote the answer rather than re-deriving it. `move` is `Some` (remove-and-reinsert, as for the list box). `apply_selection` is the same function with `select_child`/`unselect_all`/`get_selected_children`.

**Do not** factor `w_list_box.ml` and `w_flow_box.ml` into a shared functor. They differ in five prop names, two class names and three method names, and the shared part is thirty lines that read better twice than once behind an abstraction that would have to be parameterised on the wrapper type. Say this in a comment at the top of `w_flow_box.ml` so a reviewer does not file it as duplication — and if the reviewer disagrees, that is a legitimate argument and the third container (Task 8) is the point at which to have it.

- [ ] **Step 6: `Events`, `Registry`, `Live_tree`, the placement table** — `Flow_box` reads no placement attrs, so its arm in `placement_attrs_read_by` is `[]` (i.e. it falls into the wildcard, and that is correct: a `row_selectable` on a flow box child is a mistake). `Live_tree`'s `"GtkFlowBox"` arm prints the five geometry props against their defaults and the selection count.

- [ ] **Step 7: `test_lib`** — reuse `Activate_row` and `Set_selection`? **No.** Add `Activate_child of string * Key.t`, because the action names a *kind* of node and a test reading `Activate_row ("grid", …)` against a flow box is confusing; and because the handle looks the node up by `test_id` and can therefore check the kind and fail loudly on a mismatch, which it should. `Set_selection` *is* shared — it is the same question for both kinds — and its doc says which kinds it accepts.

- [ ] **Step 8: Run, read, promote, gate, commit**

```bash
./scripts/ci.sh
dune fmt 2>/dev/null; git add vtree src test test_lib
GIT_EDITOR=true git commit -F - <<'MSG'
FlowBox: keyed children, controlled selection, geometry as a prop diff

The same auto-wrapping, keyed-children and selection-fixup machinery ListBox
uses, over GtkFlowBoxChild. The geometry props (min/max per line, spacings,
homogeneous) are ordinary props, which is what makes switching one flow box
between a grid view and a list view a diff rather than five setters and a
css-class toggle.

GtkFlowBox.remove does not emit selected-children-changed, so a removed
selected child silently diverges the widget from the model; the selection fixup
runs on the next frame and puts the model's answer back, which is asserted
rather than assumed.

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01Sg3Ci8U8kUKR8C3PL1pNSs
MSG
```

**Review focus:** that `max_children_per_line`'s default was read off a live widget, not copied from this plan; that the remove-a-selected-child case asserts the recovery rather than the divergence; that the no-functor decision is argued in a comment and that the reviewer either agrees or says so now rather than at the final review.

---

