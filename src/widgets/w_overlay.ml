open! Core
open Bonsai_gtk_vtree
open Gtk_import

(* The overlay holds this about each of its overlay children; it is not a property of the
   child, so it rides on the child node's attrs and is read here (see
   [Attr.measure_overlay]). Default [false] is GTK's own
   ([GtkOverlayLayoutChild:measure]): an overlay child does not grow the overlay unless it
   is asked to. *)
let measure (node : Node.t) =
  match (Attrs.find node.attrs Measure_overlay :> Attr.Private.t option) with
  | Some (Measure_overlay b) -> b
  | Some _ | None -> false
;;

let impl : Widget_impl.t =
  { name = "Overlay"
  ; create =
      (fun (kind : Kind.t) ->
        match kind with
        | Overlay () -> (W.Overlay.new_ () :> Widget.t)
        | k -> Widget_impl.wrong_kind "Overlay" k)
  ; update =
      (fun _w ~(old : Kind.t) (new_ : Kind.t) ->
        match old, new_ with
        | Overlay (), Overlay () -> ()
        | _, k -> Widget_impl.wrong_kind "Overlay" k)
  ; reassert = None
  ; signals = []
  ; children =
      Widget_impl.Slots
        [ "child", Slot_single { set = (fun w c -> W.Overlay.set_child (cast w) c) }
        ; ( "overlays"
          , Slot_list
              { insert =
                  (fun parent ~after:_ ~node child ->
                    (* GTK has no "insert an overlay at a position": overlays stack in the
                       order added, and [after] is unusable. Order among overlays is
                       therefore *not* reconciled -- a reorder in the node list leaves the
                       painting order alone. Keys still preserve identity, which is what
                       matters (and is what [test/live/live_containers.ml] pins); a stack
                       whose paint order must change is a case for separate keys per
                       layer. *)
                    W.Overlay.add_overlay (cast parent) child;
                    W.Overlay.set_measure_overlay (cast parent) child (measure node))
                  (* This container is unordered; see [Widget_impl.list_ops.move]. *)
              ; move = None
              ; remove =
                  (fun parent child -> W.Overlay.remove_overlay (cast parent) child)
              ; updated =
                  (fun parent ~old ~node child ->
                    if not (Bool.equal (measure old) (measure node))
                    then W.Overlay.set_measure_overlay (cast parent) child (measure node))
              } )
        ]
  }
;;
