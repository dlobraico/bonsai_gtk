open! Core
open Bonsai_gtk_vtree
open Gtk_import

type root_kind =
  [ `Window
  | `Not_window
  ]

type t =
  { bonsai : Node.t Bonsai_driver.t
  ; time_source : Bonsai.Time_source.t
  ; advance_wall_clock : bool
  ; root_kind : root_kind
  ; mutable on_root_widget_changed : Widget.t -> unit
  ; scheduler : Scheduler.t
  ; ctx : Patcher.ctx
  ; mutable root : Patcher.live option
  ; mutable stopped : bool
  ; (* What {!stop} runs to drop the process-global effect hooks that close over this
       driver ([Gtk_effect.For_runtime]); a no-op until [Loop.start] or [Embed.create]
       registers hooks and hands the matching unregister here. On the driver rather than
       inside [Gtk_effect] because only the registrar knows whether this driver registered
       anything, and only [stop] knows when it died. *)
    mutable drop_effect_hooks : unit -> unit
  ; (* What the raising frame runs after marking this driver broken, before the exception
       propagates. A no-op unless the entry point sets it: [Loop.start] points it at
       [Gio.Application.quit], because under [start] a broken driver otherwise leaves an
       app that can never exit -- every window was [add_window]ed (so [run] holds while
       any exists), the close-request veto stays armed on every path, and a scheduled
       close handler's effect is [schedule_event]'s guarded no-op. A hand-driven caller
       (an embedder, a test) keeps the default: it owns its main loop and hears the raise
       directly out of [frame]. *)
    mutable on_broken : unit -> unit
  }

(* The async effects' GLib callbacks come through here (via the registered [request_frame]
   hook): the effect's continuation has already enqueued its injects, and this is the
   frame that will flush them. Guarded like {!schedule_event}, for its reasons. *)
let request_frame t =
  if (not t.stopped) && not (Scheduler.broken t.scheduler)
  then Scheduler.request_frame t.scheduler
;;

let set_effect_hooks_drop t f = t.drop_effect_hooks <- f
let set_on_broken t f = t.on_broken <- f

let schedule_event t effect =
  (* A broken driver renders nothing again (see [frame]), so queueing effects into it only
     grows a queue nobody drains — a frozen window whose memory keeps climbing. [stopped]
     is worse still: [stop] has invalidated the computation's observers, so scheduling
     into that graph is scheduling into a value nothing will ever read. Neither is
     reachable through a handler the patcher connected (all of them are disconnected by
     [stop]), but an embedder holding the driver, and a [Native] widget whose own handler
     outlives its [destroy], both are. *)
  if (not t.stopped) && not (Scheduler.broken t.scheduler)
  then (
    Bonsai_driver.schedule_event t.bonsai effect;
    Scheduler.request_frame t.scheduler)
;;

(* The two entry points' root rules, written once each because [root_kind] is a variant
   rather than a bool: there is no way to spell the wrong one and have it read plausibly
   at the call site.

   The rules are opposites rather than one being a relaxation of the other. [start] shows
   the root itself, and a [GtkWindow] is the only thing GTK can show on its own; [embed]
   parents the root into a container the caller owns, and a [GtkWindow] is a toplevel that
   cannot be parented at all. So a window root is required by one and refused by the
   other, and each message names the entry point the caller evidently wanted. *)
let check_root ~(root_kind : root_kind) (node : Node.t) =
  match root_kind, node.kind with
  | `Window, (Window _ | Windows) -> ()
  | `Window, k ->
    invalid_argf
      "Bonsai_gtk: the root node must be a Node.window or a Node.windows, got %s. A tree \
       started this way shows its own root, and a GtkWindow is the only thing GTK can \
       show on its own (Node.windows is the virtual root holding several of them). Use \
       Bonsai_gtk.Expert.embed for a tree parented into a container you already own."
      (Kind.name k)
      ()
  | `Not_window, (Window _ | Windows) ->
    invalid_arg
      "Bonsai_gtk.embed: the root node is a Node.window (or a Node.windows), but an \
       embedded tree is parented into a container the caller owns and a GtkWindow is a \
       toplevel that cannot be parented. Use Bonsai_gtk.start for a tree that owns its \
       windows, or make the root a container."
  | `Not_window, _ -> ()
