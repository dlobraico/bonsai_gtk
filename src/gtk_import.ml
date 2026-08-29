open! Core

(** Every reference to ocgtk in this library goes through this module. Note that
    [Ocgtk_gtk.Gtk] must never be [open]ed directly: it shadows [unit] (among other
    things) with a GTK class name. *)

module Gtk = Ocgtk_gtk.Gtk
module Gtk_enums = Ocgtk_gtk.Gtk_enums
module W = Gtk.Wrappers
module Widget = W.Widget
module Gobject = Gobject
module Glib = Glib

(** Downcast. Upcasts do not need this: [Gobject.obj] is contravariant in its phantom row,
    so [(button :> Widget.t)] is a plain coercion. *)
let cast = Gobject.unsafe_cast

(** The live GTK children of [w], in order. *)
let widget_children (w : Widget.t) : Widget.t list =
  let rec go acc = function
    | None -> List.rev acc
    | Some c -> go (c :: acc) (Widget.get_next_sibling c)
  in
  go [] (Widget.get_first_child w)
;;

let type_name (w : Widget.t) = Gobject.Type.name (Gobject.get_type w)
