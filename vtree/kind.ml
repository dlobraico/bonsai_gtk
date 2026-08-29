open! Core

(* Every kind's props live in a named record rather than an inline one, so that a widget
   impl can name the type it is handed ([Kind.label_props]) and so that [equal_props] is
   one derived call per kind instead of a hand-written conjunction.

   [@sexp_drop_if] on each field whose value is GTK's own default keeps a printed node
   about what the caller asked for rather than about the defaults: [Node.label "x"] prints
   as [(Label ((text x)))], and a property appears only once it has been set to something.
   It is print-only — [equal_label_props] and friends still compare every field. *)

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

type button_props =
  { label : string option [@sexp_drop_if Option.is_none]
  ; icon_name : string option [@sexp_drop_if Option.is_none]
  ; has_frame : bool [@sexp_drop_if fun b -> b]
  }
[@@deriving sexp_of, equal]

type toggle_button_props =
  { label : string option [@sexp_drop_if Option.is_none]
  ; icon_name : string option [@sexp_drop_if Option.is_none]
  ; has_frame : bool [@sexp_drop_if fun b -> b]
  ; active : bool
  }
[@@deriving sexp_of, equal]

type check_button_props =
  { label : string option [@sexp_drop_if Option.is_none]
  ; active : bool
  ; inconsistent : bool [@sexp_drop_if fun b -> not b]
  }
[@@deriving sexp_of, equal]

type switch_props = { active : bool } [@@deriving sexp_of, equal]

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
  | Toggle_button of toggle_button_props
  | Check_button of check_button_props
  | Switch of switch_props
  | Box of box_props
  | Window of window_props
  | Native of Native.t
[@@deriving sexp_of]

let name = function
  | Label _ -> "Label"
  | Button _ -> "Button"
  | Toggle_button _ -> "ToggleButton"
  | Check_button _ -> "CheckButton"
  | Switch _ -> "Switch"
  | Box _ -> "Box"
  | Window _ -> "Window"
  | Native n -> "Native:" ^ n.name
;;

let same_kind a b =
  match a, b with
  | Label _, Label _
  | Button _, Button _
  | Toggle_button _, Toggle_button _
  | Check_button _, Check_button _
  | Switch _, Switch _
  | Box _, Box _
  | Window _, Window _ -> true
  | Native a, Native b -> String.equal a.name b.name
  | _ -> false
;;

let equal_props a b =
  match a, b with
  | Label a, Label b -> equal_label_props a b
  | Button a, Button b -> equal_button_props a b
  | Toggle_button a, Toggle_button b -> equal_toggle_button_props a b
  | Check_button a, Check_button b -> equal_check_button_props a b
  | Switch a, Switch b -> equal_switch_props a b
  | Box a, Box b -> equal_box_props a b
  | Window a, Window b -> equal_window_props a b
  | Native a, Native b -> String.equal a.name b.name && phys_equal a.payload b.payload
  | _ -> false
;;
