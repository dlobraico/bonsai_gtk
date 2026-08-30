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

(* [gtk_event_controller_set_static_name] is GTK's own debugging label, and it is the only
   way to tell a controller this library attached from one the widget class attached
   itself: a [GtkButton] ships with a [GtkGestureClick], a [GtkEventControllerKey] and a
   [GtkShortcutController] of its own, so "the widget has a GtkGestureClick" says nothing.
   The name shows up in GTK Inspector, and [test/live/live_controllers.ml] counts by it.

   Static in GTK's sense means "not copied", so the string must outlive the controller;
   these are literals, which do. *)
let name_prefix = "bonsai_gtk."

let set_name (c : W.Event_controller.t) suffix =
  W.Event_controller.set_static_name c (Some (name_prefix ^ suffix))
;;

let present attrs name = Option.is_some (Attrs.find attrs name)

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
    Signals.clear_slots a.slots;
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

let update t attrs =
  sync
    t
    ~wanted:(present attrs On_click)
    ~get:(fun t -> t.click)
    ~set:(fun t a -> t.click <- a)
    ~make:W.Gesture_click.new_
    ~upcast:(fun gc -> (gc :> W.Event_controller.t))
    ~specs:(fun gc -> [ click_spec gc ])
    ~configure:configure_click
    ~name:"click"
    attrs;
  sync
    t
    ~wanted:(present attrs On_focus_enter || present attrs On_focus_leave)
    ~get:(fun t -> t.focus)
    ~set:(fun t a -> t.focus <- a)
    ~make:W.Event_controller_focus.new_
    ~upcast:(fun fc -> (fc :> W.Event_controller.t))
    ~specs:focus_specs
      (* A focus controller has nothing to configure: there is no [Attr.on_focus_*] phase
         in M2, so it stays in GTK's default (bubble) phase. *)
    ~configure:(fun _ _ -> ())
    ~name:"focus"
    attrs
;;

let clear t =
  Option.iter t.click ~f:(fun a -> Signals.clear_slots a.slots);
  Option.iter t.focus ~f:(fun a -> Signals.clear_slots a.slots)
;;

(* Slots first, for every controller, and only then the disconnecting and detaching:
   [gtk_widget_remove_controller] can provoke a leave or a cancel, and one still-armed
   slot on a *different* controller of the same widget would reach Bonsai from inside
   teardown. Emptying all of them up front is what makes that impossible. *)
let release t =
  clear t;
  Option.iter t.click ~f:(fun a ->
    Signals.disconnect a.connections;
    W.Widget.remove_controller t.widget (a.controller :> W.Event_controller.t));
  t.click <- None;
  Option.iter t.focus ~f:(fun a ->
    Signals.disconnect a.connections;
    W.Widget.remove_controller t.widget (a.controller :> W.Event_controller.t));
  t.focus <- None
;;

let attached_count t =
  List.count [ Option.is_some t.click; Option.is_some t.focus ] ~f:Fn.id
;;

let is_ours (c : W.Event_controller.t) =
  match W.Event_controller.get_name c with
  | None -> false
  | Some name -> String.is_prefix name ~prefix:name_prefix
;;
