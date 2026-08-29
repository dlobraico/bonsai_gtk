open! Core
open Bonsai_gtk_vtree
open Gtk_import

let orientation : Orientation.t -> Gtk_enums.orientation = function
  | Horizontal -> `HORIZONTAL
  | Vertical -> `VERTICAL
;;

let impl : Widget_impl.t =
  { name = "Box"
  ; create =
      (fun (kind : Kind.t) ->
        match kind with
        | Box { orientation = o; spacing; homogeneous } ->
          let box = W.Box.new_ (orientation o) spacing in
          W.Box.set_homogeneous box homogeneous;
          (box :> Widget.t)
        | k -> Widget_impl.wrong_kind "Box" k)
  ; update =
      (fun w ~(old : Kind.t) (new_ : Kind.t) ->
        match old, new_ with
        | Box old, Box new_ ->
          let box = cast w in
          if not (Orientation.equal old.orientation new_.orientation)
          then
            W.Orientable.set_orientation
              (W.Orientable.from_gobject w)
              (orientation new_.orientation);
          if old.spacing <> new_.spacing then W.Box.set_spacing box new_.spacing;
          if not (Bool.equal old.homogeneous new_.homogeneous)
          then W.Box.set_homogeneous box new_.homogeneous
        | _, k -> Widget_impl.wrong_kind "Box" k)
  ; signals = []
  ; children =
      Widget_impl.List
        { insert =
            (fun parent ~index child ->
              W.Box.insert_child_after
                (cast parent)
                child
                (Widget_impl.sibling_before parent ~index ~except:None))
        ; move =
            (fun parent ~child ~to_ ->
              (* [to_] is the index the child must occupy *after* the move, and the child
                 is still in the list at its old position, so the sibling is computed over
                 the other children only. *)
              W.Box.reorder_child_after
                (cast parent)
                child
                (Widget_impl.sibling_before parent ~index:to_ ~except:(Some child)))
        ; remove = (fun parent child -> W.Box.remove (cast parent) child)
        }
  }
;;