;;

let frame_body t =
  if t.advance_wall_clock
  then (
    Bonsai.Time_source.advance_clock t.time_source ~to_:(Time_ns.now ());
    Bonsai.Time_source.Private.flush t.time_source);
  Bonsai_driver.flush t.bonsai;
  let node = Bonsai_driver.result t.bonsai in
  (* Skipping the frames on which Bonsai hands back the physically same node looks like a
     free optimisation and is not. A model that *declines* a user's edit -- the
     digits-only field handed a letter, the switch the model refuses to flip, the stack
     page it will not navigate to -- leaves its state exactly as it was, so its view is
     the same value it was last frame. The work that would put the widget back is
     therefore precisely the work a physical-equality guard throws away, and the declined
     edit stands on screen. That is the bug spec §6.5 exists to prevent.

     What that argument rules out is skipping the frame, not diffing it. Both halves of
     the cure -- [Widget_impl.reassert] and the deferred selections -- are exactly what
     [Patcher.reassert_only] does, and they are the whole of what a no-change frame ever
     accomplished: with the node physically identical there is nothing for [Attrs.diff] to
     find and nothing for [Kind.equal_props] to admit, so a full patch would walk the same
     tree to reach the same two calls. Frames only happen on an event or on the tick, and
     an idle tick is now nearly free. *)
  check_root ~root_kind:t.root_kind node;
  Scheduler.with_patch_guard t.scheduler (fun () ->
    (match t.root with
     | Some live when phys_equal node live.Patcher.node ->
       Patcher.reassert_only t.ctx ~path:"root" live
     | Some live ->
       let patched = Patcher.patch t.ctx ~path:"root" ~is_root:true live node in
       t.root <- Some patched;
       (* The root node changed {i kind}, so the patcher mounted a replacement widget and
          destroyed the old one rather than updating it in place. An embedded root is an
          arbitrary node, and a [Node.label "Loading..."] that becomes a [Node.box [...]]
          on the next frame is an ordinary page; under [start] the one reachable flip is
          [Window] <-> [Windows] (both legal there), which works through this same arm --
          the mount presents the new toplevels and the destroy takes the old ones down --
          and notifies a callback [start] never installs. Whoever put the old widget
          somewhere has to be told, or the container goes on holding a widget nothing
          renders into again. *)
       if not (phys_equal patched.Patcher.widget live.Patcher.widget)
       then t.on_root_widget_changed patched.Patcher.widget
     | None ->
       let live = Patcher.mount t.ctx ~path:"root" ~is_root:true node in
       t.root <- Some live;
       t.on_root_widget_changed live.Patcher.widget);
    (* Inside the guard, and after the whole tree exists: this is where a [stack_switcher]
       finds the stack it names and a stack selects its page, and both write properties
       GTK notifies about. *)
    Patcher.run_fixups t.ctx);
  Bonsai_driver.trigger_lifecycles t.bonsai;
  (* [trigger_lifecycles] *schedules* the after-display effects rather than applying them,
     so another frame is needed before their results are on screen. Under a tick that
     frame is already coming. Without one we ask for it — but on the rate-limited path,
     never the idle: [has_after_display_events] is true whenever the computation contains
     an after-display handler at all (one [Clock.every] is enough), so every frame would
     request its successor and an idle would run them back to back at full CPU. *)
  if Bonsai_driver.has_after_display_events t.bonsai
     && not (Scheduler.ticking t.scheduler)
  then Scheduler.request_frame_soon t.scheduler
;;

