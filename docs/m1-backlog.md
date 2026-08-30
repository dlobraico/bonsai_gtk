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

## Closed by the final-review fix wave (`m1`, after `886b1d5`)
The four area reports are in `.superpowers/sdd/2026-08-29-bonsai-gtk-m1/final-*-report.md`
and the per-finding ledger in `fix-wave-report.md` beside them.
- **A `Driver.frame` that raises marks the driver broken and drops the pass's fixups**,
  whoever drove it — the promise `driver.mli` already made for hand-driven frames.
  Core #1.
- **Duplicate sibling keys are rejected at mount as well as at patch, with the node path.**
  Core #2 / containers I1.
- **A subtree gives up its stack names before it is replaced**, so wrapping a
  `Node.stack ~name:"nav"` in a `Node.frame` is no longer "two Node.stacks are named
  "nav"". Core #3.
- **`Signals.spec.connect` returns the object it connected to**, and teardown disconnects
  from that object. Core #4.
- **A programmatic write to a `Node.search_entry` no longer comes back as a search.**
  Controls #1.
- **`dune build -p <pkg> @runtest` works for both packages**; `test/handle/` is the
  `bonsai_gtk_test`-owned test directory, and `scripts/ci.sh` runs both `-p` builds.
  Tests I1.
- **The coverage sweep**: the nine never-patched kinds, switcher/sidebar retargeting, a
  rename onto a free name, add-and-select in one pass, head-of-list placement, a
  non-window root, `frame` on a stopped driver, css classes added and removed,
  `Attr.margin`, and the decline-the-edit test over all three entry kinds. Tests I3–I9,
  M7.
- **`Live_tree.dump` no longer segfaults on a password entry with no placeholder** — it
  reads the placeholder through a GValue rather than through ocgtk's non-nullable getter.
  Found by the coverage sweep.
- **Round 2** (`fix-wave-review.md`): `live_containers.ml`'s `wrapped` test now keys the
  stack and the frame that wraps it, so the reconciler emits an `Update` with a differing
  kind and the test actually enters `patch`'s kind-change arm — it was passing with
  `drop_stack_names` disabled (review Important 1). With it, four comments the wave itself
  got wrong were corrected in place rather than deferred: `w_search_entry.ml`'s
  one-write-one-timeout claim (review Minor 1), `live_controls.ml`'s "eight in all" against
  an accepted `7` (Minor 2), spec §6.4's run-together paragraph (Minor 5) and §6.5's
  "returns `None` while" (Minor 6), plus the raise `Bonsai_gtk_test`'s actions inherited
  from `find_by_test_id` (Minor 7).
- Neighbouring one-liners: `Scheduler.with_patch_guard` saves and restores `in_patch`;
  `Driver.schedule_event` guards `stopped`; `Driver.stop` drops the fixup queue;
  `Node.find_by_test_id` raises on a duplicate id naming both paths; `ci.sh`'s example
  smoke builds before it times the run; `examples/gallery.ml` stops writing a fresh temp
  file per run. Core Minors 1/3/4, tests M4/M5/M6.

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
- **A same-frame stack name *swap* still raises** (`src/patcher.ml`, `note_interest`'s
  rename arm): two stacks exchanging names in one frame gives `two Node.stacks are named
  "b" in one tree`, because the arm does `Hashtbl.remove old; register_stack new` per child
  left to right and the second stack still holds the new name. This replaces the
  "same-frame reuse or swap" item the fix wave deleted: the *reuse* half of that item
  (remove the stack named `"nav"`, insert a different one with that name) was never broken
  — the reconciler emits removes first — and the *swap* half still is. Loud, not
  corrupting. `fix-wave-review.md` Minor 3.
- **A vtree-level `Kind.t -> Attr.Name.t list` event table**, so `Bonsai_gtk_test` can
  reject the event attrs `Signals.require_specs` rejects at mount instead of certifying an
  app the runtime will refuse. The table is pure data; the constraint that `test_lib`
  cannot depend on ocgtk is what keeps it out of `src/`. Final review, tests I2.
- **`Kind.entry_props` has no `max_length`** — absent from spec §7's signature too, so
  never-scoped rather than dropped, but `GtkEntry:max-length` is the usual companion to a
  controlled `text`. Final review, controls out-of-scope.
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

## Carried out of the final review (Minor, unfixed)
Each cites the area report in `.superpowers/sdd/2026-08-29-bonsai-gtk-m1/`.

Diagnostics and contracts:
- **A `Node.stack ~visible_child` naming a page that never exists is silently inert
  forever** (`src/widgets/w_stack.ml`) — right for a page that arrives later, wrong for a
  typo, and every page's key is available at patch time. Same family as the
  `Attr.grid_cell`/`Attr.page_title` item above. core Minor 2.
