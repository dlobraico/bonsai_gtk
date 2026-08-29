open! Core

type payload = ..
type payload += Unit (** placeholder payload, used by tests *)

type t =
  { name : string
  ; payload : payload
  }

val sexp_of_t : t -> Sexp.t
