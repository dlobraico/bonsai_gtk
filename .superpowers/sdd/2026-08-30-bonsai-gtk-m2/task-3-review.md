# Task 3 review — the diagnostics backlog (`ee64cc6..b458449`)

Reviewer pass over `git diff ee64cc6..b458449` (19 files, +828/−83) against
`task-3-brief.md`, the plan's Pre-flight corrections and Global Constraints, spec §11 and
§5.3, and `progress.md`'s record that task-2's Minor M1 and M3 were assigned here.

## Summary

All five items land, both task-2 carries land, and the gate is real: I re-ran
`nix develop -c dune build @all` (exit 0), `dune build @test/runtest` (exit 0),
`BONSAI_GTK_LIVE_TESTS=1 xvfb-run -a dune build @test/live/runtest` (exit 0) and
`nix develop -c ./scripts/ci.sh` → `all green` (exit 0), with a clean working tree
afterwards. Every golden change is an addition; no existing rejection line moved, which is
the evidence the two-loop stack-claim rewrite did not weaken an existing check.

The two structural pieces are the interesting ones and both hold up:

- **The placement check** is threaded correctly. Every node reaches `check_placement`
  exactly once per pass — `mount` at entry (`src/patcher.ml:377`) covers `mount_single`,
  `mount_list`, `mount_slots` and `patch_list`'s `Insert`; `patch` at entry
  (`src/patcher.ml:566`) covers `patch_list`'s `Update`, `patch_single`'s `Some, Some` and
  `patch_slots`; the root arrives through the shadowing wrappers at
  `src/patcher.ml:835-846` with `parent_kind:None`. `patch_children` takes the **new**
  node's kind (`src/patcher.ml:804`), so a props change under an unchanged constructor
  cannot leave a stale parent. The public `mount`/`patch` signatures in `src/patcher.mli`
  are unchanged.
- **The stack-name swap fix** is correct, and stronger than the task text asked for. I
  worked the six cases the brief names; details under Deviation 2. The switcher-ordering
  question has a clean answer: `apply_stack_claims` runs at the end of `mount`/`patch`,
  and `Driver.frame` calls `run_fixups` strictly after that (`src/driver.ml:62-71`), so
  `resolve_stack` never reads a half-applied table.

Three Important findings, all of them contracts stated in a doc or an mli that the shipped
behaviour now contradicts, plus one architectural placement worth recording. No Critical.

**Verdict: Needs fixes** (I1 and I3 are paragraph-sized corrections to mli text that now
says the opposite of what the code does; I2 may reasonably be argued down to a carry).

## Per-deviation judgement

**Deviation 1 — the check lives in `check_placement`, with `parent_kind` threaded into
`mount`/`patch` rather than into the five child helpers. Sound.**
The reasoning in the report is right: `mount_single`/`mount_list` are handed the parent's
`Widget.t`, not its `Kind.t`, so the kind has to be threaded either way, and threading it
one level further collapses five check sites into one that already took `~path ~is_root`
and already ran at exactly those points. I verified coverage exhaustively (above) — there
is no mount or patch entry that skips it, including `patch_list`'s `Update` arm when the
kind changes (which double-checks, once in `patch` and once in the inner `mount`; harmless,
same verdict both times). `parent_kind : Kind.t option` being `None` only at the root is
the right encoding, and the root arm's message is distinct and useful. The wrapper shadowing
keeps the public signatures byte-identical, which is what `live_patcher.ml` and
`live_containers.ml` depend on.

**Deviation 2 — the swap fix is per *pass* (a `stack_claim Queue.t` applied in two loops at
the end of the walk), not two loops over a child list. Sound, and a strict improvement.**
The task text's prescription assumed `note_interest`'s rename arm ran inside a
per-children loop; it does not — it is called once per node from `mount` and from `patch`
— and two stacks exchanging names need not be siblings, so the generalisation one level up
is the only shape that works. Case by case:

- *Two stacks exchanging names.* Loop 1 removes both registrations (each guarded by
  `Gobject.same`, so each removes its own), loop 2 registers both. Pinned by a golden that
  asserts the **right** stack, not merely the absence of a raise: `before the swap,
  switchers drive: pa, pb` / `after the swap, switchers drive: pb, pa`.
- *Rename to a free name.* Give-up removes, take registers. Exercised by the swap case's
  two halves.
