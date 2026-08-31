# Task 16 review — clean-tree CI, the Task 15 carries, and the gallery click-through (`055c70e..3cb9d09`)

Reviewer pass over `git diff 055c70e..3cb9d09` (9 files, +172/−50), read in full, against
`task-16-brief.md`, `progress.md`, `task-15-review.md` (the source of the carries) and
`task-16-report.md` read in full. Fact-checking on the M1 Task 11 / Task 15 bar: every count
re-derived from the code, every claim about a widget's behaviour checked against the widget,
every screenshot in `task-16-clickthrough/` opened and read rather than listed.

**Gates run by the reviewer.**

| what | result |
|---|---|
| `nix develop -c ./scripts/ci.sh`, warm `_build`, ×3 | **all green** ×3 — 54.8 s, 54.6 s, 54.3 s |
| `dune build @test/live/runtest --force` (the report's trap) | returned in **3.257 s** having run nothing — trap confirmed |
| `@test/live/runtest` **parallel** (the pre-fix arrangement), outputs deleted between runs, ×7 | **3 failures**, including the very first run |
| `@test/live/runtest -j 1` (as shipped), outputs deleted between runs, ×8 | **8 passes, 0 failures** |
| `(locks …)` on dune 3.22 / lang 3.17, two 2 s rules at `-j 8` | strictly sequential, 4.0 s — see I3 |

All three parallel failures are the same diff, in the same place
(`test/live/expected_controllers.txt` line 12). The race reproduced on my very first attempt,
and at **3 in 7** rather than the report's 1 in 10 — this host is carrying other agents, and a
busier machine widens the window, which is worth knowing: the rate the report measured is a
floor, not a typical value.

```
++++++ test/live/output_controllers.txt
+|n1 focus from presenting the window: focus-enter,focus-leave
+|n1 focus parked off the target:
```

That is the report's diff character for character. Parallel wall clock 28.6 s, matching the
report's 28.6 s → 30.8 s figure.

## Summary

The task did the job it was given and then some. The clean-tree run was genuinely clean — no
`git clean`, only build artefacts removed by hand, `.superpowers/`, `_opam/` and `.ocgtk-src/`
left alone — and it flushed out a real defect in the gate rather than in the code, diagnosed it
with measurements instead of assertion, and wrote the diagnosis into the two places a person
would look. Step 4, which the brief allowed to be *skipped* with a note if no real display
existed, was instead executed through the XTEST route the backlog calls its most valuable
follow-up: real X button presses and keystrokes into the gallery, and the milestone's first
end-to-end exercise of `Attr.on_click` and `Attr.on_key_pressed`. I opened all three montages;
every readout the report claims moved, moved, and the checksums confirm the two "nothing
happened" frames really are byte-identical to their predecessors.

Three things are wrong, none of them Critical and none of them in the code.

1. **I1** — the fix for Task 15's I3 overshot: the README now promises a refuse-before-write
   guarantee for three widgets that have no such thing and for one UTF-8 case the code
   deliberately does not refuse.
2. **I2** — the backlog still carries the task-14 M11 entry telling a maintainer that this
   exact golden diff is an accepted flake not to be fixed. That is the one piece of prose that
   can undo the whole of §4.
3. **I3** — `-j 1` works, but dune's own `(locks)` is the better fix, it was not among the two
   alternatives the report weighed, and I verified it works on this toolchain. As shipped the
   invariant is enforced at one call site rather than by the rules that need it.

The report itself is the best of the milestone's sixteen on the thing that matters most here —
it distinguishes what it measured from what it argued, and it volunteers the methodology trap
(`--force`) that would have let it publish a false green. Two sentences in its "what this
proves" list are stronger than the evidence (Minor M1), which is the only place its honesty
slips.

## Per-deviation judgement

**1. No real display; Xvfb + XTEST instead. Accept, and it exceeds the brief.** The brief's
Step 4 says: "If no real display is available, say so in the report and leave the item in
`docs/m2-backlog.md` rather than quietly skipping it." The implementer said so, kept the item,
*and* ran the check anyway by the one route left. The residual left in the backlog (a window
manager, a compositor, Wayland's `gdk_wayland` path) is the honest remainder and is correctly
described. The one caution is that a rewritten backlog item now rests on the click-through's
"what this proves" list, and two entries in that list are overstated — see Minor M1.

**2. `.beads/issues.jsonl` moved aside for the gate runs, restored afterwards. Accept.**
Verified: `git status --porcelain` is `?? .beads/issues.jsonl` and nothing else, the file is a
`bd` export (`{"_type":"issue","id":"bonsai_gtk-811",…}`), and `git diff HEAD --stat` is empty.
The brief said no `bd`; moving an untracked export aside so `git status` is empty for a
clean-tree gate is the right reading and it was put back.

**3. Three commits rather than the brief's single "M2: clean-tree CI pass". Accept, clearly
right.** The three are three different things and the middle one carries findings a squashed
message would bury. All three carry both trailers with the brief's session URL. `3cb9d09`'s
message is the best commit message on the branch: it leads with the failing diff, states the
wrong reading, refutes it, gives the four measurements, and names the two fixes it did not
take.

**4. `examples/gallery.ml` edited, outside the brief's expected file list. Accept.** One string
and a comment, caused directly by a finding, and the string is pinned by nothing — I grepped
the tree: `examples/gallery.ml:751` is the only occurrence. `test/handle/test_gallery.ml`
checks the gallery against `Kind.Variants.descriptions`, not its prose.

**5. `test/live/dune` edited (comment only). Accept.** Documentation matching the invocation is
the point of the comment. See I3 for what that comment now recommends.

**6. `src/driver.ml` edited — a code change in the CI-pass task. Accept.** Task 15's review
offered exactly this or scoping the spec sentence, and the implementer's argument for the code
half is right: the caller who needs to be told `Expert.embed` exists is the one with an
existing GTK app, i.e. the one hitting the `start` message. The message is now symmetric with
the `embed` one (`src/driver.ml:49-58`), the change is one clause, and `git grep` finds exactly
one consumer — `test/live/expected_driver.txt:29`, promoted in the same commit. Nothing else in
the tree holds the old string except the M0 plan document, which is a dated record.

## Verification of the brief's checklist

**(1) `ci.sh` changes.** Both are right and both are commented at the right length.

- `scripts/ci.sh:36` — `git diff --exit-code HEAD -- '*.opam'`. Correct, and the comment says
  what `HEAD` buys. This is the backlog's one-word fix, and the backlog item is struck and
  marked done rather than deleted (`docs/m2-backlog.md:509-510`).
- `scripts/ci.sh:82` — `-j 1` is on the live invocation **only**. I read the whole script: no
  other `-j` anywhere, `dune build @all` (line 28), the two `-p` builds (48–57) and
  `@test/runtest` (39) all keep full parallelism. Correctly scoped.
- **Race analysis: right.** The failure shape confirms the mechanism. Expected is
  `focus-enter` on the present line and `focus-leave` on the park line; observed is both on the
  first and nothing on the second — which is what happens if the widget loses focus *before*
  the park step, so the park has nothing left to take. A neighbour's toplevel mapping is the
  only thing on that display that does it, and the report's control arms (0/15 solo, 2/8 with
  deliberate window churn) are the right two to have run.
- **Cost: right.** 28.6 s parallel measured here; the report's serial 30.8 s is consistent with
  my eight serial runs. Full `ci.sh` was 54.3–54.8 s on a warm `_build` against the report's
  81–91 s cold — the difference is the cold dune build the report deliberately forced (`_build`
  came back at 1.2 G), not a discrepancy. The archived `task-16-ci-clean.log` carries the eight
  section headers, `all green`, `CI_EXIT=0` and `ELAPSED_SECONDS=84`, matching §1's table.

**(2) `-p` builds and example smoke from a clean tree.** Green in every `ci.sh` run. The
package line the brief asked to confirm holds: `test/dune` takes `core bonsai_gtk.vtree
expect_test_helpers_core` only, `test/handle/dune` is the one taking `bonsai_gtk_test`, and
`Events` is `vtree/events.ml` with no `src/events.ml` to shadow it.

**(3) The Task 15 carries.**

| carry | landed | verified against |
|---|---|---|
| I1 six `Payload` signals, both places | **yes** | exactly six construction sites: `src/controllers.ml:139,242,263`, `src/widgets/w_list_box.ml:274`, `w_flow_box.ml:252`, `w_notebook.ml:228`. Both `src/signals.mli:76-89` and spec §6.4 now say six, name all six, and state the two generalising rules |
| I2 `CheckButton.set_group` | **yes** | `.ocgtk-src/…/check_button.mli:42` has the external; the parenthetical is gone and the replacement reason (grouping is a mutable pointer between live widgets, not a prop) is correct |
| I3 the third refusal | **partly wrong** — see **I1** below |
| M1 six event-value modules | **yes** | `src/bonsai_gtk.mli:45-51` re-exports exactly six; spec §7 and the backlog both say six |
| M2 `start`-side root message | **yes** | `src/driver.ml:49-52`, golden promoted, one consumer |
| M3 a box reorders too | **yes** | `w_box.ml:41` and `w_notebook.ml:346` are the two `move` implementations that really reorder; `w_list_box.ml:373` and `w_flow_box.ml:374` are `Some` but remove-and-re-insert, and `stack`/`grid`/`overlay` are `None`. "with `box`, one of the two containers whose children move in place" is exact |
| M4 the `git mv` claim | **yes** | replaced with the 9 % similarity statement and the old path |
| M5 the search-entry exception | **yes** | matches `w_search_entry.ml`'s own comment and the open backlog item |
| M6 headless guarantee scoped | **yes** | the added sentence matches `test_lib/bonsai_gtk_test.mli`'s N8 caveat |

Six of the nine are exactly right, one (M3) is better than the review asked for, one (I1) was
derived rather than copied as instructed — and one (I3) is wrong in the other direction.

**(4) The gallery instruction fix and the backlog.** The instruction fix is correct and the
comment behind it records a real measurement (see below). The backlog gained four items and
struck one; all five changes are real. The one problem is what it did **not** change — I2.

**(5) Housekeeping (§8).** Accurate and still true: `Xvfb :100`–`:104` are up with 3 h 20 m of
uptime and their `/tmp/.X10*-lock` files. Leaving them alone while other agents may be inside a
run is the right call. One detail in the note is wrong — they do not "push `xvfb-run -a` to
higher display numbers", because `xvfb-run -a` starts at `:99`, below them; every run of mine
took `:99`.

**(6) Out-of-scope creep.** None. Nine files touched, three of them outside the brief's
expected list, all three declared in §7 and all three justified.

### The click-through, checked against the artefacts

I opened `montage-readouts.png`, `montage-pass2.png` and `montage-entries.png` and checksummed
all 32 screenshots. Everything the report claims is in the pictures:

- pass 2: `button 3, press 1, at (498, 7), no modifiers` → `button 2, press 1` → `button 1,
  press 2` → `button 1, press 1, at (498, 7), ctrl`. Three buttons each reported as itself, the
  press count, the widget-local coordinates and the modifiers, all from real X events.
- pass 1: `keyval 0x6f` after typing `hello`, `Escape -- consumed here` with `escapes: 1`,
  `keyval 0x41, ctrl+shift`, `keyval 0xff09` with `focus: second entry`.
- `montage-entries.png`: the first entry holds `hello` through the Escape and the Tab, and the
  focus ring is on the second entry in the last tile.

**The missed-clicks measurement is sound, and the checksums are the proof.**
`11-after-left-click.png`, `12-after-right-click.png` and `13-after-double-click.png` are one
identical file (`2827712c…`) — pass 1's secondary and double clicks changed literally nothing —
and `23-double-click-on-target.png` and `24-click-below-label.png` are likewise identical
(`2b32bf5c…`), which is the deliberate 14 px-below control. That is a real measurement, not a
narrative. (Pass 1's three clicks were at three different points — `(680,146)`, `(700,160)`,
`(660,130)` in `clickthrough.sh` — so the two misses are 14 px below and 16 px above; the margin
explanation covers both, and the comment in `examples/gallery.ml:743-748` correctly records only
the one that was measured deliberately.)

The diagnosis is right: in GTK4 `Attr.margin` is space the parent's layout reserves *outside*
the widget's allocation, so a gesture on the `Node.label` cannot see it. And from the readout,
the label's allocation is wide (screen x 680 → local x 498) but only about text-height tall,
which is exactly why 14 px below missed and why "the words" is the honest instruction.

**"What it does not prove" is right on four counts and short by two** — see Minor M1.

## Critical

None.

## Important

### I1. The fix for Task 15's I3 promises a refusal three widgets do not make, and one the code deliberately declines to make

Two places, both introduced by `53d13fb`.

`README.md:95`, the Widgets table's **Text** row — a row that covers `entry`,
`password_entry`, `search_entry`, `text_view` and `editable_label`:

> — controlled: the widget is written only when the model disagrees with what it currently
> shows … (and text GTK cannot hold — invalid UTF-8, an embedded NUL — is refused rather than
> written; see Limitations).

And the new Limitations bullet:

> **A `TextView` or `EditableLabel` write that GTK cannot hold is refused, not truncated.**
> Text that is not valid UTF-8, or that carries an embedded NUL (which GTK would silently
> truncate at), is rejected *before* the write: the buffer and the library's cache of it are
> left exactly as they were…

What the code does:

- `src/widgets/w_text_view.ml:175-185` — refuses both NUL and invalid UTF-8. Correct.
- `src/widgets/w_editable_label.ml:51-59` — `unwritable` checks **NUL only**. The comment
  immediately above it (`:42-49`) is emphatic and was written on purpose:
  "{b Invalid UTF-8 is not refused here, and that is a measured difference rather than an
  oversight.} … a `GtkEditable` stores the bytes and reads them back unchanged (measured:
  `"caf\xe9 latte"` round-trips), so there is nothing to refuse … Refusing it anyway would be
  refusing a write GTK takes." `vtree/node.mli:1207` says the same in the reference doc:
  "Text that is not valid UTF-8 is {i not} refused".
