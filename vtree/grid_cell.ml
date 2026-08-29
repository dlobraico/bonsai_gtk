open! Core

(** Where a child sits in a [Node.grid], and how many cells it covers. Columns and rows
    are zero-based and may be sparse -- a grid is not a table, and nothing has to fill row
    1 for something to sit in row 2. *)
type t =
  { column : int
  ; row : int
  ; width : int
  ; height : int
  }
[@@deriving sexp_of, equal, compare]
