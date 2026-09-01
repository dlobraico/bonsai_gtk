open! Core
open Bonsai_gtk_vtree
include Ui_effect

(* One application per process: [start] holds the GLib main loop for its whole call, so
   there is never more than one live at a time and a single cell is enough. [quit] reads
   it when the effect is *performed* rather than when it is built, which is what lets an
   application put [Effect.quit] in an attr before [start] has run. *)
let app : Gtk_import.W.Application.t option ref = ref None

let quit =
  of_thunk (fun () ->
    match !app with
    | Some app -> Ocgtk_gio.Gio.Wrappers.Application.quit app
    | None -> eprintf "bonsai_gtk: Effect.quit outside of Bonsai_gtk.start\n%!")
;;

module For_start = struct
  let set_app a =
    if Option.is_some !app
    then
      eprintf
        "bonsai_gtk: Bonsai_gtk.start called while another application is still running. \
         Effect.quit will now quit the new one; only one start per process is supported.\n\
         %!";
    app := Some a
  ;;

  let clear_app () = app := None
end

(* --- the runtime hooks (M3 Task 9): what a performed effect can reach with no driver in
   hand. The [app] cell's shape, generalised: one process-global registration, read at
   perform time. Registered by [Loop.start]'s activate and by [Embed.create]; every hook
   closes over a driver, which is why {!Driver.stop} drops them through the thunk those
   two register with [Driver.set_effect_hooks_drop] -- a hook left behind would keep a
   stopped driver's whole graph alive, the [on_root_widget_changed] leak shape
   (docs/m2-backlog.md:708-717).

   Registration is last-wins with an identity-guarded unregister, exactly the stack
   registry's discipline: two embeds may be live at once, and the first one's stop must
   not take the second one's hooks down. *)
module For_runtime = struct
  type hooks =
    { request_frame : unit -> unit
    ; lookup_window : (Key.t -> Gtk_import.Widget.t option) option
    (** [None] under [Expert.embed], which has no windows: {!Window.present} then logs and
        resolves, matching {!quit}'s outside-[start] behaviour. *)
    ; context_widget : unit -> Gtk_import.Widget.t option
    }

  type registration = unit ref

  let current : (registration * hooks) option ref = ref None

  let register ?lookup_window ~request_frame ~context_widget () =
    let id = ref () in
    current := Some (id, { request_frame; lookup_window; context_widget });
    id
  ;;

  let unregister id =
    match !current with
    | Some (cur, _) when phys_equal cur id -> current := None
    | Some _ | None -> ()
  ;;
end

let hooks () = Option.map !For_runtime.current ~f:snd

(* The async pattern, written once and reused by Task 10's dialogs: the effect is built
   with [Ui_effect.Private.make], its evaluator arms a GLib source when the effect is
   {i performed}, and the source's callback ends up here -- resolving the effect's
   continuation synchronously ([Ui_effect.Expert.handle]; any injects it performs enqueue
   into the Bonsai graph exactly as a signal handler's would) and then asking the
   registered frame-requester for the frame that will flush them.

   {b [respond_to callback ()] IS the continuation run}: in this ui_effect, [on_response]
   invokes the perform-time callback chain before returning [Ignore], so by the time
   [Expert.handle] is applied there is nothing left to evaluate. Two consequences, both
   load-bearing (task-9-review Important 1). A raise in application bind code routes to
   the {i perform-time} on_exn -- for every production perform path that is
   [Bonsai_driver]'s, which re-raises -- and so arrives here
   {i out of [respond_to] itself}; the inner [try] below is what catches it, logs it by
   name (report-then-swallow, the codebase's shape everywhere else), and
   {b still falls through to the frame request}: injects that landed before the raise
   deserve their flushing frame. [Expert.handle]'s own [~on_exn] stays as a backstop for a
   ui_effect whose [respond_to] defers.

   This runs on a C-called frame, so nothing may escape: every log write is
   swallow-guarded and the whole body is wrapped once more as a backstop.

   The frame-requester can legitimately be gone: [Driver.stop] with an [after] still in
   flight drops the hooks, and the timeout fires anyway. The contract is log-and-resolve
   -- the continuation still runs (a ref it writes still moves; injects land in a graph
   nothing will read), a line says the frame is not coming, and nothing raises. *)
let resolve_from_glib ~name callback =
  let log_exn exn =
    try
      eprintf "bonsai_gtk: exception resolving Effect.%s: %s\n%!" name (Exn.to_string exn)
    with
    | _ -> ()
  in
  try
    (try
       Ui_effect.Expert.handle
         ~on_exn:log_exn
         (Ui_effect.Private.Callback.respond_to callback ())
     with
     | exn -> log_exn exn);
    match hooks () with
    | Some h -> h.request_frame ()
    | None ->
      (* "No hooks at all", not "this effect's driver is gone": if a {i later} driver's
         hooks are current when an orphaned effect fires, the arm above requests a frame
         on that driver instead and prints nothing -- harmless ([request_frame] is guarded
         and cheap; the injects went to the dead graph), and single-slot by design (the
         mli's For_runtime paragraph). *)
      (try
         eprintf
           "bonsai_gtk: Effect.%s resolved after the runtime's hooks were dropped \
            (Driver.stop); no frame was requested\n\
            %!"
           name
       with
       | _ -> ())
  with
  | _ -> ()
;;

(* [Glib.Timeout.add ?prio ~ms ~callback ()] against [Glib.Idle.add ?prio fn]: the
   label/terminator asymmetry is the binding's (fact table), quoted here so nobody
   rediscovers it. Both callbacks return [false] -- one-shot sources. *)
let after span =
  Ui_effect.Private.make ~request:() ~evaluator:(fun callback ->
    let ms = Int.max 0 (Time_ns.Span.to_int_ms span) in
    ignore
      (Glib.Timeout.add
         ~ms
         ~callback:(fun () ->
           resolve_from_glib ~name:"after" callback;
           false)
         ()
       : Glib.Timeout.id))
;;

let on_idle =
  Ui_effect.Private.make ~request:() ~evaluator:(fun callback ->
    ignore
      (Glib.Idle.add (fun () ->
         resolve_from_glib ~name:"on_idle" callback;
         false)
       : Glib.Idle.id))
;;

module Clipboard = struct
  (* Through [context_widget] because a clipboard belongs to a display and a display is
     reached from a widget ([Gdk.Display.get_default] is a namespace function ocgtk does
     not bind -- fact table). The write is [Clipboard.set_value] with a string [GValue]:
     [set_text] is a C macro the binding cannot see. *)
  let set_text text =
    of_thunk (fun () ->
      match Option.bind (hooks ()) ~f:(fun h -> h.context_widget ()) with
      | Some w ->
        let value = Gtk_import.Gobject.Value.create Gtk_import.Gobject.Type.string in
        Gtk_import.Gobject.Value.set_string value text;
        Gtk_import.Gdk.Clipboard.set_value (Gtk_import.W.Widget.get_clipboard w) value
      | None ->
        eprintf
          "bonsai_gtk: Effect.Clipboard.set_text outside a running Bonsai_gtk app; \
           nothing was written\n\
           %!")
  ;;
end

module Window = struct
  (* Synchronous, not [Private.make]-shaped: [present] is one GTK call on a window the
     runtime already holds. Every miss logs and resolves rather than raising -- an effect
     is a value a test may perform, and {!quit} set the precedent. *)
  let present key =
    of_thunk (fun () ->
      match hooks () with
      | None ->
        eprintf "bonsai_gtk: Effect.Window.present outside a running Bonsai_gtk app\n%!"
      | Some { lookup_window = None; _ } ->
        eprintf
          "bonsai_gtk: Effect.Window.present under Expert.embed, which has no windows to \
           present\n\
           %!"
      | Some { lookup_window = Some lookup; _ } ->
        (match lookup key with
         | Some w -> Gtk_import.W.Window.present (Gtk_import.cast w)
         | None ->
           eprintf
             "bonsai_gtk: Effect.Window.present: no window is keyed %S (the key must \
              name a child of the root Node.windows)\n\
              %!"
             (key : Key.t)))
  ;;
end
