open! Core

module T = struct
  type t = string [@@deriving sexp_of, compare, equal, hash]
end

include T
include Comparable.Make_plain (T)
