### Task 4: The existential event spec, and click and focus controllers

The mechanism the rest of M2 is built on, plus the two controller families whose callbacks return `unit` — so the mechanism lands with consumers but without the extra complication of a return value, which Task 5 adds.

M1's `Signals.spec.fire` takes the widget and reads the value back off it with a class getter, because GTK's callbacks mostly carry no payload. Three M2 signals break that: `GtkListBox::row-activated` hands over a row that is gone by the time anything could read it back, `GtkGestureClick::pressed` carries coordinates the widget does not store, and `GtkEventControllerKey::key-pressed` carries a keyval *and wants a `bool` back*. All three need the arguments GTK passed, so `spec` grows a variant that keeps them.

**Files:**
- Modify: `src/signals.ml`, `src/signals.mli`, `src/patcher.ml`, `src/patcher.mli`, `src/gtk_import.ml`, `src/gtk_import.mli`, `src/attr_apply.ml`, `vtree/attr.ml`, `vtree/attr.mli`, `vtree/events.ml`, `vtree/bonsai_gtk_vtree.ml`, `src/bonsai_gtk.ml`, `src/bonsai_gtk.mli`, `test_lib/bonsai_gtk_test.ml`, `test_lib/bonsai_gtk_test.mli`, `test/test_attrs.ml`, `test/handle/test_handle.ml`, `test/live/dune`, `test/live/live_events.ml`
- Create: `vtree/phase.ml`, `vtree/modifiers.ml`, `vtree/modifiers.mli`, `vtree/click_event.ml`, `src/controllers.ml`, `src/controllers.mli`, `test/live/live_controllers.ml`, `test/live/expected_controllers.txt`

**Interfaces:**
- Produces:
  ```ocaml
  (* Signals *)
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

  val spec_attr : spec -> Attr.Name.t

  (* Controllers *)
  type t
  val create : Signals.ctx -> node_path:string -> Widget.t -> t
  val update : t -> Attrs.t -> unit
  val release : t -> unit

  (* vtree/phase.ml *)
  type t = Capture | Bubble | Target [@@deriving sexp_of, equal, compare]

  (* vtree/modifiers.mli *)
  type t = { shift : bool; control : bool; alt : bool; super : bool; hyper : bool; meta : bool }
  val none : t
  val equal : t -> t -> bool

  (* vtree/click_event.ml *)
  type t =
    { button : int; n_press : int; x : float; y : float; modifiers : Modifiers.t }
  [@@deriving sexp_of]

  (* Attr *)
  val on_click : ?button:int -> ?phase:Phase.t -> Click_event.t Handler.t -> t
  val on_focus_enter : unit Handler.t -> t
  val on_focus_leave : unit Handler.t -> t
  ```
- Consumes: `W.Gesture_click.{new_,on_pressed}`, `W.Gesture_single.{set_button,get_current_button}`, `W.Event_controller_focus.{new_,on_enter,on_leave}`, `W.Event_controller.{set_propagation_phase,get_current_event_state}`, `W.Widget.{add_controller,remove_controller}`, `Ocgtk_gdk.Gdk_enums.modifiertype`.

**Three shape decisions, each of which a reviewer should push on:**

1. **`declined` is a field, not a `default` computed from `'r`.** When the slot is empty, when `in_patch` is set, or when `fire` raises, the trampoline still owes GTK a return value. For a `unit` payload that is `()`; for `key-pressed` it is `false` (propagate), and getting it wrong the other way would make a widget with no handler swallow every key it sees. It is data on the spec because the *safe* answer differs per signal and nothing else knows it.

2. **`fire` returns `'r * unit Ui_effect.t option`, not `'r Ui_effect.t`.** The return value has to reach GTK *synchronously*, on the C stack, and a Bonsai effect is scheduled and performed later. So the decision ("do I consume this key") is made from the event, purely, in the trampoline; the consequence (a state update) is an effect like any other. This is exactly the shape stavekeeper's `dialog.ml:44-47` already has by hand — `if keyval = key_escape then (win#close (); true) else false` — and Task 5's `Key_response.t` is that shape given a name.

3. **Controllers are attached on demand, not per widget.** The alternative is attaching three controllers to every widget at `create` so that `Signals.connect_all` can own them uniformly. That is three GObjects per widget for a feature most widgets never use, on a library whose whole selling point over immediate-mode GTK is that a frame is cheap. `Controllers` instead creates a controller the first time its attr appears and removes it when the last of its attrs goes away — and then hands the connecting to `Signals.connect_all` anyway, so the trampoline, the slots, the `in_patch` guard, the exception guard and the disconnect-from-the-right-object rule are all the existing code.

