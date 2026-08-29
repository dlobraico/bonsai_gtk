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

(** One GTK signal a widget impl knows how to connect, and the attr that carries its
    handler. *)
type spec =
  { attr : Attr.Name.t
  ; connect : Widget.t -> callback:(unit -> unit) -> Gobject.Signal.handler_id
  ; fire : Widget.t -> Attr.t -> unit Ui_effect.t option
  (** Turn the attr currently in the slot into the effect to schedule. [None] if the attr
      is not the one this spec handles.

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

(** Connects every spec to [w], returning the slots and the handler ids to disconnect on
    destruction. The slots start empty, so callbacks are inert until the first
    {!update_slots} — call it with the node's attrs right after creating the widget.

    Each callback is exception-guarded: nothing raised by [in_patch], [fire], or
    [schedule] escapes into GTK's C frame. *)
val connect_all
  :  ctx
  -> node_path:string
  -> Widget.t
  -> spec list
  -> slots * Gobject.Signal.handler_id list

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
val notify
  :  prop:string
  -> Widget.t
  -> callback:(unit -> unit)
  -> Gobject.Signal.handler_id

(** Raises [Invalid_argument] if [attrs] carries an event attr ({!Attr.Name.is_event})
    that none of [specs] claims — [Attr.on_toggled] on a [Node.label], say. Such an attr
    is inert rather than wrong-looking: no slot is created for it, so the handler simply
    never runs. [node_path] and [impl_name] name the offending node in the message.

    Called by the patcher at mount, once per widget. *)
val require_specs : node_path:string -> impl_name:string -> spec list -> Attrs.t -> unit

val disconnect : Widget.t -> Gobject.Signal.handler_id list -> unit
