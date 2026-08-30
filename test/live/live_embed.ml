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
   in a test -- so this drains what is pending and returns.

   Bounded, unlike the [drain] in the older live tests, and deliberately:
   [Glib.Main.pending] can stay true indefinitely right after a major collection has
   finalized a batch of wrappers -- the reviewer hit it twice while probing this task, and
   this file hit it once, hanging after a click on a page whose embed still had a 60 fps
   tick. The bound is far above what any block here needs (a click is serviced in one or
   two iterations), so reaching it means the loop was not going to end on its own. *)
let drain () =
  let iterations = ref 0 in
  while Glib.Main.pending () && !iterations < 10_000 do
    ignore (Glib.Main.iteration false : bool);
    incr iterations
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

(* The rendered root, which is the wrapper's only child. [Embedded.widget] is the wrapper
   [embed] owns and hands the caller; everything the computation built is one level in. *)
let content e = List.hd_exn (widget_children (Expert.Embedded.widget e))
let nth e i = List.nth_exn (widget_children (content e)) i
let plus embedded = List.hd_exn (widget_children (content embedded))

(* The root node changes {i kind} between frames, which is what task-12-review.md's C1 is
   about and what every "load, then render" page does. [Node.button] is [Kind.Button] and
   [Node.box] is [Kind.Box], so [Kind.same_kind] fails at the root and the patcher mounts
   a replacement widget and destroys the original. *)
let loads_then_renders (graph @ local) =
  let n, set_n = Bonsai.state 0 graph in
  let%arr n and set_n in
  if n = 0
  then Node.button ~attrs:[ Attr.on_clicked (set_n 1) ] ~label:"load" ()
  else
    Node.box
      ~orientation:Vertical
      [ Node.label (sprintf "loaded %d" n)
      ; Node.button ~attrs:[ Attr.on_clicked (set_n (n + 1)) ] ~label:"+" ()
      ]
;;

