open! Core
open Gtk_import

(** Installs [css] display-wide: one [GtkCssProvider] on the default display at
    application priority, its [prefers-color-scheme] mirrored from [GtkSettings] (and
    re-mirrored on change), so an [@media (prefers-color-scheme: dark)] block in [css]
    actually matches when the desktop is dark -- GTK 4.20+ evaluates that query per
    provider, and syncs only its own theme provider (the impl has the measurements).

    Raises [Failure] before GTK init, which is why [Loop.start] calls it from activate.
    Never removed: GTK accumulates providers, and a second [start] in one process re-adds
    one (the situation [Gtk_effect.For_start.set_app]'s warning covers). Returns the
    provider for the live suite's structural read-backs. *)
val install : css:string -> W.Css_provider.t
