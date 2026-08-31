# Task 9 report — TextView: a controlled buffer, and a cursor policy stated out loud

**Commit:** `8848e2b` on `m2`, base `ced908d`. 28 files, +1388/−18.
**Gate:** `nix develop -c ./scripts/ci.sh` → `all green`, exit 0.

Everything the brief lists landed, plus the two extras the ledger asked for (a bench-style
guard on the idle frame, and a GC-churn regression on the buffer wrapper). One carry from
Task 8's review (N9) taken. Two binding defects found and recorded; one of them shaped the
implementation.

---

## Per-step summary

**Step 1 — the failing tests.** Written first, all five files red on `Unbound value
Node.text_view` (captured before any implementation existed):

| File | What it pins |
| --- | --- |
| `test/test_widgets.ml` | constructor + all nine defaults dropping out of the sexp; `equal_props`/`same_kind` |
| `test/handle/test_handle.ml` | the declined edit headlessly (accept / refuse / accept again), and the entry-only attrs a text view rejects |
| `test/test_events.ml`, `test/live/live_events.ml` | the `all_kinds` rows and the `Kind.Variants.descriptions` count |
| `test/live/live_text.ml` | the six cases the brief enumerates, plus the bench, the GC block, the multi-byte caret and the `Driver.frame` decline |

**Step 2 — run to verify failure.** Five compile errors, one per file. Recorded.

**Step 3 — `vtree/wrap_mode.ml`.** Four constructors, `None_` for the shadowing reason,
mapped in `w_text_view.ml`. `Defaults.Text_view.wrap = Wrap_mode.None_`. `Node.text_view`'s
doc says `Word_char` is what a notes field wants and `None_` what a code field wants.

**Step 4 — `src/widgets/w_text_view.ml`.** As the brief specifies, with one addition
(the cache — see "The idle-frame cost strategy" below, which is the deviation that matters
and the one the ledger asked for a decision on).

**Step 5 — `Live_tree`.** A `"GtkTextView"` arm printing the text truncated at 60
characters with an ellipsis, `wrap` when not `NONE`, `read-only`, `monospace`, `no-cursor`,
`tab-moves-focus`, and each margin when non-zero. The truncation is documented beside the
arm, and the comment names the block in `live_text.ml` that prints a long text in full
(`long text length: 129` … `the buffer holds it in full: true`), so the golden's inability
to pin a long text is a stated limit with a stated compensation.

**Step 6 — gate and commit.** `ci.sh` green; commit message as the brief wrote it, with a
third paragraph for the cache.

---

## Stub-safety table

Read from the stubs in `.ocgtk-src/…/gtk/generated/`, not from the GIR — the rule
`docs/m1-backlog.md` states after Task 6.

| Call | Transfer | Stub does | Verdict |
| --- | --- | --- | --- |
| `Text_view.get_buffer` | none | `g_object_ref_sink(result)` before wrapping | **safe.** Correct for transfer-none; the wrapper's finaliser unrefs. One ref + one custom block per call, so it is not free — rationed by the cache. Regression test in `live_text.ml` (500 wrappers + `full_major`, buffer identity and text unchanged). |
| `Text_buffer.get_bounds` / `get_iter_at_offset` / `get_start_iter` / `get_end_iter` | n/a (out params) | `Val_GtkTextIter(&stack_local)` → `copy_GtkTextIter` → `g_boxed_copy` + a `g_boxed_free` finaliser | **safe.** Every iter is a GC-managed copy, so no stack pointer escapes. |
| `Text_buffer.get_text` | **full** | `caml_copy_string(result)`, **no `g_free`** | **LEAKS.** ~1 MB leaked per read of a 1 MB buffer, confirmed: 200 reads grew RSS by 201 MB and `Gc.full_major` reclaimed none. Recorded in `docs/m1-backlog.md`; drove the design. |
| `Text_buffer.set_text` / `place_cursor` / `get_cursor_position` / `get_char_count` | n/a | plain calls; `get_cursor_position` goes through a `GValue` and unsets it | safe. |
| `Text_buffer.on_changed` | n/a | generated closure; `Signals.disconnect` releases it | safe, and the disconnect is what `live_text.ml` case 6 pins. |
| `Text_view.set_*` (nine setters) | n/a | plain calls | safe. |

