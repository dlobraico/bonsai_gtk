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

(* Every page name this stack currently holds, in GTK's own order. Only for the message
   below: listing them is what turns "no such page" from an accusation into a fix, and a
   [GtkStack]'s pages are reached through its children rather than through a name list.
   [get_page] is the wrapper the stack put around each child; the page's name is the key
   the child node carried. *)
let page_names (s : W.Stack.t) =
  let rec walk acc child =
    match child with
    | None -> List.rev acc
    | Some c ->
      let name = W.Stack_page.get_name (W.Stack.get_page s c) in
      walk (Option.value name ~default:"<unnamed>" :: acc) (Widget.get_next_sibling c)
  in
  walk [] (Widget.get_first_child (s :> Widget.t))
;;

(* Applied as a post-pass fixup rather than in [create], [update] or [reassert]: the pages
   exist only after the children have been patched, and all three of those run before
   them.

   It is still the controlled discipline of spec §6.5 -- compared against what the widget
   is actually showing rather than against the previous node -- which is what puts the
   selection back after a user clicked a switcher button the model then ignored.

   A name no page carries is [Invalid_argument], and the fixup pass is the only place that
   can say so. [create], [update] and [reassert] all run while the stack is still being
   built, so "not yet" and "never" are indistinguishable there -- which is why this used
   to be silently inert, and why a typo in a [~visible_child] showed up as a stack stuck
   on whatever page GTK picked. By the time the fixups run the whole tree exists, so every
   page this frame renders is already added and an absent name is absent from the rendered
   tree. The patcher prefixes the stack's node path. *)
let select (w : Widget.t) ~visible_child =
  let s : W.Stack.t = cast w in
  match W.Stack.get_child_by_name s visible_child with
  | None ->
    (match page_names s with
     (* A stack with no pages at all is the one frame on which an absent name is not a
        mistake: [~visible_child] is a required argument, so a model rendering an empty
        page list has no name it could pass that would be right. Left inert, exactly as
        every absent name used to be -- the frame that adds the first page runs this
        again. With even one page present the argument is a claim about that set, and a
        name outside it is a typo. *)
     | [] -> ()
     | names ->
       invalid_argf
         "Node.stack ~visible_child:%S names no page (a page's name is its ~key; this \
          stack has %s)"
         visible_child
         (String.concat ~sep:", " names)
         ())
  | Some _ ->
    if not
         (Option.equal
            String.equal
            (W.Stack.get_visible_child_name s)
            (Some visible_child))
    then W.Stack.set_visible_child_name s visible_child
;;

(* ocgtk generates no [on_notify_visible_child_name]; the detailed name goes through the
   generic marshaller (spec §6.4). *)
let visible_child_changed : Signals.spec =
  Read_back
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
            (* This container is unordered: GTK has no reorder primitive for stack pages,
               so the reconciler is told not to emit [Move] at all. See
               [Widget_impl.list_ops.move]. Page order is only switcher button order (M1
               ruling 4). *)
        ; move = None
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
