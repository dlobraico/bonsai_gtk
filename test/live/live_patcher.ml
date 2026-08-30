open! Core
open Bonsai_gtk_vtree
module Gobject = Bonsai_gtk.Private.Gtk_import.Gobject
module Widget = Bonsai_gtk.Private.Gtk_import.Widget
module Live_tree = Bonsai_gtk.Private.Live_tree
module Native_gtk = Bonsai_gtk.Private.Native_gtk
module P = Bonsai_gtk.Private.Patcher
module W = Bonsai_gtk.Private.Gtk_import.W

let cast = Bonsai_gtk.Private.Gtk_import.cast
let widget_children = Bonsai_gtk.Private.Gtk_import.widget_children

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

(* A native widget whose [destroy] raises, which is the one way application code can raise
   from inside a teardown. Used at the bottom of this file. *)
module Native_boom = struct
  type input = unit

  let name = "boom"
  let create () = (W.Label.new_ (Some "boom") :> Widget.t)
  let update _ ~old:() () = ()
  let destroy _ = failwith "this native destroy raises"
end

let boom_impl = Native_gtk.impl (module Native_boom)
let boom () = Native_gtk.node boom_impl ()

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
  let ctx =
    P.create_ctx
      ~signals:
        { schedule = (fun e -> scheduled := e :: !scheduled)
        ; in_patch = (fun () -> false)
        ; on_exn =
            (fun ~node_path exn -> printf "EXN at %s: %s\n" node_path (Exn.to_string exn))
        }
      ~on_window_created:(fun _ -> print_endline "window created")
      ()
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
  (* A css class added by one render and dropped by the next.
     [Attr.css_class (if selected then "selected" else "row")] is how an app expresses
     selection state, and while [Attrs.diff]'s [Add_css_class]/[Remove_css_class] ops were
     covered purely, [W.Widget.remove_css_class] had never run against a real widget: the
     only live use set the same class in both renders.

     [Attr.margin] rides along. It is the one attr that expands to four writes, and until
     now only the unasserted example smoke had ever built one. *)
  let styled_view attrs = Node.window ~title:"css" (Node.label ~attrs "s") in
  let live =
    P.mount
      ctx
      ~path:"root"
      ~is_root:true
      (styled_view [ Attr.css_class "selected"; Attr.margin 7 ])
  in
  print_s (Live_tree.dump live.widget);
  let live =
    P.patch ctx ~path:"root" ~is_root:true live (styled_view [ Attr.css_class "row" ])
  in
  print_s (Live_tree.dump live.widget);
  let live = P.patch ctx ~path:"root" ~is_root:true live (styled_view []) in
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
  (match
     P.mount
       ctx
       ~path:"root"
       ~is_root:true
       (Node.window
          ~title:"outer"
          (Node.box ~orientation:Vertical [ Node.window ~title:"inner" (Node.label "x") ]))
   with
   | (_ : P.live) -> print_endline "BUG: nested window accepted"
   | exception Invalid_argument msg -> printf "nested window rejected: %s\n" msg);
  (* Two [Node.stack]s with one [~name] in one tree: an ordinary application mistake (a
     panel factory reused, a sidebar duplicated across two branches of a match), rejected
     by [apply_stack_claims] after the walk rather than during it.

     What is under test is not the rejection -- that has always worked -- but what is left
     behind. The rejection happens after the whole tree is built, connected, and, for a
     window root, {i presented}: [on_window_created] has already run. So if the rejection
     escapes [mount]'s exception-safe region, the caller gets an exception and no [live],
     while a fully wired window stays on screen for good, holding the driver through its
     signal closures. This block pins the opposite: the window is destroyed (its child is
     gone) and the handlers are disconnected (a [clicked] emitted on the button that was
     in it reaches nothing). With the guard removed both lines flip. *)
  let presented = ref None in
  let button_in_window = ref None in
  let stack_scheduled = ref 0 in
  let stack_ctx =
    P.create_ctx
      ~signals:
        { schedule = (fun (_ : unit Ui_effect.t) -> incr stack_scheduled)
        ; in_patch = (fun () -> false)
        ; on_exn =
            (fun ~node_path exn -> printf "EXN at %s: %s\n" node_path (Exn.to_string exn))
        }
      ~on_window_created:(fun w ->
        (* What [Loop.start] does with a window, so that the failure under test is the
           real one: by the time the rejection happens, the window is on screen. *)
        W.Window.present (cast w);
        (* And the last chance to hold anything from this tree: the mount is about to
           raise and will never hand back a [live]. *)
        presented := Some w;
        match widget_children w with
        | [ box ] -> button_in_window := List.hd (widget_children box)
        | _ :: _ | [] -> ())
      ()
  in
  (match
     P.mount
       stack_ctx
       ~path:"root"
       ~is_root:true
       (Node.window
          ~title:"dup"
          (Node.box
             ~orientation:Vertical
             [ Node.button
                 ~attrs:[ Attr.on_clicked (Ui_effect.print_s [%sexp "clicked"]) ]
                 ~label:"B"
                 ()
             ; Node.stack ~name:"nav" ~visible_child:"one" [ Node.label ~key:"one" "1" ]
             ; Node.stack ~name:"nav" ~visible_child:"two" [ Node.label ~key:"two" "2" ]
             ]))
   with
   | (_ : P.live) -> print_endline "BUG: duplicate stack name accepted"
   | exception Invalid_argument msg -> printf "duplicate stack name rejected: %s\n" msg);
  printf "the window was presented before the rejection: %b\n" (Option.is_some !presented);
  (* [gtk_window_destroy] hides the window and drops GTK's toplevel reference to it
     (gtkwindow.c:7047-7072), which is what takes it off screen and lets
     [Bonsai_gtk.start] return; [Patcher.destroy]'s [Window] arm is what calls it. Without
     the guard this reads [true]: a fully rendered window that nothing will ever patch
     again. *)
  printf
    "the presented window is still on screen: %b\n"
    (Option.value_map !presented ~default:true ~f:Widget.get_visible);
  Option.iter !button_in_window ~f:(fun b ->
    Gobject.Signal.emit_by_name b ~name:"clicked");
  printf "effects scheduled by that button: %d\n" !stack_scheduled;
  (* The other direction: a teardown that raises part-way must not strand the siblings it
     had not reached yet. [Native_gtk.S.destroy] is the one place teardown calls
     application code, and [Native_boom]'s raises.

     Before the collect-and-reraise, the [c] button below stayed connected and armed on a
     widget the box had already given up -- a permanently rooted GClosure holding the
     driver, which is the leak [mount]'s exception-safety exists to prevent, arriving from
     the other side. The [clicked] line is what says it is disarmed; the
     [destroy re-raised] line is what says the caller still hears about it. *)
  let boom_scheduled = ref 0 in
  let boom_ctx =
    P.create_ctx
      ~signals:
        { schedule = (fun (_ : unit Ui_effect.t) -> incr boom_scheduled)
        ; in_patch = (fun () -> false)
        ; on_exn =
            (fun ~node_path exn -> printf "EXN at %s: %s\n" node_path (Exn.to_string exn))
        }
      ~on_window_created:(fun _ -> ())
      ()
  in
  let click k =
    Node.button
      ~key:k
      ~attrs:[ Attr.on_clicked (Ui_effect.print_s [%sexp (k : string)]) ]
      ~label:k
      ()
  in
  let live =
    P.mount
      boom_ctx
      ~path:"root"
      ~is_root:true
      (Node.window
         ~title:"boom"
         (Node.box ~orientation:Vertical [ click "a"; boom (); click "c" ]))
  in
  let a = nth_box_child live 0 in
  let c = nth_box_child live 2 in
  (match P.destroy boom_ctx live with
   | () -> print_endline "BUG: a raising native destroy was swallowed"
   | exception exn -> printf "destroy re-raised: %s\n" (Exn.to_string exn));
  Gobject.Signal.emit_by_name a ~name:"clicked";
  Gobject.Signal.emit_by_name c ~name:"clicked";
  (* [c] is the one that matters: it is the sibling {i after} the raising node. *)
  printf "effects scheduled after the raising teardown: %d\n" !boom_scheduled
;;
