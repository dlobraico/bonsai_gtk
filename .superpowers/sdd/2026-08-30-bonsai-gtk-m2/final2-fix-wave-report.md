# M2 final fix wave — report

Branch `m2`, from `f06a615` to `36aa26c`. Seven commits, one per group of the brief plus a
seventh for the Minors and the backlog (deviation recorded below). The gate
(`nix develop -c ./scripts/ci.sh`) was run after every group and twice at the end; both
final runs are `all green`, and both printed all ten bench lines, which is group 6's own I1
fix proving itself.

Every finding in the five reports appears in the disposition tables below as **fixed**,
**backlogged** with its reasoning, or **argued**.

## The commits

| | commit | what |
|---|---|---|
| 1 | `8bd5df9` | Exception safety both directions (core I1, I2, M3) |
| 2 | `f16d034` | Containers: the selection anchor, the "Page N" tab, the stack's hidden page (containers I1–I3, N1–N3) |
| 3 | `2d72884` | Every `GtkEditable` refuses a NUL; the four refusal mechanisms become one (controls I2 + the entry-NUL ruling, core M6, controls M4) |
| 4 | `488c8a3` | Three more handle checks, three more actions, the coverage sweep, the two declined tests (headless C1 code half, I1, I2) |
| 5 | `7504f8e` | Docs coherence: derive-don't-list, the widget_name reason, the gap table, the superlatives (core I3, I4, M1, M2, M7; headless C1 prose, I3, I4, I5, M1, M2; controls I1, M1, M2, M3, M5) |
| 6 | `ad21cc3` | The gate: the env leak, the flaky bound, the cached live step, the bench twin, the locks (live C1, C2, I1, I2, I3, M1, M4, M5 + the locks ruling) |
| 7 | `36aa26c` | The leftovers: headless M4, M6, M8 taken; everything else backlogged with reasons |

**Deviation from the brief.** The brief asked for six commits. The seventh exists because
the Minors of four lenses were not in any group's scope and folding them into group 5 would
have made a 13-file docs commit into a 15-file one with a different subject; keeping the
disposition of the Minors reviewable on its own seemed worth one more commit. Nothing else
in the brief's grouping changed.

---

## Core lens (`final2-core-report.md`)

| # | finding | disposition |
|---|---|---|
| I1 | `apply_stack_claims` raises outside `mount`'s exception-safe region | **fixed** (1). The report's three-line shape, inside the guarantee: the completed tree is destroyed before the exception goes up, which for a window root is what takes it back off screen. `patcher.mli`'s Raises list and its exception-safety paragraph now cover it. |
| I2 | `Patcher.destroy` is not exception-safe | **fixed** (1). Collect-and-reraise per the report's sketch; `Driver.stop` and `Embed.stop` reach their trailing steps through `Exn.protect`; `native_gtk.mli` says what a raising `destroy` costs and `driver.mli`/`embed.mli` say what `stop` raises. |
| I3 | `events.mli` names 3 of 5 controller attrs; `patcher.mli` the same | **fixed** (5). Both derive rather than list, and say why the list went stale. |
| I4 | `Attr.widget_name`'s reason was removed by this branch's pin bump | **fixed** (5). `attr.mli`, `attr_apply.ml` and the backlog's conditional framing. |
| M1 | `patcher.mli`'s `report` says one caller; four ship | **fixed** (5). Stated as the rule (every widget that refuses) rather than a count. |
| M2 | `run_fixups`/`mount` Raises lists incomplete | **fixed** (1 and 5). `mount` gained the duplicate-stack-name rejection, `run_fixups` the notebook's. |
| M3 | `driver.mli` says the backstop is on the root widget | **fixed** (1). It is on the wrapper, and the doc now says why. |
| M4 | `family_attrs` rebuilds a 48-element filter per call | **backlogged**. Unmeasured, and the fix has two shapes worth choosing between with a number in hand. |
| M5 | the placement seam has no drift check | **backlogged**. Wants the treatment `live_events.ml` gives the events table — a test to write. |
| M6 | all four `take_report`s mint an ephemeron entry | **fixed** (3). One lookup, `find_opt`, in the shared module; the text view's minted `{ stale = true }` record is gone with it. |
| M7 | malformed odoc reference in `patcher.mli` | **fixed** (5), with the sentence around it. |
| M8 | `Signals.spec`'s two arms differ in connection arity | **backlogged**, beside the API-shape list where the report puts it. |
| M9 | `Controllers.update`'s `configure` raising leaves two different states | **backlogged** with the report's reasoning. |
| M10 | `W_editable_label` absent from `Private` | **backlogged**, and the reason changed under it: the label's refusal now lives in `W_entry`, which is not exported either, and no test needs either. Export whichever a test first wants. |

