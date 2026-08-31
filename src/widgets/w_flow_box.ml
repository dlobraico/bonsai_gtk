open! Core
open Bonsai_gtk_vtree
open Gtk_import

(* {b Why this is not a functor over [w_list_box.ml].}

   The two files have the same shape -- auto-wrap the child, key the wrapper's child in a
   [Child_keys] table, turn the patcher's [~after] widget into an index, compare the
   widget's selection against the model's from the fixup pass -- and roughly thirty lines
   of that shape are identical modulo names. A functor would have to be parameterised on
   the wrapper type ([GtkListBoxRow] vs [GtkFlowBoxChild]), the container type, three
   method names ([insert]/[remove]/[select_row] vs [select_child], [get_row_at_index] vs
   [get_child_at_index]), two signal names, two attr names and the whole props record --
   at which point the parameter list is longer than the body, and the reader of either
   file has to hold two widgets in their head to understand one.

   They also differ where it matters. A list box has a placeholder slot and per-row
   [selectable]/[activatable] flags; a flow box has neither and has seven geometry props
   instead. [gtk_list_box_remove] refuses an inner child while [gtk_flow_box_remove]
   accepts one. The parts that would be shared are the parts that are three lines each.

   This is a judgement, not a law: the third keyed container (Task 8's [GtkNotebook]) is
   the point at which to revisit it, and it is the one that would settle it -- a notebook
   is keyed on the page's own content widget rather than on a wrapper, so if a shared
   abstraction still fits after that, it is a real one. *)

(* This module's own table, per [Child_keys]' "one per container module" rule -- never
   [W_list_box]'s.

   Keyed on the [GtkFlowBoxChild]'s {i child} (the widget the patcher stores in
   [live.widget]) rather than on the wrapper this impl makes, which is the lifetime
   requirement [child_keys.mli] states at length: the ephemeron is weak in the OCaml
   value, and the only OCaml value for a wrapper made here is the transient one [wrap]
   returns. Keyed on the wrapper, every entry is gone at the first major collection while
   GTK keeps the children perfectly alive, and the lookups simply stop answering. *)
let child_keys = Child_keys.create ()

