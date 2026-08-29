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

module Center_box = struct
  let shrink_center_last = true
end

module Paned = struct
  let wide_handle = false
  let resize_start = true
  let resize_end = true
  let shrink_start = false
  let shrink_end = false
end
