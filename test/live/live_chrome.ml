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
     bar concealed -- every slot patched in one frame, each through its own ops. The
     header's [back] and the bar's [del] keep their widgets across the edit (keys preserve
     identity), which the dump shows as the surviving buttons. *)
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
