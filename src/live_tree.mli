open! Core
open Gtk_import

(** A sexp of the *live* GTK tree under [w] — what GTK actually holds, read back from the
    widgets themselves rather than from the shadow tree. Used by the live tests to check
    that the patcher's idea of the tree and GTK's agree.

    The shape is [(GtkType <props> (children ...))]. Props are whichever of text / label /
    title / spacing apply to the type, then the css classes, then the widget-wide layout
    properties {!Bonsai_gtk_vtree.Attr} can set (margins, halign/valign, hexpand/vexpand,
    tooltip, size request), then [hidden] and [insensitive]. Everything after the css
    classes is printed only when it differs from GTK's default, so a dump shows what the
    attributes actually did and unsetting an attribute shows up as the property
    disappearing. Internal widgets GTK creates for itself (a button's label, for instance)
    show up as children like any other. *)
val dump : Widget.t -> Sexp.t
