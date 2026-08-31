open! Core
open Bonsai_gtk_vtree
open Live_controllers_util

(* The key family: its lifecycle, its phase-disagreement rejection, and the value its
   handler hands back to GTK. See [live_controllers_util.ml]'s header for what these
   blocks can and cannot prove: no key press is deliverable through the pinned binding, so
   the evidence is the controller's presence, phase and armed slots, plus
   [Controllers.key_pressed_answer] called directly. The first two blocks present a
   toplevel, so this executable's rule carries [(locks x-display)]. *)

(* Once, before anything below: every block here needs GTK initialised. *)
let () = ignore (Ocgtk_gtk.GMain.init () : string array)

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