Out-of-scope observations: the `(locks)` recommendation was taken (group 6); the entry-NUL
recommendation was taken (group 3); the XTEST bead stays a merge decision, with its estimate
corrected in the backlog (group 7).

## Containers lens (`final2-containers-report.md`)

| # | finding | disposition |
|---|---|---|
| I1 | a reorder of a selected child NULLs GTK's own selection anchor | **fixed** (2), in both containers, with the unselect/select pair (a plain re-select early-outs, as the report says). Two live assertions, both mutation-verified — see the evidence section. |
| I2 | "unnamed tab" is really a positional `"Page N"` | **fixed** (2), doc-only per the ruling, at all five sites, and re-measured with `show_tabs` on: `Page 2`. `test_widgets.ml`'s "measured" claim now says what was actually measured and why it could not have seen otherwise. |
| I3 | `Node.stack ~visible_child` has the notebook's hidden-page divergence | **fixed** (2) as documentation, on the constructor and in `W_stack.select`, and **backlogged** for the report-once half beside the notebook's, since it is one memo serving both. |
| N1 | the "deliberately not narrowed" write argument is vacuous | **fixed** (2). Both files now say the two spellings are the same program, and where they part (a duplicate key). |
| N2 | "the one real reorder in the library" contradicts `w_box.ml` | **fixed** (2): among the keyed containers. |
| N3 | two comments say a handler runs mid-patch; under `Driver` it does not | **fixed** (2), on the notebook's own wording. |
| N4 | a duplicate key in `~selected` writes every frame | **backlogged** with reasoning: a behaviour change on the selection path that the rulings did not cover, and it wants deciding with I3's report-once question (dedupe silently, or report once like everything else that cannot be held). |

## Controls lens (`final2-controls-report.md`)

| # | finding | disposition |
|---|---|---|
| I1 | `editable_label`'s `~editing` lacks the "pair it with the attr" sentence | **fixed** (5), in `node.mli` and `attr.mli`, in the calendar's words. |
| I2 | refuse-record-report is one rule and four hand-copied implementations | **fixed** (3). `src/widgets/refusal.ml{,i}`: one functor over the value type, carrying the per-widget extra state (the text view's cache, the calendar's last-fired memo) in the same ephemeron entry so a frame is still one lookup. |
| — | the entry-NUL recommendation | **taken** (3), in `W_entry.set_text_if_needed`, so all four `GtkEditable` widgets get it from one place. Four caches stayed four rather than becoming seven. |
| M1 | `node.ml` says GTK clamps a level bar's `~value` | **fixed** (5). It does not; only the bound setters clamp, which the mli and the impl both had right. |
| M2 | `capped` does not know GTK's 65536 clamp; `Node.entry` validates nothing | **fixed** (5). `capped` clamps against GTK's ceiling (so a `~max_length` above it no longer causes the per-frame rewrite `capped` exists to prevent), the constructor rejects a negative one, and `node.mli` documents both. A `~max_length` *above* 65536 is deliberately not rejected: it is a reasonable way to spell "effectively no limit" and GTK's own answer is to clamp. |
| M3 | "while a refusal is parked the prop is not enforced" is documented for the drop-down only | **fixed** (5), on the text view, the entries, the editable label and the calendar, plus one statement in the README's refusal section — including the editable label's deliberate half-enforcement. |
| M4 | `node.mli` says nothing about a NUL in an entry's `~text` | **fixed** (3), on all three entry constructors, with the search entry's own consequence named. |
| M5 | the idle-frame cost note understates what the `GtkEditable` cast costs | **fixed** (7), in the backlog entry — the comment site itself went away with the editable label's private cache, and the backlog is where the claim is load-bearing. |

