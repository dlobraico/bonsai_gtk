open! Core
open Bonsai_gtk_vtree
open Gtk_import

let transition : Stack_transition.t -> Gtk_enums.stacktransitiontype = function
  | None_ -> `NONE
  | Crossfade -> `CROSSFADE
  | Slide_right -> `SLIDE_RIGHT
  | Slide_left -> `SLIDE_LEFT
  | Slide_up -> `SLIDE_UP
  | Slide_down -> `SLIDE_DOWN
  | Slide_left_right -> `SLIDE_LEFT_RIGHT
  | Slide_up_down -> `SLIDE_UP_DOWN
  | Over_up -> `OVER_UP
  | Over_down -> `OVER_DOWN
  | Over_left -> `OVER_LEFT
  | Over_right -> `OVER_RIGHT
  | Under_up -> `UNDER_UP
  | Under_down -> `UNDER_DOWN
  | Under_left -> `UNDER_LEFT
  | Under_right -> `UNDER_RIGHT
  | Rotate_left -> `ROTATE_LEFT
  | Rotate_right -> `ROTATE_RIGHT
;;

(* A page's name is the child's key: it is what [~visible_child] selects by and what the
   reconciler matches on, so making them the same value is what keeps the two agreeing.
   The patcher's list helpers prefix the child's path onto this message. *)
let page_name (node : Node.t) =
  match node.key with
  | Some key -> key
  | None ->
    invalid_arg "Stack child has no ~key (a stack page's key is its GTK page name)"
;;

let page_title (node : Node.t) =
  match (Attrs.find node.attrs Page_title :> Attr.Private.t option) with
  | Some (Page_title t) -> Some t
  | Some _ | None -> None
;;

(* Applied as a post-pass fixup rather than in [create], [update] or [reassert]: the pages
   exist only after the children have been patched, all three of those run before, and
   naming a page GTK does not have yet is a warning and a no-op.

   It is still the controlled discipline of spec §6.5 -- compared against what the widget
   is actually showing rather than against the previous node -- which is what puts the
   selection back after a user clicked a switcher button the model then ignored. A name no
   page carries is left alone: the frame that adds the page runs this again. *)
let select (w : Widget.t) ~visible_child =
  let s : W.Stack.t = cast w in
  if (not
        (Option.equal
           String.equal
           (W.Stack.get_visible_child_name s)
           (Some visible_child)))
     && Option.is_some (W.Stack.get_child_by_name s visible_child)
  then W.Stack.set_visible_child_name s visible_child
;;

(* ocgtk generates no [on_notify_visible_child_name]; the detailed name goes through the
   generic marshaller (spec §6.4). *)
let visible_child_changed : Signals.spec =
  { attr = Attr.Name.On_visible_child_changed
  ; connect = Signals.notify ~prop:"visible-child-name"
  ; fire =
      (fun w attr ->
        match (attr :> Attr.Private.t) with
        | On_visible_child_changed handler ->
          (* [None] only while the stack is empty, which the user cannot click their way
             into; nothing to report then. *)
          Option.map (W.Stack.get_visible_child_name (cast w)) ~f:handler
        | _ -> None)
  }
;;

let impl : Widget_impl.t =
  { name = "Stack"
  ; create =
      (fun (kind : Kind.t) ->
        match kind with
        | Stack p ->
          let s = W.Stack.new_ () in
          let w = (s :> Widget.t) in
          Widget_impl.batch w (fun () ->
            W.Stack.set_transition_type s (transition p.transition);
            W.Stack.set_transition_duration s p.transition_duration;
            W.Stack.set_hhomogeneous s p.hhomogeneous;
            W.Stack.set_vhomogeneous s p.vhomogeneous);
          (* [visible_child] is deliberately not set here: the pages do not exist yet (the
             patcher attaches children after [create]), and naming a page that is not
             there is a GTK warning. [select] applies it from the fixup pass. *)
          w
        | k -> Widget_impl.wrong_kind "Stack" k)
  ; update =
      (fun w ~(old : Kind.t) (new_ : Kind.t) ->
        match old, new_ with
        | Stack old, Stack new_ ->
          let s : W.Stack.t = cast w in
          Widget_impl.batch w (fun () ->
            if not (Stack_transition.equal old.transition new_.transition)
            then W.Stack.set_transition_type s (transition new_.transition);
            if old.transition_duration <> new_.transition_duration
            then W.Stack.set_transition_duration s new_.transition_duration;
            if not (Bool.equal old.hhomogeneous new_.hhomogeneous)
            then W.Stack.set_hhomogeneous s new_.hhomogeneous;
            if not (Bool.equal old.vhomogeneous new_.vhomogeneous)
            then W.Stack.set_vhomogeneous s new_.vhomogeneous)
        | _, k -> Widget_impl.wrong_kind "Stack" k)
      (* [visible_child] is controlled, but not from here: [reassert] runs before the
         children are patched, so on the frame that both adds a page and selects it there
         would be nothing to select. The patcher enqueues [select] instead, and the fixup
         pass runs it once the tree is complete. *)
  ; reassert = None
  ; signals = [ visible_child_changed ]
  ; children =
      Widget_impl.List
        { insert =
            (fun parent ~after:_ ~node child ->
              (* GTK has no positional insert for pages; they land in add order, which
                 only affects switcher button order (M1 ruling 4). *)
              let name = page_name node in
              match page_title node with
              | Some title ->
                ignore
                  (W.Stack.add_titled (cast parent) child (Some name) title
                   : W.Stack_page.t)
              | None ->
                ignore
                  (W.Stack.add_named (cast parent) child (Some name) : W.Stack_page.t))
        ; move = (fun _parent ~child:_ ~after:_ -> ())
        ; remove = (fun parent child -> W.Stack.remove (cast parent) child)
        ; updated =
            (fun parent ~old ~node child ->
              (* The title is held by the [GtkStackPage] the stack wrapped around this
                 child, so a changed [Attr.page_title] is written from this side. [""] is
                 GTK's "no title": [set_title] is not nullable. *)
              if not (Option.equal String.equal (page_title old) (page_title node))
              then (
                let page = W.Stack.get_page (cast parent) child in
                W.Stack_page.set_title page (Option.value (page_title node) ~default:"")))
        }
  }
;;
