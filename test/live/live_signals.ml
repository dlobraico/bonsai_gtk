open! Core
open Bonsai_gtk_vtree
module Gobject = Bonsai_gtk.Private.Gtk_import.Gobject
module Signals = Bonsai_gtk.Private.Signals
module W = Bonsai_gtk.Private.Gtk_import.W

let () =
  ignore (Ocgtk_gtk.GMain.init () : string array);
  let scheduled = ref 0 in
  let in_patch = ref false in
  let ctx : Signals.ctx =
    { schedule = (fun _ -> incr scheduled)
    ; in_patch = (fun () -> !in_patch)
    ; on_exn =
        (fun ~node_path exn -> printf "EXN at %s: %s\n" node_path (Exn.to_string exn))
    }
  in
  let button = (W.Button.new_with_label "b" :> Bonsai_gtk.Widget.t) in
  let slots, _ids =
    Signals.connect_all
      ctx
      ~node_path:"root/0"
      button
      [ Bonsai_gtk.Private.W_button.clicked ]
  in
  (* An empty slot is inert even outside a patch: nothing is connected until the first
     [update_slots]. *)
  Gobject.Signal.emit_by_name button ~name:"clicked";
  printf "empty slot: %d\n" !scheduled;
  Signals.update_slots slots (Attrs.of_list [ Attr.on_clicked Ui_effect.Ignore ]);
  Gobject.Signal.emit_by_name button ~name:"clicked";
  printf "armed slot: %d\n" !scheduled;
  (* The guard: a signal GTK emits synchronously from inside a patch must never reach
     Bonsai, however the handler slot is armed. *)
  in_patch := true;
  Gobject.Signal.emit_by_name button ~name:"clicked";
  in_patch := false;
  printf "during patch: %d\n" !scheduled;
  Gobject.Signal.emit_by_name button ~name:"clicked";
  printf "after patch: %d\n" !scheduled;
  (* A raising handler is logged, not propagated into GTK's C frame. *)
  Signals.update_slots
    slots
    (Attrs.of_list [ Attr.on_clicked (Ui_effect.of_thunk (fun () -> failwith "boom")) ]);
  Gobject.Signal.emit_by_name button ~name:"clicked";
  printf "after raising handler: %d\n" !scheduled;
  (* [clear_slots] disarms without disconnecting, which is what [Patcher.disarm] relies on
     when GTK is about to emit during teardown. *)
  Signals.clear_slots slots;
  Gobject.Signal.emit_by_name button ~name:"clicked";
  printf "after clear: %d\n" !scheduled
;;
