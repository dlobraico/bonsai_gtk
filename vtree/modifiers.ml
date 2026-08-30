open! Core

type t =
  { shift : bool
  ; control : bool
  ; alt : bool
  ; super : bool
  ; hyper : bool
  ; meta : bool
  }
[@@deriving sexp_of, equal, compare]

let none =
  { shift = false
  ; control = false
  ; alt = false
  ; super = false
  ; hyper = false
  ; meta = false
  }
;;
