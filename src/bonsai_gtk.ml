open! Core
module Bonsai = Bonsai
module Node = Bonsai_gtk_vtree.Node
module Attr = Bonsai_gtk_vtree.Attr
module Key = Bonsai_gtk_vtree.Key
module Align = Bonsai_gtk_vtree.Align
module Orientation = Bonsai_gtk_vtree.Orientation

module Native = struct
  module type S = Native_gtk.S

  let node = Native_gtk.node
end

module Effect = Bonsai_gtk__Effect

let start = Loop.start

module Expert = struct
  module Driver = Driver
end

(** No stability promise: this is what the library's own tests reach through. *)
module Private = struct
  module Attr_apply = Attr_apply

  (* The library-wide [-open Core] shadows our [Debug] with [Core.Debug], so this one
     alias has to name the wrapped compilation unit explicitly. *)
  module Debug = Bonsai_gtk__Debug
  module Gtk_import = Gtk_import
  module Native_gtk = Native_gtk
  module Patcher = Patcher
  module Registry = Registry
  module Scheduler = Scheduler
  module Signals = Signals
  module Widget_impl = Widget_impl
end
