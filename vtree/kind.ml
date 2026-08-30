open! Core

(* Every kind's props live in a named record rather than an inline one, so that a widget
   impl can name the type it is handed ([Kind.label_props]) and so that [equal_props] is
   one derived call per kind instead of a hand-written conjunction.

   [@sexp_drop_if] on each field whose value is GTK's own default keeps a printed node
   about what the caller asked for rather than about the defaults: [Node.label "x"] prints
   as [(Label ((text x)))], and a property appears only once it has been set to something.
   It is print-only — [equal_label_props] and friends still compare every field.

   Each of those defaults is [Defaults.<Widget>.<field>] rather than a literal, because
   the literal would also have to be written in [Node]'s optional argument and in this
   file's mli: three copies that drift silently, and the drift prints a property the
   caller did set as though it were never set. *)

type label_props =
  { text : string
  ; wrap : bool [@sexp_drop_if Bool.equal Defaults.Label.wrap]
  ; xalign : float [@sexp_drop_if Float.equal Defaults.Label.xalign]
  ; ellipsize : Ellipsize.t option [@sexp_drop_if Option.is_none]
  ; max_width_chars : int [@sexp_drop_if Int.equal Defaults.Label.max_width_chars]
  ; width_chars : int [@sexp_drop_if Int.equal Defaults.Label.width_chars]
  ; selectable : bool [@sexp_drop_if Bool.equal Defaults.Label.selectable]
  ; use_markup : bool [@sexp_drop_if Bool.equal Defaults.Label.use_markup]
  }
[@@deriving sexp_of, equal]

type button_props =
  { label : string option [@sexp_drop_if Option.is_none]
  ; icon_name : string option [@sexp_drop_if Option.is_none]
  ; has_frame : bool [@sexp_drop_if Bool.equal Defaults.Button.has_frame]
  }
[@@deriving sexp_of, equal]

type toggle_button_props =
  { label : string option [@sexp_drop_if Option.is_none]
  ; icon_name : string option [@sexp_drop_if Option.is_none]
  ; has_frame : bool [@sexp_drop_if Bool.equal Defaults.Toggle_button.has_frame]
  ; active : bool
  }
[@@deriving sexp_of, equal]

type check_button_props =
  { label : string option [@sexp_drop_if Option.is_none]
  ; active : bool
  ; inconsistent : bool [@sexp_drop_if Bool.equal Defaults.Check_button.inconsistent]
  }
[@@deriving sexp_of, equal]

type switch_props = { active : bool } [@@deriving sexp_of, equal]

(* The entry family. [text] carries no [@sexp_drop_if]: it is a required labelled
   argument, so it is always something the caller asked for. *)
type entry_props =
  { text : string
  ; placeholder : string option [@sexp_drop_if Option.is_none]
  ; editable : bool [@sexp_drop_if Bool.equal Defaults.Entry.editable]
  ; visibility : bool [@sexp_drop_if Bool.equal Defaults.Entry.visibility]
  ; width_chars : int [@sexp_drop_if Int.equal Defaults.Entry.width_chars]
  ; max_width_chars : int [@sexp_drop_if Int.equal Defaults.Entry.max_width_chars]
  ; xalign : float [@sexp_drop_if Float.equal Defaults.Entry.xalign]
  ; activates_default : bool [@sexp_drop_if Bool.equal Defaults.Entry.activates_default]
  ; max_length : int [@sexp_drop_if Int.equal Defaults.Entry.max_length]
  }
[@@deriving sexp_of, equal]

