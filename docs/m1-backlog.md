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
- **No synthetic click or key press exists in the pinned ocgtk binding, so no test
  anywhere delivers one.** There is no `GdkEvent` constructor for any event subtype
  (checked every `*event*.mli` under `gdk/generated/` for `new_`/`alloc`);
  `Gobject.Signal.emit_by_name` and `.notify` take no arguments and return unit, so
  neither can carry a click's `~n_press ~x ~y` or a key press's `~keyval ~keycode
  ~state`; and `Event_controller_key.forward` only re-routes an event a controller is
  already processing. What is covered instead, and what the gap therefore is:
  - the *plumbing* — that `Attr.on_click` attaches a `GtkGestureClick` with the right
    `button` and `phase`, that dropping the attr removes it, that GTK and this library
    agree on what is attached — is `test/live/live_controllers.ml`, counting by the
    debugging name `Controllers` sets on each controller;
  - the same *plumbing* for keys — that `Attr.on_key_pressed`/`on_key_released` attach one
    shared `GtkEventControllerKey`, that it carries the `phase` the attrs asked for (read
    back off the live controller), that dropping one attr empties one slot while dropping
    both removes the controller, and that two attrs asking for different phases are
    rejected at mount and at patch — is `test/live/live_controllers.ml` too. `armed=` on
    every line is what distinguishes an attached controller from one that would actually
    call a handler, which is otherwise unobservable for an event nothing can deliver;
  - the *handler* — that a middle click with shift reaches the application's closure with
    the right `Click_event.t`, and that a key handler consumes Escape and lets `x` through
    — is `test/handle/test_handle.ml`, headlessly, through
    `Bonsai_gtk_test.Action.{Click_at,Key_press,Key_release}`. `Key_press` prints the
    `Key_response.t` the handler answered, because that half of a key press is a value
    GTK reads synchronously and there is no GTK headless;
  - the *trampoline* between them — slots, the `in_patch` guard, the exception guard, and
    the value `Payload` hands back to GTK on each of those three paths — is
    `test/live/live_signals.ml`, which calls the callback `Signals.connect_all` built
    rather than emitting through GTK; and the key spec's own mapping from
    `Key_response.t` to that value is `Controllers.key_pressed_answer`, called directly in
    `live_controllers.ml` over all four constructors.
  - **Not covered:** that GTK actually routes a real button press, or a real keystroke, to
    the controller this library attached — and, for keys specifically, **that propagation
    works**: neither suite can show that a `Handled` Escape failed to reach a sibling, or
    that a `Capture`-phase controller saw the key before a child's `Bubble`-phase one. The
    routing is GTK's, and every input to it is asserted; the routing itself is not.
    Compensating controls: the gallery's Input section, and the real-display click-through
    below. Closing it properly needs an ocgtk fork patch exposing a `GdkEvent` constructor
    or `gtk_test_widget_click`/`gtk_test_widget_send_key` (none is bound today). Tasks 4
    and 5.
- Focus is the exception and *is* covered end to end: `Widget.grab_focus` on a presented
  window really drives `GtkEventControllerFocus`, and `live_controllers.ml` asserts the
  handler fires, that the reentrancy guard drops a focus change made during a patch, and
  that a removed controller stops firing. Task 4.
- GC/lifetime: remove a keyed child, `Gc.full_major`, assert the widget was finalized —
  the spec's central ownership assumption, still unwritten (carried from M0).
- After-display spin regression (needs a frame counter under `Private`) — carried from M0.
- `Driver.schedule_event`'s broken guard is exercised but not asserted: nothing public
  observes the Bonsai action queue's length. Task 1.
