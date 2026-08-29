open! Core
open Bonsai_gtk_vtree
open Gtk_import

type ctx =
  { schedule : unit Ui_effect.t -> unit
  ; in_patch : unit -> bool
  ; on_exn : node_path:string -> exn -> unit
  }

type spec =
  { attr : Attr.Name.t
  ; connect : Widget.t -> callback:(unit -> unit) -> Gobject.Signal.handler_id
  ; fire : Widget.t -> Attr.t -> unit Ui_effect.t option
  }

type slots = (Attr.Name.t, Attr.t option ref) List.Assoc.t ref

let dispatch ctx w slot spec =
  if ctx.in_patch ()
  then ()
  else (
    match !slot with
    | None -> ()
    | Some attr ->
      (match spec.fire w attr with
       | None -> ()
       | Some effect -> ctx.schedule effect))
;;

let connect_all ctx ~node_path (w : Widget.t) specs
  : slots * Gobject.Signal.handler_id list
  =
  let slots = ref [] in
  let ids =
    List.map specs ~f:(fun spec ->
      let slot = ref None in
      slots := (spec.attr, slot) :: !slots;
      spec.connect w ~callback:(fun () ->
        (* This frame is called from C: no exception may cross it. *)
        match dispatch ctx w slot spec with
        | () -> ()
        | exception exn ->
          (try ctx.on_exn ~node_path exn with
           | _ -> ())))
  in
  slots, ids
;;

let update_slots (slots : slots) attrs =
  List.iter !slots ~f:(fun (name, slot) -> slot := Attrs.find attrs name)
;;

let clear_slots (slots : slots) = List.iter !slots ~f:(fun (_, slot) -> slot := None)

(* ocgtk generates no [on_notify_*]: a detailed signal name goes through the generic
   marshaller, which carries no payload at all, so the handler reads the property back off
   the widget with the class getter (spec §6.4). That is the same shape [fire] already has
   for the [toggled] family, which is why one [spec] type covers both.

   [~after:false] matches every generated [on_*], each of which defaults [?after] to
   false. *)
let notify ~prop w ~callback =
  Gobject.Signal.connect_simple w ~name:("notify::" ^ prop) ~callback ~after:false
;;

(* An [on_*] attr on a widget whose impl declares no spec for it is a typo that would
   otherwise be silently inert: the slot is never created, so nothing is ever written to
   it, no handler ever runs, and nothing says why (spec §5.1, §11). *)
let require_specs ~node_path ~impl_name specs attrs =
  List.iter (Attrs.to_list attrs) ~f:(fun attr ->
    match Attr.name attr with
    | Some name when Attr.Name.is_event name ->
      if not (List.exists specs ~f:(fun s -> Attr.Name.equal s.attr name))
      then
        invalid_argf
          !"%s: %s does not emit %{sexp:Attr.Name.t}"
          node_path
          impl_name
          name
          ()
    | Some _ | None -> ())
;;

let disconnect (w : Widget.t) ids =
  List.iter ids ~f:(fun id -> Gobject.Signal.disconnect w id)
;;
