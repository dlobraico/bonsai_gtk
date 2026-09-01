open! Core
open Bonsai_gtk_vtree
module Actions = Bonsai_gtk.Private.Actions
module Gvariant = Bonsai_gtk.Private.Gtk_import.Gvariant
module Live_tree = Bonsai_gtk.Private.Live_tree
module P = Bonsai_gtk.Private.Patcher
module Scheduler = Bonsai_gtk.Private.Scheduler
module W = Bonsai_gtk.Private.Gtk_import.W
module Widget = Bonsai_gtk.Private.Gtk_import.Widget

let cast = Bonsai_gtk.Private.Gtk_import.cast

(* The action system against real GTK (M3 Task 6 step 6). Activations go through
   [Widget.activate_action_variant] on the {i menu button} -- GTK's own resolution walk,
   from the widget through its ancestors, which is exactly the path a menu item takes and
   so also proves the group the runtime inserted is where GTK looks for it. (The plan
   sketched [Action_group.activate_action] on a group "read back" from the widget; GTK4
   has no read-back for inserted groups -- gtk_widget_get_action_group was GTK3 -- and the
   widget-side entry point is the stronger probe anyway.) The state and enabled goldens
   are [Actions.dump]: the [GAction]-interface read-backs, the only honest source for a
   controlled-prop claim. *)

let () = ignore (Ocgtk_gtk.GMain.init () : string array)

