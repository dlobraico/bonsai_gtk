open! Core
open Bonsai_gtk_vtree
module Gobject = Bonsai_gtk.Private.Gtk_import.Gobject
module Live_tree = Bonsai_gtk.Private.Live_tree
module P = Bonsai_gtk.Private.Patcher
module Scheduler = Bonsai_gtk.Private.Scheduler

let nth_child (live : P.live) i : P.live =
  match live.children with
  | Single (Some box) ->
    (match box.children with
     | List children -> List.nth_exn children i
     | No_children | Single _ -> assert false)
  | No_children | Single None | List _ -> assert false
;;

let () =
  ignore (Ocgtk_gtk.GMain.init () : string array);
  let scheduled = ref 0 in
  let scheduler = Scheduler.create ~run_frame:(fun () -> ()) in
  let ctx : P.ctx =
    { signals =
        { schedule = (fun _ -> incr scheduled)
        ; in_patch = (fun () -> Scheduler.in_patch scheduler)
        ; on_exn =
            (fun ~node_path exn -> printf "EXN at %s: %s\n" node_path (Exn.to_string exn))
        }
    ; on_window_created = (fun _ -> ())
    }
  in
  let view ~active =
    Node.window
      ~title:"controls"
      (Node.box
         ~orientation:Vertical
         [ Node.button ~label:"plain" ()
         ; Node.button ~icon_name:"list-add-symbolic" ~has_frame:false ()
         ; Node.button ~child:(Node.label "boxed") ()
         ; Node.toggle_button
             ~attrs:[ Attr.on_toggled (fun _ -> Ui_effect.Ignore) ]
             ~label:"bold"
             ~active
             ()
         ; Node.check_button
             ~attrs:[ Attr.on_toggled (fun _ -> Ui_effect.Ignore) ]
             ~label:"agree"
             ~active
             ()
         ; Node.switch ~attrs:[ Attr.on_toggled (fun _ -> Ui_effect.Ignore) ] ~active ()
         ])
  in
  let live = P.mount ctx ~path:"root" ~is_root:true (view ~active:false) in
  print_s (Live_tree.dump live.widget);
  (* THE reentrancy case the M0 backlog asks for: flipping [active] from the model makes
     GTK emit [toggled] / [notify::active] synchronously, inside the patch. Nothing may
     reach Bonsai from there -- the model is the single source of truth (spec §4.4). *)
  let before = !scheduled in
  let live =
    Scheduler.with_patch_guard scheduler (fun () ->
      P.patch ctx ~path:"root" ~is_root:true live (view ~active:true))
  in
  printf "scheduled during patch: %d\n" (!scheduled - before);
  print_s (Live_tree.dump live.widget);
  (* Outside the patch the same signals do reach Bonsai. *)
  Gobject.Signal.emit_by_name (nth_child live 3).widget ~name:"toggled";
  Gobject.Signal.emit_by_name (nth_child live 4).widget ~name:"toggled";
  Gobject.Property.notify (nth_child live 5).widget ~name:"active";
  printf "scheduled outside patch: %d\n" (!scheduled - before);
  (* An event attr the widget cannot emit is a typo, and a loud one. *)
  (match
     P.mount
       ctx
       ~path:"root"
       ~is_root:true
       (Node.window
          ~title:"bad"
          (Node.label ~attrs:[ Attr.on_toggled (fun _ -> Ui_effect.Ignore) ] "x"))
   with
   | (_ : P.live) -> print_endline "BUG: on_toggled on a label accepted"
   | exception Invalid_argument msg -> printf "rejected: %s\n" msg);
  P.destroy ctx live;
  (* [label], [icon_name] and [child] all compete for a [GtkButton]'s one slot, and the
     patcher applies props before children -- so swapping a custom child for a label has
     to leave the label showing rather than an empty button, and swapping back has to put
     the child in. *)
  let slot_view b = Node.window ~title:"slot" (Node.box ~orientation:Vertical [ b ]) in
  let live =
    P.mount
      ctx
      ~path:"root"
      ~is_root:true
      (slot_view (Node.button ~child:(Node.label "custom") ()))
  in
  print_s (Live_tree.dump live.widget);
  let live =
    P.patch ctx ~path:"root" ~is_root:true live (slot_view (Node.button ~label:"text" ()))
  in
  print_s (Live_tree.dump live.widget);
  let live =
    P.patch
      ctx
      ~path:"root"
      ~is_root:true
      live
      (slot_view (Node.button ~child:(Node.label "custom again") ()))
  in
  print_s (Live_tree.dump live.widget);
  P.destroy ctx live
;;
