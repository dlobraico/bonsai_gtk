open! Core
open Bonsai_gtk_vtree
open Gtk_import

(* All three entry kinds implement [GtkEditable], and text, editability, width-chars,
   max-width-chars and alignment all go through it — as does [changed], which is why one
   spec serves every one of them. [from_gobject] is how the interface is reached.

   {b Four kinds, not three.} [GtkEditableLabel] implements [GtkEditable] too and has no
   [set_text] of its own, so [src/widgets/w_editable_label.ml] reaches its text through
   this same function and reuses {!set_text_if_needed}, {!needs_text} and {!changed}
   outright. Nothing in any of the three mentions an entry; keep it that way. *)
let editable (w : Widget.t) : W.Editable.t = W.Editable.from_gobject w

(* Against the *widget's* text, never against the previous node's. The user has typed
   since the last render, so the previous node's text is stale; comparing to it would
   either write on every keystroke (moving the caret to the end of what the user is still
   typing) or skip a write the model genuinely wanted. Comparing to the widget gets both
   right: a model that echoes what was typed is a no-op, and a model that rewrites it
   (uppercasing, clamping, rejecting) still wins. Spec §6.5.

   The write itself moves the caret to the end, so the position is saved and put back. GTK
   clamps it to the new text's length, which is the right answer when the model shortened
   the text.

   Returns whether it wrote. Most callers do not care, but [w_search_entry.ml] does: a
   write there arms a debounce whose emission arrives long after the patch is over, and it
   has to know which writes armed one.

   [w_editable_label.ml] is the second module outside this file to call it, and for the
   same underlying reason: the widget is a [GtkEditable], and the caret dance below is the
   policy rather than the entry's. *)
let needs_text (e : W.Editable.t) text = not (String.equal (W.Editable.get_text e) text)

(* The most of [text] a widget with this [max_length] can hold.

   [GtkEntryBuffer] truncates in *characters*, not bytes, so this counts the same unit GTK
   does: a byte is a continuation byte exactly when its top two bits are [10], and every
   other byte starts a character. (It does not validate; a malformed sequence counts as
   more characters than it should, which is what GTK's own byte walk does too.)

   This exists for the controlled-text rule, which compares against the *widget*. Handing
   [reassert] the untruncated text would compare a node's ["abcdefg"] against a widget
   forever stuck at ["abc"], so [needs_text] would be true on every frame and every frame
   -- including every idle tick through [Patcher.reassert_only] -- would write the text
   and re-place the caret. Comparing against what the widget can actually hold makes the
   over-long case cost one write rather than one per frame. [0] is GTK's "no limit". *)
let capped ~max_length text =
  if max_length <= 0 || String.length text <= max_length
  then text
  else (
    let len = String.length text in
    let rec go i chars =
      if i >= len || chars >= max_length
      then i
      else (
        let j = ref (i + 1) in
        while !j < len && Char.to_int text.[!j] land 0xc0 = 0x80 do
          incr j
        done;
        go !j (chars + 1))
    in
    String.prefix text (go 0 0))
;;

(* {1 Text a [GtkEditable] will not hold}

   One shape, and it is the silent one. [gtk_editable_set_text] takes a NUL-terminated
   string, so a text with an embedded NUL is stored up to the NUL and no further -- no
   critical, no error, no truncation the user can see. The read-back then never equals the
   model, so [needs_text] is true on every frame and the widget is rewritten sixty times a
   second for the life of the tree, silently. On a search entry it is worse than that:
   each write re-arms GTK's [search_delay] timeout, so at 60 fps a 150 ms debounce is
   reset every 16 ms and {!Attr.on_search_changed} never fires at all -- the one signal
   that would have told the application something was wrong is the one the fault
   suppresses.

   So it is refused, on exactly the terms [w_text_view.ml] set for the same silent shape:
   refused before the write, so the widget keeps what it had; remembered, so the frames
   after it cost a pointer comparison; reported once, with the node's path. That was the
   question M2 parked (docs/m2-backlog.md, "Do first in M3") and the final review's
   controls lens answered.

   {b Invalid UTF-8 is not refused, and that is measured rather than an oversight.} A
   [GtkTextBuffer] empties itself and then declines the insert, which is why the text view
   has to refuse it; a [GtkEditable] stores the bytes and reads them back unchanged
   (measured in [w_editable_label.ml]: ["caf\xe9 latte"] round-trips), so there is nothing
   to refuse and the controlled comparison settles on the first frame. Refusing it anyway
   would be refusing a write GTK takes.

   {b An over-long [~text] is not refused either}, and that is the other side of the same
   rule: [max_length] truncation is the widget's own rule applied to the model's text --
   GTK would truncate a typed string identically -- so tolerating it is honest, and
   {!capped} above makes it cost one write rather than one per frame. A NUL truncation is
   an artefact of C strings, not a rule anything applies to what the user types. *)
let unwritable text =
  if String.mem text '\000'
  then
    Some
      "text contains a NUL byte, which GTK would silently truncate the text at \
       (gtk_editable_set_text takes a NUL-terminated string); the write was refused and \
       the widget was left as it was"
  else None
;;

(* The refusal memo for all four [GtkEditable] widgets at once -- entry, password entry,
   search entry and editable label. One table, because the key is the widget and the four
   kinds never share one; and one table rather than four because the refusal itself is one
   rule, applied by the one function all four write their text through. See {!Refusal}. *)
module Refused = Refusal.Make (String) (Refusal.No_extra)

let take_report = Refused.take_report

(* Whether a write is wanted at all, in the order that makes a parked frame free: the memo
   first, the widget only if the memo has nothing (task-9-review.md R1). After a refusal
   the widget holds the old text and the node holds the unstorable one, so [needs_text]
   answers "differs" on every frame forever -- and it is [O(len)] plus a [get_text] copy
   out of GTK. Asking the memo first makes that frame a pointer comparison.

   Hoisted out of {!set_text_if_needed} so that the four [reassert]s can put the whole
   decision outside [Widget_impl.batch_if] -- a frame that writes nothing must not pay a
   freeze/thaw either. *)
let needs_write w text =
  (not (Refused.already_refused (Refused.state w) text)) && needs_text (editable w) text
;;

(* Takes the [Widget.t] rather than the [W.Editable.t] it writes through, because the
   refusal memo is keyed on the widget the patcher retains and [from_gobject] mints a
   fresh wrapper on every call. The editable is derived here.

   Returns whether it wrote -- [false] both for "already correct" and for "refused", which
   is what every caller means by it. [w_search_entry.ml] is the one that cares: a write
   there arms a debounce whose emission arrives long after the patch is over, and a
   refused write arms nothing. *)
let set_text_if_needed (w : Widget.t) text =
  let st = Refused.state w in
  if Refused.already_refused st text
  then false
  else (
    let e = editable w in
    if not (needs_text e text)
    then false
    else (
      match unwritable text with
      | Some reason ->
        (* Refused. The widget is untouched, so it goes on showing the text it had, and a
           later frame offering text GTK will store writes it on {i that} frame. *)
        Refused.refuse st text ~reason;
        false
      | None ->
        let position = W.Editable.get_position e in
        W.Editable.set_text e text;
        W.Editable.set_position e position;
        Refused.landed st;
        true))
;;

let changed : Signals.spec =
  Read_back
    { attr = Attr.Name.On_changed
    ; connect =
        (fun w ~callback ->
          (* The [GtkEditable] is where [changed] is emitted, so it is also what the
             connection has to name -- even though [from_gobject] is a checked cast to the
             same instance for all three entry kinds. *)
          let e = editable w in
          [ Signals.connected e (W.Editable.on_changed e ~callback) ])
    ; fire =
        (fun w attr ->
          match (attr :> Attr.Private.t) with
          | On_changed handler -> Some (handler (W.Editable.get_text (editable w)))
          | _ -> None)
    }
;;

(* [activate] is on each concrete class rather than on [GtkEditable], so the connector is
   the one thing the three kinds cannot share. Each one passes a [connect] that names the
   object it connected to, the same as any other spec. *)
let activate ~connect : Signals.spec =
  Read_back
    { attr = Attr.Name.On_activate
    ; connect
    ; fire =
        (fun _w attr ->
          match (attr :> Attr.Private.t) with
          | On_activate handler -> Some (handler ())
          | _ -> None)
    }
;;

let impl : Widget_impl.t =
  { name = "Entry"
  ; create =
      (fun (kind : Kind.t) ->
        match kind with
        | Entry p ->
          let e = W.Entry.new_ () in
          let w = (e :> Widget.t) in
          Widget_impl.batch w (fun () ->
            (* Only when there is one: writing [None] still builds GTK's placeholder
               label, empty, which a dump then reports as a placeholder that is not there. *)
            Option.iter p.placeholder ~f:(fun t ->
              W.Entry.set_placeholder_text e (Some t));
            if not p.visibility then W.Entry.set_visibility e false;
            if p.activates_default then W.Entry.set_activates_default e true;
            let ed = editable w in
            if p.width_chars <> -1 then W.Editable.set_width_chars ed p.width_chars;
            if p.max_width_chars <> -1
            then W.Editable.set_max_width_chars ed p.max_width_chars;
            if Float.( <> ) p.xalign 0. then W.Editable.set_alignment ed p.xalign;
            if not p.editable then W.Editable.set_editable ed false;
            (* Before the text, so a [~text] longer than [~max_length] is truncated by the
               same rule a typed one would be rather than surviving until the next edit.
               Not controlled: it constrains the widget rather than naming a value the
               model owns. *)
            if p.max_length <> 0 then W.Entry.set_max_length e p.max_length;
            (* Text last, here as in [reassert]: a width or alignment change re-lays-out
               the entry, and doing that after the write would re-run the caret placement
               the write just decided. [set_editable] is not a barrier — it gates the
               user's edits, not the program's. Written already capped, so that [create]
               and [reassert] leave the widget in the same state for the same node. *)
            ignore (set_text_if_needed w (capped ~max_length:p.max_length p.text) : bool));
          w
        | k -> Widget_impl.wrong_kind "Entry" k)
  ; update =
      (fun w ~(old : Kind.t) (new_ : Kind.t) ->
        match old, new_ with
        | Entry old, Entry new_ ->
          let e : W.Entry.t = cast w in
          let ed = editable w in
          Widget_impl.batch w (fun () ->
            if not (Option.equal String.equal old.placeholder new_.placeholder)
            then W.Entry.set_placeholder_text e new_.placeholder;
            if not (Bool.equal old.visibility new_.visibility)
            then W.Entry.set_visibility e new_.visibility;
            if not (Bool.equal old.activates_default new_.activates_default)
            then W.Entry.set_activates_default e new_.activates_default;
            if not (Bool.equal old.editable new_.editable)
            then W.Editable.set_editable ed new_.editable;
            if old.width_chars <> new_.width_chars
            then W.Editable.set_width_chars ed new_.width_chars;
            if old.max_width_chars <> new_.max_width_chars
            then W.Editable.set_max_width_chars ed new_.max_width_chars;
            if Float.( <> ) old.xalign new_.xalign
            then W.Editable.set_alignment ed new_.xalign;
            if old.max_length <> new_.max_length
            then W.Entry.set_max_length e new_.max_length)
          (* [text] is deliberately absent, so [create] and [update] agree on writing it
             last: it is controlled, which makes it [reassert]'s, and the patcher runs
             that immediately after this and on every other patch too. *)
        | _, k -> Widget_impl.wrong_kind "Entry" k)
  ; reassert =
      Some
        (fun w (kind : Kind.t) ->
          match kind with
          | Entry p ->
            (* The decision comes first because the bracket has to be outside it: an entry
               patched with the text it already shows -- which is every patch of an entry
               the model echoes -- must pay neither the write nor the freeze/thaw. See
               [Widget_impl.batch_if]. [needs_write] is also what parks a refused text on
               a pointer comparison rather than on a [get_text] and an [O(len)] compare. *)
            let text = capped ~max_length:p.max_length p.text in
            let writes = needs_write w text in
            Widget_impl.batch_if writes w (fun () ->
              if writes then ignore (set_text_if_needed w text : bool))
          | k -> Widget_impl.wrong_kind "Entry" k)
  ; signals =
      [ changed
      ; activate ~connect:(fun w ~callback ->
          [ Signals.connected w (W.Entry.on_activate (cast w) ~callback) ])
      ]
  ; children = Widget_impl.No_children
  }
;;