## Headless lens (`final2-tests-headless-report.md`)

| # | finding | disposition |
|---|---|---|
| C1(a) | the stated reason ("needs the widget implementations or the live tree") is false for every item | **fixed** (4 and 5). Three of them are now checked; the rest are listed in the gap table with the honest reason. |
| C1(b) | one listed item is already checked by the constructor | **fixed** (5). Row 7 of the table says so; the README's Limitations bullet no longer lists it as a gap. |
| C1(c) | the root-kind rule is absent from the mli | **fixed** (4). `create ?root_kind`, defaulting to `` `Window ``. |
| I1 | three event attrs have no `Action` | **fixed** (4): `Set_revealed`, `Set_position`, `Set_visible_child`, plus a fourth sweep mapping every `is_event` name to the action that fires it, exhaustively over `Attr.Name.t`. |
| I2 | two "declined" tests accept the output their action never running would produce | **fixed** (4), on the pattern their neighbours in the same file already use. |
| I3 | `Set_text` delivers text the runtime refuses | **fixed** (5) as documentation: rows 14–15 of the gap table and a paragraph on `Set_text`. |
| I4 | two mutually exclusive "the one place" superlatives | **fixed** (5). Both replaced by pointers to the one list, which has six entries, four of them deliberate. |
| I5 | neither per-package `@runtest` runs both directories | **fixed** (5) as a README paragraph. The optional half — moving the vtree-only sweeps into `test/` — is **argued**: they read `gallery_tree`, which the handle-based lifecycle sweep in the same file also reads, so it is a rewrite rather than a file move. Recorded in the README where the fact is. |
| M1 | `Set_selection` ignores `selection_mode` | **fixed** (5), as a sentence, on the `Click_at`/`~button` precedent. |
| M2 | `Set_value` ignores `~digits`; `Set_text` ignores `~max_length` | **fixed** (5), two sentences. |
| M3 | `paned_props.position` is erased from every golden | **half fixed** (4: there is a `Set_position` action now, so the handler is reachable), **half backlogged**: removing the `sexp_drop_if` moves every paned golden in the repository for a gain the action largely delivers. |
| M4 | `with_check` renders the whole tree's sexp and throws it away | **fixed** (7). `Result_spec.check` is the checks; `view` is `check` plus the rendering. |
| M5 | "props take part in `equal_props`" varies one field | **backlogged**, with the report's note that it is also what all four sweeps miss together. |
| M6 | the *package* is not ocgtk-free though the library is | **fixed** (7), one clause. |
| M7 | `bonsai_gtk_test.opam` over-declares `ppx_expect` | **backlogged**: a `dune-project` change, defensible as it stands. |
| M8 | `do_actions` reads a tree that may never have been checked | **fixed** (7), a clause where the guarantee is stated. |
| M9 | the six-entry-point test exercises one of the three checks | **backlogged** with the report's suggested shape. |

**One design note the report did not anticipate.** The root-kind check was first written as a
wrapper around the computation, which is where it belongs on paper (it reaches every entry
point, present and future). That is wrong in practice: raising from inside a `Bonsai.map`
poisons Incremental for the rest of the process — "cannot stabilize — stabilize previously
raised" — so a single root-kind failure broke every later test in the same executable. It
now lives in `Result_spec.view` beside the other three checks, with the root kind remembered
from the most recent `create`, because `Handle.t` *is* `Bonsai_test.Handle.t` (deliberately)
and has nowhere to carry it. The limit and its failure mode — always a loud rejection of a
legal tree, never a silent acceptance of an illegal one, since the two rules are opposites —
are stated in the mli.

## Live lens (`final2-tests-live-report.md`)

| # | finding | disposition |
|---|---|---|
| C1 | `ci.sh` leaks `BONSAI_GTK_LIVE_TESTS` | **fixed** (6): exported `0` for the script and pinned again on each step that must not have it, `1` only on the live step. Verified end to end (evidence below). |
| C2 | `live_embed`'s `bound_ratio = 1.2` flakes at 2x oversubscription | **fixed** (6) by the report's option (2), *and* by raising the window: the phases are interleaved in one loop with two accumulators, and `frames` went 2 000 → 20 000. **Recorded choice**: interleaving alone still gave a worst case of 1.18 against the bound of 1.2 in five loaded runs; with both, five loaded runs gave 0.97–1.02. The bound stays 1.2 and the concurrency sentence is now in the comment that needed it. |
| I1 | a second `ci.sh` in the same tree does not run the live suite | **fixed** (6). **Recorded choice**: `rm -f _build/default/test/live/output_*.txt` before the step, rather than a scoped `dune clean` — the outputs are exactly the state that makes the rules stale, and the same line is what the backlog already tells a human to do. |
| I2 | the selection bench guards the flow box only | **fixed** (6): parameterised over the container, run for both. Mutation-verified. |
| I3 | `eval "$(opam env …)"` cannot fail the script | **fixed** (6), two lines. |
| M1 | `-j 1` serialises two rules that need no display | **fixed** (6): `live_events` and `live_keyvals` carry no lock, and `test/live/dune` says why. |
| M2 | `examples/gallery.ml` is an unswept twin | **backlogged** with the report's closing shapes. |
| M3 | the pin's own check phase has the same one-display shape | **backlogged** as a pointer; `flake.nix` is the fork's side. |
| M4 | the format comment explains a `result` symlink this script does not create | **fixed** (6), one clause. |
| M5 | the example smoke passes a GUI that deadlocked | **fixed** (6), one clause saying what the check does not prove. |
| — | `(locks x-display)` vs `-j 1` | **taken** (6): the nine rules that present a toplevel. |
| — | the XTEST bead | **merge decision**, unchanged; the backlog entry is corrected — `Widget.compute_bounds`/`compute_point`/`translate_coordinates` are already bound, so one of its two named blockers is solved, and the review's `live_input.ml` sketch is recorded with it. |

---

## Test evidence

Every behavioural fix was verified by putting the old code back and watching the assertion
flip. The mutations were applied to a copy, run, and reverted.

### Group 1 — exception safety

`test/live/live_patcher.ml`, over a window this test now *presents* (what `Loop.start` does):

| line | with the fix | with `apply_stack_claims` back outside the guard |
|---|---|---|
| `the presented window is still on screen` | `false` | `true` |
| `effects scheduled by that button` | `0` | `1` |

`test/live/live_patcher.ml`, a `Native` whose `destroy` raises, mid-list:

| line | with the fix | with the collection removed |
|---|---|---|
| `destroy re-raised` | `(Failure "this native destroy raises")` | same |
| `effects scheduled after the raising teardown` | `0` | `1` (the sibling *after* the raising node stayed armed) |

`test/live/live_embed.ml`, the same rejection as an `Embed.create` first frame, where the
failure path can do nothing on its own (`Driver.stop` finds `t.root = None`):

| line | with the fix | without |
|---|---|---|
| `the tree the walk had finished was torn down` | `2 native destroys of 2` | `0 native destroys of 2` |

### Group 2 — the selection anchor

Both assertions needed a reorder that moves the *selected* child: `Reconcile.diff` emits a
`Move` for the row that jumps, not for the ones that slide, so the existing reorder cases
never went through `move` for the selected row at all.

| line | with the fix | without |
|---|---|---|
| `GTK's own selected row, having moved it` (`gtk_list_box_get_selected_row`, which returns `box->selected_row` directly) | `b` | `(none)` |
| `fb keyboard focus enters at` (`gtk_widget_child_focus` with no focus child takes `BOX_PRIV (box)->selected_child` and falls back to the first child) | `b` | `c` (the first card) |
| `fb GTK's own selected children` | `b` | `b` — and that is the point: it walks the children's own flags, so it agrees with us either way |

