open! Core
open Gtk_import

type t =
  { run_frame : unit -> unit
  ; mutable idle_armed : bool
  ; mutable in_patch : bool
  ; mutable tick : Glib.Timeout.id option
  ; mutable stopped : bool
  }

let create ~run_frame =
  { run_frame; idle_armed = false; in_patch = false; tick = None; stopped = false }
;;

let in_patch t = t.in_patch
let ticking t = Option.is_some t.tick

let with_patch_guard t f =
  t.in_patch <- true;
  Exn.protect ~f ~finally:(fun () -> t.in_patch <- false)
;;

(* Every frame runs underneath a GLib callback, so nothing may escape: an OCaml exception
   crossing a C frame would at best skip GLib's own bookkeeping. *)
let guarded_frame t =
  match t.run_frame () with
  | () -> ()
  | exception exn -> eprintf "bonsai_gtk: exception in frame: %s\n%!" (Exn.to_string exn)
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

let start_tick t ~fps =
  Option.iter t.tick ~f:Glib.Timeout.remove;
  t.tick <- None;
  (* A non-positive rate is "never tick" rather than an error or, worse, the 1ms tick a
     naive [1000. /. fps] would round to. *)
  if Float.( > ) fps 0.
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
                true))
            ()))
;;

let stop t =
  t.stopped <- true;
  Option.iter t.tick ~f:Glib.Timeout.remove;
  t.tick <- None
;;
