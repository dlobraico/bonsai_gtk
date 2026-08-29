open! Core

type t = string [@@deriving sexp_of, compare, equal, hash]

include Comparable.S_plain with type t := t
