open! Core
open Bonsai_gtk_vtree
open Gtk_import

(** A running Bonsai computation together with the GTK tree it renders into.

    This is the escape hatch under {!Bonsai_gtk.Expert}: {!Bonsai_gtk.start} is this plus
    a [GtkApplication] to own the main loop. Tests and embedders that already have a main
    loop (or want to drive frames by hand) use this directly. *)
type t

(** What the runtime will do with the root widget, and therefore what the root node is
    allowed to be. The two entry points are the two constructors, so neither can pass the
    other's rule by accident and each rejection message is written exactly once.

    - [`Window] — {!Bonsai_gtk.start}'s. The root {i must} be a [Node.window]: the
      application adds it and presents it, and nothing else can be shown on its own.
    - [`Not_window] — {!Bonsai_gtk.Expert.embed}'s. The root must be anything {i but} a
      [Node.window]: the result is parented into a container the caller owns, and a
      [GtkWindow] is a toplevel that cannot be parented. So the rule inverts rather than
      relaxes.

    Below the root the rule is the same for both and is the patcher's: a [Node.window]
    that is not the root is [Invalid_argument] wherever it appears — which, for a
    [`Not_window] tree, means anywhere at all. *)
type root_kind =
  [ `Window
  | `Not_window
  ]

(** Builds the driver but renders nothing: the first {!frame} mounts the tree.

    [root_kind] defaults to [`Window], which is {!Bonsai_gtk.start}'s rule and the one an
    escape-hatch caller who is showing a window wants. Pass [`Not_window] to render into a
    container someone else owns — or, more simply, use {!Bonsai_gtk.Expert.embed}, which
    is this plus the frame driving.

    [time_source] defaults to one started at [Time_ns.now ()] that each {!frame} advances
    to the current wall clock, which is what makes [Bonsai.Clock] work in a real app.
    Passing one in hands that control to the caller — the time source then only moves when
    the caller advances it, which is what tests want.

    [on_window_created] is called once per window node as it is mounted. Nothing else
    holds onto windows, so an implementation that drops them will leak them or never show
    them; {!Bonsai_gtk.start} adds them to the application and presents them.

    [on_root_widget_changed] is called with the root widget every time that widget becomes
    a {i different object}: once at the first {!frame}, which mounts it, and again on any
    frame where the root node changed kind and the patcher therefore mounted a replacement
    and destroyed the original. Whoever parented the old widget must re-parent the new one
    from here, or its container goes on holding a widget nothing renders into again — a
    page frozen on screen with no exception and no [broken].

    A [`Window] root never reaches the second case ([Kind.same_kind] always holds between
    two windows), which is why {!Bonsai_gtk.start} does not pass this and why the hazard
    appeared only with {!Bonsai_gtk.Expert.embed}: an embedded root is an arbitrary node,
    and a [Node.label "Loading…"] that becomes a [Node.box […]] once the data arrives is
    an ordinary page rather than a corner case. Defaults to doing nothing. *)
val create
  :  ?time_source:Bonsai.Time_source.t
  -> ?optimize:bool
  -> ?root_kind:root_kind
  -> ?on_root_widget_changed:(Widget.t -> unit)
  -> on_window_created:(Widget.t -> unit)
  -> (local_ Bonsai.graph -> Node.t Bonsai.t)
  -> t

(** One turn of the loop: advance the clock (unless the caller owns the time source),
    apply queued actions, and patch the GTK tree to the new result, then run lifecycles.

    A frame on which the computation returns the physically same node as the previous
    frame does not diff: it re-asserts the tree's controlled props and re-runs its fixups,
    which is the whole of what a no-change frame ever did. This is what makes an idle tick
    nearly free. It is not the same as skipping the frame, and must not become that: the
    frame on which a model declines a user's edit is exactly the frame whose view did not
    change, so it is the one that has to put the widget back. See [Patcher.reassert_only].

    Raises whatever the computation or the patcher raises — in particular
    [Invalid_argument] if the root node does not match this driver's [root_kind], or if a
    [Node.window] appears anywhere below the root. Under {!Bonsai_gtk.start} frames are
    driven by the scheduler, which logs the exception and stops the driver instead of
    raising; see {!broken}.

    Raises [Invalid_argument] if called after {!stop}.

    A frame that raises out of here marks the driver {!broken} on its way out and drops
    whatever that pass deferred, then re-raises. So the promise that nothing updates the
    tree again holds for hand-driven frames as well as for the scheduler's: once a frame
    has raised, later calls are no-ops rather than diffs against a half-patched shadow
    tree. *)
val frame : t -> unit

(** Queues [effect] and asks for a frame. This is the path every signal handler takes. A
    no-op once the driver is broken or {!stop}ped — in both cases nothing will ever read
    what was queued. *)
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

(** [true] once a frame has raised — whether the scheduler drove it or the caller did —
    which permanently stops this driver.

    A frame is not atomic — the patcher mutates GTK as it walks its ops and writes the
    shadow tree back only on success — so a frame that raises part-way leaves the two out
    of sync, and every later frame would diff against a tree that no longer describes GTK.
    Rather than repeat that (and the exception) at tick rate, the scheduler logs once and
    stops. The widgets stay on screen showing their last good state and the GTK main loop
    keeps running, so the window does not vanish; nothing updates it again. The fix is to
    the application. {!Bonsai_gtk.start} reports this as a non-zero exit status. *)
val broken : t -> bool

(** Marks this driver {!broken} without touching the widget tree, and removes the tick.

    For an embedder that learns from GTK — rather than from a frame that raised — that the
    tree it is rendering into must not be patched again. Unlike {!stop} it destroys
    nothing and invalidates nothing, because the widgets it would walk are exactly the
    ones that are in question; unlike a raising frame it costs no exception. Idempotent,
    and a no-op relative to {!stop} (a stopped driver already refuses frames).

    {!Bonsai_gtk.Expert.embed} connects this to its root widget's [destroy]. GTK's
    ordinary teardown does not emit that signal on a widget anything still holds a
    reference to — see {!Bonsai_gtk.Expert.Embedded} for what was measured — so this is a
    backstop for a host that disposes its children outright, not the normal path. *)
val mark_broken : t -> unit

(** Stops the scheduler, tears the widget tree down, invalidates the Bonsai computation's
    incremental observers, and drops [on_root_widget_changed]. The driver is dead
    afterwards: {!root_widget} is [None] and {!frame} raises. Build a new driver to render
    again. Idempotent.

    Dropping the callback matters because the driver itself is not collectable — its
    Bonsai graph stays reachable from Incremental's global state for the life of the
    process — so anything a callback of the caller's closes over would outlive the tree it
    belonged to. {!Bonsai_gtk.Expert.embed}'s closes over the wrapper it hands the
    embedder, and this is what makes "after [stop] you may drop it" true. *)
val stop : t -> unit
