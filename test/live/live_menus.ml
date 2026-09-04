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

(* Task-6 review I1, the measurement: does a {i late} action group (inserted after its
   widget was rooted -- pre-flight 1's bad ordering) ever reach a PopoverMenu's item
   tracker, and through which path? Three probes over one tree: the mount-time group's
   item (control); an item added by an {b in-place menu edit} (remove_all + refill on the
   same GMenu -- the path the mli's workaround claim named); and the same menu after a
   {b full model re-set} (None for a frame, then back -- fresh set_menu_model). The golden
   is the answer, and the mli says whatever it says. *)
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
      ~on_window_created:(fun w -> W.Window.present (cast w))
      ()
  in
  let pump () =
    let rec go n =
      if n > 0 && Bonsai_gtk.Private.Gtk_import.Glib.Main.iteration false then go (n - 1)
    in
    go 50
  in
  let base_actions =
    Attr.actions ~scope:"base" [ Action_spec.simple ~name:"x" Ui_effect.Ignore ]
  in
  let late_actions =
    Attr.actions ~scope:"late" [ Action_spec.simple ~name:"y" Ui_effect.Ignore ]
  in
  let menu ~with_late =
    Menu.item ~label:"X" ~action:"base.x" ()
    :: (if with_late then [ Menu.item ~label:"Y" ~action:"late.y" () ] else [])
  in
  let view ~late ~menu_state =
    Node.window
      ~title:"rebind"
      ~attrs:(if late then [ late_actions ] else [])
      (Node.box
         ~orientation:Vertical
         ~attrs:[ base_actions ]
         [ Node.menu_button
             ~label:"m"
             ?menu:
               (match menu_state with
                | `Absent -> None
                | `Base -> Some (menu ~with_late:false)
                | `Both -> Some (menu ~with_late:true))
             ()
         ])
  in
  let patch live v =
    Scheduler.with_patch_guard scheduler (fun () ->
      let live = P.patch ctx ~path:"rebind" ~is_root:true live v in
      P.run_fixups ctx;
      live)
  in
  let live =
    Scheduler.with_patch_guard scheduler (fun () ->
      let live =
        P.mount ctx ~path:"rebind" ~is_root:true (view ~late:false ~menu_state:`Base)
      in
      P.run_fixups ctx;
      live)
  in
  let button (l : P.live) =
    match l.children with
    | Single (Some box) ->
      (match box.P.children with
       | List [ mb ] -> mb.P.widget
       | _ -> assert false)
    | _ -> assert false
  in
  let type_name = Bonsai_gtk.Private.Gtk_import.type_name in
  let widget_children = Bonsai_gtk.Private.Gtk_import.widget_children in
  let rec find_labelled_model_buttons w acc =
    let acc =
      if String.equal (type_name w) "GtkModelButton"
      then (
        let rec first_label w =
          if String.equal (type_name w) "GtkLabel"
          then Some (W.Label.get_text (cast w))
          else List.find_map (widget_children w) ~f:first_label
        in
        (Option.value (first_label w) ~default:"?", w) :: acc)
      else acc
    in
    List.fold (widget_children w) ~init:acc ~f:(fun acc c ->
      find_labelled_model_buttons c acc)
  in
  let probe label (l : P.live) =
    let mb : W.Menu_button.t = cast (button l) in
    W.Menu_button.popup mb;
    pump ();
    (match W.Menu_button.get_popover mb with
     | None -> printf "%s: no internal popover\n" label
     | Some p ->
       find_labelled_model_buttons ((p :> Widget.t) : Widget.t) []
       |> List.sort ~compare:(fun (a, _) (b, _) -> String.compare a b)
       |> List.iter ~f:(fun (text, w) ->
         printf "%s: item %s sensitive=%b\n" label text (W.Widget.get_sensitive w)));
    W.Menu_button.popdown mb;
    pump ()
  in
  probe "mounted (base only)" live;
  (* The late group arrives on the rooted window, and the menu is EDITED in place. *)
  let live = patch live (view ~late:true ~menu_state:`Both) in
  probe "late group + in-place menu edit" live;
  (* The full re-set: menu absent for one frame, then back -- a fresh set_menu_model. *)
  let live = patch live (view ~late:true ~menu_state:`Absent) in
  let live = patch live (view ~late:true ~menu_state:`Both) in
  probe "late group + full model re-set" live;
  P.destroy ctx live;
  printf "rebind measurement done\n"
;;

(* The final review's same-node variant of the block above: a mounted, rooted menu button
   (no menu, no actions -- a dynamic UI's placeholder) gains [~menu] and its {i own}
   [Attr.actions] in one frame. Within one node [patch] runs [impl.update] (the model
   build) {i before} [Actions.update] (the group insert) -- the inverse of the top-down
   order the ancestor case above enjoys -- so if the item tracker bound at row-build time
   this would be the frame that stays grey after the walk certified it. Measured: it binds
   ([sensitive=true]), so the tracker's binding is late enough that within-frame write
   order is invisible, and the attr's documented re-bind workaround holds for the
   same-node, same-frame shape too. *)
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
      ~on_window_created:(fun w -> W.Window.present (cast w))
      ()
  in
  let pump () =
    let rec go n =
      if n > 0 && Bonsai_gtk.Private.Gtk_import.Glib.Main.iteration false then go (n - 1)
    in
    go 50
  in
  let view ~armed =
    Node.window
      ~title:"same-node"
      (Node.box
         ~orientation:Vertical
         [ Node.menu_button
             ~label:"m"
             ~attrs:
               (if armed
                then
                  [ Attr.actions
                      ~scope:"own"
                      [ Action_spec.simple ~name:"x" Ui_effect.Ignore ]
                  ]
                else [])
             ?menu:
               (if armed then Some [ Menu.item ~label:"X" ~action:"own.x" () ] else None)
             ()
         ])
  in
  let live =
    Scheduler.with_patch_guard scheduler (fun () ->
      let live = P.mount ctx ~path:"same-node" ~is_root:true (view ~armed:false) in
      P.run_fixups ctx;
      live)
  in
  let button (l : P.live) =
    match l.children with
    | Single (Some box) ->
      (match box.P.children with
       | List [ mb ] -> mb.P.widget
       | _ -> assert false)
    | _ -> assert false
  in
  let type_name = Bonsai_gtk.Private.Gtk_import.type_name in
  let widget_children = Bonsai_gtk.Private.Gtk_import.widget_children in
  let rec find_labelled_model_buttons w acc =
    let acc =
      if String.equal (type_name w) "GtkModelButton"
      then (
        let rec first_label w =
          if String.equal (type_name w) "GtkLabel"
          then Some (W.Label.get_text (cast w))
          else List.find_map (widget_children w) ~f:first_label
        in
        (Option.value (first_label w) ~default:"?", w) :: acc)
      else acc
    in
    List.fold (widget_children w) ~init:acc ~f:(fun acc c ->
      find_labelled_model_buttons c acc)
  in
  let live =
    Scheduler.with_patch_guard scheduler (fun () ->
      let live = P.patch ctx ~path:"same-node" ~is_root:true live (view ~armed:true) in
      P.run_fixups ctx;
      live)
  in
  let mb : W.Menu_button.t = cast (button live) in
  W.Menu_button.popup mb;
  pump ();
  (match W.Menu_button.get_popover mb with
   | None -> printf "same-node menu+actions in one frame: no internal popover\n"
   | Some p ->
     find_labelled_model_buttons ((p :> Widget.t) : Widget.t) []
     |> List.iter ~f:(fun (text, w) ->
       printf
         "same-node menu+actions in one frame: item %s sensitive=%b\n"
         text
         (W.Widget.get_sensitive w)));
  W.Menu_button.popdown mb;
  pump ();
  printf
    "same-node own.x activates: %b\n"
    (Widget.activate_action_variant (button live) "own.x" None);
  P.destroy ctx live;
  printf "same-node measurement done\n"
;;

(* Task-6 review M5, the measurement: same-scope shadowing. A descendant inserts
   [~scope:"app" [y]] while an ancestor holds [~scope:"app" [x]]; does GTK's muxer fall
   through to the ancestor's "app" for a name the nearer group lacks? The probes go
   through [activate_action_variant] from the innermost widget -- GTK's own walk -- and
   the golden decides whether the resolution walk's union env is honest or needs the
   nearest-scope-shadows rule. No menu is involved, so the walk itself is not in the way. *)
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
      ~on_window_created:(fun w -> W.Window.present (cast w))
      ()
  in
  let view =
    Node.window
      ~title:"shadow"
      (Node.box
         ~orientation:Vertical
         ~attrs:
           [ Attr.actions ~scope:"app" [ Action_spec.simple ~name:"x" Ui_effect.Ignore ] ]
         [ Node.box
             ~orientation:Vertical
             ~attrs:
               [ Attr.actions
                   ~scope:"app"
                   [ Action_spec.simple ~name:"y" Ui_effect.Ignore ]
               ]
             [ Node.label "leaf" ]
         ])
  in
  let live =
    Scheduler.with_patch_guard scheduler (fun () ->
      let live = P.mount ctx ~path:"shadow" ~is_root:true view in
      P.run_fixups ctx;
      live)
  in
  let leaf =
    match live.children with
    | Single (Some outer) ->
      (match outer.P.children with
       | List [ inner ] ->
         (match inner.P.children with
          | List [ l ] -> l.P.widget
          | _ -> assert false)
       | _ -> assert false)
    | _ -> assert false
  in
  printf
    "from the leaf, app.y (the nearer group's own): %b\n"
    (Widget.activate_action_variant leaf "app.y" None);
  printf
    "from the leaf, app.x (only in the ancestor's app): %b\n"
    (Widget.activate_action_variant leaf "app.x" None);
  P.destroy ctx live;
  printf "shadowing measurement done\n"
;;
