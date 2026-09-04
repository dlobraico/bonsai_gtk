# Task 1 review — file splits, and two golden debts

Reviewer pass over `413b415..ac7ca30` (four commits), 2026-08-31. Method: per-commit
`git diff --color-moved=plain --color-moved-ws=allow-indentation-change` with every
non-moved line read; top-level-definition accounting old vs new; comment-stripped
diffs of the nine rename-sweep files; golden partition verified by concatenation;
expect blocks verified by extraction and multiset diff; one full
`nix develop -c ./scripts/ci.sh` run at `ac7ca30`.

## Verdict: **Approve**

The motion is pure. Every claim in the implementer's report I checked held; the one
gap the report's own scoping hid (the README) is graded Minor below.

## Evidence, per review charge

**Commit 1 (`29c5a94`, patcher split).** `patcher.mli` has no diff in the commit.
Top-level accounting: all 35 definitions of the old `patcher.ml` land in exactly one
of the three files, matching the plan's assignment — `child_path`/`child_op`/
`check_placement` plus the newly named `check_unique_keys` in `patcher_checks.ml`;
ctx/stack registry/claims/fixup queue/interest table in `patcher_fixups.ml`; the walk,
`live`, `release_kind`, `disarm`, `drop_stack_names`, `reassert_only` and the entry
wrappers stay. Non-moved diff residue is exclusively: module qualification
(`Patcher_fixups.`/`Patcher_checks.` at call sites, re-formatted by ocamlformat),
`open` headers, the type-equation re-exports, and new .mli doc comments. The
`check_unique_keys` extraction is exact — old inline
`child_op ~path (fun () -> Reconcile.check_unique_keys ...)` became the identical
expression behind a name, comment re-wrapped only. Visibility: `ctx`/`stack_claim`
stay `private` in `patcher.mli`; the equation in `patcher.ml` is the standard
concrete-in-impl pattern. The new .mli's expose exactly what `patcher.ml` consumes
(verified by grep: every `val` in both new mlis has a `Patcher_*.` use site in
`patcher.ml` or is `note_interest`'s immediate-half contract), and `register_stack`/
`resolve_stack`/`default_report` stay hidden inside `patcher_fixups.ml`. The library
is wrapped with `bonsai_gtk.ml` as main module and it re-exports only
`module Patcher = Patcher` (`src/bonsai_gtk.ml:58`), so the two new modules are
unreachable outside the library.

**Commit 2 (`38412ef`, live_controllers split).** Golden partition proved by
concatenation: `cat expected_controllers_{click,focus,key}.txt` at `38412ef` is
byte-identical to the old 84-line `expected_controllers.txt` (10/48/26 lines,
matching the report's 1–10 / 11–58 / 59–84). Non-moved residue in the four new .ml
files: the per-file header comments, `open Live_controllers_util`, and the reworded
util header — no code. Block accounting closes: old file 9 `let () =` blocks, new
files 4+3+4 = 11 = 9 moved + 2 extra `GMain.init` calls (each split file now inits
GTK itself, as the report says); util has zero top-level `let ()`.

**The lock placement (charge 3).** Read `live_controllers_click.ml` in full: both
blocks mount `Node.label` roots with `~on_window_created:(fun _ -> ())` — nothing is
presented, so no lock, per the plan's "presents a toplevel" rule. Focus and key use
`presenting_ctx` (`live_controllers_util.ml:160-170`, whose `on_window_created` calls
`W.Window.present`) and keep `(locks x-display)` in their dune rules. Counts: 14
`(rule` stanzas in `test/live/dune`, 11 carrying the lock (the other 2 grep hits for
the string are in the header comment) — the dune header says "eleven rules", ci.sh now
says "eleven of the fourteen". Consistent.

**The rename sweep.** The nine source files touched only for cross-references
(`examples/gallery.ml`, `src/controllers.ml(i)`, `src/signals.mli`,
`test/handle/test_handle.ml`, `test/live/live_input.ml`, `test/live/live_lists.ml`,
`test_lib/bonsai_gtk_test.mli`, `vtree/events.mli`) were each diffed with OCaml
comments stripped (nesting-aware): all nine are comment-only. Stale-reference grep
across the repo found `README.md:357` and five sites in `docs/m2-backlog.md` — see
findings.

**Commit 3 (`7b3799c`, test_gallery split).** Non-moved residue: comment rewording,
`open! Core` headers, and the two qualifications
(`Test_gallery_tree.every_widget`, `Test_gallery_tree.gallery_tree`). Expect blocks
extracted from before (one file) and after (three files): 327 lines each side,
identical as a line multiset — combined with the moved-line analysis showing no
expect line changed, the blocks are byte-identical. `test/handle` needed no dune
change (module auto-discovery).

**Commit 4 (`ac7ca30`, paned position).** The `[@sexp_drop_if Option.is_none]`
removal is symmetric in `vtree/kind.ml:257` and `vtree/kind.mli:246`, with the same
why-comment in both. The new `test_widgets.ml` print pins
`(Paned ((orientation Horizontal) (position ())))`. The report's "no existing golden
moved" claim verified: every `Paned` sexp in a golden carries an explicit
`(position (N))` (`test_gallery.ml:225`, `test_widgets.ml:255`,
`test_handle.ml:2815,2861-2862`); the two position-less `Node.paned` constructions
(`test_events.ml:48`, `live_events.ml:62`) only read `.kind` for the family tables
and never sexp the node; the live suites dump `Live_tree`, not node sexps.

**Deviations 2–3 (file sizes).** Accepted as justified by the plan's own assignments.
`src/patcher.ml` at 747: the plan assigns "the mount/patch/destroy walk" to
`patcher.ml`, and the walk is one `let rec ... and ...` mutual recursion — splitting
it across modules is not expressible as pure motion (it would mean breaking the
recursion with explicit knots, i.e. real change), so the ~500 verification line loses
to the file-assignment line, and the plan's actual goal (headroom: the window
registry, `Windows` interest and new fixup checks land in the now-small
`patcher_fixups`/`patcher_checks`) is achieved. `test_gallery_sweeps.ml` at 608: the
plan names exactly three gallery files and the lifecycle sweep has no other named
home; inventing a fourth file would be a larger deviation. Deviation 1 (the
`test_widgets.ml` addition) I verified at its premise: there was genuinely nothing to
promote, and without the added print the removal would be exercised by no test. It is
the task's only non-motion test change and it pins exactly the distinction Step 2 is
about. Deviation 4: the kind-change arm and its comment are findable in the post-split
`src/patcher.ml` (`patch_list`, around lines 500/604); later tasks' grep-by-comment
still works.

## Findings

**Minor — README stale pointer.** `README.md:357` still cites
`test/live/live_controllers.ml`, which no longer exists. The report's sweep claim was
scoped to "src/vtree/examples/test/test_lib" (accurate, but the plan's spirit is that
no live pointer dangles, and the README is the most user-facing file of all). Fix is
one line: name `live_controllers_util.ml` (the `armed=` printer claim it supports)
or the `live_controllers_*.ml` glob, as the sweep did elsewhere.

**Out-of-scope (backlog, not this task).** `docs/m2-backlog.md` references
`live_controllers.ml` (lines 431, 454, 459, 472, 537) and `expected_controllers.txt`
(645, 655). It is a historical document describing M2 state, and Task 13 rewrites it
as `docs/m3-backlog.md` — carry a note to Task 13 that the rewrite must translate
these file names to the split files, not copy them forward.

## CI run

`nix develop -c ./scripts/ci.sh` at `ac7ca30`, run by the reviewer: exit 0. Tail:

```
== example smoke
libEGL warning: DRI3 error: Could not get DRI3 device
libEGL warning: Ensure your X server supports DRI3 to get accelerated rendering
(… repeated libEGL DRI3 warnings from the three examples …)
all green
```

Full gate order observed in the log: nix ocgtk build, fmt aliases, `dune build @all`,
.opam check, headless tests, both `-p` package builds, live suite under xvfb, example
smoke. Tree left as found: only the pre-existing `.beads/issues.jsonl` modification
and the untracked `.superpowers/sdd/` ledger files (this review among them).