- **Two grid children in one cell have no diagnostic** (`src/widgets/w_grid.ml`) —
  overlapping spans are attached silently and painted on top of each other; detecting it
  needs a per-patch occupancy set. containers M4.
- **`Native_gtk.S.destroy`'s doc does not mention that a replacement's `create` runs
  first** (`src/native_gtk.mli`), which spec §6.6 now says and the mli does not.
  core Minor 6.
- **`patch_children`'s catch-all message conflates two bugs** (`src/patcher.ml`): "the
  node's children shape changed under an unchanged kind" and "the impl's `child_ops`
  disagrees with both", the second a registry bug and unreachable today. core Minor 7.
- **`W_spin_button` rejects `Attr.on_changed`** even though `GtkSpinButton` implements
  `GtkEditable` — a defensible line, undocumented in `Node.spin_button`, and the rejection
  reads as a bug to whoever tries it. controls out-of-scope.
- **The spin button's `reassert` compares the committed value, not what the user is
  looking at** (`src/widgets/w_spin_button.ml`): while an edit is uncommitted the widget
  displays something the adjustment does not hold, so nothing is written. GTK's editing
  model rather than a defect — but `Node.spin_button`'s doc says "the value the widget
  currently holds", which a reader takes to mean what is on screen. controls Minor 8.

Behaviour:
- **A search-entry write that empties the box leaves its echo record unconsumed**
  (`src/widgets/w_search_entry.ml`). GTK emits `search-changed` synchronously, cancelling
  the timeout, when the text becomes empty; inside a patch `Signals.dispatch` drops that on
  `in_patch` before `fire` can consume the record, so a `""` record survives to be matched
  against a later emission. Benign in M1 — the model also holds `""` then, so what is lost
  is a duplicate rather than a search, and the first non-empty emission flushes it — but
  the one-record-one-emission invariant does not hold, and M2's headless `Search_changed`
  action or anything that iterates the main loop mid-patch changes that. The impl comments
  now describe the real behaviour. `fix-wave-review.md` Minor 1.
- **One failing fixup drops the rest of the pass's fixups** (`src/patcher.ml`,
  `run_fixups`): the `Exn.protect ~finally` clears the queue behind the raise, so a second
  stack's selection silently never runs. Bounded, because the frame is the last one.
  containers M2.
- **`ctx.stacks` keeps registrations from a subtree whose mount raised** — extends the
  "mount is not exception-safe" item below, which only mentions the undestroyed widget.
  containers M3. The mirror image is now reachable too: `drop_stack_names` runs *before*
  the mount in `patch`'s kind-change arm, so a mount that raises there leaves the old
  subtree alive with its names already given up. Bounded either way, since the frame is
  broken. `fix-wave-review.md` Minor 4.
