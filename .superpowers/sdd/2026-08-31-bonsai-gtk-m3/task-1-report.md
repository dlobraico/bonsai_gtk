# Task 1 report — file splits, and two golden debts

Branch `m3`, commits `413b415..ac7ca30` (four commits, one per split plus one for the
golden debt). `nix develop -c ./scripts/ci.sh`: **all green** (tail below).

## What changed

**Commit 1 — `29c5a94` patcher split.**
`src/patcher.ml` (1071 → 747 lines) keeps the mount/patch/destroy walk, the `live`
type, `release_kind`, `disarm`, `drop_stack_names`, `reassert_only` and the two
entry-point wrappers.
`src/patcher_checks.ml(i)` (45/33 lines) takes `child_path`, `child_op`,
`check_placement` and a named `check_unique_keys` (the mount-time unique-key check that
was inline in `mount_list`, with its comment).
`src/patcher_fixups.ml(i)` (325/86 lines) takes the `ctx`/`stack_claim` records,
`create_ctx`, the stack registry (`register`/`unregister`/`resolve`,
`apply_stack_claims`), `run_fixups`, `abandon_fixups`, the `interest` type,
`interest_of_kind`, `enqueue_fixups` and `note_interest`.
`patcher.mli` is untouched: `patcher.ml` re-exports `ctx`/`stack_claim` by type
equation (`type ctx = Patcher_fixups.ctx = {...}`, concrete in the fixups mli, still
`private` in the public one) and aliases `create_ctx`/`run_fixups`/`abandon_fixups` —
nothing new is exported, and the new modules are unreachable outside the library
(`bonsai_gtk.ml` does not re-export them).

**Commit 2 — `38412ef` live_controllers split.**
`test/live/live_controllers.ml` (831 lines, seven blocks) →
`live_controllers_util.ml` (170: the what-this-can-prove header, `all_controllers` /
`ours` / `names`, the `controllers` printer, `click_gesture_props`,
`key_controller_props`, `nth`, `pump`, `events`/`record`/`drain`, `presenting_ctx`) +
`live_controllers_click.ml` (132: the set_static_name gc regression, the
every-controller-attr sweep) + `live_controllers_focus.ml` (334: the N1 family-removal
regression, the end-to-end focus/click lifecycle block) + `live_controllers_key.ml`
(229: key lifecycle, phase-disagreement rejection, `key_pressed_answer` table).
Dune links only each entry module's dependency cone (verified by string-searching a
built neighbour exe before relying on it), so the shared util is linked exactly where
referenced; each split file calls `GMain.init` itself and util has no top-level side
effects.
`expected_controllers.txt` split byte-for-byte along block boundaries: lines 1–10 →
`_click`, 11–58 → `_focus`, 59–84 → `_key`.
The focus and key rules keep `(locks x-display)`; the click rule takes **no lock** —
neither of its blocks presents a toplevel (both mount bare labels with
`on_window_created` ignoring), which is the plan's "where its executable presents a
toplevel" rule. The dune header's rule/executable counts and ci.sh's "ten of the
twelve" comment were updated (now eleven of fourteen), and every doc-comment reference
to `live_controllers.ml` across src/vtree/examples/test/test_lib now names the specific
split file (util for the printer/probe claims, focus for family-removal and
gesture-lifecycle, key for `key_pressed_answer` and the Gdk-constant pin, click for the
heap-churn regression and the attr sweep).

**Commit 3 — `7b3799c` test_gallery split.**
`test/handle/test_gallery.ml` (1213 lines) → `test_gallery_tree.ml` (331: the header
coverage claim, `gallery_tree`, `every_widget`) + `test_gallery.ml` (281: only the
golden, now over `Test_gallery_tree.every_widget`) + `test_gallery_sweeps.ml` (608: the
constructor/attr/event-attr/css-class sweeps, the per-kind lifecycle sweep and the
entry-point-checks regression). Every `[%expect]` block is byte-identical; the moved
header comments now point at the files the sweeps and the golden actually live in.

**Commit 4 — `ac7ca30` the paned golden debt.**
`[@sexp_drop_if Option.is_none]` removed from `paned_props.position` in `kind.ml` and
`kind.mli`, with a comment stating why the field deliberately prints its `None`.

## What the tests prove

- Headless (`@test/runtest`), both `-p` package builds, and the full live suite under
  xvfb all pass. Every golden except the one named below is **byte-identical** across
  all four commits, which is the "no behaviour change" claim in checkable form.
- The three new live goldens are exact partitions of the old one, so each split
  executable provably prints exactly what its blocks printed before.
- `test/test_widgets.ml` gains one print: a `Node.paned` built without `~position` now
  sexps `(position ())`, pinning that "no position computed" is distinguishable from
  "no such field".

## Deviations from the plan

1. **No existing paned golden moved.** Step 2 says "promote the moved goldens
   deliberately (the only change is `(position ())` appearing)", and the M2 backlog
   predicted every paned golden would move — but every paned the suite sexps passes an
   explicit `~position` (checked every `Node.paned` call site), and the live goldens
   are `Live_tree` dumps that never carried the node sexp. So there was nothing to
   promote, and the removal would have been exercised by nothing. I added the one
   position-less paned print to `test_widgets.ml` (beside the existing paned print) so
   the distinction the step is about is actually pinned. This is the only non-motion
   test change in the task.
2. **`src/patcher.ml` is 747 lines, not under ~500.** The plan's verification says
   "wc -l on the three split sources all under ~500", but it also assigns the whole
   mount/patch/destroy walk to `patcher.ml`, and the walk alone — with its
   exception-safety comments, which I did not trim — is ~700 lines. Everything the plan
   named for the other two modules was moved; shrinking further would mean splitting
   the walk itself, which the plan does not ask for and which Task 6/8 (the growth the
   split is for) land in `patcher_fixups`/`patcher_checks` anyway. Flagging rather than
   inventing a fourth file.
3. **`test_gallery_sweeps.ml` is 608 lines** for the same reason: the plan names three
   gallery files, and the lifecycle sweep (~370 lines with its row table) has no other
   named home. The golden file (281) and tree file (331) are well under.
4. **The "Update kind-change arm" comment** the pre-flight locates "after Task 1's
   split, find it by that comment": it stayed in `patcher.ml`'s `patch_list`
   (`src/patcher.ml`, the `Update` arm's else-branch), since the walk did not move.
5. Small necessary non-move adjustments, all commented in place: each split live file
   re-calls `GMain.init`; the util header says "these suites" instead of "this file";
   the dune/ci.sh executable and lock counts; the gallery header's pointer to where the
   sweeps went; cross-file doc references renamed as listed above.

## Deliberately left undone

- No further patcher decomposition beyond the three modules the plan names (see
  deviation 2).
- The stale-adjacent backlog items sitting next to the split notes (duplicated
  `all_kinds` lists, the `bonsai_gtk_test.opam` over-declaration, etc.) — out of
  scope for a motion task.
- `.beads/issues.jsonl` has a pre-existing uncommitted modification on the branch (not
  mine); left untouched.

## ci.sh tail

```
== example smoke
libEGL warning: DRI3 error: Could not get DRI3 device
libEGL warning: Ensure your X server supports DRI3 to get accelerated rendering
(counter, gallery, embed each held for their 3 s timeout)
all green
```

Full gate ran in order: nix ocgtk build, per-directory fmt aliases, `dune build @all`,
committed .opam check, headless tests, both `-p` package builds,
`BONSAI_GTK_LIVE_TESTS=1 xvfb-run -a dune build @test/live/runtest`, example smoke —
all green at `ac7ca30`.
