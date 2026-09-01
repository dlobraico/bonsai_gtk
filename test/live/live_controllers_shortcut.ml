open! Core
open Bonsai_gtk_vtree
open Live_controllers_util

(* The Shortcut family's plumbing. What this file can prove is narrower than even the
   click and key files' (see [live_controllers_util.ml]'s header): the family holds no
   slot and no trampoline -- firing goes GTK -> NamedAction -> the Actions group's
   activate, which [live_menus.ml] and [live_input.ml] cover -- so the evidence here is
   the controller's presence, name and phase, the shortcut count GTK itself reports (the
   controller is a GListModel, so [get_n_items] is GTK's own answer, not this library's
   bookkeeping), attach-on-first / detach-on-last, and the in-between diff leaving the
   count right. [armed] listing [Shortcut] while any are installed is the
   families-report-together contract the other suites rely on.

   Neither block presents a toplevel, so the rule carries no lock -- the click file's
   arrangement. *)

let () = ignore (Ocgtk_gtk.GMain.init () : string array)

let shortcut_controller_props label w =
  match
    List.filter (ours w) ~f:(fun c ->
      String.equal (Gobject.Type.name (Gobject.get_type c)) "GtkShortcutController")
  with
  | [] -> printf "%s: no shortcut controller of ours\n" label
  | _ :: _ :: _ as all ->
    printf "%s: %d shortcut controllers of ours!\n" label (List.length all)
  | [ o ] ->
    let phase =
      match W.Event_controller.get_propagation_phase o with
      | `NONE -> "NONE"
      | `CAPTURE -> "CAPTURE"
      | `BUBBLE -> "BUBBLE"
      | `TARGET -> "TARGET"
    in
    printf
      "%s: phase=%s shortcuts=%d\n"
      label
      phase
      (W.Shortcut_controller.get_n_items (cast o))
;;

let () =
  let scheduler = Scheduler.create ~run_frame:(fun () -> ()) in
  let ctx =
    P.create_ctx
      ~signals:
        { schedule = (fun e -> Ui_effect.Expert.eval e ~f:Fn.id ~on_exn:raise)
        ; in_patch = (fun () -> Scheduler.in_patch scheduler)
        ; on_exn =
            (fun ~node_path exn -> printf "EXN at %s: %s\n" node_path (Exn.to_string exn))
        }
      ~on_window_created:(fun _ -> ())
      ()
  in
  let ctrl c =
    Trigger.create ~modifiers:{ Modifiers.none with control = true } (Keyval.of_char c)
  in
  let view ?(phase = Phase.Bubble) chords =
    Node.label
      ~attrs:
        (Attr.actions
           ~scope:"app"
           [ Action_spec.simple ~name:"a" Ui_effect.Ignore
           ; Action_spec.simple ~name:"b" Ui_effect.Ignore
           ; Action_spec.simple ~name:"c" Ui_effect.Ignore
           ]
         :: List.map chords ~f:(fun (c, action) ->
           Attr.shortcut ~phase ~trigger:(ctrl c) ~action ()))
      "sheet"
  in
  let patch live v =
    Scheduler.with_patch_guard scheduler (fun () ->
      let live = P.patch ctx ~path:"chords" ~is_root:true live v in
      P.run_fixups ctx;
      live)
  in
  let live =
    Scheduler.with_patch_guard scheduler (fun () ->
      let live =
        P.mount ctx ~path:"chords" ~is_root:true (view [ 'a', "app.a"; 'b', "app.b" ])
      in
      P.run_fixups ctx;
      live)
  in
  controllers "two chords mounted" live live.widget;
  shortcut_controller_props "two chords mounted" live.widget;
  (* The diff: one departs, one arrives, one survives -- GTK's own count says what the
     list holds afterwards. *)
  let live = patch live (view [ 'a', "app.a"; 'c', "app.c" ]) in
  controllers "one swapped" live live.widget;
  shortcut_controller_props "one swapped" live.widget;
  (* The phase is re-applied from the attrs, the key family's rule. *)
  let live = patch live (view ~phase:Capture [ 'a', "app.a"; 'c', "app.c" ]) in
  shortcut_controller_props "moved to capture" live.widget;
  (* Detach on the last: the controller is removed, not left empty. *)
  let live = patch live (view []) in
  controllers "all chords dropped" live live.widget;
  shortcut_controller_props "all chords dropped" live.widget;
  (* And a later frame gets a fresh controller configured from that frame's attrs. *)
  let live = patch live (view ~phase:Capture [ 'b', "app.b" ]) in
  controllers "one chord back" live live.widget;
  shortcut_controller_props "one chord back" live.widget;
  P.destroy ctx live;
  printf "shortcut plumbing done\n"
;;

(* Exact duplicates collapse to one installed shortcut: two identical entries would be one
   diff key anyway, and GTK running the action twice per press is nothing a caller can
   want. Distinct actions on one trigger are two shortcuts, first-match-wins being GTK's
   business. *)
let () =
  let scheduler = Scheduler.create ~run_frame:(fun () -> ()) in
  let ctx =
    P.create_ctx
      ~signals:
        { schedule = (fun e -> Ui_effect.Expert.eval e ~f:Fn.id ~on_exn:raise)
        ; in_patch = (fun () -> Scheduler.in_patch scheduler)
        ; on_exn =
            (fun ~node_path exn -> printf "EXN at %s: %s\n" node_path (Exn.to_string exn))
        }
      ~on_window_created:(fun _ -> ())
      ()
  in
  let ctrl c =
    Trigger.create ~modifiers:{ Modifiers.none with control = true } (Keyval.of_char c)
  in
  let live =
    Scheduler.with_patch_guard scheduler (fun () ->
      let live =
        P.mount
          ctx
          ~path:"dups"
          ~is_root:true
          (Node.label
             ~attrs:
               [ Attr.actions
                   ~scope:"app"
                   [ Action_spec.simple ~name:"a" Ui_effect.Ignore ]
               ; Attr.shortcut ~trigger:(ctrl 'a') ~action:"app.a" ()
               ; Attr.shortcut ~trigger:(ctrl 'a') ~action:"app.a" ()
               ]
             "sheet")
      in
      P.run_fixups ctx;
      live)
  in
  shortcut_controller_props "exact duplicate collapsed" live.widget;
  P.destroy ctx live;
  printf "shortcut duplicates done\n"
;;
