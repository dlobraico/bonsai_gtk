open! Core
open Bonsai_gtk_vtree
open Gtk_import

(** What a signal trampoline needs from the app runtime. *)
type ctx =
  { schedule : unit Ui_effect.t -> unit
  (** Hand a fired handler's effect to the Bonsai driver. *)
  ; in_patch : unit -> bool
  (** [true] while the patcher is mutating the widget tree. GTK emits signals
      synchronously from calls like [set_child]/[remove], and re-entering Bonsai from
      inside a patch would corrupt it, so callbacks are dropped then. *)
  ; on_exn : node_path:string -> exn -> unit
  (** Reports an exception raised while dispatching. Must not raise; if it does, the
      trampoline swallows it. *)
  }

(** One connected GTK handler: the id, and the object it is connected {i to}.

    Both halves are needed, and the second is the one that is easy to lose.
    [g_signal_handler_disconnect] takes the object the id was issued for, and a handler id
    is only unique per object — so disconnecting from the widget an id that belongs to
    some other GObject is at best a GLib critical and at worst disconnects an unrelated
    handler that happens to share the number, leaving the real one connected and its slot
    pinned alive as a GC root. *)
type connection

(** [connected obj id] pairs the id a connection returned with the object it was made on.
    Every {!spec.connect} ends in this. *)
val connected : 'a Gobject.obj -> Gobject.Signal.handler_id -> connection

(** One GTK signal a widget impl knows how to connect, and the attr that carries its
    handler. *)
type spec =
  { attr : Attr.Name.t
  ; connect : Widget.t -> callback:(unit -> unit) -> connection
  (** Connect [callback] and return the resulting {!connection}.

      The object connected to need {i not} be the widget: it is whatever GObject actually
      emits the signal — a [GtkEditable] delegate, and in later milestones a
      [GtkTextBuffer], a list model, or an event controller attached to the widget. What
      is required is that the returned {!connection} name that object, because that is
      what teardown disconnects from. Build it with {!connected} and the returned id,
      never by pairing an id with a different object. *)
  ; fire : Widget.t -> Attr.t -> unit Ui_effect.t option
  (** Turn the attr currently in the slot into the effect to schedule. [None] if the attr
      is not the one this spec handles, or if this particular emission is not one the
      application should hear about — a [GtkSearchEntry]'s debounced [search-changed]
      arriving after a write the library itself made, say.

      The widget is passed because GTK's callbacks mostly carry no payload — the value the
      user just changed lives on the widget — so a handler that takes an argument builds
      it by reading the property back with the class getter (spec §6.4). That is the only
      way to build one at all for the [notify::] family, whose generic marshaller carries
      nothing. *)
  }

(** The mutable cells the connected callbacks read their handler out of. Kept per widget
    for the widget's lifetime: GTK handlers are connected exactly once, at creation, and a
    re-render only rewrites the cells. *)
type slots

(** Connects every spec to [w], returning the slots and the connections to {!disconnect}
    on destruction. The slots start empty, so callbacks are inert until the first
    {!update_slots} — call it with the node's attrs right after creating the widget.

    Each callback is exception-guarded: nothing raised by [in_patch], [fire], or
    [schedule] escapes into GTK's C frame. *)
val connect_all
  :  ctx
  -> node_path:string
  -> Widget.t
  -> spec list
  -> slots * connection list

(** Points each slot at the matching attr in [attrs] (or empties it when absent). *)
val update_slots : slots -> Attrs.t -> unit

(** Empties every slot, making the still-connected GTK callbacks no-ops. Called when a
    widget is detached, so a signal GTK emits during teardown cannot fire a stale handler. *)
val clear_slots : slots -> unit

(** Connects to the detailed signal [notify::<prop>], which GTK emits whenever that
    property changes — however it changed, so a spec built on this fires for the library's
    own writes as well as the user's, and relies on the {!ctx.in_patch} guard to drop the
    former.

    This is the connector for properties whose class has no dedicated signal
    ([GtkSwitch]'s [active], for instance, whose [state-set] is the wrong hook for a
    controlled widget). *)
val notify : prop:string -> Widget.t -> callback:(unit -> unit) -> connection

(** Raises [Invalid_argument] if [attrs] carries an event attr ({!Attr.Name.is_event})
    that none of [specs] claims — [Attr.on_toggled] on a [Node.label], say. Such an attr
    is inert rather than wrong-looking: no slot is created for it, so the handler simply
    never runs. [node_path] and [impl_name] name the offending node in the message.

    Called by the patcher at mount, and again on any patch that changed the node's attrs —
    an event attr a later render adds conditionally lands on a widget mounted without it,
    and only the patch is in a position to see it (handlers are connected once, at mount,
    so no slot exists for a name no spec claims). *)
val require_specs : node_path:string -> impl_name:string -> spec list -> Attrs.t -> unit

(** Disconnects each handler from the object it was connected to. *)
val disconnect : connection list -> unit
