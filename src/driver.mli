open! Core
open Bonsai_gtk_vtree
open Gtk_import

(** A running Bonsai computation together with the GTK tree it renders into.

    This is the escape hatch under {!Bonsai_gtk.Expert}: {!Bonsai_gtk.start} is this plus
    a [GtkApplication] to own the main loop. Tests and embedders that already have a main
    loop (or want to drive frames by hand) use this directly. *)
type t

(** Builds the driver but renders nothing: the first {!frame} mounts the tree.

    [time_source] defaults to one started at [Time_ns.now ()] that each {!frame} advances
    to the current wall clock, which is what makes [Bonsai.Clock] work in a real app.
    Passing one in hands that control to the caller — the time source then only moves when
    the caller advances it, which is what tests want.

    [on_window_created] is called once per window node as it is mounted. Nothing else
    holds onto windows, so an implementation that drops them will leak them or never show
    them; {!Bonsai_gtk.start} adds them to the application and presents them. *)
val create
  :  ?time_source:Bonsai.Time_source.t
  -> ?optimize:bool
  -> on_window_created:(Widget.t -> unit)
  -> (local_ Bonsai.graph -> Node.t Bonsai.t)
  -> t

(** One turn of the loop: advance the clock (unless the caller owns the time source),
    apply queued actions, and patch the GTK tree to the new result, then run lifecycles.

    Raises whatever the computation or the patcher raises — in particular
    [Invalid_argument] if the root node is not a [Node.window]. Under {!Bonsai_gtk.start}
    frames are driven by the scheduler, which logs instead. *)
val frame : t -> unit

(** Queues [effect] and asks for a frame. This is the path every signal handler takes. *)
val schedule_event : t -> unit Ui_effect.t -> unit

(** The root widget, or [None] before the first {!frame} (and after {!stop}). *)
val root_widget : t -> Widget.t option

(** Starts running a frame [fps] times a second, which is what services [Bonsai.Clock] and
    any after-display handlers.

    A non-positive [fps] installs no tick. Frames then happen when an effect is scheduled,
    plus a ~16 ms cadence for as long as the computation has an after-display handler
    registered — enough to keep those handlers running, and nothing at all at rest for a
    computation that has none.

    That cadence is not a substitute for the tick. The wall clock only advances inside a
    frame, so a computation built on [Bonsai.Clock] makes essentially no progress without
    a tick: it renders when something else causes a frame and otherwise sits still. *)
val start_tick : t -> fps:float -> unit

(** Stops the scheduler and tears the widget tree down. The Bonsai computation itself is
    left alone; the driver is simply not driving anything any more. *)
val stop : t -> unit