let child_key (node : Node.t) =
  match node.key with
  | Some key -> key
  | None ->
    (* Unreachable through [Node.flow_box], which rejects an unkeyed child at the
       constructor; kept for the paths that constructor did not build, on
       [w_list_box.ml]'s reasoning. *)
    invalid_arg
      "flow box child has no ~key (a child's key is the identity handlers receive)"
;;

(* No per-child flags to read off the node, and that is GTK's doing: a [GtkFlowBoxChild]
   has no [selectable] and no [activatable] (its whole surface is [set_child],
   [get_child], [get_index], [is_selected], [changed]), so unlike [W_list_box.wrap] there
   is nothing here but the wrapping and the key. [Placement.read_by] has no [Flow_box] arm
   for the same reason, and [Attr.row_selectable] on one of these children is rejected. *)
let wrap ~(node : Node.t) (child : Widget.t) =
  let c = W.Flow_box_child.new_ () in
  W.Flow_box_child.set_child c (Some child);
  Child_keys.set child_keys child (child_key node);
  c
;;

(* The patcher's list ops are handed the application's own child widget, never the wrapper
   -- [Patcher.patch_list] keeps [l.widget] in its bookkeeping and computes [~after] from
   that same list. Task 6 established this for [GtkListBox] and the answer is quoted here
   rather than re-derived: climb [Widget.get_parent], with a type-name check rather than a
   bare [cast], because a wrong downcast is undefined behaviour and not an exception.

   One difference from the list box, established by experiment rather than assumed:
   [gtk_flow_box_remove] {i does} accept an inner child (it walks up to the wrapper
   itself), where [gtk_list_box_remove] logs "Tried to remove non-child" and does nothing.
   [remove] below still goes through this function, because [insert] and the index
   arithmetic have no such convenience and one way of getting from a child to its wrapper
   is easier to keep right than two.

   [GtkFlowBox] also auto-wraps a plain widget handed to [insert]. This impl wraps
   explicitly anyway, and that is load-bearing rather than belt-and-braces: [move] is
   remove-and-re-insert, and re-inserting an {i inner} child would have GTK build a
   {i second} wrapper -- so a reorder would destroy the [GtkFlowBoxChild] that held the
   selection and the whole keyed-identity claim with it. Holding the wrapper is what makes
   a move preserve it. *)
let child_of ~what (child : Widget.t) : W.Flow_box_child.t =
  match Widget.get_parent child with
  | Some parent when String.equal (type_name parent) "GtkFlowBoxChild" -> cast parent
  | Some parent ->
    invalid_argf
      "flow box: %s is parented to a %s rather than to the GtkFlowBoxChild this impl made"
      what
      (type_name parent)
      ()
  | None -> invalid_argf "flow box: %s has no parent" what ()
;;

(* Every child, in GTK's own order.

   Unlike its [GtkListBox] twin this is {i not} working around a broken binding:
   [gtk_flow_box_get_selected_children] is transfer-container, and the fork's stub does
   [g_object_ref_sink] each element before wrapping it ([ml_flow_box_gen.c:216-233] --
   checked in the pinned tree, and the comment there describes the bug it fixes). The
   [GtkListBox] twin is the one that is still unfixed.

   The walk is used anyway, for three reasons that are not "the getter is unsafe": this
   function is needed for [child_by_key] and [forget_children] regardless, so using it for
   the selection too is one shape rather than two; it depends on no hand patch to a
   generated file, which the [get_selected_children] fix currently is (the real fix
   belongs in ocgtk's generator -- see docs/m2-backlog.md -- and a regenerated stub could
   drop it silently); and it makes this file read like [w_list_box.ml], where the walk is
   mandatory. If a future reader is about to "simplify" this into the getter: check the
   stub, not the GIR, and check it again after Task 14. *)
let children (b : W.Flow_box.t) =
  let rec go i acc =
    match W.Flow_box.get_child_at_index b i with
    | None -> List.rev acc
    | Some c -> go (i + 1) (c :: acc)
  in
  go 0 []
;;

let key_of_child (c : W.Flow_box_child.t) =
  Option.bind (W.Flow_box_child.get_child c) ~f:(Child_keys.find child_keys)
;;

let key_of_child_exn (c : W.Flow_box_child.t) =
  match W.Flow_box_child.get_child c with
  | Some inner -> Child_keys.find_exn child_keys inner ~what:"flow box child"
  | None ->
    invalid_arg "flow box child has no child (every one this impl makes is given one)"
;;

(* The selection as the keys the nodes carried, in widget order -- which is the order
   [gtk_flow_box_get_selected_children] answers in too (checked: selecting index 2 then
   index 0 lists 0 then 2), and which is what [Attr.on_selected_children_changed]'s doc
   promises.

   A child GTK reports that this impl never registered cannot happen; dropping one rather
   than raising is still the right response, because this runs inside a signal emission. *)
let selected_keys (w : Widget.t) =
  children (cast w)
  |> List.filter ~f:W.Flow_box_child.is_selected
  |> List.filter_map ~f:key_of_child
;;

(* One key, resolved by walking the box. For [test/live/live_lists.ml], which asks about a
   single key; the selection fixup builds a table instead, and the difference between the
   two is the point of the next comment.

   {b Never cache this into a table that outlives the call.} The obvious optimisation --
   one key-to-wrapper map per flow box, maintained by [insert]/[remove] -- is unsafe here
   in a way that is invisible: [gtk_flow_box_select_child] handed a child that is {i not}
   in the box neither warns nor refuses. It sets the child's own selected flag, so
   [is_selected] answers [true] for a widget the box has never held (measured). A map that
   outlived a removal by even one frame would hand [apply_selection] a detached wrapper
   and get a silent, invisible "selection" for it. Deriving the answer from the box means
   a key naming a child that has left simply does not resolve, which is what makes the
   ghost-key rule below mean anything. *)
let child_by_key (w : Widget.t) key =
  List.find
    (children (cast w))
    ~f:(fun c -> Option.exists (key_of_child c) ~f:(String.equal key))
;;

(* Every entry dropped at once, for the flow box that is going away whole: its children
   never pass through [list_ops.remove], because the patcher tears a subtree down by
   walking it. [W_list_box.forget_rows]' argument, and the same placement requirement in
   [Patcher.destroy] -- the arm goes {i above} the or-pattern chain, not after it. *)
let forget_children (w : Widget.t) =
  List.iter
    (children (cast w))
    ~f:(fun c ->
      Option.iter (W.Flow_box_child.get_child c) ~f:(Child_keys.remove child_keys))
;;

(* Controlled on spec §6.5's rule, compared against the widget rather than the previous
   node, and run from the fixup pass rather than from [reassert] because the children do
   not exist when [reassert] runs. This is [W_list_box.apply_selection] line for line, and
   every argument in that function's comment holds here unchanged: the sort before the
   comparison (GTK answers in widget order, the model lists whatever order it built, and
   two orderings of one selection must not look like a change); the narrowing of
   [selected] to the keys that resolve, which is what makes a ghost key {i inert} rather
   than merely harmless; and the write iterating the unnarrowed [selected], which emits
   the same calls iterating [wanted] would (an unresolvable key is skipped by the lookup
   either way) while saying at the call site that what the model asked for is what reaches
   GTK.

   The case this container adds is a selected child being {i removed}. GTK drops it from
   the selection and -- measured, contrary to a claim that has been made about
   [GtkFlowBox] -- {i does} emit [selected-children-changed] while doing so, both from
   [gtk_flow_box_remove] and from [gtk_flow_box_remove_all]. Either way it does not matter
   here, and that is the point: the selection is re-derived from the widget on every pass
   rather than cached beside it, so whether GTK announces the change or not, the next
   frame compares the model against what is actually there. What the model still holds is
   by then a key naming no child -- inert, no write -- and the divergence lasts less than
   a frame. An application that keeps the selected {i widget} in a ref has no such
   recovery, which is what makes this the strongest single argument for the declarative
   version. *)
(* The [~selected] dedup memo (M3 Task 3 step 2, docs/m2-backlog.md:150-158). A duplicated
   key in [~selected] used to make [current] and [wanted] never compare equal -- ["a"]
   against ["a"; "a"] -- so every frame ran [unselect_all] plus the redundant re-select,
   forever, with no diagnostic. The ruling takes both halves the backlog said to decide
   together: the selection is {b deduped} before the comparison (the behaviour fix -- the
   churn stops) {b and reported once per distinct list} (the model typo stays visible).
   [Refusal]'s machinery again, keyed on the whole [~selected] value: the same duplicated
   list reports once however many frames it is rendered, a different duplicated list is a
   new datum, and a clean list clears the memo so a reintroduced duplicate is reported
   again. The patcher polls [take_report] after the fixup. *)
module Selection_memo =
  Refusal.Make
    (struct
      type t = string list

      let equal = List.equal String.equal
    end)
    (Refusal.No_extra)

let take_report = Selection_memo.take_report

(* [selected] with each key kept at its first occurrence -- order-preserving, because the
   write below iterates it in the model's order. Reported through [note_duplicates] when
   anything was dropped. *)
let dedup_selected (st : Selection_memo.t) ~arg selected =
  let seen = Hash_set.create (module String) in
  let deduped =
    List.filter selected ~f:(fun key ->
      if Hash_set.mem seen key
      then false
      else (
        Hash_set.add seen key;
        true))
  in
  if List.length deduped = List.length selected
  then Selection_memo.landed st
  else if not (Selection_memo.already_refused st selected)
  then (
    let dups =
      List.find_all_dups selected ~compare:String.compare
      |> List.map ~f:(sprintf "%S")
      |> String.concat ~sep:", "
    in
    Selection_memo.refuse
      st
      selected
      ~reason:
        (sprintf
           "%s lists %s more than once; a selection holds each key at most once, and the \
            duplicates were ignored"
           arg
           dups));
  deduped
;;

let apply_selection (w : Widget.t) ~selected =
  let sorted = List.sort ~compare:String.compare in
  (* One walk of the box, and a key table built from it {i for this call only}.

     The table is what keeps this linear. Resolving each key with [child_by_key] made the
     whole function O(|selected| x children), and it runs from the fixup queue on every
     mount, every patch {i and} every no-change frame -- so an idle application paid it
     sixty times a second. Measured at 1000 children with 200 selected: 16.5 ms per idle
     frame, the entire frame budget spent deciding that nothing had changed; 500 of 500
     cost 24 ms. With the table the same frame is 0.39 ms. [live_lists.ml]'s [bench] block
     is the regression, and it reads [false] on the old shape.

     {b Per call, and that is the safety property rather than a style choice.} It is built
     from the walk this function already had to do and dies with the call, so it cannot
     outlive a removal -- which is exactly what makes it a different thing from the
     persistent map [child_by_key] warns against. A key naming a child that left the box
     between two frames is absent from the {i next} frame's table, resolves to nothing,
     and is inert; a persistent map would still hold its detached wrapper and hand it to
     [select_child], which accepts it silently. *)
  let all = children (cast w) in
  let by_key = Hashtbl.create (module String) in
  List.iter all ~f:(fun c ->
    Option.iter (key_of_child c) ~f:(fun key ->
      (* First wins, as [List.find] did. Duplicate sibling keys are rejected by
         [Reconcile.check_unique_keys] at mount and at patch, so the two cannot differ
         today; matching the old resolution is what keeps that from mattering if it ever
         changes. *)
      ignore (Hashtbl.add by_key ~key ~data:c : [ `Ok | `Duplicate ])));
  (* In widget order, because [all] is: what [Attr.on_selected_children_changed] promises,
     and what the sort below is there to make irrelevant to the comparison. *)
  let current =
    List.filter all ~f:W.Flow_box_child.is_selected |> List.filter_map ~f:key_of_child
  in
  let selected = dedup_selected (Selection_memo.state w) ~arg:"~selected" selected in
  let wanted = List.filter selected ~f:(Hashtbl.mem by_key) in
  if not (List.equal String.equal (sorted current) (sorted wanted))
  then (
    let fb : W.Flow_box.t = cast w in
    (* A no-op in [Browse] mode, where GTK refuses to leave nothing selected; the
       [select_child] below replaces the selection there instead. *)
    W.Flow_box.unselect_all fb;
    (* The deduped [selected]: the lookup skips a key naming no child, so this is the same
       sequence of calls as iterating [wanted], written the way that says what the model
       asked for is what reaches GTK. *)
    List.iter selected ~f:(fun key ->
      Option.iter (Hashtbl.find by_key key) ~f:(W.Flow_box.select_child fb)))
;;

(* The payload is a [W.Flow_box_child.t] rather than an upcast [Widget.t]: [Signals]' ['p]
   is existential, so the callback can be handed the wrapper GTK actually passes and
   [fire] needs no downcast at all. ([task-6-review.md]'s N3, taken here and applied to
   [w_list_box.ml] in the same commit -- that file had an upcast in [connect] and a
   matching unchecked [cast] in [fire], which is exactly the bare downcast [child_of] goes
   to trouble to avoid two functions up.)

   The [Child_keys] lookup is in [fire] and not in [connect], where the payload is
   otherwise assembled: [find_exn] raises, [connect]'s closure is called straight from C,
   and [Signals.dispatch_payload] is the only thing standing between a raise and GTK's
   stack frame. Nothing is lost by deferring -- the child is an ordinary callback argument
   that stays valid, unlike a click's modifier state -- and it is not reached at all when
   the slot is empty. *)
