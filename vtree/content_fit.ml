open! Core

(** How a [Node.picture] scales its image into the space it is given. [Contain]
    letterboxes, [Cover] crops, [Fill] stretches, [Scale_down] shrinks but never enlarges.
    Paired with [can_shrink], which is what lets the widget be {i smaller} than its image
    at all. *)
type t =
  | Fill
  | Contain
  | Cover
  | Scale_down
[@@deriving sexp_of, equal, compare]
