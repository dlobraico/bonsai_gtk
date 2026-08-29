open! Core

type 'a t = 'a -> unit Ui_effect.t

let sexp_of_t _ _ = Sexp.Atom "<handler>"
let equal = phys_equal
