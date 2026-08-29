open! Core

(** The size a [Node.image] asks the icon theme for. [Inherit] takes the size from the
    surrounding context, which is GTK's own default; an explicit [pixel_size] overrides
    this entirely. *)
type t =
  | Inherit
  | Normal
  | Large
[@@deriving sexp_of, equal, compare]
