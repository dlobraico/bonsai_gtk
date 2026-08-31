# Task 9 review — TextView: a controlled buffer, and a cursor policy stated out loud

**Commit reviewed:** `8848e2b` on `m2`, base `ced908d`. Diff read in full
(`review-ced908d..8848e2b.diff`, 28 files, +1388/−18).

**Gates re-run independently, all green:**

```
nix develop -c dune build                                              exit 0
nix develop -c dune test                                               exit 0
BONSAI_GTK_LIVE_TESTS=1 nix develop -c xvfb-run -a dune build @test/live/runtest   exit 0
nix develop -c ./scripts/ci.sh                                         all green, exit 0
  bench: 0.00019 ms at 16 chars, 0.00010 ms at 1 MB, ratio 0.50 (bound 5)
```

Mutation work was done in a throwaway worktree (`git worktree add /tmp/m2-t9-verify
8848e2b`), now removed; no tracked file in the checkout was modified.

---

## Summary

This is the strongest task in M2 so far on the two axes that matter most for it. The
headline deviation — a cached last-written text plus a `changed`-driven staleness flag
instead of a buffer read per `reassert` — is not just justified in prose, it is
**forced**: I reproduced the alternative and it is 757× more expensive per idle frame at
1 MB *and* leaks the buffer every frame, because `ml_gtk_text_buffer_get_text` really does
omit `g_free` on a `transfer-full` return. And the one test the brief flagged as the most
valuable in the task — teardown disconnecting from the *buffer* rather than the view — is
non-vacuous: I re-pointed `connect` at the widget and the golden moved, on the line the
implementer added specifically to make it move.

Every stub citation in the report's stub-safety table checks out against
`.ocgtk-src/…/generated/`, including the two that carry the design (`get_buffer` does
`g_object_ref_sink`; `get_text` does not `g_free`). The `Gobject.same` / `Stdlib.Hashtbl.hash`
pairing the ephemeron rests on is real — `wrappers.c` installs `hash_gobject` as a pointer
hash and `compare_gobject` as pointer identity, so the invariant `child_keys.ml` asserts
and this file inherits is true rather than assumed.

I found one Important issue and six Minors. The Important one is the path the review brief
asked me to hunt for — "a `~text` that equals the cache but the buffer differs" — and it is
real, reachable, permanent rather than transient, and in one of its two shapes completely
silent. It is on an uncommon input (non-UTF-8 or NUL-bearing model text), the impl already
names it as a known gap, and the fix is cheap and already bound in the pinned binding, so
it is Important rather than Critical.

Nothing about memory safety, reentrancy, the signal contract, the counts, or the props is
wrong. No scope creep.

---

## Per-deviation judgement

**1. The cache (a per-view `{text; stale}` weakly keyed on the widget) instead of a
buffer read per `reassert`. — Accepted, and the ledger's requested decision is settled
in its favour.**

I reproduced the brief's literal code by replacing `holds` with `String.equal (read w) text`
and re-running the live suite. Two results:

```
                        shipped                     literal read-back
bench ratio             0.57  (bound 5) -> true     757.09 (bound 5) -> false
per idle frame at 1 MB  0.00010 ms                  0.44902 ms
```

That is the deviation's whole case, measured on this machine rather than taken on trust,
and it matches the report's numbers. Add the leak — 1 MB per frame, forever, with the
application idle — and the literal code is not shippable for this widget.

The second result matters as much: **the literal read-back produced no other diff at all.**
Every correctness line in `expected_text.txt` was byte-identical between the cache and a
frame that re-reads the buffer. So on every path the suite exercises, the cache is
observationally equivalent to the thing it replaces. That is the best available evidence
that the deviation is behaviour-preserving, and it is worth recording in the ledger.

I also traced the invariant by hand for the paths the brief named, and it holds:

- *user edit* — `changed` fires on the buffer; the invalidator is wrapped **inside**
  `connect`'s callback, before `Signals.dispatch`, so it runs on emissions dropped for
  `in_patch` and on emissions reaching an empty slot too. `Signals.connect_all`
  (`src/signals.ml:100`) connects every spec unconditionally at mount regardless of attrs,
  so a text view carrying no `Attr.on_changed` still gets its cache invalidated — I checked
  this specifically, because if the connection were attr-conditional a handler-less text
  view would silently stop being controlled.
- *programmatic write* — the write's own synchronous `changed` (twice over non-empty text)
  sets `stale`; `st.text <- text; st.stale <- false` comes **after** the write, which is
  the only correct order and is commented as such.
- *declined edit* — pinned end to end through a real `Driver.frame` in the last block of
  `live_text.ml`, not just through hand-driven patches.
- *external buffer mutation not via the view* — unreachable: the buffer is not exposed,
  `set_buffer` is deliberately never called, and a `GtkTextBuffer` emits `changed` for
  every insert and delete whatever caused them (undo included).
