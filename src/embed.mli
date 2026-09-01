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
    - Nothing is parented into {i your} container for you. {!widget} is a container
      [embed] owns, holding the rendered tree; the caller puts it wherever its own
      container puts children — [set_child], [append], [add_named], [insert_page],
      [insert]. That is why there is no "attach" here: there is no one call that covers
      them.
    - {!stop} tears the tree down and empties the wrapper, but does not unparent the
      wrapper. Remove it from your container yourself, before or after.

    Everything else is a windowed tree's: the same attribute and placement checks at the
    same points, the same [Invalid_argument] with the same paths, the same diagnostics,
    and the same "a frame that raised stops this driver for good" rule (see {!broken}).

    {2 Why {!widget} is a wrapper rather than the rendered root}

    Because the root node's {i kind} may change between frames. [Node.label "Loading…"] on
    one frame and [Node.box […]] on the next is an ordinary page, and when that happens
    the patcher mounts a replacement widget and destroys the original. Had [embed] handed
    back the rendered root, a caller who did [stack#add_named (Embedded.widget e)] once at
    mount would afterwards be holding a widget nothing renders into again — no exception,
    no stderr line, [broken] still false, and the page frozen and inert on screen because
    its handlers have been disconnected.

    So [embed] owns exactly one container, hands you that, and moves the rendered root
    into it whenever the driver reports a new one. The wrapper is a [GtkOverlay] with the
    tree as its main child: measured, it is the only single-child container in GTK 4 that
    allocates its child exactly as the caller's own container would have — a box packs
    along its orientation and a grid packs into a cell, so both silently drop the child's
    alignment on that axis, while an overlay gives its main child the whole allocation, as
    [set_child] on a window or a stack page does. All of them forward [hexpand]/[vexpand];
    only the overlay also forwards [halign]/[valign]. It draws nothing and adds no CSS,
    but it {i is} a real widget and will show up in a [Live_tree] dump and in GTK
    Inspector.

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
    alive for a page that is off screen for good. It is a real obligation — an embed
    dropped without {!stop} is permanently unreclaimable, not merely late: the patcher's
    signal closures hold the runtime, which holds the shadow tree, which holds GObject
    references back, and neither the collector nor refcounting can break that cycle.
    {!stop} is what breaks it.

    As a backstop, [create] connects to the wrapper's [destroy] and calls
    {!Bonsai_gtk.Expert.Driver.mark_broken} from it, so an embedder that {i does} dispose
    the tree outright (rather than dropping the last reference to it) gets a driver that
    stops rather than one that patches disposed widgets. GTK's ordinary teardown never
    emits that signal on a widget something still holds a reference to, so this hook has
    no measured trigger; it is the cheap answer to the one path that is not covered by the
    paragraph above. {!stop} disconnects it, because a stopped embed's wrapper is exactly
    the one that {i does} get disposed — see {!stop}. *)

type t

(** Builds the computation, mounts it with one frame, and starts the tick.

    [target_frames_per_second] defaults to 60. A non-positive value installs no tick at
    all, exactly as it does for {!Bonsai_gtk.start} — frames then happen when an effect is
    scheduled, plus a ~16 ms cadence while the computation has an after-display handler
    registered, and {!frame} is the caller's to drive. See
    {!Bonsai_gtk.Expert.Driver.start_tick}.

    Raises whatever that first frame raises — an [Invalid_argument] from a [Node]
    constructor, a window at the root, a misplaced placement attr — having first torn down
    whatever the failed mount had built ({!Bonsai_gtk.Private.Patcher.mount} is
    exception-safe) and stopped the scheduler, since a caller that got an exception
    instead of a [t] has no handle to {!stop}.

    [global_css] is [Bonsai_gtk.start]'s (application-wide provider on the {b default}
    display -- the only one the binding's display-wide hook reaches -- with the color
    scheme mirrored from [GtkSettings]; never removed, so two embeds with one each add
    two). Installed here at [create]: the caller's GTK is up by this function's contract,
    so the raises-before-init hazard [start] dodges by waiting for activate does not
    arise. *)
val create
  :  ?time_source:Bonsai.Time_source.t
  -> ?optimize:bool
  -> ?target_frames_per_second:float
  -> ?global_css:string
  -> (local_ Bonsai.graph -> Node.t Bonsai.t)
  -> t

(** The container to parent. Total, and genuinely the same widget for this [t]'s whole
    life — including across a root-kind change and across {!stop}, which is what lets the
    embedder add it once and remove it whenever it likes. It is [embed]'s wrapper, not the
    rendered root; see the note above for why, and expect to see it in a [Live_tree] dump. *)
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
    permanently stops this embed, and also once the wrapper's [destroy] has fired. The
    widgets stay exactly as they were; nothing renders into them again. Reported on stderr
    once, by the same scheduler that reports it for {!Bonsai_gtk.start}.

    This is "did rendering fail", not "is this page healthy": a {!stop}ped embed is not
    broken and this answers [false] for one. A caller keeping an [Embedded.t option]
    should treat [None] as "torn down" rather than asking this. *)
val broken : t -> bool

(** Stops the tick, tears the widget tree down, invalidates the Bonsai computation's
    incremental observers — everything {!Bonsai_gtk.Expert.Driver.stop} does — and then
    unparents the rendered tree from {!widget}, leaving it an empty container.

    It does {i not} unparent {!widget} itself, because it did not parent it. Remove it
    from your container before or after this call; both orders are safe, and after it the
    wrapper is an ordinary empty GTK widget with nothing of Bonsai's attached, which the
    embedder may keep (to mount another embed's widget beside it) or drop. Dropping it is
    what actually releases the tree — see the note above; nothing else does.

    It also disconnects the [destroy] backstop, which is not tidiness: [stop] is what
    makes the wrapper collectable, so the next thing that can happen to a
    stopped-and-dropped one is GTK disposing it from inside OCaml's finalisation — and a
    [destroy] handler there would re-enter OCaml from the collector. Measured: left
    connected, the next [embed] after a stopped embed is dropped never returns.

    Idempotent. {!frame} afterwards raises.

    Raises only what tearing the tree down raises — a native node's [destroy], in practice
    — and the unparenting and the disconnect still happen when it does, before the
    exception goes up. So there is no need to call [stop] a second time after one raised,
    and a raise never leaves the tree parented in {!widget} with the backstop connected,
    which is the state the paragraph above calls unsafe. *)
val stop : t -> unit
