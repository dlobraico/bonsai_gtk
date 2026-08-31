# Task 2 review — the phys-equal walk, the unordered marker, the batch cost, `w_switch`

Reviewed `git diff 1daa1b5..ee64cc6` (27 files, +596/−121), the report, the plan's
pre-flight corrections and Global Constraints, and spec §5.3/§6.5/§11.
`nix develop -c ./scripts/ci.sh` re-run here: **`all green`** (exit 0), same tail as the
report, including the expected `root/0/1: a Node.window may only be the root node` line
from the deliberately-broken live driver app.

## Summary

The four items land, and the two that carried real risk — the reassert-and-fixup-only
walk and `?ordered:false` — are correct. I re-derived the reconciler's index arithmetic
independently rather than trusting the goldens: a faithful transcription of
`vtree/reconcile.ml:63-106` checked over 200 000 random `old`/`new_` pairs (lengths 0–5,
mixed keyed and unkeyed, duplicate-free) and exhaustively over every sub-permutation pair
of `{a,b,c}` (256 pairs), ordered and unordered, asserting at every op that the live
element the op's index names is *physically* the element the reconciler matched. It never
fails, in either mode, including under removals that shift indices and inserts that
interleave. `after_of`'s `cur[index-1]` is also always in bounds (`i ≤ length cur` holds
at every `Insert`). The "an `Update` after a `Remove` hits the wrong widget" failure mode
the brief asked about does not exist.

