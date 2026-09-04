open! Core
open Bonsai_gtk_vtree
module Live_tree = Bonsai_gtk.Private.Live_tree
module P = Bonsai_gtk.Private.Patcher
module Scheduler = Bonsai_gtk.Private.Scheduler

(* The M3 chrome bars against real GTK: the slot shapes ([title]/[center] Singles beside
   two keyed pack lists), the per-slot insert and remove, and the props reaching the
   widget. Order within a pack area is insertion order -- GTK has no reorder primitive
   there, which is why the slot lists carry [move = None] and the constructor doc says
   keys preserve identity rather than position. The dumps are the assertion: which slot
   every child ended up in is visible in the tree GTK actually holds. *)

let () = ignore (Ocgtk_gtk.GMain.init () : string array)

let () =
  let scheduler = Scheduler.create ~run_frame:(fun () -> ()) in
  let ctx =
    P.create_ctx
      ~signals:
        { schedule = (fun _ -> ())
        ; in_patch = (fun () -> Scheduler.in_patch scheduler)
        ; on_exn =
            (fun ~node_path exn -> printf "EXN at %s: %s\n" node_path (Exn.to_string exn))
        }
      ~on_window_created:(fun _ -> ())
      ()
  in
  let view ~with_title ~header_start ~header_end ~bar_start ~bar_end ~revealed =
    Node.window
      ~title:"chrome"
      (Node.box
         ~orientation:Vertical
         [ Node.header_bar
             ?title:(if with_title then Some (Node.label "the title") else None)
             ~show_title_buttons:false
             ~decoration_layout:":close"
             ~start:(List.map header_start ~f:(fun k -> Node.button ~key:k ~label:k ()))
             ~end_:(List.map header_end ~f:(fun k -> Node.button ~key:k ~label:k ()))
             ()
         ; Node.action_bar
             ~revealed
             ~center:(Node.label "status")
             ~start:(List.map bar_start ~f:(fun k -> Node.button ~key:k ~label:k ()))
             ~end_:(List.map bar_end ~f:(fun k -> Node.button ~key:k ~label:k ()))
             ()
         ])
  in
  let live =
    P.mount
      ctx
      ~path:"chrome"
      ~is_root:true
      (view
         ~with_title:true
         ~header_start:[ "back" ]
         ~header_end:[ "menu" ]
         ~bar_start:[ "add" ]
         ~bar_end:[ "del" ]
         ~revealed:true)
  in
  P.run_fixups ctx;
  print_s (Live_tree.dump live.widget);
  (* One insertion and one removal per pack area, the title slot emptied, and the action
     bar concealed -- every slot patched in one frame, each through its own ops. The dump
     shows [back] and [del] still present, which pins that the reconciler patched rather
     than rebuilt the areas -- but a dump prints labels, not identity; that a keyed
     [Update] reuses the widget is [test/test_reconcile.ml]'s claim, and the lifecycle
     sweep's [1U] rows are where these two kinds exercise it. *)
  let live =
    Scheduler.with_patch_guard scheduler (fun () ->
      P.patch
        ctx
        ~path:"chrome"
        ~is_root:true
        live
        (view
           ~with_title:false
           ~header_start:[ "back"; "forward" ]
           ~header_end:[]
           ~bar_start:[]
           ~bar_end:[ "del"; "archive" ]
           ~revealed:false))
  in
  P.run_fixups ctx;
  print_s (Live_tree.dump live.widget);
  P.destroy ctx live;
  printf "chrome done\n"
;;

(* The popover's controlled [~open_], model-driven both ways, and the declined-dismissal
   reopen (M3 Task 5 step 4). The window is presented -- popping up a popover wants a
   realized parent -- and the popover's [open] flag in the dump is [Widget.get_visible],
   the very bit [apply_open] compares against. The last act is the controlled rule's whole
   point: the model pins [~open_:true], a programmatic [popdown] (a user dismissal in
   every respect the runtime can see -- outside the patch guard, so [on_closed] fires)
   closes it, and the next idle frame's fixup puts it back. *)
let () =
  ignore (Sys.opaque_identity 0 : int);
  let module W = Bonsai_gtk.Private.Gtk_import.W in
  let cast = Bonsai_gtk.Private.Gtk_import.cast in
  let scheduler = Scheduler.create ~run_frame:(fun () -> ()) in
  let closes = ref 0 in
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
  let view ~open_ =
    Node.window
      ~title:"popover"
      (Node.menu_button
         ~label:"menu"
         ~popover:
           (Node.popover
              ~open_
              ~attrs:[ Attr.on_closed (Ui_effect.of_sync_fun (fun () -> incr closes) ()) ]
              (Node.label "menu body"))
         ())
  in
  let popover_of (live : P.live) =
    match live.children with
    | Single (Some mb) ->
      (match mb.P.children with
       | Slots [ ("popover", Single (Some pop)) ] -> pop.P.widget
       | _ -> assert false)
    | _ -> assert false
  in
  (* [run_fixups] inside the guard, exactly as [Driver.frame] runs it -- the fixup's
     [popdown] is what emits the synchronous [closed] the guard must cover, so a helper
     that ran the fixups outside would hand the model its own close. (It did, in this
     block's first draft: [closes] read 1 after "model closed it".) *)
  let patch live v =
    Scheduler.with_patch_guard scheduler (fun () ->
      let live = P.patch ctx ~path:"pop" ~is_root:true live v in
      P.run_fixups ctx;
      live)
  in
  let idle live =
    Scheduler.with_patch_guard scheduler (fun () ->
      P.reassert_only ctx ~path:"pop" live;
      P.run_fixups ctx)
  in
  let open_bit live =
    Bonsai_gtk.Private.Gtk_import.Widget.get_visible (popover_of live)
  in
  let live =
    Scheduler.with_patch_guard scheduler (fun () ->
      let live = P.mount ctx ~path:"pop" ~is_root:true (view ~open_:false) in
      P.run_fixups ctx;
      live)
  in
  printf "popover mounted closed: open=%b closes=%d\n" (open_bit live) !closes;
  (* The model opens it... *)
  let live = patch live (view ~open_:true) in
  printf "model opened it: open=%b closes=%d\n" (open_bit live) !closes;
  (* ...and closes it -- the closed this popdown emits is synchronous inside the guarded
     fixup (pre-flight 8), so the handler hears nothing. *)
  let live = patch live (view ~open_:false) in
  printf "model closed it: open=%b closes=%d\n" (open_bit live) !closes;
  (* The declined dismissal: the model pins [true]; a dismissal from outside the guard
     fires [on_closed]; the next idle frame's fixup re-opens. *)
  let live = patch live (view ~open_:true) in
  W.Popover.popdown (cast (popover_of live));
  printf "user dismissed it: open=%b closes=%d\n" (open_bit live) !closes;
  idle live;
  printf "the model declined: open=%b closes=%d\n" (open_bit live) !closes;
  P.destroy ctx live;
  printf "popover done\n"
;;

(* Fix-wave chrome M1: [Attr.autofocus] inside the popover slot, both renderings. The grab
   runs from the fixup queue against a popover subtree that is mounted even while the
   popover is closed ([mount_slots] walks every slot), so the question is what the one
   fire-once grab does there. Measured: it {i lands} -- [Window.get_focus] points at the
   entry even while the popover is hidden, and still does once the model opens it -- so
   nothing is lost, but until the popover opens the window's focus sits on an unmapped
   widget. The [open_]-conditional rendering (the attr flipping with the popover) lands
   the grab in the frame that pops up -- popup runs first in the generic queue, the grab
   after it -- and the popover survives the grab. Both steady states are the open popover
   with focus in its entry. *)
let () =
  let module W = Bonsai_gtk.Private.Gtk_import.W in
  let module Widget = Bonsai_gtk.Private.Gtk_import.Widget in
  let cast = Bonsai_gtk.Private.Gtk_import.cast in
  let type_name = Bonsai_gtk.Private.Gtk_import.type_name in
  let widget_children = Bonsai_gtk.Private.Gtk_import.widget_children in
  let rec find_type name w =
    if String.equal (type_name w) name
    then Some w
    else List.find_map (widget_children w) ~f:(find_type name)
  in
  let run label ~autofocus_of =
    let scheduler = Scheduler.create ~run_frame:(fun () -> ()) in
    let ctx =
      P.create_ctx
        ~signals:
          { schedule = (fun _ -> ())
          ; in_patch = (fun () -> Scheduler.in_patch scheduler)
          ; on_exn =
              (fun ~node_path exn ->
                printf "EXN at %s: %s\n" node_path (Exn.to_string exn))
          }
        ~on_window_created:(fun w -> W.Window.present (cast w))
        ()
    in
    let pump () =
      let rec go n =
        if n > 0 && Bonsai_gtk.Private.Gtk_import.Glib.Main.iteration false then go (n - 1)
      in
      go 200
    in
    let view ~open_ =
      Node.window
        ~title:label
        (Node.box
           ~orientation:Vertical
           [ Node.menu_button
               ~label:"m"
               ~popover:
                 (Node.popover
                    ~open_
                    (Node.entry
                       ~attrs:[ Attr.autofocus (autofocus_of ~open_) ]
                       ~text:""
                       ()))
               ()
           ])
    in
    let live =
      Scheduler.with_patch_guard scheduler (fun () ->
        let live = P.mount ctx ~path:label ~is_root:true (view ~open_:false) in
        P.run_fixups ctx;
        live)
    in
    pump ();
    let report tag =
      let popover = Option.value_exn (find_type "GtkPopover" live.P.widget) in
      let entry = Option.value_exn (find_type "GtkEntry" live.P.widget) in
      let focus_in_entry =
        match W.Window.get_focus (cast live.P.widget) with
        | Some f ->
          Bonsai_gtk.Private.Gtk_import.Gobject.same f entry || Widget.is_ancestor f entry
        | None -> false
      in
      printf
        "popover autofocus (%s) %s: popover visible=%b, focus in popover entry=%b\n"
        label
        tag
        (Widget.get_visible popover)
        focus_in_entry
    in
    report "mounted closed";
    let live2 =
      Scheduler.with_patch_guard scheduler (fun () ->
        let l = P.patch ctx ~path:label ~is_root:true live (view ~open_:true) in
        P.run_fixups ctx;
        l)
    in
    pump ();
    report "model-opened";
    P.destroy ctx live2
  in
  run "unconditional" ~autofocus_of:(fun ~open_:_ -> true);
  run "open-conditional" ~autofocus_of:(fun ~open_ -> open_);
  printf "popover autofocus done\n"
;;

(* Fix-wave chrome M2: the popover-slot <-> [~menu] swap in one frame, both directions,
   with the popover OPEN -- the one path that bypasses the disarm-before-unparent order
   ([impl.update]'s [set_menu_model] makes GTK unparent the still-armed slot popover
   before [patch_single]'s disarm runs). Pinned: both directions converge -- the slot
   popover is gone and the model set after popover->menu, and a fresh slot popover is
   parented and popped up after menu->popover -- with no spurious [on_closed] (the
   unparent's synchronous [closed] lands inside the patch guard and is dropped).

   One stray stderr line to know about, deliberately NOT part of this golden: the
   menu->popover frame emits a single GTK critical (gtk_widget_is_ancestor on a
   non-widget). Probed during the fix wave: it appears identically when the middle frame
   is a BARE button (no menu at all), so it belongs to "destroy an open slot popover, then
   pop up a new one in the same window" -- GTK-internal stale-focus bookkeeping, not the
   swap path; recorded in docs/m3-backlog.md. *)
let () =
  let module W = Bonsai_gtk.Private.Gtk_import.W in
  let module Widget = Bonsai_gtk.Private.Gtk_import.Widget in
  let cast = Bonsai_gtk.Private.Gtk_import.cast in
  let type_name = Bonsai_gtk.Private.Gtk_import.type_name in
  let widget_children = Bonsai_gtk.Private.Gtk_import.widget_children in
  let rec find_type name w =
    if String.equal (type_name w) name
    then Some w
    else List.find_map (widget_children w) ~f:(find_type name)
  in
  let scheduler = Scheduler.create ~run_frame:(fun () -> ()) in
  let closes = ref 0 in
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
    go 200
  in
  let popover_node =
    Node.popover
      ~open_:true
      ~attrs:[ Attr.on_closed (Ui_effect.of_sync_fun (fun () -> incr closes) ()) ]
      (Node.label "slot body")
  in
  let view = function
    | `Popover ->
      Node.window
        ~title:"swap"
        (Node.box
           ~orientation:Vertical
           [ Node.menu_button ~label:"m" ~popover:popover_node () ])
    | `Menu ->
      Node.window
        ~title:"swap"
        (Node.box
           ~orientation:Vertical
           [ Node.menu_button
               ~label:"m"
               ~attrs:
                 [ Attr.actions
                     ~scope:"s"
                     [ Action_spec.simple ~name:"x" Ui_effect.Ignore ]
                 ]
               ~menu:[ Menu.item ~label:"X" ~action:"s.x" () ]
               ()
           ])
  in
  let live =
    Scheduler.with_patch_guard scheduler (fun () ->
      let live = P.mount ctx ~path:"swap" ~is_root:true (view `Popover) in
      P.run_fixups ctx;
      live)
  in
  pump ();
  let button () =
    match live.P.children with
    | Single (Some box) ->
      (match box.P.children with
       | List [ mb ] -> mb.P.widget
       | _ -> assert false)
    | _ -> assert false
  in
  let mb () : W.Menu_button.t = cast (button ()) in
  let report tag =
    printf
      "swap %s: slot popover=%s, model set=%b, closes=%d\n"
      tag
      (match find_type "GtkPopover" (button ()) with
       | Some p -> sprintf "visible=%b" (Widget.get_visible p)
       | None -> "none")
      (Option.is_some (W.Menu_button.get_menu_model (mb ())))
      !closes
  in
  report "mounted with open slot popover";
  let patch v =
    Scheduler.with_patch_guard scheduler (fun () ->
      let l = P.patch ctx ~path:"swap" ~is_root:true live v in
      P.run_fixups ctx;
      ignore (l : P.live))
  in
  patch (view `Menu);
  pump ();
  report "open popover -> menu in one frame";
  patch (view `Popover);
  pump ();
  report "menu -> open popover in one frame";
  P.destroy ctx live;
  printf "swap done\n"
;;
