open! Core

type payload = ..
type payload += Unit

type t =
  { name : string
  ; payload : payload
  }

let sexp_of_t t = [%sexp `native (t.name : string)]
