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
  ; report : node_path:string -> string -> unit
  (** Where a diagnostic that is {i not} an exception goes: the model asked for something
      the widget cannot hold, the frame carries on, and somebody has to be told. Today's
      only caller is a {!Bonsai_gtk_vtree.Node.text_view} whose [~text] GTK will not store
      (see {!Bonsai_gtk_vtree.Node.text_view}); it is a hook rather than an [eprintf] at
      the call site so that a test can capture the message instead of racing stderr
      against a golden, and so that a later milestone can route these somewhere an
      application can see.

      Distinct from {!Signals.ctx.on_exn}, which reports an exception raised while
      {i dispatching} a signal — and which a widget impl cannot reach in any case. *)
  ; stacks : (string, Widget.t) Hashtbl.t
  (** The live [GtkStack]s of this tree, by their {!Bonsai_gtk_vtree.Node.stack} [~name].
      A [stack_switcher] cannot hold a widget — the vtree has no way to name one — so it
      names a stack, and the name is looked up here after the pass that mounted them both.
      Two stacks with one name is [Invalid_argument]. *)
  ; stack_claims : stack_claim Queue.t
  (** The stack names this pass is taking, and the ones its stacks are giving up, applied
      to [stacks] at the end of the {!mount} or {!patch} that collected them — removals
      first, then additions. Two loops rather than one because a *swap* is legal: two
      stacks exchanging names in one frame would otherwise collide with each other. Empty
      between passes. *)
  ; fixups : (unit -> unit) Queue.t
  (** Work deferred to the end of a mount or patch pass, so that a node may refer to
      another node regardless of which of them the walk reaches first, and so that a
      container may act on children that do not exist until the pass is over. Drained by
      {!run_fixups}. *)
  }

and stack_claim = private
  { claim_path : string
  ; give_up : string option
  ; take : string
  ; claimant : Widget.t
  }

(** [report] defaults to an [eprintf] on the library's usual [bonsai_gtk: ] channel; pass
    one to capture the messages instead. The trailing [unit] is what makes the optional
    argument reachable. *)
val create_ctx
  :  ?report:(node_path:string -> string -> unit)
  -> signals:Signals.ctx
  -> on_window_created:(Widget.t -> unit)
  -> unit
  -> ctx

(** Runs everything the pass just finished deferred, then empties the queue — including
    when a fixup raises, since the queue describes one pass and carrying its work into the
    next frame would raise again from somewhere unrelated.

    The runtime calls this inside its reentrancy guard, immediately after the
    {!mount}/{!patch} of a frame; a test driving the patcher by hand must call it itself
    before reading back anything a fixup decides — a [stack_switcher]'s stack, or a
    stack's visible page.

    Raises [Invalid_argument] if a [stack_switcher] or [stack_sidebar] names a stack no
    node in the tree registered, naming both the switcher's path and the name it wanted,
    and if a {!Bonsai_gtk_vtree.Node.stack} that has at least one page gives a
    [~visible_child] naming none of them, naming the stack's path and the page names it
    does have. That second one can only be decided here: [create], [update] and [reassert]
    all run while the stack is still being built, so a page that is not there yet and one
    that is never coming look the same to them; by the time this runs the whole tree
    exists. A raise abandons the rest of the queue — the fixups queued behind the failing
    one do not run, and are dropped with it — which matches the all-or-nothing a raising
    frame already has: the driver stops for good rather than carrying a half-applied pass
    forward.

    A fixup may not enqueue another; nothing needs to, and a queue that feeds itself is a
    hang. *)
val run_fixups : ctx -> unit

(** Drops everything the pass deferred, running none of it, and the stack names it had not
    yet claimed.

    For the pass that raised out of {!mount} or {!patch} and so never reached
    {!run_fixups}: its queue describes a tree that was only half built, and the closures
    in it pin the widgets they captured. The runtime calls this on the way out of a frame
    that raised. *)
val abandon_fixups : ctx -> unit

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
  ; connections : Signals.connection list
  ; controllers : Controllers.t
  (** The event controllers this node's attributes ask for — a [GtkGestureClick] for
      {!Bonsai_gtk_vtree.Attr.on_click], a [GtkEventControllerFocus] for the focus pair.
      Unlike [slots], which is fixed at mount, this changes shape as the attrs do: a
      controller is attached on the frame its first attr appears and removed on the frame
      its last one goes. *)
  ; mutable children : live Children.t
  }

