open! Core
open Bonsai_gtk_vtree
open Gtk_import

let wrap_mode : Wrap_mode.t -> Gtk_enums.wrapmode = function
  | None_ -> `NONE
  | Char -> `CHAR
  | Word -> `WORD
  | Word_char -> `WORD_CHAR
;;

(* [get_buffer] is not a constructor. A [GtkTextView] builds its own buffer at
   construction and [get_buffer] returns that same object every time -- verified live: two
   calls give two OCaml wrappers around one pointer. That stable identity is what makes it
   safe to connect a signal to the buffer at mount and disconnect from it at teardown, and
   it is why [set_buffer] is not exposed: swapping the buffer would strand the connection
   on the old one.

   The wrapper is fresh each call and is not free. [ml_gtk_text_view_get_buffer] does
   [g_object_ref_sink] on the result before wrapping it, which is correct for a
   transfer-none return -- the wrapper's finaliser unconditionally unrefs -- but it does
   mean one custom block, one GObject ref and one finalisation per call. Nothing here
   calls it on an idle frame; see [state] below. *)
let buffer (w : Widget.t) : W.Text_buffer.t = W.Text_view.get_buffer (cast w)

(* The whole buffer, as a string.

   There is no whole-buffer [get_text] in the binding: reading is [get_bounds] followed by
   [get_text] over those two iters. The trailing [true] is [include_hidden_chars]; with no
   tags in play it makes no difference, and [true] is the answer that keeps making no
   difference if tags ever arrive.

   {b This call is expensive twice over}, which is what [state] exists to ration. It
   copies the whole buffer (0.42 ms for a megabyte, measured), and
   [ml_gtk_text_buffer_get_text] copies the C string into OCaml and never [g_free]s the
   original -- so every read also leaks the text. That is a binding defect, recorded in
   [docs/m1-backlog.md] with the other fork patches; no single-string transfer-full return
   in the generated stubs is freed, so it is the generator's to fix rather than this
   call's. Until then, reading the buffer once per frame would leak a megabyte a frame for
   a megabyte of notes, with the application doing nothing at all. *)
let read (w : Widget.t) =
  let b = buffer w in
  let start_, end_ = W.Text_buffer.get_bounds b in
  W.Text_buffer.get_text b start_ end_ true
;;

