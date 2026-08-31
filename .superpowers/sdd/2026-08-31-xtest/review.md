# Review — `xtest-input` (the XTEST bead)

Reviewer: the M2 final review's live-tests lens, i.e. the author of the design sketch this
branch implements. Reviewed `git diff main..xtest-input` (`b4cac1d..5150c7e`, three
commits, 7 files). I own the builds; every number below is one I measured on this host
(24 cores). "2x oversubscription" is 48 spinning shells against 24 cores, started and
killed around each batch.

Tree left clean: `git status` empty apart from the pre-existing untracked
`.beads/issues.jsonl`, no worktrees, checked out on `xtest-input`.

---

## Build and gate results

**Full gate, twice consecutively, first on a cleaned tree** (`_build`, `_build.pkg`,
`_build.pkgtest`, `result`, `bonsai_gtk.install` removed):

| run | exit | elapsed | `output_input.txt` rewritten? |
|---|---|---|---|
| 1 (clean) | 0 | 84 s | yes, 18 s before the prompt returned |
| 2 (same tree) | 0 | 58 s | yes, 19 s before the prompt returned |

Both `all green`, no `TIMED OUT` and no `xdotool … FAILED` anywhere in either log. Run 2
matters twice over: it is the second-run case, and it shows the new rule inheriting the
`rm -f _build/default/test/live/output_*.txt` that the M2 fix wave added for exactly this
(final review I1). A cached green on the one rule that covers the input path would have
been the worst possible place to lose it.

**The alias, 10 times, clean host:**

```
clean run 1..10: rc=0, 33-34 s each
== clean: 0 failures in 10 runs
```

**The alias, 8 times, 2x oversubscription** (load average 1.4 at the start, 49.8 at the
end):

```
2x-load run 1..8: rc=0, 77-97 s each
== 2x-load: 0 failures in 8 runs
```

**Twenty executions of `live_input` in total (18 alias runs + 2 gate runs), zero
failures.** That is a larger sample than the report's (10 clean + 5 loaded + 2 gates) and
it agrees with it. Solo, `live_input.exe` takes **4 s**, and the alias went from ~29 s
before this branch to 33 s — so the twelfth test costs 4 s of a serialised section, which
is the right price for the milestone's last uncovered claim.

Against the report's numbers: everything reproduces. Nothing in the report's determinism
table is overstated.

---

## Is the rule's `(locks x-display)` load-bearing?

Placement is right — the new rule carries `(locks x-display)`, and the two stale counts
("nine of the eleven" → "ten of the twelve") were both updated in `test/live/dune` and
`scripts/ci.sh`.

I did not take that on inspection. I removed the lock **from the `live_input` rule only**,
in a throwaway worktree, and re-ran the alias under the same 2x load:

| arrangement | runs | failures | failing rule |
|---|---|---|---|
| as committed | 8 | **0** | — |
| `live_input` rule with its lock removed | 8 | **7** | `output_input.txt`, every time |

And the failures are the M2 focus race exactly, with `live_input` as the **victim** rather
than only the perpetrator:

```
-|window active: true
+|window active: false
-|on activation: (focus-enter e1)
+|on activation: (focus-enter e1 focus-leave e1 focus-enter e1)
-|primary click on a GtkButton: (focus-leave e1 button button=1 …)
+|primary click on a GtkButton: (button button=1 …)
-|Tab: (capture Tab … focus-leave e1 focus-enter e2)
+|Tab: (capture Tab … focus-leave e1 focus-enter e2 focus-leave e2)
```

That is worth recording beyond "the lock is present": `live_input` is the most
lock-dependent rule in the directory. `live_controllers` needs the input focus around one
block; `live_input` needs to *hold* it for its whole 4 s run, and it is also the only rule
that takes the focus by `XSetInputFocus` and moves the shared pointer. Had this landed
during M2 under `-j 1`, it would have worked; had anyone then run `dune test` or an
editor's run-tests action, it would have failed 7 times in 8. The `(locks)` swap the fix
wave made is what allows this test to exist at all outside `ci.sh`, which is a nice
retroactive justification for it.

---

## Mutation checks

Four mutations plus a probe, all built and run in a throwaway worktree at `5150c7e`, all
reverted.

