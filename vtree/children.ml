open! Core

type 'a t =
  | No_children
  | Single of 'a option
  | List of 'a list
[@@deriving sexp_of]
