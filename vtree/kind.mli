open! Core

(** Every kind's props are a named record so that widget implementations can name the type
    they are handed and so that {!equal_props} is one derived comparison per kind.

    A field whose value is GTK's own default is dropped from the sexp, so a printed node
    shows what the caller asked for rather than the defaults. That is print-only:
    {!equal_props} still compares every field. *)

type label_props =
  { text : string
  ; wrap : bool [@sexp_drop_if fun b -> not b]
  ; xalign : float [@sexp_drop_if Float.equal 0.5]
  ; ellipsize : Ellipsize.t option [@sexp_drop_if Option.is_none]
  ; max_width_chars : int [@sexp_drop_if Int.equal (-1)]
  ; width_chars : int [@sexp_drop_if Int.equal (-1)]
  ; selectable : bool [@sexp_drop_if fun b -> not b]
  ; use_markup : bool [@sexp_drop_if fun b -> not b]
  }
[@@deriving sexp_of, equal]

type button_props = { label : string option [@sexp_drop_if Option.is_none] }
[@@deriving sexp_of, equal]

type box_props =
  { orientation : Orientation.t
  ; spacing : int [@sexp_drop_if Int.equal 0]
  ; homogeneous : bool [@sexp_drop_if fun b -> not b]
  }
[@@deriving sexp_of, equal]

type window_props =
  { title : string option [@sexp_drop_if Option.is_none]
  ; default_size : (int * int) option [@sexp_drop_if Option.is_none]
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
