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

   {b There is no synthetic click in the pinned ocgtk binding.} There is no [GdkEvent]
   constructor for any event subtype; [Gobject.Signal.emit_by_name] takes no arguments and
   returns unit, so it cannot deliver [~n_press ~x ~y]; and [Event_controller_key.forward]
   only re-routes an event a controller is already handling. So no test anywhere can make
   GTK route a real button press to a [GtkGestureClick] this library attached. What this
   file proves for {b click} is therefore the plumbing: that the attr attaches a
   controller, that dropping it removes one, that the gesture's button and phase reach
   GTK, and that the widget survives both. The handler half is proved headlessly, in
   [test/handle/test_handle.ml]'s "a click action carries the button and the modifiers",
   and the trampoline that stands between them -- slots, the [in_patch] guard, the
   exception guard, the value handed back to GTK -- in [live_signals.ml]. The gap between
   those and "GTK really routes a middle click here" is real and is in the backlog.

   {b Focus is different}: [Widget.grab_focus] is a real focus-chain operation, so on a
   presented window it drives [GtkEventControllerFocus] for real. The focus half of this
   file is end-to-end. *)

(* The controllers GTK reports on [w] that this library attached, by the debugging name
   [Controllers] sets on each. Counting by name rather than by class or by total is what
   makes the numbers below mean anything: a [GtkButton] ships with a [GtkGestureClick], a
   [GtkEventControllerKey] and a [GtkShortcutController] of its own, so "the widget has a
   GtkGestureClick" is true before this library does anything, and the total would move
   the day a GTK release changes how many a button has. *)
let ours w =
  let model = W.Widget.observe_controllers w in
  List.init (List_model.get_n_items model) ~f:(List_model.get_object model)
  |> List.filter_opt
  |> List.map ~f:cast
  |> List.filter ~f:Controllers.is_ours
;;

(* GTK's own answer beside this library's bookkeeping, compared on every line: a
   controller [Controllers] forgot to remove would show up as a difference between them,
   and a controller it removed from the wrong widget as a difference in [gtk]. *)
let controllers label (live : P.live) w =
  printf
    !"%s: gtk=%{sexp: string list} bonsai=%d\n"
    label
    (List.map (ours w) ~f:(fun c ->
       Option.value ~default:"?" (W.Event_controller.get_name c)))
    (Controllers.attached_count live.controllers)
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

let () =
  ignore (Ocgtk_gtk.GMain.init () : string array);
  let events = ref [] in
  let record s = events := s :: !events in
  let drain label =
    printf "%s: %s\n" label (String.concat ~sep:"," (List.rev !events));
    events := []
  in
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
  let view ~with_click ~with_focus =
    Node.window
      ~title:"controllers"
      (Node.box
         ~orientation:Vertical
         [ Node.button
             ~attrs:
               (List.filter_opt
                  [ (if with_focus
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
    P.mount ctx ~path:"root" ~is_root:true (view ~with_click:true ~with_focus:true)
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
        (view ~with_click:false ~with_focus:true))
  in
  P.run_fixups ctx;
  controllers "click attr dropped" (nth live 0) (nth live 0).widget;
  let live =
    Scheduler.with_patch_guard scheduler (fun () ->
      P.patch
        ctx
        ~path:"root"
        ~is_root:true
        live
        (view ~with_click:true ~with_focus:false))
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
      P.patch ctx ~path:"root" ~is_root:true live (view ~with_click:true ~with_focus:true))
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
  let target = (nth live 0).widget in
  P.destroy ctx live;
  printf "after destroy: gtk=%d\n" (List.length (ours target));
  printf "destroyed cleanly\n"
;;
