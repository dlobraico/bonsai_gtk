open! Core

(** Every kind's props are a named record so that widget implementations can name the type
    they are handed and so that {!equal_props} is one derived comparison per kind. *)

type label_props =
  { text : string
  ; wrap : bool
  ; xalign : float
  ; ellipsize : Ellipsize.t option
  ; max_width_chars : int
  ; width_chars : int
  ; selectable : bool
  ; use_markup : bool
  }
[@@deriving sexp_of, equal]

type button_props = { label : string option } [@@deriving sexp_of, equal]

type box_props =
  { orientation : Orientation.t
  ; spacing : int
  ; homogeneous : bool
  }
[@@deriving sexp_of, equal]

type window_props =
  { title : string option
  ; default_size : (int * int) option
  }
[@@deriving sexp_of, equal]

type t =
  | Label of label_props
  | Button of button_props
  | Box of box_props
  | Window of window_props
  | Native of Native.t
[@@deriving sexp_of]

(** Same constructor (and, for [Native], same [name]). Props ignored. *)
val same_kind : t -> t -> bool

val name : t -> string

(** Structural on props; [Native] payloads compare physically. *)
val equal_props : t -> t -> bool
