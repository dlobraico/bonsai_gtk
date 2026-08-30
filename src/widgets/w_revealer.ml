open! Core
open Bonsai_gtk_vtree
open Gtk_import

let transition : Reveal_transition.t -> Gtk_enums.revealertransitiontype = function
  | None_ -> `NONE
  | Crossfade -> `CROSSFADE
  | Slide_right -> `SLIDE_RIGHT
  | Slide_left -> `SLIDE_LEFT
  | Slide_up -> `SLIDE_UP
  | Slide_down -> `SLIDE_DOWN
  | Swing_right -> `SWING_RIGHT
  | Swing_left -> `SWING_LEFT
  | Swing_up -> `SWING_UP
  | Swing_down -> `SWING_DOWN
;;

(* [child-revealed] is read-only and flips when the animation *finishes*, which is the
   useful moment: it is when a hidden subtree can be dropped from the model. *)
let revealed : Signals.spec =
  Read_back
    { attr = Attr.Name.On_revealed
    ; connect = Signals.notify ~prop:"child-revealed"
    ; fire =
        (fun w attr ->
          match (attr :> Attr.Private.t) with
          | On_revealed handler -> Some (handler (W.Revealer.get_child_revealed (cast w)))
          | _ -> None)
    }
;;

(* Against the widget's own [reveal-child], which is the *input* property and so is not
   moved by the animation; [child-revealed] is the outcome and would read as "not yet" for
   the whole of a transition, making every frame write again. *)
let needs_reveal (r : W.Revealer.t) reveal =
  not (Bool.equal (W.Revealer.get_reveal_child r) reveal)
;;

let set_reveal_if_needed (r : W.Revealer.t) reveal =
  if needs_reveal r reveal then W.Revealer.set_reveal_child r reveal
;;

let impl : Widget_impl.t =
  { name = "Revealer"
  ; create =
      (fun (kind : Kind.t) ->
        match kind with
        | Revealer p ->
          let r = W.Revealer.new_ () in
          let w = (r :> Widget.t) in
          Widget_impl.batch w (fun () ->
            (* The transition is set before the reveal, so the first reveal animates the
               way the node asked rather than the way GTK defaults. *)
            W.Revealer.set_transition_type r (transition p.transition);
            W.Revealer.set_transition_duration r p.transition_duration;
            set_reveal_if_needed r p.reveal);
          w
        | k -> Widget_impl.wrong_kind "Revealer" k)
  ; update =
      (fun w ~(old : Kind.t) (new_ : Kind.t) ->
        match old, new_ with
        | Revealer old, Revealer new_ ->
          let r : W.Revealer.t = cast w in
          Widget_impl.batch w (fun () ->
            if not (Reveal_transition.equal old.transition new_.transition)
            then W.Revealer.set_transition_type r (transition new_.transition);
            if old.transition_duration <> new_.transition_duration
            then W.Revealer.set_transition_duration r new_.transition_duration)
          (* [reveal] is deliberately absent: it is controlled, so it belongs to
             [reassert] -- and it is written after the transition props for the reason
             [create] writes them in that order. *)
        | _, k -> Widget_impl.wrong_kind "Revealer" k)
  ; reassert =
      Some
        (fun w (kind : Kind.t) ->
          match kind with
          | Revealer p ->
            let r : W.Revealer.t = cast w in
            let writes = needs_reveal r p.reveal in
            Widget_impl.batch_if writes w (fun () ->
              if writes then W.Revealer.set_reveal_child r p.reveal)
          | k -> Widget_impl.wrong_kind "Revealer" k)
  ; signals = [ revealed ]
  ; children =
      Widget_impl.Single { set = (fun w child -> W.Revealer.set_child (cast w) child) }
  }
;;
