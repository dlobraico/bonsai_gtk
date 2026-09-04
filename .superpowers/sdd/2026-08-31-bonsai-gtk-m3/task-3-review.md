# Task 3 review — report-once memos, `Child_keys.length`, and the text view's caret

Reviewed `028d150..accd8d9` (four commits) against the plan's Task 3 text, the Global
Constraints, `docs/m2-backlog.md`'s "Do first in M3" entries, and the task report.
Independent runs: the Flow_box mutation (applied, observed, reverted, re-verified), a
direct `live_lists.exe` run for the bench line, and one full `nix develop -c ./scripts/ci.sh`
at `accd8d9` — **all green** (tail below).

## Verdict

**Approve.** No Critical, no Important. The four steps do what the task said, the memo
semantics are exactly the retry-every-frame/report-once shape the backlog asked for, the
mutation claim reproduces byte-for-byte, the caret attr's guard story is true on every
path and pinned live, and all 15 "Do first in M3" bullets are accounted for by name (the
report's accounting checks out against `docs/m2-backlog.md:95-191`). Three Minors, all
comment-level. My recommendation on the standing trigger is at the end.

## What I verified, per the scrutiny list

**1. The report-once memos (`b550f8c`).** One memo shape, genuinely: both twins are the
same `Refusal.Make (String) (Refusal.No_extra)` application over the shared
`src/widgets/refusal.ml` machinery, keyed (as the `refused` value) on the offending page
key. The drive block around it is written once per widget because the read-backs really
differ (stack: `get_visible_child_name` by name; notebook: `get_current_page` by index) —
that is not the list_box/flow_box kind of copy. Retry-every-frame is structural:
`Patcher.reassert_only` (src/patcher.ml:769-776) re-enqueues the select fixups on every
idle frame, and the fixup body always attempts before consulting the memo. Read-back
decides ("did GTK take it"), `landed` clears on every frame the selection shows, re-hide
re-reports — all four stages pinned in the golden for both twins
(test/live/expected_lists.txt:305-319). The report fires through `Patcher.ctx.report`
with the node path, polled via `take_report` inside the fixup closure
(src/patcher_fixups.ml:303-346), and the message names the page and the reason
(`~visible_child names the hidden page "b"; GTK will not switch to it`; notebook says
`~current_page`). **No leak:** the memo cache is an ephemeron table keyed on the
*container* widget, so an entry dies with its stack/notebook; a page key that vanishes
leaves at most one stale string in `refused`, cleared by the next landing (which happens
on every settled frame) or overwritten by the next refusal. `take_report` uses `find_opt`
and mints nothing (the M2 final-review M6 lesson, honored).

**2. The dedup (`1fee718`).** Dedupe-before-compare cannot change GTK's selection for any
legal tree: duplicate keys among siblings are `Invalid_argument` at mount and patch, so
within one container a key names at most one row and selecting it once or twice is the
same call sequence — `~selected:["a"; "a"]` is a pure model typo with no legitimate
reading, which is why dedupe-and-report-once is the right ruling and consistent with the
refuse/record/report doctrine. Order-preserving first-occurrence dedup (not the backlog's
throwaway `List.dedup_and_sort` suggestion) keeps the model's write order, which the
Browse-mode comment depends on. Report-once is keyed on the whole list; a parked node is
a pointer comparison (`already_refused`'s `phys_equal` fast path); a different duplicated
list is a new datum; a clean list clears. All pinned. **Both copies are separately
goldened**: test/live/expected_lists.txt:320-336 has a full five-stage cycle for the list
box *and* the flow box, each with its own `report dup/0:` lines and deduped `selected=`
read-back through GTK's own getters — a dedup landed in one file only fails the other
file's block. Confirmed by reading the golden, as asked.

**3. `Child_keys.length` + `tracked_keys` (`d362157`).** `length` does not force a GC: it
calls `Stdlib.Ephemeron`'s `Table.clean` (drops dead-but-unswept bindings) then `length`.
Determinism therefore comes from the *caller's* `Gc.full_major`, and both the mli and the
live test say exactly that — the doc is honest. The live test's reachability argument is
sound: `Sys.opaque_identity live` *after* the post-destroy read keeps every wrapper (the
ephemeron keys) alive across the `full_major`, so the observed zero can only be the
`forget_*` hooks' doing. Counts are deltas against the module table's baseline because
the tables are shared per kind. **Mutation re-applied myself**: `| Flow_box _ -> ()` at
src/patcher.ml:72, live suite run — the golden moves to
`flow box tracks 3 keys after the teardown` (list box and notebook stay 0, correctly:
their arms were untouched); reverted, tree verified clean, full ci.sh green after.
The task-7-M4 hole is closed.

**4. `Attr.on_cursor_moved` (`accd8d9`).** The connection names the buffer:
`Signals.notify_connection ~prop:"cursor-position" b` inside `cursor_moved`'s `connect`
(src/widgets/w_text_view.ml:287-311) — same teardown shape as `changed`, which the
existing destroy-then-emit live block covers. The feedback-loop question resolves as
**suppressed, and tested**: the controlled write's restore (`place_cursor` in
`set_text_if_needed`) emits `notify::cursor-position` synchronously, but every path that
calls `set_text_if_needed` runs under the patch guard — `Driver.run_frame` wraps both
`patch` and `reassert_only` in `Scheduler.with_patch_guard` (src/driver.ml:87-92) — and
`Signals.dispatch` returns before `fire` when `ctx.in_patch ()` (src/signals.ml:57). The
live golden's `caret after a controlled rewrite: ()` is that exact claim, and
`caret offset survived the rewrite: 11` pins the restore itself. The golden's numbers,
mapped: `5 0 11` are the three explicit `place_cursor` calls at offsets 5, 0, 11 made
*outside* the guard (each delivered through GTK's own synchronous notify on the C
stack); the trailing `11` is the caret restore surviving the same-length
`"hello world"`→`"HELLO WORLD"` rewrite. Headless `Move_cursor` is kind-checked, the
mis-aim negative prints the kind it found, and the unclamped-offset weakness is stated in
the mli beside `Set_value`'s. Every exhaustive table has its arm (Name, is_event,
controller_family = None, attr_phase = None, placement, attr_apply set/unset, gallery
sweeps, `Events.for_kind`'s TextView row; the count test moved 44→45).

**5. The parked-frame numbers.** What the parked cost scales with: per parked container
per idle frame, the fixup pays the by-name page lookup (`get_child_by_name` /
`page_index_by_key`, O(pages) — the same term the settled fixup already pays), plus one
refused GTK write and one extra read-back (a constant number of additional O(pages) GTK
calls), plus a pointer comparison for the memo. Linear in that container's page count,
constant per frame, no accumulation, nothing O(rows) — comfortably inside the backlog's
spend-where-the-measurements-are rule. On the numbers themselves: the report's
0.0090 ms/0.0007 ms (~13×) **did not reproduce** — my run of the same binary prints
`bench: stack 0.00054 ms per idle frame parked, 0.00049 ms settled` (~1.1×). The bench
is 200 single-shot frames timing a sub-microsecond operation, so the ratio is noise-bound
and machine-dependent; the conclusion (absolute cost negligible, attempt-per-frame policy
fine) holds under both measurements and is *stronger* under mine. See Minor 1.

**6. The verification clause.** All 15 bullets of `docs/m2-backlog.md`'s "Do first in M3"
list are answered by name in the report, and I checked the accounting: the closures
attributed to this task are real (verified above), the Task-2 attributions match the
ledger's Task 2 entry (require_slots, focus family, on_click claim), and the two
deliberate carries plus three absorptions match the plan's own verification text
verbatim. Task 13's rewrite has its list.

## Findings

**Important:** none.

**Minor:**

1. **The task report's headline bench ratio is not robust.** ~13× parked/settled did not
   reproduce (I measured ~1.1× on the same build; both runs agree the absolute cost is
   negligible). The report's acceptability argument survives, but the "~13×" figure
   should not be quoted onward as a property of the code — it is a property of one run.
   Suggest the controller's ledger entry record the cost as "sub-microsecond, ratio
   machine-dependent" rather than the 13×.
2. **A stale comment names a function that does not exist**, twice: the comment above
   `dedup_selected` says "Reported through [note_duplicates] when anything was dropped"
   in both `src/widgets/w_list_box.ml` and `src/widgets/w_flow_box.ml` — the reporting is
   inline in `dedup_selected` itself. Presumably a leftover from an earlier factoring.
   One line to fix, in two files (fittingly).
3. **The live caret test's mount comment misattributes the mechanism.** live_text.ml's
   new block says "The mount's own writes moved the caret inside the patch guard: nothing
   arrived" — but that `P.mount` is not under `with_patch_guard`, and the actual
   protection at mount is ordering: `Patcher.mount` runs `create` (which writes the text
   and moves the caret) before `connect_all` exists (src/patcher.ml:159-168), so there is
   no handler to fire. Under the real driver both mechanisms apply; in this test only the
   ordering does. The pin is real either way; the comment should say ordering.

**Out-of-scope (for the ledger/backlog):**

- The plan's Task 3 step 2 calls the dedup "the second fix made twice in these files";
  the report and commit say third. The M2 record supports the report: (1) the per-call
  key→child selection map (task-6 M6 → task-7 I1, `e9e7793`), (2) the M2 final-review
  containers I1 (selection preserved across a keyed reorder, applied to both files in the
  fix wave — the final2-containers report also notes N1/N3 each present twice). The
  plan's count was off by one; the trigger fires either way.
- A `~visible_child` naming a page that was *removed* while still named remains a
  per-frame raise through the fixup (pre-existing M2 arity rule, untouched here); noted
  only so nobody reads the new memo as covering it.

## The standing trigger (item 6): recommendation to the controller

The shape copied for the third time is the **`Selection_memo` + `dedup_selected` block**:
~55 byte-identical lines (the `Refusal.Make` over `string list`, the first-occurrence
filter, the report construction) present in both `w_list_box.ml` and `w_flow_box.ml`.
The two prior twice-made fixes: the O(|selected|×rows)→O(n) per-call key map (M2 task-6
M6, landed as task-7 I1), and the M2 final-review containers I1 (selection preserved
across a keyed remove/re-insert). Note the stack/notebook memo pair is *not* a fourth
instance — their drive blocks differ in the read-back and share the machinery that
should be shared.

**Recommendation: functorise, but in neither the fix wave nor Task 13 — schedule it as
an early-M4 motion-only task, with Task 13's backlog rewrite promoting it from
"declined" to "scheduled".** The evidence threshold the M2 review set is met, and the
third copy is the worst kind: subtle memo logic where a silent one-file divergence is
exactly the failure the mutation lesson exists for. But M3's fix wave comes after the
four-lens whole-branch review, whose findings should stay small and attributable —
folding a two-file structural refactor into it would churn the very lines the lenses
just read, for no M3 gain (Tasks 4–12 do not touch these files). Task 13 itself is a
docs task. The right moment is immediately after M3 merges: the live goldens now pin
both copies through GTK's own getters (this task's own contribution), which is precisely
the byte-identical-golden safety net the Task-1 motion-only pattern requires, so the
refactor is cheap, mechanically checkable, and cannot silently drop behaviour.

## ci.sh tail (my run, at `accd8d9`, tree clean)

```
== example smoke
libEGL warning: DRI3 error: Could not get DRI3 device
libEGL warning: Ensure your X server supports DRI3 to get accelerated rendering
(counter, gallery, embed each held for their 3 s timeout)
all green
```

Mutation check sequence: mutation applied → live suite run (golden moved:
`flow box tracks 3 keys after the teardown`) → reverted → `git status`/`git diff` clean →
full ci.sh green. The tree is as found (the pre-existing `.beads/issues.jsonl` drift and
untracked sdd reports excepted, neither touched by me).