(* A native widget whose only job is to count its own teardown. [Native.S.destroy] is
   exactly the hook a partial mount must still run, and it is the one piece of the
   patcher's teardown an application can observe directly. *)
module Counted = struct
  type input = string

  let name = "live_embed.counted"
  let destroyed = ref 0
  let create s : Widget.t = cast (W.Label.new_ (Some s))
  let update w ~old:(_ : string) s = W.Label.set_label (cast w) s
  let destroy (_ : Widget.t) = incr destroyed
end

let counted = Native.impl (module Counted)

(* A mount that raises on its last child, with three fully-built siblings in front of it.
   [Attr.on_clicked] on a [Node.label] is refused by [require_specs] -- a label emits no
   [clicked], so the handler would be silently inert -- which is a realistic application
   bug and lands mid-walk rather than at the root.

   The siblings in front of it are natives, because [Native.S.destroy] is the one piece of
   the patcher's teardown an application can observe directly, and it runs from
   [release_kind], the same exhaustive match [Patcher.destroy] uses -- so a kind that ever
   stopped being released on the unwind path would have to stop being released on both.

   The [Attr.on_click] on the {i box} is what loads [mount]'s unwind [Controllers.release]
   arm (task-12-review.md re-review N3). Without it that arm always released an empty
   [Controllers.t]: the raise is [require_specs]', which runs {i before} the raising
   node's own controllers are created, so the only way to reach the unwind with
   controllers built is for the raise to come from a child -- which means the attr has to
   be on the parent. The box mounts, its click gesture is attached, and then its child
   list raises. *)
let raises_after_two_natives (_graph @ local) =
  Bonsai.return
    (Node.box
       ~orientation:Vertical
       ~attrs:[ Attr.on_click (fun _ -> Ui_effect.Ignore) ]
       [ Node.button ~attrs:[ Attr.on_clicked Ui_effect.Ignore ] ~label:"one" ()
       ; Native.node counted "two"
       ; Native.node counted "three"
       ; Node.label ~attrs:[ Attr.on_clicked Ui_effect.Ignore ] "four"
       ])
;;

(* The other kind of failing first frame: one the {i walk} completes. Two stacks with one
   [~name] is an ordinary application mistake (a panel factory reused, a sidebar
   duplicated across two branches of a match), and it is decided by [apply_stack_claims]
   once the walk is over -- with everything above built, connected and, under
   [Bonsai_gtk.start], presented. The two natives are the same observable the block above
   uses. *)
let two_stacks_one_name (_graph @ local) =
  Bonsai.return
    (Node.box
       ~orientation:Vertical
       [ Native.node counted "one"
       ; Node.stack
           ~name:"nav"
           ~transition:None_
           ~visible_child:"a"
           [ Node.label ~key:"a" "a" ]
       ; Native.node counted "two"
       ; Node.stack
           ~name:"nav"
           ~transition:None_
           ~visible_child:"b"
           [ Node.label ~key:"b" "b" ]
       ])
;;

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
  click (nth embedded 1);
  (* And the same tree dumped from what [embed] handed back, which is what an embedder
     debugging one page rather than a whole window reaches for -- and which shows the
     wrapper [embed] owns sitting between the caller's container and the rendered root. *)
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
  click (nth second 1);
  click (nth second 1);
  let text_of e = W.Label.get_label (cast (nth e 0)) in
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
  click (nth embedded 1);
  printf "the first embed still renders: %S\n" (text_of embedded);
  Expert.Embedded.stop breaker;
  W.Stack.remove stack (Expert.Embedded.widget breaker);
  (* Teardown leaves the host alone: [embed] did not parent the root, so [stop] does not
     unparent it. If [stack holds] ever drops here the implementation started unparenting. *)
  Expert.Embedded.stop embedded;
  printf
    "after stop: stack holds %d, the wrapper is still a %s under a %s, holding %d\n"
    (n_children (cast stack))
    (type_name (Expert.Embedded.widget embedded))
    (parent_of (Expert.Embedded.widget embedded))
    (n_children (Expert.Embedded.widget embedded));
  W.Stack.remove stack (Expert.Embedded.widget embedded);
  printf
    "stop then remove: stack holds %d, the wrapper's parent is %s\n"
    (n_children (cast stack))
    (parent_of (Expert.Embedded.widget embedded));
  (* The other order, which the mli promises is equally safe: the embedder takes the page
     out of its container first and only then tears the tree down. *)
  W.Stack.remove stack (Expert.Embedded.widget second);
  printf "remove then stop: stack holds %d before the stop\n" (n_children (cast stack));
  let second_content = content second in
  Expert.Embedded.stop second;
  printf
    "remove then stop: the wrapper is a %s under %s holding %d; the tree it held is a %s \
     still showing %S\n"
    (type_name (Expert.Embedded.widget second))
    (parent_of (Expert.Embedded.widget second))
    (n_children (Expert.Embedded.widget second))
    (type_name second_content)
    (W.Label.get_label (cast (List.hd_exn (widget_children second_content))));
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
  click (nth orphan 1);
  printf "the host is presented and the page renders: %S\n" (text_of orphan);
  W.Window.destroy host_window;
  drain ();
  printf
    "after gtk_window_destroy: broken %b, root's parent %s, realized %b\n"
    (Expert.Embedded.broken orphan)
    (parent_of (Expert.Embedded.widget orphan))
    (W.Widget.get_realized (Expert.Embedded.widget orphan));
  click (nth orphan 1);
  Expert.Embedded.frame orphan;
  printf "a frame after the host was destroyed still patches: %S\n" (text_of orphan);
  (* And it survives the collector too: nothing here is kept alive by an OCaml stack slot
     that a major collection would clear, so the tree is still whole afterwards. *)
  let churn = List.init 2000 ~f:(fun _ -> W.Label.new_ (Some "churn")) in
  ignore (List.length churn : int);
  Gc.full_major ();
  Gc.full_major ();
  drain ();
  click (nth orphan 1);
  Expert.Embedded.frame orphan;
  printf
    "after two full majors: %S, children %d, type %s\n"
    (text_of orphan)
    (n_children (content orphan))
    (type_name (content orphan));
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
  print_endline "stopped a broken embed";
  (* ---------------------------------------------------------------------------------
     {b The root node changes kind} (task-12-review.md C1).

     The caller adds the page to its stack once, at mount, which is what [shell.ml:266]'s
     [stack#add_named viewer.widget (Some "viewer")] does and what any container idiom
     does. Then the computation's root goes from a [Node.button] to a [Node.box], the
     patcher mounts a replacement and destroys the original, and the question is what the
     stack is holding afterwards.

     Before the wrapper it was holding the destroyed button: no exception, [broken] still
     false, and the page frozen {i and inert}, because [destroy] had disconnected its
     handlers -- so even the widget still on screen no longer reached the model. The last
     two lines of this block are what would fail. *)
  let host2 = W.Window.new_ () in
  let stack2 = W.Stack.new_ () in
  W.Window.set_child host2 (Some (cast stack2 : Widget.t));
  let changer = Expert.embed ~time_source:(time_source ()) loads_then_renders in
  ignore
    (W.Stack.add_named stack2 (Expert.Embedded.widget changer) (Some "page")
     : W.Stack_page.t);
  let wrapper_before = Expert.Embedded.widget changer in
  let button_before = content changer in
  printf
    "kind change, before: the stack holds a %s holding a %s\n"
    (type_name wrapper_before)
    (type_name button_before);
  click button_before;
  printf
    "kind change, after: the stack still holds the same %s (same object: %b), now \
     holding a %s\n"
    (type_name (Expert.Embedded.widget changer))
    (phys_equal wrapper_before (Expert.Embedded.widget changer))
    (type_name (content changer));
  printf
    "the widget the patcher replaced is a %s whose parent is now %s\n"
    (type_name button_before)
    (parent_of button_before);
  print_s (Private.Live_tree.dump (cast host2 : Widget.t));
  (* The claim that matters: the new content is live, not just visible. A click on the
     button the second render built reaches the model and the third render follows. *)
  click (nth changer 1);
  printf
    "a click on the new content reached the model: %S, broken %b\n"
    (W.Label.get_label (cast (nth changer 0)))
    (Expert.Embedded.broken changer);
  Expert.Embedded.stop changer;
  W.Stack.remove stack2 (Expert.Embedded.widget changer);
  W.Window.destroy host2;
  (* ---------------------------------------------------------------------------------
     {b A mount that raises leaves nothing behind} (task-12-review.md I1).

     [Patcher.mount] is exception-safe, so the two siblings built before the third child
     was refused are torn down rather than stranded. [Native.S.destroy] is the observable:
     it runs from [release_kind], the same exhaustive match [Patcher.destroy] uses, so a
     kind that ever stopped being released on this path would have to stop being released
     on both. *)
  Counted.destroyed := 0;
  (match Expert.embed ~time_source:(time_source ()) raises_after_two_natives with
   | _ -> printf "a mount that raises: NO RAISE\n"
   | exception Invalid_argument m -> printf "a mount that raises: %s\n" m);
  printf
    "the siblings it had already built were torn down: %d native destroys of 2\n"
    !Counted.destroyed;
  (* The same guarantee for the one rejection that happens {i after} the walk rather than
     during it: two [Node.stack]s claiming one [~name] are refused by
     [Patcher.apply_stack_claims], by which point the whole tree is built and connected.

     [Embed.create]'s failure path can do nothing about that on its own -- it calls
     [Driver.stop], and the driver never assigned [t.root], so [stop] has nothing to walk.
     Either [mount] tore the tree down before raising or nobody ever will. The counter is
     the same observable as above, and it reads 0 of 2 with the guard removed. *)
  Counted.destroyed := 0;
  (match Expert.embed ~time_source:(time_source ()) two_stacks_one_name with
   | _ -> printf "a first frame rejected after the walk: NO RAISE\n"
   | exception Invalid_argument m ->
     printf "a first frame rejected after the walk: %s\n" m);
  printf
    "the tree the walk had finished was torn down: %d native destroys of 2\n"
    !Counted.destroyed;
  ()
;;

(* ------------------------------------------------------------------------------------ *)

(* {b A failed mount leaves the ctx usable} (task-12-review.md I1, the bookkeeping half).

   The destroy counter above shows the widgets are released. This shows the other thing a
   half-finished walk leaves behind: its {i registrations}. A [Node.stack] does not
   register its name as it is mounted -- it enqueues a claim, and [apply_stack_claims]
   applies the whole pass's claims once the walk is over -- so a walk that raises leaves a
   claim in the queue naming a widget that no longer exists. Applied by the next pass, it
   would either register a dead stack under that name or collide with the live one, and
   the message ("two Node.stacks are named ...") would name a frame that had nothing to do
   with it.

   [Patcher.abandon_fixups] is what empties that queue, and [Driver.frame] calls it on its
   way out of any frame that raised. This drives the patcher directly, because that is the
   only way to see it: an embed whose frame raised is broken for good, so no second mount
   ever happens on a driver's own ctx.

   Verified by experiment in both directions: with the [abandon_fixups] line below
   removed, the second mount raises [two Node.stacks are named "shared"]. *)
let () =
  let scheduler = Private.Scheduler.create ~run_frame:(fun () -> ()) in
  let ctx =
    Private.Patcher.create_ctx
      ~signals:
        { schedule = (fun _ -> ())
        ; in_patch = (fun () -> Private.Scheduler.in_patch scheduler)
        ; on_exn =
            (fun ~node_path exn -> printf "EXN at %s: %s\n" node_path (Exn.to_string exn))
        }
      ~on_window_created:(fun _ -> ())
      ()
  in
  let named_stack =
    Node.stack
      ~name:"shared"
      ~transition:None_
      ~visible_child:"a"
      [ Node.label ~key:"a" "a" ]
  in
  (match
     Private.Patcher.mount
       ctx
       ~path:"root"
       ~is_root:true
       (Node.box
          ~orientation:Vertical
          [ named_stack; Node.label ~attrs:[ Attr.on_clicked Ui_effect.Ignore ] "boom" ])
   with
   | (_ : Private.Patcher.live) -> printf "a mount that registers then raises: NO RAISE\n"
   | exception Invalid_argument m -> printf "a mount that registers then raises: %s\n" m);
  (* What [Driver.frame] does on its way out of a frame that raised. *)
  Private.Patcher.abandon_fixups ctx;
  match
    let live =
      Private.Patcher.mount
        ctx
        ~path:"root"
        ~is_root:true
        (Node.box
           ~orientation:Vertical
           [ named_stack; Node.stack_switcher ~stack:"shared" () ])
    in
    Private.Patcher.run_fixups ctx;
    live
  with
  | (_ : Private.Patcher.live) ->
    printf
      "the same ctx then mounts a tree naming the same stack, and a switcher finds it\n"
  | exception Invalid_argument m -> printf "BUG: the ctx was not clean: %s\n" m
;;

(* ------------------------------------------------------------------------------------ *)

(* {b [stop] is what releases the tree} (task-12-review.md I2).

   Everything else in this file pins that an un-stopped embed {i survives}, which is the
   measurement the mli's lifetime note rests on. This pins the other direction, which is
   the one the entry point's whole purpose rests on: [embed] exists so a long-lived
   application can mount and tear down a page per navigation, and "after [stop] the
   wrapper may be dropped" is what makes that not an unbounded leak.

   Both directions in one block, because neither is worth much alone: the [without stop]
   row is what proves the finaliser is a real instrument rather than one that never fires,
   and the [stopped] row is what proves [stop] breaks a cycle that GC alone cannot. The
   un-stopped embeds are created with no tick, so the ones deliberately leaked here do not
   go on driving frames for the rest of the run. *)
let () =
  let finalized = ref 0 in
  let n = 5 in
  (* Built and dropped inside a function so that no OCaml stack slot outlives it. *)
  let churn ~stop_them =
    let es =
      List.init n ~f:(fun _ ->
        let e =
          Expert.embed
            ~time_source:(time_source ())
            ~target_frames_per_second:0.
            (counter ~label:"churn")
        in
        Stdlib.Gc.finalise
          (fun (_ : Widget.t) -> incr finalized)
          (Expert.Embedded.widget e);
        e)
    in
    if stop_them then List.iter es ~f:Expert.Embedded.stop
  in
  let settle () =
    Gc.full_major ();
    Gc.full_major ();
    drain ()
  in
  churn ~stop_them:true;
  settle ();
  printf "%d embeds stopped and dropped: %d wrappers finalized\n" n !finalized;
  finalized := 0;
  churn ~stop_them:false;
  settle ();
  printf "%d embeds dropped without stop: %d wrappers finalized\n" n !finalized
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
