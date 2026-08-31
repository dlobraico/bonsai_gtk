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

(* What the [live_controllers_*] suites can and cannot prove, stated once so that a reader
   of their goldens is not misled by them.

   {b There is no synthetic click or key press in the pinned ocgtk binding.} There is no
   [GdkEvent] constructor for any event subtype; [Gobject.Signal.emit_by_name] takes no
   arguments and returns unit, so it cannot deliver [~n_press ~x ~y] or
   [~keyval ~keycode ~state]; and [Event_controller_key.forward] only re-routes an event a
   controller is {i already handling}, which is a thing that can only be true inside a
   handler these suites cannot cause to run. So no test anywhere can make GTK route a real
   button press or keystroke to a controller this library attached. What these suites
   prove for {b click} and {b key} is therefore the plumbing: that the attr attaches a
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
   presented window it drives [GtkEventControllerFocus] for real. The focus half
   ([live_controllers_focus.ml]) is end-to-end. *)

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
   the focus assertions deterministic rather than occasionally empty. *)
let pump () =
  let rec go n = if n > 0 && Glib.Main.iteration false then go (n - 1) in
  go 50
;;

(* What the handlers saw, drained and labelled per assertion. Shared by the blocks so that
   "nothing fired" and "this fired" read the same way everywhere. *)
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
    ()
;;
