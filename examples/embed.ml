(* A Bonsai page inside a window this file builds by hand -- the shape an incremental port
   takes, and the reason {!Bonsai_gtk.Expert.embed} exists.

   Nothing here is a bonsai_gtk application. The [GtkApplication], the
   [GtkApplicationWindow], the header bar, the [GtkStack] and the buttons that drive it
   are all written the way an existing GTK4 program already has them; the main loop is
   GTK's own. One page of that stack is a Bonsai computation, mounted with [embed], added
   to the stack with [add_named] like any other child, and torn down with [stop] before it
   is removed. Swapping it in and out repeatedly is the interesting part: each [Show]
   builds a fresh embed and each [Hide] destroys one, so the leak and the
   use-after-teardown both have somewhere to show up.

   This is stavekeeper's [Shell] with the parts that are not about embedding taken out. *)

open! Core
open Bonsai_gtk
open Bonsai.Let_syntax
module Gtk = Ocgtk_gtk.Gtk
module W = Gtk.Wrappers
module Gio_application = Ocgtk_gio.Gio.Wrappers.Application

let cast = Gobject.unsafe_cast

(* The Bonsai half: an ordinary computation, with the one rule embedding adds -- the root
   is a container, not a [Node.window]. The window belongs to the code below. *)
let page (graph @ local) =
  let count, set_count = Bonsai.state 0 graph in
  let ticks, set_ticks = Bonsai.state 0 graph in
  (* A clock, so that the tick [embed] installs on the host's main loop is visibly doing
     its job rather than only servicing clicks. *)
  let () =
    Bonsai.Clock.every
      ~when_to_start_next_effect:`Every_multiple_of_period_non_blocking
      (Bonsai.return (Time_ns.Span.of_sec 1.))
      (let%arr ticks and set_ticks in
       set_ticks (ticks + 1))
      graph
  in
  let%arr count and set_count and ticks in
  Node.box
    ~orientation:Vertical
    ~spacing:8
    ~attrs:[ Attr.margin 12 ]
    [ Node.label
        ~attrs:[ Attr.css_class "title-2" ]
        (sprintf "Bonsai page: count %d" count)
    ; Node.label (sprintf "alive for %d seconds" ticks)
    ; Node.box
        ~orientation:Horizontal
        ~spacing:8
        ~attrs:[ Attr.halign Center ]
        [ Node.button
            ~attrs:[ Attr.on_clicked (set_count (count - 1)) ]
            ~label:"\xe2\x88\x92"
            ()
        ; Node.button
            ~attrs:
              [ Attr.on_clicked (set_count (count + 1))
              ; Attr.css_class "suggested-action"
              ]
            ~label:"+"
            ()
        ]
    ]
;;

(* The imperative half. [embedded] is [None] whenever the Bonsai page is not mounted,
   which is the state an incremental port spends most of its time in: the host owns the
   window and swaps pages, and one of them happens to be declarative. *)
let build_window app =
  let win = W.Application_window.new_ app in
  W.Window.set_title (cast win) (Some "bonsai_gtk embed");
  W.Window.set_default_size (cast win) 420 260;
  let stack = W.Stack.new_ () in
  W.Stack.set_transition_type stack `CROSSFADE;
  let placeholder = W.Label.new_ (Some "The Bonsai page is not mounted.\nPress Show.") in
  ignore
    (W.Stack.add_named stack (cast placeholder) (Some "placeholder") : W.Stack_page.t);
  let embedded : Expert.Embedded.t option ref = ref None in
  let show_button = W.Button.new_with_label "Show" in
  let hide_button = W.Button.new_with_label "Hide" in
  W.Widget.set_sensitive (cast hide_button) false;
  let sync_buttons () =
    W.Widget.set_sensitive (cast show_button) (Option.is_none !embedded);
    W.Widget.set_sensitive (cast hide_button) (Option.is_some !embedded)
  in
  let show () =
    match !embedded with
    | Some _ -> ()
    | None ->
      (* [embed] mounts the tree and hands back the root; parenting it is this code's job,
         and a [GtkStack] parents by [add_named]. That there is no one call covering
         [add_named], [append], [insert_page] and [set_child] alike is exactly why [embed]
         does not try. *)
      let e = Expert.embed page in
      ignore
        (W.Stack.add_named stack (Expert.Embedded.widget e) (Some "bonsai")
         : W.Stack_page.t);
      W.Stack.set_visible_child_name stack "bonsai";
      embedded := Some e;
      sync_buttons ()
  in
  let hide () =
    match !embedded with
    | None -> ()
    | Some e ->
      (* Teardown first, then removal -- stavekeeper's [Shell] order, and the one that
         makes the obligation easy to keep: [stop] ends the tick and the Bonsai graph
         while the widget is still somewhere, and the removal afterwards is an ordinary
         [GtkStack] operation on an ordinary widget. The other order is equally safe; what
         is not safe is dropping the host with the embed still running, which would leave
         a tick patching a page nobody can see. *)
      W.Stack.set_visible_child_name stack "placeholder";
      Expert.Embedded.stop e;
      W.Stack.remove stack (Expert.Embedded.widget e);
      embedded := None;
      sync_buttons ()
  in
  ignore (W.Button.on_clicked show_button ~callback:show : Gobject.Signal.handler_id);
  ignore (W.Button.on_clicked hide_button ~callback:hide : Gobject.Signal.handler_id);
  (* And the obligation itself, in the one place a real application has to remember it:
     the window is going away, so the page stops before it does. *)
  ignore
    (W.Window.on_close_request (cast win) ~callback:(fun () ->
       hide ();
       false)
     : Gobject.Signal.handler_id);
  let controls = W.Box.new_ `HORIZONTAL 8 in
  W.Widget.set_margin_start (cast controls) 12;
  W.Widget.set_margin_end (cast controls) 12;
  W.Widget.set_margin_bottom (cast controls) 12;
  W.Widget.set_halign (cast controls) `CENTER;
  W.Box.append controls (cast show_button);
  W.Box.append controls (cast hide_button);
  let outer = W.Box.new_ `VERTICAL 0 in
  W.Widget.set_vexpand (cast stack) true;
  W.Box.append outer (cast stack);
  W.Box.append outer (cast controls);
  W.Window.set_child (cast win) (Some (cast outer : W.Widget.t));
  (* Mounted at startup rather than on the first click, so that the smoke run in
     [scripts/ci.sh] exercises the embed rather than only the window around it. *)
  show ();
  W.Window.present (cast win)
;;

let () =
  let app =
    W.Application.new_ (Some "org.bonsai_gtk.examples.embed") [ `DEFAULT_FLAGS ]
  in
  ignore
    (Gio_application.on_activate app ~callback:(fun () -> build_window app)
     : Gobject.Signal.handler_id);
  exit (Gio_application.run app 0 None)
;;
