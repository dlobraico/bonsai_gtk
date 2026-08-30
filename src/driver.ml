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
  }

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
  | `Window, Window _ -> ()
  | `Window, k ->
    invalid_argf
      "Bonsai_gtk: the root node must be a Node.window, got %s. A tree started this way \
       shows its own root, and a GtkWindow is the only thing GTK can show on its own. \
       Use Bonsai_gtk.Expert.embed for a tree parented into a container you already own."
      (Kind.name k)
      ()
  | `Not_window, Window _ ->
    invalid_arg
      "Bonsai_gtk.embed: the root node is a Node.window, but an embedded tree is \
       parented into a container the caller owns and a GtkWindow is a toplevel that \
       cannot be parented. Use Bonsai_gtk.start for a tree that owns its window, or make \
       the root a container."
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
          destroyed the old one rather than updating it in place. Under [start] this arm
          is unreachable -- a windowed root is always a [Window], so [same_kind] always
          holds at the root -- but an embedded root is an arbitrary node, and a
          [Node.label "Loading..."] that becomes a [Node.box [...]] on the next frame is
          an ordinary page. Whoever put the old widget somewhere has to be told, or the
          container goes on holding a widget nothing renders into again. *)
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
    }
  in
  cell := Some t;
  t
;;

let root_widget t = Option.map t.root ~f:(fun live -> live.Patcher.widget)

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
    Option.iter t.root ~f:(Patcher.destroy t.ctx);
    t.root <- None;
    (* A last frame that raised inside [mount]/[patch] left its deferred work behind, and
       those closures hold widgets from that pass. *)
    Patcher.abandon_fixups t.ctx;
    (* Without this the incremental graph and every observer Bonsai built for it stay
       reachable from [t.bonsai] for as long as the driver value is, which for an embedder
       that creates a driver per dialog is a real leak. *)
    Bonsai_driver.Expert.invalidate_observers t.bonsai)
;;