- [ ] **Step 1: Write the failing tests**

`test/test_attrs.ml` — the attrs are values before they are behaviour:

```ocaml
let%expect_test "controller attrs round-trip and diff" =
  let click = Attr.on_click ~button:2 (fun _ -> Ui_effect.Ignore) in
  let attrs = Attrs.of_list [ click; Attr.on_focus_enter (fun () -> Ui_effect.Ignore) ] in
  print_s [%sexp (attrs : Attrs.t)];
  [%expect {| |}];
  (* A handler that changed is a Set; a handler that is physically the same is not.
     Handlers compare physically (spec §5.2), so a view that rebuilds its closures every
     frame writes the slot every frame -- which is a slot write, not a GTK call. *)
  print_s [%sexp (Attrs.diff ~old:attrs ~new_:(Attrs.of_list [ click ]) : Attrs.op list)];
  [%expect {| |}]
;;
```

`test/live/live_controllers.ml` — the real thing. This file grows in Task 5; start it with click and focus:

```ocaml
open! Core
open Bonsai_gtk_vtree
module Gobject = Bonsai_gtk.Private.Gtk_import.Gobject
module Live_tree = Bonsai_gtk.Private.Live_tree
module P = Bonsai_gtk.Private.Patcher
module Scheduler = Bonsai_gtk.Private.Scheduler
module W = Bonsai_gtk.Private.Gtk_import.W

let () =
  ignore (Ocgtk_gtk.GMain.init () : string array);
  let events = ref [] in
  let record s = events := s :: !events in
  let scheduler = Scheduler.create ~run_frame:(fun () -> ()) in
  let ctx =
    P.create_ctx
      ~signals:
        { schedule = (fun e -> Ui_effect.Expert.eval e ~f:Fn.id)
        ; in_patch = (fun () -> Scheduler.in_patch scheduler)
        ; on_exn = (fun ~node_path exn -> printf "EXN at %s: %s\n" node_path (Exn.to_string exn))
        }
      ~on_window_created:(fun _ -> ())
  in
  (* A button with a click gesture and a focus controller. The gesture is on the button,
     not on the window, so the dump shows where the controller went -- [Live_tree] cannot
     see controllers, so what this test asserts is *behaviour*, by emitting. *)
  let view ~with_click =
    Node.window
      ~title:"controllers"
      (Node.button
         ~attrs:
           (List.filter_opt
              [ Some (Attr.on_focus_enter (fun () -> record "focus-enter"; Ui_effect.Ignore))
              ; Some (Attr.on_focus_leave (fun () -> record "focus-leave"; Ui_effect.Ignore))
              ; (if with_click
                 then
                   Some
                     (Attr.on_click (fun (e : Click_event.t) ->
                        record (sprintf "click b%d n%d ctrl=%b" e.button e.n_press e.modifiers.control);
                        Ui_effect.Ignore))
                 else None)
              ])
         ~label:"target"
         ())
  in
  let live = P.mount ctx ~path:"root" ~is_root:true (view ~with_click:true) in
  P.run_fixups ctx;
  print_s (Live_tree.dump live.widget);
  ...
```

Emitting a real click is the hard part and the plan must say how, because "call `emit_by_name`" does not work: `Gobject.Signal.emit_by_name` takes no arguments and returns unit, so it cannot deliver `~n_press ~x ~y`. Three options, in preference order:

