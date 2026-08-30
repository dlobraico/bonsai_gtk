open! Core
open Bonsai_gtk
open Bonsai.Let_syntax
module Gobject = Bonsai_gtk.Private.Gtk_import.Gobject
module Glib = Bonsai_gtk.Private.Gtk_import.Glib
module W = Bonsai_gtk.Private.Gtk_import.W

let cast = Bonsai_gtk.Private.Gtk_import.cast
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

(* Spec §11 names a non-window root first in its list of structural misuse, and nothing
   tested it -- only the nested-window half of the same sentence. A [GtkWindow] is the
   only thing GTK can show on its own, so anything else at the root has nowhere to go. *)
let rootless_app (_graph @ local) = Bonsai.return (Node.label "not a window")

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

(* The consumer half of the controlled rule, at driver level.

   [live_containers.ml] shows [Widget_impl.reassert] and the stack fixup putting a
   declined edit back, but it does so by calling [Patcher.patch] itself. The frame is what
   decides whether they run at all: a model that declines an edit leaves its state exactly
   as it was, so Bonsai hands the driver the physically same node, and a driver that
   skipped the patch on that would skip the only thing that undoes the edit.

   Nothing here changes state -- [count] has no setter that is ever called, and both
   handlers only bump a counter through an effect -- so every frame after the first
   renders the identical node. The toggle's [~active] and the stack's [~visible_child] are
   therefore pinned, and the user's changes must not survive a frame. *)
let declined_toggles = ref 0
let declined_pages = ref 0

let declining_app (graph @ local) =
  let count, (_ : (int -> unit Effect.t) Bonsai.t) = Bonsai.state 0 graph in
  let%arr count in
  Node.window
    ~title:"declined"
    (Node.box
       ~orientation:Vertical
       [ Node.toggle_button
           ~attrs:
             [ Attr.on_toggled
                 (Effect.of_sync_fun (fun (_ : bool) -> incr declined_toggles))
             ]
           ~label:"t"
           ~active:(count > 0)
           ()
       ; Node.stack
           ~name:"nav"
           ~transition:None_
           ~visible_child:"a"
           ~attrs:
             [ Attr.on_visible_child_changed
                 (Effect.of_sync_fun (fun (_ : string) -> incr declined_pages))
             ]
           [ Node.label ~key:"a" "a"; Node.label ~key:"b" "b" ]
       ])
;;

(* The same claim again, for the frame that does not diff at all.

   [declining_app] above happens to render the physically same node too (its [let%arr]
   depends on a [count] nothing changes), but it does so incidentally. This one is
   explicit: the view is built *once*, outside the computation, and handed back by
   reference on every frame -- which is what a Bonsai computation whose state did not move
   does, and is the frame [Driver.frame_body] now skips the diff on.

   Both halves of the controlled rule are exercised, because a walk that only re-asserted
   would pass the switch and fail the stack: the switch is [Widget_impl.reassert] and the
   stack's page is a fixup [Patcher.enqueue_fixups] has to re-enqueue. *)
let phys_view =
  Node.window
    ~title:"phys"
    (Node.box
       ~orientation:Vertical
       [ Node.switch ~active:false ()
       ; Node.stack
           ~name:"phys-nav"
           ~transition:None_
           ~visible_child:"a"
           [ Node.label ~key:"a" "a"; Node.label ~key:"b" "b" ]
       ])
;;

let phys_app (_graph @ local) = Bonsai.return phys_view

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
  (* The same claim for a frame nobody guarded. An embedder with its own main loop calls
     [Expert.Driver.frame] itself, so the exception comes back to *it* rather than to the
     scheduler -- and the driver has to be just as dead afterwards, because the shadow
     tree is just as half-written: the box's first child was patched before the second one
     was rejected. Without this the next hand-driven frame would diff a frame-3 node
     against a tree that is part frame 1 and part frame 2. *)
  let time_source = Bonsai.Time_source.create ~start:Time_ns.epoch in
  let by_hand =
    Expert.Driver.create ~time_source ~on_window_created:(fun _ -> ()) breaking_app
  in
  Expert.Driver.frame by_hand;
  let plus_by_hand () =
    let root = Option.value_exn (Expert.Driver.root_widget by_hand) in
    List.hd_exn (widget_children (List.hd_exn (widget_children root)))
  in
  Gobject.Signal.emit_by_name (plus_by_hand ()) ~name:"clicked";
  (match Expert.Driver.frame by_hand with
   | () -> print_endline "BUG: a hand-driven frame swallowed the exception"
   | exception Invalid_argument msg -> printf "hand-driven frame raised: %s\n" msg);
  printf "broken after a hand-driven raise: %b\n" (Expert.Driver.broken by_hand);
  (* And the next one does nothing at all rather than raising again or, worse, patching. *)
  Expert.Driver.frame by_hand;
  print_endline "the frame after that was a no-op";
  drain ();
  Expert.Driver.stop by_hand;
  (* [frame] after [stop] is caller error, not a broken app: the Bonsai graph's observers
     are invalidated and the widget tree is gone, so there is nothing to render into. *)
  (match Expert.Driver.frame by_hand with
   | () -> print_endline "BUG: frame on a stopped driver accepted"
   | exception Invalid_argument msg -> printf "rejected: %s\n" msg);
  let time_source = Bonsai.Time_source.create ~start:Time_ns.epoch in
  let rootless =
    Expert.Driver.create ~time_source ~on_window_created:(fun _ -> ()) rootless_app
  in
  (match Expert.Driver.frame rootless with
   | () -> print_endline "BUG: a non-window root accepted"
   | exception Invalid_argument msg -> printf "rejected: %s\n" msg);
  Expert.Driver.stop rootless;
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
  Expert.Driver.stop reentrant;
  let time_source = Bonsai.Time_source.create ~start:Time_ns.epoch in
  let declining =
    Expert.Driver.create ~time_source ~on_window_created:(fun _ -> ()) declining_app
  in
  Expert.Driver.frame declining;
  let child i =
    let root = Option.value_exn (Expert.Driver.root_widget declining) in
    List.nth_exn (widget_children (List.hd_exn (widget_children root))) i
  in
  (* The user flips the toggle. The model sees it and renders the same node anyway, so the
     frame the click arms is the one that has to put the widget back. *)
  W.Toggle_button.set_active (cast (child 0)) true;
  drain ();
  printf
    "declined toggle: active %b, Bonsai saw %d\n"
    (W.Toggle_button.get_active (cast (child 0)))
    !declined_toggles;
  (* The same claim for the stack, whose selection is put back by the fixup pass rather
     than by [reassert] -- and so is the other half of what a skipped patch would lose. *)
  W.Stack.set_visible_child_name (cast (child 1)) "b";
  drain ();
  printf
    "declined page: visible %s, Bonsai saw %d\n"
    (Option.value (W.Stack.get_visible_child_name (cast (child 1))) ~default:"?")
    !declined_pages;
  Expert.Driver.stop declining;
  let time_source = Bonsai.Time_source.create ~start:Time_ns.epoch in
  (* This one prints, unlike the drivers above, because the reassert-and-fixup-only walk
     is written to do *less* than a patch and nothing else pins that: routing [Window] to
     [on_window_created] from the walk -- which would re-present and refocus a real window
     on every idle tick -- left every golden in this suite byte-identical. One line per
     window, and a second one means the walk started presenting.

     (The stack half of the same hazard used to be pinned by [register_stack] raising
     [two Node.stacks are named "phys-nav"] on the second frame. It is not any more: stack
     names became claims applied at the end of a [mount] or [patch], and [reassert_only]
     applies none, so a claim enqueued from the reassert walk would sit in the queue and
     raise from the *next* real patch -- one frame late, or never for a constant app like
     this one. Unpinned rather than broken; the walk still enqueues nothing, and the line
     above is what pins the half that can be pinned.) *)
  let phys =
    Expert.Driver.create
      ~time_source
      ~on_window_created:(fun _ -> print_endline "phys window created")
      phys_app
  in
  let phys_child i =
    let root = Option.value_exn (Expert.Driver.root_widget phys) in
    List.nth_exn (widget_children (List.hd_exn (widget_children root))) i
  in
  let switch_active () = W.Switch.get_active (cast (phys_child 0)) in
  let visible_page () =
    Option.value (W.Stack.get_visible_child_name (cast (phys_child 1))) ~default:"?"
  in
  Expert.Driver.frame phys;
  printf "after mount: switch %b, page %s\n" (switch_active ()) (visible_page ());
  (* The user flips the switch and clicks through to the other page. *)
  W.Switch.set_active (cast (phys_child 0)) true;
  W.Stack.set_visible_child_name (cast (phys_child 1)) "b";
  printf
    "after the user changed them: switch %b, page %s\n"
    (switch_active ())
    (visible_page ());
  (* One frame, on which Bonsai hands back the identical node value. Nothing is diffed --
     and both edits are still put back. *)
  Expert.Driver.frame phys;
  printf
    "after the declining frame: switch %b, page %s\n"
    (switch_active ())
    (visible_page ());
  (* The tree is still patchable afterwards: the no-diff walk left [live.node] alone, so a
     later frame that *does* change something diffs against the node that was really
     rendered rather than against nothing. There is no such frame for this app -- it is a
     constant -- so the check is that the shadow tree still describes GTK. *)
  print_s (Private.Live_tree.dump (Option.value_exn (Expert.Driver.root_widget phys)));
  Expert.Driver.stop phys
;;