**Argued deviation.** The ruling asked for the assertion through `get_selected_row` *and*
`get_selected_children`. The first is exact. The second cannot be: `gtk_flow_box_get_selected_children`
collects children whose own flag is set (gtkflowbox.c:4728-4735), where
`gtk_list_box_get_selected_row` returns the anchor pointer directly (gtklistbox.c:846-851) —
so on the flow box it is not a discriminator, and the flow box's anchor has no getter at
all. It is read at gtkflowbox.c:1105-1111 (extending a shift-click, unreachable without
synthetic input) and :3210 (where keyboard focus enters), and the second of those *is*
reachable, which is what the focus probe uses. Both lines are printed, and the test says
which one can see what.

### Group 3 — the NUL refusal

`test/live/live_controls.ml`, per kind (entry, password entry, search entry, editable label):

| line | with the refusal | without |
|---|---|---|
| `asked for a text with a NUL` | `text="kept", wrote 0, reported 1` | `text="ab", wrote 2, reported 0` |
| `five idle frames parked on it` | `text="kept", wrote 0, reported 0` | `text="ab", wrote 10, reported 0` |
| `and a text GTK does take` | `text="recovered", wrote 2, reported 0` | same |

`test/live/live_text.ml`'s bench, an idle frame parked on a refused 100 000-character text
against a settled 16-character entry:

