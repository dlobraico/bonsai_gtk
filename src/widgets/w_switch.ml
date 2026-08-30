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
  Read_back
    { attr = Attr.Name.On_toggled
    ; connect = Signals.notify ~prop:"active"
    ; fire =
        (fun w attr ->
          match (attr :> Attr.Private.t) with
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

(* Controlled, on the same rule (and for the same reason) as [w_toggle_button.ml]'s. The
   comparison is separate from the write because [reassert] has to make it *before* it
   decides whether to bracket: see [Widget_impl.batch_if]. *)
let needs_active (s : W.Switch.t) active = not (Bool.equal (W.Switch.get_active s) active)

let reassert w (kind : Kind.t) =
  match kind with
  | Switch { active } ->
    let s : W.Switch.t = cast w in
    let writes = needs_active s active in
    Widget_impl.batch_if writes w (fun () -> if writes then set_both s active)
  | k -> Widget_impl.wrong_kind "Switch" k
;;

let impl : Widget_impl.t =
  { name = "Switch"
  ; create =
      (fun (kind : Kind.t) ->
        match kind with
        | Switch _ ->
          let s = W.Switch.new_ () in
          let w = (s :> Widget.t) in
          (* Through [reassert] rather than a second [set_active] of its own, so the one
             controlled prop this kind has has exactly one implementation. Two
             consequences worth being explicit about. A switch whose node says
             [~active:true] is created inactive and then written, which is one extra
             property write on the create path -- the same write the next patch would have
             made anyway. And that write emits [notify::active] for real, because [create]
             runs *before* [Patcher.mount]'s [connect_all]: there is not merely an empty
             slot at that point, there is no connection at all, so nothing can hear it. *)
          reassert w kind;
          w
        | k -> Widget_impl.wrong_kind "Switch" k)
  ; update =
      (* [active] is the only prop a switch has, and it is controlled — so every write
         this kind ever makes belongs to [reassert], and there is nothing left to diff
         here. *)
      (fun _w ~old:(_ : Kind.t) (new_ : Kind.t) ->
        match new_ with
        | Switch _ -> ()
        | k -> Widget_impl.wrong_kind "Switch" k)
  ; reassert = Some reassert
  ; signals = [ toggled ]
  ; children = Widget_impl.No_children
  }
;;
