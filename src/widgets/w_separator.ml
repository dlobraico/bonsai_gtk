open! Core
open Bonsai_gtk_vtree
open Gtk_import

let orientation : Orientation.t -> Gtk_enums.orientation = function
  | Horizontal -> `HORIZONTAL
  | Vertical -> `VERTICAL
;;

(* [gtk_separator_new] takes the orientation and there is no [GtkSeparator] setter for it,
   so a change goes through [GtkOrientable], which every separator implements. *)
let impl : Widget_impl.t =
  { name = "Separator"
  ; create =
      (fun (kind : Kind.t) ->
        match kind with
        | Separator { orientation = o } -> (W.Separator.new_ (orientation o) :> Widget.t)
        | k -> Widget_impl.wrong_kind "Separator" k)
  ; update =
      (fun w ~(old : Kind.t) (new_ : Kind.t) ->
        match old, new_ with
        | Separator old, Separator new_ ->
          if not (Orientation.equal old.orientation new_.orientation)
          then
            W.Orientable.set_orientation
              (W.Orientable.from_gobject w)
              (orientation new_.orientation)
        | _, k -> Widget_impl.wrong_kind "Separator" k)
  ; reassert = None
  ; signals = []
  ; children = Widget_impl.No_children
  }
;;