- **(a) Drive it through `Widget.activate`** for the *focus* controller (`grab_focus` really does emit `enter`), and for the click gesture accept that a synthetic press needs an event. Test what can be tested honestly.
- **(b) `Gtk.Test`** — check `.ocgtk-src` for a `gtk_test_widget_click` binding. If it exists, use it; if not, say so.
- **(c) Assert the *plumbing* rather than the emission**: that attaching the attr adds a controller (count `Widget`'s controllers — check whether `Widget.observe_controllers` or a list accessor is bound; if not, this is unobservable), that removing the attr removes it, and that the widget survives both.

**Run the pre-flight-style check first**: `grep -rn 'controller' .ocgtk-src/ocgtk/src/gtk/generated/event_controller_and__*.mli | grep -i 'list\|observe\|n_controllers'` and `ls .ocgtk-src/ocgtk/src/gtk/generated/ | grep -i test`. Then pick, and **write down in the task report which of the three you got**. If only (c) is available, the honest live test asserts attach/detach and lifetime, and the *handler* behaviour is proved headlessly by Task 4's `Bonsai_gtk_test` action instead — which is a real test of the handler and a real gap on the GTK half, and the gap goes in the backlog. Do not fake a click by calling the handler directly and then claim the controller works.

What is certainly testable, and must be:

```ocaml
  (* Dropping the attr must remove the controller and disconnect its handler. Nothing
     observes a removed controller directly, so this asserts the consequence that matters:
     the widget is still alive, still patchable, and a later frame can add the attr back
     and get a working controller again. A leaked controller would keep a slot -- and the
     closure it captured -- alive as a GC root for the widget's lifetime. *)
  let live = Scheduler.with_patch_guard scheduler (fun () ->
    P.patch ctx ~path:"root" ~is_root:true live (view ~with_click:false))
  in
  let live = Scheduler.with_patch_guard scheduler (fun () ->
    P.patch ctx ~path:"root" ~is_root:true live (view ~with_click:true))
  in
  print_s (Live_tree.dump live.widget);
  P.destroy ctx live;
  printf "destroyed cleanly\n"
```

`test/handle/test_handle.ml` — the headless half, which is where an application's key and click logic is actually tested:

```ocaml
let%expect_test "a click action carries the button and the modifiers" =
  let app (graph @ local) =
    let log, set_log = Bonsai.state [] graph in
    let%arr log and set_log in
    Node.window ~title:"clicks"
      (Node.box ~orientation:Vertical
         [ Node.label ~attrs:[ Attr.test_id "card"
                             ; Attr.on_click (fun (e : Click_event.t) ->
                                 set_log (sprintf "b%d shift=%b" e.button e.modifiers.shift :: log))
                             ] "card"
         ; Node.label ~attrs:[ Attr.test_id "log" ] (String.concat ~sep:"," log)
         ])
  in
  let handle = Bonsai_gtk_test.create app in
  Bonsai_gtk_test.Handle.show handle;
  [%expect {| |}];
  Bonsai_gtk_test.Handle.do_actions handle
    [ Click_at ("card", { button = 2; n_press = 1; x = 0.; y = 0.; modifiers = Modifiers.none }) ];
  Bonsai_gtk_test.Handle.show_diff handle;
  [%expect {| |}]
;;
```

This is stavekeeper's `library_window.ml:166-185` in miniature — middle click, or button 1 with shift, pops the piece out — and it is the whole reason the payload carries `button` and `modifiers`.

- [ ] **Step 2: Run to verify failure** — unbound `Attr.on_click`, unbound `Click_event`.

- [ ] **Step 3: `vtree/phase.ml`, `modifiers.ml(i)`, `click_event.ml`**

```ocaml
(* vtree/phase.ml *)
open! Core

(** Where in GTK's event routing a controller runs.

    [Capture] runs top-down, from the toplevel toward the target, and is what a window-wide
    Escape handler wants: it sees the key before anything a child added later can swallow
    it (stavekeeper's [dialog.ml] says exactly this, in a comment, having learned it the
    hard way). [Bubble] — GTK's default — runs bottom-up from the target, so the innermost
    widget gets first refusal, which is what a per-widget shortcut wants. [Target] runs
    only when the widget *is* the event's target.

    GTK's [`NONE] is deliberately absent: a controller in that phase never fires, which is
    what omitting the attribute already says, more clearly. *)
type t =
  | Capture
  | Bubble
  | Target
[@@deriving sexp_of, equal, compare]
```

```ocaml
(* vtree/modifiers.mli *)
open! Core

(** Which modifier keys were down.

    A record of bools rather than a set or a mask, because [vtree] cannot name GDK's
    [modifiertype] (which is a list of polymorphic variants) and because the question an
    application asks is always "was control down", never "give me the mask". The runtime
    converts at the boundary.

    Lock (caps lock) and the five button masks GDK also reports are deliberately absent:
    they are pointer and keyboard *state*, not modifiers a shortcut is keyed on, and
    including them would put a bit in every comparison that nothing wants to compare. If
    one is ever needed it goes here with a note, not into an escape hatch. *)
