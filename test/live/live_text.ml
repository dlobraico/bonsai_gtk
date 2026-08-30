open! Core
open Bonsai_gtk_vtree
open Bonsai.Let_syntax
module Glib = Bonsai_gtk.Private.Gtk_import.Glib
module Gobject = Bonsai_gtk.Private.Gtk_import.Gobject
module Live_tree = Bonsai_gtk.Private.Live_tree
module P = Bonsai_gtk.Private.Patcher
module Scheduler = Bonsai_gtk.Private.Scheduler
module Signals = Bonsai_gtk.Private.Signals
module W = Bonsai_gtk.Private.Gtk_import.W

let cast = Bonsai_gtk.Private.Gtk_import.cast

(* The window's one child, re-read through the [live] the patcher last handed back:
   [patch] returns a fresh record whenever the kind changes, and the widget is only ever
   reachable through the record held now. *)
let child_live (live : P.live) : P.live =
  match live.children with
  | Single (Some c) -> c
  | No_children | Single None | List _ | Slots _ -> assert false
;;

let child live = (child_live live).P.widget
let buffer live = W.Text_view.get_buffer (cast (child live))

(* Every read in this file goes through the same two calls the impl uses, for the reason
   the impl documents: there is no whole-buffer [get_text] in the binding. *)
let read_buffer b =
  let a, z = W.Text_buffer.get_bounds b in
  W.Text_buffer.get_text b a z true
;;

let read live = read_buffer (buffer live)
let cursor live = W.Text_buffer.get_cursor_position (buffer live)

(* Type at the caret, the way a user does -- not [set_text], which is the library's own
   call and would prove nothing about a buffer the library did not write. *)
let type_at_cursor live text = W.Text_buffer.insert_at_cursor (buffer live) text (-1)

let place_cursor live offset =
  let b = buffer live in
  W.Text_buffer.place_cursor b (W.Text_buffer.get_iter_at_offset b offset)
;;

let drain () =
  while Glib.Main.pending () do
    ignore (Glib.Main.iteration false : bool)
  done
;;

let ctx_of scheduler ~scheduled =
  P.create_ctx
    ~signals:
      { schedule = (fun _ -> incr scheduled)
      ; in_patch = (fun () -> Scheduler.in_patch scheduler)
      ; on_exn =
          (fun ~node_path exn -> printf "EXN at %s: %s\n" node_path (Exn.to_string exn))
      }
    ~on_window_created:(fun _ -> ())
;;

(* ------------------------------------------------------------------------------------ *)

