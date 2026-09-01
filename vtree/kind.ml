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

(* The other bar, and the props say how it differs from [progress_bar_props] above: a
   [GtkLevelBar] has a *range* rather than a fraction, so [value] is in the application's
   own units and [min]/[max] say what they mean.

   Unlike the two range widgets further up this file, [min] and [max] are optional and
   default to GTK's 0-1: a level bar is an output rather than a control, nothing reads a
   value back off it, and 0-1 is a fraction -- which is what a caller who does not mention
   a range wants and is exactly what a progress bar gives. [value] carries no
   [@sexp_drop_if] because it is the required labelled argument. *)
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

(* The header bar's {i title} is a slot child, not a prop: GTK4's [GtkHeaderBar] has no
   title-string setter, only [set_title_widget], and with no title widget it shows the
   window's title. [decoration_layout] is [None] for "GTK's default layout" -- the setter
   is nullable, so the unset path is honest. *)
type header_bar_props =
  { show_title_buttons : bool
       [@sexp_drop_if Bool.equal Defaults.Header_bar.show_title_buttons]
  ; decoration_layout : string option [@sexp_drop_if Option.is_none]
  }
[@@deriving sexp_of, equal]

(* [revealed] is a plain prop, not controlled: GTK's [revealed] moves only
   programmatically (the user cannot conceal an action bar), so there is nothing for a
   [reassert] to put back. *)
type action_bar_props =
  { revealed : bool [@sexp_drop_if Bool.equal Defaults.Action_bar.revealed] }
[@@deriving sexp_of, equal]

(* [open_] is controlled (spec §6.5) and so deliberately carries no [sexp_drop_if]: a
   popover the model holds closed and one it never thought about are different claims. The
   other three are plain preferences, GTK's defaults, dropped at theirs. *)
type popover_props =
  { open_ : bool
  ; position : Position.t [@sexp_drop_if Position.equal Defaults.Popover.position]
  ; autohide : bool [@sexp_drop_if Bool.equal Defaults.Popover.autohide]
  ; has_arrow : bool [@sexp_drop_if Bool.equal Defaults.Popover.has_arrow]
  }
[@@deriving sexp_of, equal]

(* [label] and [icon_name] are mutually exclusive -- GTK's setters replace each other's
   child -- and [Node.menu_button] rejects both at the constructor. [~menu] joins in
   Task 6. *)
type menu_button_props =
  { label : string option [@sexp_drop_if Option.is_none]
  ; icon_name : string option [@sexp_drop_if Option.is_none]
  ; primary : bool [@sexp_drop_if Bool.equal Defaults.Menu_button.primary]
  ; always_show_arrow : bool
       [@sexp_drop_if Bool.equal Defaults.Menu_button.always_show_arrow]
  ; menu : Menu.t option [@sexp_drop_if Option.is_none]
  (* A prop, deliberately: a [Menu.t] carries no handlers (items {i name} actions), so it
     is equalable and diffable like any other prop, and [Menu.equal] deciding "the menu
     changed" is what triggers the GMenu rebuild. *)
  }
[@@deriving sexp_of, equal]

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
   a required labelled argument, so its value is always something the caller asked for.
   The other three are GTK's own defaults -- and note that two of them are not the "off"
   value a reader expects: a [GtkListBox] selects one row by default and activates on a
   single click by default. *)
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
   reason [stack_props]' [visible_child] does not: it is a required labelled argument, so
   its value is always something the caller asked for. The other four are GTK's own, and
   none of them is a surprise -- which is worth saying because both of this notebook's
   neighbours in this file have one that is.

   There is one per-page setting beside this record and it lives on the page node's attrs
   ([Attr.tab_label]), on the rule [Attr.page_title] and [Attr.grid_cell] follow: the tab
   label is a widget the {i notebook} owns on the page's behalf rather than a property of
   either widget. *)
type notebook_props =
  { current_page : Key.t
  ; scrollable : bool [@sexp_drop_if Bool.equal Defaults.Notebook.scrollable]
  ; show_tabs : bool [@sexp_drop_if Bool.equal Defaults.Notebook.show_tabs]
  ; show_border : bool [@sexp_drop_if Bool.equal Defaults.Notebook.show_border]
  ; tab_pos : Tab_position.t [@sexp_drop_if Tab_position.equal Defaults.Notebook.tab_pos]
  }
[@@deriving sexp_of, equal]

