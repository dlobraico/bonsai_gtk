open! Core

(** Which side of its parent a {!Node.popover} points from — GTK's [GtkPositionType],
    minus nothing: all four sides are real. GTK may flip the popover to the opposite side
    when there is no room; the prop is the {i preference}. *)
type t =
  | Top
  | Bottom
  | Left
  | Right
[@@deriving sexp_of, equal, compare]
