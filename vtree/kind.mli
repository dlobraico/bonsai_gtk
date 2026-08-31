open! Core

(** Every kind's props are a named record so that widget implementations can name the type
    they are handed and so that {!equal_props} is one derived comparison per kind.

    A field whose value is GTK's own default is dropped from the sexp, so a printed node
    shows what the caller asked for rather than the defaults. That is print-only:
    {!equal_props} still compares every field. The defaults themselves are named in
    [Defaults], which is what keeps them in step with [Node]'s optional arguments. *)

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

(* [text] carries no [@sexp_drop_if] for the reason the entries' does not: it is a
   required labelled argument and a controlled prop, so its value is always something the
   caller asked for. The other nine are GTK's own. *)
type text_view_props =
  { text : string
  ; wrap : Wrap_mode.t [@sexp_drop_if Wrap_mode.equal Defaults.Text_view.wrap]
  ; editable : bool [@sexp_drop_if Bool.equal Defaults.Text_view.editable]
  ; monospace : bool [@sexp_drop_if Bool.equal Defaults.Text_view.monospace]
  ; cursor_visible : bool [@sexp_drop_if Bool.equal Defaults.Text_view.cursor_visible]
  ; accepts_tab : bool [@sexp_drop_if Bool.equal Defaults.Text_view.accepts_tab]
  ; left_margin : int [@sexp_drop_if Int.equal Defaults.Text_view.left_margin]
  ; right_margin : int [@sexp_drop_if Int.equal Defaults.Text_view.right_margin]
  ; top_margin : int [@sexp_drop_if Int.equal Defaults.Text_view.top_margin]
  ; bottom_margin : int [@sexp_drop_if Int.equal Defaults.Text_view.bottom_margin]
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

(* The other bar. A [GtkLevelBar] has a range rather than a fraction, so [value] is in the
   application's own units; [min] and [max] are optional and default to GTK's 0-1, unlike
   the two range widgets above, because a level bar is an output that nothing reads back
   and 0-1 is the fraction a caller who names no range wants. *)
type level_bar_props =
  { value : float
  ; min : float [@sexp_drop_if Float.equal Defaults.Level_bar.min]
  ; max : float [@sexp_drop_if Float.equal Defaults.Level_bar.max]
  ; mode : Level_bar_mode.t [@sexp_drop_if Level_bar_mode.equal Defaults.Level_bar.mode]
  ; inverted : bool [@sexp_drop_if Bool.equal Defaults.Level_bar.inverted]
  }
[@@deriving sexp_of, equal]

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
   difference between "put it at 240" and "wherever it ended up". No [@sexp_drop_if] on
   it, deliberately: dropping the [None] made "no position computed" indistinguishable in
   a golden from "no such field" (docs/m2-backlog.md, headless M3). *)
type paned_props =
  { orientation : Orientation.t
  ; position : int option
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

(* [selected] is the model's selection, by row key, and carries no [@sexp_drop_if]: it is
   a required labelled argument. The other three are GTK's own defaults, and two of them
   are not the value a reader guesses -- a bare [GtkListBox] selects one row and activates
   on a single click. A row's own per-row settings are not here: they are held by the
   [GtkListBoxRow] the impl wraps around each child, and ride on the child node's attrs
   ([Attr.row_selectable], [Attr.row_activatable]). *)
type list_box_props =
  { selection_mode : Selection_mode.t
       [@sexp_drop_if Selection_mode.equal Defaults.List_box.selection_mode]
  ; activate_on_single_click : bool
       [@sexp_drop_if Bool.equal Defaults.List_box.activate_on_single_click]
  ; show_separators : bool [@sexp_drop_if Bool.equal Defaults.List_box.show_separators]
  ; selected : Key.t list
  }
[@@deriving sexp_of, equal]

(* [selected] carries no [@sexp_drop_if] for the reason [list_box_props]' does not: it is
   a required labelled argument. The other seven are GTK's own defaults, and three are not
   the value a reader guesses -- a bare [GtkFlowBox] selects one child, activates on a
   single click, and lays out at most **seven** children per line.

   There is no per-child record beside this one, and that is GTK's doing rather than an
   omission: [GtkFlowBoxChild] has no [selectable] and no [activatable] -- unlike
   [GtkListBoxRow], which has both -- so a flow box holds nothing on behalf of an
   individual child and reads no placement attrs at all. *)
type flow_box_props =
  { selection_mode : Selection_mode.t
       [@sexp_drop_if Selection_mode.equal Defaults.Flow_box.selection_mode]
  ; activate_on_single_click : bool
       [@sexp_drop_if Bool.equal Defaults.Flow_box.activate_on_single_click]
  ; min_children_per_line : int
       [@sexp_drop_if Int.equal Defaults.Flow_box.min_children_per_line]
  ; max_children_per_line : int
       [@sexp_drop_if Int.equal Defaults.Flow_box.max_children_per_line]
  ; row_spacing : int [@sexp_drop_if Int.equal Defaults.Flow_box.row_spacing]
  ; column_spacing : int [@sexp_drop_if Int.equal Defaults.Flow_box.column_spacing]
  ; homogeneous : bool [@sexp_drop_if Bool.equal Defaults.Flow_box.homogeneous]
  ; orientation : Orientation.t
       [@sexp_drop_if Orientation.equal Defaults.Flow_box.orientation]
  ; selected : Key.t list
  }
[@@deriving sexp_of, equal]

(* [current_page] is the key of the page to show and carries no [@sexp_drop_if] for the
   reason [stack_props]' [visible_child] does not: it is a required labelled argument. The
   other four are GTK's own, and -- unlike both of this record's neighbours -- none of
   them is a value a reader guesses wrong: a bare [GtkNotebook] draws its tabs and its
   border, scrolls its tab area with neither, and puts the tabs at the top.

   The one per-page setting lives on the page node's attrs ([Attr.tab_label]), on
   [Attr.page_title]'s rule: the tab label is a widget the {i notebook} owns on the page's
   behalf. *)
type notebook_props =
  { current_page : Key.t
  ; scrollable : bool [@sexp_drop_if Bool.equal Defaults.Notebook.scrollable]
  ; show_tabs : bool [@sexp_drop_if Bool.equal Defaults.Notebook.show_tabs]
  ; show_border : bool [@sexp_drop_if Bool.equal Defaults.Notebook.show_border]
  ; tab_pos : Tab_position.t [@sexp_drop_if Tab_position.equal Defaults.Notebook.tab_pos]
  }
[@@deriving sexp_of, equal]

(* The drop-down's whole content is [items] and its selection is [selected], a position
   into that list with [-1] for none. Both are required labelled arguments and so carry no
   [@sexp_drop_if]; the other two are GTK's own.

   Items are props rather than children -- they are strings in a list model GTK owns, not
   widgets -- which is what makes this the one controlled selection in the library that
   lives in [Widget_impl.reassert] rather than in the fixup queue. See [Node.drop_down].
   The [items] comparison the derived [equal] performs is also what decides whether the
   GTK model is written at all; [w_drop_down.ml] splices the whole content into the model
   the drop-down already holds, and only when it really moved. *)
type drop_down_props =
  { items : string list
  ; selected : int
  ; enable_search : bool [@sexp_drop_if Bool.equal Defaults.Drop_down.enable_search]
  ; show_arrow : bool [@sexp_drop_if Bool.equal Defaults.Drop_down.show_arrow]
  }
[@@deriving sexp_of, equal]

(* The date is a {!Core.Date.t} and never GTK's three integers. [GtkCalendar] has no date
   property: it has [year], [month] and [day], and its [month] is {b zero-based} while its
   [day] is one-based. [gtk_calendar_get_date] and [select_day] would sidestep that, but
   they trade in [GDateTime] and this binding has none, so the conversion lives in
   [src/widgets/w_calendar.ml] and nowhere else. [date] is the required labelled argument
   and so carries no [@sexp_drop_if]; the three [show_*] flags are GTK's own, and two of
   them are [true].

   [marked_days] is a list of days of the month (1-31), is not controlled -- nothing the
   user does marks a day -- and is applied as [clear_marks] plus one [mark_day] per entry,
   for which order and duplicates make no difference. *)
type calendar_props =
  { date : Date.t
  ; show_day_names : bool [@sexp_drop_if Bool.equal Defaults.Calendar.show_day_names]
  ; show_heading : bool [@sexp_drop_if Bool.equal Defaults.Calendar.show_heading]
  ; show_week_numbers : bool
       [@sexp_drop_if Bool.equal Defaults.Calendar.show_week_numbers]
  ; marked_days : int list [@sexp_drop_if List.is_empty]
  }
[@@deriving sexp_of, equal]

(* Both props are controlled and neither carries a [@sexp_drop_if]: [text] is the required
   labelled argument and [editing] is a controlled prop, so both are always something the
   caller asked for.

   [editing] is {b read-only in GTK}. Controlling it means [start_editing] to enter and
   [stop_editing ~commit:true] to leave, which is two methods rather than a property
   write. See [Node.editable_label]. *)
type editable_label_props =
  { text : string
  ; editing : bool
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
  | Text_view of text_view_props
  | Spin_button of spin_button_props
  | Scale of scale_props
  | Progress_bar of progress_bar_props
  | Spinner of spinner_props
  | Level_bar of level_bar_props
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
  | List_box of list_box_props
  | Flow_box of flow_box_props
  | Notebook of notebook_props
  | Drop_down of drop_down_props
  | Calendar of calendar_props
  | Editable_label of editable_label_props
  | Center_box of center_box_props
  | Paned of paned_props
  | Overlay of overlay_props
  | Window of window_props
  | Native of Native.t
(* [variants] is here for exactly one thing: [Kind.Variants.descriptions] is a
   compiler-derived list of every constructor, so a test that must cover them all can
   assert its own list is complete rather than hoping someone bumped a literal. See
   [test/test_events.ml] and [test/live/live_events.ml]. *)
[@@deriving sexp_of, variants]

(** Same constructor (and, for [Native], same [name]). Props ignored.

    Answered by comparing {!name}, which is exhaustive with no wildcard — so a kind added
    without a decision there is a compile error and this function cannot silently answer
    [false] against itself. That failure is the expensive one: the patcher reads this as
    "is this the same widget", so a kind it got wrong is destroyed and remounted on every
    frame that touches it. *)
val same_kind : t -> t -> bool

val name : t -> string

(** Structural on props; [Native] payloads compare physically.

    Two different kinds are never equal. Two of the {i same} kind with no arm in the
    implementation raise instead of answering [false]: it is the one wildcard the variant
    is too wide to write out, and a missing arm there would otherwise make every patch of
    that kind look like a prop change forever. *)
val equal_props : t -> t -> bool
