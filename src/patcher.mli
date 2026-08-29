open! Core
open Bonsai_gtk_vtree
open Gtk_import

(** What the patcher needs from the app runtime. *)
type ctx =
  { signals : Signals.ctx
  ; on_window_created : Widget.t -> unit
  (** Called once per {!Bonsai_gtk_vtree.Kind.Window} node, after its subtree is attached.
      The runtime uses it to present the window (and to hold onto it: GTK windows are not
      owned by a parent widget). *)
  }

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

    Raises [Invalid_argument] if a node has children its widget cannot hold, or if a
    {!Bonsai_gtk_vtree.Kind.Window} node appears anywhere but the root — a [GtkWindow] is
    a toplevel and cannot be parented, so nesting one produces a GTK critical and a
    silently broken tree. *)
val mount : ctx -> path:string -> is_root:bool -> Node.t -> live

(** Diffs [node] against [live.node] and mutates the live tree to match.

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
