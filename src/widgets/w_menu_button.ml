open! Core
open Bonsai_gtk_vtree
open Gtk_import

(* A [GtkMenuButton]: props, the [~popover] Single slot patched through [set_popover], and
   the popdown focus repair below -- the one GTK behaviour this widget exists to fix once,
   at the library layer, so no port carries a timer for it again.

   [label]/[icon_name] have {i non-option} setters (no unbind in the binding), and GTK
   makes them mutually exclusive -- each setter replaces the button's one child widget.
   The constructor rejects both together; the impl's update writes whichever the new node
   carries, and a node that dropped both writes [set_label ""] (the closest thing to unset
   the binding offers -- GTK's arrow-only look needs the icon default this library cannot
   re-ask for). *)

(* {b The popdown focus repair.} GTK4 can leave the {i window's} focus widget pointing
   into a popover that has just popped down: every key the window should see then routes
   into an unmapped subtree and dies. stavekeeper's [viewer_window.ml:750-797] documents
   exactly this ("every viewer key goes dead after one menu use") and works around it
   app-side with a re-armable 60 ms x 8 polling timeout that clears [set_focus None]. This
   is that repair, made once, synchronously, with no timer: on the popover's [closed], if
   the window's focus widget is the popover or inside it, clear the window's focus. It
   rides on [closed] as its own connection in [W_popover]'s spec -- with the popover's
   other connections, so [Patcher.destroy] disconnects it before the popover can be
   collected (the dispose rule) -- rather than being connected from this impl's slot
   [set], which teardown could not reach.

   {b What is proven so far is narrower than the bug} (task-5 review, Important 2).
   stavekeeper's stranding is a [GtkPopoverMenu] after {i item activation}; the trigger
   for that path does not exist until Task 6 lands menus and actions. [live_input.ml]'s
   Escape-on-a-plain-popover block proves the surrounding chain (dismiss, [closed], window
   keys alive afterwards) -- and on that path GTK most likely restores focus itself, so
   the repair's predicate reads false and the clear never runs. Task 6 must re-prove the
   keys-alive-afterwards line after a real menu item activation, and design the fallback
   (a one-shot idle may be short against stavekeeper's 60 ms x 8 window) if the
   synchronous clear turns out to be too early there. Recorded as a Task 6 carry in the
   ledger.

   Deliberately {i not} behind the [in_patch] guard: a patch-driven [popdown] (the model
   flipping [~open_] to false) strands focus exactly as a user dismissal does, and
   clearing it is an ordinary patch-time write. The whole body is exception-guarded
   because it runs on GTK's C stack outside [Signals]' trampolines; nothing in it can
   raise from OCaml, and the guard is the backstop the signal-slot rule requires. *)
let repair_focus_after_popdown (popover : Widget.t) =
  try
    match Widget.get_root popover with
    | None -> ()
    | Some root ->
      (* A [GtkRoot] is a window (or a subclass) in every tree this library builds;
         [get_focus]/[set_focus] are window methods. *)
      let window : W.Window.t = cast root in
      (match W.Window.get_focus window with
       | Some f when Gobject.same f popover || Widget.is_ancestor f popover ->
         W.Window.set_focus window None
       | Some _ | None -> ())
  with
  | _ ->
    (* Swallowed rather than reported, and silently by necessity: this runs on GTK's C
       stack with no [Signals.ctx] in reach -- the connection is made in a spec's
       [connect], which is handed no reporting channel -- and a best-effort repair that
       failed leaves exactly the state the repair exists to fix, which the user
       experiences as the pre-repair bug rather than a new one. If the repair ever grows a
       real failure mode, threading [on_exn] into the spec's [connect] is the change to
       make. *)
    ()
;;

let apply_label_or_icon (mb : W.Menu_button.t) (p : Kind.menu_button_props) =
  match p.label, p.icon_name with
  | Some l, _ -> W.Menu_button.set_label mb l
  | None, Some i -> W.Menu_button.set_icon_name mb i
  | None, None -> ()
;;

let impl : Widget_impl.t =
  { name = "MenuButton"
  ; create =
      (fun (kind : Kind.t) ->
        match kind with
        | Menu_button p ->
          let mb = W.Menu_button.new_ () in
          let w = (mb :> Widget.t) in
          Widget_impl.batch w (fun () ->
            apply_label_or_icon mb p;
            if p.primary then W.Menu_button.set_primary mb true;
            if p.always_show_arrow then W.Menu_button.set_always_show_arrow mb true);
          w
        | k -> Widget_impl.wrong_kind "MenuButton" k)
  ; update =
      (fun w ~(old : Kind.t) (new_ : Kind.t) ->
        match old, new_ with
        | Menu_button old, Menu_button new_ ->
          let mb : W.Menu_button.t = cast w in
          Widget_impl.batch w (fun () ->
            if not
                 (Option.equal String.equal old.label new_.label
                  && Option.equal String.equal old.icon_name new_.icon_name)
            then (
              match new_.label, new_.icon_name with
              | Some _, _ | None, Some _ -> apply_label_or_icon mb new_
              | None, None ->
                (* Dropping both: there is no unbind, and an empty label is the closest
                   the binding offers to "back to nothing". *)
                W.Menu_button.set_label mb "");
            if not (Bool.equal old.primary new_.primary)
            then W.Menu_button.set_primary mb new_.primary;
            if not (Bool.equal old.always_show_arrow new_.always_show_arrow)
            then W.Menu_button.set_always_show_arrow mb new_.always_show_arrow)
        | _, k -> Widget_impl.wrong_kind "MenuButton" k)
  ; reassert = None
  ; signals = []
  ; children =
      Widget_impl.Slots
        [ ( "popover"
          , Slot_single
              { set =
                  (fun w c ->
                    (* The one place a [Node.popover] parents ([check_placement] rejects
                       it everywhere else): [set_popover] both parents the popover and
                       binds the button's toggle to it; [None] unparents. The child
                       arrives as a plain [Widget.t] and is a popover by construction --
                       the placement check ran before this. *)
                    W.Menu_button.set_popover (cast w) (Option.map c ~f:cast))
              } )
        ]
  }
;;