- *ephemeron key lost while the widget lives* — unreachable. The key is held twice: by
  `live.widget` and by `connect_all`'s callback closure, which captures `w` and is rooted
  by the GClosure. A dropped entry would also degrade safely (a fresh record is born
  `stale` and reads before it answers) — with one exception, which is Minor 1 below.

Two mutations confirm the cache is defended rather than merely asserted:

```
mutation                                 caught by
drop `st.stale <- true` in connect       live_text: `model wins` — the user's "aXY" is
                                         no longer pulled back (wrote: true -> false)
drop `refresh w st` in fire              live_text driver block — the handler reports the
                                         pre-edit text, the whole loop reads ""
```

**2. The cache stores what was written rather than re-reading. — Accepted with a
correction; see Important 1.** The cost argument is right (one failed write instead of one
per frame, Task 3's `max_length` lesson). The consequence is understated: the divergence is
not transient.

**3. `live_text.ml` case 6 re-arms the slots after the destroy. — Accepted, and this is
the best single decision in the task.** Verified by mutation, independently:

```
                                                           shipped   connect names the widget
a changed emitted on the destroyed view's buffer ...: 0        0              0     <- vacuous
slots re-armed after the destroy: (On_changed)           (On_changed)   (On_changed)
with the slot re-armed, an emission ... reaches Bonsai:         0              1     <- the test
```

The first line is vacuous in both worlds exactly as the report says — `Patcher.destroy`
(`src/patcher.ml:431,436`) clears slots before it disconnects, so an emptied slot makes a
still-connected callback inert. Without the re-arm this task would have shipped a test that
proved the wrong protection. Finding that by doing the brief's "try it" rather than by
reading is the right instinct and the write-up records both halves.

**4. 20 000 bench frames rather than 200. — Accepted.** At 0.1 µs a frame, 500 frames is
40 µs, which is timer noise. The bound has ~9× headroom (0.50–0.57 observed across four
runs including a full `ci.sh`) and the regression it guards drives the ratio to 757, so
neither end is close. Ratio-based rather than wall-clock, in the form Task 7 settled on.

**5. No `justification`. — Accepted.** Not in the brief's interface or its `Live_tree` step.

**6/7. `Kind.same_kind` / `Kind.equal_props` / `src/patcher.ml` arms not in the brief's
file list. — Accepted, correctly placed.** `interest_of_kind` and `destroy` both put
`Text_view` in the `Nothing` / `()` groups, which is right: a text view enqueues no fixup
and needs no `forget_*` teardown (its cache is weak and keyed on the retained widget, so
collection is the teardown). The `equal_props` carry to Task 10 is the right carry to
raise and I endorse it — the wildcard turns a forgotten arm into a destroy-and-remount on
every frame, which loses the caret, the focus and every connection.

**Carries.** Task 8's N9 taken with a corrected *reason* rather than corrected wording
only, which is the right way to take it. Task 8's other five correctly judged
not-applicable rather than silently dropped.

---

## Critical

None.

---

## Important

### I1. A write GTK does not take in full leaves the view permanently wrong, and one of its two shapes is silent — `src/widgets/w_text_view.ml:60-72,168-178`

The impl names this gap and argues the trade honestly, but understates it in the one way
that matters, and nothing in the suite exercises it. I probed both shapes live (throwaway
worktree, since no test covers them):

```
model text                buffer after the write   diagnostic          after 5 idle frames   after a fresh, equal-but-not-phys-equal patch
"caf\xe9 latte"           ""                       Gtk-CRITICAL        ""                    ""
"ab\x00cd"                "ab"                     none at all         "ab"                  "ab"
```

The mechanism: `gtk_text_buffer_set_text` deletes the whole buffer and then inserts, and
`gtk_text_buffer_emit_insert` has `g_return_if_fail (g_utf8_validate (text, len, NULL))`.
So the delete lands and the insert does not — the buffer goes **empty**, not "partly
written". With `-1` and an embedded NUL the insert succeeds on the prefix and GTK says
nothing.

Because `set_text_if_needed` then caches *what it tried to write*, `holds` answers `true`
on every subsequent frame and the buffer is never touched again. The impl's sentence "that
divergence costs one write instead of one per frame" is a claim about **cost** and is
true; the sentence a reader needs — that the widget stays wrong for as long as the model
asks for the same text — is not there. And the stated recovery, "a user edit re-reads and
the cache becomes the truth again", is unavailable in a configuration this constructor
documents and supports: `~editable:false`. A read-only text view showing model-supplied
bytes — a log tail, a file preview, a diff pane — is both the likeliest source of
non-UTF-8 text and the one case where no user edit will ever heal it. There the divergence
is permanent by construction.

This is also where the deviation genuinely widens the failure rather than merely
re-shaping it. The brief's literal read-back displays the same blank buffer, but the
library's own belief never diverges from the widget, so `fire`'s payload and `holds`'
answer stay truthful; the cache is what makes the library confidently wrong.

**Failure scenario, concretely.** An application renders
`Node.text_view ~editable:false ~text:(In_channel.read_all path) ()` over a latin-1 file.
The pane renders empty. One `Gtk-CRITICAL` appears on stderr at mount. Every subsequent
frame declines to write. Nothing in the model, the node, `Live_tree.dump`'s sexp of the
node, or the headless suite reports anything wrong, and no user action can recover it. With
a NUL-bearing string there is not even the critical.

**The fix is cheap and already bound.** `Glib.Utf8.validate : string -> bool` exists in the
pinned binding (`.ocgtk-src/ocgtk/src/common/glib.ml:102`, `ml_g_utf8_validate`), and I
confirmed it answers `false` for both shapes above (including the NUL one, which GTK's own
`-1` path accepts silently). Validating in `set_text_if_needed` costs O(len) on **write**
frames only — frames that already pay O(len) for the write itself — and nothing at all on
an idle frame, so it does not touch the property the bench pins. Either of these closes it:

- refuse the write, leave the cache alone, and report once (`ctx.on_exn`, or a single
  `eprintf`) — the widget keeps its previous contents rather than going blank, and the
  library's belief stays true; or
- write anyway but leave `st.stale <- true`, which costs one buffer read on the frame after
  each write and re-opens the retry loop only for input GTK will never accept.

At minimum, if the lead prefers to ship the gap as-is: correct the comment (say that the
buffer stays wrong until the model asks for something else, and that `~editable:false`
means never), and add the four-line live block — a patch with `"caf\xe9 latte"`, a patch
with `"ab\x00cd"`, and a read-back after five idle frames — so the behaviour is pinned
rather than inferred. The absence of any test writing text GTK will not take is what let
the sharper half of this go unnoticed.

---

## Minor

### M1. The `changed` closure captures the cache record instead of looking it up — `src/widgets/w_text_view.ml:196-201`

```ocaml
let b = buffer w in
let st = state w in
Signals.connected b (W.Text_buffer.on_changed b ~callback:(fun () ->
  st.stale <- true;
  callback ()))
```

`fire` calls `state w` lazily; `connect` captures the record eagerly. That is the only way
the cache can ever be *silently* wrong: if the ephemeron entry for `w` were dropped while
the widget lived, `state w` would mint a second record, the invalidator would keep setting
`stale` on the first, and `holds` would read a `stale:false` record whose `text` is a
frame behind — a text view that stops being controlled and an `on_changed` that reports
pre-edit text, with nothing to say why.

I could not reach it: the key is held both by `live.widget` and by `connect_all`'s callback
closure, which captures `w` and is rooted by the GClosure, so the entry cannot be collected
while the connection exists. So this is latent, not live. But `(state w).stale <- true`
inside the callback costs one ephemeron lookup per emission — a lookup `fire` already does
on the same path — and removes the possibility entirely, which is worth more than the
lookup. Worth taking because the reasoning that makes it safe today is three hops long and
lives nowhere in the file.

### M2. The "shorter rewrite" line cannot distinguish clamping from doing nothing — `test/live/live_text.ml:137-141`

Mutation: deleting the `place_cursor`/`get_iter_at_offset` pair entirely moves three
golden lines (`model wins` 3→13, `same-length rewrite` 5→13, `accented rewrite` 7→13) and
leaves `shorter rewrite: … cursor=5` **byte-identical** — because GTK's clamp lands the
caret at the end of the new text, which is exactly where not restoring at all leaves it.

The caret restore itself is well pinned by the other three lines, so this is not a hole in
the cursor policy's coverage. But the comment above it says the line shows that "GTK clamps
the restored offset to the end of the new text rather than raising", and only the second
half of that is observable here: what the line actually proves is that
`get_iter_at_offset` past the end does not raise. No stronger test exists — clamping always
lands at the end, so the two are indistinguishable by construction. Fix the comment to
claim what the line shows.

### M3. `Live_tree` truncates at 60 **bytes**, documented as 60 characters — `src/live_tree.ml:240-268`

`String.prefix text 60` is a byte prefix. For a text with multi-byte characters around the
boundary the dump emits a half-character; Core's sexp printer escapes the stray bytes
(`\195` etc.), so it is a cosmetic golden, not a crash — but the arm's comment, the
report and `task-9-brief.md` all say "60 characters". Either say bytes, or truncate on a
character boundary. No golden today crosses the boundary with multi-byte text, so this is
a wording fix plus a note for whoever next widens the arm.

### M4. `Wrap_mode.Char` is the one enum arm no test exercises — `src/widgets/w_text_view.ml:5-10`

`None_` (by absence), `Word` and `Word_char` all appear in `live_text.ml` /
`test_widgets.ml` / the gallery. `Char` appears nowhere, so `| Char -> \`WORD` would pass
`ci.sh`. One extra prop patch in `live_text.ml`'s block 1, or a fifth line in the props
sweep, closes it. (`wrap_mode` is the only mapping function in this file, so this is the
whole of the risk.)

### M5. The selection claim is documented in two places and tested in none — `src/widgets/w_text_view.ml:145-150`, `vtree/node.mli:243-246`

Both the impl and `Node.text_view`'s doc promise "writing the buffer collapses the
selection, so it is not restored". I verified it live and it holds — and the probe turned
up a nicer property than the doc states, which is worth having in the golden:

```
selection before:                        true
selection after an echo (no write):      true      <- the echo path preserves it
selection after a same-length rewrite:   false
```

The echo case is the one an application will actually hit (a model that echoes as you
type, with a selection standing), and "controlled costs you nothing when the model agrees"
is a stronger promise than the doc currently makes. Three lines in `live_text.ml`'s block
4, beside the caret assertions that are already there.

### M6. `docs/m1-backlog.md` overstates what the cache buys — `docs/m1-backlog.md:+408`

"so a read happens once per burst of user edits rather than sixty times a second" — it is
once per **edit**, not per burst. Every `changed` that reaches an armed slot outside a
patch runs `fire` → `refresh` → a whole-buffer read, so a keystroke in a 1 MB document
costs 0.42 ms and leaks 1 MB; sustained typing leaks several MB a second. The idle-frame
claim (the load-bearing one) is exactly right and the read is unavoidable given
`on_changed`'s contract, so this is a wording fix — but it is wording a Task 14 implementer
will read when deciding how urgent the generator patch is, and the honest number makes the
case stronger rather than weaker.

---

## Verified, no finding

Recorded so the ledger does not have to re-derive them.

- **Stub-safety table.** Every citation checked against the generated C, not the GIR:
  `ml_gtk_text_view_get_buffer` does `if (result) g_object_ref_sink(result)` before
  `Val_GtkTextBuffer` (`ml_text_view_gen.c:631-638`) — correct for transfer-none against a
  finaliser that unconditionally unrefs. `ml_gtk_text_buffer_get_text` is
  `caml_copy_string(result)` with no `g_free` (`ml_text_buffer_gen.c:243-249`) — the leak
  is real and the backlog entry is accurate. `get_bounds` / `get_iter_at_offset` go through
  `copy_GtkTextIter`, which is `g_boxed_copy` into a GC-managed record
  (`ml_text_iter_gen.c:20-25`) — no stack pointer escapes, and the impl holds no iter
  across a write (it holds none at all). `get_cursor_position` reads the `cursor-position`
  property through a `GValue` it unsets (`ml_text_buffer_gen.c:626-641`) — a **character**
  offset, which is what the policy requires.
- **The ephemeron's equality/hash pairing.** `wrappers.c:118-135` installs
  `compare_gobject` (pointer identity) and `hash_gobject` (pointer hash) in
  `ocgtk_gobject_ops`, so `Gobject.same` and `Stdlib.Hashtbl.hash` agree. The claim
  `child_keys.ml:5-9` makes and this file inherits is true.
- **Signal contract.** `connect` names the buffer and `Signals.connection` carries it, so
  the disconnect is correct (M2 test above). `connection.source` holds a buffer wrapper, so
  the buffer outlives the view for the disconnect. `Events.for_kind` says `[On_changed]`
  and the impl declares exactly one spec for it, with `require_specs` (table) and
  `require_slots` (slots) both satisfied and `live_events.ml` printing `agreed`.
- **Reentrancy / nothing deferred.** `reached Bonsai across every patch above: 0` covers
  the in-patch half; the driver block's last line —
  `driver, one more frame: "ok" (handler saw 0 more)`, taken after a `drain ()` of the main
  loop — is the search-entry lesson and covers the deferred half. `GtkTextBuffer::changed`
  is synchronous, unlike `search-changed`, so there is no debounce to record and none is
  invented.
- **Props.** `create` writes props then text; `update` writes props and leaves text to
  `reassert`, which the patcher runs immediately after (`src/patcher.ml:548-554`) — the
  same ordering and the same comment as `w_entry.ml`. All nine setters are diffed
  symmetrically, and the golden's second dump (every prop moved back to GTK's own, all
  dropped) is the half a print of the set values could not show. `batch` in `update` /
  `batch_if` in `reassert` matches every other impl in `src/widgets/`.