let () =
  let scheduler = Scheduler.create ~run_frame:(fun () -> ()) in
  let log = ref [] in
  let record s = log := s :: !log in
  let drain label =
    printf "%s: (%s)\n" label (String.concat ~sep:" " (List.rev !log));
    log := []
  in
  let ctx =
    P.create_ctx
      ~signals:
        { schedule = (fun e -> Ui_effect.Expert.eval e ~f:Fn.id ~on_exn:raise)
        ; in_patch = (fun () -> Scheduler.in_patch scheduler)
        ; on_exn =
            (fun ~node_path exn -> printf "EXN at %s: %s\n" node_path (Exn.to_string exn))
        }
      ~on_window_created:(fun w -> W.Window.present (cast w))
      ()
  in
  let eff s = Ui_effect.of_sync_fun record s in
  let view ~dark ~theme ~ping_enabled =
    Node.window
      ~title:"menus"
      (Node.box
         ~orientation:Vertical
         ~attrs:
           [ Attr.actions
               ~scope:"app"
               [ Action_spec.simple ~enabled:ping_enabled ~name:"ping" (eff "ping")
               ; Action_spec.toggle
                   ~name:"dark"
                   ~state:dark
                   (eff (sprintf "dark-requested (model holds %b)" dark))
               ; Action_spec.radio ~name:"theme" ~state:theme (fun target ->
                   Ui_effect.of_sync_fun record ("theme-requested:" ^ target))
               ]
           ]
         [ Node.menu_button
             ~label:"menu"
             ~menu:
               [ Menu.item ~label:"Ping" ~action:"app.ping" ~accel:"<Control>p" ()
               ; Menu.submenu
                   ~label:"View"
                   [ Menu.item ~label:"Dark" ~action:"app.dark" ()
                   ; Menu.section
                       ~label:"Theme"
                       [ Menu.item ~label:"Solar" ~action:"app.theme::solar" ()
                       ; Menu.item ~label:"Mono" ~action:"app.theme::mono" ()
                       ]
                   ]
               ]
             ()
         ])
  in
  let patch live v =
    Scheduler.with_patch_guard scheduler (fun () ->
      let live = P.patch ctx ~path:"menus" ~is_root:true live v in
      P.run_fixups ctx;
      live)
  in
  let live =
    Scheduler.with_patch_guard scheduler (fun () ->
      let live =
        P.mount
          ctx
          ~path:"menus"
          ~is_root:true
          (view ~dark:false ~theme:"solar" ~ping_enabled:true)
      in
      P.run_fixups ctx;
      live)
  in
  let holder (l : P.live) =
    match l.children with
    | Single (Some box) -> box
    | _ -> assert false
  in
  let button (l : P.live) =
    match (holder l).P.children with
    | List [ mb ] -> mb.P.widget
    | _ -> assert false
  in
  print_s (Live_tree.dump live.widget);
  print_s (Actions.dump (holder live).P.actions);
  (* A simple activation, resolved by GTK from the menu button's position -- the exact
     walk a menu item's click takes. *)
  printf
    "activate app.ping resolves: %b\n"
    (Widget.activate_action_variant (button live) "app.ping" None);
  drain "after activating ping";
  (* A name nothing provides does not resolve -- GTK's side of the same claim the
     resolution walk makes from the vtree. *)
  printf
    "activate app.nope resolves: %b\n"
    (Widget.activate_action_variant (button live) "app.nope" None);
  (* The declined toggle: activation requests, the model here does not move, and the
     read-back stands still -- the checkmark that does not move. *)
  printf
    "activate app.dark resolves: %b\n"
    (Widget.activate_action_variant (button live) "app.dark" None);
  drain "after activating dark";
  print_s (Actions.dump (holder live).P.actions);
  (* The model accepts on its own schedule: the next frame's controlled write moves GTK. *)
  let live = patch live (view ~dark:true ~theme:"solar" ~ping_enabled:true) in
  print_s (Actions.dump (holder live).P.actions);
  (* The radio, with its target riding the activation. *)
  printf
    "activate app.theme::mono resolves: %b\n"
    (Widget.activate_action_variant
       (button live)
       "app.theme"
       (Some (Gvariant.of_string "mono")));
  drain "after activating theme";
  let live = patch live (view ~dark:true ~theme:"mono" ~ping_enabled:true) in
  (* And enabled is controlled the same way. *)
  let live = patch live (view ~dark:true ~theme:"mono" ~ping_enabled:false) in
  print_s (Actions.dump (holder live).P.actions);
  P.destroy ctx live;
  printf "actions round trip done\n"
;;

(* Pre-flight correction 1's activation half, pinned: an [Attr.actions] first appearing on
   an already-mounted node resolves for activation (the item-tracker half -- items in an
   already-open PopoverMenu rendering insensitive -- is the documented limitation on
   [Attr.actions], measured by the pre-flight and not re-measured here). *)
let () =
  let scheduler = Scheduler.create ~run_frame:(fun () -> ()) in
  let fired = ref 0 in
  let ctx =
    P.create_ctx
      ~signals:
        { schedule = (fun e -> Ui_effect.Expert.eval e ~f:Fn.id ~on_exn:raise)
        ; in_patch = (fun () -> Scheduler.in_patch scheduler)
        ; on_exn =
            (fun ~node_path exn -> printf "EXN at %s: %s\n" node_path (Exn.to_string exn))
        }
      ~on_window_created:(fun w -> W.Window.present (cast w))
      ()
  in
  let view ~with_actions =
    Node.window
      ~title:"late"
      (Node.box
         ~orientation:Vertical
         ~attrs:
           (if with_actions
            then
              [ Attr.actions
                  ~scope:"late"
                  [ Action_spec.simple
                      ~name:"fire"
                      (Ui_effect.of_sync_fun (fun () -> incr fired) ())
                  ]
              ]
            else [])
         [ Node.label "body" ])
  in
  let live =
    Scheduler.with_patch_guard scheduler (fun () ->
      let live = P.mount ctx ~path:"late" ~is_root:true (view ~with_actions:false) in
      P.run_fixups ctx;
      live)
  in
  let box_widget (l : P.live) =
    match l.children with
    | Single (Some box) -> box.P.widget
    | _ -> assert false
  in
  printf
    "late.fire before the attr exists: %b\n"
    (Widget.activate_action_variant (box_widget live) "late.fire" None);
  let live =
    Scheduler.with_patch_guard scheduler (fun () ->
      let live = P.patch ctx ~path:"late" ~is_root:true live (view ~with_actions:true) in
      P.run_fixups ctx;
      live)
  in
  (* Bound first: printf's arguments evaluate right-to-left, so an inline [!fired] would
     read the pre-activation count. *)
  let resolved = Widget.activate_action_variant (box_widget live) "late.fire" None in
  printf "late.fire after the attr appeared: %b (fired %d)\n" resolved !fired;
  P.destroy ctx live;
  printf "late actions done\n"
;;
