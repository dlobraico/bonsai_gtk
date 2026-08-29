open! Core
open Bonsai_gtk_vtree
open Gtk_import

(** The escape hatch: a GTK widget bonsai_gtk knows nothing about, driven by an
    application-supplied module. The vtree stays pure — a native node carries only the
    module and its input — and this module turns that pair into the {!Widget_impl.t} the
    patcher needs. *)
module type S = sig
  (** The props the application diffs on. Compared physically by
      {!Bonsai_gtk_vtree.Kind.equal_props} (via the payload), so [update] runs only when
      the application hands over a different [input] value. *)
  type input

  (** Distinguishes this native widget from others in {!Bonsai_gtk_vtree.Kind.same_kind}:
      two native nodes with different names are different kinds and force a replace. Keep
      it unique per implementation. *)
  val name : string

  val create : input -> Widget.t
  val update : Widget.t -> old:input -> input -> unit
  val destroy : Widget.t -> unit
end

(** The payload {!node} stores in a {!Bonsai_gtk_vtree.Native.t}. Exposed so that
    [impl_of_payload] can be replaced or wrapped; applications should use {!node}. *)
type Native.payload += Gtk : (module S with type input = 'a) * 'a -> Native.payload

val node
  :  ?key:Key.t
  -> ?attrs:Attr.t list
  -> (module S with type input = 'a)
  -> 'a
  -> Node.t

(** The impl for a native node built by {!node}.

    The returned impl's [create]/[update] must project the [input] back out of a
    {!Bonsai_gtk_vtree.Kind.t}, whose payload has an existentially quantified input type.
    The projection is guarded by a physical-equality check on the first-class module
    value: the same module value can only have been packed with one [input] type, so an
    [Obj.magic] behind that check is sound. A payload carrying a *different* module (even
    one with the same [name]) fails the check and raises [Invalid_argument] rather than
    reinterpreting its input.

    The check compares the first-class module *values*, so a module whose signature
    matches {!S} exactly (same members, same order) passes: packing it is a no-op and
    every [(module M)] is the same block. A module that needs a coercion to fit {!S} is
    copied at each pack and would fail the check on every update; the failure is a loud
    [Invalid_argument], never a misinterpreted input.

    Raises [Invalid_argument] if [n]'s payload was not built by {!node}. *)
val impl_of_payload : Native.t -> Widget_impl.t

(** Calls the payload module's [destroy] on the widget it created. The patcher calls this
    when a native node leaves the tree; there is no [destroy] hook on {!Widget_impl.t}, so
    this is how a native implementation gets to release whatever [create] acquired.

    Raises [Invalid_argument] if [n]'s payload was not built by {!node}. *)
val destroy_payload : Native.t -> Widget.t -> unit
