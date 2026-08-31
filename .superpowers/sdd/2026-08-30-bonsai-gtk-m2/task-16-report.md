# Task 16 report — `scripts/ci.sh` end to end, from a clean tree

Branch `m2`, from `055c70e` (Task 15) to `3cb9d09`. Three commits. The gate is green from a
pristine tree, four consecutive times, and the run flushed out one real defect in the gate
itself.

## Commits

| | |
|---|---|
| `53d13fb` | Task 15's three carried errors (I1–I3), its six Minors, and `ci.sh`'s staged-opam hole |
| `887e221` | The gallery click-through, what it proves, and the one thing it found |
| `3cb9d09` | `ci.sh`: the live tests share one X display, so they now run one at a time |

## 1. The clean-tree run

**Pre-flight.** `git status --porcelain` was empty apart from one untracked file,
`.beads/issues.jsonl` — a `bd` export, not a build artefact and not mine to commit (the brief
says no `bd`). It was moved to the scratchpad for the duration of the gate runs and put back
afterwards, so every timed run below started from a genuinely empty `git status`.

`git clean -ndx`, reviewed in full, would have removed: `.beads/{.local_version,backup/,`
`embeddeddolt/,export-state.json,issues.jsonl,last-touched}`, `.superpowers/`, `_build/`,
`_build.pkg/`, `_build.pkgtest/`, `bonsai_gtk.install`, `result`, and several hundred paths
under `_opam/.opam-switch/sources/`. **Nothing was cleaned with `git clean`.** Only the build
artefacts were removed, by hand:

```
rm -rf _build _build.pkg _build.pkgtest
rm -f  result bonsai_gtk.install
```

`.superpowers/`, `_opam/` and `.ocgtk-src/` were left alone. (`.ocgtk-src/` does not appear in
`git clean -ndx` at all — it is a nested repository, which `git clean` skips.)

**The run.** `nix develop -c ./scripts/ci.sh`, with `_build` deleted first, so this is a cold
dune build (`_build` came back at 1.2 G, `_build.pkg` 259 M, `_build.pkgtest` 215 M — no dune
shared cache is configured; `~/.cache/dune` is 36 K).

| run | tree | result | wall |
|---|---|---|---|
| 1 (17:27) | clean at `53d13fb`'s parent state + carries uncommitted | `all green` | **91 s** |
| 2 (17:36) | clean at `887e221` | **FAIL** — `expected_controllers.txt` | 63 s |
| 3 (18:02) | clean at `3cb9d09` | `all green` | **84 s** |
| 4–6 (soak) | clean at `3cb9d09` | `all green` ×3 | 81 s, 81 s, 81 s |

Run 3's log is archived at `task-16-ci-clean.log`. Its section headers and tail:

```
== nix: ocgtk pin builds and passes its tests
== format
== build
== generated opam files are committed
== pure + headless tests
== per-package builds, the way opam --with-test runs them
== live tests (xvfb)
== example smoke
all green
CI_EXIT=0
ELAPSED_SECONDS=84
```

Every step of the brief's Step 2 list came up clean on a cold tree: `nix build .#ocgtk` passed
(it builds the pin, not the checkout), no format diff, no `.opam` movement, no promoted-golden
diff outside the one this task's own message change caused, both `-p` builds green, the example
smoke green for all three examples. Only the live tests failed, once, and section 4 below is
about that.

