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
    [Invalid_argument] if the root node is not a [Node.window], or if a [Node.window]
    appears anywhere below the root. Under {!Bonsai_gtk.start} frames are driven by the
    scheduler, which logs the exception and stops the driver instead of raising; see
    {!broken}.

    Raises [Invalid_argument] if called after {!stop}.

    Once a frame has raised ({!broken} is [true]) this is a no-op: the promise that
    nothing updates the tree again holds for hand-driven frames as well as for the
    scheduler's. *)
val frame : t -> unit

(** Queues [effect] and asks for a frame. This is the path every signal handler takes. A
    no-op once the driver is broken. *)
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

(** [true] once a scheduler-driven frame has raised, which permanently stops this driver.

    A frame is not atomic — the patcher mutates GTK as it walks its ops and writes the
    shadow tree back only on success — so a frame that raises part-way leaves the two out
    of sync, and every later frame would diff against a tree that no longer describes GTK.
    Rather than repeat that (and the exception) at tick rate, the scheduler logs once and
    stops. The widgets stay on screen showing their last good state and the GTK main loop
    keeps running, so the window does not vanish; nothing updates it again. The fix is to
    the application. {!Bonsai_gtk.start} reports this as a non-zero exit status. *)
val broken : t -> bool

(** Stops the scheduler, tears the widget tree down, and invalidates the Bonsai
    computation's incremental observers. The driver is dead afterwards: {!root_widget} is
    [None] and {!frame} raises. Build a new driver to render again. Idempotent. *)
val stop : t -> unit
