open! Core
open Bonsai_gtk_vtree
open Gtk_import

let position : Position.t -> Gtk_enums.positiontype = function
  | Top -> `TOP
  | Bottom -> `BOTTOM
  | Left -> `LEFT
  | Right -> `RIGHT
;;

(* The controlled [~open_] (spec §6.5), applied from the fixup queue rather than
   [reassert] -- [popup] needs the popover parented into its menu button, which has not
   happened yet when [create] runs during the mount walk, and the fixups run on the mount,
   patch {i and} reassert-only passes, which is exactly a controlled prop's coverage.
   Compared against the widget's own visibility (the readable open bit), so the frame that
   declines a user's dismissal -- same node, nothing diffed -- is the frame this pops it
   back up.

   The [popdown] this makes runs inside the patch guard, and the [closed] it provokes is
   emitted {i synchronously inside} [popdown] (measured; pre-flight correction 8), so the
   guard is what keeps the library's own closes out of [Attr.on_closed]. *)
let apply_open (w : Widget.t) ~open_ =
  let p : W.Popover.t = cast w in
  if not (Bool.equal open_ (Widget.get_visible w))
  then if open_ then W.Popover.popup p else W.Popover.popdown p
;;

(* [closed] carries nothing and reads nothing back: the popover that closed is the node
   the attr rides on. Two connections on the one signal, deliberately: the first is the
   spec's trampoline (slot-armed, guarded, [in_patch]-dropped), and the second is
   [W_menu_button.repair_focus_after_popdown] -- the GTK focus bug repair, which must run
   on {i every} close, the library's own popdowns included, so it cannot live inside the
   trampoline the guard silences. Both name the popover, so [Patcher.destroy] disconnects
   both before the popover can be collected. *)
let closed : Signals.spec =
  Read_back
    { attr = Attr.Name.On_closed
    ; connect =
        (fun w ~callback ->
          let p : W.Popover.t = cast w in
          [ Signals.connected p (W.Popover.on_closed p ~callback)
          ; Signals.connected
              p
              (W.Popover.on_closed p ~callback:(fun () ->
                 W_menu_button.repair_focus_after_popdown w))
          ])
    ; fire =
        (fun _w attr ->
          match (attr :> Attr.Private.t) with
          | On_closed handler -> Some (handler ())
          | _ -> None)
    }
;;

let impl : Widget_impl.t =
  { name = "Popover"
  ; create =
      (fun (kind : Kind.t) ->
        match kind with
        | Popover p ->
          let po = W.Popover.new_ () in
          let w = (po :> Widget.t) in
          Widget_impl.batch w (fun () ->
            (match p.position with
             | Bottom -> ()
             | pos -> W.Popover.set_position po (position pos));
            if not p.autohide then W.Popover.set_autohide po false;
            if not p.has_arrow then W.Popover.set_has_arrow po false);
          (* [open_] is deliberately not applied here: the popover has no parent yet, and
             [popup] on an unparented popover is a GTK critical. The fixup queue applies
             it once the menu button's slot has parented this (see [apply_open]). *)
          w
        | k -> Widget_impl.wrong_kind "Popover" k)
  ; update =
      (fun w ~(old : Kind.t) (new_ : Kind.t) ->
        match old, new_ with
        | Popover old, Popover new_ ->
          let po : W.Popover.t = cast w in
          Widget_impl.batch w (fun () ->
            if not (Position.equal old.position new_.position)
            then W.Popover.set_position po (position new_.position);
            if not (Bool.equal old.autohide new_.autohide)
            then W.Popover.set_autohide po new_.autohide;
            if not (Bool.equal old.has_arrow new_.has_arrow)
            then W.Popover.set_has_arrow po new_.has_arrow)
          (* [open_] is absent on purpose: controlled, so it is the fixup queue's on every
             pass, never a diffed write. *)
        | _, k -> Widget_impl.wrong_kind "Popover" k)
  ; reassert = None
  ; signals = [ closed ]
  ; children = Widget_impl.Single { set = (fun w c -> W.Popover.set_child (cast w) c) }
  }
;;
