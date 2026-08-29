# Backlog carried out of M1

Items deferred by the M1 task reviews, their rulings, and whatever M0 left open that M1
did not close. The ledger with every ruling is
`.superpowers/sdd/2026-08-29-bonsai-gtk-m1/progress.md`; per-task detail is in the
`task-N-report.md` files beside it. Nothing here blocks M1.

The filename stays `m1-backlog.md` — it is "what M1 carries out", the same way its first
version was "what M0 carried out".

## Closed during M1 (was "do first in M1")
- **Child ops by predecessor widget** — `~after:(Widget.t option)` replaces `~index` +
  `sibling_before`, so no container reads GTK's live child list back. Task 1 (`14f9312`).
- **`Driver.frame` and `Driver.schedule_event` guard `broken`**, not just `stopped`, so a
  frame that raised really is the last one. Task 1 (`14f9312`).
- **The reentrancy guard (`in_patch`) is proved end to end** — `test/live/live_signals.ml`
  for the trampoline (Task 3, `bc70731`) and `test/live/live_controls.ml` for the
  programmatic-write case driven through `Driver.frame` (Task 4, `813bbf9`/`bff0794`).
- **Per-kind unset defaults** (`Unset Visible -> true` is wrong for `GtkWindow`) — replaced
  wholesale by a creation-time snapshot per widget, so dropping an attr restores what that
  widget was created with rather than a global default. Task 2 (`b477828`).
- **`vtree/children.mli`** — Task 8 (`7323228`).
- **`Driver.t.last` duplicating `root.node`** — the field went with the phys-equal
  short-circuit. Task 9 (`545c67d`).
- **Coverage gaps the task reviews flagged** — `Resource` image sources, non-default
  `Icon_size`, unchanged-filename no-reload, the scrolled-window min/max write order, an
  expander opening *and* swapping its child in one patch, `require_specs` for
  `on_expanded_changed`/`on_revealed`, and the shared prop defaults — closed by Task 10's
  sweep (`082f12a`, `5db453e`).

## Do first in M2
- **Seal `Attr.t` / `Attr.Name.t`** (`vtree/attr.mli`): the deferred ruling from the M1
  pre-flight scan — every M2 attr is otherwise a breaking change for a downstream
  exhaustive match, and M1 added twelve.
- **A reassert-and-fixup-only walk for phys-equal roots** (`src/driver.ml`, the comment at
  `frame`): the idle-tick cost the Task 9 patch-every-frame ruling deliberately accepted.
- **`Overlay`/`Stack`/`Grid` `move` is a no-op** — if M2's `Notebook` (which *does* have
  `reorder_child`) shares the list machinery, revisit whether an explicit `Unordered`
  marker on `list_ops` should stop `Reconcile` emitting `Move` at all
  (`vtree/reconcile.ml`, `src/patcher.ml`).
- **`Signals.spec.fire` reads state back off the widget** (`src/signals.mli`); a signal
  with a genuinely unreadable payload (`ListBox::row-activated`'s row, key events' keyval)
  needs the existential-event version of `spec`. M2's `ListBox` is the forcing case.
- **A headless `Search_changed` action** for `Attr.on_search_changed`, and an
  "opened an expander" action for `on_expanded_changed`
  (`test_lib/bonsai_gtk_test.mli`) — Task 4 and Task 7 both wanted one.
- **Same-frame stack name reuse or swap raises** (`src/patcher.ml`, `register_stack`): a
  frame that removes the stack named `"nav"` and inserts a different one with that name
  hits `Hashtbl.add`. Loud, not corrupting; the fix is deferring registration to the fixup
  pass, as the visible-child write already is. Task 9.
- **`min > max` content bounds on `Node.scrolled_window` are not rejected at the
  constructor** (`vtree/node.ml`, `src/widgets/w_scrolled_window.ml`); GTK calls it a
  programming error and has no runtime check of its own. Task 7 / Task 10.
- **`Attr.grid_cell` and `Attr.page_title` are silently inert outside their container**
  (Task 9) — a typo'd placement has no diagnostic, unlike a mis-attached event attr.
- **`w_switch`'s `create` hand-rolls the active write** instead of routing it through
  `reassert` like every other controlled kind (`src/widgets/w_switch.ml`). Task 4.
- **Per-`reassert` `batch` cost** (`src/widget_impl.ml`): every controlled kind brackets a
  freeze/thaw on every patch, including the patches that write nothing. Task 4.
- **ocgtk fork: `Widget.set_name : t -> string option -> unit`** — upstream binds only
  `string`, so `Unset Widget_name` cannot write NULL back and restores `""` instead. Task 2
  (documented on `Attr.widget_name`).

## API shape decisions before they become breaking
- `Bonsai_gtk_test.Action.t` is a public variant with the same exhaustive-match exposure as
  `Attr.t`; M1 took it from one constructor to five.
