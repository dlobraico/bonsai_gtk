open! Core
open Bonsai_gtk_vtree
open Gtk_import

module type S = sig
  type input

  val name : string
  val create : input -> Widget.t
  val update : Widget.t -> old:input -> input -> unit
  val destroy : Widget.t -> unit
end

type Native.payload += Gtk : (module S with type input = 'a) * 'a -> Native.payload

let node ?key ?attrs (type a) (m : (module S with type input = a)) (input : a) =
  let module M = (val m) in
  Node.native ?key ?attrs { Native.name = M.name; payload = Gtk (m, input) }
;;

let impl_of_payload (n : Native.t) : Widget_impl.t =
  match n.payload with
  | Gtk (m, _) ->
    let module M = (val m) in
    let name = "Native:" ^ M.name in
    (* [m] is the very first-class module value stored in the payload, not a repack of it,
       so [phys_equal] on it is a reliable test of "same implementation module". A single
       module value is packed at one [input] type, hence the [Obj.magic] below is a no-op
       coercion between two spellings of that type. *)
    let get (kind : Kind.t) : M.input =
      match kind with
      | Native { payload = Gtk (m', input); _ } when phys_equal (Obj.repr m) (Obj.repr m')
        -> (Obj.magic input : M.input)
      | k -> Widget_impl.wrong_kind name k
    in
    { name
    ; create = (fun kind -> M.create (get kind))
    ; update = (fun w ~old new_ -> M.update w ~old:(get old) (get new_))
    ; signals = []
    ; children = No_children
    }
  | _ -> invalid_argf "Native node %s has no Gtk payload" n.name ()
;;

let destroy_payload (n : Native.t) (w : Widget.t) =
  match n.payload with
  | Gtk (m, _) ->
    let module M = (val m) in
    M.destroy w
  | _ -> invalid_argf "Native node %s has no Gtk payload" n.name ()
;;
