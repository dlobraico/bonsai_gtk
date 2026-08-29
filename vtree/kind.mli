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

(* [Image] and [Picture] carry their source as a closed variant rather than as separate
   optional props: the sources are mutually exclusive and GTK's setters do not compose, so
   a variant makes the exclusivity a type error and gives [equal_props] one line. *)
type image_props =
  { source : Image_source.t
  ; pixel_size : int [@sexp_drop_if Int.equal (-1)]
  ; icon_size : Icon_size.t [@sexp_drop_if Icon_size.equal Inherit]
  }
[@@deriving sexp_of, equal]

type picture_props =
  { source : Picture_source.t
  ; content_fit : Content_fit.t [@sexp_drop_if Content_fit.equal Contain]
  ; can_shrink : bool [@sexp_drop_if fun b -> b]
  ; alternative_text : string option [@sexp_drop_if Option.is_none]
  }
[@@deriving sexp_of, equal]

type separator_props = { orientation : Orientation.t } [@@deriving sexp_of, equal]

(* The single-child containers. Every default below is GTK's own, so a container built
   from its child alone is the plain GTK widget -- which is why [kinetic_scrolling] and
   [overlay_scrolling] default to [true] and are dropped from the sexp when they are. *)
type scrolled_window_props =
  { hpolicy : Policy.t [@sexp_drop_if Policy.equal Automatic]
  ; vpolicy : Policy.t [@sexp_drop_if Policy.equal Automatic]
  ; min_content_width : int [@sexp_drop_if Int.equal (-1)]
  ; min_content_height : int [@sexp_drop_if Int.equal (-1)]
  ; max_content_width : int [@sexp_drop_if Int.equal (-1)]
  ; max_content_height : int [@sexp_drop_if Int.equal (-1)]
  ; propagate_natural_width : bool [@sexp_drop_if fun b -> not b]
  ; propagate_natural_height : bool [@sexp_drop_if fun b -> not b]
  ; has_frame : bool [@sexp_drop_if fun b -> not b]
  ; kinetic_scrolling : bool [@sexp_drop_if fun b -> b]
  ; overlay_scrolling : bool [@sexp_drop_if fun b -> b]
  }
[@@deriving sexp_of, equal]

type frame_props =
  { label : string option [@sexp_drop_if Option.is_none]
  ; label_align : float [@sexp_drop_if Float.equal 0.]
  }
[@@deriving sexp_of, equal]

(* [expanded] and [reveal] carry no [@sexp_drop_if] for the reason the toggles' [active]
   does not: they are required labelled arguments and controlled props, so their value is
   always something the caller asked for. *)
type expander_props =
  { label : string option [@sexp_drop_if Option.is_none]
  ; expanded : bool
  ; use_markup : bool [@sexp_drop_if fun b -> not b]
  }
[@@deriving sexp_of, equal]

type revealer_props =
  { reveal : bool
  ; transition : Reveal_transition.t [@sexp_drop_if Reveal_transition.equal None_]
  ; transition_duration : int [@sexp_drop_if Int.equal 250]
  }
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
  | Image of image_props
  | Picture of picture_props
  | Separator of separator_props
  | Scrolled_window of scrolled_window_props
  | Frame of frame_props
  | Expander of expander_props
  | Revealer of revealer_props
  | Box of box_props
  | Window of window_props
  | Native of Native.t
[@@deriving sexp_of]

(** Same constructor (and, for [Native], same [name]). Props ignored. *)
val same_kind : t -> t -> bool

val name : t -> string

(** Structural on props; [Native] payloads compare physically. *)
val equal_props : t -> t -> bool
