open! Core
open Bonsai_gtk
open Bonsai.Let_syntax
module Gobject = Bonsai_gtk.Private.Gtk_import.Gobject
module Glib = Bonsai_gtk.Private.Gtk_import.Glib
module W = Bonsai_gtk.Private.Gtk_import.W

let cast = Bonsai_gtk.Private.Gtk_import.cast
let widget_children = Bonsai_gtk.Private.Gtk_import.widget_children
let type_name = Bonsai_gtk.Private.Gtk_import.type_name

(* Everything the driver defers happens on a GLib idle source, so the test hands the loop
   back to GLib to see it. No main loop runs here -- that is the point of an embedded tree
   in a test -- so this drains what is pending and returns. *)
let drain () =
  while Glib.Main.pending () do
    ignore (Glib.Main.iteration false : bool)
  done
;;

let n_children w = List.length (widget_children w)

let parent_of w =
  match W.Widget.get_parent w with
  | None -> "nothing"
  | Some p -> type_name p
;;

(* A caller-owned time source, as every driver-level live test uses: with none, each frame
   would advance the clock to [Time_ns.now ()], which is useless for a golden. *)
let time_source () = Bonsai.Time_source.create ~start:Time_ns.epoch

(* The shape stavekeeper's [Shell] is: a window the caller built, holding a [GtkStack] of
   named pages, none of which is a window. A bonsai tree is one page. *)
let counter ~label (graph @ local) =
  let n, set_n = Bonsai.state 0 graph in
  let%arr n and set_n in
  Node.box
    ~orientation:Vertical
    [ Node.label (sprintf "%s %d" label n)
    ; Node.button ~attrs:[ Attr.on_clicked (set_n (n + 1)) ] ~label:"+" ()
    ]
;;

let window_root (_graph @ local) =
  Bonsai.return (Node.window ~title:"no" (Node.label "x"))
;;

(* A [Node.window] below the root of an embedded tree. Under [start] this is rejected
   because a window may only be the root; under [embed] the root may not be one either, so
   the two halves add up to "not anywhere". *)
let nested_window (_graph @ local) =
  Bonsai.return
    (Node.box
       ~orientation:Vertical
       [ Node.label "a"; Node.window ~title:"nested" (Node.label "x") ])
;;

