open! Core
open Bonsai_gtk_vtree
open Gtk_import

(** How the patcher attaches children to a container of this kind. *)
type child_ops =
  | No_children
  | Single of { set : Widget.t -> Widget.t option -> unit }
  | List of
      { insert : Widget.t -> after:Widget.t option -> Widget.t -> unit
      (** Add a child that is not yet in the container, placing it directly after [after]
          — or first when [after] is [None]. [after] is the live widget the patcher's own
          bookkeeping says precedes this position, never a widget read back out of GTK: a
          container that interposes children of its own (list-box rows, stack pages) has a
          live child list that does not match the reconciler's indices, and only the
          patcher's list is authoritative. *)
      ; move : Widget.t -> child:Widget.t -> after:Widget.t option -> unit
      (** Move a child already in the container to sit directly after [after] ([None] =
          first). [after] is computed over the sibling list with [child] already taken out
          of it, which is the order GTK's [reorder_child_after] expects. *)
      ; remove : Widget.t -> Widget.t -> unit
      }

(** Everything the patcher needs to realize one {!Kind.t} as a GTK widget. *)
type t =
  { name : string
  ; create : Kind.t -> Widget.t
  (** Raises [Invalid_argument] if handed a kind this impl does not own. *)
  ; update : Widget.t -> old:Kind.t -> Kind.t -> unit
  (** Set only the props that differ between [old] and the new kind — except for a
      controlled prop, which is compared against the widget instead (see {!controlled}). *)
  ; controlled : bool
  (** [true] when [update] re-asserts a property against the *widget's* live value rather
      than against [old] — spec §6.5's rule, which every text widget and every toggle
      follows.

      The patcher then calls [update] on every patch of this kind, even when the node's
      props are identical to the last frame's. That case is not the boring one it looks
      like: it is exactly what a model that *declines* the user's edit produces — the user
      typed a letter into a digits-only field, or flipped a switch the model refused — and
      skipping [update] there would leave the widget showing the value the model rejected,
      with nothing in the tree to say so. An impl whose props are all plain writes leaves
      this [false] and is skipped when nothing changed. *)
  ; signals : Signals.spec list
  ; children : child_ops
  }

(** Runs [f] with [w]'s property notifications frozen, thawing them even if [f] raises.

    Every [update] that writes more than one property should be wrapped in this: GTK
    otherwise emits a [notify::] per setter, and each one is a callback the reentrancy
    guard has to swallow. Thawing emits one round of notifications for whatever actually
    changed. *)
val batch : Widget.t -> (unit -> unit) -> unit

(** Raises [Invalid_argument]: impl [name] was handed a kind it does not own. *)
val wrong_kind : string -> Kind.t -> 'a