| | with the refusal | without |
|---|---|---|
| entry, parked | `0.00019 ms`, ratio **0.65** | `1.17580 ms`, ratio **5320.81** |

The search entry's own consequence is asserted separately: a refused write arms no debounce,
so the timeout still elapses and `Attr.on_search_changed` fires for a real edit. (The one
`""` search at mount is GTK's own — `gtk_search_entry_set_search_delay` ends in
`reset_timeout`, gtksearchentry.c:1048 — and the test says so.)

### Group 4 — the handle's new checks

New tests in `test/handle/test_handle.ml`, each against the runtime's own message (copied
into the test library, since it cannot link `bonsai_gtk` — the goldens are what keeps the
two spellings identical):

- a box root under the default `` `Window `` raises `Bonsai_gtk: the root node must be a
  Node.window, got Box…`, and so does the same tree through `recompute_view`, which prints
  nothing;
- a window root under `~root_kind:`Not_window`` raises `Bonsai_gtk.embed: …`;
- a box root under `~root_kind:`Not_window`` is accepted;
- two siblings with one key raise `root/0: duplicate key a among one container's children…`,
  and through a slot, `root/0/overlays: …`;
- a window below the root raises `root/0/0: a Node.window may only be the root node…`.

The three new actions move three models in one `do_actions`: `reveal false`, `position 240`,
`visible_child parts`, all in one diff.

### Group 6 — the gate

C1, verified end to end. With `BONSAI_GTK_LIVE_TESTS=1` exported by the caller:

```
== pure + headless tests
== per-package builds, the way opam --with-test runs them
== live tests (xvfb)
bench: flow box 0.451 ms at sel=1, 0.398 ms at sel=200, ratio 0.88 (bound 5)
== example smoke
all green
```

The bench lines appear after the live heading and nowhere else — before the fix they ran
under "pure + headless tests", unserialised and without xvfb, and the live section then ran
nothing.

I2, verified by the reviewer's own mutation (`Hashtbl.{mem,find} by_key` → `row_by_key w`,
the shipped-then-fixed quadratic shape) in `w_list_box.ml`:

| | fixed | mutated |
|---|---|---|
| `bench: list box` | `0.394 ms at sel=1, 0.394 ms at sel=200, ratio 1.00` | `0.433 ms at sel=1, 21.302 ms at sel=200, ratio 49.24 (bound 5)` |

C2, measured at 2x oversubscription (48 spinning shells against 24 cores), five runs each:

| arrangement | ratios | worst |
|---|---|---|
| sequential (as shipped) | the review's 30 runs: 3 failures | 1.23 |
| interleaved, 2 000 frames | 1.00, 0.85, 1.18, 0.86, 0.98 | **1.18** |
| interleaved, 20 000 frames | 1.02, 1.02, 1.00, 0.98, 0.97 | **1.02** |

## The two CI tails