**The `-p` builds.** The M1 fix wave's arrangement still works, unchanged: `-p bonsai_gtk
@runtest` in `_build.pkg`, then `-p bonsai_gtk @install`, `dune install --prefix $(mktemp -d)`,
then `-p bonsai_gtk_test @runtest` in `_build.pkgtest` with `OCAMLPATH` pointed at that prefix.
Both build directories were repopulated from empty in every timed run. The package line the
brief asked me to confirm holds: `test/dune` takes `core bonsai_gtk.vtree
expect_test_helpers_core` and nothing from the other package; `test/handle/dune` is the one that
takes `bonsai_gtk_test`; and `Events` — which M2's `test/test_events.ml` uses — is
`vtree/events.ml`, inside `bonsai_gtk.vtree`, with no `src/events.ml` to shadow it.

## 2. Step 3, the milestone against spec §7

```
ls src/widgets/                                  # 36 w_*.ml + registry.ml
grep -c '| [A-Z]' src/widgets/registry.ml        # 37 = those 36, plus `Native`
grep -c MISMATCH test/live/expected_events.txt   # 0
```

(Corrected in fix round 1: the directory holds 36 `w_*.ml`, and the 37th registry arm is
`| Native n -> Native_gtk.impl_of_payload n`, which has no `w_` file. The conclusion is
unchanged.) All eight M2 names have both a file and a registry arm: `w_list_box`, `w_flow_box`,
`w_notebook`, `w_text_view`, `w_drop_down`, `w_level_bar`, `w_calendar`, `w_editable_label`.
The two things that are not widgets and so are not in that count are real: all five controller
attrs are declared in `vtree/attr.mli` (`on_click:621`, `on_focus_enter:630`,
`on_focus_leave:634`, `on_key_pressed:664`, `on_key_released`), and `Expert.embed` is at
`src/bonsai_gtk.mli:124-148` with `Expert.Embedded = Embed`.

## 3. Carries taken from Task 15

All three Importants and all six Minors, plus the backlog's one-word `ci.sh` fix. Every one is
in `53d13fb`.

**I1 — three `Payload` signals claimed, six ship.** Fixed in both places, and derived rather
than copied. `src/signals.mli` and spec §6.4 now say six, name all six, and — the part the
review actually asked for — state the generalisation the number was hiding: **a signal whose
argument is a child widget** is a `Payload` because the child is gone before anything could
look for it (`row-activated`, `child-activated`, `switch-page`), and **every controller
signal** is one because a controller remembers nothing about the event it just delivered
(`pressed`, `key-pressed`, `key-released`). Both texts close with "a new signal of either shape
is a `Payload`, not a `Read_back`", which is the mistake the count was inviting. The six sites
were re-grepped, not taken from the review: `w_list_box.ml:274`, `w_flow_box.ml:252`,
`w_notebook.ml:228`, `controllers.ml:139`, `:242`, `:263`.

**I2 — `CheckButton.set_group`.** The parenthetical is gone. The bullet now says what is true:
the method is bound, GTK's grouping is a mutable pointer from one live widget to another rather
than a prop of either, `Node.check_button` therefore exposes no `~group`, and modelling the
exclusive choice in Bonsai state is the declarative answer — which was always the right advice
under a wrong reason.

**I3 — the third refusal.** A new Limitations bullet for the TextView/EditableLabel refusal of
invalid UTF-8 and embedded NULs, placed beside the two existing refusals, and saying the thing
that distinguishes it from them: no later frame makes this value valid, so the divergence is
permanent until the model offers text GTK can hold. The Widgets table's Text row, which
asserted the opposite, now points at it.

**M1** six event-value modules, not five (spec §7 and `docs/m2-backlog.md`; both already
enumerated six). **M2** the `start`-side root message now names `Expert.embed`, so §11's "each
message names the other entry point" is true of both — this is the one code change with a
golden behind it, and `test/live/expected_driver.txt:29` was promoted with it. **M3** a box
reorders in place too, so the notebook is one of two rather than the one (README's Lists row and
spec §7; the Limitations bullet about `Stack`/`Grid`/`Overlay` was already correct and was left).
**M4** the backlog's `git mv` claim replaced with what actually happened — 9 % similarity, so
`--follow` will not reach past the rename. **M5** the search-entry echo record's one exception
named where "can never" stood. **M6** the headless-validation guarantee scoped to this module,
since the underlying type is `Bonsai_test.Handle.t`.

**Backlog's `ci.sh` one-word fix.** `git diff --exit-code HEAD -- '*.opam'`, with a comment
saying what `HEAD` buys (a regenerated-and-staged `.opam` no longer reads as clean). The backlog
item is struck and marked done rather than deleted.

The review's two report-only nits ("five one-line path updates" naming six files; the 48/49
`Attr.Name.t` arithmetic) are about `task-15-report.md`, not the deliverable, and were left.

## 4. What the clean run flushed out

**Run 2 failed in `live_controllers.ml`'s focus block:**

```
-|n1 focus from presenting the window: focus-enter
-|n1 focus parked off the target: focus-leave
+|n1 focus from presenting the window: focus-enter,focus-leave
+|n1 focus parked off the target:
```

A `focus-leave` arriving *before* the `grab_focus` that is supposed to cause it. Read at face
value that is the milestone's one genuinely end-to-end input assertion — the focus controller —
firing on its own.

It is not. `scripts/ci.sh` wraps the whole dune invocation in a single `xvfb-run`, so all eleven
live executables share **one** X display, and dune runs them in parallel. Each presents a real
toplevel, and a window mapping on an X display takes the input focus off whichever window held
it; `live_controllers` sees that as a leave it did not ask for. Which neighbour happens to map
inside that block is why it is intermittent.

Measured rather than argued, because a once-in-ten failure is what gets waved through as noise:

| arrangement | result |
|---|---|
| `live_controllers.exe` alone, 15 runs | 0 failures |
| `@test/live/runtest`, parallel (as shipped), 10 runs | **1 failure** — the reviewer, on the same host under load, got 3 in 7, so treat 1-in-10 as a floor |
| `@test/live/runtest`, `-j 1`, 15 runs | 0 failures |
| `live_controllers.exe` with other toplevels mapping on the display throughout, 8 runs | **2 failures** |
| full clean `ci.sh` after the fix, 4 runs | 0 failures |

**A methodology trap found on the way, and worth more than the fix.** `dune build
@test/live/runtest --force` does **not** re-run these rules: each declares a target
(`with-stdout-to output_*.txt`), so `--force` returns in ~3 s having executed nothing. My first
attempt at measuring the flake was eight such iterations, all "PASS", all vacuous. The real
per-test cost is `live_text` 25.2 s and the other ten 24–563 ms each, summing to 27.4 s — a
3.26 s "run" should have been the tell. Delete `_build/default/test/live/output_*.txt` between
runs instead. This is written into `scripts/ci.sh`'s comment and onto the backlog.

**Fix:** `-j 1` on the live alias, in `ci.sh` and in the invocation `test/live/dune`
documents, with the measurements in the comment. It costs 2 s of 29 (28.6 s → 30.8 s), because
`live_text` dominates the section either way — **on a warm tree**, which `ci.sh` guarantees by
running `dune build @all` first and a developer following `test/live/dune` does not; fix round 1
says so in that comment.

**Three better fixes I did not take, all filed.** *(The third was added in fix round 1; the
first version of this list weighed only two, and missed the cheapest.)*

1. **`(locks x-display)` on the eleven rules** — dune's own answer to "these must not run at
   once". Two advantages over `-j 1`, both the reviewer's. The constraint travels **with the
   rules**, so the alias cannot race however it is invoked, where `-j 1` is a flag on one call
   site and a comment everywhere else — and that is not hypothetical: the reviewer reproduced the
   failure by running the alias the way `test/live/dune` still permits. And it serialises only
   the rules that need it, where `-j 1` serialises the whole invocation, including the
   compilation and linking of eleven executables on a tree that is not already warm. Verified by
   the reviewer on this toolchain (dune 3.22.2, `lang dune 3.17`): two rules carrying
   `(locks …)`, each sleeping 2 s, at `-j 8`, ran strictly sequentially in 4.04 s. This is
   probably the right end state. Not taken here because it is a change to eleven rules with no
   review round behind it — the same reasoning that defers the other two.
2. **An `xvfb-run` per rule** — eleven displays, no coupling at all, but it buys back only those
   2 s and adds `xvfb-run -a`'s own race for a free display number.
3. **Making the focus block not depend on toplevel focus** — the honest one: what it wants to
   assert is that `Widget.grab_focus` drives the controller, not that nothing else on the
   display ever takes the focus.

## 5. Step 4 — the click-through

**Deviation, stated up front.** The plan asks for a REAL-DISPLAY click-through. This machine is
a headless server: there is no display, no window manager, no compositor. The closest honest
thing is to drive the X server the live tests already run on — which is exactly the **XTEST
route** `docs/m2-backlog.md` names as "the single most valuable follow-up in the file", and
which had never been tried. It works.

**What was run.** Two passes, both under
`xvfb-run -a -s '-screen 0 1280x800x24 -nolisten tcp'` inside `nix develop`, with `xdotool` and
ImageMagick from `nix build --no-link --print-out-paths nixpkgs#{xdotool,imagemagick}` on
`PATH`. Scripts and every screenshot are archived at
`.superpowers/sdd/2026-08-30-bonsai-gtk-m2/task-16-clickthrough/`
(`clickthrough.sh`, `clickthrough2.sh`, 32 PNGs and three montages).

