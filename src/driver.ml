open! Core
open Bonsai_gtk_vtree

type t =
  { bonsai : Node.t Bonsai_driver.t
  ; time_source : Bonsai.Time_source.t
  ; advance_wall_clock : bool
  ; scheduler : Scheduler.t
  ; ctx : Patcher.ctx
  ; mutable root : Patcher.live option
  ; mutable stopped : bool
  }

let schedule_event t effect =
  (* A broken driver renders nothing again (see [frame]), so queueing effects into it only
     grows a queue nobody drains — a frozen window whose memory keeps climbing. *)
  if not (Scheduler.broken t.scheduler)
  then (
    Bonsai_driver.schedule_event t.bonsai effect;
    Scheduler.request_frame t.scheduler)
;;

let check_root (node : Node.t) =
  match node.kind with
  | Window _ -> ()
  | k ->
    invalid_argf
      "Bonsai_gtk: the root node must be a Node.window, got %s"
      (Kind.name k)
      ()
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
    if t.advance_wall_clock
    then (
      Bonsai.Time_source.advance_clock t.time_source ~to_:(Time_ns.now ());
      Bonsai.Time_source.Private.flush t.time_source);
    Bonsai_driver.flush t.bonsai;
    let node = Bonsai_driver.result t.bonsai in
    (* Every frame patches, including the frames on which Bonsai hands back the physically
       same node.

       Skipping those looks like a free optimisation and is not. A model that *declines* a
       user's edit -- the digits-only field handed a letter, the switch the model refuses
       to flip, the stack page it will not navigate to -- leaves its state exactly as it
       was, so its view is the same value it was last frame. The patch that would put the
       widget back is therefore precisely the patch a physical-equality guard throws away,
       and the declined edit stands on screen. That is the bug spec §6.5 exists to
       prevent, and both halves of the cure -- [Widget_impl.reassert] and the
       stack-selection fixup -- live inside the patch being skipped.

       The cost is bounded rather than free: a frame that changed nothing still walks the
       shadow tree, but [Kind.equal_props] skips every impl [update] and [Attrs.diff]
       writes nothing, so no GTK call is made. Frames only happen on an event or on the
       tick. *)
    check_root node;
    Scheduler.with_patch_guard t.scheduler (fun () ->
      t.root
      <- Some
           (match t.root with
            | None -> Patcher.mount t.ctx ~path:"root" ~is_root:true node
            | Some live -> Patcher.patch t.ctx ~path:"root" ~is_root:true live node);
      (* Inside the guard, and after the whole tree exists: this is where a
         [stack_switcher] finds the stack it names and a stack selects its page, and both
         write properties GTK notifies about. *)
      Patcher.run_fixups t.ctx);
    Bonsai_driver.trigger_lifecycles t.bonsai;
    (* [trigger_lifecycles] *schedules* the after-display effects rather than applying
       them, so another frame is needed before their results are on screen. Under a tick
       that frame is already coming. Without one we ask for it — but on the rate-limited
       path, never the idle: [has_after_display_events] is true whenever the computation
       contains an after-display handler at all (one [Clock.every] is enough), so every
       frame would request its successor and an idle would run them back to back at full
       CPU. *)
    if Bonsai_driver.has_after_display_events t.bonsai
       && not (Scheduler.ticking t.scheduler)
    then Scheduler.request_frame_soon t.scheduler)
;;

let create ?time_source ?(optimize = true) ~on_window_created app =
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
  in
  let t =
    { bonsai
    ; time_source
    ; advance_wall_clock
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
let start_tick t ~fps = Scheduler.start_tick t.scheduler ~fps
let broken t = Scheduler.broken t.scheduler

let stop t =
  if not t.stopped
  then (
    t.stopped <- true;
    Scheduler.stop t.scheduler;
    Option.iter t.root ~f:(Patcher.destroy t.ctx);
    t.root <- None;
    (* Without this the incremental graph and every observer Bonsai built for it stay
       reachable from [t.bonsai] for as long as the driver value is, which for an embedder
       that creates a driver per dialog is a real leak. *)
    Bonsai_driver.Expert.invalidate_observers t.bonsai)
;;
