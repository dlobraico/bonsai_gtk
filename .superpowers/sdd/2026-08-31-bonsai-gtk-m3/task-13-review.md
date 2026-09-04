# Task 13 review — README, spec M3 amendments, `docs/m3-backlog.md`

**Verdict: one small fix round, then approve.** Two Importants: one missing backlog
citation the record explicitly assigned (the `bonsai_gtk-vdy` embed-autofocus gap), and
one report-accuracy problem (the report's final commit hash names a red pre-amend orphan;
the branch itself is green). Everything else the record assigned is present and accurate:
every count checked against the code at head is right, the spec amendments contradict no
mli, the m2-backlog strikes all name the correct closing task, and ci.sh is exit 0
"all green" at the true head by my own run.

## The range actually reviewed

The assignment said `dd891e7..8132f44`; **`8132f44` is not on the branch**. The reflog
shows it was amended 33 seconds after creation into `db26888`, the branch head — the
amend is the confessed ocamlformat fix (a line rewrap in `vtree/attr.mli`, the only
difference between the two). I reviewed `dd891e7..db26888` (4 commits: `a35ebec`,
`6e5c8aa`, `670a438`, `db26888`).

## Builds (my runs, one at a time, tree restored after)

- **fmt gate at each of the four on-branch commits** (`dune build @vtree/fmt @src/fmt
  @test/fmt @test_lib/fmt @test/live/fmt @examples/fmt`, detached-HEAD walk): exit 0 at
  `a35ebec`, `6e5c8aa`, `670a438`, `db26888` — **no red-format commit is
  bisect-reachable**.
- **fmt gate at the orphan `8132f44`: exit 1** — confirming the confession's mechanics:
  the pre-amend commit really is red, and the amend really is what fixed it.
- **`nix develop -c ./scripts/ci.sh` at `db26888`: exit 0**, checked by real exit code
  (un-piped, output captured to a log); tail is `all green`; zero `TIMED OUT` lines.
- Tree left as found: only the pre-existing `.beads/issues.jsonl` drift and the untracked
  SDD files. No commits, no pushes, no bd.

## Findings

### Important

**I1 — the `bonsai_gtk-vdy` embed-autofocus gap is missing from `docs/m3-backlog.md`.**
The ledger's Task 2 entry rules the mount-frame autofocus grab a rootless silent no-op
under `Expert.embed`, "doc-only for M3, real fix filed as bead `bonsai_gtk-vdy`
(map/notify::root retry candidate)". The in-tree doc half exists and is good
(`vtree/attr.mli:282-287` names the mechanism and the bead), but the backlog — the file
whose header promises "whatever M2 left open that M3 did not close" — never mentions the
gap or the bead: `grep vdy` over the whole diff and all of docs/ returns nothing. The
"Do first in M4" focus-model bullet (`docs/m3-backlog.md:97-102`) presents
`Attr.autofocus` as the interim floor without its one known hole. Fix: one sentence in
that bullet naming the embed no-op and bead `bonsai_gtk-vdy`.

