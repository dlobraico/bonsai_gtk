open! Core
open Bonsai_gtk_vtree
module Controllers = Bonsai_gtk.Private.Controllers
module List_model = Ocgtk_gio.Gio.Wrappers.List_model
module Gobject = Bonsai_gtk.Private.Gtk_import.Gobject
module Live_tree = Bonsai_gtk.Private.Live_tree
module P = Bonsai_gtk.Private.Patcher
module Scheduler = Bonsai_gtk.Private.Scheduler
module W = Bonsai_gtk.Private.Gtk_import.W

let cast = Bonsai_gtk.Private.Gtk_import.cast

(* What this file can and cannot prove, stated once so that a reader of the golden is not
   misled by it.

   {b There is no synthetic click or key press in the pinned ocgtk binding.} There is no
   [GdkEvent] constructor for any event subtype; [Gobject.Signal.emit_by_name] takes no
   arguments and returns unit, so it cannot deliver [~n_press ~x ~y] or
   [~keyval ~keycode ~state]; and [Event_controller_key.forward] only re-routes an event a
   controller is {i already handling}, which is a thing that can only be true inside a
   handler this file cannot cause to run. So no test anywhere can make GTK route a real
   button press or keystroke to a controller this library attached. What this file proves
   for {b click} and {b key} is therefore the plumbing: that the attr attaches a
   controller, that dropping it removes one, that the gesture's button and the
   controller's propagation phase reach GTK, that the slot is armed (which is a different
   fact from the controller being attached, and the only one that says the handler would
   be called), and that the widget survives all of it. The handler half is proved
   headlessly, in [test/handle/test_handle.ml]'s "a click action carries the button and
   the modifiers" and "Escape is handled, other keys propagate", and the trampoline that
   stands between them -- slots, the [in_patch] guard, the exception guard, the value
   handed back to GTK -- in [live_signals.ml]. The gap between those and "GTK really
   routes a middle click, or an Escape, here" is real and is in the backlog.

   {b Focus is different}: [Widget.grab_focus] is a real focus-chain operation, so on a
   presented window it drives [GtkEventControllerFocus] for real. The focus half of this
   file is end-to-end. *)

(* The controllers GTK reports on [w] that this library attached, by the debugging name
   [Controllers] sets on each. Counting by name rather than by class or by total is what
   makes the numbers below mean anything: a [GtkButton] ships with a [GtkGestureClick], a
   [GtkEventControllerKey] and a [GtkShortcutController] of its own, so "the widget has a
   GtkGestureClick" is true before this library does anything, and the total would move
   the day a GTK release changes how many a button has. *)
let all_controllers w =
  let model = W.Widget.observe_controllers w in
  List.init (List_model.get_n_items model) ~f:(List_model.get_object model)
  |> List.filter_opt
  |> List.map ~f:cast
;;

let ours w = List.filter (all_controllers w) ~f:Controllers.is_ours

let names w =
  List.map (ours w) ~f:(fun c ->
    Option.value ~default:"?" (W.Event_controller.get_name c))
;;

(* GTK's own answer beside this library's bookkeeping, compared on every line: a
   controller [Controllers] forgot to remove would show up as a difference between them,
   and a controller it removed from the wrong widget as a difference in [gtk]. *)
(* GTK's own answer beside this library's bookkeeping, compared on every line, plus the
   raw total. [total] earns its place on one line in particular: [after destroy] has no
   [bonsai=] counterpart to disagree with it, so a bare name-filtered count there would
   read zero both when the controllers were removed and when their *names* merely became
   unreadable -- which is exactly the failure the previous [set_static_name] bug produced.
   The total does not go through [get_name] at all, so the two together say which
   happened. It also puts the [GtkButton]'s own three controllers in the golden, which is
   the whole reason the filter exists. *)
let controllers label (live : P.live) w =
  printf
    !"%s: gtk=%{sexp: string list} bonsai=%d total=%d armed=%{sexp: Attr.Name.t list}\n"
    label
    (names w)
    (Controllers.attached_count live.controllers)
    (List.length (all_controllers w))
    (Controllers.armed live.controllers)
;;

(* [~button] and [~phase] are read back off the live [GtkGestureClick] rather than
   trusted. Since no click can be delivered through this binding, this is the only
   evidence there is that the two controller-level settings on [Attr.on_click] reach GTK
   at all -- and the only thing that would catch [Controllers] setting them on the wrong
   object, or not at all. The button's *own* gesture is excluded by the name filter, which
   is also why its defaults cannot be mistaken for ours. *)
