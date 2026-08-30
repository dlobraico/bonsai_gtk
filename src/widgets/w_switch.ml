open! Core
open Bonsai_gtk_vtree
open Gtk_import

(* [state-set] is the signal that looks right and is not: its callback returns a [bool]
   meaning "handled", and returning [true] suppresses GTK's own update of [state], which
   leaves it out of step with [active] — the "pending" look a switch wears while an
   asynchronous confirmation is outstanding. bonsai_gtk has no such step, so it never
   connects [state-set] and reports changes through [notify::active] instead.

   ocgtk exposes no [on_notify_active], so this goes through the generic marshaller by
   detailed name, which carries no payload — hence the getter in [fire] (spec §6.4). *)
let toggled : Signals.spec =
  { attr = Attr.Name.On_toggled
  ; connect = Signals.notify ~prop:"active"
  ; fire =
      (fun w (attr : Attr.Private.t) ->
        match attr with
        | On_toggled handler -> Some (handler (W.Switch.get_active (cast w)))
        | _ -> None)
  }
;;

(* [active] is what the user asked for, [state] what the app has actually done about it.
   With no asynchronous confirmation step the two are always equal, and writing both keeps
   the switch from rendering its pending look. *)
let set_both (s : W.Switch.t) active =
  W.Switch.set_active s active;
  W.Switch.set_state s active
;;

(* Controlled, on the same rule (and for the same reason) as [w_toggle_button.ml]'s. *)
let set_active_if_needed (s : W.Switch.t) active =
  if not (Bool.equal (W.Switch.get_active s) active) then set_both s active
;;

let impl : Widget_impl.t =
  { name = "Switch"
  ; create =
      (fun (kind : Kind.t) ->
        match kind with
        | Switch { active } ->
          let s = W.Switch.new_ () in
          if active then Widget_impl.batch (s :> Widget.t) (fun () -> set_both s true);
          (s :> Widget.t)
        | k -> Widget_impl.wrong_kind "Switch" k)
  ; update =
      (* [active] is the only prop a switch has, and it is controlled — so every write
         this kind ever makes belongs to [reassert], and there is nothing left to diff
         here. *)
      (fun _w ~old:(_ : Kind.t) (new_ : Kind.t) ->
        match new_ with
        | Switch _ -> ()
        | k -> Widget_impl.wrong_kind "Switch" k)
  ; reassert =
      Some
        (fun w (kind : Kind.t) ->
          match kind with
          | Switch { active } ->
            Widget_impl.batch w (fun () -> set_active_if_needed (cast w) active)
          | k -> Widget_impl.wrong_kind "Switch" k)
  ; signals = [ toggled ]
  ; children = Widget_impl.No_children
  }
;;