type password_entry_props =
  { text : string
  ; placeholder : string option [@sexp_drop_if Option.is_none]
  ; show_peek_icon : bool
       [@sexp_drop_if Bool.equal Defaults.Password_entry.show_peek_icon]
  ; activates_default : bool
       [@sexp_drop_if Bool.equal Defaults.Password_entry.activates_default]
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
  ; step : float [@sexp_drop_if Float.equal Defaults.Spin_button.step]
  ; digits : int [@sexp_drop_if Int.equal Defaults.Spin_button.digits]
  ; numeric : bool [@sexp_drop_if Bool.equal Defaults.Spin_button.numeric]
  ; wrap : bool [@sexp_drop_if Bool.equal Defaults.Spin_button.wrap]
  ; activates_default : bool
       [@sexp_drop_if Bool.equal Defaults.Spin_button.activates_default]
  }
[@@deriving sexp_of, equal]

type scale_props =
  { orientation : Orientation.t
  ; value : float
  ; min : float
  ; max : float
  ; step : float [@sexp_drop_if Float.equal Defaults.Scale.step]
  ; digits : int [@sexp_drop_if Int.equal Defaults.Scale.digits]
  ; draw_value : bool [@sexp_drop_if Bool.equal Defaults.Scale.draw_value]
  ; has_origin : bool [@sexp_drop_if Bool.equal Defaults.Scale.has_origin]
  ; inverted : bool [@sexp_drop_if Bool.equal Defaults.Scale.inverted]
  }
[@@deriving sexp_of, equal]

type progress_bar_props =
  { fraction : float
  ; text : string option [@sexp_drop_if Option.is_none]
  ; show_text : bool [@sexp_drop_if Bool.equal Defaults.Progress_bar.show_text]
  ; inverted : bool [@sexp_drop_if Bool.equal Defaults.Progress_bar.inverted]
  ; ellipsize : Ellipsize.t option [@sexp_drop_if Option.is_none]
  }
[@@deriving sexp_of, equal]

type spinner_props = { spinning : bool } [@@deriving sexp_of, equal]

(* [Image] and [Picture] carry their source as a closed variant rather than as separate
   optional props: the sources are mutually exclusive and GTK's setters do not compose, so
   a variant makes the exclusivity a type error and gives [equal_props] one line. *)
type image_props =
  { source : Image_source.t
  ; pixel_size : int [@sexp_drop_if Int.equal Defaults.Image.pixel_size]
  ; icon_size : Icon_size.t [@sexp_drop_if Icon_size.equal Defaults.Image.icon_size]
  }
[@@deriving sexp_of, equal]

type picture_props =
  { source : Picture_source.t
  ; content_fit : Content_fit.t
       [@sexp_drop_if Content_fit.equal Defaults.Picture.content_fit]
  ; can_shrink : bool [@sexp_drop_if Bool.equal Defaults.Picture.can_shrink]
  ; alternative_text : string option [@sexp_drop_if Option.is_none]
  }
[@@deriving sexp_of, equal]

type separator_props = { orientation : Orientation.t } [@@deriving sexp_of, equal]

(* The single-child containers. Every default below is GTK's own, so a container built
   from its child alone is the plain GTK widget -- which is why [kinetic_scrolling] and
   [overlay_scrolling] default to [true] and are dropped from the sexp when they are. *)
type scrolled_window_props =
  { hpolicy : Policy.t [@sexp_drop_if Policy.equal Defaults.Scrolled_window.hpolicy]
  ; vpolicy : Policy.t [@sexp_drop_if Policy.equal Defaults.Scrolled_window.vpolicy]
  ; min_content_width : int
       [@sexp_drop_if Int.equal Defaults.Scrolled_window.min_content_width]
  ; min_content_height : int
       [@sexp_drop_if Int.equal Defaults.Scrolled_window.min_content_height]
  ; max_content_width : int
       [@sexp_drop_if Int.equal Defaults.Scrolled_window.max_content_width]
  ; max_content_height : int
       [@sexp_drop_if Int.equal Defaults.Scrolled_window.max_content_height]
  ; propagate_natural_width : bool
       [@sexp_drop_if Bool.equal Defaults.Scrolled_window.propagate_natural_width]
  ; propagate_natural_height : bool
       [@sexp_drop_if Bool.equal Defaults.Scrolled_window.propagate_natural_height]
  ; has_frame : bool [@sexp_drop_if Bool.equal Defaults.Scrolled_window.has_frame]
  ; kinetic_scrolling : bool
       [@sexp_drop_if Bool.equal Defaults.Scrolled_window.kinetic_scrolling]
  ; overlay_scrolling : bool
       [@sexp_drop_if Bool.equal Defaults.Scrolled_window.overlay_scrolling]
  }
