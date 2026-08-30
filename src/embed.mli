open! Core
open Bonsai_gtk_vtree
open Gtk_import

(** A Bonsai computation rendering into a widget the caller parents.

    The counterpart to {!Bonsai_gtk.start}, for an application that already has a GTK main
    loop and a window and wants a Bonsai-rendered subtree inside it — porting a screen at
    a time rather than all at once, or embedding a declarative panel in an imperative app.
    {!Bonsai_gtk.start} is unchanged and stays the answer for an application that is
    bonsai_gtk all the way down.

    Three things differ from {!Bonsai_gtk.start}, and all three follow from "the caller
    owns the window":

    - The root node must {i not} be a [Node.window]: the result is parented into an
      existing container, and a [GtkWindow] is a toplevel that cannot be parented. (A
      [Node.window] below the root is rejected as it always is, which for an embedded tree
      means anywhere at all.) The message names {!Bonsai_gtk.start}, since a caller who
      returned a window from an embedded computation wanted the other entry point.
    - Nothing is parented for you. {!widget} is the root, and the caller puts it wherever
      its container puts children — [set_child], [append], [add_named], [insert_page],
      [insert]. That is why there is no "attach" here and no [~host] argument: there is no
      one call that covers them, and a container this code never writes to is a container
      it does not need to be handed.
    - {!stop} tears the tree down but does not unparent it. Remove it from your container
      yourself, before or after; the widget survives {!stop} as an ordinary widget and may
      then be dropped.

    Everything else is a windowed tree's: the same attribute and placement checks at the
    same points, the same [Invalid_argument] with the same paths, the same diagnostics,
    and the same "a frame that raised stops this driver for good" rule (see {!broken}).

    {2 Frames}

    [create] mounts the tree with one frame of its own and then installs a tick — a GLib
    timeout at [target_frames_per_second], on whatever main context the embedder is
    already running. It does not create a [GtkApplication] and does not run a main loop;
    both belong to the embedder.

    If no main loop is running the tick never fires and {!frame} is the only path, which
    is how a live test of an embedded tree works without one.

    Each [create] builds a driver of its own, so two embedded trees in one process have
    independent schedulers, independent ticks and independent broken-ness: one dying stops
    only itself. They share exactly what any two GLib users share — the main context the
    timeouts and idles are attached to.

    {2 What happens if the host is destroyed first}

    Nothing dangerous, which is worth stating precisely because it is not what "the parent
    was destroyed" usually means. The shadow tree holds a reference to every widget it
    built, so the embedded tree {i survives} its host: measured under GTK 4 with ocgtk,
    [gtk_window_destroy] on a host window emits no [destroy] on the tree below it and does
    not even unparent it, and an unparenting that does happen leaves every widget alive
    and still patchable. A frame after the host is gone is therefore not a use-after-free;
    it is a frame that patches a tree nobody can see.

    So the obligation embedding adds is about waste rather than safety: call {!stop}
    before you drop the host, or you keep a tick, a Bonsai graph and a whole widget tree
    alive for a page that is off screen for good.

    As a backstop, [create] connects to the root widget's [destroy] and calls
    {!Bonsai_gtk.Expert.Driver.mark_broken} from it, so an embedder that {i does} dispose
    the tree outright (rather than dropping the last reference to it) gets a driver that
    stops rather than one that patches disposed widgets. GTK's ordinary teardown never
    emits that signal on a widget something still holds a reference to, so this hook is
    quiet in every path measured; it is the cheap answer to the one path that is not. *)

type t

(** Builds the computation, mounts it with one frame, and starts the tick.

    Raises whatever that first frame raises — an [Invalid_argument] from a [Node]
    constructor, a window at the root, a misplaced placement attr — having first torn down
    whatever the failed mount had built, since a caller that got an exception instead of a
    [t] has no handle to {!stop}. *)
val create
  :  ?time_source:Bonsai.Time_source.t
  -> ?optimize:bool
  -> ?target_frames_per_second:float
  -> (local_ Bonsai.graph -> Node.t Bonsai.t)
  -> t

(** The root widget, for the caller to parent. Total, and the same widget for this [t]'s
    whole life: it is captured at mount, so it still answers after {!stop} — which is what
    lets the embedder remove it from its container in either order. *)
val widget : t -> Widget.t

(** One turn of the loop, by hand: what the tick does, for a caller that has no main loop
    or wants a frame at a moment of its own choosing. See
    {!Bonsai_gtk.Expert.Driver.frame} for what a frame is and what it raises; a frame that
    raises marks this embed {!broken} on its way out and then re-raises. Raises
    [Invalid_argument] if called after {!stop}. *)
val frame : t -> unit

(** Queues [effect] and asks for a frame, the way a signal handler inside the tree does. A
    no-op once this embed is {!broken} or {!stop}ped. *)
val schedule_event : t -> unit Ui_effect.t -> unit

(** [true] once a frame has raised — whether the tick drove it or the caller did — which
    permanently stops this embed, and also once the root's [destroy] has fired. The
    widgets stay exactly as they were; nothing renders into them again. Reported on stderr
    once, by the same scheduler that reports it for {!Bonsai_gtk.start}. *)
val broken : t -> bool

(** Stops the tick, tears the widget tree down and invalidates the Bonsai computation's
    incremental observers — everything {!Bonsai_gtk.Expert.Driver.stop} does.

    It does {i not} unparent {!widget}, because it did not parent it. Remove it from your
    container before or after this call; both orders are safe, and after it the widget is
    an ordinary GTK widget with nothing of Bonsai's attached, which the embedder may keep
    or drop.

    Idempotent. {!frame} afterwards raises. *)
val stop : t -> unit
