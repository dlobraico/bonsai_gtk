open! Core
open Gtk_import
module Gio_application = Ocgtk_gio.Gio.Wrappers.Application

(* [activate] runs as a GLib callback, so an exception here would cross a C frame. *)
let guarded ~where f =
  match f () with
  | () -> ()
  | exception exn ->
    eprintf "bonsai_gtk: exception in %s: %s\n%!" where (Exn.to_string exn)
;;

let start
  ?(application_id = "org.bonsai_gtk.app")
  ?time_source
  ?optimize
  ?(target_frames_per_second = 60.)
  app
  =
  let gapp = W.Application.new_ (Some application_id) [ `DEFAULT_FLAGS ] in
  Effect.For_start.set_app gapp;
  let driver = ref None in
  let on_window_created (widget : Widget.t) =
    (* GTK windows have no parent to own them: the application is what keeps this one
       alive, and presenting it is what puts it on screen. *)
    W.Application.add_window gapp (cast widget);
    W.Window.present (cast widget)
  in
  ignore
    (Gio_application.on_activate gapp ~callback:(fun () ->
       guarded ~where:"activate" (fun () ->
         match !driver with
         (* A second activation is another launch of the same application id handed to us
            by GTK; GTK re-presents the existing window itself. *)
         | Some _ -> ()
         | None ->
           let d = Driver.create ?time_source ?optimize ~on_window_created app in
           driver := Some d;
           (* The first frame is what mounts the window, so it has to happen before the
              loop starts spinning, not on the first tick. *)
           Driver.frame d;
           Driver.start_tick d ~fps:target_frames_per_second))
     : Gobject.Signal.handler_id);
  (* [0]/[None] rather than the real command line: GTK's own argument parsing is not
     something an embedded app should inherit by default. *)
  let status = Gio_application.run gapp 0 None in
  Option.iter !driver ~f:Driver.stop;
  status
;;
