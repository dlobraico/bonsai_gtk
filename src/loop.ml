open! Core
open Gtk_import
module Gio_application = Ocgtk_gio.Gio.Wrappers.Application

(* [g_application_run]'s own status codes come from the application; 1 is ours, for "the
   app never got off the ground". 2 is ours too, for "it ran, then a frame raised and the
   driver stopped" — see {!Driver.broken}. *)
let startup_failure_status = 1
let broken_driver_status = 2

let start
  ?(application_id = "org.bonsai_gtk.app")
  ?time_source
  ?optimize
  ?(target_frames_per_second = 60.)
  app
  =
  let gapp = W.Application.new_ (Some application_id) [ `DEFAULT_FLAGS ] in
  Gtk_effect.For_start.set_app gapp;
  let driver = ref None in
  let failure = ref None in
  let on_window_created (widget : Widget.t) =
    (* GTK windows have no parent to own them: the application is what keeps this one
       alive, and presenting it is what puts it on screen. *)
    W.Application.add_window gapp (cast widget);
    W.Window.present (cast widget)
  in
  ignore
    (Gio_application.on_activate gapp ~callback:(fun () ->
       (* [activate] is a GLib callback, so an exception here would cross a C frame. It is
          also the only chance this application gets: with no window added, GTK returns
          from [run] straight away, and a zero status for an app that never started would
          be a lie. So it is recorded rather than only logged. *)
       match !driver with
       (* A second activation is another launch of the same application id handed to us by
          GTK; GTK re-presents the existing window itself. *)
       | Some _ -> ()
       | None ->
         (match
            (* Named rather than defaulted: [start] and [Expert.embed] are the two callers
               of [Driver.create] and they want opposite rules, so both say which they
               are. *)
            let d =
              Driver.create
                ?time_source
                ?optimize
                ~root_kind:`Window
                ~on_window_created
                app
            in
            driver := Some d;
            (* The first frame is what mounts the window, so it has to happen before the
               loop starts spinning, not on the first tick. *)
            Driver.frame d;
            Driver.start_tick d ~fps:target_frames_per_second
          with
          | () -> ()
          | exception exn ->
            eprintf "bonsai_gtk: exception in activate: %s\n%!" (Exn.to_string exn);
            failure := Some exn))
     : Gobject.Signal.handler_id);
  (* [0]/[None] rather than the real command line: GTK's own argument parsing is not
     something an embedded app should inherit by default. *)
  let status = Gio_application.run gapp 0 None in
  (* Read before [stop], which tears the driver down. *)
  let broke = Option.exists !driver ~f:Driver.broken in
  Option.iter !driver ~f:Driver.stop;
  Gtk_effect.For_start.clear_app ();
  if status <> 0
  then status
  else if Option.is_some !failure
  then startup_failure_status
  else if broke
  then broken_driver_status
  else status
;;