Both runs of `nix develop -c ./scripts/ci.sh` on the finished tree, back to back, with
nothing cleaned between them. The second is the one that matters for live I1: before the fix
it would have printed no bench lines at all.

```
### run 1                                                          EXIT=0, 58 s
== nix: ocgtk pin builds and passes its tests
== format
== build
== generated opam files are committed
== pure + headless tests
== per-package builds, the way opam --with-test runs them
== live tests (xvfb)
bench: flow box 0.460 ms at sel=1, 0.505 ms at sel=200, ratio 1.10 (bound 5)
bench: list box 0.450 ms at sel=1, 0.393 ms at sel=200, ratio 0.87 (bound 5)
bench: 0.00021 ms at 16 chars, 0.00013 ms at 1 MB, ratio 0.62 (bound 5)
bench: 0.00015 ms parked on a refused 1 MB write, ratio 1.17 (bound 5)
bench: 0.00014 ms at 4 items, 0.00014 ms at 1000 items, ratio 0.97 (bound 5)
bench: 0.00013 ms parked on a refused selection, ratio 0.96 (bound 5)
bench: calendar 0.00017 ms settled, 0.00012 ms parked on a refused date, ratio 0.73
bench: editable label 0.00019 ms at 16 chars, 0.00013 ms parked on a refused write,
       1.23260 ms at 100 000 chars (the compare is O(len), as every entry's already is)
bench: entry 0.00022 ms settled at 16 chars, 0.00015 ms parked on a refused
       100 000-char write, ratio 0.69
bench: 0.0083 ms embedded, 0.0083 ms windowed, ratio 1.00 (bound 1.2)
== example smoke
all green

### run 2                                                          EXIT=0, 57 s
… same sections …
bench: flow box 0.453 ms at sel=1, 0.503 ms at sel=200, ratio 1.11 (bound 5)
bench: list box 0.395 ms at sel=1, 0.394 ms at sel=200, ratio 1.00 (bound 5)
bench: 0.00020 ms at 16 chars, 0.00012 ms at 1 MB, ratio 0.61 (bound 5)
bench: 0.00015 ms parked on a refused 1 MB write, ratio 1.20 (bound 5)
bench: 0.00015 ms at 4 items, 0.00014 ms at 1000 items, ratio 0.93 (bound 5)
bench: 0.00013 ms parked on a refused selection, ratio 0.96 (bound 5)
bench: calendar 0.00017 ms settled, 0.00013 ms parked on a refused date, ratio 0.77
bench: editable label 0.00022 ms at 16 chars, 0.00013 ms parked on a refused write,
       1.23101 ms at 100 000 chars
bench: entry 0.00022 ms settled at 16 chars, 0.00015 ms parked on a refused
       100 000-char write, ratio 0.70
bench: 0.0084 ms embedded, 0.0085 ms windowed, ratio 1.00 (bound 1.2)
== example smoke
all green
```

Ten bench lines in both, which is the live step doing its work twice. `git status` is clean
apart from the pre-existing untracked `.beads/issues.jsonl` (left untracked deliberately —
one commit picked it up through a `git add -A` and was amended to drop it).

## Recorded choices, in one place

1. **C2**: interleaved *and* lengthened, bound unchanged at 1.2. Interleaving alone left a
   worst case of 1.18.
2. **Live I1**: `rm -f` the live outputs rather than a scoped clean.
3. **The patcher's interest arms**: not collapsed away but *widened* —
   `Editable_label` became `Editable` over four kinds, since one refusal table serves all
   four. Four arms before, four after.
4. **Headless C1c**: the root check sits in `Result_spec.view` with a remembered root kind,
   not in a computation wrapper (which poisons Incremental process-wide).
5. **Headless I5**: the sweeps were not moved into `test/`; it is a rewrite, not a file move.
6. **Containers I2**: doc-only, per the ruling — the impl still writes NULL rather than
   `Some ""`, on the `w_stack.ml` precedent.
7. **Controls M2**: a `~max_length` above 65536 is clamped where the comparison is, not
   rejected at the constructor; a negative one is rejected.
8. **A seventh commit** for the Minors and the backlog.
