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

type 'a impl =
  { m : (module S with type input = 'a)
  ; name : string
  ; id : 'a Type_equal.Id.t
  }

type Native.payload += Gtk : 'a impl * 'a -> Native.payload

let impl (type a) (m : (module S with type input = a)) : a impl =
  let module M = (val m) in
  { m; name = M.name; id = Type_equal.Id.create ~name:M.name (fun _ -> Sexp.Atom M.name) }
;;

let node ?key ?attrs (type a) (impl : a impl) (input : a) =
  Node.native ?key ?attrs { Native.name = impl.name; payload = Gtk (impl, input) }
;;

(* The payload's input type is existential, so recovering it needs a witness. The
   [Type_equal.Id.t] created with the impl is that witness: it is unforgeable, so a
   payload built by a *different* impl fails the match and is reported, rather than having
   its input reinterpreted at the wrong type. *)
let widget_impl (type a) (impl : a impl) : Widget_impl.t =
  let module M = (val impl.m) in
  (* Same spelling as [Kind.name] gives this node, so error messages agree. *)
  let name = "Native:" ^ impl.name in
  let input_of_kind (kind : Kind.t) : a =
    match kind with
    | Native { payload = Gtk (other, input); _ } ->
      (match Type_equal.Id.same_witness other.id impl.id with
       | Some T -> input
       | None ->
         invalid_argf
           "%s: node carries a different Native_gtk.impl. Create the impl once and reuse \
            that value; a fresh impl per render is a different widget as far as the \
            patcher is concerned."
           name
           ())
    | k -> Widget_impl.wrong_kind name k
  in
  { name
  ; create = (fun kind -> M.create (input_of_kind kind))
  ; update = (fun w ~old new_ -> M.update w ~old:(input_of_kind old) (input_of_kind new_))
  ; (* [Native_gtk.S] has no controlled-prop member, and a native widget that wants to
       re-assert against itself can do so from its own [create]-installed handlers. *)
    reassert = None
  ; signals = []
  ; children = No_children
  }
;;

let impl_of_payload (n : Native.t) : Widget_impl.t =
  match n.payload with
  | Gtk (impl, _) -> widget_impl impl
  | _ -> invalid_argf "Native node %s has no Gtk payload" n.name ()
;;

let destroy_one (type a) (impl : a impl) (w : Widget.t) =
  let module M = (val impl.m) in
  M.destroy w
;;

let destroy_payload (n : Native.t) (w : Widget.t) =
  match n.payload with
  | Gtk (impl, _) -> destroy_one impl w
  | _ -> invalid_argf "Native node %s has no Gtk payload" n.name ()
;;
