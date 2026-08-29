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

(* The entry family. [text] carries no [@sexp_drop_if]: it is a required labelled
   argument, so it is always something the caller asked for. *)
type entry_props =
  { text : string
  ; placeholder : string option [@sexp_drop_if Option.is_none]
  ; editable : bool [@sexp_drop_if fun b -> b]
  ; visibility : bool [@sexp_drop_if fun b -> b]
  ; width_chars : int [@sexp_drop_if Int.equal (-1)]
  ; max_width_chars : int [@sexp_drop_if Int.equal (-1)]
  ; xalign : float [@sexp_drop_if Float.equal 0.]
  ; activates_default : bool [@sexp_drop_if fun b -> not b]
  }
[@@deriving sexp_of, equal]

type password_entry_props =
  { text : string
  ; placeholder : string option [@sexp_drop_if Option.is_none]
  ; show_peek_icon : bool [@sexp_drop_if fun b -> b]
  ; activates_default : bool [@sexp_drop_if fun b -> not b]
  }
[@@deriving sexp_of, equal]

type search_entry_props =
  { text : string
  ; placeholder : string option [@sexp_drop_if Option.is_none]
  ; search_delay : int option [@sexp_drop_if Option.is_none]
  }
[@@deriving sexp_of, equal]

(* The numeric family. [value], [min] and [max] are required labelled arguments, so like
   the entries' [text] they carry no [@sexp_drop_if]: a range widget with an implicit
   0-100 is a bug generator. [digits] differs per class -- GTK's [GtkSpinButton] shows
   whole numbers and its [GtkScale] one decimal -- so the two defaults differ here too. *)
type spin_button_props =
  { value : float
  ; min : float
  ; max : float
  ; step : float [@sexp_drop_if Float.equal 1.]
  ; digits : int [@sexp_drop_if Int.equal 0]
  ; numeric : bool [@sexp_drop_if fun b -> b]
  ; wrap : bool [@sexp_drop_if fun b -> not b]
  ; activates_default : bool [@sexp_drop_if fun b -> not b]
  }
[@@deriving sexp_of, equal]

type scale_props =
  { orientation : Orientation.t
  ; value : float
  ; min : float
  ; max : float
  ; step : float [@sexp_drop_if Float.equal 1.]
  ; digits : int [@sexp_drop_if Int.equal 1]
  ; draw_value : bool [@sexp_drop_if fun b -> b]
  ; has_origin : bool [@sexp_drop_if fun b -> b]
  ; inverted : bool [@sexp_drop_if fun b -> not b]
  }
[@@deriving sexp_of, equal]

type progress_bar_props =
  { fraction : float
  ; text : string option [@sexp_drop_if Option.is_none]
  ; show_text : bool [@sexp_drop_if fun b -> not b]
  ; inverted : bool [@sexp_drop_if fun b -> not b]
  ; ellipsize : Ellipsize.t option [@sexp_drop_if Option.is_none]
  }
[@@deriving sexp_of, equal]

type spinner_props = { spinning : bool } [@@deriving sexp_of, equal]

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
  | Entry of entry_props
  | Password_entry of password_entry_props
  | Search_entry of search_entry_props
  | Spin_button of spin_button_props
  | Scale of scale_props
  | Progress_bar of progress_bar_props
  | Spinner of spinner_props
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
  | Entry _ -> "Entry"
  | Password_entry _ -> "PasswordEntry"
  | Search_entry _ -> "SearchEntry"
  | Spin_button _ -> "SpinButton"
  | Scale _ -> "Scale"
  | Progress_bar _ -> "ProgressBar"
  | Spinner _ -> "Spinner"
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
  | Entry _, Entry _
  | Password_entry _, Password_entry _
  | Search_entry _, Search_entry _
  | Spin_button _, Spin_button _
  | Scale _, Scale _
  | Progress_bar _, Progress_bar _
  | Spinner _, Spinner _
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
  | Entry a, Entry b -> equal_entry_props a b
  | Password_entry a, Password_entry b -> equal_password_entry_props a b
  | Search_entry a, Search_entry b -> equal_search_entry_props a b
  | Spin_button a, Spin_button b -> equal_spin_button_props a b
  | Scale a, Scale b -> equal_scale_props a b
  | Progress_bar a, Progress_bar b -> equal_progress_bar_props a b
  | Spinner a, Spinner b -> equal_spinner_props a b
  | Box a, Box b -> equal_box_props a b
  | Window a, Window b -> equal_window_props a b
  | Native a, Native b -> String.equal a.name b.name && phys_equal a.payload b.payload
  | _ -> false
;;