let frame t =
  if t.stopped
  then
    invalid_arg
      "Bonsai_gtk: Driver.frame on a stopped driver (stop invalidates the Bonsai graph \
       and tears the widget tree down; build a new driver instead)";
  if Scheduler.broken t.scheduler
  then
    (* A frame already raised. The shadow tree describes a GTK tree that no longer exists,
       so diffing against it again is worse than doing nothing. Unlike [stopped] this is
       not caller error — the scheduler's own guarded path reaches here too — so it
       returns rather than raising. *)
    ()
  else (
    (* Whichever way the frame is driven, a raise ends this driver: the patcher mutates
       GTK as it walks and writes the shadow tree back only on success, so a frame that
       dies part-way leaves the two describing different trees. Under the scheduler that
       also cancels the tick; a hand-driven frame has no tick to cancel, but the next
       [frame] call has to be the no-op the [broken] contract promises rather than a diff
       against a half-patched shadow tree.

       The fixup queue goes with it. It holds what *this* pass deferred, so running it in
       some later pass would raise from a frame that had nothing to do with it — the very
       thing [run_fixups] empties the queue to prevent, on the one path that never reaches
       [run_fixups] at all. *)
    match frame_body t with
    | () -> ()
    | exception exn ->
      let backtrace = Stdlib.Printexc.get_raw_backtrace () in
      Scheduler.mark_broken t.scheduler;
      Patcher.abandon_fixups t.ctx;
      (* After the break is recorded, so anything the hook runs finds a driver already in
         its terminal state; swallow-guarded because the raise below is the frame's real
         report and the hook must not displace it. *)
      (try t.on_broken () with
       | _ -> ());
      Stdlib.Printexc.raise_with_backtrace exn backtrace)
;;