type t =
  { shift : bool
  ; control : bool
  ; alt : bool
  ; super : bool
  ; hyper : bool
  ; meta : bool
  }
[@@deriving sexp_of, equal, compare]

(** No modifier down. What a synthetic event in a headless test usually wants. *)
val none : t
```

`click_event.ml` is the record above with `[@@deriving sexp_of, equal]`. `x` and `y` are in the widget's own coordinates, and the doc says so — a gesture attached to a card reports coordinates within that card, which is what makes a per-card gesture useful (stavekeeper's `library_window.ml:155-159` comment explains why it attaches per card rather than to the FlowBox).

- [ ] **Step 4: `vtree/attr.ml(i)` — three attrs, and where their names go in the order**

`Attr.Name.t` gains, adjacent to each other and *after* the existing `On_*` names (so no existing `Attrs.diff` output reorders):

```ocaml
  | On_click
  | On_focus_enter
  | On_focus_leave
  (* Task 5 adds On_key_pressed, On_key_released here *)
```

and `Attr.t`:

```ocaml
  | On_click of
      { button : int
      ; phase : Phase.t
      ; handler : Click_event.t Handler.t
      }
  | On_focus_enter of unit Handler.t
  | On_focus_leave of unit Handler.t
```

`On_click` carries its `button` and `phase` in the constructor because they are properties of the *controller*, not of the handler, and `Controllers.update` needs to see a change in either without the handler having to change. `equal` compares `button`, `phase` and the handler physically.

Constructors:
```ocaml
val on_click : ?button:int -> ?phase:Phase.t -> Click_event.t Handler.t -> t
(** A [GtkGestureClick] on this widget.

    [button] is which mouse button to listen for; [0] (the default) means all of them, and
    the one that was pressed arrives in {!Click_event.button}. [phase] defaults to
    {!Phase.Bubble}, GTK's own — a gesture on a card in a selection container wants bubble,
    so that the container's own selection gesture still runs.

    The gesture does {i not} claim the event sequence, so a click also reaches whatever
    else would have handled it. That is deliberate and is what lets a card carry a
    middle-click handler without breaking its list box's click-to-select; an application
    that wants to consume the click has no way to say so in M2, which is named in the
    README's Limitations. *)

val on_focus_enter : unit Handler.t -> t
val on_focus_leave : unit Handler.t -> t
(** A [GtkEventControllerFocus] on this widget. [on_focus_enter] fires when focus moves
    into the widget {i or any of its children} — which is the useful sense for a composite
    widget like a [GtkSearchEntry], whose own [has_focus] is always false because its
    inner [GtkText] holds the focus.

    Both are attached to one controller, so a widget carrying either pays for one. *)
```

`Events`: add the arm from Task 1's Step 5 —

```ocaml
(* The controller attrs are legal on every kind: they are not any impl's signal, they are
   a [GtkEventController] the runtime attaches to whatever widget carries the attr. So
   [is_supported] short-circuits on them rather than consulting [for_kind], and no impl
   may declare one in its [Widget_impl.signals] -- [test/live/live_events.ml] asserts
   that, because an impl that did would connect a second handler nobody removes. *)
let is_controller_attr : Attr.Name.t -> bool = function
  | On_click | On_focus_enter | On_focus_leave -> true
  | _ -> false
;;
```

- [ ] **Step 5: `src/signals.ml(i)` — the variant**

The `Read_back` arm's trampoline is M1's, unchanged. The `Payload` arm's:

```ocaml
let dispatch_payload ctx ~node_path ~declined ~fire w slot p =
  (* Same five obligations as the read-back trampoline (spec §6.4), plus a sixth: whatever
     happens, GTK gets a value back. An exception here must not cross into C, and the
     value it returns instead has to be the *safe* one -- for a key controller that is
     "propagate", because a handler that raised has certainly not handled the key. *)
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
    ctx.on_exn ~node_path exn;
    declined
;;
```

`connect_all` matches on the variant and builds the right callback; `update_slots` and `clear_slots` are unchanged (a slot is a slot). `spec_attr` becomes `function Read_back r -> r.attr | Payload p -> p.attr`.

The mli's `spec` doc gains:

```ocaml
(** [Read_back] is the ordinary shape: GTK's callback carries nothing and the value the
    user just changed lives on the widget, so [fire] reads it back with the class getter.
    Every M1 signal is one of these, and so is every [notify::] one, whose generic
    marshaller carries nothing at all.

    [Payload] is for the signals whose arguments cannot be recovered afterwards. Three
    exist in M2: [GtkListBox::row-activated] (the row is gone by the time anything could
    look for it), [GtkGestureClick::pressed] (the coordinates are not stored anywhere), and
    [GtkEventControllerKey::key-pressed] (the keyval, and a [bool] GTK wants back). ['p] is
    the payload the [connect] closure assembles — it may combine the callback's arguments
    with things read off the object, which is how a click's [button] and [modifiers] get
    in — and ['r] is what the callback returns to GTK.

    [declined] is that return value for the emissions that reach no handler: an empty
    slot, an emission during a patch, or a [fire] that raised. It must be the *inert*
    answer for the signal — [false] ("not handled") for a key controller — because those
    three cases are precisely the ones where the application has said nothing. *)
```

- [ ] **Step 6: `src/gtk_import.ml(i)` — the GDK aliases**

```ocaml
module Gdk_enums = Ocgtk_gdk.Gdk_enums
module Gdk_constants = Ocgtk_gdk.Gdk_constants
```

with a comment: the class modules come from `Ocgtk_gdk.Gdk.Wrappers` but the enums and constants are top-level in `Ocgtk_gdk`, which is not the shape `Gtk` has, and forgetting that costs ten minutes each time.

- [ ] **Step 7: `src/controllers.ml(i)`**

```ocaml
(** The [GtkEventController]s attached to one widget on account of its attributes.

    Unlike a widget's own signals — connected once at [create] for every spec its impl
    declares — a controller exists only while an attribute asks for one. Three reasons it
    is not simply "attach all of them to every widget": three GObjects per widget is a real
    cost on a library whose claim is that a frame is cheap; a controller's propagation
    phase is part of the attribute, so there is no phase to pick before the attribute
    exists; and a widget with no key handler should not appear in GTK's capture chain at
    all.

    What it is {i not} is a second signal mechanism. The connecting, the slots, the
    [in_patch] guard, the exception guard and the disconnect-from-the-object-that-issued-
    the-id rule are all [Signals]; this module decides only which controllers should exist
    and owns their attach/detach. *)
type t

(** Attaches nothing. Call once per widget, at mount, right after [Signals.connect_all];
    the first {!update} creates whatever the attrs ask for. *)
val create : Signals.ctx -> node_path:string -> Widget.t -> t

(** Brings the attached controllers into line with [attrs]: creates one whose attrs have
    appeared, removes one whose attrs have all gone, re-points the handler slots, and
    re-applies the propagation phase and the gesture's button.

    A phase or button change re-applies the setter rather than rebuilding the controller —
    both are plain properties and GTK re-reads them per event. Cheap enough to do
    unconditionally, which is what this does: comparing first would mean storing the old
    attr, and the setter on an unchanged value is free.

    Called at mount after {!create}, and on every patch whose attrs differ. *)
val update : t -> Attrs.t -> unit

(** Empties every slot, disconnects, and removes every controller from the widget.

    The slot-emptying is first and is the load-bearing half: [gtk_widget_remove_controller]
    can itself provoke a leave or a cancel, and a slot still armed then would reach Bonsai
    from inside teardown. Same rule, same reason, as [Signals.clear_slots]. *)
val release : t -> unit
```

Implementation shape:

```ocaml
type attached =
  { controller : W.Event_controller.t
  ; slots : Signals.slots
  ; connections : Signals.connection list
  }

type t =
  { ctx : Signals.ctx
  ; node_path : string
  ; widget : Widget.t
  ; mutable click : attached option
  ; mutable focus : attached option
  (* Task 5 adds [mutable key : attached option] *)
  }
```

and one helper per family:

```ocaml
(* [wanted] is whether any of this family's attrs is present. Attach on the first, detach
   on the last, and in between only re-slot. *)
let sync t ~wanted ~get ~set ~make ~specs attrs =
  match get t, wanted with
  | None, false -> ()
  | Some a, false ->
    Signals.clear_slots a.slots;
    Signals.disconnect a.connections;
    W.Widget.remove_controller t.widget a.controller;
    set t None
  | Some a, true -> Signals.update_slots a.slots attrs
  | None, true ->
    let controller = make () in
    W.Widget.add_controller t.widget controller;
    let slots, connections =
      Signals.connect_all t.ctx ~node_path:t.node_path t.widget (specs controller)
    in
    Signals.update_slots slots attrs;
    set t (Some { controller; slots; connections })
;;
```

Note what `specs controller` does: it builds `Signals.spec`s whose `connect` **ignores the widget it is handed** and connects to the captured controller instead, returning `Signals.connected controller id`. That is exactly what `Signals.connection` was widened for in M1's fix wave, and it is why `Controllers` needs no new disconnect machinery.

The click spec:

```ocaml
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
                  are gone. *)
               let button = W.Gesture_single.get_current_button (gc :> W.Gesture_single.t) in
               let modifiers =
                 Modifiers.of_gdk
                   (W.Event_controller.get_current_event_state (gc :> W.Event_controller.t))
               in
               callback ({ button; n_press; x; y; modifiers } : Click_event.t))))
    ; fire =
        (fun _w attr (e : Click_event.t) ->
          match (attr : Attr.Private.t) with
          | On_click { handler; _ } -> (), Some (handler e)
          | _ -> (), None)
    ; declined = ()
    }