- **Counts and negatives.** `Kind.Variants.descriptions` is asserted equal to `all_kinds`
  in both `test/test_events.ml:55` and `test/live/live_events.ml:69`; `kinds checked:
  32 → 33`. `Placement.reader`'s `| _ -> []` is the right arm for a non-container.
  `require_specs` negatives exist headlessly (`On_activate`, `On_search_changed`,
  `On_toggled`) and live (the first two), with `On_activate` correctly identified as the
  line a reader copies across from an entry.
- **Headless `Set_text`.** `test_lib/bonsai_gtk_test.ml:122-125` dispatches on the attr,
  not the kind, so a text view reaches the identical handler path; the mli doc update is
  the only change needed and is the one made.
- **Truncation vs. goldens.** `expected_text.txt` is the only golden with a `GtkTextView`
  dump; its long-text block (129 chars) is the one that crosses the boundary and it prints
  the full text separately (`the buffer holds it in full: true`). No golden depends on text
  past 60.
- **GC churn on the buffer wrapper.** Not mutation-provable from OCaml (it would need the
  C stub changed and ocgtk rebuilt), but the claim it pins — `get_buffer` returns one
  stable object, 500 wrappers and five `full_major`s later — is what the whole
  connect-at-mount/disconnect-at-teardown design rests on, and it is non-vacuous for that:
  a `get_buffer` that minted a new object would fail `Gobject.same`. The safety half is
  established directly by the stub above.