[@@deriving sexp_of, equal]

type frame_props =
  { label : string option [@sexp_drop_if Option.is_none]
  ; label_align : float [@sexp_drop_if Float.equal Defaults.Frame.label_align]
  }
[@@deriving sexp_of, equal]

(* [expanded] and [reveal] carry no [@sexp_drop_if] for the reason the toggles' [active]
   does not: they are required labelled arguments and controlled props, so their value is
   always something the caller asked for. *)
type expander_props =
  { label : string option [@sexp_drop_if Option.is_none]
  ; expanded : bool
  ; use_markup : bool [@sexp_drop_if Bool.equal Defaults.Expander.use_markup]
  }
[@@deriving sexp_of, equal]

type revealer_props =
  { reveal : bool
  ; transition : Reveal_transition.t
       [@sexp_drop_if Reveal_transition.equal Defaults.Revealer.transition]
  ; transition_duration : int
       [@sexp_drop_if Int.equal Defaults.Revealer.transition_duration]
  }
[@@deriving sexp_of, equal]

type box_props =
  { orientation : Orientation.t
  ; spacing : int [@sexp_drop_if Int.equal Defaults.Box.spacing]
  ; homogeneous : bool [@sexp_drop_if Bool.equal Defaults.Box.homogeneous]
  }
[@@deriving sexp_of, equal]