- Real-display click-through of `examples/gallery.exe` — it has only ever been run under
  `xvfb`. Task 10. This is now also the compensating control for the missing synthetic
  click *and* key press above, so it should exercise a widget carrying `Attr.on_click` and
  one carrying `Attr.on_key_pressed` — the latter in `Capture` phase with a focusable
  child below it, since a wrong phase is the failure mode a plumbing test cannot see.
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
- **`gtk_list_box_get_selected_rows`'s stub is missing `g_object_ref_sink`** — a
  memory-safety defect, not a convenience one, and the most valuable of the fork patches
  M2 has found. `ml_list_box_gen.c:229-238` does
  `Val_GList_with(…, Val_GtkListBoxRow((gpointer)_tmp->data))` with no sink, while the
  method is `transfer-ownership="container"` (`gir/Gtk-4.0.gir:89573`): the `GList` is the
  caller's to free, the rows in it are borrowed. `ml_gobject_val_of_ext`'s contract
  (`ml_gobject.c:373-388`) is that the caller must sink a transfer-none pointer first,
  "since the wrapper's finalizer unconditionally `g_object_unref`s on GC" — so every call
  hands out one unbalanced unref per selected row, and a few of them dispose a
  still-parented row: the selection silently empties, GTK logs "has a parent GtkListBox
  during dispose", and the process segfaults shortly after. Reproduced in ten idle frames
  plus one major collection (task-6 review C1).

  **The fork already carries the identical fix for the twin**: `ml_flow_box_gen.c:222-233`
  sinks each `GtkFlowBoxChild` and its comment describes exactly this bug. The `GtkListBox`
  one was simply not reached. `W_list_box.selected_keys` works around it by walking
  `get_row_at_index` + `is_selected` (both correctly sinking), and `w_list_box.ml` says
  nothing in this library may call `get_selected_rows` until the patch lands.

  **The real fix belongs in the generator.** `grep -n 'Val_GList_with\|Val_GSList_with'`
  over the generated stubs finds **47 sites, of which exactly one** — the hand-patched
  FlowBox one — sinks its elements; the other 46 are the same shape and the same latent
  bug. Nothing else in
  this library uses one today (checked: our only other GObject enumeration is
  `Widget.observe_controllers`, which returns a transfer-full `GListModel` and whose
  `get_object` is transfer-full too, so both are balanced) — but Task 7's `FlowBox` and
  anything reaching for `Gesture.get_sequences`, `Widget.list_mnemonic_labels` or
  `TreeView.get_columns` walks straight into it. Generator fix > four hand patches.
- **No transfer-full string return is freed anywhere in the generated stubs** — a memory
  leak in every one of them, and the one M2 actually walks into is
  `gtk_text_buffer_get_text`. `ml_text_buffer_gen.c:243-249` does
  `char* result = gtk_text_buffer_get_text (...); CAMLreturn (caml_copy_string (result));`
  with no `g_free (result)`, while the method is `transfer-ownership="full"`: the caller
  owns the string. Reproduced (task-9): 200 whole-buffer reads of a 1 MB `GtkTextBuffer`
  grow RSS by 201 MB, and a `Gc.full_major` reclaims none of it — the OCaml copy is
  collected, the C original is not. `gtk_text_buffer_get_slice`, `gtk_text_iter_get_text`
  and `gtk_text_iter_get_slice` are the same shape, so there is **no** way to read a text
  buffer through the pinned binding without leaking it.

  **The generator already knows how to do this** — it emits `g_free (result)` after
  copying a transfer-full *array* (`ml_text_child_anchor_gen.c:63`,
  `ml_widget_gen.c:1160`, and 40-odd more) — so the miss is specifically the
  single-`char*` return path. `grep -n 'char\* result = ' ml_*.c` finds every site;
  none of them frees. Generator fix, like the `Val_GList_with` one above, not a hand
  patch.

  `w_text_view.ml` works around it on the frame path only: it caches what it last wrote
  and invalidates the cache from `GtkTextBuffer::changed`, so an *idle* frame reads
  nothing at all. Without that, a megabyte of notes open on screen would leak a megabyte a
  frame — 60 MB/s with the application doing nothing, which is the load-bearing half.

  **It does not fix the edit path, and cannot.** Every `changed` that reaches an armed
  slot outside a patch runs `fire` → a whole-buffer read, because `Attr.on_changed`'s
  contract is to hand the handler the buffer's full text. So each keystroke in a 1 MB
  document costs 0.42 ms and leaks 1 MB, and sustained typing leaks several MB a second.
  That is the number to weigh when deciding how urgent the generator patch is; it is worse
  than the idle-frame figure suggests, not better. `Live_tree.dump`'s `GtkTextView` arm
  reads the buffer too, and is a test-only path.