- **Gallery.** In the Controls page, inside a `scrolled_window` where a text view belongs,
  with a button that demonstrates the caret policy rather than describing it.
  `test_gallery.ml` updated. `examples/gallery.ml`, `test_gallery.ml`, `src/patcher.ml`,
  `test/test_events.ml`, `test/live/live_events.ml`, `vtree/attr.mli` and
  `test_lib/bonsai_gtk_test.mli` are all outside the brief's file list and all necessary;
  the only optional edit is `test/live/live_lists.ml`, which is Task 8's N9 carry and
  authorised.
- **Conventions.** `vtree/wrap_mode.ml` has no `.mli` and derives `sexp_of, equal, compare`,
  matching `tab_position.ml` / `selection_mode.ml` exactly. `None_` for the shadowing
  reason, with the same sentence the other three use.

---

## Verdict

**Approved**, with I1 to be taken — as a fix round on this task or as a Task 10 carry, the
lead's call. The deviation the ledger asked to be judged is correct, forced by measurement
rather than argued into, and observationally equivalent to the code it replaces on every
path the suite exercises; the test the brief called the most valuable in the task is
non-vacuous and was made so by the implementer noticing it was not. I1 is a real
user-visible defect on an uncommon input with a cheap, already-bound fix, and the minimum
acceptable response to it is a corrected comment plus a test — shipping the gap
undocumented in its permanent form is what I would not approve.

