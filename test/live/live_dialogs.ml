open! Core
open Bonsai_gtk
module For_runtime = Bonsai_gtk.Private.Gtk_effect.For_runtime
module For_testing = Bonsai_gtk.Private.Gtk_effect.For_live_tests
module Glib = Bonsai_gtk.Private.Gtk_import.Glib
module Gtk_enums = Ocgtk_gtk.Gtk_enums
module W = Bonsai_gtk.Private.Gtk_import.W
module Widget = Bonsai_gtk.Private.Gtk_import.Widget

(* The alert effect against real GTK (M3 Task 10 steps 1-2): a real [GtkDialog] -- the §8
   contingency, since [AlertDialog] cannot be constructed in the pin -- driven to each
   button and to both dismissal routes {i programmatically} ([Dialog.response] fires
   [on_response] synchronously on the caller's stack; pre-flight 6), so no XTEST is needed
   here. The file-chooser half needs a real keystroke and lives in [live_input.ml]'s
   dialog block.

   The keep-alive is this suite's sharpest claim: nothing in the application holds the
   dialog -- the effect is performed and the value dropped -- so without the runtime's
   table an ocgtk wrapper would be collected by the [Gc.full_major] {b between} show and
   response, the finaliser would unref it, and the dialog would vanish mid-show (§2.2's
   ownership rule, discharged for widgets by the shadow tree and here by hand). *)

let () = ignore (Ocgtk_gtk.GMain.init () : string array)

let drain () =
  let iterations = ref 0 in
  while Glib.Main.pending () && !iterations < 10_000 do
    ignore (Glib.Main.iteration false : bool);
    incr iterations
  done
;;

(* The hooks, so a resolution requests its frame somewhere real rather than logging the
   dropped-hooks line into every block. *)
let frame_requests = ref 0

let reg =
  For_runtime.register
    ~request_frame:(fun () -> incr frame_requests)
    ~context_widget:(fun () -> None)
    ()
;;

let alert ?detail ?cancel ~buttons message =
  let result = ref None in
  Ui_effect.Expert.handle
    ~on_exn:(fun exn -> printf "EXN: %s\n" (Exn.to_string exn))
    (let open Ui_effect.Let_syntax in
     let%bind i = Effect.Alert_dialog.show ?detail ?cancel ~buttons message in
     Ui_effect.of_thunk (fun () -> result := Some i));
  result
;;

let the_dialog () =
  match For_testing.live_alert_dialogs () with
  | [ d ] -> d
  | l -> failwithf "expected one live alert, found %d" (List.length l) ()
;;

(* --- each button resolves its index, and the dialog is destroyed afterwards (proved by
   [get_visible] on the held wrapper -- never by a destroy signal; pre-flight 3). *)
let () =
  List.iter [ 0; 1; 2 ] ~f:(fun i ->
    let result = alert ~buttons:[ "Cancel"; "Apply"; "Delete" ] "pick one" in
    drain ();
    let d = the_dialog () in
    let w = (d :> Widget.t) in
    printf "alert up (visible=%b); answering button %d\n" (Widget.get_visible w) i;
    W.Dialog.response d i;
    printf
      "resolved %s; destroyed=%b; live alerts=%d\n"
      (match !result with
       | Some i -> Int.to_string i
       | None -> "nothing")
      (not (Widget.get_visible w))
      (List.length (For_testing.live_alert_dialogs ())));
  printf "frame requests so far: %d\n" !frame_requests
;;

(* --- the keep-alive: a full major between show and response. Without the runtime's table
   this is the collection that would unref the wrapper and take the dialog down mid-show;
   with it, the dialog survives to be answered. *)
let () =
  let result = alert ~detail:"a detail line" ~buttons:[ "OK" ] "still here?" in
  drain ();
  Gc.full_major ();
  drain ();
  let d = the_dialog () in
  printf
    "after a full major mid-show: alive=%b visible=%b\n"
    (List.length (For_testing.live_alert_dialogs ()) = 1)
    (Widget.get_visible (d :> Widget.t));
  W.Dialog.response d 0;
  printf
    "resolved %s\n"
    (match !result with
     | Some i -> Int.to_string i
     | None -> "nothing");
  Gc.full_major ();
  drain ();
  printf
    "post-response full major: live alerts=%d\n"
    (List.length (For_testing.live_alert_dialogs ()))
;;

(* --- both dismissal routes map to [?cancel]: the raw DELETE_EVENT response id (what
   Escape delivers; pre-flight 2 measured -4, not CANCEL), and a real [Window.close] --
   the close-request path, which GtkDialog answers with the same id. *)
let () =
  let result = alert ~cancel:2 ~buttons:[ "a"; "b"; "keep" ] "dismiss me" in
  drain ();
  W.Dialog.response (the_dialog ()) (Gtk_enums.responsetype_to_int `DELETE_EVENT);
  printf
    "DELETE_EVENT with ~cancel:2 resolved %s\n"
    (match !result with
     | Some i -> Int.to_string i
     | None -> "nothing");
  let result = alert ~buttons:[ "only" ] "close me" in
  drain ();
  W.Window.close (the_dialog () :> W.Window.t);
  drain ();
  printf
    "Window.close with the default cancel resolved %s\n"
    (match !result with
     | Some i -> Int.to_string i
     | None -> "nothing");
  printf "live alerts at the end: %d\n" (List.length (For_testing.live_alert_dialogs ()))
;;

(* --- serially reentrant: two alerts at once are two dialogs (the table is a table, not a
   slot), answered in either order. *)
let () =
  let first = alert ~buttons:[ "one" ] "first" in
  let second = alert ~buttons:[ "one"; "two" ] "second" in
  drain ();
  (match For_testing.live_alert_dialogs () with
   | [ a; b ] ->
     printf "two alerts live at once\n";
     (* Answer the {i first}-shown one second: resolution order follows answers, not
        shows. The list is insertion-ordered by the probe's contract. *)
     W.Dialog.response b 1;
     printf
       "second answered 1: first=%s second=%s\n"
       (match !first with
        | Some i -> Int.to_string i
        | None -> "pending")
       (match !second with
        | Some i -> Int.to_string i
        | None -> "pending");
     W.Dialog.response a 0;
     printf
       "first answered 0: first=%s second=%s\n"
       (match !first with
        | Some i -> Int.to_string i
        | None -> "pending")
       (match !second with
        | Some i -> Int.to_string i
        | None -> "pending")
   | l -> printf "expected two live alerts, found %d\n" (List.length l));
  Gc.full_major ();
  drain ();
  printf "no criticals above this line is the teardown assertion\n";
  For_runtime.unregister reg;
  printf "done\n"
;;

(* Fix-wave core M3: [?cancel] must index [~buttons] -- rejected at effect-build time,
   before any GTK object exists, so a dismissal can never resolve an index naming no
   button. *)
let () =
  (match Effect.Alert_dialog.show ~cancel:5 ~buttons:[ "OK" ] "x" with
   | (_ : int Ui_effect.t) -> printf "out-of-range cancel was accepted (BUG)\n"
   | exception Invalid_argument m -> printf "out-of-range cancel rejected: %s\n" m);
  match Effect.Alert_dialog.show ~buttons:[] "x" with
  | (_ : int Ui_effect.t) -> printf "buttonless alert was accepted (BUG)\n"
  | exception Invalid_argument m -> printf "buttonless alert rejected: %s\n" m
;;