The shape of it: launch `_build/default/examples/gallery.exe`; poll
`xdotool search --onlyvisible --name "bonsai_gtk gallery"`; `xdotool windowfocus` (there is no
window manager, so `windowactivate` fails with "your windowmanager claims not to support
`_NET_ACTIVE_WINDOW`" and is not needed); then `mousemove X Y click N` and `key`/`type`, with
`import -window root` before and after each step and a 700×95 crop of the four readout lines for
comparison. Coordinates were read off the screenshots, which I looked at.

**What moved.** All four readouts, plus both entries. Screenshots read, not merely captured:

| step | command | readout |
|---|---|---|
| navigate | `mousemove 36 288 click 1` (sidebar row) | the stack switched to the Input page — a real click driving `Attr.on_visible_child_changed` |
| primary click | `mousemove 680 146 click 1` | `last click: button 1, press 1, at (498, 7), no modifiers` |
| secondary | `click 3`, same point | `button 3` |
| middle | `click 2`, same point | `button 2` |
| double | `click --repeat 2 --delay 60 1` | `press 2` |
| ctrl-held | `keydown ctrl; click 1; keyup ctrl` | `button 1, press 1, at (498, 7), ctrl` |
| focus | `mousemove 415 208 click 1` (first entry) | `focus: first entry` |
| typing | `type --delay 120 "hello"` | entry shows `hello`; `last key: keyval 0x6f, no modifiers` |
| Escape | `key Escape` | `escapes: 1`, `last key: Escape -- consumed here`, **and the entry still says `hello`** |
| ctrl+shift+a | `key ctrl+shift+a` | `last key: keyval 0x41, ctrl+shift` |
| Tab | `key Tab` | `focus: second entry`, `last key: keyval 0xff09`, first entry keeps `hello` |

Montages: `montage-readouts.png` (pass 1), `montage-pass2.png` (pass 2, the buttons),
`montage-entries.png` (the entry row across typing → Escape → Tab).

**What this proves.** This is the first end-to-end exercise of `Attr.on_click` and
`Attr.on_key_pressed` anywhere in the repository. The events are delivered by the X server to
GTK through the ordinary input path; nothing is synthesised inside the process. It covers, for
real: that GTK routes a button press to the `GtkGestureClick` this library attached; that
`~button:0` reports which button actually fired (1, 2 and 3 each reported as itself — a
`GtkButton` would have shown none of that); that `n_press`, the widget-local coordinates and the
modifiers all survive the trip into `Click_event.t`; that a keystroke reaches the shared
`GtkEventControllerKey`, with the right keyval and the right modifiers; that a real Escape reaches a
`Capture`-phase handler at all, since its counter moved; that `Propagate_and` really does not
consume, since `hello` reached the entry one keystroke at a time while every keystroke also
updated the readout; and that `on_focus_enter` fires on a click and on a Tab. It also re-confirms, on a real
display path, Task 13's fix for the four controlled props that used to eat typing.

**What it does not prove.** It is a hand-run demonstration, not a test: nothing re-runs it and
nothing fails if it stops working. `Attr.on_key_released` moved nothing visible because the
gallery's handler is `Ui_effect.Ignore` — the release path is still only covered headlessly.
Two things the first version of the list above claimed and should not have (reviewer's Minor M1,
accepted): it does **not** show that `Handled_and` consumed the Escape, because an Escape
inserts nothing into a `GtkText` either way, so "the entry kept its text" is equally consistent
with the key having arrived there — what moved is the counter, which proves the key reached the
capture-phase controller and no more (the `Handled`→`GDK_EVENT_STOP` chain is pinned by Task 5's
two mutation-verified tests). And it does **not** show `on_focus_leave`, because both entries
wire leave to `"(neither)"` and enter to their own name, and on a Tab enter lands last — the
readout would say `second entry` whether leave fired or not. `on_focus_leave` is covered end to
end by `live_controllers.ml`; only this run's contribution was overstated.
Propagation *between* controllers (a `Capture` parent versus a `Bubble` child) is still not
shown; the page has one key controller. And Xvfb is still X11 with no window manager and no
compositor: Wayland's `gdk_wayland` input path is untouched. The backlog's real-display item is
rewritten to be about exactly that residual rather than about the whole check.

**What it found.** Pass 1 reported *nothing* for the right click and *nothing* for the double
click, which looks precisely like the click path handling only button 1 — worth chasing, since
it would have been a genuine defect and this was the first time anything had ever pressed those
buttons. It was not a defect: both clicks missed. `Attr.on_click` sits on the `Node.label`, and
`Attr.margin 24` is space *outside* a widget's allocation, so the padding that makes the card
read as a button is not a target. Repeating both on the point the primary click had already
proved was inside gave `button 3` and `press 2` immediately, and a deliberate click 14 px lower
(`24-click-below-label.png`) moved nothing — which is the measurement, and which is why the
misses were indistinguishable from a broken handler.

The page's own instruction said "Click the card", so the page was wrong; it now says "Click the
words below", with a comment recording the measurement. Moving the gesture onto the `Node.frame`
would make the whole card live and would demonstrate "legal on any node" better than a label
does; which of the two the page should show is a choice, so it is on the backlog rather than
done here.

## 6. Backlog changes

- `ci.sh`'s `HEAD` item struck and marked done.
- Three new *Plumbing / hygiene* items: the shared-display coupling with both better fixes
  spelled out; `live_text` being 25 s of the section's 29; and the `--force` trap.
- The gallery's click-target finding.
- The **XTEST** item rewritten from "may be reachable" to the working recipe, plus the two
  things a *test* still has to solve that a by-hand run does not — mapping a widget to screen
  coordinates (a miss and a broken handler look identical), and a settling wait that is not a
  `sleep` — and the note that neither `xdotool` nor `imagemagick` is in the dev shell.
- The **real-display click-through** item rewritten: Task 16 drove all of it, every readout
  moved, and what is left is a compositor or Wayland.
- The README's untested-input limitation says what the click-through covered and that nothing
  re-runs it.

## 7. Deviations

1. **No real display; Xvfb + XTEST instead.** Headless server. Recorded above and in the README
   and backlog, with what it does and does not prove.
2. **`.beads/issues.jsonl` moved aside rather than committed or cleaned**, so the gate ran from
   an empty `git status`. Restored afterwards; it is untracked again now, exactly as found.
3. **Step 5's suggested commit message was not used verbatim.** Three commits rather than one
   "M2: clean-tree CI pass", because the carries, the click-through and the CI fix are three
   different things and the middle one has findings a squashed message would bury. Both trailers
   are on all three, with the corrected session URL.
4. **`examples/gallery.ml` was edited**, which is outside the brief's expected file list
   ("nothing, or `.opam` regeneration and formatting"). One string and a comment, to stop the
   page claiming a click target it does not have. Not pinned by any test.
5. **`test/live/dune` was edited** — a comment only, so that the invocation it documents matches
   the one `ci.sh` runs.
6. **`src/driver.ml` was edited** (Task 15's Minor M2), which is a code change in the CI-pass
   task. It is one error-message clause; the reviewer offered it as one of two options and the
   other (scoping the spec sentence) would have left the diagnostic asymmetric in the direction
   that matters — a caller with an existing GTK app is the one who needs to be told `embed`
   exists. Golden promoted, and the full gate has run over it four times.

## 8. Housekeeping note

Five idle `Xvfb` servers are running on this host (`:100`–`:104`, 640×480 — `xvfb-run`'s
default), left over from earlier `xvfb-run -a` invocations, possibly not all from this repo.
They are harmless. (Fix round 1: my claim that they push `xvfb-run -a` to higher display
numbers was wrong — `-a` starts at `:99`, below them, and every run of the reviewer's took
`:99`.) I did not kill them:
other agents are active on this machine and one of them may be inside a run.

## Status

`nix develop -c ./scripts/ci.sh` → `all green`, from a clean tree with `_build` deleted, four
times in a row, at `3cb9d09`. `git status` is clean apart from the untracked `bd` export it
started with. Nothing pushed, nothing merged, no `bd` touched.

---

# Fix round 1 (`3cb9d09..f06a615`)

Review: `task-16-review.md`, **Approved with fixes** — no Critical, nothing in the code. One
commit, `f06a615`. Gate green: `nix develop -c ./scripts/ci.sh` → `all green`, 57 s (warm
`_build`).

The reviewer independently confirmed both halves of §4 before writing anything: the race failed
on their first parallel run and on **3 of 7** with the identical diff, the shipped `-j 1`
arrangement passed **8 of 8**, and `--force` returned in 3.257 s having run nothing. They also
opened every screenshot and checksummed all 32 — `11-after-left-click.png`,
`12-after-right-click.png` and `13-after-double-click.png` are one identical file, and
`23-double-click-on-target.png` and `24-click-below-label.png` are another, which is a stronger
proof of the missed-click measurement than my prose was.

## I1 — the refusal rule promised more than three widgets deliver

The review is right and the diagnosis stings, because it is the same failure mode Task 15's
review named: I wrote the new Limitations bullet from that review's *summary* of the refusal
rule rather than from the widgets, and `w_editable_label.ml:42-49` says in bold that half of it
does not apply. Verified against the code before rewriting, not against the review:

| widget | NUL | invalid UTF-8 |
|---|---|---|
| `text_view` (`w_text_view.ml:174-186`) | refused | refused (a `GtkTextBuffer` empties itself and *then* declines the insert) |
| `editable_label` (`w_editable_label.ml:50-59`) | refused | **written, deliberately** — a `GtkEditable` stores the bytes and reads them back unchanged (measured: `"caf\xe9 latte"` round-trips), so there is nothing to refuse |
| `entry`, `search_entry`, `password_entry` | **nothing** | **nothing** — `grep -n 'unwritable\|NUL\|Utf8.validate'` across all three returns one unrelated comment |

Both places now state exactly that. The Limitations bullet is one line per widget under a
shared opener (what "refused" means where it happens); the Widgets table's parenthetical no
longer asserts a rule on behalf of five widgets and points at Limitations instead; and "the
library's cache of it" is scoped to the text view, which is the only one that keeps a text
cache — `w_editable_label.ml:66-71` says why it deliberately does not.

The entry row is the one worth reading twice, and the review's failure scenario is the reason:
a NUL in `Node.entry ~text` truncates silently in `gtk_editable_set_text`, the read-back never
equals the model, and the widget is rewritten on **every idle frame** for the life of the tree
with nothing on stderr — and until this round the README told the reader that case was handled.
Per the ruling, no widget code changed; the question is filed under *Do first in M3* ("should
`entry`/`search_entry`/`password_entry` refuse a NUL the way `text_view` does?") with the
counter-argument, for the final review to weigh.

## I2 — the backlog entry that would have undone §4

`docs/m2-backlog.md` carried task-14 M11 under *Known-and-accepted dump quirks*, a section
whose standing instruction is "do not 'fix' these when an expected file surprises you": the
same file, the same golden, the same `focus-enter,focus-leave` string, explained as "a timing
flake in the controllers focus test, not a regression". I wrote the new Plumbing item about the
same failure without re-reading it. Left standing, it is a signed instruction to promote the
golden the first time the serialisation is lost.

Struck and rewritten in place per the ruling: not timing, nothing "one frame early", the shared
X display; fixed by `-j 1`; **and if the diff comes back, the serialisation has been lost —
check `scripts/ci.sh` and how you invoked the alias before touching the golden**. Cross-referenced
in both directions, since the Plumbing section is not where a maintainer greping
`expected_controllers` lands first.

## I3 — `(locks)`, the fix I did not weigh

Taken as a recommendation, not a change, per the ruling. §4's alternatives list is now three,
with `(locks x-display)` first, both of the reviewer's advantages, and their measurement (two
2 s rules at `-j 8` under dune 3.22.2 / `lang dune 3.17`: strictly sequential, 4.04 s). The
first advantage is the one that decides it — the constraint travels with the rules, so the
alias cannot race however it is invoked, and the reviewer demonstrated that by reproducing the
failure through exactly the invocation `test/live/dune` still permits.

`scripts/ci.sh` and the backlog now name all three fixes. `test/live/dune`'s comment gained the
warm-tree caveat the ruling asked for: `-j 1` limits the whole invocation, so its 2 s cost is
measured against a tree whose executables are already built — true inside `ci.sh`, which runs
`dune build @all` first, and not true for a developer following that comment on a cold tree.

## Minors

All seven taken; none needed arguing.

- **M1** — two entries in §5's "what this proves" were stronger than the evidence, and both are
  now in "what it does not prove" with the reason. The Escape did not show `Handled_and`
  consuming the key (an Escape inserts nothing into a `GtkText` either way; what moved is the
  counter, which shows the key reached the capture-phase controller). The Tab did not show
  `on_focus_leave` (both entries wire leave to `"(neither)"` and enter to their own name, and
  enter lands last). The same sentence in the README's untested-input bullet is corrected.
  The reviewer is right that this is where the list's honesty slipped; the neighbouring four
  entries were checked against the screenshots and stand.
- **M2** — the README's untested-input bullet opened "What is **not** covered is GTK routing a
  real press…" four lines before describing a run that observed exactly that. Now "What no
  *test* covers".
- **M3** — §2's annotation said "37 `w_*.ml`"; there are **36**, and the 37th registry arm is
  `| Native n -> Native_gtk.impl_of_payload n`, which has no `w_` file. Corrected in place, with
  a note. The §7 conclusion the count supports is unaffected.
- **M4** — the backlog said the other ten live tests are "88–563 ms"; the measurement is
  **24–563 ms** (`live_keyvals` 24, `live_events` 25). The backlog now matches the report.
- **M5** — §8's reasoning about the leaked `Xvfb` servers was wrong: `xvfb-run -a` starts at
  `:99`, below `:100`–`:104`, so they push nothing. Corrected; the decision not to kill them
  stands and the reviewer confirmed they are still up.
- **M6** — the one loose blank line in the *Plumbing / hygiene* list, removed.
- **M7** — `montage-entries.png` labelled its tiles `e1.png`/`e2.png`/`e3.png`, which only ever
  existed in the scratchpad. Regenerated from `15-after-typing.png`, `16-after-escape.png` and
  `18-after-tab.png`, cropped into the archive under those names, so every label in the montage
  now names a file a reader can open.

Also folded in, though not asked for: the reviewer's **3-in-7** failure rate is recorded beside
my 1-in-10 in both the report and the backlog, because theirs was measured on the same host
under a heavier load and mine on an idle one — one-in-ten is a floor, not a typical value.

## Not changed, and why

- **No widget code.** I1's ruling says docs only, and it is right: making three entry widgets
  refuse a NUL is a behaviour change with no review round behind it, in the task whose job is to
  be a gate.
- **`(locks)` not swapped in.** Eleven rules, same reasoning.
- The review's three notes *For the final (whole-branch) review* — the XTEST bead's promotion,
  `(locks)` versus `-j 1`, and whether `.superpowers/` should survive the checkout (it is
  excluded via `.git/info/exclude:7`, a local uncommitted exclude, so all sixteen reports and
  reviews and the 32 screenshots exist only in this working copy) — are left for the merge,
  which is where the review put them.

## Status after fix round 1

`m2` at `f06a615`. `nix develop -c ./scripts/ci.sh` → `all green` (57 s, warm). `git status`
clean apart from the untracked `bd` export it started with. Nothing pushed, nothing merged, no
`bd`.
