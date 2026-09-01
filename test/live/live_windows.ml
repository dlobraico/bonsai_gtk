open! Core
open Bonsai_gtk
open Bonsai.Let_syntax
open Bonsai_gtk_vtree
module Glib = Bonsai_gtk.Private.Gtk_import.Glib
module Gobject = Bonsai_gtk.Private.Gtk_import.Gobject
module Live_tree = Bonsai_gtk.Private.Live_tree
module P = Bonsai_gtk.Private.Patcher
module Scheduler = Bonsai_gtk.Private.Scheduler
module W = Bonsai_gtk.Private.Gtk_import.W
module Widget = Bonsai_gtk.Private.Gtk_import.Widget

let cast = Bonsai_gtk.Private.Gtk_import.cast
let widget_children = Bonsai_gtk.Private.Gtk_import.widget_children
let type_name = Bonsai_gtk.Private.Gtk_import.type_name

(* [Node.windows] against real GTK (M3 Task 8 step 7): several toplevels out of one tree,
   the transient/modal reality, the close-request veto end to end, identity across a
   reorder, destruction proven by [get_visible]/[get_mapped] (never by a [destroy] signal:
   ocgtk's [Widget.on_destroy] never delivers -- pre-flight 3), and the last-present-wins
   focus ordering (pre-flight 4).

   Driven through [Expert.Driver] with hand-driven first frame plus [drain] for the
   scheduler's idles, [live_driver.ml]'s pattern -- [Bonsai_gtk.start] would own the main
   loop. The one [start]-owned claim, [Node.windows []] = the declarative quit, gets the
   real thing at the bottom: a [start] whose model renders the empty list returns. *)

let () = ignore (Ocgtk_gtk.GMain.init () : string array)

let drain () =
  let iterations = ref 0 in
  while Glib.Main.pending () && !iterations < 10_000 do
    ignore (Glib.Main.iteration false : bool);
    incr iterations
  done
;;

(* [live_input.ml]'s settling wait: the watchdog fires only when the awaited thing never
   happens, and the failure it produces is a golden diff naming the block that hung. *)
let watchdog_ms = 10_000

let pump_until ~label ~ready =
  if not (ready ())
  then (
    let expired = ref false in
    let id =
      Glib.Timeout.add
        ~ms:watchdog_ms
        ~callback:(fun () ->
          expired := true;
          false)
        ()
    in
    let iterations = ref 0 in
    while (not (ready ())) && (not !expired) && !iterations < 100_000 do
      ignore (Glib.Main.iteration true : bool);
      incr iterations
    done;
    if not !expired then Glib.Timeout.remove id;
    if not (ready ()) then printf "%s: TIMED OUT\n" label)
;;

let rec find_by_type name w =
  if String.equal (type_name w) name
  then Some w
  else List.find_map (widget_children w) ~f:(find_by_type name)
;;

(* Three windows out of one tree. The transient dialog comes {i first} in the list, before
   the window it names -- resolution is after the whole list exists, and this pins live
   that order does not matter. [prefs] and [main] each carry an autofocus entry (one per
   toplevel is the rule; two toplevels in one frame is the interplay pre-flight 5's probe
   idiom is for); [tools] carries {b no} close handler, for the swallowed-request half of
   the veto. *)
let app (graph @ local) =
  let prefs_open, set_prefs = Bonsai.state true graph in
  let main_open, set_main = Bonsai.state true graph in
  let flipped, set_flipped = Bonsai.state false graph in
  let%arr prefs_open
  and set_prefs
  and main_open
  and set_main
  and flipped
  and set_flipped in
  let prefs =
    Node.window
      ~key:"prefs"
      ~title:"prefs"
      ~transient_for:"main"
      ~modal:true
      ~resizable:false
      ~attrs:[ Attr.on_close_request (set_prefs false) ]
      (Node.entry ~attrs:[ Attr.autofocus true ] ~placeholder:"search" ~text:"" ())
  in
  let main_w =
    Node.window
      ~key:"main"
      ~title:"main"
      ~default_size:(300, 200)
      ~attrs:[ Attr.on_close_request (set_main false) ]
      (Node.box
         ~orientation:Vertical
         [ Node.entry ~attrs:[ Attr.autofocus true ] ~text:"" ()
         ; Node.label "the main window"
         ])
  in
  let tools =
    Node.window
      ~key:"tools"
      ~title:"tools"
      (Node.button ~attrs:[ Attr.on_clicked (set_flipped true) ] ~label:"flip" ())
  in
  Node.windows
    ((if prefs_open then [ prefs ] else [])
     @ (if main_open then [ main_w ] else [])
     @ [ tools ]
     |> fun l -> if flipped then List.rev l else l)
;;

let () =
  let time_source = Bonsai.Time_source.create ~start:Time_ns.epoch in
  let d =
    Expert.Driver.create
      ~time_source
      ~on_window_created:(fun w ->
        printf
          "window created: %s\n"
          (Option.value (W.Window.get_title (cast w)) ~default:"<none>");
        W.Window.present (cast w))
      app
  in
  Expert.Driver.frame d;
  drain ();
  (* The documented break: a windows root has no root widget -- the anchor is nobody's
     business -- and [Driver.windows] is the accessor, in the model's own list order. *)
  printf "root_widget is None: %b\n" (Option.is_none (Expert.Driver.root_widget d));
  let windows () = Expert.Driver.windows d in
  let window_exn key = List.Assoc.find_exn (windows ()) key ~equal:String.equal in
  printf
    "keys in model order: %s\n"
    (String.concat ~sep:"," (List.map (windows ()) ~f:fst));
  List.iter (windows ()) ~f:(fun (key, w) ->
    printf "--- %s ---\n" (key : Key.t);
    print_s (Live_tree.dump w));
  (* The transient reality behind the dump's title line: the GtkWindow [prefs] is
     transient for is [main]'s, by identity. *)
  printf
    "prefs' transient parent is main's GtkWindow: %b\n"
    (match W.Window.get_transient_for (cast (window_exn "prefs")) with
     | Some p -> Gobject.same p (window_exn "main")
     | None -> false);
  (* Autofocus interplay: one grab per toplevel, both fired in the one mount frame. The
     probe is pre-flight 5's: [Window.get_focus] plus a descendant check, because an
     entry's focus widget is its internal [GtkText] ([has_focus] on the entry reads
     false). *)
  List.iter [ "prefs"; "main" ] ~f:(fun key ->
    let w = window_exn key in
    let entry = Option.value_exn (find_by_type "GtkEntry" w) in
    printf
      "%s: window focus is inside its autofocused entry: %b\n"
      key
      (match W.Window.get_focus (cast w) with
       | Some f -> Gobject.same f entry || Widget.is_ancestor f entry
       | None -> false));
  (* Pre-flight 4: presents in one burst resolve last-present-wins, deterministically --
     mount presented in list order, so [tools] holds the focus -- and re-presenting an
     earlier window takes it back. *)
  let active key = W.Window.is_active (cast (window_exn key)) in
  pump_until ~label:"last-present" ~ready:(fun () -> active "tools");
  printf
    "after the mount burst (prefs,main,tools presented in order): active = prefs:%b \
     main:%b tools:%b\n"
    (active "prefs")
    (active "main")
    (active "tools");
  W.Window.present (cast (window_exn "main"));
  pump_until ~label:"re-present" ~ready:(fun () -> active "main");
  printf
    "after re-presenting main: active = prefs:%b main:%b tools:%b\n"
    (active "prefs")
    (active "main")
    (active "tools");
  (* --- the veto, swallowed half: [tools] has no handler, so the runtime answers GTK
     "handled", the window stays, and the once-per-window report fires -- once, however
     many requests arrive. The report is a stderr line (the trampoline has no reporting
     channel), so stderr is pointed at stdout around the two closes; both channels are
     flushed at the seams to keep the golden's ordering honest. *)
  let tools_w = window_exn "tools" in
  printf "%!";
  let saved_stderr = Caml_unix.dup Caml_unix.stderr in
  Caml_unix.dup2 Caml_unix.stdout Caml_unix.stderr;
  W.Window.close (cast tools_w);
  drain ();
  W.Window.close (cast tools_w);
  drain ();
  Out_channel.flush stderr;
  Caml_unix.dup2 saved_stderr Caml_unix.stderr;
  Caml_unix.close saved_stderr;
  printf
    "tools after two swallowed close requests: visible=%b mapped=%b\n"
    (Widget.get_visible tools_w)
    (Widget.get_mapped tools_w);
  (* --- the veto, heard half: [prefs]' handler drops its node, so the close arrives as a
     model change -- the request itself destroyed nothing (the veto), the patch did.
     Destruction is asserted with [get_visible]/[get_mapped] on the held wrapper,
     pre-flight 3's rule. *)
  let prefs_w = window_exn "prefs" in
  W.Window.close (cast prefs_w);
  drain ();
  printf
    "prefs after a handled close request: visible=%b mapped=%b\n"
    (Widget.get_visible prefs_w)
    (Widget.get_mapped prefs_w);
  printf "keys now: %s\n" (String.concat ~sep:"," (List.map (windows ()) ~f:fst));
  (* --- identity across a reorder: flipping the list is a keyed diff with [move = None],
     so no window is touched -- same GObjects, new order. *)
  let main_before = window_exn "main"
  and tools_before = window_exn "tools" in
  let flip_button = Option.value_exn (find_by_type "GtkButton" tools_before) in
  Gobject.Signal.emit_by_name flip_button ~name:"clicked";
  drain ();
  printf
    "keys after the flip: %s\n"
    (String.concat ~sep:"," (List.map (windows ()) ~f:fst));
  printf
    "both windows kept their GObjects across the reorder: %b\n"
    (Gobject.same main_before (window_exn "main")
     && Gobject.same tools_before (window_exn "tools"));
  Expert.Driver.stop d;
  printf
    "after stop: windows = %d, main visible=%b tools visible=%b\n"
    (List.length (windows ()))
    (Widget.get_visible main_before)
    (Widget.get_visible tools_before)
;;

(* --- the missing-key fixup raise, executed (task-8-review minor 4): the reference is the
   fixup pass's business, so the mount itself succeeds and [run_fixups] is what raises the
   shared [Events] string -- the same one the handle renders, here actually thrown.
   [Exn.protect] has emptied the queue by then, so the mounted tree is still ours to
   destroy. Hand-driven, because [Driver.frame] would turn the raise into a broken driver
   (its own suite's claim). *)
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
  let live =
    Scheduler.with_patch_guard scheduler (fun () ->
      let live =
        P.mount
          ctx
          ~path:"root"
          ~is_root:true
          (Node.windows [ Node.window ~key:"a" ~transient_for:"nope" (Node.label "x") ])
      in
      (match P.run_fixups ctx with
       | () -> printf "missing-key fixup did not raise\n"
       | exception Invalid_argument m -> printf "missing-key fixup raised: %s\n" m);
      live)
  in
  P.destroy ctx live;
  printf "missing-key block done\n"
;;

(* [Node.windows []] is the declarative quit, and only [Bonsai_gtk.start] can prove it:
   with no window ever added, the GtkApplication releases and [run] returns 0. The
   watchdog turns a hang -- the failure mode this pins against -- into exit 3 rather than
   a stuck CI. *)
let () =
  ignore
    (Glib.Timeout.add
       ~ms:20_000
       ~callback:(fun () ->
         eprintf "live_windows: start over windows [] hung\n%!";
         Stdlib.exit 3)
       ()
     : Glib.Timeout.id);
  let quit_app (_graph @ local) = Bonsai.return (Node.windows []) in
  let status =
    Bonsai_gtk.start ~application_id:"org.bonsai_gtk.test.live_windows" quit_app
  in
  printf "start over windows [] returned %d (the declarative quit)\n" status
;;