- `Expert.Driver.root_widget : Widget.t option` cannot survive `Node.windows` (M3).
- `start ?flags` (spec §4.1) is unimplemented; `NON_UNIQUE` is needed for two instances.
- `Kind.t`'s sexps are lossy — `sexp_of` only, with `[@sexp_drop_if]` dropping
  default-valued fields — so a `Node.t` sexp is a view for tests, not a serialisation.
  Adding `t_of_sexp` later means keeping the dropped defaults recoverable. Task 2.

## Tests worth adding
- GC/lifetime: remove a keyed child, `Gc.full_major`, assert the widget was finalized —
  the spec's central ownership assumption, still unwritten (carried from M0).
- After-display spin regression (needs a frame counter under `Private`) — carried from M0.
- `Driver.schedule_event`'s broken guard is exercised but not asserted: nothing public
  observes the Bonsai action queue's length. Task 1.
- Real-display click-through of `examples/gallery.exe` — it has only ever been run under
  `xvfb`. Task 10.
- `Live_tree.dump` collapses a placeholder `""`: a widget whose only text is empty prints
  the same as one with no text at all. Task 4.
- `focusable`/`can_focus` are absent from `Live_tree.dump`; showing them needs a per-class
  default to compare against (the pristine-widget read-back in `live_patcher.ml`). Task 2.
- Task 10's headless sweep covers every M1 widget; there is still no single live
  `Live_tree.dump` golden over the whole catalogue.
- Untested-but-implemented update branches: `Frame.label_align`, `Expander.use_markup`,
  `Revealer.transition`/`transition_duration` (none is printed by `Live_tree.dump`), and
  `W_image.update` writing `pixel_size` back to `-1`. Tasks 6 and 7.

## Known-and-accepted dump quirks
Do not "fix" these when an expected file surprises you:
- `Live_tree` prints `opacity` as GTK reports it (8-bit storage), so `Attr.opacity 0.5`
  reads back `0.501961`. Task 2.
- Every `GtkSpinButton` dump carries a constant `numeric` line: the node default is `true`
  where GTK's own is `false`. Task 5.
- GTK's icon-name resolution for `GtkImage` can churn across GTK versions, so image dumps
  may need re-promoting on a GTK bump. Accepted per the M1 plan. Task 6.
- A `Grid` child whose `Attr.grid_cell` changes is re-attached, which moves it to the end
  of GTK's child list; the cell is the placement, so nothing moves on screen — but the dump
  order changes. Task 9.

## Plumbing / hygiene
- `scripts/ci.sh`'s generated-opam check is `git diff --exit-code -- '*.opam'`; add `HEAD`
  so *staged* drift is caught too.
- `scripts/setup-switch.sh`: the reinstall stamp keys on `rev`, so a dirty `.ocgtk-src` at
  the pinned rev is not rebuilt — add a `git status --porcelain` check (it also protects
  against the re-clone `rm -rf`). Spec §2.1's "local fork edits testable without a push"
  needs "then `opam reinstall ocgtk`".
- Flake: a gir_gen-capable shell so the fork's generator tests don't depend on
  `~/src/stavekeeper#girgen`.
- Node paths are frozen at mount, so `on_exn` logs name a stale path after a move.
- `Signals.slots`' outer `ref` is built by mutation and never re-assigned afterwards.
- `mount` is not exception-safe (bounded): a node rejected by `require_specs` or
  `check_placement` leaves its already-created widget undestroyed.
- Redundant `(deps …)` in `test/live/dune`.
- The 16 ms tickless cadence is hard-coded (`src/scheduler.ml`), and `request_frame` does
  not cancel a pending `request_frame_soon`.
- `after_of` is `O(index)` per op and the surrounding `cur` bookkeeping is `O(n)` per op,
  so a list patch is `O(n·ops)`. Cheaper than M0, but M2's `ListBox` is what will feel it.
  Task 1.
- The `Update` kind-change arm still removes a child after `patch` destroyed the old live
  widget — latent until M3's `Node.windows` puts a `Window` in a list. Task 1.
- `Widget_impl.snapshot` is 17 getter calls per widget creation and grows with every
  widget-wide attr; the shape to reach for is lazy per-field capture on first `Set`, not a
  per-kind table. Task 2.
- The `page` helper is duplicated across the Task 5 live tests.

## ocgtk fork
- Six upstream PRs are open as **drafts** (#173–#178, `docs/upstream/README.md`) pending
  maintainer-side review; topic branches are pushed. Once merged upstream, rebase
  `bonsai-gtk`, re-run `nix build .#ocgtk`, move the pin.
- ocgtk's commit 2 hand-patches stubs commit 3's generator now emits; upstream may prefer
  regeneration (said in the PR text).
- The OxCaml `caml_alloc_custom_dep` branch of the GBytes accounting is only exercised in
  the opam switch, not in the stock-OCaml Nix build.
- `Widget.set_name : t -> string option -> unit` (see "Do first in M2") is the one new
  binding M1 wants from the fork.
