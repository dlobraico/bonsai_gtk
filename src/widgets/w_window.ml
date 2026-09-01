open! Core
open Bonsai_gtk_vtree
open Gtk_import

(* The controlled half of [~transient_for], called from the fixup queue with the widget
   the patcher resolved the key to (or [None] for a node that dropped the prop). Compared
   against GTK's own read-back -- [get_transient_for] exists, so no cache is kept (the
   fact table's Window row) -- and written only on a difference, which is the whole of the
   controlled-prop discipline: a parked frame costs one getter. *)
let apply_transient_for (w : Widget.t) ~(desired : Widget.t option) =
  let win : W.Window.t = cast w in
  let current = W.Window.get_transient_for win in
  let desired = Option.map desired ~f:(fun d : W.Window.t -> cast d) in
  let differs =
    match current, desired with
    | None, None -> false
    | Some a, Some b -> not (Gobject.same a b)
    | Some _, None | None, Some _ -> true
  in
  if differs then W.Window.set_transient_for win desired
;;

(* The close ruling (Task 8, the architecture bullet): the runtime ALWAYS answers GTK
   "handled", so the X button never destroys a window behind the patcher's back -- a
   window closes when, and only when, the model stops rendering its node. The two rejected
   alternatives (allow-and-desync, allow-and-hope-the-app-quits) both leave the shadow
   tree describing a window GTK has destroyed.

   The spec is a [Payload] because GTK reads the return synchronously ([close-request]
   joins [key-pressed] under the Global Constraints' rule), but the [bool] GTK sees is
   produced by the wrapper below and is constant [true]: what flows back through the
   trampoline is only whether anybody heard. [declined = `Unhandled] therefore reaches the
   wrapper on the three no-handler paths (empty slot, in-patch emission, a handler that
   raised), and the wrapper reports the first of them once per window -- the [reported]
   ref is per-connection, and [connect] runs once per widget. The line's wording claims
   only "unhandled": the usual reason is no armed handler, but the raised-handler path
   (already reported via [on_exn]) and an in-patch emission reach it too, so naming
   no-handler as {i the} cause would misstate two of the three. A once-latched stderr line
   rather than [ctx.report], because the trampoline has no node path and [Signals.ctx] no
   reporting channel (the mli of [Attr.on_close_request] says so) -- and swallow-guarded,
   because this frame was called from C and an [Out_channel] raise (EPIPE on stderr, say)
   must not cross into it, the trampoline's own absolute rule. *)
let close_request : Signals.spec =
  Payload
    { attr = Attr.Name.On_close_request
    ; connect =
        (fun w ~callback ->
          let win : W.Window.t = cast w in
          let reported = ref false in
          Signals.connected
            win
            (W.Window.on_close_request win ~callback:(fun () ->
               (match callback () with
                | `Handled -> ()
                | `Unhandled ->
                  if not !reported
                  then (
                    reported := true;
                    try
                      eprintf
                        "bonsai_gtk: a close request went unhandled; the window stays \
                         open -- a window closes when its node leaves the tree (arm \
                         Attr.on_close_request to hear the request)\n\
                         %!"
                    with
                    | _ -> ()));
               (* The veto, on every path. *)
               true)))
    ; fire =
        (fun _w attr () ->
          match (attr :> Attr.Private.t) with
          | On_close_request handler -> `Handled, Some (handler ())
          | _ -> `Handled, None)
    ; declined = `Unhandled
    }
;;

let impl : Widget_impl.t =
  { name = "Window"
  ; create =
      (fun (kind : Kind.t) ->
        match kind with
        | Window { title; default_size; transient_for = _; modal; resizable } ->
          (* [transient_for] is deliberately not applied here: it names a sibling window
             that may not exist yet, so the patcher resolves and applies it from the fixup
             queue once the whole list does (see [apply_transient_for]). *)
          let window = W.Window.new_ () in
          Widget_impl.batch
            (window :> Widget.t)
            (fun () ->
              W.Window.set_title window title;
              Option.iter default_size ~f:(fun (width, height) ->
                W.Window.set_default_size window width height);
              if modal then W.Window.set_modal window true;
              if not resizable then W.Window.set_resizable window false);
          (window :> Widget.t)
        | k -> Widget_impl.wrong_kind "Window" k)
  ; update =
      (fun w ~(old : Kind.t) (new_ : Kind.t) ->
        match old, new_ with
        | Window old, Window new_ ->
          Widget_impl.batch w (fun () ->
            if not (Option.equal String.equal old.title new_.title)
            then W.Window.set_title (cast w) new_.title;
            if not (Bool.equal old.modal new_.modal)
            then W.Window.set_modal (cast w) new_.modal;
            if not (Bool.equal old.resizable new_.resizable)
            then W.Window.set_resizable (cast w) new_.resizable;
            (* [transient_for] is the fixup queue's on every pass, never a diffed write. *)
            (* GTK has no way to clear a default size, so [None] leaves the current one
               alone rather than fighting the window manager. *)
            match new_.default_size with
            | Some (width, height)
              when not
                     (Option.equal [%equal: int * int] old.default_size new_.default_size)
              -> W.Window.set_default_size (cast w) width height
            | _ -> ())
        | _, k -> Widget_impl.wrong_kind "Window" k)
  ; reassert = None
  ; signals = [ close_request ]
  ; children =
      Widget_impl.Single { set = (fun w child -> W.Window.set_child (cast w) child) }
  }
;;
