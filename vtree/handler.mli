open! Core

type 'a t = 'a -> unit Ui_effect.t

val sexp_of_t : ('a -> Sexp.t) -> 'a t -> Sexp.t
val equal : 'a t -> 'a t -> bool
