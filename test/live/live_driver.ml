open! Core
open Bonsai_gtk
open Bonsai.Let_syntax
module Gobject = Bonsai_gtk.Private.Gtk_import.Gobject
module Glib = Bonsai_gtk.Private.Gtk_import.Glib

let widget_children = Bonsai_gtk.Private.Gtk_import.widget_children

let app (graph @ local) =
  let count, set_count = Bonsai.state 0 graph in
  let%arr count and set_count in
  Node.window
    ~title:"drv"
    (Node.box
       ~orientation:Vertical
       [ Node.label (sprintf "Count: %d" count)
       ; Node.button ~attrs:[ Attr.on_clicked (set_count (count + 1)) ] ~label:"+" ()
       ])
;;

(* Everything the driver does after a click happens on a GLib idle source, so the test has
   to hand the main loop back to GLib to see any of it. *)
let drain () =
  while Glib.Main.pending () do
    ignore (Glib.Main.iteration false : bool)
  done
;;

(* A frame that raises must stop the driver instead of repeating itself at tick rate. This
   app renders a [Node.window] as a box child once its count reaches 1 — structural misuse
   the patcher rejects (spec §11) — which is a realistic stand-in for any app bug that
   surfaces mid-patch. *)
let breaking_app (graph @ local) =
  let count, set_count = Bonsai.state 0 graph in
  let%arr count and set_count in
  Node.window
    ~title:"break"
    (Node.box
       ~orientation:Vertical
       (Node.button ~attrs:[ Attr.on_clicked (set_count (count + 1)) ] ~label:"+" ()
        :: (if count = 0 then [] else [ Node.window ~title:"nested" (Node.label "x") ])))
;;

(* The producer half of the reentrancy guard, end to end.

   [live_signals.ml] proves that [Signals.dispatch] returns early when the [in_patch] it
   is handed says so, and [live_controls.ml] proves it with a [Scheduler] the test
   brackets by hand. Neither shows that a *real* frame is bracketed, which is what
   [driver.ml]'s [with_patch_guard] is for -- so this app makes a frame provoke the signal
   itself.

   Clicking [flip] changes [on], and the frame that renders it writes [active] on the
   toggle button; GTK emits [toggled] synchronously from inside that write, while the
   patcher is still walking the tree. Unguarded, that would bump [toggled] -- and in
   general re-enter Bonsai from the middle of a patch, which spec §4.4 forbids. *)
let reentrant_app (graph @ local) =
  let on, set_on = Bonsai.state false graph in
  let toggled, set_toggled = Bonsai.state 0 graph in
  let%arr on and set_on and toggled and set_toggled in
  Node.window
    ~title:"reentry"
    (Node.box
       ~orientation:Vertical
       [ Node.button ~attrs:[ Attr.on_clicked (set_on (not on)) ] ~label:"flip" ()
       ; Node.toggle_button
           ~attrs:[ Attr.on_toggled (fun (_ : bool) -> set_toggled (toggled + 1)) ]
           ~label:"t"
           ~active:on
           ()
       ; Node.label (sprintf "on: %b toggled: %d" on toggled)
       ])
;;

let () =
  ignore (Ocgtk_gtk.GMain.init () : string array);
  (* A caller-owned time source: with none, every frame would advance the clock to
     [Time_ns.now ()], which is fine for an app and useless for a reproducible test. *)
  let time_source = Bonsai.Time_source.create ~start:Time_ns.epoch in
  let d =
    Expert.Driver.create
      ~time_source
      ~on_window_created:(fun _ -> print_endline "window created")
      app
  in
  let dump () =
    print_s (Private.Live_tree.dump (Option.value_exn (Expert.Driver.root_widget d)))
  in
  Expert.Driver.frame d;
  dump ();
  let button () =
    let root = Option.value_exn (Expert.Driver.root_widget d) in
    let box = List.hd_exn (widget_children root) in
    List.nth_exn (widget_children box) 1
  in
  (* Two clicks with a frame in between, not two in a row: [set_count (count + 1)] closes
     over the [count] of the render that built it, so without the frame both effects would
     set the count to 1 and prove nothing. Draining to `Count: 2` is exactly the claim
     worth testing — the idle armed by the first click ran a frame, and that frame rewrote
     the button's handler slot to the effect built from the *new* count. *)
  Gobject.Signal.emit_by_name (button ()) ~name:"clicked";
  drain ();
  Gobject.Signal.emit_by_name (button ()) ~name:"clicked";
  drain ();
  dump ();
  Expert.Driver.stop d;
  print_endline "stopped";
  (* The click below reaches the computation through the scheduler's idle, which is the
     guarded path — [Expert.Driver.frame] would simply re-raise. *)
  let time_source = Bonsai.Time_source.create ~start:Time_ns.epoch in
  let broken =
    Expert.Driver.create ~time_source ~on_window_created:(fun _ -> ()) breaking_app
  in
  Expert.Driver.frame broken;
  printf "broken before: %b\n" (Expert.Driver.broken broken);
  let plus () =
    let root = Option.value_exn (Expert.Driver.root_widget broken) in
    List.hd_exn (widget_children (List.hd_exn (widget_children root)))
  in
  Gobject.Signal.emit_by_name (plus ()) ~name:"clicked";
  drain ();
  printf "broken after: %b\n" (Expert.Driver.broken broken);
  (* The window is still there, showing its last good state — a dead app the user can
     close, not a vanished one. A second click arms nothing, so nothing re-raises. *)
  Gobject.Signal.emit_by_name (plus ()) ~name:"clicked";
  drain ();
  (* A hand-driven frame is refused the same way: [driver.mli] promises that nothing
     updates the tree again once a frame has raised, and the shadow tree no longer
     describes GTK, so diffing against it would be worse than doing nothing. It returns
     rather than raising — unlike [stopped], being broken is not caller error. *)
  Expert.Driver.frame broken;
  printf
    "frame on broken driver returned, still broken: %b\n"
    (Expert.Driver.broken broken);
  print_s (Private.Live_tree.dump (Option.value_exn (Expert.Driver.root_widget broken)));
  Expert.Driver.stop broken;
  print_endline "broken driver stopped";
  let time_source = Bonsai.Time_source.create ~start:Time_ns.epoch in
  let reentrant =
    Expert.Driver.create ~time_source ~on_window_created:(fun _ -> ()) reentrant_app
  in
  Expert.Driver.frame reentrant;
  let nth i =
    let root = Option.value_exn (Expert.Driver.root_widget reentrant) in
    List.nth_exn (widget_children (List.hd_exn (widget_children root))) i
  in
  let dump_reentrant () =
    print_s
      (Private.Live_tree.dump (Option.value_exn (Expert.Driver.root_widget reentrant)))
  in
  (* [on] flips, so the next frame writes [active] on the toggle button and GTK emits
     [toggled] from inside the patch. [toggled: 0] is the whole claim: the guard swallowed
     it. *)
  Gobject.Signal.emit_by_name (nth 0) ~name:"clicked";
  drain ();
  dump_reentrant ();
  (* The very same signal, emitted while no frame is running, does reach Bonsai -- so
     [toggled: 0] above is the guard at work and not a handler that was never armed. *)
  Gobject.Signal.emit_by_name (nth 1) ~name:"toggled";
  drain ();
  dump_reentrant ();
  Expert.Driver.stop reentrant
;;