Suggested carry to Task 10: M1 (one word, removes the cache's only silent-failure shape),
M4 and M5 (a line each), and M2/M3/M6 (wording). M6 belongs with the `docs/m1-backlog.md`
entry Task 14 will read.

---

# Re-review — fix round 1 (`1c61269`)

Scoped to `git diff 8848e2b..1c61269` (14 files, +428/−44) against the findings above.

**Gates re-run independently:** `nix develop -c ./scripts/ci.sh` → `all green`, exit 0
(`bench: 0.00020 ms at 16 chars, 0.00013 ms at 1 MB, ratio 0.64 (bound 5)`). Mutation work
in a throwaway worktree at `1c61269`, now removed; no tracked file in the checkout was
modified.

## Summary

I1 is closed properly — not papered over. The implementer re-verified my table before
acting on it and found the case is worse than I reported: the previous contents are
*destroyed*, not merely left unwritten, because `set_text`'s delete lands before the
refused insert. Refusing the write rather than caching the attempt is the right shape, and
it is the one that keeps the cache's invariant (`text` describes the buffer) true by
construction instead of by exception. All six Minors are genuinely closed, three of them
mutation-verified by me below.

The new reporting channel is well-judged. `Patcher.ctx.report` carries the node path,
defaults to the library's existing `bonsai_gtk: ` stderr channel (matching `loop.ml:49`,
`scheduler.ml:78`, `gtk_effect.ml:14`, `driver.ml:150`), and is a hook so the live golden
captures messages instead of racing stderr. The `create_ctx` trailing `unit` is 15 lines of
`()` across five test files and the driver — mechanical, and the compiler forced every one.
The deviation from the ruling's "`ctx.on_exn` or whatever the driver's hook is" is argued
correctly: `Signals.ctx.on_exn` takes an `exn`, means "raised while dispatching a signal",
and is not reachable from a `Widget_impl` at all; the alternative was threading `~path`
through all 32 impls.

**One new Important**, introduced by this round and invisible to the bench that is supposed
to guard exactly this property: a text view parked on a refused write pays an
**O(buffer-length)** idle frame, forever. I measured it, and I verified a three-line fix
that removes it with every golden unchanged.

## The questions asked

**Is the refusal memory correct — can it suppress a legitimate report?** No. The memo is
consulted only after `holds` has said the buffer does not hold `text`, and it matches only
the exact text a refusal was already decided and reported for. `unwritable` is a pure
function of the string (`String.mem '\000'` + `Glib.Utf8.validate`), so a text refused once
can never become storable, and skipping it is always right. `st.refused <- None` on every
successful write is what stops the memo outliving the state that justified it — pinned by
the golden's `latin-1 again` line, which reports a second time for the *same* text after a
valid write in between. The one suppression I could construct is benign: refuse X → user
edits the buffer → model still offers X → no write and no second message. The buffer keeps
the user's text and the model is out of line with it, which is correct (X is unstorable)
and was already reported once.