`set_buffer` is deliberately **not** called anywhere: swapping the buffer would strand the
`changed` connection on the old one. Said in the impl and in `Node.text_view`'s doc.

### The two binding defects, recorded

1. **No transfer-full *string* return is freed anywhere in the generated stubs.**
   `gtk_text_buffer_get_text` is the one M2 walks into; `get_slice`,
   `Text_iter.get_text` and `Text_iter.get_slice` are the same shape, so there is **no
   non-leaking way to read a text buffer** through the pinned binding. The generator
   already frees transfer-full *arrays* (`g_free(result)` after the copy loop, 40-odd
   sites), so the miss is specifically the single-`char*` path — a generator fix, like the
   `Val_GList_with` one. Written up in `docs/m1-backlog.md` for Task 14.

2. **GLib handler ids come from one global counter, not a per-instance one** (measured:
   118/119/120 across two buffers and a view). So `signals.mli`'s worse case for a wrong
   disconnect — "at worst disconnects an unrelated handler that happens to share the
   number" — cannot happen on this GLib: the wrong disconnect logs
   `instance '0x…' has no handler with id 'N'` and leaves the real handler connected. The
   bug is still real and still the one `Signals.connection` exists to prevent; only the
   second clause of the doc is theoretical, and the backlog says so.

---

## The cursor policy

