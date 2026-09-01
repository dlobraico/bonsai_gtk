open! Core

(** GTK's own default for every optional property in {!Node}, named once.

    Each of these is read from three places: the optional argument's default in [Node],
    the [@sexp_drop_if] on the matching [Kind] field -- which is what keeps a printed node
    about what the caller asked for rather than about the defaults -- and that field's
    mirror in [kind.mli]. Written out three times they drift silently, and the failure is
    quiet in the worst way: a default that moves in [Node] alone makes the sexp go on
    dropping a value the caller {i did} ask for, so the node prints as though the property
    were never set.

    Only properties whose absence has a value live here. An optional property whose [Kind]
    field is an [option] -- a label, an icon name, a placeholder -- defaults to [None] and
    is passed straight through, so there is nothing to keep in step. *)

module Label = struct
  let wrap = false
  let xalign = 0.5
  let max_width_chars = -1
  let width_chars = -1
  let selectable = false
  let use_markup = false
end

module Button = struct
  let has_frame = true
end

module Toggle_button = struct
  let has_frame = true
end

module Check_button = struct
  let inconsistent = false
end

module Entry = struct
  let editable = true
  let visibility = true
  let width_chars = -1
  let max_width_chars = -1
  let xalign = 0.
  let activates_default = false

  (* GTK's own [GtkEntry:max-length] default, and it is [0] rather than the [-1] the
     size-request properties above use: for a *limit* zero is the sentinel that means "no
     limit", and a negative value would be an error. *)
  let max_length = 0
end

module Password_entry = struct
  let show_peek_icon = true
  let activates_default = false
end

(* [digits] differs per class: GTK's [GtkSpinButton] shows whole numbers and its
   [GtkScale] one decimal. *)
module Spin_button = struct
  let step = 1.
  let digits = 0
  let numeric = true
  let wrap = false
  let activates_default = false
end

module Scale = struct
  let step = 1.
  let digits = 1
  let draw_value = true
  let has_origin = true
  let inverted = false
end

module Progress_bar = struct
  let show_text = false
  let inverted = false
end

module Image = struct
  let pixel_size = -1
  let icon_size = Icon_size.Inherit
end

module Picture = struct
  let content_fit = Content_fit.Contain
  let can_shrink = true
end

module Scrolled_window = struct
  let hpolicy = Policy.Automatic
  let vpolicy = Policy.Automatic
  let min_content_width = -1
  let min_content_height = -1
  let max_content_width = -1
  let max_content_height = -1
  let propagate_natural_width = false
  let propagate_natural_height = false
  let has_frame = false
  let kinetic_scrolling = true
  let overlay_scrolling = true
end

module Frame = struct
  let label_align = 0.
end

module Expander = struct
  let use_markup = false
end

module Revealer = struct
  let transition = Reveal_transition.None_
  let transition_duration = 250
end

module Box = struct
  let spacing = 0
  let homogeneous = false
end

module Grid = struct
  let row_spacing = 0
  let column_spacing = 0
  let row_homogeneous = false
  let column_homogeneous = false
end

module Stack = struct
  let transition = Stack_transition.None_
  let transition_duration = 200
  let hhomogeneous = true
  let vhomogeneous = true
end

(* GTK's own, read off a fresh [GtkNotebook]. Unlike the flow box's, none of these is a
   surprise -- tabs and border are drawn, the scrolling arrows are not, and the tabs are
   at the top -- which is worth saying out loud precisely because the two containers
   either side of it in this file both have a default a reader guesses wrong. *)
module Notebook = struct
  let scrollable = false
  let show_tabs = true
  let show_border = true
  let tab_pos = Tab_position.Top
end

(* GTK's own, read off a fresh [GtkTextView] rather than out of the docs, and two of the
   six are not the value a reader guesses: [cursor-visible] and [accepts-tab] are both
   [true], so a bare text view draws a caret even when it is not focused and swallows Tab
   rather than moving the focus on. The margins are GTK's [0] and are padding rather than
   margin, whatever their names say. *)
module Text_view = struct
  let wrap = Wrap_mode.None_
  let editable = true
  let monospace = false
  let cursor_visible = true
  let accepts_tab = true
  let left_margin = 0
  let right_margin = 0
  let top_margin = 0
  let bottom_margin = 0
end

(* GTK's own, and two of the three are worth stating out loud because they are not the
   value a reader guesses: a bare [GtkListBox] has [selection-mode] [SINGLE] (not [NONE])
   and [activate-on-single-click] [true]. *)
module List_box = struct
  let selection_mode = Selection_mode.Single
  let activate_on_single_click = true
  let show_separators = false
end

(* GTK's own, read off a fresh [GtkFlowBox] rather than out of the docs, and three of the
   seven are not the value a reader guesses. [selection_mode] is [SINGLE], as a list box's
   is. [activate_on_single_click] is [true] -- stavekeeper's library grid sets it to
   [false] on purpose, so that a single click selects a card and a double click opens it,
   which is the interaction a grid of cards wants and is not GTK's default.
   [max_children_per_line] is a real **7**, not "unlimited": an application that never
   mentions it gets seven per line however wide its window is. Confirmed live --
   [get_max_children_per_line] on a box nothing has touched answers 7. *)
module Flow_box = struct
  let selection_mode = Selection_mode.Single
  let activate_on_single_click = true
  let min_children_per_line = 0
  let max_children_per_line = 7
  let row_spacing = 0
  let column_spacing = 0
  let homogeneous = false
  let orientation = Orientation.Horizontal
end

module Center_box = struct
  let shrink_center_last = true
end

module Header_bar = struct
  let show_title_buttons = true
end

module Action_bar = struct
  let revealed = true
end

module Popover = struct
  let open_ = false
  let position = Position.Bottom
  let autohide = true
  let has_arrow = true
end

module Menu_button = struct
  let primary = false
  let always_show_arrow = false
end

(* GTK's own: a fresh [GtkWindow] is resizable and not modal, and is transient for
   nothing. [~transient_for] has no default here because [None] is not a value the model
   picked -- it is the absence of the prop, an ordinary option. *)
module Window = struct
  let modal = false
  let resizable = true
end

module Paned = struct
  let wide_handle = false
  let resize_start = true
  let resize_end = true
  let shrink_start = false
  let shrink_end = false
end

(* GTK's own, read off a fresh [GtkDropDown] rather than out of the docs. [show_arrow] is
   the one worth stating: it is [true], so a drop-down that never mentions it draws the
   arrow, and [~show_arrow:false] is for the case a drop-down is styled as a plain button.
   [enable_search] is [false], which is what a list of three modes wants. *)
module Drop_down = struct
  let enable_search = false
  let show_arrow = true
end

(* GTK's own, read off a fresh [GtkLevelBar]. All four are unsurprising -- a bar runs from
   0 to 1, draws one continuous block, and fills from the start edge -- which is worth
   saying because the two kinds either side of this one in [Kind.t] both have a default
   that is not what a reader guesses. *)
module Level_bar = struct
  let min = 0.
  let max = 1.
  let mode = Level_bar_mode.Continuous
  let inverted = false
end

(* GTK's own, read off a fresh [GtkCalendar]. Two of the three are [true]: a bare calendar
   draws its heading (the month and year, with the four walk buttons) and the row of
   weekday initials, and does {i not} draw the ISO week number column. So the two
   [~show_*] arguments a caller is likely to write are the ones that turn something off.

   There is no default for [~date]: it is a required labelled argument, for the reason the
   entries' [~text] is. A calendar built with no date shows {i today}, which is a value
   that changes underneath an application while it runs and which no model chose -- and
   the whole point of the controlled date is that the calendar shows what the model says.

   [marked_days] defaults to no marks, which is GTK's, and is an ordinary list rather than
   an option: there is no difference between "no marks" and "do not mention marks". *)
module Calendar = struct
  let show_day_names = true
  let show_heading = true
  let show_week_numbers = false
  let marked_days = ([] : int list)
end

(* GTK's own, and the only one there is: a [GtkEditableLabel] comes up showing its label
   rather than its entry. [~text] is required, like the entries'. *)
module Editable_label = struct
  let editing = false
end
