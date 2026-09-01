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

(* The Shortcut family's live state, and it is not an [attached]: there is
   {b no slot and no trampoline} -- a shortcut fires a {i named action}, so the firing
   path is GTK -> [GtkNamedAction] -> the [Actions] group's activate trampoline, which
   already obeys the five rules. This family's whole job is attach/detach/diff, and
   [installed] is the diff's memory: [remove_shortcut] needs the very [Shortcut.t] that
   was added, keyed here by the (trigger, action) pair the vtree spelled. *)
type shortcut_family =
  { controller : W.Shortcut_controller.t
  ; mutable installed : ((Trigger.t * string) * W.Shortcut.t) list
  }

type t =
  { ctx : Signals.ctx
  ; node_path : string
  ; widget : Widget.t
  ; mutable click : W.Gesture_click.t attached option
  ; mutable focus : W.Event_controller_focus.t attached option
  ; mutable key : W.Event_controller_key.t attached option
  ; mutable shortcut : shortcut_family option
  }

let create ctx ~node_path widget =
  { ctx; node_path; widget; click = None; focus = None; key = None; shortcut = None }
;;

(* GTK's own debugging label, and the only way to tell a controller this library attached
   from one the widget class attached itself: a [GtkButton] ships with a
   [GtkGestureClick], a [GtkEventControllerKey] and a [GtkShortcutController] of its own,
   so "the widget has a GtkGestureClick" says nothing. The name shows up in GTK Inspector,
   and [test/live/live_controllers_util.ml] counts by it.

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
   [test/live/live_controllers_click.ml]'s heap-churn case is the regression test. *)
let name_prefix = "bonsai_gtk."

let set_name (c : W.Event_controller.t) suffix =
  W.Event_controller.set_name c (Some (name_prefix ^ suffix))
;;

(* Whether this family's controller should exist: exactly while at least one of the attrs
   [Events] assigns to it is present. Asking the table rather than naming the attrs here
   is what keeps "which attrs mean click" in one place -- an attr joining an existing
   family does so in [vtree/events.ml], and nothing in this file changes. *)
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
  | Key -> Option.map t.key ~f:(fun a -> a.slots)
  (* No slots to clear or arm: the shortcut family holds no handlers (see
     [shortcut_family]), so for slot-shaped questions it does not exist. *)
  | Shortcut -> None
;;

let clear t =
  List.iter Events.Family.all ~f:(fun family ->
    Option.iter (attached t family) ~f:Signals.clear_slots)
;;

let armed t =
  (List.concat_map Events.Family.all ~f:(fun family ->
     match attached t family with
     | None -> []
     | Some slots -> Signals.armed slots)
   @
   (* The shortcut family has no slots, so "armed" is answered from its own state: the
      name is listed exactly while shortcuts are installed, which is what the live dumps
      read. *)
   match t.shortcut with
   | Some { installed = _ :: _; _ } -> [ Attr.Name.Shortcut ]
   | Some { installed = []; _ } | None -> [])
  |> List.sort ~compare:Attr.Name.compare
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
    (* This family's slots only. Emptying every family's here would be wrong: [update]
       calls [sync] once per family in order, and each family's own [sync] is the only
       thing that re-arms it, so a family removed at iteration i would wipe the slots of
       every family already processed -- and nothing would re-arm them until the next
       patch of this node. The invariant that motivated the wider clear (no sibling slot
       armed while [remove_controller] runs, which can itself provoke a leave or a cancel)
       is kept by [update]'s single up-front [clear], which happens before any family is
       touched and is undone for the survivors by their own [update_slots]. *)
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
          | On_click { handler; _ } ->
            let response = handler e in
            (* Synchronously, on the C stack, while the sequence is still current: this is
               the whole reason the handler answers a [Click_response.t] rather than
               returning an effect. [set_state] answers whether the state could be
               changed, which nothing here can act on -- a sequence that is already
               claimed or denied stays that way -- so the [bool] is ignored by type. *)
            if Click_response.claim response
            then ignore (W.Gesture.set_state (gc :> W.Gesture.t) `CLAIMED : bool);
            (), Click_response.effect response
          | _ -> (), None)
        (* A [pressed] callback returns nothing to GTK, and the three no-handler paths
           claim nothing ([declined] is [Continue]-shaped), which preserves M2's
           behaviour: a click nobody answers still reaches whatever else would have
           handled it. [key_pressed_spec] below is where a [declined] {i value} earns its
           keep. *)
    ; declined = ()
    }
;;

(* [enter], [leave] and [contains-focus] ride on one [GtkEventControllerFocus], so a
   widget carrying any of the three attrs pays for one controller and gets all three
   specs; the slot of an attr that is absent is simply never filled.

   The third is a [notify::] on the {i controller} -- [contains-focus] is the controller's
   property, not the widget's -- so its connection names the controller, which is exactly
   what [Signals.connection] exists for, and its [fire] reads the property back off the
   captured controller because the generic marshaller carries nothing. Like every
   [notify::], it fires for the library's own doing as well as the user's (an
   [Attr.autofocus] grab included); the [in_patch] guard drops those. *)
let focus_specs (fc : W.Event_controller_focus.t) : Signals.spec list =
  [ Read_back
      { attr = Attr.Name.On_focus_enter
      ; connect =
          (fun _w ~callback ->
            [ Signals.connected fc (W.Event_controller_focus.on_enter fc ~callback) ])
      ; fire =
          (fun _w attr ->
            match (attr :> Attr.Private.t) with
            | On_focus_enter { handler; _ } -> Some (handler ())
            | _ -> None)
      }
  ; Read_back
      { attr = Attr.Name.On_focus_leave
      ; connect =
          (fun _w ~callback ->
            [ Signals.connected fc (W.Event_controller_focus.on_leave fc ~callback) ])
      ; fire =
          (fun _w attr ->
            match (attr :> Attr.Private.t) with
            | On_focus_leave { handler; _ } -> Some (handler ())
            | _ -> None)
      }
  ; Read_back
      { attr = Attr.Name.On_contains_focus_changed
      ; connect =
          (fun _w ~callback ->
            [ Signals.notify_connection ~prop:"contains-focus" fc ~callback ])
      ; fire =
          (fun _w attr ->
            match (attr :> Attr.Private.t) with
            | On_contains_focus_changed handler ->
              Some (handler (W.Event_controller_focus.contains_focus fc))
            | _ -> None)
      }
  ]
;;

(* The two key attrs on one [GtkEventControllerKey], and the only place in this library
   where a handler's answer reaches C.

   [key-pressed]'s callback returns a [bool] -- GTK routes the key on it -- so this is a
   [Payload] spec whose ['r] is [bool] and whose [declined] is [event_propagate]. That
   constant, rather than a bare [false], because the value is not "false" in any
   interesting sense: it is GDK's name for "I did not handle this, keep going", and
   getting it backwards would make a widget whose handler raised, or whose slot is empty,
   swallow every keystroke in the application. Those are precisely the three paths
   [Signals.dispatch_payload] returns [declined] on -- empty slot, emission during a
   patch, [fire] raised -- and on all three the application has said nothing.

   [keyval] and [keycode] are callback arguments, so unlike the click gesture there is
   nothing to read off the controller while the event is current; the modifiers come in as
   [~state] rather than being fetched. The payload is still assembled in [connect] because
   that is where the conversion from [Gdk_enums.modifiertype] belongs -- [vtree] cannot
   name that type. *)
(* [GDK_EVENT_PROPAGATE]. Named rather than written [false] at the two places it is
   needed, so that the spec's [declined] and this module's fallback are the same value by
   construction; [test/live/live_controllers_key.ml] pins it against [Gdk_constants]. *)
let key_pressed_declined = Gdk_constants.event_propagate

(* The whole of the decision, lifted out of the spec so that it can be called. It is the
   one link in the chain from [Key_response.t] to GTK's [key-pressed] return that no test
   could otherwise reach: [Key_response.handled] is pinned in [test/test_attrs.ml],
   [Signals.dispatch_payload]'s three [declined] paths in [live_signals.ml], and the
   callback's [bool] return type by the compiler -- but the mapping between them was
   reachable only through a key press, and there is no synthetic key press. Getting it
   backwards would make [Handled] fail to stop propagation, which is the whole point of
   the constructor. *)
let key_pressed_answer (attr : Attr.t) (e : Key_event.t) =
  match (attr :> Attr.Private.t) with
  | On_key_pressed { handler; _ } ->
    let response = handler e in
    Key_response.handled response, Key_response.effect response
  | _ -> key_pressed_declined, None
;;

let key_pressed_spec (kc : W.Event_controller_key.t) : Signals.spec =
  Payload
    { attr = Attr.Name.On_key_pressed
    ; connect =
        (fun _w ~callback ->
          Signals.connected
            kc
            (W.Event_controller_key.on_key_pressed
               kc
               ~callback:(fun ~keyval ~keycode ~state ->
                 callback
                   ({ keyval; keycode; modifiers = modifiers_of_gdk state } : Key_event.t))))
    ; fire = (fun _w attr e -> key_pressed_answer attr e)
    ; declined = key_pressed_declined
    }
;;

(* [key-released] returns [unit] to GTK -- a release cannot be consumed, the press it
   follows was routed long ago -- so its handler is an ordinary [Handler.t] and there is
   no unsafe answer to get wrong. It is still a [Payload] rather than a [Read_back]: the
   keyval is a callback argument and nothing on the controller remembers it afterwards. *)
let key_released_spec (kc : W.Event_controller_key.t) : Signals.spec =
  Payload
    { attr = Attr.Name.On_key_released
    ; connect =
        (fun _w ~callback ->
          Signals.connected
            kc
            (W.Event_controller_key.on_key_released
               kc
               ~callback:(fun ~keyval ~keycode ~state ->
                 callback
                   ({ keyval; keycode; modifiers = modifiers_of_gdk state } : Key_event.t))))
    ; fire =
        (fun _w attr e ->
          match (attr :> Attr.Private.t) with
          | On_key_released { handler; _ } -> (), Some (handler e)
          | _ -> (), None)
    ; declined = ()
    }
;;

let key_specs kc = [ key_pressed_spec kc; key_released_spec kc ]

(* One controller per family, one phase, and up to two attrs that can each ask for one.
   The rejection is [Events.family_phase_rejection] rather than a message built here,
   because [Bonsai_gtk_test] refuses the same node with the same string -- see that
   function.

   Raising from [configure] is raising from inside [update], which the patcher calls at
   mount and on every patch: the same place, and the same [Invalid_argument] carrying the
   node path, as every other structural rejection (spec §11). It runs before
   [add_controller] on the attach path, so a rejected node leaves nothing attached.

   Shared by the Focus and Key families, which are exactly the families whose phase comes
   from more than one attr; the click gesture's is a field of its one attr and
   [configure_click] writes it directly. *)
let configure_phase (c : W.Event_controller.t) (family : Events.Family.t) attrs ~node_path
  =
  Option.iter (Events.family_phase_rejection ~path:node_path family attrs) ~f:invalid_arg;
  match Events.family_phase family attrs with
  | Some phase -> W.Event_controller.set_propagation_phase c (propagation_phase phase)
  | None -> ()
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

(* The node's shortcut list, merged and deduplicated. Exact duplicates (same trigger, same
   action) collapse to one installed [Shortcut.t] -- two identical entries would be one
   assoc key anyway, and GTK running the action twice per press is nothing a caller can
   want. *)
let wanted_shortcuts attrs =
  match (Attrs.find attrs Attr.Name.Shortcut :> Attr.Private.t option) with
  | Some (Shortcut shortcuts) ->
    List.dedup_and_sort shortcuts ~compare:(fun (a : Attr.shortcut) b ->
      [%compare: Trigger.t * string] (a.trigger, a.action) (b.trigger, b.action))
  | Some _ | None -> []
;;

(* One GTK shortcut from vtree data: the trigger through [Keyval_trigger.new_] -- never
   [Shortcut_trigger.parse_string], whose non-option return wraps NULL on garbage
   (pre-flight correction 7) -- and the action through [Named_action.new_], which is the
   whole reason shortcuts route through the action system: the binding cannot build a
   [CallbackAction], so a shortcut cannot hold a closure. *)
let make_shortcut (s : Attr.shortcut) =
  let trigger =
    W.Keyval_trigger.new_ s.trigger.key (gdk_of_modifiers s.trigger.modifiers)
  in
  let action = W.Named_action.new_ s.action in
  W.Shortcut.new_
    (Some (trigger :> W.Shortcut_trigger.t))
    (Some (action :> W.Shortcut_action.t))
;;

(* The family's own sync: attach on the first shortcut, detach on the last, and diff by
   (trigger, action) in between -- remove departed, add new, leave survivors alone (a
   [GtkShortcut] is immutable in everything the vtree can say about it). The phase is
   re-applied from the attrs like the key family's, and the same
   [Events.family_phase_rejection] refuses a disagreement -- every entry shares this one
   controller. *)
let sync_shortcuts t attrs =
  Option.iter
    (Events.family_phase_rejection ~path:t.node_path Shortcut attrs)
    ~f:invalid_arg;
  let wanted = wanted_shortcuts attrs in
  match t.shortcut, wanted with
  | None, [] -> ()
  | Some f, [] ->
    W.Widget.remove_controller t.widget (f.controller :> W.Event_controller.t);
    t.shortcut <- None
  | None, wanted ->
    let controller = W.Shortcut_controller.new_ () in
    set_name (controller :> W.Event_controller.t) "shortcut";
    (match Events.family_phase Shortcut attrs with
     | Some phase ->
       W.Event_controller.set_propagation_phase
         (controller :> W.Event_controller.t)
         (propagation_phase phase)
     | None -> ());
    let installed =
      List.map wanted ~f:(fun s ->
        let sc = make_shortcut s in
        W.Shortcut_controller.add_shortcut controller sc;
        (s.trigger, s.action), sc)
    in
    W.Widget.add_controller t.widget (controller :> W.Event_controller.t);
    t.shortcut <- Some { controller; installed }
  | Some f, wanted ->
    (match Events.family_phase Shortcut attrs with
     | Some phase ->
       W.Event_controller.set_propagation_phase
         (f.controller :> W.Event_controller.t)
         (propagation_phase phase)
     | None -> ());
    let wanted_keys =
      List.map wanted ~f:(fun (s : Attr.shortcut) -> s.trigger, s.action)
    in
    let keep, drop =
      List.partition_tf f.installed ~f:(fun (key, _) ->
        List.mem wanted_keys key ~equal:[%equal: Trigger.t * string])
    in
    List.iter drop ~f:(fun (_, sc) ->
      W.Shortcut_controller.remove_shortcut f.controller sc);
    let added =
      List.filter_map wanted ~f:(fun s ->
        let key = s.trigger, s.action in
        if List.Assoc.mem keep key ~equal:[%equal: Trigger.t * string]
        then None
        else (
          let sc = make_shortcut s in
          W.Shortcut_controller.add_shortcut f.controller sc;
          Some (key, sc)))
    in
    f.installed <- keep @ added
;;

(* One [sync] per family, dispatched from an exhaustive match on [Events.Family.t].

   The match is the point. [Events.controller_family] is what makes a controller attr
   legal on every kind, skipped by [Signals.require_slots], and connected by no widget
   impl; this is the other end of that, and without the exhaustiveness a family could be
   named there and attached by nothing -- accepted everywhere, wired nowhere, with no
   diagnostic. Adding [Key] to the variant was four compile errors, of which this match
   was one. *)
let update t attrs =
  (* Once, before any family is touched, rather than inside [sync]'s removal branch.

     Two things have to hold at the same time and only this ordering gets both. No slot
     may be armed while [gtk_widget_remove_controller] runs, because it can itself provoke
     a leave or a cancel and a sibling family's handler would then reach Bonsai from
     inside a patch -- that is the invariant [release] states and it is why the emptying
     is wide. And every family that *survives* this frame has to end it armed -- so the
     emptying cannot happen between two families' [sync] calls, where it would undo the
     arming the earlier ones just did. Up front satisfies both: each surviving family's
     own [update_slots], below, re-arms it.

     Unconditional rather than "only when some family is going away": the condition is one
     more thing to get wrong, and the cost is a walk of at most three short assoc lists
     per patched node. *)
  clear t;
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
        ~configure:(fun fc attrs ->
          configure_phase (fc :> W.Event_controller.t) Focus attrs ~node_path:t.node_path)
        ~name:"focus"
        attrs
    | Key ->
      sync
        t
        ~wanted
        ~get:(fun t -> t.key)
        ~set:(fun t a -> t.key <- a)
        ~make:W.Event_controller_key.new_
        ~upcast:(fun kc -> (kc :> W.Event_controller.t))
        ~specs:key_specs
        ~configure:(fun kc attrs ->
          configure_phase (kc :> W.Event_controller.t) Key attrs ~node_path:t.node_path)
        ~name:"key"
        attrs
    | Shortcut ->
      (* Its own sync, not the generic one: no slots, no specs, and the diff is over a
         list of GTK objects rather than a handler cell. [wanted] is unused because the
         family decides from the merged list itself. *)
      ignore (wanted : bool);
      sync_shortcuts t attrs)
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
      t.focus <- None
    | Key ->
      Option.iter t.key ~f:(fun a -> detach a (fun c -> (c :> W.Event_controller.t)));
      t.key <- None
    | Shortcut ->
      (* Nothing to disconnect: the family holds no signal connections (the firing path is
         GTK's, into [Actions]' trampoline), so detaching is the whole teardown. *)
      Option.iter t.shortcut ~f:(fun f ->
        W.Widget.remove_controller t.widget (f.controller :> W.Event_controller.t));
      t.shortcut <- None)
;;

(* Derived from the same [Events.Family.t] match as everything else here, so a family that
   is added and then not counted is not a possible state. *)
let attached_count t =
  List.count Events.Family.all ~f:(fun family ->
    match family with
    | Shortcut -> Option.is_some t.shortcut
    | Click | Focus | Key -> Option.is_some (attached t family))
;;

let is_ours (c : W.Event_controller.t) =
  match W.Event_controller.get_name c with
  | None -> false
  | Some name -> String.is_prefix name ~prefix:name_prefix
;;
