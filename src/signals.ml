open! Core
open Bonsai_gtk_vtree
open Gtk_import

type ctx =
  { schedule : unit Ui_effect.t -> unit
  ; in_patch : unit -> bool
  ; on_exn : node_path:string -> exn -> unit
  }

type connection =
  { source : unit Gobject.obj
  ; handler_id : Gobject.Signal.handler_id
  }

(* A handler id means nothing on its own: [g_signal_handler_disconnect] takes the object
   the id was issued for, and ids are only unique per object. Carrying the object with the
   id is what lets a spec connect to something other than the widget -- a text view's
   buffer, a drop-down's model, an event controller -- and still be torn down correctly. *)
let connected obj handler_id = { source = Gobject.coerce obj; handler_id }

type spec =
  { attr : Attr.Name.t
  ; connect : Widget.t -> callback:(unit -> unit) -> connection
  ; fire : Widget.t -> Attr.t -> unit Ui_effect.t option
  }

(* Task 4 turns [spec] into a variant; every reader that only wants the name goes through
   this rather than through the field, so that change stays inside this module. *)
let spec_attr spec = spec.attr

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

let connect_all ctx ~node_path (w : Widget.t) specs : slots * connection list =
  let slots = ref [] in
  let connections =
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
  slots, connections
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
  connected
    w
    (Gobject.Signal.connect_simple w ~name:("notify::" ^ prop) ~callback ~after:false)
;;

(* An [on_*] attr on a widget whose impl declares no spec for it is a typo that would
   otherwise be silently inert: the slot is never created, so nothing is ever written to
   it, no handler ever runs, and nothing says why (spec §5.1, §11). Run at mount and on
   every attr-changing patch, because a conditionally-added attr misses the mount.

   The answer comes from [Events], not from the impl's own [signals], so that this
   rejection and [Bonsai_gtk_test]'s are the same function of the same data -- a headless
   suite that goes green now means the runtime will accept the tree too.
   [test/live/live_events.ml] is what keeps [Events] and the impls in agreement. *)
let require_specs ~node_path ~impl_name kind attrs =
  match Events.unsupported kind attrs with
  | None -> ()
  | Some name ->
    (* Message shape unchanged from M1, deliberately: [Attr.Name.to_string] is
       [Sexp.to_string (sexp_of_t _)], so the existing expected files do not churn. *)
    invalid_argf
      "%s: %s does not emit %s"
      node_path
      impl_name
      (Attr.Name.to_string name)
      ()
;;

let disconnect connections =
  List.iter connections ~f:(fun c -> Gobject.Signal.disconnect c.source c.handler_id)
;;
