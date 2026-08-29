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
  ; fire : Attr.t -> unit Ui_effect.t option
  }

type slots = (Attr.Name.t, Attr.t option ref) List.Assoc.t ref

let dispatch ctx slot spec =
  if ctx.in_patch ()
  then ()
  else (
    match !slot with
    | None -> ()
    | Some attr ->
      (match spec.fire attr with
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
        match dispatch ctx slot spec with
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

let disconnect (w : Widget.t) ids =
  List.iter ids ~f:(fun id -> Gobject.Signal.disconnect w id)
;;
