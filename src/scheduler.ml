open! Core
open Gtk_import

(* The cadence {!request_frame_soon} runs at, in milliseconds: one 60Hz frame, the same
   rate the default tick would have provided. *)
let soon_ms = 16

type t =
  { run_frame : unit -> unit
  ; mutable idle_armed : bool
  ; mutable soon : Glib.Timeout.id option
  ; mutable in_patch : bool
  ; mutable tick : Glib.Timeout.id option
  ; mutable stopped : bool
  ; mutable broken : bool
  }

let create ~run_frame =
  { run_frame
  ; idle_armed = false
  ; soon = None
  ; in_patch = false
  ; tick = None
  ; stopped = false
  ; broken = false
  }
;;

let in_patch t = t.in_patch
let ticking t = Option.is_some t.tick
let broken t = t.broken

let stop t =
  t.stopped <- true;
  Option.iter t.tick ~f:Glib.Timeout.remove;
  t.tick <- None;
  Option.iter t.soon ~f:Glib.Timeout.remove;
  t.soon <- None
;;

(* Saved and restored rather than cleared: a nested [with_patch_guard] that cleared the
   flag on its own exit would leave the rest of the outer patch dispatching signals into
   Bonsai mid-patch, and silently. Nothing in M1 nests — [Driver.frame] is the only caller
   and no GTK call the patcher makes spins the main loop — so this is about the next thing
   that does (a dialog, anything that iterates the loop) rather than about a live bug. *)
let with_patch_guard t f =
  let was = t.in_patch in
  t.in_patch <- true;
  Exn.protect ~f ~finally:(fun () -> t.in_patch <- was)
;;

(* A raising frame stops the scheduler rather than being logged and retried. The patcher
   mutates GTK as it walks the ops and only then writes the shadow tree back, so a frame
   that dies part-way leaves GTK's tree ahead of the shadow tree's idea of it. Every later
   frame would diff from that stale shadow tree — wrong ordering at best, and the same
   exception again at tick rate at worst. One clear error and a stopped driver beat a live
   app patching a tree it no longer describes. What becomes of the widgets is the entry
   point's business, decided through [Driver.set_on_broken]: [Loop.start] quits the
   application (M3's close-request veto made a broken app's windows unclosable, so "frozen
   but still displayed" stopped being an option there); an embedder's stay frozen at their
   last good state, on its own main loop.

   This is the whole of the state transition, and it lives here rather than inside
   [guarded_frame] because a frame driven by hand — an embedder with its own main loop, a
   test — raises out of [Driver.frame] without ever reaching the scheduler's guarded path,
   and the promise that nothing patches the tree again has to hold for that frame too. *)
let mark_broken t =
  t.broken <- true;
  stop t
;;

(* Every frame runs underneath a GLib callback, so nothing may escape: an OCaml exception
   crossing a C frame would at best skip GLib's own bookkeeping. [run_frame] is expected
   to have called [mark_broken] on its way out (that is what [Driver.frame] does); calling
   it again here is idempotent and keeps this scheduler's own contract independent of who
   drives it. *)
let guarded_frame t =
  match t.run_frame () with
  | () -> ()
  | exception exn ->
    eprintf
      "bonsai_gtk: exception in frame, stopping the driver: %s\n%!"
      (Exn.to_string exn);
    mark_broken t
;;

let request_frame t =
  if (not t.stopped) && not t.idle_armed
  then (
    t.idle_armed <- true;
    ignore
      (Glib.Idle.add ~prio:(Glib.int_of_priority `HIGH_IDLE) (fun () ->
         (* Cleared first, so that an effect scheduled *by* this frame arms the next one
            instead of being swallowed. *)
         t.idle_armed <- false;
         if not t.stopped then guarded_frame t;
         false)
       : Glib.Idle.id))
;;

let request_frame_soon t =
  (* An idle already armed will run a frame sooner than this timeout would, and that frame
     re-requests if it still needs to — so there is nothing to add here. *)
  if (not t.stopped) && (not t.idle_armed) && Option.is_none t.soon
  then
    t.soon
    <- Some
         (Glib.Timeout.add
            ~ms:soon_ms
            ~callback:(fun () ->
              (* Cleared first, for the same reason [request_frame] clears its flag first:
                 the frame this runs may well ask for the next one. *)
              t.soon <- None;
              if not t.stopped then guarded_frame t;
              false)
            ())
;;

let start_tick t ~fps =
  Option.iter t.tick ~f:Glib.Timeout.remove;
  t.tick <- None;
  (* A non-positive rate is "never tick" rather than an error or, worse, the 1ms tick a
     naive [1000. /. fps] would round to. A stopped scheduler is never restarted. *)
  if (not t.stopped) && Float.( > ) fps 0.
  then (
    let ms = Int.max 1 (Float.to_int (1000. /. fps)) in
    t.tick
    <- Some
         (Glib.Timeout.add
            ~ms
            ~callback:(fun () ->
              if t.stopped
              then false
              else (
                guarded_frame t;
                (* [guarded_frame] stops the scheduler if the frame raised, which has
                   already removed this very source; returning [false] keeps GLib from
                   re-arming it either way. *)
                not t.stopped))
            ()))
;;
