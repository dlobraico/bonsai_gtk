open! Core
open Bonsai_gtk_vtree
open Gtk_import

(** The one child slot of a single-child container. [None] empties it. *)
type single_ops = { set : Widget.t -> Widget.t option -> unit }

(** The ordered children of a list container. *)
type list_ops =
  { insert : Widget.t -> after:Widget.t option -> node:Node.t -> Widget.t -> unit
  (** Add a child that is not yet in the container, placing it directly after [after] — or
      first when [after] is [None]. [after] is the live widget the patcher's own
      bookkeeping says precedes this position, never a widget read back out of GTK: a
      container that interposes children of its own (list-box rows, stack pages) has a
      live child list that does not match the reconciler's indices, and only the patcher's
      list is authoritative.

      [node] is the child's description: some containers keep per-child settings of their
      {i own} — an overlay's measure flag, a grid cell, a stack page's title — which are
      not properties of the child widget and so are read from the child node's attrs here
      rather than applied by [Attr_apply]. *)
  ; move : Widget.t -> child:Widget.t -> after:Widget.t option -> unit
  (** Move a child already in the container to sit directly after [after] ([None] =
      first). [after] is computed over the sibling list with [child] already taken out of
      it, which is the order GTK's [reorder_child_after] expects.

      A container GTK gives no reordering primitive for — [Overlay] is the M1 case — makes
      this a documented no-op: identity is preserved by keys, and only the paint or tab
      order goes unreconciled. *)
  ; remove : Widget.t -> Widget.t -> unit
  ; updated : Widget.t -> old:Node.t -> node:Node.t -> Widget.t -> unit
  (** Called after a child that stayed in place was patched, with its previous and new
      descriptions. This is where those same parent-held settings are re-applied when they
      change. {!no_list_update} for containers that have none. *)
  }

(** One slot of a {!Slots} container: a slot has a shape of its own, and the patcher
    drives it with exactly the code it uses for a top-level shape. *)
type slot_ops =
  | Slot_single of single_ops
  | Slot_list of list_ops

(** How the patcher attaches children to a container of this kind. It must agree with the
    [Children.t] shape the node constructors build — for {!Slots}, down to the slot names
    and their order; the patcher raises [Invalid_argument] otherwise. *)
type child_ops =
  | No_children
  | Single of single_ops
  | List of list_ops
  | Slots of (string * slot_ops) list

(** Everything the patcher needs to realize one {!Kind.t} as a GTK widget. *)
type t =
  { name : string
  ; create : Kind.t -> Widget.t
  (** Raises [Invalid_argument] if handed a kind this impl does not own. *)
  ; update : Widget.t -> old:Kind.t -> Kind.t -> unit
  (** Set only the props that differ between [old] and the new kind. The patcher skips
      this entirely when the two kinds' props are equal, so a *controlled* prop must not
      be written here — put it in {!reassert}. *)
  ; reassert : (Widget.t -> Kind.t -> unit) option
  (** The controlled props of this kind, re-applied against the widget's live value — spec
      §6.5's rule, which every text widget and every toggle follows.

      The patcher calls this on {i every} patch of a node of this kind, before the attrs
      and children and after any {!update}, and it must therefore compare against the
      widget rather than against the previous node: a model that {i declines} the user's
      change renders exactly the props it rendered last frame — the user typed a letter
      into a digits-only field, or flipped a switch the model refused — so [update] is
      skipped, and this hook is the only thing left to put the widget back. Writing the
      controlled prop in [update] instead would work whenever the model agreed and fail
      silently whenever it did not, which is the bug §6.5 exists to prevent.

      It runs while the patcher's reentrancy guard is set, so the signals GTK emits from
      the write are dropped rather than fed back to Bonsai; it should bracket its writes
      in {!batch} for the same reason. Implementations are called with the {i new} kind
      and must raise {!wrong_kind} on any other. [None] for a kind with no controlled prop
      — which is most of them, and is why this is an option rather than a [unit -> unit]
      every impl would have to write. *)
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

(** The do-nothing {!list_ops.updated}, for a container that holds no per-child settings
    of its own. Written once rather than as a lambda per impl. *)
val no_list_update : Widget.t -> old:Node.t -> node:Node.t -> Widget.t -> unit