(* [items] is the drop-down's whole content and [selected] the position of the one
   showing, [-1] for none; neither carries a [@sexp_drop_if], because both are required
   labelled arguments. The other two are GTK's own.

   The items are *props* rather than children, which is what makes this widget's selection
   different from the three keyed containers': a [GtkDropDown]'s items are strings in a
   list model GTK owns, not widgets, so there is no [Key.t] to name one and no child to be
   missing when the selection is applied. [Node.drop_down] documents what follows from
   that.

   [items] is compared by [equal_list_string] like any other field, and that comparison is
   what decides whether the GTK model is written at all -- see [w_drop_down.ml], which
   splices the whole content into the model the drop-down already holds, and only when
   this field really moved. *)
type drop_down_props =
  { items : string list
  ; selected : int
  ; enable_search : bool [@sexp_drop_if Bool.equal Defaults.Drop_down.enable_search]
  ; show_arrow : bool [@sexp_drop_if Bool.equal Defaults.Drop_down.show_arrow]
  }
[@@deriving sexp_of, equal]

(* The date is a {!Core.Date.t} and never GTK's three integers, which is the whole point
   of this record: [GtkCalendar] has no date property at all, only [year], [month] and
   [day] -- and its [month] is {b zero-based} while its [day] is one-based, an asymmetry
   that reads correctly through January and is wrong for the other eleven months.
   [gtk_calendar_get_date] and [gtk_calendar_select_day] would hand over a [GDateTime] and
   sidestep it, but they take and return one and this binding has no [GDateTime] anywhere
   (there is no [GLib-2.0.gir] in the checkout to generate one from), so they are not
   bound. The conversion therefore has to live somewhere, and it lives in
   [src/widgets/w_calendar.ml] alone.

   [date] carries no [@sexp_drop_if] because it is the required labelled argument, and
   because a calendar with an implicit date would show {i today} -- a value nothing chose
   and which moves while the application runs.

   [marked_days] is a list of {i days of the month}, 1-31, and is deliberately not
   controlled: nothing the user does marks a day. It is an [int list] rather than a set
   because it is short, because [equal_calendar_props] then compares it in list order
   (which is what a view producing a sorted list already gives), and because the impl
   applies it with [clear_marks] followed by one [mark_day] per entry -- an operation for
   which order and duplicates make no difference.

   {b The comparison is stricter than the write}, and deliberately: [[1; 2]] and [[2; 1]]
   are unequal here and cost a [clear_marks], 31 [mark_day]s at worst and a redraw for no
   visible change. Making them equal would mean sorting (or set-ifying) on every
   comparison -- an allocation per calendar per differing frame, to save a redraw for a
   view that rebuilds its marks in a different order each time, which is not a view
   anybody writes. If one ever appears, the fix belongs in the {i view} (hand a sorted
   list) rather than here (task-11-review.md Minor 6). Marks are per day-of-month and
   survive a month change: day 31 marked while February is showing is still marked in
   March (measured). *)
type calendar_props =
  { date : Date.t
  ; show_day_names : bool [@sexp_drop_if Bool.equal Defaults.Calendar.show_day_names]
  ; show_heading : bool [@sexp_drop_if Bool.equal Defaults.Calendar.show_heading]
  ; show_week_numbers : bool
       [@sexp_drop_if Bool.equal Defaults.Calendar.show_week_numbers]
  ; marked_days : int list [@sexp_drop_if List.is_empty]
  }
[@@deriving sexp_of, equal]

