open! Core

(** Placeholder library interface. Task 11 adds the public API (and an mli); until then
    everything is under [Private], which carries no stability promise. *)
module Private = struct
  module Attr_apply = Attr_apply

  (* The library-wide [-open Core] shadows our [Debug] with [Core.Debug], so this one
     alias has to name the wrapped compilation unit explicitly. *)
  module Debug = Bonsai_gtk__Debug
  module Gtk_import = Gtk_import
  module Native_gtk = Native_gtk
  module Patcher = Patcher
  module Registry = Registry
  module Signals = Signals
  module Widget_impl = Widget_impl
end
