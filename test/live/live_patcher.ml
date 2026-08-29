open! Core
open Bonsai_gtk_vtree
module Gobject = Bonsai_gtk.Private.Gtk_import.Gobject
module Widget = Bonsai_gtk.Private.Gtk_import.Widget
module Debug = Bonsai_gtk.Private.Debug
module Native_gtk = Bonsai_gtk.Private.Native_gtk
module P = Bonsai_gtk.Private.Patcher
module W = Bonsai_gtk.Private.Gtk_import.W

let cast = Bonsai_gtk.Private.Gtk_import.cast

(* Exercises the native escape hatch, whose [input] projection is the one unsafe cast in
   the library: [create]/[update]/[destroy] must all reach this module. *)
module Native_counter = struct
  type input = int

  let name = "counter"
  let create n = (W.Label.new_ (Some (Int.to_string n)) :> Widget.t)
  let update w ~old n = if old <> n then W.Label.set_text (cast w) (Int.to_string n)
  let destroy _ = print_endline "native destroyed"
end

let counter n = Native_gtk.node (module Native_counter) n

(* The [a]-keyed button, which the second render moves and relabels. Reaching for it by
   position is how we show it is the *same* GTK widget across the patch. *)
let nth_box_child (live : P.live) i : Widget.t =
  match live.children with
  | Single (Some box) ->
    (match box.children with
     | List children -> (List.nth_exn children i).widget
     | No_children | Single _ -> assert false)
  | No_children | Single None | List _ -> assert false
;;

let () =
  ignore (Ocgtk_gtk.GMain.init () : string array);
  let scheduled = ref [] in
  let ctx : P.ctx =
    { signals =
        { schedule = (fun e -> scheduled := e :: !scheduled)
        ; in_patch = (fun () -> false)
        ; on_exn =
            (fun ~node_path exn -> printf "EXN at %s: %s\n" node_path (Exn.to_string exn))
        }
    ; on_window_created = (fun _ -> print_endline "window created")
    }
  in
  let view label items =
    Node.window
      ~title:"T"
      (Node.box
         ~orientation:Vertical
         ~spacing:4
         (Node.label ~attrs:[ Attr.css_class "title" ] label
          :: List.map items ~f:(fun (key, text) ->
            Node.button
              ~key
              ~attrs:[ Attr.on_clicked (Ui_effect.print_s [%sexp (key : string)]) ]
              ~label:text
              ())))
  in
  let live = P.mount ctx ~path:"root" (view "v1" [ "a", "A"; "b", "B" ]) in
  print_s (Debug.dump_live_tree live.widget);
  (* v1 order is [label; a; b]. *)
  let a_before = nth_box_child live 1 in
  let live =
    P.patch ctx ~path:"root" live (view "v2" [ "b", "B"; "c", "C"; "a", "A!" ])
  in
  print_s (Debug.dump_live_tree live.widget);
  (* v2 order is [label; b; c; a]: [a] was moved and relabelled, not recreated. *)
  let a_after = nth_box_child live 3 in
  printf "same widget for a: %b\n" (Gobject.same a_before a_after);
  (* A fired signal must reach the handler currently in the slot. *)
  Gobject.Signal.emit_by_name (nth_box_child live 1) ~name:"clicked";
  printf "scheduled effects: %d\n" (List.length !scheduled);
  (* Key [b] changes kind while keeping its key, so [Reconcile] emits an [Update] whose
     item is a different kind: the patcher has to remount it and re-parent the fresh
     widget at the *same* index rather than at the end of the box. *)
  let live =
    P.patch
      ctx
      ~path:"root"
      live
      (Node.window
         ~title:"T"
         (Node.box
            ~orientation:Vertical
            ~spacing:4
            [ Node.label ~attrs:[ Attr.css_class "title" ] "v3"
            ; Node.label ~key:"b" "b is a label now"
            ; Node.button ~key:"c" ~label:"C" ()
            ; Node.button ~key:"a" ~label:"A!" ()
            ]))
  in
  print_s (Debug.dump_live_tree live.widget);
  (* Swapping the whole child list out for a native node: every keyed button is removed,
     and the native widget is created through [Registry]'s [Native] arm. *)
  let native_view n =
    Node.window ~title:"T" (Node.box ~orientation:Vertical [ counter n ])
  in
  let live = P.patch ctx ~path:"root" live (native_view 1) in
  print_s (Debug.dump_live_tree live.widget);
  (* Same module, new input: [update] runs rather than the widget being recreated. *)
  let native_before = nth_box_child live 0 in
  let live = P.patch ctx ~path:"root" live (native_view 2) in
  print_s (Debug.dump_live_tree live.widget);
  printf
    "same widget for native: %b\n"
    (Gobject.same native_before (nth_box_child live 0));
  (* Dropping the box takes the native node with it, so its [destroy] must run. *)
  let live =
    P.patch ctx ~path:"root" live (Node.window ~title:"T" (Node.label "replaced"))
  in
  print_s (Debug.dump_live_tree live.widget);
  P.destroy ctx live;
  print_endline "destroyed"
;;