;;
```

`Modifiers.of_gdk` lives in `src/` (it names `Gdk_enums.modifiertype`), not in `vtree`. Put it in `src/controllers.ml` or, better, in `src/gtk_import.ml` beside the other conversions, so Task 5 can use it too.

Wire `Controllers` into `Patcher.live` as a field, created in `mount` after `Signals.connect_all`, `update`d in `patch` on the same condition that re-runs `Signals.update_slots`, and `release`d in `destroy` alongside `clear_slots`/`disconnect`. **Check the ordering in `destroy` carefully**: `patcher.mli` promises that on the paths where a subtree is unparented before being destroyed, the slots of the whole subtree are emptied *before* the unparenting. Controllers must obey the same promise, so whatever helper does the pre-emptying (`disarm`) gains a `Controllers.clear` — a slot-emptying without the detaching, since the detaching happens in `destroy`. If `release` is the only entry point, split it.

- [ ] **Step 8: `test_lib` — the `Click_at` and focus actions**

```ocaml
| Click_at of string * Click_event.t
(** test_id of a node carrying [Attr.on_click], and the click to deliver. Fires that
    handler with exactly that event; nothing is derived from the node, and in particular
    the [button] the attr was constructed with is {i not} consulted — a headless test that
    delivers button 3 to a [~button:1] gesture is testing its own handler, not GTK's
    filtering, and pretending otherwise would make the action's behaviour depend on a
    detail no headless model has. Build the event with {!Bonsai_gtk_vtree.Click_event}'s
    record and {!Modifiers.none}. *)

