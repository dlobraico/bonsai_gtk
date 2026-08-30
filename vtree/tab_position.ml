open! Core

(** Which edge of a {!Node.notebook} its tabs are drawn on.

    GTK's own [GtkPositionType], which several other widgets also take; it is named for
    the notebook because the notebook is the only thing in this library that reads one,
    and a name that says what it is for is worth more than a name that says which C enum
    it came from. A second reader would generalise it. *)
type t =
  | Top
  | Bottom
  | Left
  | Right
[@@deriving sexp_of, equal, compare]
