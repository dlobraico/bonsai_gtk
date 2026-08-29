open! Core
open Bonsai_gtk_vtree
open Gtk_import

type child_ops =
  | No_children
  | Single of { set : Widget.t -> Widget.t option -> unit }
  | List of
      { insert : Widget.t -> after:Widget.t option -> Widget.t -> unit
      ; move : Widget.t -> child:Widget.t -> after:Widget.t option -> unit
      ; remove : Widget.t -> Widget.t -> unit
      }

type t =
  { name : string
  ; create : Kind.t -> Widget.t
  ; update : Widget.t -> old:Kind.t -> Kind.t -> unit
  ; signals : Signals.spec list
  ; children : child_ops
  }

let wrong_kind name kind = invalid_argf "%s impl received %s" name (Kind.name kind) ()