(* Two props, both controlled, and neither carries a [@sexp_drop_if]: [text] is the
   required labelled argument (the entries' rule) and [editing] is a controlled prop whose
   value is always something the caller asked for (the toggles' rule).

   [editing] being controlled is the unusual one. It is {b read-only in GTK} -- there is
   no [gtk_editable_label_set_editing] -- so the impl enters editing mode with
   [start_editing] and leaves it with [stop_editing ~commit:true], which are two methods
   rather than a property write and are not symmetric with each other.
   [Node.editable_label] says why committing is the only defensible reading of a model
   that renders [~editing:false]. *)
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
  ; transient_for : Key.t option [@sexp_drop_if Option.is_none]
  ; modal : bool [@sexp_drop_if Bool.equal Defaults.Window.modal]
  ; resizable : bool [@sexp_drop_if Bool.equal Defaults.Window.resizable]
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
  | Header_bar of header_bar_props
  | Action_bar of action_bar_props
  | Popover of popover_props
  | Menu_button of menu_button_props
  | Window of window_props
  (* Carries nothing: the windows root is a virtual node -- one never-shown anchor widget
     holding the keyed toplevels -- and everything it could say (the children, their keys)
     lives on the node, not the kind. The one nullary constructor, because OCaml has no
     empty record and a [unit] payload would be a third spelling of "nothing". *)
  | Windows
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
  | Text_view _ -> "TextView"
  | Spin_button _ -> "SpinButton"
  | Scale _ -> "Scale"
  | Progress_bar _ -> "ProgressBar"
  | Spinner _ -> "Spinner"
  | Level_bar _ -> "LevelBar"
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
  | List_box _ -> "ListBox"
  | Flow_box _ -> "FlowBox"
  | Notebook _ -> "Notebook"
  | Drop_down _ -> "DropDown"
  | Calendar _ -> "Calendar"
  | Editable_label _ -> "EditableLabel"
  | Center_box _ -> "CenterBox"
  | Paned _ -> "Paned"
  | Overlay _ -> "Overlay"
  | Header_bar _ -> "HeaderBar"
  | Action_bar _ -> "ActionBar"
  | Popover _ -> "Popover"
  | Menu_button _ -> "MenuButton"
  | Window _ -> "Window"
  | Windows -> "Windows"
  | Native n -> "Native:" ^ n.name
;;

(* A [name] comparison rather than the 32-arm matrix this used to be.

   The matrix ended in [| _ -> false], and that wildcard is the worst place in this file
   to forget an arm: the patcher reads [same_kind] as "is this the same widget", so a kind
   whose arm is missing answers [false] against itself and is destroyed and remounted on
   {i every} frame that touches it -- losing the caret, the selection, the focus and every
   signal connection, silently and at sixty frames a second. Nothing else notices;
   [equal_props] is not even consulted.

   [name] is exhaustive with no wildcard, so a kind added without a decision there is a
   compile error, and this function inherits that. It also handles [Native] by
   construction: [name] renders it as ["Native:" ^ n.name], which is exactly the
   comparison the matrix's one special arm made by hand.

   The cost is a string comparison per node per patch in place of a tag comparison. The
   strings are short literals and [String.equal] compares lengths first, so two different
   kinds nearly always answer on the length; two of the same kind compare a handful of
   bytes.

   {b A [Native] node additionally allocates two strings per comparison}, since [name]
   builds ["Native:" ^ n.name] for each side, where the old matrix compared the two
   [n.name]s with no allocation at all. That is the real cost of this change and it is
   worth naming: it is two short minor-heap allocations per native node per patch, against
   a wildcard that made a forgotten arm destroy and remount a widget sixty times a second.
   If native nodes ever become common enough for that to matter, the fix is a [tag]
   function returning a variant -- exhaustive like [name], and allocation-free -- rather
   than going back to the matrix. (task-9-report.md's carry 1; task-10-review.md M4.) *)
let same_kind a b = String.equal (name a) (name b)

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
  | Text_view a, Text_view b -> equal_text_view_props a b
  | Spin_button a, Spin_button b -> equal_spin_button_props a b
  | Scale a, Scale b -> equal_scale_props a b
  | Progress_bar a, Progress_bar b -> equal_progress_bar_props a b
  | Spinner a, Spinner b -> equal_spinner_props a b
  | Level_bar a, Level_bar b -> equal_level_bar_props a b
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
  | List_box a, List_box b -> equal_list_box_props a b
  | Flow_box a, Flow_box b -> equal_flow_box_props a b
  | Notebook a, Notebook b -> equal_notebook_props a b
  | Drop_down a, Drop_down b -> equal_drop_down_props a b
  | Calendar a, Calendar b -> equal_calendar_props a b
  | Editable_label a, Editable_label b -> equal_editable_label_props a b
  | Center_box a, Center_box b -> equal_center_box_props a b
  | Paned a, Paned b -> equal_paned_props a b
  | Overlay a, Overlay b -> equal_overlay_props a b
  | Header_bar a, Header_bar b -> equal_header_bar_props a b
  | Action_bar a, Action_bar b -> equal_action_bar_props a b
  | Popover a, Popover b -> equal_popover_props a b
  | Menu_button a, Menu_button b -> equal_menu_button_props a b
  | Window a, Window b -> equal_window_props a b
  | Windows, Windows -> true
  | Native a, Native b -> String.equal a.name b.name && phys_equal a.payload b.payload
  (* The one wildcard left in this file, and it is guarded rather than silent.

     It cannot be written out: avoiding it means 34 squared arms. What it {i can} do is
     tell the two cases apart. Two different kinds are genuinely not equal, and the
     patcher never asks -- it checks [same_kind] first -- but [Bonsai_gtk_test] and the
     odd test do. Two of the {i same} kind reaching here means an arm above is missing,
     which without this line would make every patch of that kind look like a prop change
     and re-run [update] forever (or, worse, be read as "props are equal, skip the update"
     by a caller that inverted it). Loud is better. *)
  | _ ->
    if same_kind a b
    then
      failwithf
        "Kind.equal_props: no arm for %s -- the variant gained a constructor and this \
         match did not"
        (name a)
        ()
    else false
;;