| Focus_enter of string
| Focus_leave of string
(** test_id of a node carrying the matching attr. *)
```

- [ ] **Step 9: Run, read, promote, gate**

`live_events.ml` gains the assertion that no impl declares a controller attr. Every other expected file unchanged.

- [ ] **Step 10: Commit**

```bash
dune fmt 2>/dev/null; git add vtree src test test_lib
GIT_EDITOR=true git commit -F - <<'MSG'
Signals carry their own arguments, and widgets carry event controllers

[Signals.spec] becomes a variant. [Read_back] is M1's shape -- GTK's callback
carries nothing and [fire] reads the value off the widget -- and the new
existential [Payload] keeps the arguments GTK passed and hands a value back to
GTK. Three M2 signals need it: a list box's activated row, a click's
coordinates, and (next task) a key press, which also wants a bool returned
synchronously while its effect is scheduled as usual.

[Controllers] attaches a GtkGestureClick or a GtkEventControllerFocus to a
widget when [Attr.on_click] / [Attr.on_focus_enter] / [on_focus_leave] appears
and removes it when the last of them goes, reusing [Signals]' trampolines,
slots, guards and disconnect rules underneath rather than growing a second
mechanism.

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01Sg3Ci8U8kUKR8C3PL1pNSs
MSG
```

**Review focus:** that a removed controller's slot is emptied *before* `remove_controller`, and that `destroy`'s pre-unparent emptying covers controllers too; that `Payload`'s trampoline returns `declined` on all three of the paths it is supposed to (empty slot, in_patch, exception) — the reviewer should be able to point at each; that `connect` assembling the payload (rather than `fire`) is what makes `button` and `modifiers` readable at all, and that the comment says so; that no controller attr appears in any impl's `signals`; that the live test's method of provoking a click is honestly described, and that if it is option (c) the gap is in the backlog rather than papered over.

---

