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
    ()
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
  (* [Wrap_mode.Char] on its own, because it is the one arm of the enum nothing else in
     the suite reaches -- [None_] by absence, [Word] and [Word_char] in the blocks below
     and in the gallery -- so [| Char -> `WORD] would otherwise pass the whole gate
     (task-9-review.md M4). *)
  let live =
    P.patch
      ctx
      ~path:"root"
      ~is_root:true
      live
      (Node.window
         ~title:"text"
         (Node.text_view
            ~attrs:[ Attr.on_changed (fun _ -> Ui_effect.Ignore) ]
            ~wrap:Char
            ~text:"a styled note"
            ()))
  in
  print_s (Live_tree.dump live.widget);
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
  (* Then a rewrite to something shorter than the caret's offset. What this line shows is
     that [get_iter_at_offset] past the end does not raise -- and only that. It cannot
     show the clamp: GTK clamps to the end of the new text, which is exactly where not
     restoring the caret at all would leave it, so the two are indistinguishable by
     construction and deleting the restore leaves this line byte-identical. The restore
     itself is pinned by the three lines around it, each of which moves to 13 if it is
     removed (task-9-review.md M2). *)
  place_cursor live 11;
  let live = observe "shorter rewrite" live (plain ~text:"short") in
  (* 4. The echo. The model renders text the buffer already holds: nothing is written and
     the caret does not move, which is the whole of what "controlled" costs when the model
     agrees.

     [place_cursor] is what sets the caret here, so the selection claim below is made
     separately rather than by selecting a range first -- a [select_range] would move the
     caret to its second iter and take this line's [cursor=2] with it. *)
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
  (* The selection, which is documented in two places and until now tested in none
     (task-9-review.md M5). [set_text] collapses a selection even when the text it writes
     is identical -- measured -- so "the echo writes nothing" is not a cost saving, it is
     what keeps a selection standing under a model that echoes as you type. That is a
     stronger promise than [Node.text_view]'s doc makes, and it is the case an application
     actually hits. The write two blocks down is what drops it. *)
  let selected () =
    let held, _, _ = W.Text_buffer.get_selection_bounds (buffer live) in
    held
  in
  W.Text_buffer.select_range
    (buffer live)
    (W.Text_buffer.get_iter_at_offset (buffer live) 1)
    (W.Text_buffer.get_iter_at_offset (buffer live) 3);
  printf "selection held: %b\n" (selected ());
  let live = observe "echo again, with a selection standing" live (plain ~text:"short") in
  printf "selection after an echo: %b\n" (selected ());
  (* 5. The reentrancy case. A programmatic write emits [changed] on the *buffer*,
     synchronously, from inside the patch -- the first signal in this library on a
     long-lived GObject that is not the widget to go through the [in_patch] guard. Nothing
     may reach Bonsai from there (spec §4.4). *)
  let scheduled_before = !scheduled in
  let live = observe "model rewrites" live (plain ~text:"rewritten from the model") in
  printf "reached Bonsai across every patch above: %d\n" (!scheduled - scheduled_before);
  printf "selection after a write: %b\n" (selected ());
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
  let refusals = ref 0 in
  let scheduler = Scheduler.create ~run_frame:(fun () -> ()) in
  (* A [report] of its own, counted rather than printed: the default would put a line on
     stderr in the middle of the gate's output, and the count is a better assertion anyway
     -- it is what says the refusal really happened and happened exactly once, which is
     the state the third measurement claims to be timing. *)
  let ctx =
    P.create_ctx
      ~report:(fun ~node_path:_ _ -> incr refusals)
      ~signals:
        { schedule = (fun _ -> incr scheduled)
        ; in_patch = (fun () -> Scheduler.in_patch scheduler)
        ; on_exn =
            (fun ~node_path exn -> printf "EXN at %s: %s\n" node_path (Exn.to_string exn))
        }
      ~on_window_created:(fun _ -> ())
      ()
  in
  (* One measurement: mount a view holding [len] characters, optionally park it on a
     refused write, and time [frames] idle frames through the fixup queue.

     [~refused:true] is the case the first two measurements structurally cannot reach
     (task-9-review.md R1). The refused text is the {i same length} as the one the buffer
     holds and differs only in its last byte, which is the worst case on purpose:
     [String.equal] short-circuits on length, so a refusal whose text is a different
     length from the buffer's costs nothing to notice and would flatter this. Same length,
     one byte apart, is a full memcmp -- and a log tail or a file preview re-rendering a
     similar-length document is exactly where the lengths coincide. *)
  let idle_frame_ms ~len ~refused =
    let text = String.make len 'x' in
    let live =
      P.mount
        ctx
        ~path:"bench"
        ~is_root:true
        (Node.window ~title:"bench" (Node.text_view ~text ()))
    in
    let live =
      if not refused
      then live
      else (
        let unstorable = String.make (len - 1) 'x' ^ "\xe9" in
        Scheduler.with_patch_guard scheduler (fun () ->
          P.patch
            ctx
            ~path:"bench"
            ~is_root:true
            live
            (Node.window ~title:"bench" (Node.text_view ~text:unstorable ()))))
    in
    (* The buffer really holds the storable text -- in the refused case because the write
       was refused, which is the state under test. Printed, because it is also what stops
       this timing a [reassert] that has quietly stopped doing anything. *)
    printf
      "bench: %s, buffer holds %d characters (refusals so far %d)\n"
      (if refused then "parked on a refused write" else "settled")
      (W.Text_buffer.get_char_count (buffer live))
      !refusals;
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
  let small = idle_frame_ms ~len:16 ~refused:false in
  let big = idle_frame_ms ~len:1_000_000 ~refused:false in
  let big_refused = idle_frame_ms ~len:1_000_000 ~refused:true in
  (* Still one, after twenty thousand frames parked on it: the memo is consulted before
     anything else, so the frames after the refusal neither compare nor report. *)
  printf "bench: refusals reported across every frame above: %d\n" !refusals;
  let ratio = big /. small in
  let refused_ratio = big_refused /. big in
  printf
    "bench: %d idle frames over 16 and over 1000000 characters, cost ratio under %g: %b\n"
    frames
    bound_ratio
    Float.(ratio < bound_ratio);
  printf
    "bench: an idle frame parked on a refused 1 MB write, against a settled one, under \
     %g: %b\n"
    bound_ratio
    Float.(refused_ratio < bound_ratio);
  eprintf
    "bench: %.5f ms at 16 chars, %.5f ms at 1 MB, ratio %.2f (bound %g)\n%!"
    small
    big
    ratio
    bound_ratio;
  eprintf
    "bench: %.5f ms parked on a refused 1 MB write, ratio %.2f (bound %g)\n%!"
    big_refused
    refused_ratio
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
  (* The truncation counts characters, not bytes (task-9-review.md M3). This text puts a
     two-byte character astride the 60-byte boundary: a byte prefix would cut it in half
     and the sexp printer would escape the stray continuation byte into the golden. The
     dump below ends on a whole character. *)
  let astride = String.concat [ String.make 59 'x'; "\xc3\xa9"; String.make 20 'y' ] in
  let live =
    P.patch
      ctx
      ~path:"long"
      ~is_root:true
      live
      (Node.window ~title:"long" (Node.text_view ~text:astride ()))
  in
  print_s (Live_tree.dump live.widget);
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

(* ------------------------------------------------------------------------------------ *)

(* Text GTK will not store, which is the case the first round shipped as a documented gap
   and which nothing exercised (task-9-review.md I1).

   Two shapes, and they fail differently. [gtk_text_buffer_set_text] deletes the whole
   buffer and then inserts, and [gtk_text_buffer_emit_insert] has
   [g_return_if_fail (g_utf8_validate (text, len, NULL))] -- so for text that is not valid
   UTF-8 the delete lands and the insert does not, and the buffer ends up {i empty} rather
   than partly written, with a [Gtk-CRITICAL] on stderr. For text with an embedded NUL the
   [-1] length terminates at the NUL, GTK inserts the prefix, and there is no diagnostic
   at all. Measured, both:

   {v
     model text          buffer after an unguarded set_text   diagnostic
     "caf\xe9 latte"     ""                                   Gtk-CRITICAL
     "ab\x00cd"          "ab"                                 none
   v}

   Cached as written, either one makes [holds] answer [true] forever, so the view stays
   wrong for as long as the model asks for the same text -- and under [~editable:false],
   which is both the likeliest source of such text (a log tail, a file preview) and the
   one configuration where no user edit can ever heal it, permanently.

   So the write is refused instead: the buffer keeps what it had, the cache keeps what the
   buffer has, and the patcher reports once with the node's path. The refusal is
   remembered against the text that caused it, so a model that keeps asking pays one
   validation and one message rather than one of each per frame. *)
let () =
  let scheduled = ref 0 in
  let reports = ref [] in
  let scheduler = Scheduler.create ~run_frame:(fun () -> ()) in
  let ctx =
    P.create_ctx
      ~report:(fun ~node_path message -> reports := (node_path, message) :: !reports)
      ~signals:
        { schedule = (fun _ -> incr scheduled)
        ; in_patch = (fun () -> Scheduler.in_patch scheduler)
        ; on_exn =
            (fun ~node_path exn -> printf "EXN at %s: %s\n" node_path (Exn.to_string exn))
        }
      ~on_window_created:(fun _ -> ())
      ()
  in
  let view ~text = Node.window ~title:"bad" (Node.text_view ~editable:false ~text ()) in
  let take_reports () =
    let r = List.rev !reports in
    reports := [];
    Sexp.to_string [%sexp (r : (string * string) list)]
  in
  let live = P.mount ctx ~path:"bad" ~is_root:true (view ~text:"a good note") in
  printf "mounted: %S (reports %s)\n" (read live) (take_reports ());
  let idle live =
    for _ = 1 to 5 do
      Scheduler.with_patch_guard scheduler (fun () ->
        P.reassert_only ctx ~path:"bad" live;
        P.run_fixups ctx)
    done
  in
  let refuse label live text =
    let live =
      Scheduler.with_patch_guard scheduler (fun () ->
        P.patch ctx ~path:"bad" ~is_root:true live (view ~text))
    in
    printf "%s: buffer %S (reports %s)\n" label (read live) (take_reports ());
    idle live;
    (* Five idle frames later: still the previous contents, and not one more message --
       the refusal is remembered against the text, so the frames after it are free. *)
    printf
      "%s, five idle frames later: buffer %S (reports %s)\n"
      label
      (read live)
      (take_reports ());
    live
  in
  let live = refuse "latin-1" live "caf\xe9 latte" in
  let live = refuse "embedded NUL" live "ab\x00cd" in
  (* And the model is not wedged: the next text GTK {i will} take must land. This is the
     line that stops the fix from being "never write again". *)
  let live =
    Scheduler.with_patch_guard scheduler (fun () ->
      P.patch ctx ~path:"bad" ~is_root:true live (view ~text:"caf\xc3\xa9 latte"))
  in
  printf
    "a valid text after two refusals: %S (reports %s)\n"
    (read live)
    (take_reports ());
  (* A second refusal of the *same* text after a valid write in between is a new decision
     and is reported again -- the memory is of a text, not of a widget. *)
  let live = refuse "latin-1 again" live "caf\xe9 latte" in
  P.destroy ctx live;
  (* And at *mount*, which is the likeliest way an application meets this: a read-only
     pane rendering bytes off disk, wrong from the first frame. [create] writes the text
     and [note_interest] reports it, in that order, so the message carries the mounting
     node's path like any other. The view comes up empty rather than wrong-looking,
     because there was nothing there to keep. *)
  let born = P.mount ctx ~path:"born" ~is_root:true (view ~text:"caf\xe9 latte") in
  printf "mounted with unstorable text: %S (reports %s)\n" (read born) (take_reports ());
  P.destroy ctx born
;;

(* ------------------------------------------------------------------------------------ *)

(* The drop-down, which is in this file rather than in [live_lists.ml] because it is not a
   container: its items are props, its selection is an index, and the thing it shares with
   the text view above is a controlled prop that GTK can refuse.

   Everything below turns on one claim:
   {b the GTK model is rebuilt only when the items differ}. Rebuilding a [GtkStringList]
   resets the selection, closes an open popup and re-lays-out the button, so a frame that
   did it unconditionally would make the widget unusable rather than merely slow -- and no
   golden of properties could tell the two implementations apart, because a rebuilt model
   holding the same strings reads identically. So the model's {i GObject identity} is what
   is asserted, which is the one thing that differs. *)
module List_model = Bonsai_gtk.Private.Gtk_import.List_model
module W_drop_down = Bonsai_gtk.Private.W_drop_down

let drop_down live : W.Drop_down.t = cast (child live)
let model live = Option.value_exn (W.Drop_down.get_model (drop_down live))

(* Through the impl's own translation, not a second copy of it here: [-1] and
   [GTK_INVALID_LIST_POSITION] meet in exactly two functions and this is a reader of one. *)
let selected live = W_drop_down.of_gtk (W.Drop_down.get_selected (drop_down live))

let items live =
  let m = model live in
  List.init (List_model.get_n_items m) ~f:(fun i ->
    W.String_object.get_string (cast (Option.value_exn (List_model.get_object m i))))
;;

let picker ?(handler = true) ~items ~selected () =
  Node.window
    ~title:"picker"
    (Node.drop_down
       ~attrs:
         (if handler then [ Attr.on_selected_changed (fun _ -> Ui_effect.Ignore) ] else [])
       ~items
       ~selected
       ())
;;

let () =
  let scheduled = ref 0 in
  let scheduler = Scheduler.create ~run_frame:(fun () -> ()) in
  let ctx = ctx_of scheduler ~scheduled in
  let live =
    P.mount
      ctx
      ~path:"pick"
      ~is_root:true
      (picker ~items:[ "60"; "90"; "120" ] ~selected:1 ())
  in
  (* 1. The props. [Live_tree] prints the items out of the model and the selection as a
        position, and prints no children at all: a [GtkDropDown]'s twenty-odd internal
        widgets are a popover, a search entry and a list view whose item widgets come and
        go with the model, none of which is the application's tree. *)
  print_s (Live_tree.dump live.widget);
  (* Our own count of what GTK really emits, beside the trampoline's. Without it the
     reentrancy claims below would be vacuous: "Bonsai heard nothing" is only interesting
     while GTK is emitting something. *)
  let notifies = ref 0 in
  let (_ : Gobject.Signal.handler_id) =
    Gobject.Signal.connect_simple
      (drop_down live)
      ~name:"notify::selected"
      ~callback:(fun () -> incr notifies)
      ~after:false
  in
  let patch label live node =
    let before = model live in
    let notifies_before = !notifies
    and scheduled_before = !scheduled in
    let live =
      Scheduler.with_patch_guard scheduler (fun () ->
        P.patch ctx ~path:"pick" ~is_root:true live node)
    in
    printf
      "%s: items=%s selected=%d (same model: %b, GTK emitted: %d, reached Bonsai: %d)\n"
      label
      (Sexp.to_string [%sexp (items live : string list)])
      (selected live)
      (Gobject.same before (model live))
      (!notifies - notifies_before)
      (!scheduled - scheduled_before);
    live
  in
  (* 2. The claim, and it goes first because it is the one that would pass silently
     against a wrong implementation. Changing only the selection must not rebuild the
     model. *)
  let live =
    patch "selection alone" live (picker ~items:[ "60"; "90"; "120" ] ~selected:2 ())
  in
  (* And a patch that changes nothing at all -- which is every frame of an application at
     rest -- writes nothing and rebuilds nothing. *)
  let live =
    patch "nothing at all" live (picker ~items:[ "60"; "90"; "120" ] ~selected:2 ())
  in
  (* Nor do idle frames, which do not diff the node at all: [reassert_only] is the whole
     of what a settled application runs, and it must not touch the model. *)
  let before_idle = model live in
  for _ = 1 to 5 do
    Scheduler.with_patch_guard scheduler (fun () ->
      P.reassert_only ctx ~path:"pick" live;
      P.run_fixups ctx)
  done;
  printf
    "five idle frames: same model: %b, selected=%d, reached Bonsai: %d\n"
    (Gobject.same before_idle (model live))
    (selected live)
    !scheduled;
  (* 3. Changing the items rebuilds the model -- a different GObject -- {i and} re-applies
     the selection inside the same patch, so the drop-down is never left showing the item
     GTK's autoselect picked. Read back straight after [P.patch], with no fixup pass in
     between, because nothing about this is deferred. *)
  let live =
    patch "items changed" live (picker ~items:[ "60"; "90"; "120"; "144" ] ~selected:3 ())
  in
  (* The same rebuild with the selection standing still: GTK resets the selection to item
     0 as part of taking the new model (its autoselect again -- not to "nothing", which is
     what a reading of the docs suggests), and [reassert] puts it back in the same frame. *)
  let live =
    patch
      "items changed, selection unchanged"
      live
      (picker ~items:[ "50"; "70" ] ~selected:1 ())
  in
  (* 5. The reentrancy accounting, gathered: every line above emitted [notify::selected]
     for real -- from [set_model] and from [set_selected] both -- and not one of those
     emissions reached Bonsai, because they all happened inside a patch. Nothing is
     deferred here, unlike a [GtkSearchEntry]'s debounced signal, so draining the main
     loop changes nothing either. *)
  drain ();
  printf "after a drain: GTK emitted %d in all, Bonsai heard %d\n" !notifies !scheduled;
  (* 4. The declined choice. The "user" picks item 0 outside any patch, which is a real
     emission and does reach Bonsai; the model then re-renders the index it was already
     rendering, so [Kind.equal_props] is true, [update] is skipped entirely, and
     [Widget_impl.reassert] is the only thing left to put the widget back. *)
  W.Drop_down.set_selected (drop_down live) 0;
  printf "user picked: selected=%d (reached Bonsai: %d)\n" (selected live) !scheduled;
  let live = patch "model declines" live (picker ~items:[ "50"; "70" ] ~selected:1 ()) in
  P.destroy ctx live
;;

(* ------------------------------------------------------------------------------------ *)

(* [~selected:(-1)] over a non-empty list: a state GTK will not hold, treated exactly as
   the text view treats text a [GtkTextBuffer] will not store.

   A [GtkDropDown] selects through an internal [GtkSingleSelection] whose [autoselect] is
   on and which no drop-down method exposes, so [set_selected] with the "nothing" sentinel
   over a non-empty model does nothing at all -- the previous item stays selected and GTK
   does not even emit [notify::selected]. The library writes it once, reads back, sees the
   refusal, reports it with the node's path, and then leaves the widget alone; the model
   is free to ask for something else, and a list that becomes empty makes the same request
   land. *)
let () =
  let scheduled = ref 0 in
  let reports = ref [] in
  let scheduler = Scheduler.create ~run_frame:(fun () -> ()) in
  let ctx =
    P.create_ctx
      ~report:(fun ~node_path message -> reports := (node_path, message) :: !reports)
      ~signals:
        { schedule = (fun _ -> incr scheduled)
        ; in_patch = (fun () -> Scheduler.in_patch scheduler)
        ; on_exn =
            (fun ~node_path exn -> printf "EXN at %s: %s\n" node_path (Exn.to_string exn))
        }
      ~on_window_created:(fun _ -> ())
      ()
  in
  let take_reports () =
    let r = List.rev !reports in
    reports := [];
    Sexp.to_string [%sexp (r : (string * string) list)]
  in
  let idle live =
    for _ = 1 to 5 do
      Scheduler.with_patch_guard scheduler (fun () ->
        P.reassert_only ctx ~path:"none" live;
        P.run_fixups ctx)
    done
  in
  let show label live =
    printf "%s: selected=%d (reports %s)\n" label (selected live) (take_reports ());
    idle live;
    printf
      "%s, five idle frames later: selected=%d (reports %s)\n"
      label
      (selected live)
      (take_reports ())
  in
  let patch live node =
    Scheduler.with_patch_guard scheduler (fun () ->
      P.patch ctx ~path:"none" ~is_root:true live node)
  in
  (* At mount, which is the likeliest way an application meets this: a picker rendered
     before anything has been chosen. The message carries the mounting node's path, like
     every other, and it is emitted from [enqueue_fixups] after [create]. *)
  let live =
    P.mount ctx ~path:"none" ~is_root:true (picker ~items:[ "a"; "b" ] ~selected:(-1) ())
  in
  show "mounted asking for none" live;
  (* Not wedged: the next index GTK {i will} take lands, and clears the refusal. *)
  let live = patch live (picker ~items:[ "a"; "b" ] ~selected:1 ()) in
  show "then item 1" live;
  (* And asking for none again after a write that landed is a new decision, reported again
     -- the refusal is remembered against the index, and every successful write forgets
     it. *)
  let live = patch live (picker ~items:[ "a"; "b" ] ~selected:(-1) ()) in
  show "asking for none again" live;
  (* An empty list is the shape in which "nothing selected" is a state GTK holds: the
     rebuild leaves the widget with no selection of its own, so there is nothing to write
     and nothing to refuse. *)
  let live = patch live (picker ~items:[] ~selected:(-1) ()) in
  show "no items at all" live;
  (* Back to a non-empty list with the same [~selected]. The rebuild forgot the refusal,
     which it must: a model rebuild changes GTK's answer, and remembering across one would
     leave the library sure of something that is no longer true. So this is decided again,
     and reported again. *)
  let live = patch live (picker ~items:[ "a" ] ~selected:(-1) ()) in
  show "items again" live;
  P.destroy ctx live
;;

(* ------------------------------------------------------------------------------------ *)

(* The model wrapper under GC churn, and the reference counts behind it.

   Two separate facts, and only one of them is this library's doing.

   [get_model] is a transfer-none return whose stub reference-sinks before wrapping, which
   is the pairing the wrapper's unconditional unref needs -- so a dump or a test may call
   it in a loop and collect the wrappers without ever disturbing the model the drop-down
   holds. That is the shape that was {i wrong} for [GtkListBox.get_selected_rows] in Task
   6 and cost a segfault, so it is checked here rather than assumed.

   [String_list.new_] is a constructor -- transfer-full -- and its stub reference-sinks
   too, which is one ref too many: [GtkStringList] descends from [GObject] rather than
   [GInitiallyUnowned], so it is not floating and the sink is a plain extra reference that
   the finaliser does not balance. A fresh model therefore reads a reference count of 2
   where it should read 1, and one model is leaked per items change (never per frame). It
   is a generator defect, it is recorded in [docs/m1-backlog.md] for Task 14, and the
   count is pinned here so that the fix is visible in this golden when it lands. *)
let () =
  let scheduled = ref 0 in
  let scheduler = Scheduler.create ~run_frame:(fun () -> ()) in
  let ctx = ctx_of scheduler ~scheduled in
  let fresh = W.String_list.new_ (Some [| "x"; "y" |]) in
  printf
    "a fresh GtkStringList holds %d references (1 is correct; 2 is the stub's extra \
     ref_sink)\n"
    (Gobject.get_ref_count fresh);
  let live =
    P.mount ctx ~path:"gc" ~is_root:true (picker ~items:[ "a"; "b"; "c" ] ~selected:0 ())
  in
  (* Five hundred wrappers around the one model, then a full major collection with every
     one of them unreachable. Under the [get_selected_rows] shape this drops the model's
     count five hundred times and the read below is a use-after-free. *)
  for _ = 1 to 500 do
    ignore
      (Sys.opaque_identity (W.Drop_down.get_model (drop_down live)) : List_model.t option)
  done;
  Gc.full_major ();
  printf
    "after 500 get_model wrappers and a full major: items=%s selected=%d\n"
    (Sexp.to_string [%sexp (items live : string list)])
    (selected live);
  (* And the model the drop-down replaced: the old one is unreachable from OCaml and from
     GTK both, and collecting it must not disturb the new one. *)
  let live =
    Scheduler.with_patch_guard scheduler (fun () ->
      P.patch
        ctx
        ~path:"gc"
        ~is_root:true
        live
        (picker ~items:[ "d"; "e" ] ~selected:1 ()))
  in
  Gc.full_major ();
  printf
    "after a rebuild and a full major: items=%s selected=%d\n"
    (Sexp.to_string [%sexp (items live : string list)])
    (selected live);
  P.destroy ctx live
;;

(* ------------------------------------------------------------------------------------ *)

(* The level bar: four properties, no signals, nothing controlled.

   Its one trap is the write order. [gtk_level_bar_set_min_value] checks nothing about the
   maximum and clamps the value {i up} to the new minimum; [set_max_value] clamps it down.
   So a bar moved from 0-1 to 2-10 by writing the minimum first passes through
   [min=2 max=1] -- GTK accepts it, silently, and this block prints the measurement rather
   than asserting a comment. [w_level_bar.ml] writes whichever bound moves outward first,
   so that state is never entered; it also rewrites the value whenever the bounds moved,
   which is what makes the final state right regardless. *)
let () =
  let scheduled = ref 0 in
  let scheduler = Scheduler.create ~run_frame:(fun () -> ()) in
  let ctx = ctx_of scheduler ~scheduled in
  let bar ?min ?max ?mode ?inverted ~value () =
    Node.window ~title:"levels" (Node.level_bar ?min ?max ?mode ?inverted ~value ())
  in
  let live = P.mount ctx ~path:"bar" ~is_root:true (bar ~value:0.4 ()) in
  print_s (Live_tree.dump live.widget);
  let patch live node =
    let live =
      Scheduler.with_patch_guard scheduler (fun () ->
        P.patch ctx ~path:"bar" ~is_root:true live node)
    in
    print_s (Live_tree.dump live.widget);
    live
  in
  (* The range moving up, which is the order-sensitive direction: the new minimum is above
     the old maximum. *)
  let live = patch live (bar ~min:2. ~max:10. ~value:3. ()) in
  (* And back down, the other direction: the new maximum is below the old minimum. *)
  let live = patch live (bar ~min:0. ~max:1. ~value:0.5 ()) in
  (* Bounds moving with the value standing still, which is the line that shows why the
     value is rewritten whenever a bound moved. [set_min_value 0.8] clamps the live value
     {i up} to 0.8; the rewrite then puts the node's 0.5 back -- and GTK takes it, because
     [gtk_level_bar_set_value] does {i not} clamp, so a level bar can hold a value below
     its minimum but cannot keep one across a bound moving over it. Deleting the
     [old.min <> new_.min] disjunct in [w_level_bar.ml]'s value condition makes the next
     line print [(value 0.8)] -- GTK's number rather than the model's -- which is what
     this case exists to catch. *)
  let live = patch live (bar ~min:0.8 ~max:1. ~value:0.5 ()) in
  let live =
    patch live (bar ~min:0. ~max:5. ~mode:Discrete ~inverted:true ~value:3. ())
  in
  P.destroy ctx live;
  (* What the ordering is defence against, measured on a raw widget rather than claimed in
     a comment: GTK accepts an inverted range in silence, clamps the value up to the
     minimum, and logs nothing at all -- realized, in discrete mode, with a main loop
     running. This is also the measurement behind [Node.level_bar] rejecting a [~min]
     above its [~max]: there is no later diagnostic for it anywhere. *)
  let raw = W.Level_bar.new_ () in
  W.Level_bar.set_value raw 0.5;
  W.Level_bar.set_min_value raw 2.;
  printf
    "raw widget, minimum written first: min=%g max=%g value=%g\n"
    (W.Level_bar.get_min_value raw)
    (W.Level_bar.get_max_value raw)
    (W.Level_bar.get_value raw);
  W.Level_bar.set_max_value raw 10.;
  printf
    "raw widget, maximum written second: min=%g max=%g value=%g (the value the caller \
     asked for is gone)\n"
    (W.Level_bar.get_min_value raw)
    (W.Level_bar.get_max_value raw)
    (W.Level_bar.get_value raw)
;;

(* ------------------------------------------------------------------------------------ *)

(* The declined choice through a real [Driver.frame], which is the claim the hand-driven
   patches above cannot make. A model that will only sit on an even index: when it
   refuses, its state does not move, so the frame Bonsai runs hands back the
   {i physically same node} and is not diffed at all -- [Widget_impl.reassert] is the only
   thing left, and a driver that skipped it would leave the user's choice standing with
   the model holding something else.

   The whole loop is real: GTK emits [notify::selected], the trampoline schedules the
   handler's effect, the driver's idle runs the frame, and the frame corrects the widget.
   [live_driver.ml] makes this claim for a toggle, the block above it for a buffer; this
   is the one for a widget whose signal is a property notification. *)
let () =
  let seen = ref [] in
  let time_source = Bonsai.Time_source.create ~start:Time_ns.epoch in
  let d =
    Bonsai_gtk.Expert.Driver.create
      ~time_source
      ~on_window_created:(fun _ -> ())
      (fun (graph @ local) ->
        let selected, set_selected = Bonsai.state 0 graph in
        let%arr selected and set_selected in
        Node.window
          ~title:"picker"
          (Node.drop_down
             ~attrs:
               [ Attr.on_selected_changed (fun i ->
                   seen := i :: !seen;
                   if i % 2 = 0 then set_selected i else Ui_effect.Ignore)
               ]
             ~items:[ "zero"; "one"; "two"; "three" ]
             ~selected
             ()))
  in
  Bonsai_gtk.Expert.Driver.frame d;
  let driven () : W.Drop_down.t =
    let root = Option.value_exn (Bonsai_gtk.Expert.Driver.root_widget d) in
    cast (List.hd_exn (Bonsai_gtk.Private.Gtk_import.widget_children root))
  in
  let driven_selected () = W_drop_down.of_gtk (W.Drop_down.get_selected (driven ())) in
  let pick i = W.Drop_down.set_selected (driven ()) i in
  (* The mount happened inside a real frame, so the [notify::selected] GTK emitted while
     the selection was written was swallowed by the guard. *)
  printf
    "driver, after mount: %d (handler saw %d)\n"
    (driven_selected ())
    (List.length !seen);
  pick 2;
  (* Printed before the drain as well as after: the emission arms the driver's idle, and
     by the time the loop is handed back the frame it armed has already run -- so without
     this line an accepted choice would be indistinguishable from one that never landed. *)
  printf "driver, user picked 2, before the frame: %d\n" (driven_selected ());
  drain ();
  printf "driver, after the frame the choice armed: %d\n" (driven_selected ());
  (* Now the refusal. The handler sees 3, the model keeps its 2, and the frame it runs is
     a no-diff one -- so [reassert] is the only thing that can put the drop-down back, and
     it must. *)
  pick 3;
  printf "driver, user picked 3, before the frame: %d\n" (driven_selected ());
  drain ();
  printf
    "driver, after the frame the refusal armed: %d (handler saw %s)\n"
    (driven_selected ())
    (Sexp.to_string [%sexp (List.rev !seen : int list)]);
  (* One more frame with nothing having happened: the correction above is not a loop.
     [reassert] compares against the widget before it writes, so this frame writes nothing
     -- and the handler sees nothing new, which is what says the correcting write did not
     feed itself back in. *)
  let before = List.length !seen in
  Bonsai_gtk.Expert.Driver.frame d;
  drain ();
  printf
    "driver, one more frame: %d (handler saw %d more)\n"
    (driven_selected ())
    (List.length !seen - before);
  Bonsai_gtk.Expert.Driver.stop d
;;

(* ------------------------------------------------------------------------------------ *)

(* What an idle frame over a drop-down costs, and whether it depends on the size of the
   list.

   The claim under test is "the model is rebuilt only when the items differ", from the
   other side: an implementation that rebuilt on every frame -- or one whose [reassert]
   compared the item lists -- would be linear in the item count, and this ratio would show
   it. With the model left alone, an idle frame is one [get_selected] and one integer
   comparison whatever the list holds, so four items and a thousand cost the same.

   A ratio rather than a timing, for [live_lists.ml]'s reason: the absolute number depends
   on the machine and on how oversubscribed CI is, and contention scales both measurements
   equally. The bound of 5 is an order of magnitude clear of both ends.

   The second measurement is a frame parked on a refused [~selected:(-1)], which is the
   shape task-9-review.md's R1 caught on the text view: a controlled prop the widget will
   not take leaves [reassert] deciding {i not} to write on every frame forever, and the
   deciding is what has to be cheap. Here the memo makes it an integer comparison; without
   it, every one of those frames would set the property and take a
   [freeze_notify]/[thaw_notify] pair for a write GTK throws away. *)
let () =
  let bound_ratio = 5.0 in
  let frames = 20_000 in
  let scheduled = ref 0 in
  let refusals = ref 0 in
  let scheduler = Scheduler.create ~run_frame:(fun () -> ()) in
  let ctx =
    P.create_ctx
      ~report:(fun ~node_path:_ _ -> incr refusals)
      ~signals:
        { schedule = (fun _ -> incr scheduled)
        ; in_patch = (fun () -> Scheduler.in_patch scheduler)
        ; on_exn =
            (fun ~node_path exn -> printf "EXN at %s: %s\n" node_path (Exn.to_string exn))
        }
      ~on_window_created:(fun _ -> ())
      ()
  in
  let idle_frame_ms ~n ~refused =
    let items = List.init n ~f:(fun i -> sprintf "item %d" i) in
    let live =
      P.mount
        ctx
        ~path:"bench"
        ~is_root:true
        (picker ~items ~selected:(if refused then -1 else n - 1) ())
    in
    (* Printed, because it is what says the frames below are timing the state they claim
       to: a refused frame is one whose widget is showing something other than the node's
       [-1], and it has been reported exactly once. *)
    printf
      "bench: %s, %d items, showing %d (refusals so far %d)\n"
      (if refused then "parked on a refused ~selected:(-1)" else "settled")
      n
      (selected live)
      !refusals;
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
  let small = idle_frame_ms ~n:4 ~refused:false in
  let big = idle_frame_ms ~n:1000 ~refused:false in
  let big_refused = idle_frame_ms ~n:1000 ~refused:true in
  (* Still one, after twenty thousand frames parked on it. *)
  printf "bench: refusals reported across every frame above: %d\n" !refusals;
  let ratio = big /. small in
  let refused_ratio = big_refused /. big in
  printf
    "bench: %d idle frames over 4 and over 1000 items, cost ratio under %g: %b\n"
    frames
    bound_ratio
    Float.(ratio < bound_ratio);
  printf
    "bench: an idle frame parked on a refused selection, against a settled one, under \
     %g: %b\n"
    bound_ratio
    Float.(refused_ratio < bound_ratio);
  eprintf
    "bench: %.5f ms at 4 items, %.5f ms at 1000 items, ratio %.2f (bound %g)\n%!"
    small
    big
    ratio
    bound_ratio;
  eprintf
    "bench: %.5f ms parked on a refused selection, ratio %.2f (bound %g)\n%!"
    big_refused
    refused_ratio
    bound_ratio
;;
