### Task 9: TextView — a controlled buffer, and a cursor policy stated out loud

The one M2 widget whose signal lives on a different GObject than the widget, which is what M1's object-carrying `connect` was widened for (spec §6.4's amendment names `GtkTextBuffer` explicitly as the case it was anticipating).

**Files:**
- Modify: `vtree/kind.ml(i)`, `vtree/node.ml(i)`, `vtree/defaults.ml`, `vtree/events.ml`, `vtree/bonsai_gtk_vtree.ml`, `src/widgets/registry.ml`, `src/live_tree.ml`, `src/bonsai_gtk.ml(i)`, `test/test_widgets.ml`, `test/handle/test_handle.ml`, `test/live/dune`
- Create: `vtree/wrap_mode.ml`, `src/widgets/w_text_view.ml`, `test/live/live_text.ml`, `test/live/expected_text.txt`

**Interfaces:**
- Produces:
  ```ocaml
  (* vtree/wrap_mode.ml *)
  type t = None_ | Char | Word | Word_char [@@deriving sexp_of, equal, compare]

  val text_view
    :  ?key:Key.t -> ?attrs:Attr.t list
    -> ?wrap:Wrap_mode.t
    -> ?editable:bool
    -> ?monospace:bool
    -> ?cursor_visible:bool
    -> ?accepts_tab:bool
    -> ?left_margin:int -> ?right_margin:int -> ?top_margin:int -> ?bottom_margin:int
    -> text:string
    -> unit
    -> t
  ```
- Consumes: `W.Text_view.{new_,get_buffer,set_wrap_mode,set_editable,set_monospace,set_cursor_visible,set_accepts_tab,set_left_margin,set_right_margin,set_top_margin,set_bottom_margin}`, `W.Text_buffer.{get_bounds,get_text,set_text,get_cursor_position,get_iter_at_offset,place_cursor,get_char_count,on_changed}`.

**The three ocgtk facts that shape the implementation**, each verified and each easy to get wrong:

- `Text_buffer.set_text : t -> string -> int -> unit` — the trailing `int` is a **byte length**; `-1` means NUL-terminated, which is what to pass. `String.length s` also works and is equivalent for OCaml's byte strings; pass `-1` and say why in a comment, so nobody "fixes" it to a character count.
- `Text_buffer.get_text : t -> Text_iter.t -> Text_iter.t -> bool -> string` — there is no whole-buffer variant. Reading is `let a, b = W.Text_buffer.get_bounds buf in W.Text_buffer.get_text buf a b true`. The trailing `true` is `include_hidden_chars`; with no tags in play it makes no difference, and `true` is the answer that keeps making no difference if tags ever arrive.
- **`Text_iter` has no constructor.** Every iter comes from a buffer getter and is a GC-managed copy; mutating one (`set_offset`, `forward_char`) touches your copy and not the buffer. Iters are invalidated by edits, so re-fetch after every mutation — which the code below does by never holding one across a write.

**The cursor policy, stated rather than implied.** `GtkEntry`'s `reassert` saves `get_position` and restores it, because `set_text` moves the caret to the end and GTK clamps a restored position to the new length. A `GtkTextBuffer` is the same problem with a worse failure: a multi-line note whose caret jumps to the end on every keystroke the model echoes is unusable. So:

```ocaml
(* Controlled, on spec §6.5's rule: written only when the buffer's current text differs
   from the model's, never when the previous node's did.

   The cursor is saved as a *character offset* and restored after the write, which is the
   same policy [w_entry.ml] uses and has the same two properties. It is right when the
   model echoed what was typed (nothing is written, so nothing moves) and right when the
   model rewrote it in place (uppercasing, trimming trailing space: the offset still
   means what it meant). It is *approximate* when the model changed the text's length
   before the cursor -- an autocompleter inserting six characters at the start leaves the
   caret six characters early -- and GTK clamps an offset past the end.

   That is a policy, not an accident, and the honest alternative is worse: preserving the
   cursor by diffing old against new text would be a general text-diff in a widget impl,
   and preserving nothing would put the caret at the end of the document on every write.
   Applications that need better own the cursor themselves, which M2 does not expose --
   [notify::cursor-position] is the hook, and it is on the backlog.

   The selection is *not* preserved: [set_text] collapses it, and restoring it would mean
   restoring an anchor the model may have invalidated. An application that programmatically
   rewrites text under a selection is doing something the user will notice however this
   behaves. *)
```

Write that comment. It is the kind of thing that gets re-litigated in three months.

- [ ] **Step 1: Write the failing tests**

`test/test_widgets.ml` — constructor and defaults, including that `~text` is required (positional-ish, a labelled non-optional) so a text view always has a controlled text, like the entries.

`test/handle/test_handle.ml` — the declined edit, headlessly:

```ocaml
let notes (graph @ local) =
  let text, set_text = Bonsai.state "" graph in
  let%arr text and set_text in
  (* A model that refuses anything over ten characters: the state does not change, so the
     view does not change, so the *only* thing that puts the widget back is [reassert] --
     which is what makes this the interesting test and not a formality. *)
  Node.window ~title:"Notes"
    (Node.text_view
       ~attrs:[ Attr.test_id "body"; Attr.on_changed (fun s -> if String.length s <= 10 then set_text s else Effect.Ignore) ]
       ~text
       ())
;;
```

with two `Set_text` actions, one accepted and one refused, and `show_diff` after each. The refused one must show **no diff**, which is the headless shadow of the live claim below.

`test/live/live_text.ml` — the GTK half. This file grows through Tasks 9–11:

