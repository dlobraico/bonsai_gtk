open! Core

(* Every kind's props live in a named record rather than an inline one, so that a widget
   impl can name the type it is handed ([Kind.label_props]) and so that [equal_props] is
   one derived call per kind instead of a hand-written conjunction. *)

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

let name = function
  | Label _ -> "Label"
  | Button _ -> "Button"
  | Box _ -> "Box"
  | Window _ -> "Window"
  | Native n -> "Native:" ^ n.name
;;

let same_kind a b =
  match a, b with
  | Label _, Label _ | Button _, Button _ | Box _, Box _ | Window _, Window _ -> true
  | Native a, Native b -> String.equal a.name b.name
  | _ -> false
;;

let equal_props a b =
  match a, b with
  | Label a, Label b -> equal_label_props a b
  | Button a, Button b -> equal_button_props a b
  | Box a, Box b -> equal_box_props a b
  | Window a, Window b -> equal_window_props a b
  | Native a, Native b -> String.equal a.name b.name && phys_equal a.payload b.payload
  | _ -> false
;;