- `src/widgets/w_entry.ml`, `w_search_entry.ml`, `w_password_entry.ml` — **no `unwritable`, no
  validation, no report**. `grep -n "unwritable\|NUL\|Utf8.validate"` across all three returns
  one unrelated comment line.

So the Widgets-table parenthetical is true of one of the five widgets it sits on for UTF-8 and
two of five for NUL, and the Limitations bullet is half wrong about the widget named in its own
title. Task 15's I3 existed because the Text row asserted the *opposite*; the correction landed
past the target.

Third clause in the same bullet: "the buffer and the library's cache of it are left exactly as
they were". The editable label deliberately keeps **no** text cache —
`w_editable_label.ml:66-71`: "There is no {i text} cache of the kind `w_text_view.ml` keeps, and
none is wanted."

**Failure scenario.** An application renders `Node.entry ~text` from a file or a network
payload that carries a NUL. The README says the write is refused and reported once through the
patcher's channel. What actually happens: `gtk_editable_set_text` stores the prefix silently,
`get_text` reads the truncated string back, the controlled comparison never settles, and the
entry is rewritten on **every idle frame** for the life of the widget — with nothing on stderr
at all. The developer has been told in advance that this case is handled, so the per-frame write
is the last place they look. Symmetrically, a `Node.editable_label` fed invalid UTF-8 is
*written* (measured, per the code), while the README says it is refused — a reader building a
model that normalises text ahead of the widget would build it against the wrong rule.

