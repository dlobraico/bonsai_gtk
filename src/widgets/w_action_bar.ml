open! Core
open Bonsai_gtk_vtree
open Gtk_import

(* Pure structure, [w_header_bar.ml]'s shape over the bottom strip: no signals, three
   slots, one plain prop. [revealed] is deliberately not controlled -- the user cannot
   move it, so there is nothing for a [reassert] to put back -- and GTK's own caveat
   stands: revealing is not visibility, so a bar carrying [Attr.visible false] stays
   hidden however [revealed] is set. The pack areas are the header bar's in every respect
   ([move = None], one slot-agnostic [remove], insertion order kept). *)
let impl : Widget_impl.t =
  { name = "ActionBar"
  ; create =
      (fun (kind : Kind.t) ->
        match kind with
        | Action_bar p ->
          let ab = W.Action_bar.new_ () in
          if not p.revealed then W.Action_bar.set_revealed ab false;
          (ab :> Widget.t)
        | k -> Widget_impl.wrong_kind "ActionBar" k)
  ; update =
      (fun w ~(old : Kind.t) (new_ : Kind.t) ->
        match old, new_ with
        | Action_bar old, Action_bar new_ ->
          if not (Bool.equal old.revealed new_.revealed)
          then W.Action_bar.set_revealed (cast w) new_.revealed
        | _, k -> Widget_impl.wrong_kind "ActionBar" k)
  ; reassert = None
  ; signals = []
  ; children =
      Widget_impl.Slots
        [ ( "center"
          , Slot_single { set = (fun w c -> W.Action_bar.set_center_widget (cast w) c) } )
        ; ( "start"
          , Slot_list
              { insert =
                  (fun parent ~after:_ ~node:_ child ->
                    W.Action_bar.pack_start (cast parent) child)
              ; move = None
              ; remove = (fun parent child -> W.Action_bar.remove (cast parent) child)
              ; updated = (fun _parent ~old:_ ~node:_ _child -> ())
              } )
        ; ( "end"
          , Slot_list
              { insert =
                  (fun parent ~after:_ ~node:_ child ->
                    W.Action_bar.pack_end (cast parent) child)
              ; move = None
              ; remove = (fun parent child -> W.Action_bar.remove (cast parent) child)
              ; updated = (fun _parent ~old:_ ~node:_ _child -> ())
              } )
        ]
  }
;;