- **`g_object_ref_sink` on a constructor's return leaks the object, once per call** — the
  mirror image of the `get_selected_rows` defect above, and Task 10 walked into it.
  `ml_gtk_string_list_new` (`ml_string_list_gen.c`) ends
  `GtkStringList *obj = gtk_string_list_new (c_arg1); if (obj) g_object_ref_sink (obj);`,
  which is right for every *widget* constructor beside it and wrong here: `GtkStringList`
  descends from `GObject`, not `GInitiallyUnowned`, so it is never floating and
  `g_object_ref_sink` degenerates to `g_object_ref`. The constructor already transferred
  ownership, so the wrapper holds two references and its finaliser drops one. Measured:
  `Gobject.get_ref_count` on a fresh `String_list.new_` is **2**, and
  `test/live/live_text.ml` prints it, so the fix shows up in that golden when it lands.

  `w_drop_down.ml` rebuilds its model with `String_list.new_`, so an application leaks one
  `GtkStringList` (and the strings it owns) per *items change* — never per frame, which is
  what keeps this a leak rather than a crisis. The create path avoids it by going through
  `Drop_down.new_from_strings`, which builds the model inside GTK.

  **Generator fix, not a hand patch**: the rule is `ref_sink` iff the type is
  `GInitiallyUnowned` *or* the transfer is none/floating, and the generator currently
  applies it to every constructor. `GtkStringObject`, `GtkStringFilter`, `GtkStringSorter`,
  every `GListStore`-shaped class and every non-widget `*_new` in the tree is the same
  shape. Worth doing beside the `Val_GList_with` sweep, which is the same audit from the
  other end.
- **`gtk_drop_down_get_selected_item`'s stub is broken twice over** and is unusable.
  `ml_drop_down_gen.c` ends `CAMLreturn (ml_gobject_val_of_ext (result));` while the `.mli`
  declares `t -> [ \`object_ ] Gobject.obj option`. So (a) the transfer-none return is
  never sunk — the `get_selected_rows` bug again, one unbalanced unref per call — and
  (b) the value returned is a bare custom block where OCaml expects an `option`, which
  reads as `Some` with the raw pointer word as its payload; a NULL return calls
  `caml_failwith` rather than answering `None`. The `_option` variant
  (`ml_gobject_val_of_ext_option`) exists two functions away in `wrappers.c` and is what
  the site wants, after a sink.

  Nothing in this library calls it: `w_drop_down.ml` and `Live_tree` read the position with
  `get_selected` and the strings with `List_model.get_object` (transfer-full, correctly not
  sunk) plus `String_object.get_string` (transfer-none, correctly copied). Worth fixing
  because it is the *obvious* call for "what is selected", so the next person to want it
  will reach for it.
- **`gtk_drop_down_get_expression` answers `None` on a drop-down that has one**, and its
  stub `g_object_ref_sink`s a `GtkExpression`, which is not a `GObject` at all (it has its
  own `gtk_expression_ref`/`unref`). Measured: `Drop_down.new_from_strings` is documented
  to install a property expression, and `get_expression` on its result is `None` on GTK
  4.22 through this binding. Nothing here calls it, but it means the library cannot assert
  that `~enable_search:true` will actually filter — the expression is what the popup's
  filter reads, and this is the only way to see whether one is installed. Same audit as the
  two above.
- **Handler ids come from one global counter, not a per-instance one** (measured on this
  GLib: two handlers on two different `GtkTextBuffer`s and one on a `GtkTextView` got
  118/119/120). So `signals.mli`'s worse case for disconnecting a handler id from the
  wrong object — "at worst disconnects an unrelated handler that happens to share the
  number" — cannot happen here: the wrong disconnect logs
  `instance '0x...' has no handler with id 'N'` and leaves the real handler connected.
  Still a bug, and still the one `Signals.connection` exists to prevent; the doc's second
  clause is the theoretical half and should say so if it is ever rewritten.
- **Rule of thumb this established, for any new binding call that returns objects:** read
  the *stub*, not the GIR. A `Val_GList_with` site without `g_object_ref_sink`, or any
  `Val_*` wrapping a transfer-none pointer, is an unbalanced unref that GC turns into a
  use-after-free — and neither the type checker nor a short-lived test will show it,
  because nothing collects before exit. `test/live/live_lists.ml`'s first block is the
  shape of test that does: N frames, a `Gc.full_major`, and an assertion that the widgets
  are still there.