let create
  ?time_source
  ?(optimize = true)
  ?(root_kind = `Window)
  ?(on_root_widget_changed = fun (_ : Widget.t) -> ())
  ~on_window_created
  app
  =
  let advance_wall_clock = Option.is_none time_source in
  let time_source =
    Option.value_or_thunk time_source ~default:(fun () ->
      Bonsai.Time_source.create ~start:(Time_ns.now ()))
  in
  (* [default_for_test_handles] reads alarmingly in a production driver, but despite the
     name it is the zero-overhead no-op configuration ([Not_watching], [Not_profiling], no
     timers) and the only instrumentation value [Bonsai_driver] exposes publicly.
     bonsai_term uses it in production for the same reason. *)
  let bonsai =
    Bonsai_driver.create
      ~optimize
      ~time_source
      ~instrumentation:(Bonsai_driver.Instrumentation.default_for_test_handles ())
      app
  in
  (* The scheduler and the signal context both need the [t] they are part of. A [let rec]
     over these records is rejected (the right-hand sides are function applications), so
     they close over a cell that is filled in before anything can read it: nothing here
     runs a callback, and every callback runs from a GLib source armed later. *)
  let cell = ref None in
  let this () = Option.value_exn !cell in
  let scheduler = Scheduler.create ~run_frame:(fun () -> frame (this ())) in
  let ctx =
    Patcher.create_ctx
      ~signals:
        { schedule = (fun effect -> schedule_event (this ()) effect)
        ; in_patch = (fun () -> Scheduler.in_patch scheduler)
        ; on_exn =
            (fun ~node_path exn ->
              eprintf
                "bonsai_gtk: exception in handler at %s: %s\n%!"
                node_path
                (Exn.to_string exn))
        }
      ~on_window_created
      ()
  in
  let t =
    { bonsai
    ; time_source
    ; advance_wall_clock
    ; root_kind
    ; on_root_widget_changed
    ; scheduler
    ; ctx
    ; root = None
    ; stopped = false
    ; drop_effect_hooks = (fun () -> ())
    ; on_broken = (fun () -> ())
    }
  in
  cell := Some t;
  t
;;

(* [None] for a [Windows] root -- a breaking change of M3 Task 8, documented in the mli:
   the widget a [Windows] live holds is the never-shown anchor, and handing that to a
   caller who would present or parent it is strictly worse than making them ask {!windows}
   for the real toplevels. *)
let root_widget t =
  Option.bind t.root ~f:(fun live ->
    match live.Patcher.node.Node.kind with
    | Windows -> None
    | _ -> Some live.Patcher.widget)
;;

(* The order comes from the {i node}'s child list and only the widgets from the lives: the
   patcher's own list keeps insertion order for a [move = None] container (a reorder is a
   keyed diff that touches nothing), which is the right answer for GTK and the wrong one
   for an accessor documented as "the model's own list order" -- measured in
   [live_windows.ml]'s flip block, which is what pins this. Every windows child carries a
   key (the constructor and the shared walk both insist), so nothing is dropped. *)
let windows t =
  match t.root with
  | None -> []
  | Some live ->
    (match live.Patcher.node.Node.kind, live.Patcher.children with
     | Windows, Children.List lives ->
       let by_key =
         List.filter_map lives ~f:(fun (l : Patcher.live) ->
           Option.map l.Patcher.node.Node.key ~f:(fun key -> key, l.Patcher.widget))
       in
       (match live.Patcher.node.Node.children with
        | Children.List nodes ->
          List.filter_map nodes ~f:(fun (n : Node.t) ->
            Option.bind n.Node.key ~f:(fun key ->
              Option.map (List.Assoc.find by_key key ~equal:Key.equal) ~f:(fun widget ->
                key, widget)))
        | _ -> by_key)
     | _ -> [])
;;

(* Deliberately not [stop]: the caller reaching for this is one that has just been told
   the widgets are going away, and [stop] would walk the whole shadow tree disconnecting
   handlers from exactly those widgets. Marking broken removes the tick and turns every
   later frame into the no-op [broken] already promises, and touches nothing. *)
let mark_broken t = Scheduler.mark_broken t.scheduler
let start_tick t ~fps = Scheduler.start_tick t.scheduler ~fps
let broken t = Scheduler.broken t.scheduler

let stop t =
  if not t.stopped
  then (
    t.stopped <- true;
    (* First, so that nothing performed during the teardown below can reach a half-stopped
       driver through the global hooks -- and reset, so a second [stop] does not
       unregister whatever some later driver registered meanwhile. *)
    t.drop_effect_hooks ();
    t.drop_effect_hooks <- (fun () -> ());
    Scheduler.stop t.scheduler;
    (* Dropped, because it is the caller's closure and it captures the caller's widgets --
       [Expert.embed]'s captures the wrapper it hands the embedder and then tells the
       embedder it may drop. A stopped driver will never report a root again, and it is
       not itself collectable (a driver's Bonsai graph is reachable from Incremental's
       global state for the process's life), so a callback left in this field would keep
       whatever it closes over alive for just as long -- turning "you may drop the
       wrapper" into a promise the runtime quietly breaks. Measured: without this, a
       stopped-and-dropped embed's wrapper is never finalized; with it, it is. *)
    t.on_root_widget_changed <- (fun (_ : Widget.t) -> ());
    (* The same drop, for the other caller-owned callback: under [Bonsai_gtk.start] it
       closes over the [GtkApplication] (docs/m2-backlog.md's one-liner), and a stopped
       driver will never mount a window again. *)
    Patcher.drop_on_window_created t.ctx;
    (* [Patcher.destroy] can raise -- the one place teardown calls application code is a
       native node's [destroy] -- and the three steps after it are the ones that make a
       stopped driver actually collectable. Reached through [Exn.protect] so that a native
       widget misbehaving costs the caller an exception rather than a driver that has half
       stopped: [root] cleared (so [root_widget] does not go on answering [Some] for a
       torn-down tree), the last failed pass's closures dropped, and the incremental
       observers invalidated. The exception still reaches the caller, after all of it.
       [Patcher.destroy] is itself collect-and-reraise, so the rest of the tree is torn
       down before it gets here. *)
    Exn.protect
      ~f:(fun () -> Option.iter t.root ~f:(Patcher.destroy t.ctx))
      ~finally:(fun () ->
        t.root <- None;
        (* A last frame that raised inside [mount]/[patch] left its deferred work behind,
           and those closures hold widgets from that pass. *)
        Patcher.abandon_fixups t.ctx;
        (* Without this the incremental graph and every observer Bonsai built for it stay
           reachable from [t.bonsai] for as long as the driver value is, which for an
           embedder that creates a driver per dialog is a real leak. *)
        Bonsai_driver.Expert.invalidate_observers t.bonsai))
;;
