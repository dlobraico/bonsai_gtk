# M1 final-review fix wave

Branch `m1`, base `886b1d5`, head `1eeba76`. Eleven commits, one per finding or per
tightly related group. Nothing pushed, nothing merged, `bd` not run.

`nix develop -c ./scripts/ci.sh` ends with `all green` (tail at the bottom).

## Per finding

| # | Finding | Commit | What was done | Test that proves it |
|---|---|---|---|---|
| 1 | Core #1 — a hand-driven `Driver.frame` that raises does not set `broken` | `94d9cbc` | The state transition moved out of `Scheduler.guarded_frame` into `Scheduler.mark_broken`, which `Driver.frame` calls on its way out before re-raising with the original backtrace; `Patcher.abandon_fixups` drops the failed pass's queue, and `Driver.stop` drops it too. `guarded_frame` still calls `mark_broken` (idempotent) — see deviations. | `live_driver.ml`: a hand-driven raising frame gives `broken after a hand-driven raise: true`, the next `frame` is a no-op, and `frame` after `stop` raises. `live_containers.ml`: a mount that raises after enqueuing a stack fixup leaves `fixups left behind by the failed pass: 1`, and `abandon_fixups` clears it. |
| 2 | Core #2 / containers I1 — duplicate sibling keys not checked at mount, message carries no path | `16ed479` | `Reconcile.check_unique_keys` exposed and called from `Patcher.mount_list`; both it and the `Reconcile.diff` call in `patch_list` wrapped in `child_op ~path`. Message reworded (it no longer says `Reconcile.diff:`) to state the rule. | `live_containers.ml`: rejected at mount for a box (`dupkey/0`) and for a stack's page names (`duppage/0`), and at patch (`patchdup/0`), each with its path. `test_reconcile.ml` updated. |
| 3 | Core #3 — `register_stack` collides on an ordinary refactor | `b76029b` | `Patcher.drop_stack_names` walks the old subtree and gives up its registrations in the kind-change arm, before the replacement is mounted. `destroy`'s `Gobject.same` guard factored out as `unregister_stack` and shared. | `live_containers.ml`: `stack wrapped in a frame; switcher drives the surviving stack: true`, and a patch that puts a *second* live stack under a held name still gives `rejected: twin/0/1/0: two Node.stacks are named "twin" in one tree`. |
| 4 | Core #4 — `Signals.spec.connect` returns a bare handler id | `cc34750` | New abstract `Signals.connection` (`source` + `handler_id`), built with `Signals.connected obj id`; `Signals.disconnect : connection list -> unit` disconnects each from its own object; `live.handler_ids` → `live.connections`. All ten M1 specs updated — the entry family's `changed` now names the `GtkEditable` it connected to. Contract stated in `signals.mli` and spec §6.4. | No new test: the change is type-driven and every existing live signal test (`entry signals reaching Bonsai: 8`, the notify family, the teardown paths) exercises connect and disconnect. |
| 5 | Controls #1 — a programmatic write to a `Node.search_entry` fires `on_search_changed` | `185014d` | `w_search_entry` records the text it last wrote in an `Ephemeron.K1` table keyed on the widget (weak, so a destroyed entry takes its record with it) and `fire` returns `None` while the widget's text still equals it; the record is consumed on the first emission either way. `W_entry.set_text_if_needed` now reports whether it wrote, so only a write that armed a debounce is recorded. `Node.search_entry`'s doc updated. | `live_controls.ml`: `searches after the mount wrote the text: 0`, `searches after the model rewrote it: 0`, `searches after a real edit: BACHS`. Reverting the check turns the last line into `bach,BACH,BACHS` (verified). The loop is pumped by a bounded `Glib.Main.iteration true` woken by a timeout source — no `Unix.sleep`. |
| 6 | Containers I2 — grid re-attach drops focus | `29b8f67` | `w_grid`'s `updated` hook saves `Root.get_focus` before the `remove`/`attach` pair and restores it if it was inside the moved child; comment corrected. **The premise does not reproduce** — see deviations. | `live_containers.ml`: `focus is in the entry: true` / `focus survives the re-attach: true`. It passes with and without the restore on GTK 4.22.4; what it pins is the behaviour. |
| 7 | Tests I1 — `dune build -p <pkg> @runtest` fails for both packages | `ed9356e` | `test_handle.ml` and `test_gallery.ml` moved to `test/handle/`, a directory the `bonsai_gtk_test` package owns; `test/` keeps the pure tests and depends on `bonsai_gtk` alone; both libraries name their package. `dune-project`'s comment corrected and the dep lists follow. `ci.sh` runs both `-p` builds in build dirs of their own, installing `bonsai_gtk` into a temp prefix first because `-p` hides the local copy. | `ci.sh`'s `== per-package builds` step. Verified non-vacuous: breaking an expect test in `test/handle/` makes `dune build -p bonsai_gtk_test @runtest` fail. |
| 8 | Tests I2 — headless handle vs `require_specs` | `6db7e82` | `Bonsai_gtk_test.create`'s docstring now says plainly that structural validation happens at mount, lists what the runtime rejects and the handle does not, and points at the M2 table. Backlog item added under "Do first in M2"; the table itself was **not** built, as ruled. | Documentation only. |
| 9 | Tests I3–I9 — coverage | `32f925a` | One sequence patches every prop of `Window`, `Box`, `Grid`, `Paned`, `Center_box` and `Spinner`; switcher/sidebar retargeting `"a"` → `"b"`; a stack renamed to a *free* name while a switcher names the old one; a page added and selected in the same pass; an insert in front of existing siblings and a `Move` to index 0; a non-window root; a css class added then removed, with `Attr.margin` beside it; the decline-the-edit block parameterised over all three entry kinds, each ending on a prop of its own. (`frame` on a stopped driver landed in `94d9cbc`.) | The four `expected_*.txt` goldens. Highlights: `default size 320x240, box homogeneous false` → `400x300 / true`; `re-pointed at stack b -- switcher true, sidebar true`; `rejected: rn/0/0: no Node.stack is named "old"`; `(GtkStack (visible (encores)))`; `(b c)` → `(a b c)` → `(c a b)`; `password_entry echo is a no-op: ab (the patch wrote: false)`. |
| 10 | Tests M4 / M5 / M6 | `c03fb2f` | M4: `Node.find_by_test_id` walks the whole tree and raises naming every path (`Children.iteri` computes them). M5: `ci.sh` builds the examples first and runs them out of `_build`, so the 3 s budget covers the run alone. M6: the gallery writes its PNG to a fixed name instead of a fresh temp file per run. All three under ~20 lines. | `test_node.ml`: `"Node.find_by_test_id: 2 nodes carry the test_id delete (root/0/1, root/0/2); ..."`. M5/M6 are script and example changes. |
| — | Docs | `1eeba76` | Spec §6.2 (mount-before-destroy, prop/attr order), §6.4 (`Signals.connection`, `fire`'s second `None`), §6.5 (deferred-signal rule), §6.6 (native `create`/`destroy` overlap), §9 + §10 (package split, `test/handle/`), §11 (mount-time key check with path, rename-onto-a-free-name). README: `test/handle/`, a Limitations bullet on what the headless handle does not catch, the search entry's user-only signal, the per-package builds. Backlog as below. | — |

### One extra fix, not in the brief

`32f925a` also fixes a **segfault** the new coverage flushed out. `Live_tree.dump` read a
password entry's placeholder with `gtk_password_entry_get_placeholder_text`, which returns
NULL when unset and which ocgtk binds as `string` — so dumping any `Node.password_entry`
without a placeholder core-dumped. Every existing test happened to set one. It now reads
the property through a GValue, whose stub maps NULL to `""`, which is already what the
surrounding code treats as "no placeholder". The nullable binding is on the ocgtk fork
list.

## Deviations from the rulings

1. **Finding 1 — `guarded_frame` still calls `mark_broken`.** The ruling said to leave
   `guarded_frame` responsible only for logging. `Driver.frame` does now own the
   transition, which is the point of the finding; `guarded_frame` calls the same
   (idempotent) function afterwards so that `Scheduler.broken`'s documented contract — "a
   frame that raised is the last one" — does not depend on which `run_frame` the scheduler
   was built with. Without it, a scheduler whose thunk raises without marking broken would
   keep ticking and re-raising.

2. **Finding 1 — the "stale fixup does not run in the next frame" test is at patcher
   level.** Once `Driver.frame` marks the driver broken there *is* no next frame, so the
   claim is not observable through the driver. It is asserted where it is observable: a
   pass that raises leaves its fixup queue populated, and `abandon_fixups` — which
   `Driver.frame` now calls — empties it.

3. **Finding 6 — the premise does not reproduce, and the fix is insurance.** I probed GTK
   4.22.4 directly (window + grid + entry, focus set, `gtk_grid_remove`, re-attach), both
   unmapped and after `present()`: the child really is unrooted (`get_root` goes to `None`
   and back), and `gtk_root_get_focus` keeps pointing at the entry's internal `GtkText`
   throughout. So the review's failure scenario does not happen on this GTK, and the
   comment it asked me to correct ("its focus and its entry text do too") was right. I
   took the save/restore anyway, per the ruling: an unroot leaving the toplevel's focus
   alone is not something GTK promises, and it costs three getters on a path that only
   runs when a cell actually changed. The comment now describes what the pair does to the
   child's rooting rather than asserting a GTK behaviour, and points at the test. The live
   assertion is in, and passes with or without the restore — flagged in the test comment
   and in the backlog so nobody later reads it as proof the restore does something here.

4. **Finding 7 — `-p bonsai_gtk_test @runtest` needs an install step.** It cannot succeed
   from a bare checkout however the test directories are arranged: `bonsai_gtk_test`
   genuinely depends on `bonsai_gtk.vtree`, and `--only-packages` hides it. That is not a
   repo defect — it is what opam does, having installed `bonsai_gtk` first — so `ci.sh`
   installs `bonsai_gtk` into a `mktemp -d` prefix and puts it on `OCAMLPATH` for the
   second build. Both builds use `--build-dir` of their own so release-mode flags do not
   invalidate the main `_build`; `.gitignore` covers them.

5. **Finding 9 — `Attr.margin` (tests M7) came along for free** with the css-class test,
   since both live in the same attr sweep. It was on the backlog rather than in the brief.

## Backlog additions (`docs/m1-backlog.md`)

New sections and entries, each citing its area report:

- **"Closed by the final-review fix wave"** — the ten items above, plus the neighbouring
  one-liners taken opportunistically (core Minors 1, 3, 4).
- **"Do first in M2"** — the vtree-level `Kind.t -> Attr.Name.t list` event table for the
  headless handle (tests I2, ruled not to build now); `Kind.entry_props` has no
  `max_length`. Removed: "same-frame stack name reuse or swap raises" (fixed).
- **"Carried out of the final review (Minor, unfixed)"**, new section, 19 entries grouped
  as diagnostics/contracts, behaviour, consistency and tests: core Minors 2, 6, 7;
  controls Minors 2, 3, 5, 6, 7, 8, 9, 10 and the two out-of-scope notes; containers M1,
  M2, M3, M4, M5, M6; tests M1, M2, M3.
- **"API shape decisions"** — no `close-request` on `Node.window` (containers
  out-of-scope), which is the frame M3's `Node.windows` has to reconcile in.
- **"Known-and-accepted dump quirks"** — GTK 4.22 preserves the root's focus across an
  unparent/re-parent, so `w_grid.ml`'s save/restore is insurance and the focus assertion
  passes without it.
- **"ocgtk fork"** — the `Widget.set_name` item becomes a list of three nullable string
  bindings M1 wants: that one, `Password_entry.set_placeholder_text`, and
  `Password_entry.get_placeholder_text` (flagged as a *crash*, with the `Live_tree.dump`
  workaround), plus `Stack_page.set_title`.

## Gate

```
== nix: ocgtk pin builds and passes its tests
== format
== build
== generated opam files are committed
== pure + headless tests
== per-package builds, the way opam --with-test runs them
== live tests (xvfb)
bonsai_gtk: exception in frame, stopping the driver: (Invalid_argument
  "root/0/1: a Node.window may only be the root node, not a child of another node")
== example smoke
all green
```

(The `exception in frame` line is `live_driver.ml`'s `breaking_app` logging to stderr on
purpose, as it was before this wave.)

---

# Round 2 — closing `fix-wave-review.md`

Commit `86224d9` on `m1` (head was `1eeba76`). Nothing pushed, nothing merged.

## Important 1 — the Core #3 test was vacuous

The reviewer is right, and the mechanism is exactly as they diagnosed. In `wrapped`, the
stack sat in a `Node.box`'s **unkeyed** child list beside the switcher. `Reconcile.diff`'s
unkeyed matcher pairs positionally only when `same_kind` holds, and `Stack` against `Frame`
fails it — so the reconciler emitted `Remove {index=1}` + `Insert {index=1}` rather than an
`Update`, `removes @ ops` put the remove first, and `destroy` unregistered `"refactor"`
before `mount` re-registered it. `patch`'s kind-change arm — the only caller of
`drop_stack_names` — was never entered.

Fixed by the first of the two suggested shapes: the stack and the frame that wraps it both
carry `~key:"nav"`, so the reconciler emits an `Update` whose item is a different kind,
which *is* the arm. That keeps the switcher-follows-the-new-widget assertion the test also
makes; the window's-single-child shape would have lost it.

### Mutation evidence

| Step | Command | Result |
|---|---|---|
| 1. Reproduce | `if false then drop_stack_names ctx live;` (`src/patcher.ml:369`), old test | `BONSAI_GTK_LIVE_TESTS=1 … @test/live/runtest` → **exit 0**, whole live suite green. The reviewer's finding, confirmed. |
| 2. Fix the test, fix still disabled | same mutation, stack and frame both `~key:"nav"` | **FAILS**: `live_containers.exe` dies with `(Invalid_argument "wrap/0/1/0: two Node.stacks are named \"refactor\" in one tree")`, raised from `Patcher.mount` ← `Patcher.patch` ← `patch_list` ← … ← `live_containers.ml:805`. That is the finding's own scenario. |
| 3. Restore | `drop_stack_names ctx live;` restored | Green. `test/live/expected_containers.txt` is **byte-identical** — only the tree shape the test walks changed, not what it prints. |

## The eight Minors

Four are defects in text this wave itself authored, each a paragraph or a line. Backlogging
"correct the comment I just got wrong" would leave a knowingly-false claim in the tree, so
those are **fixed in place** and recorded in the backlog's "closed" section instead of its
open ones; the other four are genuine deferred work and are **backlogged** as instructed.
All eight appear in `docs/m1-backlog.md` citing `fix-wave-review.md`.

| Minor | Disposition | What |
|---|---|---|
| 1 — the one-write-one-timeout invariant is false for a write that empties the box | **Comment fixed; residual risk backlogged** | `w_search_entry.ml`'s two comments now describe GTK's real behaviour (a change to `""` emits `search-changed` synchronously and cancels the timeout, so the patch guard drops it before `fire` can consume the record) and say why the orphaned `""` record is benign in M1 — the model holds `""` too, so what it can cost is a duplicate, and the first non-empty emission flushes it. The behavioural risk, and why M2's headless `Search_changed` action changes the calculus, is a new "Behaviour" entry. |
| 2 — "Eight in all" against an accepted `7` | **Fixed** | `live_controls.ml`'s comment now says eight emissions, seven reaching Bonsai, names the eighth as *declined* rather than dropped, and points at the dedicated search-echo block for the claim it can no longer make. |
| 3 — the backlog removal overshoots | **Backlogged (restored, corrected)** | New "Do first in M2" entry: the same-frame **swap** still raises (`note_interest`'s rename arm removes then registers per child, left to right), while the **reuse** half of the deleted item was never broken, since removes come first. |
| 4 — `drop_stack_names` drops registrations early on a raising mount | **Backlogged** | One sentence on the existing containers-M3 entry, which covered only the mirror case. |
| 5 — missing blank line in spec §6.4 | **Fixed** | The `fire`-returns-`None` paragraph no longer runs into "Signals ocgtk does not generate as `on_*`". |
| 6 — spec §6.5 reads as persistent suppression | **Fixed** | Now: "declines the next emission if the widget's text still equals it. The record is consumed on that first emission either way, so it can never suppress more than the one signal the write armed." |
| 7 — `bonsai_gtk_test.mli` does not mention the new raise | **Fixed** | A doc paragraph on `result_spec`: two nodes under one `test_id` raise `Invalid_argument` naming both paths, an id no node carries raises `Failure`. |
| 8 — the gallery trades a leak for a symlink follow | **Backlogged** | Under "Tests", with the reason the fixed name is still right (nothing can remove the file) and the note that `Filename.temp_file` used `O_EXCL`. |

## Gate

```
== nix: ocgtk pin builds and passes its tests
== format
== build
== generated opam files are committed
== pure + headless tests
== per-package builds, the way opam --with-test runs them
== live tests (xvfb)
bonsai_gtk: exception in frame, stopping the driver: (Invalid_argument
  "root/0/1: a Node.window may only be the root node, not a child of another node")
== example smoke
all green
```
