# Task 5 review — key controllers: the `bool` return, phases, and a keyval table `vtree` can name

**Commit:** `7ba161a` on `m2`, base `93c819c`. 27 files, +1472/-63.
**Reviewer gates run:** `nix develop -c dune build` (exit 0);
`BONSAI_GTK_LIVE_TESTS=1 nix develop -c xvfb-run -a dune build @test/live/runtest` (exit 0,
the one stderr line is `live_driver.ml`'s deliberate raise);
`nix develop -c ./scripts/ci.sh` → `all green`. Four mutations run in a throwaway
worktree (`git worktree add /tmp/m2-t5-verify 7ba161a`, removed afterwards); all four were
caught — see "Mutation evidence" below.

---

## Summary

This lands the thing the whole `Payload` existential was built for, and it lands it
correctly. The chain the brief names as the Critical — handler → `Key_response.t` →
`Controllers.key_pressed_answer` → the `Payload` trampoline → `key-pressed`'s C return —
is sound at every link, synchronous where it has to be, and asynchronous where it has to
be: `Signals.dispatch_payload` (`src/signals.ml:78-92`) computes `r` and returns it on the
same stack, having merely handed the effect to `ctx.schedule`, which is
`Driver.schedule_event` (`src/driver.ml:14-26`) → `Bonsai_driver.schedule_event` +
`Scheduler.request_frame`, and `request_frame` arms a `Glib.Idle` (`src/scheduler.ml:83-95`)
rather than running a frame. So a `Handled` becomes `GDK_EVENT_STOP` before any Bonsai work
happens, which is exactly the contract. All three `declined` paths — `in_patch`, empty
slot, `fire` raised — return `Controllers.key_pressed_declined = Gdk_constants.event_propagate`,
and the golden pins that against GDK (`declined=false event_propagate=false event_stop=true`)
rather than against a self-agreeing literal.

The rest holds up under the same scrutiny. One `GtkEventControllerKey` serves both attrs
and the live test asserts *exactly one of ours* by GObject type name rather than counting
(`test/live/live_controllers.ml`'s `key_controller_props`), which is stronger than the
accessor the brief suggested. The `Key` family went into precisely the one table Task 4
prepared (`Events.Family.t` + `controller_family`), and everything else — `is_controller_attr`,
`family_attrs`, `require_slots`'s skip, `is_supported`'s short-circuit,
`Controllers.{attached,update,release}` — derived from it with no second list. I checked
every site in the tree that enumerates controller attrs (`git grep On_focus_leave`): all
eleven got their key arms, and the three that are exhaustive matches got them from the
compiler.

The keysym table is right (I checked all nineteen values against X11 `keysymdef.h` by hand
and the live test checks them against the pinned `Gdk_constants`), `f` and `of_char` raise
rather than guessing, and the mli's `val` count matches the `check` count.

No Critical. No Important. Six Minors, all documentation or test-robustness; none of them
blocks.

---

## Judgement of the "testing option obtained" claim

**Accepted, and the evidence is better than the claim.** The report says key = the brief's
option (c), plumbing only, as pre-flight correction 1 predicted. I re-verified the
underlying fact independently in `.ocgtk-src/ocgtk/src/gtk/generated/event_controller_key.mli`:
`forward` is documented "can only be used in handlers for the `key-pressed`, `key-released`
or `modifiers` signals", i.e. it re-routes an event the controller is *already* processing,
which is a state no test can construct; there is no `GdkEvent` constructor; `emit_by_name`
carries no arguments. The conclusion is correct and the fallback was not needed.

What was landed instead is more than the brief asked for, and I confirmed each piece
actually bites by mutating it:

- The one uncovered link — the spec's own `fire` — was lifted out as
  `Controllers.key_pressed_answer` and called directly over all four constructors. This is
  the right call, and it is not duplication: `key_pressed_spec`'s `fire` *is*
  `key_pressed_answer` (`src/controllers.ml:246`), so the two cannot drift.
- `declined` is bound once as `key_pressed_declined` and used both as the spec's `declined`
  and as `key_pressed_answer`'s fallback, so those cannot drift either.
- `Controllers.armed` (Task 4's round-2 addition) is what makes "the controller is attached"
  and "the controller would call something" two separately asserted facts, and every key
  line in the golden carries it.

The honesty of the gap statement is good. `docs/m1-backlog.md` now names the *key-specific*
half — that propagation itself is unverified, that a `Handled` Escape is not shown to fail
to reach a sibling, that a `Capture` controller is not shown to beat a child's `Bubble` one
— and names `gtk_test_widget_send_key` beside `gtk_test_widget_click` as what would close
it. `bonsai_gtk_test.mli` states the same gap in the action's doc *and* in `create`'s
opening, which is where the brief asked for it. The phase is the one input to GTK's routing
that a plumbing test *can* observe, and it is observed, read back off the live controller in
four states (`CAPTURE`/`BUBBLE`/`TARGET`, plus released-only still carrying it).

### Mutation evidence

| Mutation | Caught by |
|---|---|
| `Key_response.handled` inverted (`Handled -> false`) | `test/test_attrs.ml:212` **and** `expected_controllers.txt:79` — both, independently |
| `key_pressed_declined := Gdk_constants.event_stop` | `expected_controllers.txt:83` (`declined=true`) |
| `configure_key` writes `Bubble` regardless of the attr | `expected_controllers.txt:60` — six lines diff |
| `Events.key_phase_rejection` dropped from `Bonsai_gtk_test.require_supported` | `test/handle/test_handle.ml:989` (`"did not raise"`) |

The Critical the brief names is therefore not merely argued, it is pinned twice over.

---

## Per-deviation judgement

1. **Differing-phase rule in `vtree/events.ml`, not `src/controllers.ml`** — **sound, and
   an improvement on the brief.** Written where the brief said, it would have been a fourth
   structural mistake a headless suite certifies and the runtime refuses, which is the
   failure `Events` and `Placement` exist to remove and which `bonsai_gtk_test.mli` warns
   about by name. The two messages are identical outright (one renderer,
   `Events.key_phase_rejection`), and I confirmed the *ordering* claim holds: mount runs
   `Placement.rejection` (`patcher.ml:277`) → `require_specs` (`:291`) → `require_slots`
   (`:298`) → `Controllers.update` (`:304`), and `require_supported` runs placement →
   `Events.unsupported` → `key_phase_rejection` in the same order, so a node with two
   mistakes reports the same one in both places.
2. **`declined = Gdk_constants.event_propagate` rather than literal `false`** — **sound.**
   The brief offered either and asked which; this is the better half, because it is the
   spelling a test can pin against GDK. The report's note that "consistent with
   `key_released_spec`" does not bind (its `declined` is `()`, which has no constant) is
   correct.
3. **No `Controllers.Private.key_controller` accessor** — **sound, and stronger than the
   brief's suggestion.** Filtering `Widget.observe_controllers` by `Controllers.is_ours`
   and GObject type name is the same five lines `click_gesture_props` already uses, and it
   additionally asserts there is exactly one key controller of ours — a fact a direct
   accessor structurally cannot express. Confirmed by reading `key_controller_props`: the
   `_ :: _ :: _` arm prints a loud line that would diff.
4. **`Controllers.key_pressed_answer` / `key_pressed_declined` exposed instead** —
   **sound.** The audit behind it is correct: every other link was already covered
   (`Key_response.handled` headlessly, `dispatch_payload`'s three paths in
   `live_signals.ml`, trampoline-result → `key-pressed`'s return by the type system, which
   I verified against ocgtk's `on_key_pressed : callback:(keyval:int -> keycode:int ->
   state:Gdk_enums.modifiertype -> bool) -> _`). The only reachable-by-nothing link was
   `fire`, and making `fire`'s body a named function rather than duplicating it is the
   right shape. **It cannot leak into the public API**: `Controllers` appears in
   `bonsai_gtk.mli` only inside `module Private`, whose doc is "No stability promise: this
   is what the library's own tests reach through" (`src/bonsai_gtk.mli:124-137`), the same
   door `armed` and `is_ours` already use. The report's own carry — that these should go
   the day a real key press becomes deliverable — is the right disposition.
5. **`src/gtk_import.ml` unchanged** — **sound.** `modifiers_of_gdk`, `propagation_phase`
   and the `Gdk_constants` alias all landed in Task 4 and needed nothing. I re-checked
   `modifiers_of_gdk` (`gtk_import.ml:48-67`) for the brief's modifier-decoding question:
   it folds over `Gdk_enums.modifiertype = modifiertype_flag list`, so **combined masks
   work by construction**, and the match is exhaustive with the button and lock masks
   explicitly dropped. `modifiertype_of_int` in the binding is a straight bitmask decode
   (`gdk_enums.ml`), so `Ctrl+Shift` arrives as `{ shift = true; control = true }`.
6. **`Keyval.of_char 'A'` not checked against the binding** — **sound, and verified
   independently.** `gdk_constants.mli` really does declare `val key_a` twice, and the
   `.ml` really does define `key_a = 65` (line 54) and `key_a = 97` (line 1552), the second
   shadowing the first. So `K.key_A` does not exist and cannot be made to. The brief
   anticipated exactly this and said "drop that line and say so in `of_char`'s doc"; the
   line is dropped and `keyval.mli`'s doc says so, with the extra and useful observation
   that a capital *is* its own keysym so a shift-insensitive handler has to match both.
   `of_char 'W'` is still pinned headlessly against `0x57`. See Minor M4 for the one thing
   this reasoning does not go far enough on.
7. **Plain `sprintf` rather than `ppx_custom_printf`** — **sound**, and it matches
   `Placement.rejection`, which avoids the same ocamlformat rewrite for the same reason.
   The golden is the evidence the problem was real.
8. **`Key_response.handler` as a named type** — **sound.** `Attr.Private.t` derives
   `sexp_of` and a bare arrow has no derivable one; this is precisely why `Handler.t`
   exists, and `handler = Key_event.t -> t` is the same type, so
   `Attr.on_key_pressed : ?phase:Phase.t -> (Key_event.t -> Key_response.t) -> t` is
   published exactly as the brief specified.
9. **Extra tests beyond the brief's list** — **sound and welcome.** The headless keysym
   golden in `test_attrs.ml` is the one I would have asked for: it makes a value change a
   diff even with no display, which the live-gated `live_keyvals.ml` alone would not. The
   `Propagate_and` + `Key_release` handle test is the constructor a reader asks about, and
   the phase-conflict test has an *agreeing* counterpart so the check is shown not to be
   over-eager.

---

## Critical

None.

I looked specifically for the failure the brief names — a `Handled` that does not stop
propagation — along every link, and mutated two of them. It is not present, and it is
pinned by two independent tests.

## Important

None.

---

## Minor

**M1. `vtree/key_event.ml:15` — the `modifiers` doc describes the click path, not the key
path.**

> `[modifiers]` is read off the controller while the event is still current

For a key event it is not: it arrives as the `~state` callback argument and is converted in
`connect` (`src/controllers.ml:262` and `:290`). `Controllers`' own comment says so
outright — "the modifiers come in as `[~state]` rather than being fetched"
(`src/controllers.ml:214-217`) — so the two files contradict each other. The sentence is
true of `Click_event`, where `get_current_event_state` really is read off the gesture while
the event is current, and reads as a copy-paste from there. `Key_event` has no `.mli`, so
this is the published doc. The second half of the paragraph ("the state *before* this key
was pressed, which is GDK's convention") is correct and worth keeping.

*Failure scenario:* a reader porting `viewer_window.ml`'s auto-repeat suppression concludes
the modifiers are only valid inside the handler's dynamic extent and writes defensive code
for a constraint that does not exist; or, worse, concludes that `Key_event.t` cannot be
stored past the callback and copies fields out of it.

**M2. Four stale "Task 5 will…" forward references, one in a public `.mli`.**

- `vtree/events.mli:23` — "…and Task 5's two key attrs **will** share a
  `GtkEventControllerKey` the same way", in the doc of `Events.Family.t`, three lines above
  the `Key` constructor that already does.
- `src/controllers.ml:53` — "Task 5's second key attr joins its family in
  `[vtree/events.ml]` and nothing in this file changes."
- `src/controllers.ml:169` — "Task 5's key spec is where `[declined]` earns its keep."
- `src/controllers.ml:323` — "Task 5 adds `[Key]` to the variant and the compiler asks for
  its arm here."

The equivalent line in `vtree/attr.ml` and the one in `vtree/events.ml`'s `for_kind`
comment *were* updated (the latter rather nicely, to "Adding `[Key]` here was four compile
errors and no thought, which is what the table was for"), so this is an oversight rather
than a policy. `events.mli` is the one that matters: it is public API documentation that
tells a downstream reader a landed feature is still future work.

**M3. `vtree/attr.mli`'s `on_key_pressed` under-states where the phase conflict is caught.**

> giving them different phases is `[Invalid_argument]` **at mount**

It is raised at mount, at *patch* (a conditionally-added `~phase` reaching a widget mounted
without it — asserted in `live_controllers.ml`'s "patch rejected" line), and at
`Bonsai_gtk_test` handle time. All three are tested; only one is documented.

*Failure scenario:* an author reads "at mount", assumes a headless suite cannot catch it,
and does not learn from their green handle test that the tree is unmountable — which is the
precise outcome deviation 1 went to some trouble to prevent.

**M4. `live_keyvals.ml`'s lowercase-letter checks silently depend on declaration order in
the generated binding.**

The comment explains at length why the *capitals* cannot be checked (both `XK_A` and `XK_a`
generate `key_a`, second wins) and then concludes: "What is checked is that the lowercase
letters, the digits and the punctuation agree." But the lowercase letters are checked
against the *same shadowed names*: `gdk_constants.ml` defines `key_w = 87` at line 1514 and
`key_w = 119` at line 2438, `key_z = 90` then `key_z = 122`, `key_a = 65` then `key_a = 97`.
The checks pass only because ocgtk's generator happens to emit the uppercase block before
the lowercase one. `key_slash` (47), `key_space` (32) and `key_0` (48) have no such
duplicate and are genuinely unambiguous.

*Failure scenario:* an ocgtk regen or fork bump that sorts constants differently makes
`K.key_a` resolve to 65. `live_keyvals.ml` prints `MISMATCH of_char a: vtree=0x61 gdk=0x41`
— and both the test's own comment and the brief instruct the reader to treat a MISMATCH as
"the hard-coded table is suspect, stop and report", when in fact `Keyval.of_char 'a' = 97`
is still exactly right and the binding is the ambiguous side. A cheap fix: either add
`check "of_char a"` only against the unambiguous punctuation/digit constants and note that
letters are covered transitively by the same arithmetic, or keep them and add one line
saying the letter checks read the *second* of two declarations, so a MISMATCH on a letter
means "the generator reordered", not "the table is wrong".

**M5. `Events.key_phase` is public and answers for a node that `key_phase_rejection`
rejects.**

`events.mli:60-66` says the disagreeing case "is a value no caller ever reaches:
`key_phase_rejection` is non-`None` for exactly those attrs, and both consumers check it
first". That is true of the two in-repo consumers — `Controllers.configure_key` checks
first (`src/controllers.ml:305`), `Bonsai_gtk_test` never calls `key_phase` at all — but
`Events` is a public `vtree` module, so the sentence documents a convention rather than a
guarantee. Cost of the trap is low and it is documented; noting it because the surrounding
code (`Placement`, `Attr.Private`) is otherwise careful to make wrong use unrepresentable
rather than merely discouraged.

**M6. The disarmed-slot state after a rejected patch rests on a `Driver`-only invariant.**

`live_controllers.ml`'s "phases after the rejected patch" line records `armed=()` and
argues, correctly and in a good comment, that it is not a live hazard because an exception
inside a frame stops the driver for good (spec §11). Two notes for later rather than now:
the golden itself demonstrates a context (a direct `P.patch`) where the node keeps living
with an attached, inert key controller; and `Expert.embed` (Task 12) will introduce a
second root whose exception policy is not yet written. Worth a line in Task 12's brief that
whatever `embed` does on a raising frame has to be "stop", not "skip this frame".

**Note, not a finding.** Task 4's argued-not-fixed M6 — the controller's GClosure captures
`t.widget` (via `Signals.connect_all`'s `dispatch_payload … w slot p`), so
widget → controller → closure → widget is a cycle across the GObject/OCaml boundary — now
holds for the key controller too, on identical terms. Nothing new; it inherits the existing
disposition and the backlog's GC/lifetime item.

**Carries confirmed still open.** The focus `~phase` asymmetry (Task 4's carry) is visibly
worse with two of three families now taking one — `test/handle/test_handle.ml:748` still
prints `(On_focus_leave <handler>)` with no phase beside
`(On_key_pressed (phase Bubble) …)` — and the report's suggestion that adding it would let
`key_phase_rejection` generalise into a `family_phase_rejection` is the right shape.
README Limitations and the gallery Input section remain Task 15/16 and are correctly out of
scope here; the report's expansion of both carries (two sentences not one; a `Capture`-phase
key handler over a focusable child) is a real improvement on what Task 4 left.

---

## Out-of-scope creep

None found. Every file outside the brief's list is a forced consequence: `test_placement.ml`'s
count 32 → 34, `test_events.ml`'s two goldens, `attr_apply.ml`'s two inert arms,
`placement.ml`'s `reader` arm, `bonsai_gtk.ml(i)`'s three re-exports. `src/gtk_import.ml`
was listed as a file to modify and correctly was not. No widget impl, no patcher logic, no
`Signals` change.

---

## Verdict

**Approved.**

The Critical the brief singled out is absent and is pinned by two independent tests, both of
which I confirmed fail under an inverted `Key_response.handled`. The plumbing-only testing
option is the one the pre-flight predicted, obtained honestly, and compensated further than
the brief required — the phase is read back off the live controller in four states, the
spec's own `fire` is exposed and exercised over all four constructors, and the gap that
remains is written down in three places with its closing condition. The differing-phase
rejection improves on the task text by living in `vtree`, and the six Minors are
documentation and test-robustness items that can ride with Task 6 or a later doc pass; none
of them changes behaviour and none should hold this commit.
