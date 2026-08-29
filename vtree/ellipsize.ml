open! Core

(** Where a [GtkLabel]/[GtkProgressBar] drops characters when its text does not fit. There
    is deliberately no "none" constructor: the absence of ellipsization is
    [None : t option], which keeps the constructor list from shadowing [Option.None] in
    every match. *)
type t =
  | Start
  | Middle
  | End
[@@deriving sexp_of, equal, compare]
