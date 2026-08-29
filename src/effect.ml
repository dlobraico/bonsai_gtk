open! Core
include Ui_effect

(* [start] runs one application per process and holds it for the process's lifetime, so a
   single cell is enough; [quit] reads it when performed rather than when built, which is
   what lets applications put [Effect.quit] in an attr before [start] has run. *)
let app : Gtk_import.W.Application.t option ref = ref None

let quit =
  of_thunk (fun () ->
    match !app with
    | Some app -> Ocgtk_gio.Gio.Wrappers.Application.quit app
    | None -> eprintf "bonsai_gtk: Effect.quit outside of Bonsai_gtk.start\n%!")
;;

module For_start = struct
  let set_app a = app := Some a
end
