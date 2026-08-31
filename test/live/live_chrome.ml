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
