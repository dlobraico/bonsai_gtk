open! Core

(** Every reference to ocgtk in this library goes through this module. Note that
    [Ocgtk_gtk.Gtk] must never be [open]ed directly: it shadows [unit] (among other
    things) with a GTK class name. *)

module Gtk = Ocgtk_gtk.Gtk
module Gtk_enums = Ocgtk_gtk.Gtk_enums

(* GDK is not shaped like GTK, and forgetting that costs ten minutes each time: the class
   modules live under [Ocgtk_gdk.Gdk.Wrappers] (as [Ocgtk_gtk.Gtk.Wrappers] holds GTK's),
   but the enums and the constants are *top-level* in [Ocgtk_gdk] -- there is no
   [Ocgtk_gdk.Gdk.Gdk_enums]. Aliased here so the rest of the library never has to
   remember which. *)
module Gdk_enums = Ocgtk_gdk.Gdk_enums
module Gdk_constants = Ocgtk_gdk.Gdk_constants
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

(* GDK reports the modifier state as a list of polymorphic variants, which [vtree] may not
   name (it does not link ocgtk), so the boundary converts it into the plain record of
   bools an application actually asks questions of.

   [`LOCK_MASK] and the five [`BUTTONn_MASK]s GDK also puts in this list are dropped on
   purpose: they are pointer and keyboard *state* rather than modifiers a shortcut is
   keyed on, and [Modifiers] says so. [`NO_MODIFIER_MASK] never appears --
   [modifiertype_of_int 0] is the empty list -- but is listed rather than wildcarded so
   that a GDK flag added later is a compile error here instead of a silent drop.

   [`ALT_MASK] is GDK4's spelling of what GDK3 called MOD1. *)
let modifiers_of_gdk (state : Gdk_enums.modifiertype) : Bonsai_gtk_vtree.Modifiers.t =
  List.fold
    state
    ~init:Bonsai_gtk_vtree.Modifiers.none
    ~f:(fun (acc : Bonsai_gtk_vtree.Modifiers.t) flag ->
      match flag with
      | `SHIFT_MASK -> { acc with shift = true }
      | `CONTROL_MASK -> { acc with control = true }
      | `ALT_MASK -> { acc with alt = true }
      | `SUPER_MASK -> { acc with super = true }
      | `HYPER_MASK -> { acc with hyper = true }
      | `META_MASK -> { acc with meta = true }
      | `NO_MODIFIER_MASK
      | `LOCK_MASK
      | `BUTTON1_MASK
      | `BUTTON2_MASK
      | `BUTTON3_MASK
      | `BUTTON4_MASK
      | `BUTTON5_MASK -> acc)
;;

(* [Phase.Capture] is what a window-wide Escape handler wants and [Bubble] is GTK's own
   default; GTK's [`NONE] has no spelling in {!Phase} because a controller in that phase
   never fires, which omitting the attribute already says. *)
let propagation_phase (phase : Bonsai_gtk_vtree.Phase.t) : Gtk_enums.propagationphase =
  match phase with
  | Capture -> `CAPTURE
  | Bubble -> `BUBBLE
  | Target -> `TARGET
;;