**Fix** (docs only, no code change wanted): scope both sentences. The text view refuses invalid
UTF-8 *and* NUL; the editable label refuses NUL only and stores invalid UTF-8 unchanged by
design, for the reason its own comment gives; the three entry widgets validate nothing. Drop
"and the library's cache of it", or attribute the cache to the text view.

### I2. The backlog still tells a maintainer to wave through the exact failure this task diagnosed

`docs/m2-backlog.md:490-493`, under `## Known-and-accepted dump quirks` — a section whose
standing instruction is *"Do not 'fix' these when an expected file surprises you"*:

> **`test/live/expected_controllers.txt` has been seen to flake under Xvfb**, with
> `focus-enter,focus-leave` arriving one frame early. Observed once, on a `ci.sh` run against a
> restored pin; it is a timing flake in the controllers focus test, not a regression — recorded
> here so a future pin bump is not blamed for it. task-14 M11.

That is the same file, the same golden, and the same `focus-enter,focus-leave` string as the
failure §4 spent the task diagnosing. Task 16 established that it is **not** a timing flake and
**not** "one frame early" — it is a neighbouring executable's window mapping stealing the input
focus on a shared display — and fixed it. The new item at `:499` says all of that, in a
different section, with no cross-reference in either direction, and this entry was left standing
with its now-known-wrong explanation and its "do not fix" framing intact.