- *Unchanged name — the "heal" path.* The old `Hashtbl.set` becomes give-up-then-take of
  the same name. When the entry was lost to an earlier teardown the give-up is a guarded
  no-op and the take re-registers, so it still heals. When the entry is held by a
  *different* widget it now raises where `set` used to overwrite silently — which cannot
  be a new false positive, because two live stacks under one name is already rejected at
  mount and at patch. Improvement, not a regression.
- *Genuine collision.* Still raises, from loop 2, with the same message and the same path:
  `rejected: ren/0/1: two Node.stacks are named "first" in one tree` is byte-identical in
  `expected_containers.txt`.
- *A mount that raises mid-walk.* `apply_stack_claims` never runs, so the claims stay
  queued; `Driver.frame` catches, marks the scheduler broken and calls `abandon_fixups`
  (`src/driver.ml:110-116`), which now clears `stack_claims` too — and `broken` makes
  every later `frame` a no-op, so there is no next pass to carry them into. Correct.
- *Interaction with `drop_stack_names` in the kind-change arm.* Both `drop_stack_names`
  and `destroy`'s own `unregister_stack` run **during** the walk, i.e. strictly before any
  claim is applied, so the mount-before-destroy ordering can no longer collide at all. The
  report's "belt-and-braces, kept because it states the requirement" is a fair call.

One unremarked bonus worth recording: the deferral also fixes a pre-existing false
positive. Under the old code an `Insert` of a stack whose name is freed by a `Remove`
later in the same op list raised `two Node.stacks are named`; now the destroy runs during
the walk and the claim applies after it. Nothing pins that, and nothing needs to today.

Two residuals, neither blocking. `apply_stack_claims` can mutate `ctx.stacks` partially
before raising (all give-ups applied, some takes) — consistent with the existing
"a raising frame stops the driver for good" contract, but it means a hand-driven test that
continues past a rejection is working against a table missing the failed pass's give-ups.
And see Minor M4 for a comment this commit invalidated.

**Deviation 3 — a stack with no pages at all is exempt from the `~visible_child` raise.
Sound.** `~visible_child` is a required argument, so a model rendering an empty page list
has no value it could pass that would be right; raising there would make an empty stack
inexpressible. This is narrower than the "stop and report" the ruling demanded, and the
premise the ruling actually asked about was checked properly: the add-and-select-in-one-pass
case at `test/live/live_containers.ml:659-679` runs with the raise in place and does not
fire, which is the proof that the fixup pass really can tell "not yet" from "never". Both
sides are pinned. The residual risk is the one the ruling knowingly accepted — a frame that
drops a page while `visible_child` still names it now stops the driver where it used to be
inert — and that is exactly what makes I1 an Important rather than a nicety.

**Deviation 4 — the `select` rejection is path-prefixed by `enqueue_fixups`'s existing
`child_op ~path` rather than by `select` itself. Sound.** §11 requires the node path and
`select` is a container op; container ops know nothing about where they are anywhere else
in this file. Golden reads `typo/0: …`, the stack's own path.

**On the test ordering.** The report is candid that `~max_length` could not compile before
`Kind` had the field, so the four runtime checks were proved failing by temporarily
neutering them rather than by red-then-green in sequence. The neutered diff is reproduced
in the report and is re-runnable, and the `swap rejected: swap/0/2: two Node.stacks are
named "beta" in one tree` line in it is genuine evidence that the two-loop application is
what fixes item 5. Weaker than the plan's ordering, adequately compensated, correctly
disclosed.

## Critical

None.

## Important

**I1. `Node.stack`'s doc now states the opposite of what `~visible_child` does, and
`run_fixups`'s doc does not list the new raise.**
`vtree/node.mli:547-548` still reads: *"Naming a page that does not exist leaves the
selection alone rather than raising: the frame that adds the page will select it."* After
this commit that holds only for a stack with **zero** pages; with one or more it is
`Invalid_argument`. This is the single place an application author reads the `~visible_child`
contract, and it is the contract this task exists to change — the `entry` and
`scrolled_window` docs in the same file were both updated, this one was not.
`src/patcher.mli:51-57` has the matching gap: `run_fixups`'s "Raises" paragraph names only
the switcher-resolves-nothing case, so a hand-driven test author reading it does not learn
that a stack's `select` can raise from the same queue.

