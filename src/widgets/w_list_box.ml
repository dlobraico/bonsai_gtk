open! Core
open Bonsai_gtk_vtree
open Gtk_import

let selection_mode : Selection_mode.t -> Gtk_enums.selectionmode = function
  | None_ -> `NONE
  | Single -> `SINGLE
  | Browse -> `BROWSE
  | Multiple -> `MULTIPLE
;;

(* One table for every list box in the process. Keyed on the [GtkListBoxRow] wrapper this
   impl creates, never on the application's child widget: two list boxes may render the
   same child node, and the wrapper is what GTK hands back. *)
let row_keys = Child_keys.create ()

let row_key (node : Node.t) =
  match node.key with
  | Some key -> key
  | None ->
    (* Unreachable: [Node.list_box] rejects an unkeyed child at the constructor. Kept
       because the patcher can reach [insert] from a path that constructor did not build
       (a [Node.native] payload assembling children, a future constructor), and a silent
       [""] key would make every row answer to the same name. *)
    invalid_arg
      "list box child has no ~key (a row's key is the identity handlers receive)"
;;

(* The two settings the *list box* holds about each row, read off the child node's attrs
   for the reason [Attr.page_title] and [Attr.grid_cell] are (spec §5.3's M1 amendment).
   [true] on both is GTK's own default for a fresh [GtkListBoxRow], and answering with it
   rather than with an option is what makes [updated] correct when the attr goes *away*:
   dropping [Attr.row_selectable false] from a row has to put [true] back, and an
   [Option.iter] over the new node's attrs would write nothing at all. *)
let selectable (node : Node.t) =
  match (Attrs.find node.attrs Row_selectable :> Attr.Private.t option) with
  | Some (Row_selectable b) -> b
  | Some _ | None -> true
;;

let activatable (node : Node.t) =
  match (Attrs.find node.attrs Row_activatable :> Attr.Private.t option) with
  | Some (Row_activatable b) -> b
  | Some _ | None -> true
;;

let wrap ~(node : Node.t) (child : Widget.t) =
  let row = W.List_box_row.new_ () in
  W.List_box_row.set_child row (Some child);
  (* A header row is [~attrs:[ Attr.row_selectable false; Attr.row_activatable false ]] --
     which is what an application written against GTK directly builds by hand, since
     [set_header_func] is not in the binding. *)
  W.List_box_row.set_selectable row (selectable node);
  W.List_box_row.set_activatable row (activatable node);
  Child_keys.set row_keys (row :> Widget.t) (row_key node);
  row
;;

(* The patcher's list ops are handed the *child's own* widget, never the wrapper:
   [Patcher.patch_list] keeps [l.widget] in its bookkeeping and computes [~after] from the
   same list, and a container that interposes children of its own gets no say in that. So
   every op here has to get from the application's child back to the [GtkListBoxRow] this
   impl put around it, and [Widget.get_parent] is that step -- one call, exactly what GTK
   guarantees for a wrapped child, and nothing to keep in step the way a second table
   would be.

   Letting GTK do the unwrapping is not an option: [gtk_list_box_remove] handed an inner
   child logs "Tried to remove non-child" and does nothing, and there is no
   insert-an-inner-child at all.

   The type check rather than a bare [cast]: this is the one assumption the whole file
   rests on, and a wrong downcast is undefined behaviour rather than an exception. *)
let row_of ~what (child : Widget.t) : W.List_box_row.t =
  match Widget.get_parent child with
  | Some parent when String.equal (type_name parent) "GtkListBoxRow" -> cast parent
  | Some parent ->
    invalid_argf
      "list box: %s is parented to a %s rather than to the GtkListBoxRow this impl made"
      what
      (type_name parent)
      ()
  | None -> invalid_argf "list box: %s has no parent" what ()
;;

(* Every selected row, as the keys the nodes carried. Read through [Child_keys], because
   the question an application asks is about its own rows and GTK's answer is a list of
   widgets it has never seen.

   A row GTK reports that this impl did not register cannot happen -- every row in a
   [GtkListBox] this library owns was made by [wrap] -- but dropping one is the right
   response if it ever does: this runs inside a signal emission, and under-reporting a
   selection is better than raising there. *)
let selected_keys (w : Widget.t) =
  W.List_box.get_selected_rows (cast w)
  |> List.filter_map ~f:(fun row -> Child_keys.find row_keys (row :> Widget.t))
;;

let row_by_key (w : Widget.t) key =
  let b : W.List_box.t = cast w in
  let rec go i =
    match W.List_box.get_row_at_index b i with
    | None -> None
    | Some row ->
      if Option.exists (Child_keys.find row_keys (row :> Widget.t)) ~f:(String.equal key)
      then Some row
      else go (i + 1)
  in
  go 0
;;

(* Controlled, on spec §6.5's rule and compared against the widget rather than the
   previous node -- so the frame on which the model *declines* a click puts the selection
   back.

   From the fixup pass rather than [reassert] because the rows do not exist when
   [reassert] runs; see [Widget_impl.reassert]'s own note about [Stack]. The frame that
   both adds a row and selects it is the case: [reassert] runs before the children are
   patched, so there would be nothing to select.

   Keys naming no row are ignored rather than rejected: a model that holds a selected id
   across a filter change is doing something reasonable, and the row comes back when the
   filter does. This is deliberately *unlike* [Node.stack ~visible_child], which raises --
   a stack shows exactly one page and a name that never resolves is a typo with no other
   symptom. Both are documented on their constructors.

   Sorting both sides before comparing is deliberate: GTK reports selected rows
   in *widget* order and the model lists them in whatever order it built. Two orderings of
   one selection must not look like a change, or this would write on every frame and the
   user could never keep a multi-selection. *)
let apply_selection (w : Widget.t) ~selected =
  let sorted = List.sort ~compare:String.compare in
  let current = selected_keys w in
  if not (List.equal String.equal (sorted current) (sorted selected))
  then (
    let lb : W.List_box.t = cast w in
    (* A no-op in [Browse] mode, where GTK refuses to leave nothing selected; the
       [select_row] below replaces the selection there instead. Nothing is clamped: what
       the model asked for is written, and what GTK kept is what the next frame's
       comparison reads back. See [Node.list_box]. *)
    W.List_box.unselect_all lb;
    List.iter selected ~f:(fun key ->
      Option.iter (row_by_key w key) ~f:(fun row -> W.List_box.select_row lb (Some row))))
;;

(* GTK hands this callback a [GtkListBoxRow] the application has never seen, and the row's
   index moves whenever the list does -- which is why an application written against GTK
   directly keeps an array beside the list box. The key the node carried is what the
   handler gets instead, and [Child_keys] is the map that makes it possible. This is the
   whole reason [Signals]' [Payload] arm exists for a signal that returns [unit].

   The lookup is in [fire] rather than in [connect], where the payload is otherwise
   assembled: [Child_keys.find_exn] raises, [connect]'s closure is called straight from C,
   and [Signals.dispatch_payload] is the only thing here that stands between a raise and
   GTK's stack frame. Nothing is lost by deferring it -- the row is an ordinary callback
   argument that stays valid, unlike a click's modifier state -- and it is not even
   reached when the slot is empty. *)
let row_activated : Signals.spec =
  Payload
    { attr = Attr.Name.On_row_activated
    ; connect =
        (fun w ~callback ->
          Signals.connected
            w
            (W.List_box.on_row_activated (cast w) ~callback:(fun ~row ->
               callback (row :> Widget.t))))
    ; fire =
        (fun _w attr row ->
          match (attr :> Attr.Private.t) with
          | On_row_activated handler ->
            (), Some (handler (Child_keys.find_exn row_keys row ~what:"list box row"))
          | _ -> (), None)
    ; declined = ()
    }
;;

(* [selected-rows-changed] carries nothing, so this one is a [Read_back] -- the
   selection *is* readable off the widget. It still goes through [Child_keys], to answer
   in the application's terms rather than GTK's. *)
let selected_rows_changed : Signals.spec =
  Read_back
    { attr = Attr.Name.On_selected_rows_changed
    ; connect =
        (fun w ~callback ->
          Signals.connected w (W.List_box.on_selected_rows_changed (cast w) ~callback))
    ; fire =
        (fun w attr ->
          match (attr :> Attr.Private.t) with
          | On_selected_rows_changed handler -> Some (handler (selected_keys w))
          | _ -> None)
    }
;;

let impl : Widget_impl.t =
  { name = "ListBox"
  ; create =
      (fun (kind : Kind.t) ->
        match kind with
        | List_box p ->
          let b = W.List_box.new_ () in
          let w = (b :> Widget.t) in
          Widget_impl.batch w (fun () ->
            W.List_box.set_selection_mode b (selection_mode p.selection_mode);
            W.List_box.set_activate_on_single_click b p.activate_on_single_click;
            W.List_box.set_show_separators b p.show_separators);
          (* [selected] is deliberately not applied here: the rows do not exist yet (the
             patcher attaches children after [create]), so there would be nothing to
             select. [apply_selection] does it from the fixup pass. *)
          w
        | k -> Widget_impl.wrong_kind "ListBox" k)
  ; update =
      (fun w ~(old : Kind.t) (new_ : Kind.t) ->
        match old, new_ with
        | List_box old, List_box new_ ->
          let b : W.List_box.t = cast w in
          Widget_impl.batch w (fun () ->
            (* Writing the mode clears the selection GTK was holding -- switching a
               [Multiple] list box to [Single] drops all of it rather than keeping one --
               which is harmless here only because the selection fixup runs after every
               pass and puts the model's back. *)
            if not (Selection_mode.equal old.selection_mode new_.selection_mode)
            then W.List_box.set_selection_mode b (selection_mode new_.selection_mode);
            if not (Bool.equal old.activate_on_single_click new_.activate_on_single_click)
            then W.List_box.set_activate_on_single_click b new_.activate_on_single_click;
            if not (Bool.equal old.show_separators new_.show_separators)
            then W.List_box.set_show_separators b new_.show_separators)
        | _, k -> Widget_impl.wrong_kind "ListBox" k)
      (* [selected] is controlled, but not from here: [reassert] runs before the children
         are patched, so on the frame that both adds a row and selects it there would be
         nothing to select. The patcher enqueues [apply_selection] instead, and the fixup
         pass runs it once the tree is complete. *)
  ; reassert = None
  ; signals = [ row_activated; selected_rows_changed ]
  ; children =
      Widget_impl.Slots
        [ (* Not a row: it has no key, it is never selected or activated, and it must not
             take part in the rows' reconciliation. GTK shows it in place of an empty
             list. *)
          ( "placeholder"
          , Widget_impl.Slot_single
              { set = (fun w c -> W.List_box.set_placeholder (cast w) c) } )
        ; ( "rows"
          , Slot_list
              { insert =
                  (fun parent ~after ~node child ->
                    let row = wrap ~node child in
                    (* [GtkListBox] has no insert-after; it has insert-at-index. The
                       patcher's [after] is a *widget*, so turn it back into an index with
                       the wrapper's own [get_index] -- which is GTK's answer, not the
                       patcher's, and is correct here precisely because the list box
                       interposes nothing else: its rows are exactly the wrappers this
                       impl made, and a placeholder is not one of them. [None] is index 0. *)
                    let index =
                      match after with
                      | None -> 0
                      | Some w ->
                        W.List_box_row.get_index (row_of ~what:"the preceding row" w) + 1
                    in
                    W.List_box.insert (cast parent) (row :> Widget.t) index)
              ; move =
                  Some
                    (fun parent ~child ~after ->
                      (* No [reorder_child_after] on a [GtkListBox]: remove and re-insert.
                         The row survives (this scope holds a reference to it across the
                         unparenting), so keyed identity is preserved -- which is the
                         whole claim, and [live_lists.ml]'s reorder case is what checks
                         it. [remove] can drop the selection; the selection fixup runs
                         after every pass and puts it back.

                         The predecessor's index is read *after* the removal, because
                         [after] was computed over the sibling list with this child
                         already taken out of it, and that is the list GTK holds once the
                         remove has happened. Today the two orders give the same answer --
                         [Reconcile.diff] emits every [Move] with [from > to_], so the
                         predecessor is always before the row being moved and its index is
                         untouched by the removal -- so this is not a bug fixed but an
                         assumption not made: it is what [after]'s contract says, and it
                         stays right if that invariant ever widens. *)
                      let row = row_of ~what:"the row being moved" child in
                      W.List_box.remove (cast parent) (row :> Widget.t);
                      let index =
                        match after with
                        | None -> 0
                        | Some w ->
                          W.List_box_row.get_index (row_of ~what:"the preceding row" w)
                          + 1
                      in
                      W.List_box.insert (cast parent) (row :> Widget.t) index)
              ; remove =
                  (fun parent child ->
                    let row = row_of ~what:"the row being removed" child in
                    (* Dropped here rather than left to the GC: the table is shared by
                       every list box in the process, and a filtered list would otherwise
                       accumulate entries until the rows themselves were collected. *)
                    Child_keys.remove row_keys (row :> Widget.t);
                    W.List_box.remove (cast parent) (row :> Widget.t))
              ; updated =
                  (fun _parent ~old ~node child ->
                    (* The key cannot change -- a changed key is a different child to the
                       reconciler -- so only the two row flags are re-read. *)
                    let row = row_of ~what:"a patched row" child in
                    if not (Bool.equal (selectable old) (selectable node))
                    then W.List_box_row.set_selectable row (selectable node);
                    if not (Bool.equal (activatable old) (activatable node))
                    then W.List_box_row.set_activatable row (activatable node))
              } )
        ]
  }
;;
