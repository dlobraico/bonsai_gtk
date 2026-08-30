open! Core
open Bonsai_gtk_vtree
open Gtk_import

(* GTK's "nothing is selected" is [GTK_INVALID_LIST_POSITION], which is [G_MAXUINT] and
   which OCaml sees as [4294967295]. The vtree says [-1], because that is the number an
   application writes and because a positive sentinel larger than every real index would
   compare the wrong way round against any bounds check that met it.

   The translation is these two functions and nothing else in the library: no other file
   mentions [invalid_list_position], and [Node.drop_down]'s [~selected] and
   [Attr.on_selected_changed]'s argument are both in vtree units on either side of them. *)
let to_gtk = function
  | -1 -> Gtk_constants.invalid_list_position
  | n -> n
;;

let of_gtk n = if n = Gtk_constants.invalid_list_position then -1 else n

(* The items, written into the model the drop-down already holds.

   [GtkStringList] has [append], [remove] and [splice], and the brief's ruling rejected
   computing a minimal splice from two string lists -- a diff nobody has asked for. It is
   right to. But [splice] does not require a diff: [splice model 0 n_old new_items]
   replaces the whole content in one call, which is the same "no diff, one call" property
   a model replacement has and strictly better on four counts:

   - {b it allocates no GObject}, so it does not pay [String_list.new_]'s leaked reference
     (the stub reference-sinks a non-floating constructor return, so one model plus its
     copied strings is leaked per call, permanently, with no [unref] reachable from OCaml
     to compensate -- see [docs/m1-backlog.md]);
   - {b the selection survives}. [GtkSingleSelection] carries its position across a splice
     and only moves it when the content forces it, where taking a whole new model resets
     it to item 0. So "the widget is never left showing an item the model did not choose"
     stops depending on the [update]-then-[reassert] ordering and becomes true by
     construction; the ordering still holds and is still what corrects the cases where the
     content {i does} force a move;
   - it therefore emits {b half} the [notify::selected] traffic: one write's worth rather
     than a reset plus a re-apply (measured, and the counts are in the golden);
   - it skips the popup close and the model swap that [set_model] forces.

   The model object is consequently {b never replaced} after [create]. That is a stronger
   claim than the one this file used to make, and it is the one [test/live/live_text.ml]
   asserts, by GObject identity across every patch in the file.

   {b Why the cast is safe, and what happens if it ever is not.} [get_model] answers a
   [List_model.t] -- the interface -- and [splice] is a [GtkStringList] method, so this
   has to go the other way from [from_gobject]'s checked interface cast and there is no
   checked downcast in the binding. The invariant is that this library installs a
   [GtkStringList] and nothing else: [create] uses [new_from_strings], and the only other
   writer of the model property is the fallback below. Rather than rest on that, the type
   is checked at runtime -- one [g_type_is_a] per items change -- and a model that is
   somehow not a [GtkStringList] falls back to replacement, which is correct for any model
   and merely leaks. So the invariant is enforced rather than assumed, and breaking it
   later degrades rather than corrupts. *)
let string_list_type = lazy (Gobject.Type.from_name "GtkStringList")

let set_items (d : W.Drop_down.t) items =
  let additions = Array.of_list items in
  match W.Drop_down.get_model d with
  | Some model when Gobject.Type.is_a (Gobject.get_type model) (force string_list_type) ->
    let sl : W.String_list.t = cast model in
    (* [n_removals] must be exact -- [gtk_string_list_splice] requires
       [position + n_removals <= length] -- so it is read off the model rather than off
       the previous node, which is the same reason every controlled prop compares against
       the widget. *)
    W.String_list.splice sl 0 (List_model.get_n_items model) (Some additions)
  | Some _ | None ->
    (* Unreachable through this library's own constructors, and kept because "unreachable"
       is an invariant rather than a type. It is also the one path that still calls the
       leaking [String_list.new_]; a model that got here would leak one GObject per items
       change, which is worth strictly less than corrupting memory with an unchecked cast. *)
    let sl = W.String_list.new_ (Some additions) in
    W.Drop_down.set_model d (Some (List_model.from_gobject sl))
;;

(* What this drop-down has already asked GTK for and been refused, per widget.

   Weakly keyed on the widget, as [w_text_view.ml]'s cache and [w_search_entry.ml]'s echo
   record are: a view that is destroyed takes its entry with it rather than pinning the
   GObject alive. The key must be the [Widget.t] the patcher retains -- the same value
   [create] returned and [reassert] is handed -- which is [Child_keys]' invariant in a
   smaller place. *)
module Cache = Stdlib.Ephemeron.K1.Make (struct
    type t = Widget.t

    let equal = Gobject.same
    let hash = Stdlib.Hashtbl.hash
  end)

type cached =
  { (* The vtree index a write was last refused for, kept so that the decision is made
       once rather than on every frame -- see [reassert]. An [int option] rather than the
       [string option] the text view keeps for the same purpose, so there is no string to
       adopt and the comparison is already a machine word. *)
    mutable refused : int option
  ; (* A refusal the patcher has not yet reported. Taken (and cleared) by
       [Patcher.enqueue_fixups], which is the one place holding both this widget and the
       path of the node it came from. *)
    mutable unreported : string option
  }

let cache : cached Cache.t = Cache.create 8

let state w =
  match Cache.find_opt cache w with
  | Some st -> st
  | None ->
    let st = { refused = None; unreported = None } in
    Cache.replace cache w st;
    st
;;

(* The message for a refused selection, if there is one that has not been reported yet.

   Called by the patcher once per drop-down per frame, because a [Widget_impl] is handed a
   widget and a kind and knows neither where it is in the tree nor how the runtime
   reports. Cleared by the read, so one refusal is reported once however many frames it
   survives. *)
let take_report w =
  let st = state w in
  match st.unreported with
  | None -> None
  | Some message ->
    st.unreported <- None;
    Some message
;;

let forget_refusal w =
  let st = state w in
  st.refused <- None
;;

(* Why GTK is still showing something else after a write.

   Two shapes, and they are the two states a [GtkDropDown] will not hold. Neither is a
   mistake the constructor can refuse, because both are states a correct model passes
   {i through}: the vtree's job here is to say what happened, not to end the frame.

   {b Nothing selected, over a non-empty list.} A [GtkDropDown] selects through an
   internal [GtkSingleSelection] whose [autoselect] property is [true] and which no
   drop-down method exposes, so [gtk_drop_down_set_selected] with the "nothing" sentinel
   over a non-empty model does nothing at all: the item that was selected stays selected
   and GTK does not even emit [notify::selected] (measured -- two items,
   [set_selected invalid], zero notifications, selection unchanged).

   {b An index past the end.} GTK ignores a position outside its model, silently and
   without a notification (measured: [set_selected 5] on a three-item model leaves the
   selection where it was). This is the state a model reaches by holding its items and its
   index in two different pieces of Bonsai state and shrinking the list -- for one frame
   the index is stale, and it is a frame every real application will have. It is the
   drop-down's version of Tasks 6-8's ghost key, and it gets the ghost key's answer: inert
   while it names nothing, selected on the frame the list grows to include it, and
   reported once so that a model which is {i permanently} wrong is not silent.

   Both are written once, read back, remembered against the index, and reported with the
   node's path -- the treatment [w_text_view.ml] gives text a [GtkTextBuffer] will not
   store. *)
let n_items (d : W.Drop_down.t) =
  match W.Drop_down.get_model d with
  | None -> 0
  | Some model -> List_model.get_n_items model
;;

let refusal (d : W.Drop_down.t) ~selected ~live =
  let showing =
    if live = -1 then "nothing is selected" else sprintf "item %d is still selected" live
  in
  if selected = -1
  then
    sprintf
      "~selected:-1 asks for nothing to be selected, but a GtkDropDown over a non-empty \
       list keeps a selection (its GtkSingleSelection has autoselect set, and no \
       GtkDropDown method turns that off); %s. Render ~items:[] for a drop-down with \
       nothing in it, or select an item."
      showing
  else
    sprintf
      "~selected:%d names no item: the list holds %d. GTK ignores a position outside its \
       model, so %s -- and %d will be selected on the frame the list grows to include \
       it. If the index and the items come from different state, clamp the index where \
       the view builds the node."
      selected
      (n_items d)
      showing
      selected
;;

(* Write the selection and check that it landed.

   The read-back is what turns "GTK ignores this" into something the library can say out
   loud. It is one C call and it happens only on a frame that was about to write anyway. *)
let select (d : W.Drop_down.t) st ~selected =
  let want = to_gtk selected in
  W.Drop_down.set_selected d want;
  let live = W.Drop_down.get_selected d in
  if live = want
  then st.refused <- None
  else (
    st.refused <- Some selected;
    st.unreported <- Some (refusal d ~selected ~live:(of_gtk live)))
;;

(* Whether this exact selection has already been decided against.

   Safe to consult {i before} the comparison with the widget, on [w_text_view.ml]'s
   [already_refused] reasoning: [st.refused] is cleared by every write that lands and by
   every items change, which are the only two things that can change GTK's answer, so a
   matching memo means the write can only fail again. Without it, a drop-down parked on
   [~selected:(-1)] over a non-empty list would set the property on every idle frame
   forever -- each one a C call GTK throws away, and each one inside a
   [freeze_notify]/[thaw_notify] pair. *)
let already_refused st selected =
  match st.refused with
  | Some n -> n = selected
  | None -> false
;;

(* [items] is compared here, and this comparison is what decides whether the expensive
   half of [update] runs.

   [phys_equal] first, and it is worth the line: a view that computes its items once and
   hands back the same list every render answers in a pointer comparison. When it does not
   -- a view that builds the list inline, which is the common shape -- this is [n] string
   comparisons that stop at the first difference.

   Either way it is paid only on a frame where {i something} about this node already
   differed: the patcher compares [Kind.equal_props] first and skips [update] entirely
   when the props are equal, so an idle frame never reaches this function at all. *)
let same_items a b = phys_equal a b || List.equal String.equal a b

(* [GtkDropDown]'s only signal is [activate], which fires when the user re-picks the item
   already showing and carries nothing; there is no [selected] signal. So a selection
   change arrives as [notify::selected] through the generic marshaller, which carries no
   payload, and the handler reads the position back off the widget (spec §6.4) -- the same
   shape [w_switch.ml] and [w_stack.ml] established, needing no new machinery.

   This is the connection stavekeeper makes by hand today ([setlist_ui.ml:145-152], with a
   comment saying ocgtk binds no such signal), and this is the library's answer to it. Two
   differences worth naming: the raw version is [~after:true] where the generated helpers
   and this one are [~after:false], and the raw version fires for the {i library's} writes
   too, where this one is behind the reentrancy guard -- which matters here more than for
   most signals, because re-applying the selection after an items change is a write the
   library makes on the user's behalf inside a patch. *)
let selected_changed : Signals.spec =
  Read_back
    { attr = Attr.Name.On_selected_changed
    ; connect = Signals.notify ~prop:"selected"
    ; fire =
        (fun w attr ->
          match (attr :> Attr.Private.t) with
          | On_selected_changed handler ->
            Some (handler (of_gtk (W.Drop_down.get_selected (cast w))))
          | _ -> None)
    }
;;

(* Controlled (spec §6.5), and the one selection in this library that lives in [reassert]
   rather than in the fixup queue.

   The other three -- a stack's visible child, a list box's and a flow box's selection, a
   notebook's page -- name {i children}, and [reassert] runs before the children are
   patched, so on the frame that both adds a row and selects it there would be nothing to
   select. A drop-down's items are {i props} of the same node: by the time this runs they
   have already been written by [create] or [update], so there is nothing to wait for. The
   asymmetry is the items' doing, not an oversight.

   Compared against the widget rather than the previous node, like every controlled prop:
   the user may have chosen something since the last render, and a model that declined the
   choice renders exactly the props it rendered before -- so [update] is skipped and this
   is the only thing left to put the widget back. *)
let reassert w (kind : Kind.t) =
  match kind with
  | Drop_down p ->
    let d : W.Drop_down.t = cast w in
    let st = state w in
    (* The memo first, for [w_text_view.ml]'s reason (task-9-review.md R1): a frame parked
       on a refusal must pay neither the write nor the freeze/thaw. Both questions are
       O(1) here -- an int getter and an int compare -- so this ordering is about not
       writing rather than about not comparing, but the shape is the same one. *)
    let writes =
      (not (already_refused st p.selected))
      && W.Drop_down.get_selected d <> to_gtk p.selected
    in
    Widget_impl.batch_if writes w (fun () ->
      if writes then select d st ~selected:p.selected)
  | k -> Widget_impl.wrong_kind "DropDown" k
;;

let impl : Widget_impl.t =
  { name = "DropDown"
  ; create =
      (fun (kind : Kind.t) ->
        match kind with
        | Drop_down p ->
          (* [new_from_strings] rather than [new_ (Some model) None], for two reasons. It
             builds the [GtkStringList] inside GTK, so the create path never touches
             [String_list.new_] and never pays its leaked reference. And it is documented
             to install the [expression] property that the popup's search filter needs --
             without one, [~enable_search:true] shows a search entry that matches nothing.
             (This library cannot assert that second half: ocgtk's [get_expression]
             answers [None] on a drop-down GTK built with one, its stub having
             [g_object_ref_sink]ed a [GtkExpression], which is not a [GObject]. Recorded
             with the other binding defects.) *)
          let d = W.Drop_down.new_from_strings (Array.of_list p.items) in
          let w = (d :> Widget.t) in
          Widget_impl.batch w (fun () ->
            (* GTK's own are [false] and [true], so each is written only when the node
               asks for the other -- a no-op write would still emit a [notify::] for the
               guard to swallow. [Defaults] is not re-exported from [Bonsai_gtk_vtree] (it
               is [Kind]'s and [Node]'s), so the two values are spelled out here, as every
               other impl in this directory spells its own out. *)
            if p.enable_search then W.Drop_down.set_enable_search d true;
            if not p.show_arrow then W.Drop_down.set_show_arrow d false;
            (* Selection last, and through [reassert] rather than a second [set_selected]
               of its own, so the one controlled prop this kind has has exactly one
               implementation -- including the read-back that notices GTK declining it. A
               drop-down built from a non-empty list comes up showing item 0, so a node
               asking for anything else pays one write here, which is the write the next
               patch would have made anyway. *)
            reassert w kind);
          w
        | k -> Widget_impl.wrong_kind "DropDown" k)
  ; update =
      (fun w ~(old : Kind.t) (new_ : Kind.t) ->
        match old, new_ with
        | Drop_down old, Drop_down new_ ->
          let d : W.Drop_down.t = cast w in
          Widget_impl.batch w (fun () ->
            if not (same_items old.items new_.items)
            then (
              set_items d new_.items;
              (* A rebuild changes what GTK will accept -- a model that has become empty
                 will now take "nothing selected", and one that has become non-empty will
                 not -- so a refusal remembered against the old model must not outlive it.
                 [reassert] runs immediately after this and decides again. *)
              forget_refusal w);
            if not (Bool.equal old.enable_search new_.enable_search)
            then W.Drop_down.set_enable_search d new_.enable_search;
            if not (Bool.equal old.show_arrow new_.show_arrow)
            then W.Drop_down.set_show_arrow d new_.show_arrow)
          (* [selected] is deliberately absent: it is controlled, so it belongs to
             [reassert], which the patcher runs immediately after this and on every other
             patch too -- including this one, where the model rebuild above has just reset
             the widget's selection to item 0. That ordering is the whole reason a rebuild
             is safe: the selection is re-applied in the same frame, so the drop-down is
             never left showing an item the model did not choose. *)
        | _, k -> Widget_impl.wrong_kind "DropDown" k)
  ; reassert = Some reassert
  ; signals = [ selected_changed ]
  ; children = Widget_impl.No_children
  }
;;
