open! Core
open Bonsai_gtk_vtree
open Gtk_import

type child_ops =
  | No_children
  | Single of { set : Widget.t -> Widget.t option -> unit }
  | List of
      { insert : Widget.t -> index:int -> Widget.t -> unit
      ; move : Widget.t -> child:Widget.t -> to_:int -> unit
      ; remove : Widget.t -> Widget.t -> unit
      }

type t =
  { name : string
  ; create : Kind.t -> Widget.t
  ; update : Widget.t -> old:Kind.t -> Kind.t -> unit
  ; signals : Signals.spec list
  ; children : child_ops
  }

let sibling_before parent ~index ~except : Widget.t option =
  if index = 0
  then None
  else (
    let kids =
      widget_children parent
      |> List.filter ~f:(fun c ->
        match except with
        | None -> true
        | Some e -> not (Gobject.same c e))
    in
    List.nth kids (index - 1))
;;

let wrong_kind name kind = invalid_argf "%s impl received %s" name (Kind.name kind) ()