**Does it leak?** No. One `string option` per live text view, in the same weakly-keyed
ephemeron, cleared on the next successful write. Nothing accumulates.

**Does the error path match how the driver reports elsewhere?** Yes —
`bonsai_gtk: <path>: <message>` on stderr with `%!`, the same channel and flush discipline
as the four existing sites. `driver.ml:150` spells the path as `at %s` and this as `%s: `;
both spellings already exist in the library (`Signals.require_specs` raises path-first), so
this is consistent rather than novel.

**Does a valid text after a refusal always land?** Yes, on every path I traced: after one
refusal, after two, after a user edit in between (`already_refused` is keyed on the text, so
a different text is never suppressed; `holds` then re-reads because the edit set `stale`),
and at mount. The golden pins the first two directly.

**Is the idle bench untouched?** Yes for the settled path — `ratio 0.64 (bound 5)`, with the
extra `take_report` ephemeron lookup showing as 0.00010 → 0.00013 ms at 1 MB, within noise
of the run-to-run spread I saw across four runs. **No for the refused path**, which the
bench does not cover at all; see Important R1.

**Are M1–M6 genuinely closed?** Yes, all six. Three verified by mutation rather than by
reading:

```
mutation                                          caught by
| Char -> `WORD                                   golden: (wrap char) -> (wrap word)          [M4]
byte prefix instead of utf8_prefix                golden: ...xxx\195\169... -> ...xxx\195...  [M3]
drop the refusal memory                           golden: five idle frames -> five messages   [I1]
drop the NUL branch from unwritable               golden: the NUL message becomes the UTF-8
                                                  one (the buffer outcome is identical, so
                                                  only the distinct message catches it)      [I1]
```

That last one is worth recording: the report argues the NUL check is not redundant defence
even though `validate` rejects NUL today, and the mutation shows the claim is *tested* — the
refusal happens either way, and it is only the message that tells you which of the two
shapes you hit.

M1 is `(state w).stale <- true` with the three-hop reasoning that made the capture safe
written down beside it. M2's comment now claims what the line shows and says why no stronger
test exists. M5 took the better property and handled the caret interaction correctly
(`select_range` after the caret assertions, with the `cursor=2` → `cursor=1` golden churn
explained in the file). M6's backlog entry is now sharper than my finding asked for — it
states outright that the cache fixes the idle path and *cannot* fix the edit path, with the
per-keystroke number.

## Important

### R1. A text view parked on a refused write pays an O(buffer-length) idle frame, forever — `src/widgets/w_text_view.ml`, `reassert` + `set_text_if_needed`

`reassert` is unchanged from the first round:

```ocaml
let st = state w in
let writes = not (holds w st p.text) in
Widget_impl.batch_if writes w (fun () ->
  if writes then ignore (set_text_if_needed w p.text : bool))
```

After a refusal the buffer holds the *old* text and `st.text` describes it (correctly — that
is the fix), while `p.text` is the unstorable one. So `holds` answers **false** on every
subsequent idle frame, and each of those frames now runs: a full `String.equal` in `holds`,
then `batch_if true` — a `freeze_notify`/`thaw_notify` pair — then `set_text_if_needed`,
which runs `holds` a **second** time before the refusal memo is consulted. Two whole-buffer
comparisons and a bracket, at 60 Hz, for as long as the model keeps asking.

`String.equal` short-circuits on length, so this is invisible whenever the refused text and
the buffer's contents differ in length. When they do not, it is a full memcmp. Measured
(20 000 frames each, same harness as the shipped bench):

```
settled, 16 chars            0.00030 ms per idle frame
refused, 16 chars            0.00028 ms per idle frame
settled, 1 MB                0.00017 ms per idle frame
refused, 1 MB (same length)  0.06341 ms per idle frame      <- 364x a settled frame
```

This is the exact property the task's headline bench exists to pin — that an idle frame's
cost does not scale with the buffer — and it is now violated on a path the bench cannot see,
because the bench mounts a *storable* text. The state is reachable and persistent by
construction: a read-only pane re-rendering a large latin-1 payload is I1's own motivating
example, and a log tail or file preview that re-renders a similar-length document is exactly
where the lengths coincide.

Two smaller things fall out of the same spot. The `batch_if` comment two lines above says a
text view on an idle frame "must pay neither the write nor the freeze/thaw" — it now pays
the freeze/thaw. And the memo's own comment claims "the string is adopted so that the frames
after it answer in a pointer comparison", but there is no adoption in the code:
`st.refused <- Some text` runs only when the refusal is first decided, so a model that
rebuilds the string each frame re-runs `String.equal` against `st.refused` too. `holds` does
adopt; this does not.

**Fix, verified.** Factor the memo out with the adoption its comment already promises, and
consult it *before* `holds` in `reassert` — safe because `unwritable` is pure and
`st.refused` is cleared on every successful write, so a matching memo means the write can
only fail:

```ocaml
let already_refused st text =
  match st.refused with
  | Some refused ->
    phys_equal refused text
    || (String.equal refused text && (st.refused <- Some text; true))
  | None -> false