(* What the library believes the live buffer holds, per text view.

   [reassert] runs on every patch {i and} on every no-change frame through
   [Patcher.reassert_only], so whatever it does is paid sixty times a second by an
   application doing nothing. The controlled-text rule says to compare against the
   {i live widget} rather than against the previous node (spec §6.5) -- and reading a text
   buffer back is O(length) and leaks, so doing it literally would make an idle frame over
   a large document both slow and unbounded in memory. This is how the rule is kept
   without the read.

   The invariant: while [stale] is [false], [text] is what the buffer holds. It is
   established by every write (which knows what it wrote) and re-established by every
   read, and it is invalidated by the [changed] handler in {!changed}'s [connect] -- which
   runs on {i every} emission, the library's own writes included, because a
   [GtkTextBuffer] emits [changed] for every insert and every delete whatever caused it.
   There is no third way to change a buffer's text, so there is no way for the cache to go
   quietly wrong.

   The one gap is a write GTK does not take in full: [set_text] wants valid UTF-8, and a
   text that is not (or that contains an embedded NUL, which the [-1] length below
   terminates at) leaves the buffer holding something other than what was written. The
   cache records {i what was written} rather than re-reading, so that divergence costs one
   write instead of one per frame -- which is Task 3's [max_length] lesson applied to the
   only shape it can take here. A user edit re-reads and the cache becomes the truth
   again.

   Weakly keyed on the widget, as [w_search_entry.ml]'s echo record is: a view that is
   destroyed takes its entry with it rather than pinning the GObject alive. The key must
   be the [Widget.t] the patcher retains -- the same value [create] returned and
   [reassert] is handed -- which is [Child_keys]' invariant in a smaller place. *)
module Cache = Stdlib.Ephemeron.K1.Make (struct
    type t = Widget.t

    let equal = Gobject.same
    let hash = Stdlib.Hashtbl.hash
  end)

type cached =
  { mutable text : string
  ; mutable stale : bool
  ; (* The exact text a write was last refused for, kept so that the decision is made once
       rather than on every frame -- see [set_text_if_needed]. *)
    mutable refused : string option
  ; (* A refusal the patcher has not yet reported. Taken (and cleared) by
       [Patcher.enqueue_fixups], which is the one place that holds both this widget and
       the path of the node it came from. *)
    mutable unreported : string option
  }

let cache : cached Cache.t = Cache.create 8

(* Created [stale], so that a record which appears from nowhere knows nothing and reads
   before it answers. [create] calls this on a freshly built view whose buffer is empty,
   where that first read costs nothing. *)
let state w =
  match Cache.find_opt cache w with
  | Some st -> st
  | None ->
    let st = { text = ""; stale = true; refused = None; unreported = None } in
    Cache.replace cache w st;
    st
;;

(* The message for a refused write, if there is one that has not been reported yet.

   Called by the patcher, once per text view per frame, because a [Widget_impl] is handed
   a widget and a kind and knows neither where it is in the tree nor how the runtime
   reports. Cleared by the read, so one refusal is reported once however many frames it
   survives. *)
let take_report w =
  let st = state w in
  match st.unreported with
  | None -> None
  | Some message ->
    st.unreported <- None;
    Some message
;;

let refresh w st =
  if st.stale
  then (
    st.text <- read w;
    st.stale <- false)
;;

(* Whether the buffer already holds [text] -- the comparison the whole controlled-text
   rule turns on, and the one thing here that runs on every idle frame.

   [phys_equal] first, and it is not a micro-optimisation: [reassert_only] runs on the
   frames where Bonsai handed back the physically same node, so the string it offers is
   the {i same value} the last write stored, and the common case answers in a pointer
   comparison rather than in a megabyte of [memcmp] (0.032 ms for a megabyte, measured --
   two percent of a frame's budget, for a question whose answer never changes).

   When they are equal but not physically so -- the frame after a user edit the model
   echoed, where the cache holds the string GTK built and the node holds the model's --
   the node's string is adopted into the cache. They are equal, so nothing is lost, and it
   turns a steady state that would compare a megabyte every frame forever into one that
   compares a pointer. *)
let holds w st text =
  refresh w st;
  phys_equal st.text text
  || (String.equal st.text text
      &&
      (st.text <- text;
       true))
;;

(* Whether GTK will store [text] at all, and the reason if not.

   [gtk_text_buffer_set_text] deletes the whole buffer and then inserts, and
   [gtk_text_buffer_emit_insert] guards the insert with
   [g_return_if_fail (g_utf8_validate (text, len, NULL))]. So handing it text that is not
   valid UTF-8 lands the delete and refuses the insert: the buffer ends up {i empty} --
   not partly written -- with a [Gtk-CRITICAL] on stderr and the previous contents gone.
   Measured, not read: ["caf\xe9 latte"] leaves a buffer that held ["a good note"] holding
   [""].

   The NUL check is separate and is not redundant defence. [set_text]'s [-1] means
   "NUL-terminated", so GTK stops at the first NUL and stores the prefix -- silently, with
   no critical and no error. [g_utf8_validate] with an explicit length happens to reject
   NUL bytes on this GLib, so [validate] alone would catch it today; naming the case
   separately is what keeps the {i silent} shape from coming back if that ever changes,
   and lets the message say which of the two happened.

   O(len), and only on a frame that was about to write -- which already pays O(len) for
   the write. An idle frame never reaches this. *)
let unwritable text =
  if String.mem text '\000'
  then
    Some
      "text contains a NUL byte, which GTK would silently truncate at; the write was \
       refused and the buffer was left as it was"
  else if not (Glib.Utf8.validate text)
  then
    Some
      "text is not valid UTF-8, which GTK refuses to insert *after* emptying the buffer; \
       the write was refused and the buffer was left as it was"
  else None
;;

(* Whether a write of [text] has already been decided against, and reported.

   The memo is against the {i text} rather than against the widget: a model that keeps
   asking for the same unstorable text pays one validation and one message, and a model
   that changes to a different unstorable text is a new datum and is validated and
   reported again.

   The string is adopted on a match, exactly as [holds] adopts, and for the same reason: a
   model that rebuilds an equal string every frame would otherwise re-run [String.equal]
   against the memo forever. (The first round's comment claimed this adoption and the code
   did not do it -- task-9-review.md R1.)

   [unwritable] is pure, so a text refused once is refused always, and [st.refused] is
   cleared by every successful write. That is what makes it safe for [reassert] to consult
   this {i before} [holds]: a matching memo means the write can only fail, so the frame
   has nothing to do and need not compare anything or bracket anything. *)
let already_refused st text =
  match st.refused with
  | Some refused ->
    phys_equal refused text
    || (String.equal refused text
        &&
        (st.refused <- Some text;
         true))
  | None -> false
;;

(* Controlled, on spec §6.5's rule: written only when the buffer's current text differs
   from the model's, never when the previous node's did.

   The cursor is saved as a *character offset* and restored after the write, which is the
   same policy [w_entry.ml] uses and has the same two properties. It is right when the
   model echoed what was typed (nothing is written, so nothing moves) and right when the
   model rewrote it in place (uppercasing, trimming trailing space: the offset still means
   what it meant). It is *approximate* when the model changed the text's length before the
   cursor -- an autocompleter inserting six characters at the start leaves the caret six
   characters early -- and GTK clamps an offset past the end.

   That is a policy, not an accident, and the honest alternative is worse: preserving the
   cursor by diffing old against new text would be a general text-diff in a widget impl,
   and preserving nothing would put the caret at the end of the document on every write.
   Applications that need better own the cursor themselves, which M2 does not expose --
   [notify::cursor-position] is the hook, and it is on the backlog.

   The selection is *not* preserved: [set_text] collapses it, and restoring it would mean
   restoring an anchor the model may have invalidated. An application that
   programmatically rewrites text under a selection is doing something the user will
   notice however this behaves.

   Returns whether it wrote, as [W_entry.set_text_if_needed] does. *)
let set_text_if_needed w text =
  let st = state w in
  if holds w st text
  then false
  else if (* Already decided, and already reported. This keeps the function correct on its
             own, whoever calls it; [reassert] additionally asks the same question
             {i first}, which is what makes a frame parked on a refusal cost nothing at
             all. *)
          already_refused st text
  then false
  else (
    match unwritable text with
    | Some reason ->
      (* Refused. The buffer is untouched, so the cache -- which describes the buffer --
         is untouched too, and the library's belief stays true. That is the half the first
         round got wrong: caching what was *attempted* left [holds] answering [true]
         against a buffer that held something else, permanently under [~editable:false],
         where no user edit will ever re-read it. *)
      st.refused <- Some text;
      st.unreported <- Some reason;
      false
    | None ->
      let b = buffer w in
      let offset = W.Text_buffer.get_cursor_position b in
      (* [-1] is GTK's "the string is NUL-terminated". Not a character count: passing one
         would truncate any text containing a multi-byte character. [String.length text]
         is the other correct spelling and differs only for a text with an embedded NUL,
         which a [GtkTextBuffer] cannot hold either way. *)
      W.Text_buffer.set_text b text (-1);
      (* Re-fetch: no [Text_iter] is held across the write -- every iter is a GC-managed
         copy that edits invalidate -- and [get_iter_at_offset] clamps an offset past the
         end, which is the right answer when the model shortened the text.

         The write emitted [changed] synchronously (twice, over non-empty text: a delete
         and an insert), so [st.stale] is [true] by now; the assignment below is what puts
         the cache back, and it has to come after the write rather than before it. *)
      W.Text_buffer.place_cursor b (W.Text_buffer.get_iter_at_offset b offset);
      st.text <- text;
      st.stale <- false;
      st.refused <- None;
      true)
;;

let changed : Signals.spec =
  Read_back
    { attr = Attr.Name.On_changed
    ; connect =
        (fun w ~callback ->
          (* The buffer is where [changed] is emitted, so the buffer is what the
             connection must name -- a handler id is unique per object, and disconnecting
             a buffer's id from the widget would at best log a GLib critical and at worst
             disconnect something unrelated (spec §6.4's M1 amendment).
             [test/live/live_text.ml]'s last block is what catches that: it destroys the
             view and then emits on a buffer handle it still holds.

             The cache is invalidated here rather than in [fire], because it has to be
             invalidated on {i every} emission -- including the ones [Signals.dispatch]
             drops for [in_patch] and the ones that reach an empty slot, which are still
             edits.

             [(state w).stale] rather than a record captured here, which is what [fire] on
             the next lines already does. Capturing would be faster by one ephemeron
             lookup per emission and would be the cache's only *silent* failure shape: if
             the entry for [w] were ever dropped while the widget lived, [state w] would
             mint a second record, this callback would go on invalidating the first, and
             [holds] would read a clean record a frame behind -- a text view that quietly
             stops being controlled. It cannot happen today (the key is held both by
             [live.widget] and by this closure, which [connect_all] roots in the
             GClosure), but that reasoning is three hops long and lives nowhere near here.
             task-9-review.md M1.

             The closure captures neither the record nor the buffer, so it adds no
             reference of its own to the object it is connected to. *)
          let b = buffer w in
          Signals.connected
            b
            (W.Text_buffer.on_changed b ~callback:(fun () ->
               (state w).stale <- true;
               callback ())))
    ; fire =
        (fun w attr ->
          match (attr :> Attr.Private.t) with
          | On_changed handler ->
            (* The read the handler needs is the read the cache wanted anyway: this runs
               on a real user edit, which is the moment the cache is stale and the next
               [reassert]'s comparison would have had to pay for it. *)
            let st = state w in
            refresh w st;
            Some (handler st.text)
          | _ -> None)
    }
;;

let impl : Widget_impl.t =
  { name = "TextView"
  ; create =
      (fun (kind : Kind.t) ->
        match kind with
        | Text_view p ->
          let v = W.Text_view.new_ () in
          let w = (v :> Widget.t) in
          Widget_impl.batch w (fun () ->
            (* [None_] is GTK's own, so writing it would be a no-op with a [notify::]
               attached. [Defaults] is not re-exported from [Bonsai_gtk_vtree] -- it is
               [Kind]'s and [Node]'s -- so the default is spelled out here, as every other
               impl in this directory spells its own out. *)
            (match p.wrap with
             | None_ -> ()
             | wrap -> W.Text_view.set_wrap_mode v (wrap_mode wrap));
            if not p.editable then W.Text_view.set_editable v false;
            if p.monospace then W.Text_view.set_monospace v true;
            if not p.cursor_visible then W.Text_view.set_cursor_visible v false;
            if not p.accepts_tab then W.Text_view.set_accepts_tab v false;
            if p.left_margin <> 0 then W.Text_view.set_left_margin v p.left_margin;
            if p.right_margin <> 0 then W.Text_view.set_right_margin v p.right_margin;
            if p.top_margin <> 0 then W.Text_view.set_top_margin v p.top_margin;
            if p.bottom_margin <> 0 then W.Text_view.set_bottom_margin v p.bottom_margin;
            (* Text last, here as in [reassert] and for [w_entry.ml]'s reason: a margin or
               a wrap change re-lays-out the view, and doing that after the write would
               re-run the caret placement the write just decided. *)
            ignore (set_text_if_needed w p.text : bool));
          w
        | k -> Widget_impl.wrong_kind "TextView" k)
  ; update =
      (fun w ~(old : Kind.t) (new_ : Kind.t) ->
        match old, new_ with
        | Text_view old, Text_view new_ ->
          let v : W.Text_view.t = cast w in
          Widget_impl.batch w (fun () ->
            if not (Wrap_mode.equal old.wrap new_.wrap)
            then W.Text_view.set_wrap_mode v (wrap_mode new_.wrap);
            if not (Bool.equal old.editable new_.editable)
            then W.Text_view.set_editable v new_.editable;
            if not (Bool.equal old.monospace new_.monospace)
            then W.Text_view.set_monospace v new_.monospace;
            if not (Bool.equal old.cursor_visible new_.cursor_visible)
            then W.Text_view.set_cursor_visible v new_.cursor_visible;
            if not (Bool.equal old.accepts_tab new_.accepts_tab)
            then W.Text_view.set_accepts_tab v new_.accepts_tab;
            if old.left_margin <> new_.left_margin
            then W.Text_view.set_left_margin v new_.left_margin;
            if old.right_margin <> new_.right_margin
            then W.Text_view.set_right_margin v new_.right_margin;
            if old.top_margin <> new_.top_margin
            then W.Text_view.set_top_margin v new_.top_margin;
            if old.bottom_margin <> new_.bottom_margin
            then W.Text_view.set_bottom_margin v new_.bottom_margin)
          (* [text] is deliberately absent, so [create] and [update] agree on writing it
             last: it is controlled, which makes it [reassert]'s, and the patcher runs
             that immediately after this and on every other patch too. *)
        | _, k -> Widget_impl.wrong_kind "TextView" k)
  ; reassert =
      Some
        (fun w (kind : Kind.t) ->
          match kind with
          | Text_view p ->
            (* The comparison comes first because the bracket has to be outside the
               decision: a text view patched with the text it already shows -- which is
               every patch of one the model echoes, and every idle frame -- must pay
               neither the write nor the freeze/thaw. See [Widget_impl.batch_if].

               [already_refused] comes first in turn, and that ordering is the whole of
               task-9-review.md R1. After a refusal the buffer holds the old text and
               [st.text] correctly describes it, while [p.text] is the unstorable one --
               so [holds] answers false on {i every} subsequent frame, and without this
               line each of them ran a whole-buffer [String.equal] here, took the
               freeze/thaw, and ran [String.equal] a second time inside
               [set_text_if_needed] before reaching the memo. Measured at 1 MB with a
               refused text of the same length (the case where [String.equal] cannot
               short-circuit): 0.062 ms per idle frame against 0.00012 ms settled, 518x,
               forever, on the very property this widget's bench exists to pin. Asking the
               memo first makes the parked frame a pointer comparison like any other.

               Skipping [holds] also skips its [refresh], which is right: [stale] simply
               stays set until the model offers a text GTK will take, and that frame pays
               the one read it genuinely needs. *)
            let st = state w in
            let writes = (not (already_refused st p.text)) && not (holds w st p.text) in
            Widget_impl.batch_if writes w (fun () ->
              if writes then ignore (set_text_if_needed w p.text : bool))
          | k -> Widget_impl.wrong_kind "TextView" k)
  ; signals = [ changed ]
  ; children = Widget_impl.No_children
  }
;;
