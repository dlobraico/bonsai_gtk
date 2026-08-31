### Task 10: DropDown and LevelBar — a rebuilt model, and a trivial one

Paired deliberately: `GtkDropDown` is the most awkward widget in M2 (its model is a separate GObject that has to be rebuilt, and its only selection signal is a `notify::`), and `GtkLevelBar` is four properties and no signals.

**Files:**
- Modify: `vtree/attr.ml(i)`, `vtree/kind.ml(i)`, `vtree/node.ml(i)`, `vtree/defaults.ml`, `vtree/events.ml`, `vtree/bonsai_gtk_vtree.ml`, `src/widgets/registry.ml`, `src/live_tree.ml`, `src/bonsai_gtk.ml(i)`, `test_lib/bonsai_gtk_test.ml(i)`, `test/test_widgets.ml`, `test/handle/test_handle.ml`, `test/live/live_text.ml`
- Create: `vtree/level_bar_mode.ml`, `src/widgets/w_drop_down.ml`, `src/widgets/w_level_bar.ml`

**Interfaces:**
- Produces:
  ```ocaml
  val drop_down
    :  ?key:Key.t -> ?attrs:Attr.t list
    -> ?enable_search:bool
    -> ?show_arrow:bool
    -> items:string list
    -> selected:int          (** [-1] for none *)
    -> unit
    -> t

  val level_bar
    :  ?key:Key.t -> ?attrs:Attr.t list
    -> ?min:float -> ?max:float
    -> ?mode:Level_bar_mode.t
    -> ?inverted:bool
    -> value:float
    -> unit
    -> t

  val on_selected_changed : int Handler.t -> Attr.t

  (* Bonsai_gtk_test.Action *)
  | Set_selected of string * int
  ```
- Consumes: `W.Drop_down.{new_from_strings,set_model,get_model,set_selected,get_selected,set_enable_search,set_show_arrow}`, `W.String_list.{new_,get_n_items,get_string}`, `Ocgtk_gio.Gio.Wrappers.List_model.from_gobject`, `Ocgtk_gtk.Gtk_constants.invalid_list_position`, `W.Level_bar.{new_,set_value,get_value,set_min_value,set_max_value,set_mode,set_inverted}`.

**Four rulings for DropDown:**

1. **`-1` is "nothing selected" in the vtree; `invalid_list_position` is at the boundary.** GTK's sentinel is `G_MAXUINT`, which OCaml sees as `4294967295` — not `-1`, and a number no application would write on purpose. `Node.drop_down ~selected:(-1)` translates to it on the way in and back from it on the way out, in `w_drop_down.ml` and nowhere else. Say so on the constructor: `-1` is the value, and any other out-of-range index is `Invalid_argument` at the constructor (it is checkable there — `items` is in hand).

2. **The model is rebuilt only when the items differ, and the identity short-circuit is on the *list*, not on the widget.** Rebuilding a `GtkStringList` resets the selection, closes an open popup and re-lays-out the button, so doing it on every frame would make the widget unusable. `update` compares the new `items` against the old node's — an ordinary prop comparison, which the patcher has already done via `Kind.equal_props`, so in practice `update` is only reached when *something* differs and the items comparison inside it is what decides whether the expensive half runs:

```ocaml
(* Rebuilt, not mutated: [GtkStringList] has [append]/[remove]/[splice], and computing a
   minimal splice from two string lists is a diff nobody has asked for. A whole-model
   replacement is one call and is correct; what makes it affordable is that it happens
   only when the items actually changed, which for the dropdowns a real app has (a fixed
   list of modes, a list of setlists that changes when the database does) is rare.

   Rebuilding resets [selected] to [invalid_list_position], so the selection is re-applied
   immediately after -- by [reassert], which the patcher runs right after [update] and
   which compares against the widget. Nothing else re-selects, and the ordering is the
   whole reason this is safe. *)
```

3. **`selected` is controlled and lives in `reassert`**, unlike the three containers' selections — because a dropdown's items are *props*, not children, so they exist by the time `reassert` runs. This is the one M2 selection that is not a fixup and the doc says why, in one sentence, so the asymmetry does not read as an oversight.

4. **`on_selected_changed` is a `notify::selected`.** `GtkDropDown`'s only signal is `activate`. Use `Signals.notify ~prop:"selected"` and `get_selected`; report `-1` for `invalid_list_position`. This is the pattern `w_switch.ml` and `w_stack.ml` established and it needs no new machinery — note in the impl that stavekeeper reaches for the identical raw connection today (`setlist_ui.ml:145-152`, with a comment saying ocgtk binds no such signal), and that this is the library's answer to it.

