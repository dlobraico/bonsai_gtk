open! Core
open Bonsai_gtk_vtree
open Gtk_import

(** Every attribute value [unset] can restore, read off a widget before anything has been
    applied to it. Take one per widget at creation and keep it for the widget's lifetime;
    it is what makes "drop this attribute" mean "put back whatever GTK had", which differs
    per widget class ([focusable] on a button vs a label, [visible] on a window vs
    anything else) and which no constant could get right for all of them. *)
type defaults

(** Call once, on a freshly created widget, before any attribute has been applied. *)
val snapshot : Widget.t -> defaults

(** Applies one attribute diff op from {!Attrs.diff} to a live widget.

    [Unset] restores the value [defaults] recorded for that attribute. [Width_request] and
    [Height_request] share GTK's single [set_size_request] setter, so each one reads the
    current pair back with [get_size_request] and rewrites only its own half; unsetting
    one leaves the other in place.

    [Test_id] and [On_clicked] have no GTK effect here: the former is inspected by the
    headless test handle, the latter is owned by {!Signals}. *)
val apply : defaults:defaults -> Widget.t -> Attrs.op -> unit

(** Applies every attribute of [t] to a freshly created widget. Equivalent to [apply]ing
    [Set] for each attr in [Attrs.to_list], which includes the css classes. *)
val apply_all : Widget.t -> Attrs.t -> unit
