open! Core

(** Build GTK4 applications with Bonsai.

    An application is a function from a [Bonsai.graph] to a {!Node.t} describing the
    window to show. {!start} runs it: it opens the window, and every time the
    computation's result changes it patches the live GTK widgets to match rather than
    rebuilding them. *)

module Bonsai = Bonsai

(** A live GTK widget — ocgtk's [Gtk.Wrappers.Widget.t], which is what {!Native.S} builds
    and what {!Expert.Driver} hands back. Exposed so those signatures name a type
    applications can write down. *)
module Widget = Gtk_import.Widget

(** The virtual tree an application returns. A node is a plain value — building one
    creates no widgets — so a computation may return a different one every frame. *)
module Node = Bonsai_gtk_vtree.Node

module Attr = Bonsai_gtk_vtree.Attr
module Key = Bonsai_gtk_vtree.Key
module Align = Bonsai_gtk_vtree.Align
module Ellipsize = Bonsai_gtk_vtree.Ellipsize
module Content_fit = Bonsai_gtk_vtree.Content_fit
module Icon_size = Bonsai_gtk_vtree.Icon_size
module Image_source = Bonsai_gtk_vtree.Image_source
module Picture_source = Bonsai_gtk_vtree.Picture_source
module Orientation = Bonsai_gtk_vtree.Orientation

(** The escape hatch, for GTK widgets this library has no {!Node} constructor for. An
    application supplies the module that creates and updates the widget; the patcher
    treats it like any other node, keyed and diffed alongside the rest of the tree. *)
module Native : sig
  module type S = Native_gtk.S

  (** An implementation plus the type witness that lets the patcher recover its [input]
      from a node. Build it once, at the top level of the module that defines the widget,
      and reuse that value: two [impl]s made from the same module are different widgets as
      far as the patcher is concerned. *)
  type 'a impl = 'a Native_gtk.impl

  val impl : (module S with type input = 'a) -> 'a impl
  val node : ?key:Key.t -> ?attrs:Attr.t list -> 'a impl -> 'a -> Node.t

  (** The library's own {!node}: a [GtkPicture] fed a [GdkPaintable]. It ships here rather
      than as a [Node] constructor because its input is an ocgtk value, which the vtree
      may not name -- and it is the worked example an application copies. *)
  module Picture = Paintable_picture
end

(** [Ui_effect] plus {!Effect.quit}. *)
module Effect : sig
  include module type of struct
    include Ui_effect
  end

  (** Quits the application started by {!start}: the main loop returns and {!start} yields
      its exit status. This targets whichever application {!start} is currently running —
      the library supports one per process. Outside {!start} — under {!Expert.Driver}, in
      a headless test, or after {!start} has returned — there is nothing to quit, so
      performing this logs and does nothing. *)
  val quit : unit t
end

(** Runs [app] as a [GtkApplication] and returns its exit status. Blocks until the last
    window is closed or an {!Effect.quit} is performed.

    One application per process: {!Effect.quit} finds the running application through a
    single reference the library holds for the duration of the call, so two overlapping
    [start]s would fight over it (the second warns on stderr).

    [target_frames_per_second] (default 60) is how often a frame runs unprompted, which is
    what drives [Bonsai.Clock] and after-display handlers; frames caused by user
    interaction do not wait for it. A non-positive value installs no tick at all: frames
    then happen on interaction, plus a ~16 ms cadence for as long as the computation has
    an after-display handler to service — which keeps those handlers alive but does not
    stand in for the tick, since [Bonsai.Clock] only advances inside a frame. Passing a
    [time_source] takes wall-clock advancement away from the library and hands it to the
    caller.

    Returns GTK's exit status, or a non-zero status of its own if building the computation
    or rendering its first frame raised — an application that never opened a window does
    not report success.

    An exception raised by any later frame is logged once and stops the driver for good:
    the window stays on screen at its last good state and the main loop keeps running (so
    the app does not vanish under the user), but nothing renders into it again and [start]
    returns a non-zero status. A frame is not atomic — the patcher mutates GTK as it goes
    and records what it did only on success — so continuing after one raised would mean
    diffing against a tree that no longer describes GTK. A raising frame is an application
    bug to fix, not a condition to recover from. *)
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
  module Gtk_import = Gtk_import
  module Live_tree = Live_tree
  module Native_gtk = Native_gtk
  module Patcher = Patcher
  module Registry = Registry
  module Scheduler = Scheduler
  module Signals = Signals
  module W_button = W_button
  module Widget_impl = Widget_impl
end
