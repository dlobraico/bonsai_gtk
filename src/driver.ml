open! Core
open Bonsai_gtk_vtree

type t =
  { bonsai : Node.t Bonsai_driver.t
  ; time_source : Bonsai.Time_source.t
  ; advance_wall_clock : bool
  ; scheduler : Scheduler.t
  ; ctx : Patcher.ctx
  ; mutable root : Patcher.live option
  ; mutable last : Node.t option
  }

let schedule_event t effect =
  Bonsai_driver.schedule_event t.bonsai effect;
  Scheduler.request_frame t.scheduler
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
  if t.advance_wall_clock
  then (
    Bonsai.Time_source.advance_clock t.time_source ~to_:(Time_ns.now ());
    Bonsai.Time_source.Private.flush t.time_source);
  Bonsai_driver.flush t.bonsai;
  let node = Bonsai_driver.result t.bonsai in
  (* Bonsai hands back the physically same node when nothing it depends on changed, so
     this skips the whole diff on a frame that only advanced the clock. *)
  let changed =
    match t.last with
    | None -> true
    | Some previous -> not (phys_equal previous node)
  in
  if changed
  then (
    check_root node;
    Scheduler.with_patch_guard t.scheduler (fun () ->
      t.root
      <- Some
           (match t.root with
            | None -> Patcher.mount t.ctx ~path:"root" node
            | Some live -> Patcher.patch t.ctx ~path:"root" live node));
    t.last <- Some node);
  Bonsai_driver.trigger_lifecycles t.bonsai;
  (* [trigger_lifecycles] *schedules* the after-display effects rather than applying them,
     so another frame is needed before their results are on screen. Under a tick that
     frame is already coming; without one we have to ask for it. The distinction matters:
     [has_after_display_events] is true whenever the computation contains an after-display
     handler at all (a single [Edge.on_change] is enough), so arming an idle
     unconditionally would spin the main loop at full speed for the life of the app. *)
  if Bonsai_driver.has_after_display_events t.bonsai
     && not (Scheduler.ticking t.scheduler)
  then Scheduler.request_frame t.scheduler
;;

let create ?time_source ?(optimize = true) ~on_window_created app =
  let advance_wall_clock = Option.is_none time_source in
  let time_source =
    Option.value_or_thunk time_source ~default:(fun () ->
      Bonsai.Time_source.create ~start:(Time_ns.now ()))
  in
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
  let ctx : Patcher.ctx =
    { signals =
        { schedule = (fun effect -> schedule_event (this ()) effect)
        ; in_patch = (fun () -> Scheduler.in_patch scheduler)
        ; on_exn =
            (fun ~node_path exn ->
              eprintf
                "bonsai_gtk: exception in handler at %s: %s\n%!"
                node_path
                (Exn.to_string exn))
        }
    ; on_window_created
    }
  in
  let t =
    { bonsai; time_source; advance_wall_clock; scheduler; ctx; root = None; last = None }
  in
  cell := Some t;
  t
;;

let root_widget t = Option.map t.root ~f:(fun live -> live.Patcher.widget)
let start_tick t ~fps = Scheduler.start_tick t.scheduler ~fps

let stop t =
  Scheduler.stop t.scheduler;
  Option.iter t.root ~f:(Patcher.destroy t.ctx);
  t.root <- None;
  t.last <- None
;;
