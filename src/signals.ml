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

(* The two arms' records share [attr], [connect] and [fire] deliberately; see the mli. *)
[@@@warning "-30"]

(* Two shapes of GTK callback, and the second is existential in both directions: the
   payload GTK hands in and the value it wants back are the spec's own business, so
   [connect_all] can hold a list of them without knowing either. See the mli. *)
type spec =
  | Read_back of read_back
  | Payload : ('p, 'r) payload -> spec

and read_back =
  { attr : Attr.Name.t
  ; connect : Widget.t -> callback:(unit -> unit) -> connection
  ; fire : Widget.t -> Attr.t -> unit Ui_effect.t option
  }

and ('p, 'r) payload =
  { attr : Attr.Name.t
  ; connect : Widget.t -> callback:('p -> 'r) -> connection
  ; fire : Widget.t -> Attr.t -> 'p -> 'r * unit Ui_effect.t option
  ; declined : 'r
  }

[@@@warning "+30"]

(* Every reader that only wants the name goes through this rather than through a field, so
   that the variant stays inside this module. *)
let spec_attr = function
  | Read_back r -> r.attr
  | Payload p -> p.attr
;;

type slots = (Attr.Name.t, Attr.t option ref) List.Assoc.t ref

let dispatch ctx w slot (spec : read_back) =
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

(* The same five obligations as the read-back trampoline (spec §6.4), plus a sixth:
   whatever happens, GTK gets a value back. An exception here must not cross into C, and
   the value it returns instead has to be the *safe* one -- for a key controller that is
   "propagate", because a handler that raised has certainly not handled the key.

   Three paths return [declined], and they are the three on which the application has said
   nothing: the slot is empty (no handler on this node), the emission arrived during a
   patch (Bonsai must not be re-entered), or [fire] raised (which is reported and then
   treated as no answer). Everything else returns what [fire] decided, synchronously,
   while its effect -- if it produced one -- is scheduled like any other. *)
let dispatch_payload ctx ~node_path ~declined ~fire w slot p =
  match
    if ctx.in_patch ()
    then declined
    else (
      match !slot with
      | None -> declined
      | Some attr ->
        let r, effect = fire w attr p in
        Option.iter effect ~f:ctx.schedule;
        r)
  with
  | r -> r
  | exception exn ->
    (try ctx.on_exn ~node_path exn with
     | _ -> ());
    declined
;;

let connect_all ctx ~node_path (w : Widget.t) specs : slots * connection list =
  let slots = ref [] in
  let connections =
    List.map specs ~f:(fun spec ->
      let slot = ref None in
      slots := (spec_attr spec, slot) :: !slots;
      match spec with
      | Read_back spec ->
        spec.connect w ~callback:(fun () ->
          (* This frame is called from C: no exception may cross it. *)
          match dispatch ctx w slot spec with
          | () -> ()
          | exception exn ->
            (try ctx.on_exn ~node_path exn with
             | _ -> ()))
      | Payload { connect; fire; declined; attr = _ } ->
        (* No [try] around this one: [dispatch_payload] has to catch the exception itself,
           because the frame owes GTK a value even when it raised and only the spec knows
           which value is safe. *)
        connect w ~callback:(fun p ->
          dispatch_payload ctx ~node_path ~declined ~fire w slot p))
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
let require_specs ~node_path kind attrs =
  match Events.unsupported kind attrs with
  | None -> ()
  | Some name ->
    (* Message shape unchanged from M1, deliberately: [Attr.Name.to_string] is
       [Sexp.to_string (sexp_of_t _)], so the existing expected files do not churn.

       The widget is named by [Kind.name] rather than by the impl's own [name], which the
       patcher used to pass in. The two agree for every kind today, but only by
       convention, and [Bonsai_gtk_test] has no impl to ask -- taking the name from the
       kind is what makes the two messages identical by construction instead of by
       inspection. *)
    invalid_argf
      "%s: %s does not emit %s"
      node_path
      (Kind.name kind)
      (Attr.Name.to_string name)
      ()
;;

(* The backstop for [Events.for_kind] and a widget impl's [signals] drifting apart.
   [require_specs] now asks the table, not the impl, so an impl that omits a spec the
   table lists would let the attr through with no slot behind it -- and [update_slots]
   iterates the *slots*, so it would never notice the orphan and the handler would
   silently never fire, which is the exact failure [require_specs] exists to prevent.

   [test/live/live_events.ml] compares the two lists for every kind, but it is behind the
   live gate; this runs on every mount, unconditionally, and turns a silent no-op into a
   loud [Invalid_argument]. It is a handful of assoc lookups over lists of length <= 3. *)
let require_slots ~node_path ~impl_name (slots : slots) attrs =
  List.iter (Attrs.to_list attrs) ~f:(fun attr ->
    match Attr.name attr with
    (* Controller attrs are skipped: they are no impl's signal, so no slot for one lives
       on the widget. [Controllers] builds their slots from the attr itself, on the frame
       the attr appears, which is why "the attr is here but has no slot" is not a state
       they can reach. *)
    | Some name when Attr.Name.is_event name && not (Events.is_controller_attr name) ->
      if not (List.Assoc.mem !slots name ~equal:Attr.Name.equal)
      then
        invalid_argf
          "%s: %s connected no signal for %s, which Events says it emits (the widget \
           impl and the table disagree)"
          node_path
          impl_name
          (Attr.Name.to_string name)
          ()
    | Some _ | None -> ())
;;

let disconnect connections =
  List.iter connections ~f:(fun c -> Gobject.Signal.disconnect c.source c.handler_id)
;;
