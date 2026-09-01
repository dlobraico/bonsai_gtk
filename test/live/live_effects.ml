open! Core
open Bonsai_gtk
open Bonsai_gtk_vtree
module For_runtime = Bonsai_gtk.Private.Gtk_effect.For_runtime
module Glib = Bonsai_gtk.Private.Gtk_import.Glib
module Gobject = Bonsai_gtk.Private.Gtk_import.Gobject
module W = Bonsai_gtk.Private.Gtk_import.W

let cast = Bonsai_gtk.Private.Gtk_import.cast

(* The §8 effects that need no dialog (M3 Task 9): [after] and [on_idle] resolving in bind
   order through real GLib sources, [Clipboard.set_text] reaching a real [GdkClipboard],
   [Window.present] flipping [is_active] between two windows of one [Node.windows] tree --
   and the teardown half, which the plan calls the review's first stop: an [after] still
   in flight when [Driver.stop] drops the hooks fires anyway, resolves, logs the missing
   frame-requester, and takes nothing down.

   The hooks are registered here exactly as [Loop.start]'s activate registers them
   (request-frame from the driver, lookup through [Driver.windows], context from
   [root_widget]-or-first-window), because this suite drives its own loop -- [start] would
   own it. The identity-guarded unregister gets its own block at the bottom. *)

let () = ignore (Ocgtk_gtk.GMain.init () : string array)

let drain () =
  let iterations = ref 0 in
  while Glib.Main.pending () && !iterations < 10_000 do
    ignore (Glib.Main.iteration false : bool);
    incr iterations
  done
;;

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

