open! Core

(** Build GTK4 applications with Bonsai.

    An application is a function from a [Bonsai.graph] to a {!Node.t} describing the
    window to show. {!start} runs it: it opens the window, and every time the
    computation's result changes it patches the live GTK widgets to match rather than
    rebuilding them. *)

module Bonsai = Bonsai

(** The virtual tree an application returns. A node is a plain value — building one
    creates no widgets — so a computation may return a different one every frame. *)
module Node = Bonsai_gtk_vtree.Node

module Attr = Bonsai_gtk_vtree.Attr
module Key = Bonsai_gtk_vtree.Key
module Align = Bonsai_gtk_vtree.Align
module Orientation = Bonsai_gtk_vtree.Orientation

(** The escape hatch, for GTK widgets this library has no {!Node} constructor for. An
    application supplies the module that creates and updates the widget; the patcher
    treats it like any other node, keyed and diffed alongside the rest of the tree. *)
module Native : sig
  module type S = Native_gtk.S

  val node
    :  ?key:Key.t
    -> ?attrs:Attr.t list
    -> (module S with type input = 'a)
    -> 'a
    -> Node.t
end

(** [Ui_effect] plus {!Effect.quit}. *)
module Effect : sig
  include module type of struct
    include Ui_effect
  end

  (** Quits the application started by {!start}: the main loop returns and {!start} yields
      its exit status. Outside {!start} — under {!Expert.Driver}, or in a headless test —
      there is nothing to quit, so performing this logs and does nothing. *)
  val quit : unit t
end

(** Runs [app] as a [GtkApplication] and returns its exit status. Blocks until the last
    window is closed or an {!Effect.quit} is performed.

    [target_frames_per_second] (default 60) is how often a frame runs unprompted, which is
    what drives [Bonsai.Clock] and after-display handlers; frames caused by user
    interaction do not wait for it. Passing a [time_source] takes wall-clock advancement
    away from the library and hands it to the caller. *)
val start
  :  ?application_id:string
  -> ?time_source:Bonsai.Time_source.t
  -> ?optimize:bool
  -> ?target_frames_per_second:float
  -> (local_ Bonsai.graph -> Node.t Bonsai.t)
  -> int

(** For code that already owns a main loop, or wants to drive frames by hand. *)
module Expert : sig
  module Driver = Driver
end

(** No stability promise: this is what the library's own tests reach through. *)
module Private : sig
  module Attr_apply = Attr_apply
  module Debug = Bonsai_gtk__Debug
  module Gtk_import = Gtk_import
  module Native_gtk = Native_gtk
  module Patcher = Patcher
  module Registry = Registry
  module Scheduler = Scheduler
  module Signals = Signals
  module Widget_impl = Widget_impl
end