**Failure scenario.** The serialisation is lost — someone tidies `-j 1` out of `ci.sh`, a dune
upgrade changes how `-j` interacts with the alias, a new live rule is added that maps a toplevel
in a way `-j 1` does not cover, or a developer runs the alias the way `test/live/dune` will
still let them (see I3). `expected_controllers.txt` diffs with exactly that shape. The
maintainer greps the backlog for `expected_controllers`, lands in the section headed "do not fix
these", reads "it is a timing flake … not a regression", and promotes the golden. The regression
ships and the golden now encodes it. This is precisely the "a once-in-ten failure is what gets
waved through as noise" outcome that the report's own §4 exists to prevent — and the backlog is
the artefact that would do the waving.

**Fix.** Strike the task-14 M11 entry, or rewrite it in place: "Diagnosed in M2's Task 16 — the
cause was the shared X display, not timing, and it is fixed by `-j 1`. **If you see this again
the serialisation has been lost**; see *Plumbing / hygiene*." And add the back-reference from the
Plumbing item, since the two entries are the same phenomenon seen twice.

### I3. `-j 1` is the weakest of the three available fixes, and dune's own mechanism for this was not weighed

`scripts/ci.sh:82` and `test/live/dune:16-24`.

§4 weighed two alternatives and filed both: an `xvfb-run` per rule (rejected for `xvfb-run -a`'s
own display-number race — a fair objection), and making the focus block not depend on toplevel
focus (named "the honest one" and correctly deferred). It did not consider the third, which is
dune's built-in answer to "these rules must not run at the same time":

