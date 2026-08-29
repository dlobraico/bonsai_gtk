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
  print_s (Private.Live_tree.dump (Option.value_exn (Expert.Driver.root_widget broken)));
  Expert.Driver.stop broken;
  print_endline "broken driver stopped"
;;