(* A placement attr on the embedded root, whose parent -- as far as the patcher is
   concerned -- is nothing at all, exactly as a windowed root's is. *)
let misplaced_root (_graph @ local) =
  Bonsai.return (Node.label ~attrs:[ Attr.grid_cell ~column:0 ~row:0 () ] "x")
;;

(* Structural misuse a click introduces, so the frame that raises is a *later* one and
   arrives through the tick's own guarded path rather than out of [create]. *)
let breaks_on_click (graph @ local) =
  let n, set_n = Bonsai.state 0 graph in
  let%arr n and set_n in
  Node.box
    ~orientation:Vertical
    (Node.button ~attrs:[ Attr.on_clicked (set_n (n + 1)) ] ~label:"+" ()
     :: (if n = 0 then [] else [ Node.window ~title:"nested" (Node.label "x") ]))
;;

let plus embedded = List.nth_exn (widget_children (Expert.Embedded.widget embedded)) 0

let click w =
  Gobject.Signal.emit_by_name w ~name:"clicked";
  drain ()
;;

let () =
  ignore (Ocgtk_gtk.GMain.init () : string array);
  let window = W.Window.new_ () in
  let stack = W.Stack.new_ () in
  W.Window.set_child window (Some (cast stack : Widget.t));
  let embedded = Expert.embed ~time_source:(time_source ()) (counter ~label:"count") in
  (* Nothing has been parented: [embed] hands back a root and the caller puts it where its
     own container puts children. A [GtkStack] takes [add_named], which is not [set_child]
     -- which is the whole reason [embed] does not do this for you. *)
  printf
    "before the caller parents it: stack holds %d, root's parent is %s\n"
    (n_children (cast stack))
    (parent_of (Expert.Embedded.widget embedded));
  ignore
    (W.Stack.add_named stack (Expert.Embedded.widget embedded) (Some "page")
     : W.Stack_page.t);
  (* Dumped from the *window*, not from the embedded root: that is what shows the tree is
     really inside the stack rather than a sibling toplevel. *)
  print_s (Private.Live_tree.dump (cast window : Widget.t));
  (* The user clicks. The effect is queued and an idle armed; draining runs the frame the
     way a real main loop would, with no [GtkApplication] anywhere. *)
  click (List.nth_exn (widget_children (Expert.Embedded.widget embedded)) 1);
  (* And the same tree dumped from its own root, which is what an embedder debugging one
     page rather than a whole window reaches for. *)
  print_s (Private.Live_tree.dump (Expert.Embedded.widget embedded));
  (* A frame by hand, which is the only path when no main loop is running at all. *)
  Expert.Embedded.schedule_event embedded (Effect.Ignore : unit Effect.t);
  Expert.Embedded.frame embedded;
  printf "broken: %b\n" (Expert.Embedded.broken embedded);
  (* A window root is refused, and the message names the entry point the caller wanted. *)
  (match Expert.embed ~time_source:(time_source ()) window_root with
   | _ -> printf "window root: NO RAISE\n"
   | exception Invalid_argument m -> printf "window root: %s\n" m);
  (match Expert.embed ~time_source:(time_source ()) nested_window with
   | _ -> printf "nested window: NO RAISE\n"
   | exception Invalid_argument m -> printf "nested window: %s\n" m);
  (match Expert.embed ~time_source:(time_source ()) misplaced_root with
   | _ -> printf "misplaced attr on the root: NO RAISE\n"
   | exception Invalid_argument m -> printf "misplaced attr on the root: %s\n" m);
  (* A failed [create] hands back no [t], so it has to leave nothing running: a second one
     over the same stack works, which it would not if the first had left a tick behind
     patching a half-built tree. *)
  let second = Expert.embed ~time_source:(time_source ()) (counter ~label:"second") in
  ignore
    (W.Stack.add_named stack (Expert.Embedded.widget second) (Some "second")
     : W.Stack_page.t);
  printf "a second embed alongside the first: stack holds %d\n" (n_children (cast stack));
  (* Two embeds, two drivers, two schedulers: a click in one moves only its own state, and
     each answers frames of its own. *)
  click (List.nth_exn (widget_children (Expert.Embedded.widget second)) 1);
  click (List.nth_exn (widget_children (Expert.Embedded.widget second)) 1);
  let text_of e =
    let label = List.hd_exn (widget_children (Expert.Embedded.widget e)) in
    W.Label.get_label (cast label)
  in
  printf "after two clicks on the second: %S and %S\n" (text_of embedded) (text_of second);
  (* And two broken-nesses. The third embed's tick drives a frame that raises -- the
     scheduler's own guarded path, the same one [start] uses, which logs to stderr and
     stops that driver -- and the other two go on rendering. *)
  let breaker = Expert.embed ~time_source:(time_source ()) breaks_on_click in
  ignore
    (W.Stack.add_named stack (Expert.Embedded.widget breaker) (Some "breaker")
     : W.Stack_page.t);
  eprintf "live_embed: the bonsai_gtk frame exception that follows is expected\n%!";
  click (plus breaker);
  printf
    "after the breaker's frame raised: breaker %b, first %b, second %b\n"
    (Expert.Embedded.broken breaker)
    (Expert.Embedded.broken embedded)
    (Expert.Embedded.broken second);
  click (List.nth_exn (widget_children (Expert.Embedded.widget embedded)) 1);
  printf "the first embed still renders: %S\n" (text_of embedded);
  Expert.Embedded.stop breaker;
  W.Stack.remove stack (Expert.Embedded.widget breaker);
  (* Teardown leaves the host alone: [embed] did not parent the root, so [stop] does not
     unparent it. If [stack holds] ever drops here the implementation started unparenting. *)
  Expert.Embedded.stop embedded;
  printf
    "after stop: stack holds %d, the root is still a %s under a %s\n"
    (n_children (cast stack))
    (type_name (Expert.Embedded.widget embedded))
    (parent_of (Expert.Embedded.widget embedded));
  W.Stack.remove stack (Expert.Embedded.widget embedded);
  printf
    "stop then remove: stack holds %d, the root's parent is %s\n"
    (n_children (cast stack))
    (parent_of (Expert.Embedded.widget embedded));
  (* The other order, which the mli promises is equally safe: the embedder takes the page
     out of its container first and only then tears the tree down. *)
  W.Stack.remove stack (Expert.Embedded.widget second);
  printf "remove then stop: stack holds %d before the stop\n" (n_children (cast stack));
  Expert.Embedded.stop second;
  printf
    "remove then stop: the root is a %s under %s, still usable: %S\n"
    (type_name (Expert.Embedded.widget second))
    (parent_of (Expert.Embedded.widget second))
    (text_of second);
  (* [stop] is idempotent, and a frame after it is caller error the way it is for a
     driver: the Bonsai graph's observers are gone. *)
  Expert.Embedded.stop embedded;
  (match Expert.Embedded.frame embedded with
   | () -> printf "frame after stop: NO RAISE\n"
   | exception Invalid_argument m -> printf "frame after stop: %s\n" m);
  (* --------------------------------------------------------------------------------- The
     host destroyed under a live embed.

     What GTK actually does, measured here rather than assumed: [gtk_window_destroy] on
     the host emits no [destroy] on the tree below it and does not even unparent it,
     because the shadow tree holds a reference to every widget it built. So the embedded
     tree survives its host, and a frame afterwards patches widgets that are alive and
     simply off screen. That is a leak and wasted work, not a use-after-free -- which is
     why the mli's obligation is "stop before you drop the host", stated as an economy
     rather than as a safety rule. *)
  let host_window = W.Window.new_ () in
  let host_stack = W.Stack.new_ () in
  W.Window.set_child host_window (Some (cast host_stack : Widget.t));
  let orphan = Expert.embed ~time_source:(time_source ()) (counter ~label:"orphan") in
  ignore
    (W.Stack.add_named host_stack (Expert.Embedded.widget orphan) (Some "page")
     : W.Stack_page.t);
  W.Window.present host_window;
  drain ();
  click (List.nth_exn (widget_children (Expert.Embedded.widget orphan)) 1);
  printf "the host is presented and the page renders: %S\n" (text_of orphan);
  W.Window.destroy host_window;
  drain ();
  printf
    "after gtk_window_destroy: broken %b, root's parent %s, realized %b\n"
    (Expert.Embedded.broken orphan)
    (parent_of (Expert.Embedded.widget orphan))
    (W.Widget.get_realized (Expert.Embedded.widget orphan));
  click (List.nth_exn (widget_children (Expert.Embedded.widget orphan)) 1);
  Expert.Embedded.frame orphan;
  printf "a frame after the host was destroyed still patches: %S\n" (text_of orphan);
  (* And it survives the collector too: nothing here is kept alive by an OCaml stack slot
     that a major collection would clear, so the tree is still whole afterwards. *)
  let churn = List.init 2000 ~f:(fun _ -> W.Label.new_ (Some "churn")) in
  ignore (List.length churn : int);
  Gc.full_major ();
  Gc.full_major ();
  drain ();
  click (List.nth_exn (widget_children (Expert.Embedded.widget orphan)) 1);
  Expert.Embedded.frame orphan;
  printf
    "after two full majors: %S, children %d, type %s\n"
    (text_of orphan)
    (n_children (Expert.Embedded.widget orphan))
    (type_name (Expert.Embedded.widget orphan));
  (* [stop] on a tree whose host is gone is the ordinary teardown, not a special case: it
     walks widgets that are all still there. *)
  Expert.Embedded.stop orphan;
  printf "stop after the host was destroyed: broken %b\n" (Expert.Embedded.broken orphan);
  (* --------------------------------------------------------------------------------- The
     destroy backstop. No GTK teardown measured here emits [destroy] on a widget the
     shadow tree holds a reference to, so the hook covers only an embedder that disposes
     the tree outright -- which is what emitting the signal stands in for. *)
  let disposed = Expert.embed ~time_source:(time_source ()) (counter ~label:"disposed") in
  printf "before the destroy: broken %b\n" (Expert.Embedded.broken disposed);
  Gobject.Signal.emit_by_name (Expert.Embedded.widget disposed) ~name:"destroy";
  printf "after the root's destroy fired: broken %b\n" (Expert.Embedded.broken disposed);
  (* Broken, not stopped: a frame is the no-op [Driver.broken] promises rather than a
     raise or a patch, and [stop] afterwards is still the caller's to make. *)
  Expert.Embedded.frame disposed;
  printf "a frame on it was a no-op, still broken: %b\n" (Expert.Embedded.broken disposed);
  Expert.Embedded.stop disposed;
  print_endline "stopped a broken embed"
;;

(* ------------------------------------------------------------------------------------ *)

(* What an embedded root costs per idle frame, against a windowed one rendering the same
   subtree.

   The claim under test is the one the whole entry point rests on: embedding is the same
   runtime with a different rule about the root, so an application that ticks at 60 fps
   with a window pays the same at 60 fps inside someone else's window. If [embed] ever
   grows per-frame work of its own -- a parent check, a rootedness poll, a "did the host
   go away" walk, all of which were considered here -- this is what notices.

   Both drivers are handed a computation that returns a *physically fixed* node, so both
   frames take [Patcher.reassert_only] rather than a diff: that is what an idle frame is,
   and [Widget_impl.reassert] on the switch plus the fixup pass is the work it does. The
   two trees are the identical [Node.t] value, so the windowed one differs by exactly one
   node -- its [Node.window] -- and should therefore be a hair *more* expensive. The bound
   is one-sided and generous for that reason: what would fail it is embedding doing extra
   work, not the window being free.

   A ratio rather than a wall-clock bound, for [task-7-review.md] N1's reason: contention
   scales both measurements and cancels. The verdict goes to the golden and the numbers to
   stderr, which is not compared, so a failure says how far over it went.

   Measured at 2f8eeb9 + this task, three runs under xvfb: 0.0085/0.0086/0.0086 ms
   embedded against 0.0096/0.0098/0.0096 ms windowed, a ratio of 0.89 every time. The gap
   is the [Node.window] itself -- one more node whose [reassert] runs every frame -- and
   it is why the bound is one-sided at 1.2 rather than symmetric: the claim is "no worse",
   and 1.2 still catches a doubling. *)
let bench_view =
  Node.box
    ~orientation:Vertical
    (Node.switch ~active:false ()
     :: List.init 100 ~f:(fun i -> Node.label (sprintf "row %d" i)))
;;

let bench_windowed (_graph @ local) =
  Bonsai.return (Node.window ~title:"bench" bench_view)
;;

let bench_embedded (_graph @ local) = Bonsai.return bench_view

let () =
  let frames = 2000 in
  let bound_ratio = 1.2 in
  let ms_per_frame ~run =
    (* One frame first, outside the timing: that is the mount, which builds 101 widgets
       and is not what this measures. *)
    run ();
    let start = Time_ns.now () in
    for _ = 1 to frames do
      run ()
    done;
    Time_ns.Span.to_ms (Time_ns.diff (Time_ns.now ()) start) /. Int.to_float frames
  in
  let windowed =
    Expert.Driver.create
      ~time_source:(time_source ())
      ~on_window_created:(fun _ -> ())
      bench_windowed
  in
  let windowed_ms = ms_per_frame ~run:(fun () -> Expert.Driver.frame windowed) in
  Expert.Driver.stop windowed;
  (* [~target_frames_per_second:0.] installs no tick: the frames below are the ones this
     loop drives and nothing else, and no GLib source outlives the measurement. *)
  let embedded =
    Expert.embed ~time_source:(time_source ()) ~target_frames_per_second:0. bench_embedded
  in
  let embedded_ms = ms_per_frame ~run:(fun () -> Expert.Embedded.frame embedded) in
  Expert.Embedded.stop embedded;
  let ratio = embedded_ms /. windowed_ms in
  printf
    "bench: %d idle frames, embedded/windowed cost ratio under %g: %b\n"
    frames
    bound_ratio
    Float.(ratio < bound_ratio);
  eprintf
    "bench: %.4f ms embedded, %.4f ms windowed, ratio %.2f (bound %g)\n%!"
    embedded_ms
    windowed_ms
    ratio
    bound_ratio
;;
