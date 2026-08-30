open! Core
open Bonsai_gtk_vtree
open Gtk_import

(** The escape hatch: a GTK widget bonsai_gtk knows nothing about, driven by an
    application-supplied module. The vtree stays pure — a native node carries only the
    implementation and its input — and this module turns that pair into the
    {!Widget_impl.t} the patcher needs. *)
module type S = sig
  (** The props the application diffs on. *)
  type input

  (** Distinguishes this native widget from others in {!Bonsai_gtk_vtree.Kind.same_kind}:
      two native nodes with different names are different kinds and force a replace. Keep
      it unique per implementation. *)
  val name : string

  val create : input -> Widget.t

  (** Bring the widget up to date. [old] is the input the widget was last rendered from.

      This runs on *every* re-render, not only when the input changed: the patcher
      compares native payloads physically, and building a node allocates a fresh payload
      each time, so [old] and the new input are routinely equal. Implementations must
      tolerate that — compare and do nothing rather than assuming a change. *)
  val update : Widget.t -> old:input -> input -> unit

  (** Release whatever {!create} acquired — a subscription, a timer, a file handle. Called
      when the node leaves the tree.

      Only that. Do not unparent or destroy the widget: the patcher owns the widget's
      place in the tree and removes it itself, and a [destroy] that races it will either
      double-free or leave the patcher holding a dead widget.

      This is the one place a teardown calls application code, so what happens when it
      raises is part of the contract: the rest of the teardown still runs — the later
      siblings in the same list, the enclosing node's own release, and (under
      {!Bonsai_gtk.Expert.Driver.stop}) the driver's trailing steps — and the exception is
      then re-raised to whoever called [stop] or drove the frame. Nothing retries it and
      nothing else releases what this node held, so an implementation that raises has
      leaked whatever [create] acquired: catch inside if there is anything to do about it. *)
  val destroy : Widget.t -> unit
end

(** An implementation, paired with the type witness that lets the patcher recover [input]
    from a node's existentially typed payload.

    Create it once, at the top level of the module that defines the widget, and reuse that
    value for every node. Two [impl]s built from the same module are *different* as far as
    the patcher is concerned — {!node} would build nodes whose input it refuses to project
    (a loud [Invalid_argument], never a misread input). *)
type 'a impl

val impl : (module S with type input = 'a) -> 'a impl

(** [attrs] may carry any of the widget-wide attributes, but no event attr
    ([Attr.on_clicked], [Attr.on_toggled], ...): a native impl declares no signal specs,
    so there would be nothing to connect the handler to. The patcher rejects one with
    [Invalid_argument] at mount rather than leaving it silently inert. A native widget
    that needs to reach Bonsai connects its own GTK handler in [create] and closes over
    whatever it needs. *)
val node : ?key:Key.t -> ?attrs:Attr.t list -> 'a impl -> 'a -> Node.t

(** The payload {!node} stores in a {!Bonsai_gtk_vtree.Native.t}. Exposed so that
    [impl_of_payload] can be replaced or wrapped; applications should use {!node}. *)
type Native.payload += Gtk : 'a impl * 'a -> Native.payload

(** The impl for a native node built by {!node}.

    Raises [Invalid_argument] if [n]'s payload was not built by {!node}; the returned impl
    raises if it is later handed a node built by a different {!impl}. *)
val impl_of_payload : Native.t -> Widget_impl.t

(** Calls the payload module's [destroy] on the widget it created. The patcher calls this
    when a native node leaves the tree; there is no [destroy] hook on {!Widget_impl.t}, so
    this is how a native implementation gets to release whatever [create] acquired.

    Raises [Invalid_argument] if [n]'s payload was not built by {!node}. *)
val destroy_payload : Native.t -> Widget.t -> unit