let click_gesture_props label w =
  match
    List.find (ours w) ~f:(fun c ->
      String.equal (Gobject.Type.name (Gobject.get_type c)) "GtkGestureClick")
  with
  | None -> printf "%s: no gesture of ours\n" label
  | Some o ->
    let phase =
      match W.Event_controller.get_propagation_phase o with
      | `NONE -> "NONE"
      | `CAPTURE -> "CAPTURE"
      | `BUBBLE -> "BUBBLE"
      | `TARGET -> "TARGET"
    in
    printf "%s: button=%d phase=%s\n" label (W.Gesture_single.get_button (cast o)) phase
;;

(* The same read-back for the key controller, and it matters more than the gesture's: a
   key controller in the wrong phase is the failure stavekeeper's [dialog.ml] comment is
   entirely about. In BUBBLE, GTK runs the *last* controller added first, so a controller
   a child adds later sees Escape first and swallows it, and the dialog never closes. With
   no key press deliverable, this read-back is the only evidence there is that
   [Attr.on_key_pressed ~phase:Capture] reaches GTK at all.

   It also asserts there is exactly one of ours: both key attrs share a single
   [GtkEventControllerKey], and a second one would be a widget paying twice and, in
   capture phase, two handlers racing for the same key. *)
let key_controller_props label w =
  match
    List.filter (ours w) ~f:(fun c ->
      String.equal (Gobject.Type.name (Gobject.get_type c)) "GtkEventControllerKey")
  with
  | [] -> printf "%s: no key controller of ours\n" label
  | _ :: _ :: _ as all ->
    printf "%s: %d key controllers of ours!\n" label (List.length all)
  | [ o ] ->
    let phase =
      match W.Event_controller.get_propagation_phase o with
      | `NONE -> "NONE"
      | `CAPTURE -> "CAPTURE"
      | `BUBBLE -> "BUBBLE"
      | `TARGET -> "TARGET"
    in
    printf "%s: phase=%s\n" label phase
;;

