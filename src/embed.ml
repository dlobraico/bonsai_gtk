open! Core
open Gtk_import

type t =
  { driver : Driver.t
  ; (* Captured at mount rather than read from the driver on demand: [Driver.root_widget]
       answers [None] after [stop], and the widget the embedder has to remove from its
       container is precisely the one it needs after [stop]. Holding it here also keeps a
       reference to the root for this record's lifetime, which is a small part of why an
       embedded tree outlives its host. *)
    widget : Widget.t
  }

let widget t = t.widget
let frame t = Driver.frame t.driver
let schedule_event t effect = Driver.schedule_event t.driver effect
let broken t = Driver.broken t.driver
let stop t = Driver.stop t.driver

let create ?time_source ?optimize ?(target_frames_per_second = 60.) app =
  let driver =
    Driver.create
      ?time_source
      ?optimize
      ~root_kind:`Not_window
      ~on_window_created:(fun _ ->
        (* Unreachable: [root_kind] refuses a window at the root and the patcher refuses
           one anywhere below it, so no [Window] node ever reaches a mount here. It is a
           [failwith] rather than a no-op because reaching it would mean one of those two
           checks had a hole, and a silently unpresented window is the failure mode §11
           exists to prevent. *)
        failwith
          "bonsai_gtk: a window was mounted inside an embedded tree, which the root-kind \
           check and the patcher should both have rejected")
      app
  in
  (* The first frame is what mounts the tree, and it is the frame most likely to raise: a
     constructor's [Invalid_argument], a window at the root, a misplaced placement attr.
     It runs before the tick is installed so that a failure leaves no timeout behind, and
     it runs under a [stop] on the way out because the caller is about to receive an
     exception instead of a [t] and would otherwise have no handle to tear the partial
     tree down. *)
  (match Driver.frame driver with
   | () -> ()
   | exception exn ->
     let backtrace = Stdlib.Printexc.get_raw_backtrace () in
     Driver.stop driver;
     Stdlib.Printexc.raise_with_backtrace exn backtrace);
  let widget =
    match Driver.root_widget driver with
    | Some w -> w
    | None ->
      (* [Driver.frame] returned, so it mounted; the only other way here is a driver that
         was already broken, which a fresh one cannot be. *)
      failwith "bonsai_gtk: an embedded tree mounted no root widget"
  in
  (* The backstop for a host that disposes its children rather than dropping the last
     reference to them. Measured under GTK 4: neither [gtk_window_destroy] on an ancestor
     nor the unparenting that a container's own dispose performs emits [destroy] on a
     widget something still holds a reference to -- and the shadow tree holds one for
     every widget in this tree -- so in every ordinary teardown this handler stays silent
     and the tree simply survives, off screen and still patchable. The one path it covers
     is an embedder that runs dispose on the tree outright, after which patching would
     touch widgets GTK has already emptied.

     [mark_broken] rather than [stop]: [stop] would walk this very subtree disconnecting
     handlers from the widgets whose disposal is the thing being reported, and we are
     inside one of their signal emissions while it happens. Marking broken removes the
     tick and makes every later frame the no-op [Driver.broken] promises, and touches no
     widget at all. The embedder still calls [stop] itself, which is then a tear-down of a
     driver that has already stopped rendering. *)
  ignore
    (W.Widget.on_destroy widget ~callback:(fun () -> Driver.mark_broken driver)
     : Gobject.Signal.handler_id);
  Driver.start_tick driver ~fps:target_frames_per_second;
  { driver; widget }
;;
