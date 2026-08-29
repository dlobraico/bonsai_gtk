open! Core
open Bonsai_gtk_vtree
open Gtk_import

(** Applies one attribute diff op from {!Attrs.diff} to a live widget.

    [Unset] restores the GTK default for that attribute. [Width_request] and
    [Height_request] share GTK's single [set_size_request] setter, so each one reads the
    current pair back with [get_size_request] and rewrites only its own half; unsetting
    one leaves the other in place.

    [Test_id] and [On_clicked] have no GTK effect here: the former is inspected by the
    headless test handle, the latter is owned by {!Signals}. *)
val apply : Widget.t -> Attrs.op -> unit

(** Applies every attribute of [t] to a freshly created widget. Equivalent to [apply]ing
    [Set] for each attr in [Attrs.to_list], which includes the css classes. *)
val apply_all : Widget.t -> Attrs.t -> unit