| # | what | result |
|---|---|---|
| **M1a** | the "miss" click aimed 10 px *inside* the target instead of 10 px past it (the brief's "shift the aim → the negative must catch it") | **caught** — the negative line gains a `hit-aim=false` event in front of the sentinel: `… (label button=1 n_press=1 hit-aim=false in-bounds=true mods=none label button=1 n_press=1 hit-aim=true …)`. Reproduces the report's mutation 2 exactly |
| **M1b** | every aim shifted 30 px down (`x +. ax, y +. ay +. 30.`) | **caught hard** — all six `hit-aim` flip to `false`, and the ctrl-click block's target moves off the label so the watchdog fires: `ctrl-click: TIMED OUT` lands in the golden. This is also the only exercise anywhere of `pump_until`'s failure path, and it behaves as designed: a named line, no hang, no backtrace |
| **M2** | the capture handler returns `Propagate` for Escape instead of `Handled` | **caught** — exactly one line moves: `key Escape (capture handles): (capture Escape mods=none entry1 Escape)`. The milestone's single most valuable new assertion is a real instrument |
| **M3** | the double click's `xdotool --delay` raised 80 ms → 500 ms | **golden unchanged** |
| **M3b** | …and raised to **2000 ms** | **golden unchanged** |

M3/M3b were my own probe, not a defect hunt: `--delay 80` is the one thing in the file
that looked like a residual wall-clock assumption, since a `n_press=2` assertion usually
depends on staying inside `gtk-double-click-time` (400 ms by default) and a `sleep` inside
`xdotool` will overrun under load. **It is not one.** Two presses at the same point still
arrive as `n_press = 2` two seconds apart, so the press-count reset here is governed by
distance alone — which is precisely what the file's own comment at the target's
`~width_request` says, and it is now measured rather than asserted. The file's headline
claim that nothing in it waits on wall-clock time survives the probe.

The goldens are instruments. Combined with the report's three mutations, seven of seven
mutations of this file's load-bearing assertions are caught.

---

## Per-deviation judgement

**1. The primary target is a `Node.label`, with the `GtkButton` kept as a second target —
accept, and it is better than the sketch.** My sketch said "a button with `Attr.on_click`"
without having thought about the button's own `GtkGestureClick`. Making the exact
assertions (three button numbers, `n_press` 2, an aimed coordinate) depend on how two
gestures share a claimed sequence would have been a bad trade, and keeping the button as a
second target means the golden answers the question rather than ducking it — `primary
click on a GtkButton: (focus-leave e1 button button=1 n_press=1 hit-aim=true …)` is a fact
about GTK this suite could not previously ask. A `GtkButton` would also never have seen
buttons 2 and 3 at all, so on the sketch's tree three of the golden's lines could not
exist. Nothing lost; two things gained.

**2. Aim from `translate_coordinates` + `get_width`/`get_height` rather than
`compute_bounds` — accept without reservation; this is the best thing on the branch.** My
sketch named `compute_bounds`, and I put it in the backlog as the reason the XTEST estimate
was too pessimistic. It is bound, and it is the wrong call, and the branch found that out
by being bitten by it and then measured the difference instead of just avoiding it: a
themed `GtkButton` allocated 320x120 has a widget box of 286x110 inset by (17,5) while
`compute_bounds` answers 320x120, so aiming at the centre of the bounds lands 17 px off —
the same shape of miss that made a working handler look broken in the by-hand run. Keeping
`compute_bounds` as a reported `bounds-is-box` per target, rather than deleting the call,
is the right resolution: the sketch's claim is on the record as false for themed widgets
and true for plain ones, which is more useful than either taking it or dropping it. My
backlog wording was wrong and the branch corrected it with a measurement. (See Minor 1 for
the one place the file still says the old thing.)

**3. `%{bin:xdotool}` making an absent binary a named rule failure rather than a skip —
accept.** My sketch asked for a skip, and the reason given for not doing it is correct on
both halves: dune's `enabled_if` has no "does this binary exist" predicate, so the only
route to a skip is a second environment variable nobody sets, which would recreate the
`BONSAI_GTK_LIVE_TESTS` foot-gun the fix wave just closed (final review C1) on a rule
whose whole purpose is to be hard to lose. And `%{bin:xdotool}` is strictly better than
what I asked for in a way I had not considered: it hands the executable an **absolute
path**, so the test does not consult `PATH` at all, and `Sys.get_argv ().(1)` cannot pick
up some other xdotool. Since `334b674` puts xdotool in the devShell, its absence now means
a misconfigured shell, and failing loudly with "Program xdotool not found" is the right
answer — it is the same class of fix as the store-path removal in the same commit. I
verified the devShell provides it: `xdotool -> /nix/store/skbn0…-xdotool-4.20260303.1/bin/xdotool`,
a newer xdotool than the 3.2021 the by-hand script pinned, and the test passes with it.

**4. The propagation proof needed a control (F1) — accept, and it is a real discovery.** My
sketch said "a printable key reaching both the capture handler AND the entry", which cannot
be shown through the entry's own controller because the `GtkText` inside a `GtkEntry`
consumes printables in the target phase. Proving the printable half through the entry's
*text* and the controller half through F1 is stronger than what I asked for, and it turns
the Escape line into a one-symbol difference from a control line rather than an
unsupported negative. This is the difference between a test and an assertion.

**5. Three counters rather than one — accept.** `xdotool keydown ctrl` being a real key
press that wakes a one-counter wait before the click arrives is the kind of thing you only
find by running it. The golden naming `Control_L` on the ctrl-click line rather than
hiding it is the honest choice.

**6. A golden line asserting an ocgtk bug — accept, with a caveat.** `compute_bounds rect
survives a later ocgtk call: false` is the right instinct and has precedent
(`live_keyvals.ml` checks `Keyval` against `Gdk_constants` on every run). See Important 1
for the caveat, which is about how the bug is characterised, not about pinning it.

### Was any of the sketch's intent lost?

No. Every element I asked for is present — app-and-driver in one executable, coordinates
from the binding, `Unix.create_process`, a settling wait that pumps rather than sleeps, a
golden diff, `(locks x-display)`, the `enabled_if`, the XTEST-not-XSendEvent note written
into the file where a "simplifier" will meet it. Two corrections to the sketch were right
(the aiming call; the bounded-wait shape — my "bounded by an iteration count" is not
enough, because a *blocking* iteration cannot be counted out of, so the GLib timeout under
it is a real fix). Three things exceed it: the miss block, the `hit-aim` cross-check that
turns "some coordinates arrived" into "the coordinates aimed at arrived", and the F1
control. One thing I listed as uncovered and did not explicitly ask to be proven — that a
`Capture`-phase controller sees the key *before* a child's `Bubble`-phase one — is proven
incidentally, since both handlers append to one ordered log and the `Tab` and F1 lines show
`capture` ahead of `entry1`.

---

## Critical

None.

---

## Important

### I1 — the `graphene_rect_t` bug is worse than the record says, and the record undercounts it by 152

The branch's finding 2 is real and well caught. Its *characterisation* — "does not own its
storage", in the report, `box_of`'s comment, and `docs/m2-backlog.md` — reads as a lifetime
convention. It is not one. The stub is:

```c
/* ocgtk src/gtk/generated/ml_widget_gen.c:1369 */
CAMLexport CAMLprim value ml_gtk_widget_compute_bounds(value self, value arg1)
{
  CAMLparam2(self, arg1);
  graphene_rect_t out2;                                  /* <- a C stack local */
  gboolean result = gtk_widget_compute_bounds(…, &out2);
  …
  Store_field(ret, 1, Val_graphene_rect_t(&out2));       /* <- wraps the pointer */
  CAMLreturn(ret);
}
```

and `Val_graphene_rect_t` is `ml_gir_record_val_ptr_with_type(graphene_rect_get_type(), ptr)`
(`src/graphene/generated/ml_rect_gen.c:24`) — a *val_ptr* wrapper, no copy. So the OCaml
value holds a pointer into a stack frame that is destroyed by `CAMLreturn`. Every read
through it is a read-after-return: undefined behaviour, not a stale-but-defined buffer.

Two consequences the current wording hides:

1. **`box_of`'s workaround is not actually safe, only lucky.** Reading all four fields
   "immediately" still dereferences the dead frame — and each `Rect.get_x` is itself a C
   call that pushes a frame which may or may not sit on the same bytes. It works today,
   deterministically, on this build; it is not guaranteed by anything, and a different
   compiler, optimisation level or ocgtk rebuild could change it. The comment should say
   "works by stack-layout luck" rather than "read them immediately", so nobody adopts the
   pattern elsewhere on the strength of it.
2. **Two golden lines are therefore functions of stack layout rather than of anything this
   repository controls**: `bounds-is-box=…` on each geometry line, and the `survives` line.
   An ocgtk rebuild could turn the gate red with no change here, and the diff would point
   at this test rather than at the binding.

What keeps this Important rather than Critical: none of the test's *assertions* depend on
it. The aim comes from `translate_coordinates` + `get_width`/`get_height`, so every click,
every `hit-aim` and the negative are unaffected; only the diagnostic lines would move. And
in 20 runs they did not move once.

**The blast radius is not one stub.** I swept the generated C for the same shape — a local
`<type> outN;` handed to `Val_<type>(&outN)` — and found **153 stubs across 22 files**:

```
graphene_vec3_t 28 · graphene_rect_t 22 · graphene_point3d_t 18 · graphene_vec4_t 17
graphene_vec2_t 16 · graphene_point_t 13 · graphene_matrix_t 10 · graphene_box_t 8
graphene_quaternion_t 8 · graphene_plane_t 4 · graphene_sphere_t 3 · graphene_quad_t 2
graphene_size_t 2 · graphene_euler_t 1 · graphene_ray_t 1
```

The backlog currently says "Worth checking every stub that returns a boxed struct by value,
not just this one". That is right, and a number is better than an instruction: it makes the
fork item scoped work (one generator change — allocate and copy, the way the record
converters do for transfer-full returns — plus a regeneration) rather than an open-ended
audit. Recommend: sharpen the wording in `docs/m2-backlog.md` (and `box_of`'s comment) from
"does not own its storage" to "returns a pointer to a destroyed stack frame — undefined
behaviour, not a stale buffer", record the 153 and the fact that it is generator-wide
rather than `compute_bounds`-specific, and keep the golden line as the canary it is.

None of this asks the branch to change code.

---

## Minor

1. **The file's own headline says to use the call the file proves is wrong.**
   `test/live/live_input.ml:38`: "coordinates come from `[Widget.compute_bounds]` on the
   target in the toplevel's coordinate space, so nothing here encodes a window size, a font
   or a theme". They do not — that is deviation 2, and the 300-lines-later comment at
   `:366-378` explains at length why `compute_bounds` is the wrong call here.
   `live_input.ml:211` repeats it ("the assertion that makes `[compute_bounds]` and the
   (0,0) toplevel real rather than assumed" — it makes the *box* aim real). Both are
   leftovers from the first version of the file, which the report says is where the finding
   came from. This is the highest-priority Minor: a maintainer who reads the header and not
   the body reaches for exactly the call that produces a silent 17 px miss, which is the
   failure this branch exists to prevent. Two sentences.

2. **The report says the `live_embed` bound-ratio flake is still open; it was fixed before
   this branch started.** Expanded, with the decisive evidence, in the Addendum below —
   it is a required correction for the fix round, not an optional tidy.
   **The report says the `live_embed` bound-ratio flake is still open; it was fixed before
   this branch started.** `report.md:179-180` ("It is unrelated to this work and remains
   open") and `:263` ("is untouched and still open"). The M2 fix wave fixed it in
   `ad21cc3`, which is in `main` and therefore in this branch's history: the bench is the
   interleaved 20 000-frame version, and the report's own two ci tails show it —
   `bench: 0.0103 ms embedded, 0.0103 ms windowed, ratio 1.00`, the equal-sided signature
   of the fix, where the pre-fix version reported 0.87. I re-verified it as fixed at
   `36aa26c` (0 failures in 20 runs at 2x oversubscription). The correct statement is that
   it did not fire because it no longer flakes. Confined to `report.md`; no committed file
   repeats it.

3. **A README claim that is nearly vacuous.** The Limitations rewrite says Escape is
   "`Handled` in the capture phase and reaching neither the entry's own controller nor its
   text". The "nor its text" half proves nothing: Escape is not printable, so a `GtkText`
   would leave the text alone whether or not the key was consumed. The load-bearing
   evidence is the absence of `entry1 Escape` against the F1 control, which the report
   states correctly and the README does not mention. Same class of overclaim the M2 review
   moved out of the click-through's "what this proves", so there is precedent for trimming
   it.

4. **The README's new section is filed under the wrong heading.** `### Testing the input
   path` sits under "What is deliberately still out:", and most of its content is now what
   is deliberately *in*. It ends with the real-display residual, so it is not wrong, just
   awkward — either move the heading above that line or lead the section with the residual.

5. **`in-bounds` never adds information.** Given `hit-aim=true` (within 1 px of the aimed
   point) and an aim that is a fraction strictly inside the box for every click that
   records, `in-bounds` is implied. The only aim with a fraction of `1.0` is the miss, which
   by construction never records. Harmless, and arguably worth keeping as a guard for future
   aim points; noting so it is a choice rather than an oversight.

6. **`(Sys.get_argv ()).(1)` raises `Invalid_argument "index out of bounds"`** if someone
   runs the executable by hand without the xdotool path. The dune rule always passes it, so
   this only bites a person debugging. A one-line message naming the expected argument would
   pay for itself the first time.

7. **The by-hand scripts' new guard advertises a fix the devShell does not provide.** They
   check `xdotool`, `import` and `magick` and print "run under nix develop" for any missing
   one, but only `xdotool` was added to `flake.nix`; on this host `magick`/`import` resolve
   from an ambient `/nix/store/…-imagemagick-7.1.2-29` rather than from the shell. Since
   `.superpowers/sdd/.gitignore` is `*`, those scripts are untracked and nothing stale
   ships — the report says as much and is right that this could not be committed. Recorded
   only so the next person is not surprised. (Adding `imagemagick` beside `xdotool` would
   make the message true and costs one word.)

---

## Verdict

**Approve.** This closes the milestone's one genuinely uncovered claim — that GTK routes a
real button press and a real keystroke to the controllers this library attaches, and that
`Key_response.Handled` stops the routing — and it closes it as a test rather than as a
demonstration: 20 executions, zero failures, including 8 at 2x oversubscription, two full
gates, and no sleeps, screenshots or hardcoded pixels anywhere in it. Seven of seven
mutations of its load-bearing assertions are caught, including both the brief named. The
`(locks x-display)` on the new rule is not decoration: without it the rule fails 7 loaded
runs in 8.

The three deviations from my sketch are all improvements on it, and two of them correct
things I got wrong — the aiming call, which I had put in the backlog as settled, and the
bounded-wait shape. The branch also came back with three facts about GTK that were
previously guesses (an `Attr.on_click` on a `GtkButton` does see the press; a `GtkEntry`'s
bubble-phase controller never sees a printable; the press-count reset is by distance) and
one real binding bug.

Nothing blocks the merge. For the fix wave: **Minor 1** (two sentences — the file's header
still recommends the call the file disproves) is the one I would not merge without, and
**Important 1** is a wording change in `docs/m2-backlog.md` plus the 153-stub count, which
turns the fork item from an audit into scoped work. Minors 2-7 are one line each and can
ride or wait.

---

# Addendum — the report's "still open" claim about `live_embed`, and whether it spread

Added after the review at the team lead's request. One finding, and one clean bill of
health.

## A1 (Minor, but a required correction) — `report.md` states as open a defect that was closed before this branch began

`.superpowers/sdd/2026-08-31-xtest/report.md` says it twice:

- `:179-180` — "The `live_embed` bound-ratio flake the final review measured at 2x
  oversubscription (`bound_ratio = 1.2`, review C2) did not fire in either loaded batch —
  observed ratio 1.00 throughout. It is unrelated to this work and **remains open**."
- `:263` (under *Still open*) — "**`live_embed.ml`'s `bound_ratio = 1.2`** (final review C2)
  is **untouched and still open**."

Both are false. C2 was fixed by the M2 fix wave in `ad21cc3`, which is an ancestor of
`main` and therefore of this branch. The fix interleaved the two measurement phases into
one loop with two accumulators and raised `frames` from 2 000 to 20 000.

What makes this more than a slip is that the fixed code was **in the implementer's own
working tree while they wrote the sentence**. At their base, `b4cac1d`, the file already
reads:

```ocaml
(* … Taken sequentially the bound failed 3 times in 30 runs at 2x oversubscription (final
   review, live C2). So the two are {i interleaved}: one loop, one windowed frame and one
   embedded frame per iteration, two totals. …
   Measured interleaved, three runs under xvfb on an idle host: … ratios 0.98/0.99/0.99.
   Under 2x oversubscription, five runs: 0.97 to 1.02. … *)
…
  let frames = 20_000 in
  let bound_ratio = 1.2 in
```

— `b4cac1d:test/live/live_embed.ml:581-612`, naming "final review, live C2" explicitly.

The report's own evidence contradicts its conclusion, too. Both ci tails it pastes show
`bench: 0.0103 ms embedded, 0.0103 ms windowed, ratio 1.00 (bound 1.2)` — two equal
numbers, which is the signature of the interleaved version. The pre-fix sequential bench
reported ~0.87 with the two sides visibly different, and that asymmetry is exactly what the
fix removed. So "observed ratio 1.00 throughout" was the fix working, read as luck.

I re-verified the fix independently in the fix-wave re-review: **0 failures in 20 runs at
2x oversubscription, ratios 0.84–1.14**, against 3 failures in 30 and a 0.45–1.23 spread
before it.

**Correction for the fix round.** Both lines should say that C2 is closed, by `ad21cc3`,
and that the ratio of 1.00 the batches observed is the interleaved bench's centre rather
than a flake declining to fire. Scope is `report.md` only — I checked, and no committed
file on this branch repeats the claim: `docs/m2-backlog.md` mentions `live_embed.ml` only
in the unrelated bounded-`drain` entry, and mentions `1.2` nowhere. So nothing ships wrong;
what is at stake is the SDD record, which is what the next round will read.

## A2 — nothing in `live_input.ml` inherited the stale assumption

Checked directly, and it is clean for a structural reason rather than by luck: **there is
nothing in `live_input.ml` for the assumption to live in.**

- **It measures nothing.** No `Time_ns`, no `Span`, no ratio, no bound_ratio, no `frames`,
  no per-frame cost, no bench of any kind. Grepped for every one. The C2 fallacy —
  "contention scales both measurements and cancels", which holds only if the two
  measurements are concurrent — needs two measurements compared across time, and this file
  makes none. The only `bound` words in it are `pump_until`'s watchdog and the two
  iteration counts; the only `bounds` words are geometry (`compute_bounds`, `in-bounds`).
- **Its one wall-clock quantity is one-sided and is not a comparison.** `watchdog_ms =
  10_000` fires only when an awaited event never arrives, and its effect is a named
  `… : TIMED OUT` line in the golden. I exercised that path for real during the mutation
  work (M1b), and it behaved as designed. A failure bound is the opposite shape from the
  C2 defect, which was an assertion *about* elapsed time.
- **The one thing it did borrow from `live_embed.ml` is current, not stale.** The comment
  at `live_input.ml:153` credits "the `[live_embed.ml]` `drain` shape", and the two
  functions are byte-identical, including the 10 000 bound. I confirmed `ad21cc3` never
  touched `drain` — the single "drain" line in that commit's diff of `live_embed.ml` is a
  context line, not a change. So the borrowing is from code the fix wave left alone and
  that is still right.
- **The one place that looked like a residual timing assumption is not one.** The double
  click's `xdotool --delay 80` is the only interval the file names, and I probed it in the
  review: raising it to 500 ms and then to **2000 ms** left the golden unchanged, so
  `n_press = 2` is governed by distance alone and carries no elapsed-time claim.
- **`pump_until` corrects the sketch in the same direction the C2 fix went.** My design
  sketch said "bounded by an iteration count"; the file's comment at `:123-127` explains
  that a *blocking* iteration cannot be counted out of and puts a GLib timeout underneath
  as the real bound. That is the same kind of correction as interleaving — replacing a
  bound that does not actually constrain the thing it names with one that does.

Conclusion: A1 is a defect in the written record only, and it did not propagate into the
code. My verdict on the branch is unchanged — **Approve**, with Minor 1 (the file header
still recommending `compute_bounds`) still the one item I would not merge without, and A1
added to the fix round's list as a two-line correction to `report.md`.