Failure scenario: an author reads `node.mli`, wires `~visible_child` to a selection state
that can lag the page list by one frame (close-a-tab, where the list is written by one
effect and the selection by another), and the first frame on which they disagree raises out
of `run_fixups` inside the patch guard — `Driver.frame` marks the scheduler broken
(`src/driver.ml:113`) and the application is dead for good, with a message the documentation
said could not happen.

Fix: replace the sentence with the shipped rule, including the empty-stack carve-out from
deviation 3 and the fact that the raise arrives from the fixup pass with the stack's node
path; add one clause to `run_fixups`'s Raises paragraph.

**I2. The placement table lives in `src/patcher.ml`, so `Bonsai_gtk_test` now certifies
trees the runtime rejects.**
`test_lib/bonsai_gtk_test.ml:32-49` (the comment at line 33) exists for precisely this: its comment says *"The event
half of what the runtime checks at mount, checked here from the same table ([Events]) so
that a headless suite cannot certify a tree the runtime refuses."* The plan's Task 1
rationale says the same thing in the milestone's own words. `placement_attrs_read_by` and
`placement_attr_reader` (`src/patcher.ml:273-322`) are pure `Kind.t` / `Attr.Name.t` data
with no ocgtk in them — structurally identical to `Events.for_kind`, which was deliberately
put in `vtree/` for this reason — but they landed in `src/`, which `test_lib` cannot depend
on. The parent kind the check needs is available to a `Children.iteri` walk over `Node.t`
just as it is to the patcher's.

Failure scenario: a handle test over a view carrying `Attr.page_title` on a box child
renders and passes; the same view raises `Invalid_argument` at first mount in production.
The gap gets worse at Task 6, whose arm is `List_box -> [ Row_selectable; Row_activatable ]`
— a row attribute on a non-row child is a far likelier typo than `grid_cell` on a box, and
`sidebar.ml`/`layer_panel.ml` are exactly the screens a headless suite would cover first.

The task text did say "in `src/patcher.ml`", so this is plan-directed and the implementer
may reasonably argue it down to a carry rather than a fix here. If argued down it needs to
be recorded — the report's carry list mentions the two tables only as something Tasks 6–8
must extend, not as a headless/live divergence.

**I3. `Node.entry`'s new doc promises a feedback path that does not exist, and the
divergence it hides costs a write on every frame.**
`vtree/node.mli:131-133` says lowering `max_length` below the current text *"truncates that
text, which GTK does on the widget and which the model learns about through
[Attr.on_changed] like any other edit."* It does not. `Signals.dispatch`
(`src/signals.ml:35`) returns immediately while `in_patch` is set, and both writes that
can truncate — `w_entry.ml:121-122`'s `set_max_length` in `update`, and the controlled text
write in `reassert` — run inside `Scheduler.with_patch_guard`. The `changed` emission is
swallowed and the model is never told.

This commit's own golden shows the resulting state: after `~max_length:3 ~text:"abcdefg"`,
`test/live/expected_controls.txt` prints `(GtkEntry (text abc) (max-length 3) …)` while
`live.node` still holds `"abcdefg"`. That divergence is permanent absent user input, and it
is not free: `needs_text` (`w_entry.ml:24`) compares the widget's `"abc"` against the node's
`"abcdefg"` and can never become false, so `reassert` writes the text and re-reads the
caret position on **every** subsequent frame — including every idle tick, through
`reassert_only`, which is the cost Task 2 was written to remove.

Fix, in order of preference: (a) have `w_entry`'s `reassert` stop re-writing once GTK has
truncated — compare against what the widget can actually hold; or at minimum (b) correct
the sentence to say the truncation is silent, the node keeps the untruncated value, and a
`~text` longer than `~max_length` is an application error. Either way the "learns about it
through `Attr.on_changed`" claim has to go: it is a documented behaviour with no test,
which is exactly the failure mode the plan's reviewer remit names.

## Minor

**M1. The `visible_child` raise is pinned at mount only, never at patch.** The brief asks
for each diagnostic "at mount AND at patch where applicable", and the placement check gets
both (`page_title added by a patch: mis/0/0: …`). The stack one only has the mount case
(`raises "visible_child names no page"` mounts and then calls `run_fixups`). The mechanism
is the same re-enqueue on every pass, so the behaviour is almost certainly right — but a
change that made the fixup mount-only would leave the golden untouched. One patch that
introduces a typo'd `~visible_child` beside the existing case would close it.

