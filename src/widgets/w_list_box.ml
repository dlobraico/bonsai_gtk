open! Core
open Bonsai_gtk_vtree
open Gtk_import

(* One table for every list box in the process, mapping each row's *child* to the key its
   node carried. A row is looked up through [W.List_box_row.get_child].

   Keyed on the child rather than on the [GtkListBoxRow] this impl makes, and that is a
   lifetime requirement rather than a preference. [Child_keys] is an ephemeron over the
   OCaml value, so an entry lives exactly as long as {i that value} is reachable -- and
   the only OCaml value for a wrapper this impl makes is the transient one [wrap] returns,
   which is unreachable the moment [wrap] does. Keyed on the wrapper, the table lost every
   entry at the first major collection: the rows stayed selected and [selected_keys]
   answered nothing, with no error anywhere. The child's OCaml value is the one the
   patcher stores in [live.widget], so it is reachable for exactly as long as the node is,
   which is the lifetime the table wants -- and is why [w_search_entry.ml]'s [Echo], keyed
   on a widget the live tree holds, has always worked.

   Uniqueness is unaffected by the change: two list boxes rendering the same child
   {i node} still mount two distinct child widgets. *)
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
  Child_keys.set row_keys child (row_key node);
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

(* Every row, in GTK's own order.

   {b Do not replace this with [W.List_box.get_selected_rows]}, however much shorter that
   reads. [gtk_list_box_get_selected_rows] is transfer-container -- the [GList] is the
   caller's to free, the rows in it are borrowed -- and ocgtk's generated stub wraps each
   row with no [g_object_ref_sink] while the wrapper's finaliser unconditionally unrefs it
   ([ml_list_box_gen.c:229-238]). Every call therefore hands out one unbalanced unref per
   selected row, and since [apply_selection] reads the selection on every mount, every
   patch and every no-change frame, an idle application disposes its own still-parented
   rows within a few frames of a major collection: the selection empties itself, GTK logs
   "has a parent GtkListBox during dispose", and the process segfaults shortly after.
   [test/live/live_lists.ml]'s first block reproduces exactly that when this walk is put
   back.

   [get_row_at_index] does [g_object_ref_sink] its result ([ml_list_box_gen.c:258-265]),
   so this walk is balanced. The fork already carries the identical fix for
   [GtkFlowBoxChild] one file over ([ml_flow_box_gen.c:222-233], whose comment describes
   this exact bug); the [GtkListBox] twin is unfixed in the pinned binding and is on the
   backlog for Task 14. Until that lands, nothing in this library may call
   [get_selected_rows]. *)
let rows (b : W.List_box.t) =
  let rec go i acc =
    match W.List_box.get_row_at_index b i with
    | None -> List.rev acc
    | Some row -> go (i + 1) (row :: acc)
  in
  go 0 []
;;

(* The key a row was built from: through its child, because that is what the table is
   keyed on. A row this impl made always has one. *)
let key_of_row (row : W.List_box_row.t) =
  Option.bind (W.List_box_row.get_child row) ~f:(Child_keys.find row_keys)
;;

let key_of_row_exn (row : W.List_box_row.t) =
  match W.List_box_row.get_child row with
  | Some child -> Child_keys.find_exn row_keys child ~what:"list box row"
  | None ->
    invalid_arg "list box row has no child (every row this impl makes is given one)"
;;

(* Every selected row, as the keys the nodes carried. Read through [Child_keys], because
   the question an application asks is about its own rows and GTK's answer is a list of
   widgets it has never seen. In widget order, which is what
   [Attr.on_selected_rows_changed]'s doc promises.

   A row GTK reports that this impl did not register cannot happen -- every row in a
   [GtkListBox] this library owns was made by [wrap] -- but dropping one is the right
   response if it ever does: this runs inside a signal emission, and under-reporting a
   selection is better than raising there. *)
let selected_keys (w : Widget.t) =
  rows (cast w)
  |> List.filter ~f:W.List_box_row.is_selected
  |> List.filter_map ~f:key_of_row
;;

(* One key, resolved by walking the list box. The selection fixup builds a table from its
   own walk instead; see [apply_selection], and see [W_flow_box.child_by_key] for why
   neither may be cached into a table that outlives the call. *)
let row_by_key (w : Widget.t) key =
  List.find
    (rows (cast w))
    ~f:(fun row -> Option.exists (key_of_row row) ~f:(String.equal key))
;;