```
(rule (alias runtest) (locks x-display) …)
```

**Verified on this toolchain**, since a review should not recommend an unchecked fix: two rules
carrying `(locks xdisp)`, each sleeping 2 s, built at `-j 8` under dune 3.22.2 with
`(lang dune 3.17)` ran strictly sequentially — 4.04 s wall, timestamps `397→399` and `399→401`.
It is available and it does what is needed.

Two concrete things it buys that `-j 1` does not:

1. **The constraint travels with the rules.** As shipped, the invariant is enforced by a flag on
   one call site in `ci.sh`. Anyone who runs the live tests any other way — `BONSAI_GTK_LIVE_TESTS=1
   xvfb-run -a dune build @test/live/runtest` without the flag, `dune test` with the variable set,
   an editor's runtest button — gets the race back, and the only thing standing between them and
   it is a comment. That is not hypothetical: it is how *I* reproduced the failure — three times in
   seven runs, in this checkout, at this commit. With `(locks)` the rules cannot overlap however they are invoked.
2. **It does not serialise everything else.** `-j 1` limits the whole dune invocation. In `ci.sh`
   that costs nothing, because `dune build @all` at line 28 has already built the executables. But
   `test/live/dune:16` now documents `-j 1` as *the* way to run the live tests, and a developer
   following that on a cold or partly-cold tree serialises the compilation and linking of eleven
   executables as well as their execution. The comment recommends the flag without noting that its
   2 s cost is measured against a warm tree.

I am not asking for the change as a condition of this task — the shipped fix works (8/8 serial
passes here against 3 failures in 7 parallel runs) and swapping the mechanism is a change with no
review round behind it, which is exactly the reasoning §4 used to defer the other two. But it
belongs in the report's "two better fixes I did not take" list, which is the artefact a future
reader will consult, and it is cheaper and safer than either of the two that are in it. Add it as
the third, with the two advantages above, and let the milestone's final review pick.

