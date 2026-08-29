open! Core

type t =
  | Horizontal
  | Vertical
[@@deriving sexp_of, equal, compare]