(* The slot containers (spec §5.3's fourth children shape). Their children are addressed
   by role rather than position, and none of the props below is about a child -- an
   overlay's per-child measure flag lives on the child node's attrs, because it is a
   setting the overlay holds about that child rather than a property of either widget. *)
type center_box_props =
  { shrink_center_last : bool
       [@sexp_drop_if Bool.equal Defaults.Center_box.shrink_center_last]
  }
[@@deriving sexp_of, equal]

(* [position] is [None] for "leave GTK's own split". It is deliberately *not* controlled
   -- see [Node.paned] -- which is why it is an option rather than a plain int: there is a
   difference between "put it at 240" and "wherever it ended up". *)
type paned_props =
  { orientation : Orientation.t
  ; position : int option [@sexp_drop_if Option.is_none]
  ; wide_handle : bool [@sexp_drop_if Bool.equal Defaults.Paned.wide_handle]
  ; resize_start : bool [@sexp_drop_if Bool.equal Defaults.Paned.resize_start]
  ; resize_end : bool [@sexp_drop_if Bool.equal Defaults.Paned.resize_end]
  ; shrink_start : bool [@sexp_drop_if Bool.equal Defaults.Paned.shrink_start]
  ; shrink_end : bool [@sexp_drop_if Bool.equal Defaults.Paned.shrink_end]
  }
[@@deriving sexp_of, equal]

(* A [GtkOverlay] has no properties of its own: it is entirely its children. *)
type overlay_props = unit [@@deriving sexp_of, equal]

(* [Grid] holds no per-child anything: a child's cell is on the child node's attrs
   ([Attr.grid_cell]), because [gtk_grid_attach] is a call on the grid rather than a
   property of either widget. *)
type grid_props =
  { row_spacing : int [@sexp_drop_if Int.equal Defaults.Grid.row_spacing]
  ; column_spacing : int [@sexp_drop_if Int.equal Defaults.Grid.column_spacing]
  ; row_homogeneous : bool [@sexp_drop_if Bool.equal Defaults.Grid.row_homogeneous]
  ; column_homogeneous : bool [@sexp_drop_if Bool.equal Defaults.Grid.column_homogeneous]
  }
[@@deriving sexp_of, equal]

(* [name] is what a [Stack_switcher] or [Stack_sidebar] elsewhere in the tree finds this
   stack by, and [visible_child] is the page name -- the child node's [Key.t] -- to show.
   Neither carries a [@sexp_drop_if]: both are required labelled arguments, so their value
   is always something the caller asked for. *)
type stack_props =
  { name : string
  ; visible_child : string
  ; transition : Stack_transition.t
       [@sexp_drop_if Stack_transition.equal Defaults.Stack.transition]
  ; transition_duration : int [@sexp_drop_if Int.equal Defaults.Stack.transition_duration]
  ; hhomogeneous : bool [@sexp_drop_if Bool.equal Defaults.Stack.hhomogeneous]
  ; vhomogeneous : bool [@sexp_drop_if Bool.equal Defaults.Stack.vhomogeneous]
  }
[@@deriving sexp_of, equal]

(* Shared by [Stack_switcher] and [Stack_sidebar], which differ only in which GTK widget
   they are: each names the [Stack] it drives and holds nothing else. *)
type stack_ref_props = { stack : string } [@@deriving sexp_of, equal]

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
  | Grid of grid_props
  | Stack of stack_props
  | Stack_switcher of stack_ref_props
  | Stack_sidebar of stack_ref_props
  | Center_box of center_box_props
  | Paned of paned_props
  | Overlay of overlay_props
  | Window of window_props
  | Native of Native.t
[@@deriving sexp_of, variants]

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
  | Image _ -> "Image"
  | Picture _ -> "Picture"
  | Separator _ -> "Separator"
  | Scrolled_window _ -> "ScrolledWindow"
  | Frame _ -> "Frame"
  | Expander _ -> "Expander"
  | Revealer _ -> "Revealer"
  | Box _ -> "Box"
  | Grid _ -> "Grid"
  | Stack _ -> "Stack"
  | Stack_switcher _ -> "StackSwitcher"
  | Stack_sidebar _ -> "StackSidebar"
  | Center_box _ -> "CenterBox"
  | Paned _ -> "Paned"
  | Overlay _ -> "Overlay"
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
  | Image _, Image _
  | Picture _, Picture _
  | Separator _, Separator _
  | Scrolled_window _, Scrolled_window _
  | Frame _, Frame _
  | Expander _, Expander _
  | Revealer _, Revealer _
  | Box _, Box _
  | Grid _, Grid _
  | Stack _, Stack _
  | Stack_switcher _, Stack_switcher _
  | Stack_sidebar _, Stack_sidebar _
  | Center_box _, Center_box _
  | Paned _, Paned _
  | Overlay _, Overlay _
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
  | Image a, Image b -> equal_image_props a b
  | Picture a, Picture b -> equal_picture_props a b
  | Separator a, Separator b -> equal_separator_props a b
  | Scrolled_window a, Scrolled_window b -> equal_scrolled_window_props a b
  | Frame a, Frame b -> equal_frame_props a b
  | Expander a, Expander b -> equal_expander_props a b
  | Revealer a, Revealer b -> equal_revealer_props a b
  | Box a, Box b -> equal_box_props a b
  | Grid a, Grid b -> equal_grid_props a b
  | Stack a, Stack b -> equal_stack_props a b
  | Stack_switcher a, Stack_switcher b | Stack_sidebar a, Stack_sidebar b ->
    equal_stack_ref_props a b
  | Center_box a, Center_box b -> equal_center_box_props a b
  | Paned a, Paned b -> equal_paned_props a b
  | Overlay a, Overlay b -> equal_overlay_props a b
  | Window a, Window b -> equal_window_props a b
  | Native a, Native b -> String.equal a.name b.name && phys_equal a.payload b.payload
  | _ -> false
;;