**M2. The add-and-select-in-one-pass case is now load-bearing and does not say so.**
`test/live/live_containers.ml:659-679` is the only evidence that the new raise cannot fire
on a legitimate frame — the whole of the task's ruling rests on it — but its comment still
describes only the old contract ("`W_stack.select` is a no-op while `get_child_by_name`
has nothing"). A future editor simplifying that block would delete the proof without
knowing it was one. Two sentences on that comment.

**M3. Nothing pins that a failed pass leaves no stack claims behind.**
`expected_containers.txt` pins the fixup queue across a failure (`fixups left behind by the
failed pass: 1` / `fixups after abandon_fixups: 0`) and `ctx.stack_claims` is exposed in the
same `private` ctx, but it is never counted. Every `raises` call in the file is followed by
`P.abandon_fixups`, so a regression that stopped clearing claims would be invisible there
and would surface only as a mystery `two Node.stacks are named` from an unrelated later
frame. One more `Queue.length` print beside the existing two.

**M4. `live_driver.ml`'s new comment relies on a pin this commit removed.** The comment
added at `test/live/live_driver.ml:303-309` says *"The stack half of the same hazard is
already pinned: a `register_stack` from the walk raises `two Node.stacks are named
"phys-nav"`."* After this commit `note_interest` enqueues a claim instead of registering,
and `reassert_only` never calls `apply_stack_claims` — so a claim enqueued from the
reassert walk would sit in `ctx.stack_claims` and raise from the *next* real patch, one
frame late, or never if no patch follows. The window half the comment was added to fix is
correct and lands; the parenthetical about the stack half is now wrong.

**M5. The empty-stack carve-out is stated only in `w_stack.ml`'s comment and the live
test.** It is part of the public contract of a required argument. Folds into I1's fix.

**M6. `Attr.measure_overlay` on an `Overlay`'s *main* child stays accepted and inert.**
The table's granularity is the parent's kind, not its slot. Correctly called out in the
table's comment and in the report's "Deliberately not done", with the right trigger for
revisiting it (a slot container reading two different placement attrs). Worth one backlog
line so it is not rediscovered as a bug.

## Out of scope, correctly not attempted

- **Two grid children in one cell.** The brief listed it conditionally ("if included"); it
  is a `docs/m1-backlog.md:124-126` item filed under *"Carried out of the final review"* and
  attributed to containers M4, not to Task 3's five. Correctly absent.
- **`w_switch`'s `create` hand-rolling the active write.** `docs/m1-backlog.md:108-109`
  assigns it to **Task 4**. Correctly absent — no `w_switch.ml` change in the diff.
- No other creep: the diff touches exactly the files the task named, plus the two carry
  files (`docs/m1-backlog.md`, the spec's §5.3) and `test/live/live_driver.ml` for carry M1.

## The two task-2 carries

- **Minor M1** — `test/live/live_driver.ml`'s `phys` driver now prints from
  `on_window_created`, and `expected_driver.txt` grew by exactly one `phys window created`
  line, which is what the finding asked for. The related observation (nothing distinguishes
  the phys-equal fast path from the slow one) was correctly ruled a backlog line and is one,
  at `docs/m1-backlog.md:239-244`, attributed to the task-2 review. See M4 for the one
  inaccurate clause in the new comment.
- **Minor M3** — spec §5.3 gains an *M2 amendment (2026-08-30)* in the same style §5.3 and
  §11 already use, with the two superseded sentences left standing above it. It states the
  marker, the `move : … option` encoding, the three `None` containers and `Notebook`'s
  `Some`, the raise on a `Move` reaching a container without one, and the set-only
  apply-equality. Matches the finding.
- **Minor M2** was ruled "leave it" by the controller and is left.

## Verdict

**Needs fixes.** Nothing in the shipped behaviour is wrong — the five items work, the
placement threading is complete, and the stack-claim rewrite is correct on every case the
brief names and fixes a pre-existing false positive besides. What needs answering is three
Important findings, two of which (I1, I3) are mli text that now contradicts the code and
one of which (I2) is an architectural placement the task text prescribed and that may be
argued down to a carry. The six Minors are test-durability and comment-accuracy items;
M1–M3 are cheap enough to be worth doing in the same round.

---

# Re-review — fix round 1 (`b458449..3ea4594`)

Scoped to the two fix commits and to my own findings: `a9b7b34` (I2, M6) and `3ea4594`
(I1, I3, M1–M5). I did not re-review the rest of the task.

## What I verified myself

- `nix develop -c ./scripts/ci.sh` on the committed tree → `all green` (exit 0).
- **Single source.** `placement_attrs_read_by`, `placement_attr_reader`,
  `placement_attr_names` and `attr_spelling` are gone from `src/`. A grep for the table
  across `src/` and `test_lib/` returns exactly two hits, and both are call sites:
  `src/patcher.ml:276` and `test_lib/bonsai_gtk_test.ml:49`, each
  `Option.iter (Placement.rejection …) ~f:invalid_arg`. No copy, no second spelling.
- **The handle's message is the runtime's.** Compared byte for byte against the live
  goldens; `root/0/0: Attr.grid_cell is not read by Box (a placement attribute is read by
  the container, and this one holds children for Grid)` is identical in
  `test/handle/test_handle.ml` and `test/live/expected_containers.txt`. It has to be —
  both raise the string `rejection` returns.
- **`capped` counts characters, not bytes.** I transcribed the algorithm and ran it against
  Python's UTF-8 slicing over 14 cases — 2-, 3- and 4-byte sequences, the
  `String.length text <= max_length` fast path, exact-fit, and `max_length <= 0`. Zero
  mismatches. The continuation-byte test (`land 0xc0 = 0x80`) and the `String.prefix` of a
  byte offset are both right.
- **The write counter is not vacuous.** In a throwaway worktree at `3ea4594` with `capped`
  neutered to the identity, the two goldens move to `two idle frames over an over-long
  text wrote: 4` and `an idle frame over a multi-byte text wrote: 2` — the report's numbers
  reproduced independently. The probe connects `W.Editable.on_changed` directly rather than
  through `Signals`, so the patch guard does not suppress it; that is why it registers the
  library's own writes, which is exactly the thing being counted.
- **The character/byte distinction is pinned by the dump, and only by the dump.** With
  `capped` replaced by `String.prefix text max_length`, the only golden that moves is
  `(text "h\195\169l")` → `(text "h\195\169")` — two characters where GTK allows three —
  and both write counts stay at `0`. That confirms the report's own correction (a byte-wise
  cap settles on a wrong string rather than writing every frame) and confirms the
  multi-byte case is load-bearing rather than decorative.
- **GTK agrees with `capped`.** Under the neutered build the library writes the full
  `"héllo wörld"` and the dump still reads `h\195\169l` — GTK's own truncation lands on
  exactly the string `capped` computes. That is independent evidence for the unit, not just
  a golden agreeing with itself.
- **No regressions in the goldens.** Zero deleted lines across
  `git diff b458449..3ea4594 -- test/live/expected_*.txt`. The only removals anywhere under
  `test/` are the two comments M2 and M4 rewrote.
- Worktree removed; the checkout is clean at `3ea4594` on `m2` (the one untracked
  `.beads/issues.jsonl` predates this review).

## Finding by finding

**I1 — the `~visible_child` and `run_fixups` contracts. Resolved.**
`vtree/node.mli`'s `stack` doc loses *"Naming a page that does not exist leaves the
selection alone rather than raising"* and states the shipped rule: `Invalid_argument` from
the fixup pass with the stack's path and the page names it does have; why that pass is the
earliest point the mistake is knowable; the lag-by-a-frame consequence in concrete terms
(closing a tab, one effect rewriting the list and another the selection) and that it stops
the driver for good; and the zero-page carve-out, which is M5 and belongs exactly there
because it is the contract of a required argument. `src/patcher.mli`'s `run_fixups` Raises
paragraph gains the second clause with the one-sentence reason. Both now match the code.

**I2 — the placement table moves to `vtree/`. Resolved, and better than the finding asked
for.** `vtree/placement.ml(i)` sits beside `Events` and both consumers read it. The
departure from the `Events` precedent is the right call and is argued in the mli: `Events`'
two consumers rebuild the same message from the same ingredients and agree *by convention*,
whereas placement's message has two shapes and names three things, so both consumers call
`rejection` and get one string — identical by construction rather than by inspection.
`names` is derived from `reader` so the two tables cannot disagree about membership, and
`reader` stays exhaustive with no wildcard, which is the forcing function Tasks 6–8 need.

`test/test_placement.ml` pins the table itself, which nothing did before: the three
placement names and their readers, that the other 29 of 32 `Attr.Name.t`s are classified
non-placement, that `read_by` and `reader` are mutual inverses, that every placement name
is read by exactly one container, and that the wildcard arm rejects all. The four handle
cases plus the positive case pin the check in both directions at handle time. The
`test_lib` mli's "what is validated here" paragraph is rewritten honestly, including the
sharper point that a misplaced placement attr is unobservable and the handle was therefore
the only place it could ever have been caught.

One observation, not a finding: `check_placement` runs the window-off-root check before the
placement check and the handle runs placement only, so a node that is both a nested
`Node.window` and carries a misplaced attr reports different messages headlessly and live.
The `test_lib` mli already lists window-off-root among the mount-only checks, so this is
documented rather than surprising, and the report's "same one here and there" claim is
about the two checks the handle actually runs, where it holds.

**I3 — the `max_length` truncation. Resolved, both halves.**
(a) `capped` is correct on the unit and verified above; `create` and `reassert` both write
and compare it, so a node the model re-renders unchanged costs one write rather than one
per frame, on the patch path and on the idle-tick path through `reassert_only`. The
ordering is right in both directions: `update` writes `set_max_length` before `reassert`
writes the text, so lowering the cap truncates and then compares against the truncated
widget, and raising it restores the full text from the node on the same frame — which is
incidentally what keeping the untruncated value in the node buys.
(b) The doc drops the false `Attr.on_changed` claim entirely and says what actually
happens: the truncation is silent because the write is inside the patch guard, the node
keeps the untruncated value so model and screen disagree until a later render or a user
edit, the library does not rewrite every frame, and a model that needs the truncated value
should clamp where it owns the text. Labelled as an application inconsistency the library
tolerates, which is the honest framing.

**M1 — Taken.** A stack mounted with a correct `~visible_child` and patched to a typo'd
one: `visible_child typo introduced by a patch: retyped/0: …`. The raise now has a golden
on both the mount and the patch path.

**M2 — Taken.** The add-and-select case now says it is load-bearing, says what a regression
would look like (it would stop selecting the wrong page and start killing the driver), and
tells a future editor not to simplify it away.

**M3 — Taken.** `stack claims left behind: 1` / `stack claims after abandon_fixups: 0`
beside the existing fixup counts. The `1` is real coverage rather than a zero that would
print either way: the `halfbuilt` pass mounts a stack and then raises on a nested window,
so there genuinely is a claim to strand.

**M4 — Taken, accurately.** The parenthetical now says the stack half *used to be* pinned,
why it is not any more (names became claims, `reassert_only` applies none), and what the
consequence would be (a claim from the reassert walk raises from the next real patch — one
frame late, or never for a constant app). "Unpinned rather than broken" is the correct
characterisation: the walk still enqueues nothing.

**M5 — Taken,** folded into I1's `node.mli` rewrite as the finding suggested.

**M6 — Taken** as the backlog line, with the trigger for revisiting it and attribution.

**The two Deviation-2 residuals I marked non-blocking are argued down, correctly.** The
partial-mutation-before-raise case cannot arise outside a test that is already calling
`abandon_fixups`, and making it atomic means building a whole replacement table for a case
production never reaches; leaving it is right. The incidentally-fixed `Insert`/`Remove`
false positive is left unpinned, as I suggested.

## New findings

None Critical or Important. One trivial observation: `Placement.is_read_by ~parent name`
answers `true` for a name that is not a placement attr at all. The mli says so plainly and
`misplaced` pre-filters by `names`, so nothing in the tree can be misled — but the name
reads as a question about one attr and answers a different question over two-thirds of its
domain. Not worth a commit on its own; worth knowing if a Task 6–8 author reaches for it
directly.

## Verdict

**Approved.** All three Important findings are resolved — I1 and I3 by making the docs
match the code and, for I3, by fixing the code as well; I2 by a genuine single-source move
with the headless and live checks now provably raising the same string. All six Minors are
taken or argued. The two behavioural claims that mattered — that the truncated comparison
uses characters and that it actually stops the per-frame write — I reproduced independently
rather than reading, and both hold. CI is green, no golden line was deleted, and nothing in
the round-0 behaviour regressed.
