open! Core
open Bonsai_gtk_vtree
open Gtk_import

(** How the patcher attaches children to a container of this kind. *)
type child_ops =
  | No_children
  | Single of { set : Widget.t -> Widget.t option -> unit }
  | List of
      { insert : Widget.t -> index:int -> Widget.t -> unit
      (** Insert so the child ends up at [index] in the parent's child list. The child is
          not yet a child of the parent. *)
      ; move : Widget.t -> child:Widget.t -> to_:int -> unit
      (** Move an existing child so it ends up at [to_], where [to_] indexes the child
          list as it will be *after* the move. *)
      ; remove : Widget.t -> Widget.t -> unit
      }

(** Everything the patcher needs to realize one {!Kind.t} as a GTK widget. *)
type t =
  { name : string
  ; create : Kind.t -> Widget.t
  (** Raises [Invalid_argument] if handed a kind this impl does not own. *)
  ; update : Widget.t -> old:Kind.t -> Kind.t -> unit
  (** Set only the props that differ between [old] and the new kind. *)
  ; signals : Signals.spec list
  ; children : child_ops
  }

(** The sibling a child must be placed *after* so that it lands at [index] among
    [parent]'s children, ignoring [except] (the child being moved, which is still in the
    list at its old position). [None] means "at the beginning", which is what GTK's
    [*_child_after] calls take for a null sibling.

    Raises [Invalid_argument] if [index] exceeds the length of the considered child list:
    such an [index] has no sibling to name, and answering [None] would silently place the
    child at the *beginning* rather than the end. Reaching that case means GTK's live
    child order has drifted from the list the reconciler computed indices against, so it
    is a bug worth failing on rather than mis-ordering the tree. *)
val sibling_before : Widget.t -> index:int -> except:Widget.t option -> Widget.t option

(** Raises [Invalid_argument]: impl [name] was handed a kind it does not own. *)
val wrong_kind : string -> Kind.t -> 'a