The walk is equivalent to the patch it replaces. I worked through what a full `patch` of a
phys-equal node actually does: `Attrs.diff` over the physically same `Attrs.t` is empty
(`Map.fold_symmetric_diff` short-circuits), so `require_specs` is skipped and no attr op
is applied; `Kind.equal_props` is true, so no `update`; `Signals.update_slots` rewrites
the slots with the identical closures; `ops.updated` is guarded on a changed value in all
three impls that have one (`w_grid.ml:85`, `w_stack.ml:142`, `w_overlay.ml:52`); and
`note_interest ~pass:(`Patch …)` reduces to a `Hashtbl.set` of a registration that is
already correct. What is left is `reassert` and the deferred selections, which is exactly
what `reassert_only` does. Nothing is lost.

The two hazards on the other side are both handled and, contrary to what I expected,
mostly *pinned*: `enqueue_fixups`'s `Nothing | Window -> ()` arm (`src/patcher.ml:145`)
is what keeps windows unpresented and stack names unregistered, and if the walk called
`note_interest ~pass:`Mount`` instead, `register_stack`'s `Hashtbl.add` would raise
`two Node.stacks are named "phys-nav" in one tree` on the second frame of the new
`live_driver.ml` test. The window half is the one gap (Minor 1).

`batch_if`'s `writes` is the correct condition at every one of the ten call sites, and
the multi-write cases (`w_entry`'s text+position, `w_switch`'s active+state) are both
governed by the single predicate that gates them, so the bracket is never absent when a
write happens.

**Verdict: Approved.** Three Minor findings, none blocking.

## Per-deviation judgement

1. **Trailing `unit` on `Reconcile.diff`.** *Sound.* Warning 16 is real — every other
   argument is labelled, so `?ordered` is unerasable without it. The alternative
   (mandatory `~ordered`) would have touched every call site and every existing test for
   no gain. The mli says why the `()` is there, which is what stops it being deleted.
2. **An unordered `Update` is indexed by `from`, not by `i`.** *Sound, and it is the only
   correct answer* — this is the load-bearing deviation and the report is right that it is
   forced rather than chosen. With no `Move`, the item matched at `new_` position 0 has
   not moved, so `Update { index = 0 }` would patch whatever child is sitting at 0.
   Verified exhaustively (above), and the consequence the report documents —
   `apply ops old = new_` no longer holds, only the set does — is stated in
   `vtree/reconcile.mli:51-56` and is what the new quickcheck's sorted comparison exists
   for. The pre-existing grid-reorder golden is a genuine independent witness: it was
   already exercising this path and did not move.
3. **`enqueue_fixups ctx ~path ~widget ~interest` rather than `ctx ~path live`.** *Sound.*
   `note_interest` is called from `mount` before the `live` record exists, so a `live`
   parameter would have forced either a second copy or a restructure of `mount`. Taking
   the three things it needs keeps one exhaustive `interest` match (no wildcard in either
   `enqueue_fixups` or `note_interest`, so Tasks 6–8 cannot add a selection without the
   compiler asking). Behaviour for `mount`/`patch` is unchanged: same registrations, same
   enqueue order, same sequence.
4. **`note_interest` was already shared, so the factoring split immediate from deferred
   rather than de-duplicating two copies.** *Sound.* The plan mispredicted the starting
   state; the split it actually performed is the one `reassert_only` needs, and the
   distinction is stated where it lives.
5. **`Move` on a container with no `move` raises rather than being ignored.** *Sound.*
   Unreachable by construction (`~ordered:(Option.is_some ops.move)` at
   `src/patcher.ml:468` is the only `diff` call site the patcher has, and `Reconcile.diff`
   is otherwise only reachable from tests). Message is §11-shaped — `Invalid_argument`,
   node path first — though it is an internal invariant rather than the user misuse §11
   enumerates, which is right for something an app author cannot provoke. A silent drop
   here would desynchronise `cur` from GTK, which is the exact bug the option removes.
6. **`reassert_only` takes `~path`** (the task's sketched mli did not). *Sound* — Step 6
   explicitly preferred threading over a `path` field on `live`, and
   `Children.iteri ~path` already spells child paths identically to `mount`/`patch`
   (`vtree/children.ml:26-33`), so the paths in a fixup's error message name the same node
   the patcher would name.

Measured numbers: 55.2 ns vs the pre-flight's 79.5 ns for the same shape is machine noise,
not a disagreement, and either number keeps pre-flight correction 4's ruling
(`batch_if` stays). The doc comment on `batch_if` quotes 79.5 ns while the report measured
55.2 ns; both are "cheap, not free", so the conclusion is unaffected.

## Critical

None.

## Important

None.

## Minor

**M1. Nothing fails if the walk re-presents a window, and nothing fails if the fast path
is switched off entirely.** `test/live/live_driver.ml:304` creates the `phys` driver with
`~on_window_created:(fun _ -> ())`, so a `reassert_only` that routed `Window` to
`ctx.on_window_created` — one of the two "does too much" hazards the walk is written
around, and the one that would raise and refocus a real window on every idle tick — would
leave every golden byte-identical. The stack-name hazard *is* covered (a `register_stack`
from the walk raises `two Node.stacks are named "phys-nav"`), and the "does too little"
side is covered twice over. Fix is one line: give that driver
`~on_window_created:(fun _ -> print_endline "phys window created")` and let the golden
carry the single line, exactly as `live_driver.ml:158` already does for the first driver.

Relatedly, no test distinguishes the fast path from the slow one: replacing
`phys_equal node live.Patcher.node` (`src/driver.ml:63`) with `false` leaves the whole
suite green, because the two paths are behaviourally identical by design. That is
tolerable — the change's contract *is* "no observable difference" — but it means the
optimisation is unpinned, and a future refactor that accidentally makes the guard
unreachable would be invisible. Worth a backlog line rather than a fix.

**M2. `batch_if`'s contract permits an unbracketed write; only the call sites forbid it.**
`src/widget_impl.ml:51` is `if writes then batch w f else f ()`, and every call site is
spelled `batch_if writes w (fun () -> if writes then <write>)` — the condition is written
twice, and the mli (`src/widget_impl.mli:107`) documents the `false` branch as "`f ()`",
i.e. an *unbracketed run of the closure*. So the invariant "a write implies a freeze" is
maintained by ten copies of an internal `if` rather than by the abstraction. All ten are
correct today, including the two that write more than one property under a single
predicate (`w_entry.ml:127-132` writes `text` and then `position`, both gated by
`needs_text`; `w_switch.ml:38-40` writes `active` and `state`, both gated by
`needs_active`), so this is a shape observation, not a defect. If it is ever tightened,
`val batch_if : bool -> Widget.t -> (unit -> unit) -> unit` doing nothing at all when
`writes` is false would make the doubled condition unnecessary and the illegal state
unrepresentable — at the cost of a name that no longer reads as "batch, conditionally".
The plan prescribed the current shape; I would leave it and let the mli's existing warning
about multi-prop disjunctions stand.

**M3. Spec §5.3 now describes the mechanism this task replaced.**
`docs/superpowers/specs/2026-08-28-bonsai-gtk-design.md:324-328` still says "`Reconcile`'s
`Move` op is a **no-op** in those three" and that an explicit `Unordered` marker on
`list_ops` "should be reconsidered" when `Notebook` arrives. Both sentences are now
superseded — no `Move` is emitted, and the marker exists — and §5.3 is the paragraph a
reader is sent to by `Widget_impl.list_ops.move`'s own doc. The plan's file table does not
list spec edits for this task and Task 15 rewrites the backlog rather than the spec, so
this is drift to record rather than a fix to demand here; the two sentences want an M2
amendment in the style §5.3 and §11 already use.

## Observations (no action)

- **Carry for Tasks 6/7.** In unordered mode `Insert`'s index is `new_`'s position while
  every other index is the live list's, so a newly inserted child lands at `new_`'s index
  *within* the live order. That is invisible for the three containers taking `None` today
  (`Overlay.add_overlay`, `Stack.add_named` and `Grid.attach` all ignore `~after`), but
  `GtkListBox`/`GtkFlowBox` insert *by position*. If either takes `move = None`, its new
  rows will land at their `new_` index in an otherwise-live-ordered list — consistent, and
  `cur` stays in step with GTK, but worth deciding deliberately. `list_ops.move`'s doc
  says children "stay in the order they were first added", which is precisely true only
  for containers whose `insert` ignores `after`.
- `Widget_impl.batch w` on a scale or spin button freezes the *widget*, while
  `W.Range.set_value` writes `GtkAdjustment:value`, and `value-changed`
  (`w_scale.ml:16-18`) is a plain signal rather than a `notify::` in any case — so the
  bracket there was never suppressing anything and `Scheduler.in_patch` is what does the
  work. Pre-existing (M1), and `batch_if` strictly improves it by skipping the bracket
  entirely on the no-write path.
- `Patcher.reassert_only` is exported, and its mli correctly tells the caller to run
  `run_fixups` afterwards inside the guard. `Driver.frame` already abandons the queue and
  marks the scheduler broken when the walk raises (`src/driver.ml:109-115`), so exception
  safety matches `mount`/`patch` exactly; `Widget_impl.batch`'s `Exn.protect` still means a
  raising `reassert` cannot leave a widget frozen, and `batch_if false` never freezes at
  all. Task 12's `Expert.embed` will need the same three-line discipline.
- Nothing in the diff is out of scope: every file is named by the task text (Step 5's
  audit list accounts for the nine extra widget files), the only goldens that moved did so
  by addition, and no `expected_*.txt` line was deleted.

## Verdict

**Approved.** The three Minor items are worth a follow-up bead each — M1 is a one-line
test change, M3 a spec amendment, M2 a judgement call I would resolve as "leave it".