**I2 — the report's commit hashes are stale and name a red commit as the final one.**
`task-13-report.md` cites the range as `a35ebec..8132f44` and says the fmt fix was
"amended into `8132f44`". The amend *produced* `db26888`; `8132f44` is the pre-amend
orphan and **fails the fmt gate** (verified, exit 1). The branch is fine — this is a
record problem, not a tree problem — but the report is what the controller and the final
lenses read, and as written it points them at a commit that is both off-branch and red
(this review's own assigned range inherited the error). Fix: correct the two hash
references in the report to `db26888`. While in there: "eight closed with task cites"
precedes a parenthetical listing nine items — make the count match.

### Minor

**M1 — the menubar has no backlog home, and its recorded disposal is factually wrong.**
README Limitations says "No menubar (`Application.set_menubar` / `PopoverMenuBar`)"
(`README.md:587`), but `docs/m3-backlog.md` contains no menubar entry anywhere. The
task-6 review's out-of-scope list disposed of it with "already on the fork-round-3 list"
— it is not: neither the plan's candidate list nor the backlog's copy has a menubar
item (the plan's survey line hedges "all in 'Fork round 3 candidates' *or out of
scope'"). As it stands the only record of the gap is a README limitation with nothing
behind it. One line — fork list or "Do first in M4" — closes it.

**M2 — line-numbered m2-backlog citations in code drifted under the strikes.** The
strike insertions shift `docs/m2-backlog.md` by up to +3 lines mid-file, so
`src/patcher.ml:492` ("175-182"), `src/child_keys.mli:72` ("158-166") and
`w_list_box.ml:225` / `w_flow_box.ml:198` ("150-158") now land 0–3 lines shy of their
entries. Every cited entry is still resident (nothing dangles) and the ranges still
overlap their targets, so this is cosmetic; fix opportunistically or not at all.

**M3 — one "Do first in M3" bullet is neither struck nor named.** "No live test
delivers a synthetic click or key press" (base `docs/m2-backlog.md:116-119`) was closed
at M2's own close-out (the `xtest-input` branch; its "Tests worth adding" twin *is*
struck at base 481-489), but the Do-first bullet was left unstruck then and the Task 13
sweep — whose plan text says every 95-191 bullet accounted "by name" — carried the
inconsistency forward: unstruck in m2-backlog, unnamed in m3-backlog's Closed list
(only implied by the click-claim bullet's "proven with real XTEST input"). A strike
citing the M2 close-out tidies it.

### Nits (no action required)

- The strike idiom (`~~**heading**~~ — **closed…**` with the original body kept) leaves
  grammatical fragments (".**, while `on_click`…"); consistent and legible, noted as a
  choice of record.
- README migration note's "the X button (and Alt+F4, and `Window.close`)" — `Window.close`
  here is GTK's `gtk_window_close`, mirroring `attr.mli`'s wording, but four sections
  later the Effects section says `Window.close` does not ship; a reader can trip on the
  collision. The mli has the same wording, so leaving it is defensible.

## Sweep completeness — my own checklist against the diff

Built independently from the ledger, all twelve reviews' out-of-scope sections, the plan,
and the base m2-backlog. Everything below verified present:

- **Task 1**: header translation table (`m3-backlog.md:12-16`) and the five
  `live_controllers.ml` references read-against-split-files note (`:84-87`). Present.
- **Task 3**: functorise **promoted, not struck** — status note in m2-backlog (not a
  strikethrough), "scheduled early-M4 motion-only" in both Closed and Do-first-in-M4;
  the third-copy-not-second correction of record carried; the stack/notebook
  not-a-fourth-instance caveat carried. Present.
- **Task 5**: `notify::visible` popover-open reporting in Do-first-in-M4; `on_closed`
  direct-effect signature and handlerless-dismissal latency both under "Carried out of
  M3's task reviews". Present.
- **Task 6**: Down+Return residual beside the M2 input residual, stated as one family
  with the measurement. Present. (Its menubar sibling is M1 above.)
- **Task 7**: targeted shortcuts (feasible, deliberately unshipped, shipping's exact
  removals) with the enabled-state conditional-chord story placed beside it as that
  review instructed. Present.
- **Task 8**: README migration note leads Limitations, one-attr fix shown
  (`Attr.on_close_request Effect.quit` — matches the real signature,
  `vtree/attr.mli:786`, and `examples/counter.ml:12` now carries it); the close ruling
  as §6.5's controlled-prop story; out-of-scope 7 (twin-string split) and 8
  (present-before-transient) both carried. Present.
- **Task 9**: §8 accounting matches `gtk_effect.mli` exactly (get_text omission with
  why, close/set_title with the Paned lesson, `?cancel`/DELETE_EVENT −4, respond_to
  mechanics, keep-alive tables); the multi-driver hook slot in Do-first-in-M4 citing
  Minor 1 + out-of-scope 5. Present.
- **Task 10**: chooser-ACCEPT residual in Input residuals; both dialog contingencies
  quotable in §7/§8 and quoted faithfully from the mlis. Present.
- **Task 11**: equal-priority precedence, prefers-contrast, permanent settings
  connections — all three carried with citations. Present.
- **Task 12**: nothing-sweeps-the-example in Do-first-in-M4 with the stale 36/38
  re-recorded against the 42-kind catalogue and the derived-count caveat; the
  chrome-smoke-coverage precision note carried. Present.
- **Fork round 3**: all eight plan candidates copied in substance-faithfully, the four
  round-2 carries appended, the read-the-stub rule restated, m2-backlog kept
  authoritative for the round-2 ledger. Present.
- **`a35ebec` (Task-12 minors)**: exactly the review's three — autofocus reasoning into
  the gallery comment (both halves now in-tree), `~label:""` dropped in both examples
  with the separator-idiom comment, `examples/dune` counts three. Nothing beyond the
  three findings. Clean.

## Accuracy — every stated count checked against the code at `db26888`

- **42 `Node.*` constructors / 42 kinds**: `Kind.t` hand-counted at 42 variants
  (`vtree/kind.ml:492`); `node.mli` has 43 `val`s, one of which (`find_by_test_id`) is
  not a constructor. Right.
- **21 signal attrs**: enumerated in `vtree/events.ml:159-179` — 10 M1 + 8 M2 + 3 M3,
  matching the README's roll call name for name. Right.
- **7 controller attrs over 4 families**: `On_click`, `On_key_pressed`, `On_key_released`,
  `On_focus_enter`, `On_focus_leave`, `On_contains_focus_changed`, `Shortcut` over
  Click/Key/Focus/Shortcut (`events.ml:131-134`). Right.
- **29 `Bonsai_gtk_test.Action.t` constructors** (from nineteen): counted 29 in
  `test_lib/bonsai_gtk_test.mli`; the README table's rows sum 5+12+5+7=29, and the M2
  row's recovered omissions (`Set_revealed`/`Set_position`/`Set_visible_child`) are real
  constructors. Right.
- **"Seventeen of twenty-one rules carry `(locks x-display)`"**: 21 `(rule` stanzas, 17
  literal lock fields (the two other grep hits are the header census itself), census
  sentence at `test/live/dune:43`. Right.
- **Spec vs mli**: §6.5's close ruling and `attr.mli:771-786` tell the same story in the
  same terms (always-veto, swallow-and-report-once, headless loud-fail divergence);
  §8's five accounting bullets are each verifiable against `gtk_effect.mli` (lines
  37-113) and the two under-specified mechanics match the Task 9/10 review records. No
  contradiction found.
- **m2-backlog strikes sampled (all, not five)**: click→T2, contains_focus→T2,
  ?phase→T2, cursor→T3, Child_keys→T3, current_page→T3, ~selected dedup→T3,
  require_slots→T2, close-request→T8, root_widget→T8, Update arm→T8,
  on_window_created→T8, file splits→T1 — every one matches the ledger's closing task.
  The "Recorded during M3" section's four items are all genuinely re-homed in
  m3-backlog, and its "Swept" marker is accurate.
- **Retargeted pointers**: the four moved-content sites all now cite m3-backlog with the
  right section (`test/test_menu.ml:197`, `vtree/action_resolution.ml:107`,
  `vtree/attr.ml:617` + `attr.mli:917`, `src/gtk_effect.mli:143`); the ~30 remaining
  m2-backlog citations all point at still-resident content (spot-checked the
  load-bearing ones; `gtk_effect.mli:134`'s leak-shape cite is the unstruck
  Driver-never-reclaimed entry). No dangling reference. (Line-number drift is M2.)

## Judgment calls the task asked for

- **The digest deviation is right.** "Carried forward from M2" digests ~60 minors with
  citations instead of copying ~300 lines; the authoritative-marking the deviation
  depends on is actually present in all three places (the m3-backlog section preamble,
  the README's closing paragraph, the fork section). The digest itself is faithful — I
  checked its highlight clusters against the base file's sections and found no
  still-open M2 item silently dropped, and two entries usefully updated in passing
  (family_attrs now "seven names, four families"; all_kinds "both grew `Windows` by
  hand").
- **README readability**: Limitations now reads as one coherent section — migration note
  first (the one action an M2 reader must take), then the input residual as a single
  family with the two unreachable-even-on-Xvfb inputs, then the focus gap leading Input,
  then per-area entries, with Effects/CSS promoted to their own top-level sections. The
  Status paragraph, tables and section cross-references are consistent with each other
  and with the code. The old M2 text has no orphaned remnants (`grep -n "M2"` hits are
  all deliberate history).

## Process

Reviewed on the implementer's checkout, one build at a time. Read in full: the plan's
Task 13 + fork list, the entire ledger, all twelve reviews' out-of-scope sections, the
base `docs/m2-backlog.md`'s swept regions, the complete diff, `task-13-report.md`, and
the mlis the spec quotes. Tree left as found; this file is the review's one addition.

# Re-review (fix round 1) + Task 14 verification

## Fix round 1 — `db26888..9ee1fd6`: APPROVED

One commit, checked against my five findings only; every hunk traces to a finding.

- **I1 closed.** The M4 focus-model bullet now names the embed no-op with the mechanism
  (tree parented after the frame), the doc-only ruling, and bead `bonsai_gtk-vdy` with
  the retry candidate — matching the ledger's Task 2 entry and `attr.mli:282-287`.
- **I2 closed.** The report's range is `a35ebec..db26888`, `8132f44` is named the
  pre-amend off-branch orphan at the top and in the verification section, the amend
  attribution reads "producing `db26888`", and the count is now "nine closed". One
  leftover nit, not blocking: the step-2 section heading (report line 103) still reads
  "The README (`8132f44`, step 2)".
- **M1 closed.** Menubar is fork-round-3 item 9, with the task-6 disposal's error
  stated in place ("this line is what makes that disposal true") — the honest shape.
- **M2 closed, properly.** All four citations recomputed against the file's *final*
  layout (I verified each lands exactly: Child_keys at 123-130, dedup at 153-161,
  require_slots at 181-186), including the +3 shift this fix's own strike added, and
  `child_keys.mli`'s citation retargeted to the entry its sentence actually describes —
  the old `158-166` had never pointed at the Child_keys entry, which my M2 (calling the
  drift "0-3 lines") understated.
- **M3 closed.** The synthetic-click bullet struck with the M2-close-out attribution
  (`xtest-input`, live_input.ml) and the tidied-at-Task-13 note.

**Builds, my runs at `9ee1fd6`**: fmt gate (all six dir aliases) exit 0; headless suite
(`dune build @test/runtest`) exit 0.

**One NEW Minor, found during Task 14 verification and equally my first-pass miss**:
`docs/m3-backlog.md:348` says "The pin is unchanged from M2's close: `649498b4`, the
fork's `m2-bindings` head (`ocgtk-pin.json`)" — but `ocgtk-pin.json` has carried
`72cc75f2` since M2's own fork round 2 (`6a00f3e`, 2026-08-31, in the M2 base), which
is the hash the M3 ledger header and the task-14 report both carry. "Unchanged from
M2's close" is true; the hash named is the *pre*-round-2 one, copied forward from
m2-backlog's fork section (itself written before the round-2 bump landed). One-hash
fix for the final fix wave; not worth a round of its own.

## Task 14 verification — the report against the recovered logs

The cold tree is deleted; `ci-run1.log`, `ci-run2.log` (96 lines each) and
`setup-switch.log` (854 lines) are the surviving evidence. Verdict in
`task-14-review.md`; findings summarised there.
