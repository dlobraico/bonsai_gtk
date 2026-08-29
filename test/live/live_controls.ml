open! Core
open Bonsai_gtk_vtree
module Gobject = Bonsai_gtk.Private.Gtk_import.Gobject
module Live_tree = Bonsai_gtk.Private.Live_tree
module P = Bonsai_gtk.Private.Patcher
module Scheduler = Bonsai_gtk.Private.Scheduler
module W = Bonsai_gtk.Private.Gtk_import.W

let cast = Bonsai_gtk.Private.Gtk_import.cast

let nth_child (live : P.live) i : P.live =
  match live.children with
  | Single (Some box) ->
    (match box.children with
     | List children -> List.nth_exn children i
     | No_children | Single _ | Slots _ -> assert false)
  | No_children | Single None | List _ | Slots _ -> assert false
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
  let text_attrs = Attr.on_changed (fun _ -> Ui_effect.Ignore) in
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
           (* The entry kinds, for their own props rather than for [active]: they are
              identical in both views, so they take no part in the patch below. Their
              event attrs are here so that every spec each impl declares has a slot to
              fire out of -- emitted by hand further down. *)
         ; Node.entry
             ~attrs:[ text_attrs; Attr.on_activate Ui_effect.Ignore ]
             ~placeholder:"name"
             ~width_chars:8
             ~text:"typed"
             ()
         ; Node.entry
             ~attrs:[ text_attrs ]
             ~text:"secret"
             ~visibility:false
             ~editable:false
             ~xalign:1.
             ~max_width_chars:20
             ~activates_default:true
             ()
         ; Node.password_entry
             ~attrs:[ text_attrs; Attr.on_activate Ui_effect.Ignore ]
             ~placeholder:"passphrase"
             ~show_peek_icon:false
             ~text:""
             ()
         ; Node.search_entry
             ~attrs:
               [ text_attrs
               ; Attr.on_activate Ui_effect.Ignore
               ; Attr.on_search_changed (fun _ -> Ui_effect.Ignore)
               ]
             ~placeholder:"filter"
             ~search_delay:200
             ~text:"bach"
             ()
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
  (* Every spec the three entry impls declare, fired from its own widget: [changed] comes
     through [GtkEditable] on all four entries, [activate] off each concrete class, and
     [search-changed] off the search entry alone. Eight in all -- the read-only entry
     carries no [on_activate] -- and each spec that failed to connect would drop this
     count. *)
  let before = !scheduled in
  List.iter [ 6; 7; 8; 9 ] ~f:(fun i ->
    Gobject.Signal.emit_by_name (nth_child live i).widget ~name:"changed");
  List.iter [ 6; 8; 9 ] ~f:(fun i ->
    Gobject.Signal.emit_by_name (nth_child live i).widget ~name:"activate");
  Gobject.Signal.emit_by_name (nth_child live 9).widget ~name:"search-changed";
  printf "entry signals reaching Bonsai: %d\n" (!scheduled - before);
  (* The other half of the controlled rule, and the half a props diff cannot see. A model
     that *declines* the user's change renders exactly the props it rendered last frame,
     so [update] is skipped and only [Widget_impl.reassert] is left to put the widget
     back. Flip all three toggles behind the model's back, then patch with the tree
     unchanged at [active:true]: every one must come back on, and none of it may reach
     Bonsai. *)
  W.Toggle_button.set_active (cast (nth_child live 3).widget) false;
  W.Check_button.set_active (cast (nth_child live 4).widget) false;
  W.Switch.set_active (cast (nth_child live 5).widget) false;
  let before = !scheduled in
  let live =
    Scheduler.with_patch_guard scheduler (fun () ->
      P.patch ctx ~path:"root" ~is_root:true live (view ~active:true))
  in
  printf
    "declined toggle %b, check %b, switch %b (state %b); reached Bonsai: %d\n"
    (W.Toggle_button.get_active (cast (nth_child live 3).widget))
    (W.Check_button.get_active (cast (nth_child live 4).widget))
    (W.Switch.get_active (cast (nth_child live 5).widget))
    (W.Switch.get_state (cast (nth_child live 5).widget))
    (!scheduled - before);
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
  (* Spec §11 says mount *and* patch time. An event attr a later render adds -- the
     conditional [if editing then Attr.on_toggled ...] -- lands on a widget that was
     mounted without it, so only the patch is in a position to reject it. *)
  let late = Node.window ~title:"late" (Node.label ~attrs:[ Attr.tooltip "t" ] "x") in
  let late_live = P.mount ctx ~path:"late" ~is_root:true late in
  (match
     P.patch
       ctx
       ~path:"late"
       ~is_root:true
       late_live
       (Node.window
          ~title:"late"
          (Node.label
             ~attrs:[ Attr.tooltip "t"; Attr.on_toggled (fun _ -> Ui_effect.Ignore) ]
             "x"))
   with
   | (_ : P.live) -> print_endline "BUG: on_toggled added by a patch accepted"
   | exception Invalid_argument msg -> printf "rejected at patch: %s\n" msg);
  P.destroy ctx late_live;
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
  P.destroy ctx live;
  (* Controlled text (spec §6.5). Render "a", then let the "user" type "ab" straight into
     the widget, then re-render a node that still says "a" -- the model declined the edit,
     or has not caught up -- and the widget must be corrected back to "a". Then type "ab"
     again and re-render a node that says "ab" -- the model echoed -- and nothing must be
     written at all.

     "Nothing was written" is observed directly, with a counter connected to the widget's
     own [changed] signal: it fires for every [set_text], the patcher's reentrancy guard
     notwithstanding, so a patch that wrote is a patch this counter saw. (Whether it saw
     one or two is GTK's business -- [gtk_editable_set_text] is a delete followed by an
     insert -- hence the boolean.) The guard is what the third line measures, and the two
     are different claims: a write Bonsai never hears about is still a caret jump the user
     feels. *)
  let entry_view text =
    Node.window
      ~title:"e"
      (Node.entry ~attrs:[ Attr.on_changed (fun _ -> Ui_effect.Ignore) ] ~text ())
  in
  (* Re-read through the current [live]: [patch] returns a fresh record whenever the kind
     changes, and the widget is only ever reachable through the record we hold now. *)
  let editable_of (live : P.live) =
    match live.children with
    | Single (Some e) -> W.Editable.from_gobject e.widget
    | No_children | Single None | List _ | Slots _ -> assert false
  in
  let live = P.mount ctx ~path:"root" ~is_root:true (entry_view "a") in
  let writes = ref 0 in
  let (_ : Gobject.Signal.handler_id) =
    W.Editable.on_changed (editable_of live) ~callback:(fun () -> incr writes)
  in
  let reached_bonsai = ref 0 in
  let observe label live node =
    let writes_before = !writes
    and scheduled_before = !scheduled in
    let live =
      Scheduler.with_patch_guard scheduler (fun () ->
        P.patch ctx ~path:"root" ~is_root:true live node)
    in
    reached_bonsai := !reached_bonsai + (!scheduled - scheduled_before);
    printf
      "%s: %s (the patch wrote: %b)\n"
      label
      (W.Editable.get_text (editable_of live))
      (!writes > writes_before);
    live
  in
  (* The user types, outside any patch: this is the state the model is behind. *)
  W.Editable.set_text (editable_of live) "ab";
  let live = observe "model wins" live (entry_view "a") in
  W.Editable.set_text (editable_of live) "ab";
  let live = observe "echo is a no-op" live (entry_view "ab") in
  printf "changed events reaching Bonsai from patches: %d\n" !reached_bonsai;
  print_s (Live_tree.dump live.widget);
  P.destroy ctx live;
  (* The controlled-value rule, the numeric twin of the entry case above: drag the scale
     and spin the spin button behind the model's back, re-render the old value, and the
     model wins. Both classes carry their own [value-changed] -- the scale's through
     [GtkRange], the spin button's its own -- so both are fired outside a patch first, to
     show each spec is connected at all. *)
  let numeric_attrs = Attr.on_value_changed (fun _ -> Ui_effect.Ignore) in
  let scale_view value =
    Node.window
      ~title:"n"
      (Node.box
         ~orientation:Vertical
         [ Node.scale
             ~attrs:[ numeric_attrs ]
             ~orientation:Horizontal
             ~min:0.
             ~max:10.
             ~value
             ()
         ; Node.spin_button ~attrs:[ numeric_attrs ] ~min:0. ~max:100. ~value ()
         ; Node.progress_bar ~fraction:(value /. 10.) ~text:"p" ~show_text:true ()
         ; Node.spinner ~spinning:true ()
         ])
  in
  let live = P.mount ctx ~path:"root" ~is_root:true (scale_view 3.) in
  print_s (Live_tree.dump live.widget);
  let before = !scheduled in
  Gobject.Signal.emit_by_name (nth_child live 0).widget ~name:"value-changed";
  Gobject.Signal.emit_by_name (nth_child live 1).widget ~name:"value-changed";
  printf "value-changed reaching Bonsai outside a patch: %d\n" (!scheduled - before);
  W.Range.set_value (cast (nth_child live 0).widget) 7.;
  W.Spin_button.set_value (cast (nth_child live 1).widget) 42.;
  let before = !scheduled in
  let live =
    Scheduler.with_patch_guard scheduler (fun () ->
      P.patch ctx ~path:"root" ~is_root:true live (scale_view 3.))
  in
  printf
    "model wins: scale %g, spin %g\n"
    (W.Range.get_value (cast (nth_child live 0).widget))
    (W.Spin_button.get_value (cast (nth_child live 1).widget));
  printf "value-changed reaching Bonsai from patches: %d\n" (!scheduled - before);
  let live =
    Scheduler.with_patch_guard scheduler (fun () ->
      P.patch ctx ~path:"root" ~is_root:true live (scale_view 6.))
  in
  print_s (Live_tree.dump live.widget);
  P.destroy ctx live
;;