(* The window's box's n'th child, as both the live record and the GTK widget. *)
let nth (live : P.live) i =
  match live.children with
  | Single (Some box) ->
    (match box.children with
     | List children -> List.nth_exn children i
     | No_children | Single _ | Slots _ -> assert false)
  | No_children | Single None | List _ | Slots _ -> assert false
;;

(* GTK does its focus bookkeeping from the main loop, so a [grab_focus] whose signals are
   read back in the same breath reads them back too early. Draining the loop is what makes
   the focus half of this file deterministic rather than occasionally empty. *)
let pump () =
  let rec go n = if n > 0 && Glib.Main.iteration false then go (n - 1) in
  go 50
;;

(* Once, before anything below: every block here needs GTK initialised, and the regression
   case has to run before the assertions that depend on the thing it pins. *)
let () = ignore (Ocgtk_gtk.GMain.init () : string array)

(* What the handlers saw, drained and labelled per assertion. Shared by the blocks below
   so that "nothing fired" and "this fired" read the same way everywhere. *)
let events = ref []
let record s = events := s :: !events

let drain label =
  printf "%s: %s\n" label (String.concat ~sep:"," (List.rev !events));
  events := []
;;

(* A window whose focus assertions work: presented, not merely created. *)
let presenting_ctx scheduler =
  P.create_ctx
    ~signals:
      { schedule = (fun e -> Ui_effect.Expert.eval e ~f:Fn.id ~on_exn:raise)
      ; in_patch = (fun () -> Scheduler.in_patch scheduler)
      ; on_exn =
          (fun ~node_path exn -> printf "EXN at %s: %s\n" node_path (Exn.to_string exn))
      }
    ~on_window_created:(fun w -> W.Window.present (cast w))
;;

(* Regression for the [set_static_name] bug (review C1).

   [gtk_event_controller_set_static_name] stores the pointer it is handed
   {i without copying}, so naming a controller with a runtime-computed OCaml string left
   GTK pointing into the heap: after a collection [get_name] read garbage, and after a
   compaction that returned the chunk to the OS it was a read of unmapped memory --
   reachable from GTK Inspector on any application built with this library.

   It also hollowed out this whole file. Every [gtk=] line above is [observe_controllers]
   filtered by [Controllers.is_ours], which is that same read: under allocation pressure
   the filter starts rejecting our own controllers, so the lines with a [bonsai=] beside
   them go flaky-red with no bug behind them, and [after destroy] passes {i vacuously} --
   it cannot tell "removed" from "unnameable". So this runs before the assertions that
   depend on it.

   The churn is deliberate: short-lived allocations force minor collections, and
   [Gc.compact] moves and can release what survives, which is what turns a stale pointer
   from "wrong bytes" into "freed memory". *)
let () =
  let scheduler = Scheduler.create ~run_frame:(fun () -> ()) in
  let ctx =
    P.create_ctx
      ~signals:
        { schedule = (fun e -> Ui_effect.Expert.eval e ~f:Fn.id ~on_exn:raise)
        ; in_patch = (fun () -> Scheduler.in_patch scheduler)
        ; on_exn =
            (fun ~node_path exn -> printf "EXN at %s: %s\n" node_path (Exn.to_string exn))
        }
      ~on_window_created:(fun _ -> ())
  in
  (* A label, not a button: a label emits no signal at all, so a controller on one can
     only have come from the attr. *)
  let live =
    P.mount
      ctx
      ~path:"gc"
      ~is_root:true
      (Node.label
         ~attrs:
           [ Attr.on_click ~button:2 (fun _ -> Ui_effect.Ignore)
           ; Attr.on_focus_enter (fun () -> Ui_effect.Ignore)
           ]
         "x")
  in
  P.run_fixups ctx;
  controllers "before gc" live live.widget;
  for _ = 1 to 20 do
    for _ = 1 to 100_000 do
      ignore (Sys.opaque_identity (Bytes.create 8) : Bytes.t)
    done;
    Gc.compact ()
  done;
  (* The names must read back exactly as they did, and the gesture's own properties with
     them -- a stale [priv->name] and a stale anything else fail the same way. *)
  controllers "after gc" live live.widget;
  click_gesture_props "after gc" live.widget;
  P.destroy ctx live;
  printf "gc regression done\n"
;;

(* Every controller attr [Events] admits is one [Controllers] actually attaches (review
   I1).

   [Events.controller_family] is what makes these attrs legal on every kind, skipped by
   [Signals.require_slots] and connected by no widget impl. The exhaustive match in
   [Controllers.update] is what stops a family being named there and attached by nothing;
   this is the other half, and it is what catches a family that is dispatched but wired
   {i wrongly} -- a [sync] whose [wanted] reads the empty attr set, say, which the
   compiler cannot see.

   The row list is hand-written because there is no way to derive a *value* per
   constructor of [Attr.Name.t]; the assertion below is what stops it going stale, exactly
   as [live_events.ml]'s [all_kinds] count does for [Kind.t]. *)
let each_controller_attr : (Attr.Name.t * Attr.t) list =
  [ On_click, Attr.on_click (fun _ -> Ui_effect.Ignore)
  ; On_focus_enter, Attr.on_focus_enter (fun () -> Ui_effect.Ignore)
  ; On_focus_leave, Attr.on_focus_leave (fun () -> Ui_effect.Ignore)
  ; On_key_pressed, Attr.on_key_pressed (fun _ -> Key_response.Propagate)
  ; On_key_released, Attr.on_key_released (fun _ -> Ui_effect.Ignore)
  ]
;;

let () =
  assert (
    List.equal
      Attr.Name.equal
      (List.map each_controller_attr ~f:fst)
      (List.filter Attr.Name.all ~f:Events.is_controller_attr))
;;

let () =
  let scheduler = Scheduler.create ~run_frame:(fun () -> ()) in
  let ctx =
    P.create_ctx
      ~signals:
        { schedule = (fun e -> Ui_effect.Expert.eval e ~f:Fn.id ~on_exn:raise)
        ; in_patch = (fun () -> Scheduler.in_patch scheduler)
        ; on_exn =
            (fun ~node_path exn -> printf "EXN at %s: %s\n" node_path (Exn.to_string exn))
        }
      ~on_window_created:(fun _ -> ())
  in
  List.iter each_controller_attr ~f:(fun (name, attr) ->
    (* A label again: it emits nothing, so anything attached came from the attr, and the
       node is accepted at all only because controller attrs are legal on every kind. *)
    let live = P.mount ctx ~path:"sweep" ~is_root:true (Node.label ~attrs:[ attr ] "x") in
    P.run_fixups ctx;
    printf
      !"%{sexp: Attr.Name.t} -> family=%{sexp: Events.Family.t option} attached=%{sexp: \
        string list}\n"
      name
      (Events.controller_family name)
      (names live.widget);
    P.destroy ctx live);
  printf "every controller attr attaches a controller\n"
;;

(* Regression for N1: removing one controller family must not disarm the families beside
   it, in any direction.

   [Controllers.update] visits the families in [Events.Family.all] order and each family's
   own [sync] is the only thing that re-arms it, so an emptying that happens *between* two
   [sync] calls undoes the arming the earlier ones just did. Round 1 put a whole-widget
   [clear] in [sync]'s removal branch, and it did exactly that: dropping the focus attrs
   while keeping [on_click] left the gesture attached with an empty slot, so a middle
   click between that frame and the next render reached nothing. It was invisible because
   no click can be delivered -- hence [Controllers.armed], which is the only way to tell a
   controller that will call something from one that will not.

   All three directions, because the order of [Events.Family.all] decides which family is
   the victim: [Key] was appended to it, which moves the order again and makes the
   click-dropped direction the widest of the three (both of the families after it would go
   dark). The click-dropped direction is asserted through the focus handlers actually
   firing, *in the same frame as the patch* (no second render intervenes), and through the
   key slots still being armed; the other two through the slots, which is all that can be
   observed of a controller nothing can deliver an event to. *)
let () =
  let scheduler = Scheduler.create ~run_frame:(fun () -> ()) in
  let ctx = presenting_ctx scheduler in
  let view ~with_click ~with_focus ~with_key =
    Node.window
      ~title:"n1"
      (Node.box
         ~orientation:Vertical
         [ Node.button
             ~attrs:
               (List.filter_opt
                  [ (if with_click
                     then
                       Some
                         (Attr.on_click (fun _ ->
                            record "click";
                            Ui_effect.Ignore))
                     else None)
                  ; (if with_focus
                     then
                       Some
                         (Attr.on_focus_enter (fun () ->
                            record "focus-enter";
                            Ui_effect.Ignore))
                     else None)
                  ; (if with_focus
                     then
                       Some
                         (Attr.on_focus_leave (fun () ->
                            record "focus-leave";
                            Ui_effect.Ignore))
                     else None)
                  ; (if with_key
                     then
                       Some
                         (Attr.on_key_pressed (fun _ ->
                            record "key-pressed";
                            Key_response.Handled))
                     else None)
                  ; (if with_key
                     then
                       Some
                         (Attr.on_key_released (fun _ ->
                            record "key-released";
                            Ui_effect.Ignore))
                     else None)
                  ])
             ~label:"target"
             ()
         ; Node.button ~label:"other" ()
         ])
  in
  let patch live v =
    let live =
      Scheduler.with_patch_guard scheduler (fun () ->
        P.patch ctx ~path:"n1" ~is_root:true live v)
    in
    P.run_fixups ctx;
    live
  in
  (* Focus into the target and back out again. Every round below starts with focus parked
     on [other], so each one prints the same two events when the controller is live and
     nothing when it is not -- which is what makes the lines comparable rather than each
     needing its own reading. *)
  let focus_round live =
    ignore (W.Widget.grab_focus (nth live 0).widget : bool);
    pump ();
    ignore (W.Widget.grab_focus (nth live 1).widget : bool);
    pump ()
  in
  let live =
    P.mount
      ctx
      ~path:"n1"
      ~is_root:true
      (view ~with_click:true ~with_focus:true ~with_key:true)
  in
  P.run_fixups ctx;
  controllers "n1 baseline" (nth live 0) (nth live 0).widget;
  (* Presenting the window focuses its first focusable child, which is the target -- and
     the controller is live from mount, so that arrives as an [enter]. Drained here so the
     baseline round and the rounds after each patch print the same shape and can be
     compared directly, which is the whole of what this block asserts. *)
  pump ();
  drain "n1 focus from presenting the window";
  ignore (W.Widget.grab_focus (nth live 1).widget : bool);
  pump ();
  drain "n1 focus parked off the target";
  focus_round live;
  drain "n1 baseline focus";
  (* Direction 1: drop the click family, keep focus and key. Click is first in
     [Family.all], so under the round-1 bug this is the frame that wiped both of the
     others. The focus and key attrs are byte-identical across it, so anything that stops
     them firing -- or empties their slots -- came from the click family's removal. Driven
     immediately, before any further render. *)
  let live = patch live (view ~with_click:false ~with_focus:true ~with_key:true) in
  controllers "n1 click family dropped" (nth live 0) (nth live 0).widget;
  focus_round live;
  drain "n1 focus in the same frame that dropped on_click";
  (* Direction 2: back to all three, then drop the focus family. Nothing can deliver a
     click or a key, so the assertion is the slots:
     [armed=(On_click On_key_pressed On_key_released)] is a widget whose handlers would be
     called, [armed=()] one whose controllers are attached and inert. *)
  let live = patch live (view ~with_click:true ~with_focus:true ~with_key:true) in
  controllers "n1 all three back" (nth live 0) (nth live 0).widget;
  let live = patch live (view ~with_click:true ~with_focus:false ~with_key:true) in
  controllers "n1 focus family dropped" (nth live 0) (nth live 0).widget;
  focus_round live;
  drain "n1 focus after its own family was dropped";
  (* Direction 3: back to all three, then drop the key family -- the one this task added,
     and the one at the end of [Family.all], so it is the direction a future family
     appended after it would break first. Focus is driven for real in the same frame, and
     the click slot has to still be armed. *)
  let live = patch live (view ~with_click:true ~with_focus:true ~with_key:true) in
  controllers "n1 all three back again" (nth live 0) (nth live 0).widget;
  ignore (W.Widget.grab_focus (nth live 1).widget : bool);
  pump ();
  drain "n1 focus parked off the target again";
  let live = patch live (view ~with_click:true ~with_focus:true ~with_key:false) in
  controllers "n1 key family dropped" (nth live 0) (nth live 0).widget;
  focus_round live;
  drain "n1 focus in the same frame that dropped the key attrs";
  P.destroy ctx live;
  printf "n1 regression done\n"
;;

let () =
  let scheduler = Scheduler.create ~run_frame:(fun () -> ()) in
  let ctx =
    P.create_ctx
      ~signals:
        { schedule = (fun e -> Ui_effect.Expert.eval e ~f:Fn.id ~on_exn:raise)
        ; in_patch = (fun () -> Scheduler.in_patch scheduler)
        ; on_exn =
            (fun ~node_path exn -> printf "EXN at %s: %s\n" node_path (Exn.to_string exn))
        }
        (* The window is *presented*, not merely created: [Widget.grab_focus] only drives
           the focus chain on a realized, mapped widget, so without this the focus
           assertions below would silently read nothing at all. *)
      ~on_window_created:(fun w -> W.Window.present (cast w))
  in
  (* A button with a click gesture and a focus controller, and a second button to move the
     focus to. The gesture is on the button, not on the window, so the counts below show
     where the controller went -- [Live_tree] cannot see controllers, so what this test
     asserts about them is their presence on the right widget and their behaviour. *)
  let view ?(with_focus_enter = true) ~with_click ~with_focus () =
    Node.window
      ~title:"controllers"
      (Node.box
         ~orientation:Vertical
         [ Node.button
             ~attrs:
               (List.filter_opt
                  [ (if with_focus && with_focus_enter
                     then
                       Some
                         (Attr.on_focus_enter (fun () ->
                            record "focus-enter";
                            Ui_effect.Ignore))
                     else None)
                  ; (if with_focus
                     then
                       Some
                         (Attr.on_focus_leave (fun () ->
                            record "focus-leave";
                            Ui_effect.Ignore))
                     else None)
                  ; (if with_click
                     then
                       Some
                         (Attr.on_click
                            ~button:2
                            ~phase:Capture
                            (fun (e : Click_event.t) ->
                               record
                                 (sprintf
                                    "click b%d n%d ctrl=%b"
                                    e.button
                                    e.n_press
                                    e.modifiers.control);
                               Ui_effect.Ignore))
                     else None)
                  ])
             ~label:"target"
             ()
         ; Node.button ~label:"other" ()
         ])
  in
  let live =
    P.mount ctx ~path:"root" ~is_root:true (view ~with_click:true ~with_focus:true ())
  in
  P.run_fixups ctx;
  print_s (Live_tree.dump live.widget);
  let target = nth live 0 in
  let other = nth live 1 in
  controllers "mounted target" target target.widget;
  controllers "mounted other" other other.widget;
  click_gesture_props "mounted gesture" target.widget;
  pump ();
  (* Focus, for real: [grab_focus] on a presented window drives the focus chain, and the
     controller this library attached is what turns that into a handler call. *)
  ignore (W.Widget.grab_focus target.widget : bool);
  pump ();
  drain "focus into target";
  ignore (W.Widget.grab_focus other.widget : bool);
  pump ();
  drain "focus to other";
  (* The reentrancy guard, on a real controller: a focus change GTK makes while a patch is
     running must not reach Bonsai, however armed the slot is. *)
  Scheduler.with_patch_guard scheduler (fun () ->
    ignore (W.Widget.grab_focus target.widget : bool);
    pump ());
  drain "focus during a patch";
  ignore (W.Widget.grab_focus other.widget : bool);
  pump ();
  drain "focus away again";
  (* Dropping the attr must remove the controller and disconnect its handler. Nothing
     observes a removed controller directly, so this asserts the consequence that matters:
     the widget is still alive, still patchable, and a later frame can add the attr back
     and get a working controller again. A leaked controller would keep a slot -- and the
     closure it captured -- alive as a GC root for the widget's lifetime. *)
  let live =
    Scheduler.with_patch_guard scheduler (fun () ->
      P.patch
        ctx
        ~path:"root"
        ~is_root:true
        live
        (view ~with_click:false ~with_focus:true ()))
  in
  P.run_fixups ctx;
  controllers "click attr dropped" (nth live 0) (nth live 0).widget;
  (* One attr of a shared family going away is not the family going away: dropping
     [on_focus_enter] alone must leave the [GtkEventControllerFocus] attached with one
     slot emptied, not remove it. That is [sync]'s [Some _, true] branch with an attr
     actually disappearing, which nothing else here reaches -- everywhere else the two
     focus attrs move together. *)
  let live =
    Scheduler.with_patch_guard scheduler (fun () ->
      P.patch
        ctx
        ~path:"root"
        ~is_root:true
        live
        (view ~with_click:false ~with_focus:true ~with_focus_enter:false ()))
  in
  P.run_fixups ctx;
  controllers "on_focus_enter alone dropped" (nth live 0) (nth live 0).widget;
  ignore (W.Widget.grab_focus (nth live 1).widget : bool);
  pump ();
  ignore (W.Widget.grab_focus (nth live 0).widget : bool);
  pump ();
  ignore (W.Widget.grab_focus (nth live 1).widget : bool);
  pump ();
  drain "focus in and out with only on_focus_leave";
  let live =
    Scheduler.with_patch_guard scheduler (fun () ->
      P.patch
        ctx
        ~path:"root"
        ~is_root:true
        live
        (view ~with_click:true ~with_focus:false ()))
  in
  P.run_fixups ctx;
  controllers "focus attrs dropped, click back" (nth live 0) (nth live 0).widget;
  (* And the focus controller really is gone: the same [grab_focus] that fired a handler
     above now fires nothing. This is the assertion that a removed controller is removed
     rather than merely unreferenced. *)
  ignore (W.Widget.grab_focus (nth live 0).widget : bool);
  pump ();
  drain "focus after its attrs were dropped";
  let live =
    Scheduler.with_patch_guard scheduler (fun () ->
      P.patch
        ctx
        ~path:"root"
        ~is_root:true
        live
        (view ~with_click:true ~with_focus:true ()))
  in
  P.run_fixups ctx;
  controllers "both attrs back" (nth live 0) (nth live 0).widget;
  click_gesture_props "re-added gesture" (nth live 0).widget;
  (* A fresh controller, not a resurrected one, and it works. *)
  ignore (W.Widget.grab_focus (nth live 1).widget : bool);
  pump ();
  ignore (W.Widget.grab_focus (nth live 0).widget : bool);
  pump ();
  drain "focus after the attrs came back";
  print_s (Live_tree.dump live.widget);
  let target_live = nth live 0 in
  let target = target_live.widget in
  controllers "before destroy" target_live target;
  P.destroy ctx live;
  printf
    !"after destroy: gtk=%{sexp: string list} total=%d\n"
    (names target)
    (List.length (all_controllers target));
  printf "destroyed cleanly\n"
;;

(* The key family's own lifecycle, and the two facts about it that are directly
   observable: the phase GTK was actually given, and which slots are armed.

   Both key attrs share one [GtkEventControllerKey], so the interesting frames are the
   ones where only one of them is present -- the controller has to stay, with one slot
   emptied, rather than being removed and rebuilt. That is [sync]'s [Some _, true] branch
   with an attr genuinely disappearing, and [Controllers.armed] is what tells the two
   apart. *)
let () =
  let scheduler = Scheduler.create ~run_frame:(fun () -> ()) in
  let ctx = presenting_ctx scheduler in
  let view ?(phase = Phase.Capture) ~with_pressed ~with_released () =
    Node.window
      ~title:"keys"
      (Node.box
         ~orientation:Vertical
         [ Node.button
             ~attrs:
               (List.filter_opt
                  [ (if with_pressed
                     then
                       Some
                         (Attr.on_key_pressed ~phase (fun _ ->
                            record "key-pressed";
                            Key_response.Handled))
                     else None)
                  ; (if with_released
                     then
                       Some
                         (Attr.on_key_released ~phase (fun _ ->
                            record "key-released";
                            Ui_effect.Ignore))
                     else None)
                  ])
             ~label:"target"
             ()
         ; Node.button ~label:"other" ()
         ])
  in
  let patch live v =
    let live =
      Scheduler.with_patch_guard scheduler (fun () ->
        P.patch ctx ~path:"keys" ~is_root:true live v)
    in
    P.run_fixups ctx;
    live
  in
  let live =
    P.mount
      ctx
      ~path:"keys"
      ~is_root:true
      (view ~with_pressed:true ~with_released:true ())
  in
  P.run_fixups ctx;
  controllers "keys both attrs" (nth live 0) (nth live 0).widget;
  key_controller_props "keys both attrs" (nth live 0).widget;
  (* One attr of the shared family going away is not the family going away: the controller
     stays, and exactly one slot empties. A rebuild would show up as the same [bonsai=1]
     with both slots armed. *)
  let live = patch live (view ~with_pressed:true ~with_released:false ()) in
  controllers "keys released dropped" (nth live 0) (nth live 0).widget;
  key_controller_props "keys released dropped" (nth live 0).widget;
  let live = patch live (view ~with_pressed:false ~with_released:true ()) in
  controllers "keys pressed dropped" (nth live 0) (nth live 0).widget;
  (* [on_key_released] alone still carries the phase, which is why both attrs have a
     [?phase] rather than only [on_key_pressed]: with only the release attr present there
     would otherwise be no way to say where the controller sits. *)
  key_controller_props "keys pressed dropped" (nth live 0).widget;
  (* Both gone: the controller is removed, not merely disarmed. *)
  let live = patch live (view ~with_pressed:false ~with_released:false ()) in
  controllers "keys both dropped" (nth live 0) (nth live 0).widget;
  key_controller_props "keys both dropped" (nth live 0).widget;
  (* And a later frame gets a fresh one, configured from the attrs of *that* frame -- the
     phase is re-read, not remembered. *)
  let live = patch live (view ~phase:Bubble ~with_pressed:true ~with_released:true ()) in
  controllers "keys re-added in bubble" (nth live 0) (nth live 0).widget;
  key_controller_props "keys re-added in bubble" (nth live 0).widget;
  (* A phase change on a controller that is already attached re-applies the property
     rather than rebuilding: same [GtkEventControllerKey], new phase. *)
  let live = patch live (view ~phase:Target ~with_pressed:true ~with_released:true ()) in
  controllers "keys moved to target" (nth live 0) (nth live 0).widget;
  key_controller_props "keys moved to target" (nth live 0).widget;
  (* Nothing fired throughout: no key press is deliverable through this binding, and the
     drain is here so that a future binding that *can* deliver one turns this line into a
     failing diff rather than passing silently. *)
  drain "keys nothing was delivered";
  P.destroy ctx live;
  printf "key lifecycle done\n"
;;

(* Two key attrs asking for different propagation phases is a node that cannot be mounted:
   one [GtkEventControllerKey], one phase, and picking either silently would give one attr
   routing its author did not ask for. Raised from [Controllers], with the node path, like
   every other structural rejection; [test/handle/test_handle.ml] pins that
   [Bonsai_gtk_test] refuses the same tree with the same string, which is what stops a
   headless suite certifying it. *)
let () =
  let scheduler = Scheduler.create ~run_frame:(fun () -> ()) in
  let ctx = presenting_ctx scheduler in
  let view ~pressed_phase ~released_phase =
    Node.window
      ~title:"phases"
      (Node.box
         ~orientation:Vertical
         [ Node.button
             ~attrs:
               [ Attr.on_key_pressed ~phase:pressed_phase (fun _ ->
                   Key_response.Propagate)
               ; Attr.on_key_released ~phase:released_phase (fun _ -> Ui_effect.Ignore)
               ]
             ~label:"target"
             ()
         ])
  in
  (match
     P.mount
       ctx
       ~path:"phases"
       ~is_root:true
       (view ~pressed_phase:Capture ~released_phase:Bubble)
   with
   | live ->
     printf "NOT REJECTED at mount\n";
     P.destroy ctx live
   | exception Invalid_argument msg -> printf "mount rejected: %s\n" msg);
  (* And at patch, on the frame the disagreement appears -- a conditionally-added [~phase]
     reaches a widget that mounted without it, which is the same reason
     [Signals.require_specs] runs on patch as well as on mount. *)
  let live =
    P.mount
      ctx
      ~path:"phases"
      ~is_root:true
      (view ~pressed_phase:Capture ~released_phase:Capture)
  in
  P.run_fixups ctx;
  key_controller_props "phases agreeing" (nth live 0).widget;
  (match
     Scheduler.with_patch_guard scheduler (fun () ->
       P.patch
         ctx
         ~path:"phases"
         ~is_root:true
         live
         (view ~pressed_phase:Capture ~released_phase:Target))
   with
   | _ -> printf "NOT REJECTED at patch\n"
   | exception Invalid_argument msg -> printf "patch rejected: %s\n" msg);
  (* The rejected patch left the controller where it was, in the phase the last accepted
     frame gave it: [configure] runs before anything is written on the attach path, and on
     the re-configure path the setter is never reached.

     The slots *are* empty, and that is recorded rather than hidden: [Controllers.update]
     empties every slot once up front and re-arms each family from its own [sync], so a
     raise partway through leaves the families it had not reached yet disarmed. That is
     not a live hazard -- an exception inside a frame stops the driver for good (spec
     §11), so there is no next frame for a disarmed slot to matter in -- but it is the
     state, and a golden that showed [armed=(On_key_pressed On_key_released)] here would
     be describing a rollback this library does not do. *)
  controllers "phases after the rejected patch" (nth live 0) (nth live 0).widget;
  key_controller_props "phases after the rejected patch" (nth live 0).widget;
  P.destroy ctx live;
  printf "phase rejection done\n"
;;

(* The value [Attr.on_key_pressed]'s handler hands back to GTK.

   This is the one link in the chain that nothing else can reach. [Key_response.handled]
   is pinned headlessly in [test/test_attrs.ml]; [Signals.dispatch_payload]'s three
   [declined] paths in [live_signals.ml]; and that the trampoline's result becomes
   [key-pressed]'s return is the compiler's job, since
   [Event_controller_key.on_key_pressed]'s callback is typed [... -> bool] and the spec's
   ['r] is fixed to [bool] by [declined]. What sits between them is
   [Controllers.key_pressed_answer], and with no synthetic key press there is no way to
   observe it through GTK -- so it is called directly, over all four responses.

   Inverted, this is the Critical: a [Handled] that answered [false] would consume
   nothing, and stavekeeper's Escape would close the dialog *and* reach whatever was
   underneath. *)
let () =
  let touched = ref false in
  let touch = Ui_effect.of_sync_fun (fun () -> touched := true) () in
  (* One printer for all four, so the two halves of the decision -- what GTK is told, and
     what Bonsai is asked to do -- are visibly independent rather than each response
     needing its own reading. *)
  let answer response =
    touched := false;
    let handled, effect =
      Controllers.key_pressed_answer
        (Attr.on_key_pressed (fun _ -> response))
        { Key_event.keyval = Keyval.escape; keycode = 9; modifiers = Modifiers.none }
    in
    Option.iter effect ~f:(fun e -> Ui_effect.Expert.eval e ~f:Fn.id ~on_exn:raise);
    printf
      !"%{sexp: Key_response.t} -> handled=%b performed=%b\n"
      response
      handled
      !touched
  in
  answer Key_response.Propagate;
  answer Key_response.Handled;
  answer (Key_response.Propagate_and touch);
  answer (Key_response.Handled_and touch);
  (* And the inert answer is GDK's own constant, not a [false] that happens to match: an
     empty slot, an emission during a patch and a handler that raised all take this path,
     and the opposite value would make a broken handler swallow the application's
     keyboard. *)
  printf
    "declined=%b event_propagate=%b event_stop=%b\n"
    Controllers.key_pressed_declined
    Ocgtk_gdk.Gdk_constants.event_propagate
    Ocgtk_gdk.Gdk_constants.event_stop;
  printf "key answers done\n"
;;
