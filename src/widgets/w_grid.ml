open! Core
open Bonsai_gtk_vtree
open Gtk_import

(* A grid child's coordinates are an argument to a call on the *grid*, not a property of
   the child, so they ride on the child node's attrs and are read here (spec §7). There is
   no default: a grid child with no cell would stack at (0,0) with every other one, which
   looks like a layout bug rather than the missing attribute it is.

   The message carries no path -- the ops know nothing about where in the tree they are --
   so the patcher's list helpers prefix one (spec §11). *)
let cell (node : Node.t) =
  match (Attrs.find node.attrs Grid_cell :> Attr.Private.t option) with
  | Some (Grid_cell c) -> c
  | Some _ | None ->
    invalid_arg "Grid child has no Attr.grid_cell (every child of a Node.grid needs one)"
;;

let attach parent (node : Node.t) child =
  let c = cell node in
  W.Grid.attach (cast parent) child c.column c.row c.width c.height
;;

let impl : Widget_impl.t =
  { name = "Grid"
  ; create =
      (fun (kind : Kind.t) ->
        match kind with
        | Grid p ->
          let g = W.Grid.new_ () in
          let w = (g :> Widget.t) in
          Widget_impl.batch w (fun () ->
            W.Grid.set_row_spacing g p.row_spacing;
            W.Grid.set_column_spacing g p.column_spacing;
            W.Grid.set_row_homogeneous g p.row_homogeneous;
            W.Grid.set_column_homogeneous g p.column_homogeneous);
          w
        | k -> Widget_impl.wrong_kind "Grid" k)
  ; update =
      (fun w ~(old : Kind.t) (new_ : Kind.t) ->
        match old, new_ with
        | Grid old, Grid new_ ->
          let g : W.Grid.t = cast w in
          Widget_impl.batch w (fun () ->
            if old.row_spacing <> new_.row_spacing
            then W.Grid.set_row_spacing g new_.row_spacing;
            if old.column_spacing <> new_.column_spacing
            then W.Grid.set_column_spacing g new_.column_spacing;
            if not (Bool.equal old.row_homogeneous new_.row_homogeneous)
            then W.Grid.set_row_homogeneous g new_.row_homogeneous;
            if not (Bool.equal old.column_homogeneous new_.column_homogeneous)
            then W.Grid.set_column_homogeneous g new_.column_homogeneous)
        | _, k -> Widget_impl.wrong_kind "Grid" k)
  ; reassert = None
  ; signals = []
  ; children =
      Widget_impl.List
        { insert = (fun parent ~after:_ ~node child -> attach parent node child)
        ; (* Order in the node list means nothing to a grid -- the cell is the placement
             -- so a reorder that keeps the cells must not touch GTK (M1 ruling 4). *)
          move = (fun _parent ~child:_ ~after:_ -> ())
        ; remove = (fun parent child -> W.Grid.remove (cast parent) child)
        ; updated =
            (fun parent ~old ~node child ->
              (* GTK has no "move an attached child": a coordinate change is a detach and
                 a re-attach of the same widget (spec §7). The widget survives, so its
                 entry text and every other piece of its own state does. Its rooting does
                 not: [gtk_grid_remove] is [gtk_widget_unparent], so between these two
                 calls the child's whole subtree is unrooted and re-rooted, which is the
                 lifecycle everything keyed on the toplevel hangs off — the window's focus
                 widget among them. A form that widens a row while the user is filling in
                 the field on it (a validation message appearing beside it) is the shape
                 that would notice.

                 GTK 4.22 turns out to leave [gtk_root_get_focus] alone across the pair —
                 [test/live/live_containers.ml] pins that — so the save and restore below
                 is insurance rather than a repair: it is three getters on a path that
                 only runs when a cell actually changed, and it does not depend on an
                 unroot leaving the toplevel's focus untouched, which is not something GTK
                 promises. Only a focus that was *inside* the moved child is restored;
                 focus elsewhere in the window has nothing to do with this unparenting and
                 must not be dragged here. *)
              if not (Grid_cell.equal (cell old) (cell node))
              then (
                let root = Widget.get_root child in
                let refocus =
                  Option.bind root ~f:(fun root ->
                    Option.filter (W.Root.get_focus root) ~f:(fun focused ->
                      Gobject.same focused child || Widget.is_ancestor focused child))
                in
                W.Grid.remove (cast parent) child;
                attach parent node child;
                Option.iter (Option.both root refocus) ~f:(fun (root, focused) ->
                  W.Root.set_focus root (Some focused))))
        }
  }
;;
