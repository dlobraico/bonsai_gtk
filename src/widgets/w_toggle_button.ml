open! Core
open Bonsai_gtk_vtree
open Gtk_import

let toggled : Signals.spec =
  { attr = Attr.Name.On_toggled
  ; connect =
      (fun w ~callback ->
        Signals.connected w (W.Toggle_button.on_toggled (cast w) ~callback))
  ; fire =
      (fun w (attr : Attr.Private.t) ->
        match attr with
        | On_toggled handler -> Some (handler (W.Toggle_button.get_active (cast w)))
        | _ -> None)
  }
;;

(* Controlled (spec §6.5): compare against what the widget currently shows, not against
   the previous node's [active]. The user may have flipped it since the last render, and a
   model that chose not to follow must pin the widget back rather than skip the write --
   which is why this is [reassert] rather than part of [update]. The patcher skips
   [update] entirely on the patch where the model declined, that being precisely the patch
   where the props did not move. *)
let set_active_if_needed (b : W.Toggle_button.t) active =
  if not (Bool.equal (W.Toggle_button.get_active b) active)
  then W.Toggle_button.set_active b active
;;

let impl : Widget_impl.t =
  { name = "ToggleButton"
  ; create =
      (fun (kind : Kind.t) ->
        match kind with
        | Toggle_button p ->
          (* [GtkToggleButton] has [new_with_label] but no [new_from_icon_name], so both
             props go through the shared setter path rather than the constructor. *)
          let b = W.Toggle_button.new_ () in
          Widget_impl.batch
            (b :> Widget.t)
            (fun () ->
              W_button.apply_button_props
                (cast b)
                ~old:None
                ~label:p.label
                ~icon_name:p.icon_name
                ~has_frame:p.has_frame;
              set_active_if_needed b p.active);
          (b :> Widget.t)
        | k -> Widget_impl.wrong_kind "ToggleButton" k)
  ; update =
      (fun w ~(old : Kind.t) (new_ : Kind.t) ->
        match old, new_ with
        | Toggle_button old, Toggle_button new_ ->
          Widget_impl.batch w (fun () ->
            W_button.apply_button_props
              (cast w)
              ~old:(Some (old.label, old.icon_name, old.has_frame))
              ~label:new_.label
              ~icon_name:new_.icon_name
              ~has_frame:new_.has_frame)
          (* [active] is deliberately absent: it is controlled, so it belongs to
             [reassert]. *)
        | _, k -> Widget_impl.wrong_kind "ToggleButton" k)
  ; reassert =
      Some
        (fun w (kind : Kind.t) ->
          match kind with
          | Toggle_button p ->
            Widget_impl.batch w (fun () -> set_active_if_needed (cast w) p.active)
          | k -> Widget_impl.wrong_kind "ToggleButton" k)
  ; signals =
      [ toggled ]
      (* Shared with [w_button.ml]: a [GtkToggleButton] is a [GtkButton], down to the one
         slot its label, its icon and its child all compete for. *)
  ; children = Widget_impl.Single { set = W_button.set_child_slot }
  }
;;
