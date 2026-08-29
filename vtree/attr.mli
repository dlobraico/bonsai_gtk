open! Core

module Name : sig
  type t =
    | Margin_start
    | Margin_end
    | Margin_top
    | Margin_bottom
    | Halign
    | Valign
    | Hexpand
    | Vexpand
    | Sensitive
    | Visible
    | Tooltip
    | Width_request
    | Height_request
    | Test_id
    | On_clicked
  [@@deriving sexp_of, compare, equal]

  include Comparable.S_plain with type t := t
end

type t =
  | Css_class of string
  | Margin_start of int
  | Margin_end of int
  | Margin_top of int
  | Margin_bottom of int
  | Halign of Align.t
  | Valign of Align.t
  | Hexpand of bool
  | Vexpand of bool
  | Sensitive of bool
  | Visible of bool
  | Tooltip of string
  | Width_request of int
  | Height_request of int
  | Test_id of string
  | On_clicked of unit Handler.t
  | Many of t list
[@@deriving sexp_of]

(** [None] for [Css_class] (accumulates, not keyed) and [Many]. *)
val name : t -> Name.t option

(** Structural, except handlers compare physically. *)
val equal : t -> t -> bool

val css_class : string -> t
val margin_start : int -> t
val margin_end : int -> t
val margin_top : int -> t
val margin_bottom : int -> t

(** all four sides *)
val margin : int -> t

val halign : Align.t -> t
val valign : Align.t -> t
val hexpand : bool -> t
val vexpand : bool -> t
val sensitive : bool -> t
val visible : bool -> t
val tooltip : string -> t
val width_request : int -> t
val height_request : int -> t
val test_id : string -> t
val on_clicked : unit Ui_effect.t -> t
val many : t list -> t
val empty : t
