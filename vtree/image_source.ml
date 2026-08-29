open! Core

(** Where a [Node.image] gets its picture. The alternatives are a closed variant rather
    than four optional arguments because GTK's setters do not compose -- setting a file
    after an icon name silently wins, and nothing tells you which one is live. *)
type t =
  | Empty
  | Icon_name of string
  | File of string
  | Resource of string
[@@deriving sexp_of, equal, compare]
