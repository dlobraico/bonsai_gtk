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
(* [Gtk_constants] is GTK's own top-level constants -- the only one this library reads is
   [invalid_list_position], the "nothing is selected" sentinel a [GtkDropDown] answers
   with -- and it sits beside [Gtk] rather than inside it, exactly as GDK's does. *)
module Gtk_constants = Ocgtk_gtk.Gtk_constants
module Gdk_enums = Ocgtk_gdk.Gdk_enums
module Gdk_constants = Ocgtk_gdk.Gdk_constants
module W = Gtk.Wrappers

(* GIO's list-model interface, which a [GtkDropDown]'s model is handed and read back
   through. It is in [ocgtk.gio] rather than [ocgtk.gtk], and it is aliased here for the
   reason everything else in this file is: so that no widget impl has to remember which
   library a GTK-facing type lives in. *)
module List_model = Ocgtk_gio.Gio.Wrappers.List_model

(* The GIO wrappers as a whole, for the action system ([src/actions.ml],
   [w_menu_button.ml]'s GMenu building): [Menu], [Menu_item], [Simple_action],
   [Simple_action_group], and the three interface casts ([Action], [Action_map],
   [Action_group]). Aliased for the reason everything here is. *)
module Gio = Ocgtk_gio.Gio.Wrappers

(* GVariant and its type strings live at the top level of ocgtk's common library, beside
   [Gobject] and [Glib]. *)
module Gvariant = Gvariant
module Gvariant_type = Gvariant_type

(* The GDK class wrappers, beside [W] for the same reason [Gio] sits here: today only the
   clipboard is reached ([Gdk.Clipboard.set_value] is the one write the binding has --
   fact table), and no widget impl should have to remember it lives in [ocgtk.gdk]. *)
module Gdk = Ocgtk_gdk.Gdk.Wrappers
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

(* The inverse of [modifiers_of_gdk], for the boundary that hands GDK a modifier set -- a
   shortcut trigger. Only the six real modifiers exist on the vtree side, so nothing here
   can produce the lock/button flags the forward direction drops. *)
let gdk_of_modifiers (m : Bonsai_gtk_vtree.Modifiers.t) : Gdk_enums.modifiertype =
  List.filter_map
    [ m.shift, `SHIFT_MASK
    ; m.control, `CONTROL_MASK
    ; m.alt, `ALT_MASK
    ; m.super, `SUPER_MASK
    ; m.hyper, `HYPER_MASK
    ; m.meta, `META_MASK
    ]
    ~f:(fun (on, flag) -> if on then Some flag else None)
;;

(* [GtkOrientable]'s enum, shared by the five kinds that take an orientation ([Box],
   [Separator], [Scale], [Paned], [Flow_box]). It was a private four-line copy in each of
   the first four before the fifth arrived, which is one copy past the point where the
   duplication stops being cheaper than the name. *)
let orientation : Bonsai_gtk_vtree.Orientation.t -> Gtk_enums.orientation = function
  | Horizontal -> `HORIZONTAL
  | Vertical -> `VERTICAL
;;

(* Shared by [w_list_box] and [w_flow_box]: [gtk_list_box_set_selection_mode] and
   [gtk_flow_box_set_selection_mode] take the same enum, and one converter with two
   callers is what {!Bonsai_gtk_vtree.Selection_mode} being one type already implies. *)
let selection_mode : Bonsai_gtk_vtree.Selection_mode.t -> Gtk_enums.selectionmode
  = function
  | None_ -> `NONE
  | Single -> `SINGLE
  | Browse -> `BROWSE
  | Multiple -> `MULTIPLE
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
