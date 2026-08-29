open! Core

type t [@@deriving sexp_of]

type op =
  | Set of Attr.t
  | Unset of Attr.Name.t
  | Add_css_class of string
  | Remove_css_class of string
[@@deriving sexp_of]

val empty : t
val of_list : Attr.t list -> t
val find : t -> Attr.Name.t -> Attr.t option
val css_classes : t -> string list
val test_id : t -> string option
val to_list : t -> Attr.t list

(** Ops to turn a widget carrying [old] into one carrying [new_]. Order: css removals, css
    additions, then keyed attrs in [Attr.Name] order (Set for changed/new, Unset for
    gone). *)
val diff : old:t -> new_:t -> op list
