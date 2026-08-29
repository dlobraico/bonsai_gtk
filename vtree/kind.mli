open! Core

type t =
  | Label of { text : string }
  | Button of { label : string option }
  | Box of
      { orientation : Orientation.t
      ; spacing : int
      ; homogeneous : bool
      }
  | Window of
      { title : string option
      ; default_size : (int * int) option
      }
  | Native of Native.t
[@@deriving sexp_of]

(** Same constructor (and, for [Native], same [name]). Props ignored. *)
val same_kind : t -> t -> bool

val name : t -> string

(** Structural on props; [Native] payloads compare physically. *)
val equal_props : t -> t -> bool
