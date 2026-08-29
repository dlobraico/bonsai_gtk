open! Core
open Bonsai_gtk_vtree
open Gtk_import

(* Three named slots, each a [Single]: the patcher drives them with exactly the code it
   uses for a single-child container, one slot at a time, so emptying [center] cannot
   disturb [start] or [end]. *)
let impl : Widget_impl.t =
  { name = "CenterBox"
  ; create =
      (fun (kind : Kind.t) ->
        match kind with
        | Center_box p ->
          let b = W.Center_box.new_ () in
          if not p.shrink_center_last then W.Center_box.set_shrink_center_last b false;
          (b :> Widget.t)
        | k -> Widget_impl.wrong_kind "CenterBox" k)
  ; update =
      (fun w ~(old : Kind.t) (new_ : Kind.t) ->
        match old, new_ with
        | Center_box old, Center_box new_ ->
          if not (Bool.equal old.shrink_center_last new_.shrink_center_last)
          then W.Center_box.set_shrink_center_last (cast w) new_.shrink_center_last
        | _, k -> Widget_impl.wrong_kind "CenterBox" k)
  ; reassert = None
  ; signals = []
  ; children =
      Widget_impl.Slots
        [ ( "start"
          , Slot_single { set = (fun w c -> W.Center_box.set_start_widget (cast w) c) } )
        ; ( "center"
          , Slot_single { set = (fun w c -> W.Center_box.set_center_widget (cast w) c) } )
        ; "end", Slot_single { set = (fun w c -> W.Center_box.set_end_widget (cast w) c) }
        ]
  }
;;
