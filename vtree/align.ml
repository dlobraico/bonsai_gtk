open! Core

type t =
  | Fill
  | Start
  | End
  | Center
  | Baseline
[@@deriving sexp_of, equal, compare]