Written at length in `w_text_view.ml` (the brief's paragraph, verbatim in substance) and
again, in the application's vocabulary, on `Node.text_view` in `node.mli` — because it is a
promise to the caller, not an implementation note.

**The policy:** the caret is saved as a **character offset** before the write and restored
after it. The selection is **not** preserved.

**Measured behaviour it rests on** (probed live before the code was written):

- `set_text` moves the caret to the end (offset 10 on a 10-character rewrite).
- Restoring a saved offset works exactly (`cursor restored: 4`).
- Restoring an offset past the end **clamps** rather than raising: offset 4 restored into a
  2-character buffer gives 2. So `get_iter_at_offset` needs no guard.
- `set_text` **collapses the selection**, even when the text written is identical
  (`selection before: true` → `selection after rewriting the same text: false`). That is
  why the selection is not restored and why an echo must not write.
- `set_text` emits `changed` **synchronously**: once over an empty buffer, twice over a
  non-empty one (a delete and an insert) — including when the text written is identical,
  which is the sharp reason a no-diff frame must not write.

**Where the policy is exact, and where it is not:**

| Case | Result | Pinned by |
| --- | --- | --- |
| model echoes what was typed | nothing written, caret does not move | `echo is a no-op: … cursor=2 (the patch wrote: false)` |
| model rewrites in place, same length | offset survives | `same-length rewrite: text="A STYLED NOTE" cursor=5` |
| model shortens past the caret | GTK clamps to the end | `shorter rewrite: text="short" cursor=5` |
| model changes length *before* the caret | caret lands wrong by that much | documented, not tested — it is the stated approximation |
| multi-byte text | the offset is characters, not bytes | `accented rewrite: … cursor=7` on a 16-byte / 13-character text |

---

## The idle-frame cost strategy, with numbers

**This is the deviation from the brief's literal code, and it is the one the ledger asked
for.** The brief's `set_text_if_needed` opens `if String.equal (read w) text` — a whole
buffer read on **every** `reassert`, and `reassert` runs on every patch *and* on every
no-change frame through `Patcher.reassert_only`. Measured on this machine:

- one whole-buffer read of 1 MB: **0.42 ms** (2.5% of a 16.7 ms frame), **and 1 MB leaked**
  — 60 MB/s with the application doing nothing;
- `String.equal` over the same megabyte: **0.032 ms** (1.9% of a frame), for a question
  whose answer never changes.

So the literal code is not viable for the widget whose whole point is holding a lot of
text. What shipped instead:

**A per-view cache of what the buffer holds, invalidated by the buffer's own `changed`.**
A weakly-keyed (`Ephemeron.K1`, on the `Widget.t` the patcher retains — `w_search_entry`'s
echo-record pattern, and `Child_keys`' invariant in a smaller place) record of
`{ mutable text; mutable stale }`. Invariant: *while `stale` is false, `text` is what the
buffer holds.* Maintained by three facts:

1. every write knows what it wrote and sets the cache **after** the write (the write's own
   synchronous `changed` has already set `stale`);
2. every read refreshes the cache and clears `stale`;
3. `stale` is set by a handler wrapped **inside** the `changed` spec's `connect` — so it
   runs on *every* emission, including the ones `Signals.dispatch` drops for `in_patch` and
   the ones that reach an empty slot, which are still edits. One connection, disconnected
   correctly at teardown. A `GtkTextBuffer` emits `changed` for every insert and delete
   whatever caused it, so there is no third way for the text to change.

**Plus a `phys_equal` fast path with adoption.** `reassert_only` runs precisely on frames
where Bonsai handed back the physically same node, so the string offered is the *same
value* the last write stored — a pointer comparison. When the strings are equal but not
physically so (the frame after a user edit the model echoed: the cache holds GTK's string,
the node holds the model's), the node's string is adopted into the cache, which turns a
steady state that would `memcmp` a megabyte every frame forever into one that compares a
pointer.

**Result, asserted in the golden as a ratio rather than a wall clock** (Task 7's N1, in the
form Task 7 settled on — the property is that the cost does *not* scale with the buffer, so
contention cancels):

```
bench: 20000 idle frames over 16 and over 1000000 characters, cost ratio under 5: true
bench: 0.00018 ms at 16 chars, 0.00010 ms at 1 MB, ratio 0.57 (bound 5)
```

An idle frame over a megabyte costs ~0.1 µs — 4000× less than the read it replaces — and
allocates and leaks nothing. Reading the buffer back each frame would put the ratio in the
hundreds. (Frames were raised from 500 to 20 000: at 0.1 µs a frame, 500 of them total
40 µs, which is a measurement made of timer noise; the ratio wandered between 1 and 3 run
to run at that scale and is stable at 20 000.)

**The one gap, stated in the impl:** a write GTK does not take in full — invalid UTF-8, or
a text with an embedded NUL, which the `-1` length terminates at — leaves the buffer
holding something other than what was written, and the cache (which records the *write*
rather than re-reading) diverges. That costs **one** write rather than one per frame, which
is Task 3's `max_length` lesson applied to the only shape it can take here; a user edit
re-reads and the cache becomes truth again. Re-reading after every write would close the
gap exactly and reintroduce the per-frame-forever loop for the same input, which is the
worse trade.

`set_text`'s trailing argument is `-1`, commented as "GTK's NUL-terminated, not a character
count", with the note that `String.length` is the other correct spelling and differs only
for a text with an embedded NUL. No `Text_iter` is held across a write — the impl never
holds one at all.

---

## The live tests, and one that started out vacuous

`test/live/live_text.ml` (+ `expected_text.txt`, + a `dune` rule). The six cases the brief
lists, in order, plus four more.

**Case 6 needed rewriting to be worth anything, and the brief's "try it" is what found
that.** As first written it destroyed the view and emitted `changed` on a buffer handle it
still held. With `connect` mutated to name the **widget** instead of the buffer, the file's
output was **byte-identical** — because `Patcher.destroy` calls `Signals.clear_slots`
*before* `Signals.disconnect`, and an emptied slot makes a still-connected callback inert.
The test was measuring the first protection and claiming the second.

Fixed by isolating the disconnect: the child `live`'s slots and attrs are taken before the
destroy, and after it the slot is **re-armed** with `Signals.update_slots` (with
`Signals.armed` printed first, so a re-arm that quietly did nothing would not make the next
line vacuous in turn). Re-verified by mutation:

```
                                                          shipped   connect names the widget
slots re-armed after the destroy: (On_changed)            (On_changed)   (On_changed)
with the slot re-armed, an emission … reaches Bonsai:          0              1
```

The comment in the file records both halves and the mutation result, so a later reader does
not re-derive it.

**The other blocks:**

- **Props**, set and then all moved back to GTK's own, so the dump shows both that they
  land and that they drop.
- **The reentrancy case** — a programmatic write emits `changed` on the buffer,
  synchronously, from inside the patch: `reached Bonsai across every patch above: 0`,
  while the same signal outside a patch reaches Bonsai (`: 1`). First non-widget GObject
  in this library to go through the `in_patch` guard.
- **No-diff frames write nothing**: `ten idle frames wrote: 0 (text="short" cursor=2)` —
  text *and* caret unmoved, which is the claim a write count alone would not make.
- **GC churn on the buffer wrapper**: 500 `get_buffer` wrappers made and collected across
  five `full_major`s, buffer identity and text unchanged each time; flushed per batch,
  because the failure it guards against is a segfault.
- **`require_specs` negatives**, live and headless: `On_activate` and `On_search_changed`
  rejected on a `TextView`. `On_activate` is the one worth having — an entry has it, a text
  view does not (Enter inserts a newline), so it is exactly the line a reader copies across.
- **The declined edit through a real `Driver.frame`**, which the hand-driven patches cannot
  claim: a model refusing anything over ten characters, the user typing into the real
  buffer, GTK's `changed` → the trampoline → the driver's idle → the correcting frame.

```
driver, user typed too much, before the frame: "ok far too long"
driver, after the frame the refusal armed: "ok" (handler saw (ok"ok far too long"))
driver, one more frame: "ok" (handler saw 0 more)
```

The last line is the half that says the correction is not a loop: the correcting write did
not feed itself back in.

- **Multi-byte**, because the caret is a *character* offset over a buffer addressed in
  characters while OCaml's string is bytes: a 16-byte / 13-character text round-trips, and
  offset 7 lands on a character boundary a byte offset would have put inside an `é`.

---

## Deviations, with reasons

1. **The cache** (above). The brief's `read w` on every `reassert` is replaced by a cached
   comparison. Reason: 0.42 ms **and a 1 MB leak** per idle frame at 1 MB, both measured.
   The ledger asked for exactly this decision and for it to be documented; it is, in the
   impl and here.
2. **The cache stores what was written, not a re-read.** Reason: one write instead of one
   per frame when GTK declines part of a write. Task 3's `max_length` rule.
3. **`live_text.ml` case 6 re-arms the slots after the destroy.** Reason: without it the
   test is vacuous, proven by mutation. Documented in the file.
4. **The bench uses 20 000 frames, not the lists bench's 200.** Reason: a 0.1 µs frame
   needs that many to be a measurement rather than timer noise.
5. **No `justification`.** The brief's interface does not list it and neither does its
   `Live_tree` step; not added.
6. **`Kind.same_kind` and `Kind.equal_props` needed new arms** — not in the brief's file
   list, and both have `| _ -> false` wildcards, so omitting them compiles. See "Carries"
   item 1; the `equal_props` test written in Step 1 is what caught it.
7. **`src/patcher.ml`** needed two arms (`interest_of_kind`, `destroy`) — exhaustive
   matches, so these were compile errors rather than a hazard. Not in the brief's file
   list either.

No scope was dropped.

---

## Carries taken

- **`task-8-review.md` N9 (wording).** Taken. The forward-move block's header in
  `test/live/live_lists.ml` blamed the page count for something that is `~after`'s
  position; corrected to the reviewer's suggested wording, with a parenthetical recording
  what was wrong and why, so the ledger does not inherit a third stated-reason defect. The
  same paragraph in `task-8-report.md` is corrected to match.
- **Task 8 report carry 3 (`Tab_position` is an unlisted public module).** Nothing to do
  here beyond noting that `Wrap_mode` is now a second one — added to the carry below for
  Task 15/16 rather than acted on.
- Task 8's carries 1, 2, 4, 5 and 6 are about the list containers and the notebook and have
  no text-view analogue; not applicable, not silently dropped.

---

## Test and CI tails

```
== live tests (xvfb)
bench: 0.371 ms at sel=1, 0.414 ms at sel=200, ratio 1.11 (bound 5)
bench: 0.00018 ms at 16 chars, 0.00010 ms at 1 MB, ratio 0.57 (bound 5)
== example smoke
all green
```

`test/live/expected_events.txt`: `kinds checked: 32` → `33`. Every other golden unchanged;
`expected_text.txt` is new.

---

## Carries to Task 10

1. **`Kind.same_kind` and `Kind.equal_props` end in `| _ -> false`.** A kind added without
   arms in both compiles clean and is *silently* wrong in the worst way available: the
   patcher sees every patch of that kind as a kind change, so it destroys and remounts —
   losing the caret, the selection, the focus and every signal connection, on every frame
   that touches the widget. `Events.for_kind` and `Placement.reader` have no wildcard for
   exactly this reason; these two do, and they are the two places a new kind is most likely
   to be forgotten. Task 10 adds `Level_bar`: **add both arms, and consider whether the
   wildcards should go** (`same_kind` can be written as a `Kind.name` comparison or with a
   full matrix; `equal_props` cannot avoid the wildcard without 32² arms, but a
   `same_kind a b && …` guard in front of it would turn the silent case into a reachable
   `assert false`). Caught here only because Step 1 wrote an `equal_props` test.
2. **`Wrap_mode` is a second public module in `Bonsai_gtk` the plan does not list**, beside
   Task 8's `Tab_position`. Task 15's docs and Task 16's spec §7 / §5.1 sweep should
   account for both, and for `?wrap`.
3. **There is no non-leaking way to read a `GtkTextBuffer` through the pinned binding.**
   Anything later that wants a buffer's text — a save action, a search, a diff — pays a
   full-length leak per call. `Live_tree`'s dump does, and is test-only. See
   `docs/m1-backlog.md`; it is a generator fix, and it is the second-most valuable of the
   fork patches after the `Val_GList_with` one.
4. **The cache's invariant is not defended by a test that reads the buffer independently
   on an idle frame** — doing so would itself leak, and would defeat the thing under test.
   What defends it instead is the ratio bench (a frame that read the buffer could not be
   size-independent) plus every `text=%S` line in the file, each of which *is* an
   independent read taken outside a frame. Worth knowing before anything relaxes the bench.
5. **A `notify::cursor-position` attr is the hook for an application that wants to own the
   caret**, which is what closes the stated approximation in the cursor policy. Named in
   `Node.text_view`'s doc as backlog; not filed anywhere else yet.
6. **`Attr.on_changed` now covers two different GTK signals on two different object kinds**
   (`GtkEditable::changed` and `GtkTextBuffer::changed`). Its doc says so. A third would be
   a good moment to ask whether the attr name is still carrying its weight.

---

# Task 9 report — Fix round 1

**Commit:** `1c61269` on `m2`, base `8848e2b`. 14 files, +428/−44.
**Gate:** `nix develop -c ./scripts/ci.sh` → `all green`, exit 0.

I1 taken as ruled, and all six Minors taken — none needed arguing. Every claim in the
review was re-verified against GTK before being acted on rather than taken on trust; the
probe output is below each heading.

---

## I1 — a write GTK refuses is now refused here instead

**Verified first.** The reviewer's table reproduces exactly, and the sharper half is worse
than the first round's comment implied — the previous contents are *destroyed*, not merely
left unwritten:

```
model text          validate   buffer (held "PREVIOUS CONTENTS")   diagnostic
"caf\xc3\xa9 latte" true       "café latte"                        —
"caf\xe9 latte"     false      ""                                  Gtk-CRITICAL
"ab\x00cd"          false      "ab"                                none at all
```

`gtk_text_buffer_set_text` deletes the whole buffer and then inserts, and
`gtk_text_buffer_emit_insert` guards the insert with
`g_return_if_fail (g_utf8_validate (text, len, NULL))` — so the delete lands and the insert
does not. `Glib.Utf8.validate` (`ml_glib.c:489`, which passes `caml_string_length` rather
than `-1`) answers `false` for both shapes, so it catches the NUL case too on this GLib.

**The fix, as ruled.** `set_text_if_needed` validates before writing; an unstorable text is
refused, the buffer and the cache are both left untouched, and the reason is recorded for
the patcher to report. The cache therefore keeps describing the buffer, which is the part
the first round got wrong: caching what was *attempted* left `holds` answering `true`
against a buffer holding something else.

The NUL check is kept separate from `validate` and is not redundant defence: `set_text`'s
`-1` means NUL-terminated, so GTK stores the prefix *silently*. `validate` happens to reject
NUL bytes today; naming the case separately is what keeps the silent shape from returning if
that changes, and lets the message say which of the two happened.

**Reported once, with the node path, through a real channel.** A `Widget_impl` is handed a
widget and a kind — it knows neither where it is in the tree nor how the runtime reports,
and `Signals.ctx.on_exn` is neither reachable from one nor the right meaning (it reports an
exception raised while *dispatching a signal*). So:

- `Patcher.ctx` gains `report : node_path:string -> string -> unit`, optional on
  `create_ctx` with an `eprintf` default on the library's usual `bonsai_gtk: ` channel —
  the same shape `scheduler.ml`, `loop.ml` and `gtk_effect.ml` already use. A hook rather
  than an inline `eprintf` so a test can capture the message instead of racing stderr
  against a golden, and so a later milestone can route it somewhere an application sees.
  `create_ctx` gains a trailing `unit` (13 call sites, mechanical).
- `Text_view` becomes a patcher `interest`. `enqueue_fixups` is the one place holding both
  the widget and the path of the node it came from, and it runs after `create` on a mount
  and after `reassert` on a patch and on an idle frame — the three places a write can be
  refused. It enqueues nothing and allocates nothing unless there is something to say; the
  cost is one ephemeron lookup per text view per frame.

**Reported once, not once per frame.** The refusal is remembered against the *text* (with
the string adopted, so later frames answer in a pointer comparison), not against the widget.
A model that keeps asking pays one validation and one message; a model that changes to a
different unstorable text is a new datum and is validated and reported again.

**The live block, red before the fix.** Written against the plumbing before the guard
existed, so the red is the real behaviour and not a compile error:

```
                                    before (8848e2b)              after (1c61269)
mounted: "a good note"              reports ()                    reports ()
latin-1                             buffer ""                     buffer "a good note"
                                    reports ()                    reports ((bad/0 "…not valid UTF-8…"))
  five idle frames later            buffer ""     reports ()      buffer "a good note"  reports ()
embedded NUL                        buffer "ab"   reports ()      buffer "a good note"  reports ((bad/0 "…NUL byte…"))
  five idle frames later            buffer "ab"   reports ()      buffer "a good note"  reports ()
a valid text after two refusals     "café latte"                  "café latte"
latin-1 again (after a valid write) buffer ""                     buffer "café latte"   reports ((bad/0 "…"))
mounted with unstorable text        —                             buffer ""             reports ((born/0 "…"))
```

Four claims beyond the reviewer's three: that the same text refused again *after a valid
write in between* is a new decision and is reported again; that a valid text after two
refusals still lands (the fix is not "never write again"); that five idle frames after a
refusal cost nothing and say nothing; and the mount-time case, which is the likeliest way an
application meets this — a read-only pane rendering bytes off disk, wrong from the first
frame. Mutation-checked: deleting the refusal memory turns the "five idle frames later" line
from `reports ()` into five copies of the message.

**Documented on `Node.text_view`**, in the application's vocabulary: `text` must be valid
UTF-8 without a NUL; what GTK does to each; that the library refuses and reports rather than
letting it through; that the model is not wedged; and that `~editable:false` over
bytes-off-disk is where this bites and decoding at the edge is the answer.

**The bench is unaffected**, as required — validation is O(len) on write frames only, which
already pay O(len) for the write, and an idle frame never reaches it:
`bench: 0.00035 ms at 16 chars, 0.00012 ms at 1 MB, ratio 0.35 (bound 5)`.

---

## Minors — all six taken

**M1 (the `changed` closure captured the cache record).** Now `(state w).stale <- true`,
which is what `fire` on the next lines already does. One ephemeron lookup per emission buys
away the cache's only *silent* failure shape, and the comment records why the capture looked
safe (the key is held by `live.widget` and by the closure `connect_all` roots) — reasoning
three hops long that lived nowhere near the code.

**M2 (the "shorter rewrite" line cannot distinguish clamping from doing nothing).** Correct,
and I reproduced it: deleting the restore leaves that line byte-identical while moving the
other three. The comment now claims what the line shows — that `get_iter_at_offset` past the
end does not raise — and says why no stronger test exists (a clamp lands where not restoring
lands, so they are indistinguishable by construction).

**M3 (60 bytes, documented as 60 characters).** `Live_tree` now truncates on a character
boundary, by the same continuation-byte rule `W_entry.capped` uses, with the comment saying
so. Pinned by a new case whose 60th character straddles the boundary:

```
(text "xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx\195\169...")
```

59 `x`s and a whole `é`. A byte prefix would end `…xxx\195...`.

**M4 (`Wrap_mode.Char` unexercised).** A patch setting `~wrap:Char` in `live_text.ml`'s
first block; the golden now carries `(wrap char)`. Mutation-checked: `| Char -> \`WORD`
prints `(wrap word)` and fails.

**M5 (the selection claim documented twice, tested nowhere).** Taken with the reviewer's
better property. A selection is set with the caret assertions already made (after them, so
`select_range` does not move the caret this file pins), then:

```
selection held: true
echo again, with a selection standing: … (the patch wrote: false)
selection after an echo: true
model rewrites: … (the patch wrote: true)
selection after a write: false
```

"The echo writes nothing" is not a cost saving — it is what keeps a selection standing under
a model that echoes as you type, which is a stronger promise than the doc made.

**M6 (`docs/m1-backlog.md` overstates what the cache buys).** Corrected, and sharpened: the
entry now says explicitly that the cache fixes the *idle* path only and **cannot** fix the
edit path, because `Attr.on_changed`'s contract is to hand the handler the buffer's full
text — so every keystroke in a 1 MB document costs 0.42 ms and leaks 1 MB, and sustained
typing leaks several MB a second. That is the number a Task 14 implementer should weigh.

---

## Deviations in this round

One, and it is the shape of the reporting channel rather than its behaviour. The ruling said
"`ctx.on_exn` or whatever the driver's reporting hook is". `Signals.ctx.on_exn` takes an
`exn`, means "raised while dispatching a signal", and is not reachable from a widget impl;
threading a `~path` into `Widget_impl.create`/`reassert` instead would have touched all 32
impls. A new `Patcher.ctx.report` plus a `Text_view` interest was the smallest change that
carries the node path, is testable, and puts the sink in one named place. Its default is the
`eprintf` the ruling wanted avoided *at the call site* — the library's existing channel,
reached through a hook rather than printed ad hoc.

---

## CI tail

```
== live tests (xvfb)
bench: 0.368 ms at sel=1, 0.425 ms at sel=200, ratio 1.16 (bound 5)
bench: 0.00035 ms at 16 chars, 0.00012 ms at 1 MB, ratio 0.35 (bound 5)
== example smoke
all green
```

Only `expected_text.txt` moved. No other golden changed.

---

## Carries to Task 10 — revised

Items 1–6 of the first report's list stand, with these changes:

- **Item 4 is closed.** The cache's invariant is now defended by a test that reads the
  buffer independently after a refused write, on the path where the cache and the buffer
  could most easily disagree.
- **New: `Patcher.ctx.report` has one caller.** If a second kind needs to say "the model
  asked for something I cannot hold", it should use this rather than inventing a channel —
  and the two candidates already exist in the ledger: Task 8's hidden-page divergence and a
  `~selected` a list box's mode cannot hold, both recorded as "a model to bring into line"
  with no way to tell anyone. Both are `interest`s already, so both are one line from a
  message. That is the development-mode warning Task 8's carry 4 asked for, now that
  somewhere exists to put it.
- **New: the refusal is remembered per text, not per widget.** A model alternating between
  two unstorable texts reports on every frame. Bounded (one message per change of text) and
  correct, but worth knowing before anything routes `report` somewhere noisier than stderr.

---

# Task 9 report — Fix round 2

**Commit:** `d9f9d93` on `m2`, base `1c61269`. 3 files, +129/−36.
**Gate:** `nix develop -c ./scripts/ci.sh` → `all green`, exit 0.

R1 taken as ruled. The finding is correct in all three of its parts, and I reproduced the
regression independently before touching the code — including the part that is a comment
telling a lie about the code beside it, which is the species this milestone's review rounds
keep catching.

---

## R1 — a parked refusal is now decided before anything is compared

**Reproduced first, with the bench arm the ruling asked for.** Written against round 1's
code, so the red is the real behaviour:

```
                                     before (1c61269)   after (d9f9d93)
settled, 16 chars                    0.00020 ms         0.00021 ms
settled, 1 MB                        0.00012 ms         0.00013 ms
parked on a refused 1 MB write       0.06159 ms         0.00015 ms
  ratio against a settled 1 MB frame    517.86             1.14      (bound 5)
  golden verdict                        false              true
```

**Why it happened.** Round 1's fix is what created the state: after a refusal the buffer
holds the old text and `st.text` correctly describes it — that is the fix — while `p.text`
is the unstorable one. So `holds` answers `false` on every subsequent idle frame, and each
of them ran a whole-buffer `String.equal` in `holds`, then `batch_if true` (a
`freeze_notify`/`thaw_notify` pair), then `set_text_if_needed`, which ran `holds` a **second
time** before reaching the memo. `String.equal` short-circuits on length, so this is
invisible whenever the refused text and the buffer's differ in length — and a log tail or a
file preview re-rendering a similar-length document is exactly where they coincide.

It is the same property the headline bench exists to pin, violated on a path that bench
structurally cannot see, because it mounts a *storable* text.

**The fix.** `already_refused` is now a function of its own, consulted **first** in
`reassert`:

```ocaml
let writes = (not (already_refused st p.text)) && not (holds w st p.text) in
```

Safe, and the reason is written into the function's comment rather than left to be
re-derived: `unwritable` is pure, so a text refused once is refused always; and
`st.refused` is cleared by every successful write. A matching memo therefore means the
write can only fail, so the frame has nothing to compare and nothing to bracket. Skipping
`holds` also skips its `refresh`, which is right and slightly better — `stale` stays set
until the model offers a text GTK will take, and that frame pays the one read it genuinely
needs.

**The comment that was lying.** Round 1's memo comment claimed "the string is adopted so
that the frames after it answer in a pointer comparison". There was no adoption:
`st.refused <- Some text` ran only when the refusal was first decided, so a model that
rebuilds an equal string each frame re-ran `String.equal` against the memo forever. `holds`
adopts; the memo did not. `already_refused` now does, and its comment records that the
claim came before the code.

**The `batch_if` claim** two lines above ("must pay neither the write nor the freeze/thaw")
was also false on the parked path in round 1. It is true again — a parked frame now takes
neither.

---

## The bench arm

A third measurement, and the shape of it is the point: the refused text is the **same
length** as the one the buffer holds and differs only in its last byte. `String.equal`
short-circuits on length, so a refusal whose text is a different length costs nothing to
notice and would have flattered the measurement into passing. Same length, one byte apart,
is a full memcmp — the worst case, on purpose, and the realistic one.

It is also self-checking in a second way. The bench's `ctx` takes a `report` that counts
rather than prints (which keeps the gate's stderr clean as a side effect), and the count is
in the golden:

```
bench: settled, buffer holds 16 characters (refusals so far 0)
bench: settled, buffer holds 1000000 characters (refusals so far 0)
bench: parked on a refused write, buffer holds 1000000 characters (refusals so far 1)
bench: refusals reported across every frame above: 1
bench: an idle frame parked on a refused 1 MB write, against a settled one, under 5: true
```

The buffer still holding 1 000 000 characters is what says the write was really refused;
`refusals so far 1` says it was reported; and `1` after twenty thousand parked frames pins
"reported once" over a duration no other test covers.

Mutation-checked: restoring `let writes = not (holds w st p.text)` gives
`under 5: false` and `ratio 517.75`.

---

## Every golden outside the bench is unchanged

As required, and verified rather than assumed — the whole diff against the promoted golden:

```
-|bench: buffer holds 16 characters
-|bench: buffer holds 1000000 characters
+|bench: settled, buffer holds 16 characters (refusals so far 0)
+|bench: settled, buffer holds 1000000 characters (refusals so far 0)
+|bench: parked on a refused write, buffer holds 1000000 characters (refusals so far 1)
+|bench: refusals reported across every frame above: 1
+|bench: an idle frame parked on a refused 1 MB write, against a settled one, under 5: true
```

Nothing else moved: the refusal block, `a valid text after two refusals`, `latin-1 again`
reporting a second time, the mount case, the caret lines, the selection lines, the
disconnect block and the driver block are all byte-identical. `dune test` and the headless
suite are unchanged too. The reordering is behaviour-preserving on everything the suite
pins.

---

## Deviations in this round

None.

---

## CI tail

```
== live tests (xvfb)
bench: 0.373 ms at sel=1, 0.419 ms at sel=200, ratio 1.12 (bound 5)
bench: 0.00021 ms at 16 chars, 0.00013 ms at 1 MB, ratio 0.63 (bound 5)
bench: 0.00015 ms parked on a refused 1 MB write, ratio 1.14 (bound 5)
== example smoke
all green
```

---

## Carries to Task 10 — unchanged from fix round 1

The revised list stands. One observation to add rather than a carry: **round 1's fix created
round 2's regression**, and neither round's tests would have caught it without the bench arm
being asked for specifically. The general shape — "a controlled prop the widget refuses
leaves `reassert` deciding *not* to write, expensively, on every frame forever" — is not
text-view-specific. Task 8's hidden-page divergence and a `~selected` a list box's mode
cannot hold are the same shape and are both already in the ledger as "a model to bring into
line"; whichever task gives them the `report` hook should check what their parked frames
cost at the same time.