**LevelBar** has no signals and no controlled prop (`value` is set by the program, never by the user — there is no interaction). It is `create` + `update` + `Live_tree` arm + a gallery entry, and it is in this task to keep Task 10 the same size as its neighbours. Its one trap: `set_min_value`/`set_max_value`/`set_value` must be written in an order that never leaves min above max, so write `min` and `max` before `value`, and when both bounds change write whichever moves *outward* first. Bracket in `batch`.

- [ ] **Step 1: Write the failing tests**

`test/test_widgets.ml`:

```ocaml
let%expect_test "drop down rejects an out-of-range selection at the constructor" =
  Expect_test_helpers_core.require_does_raise (fun () ->
    Node.drop_down ~items:[ "a"; "b" ] ~selected:2 ());
  [%expect {| |}];
  (* [-1] is the one out-of-range value that means something. *)
  print_s [%sexp (Node.drop_down ~items:[ "a"; "b" ] ~selected:(-1) () : Node.t)];
  [%expect {| |}]
;;
```

`test/live/live_text.ml` — append:

```ocaml
  (* 1. A dropdown, its items, and which is selected. *)
  (* 2. Changing the *selection* alone must not rebuild the model: take the model's GObject
        before and after and assert [Gobject.same]. Without this, "rebuilt only when the
        items differ" is a comment rather than a claim. *)
  (* 3. Changing the items rebuilds the model *and* re-applies the selection in the same
        frame, so the widget is never left showing [invalid_list_position]. Assert
        [get_selected] after the patch, not just the item list.
  (* 4. The declined selection: the user picks item 2, the model re-renders 0. *)
  (* 5. The reentrancy case: [set_selected] emits [notify::selected] synchronously inside
        the patch, and a model rebuild emits it too. [scheduled] unchanged across both. *)
  (* 6. A level bar's three-value write leaves min <= max at every intermediate step --
        assert by writing a value/min/max triple that would be invalid in the wrong order
        and checking GTK logged nothing (the dump is the check: a clamped value shows). *)
```

Case 2 is the one that would silently pass with a wrong implementation, so it goes first.

- [ ] **Step 2–5: implement.** The model rebuild:

```ocaml
let set_items (d : W.Drop_down.t) items =
  let sl = W.String_list.new_ (Some (Array.of_list items)) in
  (* [String_list.t]'s row is [`string_list | `object_] and [List_model.t]'s is
     [`list_model], so a [:>] coercion does not typecheck. [from_gobject] is the checked
     interface cast -- the same idiom as [Editable.from_gobject] in w_entry.ml -- and it
     raises [Failure] rather than corrupting anything if handed the wrong type. *)
  W.Drop_down.set_model d (Some (Ocgtk_gio.Gio.Wrappers.List_model.from_gobject sl))
;;
```

and the sentinel translation:

```ocaml
(* GTK's "nothing selected" is G_MAXUINT, which OCaml sees as 4294967295. The vtree says
   [-1], because that is the number an application writes and because a positive sentinel
   larger than any real index would compare wrongly against a bounds check somewhere. The
   translation is here and only here. *)
let to_gtk = function
  | -1 -> Ocgtk_gtk.Gtk_constants.invalid_list_position
  | n -> n
;;

let of_gtk n = if n = Ocgtk_gtk.Gtk_constants.invalid_list_position then -1 else n
```

- [ ] **Step 6: `Live_tree`** — `"GtkDropDown"` printing the item list (read back through `get_model` → `List_model.get_object` → `String_object.get_string`, or through the `GtkStringList` if the cast is cheaper — check which the binding makes easier) and `selected`; `"GtkLevelBar"` printing `value`, `min`/`max` when not `0.`/`1.`, `mode` when `DISCRETE`, `inverted`.

Reading the items back is worth the trouble: without it the golden shows a dropdown button and nothing about what is in it, and case 3 above has nothing to assert against.

- [ ] **Step 7: Run, read, promote, gate, commit**

```bash
./scripts/ci.sh
dune fmt 2>/dev/null; git add vtree src test test_lib
GIT_EDITOR=true git commit -F - <<'MSG'
DropDown over a rebuilt string model, and LevelBar

A GtkDropDown's items live in a separate GObject, so changing them means
replacing the model -- which resets the selection, so the selection is
re-applied by [reassert] on the same frame and the widget is never left showing
nothing. The model is rebuilt only when the items differ, which a live test
asserts by GObject identity rather than by comment.

"Nothing selected" is -1 in the vtree and G_MAXUINT at the boundary, translated
in one place. Selection changes arrive as notify::selected, GtkDropDown having
no signal of its own -- the same raw connection stavekeeper makes by hand today.

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01Sg3Ci8U8kUKR8C3PL1pNSs
MSG
```

**Review focus:** that the model-identity test exists and would fail on an unconditional rebuild; that the selection is re-applied on the same frame as a rebuild, not the next; that `-1`↔`invalid_list_position` appears in exactly two functions; that the level bar's writes cannot transiently invert its bounds.

---