(* 1. The props, and 2-4: the controlled buffer and its caret. *)
let () =
  ignore (Ocgtk_gtk.GMain.init () : string array);
  let scheduled = ref 0 in
  let scheduler = Scheduler.create ~run_frame:(fun () -> ()) in
  let ctx = ctx_of scheduler ~scheduled in
  (* 1. Every prop the node carries, none of them GTK's default, so the dump shows all of
        them at once. The text is short enough to survive [Live_tree]'s truncation. *)
  let styled =
    Node.window
      ~title:"text"
      (Node.text_view
         ~attrs:[ Attr.on_changed (fun _ -> Ui_effect.Ignore) ]
         ~wrap:Word_char
         ~editable:false
         ~monospace:true
         ~cursor_visible:false
         ~accepts_tab:false
         ~left_margin:6
         ~right_margin:7
         ~top_margin:8
         ~bottom_margin:9
         ~text:"a styled note"
         ())
  in
  let live = P.mount ctx ~path:"root" ~is_root:true styled in
  print_s (Live_tree.dump live.widget);
  (* Each prop moved back to GTK's own: the dump drops all of them, which is the half a
     print of the set values cannot show. *)
  let plain ~text =
    Node.window
      ~title:"text"
      (Node.text_view ~attrs:[ Attr.on_changed (fun _ -> Ui_effect.Ignore) ] ~text ())
  in
  let live = P.patch ctx ~path:"root" ~is_root:true live (plain ~text:"a styled note") in
  print_s (Live_tree.dump live.widget);
  (* A count of [changed] emissions on the buffer is how every "did the patch write"
     question below is answered: GTK emits it for the library's own writes too -- twice
     for a [set_text] over non-empty text, once over empty -- which is exactly why the
     reentrancy guard exists. The handler is the test's own and is never disconnected; the
     buffer outlives it. *)
  let writes = ref 0 in
  let (_ : Gobject.Signal.handler_id) =
    W.Text_buffer.on_changed (buffer live) ~callback:(fun () -> incr writes)
  in
  let observe label live node =
    let writes_before = !writes
    and scheduled_before = !scheduled in
    let live =
      Scheduler.with_patch_guard scheduler (fun () ->
        P.patch ctx ~path:"root" ~is_root:true live node)
    in
    printf
      "%s: text=%S cursor=%d (the patch wrote: %b, reached Bonsai: %d)\n"
      label
      (read live)
      (cursor live)
      (!writes > writes_before)
      (!scheduled - scheduled_before);
    live
  in
  (* 2. The controlled write. The "user" types at the caret, outside any patch; the model
     still says what it said last frame, so [update] is skipped and only [reassert] is
     left to put the buffer back (spec §6.5). *)
  place_cursor live 1;
  type_at_cursor live "XY";
  printf "after typing: text=%S cursor=%d\n" (read live) (cursor live);
  let live = observe "model wins" live (plain ~text:"a styled note") in
  (* 3. The caret. Put it in the middle and have the model rewrite the text to something
     of the same length: the offset is saved as a character offset across the write and
     survives it. This is the case the policy is right about. *)
  place_cursor live 5;
  let live = observe "same-length rewrite" live (plain ~text:"A STYLED NOTE") in
  (* Then a rewrite to something shorter than the caret's offset. GTK clamps the restored
     offset to the end of the new text rather than raising, which is the right answer when
     the model shortened the text. *)
  place_cursor live 11;
  let live = observe "shorter rewrite" live (plain ~text:"short") in
  (* 4. The echo. The model renders text the buffer already holds: nothing is written and
     the caret does not move, which is the whole of what "controlled" costs when the model
     agrees. *)
  place_cursor live 2;
  let live = observe "echo is a no-op" live (plain ~text:"short") in
  (* And an idle frame -- the physically same node, through [reassert_only], which is what
     [Driver.frame] runs sixty times a second when nothing changed. *)
  let writes_before = !writes in
  for _ = 1 to 10 do
    Scheduler.with_patch_guard scheduler (fun () ->
      P.reassert_only ctx ~path:"root" live;
      P.run_fixups ctx)
  done;
  printf
    "ten idle frames wrote: %d (text=%S cursor=%d)\n"
    (!writes - writes_before)
    (read live)
    (cursor live);
  (* 5. The reentrancy case. A programmatic write emits [changed] on the *buffer*,
     synchronously, from inside the patch -- the first signal in this library on a
     long-lived GObject that is not the widget to go through the [in_patch] guard. Nothing
     may reach Bonsai from there (spec §4.4). *)
  let scheduled_before = !scheduled in
  let live = observe "model rewrites" live (plain ~text:"rewritten from the model") in
  printf "reached Bonsai across every patch above: %d\n" (!scheduled - scheduled_before);
  (* Outside a patch the same signal does reach Bonsai, which is what makes the line above
     a guard rather than a broken connection. *)
  let scheduled_before = !scheduled in
  Gobject.Signal.emit_by_name (buffer live) ~name:"changed";
  printf
    "a changed emitted outside a patch reaches Bonsai: %d\n"
    (!scheduled - scheduled_before);
  (* 6. Teardown disconnects from the *buffer*, which is the claim M1's fix wave widened
     [Signals.connection] to make and the first test in this library that can catch it
     going wrong. The handles below are taken before the destroy: the buffer wrapper keeps
     the [GtkTextBuffer] alive across it, and the child's [live] record carries the slots.

     Two emissions, because [destroy] protects this twice over and only the second half is
     what is under test here. It empties the slots first (so that a signal GTK emits while
     a subtree is being torn down cannot reach a stale handler) and *then* disconnects --
     and an emptied slot makes a still-connected callback inert, so the first emission
     below would read 0 whether or not the disconnect named the right object. Verified by
     experiment, not by reading: with [connect] changed to name the widget, this file's
     output was byte-identical.

     So the slot is deliberately re-armed after the destroy, which isolates the
     disconnect. [armed] is printed first, because a re-arm that quietly did nothing would
     make the line below vacuous in exactly the way the line above it is.

     What a wrong disconnect does, confirmed against GLib 2.x: handler ids come from a
     single global counter, so [g_signal_handler_disconnect (view, buffer_id)] finds no
     such handler on the view, logs a GLib critical, and leaves the buffer's handler
     connected -- it cannot hit an unrelated handler that happens to share the number,
     which is the worse outcome [signals.mli] warns about and which a per-instance counter
     would allow. Connected, the callback would fire here and schedule. *)
  let orphan = buffer live in
  let orphan_slots = (child_live live).P.slots in
  let orphan_attrs = (child_live live).P.node.attrs in
  P.destroy ctx live;
  let scheduled_before = !scheduled in
  Gobject.Signal.emit_by_name orphan ~name:"changed";
  printf
    "a changed emitted on the destroyed view's buffer reaches Bonsai: %d\n"
    (!scheduled - scheduled_before);
  Signals.update_slots orphan_slots orphan_attrs;
  printf
    "slots re-armed after the destroy: %s\n"
    (Sexp.to_string [%sexp (Signals.armed orphan_slots : Attr.Name.t list)]);
  let scheduled_before = !scheduled in
  Gobject.Signal.emit_by_name orphan ~name:"changed";
  printf
    "with the slot re-armed, an emission on that buffer reaches Bonsai: %d\n"
    (!scheduled - scheduled_before)
;;

(* ------------------------------------------------------------------------------------ *)

(* The event attrs a text view cannot emit, rejected at mount. [On_activate] is the one
   worth having here: an entry has it and a text view does not, so it is the line a reader
   copies across from an entry and the one that would otherwise be silently inert. *)
let () =
  let scheduled = ref 0 in
  let scheduler = Scheduler.create ~run_frame:(fun () -> ()) in
  let ctx = ctx_of scheduler ~scheduled in
  List.iter
    [ Attr.on_activate Ui_effect.Ignore
    ; Attr.on_search_changed (fun _ -> Ui_effect.Ignore)
    ]
    ~f:(fun attr ->
      match
        P.mount
          ctx
          ~path:"root"
          ~is_root:true
          (Node.window ~title:"bad" (Node.text_view ~attrs:[ attr ] ~text:"" ()))
      with
      | (_ : P.live) -> print_endline "BUG: an entry-only attr on a text view accepted"
      | exception Invalid_argument msg -> printf "rejected: %s\n" msg)
;;

(* ------------------------------------------------------------------------------------ *)

(* [get_buffer] is a transfer-none return, and its stub does sink -- checked in
   [ml_text_view_gen.c] before a line of this widget was written, on the rule
   [docs/m1-backlog.md] states: read the stub, not the GIR. The wrapper's finaliser
   unconditionally unrefs, so a stub that had *not* sunk would hand out one unbalanced
   unref per call, and a few hundred of them plus a collection would dispose the view's
   own buffer under it.

   This is that experiment. It is not a benchmark and not a timing: five hundred wrappers
   are made and collected, and the claim is that the buffer is still there, still the same
   object, and still holds its text. Flushed per batch, because the failure it guards
   against is a crash -- with the buffer held to exit, a regression prints nothing at all
   and the golden diff says only "got signal SEGV". *)
let () =
  let scheduled = ref 0 in
  let scheduler = Scheduler.create ~run_frame:(fun () -> ()) in
  let ctx = ctx_of scheduler ~scheduled in
  let live =
    P.mount
      ctx
      ~path:"gc"
      ~is_root:true
      (Node.window ~title:"gc" (Node.text_view ~text:"kept" ()))
  in
  (* Taken once and held: the identity every batch below is compared against. *)
  let original = buffer live in
  for batch = 1 to 5 do
    for _ = 1 to 100 do
      ignore (Sys.opaque_identity (buffer live) : W.Text_buffer.t)
    done;
    (* [full_major] rather than [minor]: the wrappers are custom blocks with finalisers,
       and it is the finaliser running that would do the damage. *)
    Gc.full_major ();
    printf
      "gc: after %d get_buffer wrappers + full_major, same buffer %b, text %S\n"
      (batch * 100)
      (Gobject.same original (buffer live))
      (read live);
    Out_channel.flush stdout
  done;
  (* And the frames themselves, which is the shape the other containers' regressions use:
     a hundred idle frames through [reassert_only] and a collection, and the view is still
     patchable afterwards. *)
  for _ = 1 to 100 do
    Scheduler.with_patch_guard scheduler (fun () ->
      P.reassert_only ctx ~path:"gc" live;
      P.run_fixups ctx)
  done;
  Gc.full_major ();
  let live =
    P.patch
      ctx
      ~path:"gc"
      ~is_root:true
      live
      (Node.window ~title:"gc" (Node.text_view ~text:"still patchable" ()))
  in
  print_s (Live_tree.dump live.widget);
  P.destroy ctx live
;;

(* ------------------------------------------------------------------------------------ *)

(* The cost of an idle frame over a large buffer, and the reason the impl caches at all.

   The shape this guards against: [reassert] runs on every patch {i and} on every
   no-change frame through [reassert_only], so whatever it does is paid sixty times a
   second by an application doing nothing. Comparing the model's text against the buffer's
   by reading the buffer back would make that O(len) per frame -- and worse than O(len),
   because the binding's [gtk_text_buffer_get_text] stub copies the string into OCaml and
   never frees the C original (see [docs/m1-backlog.md]): a megabyte of notes open on
   screen would leak a megabyte a frame, 60 MB a second, with the process doing nothing at
   all. Measured on this machine: one whole-buffer read of 1 MB is 0.42 ms, and a
   [String.equal] over the same megabyte is 0.032 ms.

   {b What is asserted is a ratio, not a wall-clock bound}, which is [task-7-review.md]'s
   N1 taken in the form Task 7 settled on: the property under test is that the frame's
   cost does {i not} scale with the size of the buffer, so the same frame is timed over a
   tiny buffer and a megabyte one and the {i ratio} is what the golden gets. Contention
   scales both, so it cancels. With the cache both frames are a pointer comparison and the
   ratio is about 1; reading the buffer back each frame puts it in the hundreds. A bound
   of 5 is an order of magnitude clear of both ends and is not a timing at all.

   The numbers go to stderr, which is not compared, so a failure says how far over it went
   rather than only [false]. *)
let () =
  let bound_ratio = 5.0 in
  (* Twenty thousand rather than the lists bench's two hundred: with the cache in place a
     frame here is under a tenth of a microsecond, and five hundred of them total forty
     microseconds -- a measurement made almost entirely of timer resolution and scheduler
     noise, which showed up as a ratio wandering between 1 and 3 run to run. Twenty
     thousand puts each measurement in the milliseconds, where the ratio is stable. *)
  let frames = 20_000 in
  let scheduled = ref 0 in
  let scheduler = Scheduler.create ~run_frame:(fun () -> ()) in
  let ctx = ctx_of scheduler ~scheduled in
  let idle_frame_ms ~len =
    let text = String.make len 'x' in
    let live =
      P.mount
        ctx
        ~path:"bench"
        ~is_root:true
        (Node.window ~title:"bench" (Node.text_view ~text ()))
    in
    (* The buffer really holds it, which is what stops this timing a [reassert] that has
       quietly stopped doing anything. *)
    printf
      "bench: buffer holds %d characters\n"
      (W.Text_buffer.get_char_count (buffer live));
    let start = Time_ns.now () in
    for _ = 1 to frames do
      Scheduler.with_patch_guard scheduler (fun () ->
        P.reassert_only ctx ~path:"bench" live;
        P.run_fixups ctx)
    done;
    let ms =
      Time_ns.Span.to_ms (Time_ns.diff (Time_ns.now ()) start) /. Int.to_float frames
    in
    P.destroy ctx live;
    ms
  in
  let small = idle_frame_ms ~len:16 in
  let big = idle_frame_ms ~len:1_000_000 in
  let ratio = big /. small in
  printf
    "bench: %d idle frames over 16 and over 1000000 characters, cost ratio under %g: %b\n"
    frames
    bound_ratio
    Float.(ratio < bound_ratio);
  eprintf
    "bench: %.5f ms at 16 chars, %.5f ms at 1 MB, ratio %.2f (bound %g)\n%!"
    small
    big
    ratio
    bound_ratio
;;

(* ------------------------------------------------------------------------------------ *)

(* The whole text, printed by a test rather than by the dump. [Live_tree] truncates a text
   view's text at 60 characters, so the golden cannot pin a long one; this is the block
   that does, and it is here so that a reader of the truncation comment has somewhere to
   be sent. *)
let () =
  let scheduled = ref 0 in
  let scheduler = Scheduler.create ~run_frame:(fun () -> ()) in
  let ctx = ctx_of scheduler ~scheduled in
  let long = String.concat ~sep:" " (List.init 20 ~f:(fun i -> sprintf "word%d" i)) in
  let live =
    P.mount
      ctx
      ~path:"long"
      ~is_root:true
      (Node.window ~title:"long" (Node.text_view ~wrap:Word ~text:long ()))
  in
  printf "long text length: %d\n" (String.length long);
  printf "dump truncates:\n";
  print_s (Live_tree.dump live.widget);
  printf "the buffer holds it in full: %b\n" (String.equal (read live) long);
  (* A multi-byte text, because the caret is saved as a *character* offset and the buffer
     is addressed in characters while OCaml's string is bytes. Three of these characters
     are two bytes each. *)
  let accented = "h\xc3\xa9llo w\xc3\xb6rld \xc3\xa4" in
  let live =
    P.patch
      ctx
      ~path:"long"
      ~is_root:true
      live
      (Node.window ~title:"long" (Node.text_view ~wrap:Word ~text:accented ()))
  in
  printf
    "accented: bytes=%d characters=%d round-trips: %b\n"
    (String.length accented)
    (W.Text_buffer.get_char_count (buffer live))
    (String.equal (read live) accented);
  (* The caret lands on a character boundary, not a byte one: offset 7 is the [w] of
     "wörld", which a byte offset would put in the middle of the [é]. *)
  place_cursor live 7;
  let live =
    P.patch
      ctx
      ~path:"long"
      ~is_root:true
      live
      (Node.window
         ~title:"long"
         (Node.text_view ~wrap:Word ~text:"H\xc3\x89LLO W\xc3\x96RLD \xc3\x84" ()))
  in
  printf "accented rewrite: text=%S cursor=%d\n" (read live) (cursor live);
  P.destroy ctx live
;;

(* ------------------------------------------------------------------------------------ *)

(* The declined edit through a real [Driver.frame], which is the claim the hand-driven
   patches above cannot make. A model that refuses anything over ten characters: when it
   refuses, its state does not move, so the frame Bonsai runs hands back the
   {i physically same node} and is not diffed at all -- [Widget_impl.reassert] is the only
   thing left, and a driver that skipped it would leave the refused text standing in the
   buffer with the model holding something else.

   The whole loop is real: GTK emits [changed] on the buffer, the trampoline schedules the
   handler's effect, the driver's idle runs the frame, and the frame corrects the widget.
   [live_driver.ml] makes this claim for a toggle and [live_lists.ml] for a notebook page;
   this is the one for a buffer, whose signal is not on the widget at all. *)
let () =
  let seen = ref [] in
  let time_source = Bonsai.Time_source.create ~start:Time_ns.epoch in
  let d =
    Bonsai_gtk.Expert.Driver.create
      ~time_source
      ~on_window_created:(fun _ -> ())
      (fun (graph @ local) ->
        let text, set_text = Bonsai.state "" graph in
        let%arr text and set_text in
        Node.window
          ~title:"notes"
          (Node.text_view
             ~attrs:
               [ Attr.on_changed (fun s ->
                   seen := s :: !seen;
                   if String.length s <= 10 then set_text s else Ui_effect.Ignore)
               ]
             ~wrap:Word_char
             ~text
             ()))
  in
  Bonsai_gtk.Expert.Driver.frame d;
  let driven () =
    let root = Option.value_exn (Bonsai_gtk.Expert.Driver.root_widget d) in
    List.hd_exn (Bonsai_gtk.Private.Gtk_import.widget_children root)
  in
  let driven_buffer () = W.Text_view.get_buffer (cast (driven ())) in
  let driven_text () = read_buffer (driven_buffer ()) in
  let type_ text = W.Text_buffer.insert_at_cursor (driven_buffer ()) text (-1) in
  (* The mount happened inside a real frame, so the [changed] GTK emitted while the
     (empty) text was written was swallowed by the guard. *)
  printf "driver, after mount: %S (handler saw %d)\n" (driven_text ()) (List.length !seen);
  type_ "ok";
  (* Printed before the drain as well as after: the emission arms the driver's idle, and
     by the time the loop is handed back the frame it armed has already run -- so without
     this line an accepted edit would be indistinguishable from one that never landed. *)
  printf "driver, user typed, before the frame: %S\n" (driven_text ());
  drain ();
  printf "driver, after the frame the edit armed: %S\n" (driven_text ());
  (* Now the refusal. Fourteen characters reach the handler, the model keeps its "ok", and
     the frame it runs is a no-diff one -- so [reassert] is the only thing that can put
     the buffer back, and it must. *)
  type_ " far too long";
  printf "driver, user typed too much, before the frame: %S\n" (driven_text ());
  drain ();
  printf
    "driver, after the frame the refusal armed: %S (handler saw %s)\n"
    (driven_text ())
    (Sexp.to_string [%sexp (List.rev !seen : string list)]);
  (* One more frame, with nothing having happened: the correction above is not a loop.
     [reassert] compares against the cache before it writes, so this frame does nothing at
     all -- and the handler sees nothing new, which is what says the correcting write did
     not feed itself back in. *)
  let before = List.length !seen in
  Bonsai_gtk.Expert.Driver.frame d;
  drain ();
  printf
    "driver, one more frame: %S (handler saw %d more)\n"
    (driven_text ())
    (List.length !seen - before);
  Bonsai_gtk.Expert.Driver.stop d
;;