## Minor

**M1. Two entries in §5's "what this proves" are stronger than the run's evidence, and belong in
"what it does not prove".**

- *"…and that `on_focus_enter`/`on_focus_leave` track a click and a Tab."* Both entries wire
  `Attr.on_focus_leave` to `set_focus "(neither)"` and `Attr.on_focus_enter` to their own name
  (`examples/gallery.ml:775-776, 791-792`). On a Tab from the first entry to the second, leave and
  enter both fire and enter lands last, so the readout says `second entry` — which is exactly what
  it would say if `on_focus_leave` never fired at all. No screenshot in the archive shows
  `(neither)` after startup. The run proves `on_focus_enter`; it cannot see `on_focus_leave` either
  way. (`on_focus_leave` *is* covered end to end by `live_controllers.ml`, so nothing is unproven —
  only this run's contribution is overstated.)
- *"…that a `Capture`-phase `Handled_and` really consumes the key, since Escape incremented the
  counter and the entry underneath kept its text."* Escape inserts nothing into a `GtkText`
  whether it is consumed or propagated, so "the entry kept its text" is equally consistent with the
  key having reached the entry. The counter proves the key reached the capture-phase controller —
  which is the valuable half and is genuinely new — not that `GDK_EVENT_STOP` was honoured. (That
  chain is pinned by Task 5's two mutation-verified tests.) The `Propagate_and` half is different
  and *is* proven: `hello` arrived in the entry while every keystroke also moved the readout.

The same "an Escape consumed in the capture phase while the entry below kept its text" is in
`README.md`'s untested-input bullet, so the fix is two sentences in the report and one in the README.

**M2. "Covered" does two jobs in one README paragraph.** The untested-input bullet still opens
"What is **not** covered is GTK routing a real press to the controller in between", and four lines
later describes a run in which precisely that was observed and screenshotted. It resolves on "It is
a hand-run demonstration, not a test", but the opening should say "not covered *by any test*".

**M3. Report §2's file count is off by one.** `ls src/widgets/ # 37 w_*.ml + registry.ml` — there
are **36** `w_*.ml` plus `registry.ml` (37 files in the directory). The 37 registry arms are the 36
widget modules plus `| Native n -> Native_gtk.impl_of_payload n` (`src/widgets/registry.ml:41`),
which has no `w_` file. The §7 conclusion the count supports is correct; only the annotation is
wrong. Report-only.

**M4. The per-test timing floor disagrees with itself.** Report §4: "the other ten 24–563 ms
each". `docs/m2-backlog.md`: "the other ten are 88–563 ms each". Same measurement, two lower
bounds; one is wrong.

**M5. §8's reasoning about the leaked Xvfb servers is wrong, though the note is otherwise
accurate.** They do not "push `xvfb-run -a` to higher display numbers": `xvfb-run -a` starts at
`:99`, which is below `:100`–`:104`, and every run in this review took `:99`. The servers are real
and still up; the decision not to kill them is right.

**M6. A stray blank line makes one backlog list render loose.** `docs/m2-backlog.md`, between the
gallery-click-card item and the struck opam item — the only blank line between items in that
section.

**M7. `montage-entries.png` labels tiles `e1.png`/`e2.png`/`e3.png`, which are not in the
archive.** Nothing is lost — `15-after-typing.png`, `16-after-escape.png` and `18-after-tab.png`
carry the same content — but the montage names three files a reader cannot open.

## For the final (whole-branch) review

- **The click-through re-runs nowhere.** It is the milestone's only end-to-end evidence for
  `Attr.on_click` and `Attr.on_key_pressed`, and the very finding it produced — a click target
  that had silently not been one — is the kind of thing that will drift back the moment the page
  changes. The XTEST bead is now the highest-value open item on the branch by some distance, and
  the two problems the backlog says a *test* still has to solve (mapping a widget to screen
  coordinates; a settling wait that is not a `sleep`) are both tractable now that the route is
  known to work. Worth a decision at merge, not a backlog line.
- **`(locks)` versus `-j 1`** (I3) is a one-line change to eleven rules; if the final review wants
  it, that is the place.
- **The milestone's entire SDD record is untracked.** `.superpowers/` is excluded via
  `.git/info/exclude:7` — a local, uncommitted exclude — so all sixteen reports, all sixteen
  reviews, `task-16-ci-clean.log` and the 32 click-through screenshots exist only in this working
  copy. That is the established convention across M1 and M2 and is not this task's problem, but
  the merge is the moment to decide whether the evidence for a shipped milestone should survive
  the checkout.

## Verdict

**Approved with fixes.**

No Critical. I1 and I2 are prose-only and are two edits each; I3 is a recommendation the final
review can take or leave, plus one paragraph the report should carry. Nothing here needs a round
of its own and nothing blocks the merge — the gate is green, the fix it shipped is the right
diagnosis of a real defect, and I confirmed both halves of that independently: the race failed on
my first parallel run and on three of seven with the identical diff, and the shipped arrangement
passed eight times out of eight.

What this task got right is the part that is easy to fake and expensive to skip. It did not take
its own passes at face value — it found that `--force` had been reporting a flaky test green in
3 seconds a time, said so in the report, wrote it into `ci.sh`'s comment and onto the backlog, and
re-measured properly. It did not accept a once-in-ten failure as noise, and it did not accept the
first reading of that failure (the focus controller firing on its own) either. And handed a step it
was explicitly permitted to skip, it found a way to do it, and then wrote down what its way did not
reach. The two overstatements in Minor M1 are the exception rather than the pattern, and both are
in a list whose neighbouring four entries are scrupulous.

The one systemic note, and it is the same one Task 15's review ended on: the misses are in
sentences that were *carried* rather than *derived*. I1 is a Limitations bullet written from the
review's summary of the refusal rule rather than from `w_editable_label.ml`, which says in bold
that half of it does not apply; I2 is an old backlog entry that nobody re-read while writing the
new one about the same failure. Everything Task 16 measured is right. What it inherited is where
to look.

---

## Re-review — fix round 1 (`3cb9d09..f06a615`)

Scoped to the fix diff (4 files, +67/−26, docs and comments only), plus the report's rewritten
§4/§5/§8, the regenerated montage, and a re-run of the gate. Everything below was re-derived
from the code rather than read off the commit message.

**Gate.** `nix develop -c ./scripts/ci.sh` → **all green**, 56.9 s warm. `git status` is
`?? .beads/issues.jsonl` and nothing else; `git diff HEAD` empty.

### I1 — fixed, and the fix is better than the finding asked for

`README.md` now carries three rules instead of one, and each matches its widget:

- **`TextView` refuses both** — `w_text_view.ml:175-185`. ✅ The "its cached copy of the buffer
  text is left untouched along with the buffer" clause is now scoped to the one widget that
  keeps a cache, which was the third half-error in the old bullet.
- **`EditableLabel` refuses a NUL only**, and writes invalid UTF-8 on purpose — matches
  `w_editable_label.ml:42-59` clause for clause, including the `"caf\xe9 latte"` round-trip and
  the reason ("refusing it would be refusing a write GTK takes"), and matches
  `vtree/node.mli:1207`. ✅
- **`Entry`/`PasswordEntry`/`SearchEntry` validate nothing.** ✅ — and the fix does not stop at
  saying so. It states the consequence, which I checked end to end: `needs_text`
  (`w_entry.ml:33`) compares `W.Editable.get_text` against the model text; `reassert`
  (`:170-183`) computes `writes = needs_text e text` and writes whenever it is true; and all
  three widgets reach the editable through `W_entry.set_text_if_needed`
  (`w_password_entry.ml:26`). A NUL in `~text` therefore truncates on the way in, never
  compares equal on the way back, and is rewritten on **every idle frame for the life of the
  tree, silently** — exactly as the README now says. That is a claim the first version did not
  make, and it is right.

The Widgets table no longer asserts a rule on behalf of five widgets; it points at the split.
And the open question is filed where it belongs — `docs/m2-backlog.md`, last item of *Do first
in M3*, with both sides stated (the same `unwritable`/`already_refused` machinery is right
there; three more per-widget caches are a cost). Worth noting that `w_entry.ml:43-46`'s own
`capped` comment describes this identical per-frame-write pathology for `max_length` and treats
it as worth avoiding, which makes the backlog question a live one rather than a hypothetical —
the file already contains the precedent for answering it "yes".

### I2 — fixed, both directions

`docs/m2-backlog.md:498-506`: the task-14 M11 entry is struck in place, not deleted, and
rewritten with the true cause ("It was not timing and nothing arrived 'one frame early'"), the
fix, and the instruction that matters — **"If you see this diff again, the serialisation has
been lost — check `scripts/ci.sh` and how you invoked the alias before you touch the golden."**
It points at *Plumbing / hygiene*; the Plumbing item points back and says why ("which is where a
maintainer hitting the diff is most likely to land first"). Keeping it struck under the
"do not fix these" heading rather than deleting it is the right call: the next person to see
that diff will grep for the string, and what they will find now tells them the opposite of what
it used to.

### I3 — recorded as asked, correctly not taken

`scripts/ci.sh:78-87` now names all three alternatives and characterises `(locks x-display)` as
"probably the right end state", with the reason (binds the constraint to the rules rather than
to one flag on one call site) and the reason for not doing it here (eleven rules, no review
round). `docs/m2-backlog.md:523-528` carries it with the verification attributed. Deferring the
swap is consistent with how §4 deferred the other two, and I agree with it.

### Minors — all seven taken

M1 in **both** places, and the harder half was done: §5's "what this proves" list was itself
weakened ("that a *real Escape reaches* a `Capture`-phase handler at all, since its counter
moved"; "that `on_focus_enter` fires on a click and on a Tab"), not just annotated, and the two
retractions sit in "what it does not prove" with their reasons and with the pointer to what
does cover them. M2 → "What no *test* covers". M3 → 36, with the parenthetical naming `Native`
as the 37th arm. M4 → 24–563 ms in both documents, now with the two tests named
(`live_keyvals` 24, `live_events` 25), which settles which of the two numbers was wrong. M5 →
corrected, decision unchanged. M6 → blank line gone. M7 → montage regenerated; I opened it,
the content is identical and the three tiles are now labelled `15-after-typing-entries.png`,
`16-after-escape-entries.png` and `18-after-tab-entries.png`, all three of which are in the
archive.

The *"Not changed, and why"* section is accurate on all three of its entries.

### New (Minor, from this round)

**N1. The Escape overclaim survives in the third of the three places it appears.**
`docs/m2-backlog.md:404-405`, the click-through entry: "…Escape counted and **consumed with the
entry keeping its text**, and focus moving to the second entry on Tab." That is the exact
sentence Minor M1 was about, corrected in `README.md` and in the report and missed here. The
second half ("focus moving to the second entry on Tab") is accurate and should stay — it claims
only what the readout showed. The backlog is the document M3 inherits and the one a planner
reads to size the remaining input gap, so it is the place where the overstatement lasts
longest. One clause.

**N2. The pre-build command the new `test/live/dune` note recommends does not work.**
`test/live/dune:41-45`: "…`dune build @test/live` (or @all) first, then the line above." Dune
reads `@test/live` as *alias `live` in directory `test`*, not the default alias of `test/live`:

```
$ dune build @test/live
Error: Alias "live" specified on the command line is empty.
It is not defined in test or any of its descendants.
```

The parenthetical `@all` works, and so do `dune build @test/live/default` and `dune build
test/live` (both verified, rc=0). One token, in a note whose whole purpose is to hand a
developer the warm-tree recipe.

### Verdict

**Approved.**

All three Importants are closed, and I1 is closed better than it was raised: the round did not
stop at deleting the wrong sentence, it went to `w_entry.ml` and worked out what actually
happens to the three widgets nobody had documented, which is a defect the review only pointed at
sideways. I2 is closed in the way that survives — struck in place, so the grep that would have
found the wrong advice now finds the right one. I3 was recorded rather than taken, which is the
correct decision at this point in the milestone.

The two Minors above are a clause and a token. Neither blocks the merge; both are worth taking
in whatever touches these files next, and N1 belongs in the same edit as anything else the final
review does to the backlog.
