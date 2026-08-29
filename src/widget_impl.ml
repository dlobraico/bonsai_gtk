open! Core
open Bonsai_gtk_vtree
open Gtk_import

type single_ops = { set : Widget.t -> Widget.t option -> unit }

type list_ops =
  { insert : Widget.t -> after:Widget.t option -> node:Node.t -> Widget.t -> unit
  ; move : Widget.t -> child:Widget.t -> after:Widget.t option -> unit
  ; remove : Widget.t -> Widget.t -> unit
  ; updated : Widget.t -> old:Node.t -> node:Node.t -> Widget.t -> unit
  }

type slot_ops =
  | Slot_single of single_ops
  | Slot_list of list_ops

type child_ops =
  | No_children
  | Single of single_ops
  | List of list_ops
  | Slots of (string * slot_ops) list

type t =
  { name : string
  ; create : Kind.t -> Widget.t
  ; update : Widget.t -> old:Kind.t -> Kind.t -> unit
  ; reassert : (Widget.t -> Kind.t -> unit) option
  ; signals : Signals.spec list
  ; children : child_ops
  }

(* Spec §7: a prop batch is bracketed, so GTK emits one round of [notify::] at the end
   rather than one per setter — which matters here beyond tidiness, because every
   [notify::] we emit is one the [in_patch] guard has to swallow, and every swallowed
   signal is a callback into OCaml that did nothing.

   [Exn.protect] rather than a bare pair of calls: an exception between the two would
   leave the object frozen forever, and a frozen widget silently stops updating. *)
let batch (w : Widget.t) f =
  Gobject.Property.freeze_notify w;
  Exn.protect ~f ~finally:(fun () -> Gobject.Property.thaw_notify w)
;;

let wrong_kind name kind = invalid_argf "%s impl received %s" name (Kind.name kind) ()

(* For containers with no per-child settings of their own -- the common case. *)
let no_list_update _parent ~old:_ ~node:_ _child = ()