let child_activated : Signals.spec =
  Payload
    { attr = Attr.Name.On_child_activated
    ; connect =
        (fun w ~callback ->
          Signals.connected
            w
            (W.Flow_box.on_child_activated (cast w) ~callback:(fun ~child ->
               callback child)))
    ; fire =
        (fun _w attr child ->
          match (attr :> Attr.Private.t) with
          | On_child_activated handler -> (), Some (handler (key_of_child_exn child))
          | _ -> (), None)
    ; declined = ()
    }
;;

(* [selected-children-changed] carries nothing, so the selection is read back off the
   widget -- through [Child_keys], to answer in the application's terms. *)
let selected_children_changed : Signals.spec =
  Read_back
    { attr = Attr.Name.On_selected_children_changed
    ; connect =
        (fun w ~callback ->
          [ Signals.connected
              w
              (W.Flow_box.on_selected_children_changed (cast w) ~callback)
          ])
    ; fire =
        (fun w attr ->
          match (attr :> Attr.Private.t) with
          | On_selected_children_changed handler -> Some (handler (selected_keys w))
          | _ -> None)
    }
;;

(* [GtkFlowBox] implements [GtkOrientable] rather than owning the property, so the
   orientation goes through the interface cast -- the [w_box.ml] pattern. *)
let orientable (b : W.Flow_box.t) = W.Orientable.from_gobject b

let write_props (b : W.Flow_box.t) (p : Kind.flow_box_props) =
  W.Flow_box.set_selection_mode b (selection_mode p.selection_mode);
  W.Flow_box.set_activate_on_single_click b p.activate_on_single_click;
  W.Flow_box.set_min_children_per_line b p.min_children_per_line;
  W.Flow_box.set_max_children_per_line b p.max_children_per_line;
  W.Flow_box.set_row_spacing b p.row_spacing;
  W.Flow_box.set_column_spacing b p.column_spacing;
  W.Flow_box.set_homogeneous b p.homogeneous;
  W.Orientable.set_orientation (orientable b) (orientation p.orientation)
;;

let impl : Widget_impl.t =
  { name = "FlowBox"
  ; create =
      (fun (kind : Kind.t) ->
        match kind with
        | Flow_box p ->
          let b = W.Flow_box.new_ () in
          let w = (b :> Widget.t) in
          Widget_impl.batch w (fun () -> write_props b p);
          (* [selected] is not applied here: the children do not exist yet (the patcher
             attaches them after [create]). [apply_selection] does it from the fixup pass. *)
          w
        | k -> Widget_impl.wrong_kind "FlowBox" k)
  ; update =
      (fun w ~(old : Kind.t) (new_ : Kind.t) ->
        match old, new_ with
        | Flow_box old, Flow_box new_ ->
          let b : W.Flow_box.t = cast w in
          (* One batch for up to eight setters, which is the case this widget exists to
             show off: stavekeeper switches its library grid between a grid view and a
             list view by hand, with four setters and a CSS-class toggle in a
             [configure_grid_for_view] function that the two call sites have to remember
             to call. Here it is four fields of the next render's props, and the diff
             writes exactly the ones that moved, inside one freeze/thaw. *)
          Widget_impl.batch w (fun () ->
            (* Writing the mode clears whatever GTK was holding -- [Multiple] to [Single]
               drops the whole selection rather than keeping one of it (measured) -- which
               is harmless only because the selection fixup runs after every pass and puts
               the model's back. *)
            if not (Selection_mode.equal old.selection_mode new_.selection_mode)
            then W.Flow_box.set_selection_mode b (selection_mode new_.selection_mode);
            if not (Bool.equal old.activate_on_single_click new_.activate_on_single_click)
            then W.Flow_box.set_activate_on_single_click b new_.activate_on_single_click;
            if not (Int.equal old.min_children_per_line new_.min_children_per_line)
            then W.Flow_box.set_min_children_per_line b new_.min_children_per_line;
            if not (Int.equal old.max_children_per_line new_.max_children_per_line)
            then W.Flow_box.set_max_children_per_line b new_.max_children_per_line;
            if not (Int.equal old.row_spacing new_.row_spacing)
            then W.Flow_box.set_row_spacing b new_.row_spacing;
            if not (Int.equal old.column_spacing new_.column_spacing)
            then W.Flow_box.set_column_spacing b new_.column_spacing;
            if not (Bool.equal old.homogeneous new_.homogeneous)
            then W.Flow_box.set_homogeneous b new_.homogeneous;
            if not (Orientation.equal old.orientation new_.orientation)
            then
              W.Orientable.set_orientation (orientable b) (orientation new_.orientation))
        | _, k -> Widget_impl.wrong_kind "FlowBox" k)
      (* [selected] is controlled but not from here, for [w_list_box.ml]'s reason:
         [reassert] runs before the children are patched, so the frame that both adds a
         card and selects it would have nothing to select. The patcher enqueues
         [apply_selection] instead. *)
  ; reassert = None
  ; signals = [ child_activated; selected_children_changed ]
  ; children =
      (* A plain list, unlike the list box's two slots: a flow box has no placeholder. *)
      Widget_impl.List
        { insert =
            (fun parent ~after ~node child ->
              let c = wrap ~node child in
              (* [GtkFlowBox] has insert-at-index, not insert-after, so the patcher's
                 [after] widget is turned back into an index with the wrapper's own
                 [get_index] -- GTK's answer rather than the patcher's, and correct here
                 because a flow box interposes nothing except the wrappers this impl made.
                 [None] is index 0. *)
              let index =
                match after with
                | None -> 0
                | Some w ->
                  W.Flow_box_child.get_index (child_of ~what:"the preceding child" w) + 1
              in
              W.Flow_box.insert (cast parent) (c :> Widget.t) index)
        ; move =
            Some
              (fun parent ~child ~after ->
                (* No [reorder_child_after] on a [GtkFlowBox]: remove and re-insert. The
                   wrapper survives (this scope holds a reference to it across the
                   unparenting), so the [GtkFlowBoxChild] and the card inside it are the
                   same GObjects afterwards, which is the keyed-identity claim and what
                   [live_lists.ml]'s reorder case checks. The removal can drop the
                   selection; the fixup pass puts it back.

                   The predecessor's index is read {i after} the removal, because [after]
                   was computed over the sibling list with this child already taken out of
                   it. Today the two orders agree ([Reconcile.diff] emits every [Move]
                   with [from > to_], so the predecessor is always before the moved
                   child); this is an assumption not made rather than a bug fixed. *)
                let c = child_of ~what:"the child being moved" child in
                (* The list box's repair, over the other container, because GTK does the
                   same thing here: [gtk_flow_box_remove] clears [priv->selected_child]
                   and leaves [CHILD_PRIV (child)->selected] set (gtkflowbox.c:3132-3137),
                   and [insert] does not restore it. Every reader in this library reads
                   the flag, so the divergence is invisible to [selected_keys], to
                   [apply_selection] and to the goldens, while GTK's own side has lost the
                   range anchor a shift-click needs (:1105-1111) and the row keyboard
                   navigation starts from (:3210). A sortable grid of cards -- this
                   container's showcase use -- reproduces it by sorting with a card
                   selected. *)
                let was_selected = W.Flow_box_child.is_selected c in
                W.Flow_box.remove (cast parent) (c :> Widget.t);
                let index =
                  match after with
                  | None -> 0
                  | Some w ->
                    W.Flow_box_child.get_index (child_of ~what:"the preceding child" w)
                    + 1
                in
                W.Flow_box.insert (cast parent) (c :> Widget.t) index;
                (* The pair rather than a plain re-select, for the reason
                   [w_list_box.ml]'s twin gives: [gtk_flow_box_select_child_internal]
                   early-outs on [if (CHILD_PRIV (child)->selected) return]
                   (gtkflowbox.c:1013-1014), so selecting a child whose flag survived does
                   nothing at all. In [Multiple] the unselect clears this child alone
                   (:996); in [Single]/[Browse] the round trip lands on the same single
                   selection. *)
                if was_selected
                then (
                  W.Flow_box.unselect_child (cast parent) c;
                  W.Flow_box.select_child (cast parent) c))
        ; remove =
            (fun parent child ->
              let c = child_of ~what:"the child being removed" child in
              (* [child] is the table's key, not [c]; see [child_keys].

                 Dropped {i before} the GTK call. GTK does emit
                 [selected-children-changed] synchronously from the remove (measured -- it
                 does, and so does [remove_all], contrary to a claim in circulation).
                 Under [Driver] the reentrancy guard swallows that emission and the
                 application's handler never runs; a test driving [Patcher.patch] by hand
                 sees one while the patch is half-done, which is where it was measured.
                 What a handler that does run is told does not depend on this ordering,
                 though: [selected_keys] walks the children the box still holds, so a
                 departed card cannot appear in it whatever the table remembers. The order
                 is kept because it is free and because it keeps the table matching the
                 tree at every point a handler could look -- not because moving it breaks
                 anything, which was checked and does not. *)
              Child_keys.remove child_keys child;
              W.Flow_box.remove (cast parent) (c :> Widget.t))
        ; updated =
            (* Nothing to re-read: the key cannot change (a changed key is a different
               child to the reconciler) and a [GtkFlowBoxChild] has no other settings the
               flow box holds on its behalf. The list box's [updated] re-reads two row
               flags; this container has none, which is why this is
               [Widget_impl.no_list_update] rather than an empty function of its own. *)
            Widget_impl.no_list_update
        }
  }
;;
