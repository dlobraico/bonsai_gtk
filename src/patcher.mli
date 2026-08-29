open! Core
open Bonsai_gtk_vtree
open Gtk_import

(** What the patcher needs from the app runtime, plus the two pieces of bookkeeping a
    single pass cannot do on its own. Build it with {!create_ctx} rather than as a record
    literal, so that the next field costs its callers nothing. *)
type ctx = private
  { signals : Signals.ctx
  ; on_window_created : Widget.t -> unit
  (** Called once per {!Bonsai_gtk_vtree.Kind.Window} node, after its subtree is attached.
      The runtime uses it to present the window (and to hold onto it: GTK windows are not
      owned by a parent widget). Called at mount only — a patched window is the same
      window. *)
  ; stacks : (string, Widget.t) Hashtbl.t
  (** The live [GtkStack]s of this tree, by their {!Bonsai_gtk_vtree.Node.stack} [~name].
      A [stack_switcher] cannot hold a widget — the vtree has no way to name one — so it
      names a stack, and the name is looked up here after the pass that mounted them both.
      Two stacks with one name is [Invalid_argument]. *)
  ; fixups : (unit -> unit) Queue.t
  (** Work deferred to the end of a mount or patch pass, so that a node may refer to
      another node regardless of which of them the walk reaches first, and so that a
      container may act on children that do not exist until the pass is over. Drained by
      {!run_fixups}. *)
  }

val create_ctx : signals:Signals.ctx -> on_window_created:(Widget.t -> unit) -> ctx

(** Runs everything the pass just finished deferred, then empties the queue — including
    when a fixup raises, since the queue describes one pass and carrying its work into the
    next frame would raise again from somewhere unrelated.

    The runtime calls this inside its reentrancy guard, immediately after the
    {!mount}/{!patch} of a frame; a test driving the patcher by hand must call it itself
    before reading back anything a fixup decides — a [stack_switcher]'s stack, or a
    stack's visible page.

    Raises [Invalid_argument] if a [stack_switcher] or [stack_sidebar] names a stack no
    node in the tree registered, naming both the switcher's path and the name it wanted. A
    raise abandons the rest of the queue — the fixups queued behind the failing one do not
    run, and are dropped with it — which matches the all-or-nothing a raising frame
    already has: the driver stops for good rather than carrying a half-applied pass
    forward.

    A fixup may not enqueue another; nothing needs to, and a queue that feeds itself is a
    hang. *)
val run_fixups : ctx -> unit

(** The shadow tree: one record per {!Bonsai_gtk_vtree.Node.t} currently realized, holding
    the GTK widget and everything needed to patch or tear it down. [node] is the node this
    widget was last rendered from, and is what the next {!patch} diffs against. *)
type live =
  { mutable node : Node.t
  ; widget : Widget.t
  ; impl : Widget_impl.t
  ; defaults : Attr_apply.defaults
  (** Read off the widget the instant it was created — after [create] applied the kind's
      props, before any attribute was — and kept for its lifetime: it is what an [Unset]
      op restores to. *)
  ; slots : Signals.slots
  ; handler_ids : Gobject.Signal.handler_id list
  ; mutable children : live Children.t
  }

(** Creates the widget for [node] and its whole subtree, attaching children to their
    parents. The returned [live] is *not* attached to anything: the caller parents it (or,
    for a window, presents it).

    [path] identifies the node for exception reporting; children extend it with their
    index. [is_root] must be [true] only for the node the runtime treats as the tree's
    root; every recursive call passes [false].

    Some of the work is deferred to {!run_fixups}, which the caller runs once the whole
    pass is done: a [stack_switcher] resolving the stack it names, and a stack selecting
    its visible page (which does not exist while the stack is being built).

    Raises [Invalid_argument] if a node has children its widget cannot hold, if a
    container rejects a child node — a {!Bonsai_gtk_vtree.Node.grid} child with no
    {!Bonsai_gtk_vtree.Attr.grid_cell}, a stack page with no key — or if a
    {!Bonsai_gtk_vtree.Kind.Window} node appears anywhere but the root — a [GtkWindow] is
    a toplevel and cannot be parented, so nesting one produces a GTK critical and a
    silently broken tree. *)
val mount : ctx -> path:string -> is_root:bool -> Node.t -> live

(** Diffs [node] against [live.node] and mutates the live tree to match.

    Props whose value changed are written by the impl's [update]; a {i controlled} prop
    (spec §6.5) is written by its [reassert] hook instead, which runs on every patch —
    because the patch where the model declined the user's change is exactly the patch
    where nothing in the tree moved. See {!Widget_impl.reassert}.

    Returns [live] itself when the root kind is unchanged (the common case; [live] has
    been updated in place). When the kind changed, the whole subtree is remounted and
    the *new* live is returned, with the old one already destroyed — the caller is
    responsible for re-parenting, since the patcher does not know where [live] was
    attached.

    Raises [Invalid_argument] if a node's children shape changed under an unchanged kind
    (e.g. a single-child container asked to hold a list), or if a window node appears
    off-root (see {!mount}). *)
val patch : ctx -> path:string -> is_root:bool -> live -> Node.t -> live

(** Tears [live] and its subtree down: empties the signal slots (so a signal GTK emits
    during teardown cannot reach a handler), disconnects, and lets native implementations
    release what they allocated. On the paths where the patcher unparents a subtree before
    destroying it, the slots of the whole subtree are emptied before the unparenting
    rather than here, so the guarantee holds in both orders. Windows are destroyed
    outright; any other widget is merely detached from Bonsai and is expected to be
    unparented by the caller (or by its parent going away). *)
val destroy : ctx -> live -> unit
