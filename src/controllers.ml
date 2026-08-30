open! Core
open Bonsai_gtk_vtree
open Gtk_import

(* One controller, plus the slots and connections [Signals] built for it. The controller
   is kept at its *concrete* type rather than upcast to [Event_controller.t], so that
   re-applying a gesture's button needs no downcast: [sync] below is polymorphic in it and
   the upcast happens only where GTK asks for one. *)
type 'a attached =
  { controller : 'a
  ; slots : Signals.slots
  ; connections : Signals.connection list
  }

type t =
  { ctx : Signals.ctx
  ; node_path : string
  ; widget : Widget.t
  ; mutable click : W.Gesture_click.t attached option
  ; mutable focus : W.Event_controller_focus.t attached option
  (* Task 5 adds [mutable key : W.Event_controller_key.t attached option]. *)
  }

let create ctx ~node_path widget = { ctx; node_path; widget; click = None; focus = None }

(* GTK's own debugging label, and the only way to tell a controller this library attached
   from one the widget class attached itself: a [GtkButton] ships with a
   [GtkGestureClick], a [GtkEventControllerKey] and a [GtkShortcutController] of its own,
   so "the widget has a GtkGestureClick" says nothing. The name shows up in GTK Inspector,
   and [test/live/live_controllers.ml] counts by it.

   [set_name], never [set_static_name]. The "static" one stores the pointer it is handed
   without copying -- it assigns the argument straight into [priv->name] and sets
   [priv->name_is_static] -- so the string must outlive the controller, and nothing OCaml
   can pass it qualifies. This concatenation is a fresh heap value that is unreachable the
   moment the call returns, so GTK would be left pointing into memory the collector
   reclaims: garbage from [get_name] after the next collection, and a read of unmapped
   memory after a compaction that returns the chunk to the OS. Hoisting the two names to
   top-level literals is not the fix either -- OCaml does not promise literals are static
   data, and under bytecode they live in the heap and are moved by compaction. [set_name]
   g_strdups, which is what a runtime-computed name needs.
   [test/live/live_controllers.ml]'s heap-churn case is the regression test. *)
let name_prefix = "bonsai_gtk."

let set_name (c : W.Event_controller.t) suffix =
  W.Event_controller.set_name c (Some (name_prefix ^ suffix))
;;

(* Whether this family's controller should exist: exactly while at least one of the attrs
   [Events] assigns to it is present. Asking the table rather than naming the attrs here
   is what keeps "which attrs mean click" in one place -- Task 5's second key attr joins
   its family in [vtree/events.ml] and nothing in this file changes. *)
let wanted attrs family =
  List.exists (Events.family_attrs family) ~f:(fun name ->
    Option.is_some (Attrs.find attrs name))
;;

(* Every attached family's slots. The one place that has to know all of them; the
   [Events.Family.t] match is what makes a new family a compile error here rather than a
   controller [clear] silently skips. *)
let attached t (family : Events.Family.t) =
  match family with
  | Click -> Option.map t.click ~f:(fun a -> a.slots)
  | Focus -> Option.map t.focus ~f:(fun a -> a.slots)
;;

let clear t =
  List.iter Events.Family.all ~f:(fun family ->
    Option.iter (attached t family) ~f:Signals.clear_slots)
;;

(* [wanted] is whether any of this family's attrs is present. Attach on the first, detach
   on the last, and in between only re-slot and re-configure.

   The four cases are the whole of the module's policy, and the order inside them is the
   part that matters: on the way in, the controller is attached and connected while its
   slots are still empty (so an [enter] GTK emits from [add_controller] itself is inert,
   exactly as a signal emitted from [create] is), and on the way out the slots are
   emptied *before* [remove_controller], which can itself provoke a leave or a cancel. *)
let sync
  (type a)
  t
  ~(wanted : bool)
  ~(get : t -> a attached option)
  ~(set : t -> a attached option -> unit)
  ~(make : unit -> a)
  ~(upcast : a -> W.Event_controller.t)
  ~(specs : a -> Signals.spec list)
  ~(configure : a -> Attrs.t -> unit)
  ~(name : string)
  attrs
  =
  match get t, wanted with
  | None, false -> ()
  | Some a, false ->
    (* Every family's slots, not just this one's, and for the reason [release] gives:
       [remove_controller] can itself provoke a leave or a cancel, and a still-armed slot
       on a *sibling* controller of the same widget would reach Bonsai from inside it.
       Unreachable today -- [update] only runs from a patch, which the driver wraps in the
       reentrancy guard -- but the slot-emptying exists precisely as belt-and-braces
       against that guard not being the whole story, and the two removal paths must not
       disagree about it. *)
    clear t;
    Signals.disconnect a.connections;
    W.Widget.remove_controller t.widget (upcast a.controller);
    set t None
  | Some a, true ->
    configure a.controller attrs;
    Signals.update_slots a.slots attrs
  | None, true ->
    let controller = make () in
    set_name (upcast controller) name;
    configure controller attrs;
    W.Widget.add_controller t.widget (upcast controller);
    (* [specs controller] builds [Signals.spec]s whose [connect] *ignores the widget it is
       handed* and connects to the captured controller instead, returning
       [Signals.connected controller id]. That is exactly what [Signals.connection] names
       an object for, and it is why this module needs no disconnect machinery of its own. *)
    let slots, connections =
      Signals.connect_all t.ctx ~node_path:t.node_path t.widget (specs controller)
    in
    Signals.update_slots slots attrs;
    set t (Some { controller; slots; connections })
;;

let click_spec (gc : W.Gesture_click.t) : Signals.spec =
  Payload
    { attr = Attr.Name.On_click
    ; connect =
        (fun _w ~callback ->
          Signals.connected
            gc
            (W.Gesture_click.on_pressed gc ~callback:(fun ~n_press ~x ~y ->
               (* The button and the modifier state are not callback arguments: they are
                  read off the gesture and its controller while the event is still
                  current. This is the whole reason [Payload]'s [connect] assembles the
                  payload rather than [fire] doing it -- after the callback returns, both
                  are gone.

                  [get_current_event_state] is on [GtkEventController], not on
                  [GtkGesture], hence the coercion. *)
               let button =
                 W.Gesture_single.get_current_button (gc :> W.Gesture_single.t)
               in
               let modifiers =
                 modifiers_of_gdk
                   (W.Event_controller.get_current_event_state
                      (gc :> W.Event_controller.t))
               in
               callback ({ button; n_press; x; y; modifiers } : Click_event.t))))
    ; fire =
        (fun _w attr (e : Click_event.t) ->
          match (attr :> Attr.Private.t) with
          | On_click { handler; _ } -> (), Some (handler e)
          | _ -> (), None)
        (* A [pressed] callback returns nothing to GTK, so there is no unsafe answer to
           get wrong here. Task 5's key spec is where [declined] earns its keep. *)
    ; declined = ()
    }
;;

(* [enter] and [leave] ride on one [GtkEventControllerFocus], so a widget carrying either
   attr pays for one controller and gets both specs; the slot of the attr that is absent
   is simply never filled. *)
let focus_specs (fc : W.Event_controller_focus.t) : Signals.spec list =
  [ Read_back
      { attr = Attr.Name.On_focus_enter
      ; connect =
          (fun _w ~callback ->
            Signals.connected fc (W.Event_controller_focus.on_enter fc ~callback))
      ; fire =
          (fun _w attr ->
            match (attr :> Attr.Private.t) with
            | On_focus_enter handler -> Some (handler ())
            | _ -> None)
      }
  ; Read_back
      { attr = Attr.Name.On_focus_leave
      ; connect =
          (fun _w ~callback ->
            Signals.connected fc (W.Event_controller_focus.on_leave fc ~callback))
      ; fire =
          (fun _w attr ->
            match (attr :> Attr.Private.t) with
            | On_focus_leave handler -> Some (handler ())
            | _ -> None)
      }
  ]
;;

(* Both properties are re-applied unconditionally: they are plain GTK properties that the
   gesture re-reads per event, and comparing first would mean keeping the old attr around
   for no gain. A frame that dropped the attr does not get here at all -- [sync]'s
   [wanted] is false and the controller is removed. *)
let configure_click (gc : W.Gesture_click.t) attrs =
  match (Attrs.find attrs Attr.Name.On_click :> Attr.Private.t option) with
  | Some (On_click { button; phase; handler = _ }) ->
    W.Gesture_single.set_button (gc :> W.Gesture_single.t) button;
    W.Event_controller.set_propagation_phase
      (gc :> W.Event_controller.t)
      (propagation_phase phase)
  | Some _ | None -> ()
;;

(* One [sync] per family, dispatched from an exhaustive match on [Events.Family.t].

   The match is the point. [Events.controller_family] is what makes a controller attr
   legal on every kind, skipped by [Signals.require_slots], and connected by no widget
   impl; this is the other end of that, and without the exhaustiveness a family could be
   named there and attached by nothing -- accepted everywhere, wired nowhere, with no
   diagnostic. Task 5 adds [Key] to the variant and the compiler asks for its arm here. *)
let update t attrs =
  List.iter Events.Family.all ~f:(fun (family : Events.Family.t) ->
    let wanted = wanted attrs family in
    match family with
    | Click ->
      sync
        t
        ~wanted
        ~get:(fun t -> t.click)
        ~set:(fun t a -> t.click <- a)
        ~make:W.Gesture_click.new_
        ~upcast:(fun gc -> (gc :> W.Event_controller.t))
        ~specs:(fun gc -> [ click_spec gc ])
        ~configure:configure_click
        ~name:"click"
        attrs
    | Focus ->
      sync
        t
        ~wanted
        ~get:(fun t -> t.focus)
        ~set:(fun t a -> t.focus <- a)
        ~make:W.Event_controller_focus.new_
        ~upcast:(fun fc -> (fc :> W.Event_controller.t))
        ~specs:focus_specs
          (* A focus controller has nothing to configure: there is no [Attr.on_focus_*]
             phase in M2, so it stays in GTK's default (bubble) phase. *)
        ~configure:(fun _ _ -> ())
        ~name:"focus"
        attrs)
;;

(* Slots first, for every controller, and only then the disconnecting and detaching:
   [gtk_widget_remove_controller] can provoke a leave or a cancel, and one still-armed
   slot on a *different* controller of the same widget would reach Bonsai from inside
   teardown. Emptying all of them up front is what makes that impossible -- which is also
   why [clear] is a call here rather than three lines inlined per family.

   Detaching one family is [sync]'s [Some _, false] branch, which does the same three
   steps in the same order; the difference is only that this one runs for every family and
   leaves [t] empty. *)
let release t =
  clear t;
  List.iter Events.Family.all ~f:(fun (family : Events.Family.t) ->
    let detach (a : _ attached) upcast =
      Signals.disconnect a.connections;
      W.Widget.remove_controller t.widget (upcast a.controller)
    in
    match family with
    | Click ->
      Option.iter t.click ~f:(fun a -> detach a (fun c -> (c :> W.Event_controller.t)));
      t.click <- None
    | Focus ->
      Option.iter t.focus ~f:(fun a -> detach a (fun c -> (c :> W.Event_controller.t)));
      t.focus <- None)
;;

(* Derived from the same [Events.Family.t] match as everything else here, so a family that
   is added and then not counted is not a possible state. *)
let attached_count t =
  List.count Events.Family.all ~f:(fun family -> Option.is_some (attached t family))
;;

let is_ours (c : W.Event_controller.t) =
  match W.Event_controller.get_name c with
  | None -> false
  | Some name -> String.is_prefix name ~prefix:name_prefix
;;