(* Every row's entry dropped at once, for the list box that is going away whole. Its rows
   never pass through [list_ops.remove] -- the patcher tears a subtree down by walking it,
   not by removing each child from its parent -- so without this their entries would sit
   in the process-wide table until the wrappers themselves were collected. The ephemeron
   makes that bounded rather than a leak, but "the next GC" is no more a bound for a page
   the user switched away from than it is for a row the user filtered out, which is the
   argument [list_ops.remove] already makes.

   Called from [Patcher.destroy], where the [GtkListBox] still holds its rows: the
   children's own teardown detaches them from Bonsai without unparenting them. *)
let forget_rows (w : Widget.t) =
  List.iter
    (rows (cast w))
    ~f:(fun row ->
      Option.iter (W.List_box_row.get_child row) ~f:(Child_keys.remove row_keys))
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
   user could never keep a multi-selection.

   Narrowing to the keys that resolve to a row before comparing is the same claim from the
   other side, and it is what makes "a key naming no row is ignored" mean {i inert} rather
   than merely {i harmless}. [current] can only hold keys of rows that exist, so comparing
   it against the unfiltered [selected] is false forever the moment the model holds one
   extra id -- and every frame would then [unselect_all] and re-select the whole surviving
   selection, which is exactly what the sorting above exists to prevent, arriving by
   another door. It is also the case ruling 4 went out of its way to bless: a model that
   keeps a selected id through a filter change.

   The row still comes back {i on the frame the row does}: a returning row makes [wanted]
   grow, the comparison goes false once, and the fixup selects it -- the same-frame rule
   [Node.stack ~visible_child] has, and the reason this is a fixup rather than a
   [reassert].

   What is deliberately {i not} narrowed is the write itself: [selected] is what gets
   written, so ruling 5 is untouched -- what the model asked for reaches GTK, and what GTK
   kept is what the next frame reads back. A model asking for something the mode cannot
   hold (three keys in [Single], a [row_selectable false] row) therefore still rewrites on
   every frame; that is documented on [Node.list_box] as a model to bring into line with
   its mode, and it is not the same thing as a key that is simply not here yet. *)
let apply_selection (w : Widget.t) ~selected =
  let sorted = List.sort ~compare:String.compare in
  (* One walk of the list box, and a key table built from it for this call only -- the
     same change, for the same reason, as [W_flow_box.apply_selection], whose comment
     carries the measurement. Resolving each key with [row_by_key] made this O(|selected|
     x rows) on every mount, every patch and every no-change frame; a sidebar merely
     happens to be small, and the code was identical.

     Per call rather than per widget, and that is a safety property: the table is built
     from the walk this function already does and dies with the call, so it cannot outlive
     a removal and hand [select_row] a detached row. *)
  let all = rows (cast w) in
  let by_key = Hashtbl.create (module String) in
  List.iter all ~f:(fun row ->
    Option.iter (key_of_row row) ~f:(fun key ->
      (* First wins, as [List.find] did; duplicate sibling keys are rejected by
         [Reconcile.check_unique_keys] at mount and at patch. *)
      ignore (Hashtbl.add by_key ~key ~data:row : [ `Ok | `Duplicate ])));
  (* In widget order, because [all] is -- what [Attr.on_selected_rows_changed] promises. *)
  let current =
    List.filter all ~f:W.List_box_row.is_selected |> List.filter_map ~f:key_of_row
  in
  let wanted = List.filter selected ~f:(Hashtbl.mem by_key) in
  if not (List.equal String.equal (sorted current) (sorted wanted))
  then (
    let lb : W.List_box.t = cast w in
    (* A no-op in [Browse] mode, where GTK refuses to leave nothing selected; the
       [select_row] below replaces the selection there instead. Nothing is clamped: what
       the model asked for is written, and what GTK kept is what the next frame's
       comparison reads back. See [Node.list_box]. *)
    W.List_box.unselect_all lb;
    List.iter selected ~f:(fun key ->
      Option.iter (Hashtbl.find by_key key) ~f:(fun row ->
        W.List_box.select_row lb (Some row))))
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
   reached when the slot is empty.

   The payload's type is [W.List_box_row.t], not an upcast [Widget.t]: [Signals]' ['p] is
   existential, so [connect] can hand the callback the row GTK actually passed and [fire]
   needs no downcast. It was a [Widget.t] with a bare [cast] in [fire] until
   [task-6-review.md]'s N3 pointed out that this file goes to the trouble of a type-name
   check in [row_of] for exactly that reason. [w_flow_box.ml] was written this way from
   the start. *)
let row_activated : Signals.spec =
  Payload
    { attr = Attr.Name.On_row_activated
    ; connect =
        (fun w ~callback ->
          Signals.connected
            w
            (W.List_box.on_row_activated (cast w) ~callback:(fun ~row -> callback row)))
    ; fire =
        (fun _w attr row ->
          match (attr :> Attr.Private.t) with
          | On_row_activated handler -> (), Some (handler (key_of_row_exn row))
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
                    (* [child] is the table's key, not [row]; see [row_keys]. *)
                    (* Dropped here rather than left to the GC: the table is shared by
                       every list box in the process, and a filtered list would otherwise
                       accumulate entries until the rows themselves were collected.

                       *Before* the GTK call, which is the right order but -- correcting
                       what this comment claimed in M2 -- is belt-and-braces rather than
                       load-bearing. GTK does emit [selected-rows-changed] synchronously
                       from the remove, so a handler really does run mid-patch; but
                       [selected_keys] answers by walking the rows the list box still
                       holds, so a row that has left cannot appear in that answer whatever
                       the table still remembers. Moving this line down changes no
                       observable behaviour (measured in [live_lists.ml], for both
                       containers). Keep the order anyway: it is free, and it is what
                       makes the table's contents match the tree at every point a handler
                       could look. *)
                    Child_keys.remove row_keys child;
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