```ocaml
  (* 1. Props: wrap mode, editable, monospace, the four margins. *)
  (* 2. The controlled write. Type into the buffer by hand (insert at the cursor, the way a
        user does), then render the *same* model text: the buffer must go back. *)
  (* 3. The caret. Put the cursor in the middle, have the model rewrite the text to
        something of the same length, and assert the offset survived. Then have it rewrite
        to something shorter and assert the offset clamped rather than raised. *)
  (* 4. The echo. Render text the buffer already holds: [get_text] is called, [set_text] is
        not, and the caret does not move. Observable as the cursor offset being unchanged
        after a patch that "wrote" the same string. *)
  (* 5. The reentrancy case. A programmatic write emits [changed] on the buffer,
        synchronously, from inside the patch; [scheduled] must not move. This is the
        buffer-object version of the case live_controls.ml pins for entries, and it is the
        first time a signal connected to a non-widget GObject goes through the guard. *)
  (* 6. Teardown disconnects from the *buffer*. Destroy the view, then emit [changed] on
        the buffer handle the test still holds: nothing fires. A connection that named the
        widget instead of the buffer would fail to disconnect here -- which is exactly the
        bug M1's fix wave widened [Signals.connection] to prevent, and this is the first
        test that can actually catch it. *)
```

Case 6 is the most valuable test in this task and did not exist before, because M1 had no signal on a long-lived non-widget object. Write it.

- [ ] **Step 2: Run to verify failure.**

- [ ] **Step 3: `vtree/wrap_mode.ml`** — four constructors, `None_` for the shadowing reason, mapping to `Gtk_enums.wrapmode`'s `` `NONE | `CHAR | `WORD | `WORD_CHAR ``. GTK's default is `` `NONE ``, so `Defaults.Text_view.wrap = Wrap_mode.None_`; note in `Node.text_view`'s doc that `Word_char` is what a notes field usually wants (wrap at word boundaries, break a word that does not fit) and `None_` is what a code field wants.

- [ ] **Step 4: `src/widgets/w_text_view.ml`**

```ocaml
let buffer (w : Widget.t) : W.Text_buffer.t = W.Text_view.get_buffer (cast w)

(* [get_buffer] is not a constructor: [GtkTextView] makes its own buffer at construction
   and [get_buffer] returns that same one every time, so this is a cheap accessor and the
   object identity is stable for the widget's lifetime -- which is what makes it safe to
   connect a signal to it at [create] and disconnect at [destroy]. Do not call
   [set_buffer]: swapping the buffer would strand the connection on the old one. *)

let read w =
  let b = buffer w in
  let start_, end_ = W.Text_buffer.get_bounds b in
  W.Text_buffer.get_text b start_ end_ true
;;

let set_text_if_needed w text =
  let b = buffer w in
  if String.equal (read w) text
  then false
  else (
    let offset = W.Text_buffer.get_cursor_position b in
    (* [-1] is GTK's "the string is NUL-terminated". Not a character count: passing one
       would truncate any text containing a multi-byte character. *)
    W.Text_buffer.set_text b text (-1);
    (* Re-fetch: the iter above (if any) is invalid after the write, and [get_iter_at_offset]
       clamps an offset past the end, which is the right answer when the model shortened
       the text. *)
    W.Text_buffer.place_cursor b (W.Text_buffer.get_iter_at_offset b offset);
    true)
;;

let changed : Signals.spec =
  Read_back
    { attr = Attr.Name.On_changed
    ; connect =
        (fun w ~callback ->
          (* The buffer is where [changed] is emitted, so the buffer is what the connection
             must name -- a handler id is unique per object, and disconnecting a buffer's
             id from the widget would at best log a GLib critical and at worst disconnect
             something unrelated (spec §6.4's M1 amendment). *)
          let b = buffer w in
          Signals.connected b (W.Text_buffer.on_changed b ~callback))
    ; fire =
        (fun w attr ->
          match (attr : Attr.Private.t) with
          | On_changed handler -> Some (handler (read w))
          | _ -> None)
    }
;;
```

`reassert` is `set_text_if_needed` under `batch_if`. `create` writes the props and then the text last, matching `w_entry.ml`'s ordering and for the same reason (a margin or wrap change re-lays-out the view, and doing that after the write would re-run the caret placement).

- [ ] **Step 5: `Live_tree`** — a `"GtkTextView"` arm printing the text (through `get_bounds`+`get_text`), `wrap-mode` when not `NONE`, `read-only` when not editable, `monospace`, and the margins when non-zero. **Truncate the text** at, say, 60 characters with an ellipsis: a golden with a paragraph in it is unreadable and would churn on every wording change. Say so in a comment beside the arm, and note that the truncation means the golden cannot pin a long text — which is fine, because case 2 above prints the text itself.

- [ ] **Step 6: Run, read, promote, gate, commit**

```bash
./scripts/ci.sh
dune fmt 2>/dev/null; git add vtree src test
GIT_EDITOR=true git commit -F - <<'MSG'
TextView: a controlled buffer, and a cursor policy written down

The text is controlled on spec §6.5's rule, and the caret is saved as a
character offset across the write -- exact when the model echoed or rewrote in
place, approximate when it changed the length before the cursor, and clamped by
GTK when it shortened the text. That is a policy rather than an accident and
the impl says so at length, because the alternatives (a text diff in a widget
impl, or the caret at the end after every write) are both worse.

[changed] is connected to the GtkTextBuffer, not the view: the first signal in
this library on a long-lived object that is not the widget, and the first test
that can catch a connection naming the wrong object -- destroying the view and
then emitting on the buffer must fire nothing.

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01Sg3Ci8U8kUKR8C3PL1pNSs
MSG
```

**Review focus:** that `set_text`'s trailing argument is `-1` and commented; that no `Text_iter` is held across a write; that the disconnect-from-the-buffer test would fail if `connect` named the widget (try it); that `Live_tree`'s truncation is documented and that some test still pins the full text.

---