- **An overlay child whose *kind* changes jumps to the top of the z-order**
  (`src/patcher.ml`'s kind-change arm is remove-then-insert, and `add_overlay` appends) —
  distinct from the known "`Overlay` `move` is a no-op", which is about a reorder in the
  node list. containers M5.
- **Dropping `Attr.page_title` leaves a blank, clickable switcher button**
  (`src/widgets/w_stack.ml` writes `""`, and `""` is not GTK's "no title" for a switcher
  or a sidebar). Needs a nullable `Stack_page.set_title` in the fork. containers M1.
- **`w_switch`'s `reassert` cannot see a `state`/`active` divergence** — latent, since M1
  never connects `state-set`. controls Minor 10.

Consistency:
- **`apply_button_props` writes an empty label on the toggle-button create path** while
  its `Button` sibling deliberately does not, so `Node.toggle_button ~active:false ()`
  carries an empty `GtkLabel` and a `text-button` class that `Node.button ()` does not.
  controls Minor 2.
- **A dropped placeholder builds the empty label `create` avoids** — `create` uses
  `Option.iter`, `update` passes the option straight through, so
  `~placeholder:"x"` → no placeholder is not the same live widget as a fresh one.
  `Live_tree.dump` collapses it, so no golden can catch it. controls Minor 3.
- **`w_entry.ml`'s shared-machinery comment overclaims**: only `text` and `changed` are
  actually shared, and `editable`/`width_chars`/`max_width_chars`/`xalign` are on
  `Node.entry` alone though all three kinds implement `GtkEditable`. controls Minor 5.
- **`Paintable_picture.apply` writes three props outside `Widget_impl.batch`**, and
  re-sets the paintable whenever either of the other two changed. It is the file the docs
  point at as the worked example, so it should model the convention. controls Minor 6.
- **`Native.Picture` has no `alternative_text`** although `Node.picture` does, and an
  app-rendered surface is the one GTK can infer nothing about. controls Minor 7.
- **Three conventions for writing a default-valued prop at `create`** — `W_image` uses two
  of them in adjacent lines. controls Minor 9.
- **`w_frame.create` and `w_center_box.update` write outside `Widget_impl.batch`** (one
  property each, so consistency rather than cost). containers M6.

Tests:
- **`examples/gallery.ml` writes its sample PNG to a fixed path in `$TMPDIR`**, so
  `Out_channel.write_all` follows whatever is already there, where `Filename.temp_file`
  created with `O_EXCL`. Example-only, and the fixed name is what stops the per-run litter
  (nothing can remove the file: GTK holds the path and the process ends on a window close
  or a signal), but the previous code was safer in that one respect.
  `fix-wave-review.md` Minor 8.
- **`Attr.Name.is_event` is tested on 2 of 32 names**, and 7 of the 10 event attrs have no
  negative `require_specs` test. The mechanism is covered; the *classification* is not, and
  adding an `On_foo` to the `false` branch compiles. A table over `Attr.Name.all` would pin
  it. tests M1.
- **Three expect tests pass props the sexp then drops** (`test/test_widgets.ml`'s
  `~content_fit:Contain`, `~can_shrink:true`, `~vpolicy:Automatic`, `~step:1.` are all
  defaults, erased by `[@sexp_drop_if]`), so they look like coverage and are not.
  tests M2.
- **`test/handle/test_gallery.ml`'s "exactly once" comment is inaccurate** — `Node.button`
  appears three times. The substance ("at least once", all 29) holds. tests M3.

## API shape decisions before they become breaking
- `Bonsai_gtk_test.Action.t` is a public variant with the same exhaustive-match exposure as
  `Attr.t`; M1 took it from one constructor to five.
- `Expert.Driver.root_widget : Widget.t option` cannot survive `Node.windows` (M3).
- `start ?flags` (spec §4.1) is unimplemented; `NON_UNIQUE` is needed for two instances.
- No `close-request` on `Node.window`. Absent from the spec, the M1 plan and `Attr.t`, so
  not an M1 omission — but with no handler a model can neither veto nor observe a window
  close, which is exactly the frame in which M3's `Node.windows` has to reconcile
  multi-window state. Final review, containers out-of-scope.
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
- `Bonsai_gtk_vtree.Placement`'s granularity is the parent's *kind*, not its slot, so
  `Attr.measure_overlay` on a `Node.overlay`'s **main** child is accepted and stays inert
  (only the `~overlays` slot reads it). Tightening it means threading the slot name in
  beside the kind; worth doing when a slot container reads two different placement attrs
  on two different slots, and not before. M2 task-3 review, Minor 6.
- Nothing distinguishes `Driver.frame`'s phys-equal fast path from the slow one: replacing
  `phys_equal node live.Patcher.node` (`src/driver.ml`) with `false` leaves the whole suite
  green, because the two paths are behaviourally identical by design. Tolerable — the
  change's contract *is* "no observable difference" — but it leaves the optimisation
  unpinned, so a refactor that made the guard unreachable would be invisible. M2 task-2
  review, Minor 1.
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
- GTK 4.22 leaves `gtk_root_get_focus` pointing into a widget across an unparent and a
  re-parent, so the save/restore in `w_grid.ml`'s `updated` hook is insurance rather than a
  repair, and `test/live/live_containers.ml`'s focus assertion passes without it. It pins
  the behaviour on whichever GTK the tests run against. Final review, containers I2.

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
- **Nullable string bindings M1 wants**, all of them cases where the C API takes or
  returns NULL and the generator emitted `string`:
  - `Widget.set_name : t -> string option -> unit` (see "Do first in M2"), so
    `Unset Widget_name` can write NULL back instead of `""`.
  - `Password_entry.get_placeholder_text : t -> string option`. The current binding is a
    **crash**, not a wrong value: `gtk_password_entry_get_placeholder_text` returns NULL
    when unset and the stub copies it. `Live_tree.dump` works around it by reading the
    property through a GValue, whose stub maps NULL to `""`. controls Minor 4.
  - `Password_entry.set_placeholder_text : t -> string option -> unit`, so the three
    entries can share one rule instead of the update path forcing `""`. controls Minor 4.
  - `Stack_page.set_title : t -> string option -> unit`, so a page that loses its
    `Attr.page_title` gets no switcher button rather than a blank clickable one.
    containers M1.