(** Creates the widget for [node] and its whole subtree, attaching children to their
    parents. The returned [live] is *not* attached to anything: the caller parents it (or,
    for a window, presents it).

    [path] identifies the node for exception reporting; children extend it with their
    index. [is_root] must be [true] only for the node the runtime treats as the tree's
    root; every recursive call passes [false]. It says {i where} the node is, not what it
    is allowed to be: it exempts the root from the below-the-root window rule below, and
    whether a window is legal {i there} is the runtime's — see
    {!Bonsai_gtk.Expert.Driver.root_kind}, which requires one under [Bonsai_gtk.start] and
    refuses one under [Bonsai_gtk.Expert.embed], and does so before this is reached. So an
    embedded root is passed [~is_root:true] like any other root, and the window it may not
    be has already been rejected with a better message than this file could give.

    Some of the work is deferred to {!run_fixups}, which the caller runs once the whole
    pass is done: a [stack_switcher] resolving the stack it names, and a stack selecting
    its visible page (which does not exist while the stack is being built).

    Raises [Invalid_argument] if a node has children its widget cannot hold, if a
    container rejects a child node — a {!Bonsai_gtk_vtree.Node.grid} child with no
    {!Bonsai_gtk_vtree.Attr.grid_cell}, a stack page with no key — if a child carries a
    container-placement attribute its parent does not read
    ({!Bonsai_gtk_vtree.Attr.grid_cell} on a box child,
    {!Bonsai_gtk_vtree.Attr.page_title} outside a stack), or if a
    {!Bonsai_gtk_vtree.Kind.Window} node appears anywhere but the root — a [GtkWindow] is
    a toplevel and cannot be parented, so nesting one produces a GTK critical and a
    silently broken tree.

    Placement attributes are checked here rather than by [Attr_apply], which sees a child
    without knowing its parent, or by the constructor, which cannot know either. Nothing
    applies them to the child, so a misplaced one has no other diagnostic at all. *)
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

    Raises [Invalid_argument] on everything {!mount} does — the placement-attribute check
    runs on every node of every pass, so an attr a frame *adds* is rejected on the frame
    that adds it — and additionally if a node's children shape changed under an unchanged
    kind (e.g. a single-child container asked to hold a list). *)
val patch : ctx -> path:string -> is_root:bool -> live -> Node.t -> live

(** Re-applies every controlled prop in [live]'s subtree and re-enqueues the fixups the
    same tree would enqueue, without diffing anything.

    For the frame on which the computation hands back the physically same {!Node.t} it
    handed back last frame. Nothing in the tree can have changed — it is the same value —
    so there is no [update] to run, no attr diff to compute and no child list to
    reconcile. What is left, and what a full {!patch} of that frame was really doing, is
    the two halves of the controlled-prop rule (spec §6.5): {!Widget_impl.reassert} and
    the deferred selections. That matters because a model which {i declines} a user's edit
    renders exactly what it rendered before, so the frame with nothing to diff is the very
    frame on which the widget has to be put back.

    The caller runs {!run_fixups} afterwards, exactly as it does after a {!mount} or a
    {!patch}, and inside the same reentrancy guard. [live.node] is left alone (it is
    already the node that was rendered), so a later frame that does change something still
    diffs against what is really on screen. Raises whatever a [reassert] raises.

    [path] identifies the root of the walk for exception reporting, the same as
    {!mount}'s. *)
val reassert_only : ctx -> path:string -> live -> unit

(** Tears [live] and its subtree down: empties the signal slots (so a signal GTK emits
    during teardown cannot reach a handler), disconnects, removes and disconnects the
    event controllers, and lets native implementations release what they allocated. On the
    paths where the patcher unparents a subtree before destroying it, the slots of the
    whole subtree — the widgets' own and their controllers' — are emptied before the
    unparenting rather than here, so the guarantee holds in both orders. Windows are
    destroyed outright; any other widget is merely detached from Bonsai and is expected to
    be unparented by the caller (or by its parent going away). *)
val destroy : ctx -> live -> unit
