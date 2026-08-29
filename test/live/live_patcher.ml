open! Core
open Bonsai_gtk_vtree
module Gobject = Bonsai_gtk.Private.Gtk_import.Gobject
module Widget = Bonsai_gtk.Private.Gtk_import.Widget
module Live_tree = Bonsai_gtk.Private.Live_tree
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

(* Built once at the top level, as every native widget must be: the impl carries the type
   witness the patcher matches on, so a fresh one per render would be a different widget. *)
let counter_impl = Native_gtk.impl (module Native_counter)
let counter n = Native_gtk.node counter_impl n

(* The [a]-keyed button, which the second render moves and relabels. Reaching for it by
   position is how we show it is the *same* GTK widget across the patch. *)
let nth_box_child (live : P.live) i : Widget.t =
  match live.children with
  | Single (Some box) ->
    (match box.children with
     | List children -> (List.nth_exn children i).widget
     | No_children | Single _ | Slots _ -> assert false)
  | No_children | Single None | List _ | Slots _ -> assert false
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
  let live = P.mount ctx ~path:"root" ~is_root:true (view "v1" [ "a", "A"; "b", "B" ]) in
  print_s (Live_tree.dump live.widget);
  (* v1 order is [label; a; b]. *)
  let a_before = nth_box_child live 1 in
  let live =
    P.patch
      ctx
      ~path:"root"
      ~is_root:true
      live
      (view "v2" [ "b", "B"; "c", "C"; "a", "A!" ])
  in
  print_s (Live_tree.dump live.widget);
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
      ~is_root:true
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
  print_s (Live_tree.dump live.widget);
  (* Swapping the whole child list out for a native node: every keyed button is removed,
     and the native widget is created through [Registry]'s [Native] arm. *)
  let native_view n =
    Node.window ~title:"T" (Node.box ~orientation:Vertical [ counter n ])
  in
  let live = P.patch ctx ~path:"root" ~is_root:true live (native_view 1) in
  print_s (Live_tree.dump live.widget);
  (* Same impl, new input: [update] runs rather than the widget being recreated. *)
  let native_before = nth_box_child live 0 in
  let live = P.patch ctx ~path:"root" ~is_root:true live (native_view 2) in
  print_s (Live_tree.dump live.widget);
  printf
    "same widget for native: %b\n"
    (Gobject.same native_before (nth_box_child live 0));
  (* Dropping the box takes the native node with it, so its [destroy] must run. *)
  let live =
    P.patch
      ctx
      ~path:"root"
      ~is_root:true
      live
      (Node.window ~title:"T" (Node.label "replaced"))
  in
  print_s (Live_tree.dump live.widget);
  P.destroy ctx live;
  print_endline "destroyed";
  (* Every ordinary attribute, set and then dropped. [Attr_apply.unset] is the half with
     the non-obvious choices in it — it restores the value the widget was created with,
     snapshotted before any attr touched it — and the second dump is what proves each of
     those actually lands. *)
  let attr_view attrs = Node.window ~title:"attrs" (Node.label ~attrs "styled") in
  let live =
    P.mount
      ctx
      ~path:"root"
      ~is_root:true
      (attr_view
         [ Attr.margin_start 1
         ; Attr.margin_end 2
         ; Attr.margin_top 3
         ; Attr.margin_bottom 4
         ; Attr.halign Start
         ; Attr.valign Center
         ; Attr.hexpand true
         ; Attr.vexpand true
         ; Attr.tooltip "hi"
         ; Attr.sensitive false
         ; Attr.visible false
         ; Attr.width_request 20
         ; Attr.height_request 30
         ; Attr.opacity 0.5
         ; Attr.focusable true
         ; Attr.can_focus false
         ; Attr.widget_name "styled-label"
         ; Attr.cursor_name "pointer"
         ])
  in
  print_s (Live_tree.dump live.widget);
  let live = P.patch ctx ~path:"root" ~is_root:true live (attr_view []) in
  print_s (Live_tree.dump live.widget);
  (* [focusable]/[can_focus] have no place in the dump (their defaults are per widget
     class), so they are checked by reading them back and comparing against a label that
     never had them set. *)
  let styled =
    (Option.value_exn
       (match live.children with
        | Single c -> c
        | No_children | List _ | Slots _ -> None))
      .P.widget
  in
  let pristine = (W.Label.new_ (Some "l") :> Widget.t) in
  printf
    "focus restored: %b %b\n"
    (Bool.equal (Widget.get_focusable styled) (Widget.get_focusable pristine))
    (Bool.equal (Widget.get_can_focus styled) (Widget.get_can_focus pristine));
  P.destroy ctx live;
  (* A [GtkWindow] is created hidden; a [GtkLabel] is created visible. "Unset" means "put
     back what this widget had", not a constant, so the same op restores different values
     here. *)
  let live =
    P.mount
      ctx
      ~path:"root"
      ~is_root:true
      (Node.window
         ~attrs:[ Attr.visible true ]
         ~title:"vis"
         (Node.label ~attrs:[ Attr.visible false ] "l"))
  in
  print_s (Live_tree.dump live.widget);
  let live =
    P.patch
      ctx
      ~path:"root"
      ~is_root:true
      live
      (Node.window ~title:"vis" (Node.label "l"))
  in
  print_s (Live_tree.dump live.widget);
  P.destroy ctx live;
  (* Every [Node.label] text property, set and then dropped back to GTK's defaults. *)
  let label_view label = Node.window ~title:"label" (label "text") in
  let live =
    P.mount
      ctx
      ~path:"root"
      ~is_root:true
      (label_view
         (Node.label
            ~wrap:true
            ~xalign:0.
            ~ellipsize:Middle
            ~max_width_chars:14
            ~width_chars:6
            ~selectable:true))
  in
  print_s (Live_tree.dump live.widget);
  let live =
    P.patch
      ctx
      ~path:"root"
      ~is_root:true
      live
      (Node.window ~title:"label" (Node.label ~use_markup:true "<b>bold</b>"))
  in
  print_s (Live_tree.dump live.widget);
  let live =
    P.patch ctx ~path:"root" ~is_root:true live (label_view (fun t -> Node.label t))
  in
  print_s (Live_tree.dump live.widget);
  P.destroy ctx live;
  (* Spec §11: a window below the root is structural misuse, not something to render. *)
  match
    P.mount
      ctx
      ~path:"root"
      ~is_root:true
      (Node.window
         ~title:"outer"
         (Node.box ~orientation:Vertical [ Node.window ~title:"inner" (Node.label "x") ]))
  with
  | (_ : P.live) -> print_endline "BUG: nested window accepted"
  | exception Invalid_argument msg -> printf "nested window rejected: %s\n" msg
;;