(* The resolution order, in a ref rather than Bonsai state: what this suite asserts is the
   {i effects'} sequencing, and a ref cannot go stale the way a closed-over model value
   can. *)
let order : string list ref = ref []
let record s = Ui_effect.of_thunk (fun () -> order := s :: !order)

let go_effect =
  let open Ui_effect.Let_syntax in
  (* [bind] is the ordering claim: [on_idle] is not even armed until [after] has resolved,
     so "after,on_idle" in the golden means each really completed before its successor
     began -- resolved in order, as the plan's step 1 asks. *)
  let%bind () = Effect.after (Time_ns.Span.of_int_ms 16) in
  let%bind () = record "after(16ms)" in
  let%bind () = Effect.on_idle in
  record "on_idle"
;;

let app (_graph @ local) =
  Bonsai.return
    (Node.windows
       [ Node.window
           ~key:"a"
           ~title:"a"
           (Node.button ~attrs:[ Attr.on_clicked go_effect ] ~label:"go" ())
       ; Node.window ~key:"b" ~title:"b" (Node.label "b")
       ])
;;

let () =
  let time_source = Bonsai.Time_source.create ~start:Time_ns.epoch in
  let d =
    Expert.Driver.create
      ~time_source
      ~on_window_created:(fun w -> W.Window.present (cast w))
      app
  in
  (* Registered before the first frame, as [Loop.start] registers them, so an effect the
     first frame performs already finds them; dropped by [Driver.stop] through the same
     registered thunk the runtime uses. *)
  let reg =
    For_runtime.register
      ~request_frame:(fun () -> Expert.Driver.request_frame d)
      ~lookup_window:(fun key ->
        List.Assoc.find (Expert.Driver.windows d) key ~equal:Key.equal)
      ~context_widget:(fun () ->
        match Expert.Driver.root_widget d with
        | Some w -> Some w
        | None -> Option.map (List.hd (Expert.Driver.windows d)) ~f:snd)
      ()
  in
  Expert.Driver.set_effect_hooks_drop d (fun () -> For_runtime.unregister reg);
  Expert.Driver.frame d;
  drain ();
  let window_exn key =
    List.Assoc.find_exn (Expert.Driver.windows d) key ~equal:Key.equal
  in
  (* --- after then on_idle, from a button's effect, resolved in bind order. *)
  let button =
    let rec go w =
      if String.equal (Bonsai_gtk.Private.Gtk_import.type_name w) "GtkButton"
      then Some w
      else List.find_map (Bonsai_gtk.Private.Gtk_import.widget_children w) ~f:go
    in
    Option.value_exn (go (window_exn "a"))
  in
  Gobject.Signal.emit_by_name button ~name:"clicked";
  pump_until ~label:"after-then-idle" ~ready:(fun () -> List.length !order = 2);
  printf "resolved in order: %s\n" (String.concat ~sep:"," (List.rev !order));
  (* --- the clipboard write. The assertion is deliberately thin -- the call returned and
     nothing logged or crashed -- because there is no bound read: [get_text] has no sync
     form and no bound async one (fact table; fork-round-3 candidate), so the honest round
     trip arrives with a future read. *)
  Expert.Driver.schedule_event d (Effect.Clipboard.set_text "bonsai_gtk clipboard");
  drain ();
  printf "set_text: ok\n";
  (* --- Window.present flips the active window: b was presented last at mount, so it
     holds the focus; presenting a takes it. *)
  let active key = W.Window.is_active (cast (window_exn key)) in
  pump_until ~label:"mount-active" ~ready:(fun () -> active "b");
  printf "before present: active = a:%b b:%b\n" (active "a") (active "b");
  Expert.Driver.schedule_event d (Effect.Window.present "a");
  pump_until ~label:"present-a" ~ready:(fun () -> active "a");
  printf "after Window.present \"a\": active = a:%b b:%b\n" (active "a") (active "b");
  (* A key naming no window logs and resolves -- an effect is a value a test may perform,
     never a raise. The line is stderr's, captured by pointing it at stdout. *)
  printf "%!";
  let saved_stderr = Caml_unix.dup Caml_unix.stderr in
  Caml_unix.dup2 Caml_unix.stdout Caml_unix.stderr;
  Expert.Driver.schedule_event d (Effect.Window.present "zzz");
  drain ();
  Out_channel.flush stderr;
  Caml_unix.dup2 saved_stderr Caml_unix.stderr;
  Caml_unix.close saved_stderr;
  (* --- a raising continuation (task-9-review Important 1), on the production perform
     path: the driver performs with Bonsai_driver's re-raising on_exn, so the raise in the
     bind code comes back out of [respond_to] itself and the resolver must log it by name
     and carry on -- the loop surviving is the doctrine's hard half, and this is exactly
     the path Task 10's dialog continuations ride. The survivor effect after it is the
     survival proof. *)
  order := [];
  printf "%!";
  let saved_stderr = Caml_unix.dup Caml_unix.stderr in
  Caml_unix.dup2 Caml_unix.stdout Caml_unix.stderr;
  Expert.Driver.schedule_event
    d
    (let open Ui_effect.Let_syntax in
     let%bind () = Effect.on_idle in
     (* The marker before the raise pins that the continuation ran up to it: injects that
        land before a raise are real, which is why the resolver still requests the
        flushing frame. *)
     let%bind () = Ui_effect.of_thunk (fun () -> printf "pre-boom reached\n%!") in
     Ui_effect.of_thunk (fun () -> failwith "boom in the continuation"));
  Expert.Driver.schedule_event
    d
    (let open Ui_effect.Let_syntax in
     let%bind () = Effect.on_idle in
     record "survivor");
  pump_until ~label:"raising-continuation" ~ready:(fun () -> List.length !order = 1);
  Out_channel.flush stderr;
  Caml_unix.dup2 saved_stderr Caml_unix.stderr;
  Caml_unix.close saved_stderr;
  printf
    "the loop survived a raising continuation, and the next effect resolved: %s\n"
    (String.concat ~sep:"," (List.rev !order));
  (* --- teardown (step 3, the review's first stop): an [after] armed and then orphaned by
     [stop]. The frame that performs it arms the GLib timeout; [stop] drops the hooks; the
     timeout still fires, the effect still resolves (the ref moves), the resolver logs the
     dropped frame-requester instead of raising into C, and requests nothing. *)
  let late = ref false in
  Expert.Driver.schedule_event
    d
    (let open Ui_effect.Let_syntax in
     let%bind () = Effect.after (Time_ns.Span.of_int_ms 40) in
     Ui_effect.of_thunk (fun () -> late := true));
  drain ();
  Expert.Driver.stop d;
  printf "stopped with a 40 ms after in flight; resolved yet: %b\n%!" !late;
  let saved_stderr = Caml_unix.dup Caml_unix.stderr in
  Caml_unix.dup2 Caml_unix.stdout Caml_unix.stderr;
  pump_until ~label:"late-after" ~ready:(fun () -> !late);
  (* The no-hooks miss logs (task-9-review minor 3), while the hooks are genuinely gone:
     present and set_text each log-and-resolve. Performed directly -- the driver is
     stopped, which is the point. (The under-embed present arm stays unexecuted: it
     genuinely needs an embed.) *)
  Ui_effect.Expert.handle
    ~on_exn:(fun exn -> printf "EXN: %s\n" (Exn.to_string exn))
    (Effect.Window.present "a");
  Ui_effect.Expert.handle
    ~on_exn:(fun exn -> printf "EXN: %s\n" (Exn.to_string exn))
    (Effect.Clipboard.set_text "nobody's clipboard");
  Out_channel.flush stderr;
  Caml_unix.dup2 saved_stderr Caml_unix.stderr;
  Caml_unix.close saved_stderr;
  printf "the in-flight after resolved after stop: %b\n" !late
;;

(* --- the identity-guarded unregister: a displaced registration's drop (the first of two
   embeds, stopped) must not take the replacement's hooks down. [on_idle]'s resolve
   requests a frame through whatever hooks are current, which is the probe. *)
let () =
  let hits = ref 0 in
  let reg1 =
    For_runtime.register ~request_frame:ignore ~context_widget:(fun () -> None) ()
  in
  let reg2 =
    For_runtime.register
      ~request_frame:(fun () -> incr hits)
      ~context_widget:(fun () -> None)
      ()
  in
  For_runtime.unregister reg1;
  let resolved = ref false in
  Ui_effect.Expert.handle
    ~on_exn:(fun exn -> printf "EXN: %s\n" (Exn.to_string exn))
    (let open Ui_effect.Let_syntax in
     let%bind () = Effect.on_idle in
     Ui_effect.of_thunk (fun () -> resolved := true));
  pump_until ~label:"guarded-unregister" ~ready:(fun () -> !resolved);
  printf
    "a displaced registration's drop left the replacement armed: frame requests = %d\n"
    !hits;
  (* The negative clamp: a span below zero behaves as zero and resolves promptly rather
     than wedging or raising. *)
  let neg = ref false in
  Ui_effect.Expert.handle
    ~on_exn:(fun exn -> printf "EXN: %s\n" (Exn.to_string exn))
    (let open Ui_effect.Let_syntax in
     let%bind () = Effect.after (Time_ns.Span.of_int_ms (-5)) in
     Ui_effect.of_thunk (fun () -> neg := true));
  pump_until ~label:"negative-clamp" ~ready:(fun () -> !neg);
  printf "after (-5 ms) resolved: %b\n" !neg;
  (* The frame request survives a raising continuation (the Important's other half):
     performed with a re-raising on_exn, Bonsai_driver's production shape, so the raise
     comes back out of [respond_to] -- and [hits] still moves, because the resolver falls
     through to the frame request after logging. The log line lands via the same stderr
     pointing the driver block uses. *)
  let before = !hits in
  printf "%!";
  let saved_stderr = Caml_unix.dup Caml_unix.stderr in
  Caml_unix.dup2 Caml_unix.stdout Caml_unix.stderr;
  (* The printing pins the ROUTE: the raise reaches the perform-time on_exn first (the
     driver's is Bonsai_driver's re-raise, whose [Reraised] wrapper the block above's log
     line shows), and only its re-raise brings it out of respond_to to the resolver. *)
  Ui_effect.Expert.handle
    ~on_exn:(fun exn ->
      printf "perform-time on_exn saw: %s\n%!" (Exn.to_string exn);
      raise exn)
    (let open Ui_effect.Let_syntax in
     let%bind () = Effect.on_idle in
     let%bind () = Ui_effect.of_thunk (fun () -> printf "pre-boom-2 reached\n%!") in
     Ui_effect.of_thunk (fun () -> failwith "boom under a re-raising on_exn"));
  pump_until ~label:"raise-still-requests" ~ready:(fun () -> !hits > before);
  Out_channel.flush stderr;
  Caml_unix.dup2 saved_stderr Caml_unix.stderr;
  Caml_unix.close saved_stderr;
  printf "frame requested despite the raise: %b\n" (!hits > before);
  For_runtime.unregister reg2;
  printf "done\n"
;;
