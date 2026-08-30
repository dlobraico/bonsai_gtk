open! Core
module Bonsai = Bonsai
module Widget = Gtk_import.Widget
module Node = Bonsai_gtk_vtree.Node
module Attr = Bonsai_gtk_vtree.Attr
module Key = Bonsai_gtk_vtree.Key
module Align = Bonsai_gtk_vtree.Align
module Ellipsize = Bonsai_gtk_vtree.Ellipsize
module Content_fit = Bonsai_gtk_vtree.Content_fit
module Icon_size = Bonsai_gtk_vtree.Icon_size
module Image_source = Bonsai_gtk_vtree.Image_source
module Picture_source = Bonsai_gtk_vtree.Picture_source
module Policy = Bonsai_gtk_vtree.Policy
module Reveal_transition = Bonsai_gtk_vtree.Reveal_transition
module Stack_transition = Bonsai_gtk_vtree.Stack_transition
module Tab_position = Bonsai_gtk_vtree.Tab_position
module Wrap_mode = Bonsai_gtk_vtree.Wrap_mode
module Selection_mode = Bonsai_gtk_vtree.Selection_mode
module Level_bar_mode = Bonsai_gtk_vtree.Level_bar_mode
module Grid_cell = Bonsai_gtk_vtree.Grid_cell
module Orientation = Bonsai_gtk_vtree.Orientation
module Phase = Bonsai_gtk_vtree.Phase
module Modifiers = Bonsai_gtk_vtree.Modifiers
module Click_event = Bonsai_gtk_vtree.Click_event
module Keyval = Bonsai_gtk_vtree.Keyval
module Key_event = Bonsai_gtk_vtree.Key_event
module Key_response = Bonsai_gtk_vtree.Key_response

module Native = struct
  module type S = Native_gtk.S

  type 'a impl = 'a Native_gtk.impl

  let impl = Native_gtk.impl
  let node = Native_gtk.node

  module Picture = Paintable_picture
end

module Effect = Gtk_effect

let start = Loop.start

module Expert = struct
  module Driver = Driver
  module Embedded = Embed

  let embed = Embed.create
end

(** No stability promise: this is what the library's own tests reach through. *)
module Private = struct
  module Attr_apply = Attr_apply
  module Controllers = Controllers
  module Gtk_import = Gtk_import
  module Live_tree = Live_tree
  module Native_gtk = Native_gtk
  module Patcher = Patcher
  module Registry = Registry
  module Scheduler = Scheduler
  module Signals = Signals
  module W_button = W_button
  module W_calendar = W_calendar
  module W_drop_down = W_drop_down
  module W_list_box = W_list_box
  module W_flow_box = W_flow_box
  module W_notebook = W_notebook
  module W_text_view = W_text_view
  module Widget_impl = Widget_impl
end