;;

(* in reassert *)
let writes = (not (already_refused st p.text)) && not (holds w st p.text) in
```

with `set_text_if_needed`'s second branch calling `already_refused st text`. I applied
exactly this in the worktree:

```
settled, 16 chars            0.00022 ms      refused, 16 chars            0.00013 ms
settled, 1 MB                0.00013 ms      refused, 1 MB (same length)  0.00014 ms
refused/settled at 16 chars: 0.6x   at 1 MB: 1.1x        (was 364.1x)
```

and re-ran both suites: `dune test` and the live golden pass **unchanged**, refusal block
included — the reordering is behaviour-preserving on everything the suite pins, including
`a valid text after two refusals`, `latin-1 again` reporting a second time, and the mount
case. Skipping `holds` on a refused frame also skips its `refresh`, which is fine and
slightly better: `stale` simply stays set until the model offers a storable text, and that
frame pays the one read it genuinely needs.

Worth adding a bench arm for the refused path at the same time, since the existing one
structurally cannot cover it.

## Minor

### R2. `enqueue_fixups`' `Text_view` arm enqueues nothing

Documented in the arm itself ("Not a fixup at all"), and the placement is right — it is the
one place holding both the widget and the node path, and it runs after `create` on a mount,
after `reassert` on a patch, and in `reassert_only`, which I checked are the three places a
write can be refused. But the function's name now covers two jobs. If a second caller
arrives (the report's own carry names two candidates), a `notify_interests` / `enqueue`
split would be worth the rename. Nothing to do now.

### R3. `take_report` uses `state w` rather than `Cache.find_opt`

It will mint a `{ stale = true }` record for a widget whose entry was collected, once per
frame, purely to find `None` in it. Harmless — a fresh record reads before it answers — and
unreachable while `create` runs first, but `find_opt` says what is meant and cannot resurrect
an entry the patcher has no use for.

## Verdict

**Approved**, conditional on R1 — three lines, tested, every golden unchanged, and I have
given the exact patch above. I1 is closed correctly and for the right reason: the cache now
describes the buffer on every path rather than describing an attempt, which is what makes
the invariant provable instead of argued. All six Minors are closed, four of them pinned by
tests that fail under mutation. R2 and R3 are notes, not conditions.

The revised carries to Task 10 are right, and the new one about `Patcher.ctx.report` having
one caller is the most valuable thing in this round beyond the fix itself — Task 8's
hidden-page divergence and a `~selected` a list box's mode cannot hold are both `interest`s
already, and both are now one line from a message they previously had nowhere to put.

---

# Re-review 2 — fix round 2 (`d9f9d93`)

Scoped to `git diff 1c61269..d9f9d93` (3 files, +129/−36) against R1.

**Gate re-run independently:** `nix develop -c ./scripts/ci.sh` → `all green`, exit 0.
Mutation and probe work in a throwaway worktree at `d9f9d93`, now removed; no tracked file
in the checkout was modified.

## Summary

R1 is closed exactly as proposed, with the reasoning that makes the early-out safe written
into `already_refused`'s own comment rather than left in the review file — which is the
right place for it, since the next reader of that line will not have this document open.
The bench arm is better than the one I asked for: it picks the worst case deliberately
(same length, one byte apart, so `String.equal` cannot short-circuit) and says so, and it
carries a second, independent assertion — `refusals reported across every frame above: 1`
— that pins "reported once" over twenty thousand parked frames, which no other test covers.

Verified by mutation: restoring `let writes = not (holds w st p.text)` gives
`ratio 503.17` and flips the golden verdict `true → false`. Note the two assertions are
genuinely independent — under that mutation the refusal count stays `1`, because
`set_text_if_needed`'s own memo check still suppresses the report; only the timing arm
moves. Each line pins its own thing.

Every golden outside the bench is unchanged, as claimed and as I confirmed.

No new Important. Two Minor notes, neither a condition.

## Does the early-out ever skip a write it should make?

No, and this holds by construction rather than by luck. `st.refused = Some r` is only ever
assigned in the branch where `unwritable r <> None`; `already_refused st t` returns true
only when `String.equal r t`; and `unwritable` is a function of the string's contents
alone. So a matching memo implies `unwritable t <> None`, i.e. the write it skips could
only have failed. The adoption (`st.refused <- Some text` on a match) substitutes an equal
string, which preserves that. Clearing on a successful write is therefore a *reporting*
policy, not a correctness requirement — which is worth knowing, because it means the memo
cannot go stale in the dangerous direction even if that clear were ever missed.

Confirmed empirically across every transition I could construct, including the two the
suite does not cover:

```
mounted                                        buffer "start"    reports +0
invalid X                                      buffer "start"    reports +1
invalid Y (different) -> new datum             buffer "start"    reports +1
valid Z lands                                  buffer "zzz"      reports +0
invalid X again, after a valid write           buffer "zzz"      reports +1
valid Z the buffer already holds (no write)    buffer "zzz"      reports +0
invalid X again, after a no-op valid patch     buffer "zzz"      reports +0
valid W after that                             buffer "wwww"     reports +0
invalid X once more                            buffer "wwww"     reports +1
user typed into the parked view                buffer "!wwww"
valid V after the edit                         buffer "vvv"      reports +0
```

Every valid text lands, on every path — after one refusal, after a *different* refusal,
after a no-op valid patch that left the memo standing, and after a user edit into a parked
view. A different invalid text is treated as a new datum and reported. Nothing is skipped
that should have been written.

## The bench's margin

Stable, with one caveat worth recording rather than acting on. Five clean runs:

```
parked ratio: 1.19  1.11  1.10  1.13  1.19        (bound 5)
```

A spread of 0.09 and 4.2× of headroom, against a regression that drives it to ~503 — so
the bound sits roughly two orders of magnitude from failure. The ratio sitting a little
*above* 1 rather than at 1 is a mild positive signal: the parked frame really does one
extra `phys_equal` and `state` lookup, so it is measuring something.

The caveat: both arms are sub-microsecond (~130–150 ns a frame), so contention does not
cancel the way it does for the lists bench — it is additive preemption noise on a very
small measurement, not proportional noise on a large one. Under 24-way CPU
oversubscription (`nproc` spinners on a 24-core box, far harsher than CI), three runs gave
`1.06  2.68  1.07`. It passed, but the excursion reaches half the bound, which is the
territory Task 7's N1 was raised from.

Nothing to do now. If it ever goes red, the fix is not a bigger bound but a better
denominator: time a *parked* frame at 16 characters against a *parked* frame at 1 MB, the
same size-ratio shape the settled arm already uses. That catches the identical regression
(a parked 16-char frame memcmps 16 bytes, a parked 1 MB frame memcmps a megabyte) and puts
two equally contention-prone measurements on both sides of the division, so the noise
cancels properly.

## Minor

### RR1. The repeat-report suppression for a *rebuilt* equal string is real behaviour and is untested

`already_refused`'s `String.equal` arm does not only save a comparison — it suppresses a
duplicate report. A model whose `text` is computed rather than stored (any `sprintf`,
`String.concat`, or read-through) hands back an equal-but-fresh string whenever it
re-renders for an unrelated reason, and without that arm each of those frames would report
again. That is `node.mli`'s "once per offending text, not once per frame" promise, and the
suite only pins it for the physically-same-string case: the `idle` loops and the bench go
through `reassert_only` on the stored node, so they hit `phys_equal`, and the two
`refuse "latin-1"` calls have a valid write between them that clears the memo.

It does work — I checked:

```
invalid X (rebuilt string)     reports +1     (memo was cleared by the preceding valid write)
invalid X (rebuilt again)      reports +0     (String.equal arm, then the adoption)
```

One extra line in the refusal block — a patch with `String.copy` of the text just refused,
asserting `reports ()` — pins the promise the doc makes. Cheap, and it is the arm a later
"simplify this to `phys_equal`" would silently break.

### RR2. Whether a repeat is re-reported depends on whether the intervening valid text caused a write

Lines 5 and 7 of the table above differ: after a valid text that *wrote*, a repeat of the
refused text is reported again; after a valid text the buffer already held — which returns
at `holds` and never reaches the memo-clearing line — the same repeat is silent. Both are
defensible and neither loses information (the standing message is still an accurate
description of the view), and the doc's "once per offending text" is honoured either way —
arguably more literally by the silent branch. Recording it because it is the one place the
reporting rule is a function of something other than the model's own sequence of texts, and
because a future reader comparing those two lines will wonder.

## Verdict

**Approved**, no conditions. R1 is closed correctly, the early-out is safe by construction
and verified empirically over eleven transitions, the new bench arm is well-shaped and
mutation-verified at ~503× against a bound of 5, and everything outside it is byte-identical.
RR1 and RR2 are notes for whoever next touches this file.

The report's closing observation is the right one to carry, and I would put it in the ledger
rather than only in the report: **round 1's fix created round 2's regression, and neither
round's tests would have found it without a bench arm being asked for by name.** The shape —
"a controlled prop the widget refuses leaves `reassert` deciding *not* to write, expensively,
on every frame forever" — is not text-view-specific, and Task 8's hidden-page divergence and
a `~selected` a list box's mode cannot hold are both already in the ledger as the same shape.
Whichever task gives them the `report` hook should measure their parked frames at the same
time.
