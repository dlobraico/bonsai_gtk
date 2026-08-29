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
module Grid_cell = Bonsai_gtk_vtree.Grid_cell
module Orientation = Bonsai_gtk_vtree.Orientation

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
end

(** No stability promise: this is what the library's own tests reach through. *)
module Private = struct
  module Attr_apply = Attr_apply
  module Gtk_import = Gtk_import
  module Live_tree = Live_tree
  module Native_gtk = Native_gtk
  module Patcher = Patcher
  module Registry = Registry
  module Scheduler = Scheduler
  module Signals = Signals
  module W_button = W_button
  module Widget_impl = Widget_impl
end
