open! Core
open Bonsai_gtk_vtree
open Live_controllers_util

(* The focus family, end to end, and the family-removal regression that is observed
   through it. See [live_controllers_util.ml]'s header: [Widget.grab_focus] is a real
   focus-chain operation, so on a presented window these blocks drive
   [GtkEventControllerFocus] for real. Both blocks present a toplevel, so this
   executable's rule carries [(locks x-display)]. *)

(* Once, before anything below: every block here needs GTK initialised. *)
let () = ignore (Ocgtk_gtk.GMain.init () : string array)

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
      ()
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
