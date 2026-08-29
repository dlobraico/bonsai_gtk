open! Core
include Ui_effect

(* One application per process: [start] holds the GLib main loop for its whole call, so
   there is never more than one live at a time and a single cell is enough. [quit] reads
   it when the effect is *performed* rather than when it is built, which is what lets an
   application put [Effect.quit] in an attr before [start] has run. *)
let app : Gtk_import.W.Application.t option ref = ref None

let quit =
  of_thunk (fun () ->
    match !app with
    | Some app -> Ocgtk_gio.Gio.Wrappers.Application.quit app
    | None -> eprintf "bonsai_gtk: Effect.quit outside of Bonsai_gtk.start\n%!")
;;

module For_start = struct
  let set_app a =
    if Option.is_some !app
    then
      eprintf
        "bonsai_gtk: Bonsai_gtk.start called while another application is still running. \
         Effect.quit will now quit the new one; only one start per process is supported.\n\
         %!";
    app := Some a
  ;;

  let clear_app () = app := None
end
