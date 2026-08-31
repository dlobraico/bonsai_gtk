# Backlog carried out of M2

Items deferred by the M2 task reviews, their rulings, and whatever M1 left open that M2 did
not close. The ledger with every ruling is
`.superpowers/sdd/2026-08-30-bonsai-gtk-m2/progress.md`; per-task detail is in the
`task-N-report.md` and `task-N-review.md` files beside it. Nothing here blocks M2.

The file is renamed this time. M1 kept `m1-backlog.md` on purpose — "a rename churns links
for nothing" — but two milestones in, a file called `m1-backlog.md` describing M2's
leftovers is a trap, so this is `m2-backlog.md`. The rewrite was total
enough that rename detection does not fire (9% similarity), so `git log --follow` will not
reach back past it: the M1 history is under the old path, `docs/m1-backlog.md`.

## Closed during M2 (was "do first in M2")

All thirteen, in the tasks the plan put them in — plus one the final review's fix wave took:

- **`entry`/`search_entry`/`password_entry` now refuse a NUL, the way `text_view` and
  `editable_label` do.** They validated nothing: `gtk_editable_set_text` takes a
  NUL-terminated string, so a NUL in `~text` truncated silently, the read-back never equalled
  the model, and the widget was rewritten on *every* idle frame for the life of the tree with
  nothing on stderr — measured at 1.18 ms per idle frame against 0.00019 ms parked, 5300×, on
  a 100 000-character text. On a search entry each of those writes re-armed the debounce, so
  `Attr.on_search_changed` never fired at all. The refusal lives in
  `W_entry.set_text_if_needed`, the one function all four `GtkEditable` widgets write their
  text through, so it is one rule rather than three more. The counter-argument on record —
  "three more per-widget caches are a cost" — was an artefact of the copying: the four
  hand-copied refuse-record-report mechanisms became one `Refusal` functor in the same
  change, and the number of caches went from four to four rather than to seven. Final review,
  controls I2 + recommendation; task-16 review I1.

- **Seal `Attr.t`** — the constructors moved to `Attr.Private` and `Attr.t` is
  `private Private.t`, so an application can neither build one from a raw constructor nor
  match on one without spelling the coercion. Task 1 (`09ee6f7`, made compiler-enforced in
  `1daa1b5`: the plan's alias spelling does not typecheck). `Attr.Name.t` stays concrete,
  deliberately — see "API shape decisions" below.
- **A vtree-level `Kind.t -> Attr.Name.t list` event table** (`vtree/events.ml`), so
  `Bonsai_gtk_test` rejects the event attrs `Signals.require_specs` rejects at mount instead
  of certifying a tree the runtime refuses. Task 1 (`09ee6f7`).
- **A headless `Search_changed` action, and one for an expander** — `Action.Search_changed`
  and `Action.Set_expanded`. Task 1 (`09ee6f7`).
- **`Overlay`/`Stack`/`Grid` `move` is a no-op** → an explicit unordered marker.
  `Widget_impl.list_ops.move` is an `option`; `None` means "no reorder primitive" and
  `Reconcile.diff ~ordered:false` emits no `Move` at all rather than one that is dropped. A
  `Move` reaching a container without `move` is `Invalid_argument`, because a dropped one
  desynchronises the patcher's child list from GTK's. Task 2 (`ee64cc6`).
- **A reassert-and-fixup-only walk for phys-equal roots** — `Patcher.reassert_only`, taken by
  `Driver.frame` whenever Bonsai hands back the physically same node. Task 2 (`ee64cc6`).
- **Per-`reassert` `batch` cost** — `Widget_impl.batch_if`, so a `reassert` that writes
  nothing pays no freeze/thaw. Measured at ~80 ns per `batch` call, which is what kept the
  conditional rather than removing the bracket. Task 2 (`ee64cc6`).
- **`w_switch`'s `create` hand-rolled the active write** — it routes through `reassert` like
  every other controlled kind. Task 2 (`ee64cc6`).
- **`Signals.spec.fire` reads state back off the widget** → the existential-event version.
  `spec` is now a variant: `Read_back` is the M1 shape, `Payload : ('p, 'r) payload -> spec`
  carries the signal's own arguments *and* a return value handed back to GTK. Task 4
  (`9c081e5`) rather than Tasks 1–3 — `ListBox::row-activated` was the forcing case, and it
  arrives with the container.
- **`min > max` content bounds on `Node.scrolled_window`** are rejected at the constructor.
  Task 3 (`b458449`).
- **`Attr.grid_cell` and `Attr.page_title` are silently inert outside their container** —
  now `Invalid_argument` naming the container that *does* read the attr, from a table in
  `vtree/placement.ml` that both the patcher and the headless handle read. Task 3
  (`b458449`, moved to `vtree` in `a9b7b34`).
- **A same-frame stack name *swap* still raises** — fixed by pass-level give-ups-then-takes.
  Task 3 (`b458449`).
- **`Kind.entry_props` has no `max_length`** — it has one, and `w_entry`'s `reassert`
  compares against the truncated text (in characters) so that truncation does not cause a
  per-frame write. Task 3 (`b458449`).
- **ocgtk fork: `Widget.set_name : t -> string option -> unit`** — landed with the other two
  nullable bindings on the fork's `m2-bindings` branch and pinned. Task 14; pin bumped to
  `649498b4` in `3a87d1c`. (The *behavioural* half is not taken — see "Do first in M3".)

## Closed during M2 from the M1 final-review carries

- **A `Node.stack ~visible_child` naming a page that never exists is silently inert
  forever** — now `Invalid_argument` from the fixup pass, listing the pages the stack does
  have, with a carve-out for an empty stack (a model rendering no pages has no name it could
  pass that would be right). Task 3 (`b458449`).
- **`Attr.Name.is_event` is tested on 2 of 32 names** — `test/test_events.ml` now partitions
  `Attr.Name.all` and pins both halves, and a second test checks the partition against
  `Events.for_kind` and `Events.controller_family`. Task 1 (`09ee6f7`).
- **`mount` is not exception-safe** — `Patcher.mount` tears down what it built and re-raises.
  It was not "bounded", as the M1 entry assumed: every signal a partial mount had connected
  rooted a closure holding the runtime, which held the shadow tree, which held GObject
  references back, so one connected handler in a failed mount retained the whole driver and
  its Bonsai graph permanently (~50k live words per failure, measured). Task 12 (`629185c`).
- **`Bonsai_gtk_test` has no validating `recompute_view`** — `Handle` is a hand-written
  signature shadowing all three entry points that skipped the checks. The first run found a
  call site certifying a tree the runtime refuses. Task 13 (`e7a1e7e`).
- **`test/handle/test_gallery.ml`'s "exactly once" comment is inaccurate** — the claim is now
  checked against `Kind.Variants.descriptions` and `Attr.Name.all` rather than asserted in
  prose. Task 13 (`c5fb8a2`).

## Do first in M3

- **`Attr.on_click` cannot claim the event sequence.** The gesture deliberately does not, so
  a click on a card also reaches its list box's click-to-select — but an application that
  wants to *consume* one has no way to say so. Tasks 4–5.
- **`Attr.on_focus_enter`/`on_focus_leave` are events, not the `contains_focus` query**
  stavekeeper polls. An app that needs the bit keeps it in its own model. Task 4.
- **The focus attrs take no `?phase`**, while `on_click`, `on_key_pressed` and
  `on_key_released` all do. Visibly asymmetric in a sexp golden
  (`test/handle/test_handle.ml` prints `(On_focus_leave <handler>)` beside
  `(On_key_pressed (phase Bubble) …)`), and adding one would let
  `Events.key_phase_rejection` generalise into a `family_phase_rejection`. Tasks 4–5.
- **`TextView` exposes no cursor position.** The controlled write preserves the caret as a
  character offset — exact for an in-place rewrite, approximate for one that changes length
  before the caret. `notify::cursor-position` is the hook for an application that wants to
  own the caret, and it is what closes the stated approximation. Task 9.
- **`Bonsai_gtk_test.Key_press` cannot model propagation**, and neither can anything else
  here: there is no widget hierarchy in the handle for an event to travel through, and the
  live suite cannot synthesise a press at all. See "Tests worth adding". Tasks 4–5.
- **The `Keyval` table is curated, not complete** — seventeen names plus `Keyval.f` and
  `Keyval.of_char`; anything else is a raw `int`. Task 5.
- **No live test delivers a synthetic click or key press.** Task 4 landed on option (c) —
  plumbing only — and this is the biggest untested surface in the milestone. It has its own
  entry under "Tests worth adding", with what *is* covered and what the two closing routes
  are.
- **`Child_keys` is one ephemeron table per module and is never compacted**: an entry is
  removed on `remove` and otherwise waits for the GC. Correct — the table is keyed on the
  child widget the patcher retains, which is the invariant `child_keys.mli` states and Tasks
  7–8 inherited — but nothing measures it, and `child_keys.mli` exposes no size accessor, so
  `forget_children`/`forget_rows` are also unpinned (task-7 review M4: replacing the
  `Flow_box` arm of `Patcher.destroy` with `| Flow_box _ -> ()` leaves the goldens
  byte-identical, verified). A `Child_keys.length` exposed for tests plus one live case per
  container closes both, and should be done for all three containers at once.
- **`after_of` is still `O(index)` and the `cur` bookkeeping `O(n)` per op, so a list patch
  is `O(n·ops)`.** M1 predicted "M2's `ListBox` is what will feel it". **It did not** — what
  bit instead was `apply_selection`, which was `O(|selected| × rows)` per frame and cost
  **24 ms per idle frame at 200-selected-of-1000**; a per-call key→child map took it to
  **0.39 ms**, in both `w_list_box.ml` and `w_flow_box.ml`, with a live bench regression
  (task-6 M6 → task-7 I1, `e9e7793`). The reconciler's own `O(n·ops)` was never the term
  that showed up in a measurement. Recorded so M3 spends the next optimisation where the
  numbers are rather than where the prediction was.
- **A hidden `~current_page` diverges forever with no diagnostic** (`w_notebook.ml`'s select
  fixup): a page carrying `Attr.visible false` that is also `~current_page` makes the fixup
  write on every frame, forever, with no error. Same shape as a `~selected` a list box's
  selection mode cannot hold. Both are "a model to bring into line", both are candidates for
  the `Patcher.ctx.report` hook Task 9 built, and whichever task gives it to them should
  measure their parked frames at the same time. Tasks 8–10.
  **`w_stack.ml`'s select fixup has the identical hole** (final review, containers I3), for a
  different GTK reason: `gtk_stack_set_visible_child_full` ends with
  `if (gtk_widget_get_visible (child_info->widget)) set_visible_child (...)` —
  gtkstack.c:2308-2310, no `else`, no warning — so a `~visible_child` naming a page that
  carries `Attr.visible false` resolves, writes, does nothing, and is written again on every
  frame. The fix wave took the documentation half (both constructors and both impls now say
  it); the report-once half is this item, and the stack and the notebook should get it
  together, since it is one memo shape serving both.
- **A duplicate key in `~selected` writes on every frame** (final review, containers N4).
  `~selected:["a"; "a"]` with `a` present gives `current = ["a"]` and `wanted = ["a"; "a"]`
  in both `w_list_box.ml` and `w_flow_box.ml`, which never compare equal, so every frame runs
  `unselect_all` plus a redundant `select_row`, forever, with no diagnostic. Unlike the mode
  case this is a pure model typo, and the fix is one `List.dedup_and_sort` in
  `apply_selection`. Left out of the fix wave deliberately: it is a behaviour change on the
  selection path that the controller's rulings did not cover, and it wants deciding together
  with the item above — dedupe silently, or report once like everything else in M2 that
  cannot be held.
- **`w_list_box.ml` and `w_flow_box.ml` are two copies of one container.** M2 declined to
  functorise them (task-7 deviation 8, and the reviewer agreed) on the grounds that no fix
  had had to be made twice — and then I1 was made twice in the same round. The standing
  trigger the review left: if M3 produces a third, that is the evidence the header comment
  says would settle it.
- **The behavioural half of the fork's three nullable bindings is not taken.** The pin now
  has them, and the library still writes `Some`: `Unset Widget_name` writes
  `Some d.widget_name` rather than `None`, `w_stack.ml` writes `Some ""` for a dropped
  `Attr.page_title` (so it still leaves a blank clickable switcher button — the
  containers-M1 item the binding existed to close), and `w_password_entry.ml` still forces
  `""`. Task 14 scoped itself to the fork and left these deliberately: they are behaviour
  changes to M2 code with goldens attached. The password-entry one has no visible effect
  (GTK normalises the NULL back to `""` once the internal `GtkText` exists, measured on
  4.22). `Attr.widget_name`'s doc no longer blames the binding — the fix wave corrected it
  to say the caveat is now a deliberate choice — so what is left here is only the
  behavioural change itself.
- **`Patcher.require_slots` is not called on the patch path** (`src/patcher.ml`; the mount
  call is its only one, while `require_specs` has two). If a widget impl drifted so that
  `Events.for_kind` lists an attr the impl declares no spec for, and an app adds that attr
  conditionally on frame 2, mount's check passed, patch's `require_specs` consults the table
  and passes, `update_slots` never sees the orphan, and the handler silently never fires.
  Needs a pre-existing drift that `live_events.ml` catches in CI, hence Minor — but it is a
  one-line fix and the review named it "the one I would take before Task 4 lands the
  controller attrs". task-1 review Minor 8.
- **`Bonsai_gtk_test.Action.Activate_row` fires on a row carrying `Attr.row_activatable
  false`**, and `Activate_child`/`Set_page` follow it. It is one of six places where the
  headless handle certifies something the runtime will not do — this entry used to call it
  the only one, and `test_handle.ml` said the same of a different case; the six are now
  listed once, on `Bonsai_gtk_test.create`. The argument for this one was accepted: the
  harness models no event routing at all, and filtering this case would be the only routing
  it implements. Recorded because the decision should be revisited once, deliberately, for
  all three. `bonsai_gtk_test.mli` now carries the sentence. task-6 review M5; final review,
  headless I4.

## API shape decisions before they become breaking

- **`Bonsai_gtk_test.Action.t` is a public variant with nineteen constructors** — M1 took it
  from one to five, M2 from five to nineteen — with the same exhaustive-match exposure
  `Attr.t` had before it was sealed. Sealing it means the same `private` treatment.
- **`Key_response.t`, `Phase.t`, `Selection_mode.t`, `Wrap_mode.t`, `Tab_position.t`,
  `Level_bar_mode.t`, `Click_event.t`, `Key_event.t` and `Modifiers.t` are all public
  variants or records.** Most are GTK enums and will not grow; `Key_response.t` and
  `Click_event.t` are this library's own, and either could.
- **`Kind.t` derives `variants`**, which publishes a lowercase constructor function per kind
  plus the whole `Variants` module (`fold`, `iter`, `map`, `make_matcher`, `to_rank`,
  `to_name`, …) — about thirty names on the type every widget task extends, in the commit
  whose theme was narrowing. Only `Variants.descriptions` is wanted. Deriving in `kind.ml`
  and re-exporting `val descriptions` (or a `constructor_count`) is the shape.
  task-1 review Minor 9.
- **`Events.key_phase` is public and answers for a node `key_phase_rejection` rejects.** The
  mli says the disagreeing case is "a value no caller ever reaches", which is true of the two
  in-repo consumers but is a convention rather than a guarantee for a public `vtree` module.
  Noted because the surrounding code (`Placement`, `Attr.Private`) is otherwise careful to
  make wrong use unrepresentable rather than discouraged. task-5 review M5.
- **`Placement.is_read_by ~parent name` answers `true` for a name that is not a placement
  attr at all.** The mli says so and `misplaced` pre-filters, so nothing in the tree can be
  misled — but the name reads as a question about one attr and answers a different question
  over two-thirds of its domain. task-3 re-review.
- **`Controllers.key_pressed_answer` and `key_pressed_declined` are test-facing exports** that
  widen `controllers.mli`. They exist because no real key press can be delivered; they should
  go the day one can. Task 5.
- `Expert.Driver.root_widget : Widget.t option` cannot survive `Node.windows` (M3).
- `start ?flags` (spec §4.1) is unimplemented; `NON_UNIQUE` is needed for two instances.
- No `close-request` on `Node.window`. With no handler a model can neither veto nor observe a
  window close, which is exactly the frame in which M3's `Node.windows` has to reconcile
  multi-window state.
- `Kind.t`'s sexps are lossy — `sexp_of` only, with `[@sexp_drop_if]` dropping default-valued
  fields — so a `Node.t` sexp is a view for tests, not a serialisation.
- **`Node.editable_label` has no `~editable`, `~width_chars` or `~xalign`**, though all three
  exist on `GtkEditable` and `w_entry.ml` already writes them. A rename-in-place field will
  want at least `~width_chars`. task-11 carry 1.
- **`Node.flow_box` accepts `~min_children_per_line > ~max_children_per_line`** silently; the
  mli documents that the maximum wins. Ruled better than a check — recorded so it is not
  rediscovered as an omission. task-7 M2.
- **`W_spin_button` rejects `Attr.on_changed`** even though `GtkSpinButton` implements
  `GtkEditable` — defensible, undocumented in `Node.spin_button`, and it reads as a bug to
  whoever tries it. Carried from M1.

## Carried out of M2's task reviews (Minor, unfixed)

Each cites the review in `.superpowers/sdd/2026-08-30-bonsai-gtk-m2/`.

### Left by the final review's fix wave

The wave took every Critical and Important across the five lenses, and the Minors that were
a sentence or a line. These are the ones it deliberately did not take, with the reason.

- **`Events.family_attrs` rebuilds a 48-element filter on every call** (core M4), three times
  per patched node per frame, through `Controllers.wanted` — unconditionally, including for
  the great majority of nodes carrying no controller attr at all. That is ~144
  `controller_family` matches plus three list allocations per node per frame that can never
  answer anything but `false`. The identical derive-from-the-table idiom one file over,
  `Placement.names`, is a top-level `let` computed once. Not taken because it is unmeasured
  and the fix has two shapes worth choosing between with a number in hand (memoise over
  `Family.all`, or have `wanted` walk the node's 0–5 attrs and ask `controller_family`); the
  milestone's own lesson is that per-frame per-node walks are where the numbers have actually
  been, so measure first.
- **The placement seam has no drift check equivalent to the events seam's** (core M5). A new
  container kind copy-pasting a `read_by` arm would be accepted by `is_read_by`, contradicted
  by `reader`, missed by `test_placement.ml`'s hand-written six-element list, and its
  children's `Attr.grid_cell` silently inert; and nothing checks that a container which
  *declares* a placement attr actually applies it. A new *attr* is caught, because `reader` is
  exhaustive. Wants the same treatment `live_events.ml` gives the events table, which is a
  test to write rather than a line to change.
- **`Signals.spec`'s two arms differ in connection arity with no stated reason** (core M8):
  `Read_back.connect` returns a list (the calendar needs three connections for one attr) and
  `Payload.connect` returns one, and the mli justifies the first and never mentions the
  asymmetry. Nothing needs it today; it belongs beside the *API shape decisions* list, since
  it is the shape a future `Payload` needing two emissions would have to break.
- **`Controllers.update`'s `configure` raising leaves different states on its two paths**
  (core M9). The attach branch runs `configure` before `add_controller`, so a rejected node
  leaves nothing attached; the update branch runs it before `update_slots`, so a key-phase
  rejection on a *patch* leaves the controller attached, connected and with empty slots.
  Harmless — the frame is about to break the driver for good — and recorded because the
  comment that documents the first path reads as if it covered both.
- **`W_editable_label` is absent from `Bonsai_gtk.Private`** (core M10) while its three
  `ctx.report` siblings are exported. Less of an asymmetry after the wave than before: the
  label's refusal now lives in `W_entry`, which is not exported either, and no test needs
  either of them. Export whichever a test first wants, rather than both on principle.
- **A duplicate key in a `~selected` list** — see *Do first in M3*, where it sits with the
  hidden-page divergence it should be decided alongside.
- **`Kind.paned_props.position` is erased from every golden at its default** (headless M3):
  `[@sexp_drop_if Option.is_none]`, where `None` means "GTK decides", so a model that never
  computed a position and one that has no such field are indistinguishable in the sexp. Every
  other controlled prop deliberately carries no `sexp_drop_if`. The fix wave closed the other
  half of this — there is a `Set_position` action now, so the handler is reachable — and left
  the erasure, because removing the `sexp_drop_if` moves every paned golden in the repository
  for a gain that the action already largely delivers.
- **"props take part in `equal_props`" varies one field** (headless M5). Every `equal_*_props`
  is `[@@deriving equal]`, so per-field participation is the compiler's guarantee and those
  tests pin only that `equal_props`'s arm dispatches to the right derived function — which is
  worth having, but is not what the titles claim. Worth knowing because it is also what all
  four sweeps miss together: a hand-written `equal_props` arm ignoring a field is caught by
  nothing, and `Kind.t`'s `Native` arm (`phys_equal a.payload b.payload`) is exactly such an
  arm.
- **`bonsai_gtk_test.opam` over-declares `ppx_expect`** as a hard dependency while
  `test_lib/dune` preprocesses with `ppx_jane` only (headless M7). Defensible — consumers of a
  test handle write expect tests — and it is the one dependency in either opam file that no
  stanza needs. A `dune-project` change, so it wants doing when something else moves there.
- **The six-entry-point test exercises one of the three checks** (headless M9):
  `test_gallery.ml`'s regression proves all six entry points reach the validation using an
  `Events` violation only. Sound by construction today (all the checks share one call site),
  but the test calls itself the regression for the whole guarantee, and a refactor that moved
  one check out of that call site would not move this golden. A three-row table instead of six
  lines closes it.
- **`examples/gallery.ml` is a hand-maintained twin of `test/handle/test_gallery.ml`, and only
  the twin in `test/` is under the sweeps** (live M2). Coverage is identical today (36
  constructors in the example against 38 in the test, the extras being `Node.native` and the
  type name), and the example is a real compile-time drift net — it is built by `dune build
  @all` and by the smoke — but nothing keeps its *content* aligned, so a new M3 constructor
  turns the test red and says nothing about the example. Closing shape: a shared module, or a
  sweep over the example's own tree.
- **The one-display-in-parallel shape lives in the pin's own check phase too** (live M3):
  `flake.nix` runs `xvfb-run -a dune runtest -p ocgtk -j $NIX_BUILD_CORES` — one `xvfb-run`,
  `NIX_BUILD_CORES` jobs, which is the exact arrangement this milestone diagnosed. Whether
  ocgtk's own tests present toplevels is unchecked, so this is a pointer rather than a finding,
  and `flake.nix` is the fork's side of the fence.

Diagnostics and contracts:

- **A `Node.notebook` page whose `~key` is missing raises with no node path** — the
  constructor runs before a tree exists, so the message names the child's index instead.
  That is the intended trade (a better message at the point of the mistake), but the M1 live
  case that used to prove the patcher prefixes a child path no longer proves it. Noting, so
  a later reader does not conclude the prefixing was dropped. task-6 M4.
- **A `row_*` attr on a list box's `?placeholder` is accepted and silently inert** —
  `Placement.read_by`'s granularity is the parent's *kind*, not its slot, so the placeholder
  is indistinguishable from a row. The identical case for `Attr.measure_overlay` on an
  overlay's main child is under "Tests worth adding". task-6 M7.
- **`Controllers.update`'s unconditional `clear t` is safe only because `sync`'s re-arm is
  unconditional.** A future "skip `update_slots` when the attrs are physically equal"
  optimisation in either place would reintroduce the Task 4 round-2 regression in a worse
  form — every controller slot on every node empty on every frame — and the re-arm branch has
  nothing saying it must not become conditional. One comment closes it. task-4 re-review 2.
- **Several `Click_event` doc claims have no test and cannot have one in M2**: that `x`/`y`
  are in the widget's own coordinates, that `n_press` counts up within a multi-click, that
  `~button:0` means "any", and that the gesture does not claim the sequence. Part of the
  option-(c) gap rather than a separate omission — recorded so that gap is understood to
  cover the documented *semantics*, not just "a press arrives". task-4 M4.
- **Each controller's GClosure holds an OCaml root on the widget's wrapper**:
  `Signals.connect_all` passes the widget into both trampolines and both controller specs
  ignore it (`fun _w …`), so there is a second GObject/OCaml reference cycle per controller
  on top of the one M1's own handlers create. Broken correctly by `release`/`sync`'s
  `disconnect`, so nothing leaks today; narrowing it means changing `connect_all`'s signature,
  which every M1 spec shares. It is another reason the still-unwritten GC/lifetime test
  matters. task-4 M6, inherited unchanged by the key controller (task-5).
- **`patch_children`'s catch-all message conflates two bugs**: "the node's children shape
  changed under an unchanged kind" and "the impl's `child_ops` disagrees with both", the
  second a registry bug and unreachable today. Carried from M1.
- **`Native_gtk.S.destroy`'s doc does not mention that a replacement's `create` runs first**,
  which spec §6.6 says and the mli does not. Carried from M1.
- **Two grid children in one cell have no diagnostic** — overlapping spans are attached
  silently and painted on top of each other; detecting it needs a per-patch occupancy set.
  Carried from M1.

Behaviour:

- **A search-entry write that empties the box leaves its echo record unconsumed.** GTK emits
  `search-changed` synchronously, cancelling the timeout, when the text becomes empty; inside
  a patch `Signals.dispatch` drops that on `in_patch` before `fire` can consume the record, so
  a `""` record survives to be matched against a later emission. Benign — what is lost is a
  duplicate rather than a search — but the one-record-one-emission invariant does not hold, and
  M2's headless `Search_changed` action or anything that iterates the main loop mid-patch
  changes that. Carried from M1.
- **One failing fixup drops the rest of the pass's fixups** (`run_fixups`'s
  `Exn.protect ~finally` clears the queue behind the raise). Bounded, because the frame is the
  last one. Carried from M1.
- **`drop_stack_names` runs *before* the mount in `patch`'s kind-change arm**, so a mount that
  raises there leaves the old subtree alive with its names already given up. The mirror image —
  `ctx.stacks` keeping registrations from a subtree whose mount raised — is not a defect and
  Task 12 pinned it. Bounded, since the frame is broken. Carried from M1.
- **An overlay child whose *kind* changes jumps to the top of the z-order** (the kind-change
  arm is remove-then-insert, and `add_overlay` appends). Distinct from "`Overlay` has no
  reorder". Carried from M1.
- **`w_switch`'s `reassert` cannot see a `state`/`active` divergence** — latent, since nothing
  connects `state-set`. Carried from M1.
- **The spin button's `reassert` compares the committed value, not what the user is looking
  at**: while an edit is uncommitted the widget displays something the adjustment does not
  hold, so nothing is written. GTK's editing model rather than a defect, but
  `Node.spin_button`'s doc says "the value the widget currently holds". Carried from M1.
- **`w_calendar.ml`'s `same_marks` is order- and duplicate-sensitive; the write is not.**
  `[1; 2]` → `[2; 1]` costs a `clear_marks`, a re-mark and a redraw for no visible change.
  Argued and accepted: set-ifying costs an allocation per calendar per differing frame to save
  ≤31 `mark_day`s for a view that no application writes, and if one appears the fix belongs in
  the view. task-11 M6.
- **`w_text_view.ml`'s repeat-report suppression depends on whether the intervening valid text
  caused a write.** After a valid text that *wrote*, a repeat of a refused text is reported
  again; after a valid text the buffer already held — which returns at `holds` and never
  reaches the memo-clearing line — the same repeat is silent. Both defensible; recorded because
  it is the one place the reporting rule is a function of something other than the model's own
  sequence of texts. task-9 re-review 2 RR2.

Consistency:

- ~~**`take_report` uses `state w` rather than `Cache.find_opt`**~~ — closed by the final
  review's fix wave. It was all four copies rather than only `w_text_view.ml`'s (final review,
  core M6); the shared `Refusal` module does the lookup once, with `find_opt`, so no widget
  mints an entry to find `None` in it. task-9 re-review R3.
- **`enqueue_fixups`' `Text_view` arm enqueues nothing** — the placement is right and the name
  now covers two jobs. If a second caller arrives, a `notify_interests`/`enqueue` split is
  worth the rename. task-9 re-review R2.
- **`Signals.read_back.connect`'s connection list has exactly one user**, and the dedup the
  calendar needs for it lives in `w_calendar.ml` rather than in `Signals`. A third user is when
  it should move. task-11 carry 6.
- **The calendar's four unexposed heading signals** (`next-month`, `prev-month`, `next-year`,
  `prev-year`) are a decision recorded in `vtree/events.ml` and nowhere a user reads. If an
  application ever wants "the user is browsing" separately from "the date changed", that is the
  hook — as is `notify::day`, the unconnected fourth, which would make the calendar's
  completeness argument structural rather than measured. task-11 carries 5 and 7.
- **The editable label's `~text` is compared `O(len)` per idle frame**, like every entry's; at
  100 000 characters that is **1.22 ms per idle frame**, about 7% of a 60 fps budget for one
  widget (measured). It is `Node.entry`'s existing behaviour, not a regression. If a profile
  ever shows entries dominating an idle frame, the fix is `w_text_view.ml`'s cache generalised
  over `GtkEditable`, in one place for all four kinds — and it is a better trade than the
  comparison alone suggests (final review, controls M5): reaching the interface goes through
  `W.Editable.from_gobject`, whose stub does a `g_type_is_a` check, a `g_object_ref` and a
  `caml_alloc_custom` of a finalised wrapper, so each of the four editable widgets allocates a
  finalised custom block, takes a GObject reference and schedules an unref on every idle frame
  on top of the `caml_copy_string`. Tens of nanoseconds per widget per frame, so not a defect
  — but the cache would remove all of it, not just the compare. task-11 carry 3 / re-review M5.
- **`apply_button_props` writes an empty label on the toggle-button create path** while its
  `Button` sibling deliberately does not. Carried from M1.
- **A dropped placeholder builds the empty label `create` avoids.** Carried from M1.
- **`w_entry.ml`'s shared-machinery comment overclaims**: only `text` and `changed` are shared.
  Carried from M1.
- **`Paintable_picture.apply` writes three props outside `Widget_impl.batch`**, and it is the
  file the docs point at as the worked example. Carried from M1.
- **`Native.Picture` has no `alternative_text`** although `Node.picture` does. Carried from M1.
- **Three conventions for writing a default-valued prop at `create`** — `W_image` uses two of
  them in adjacent lines. Carried from M1.
- **`w_frame.create` and `w_center_box.update` write outside `Widget_impl.batch`.** Carried
  from M1.
- **`test/live/live_controllers.ml` is 800-odd lines over seven blocks**, and
  `test/handle/test_gallery.ml` is 1077 lines of which ~540 are one golden, with the three
  sweeps behind it. Both want splitting before M3 grows them again; a large pure-motion diff
  in front of a round's substance is what made it not worth doing inside M2.
  task-5 report, task-13 N7.
- **The two `all_kinds` lists** in `test/test_events.ml` and `test/live/live_events.ml` are
  still duplicated verbatim. Each is now count-checked against `Kind.t`, so neither can rot
  silently; neither is checked against the other. task-1 Minor 3 residual.
- **`task-8-report.md`'s deviation 6 is stale** — it still justifies the sixth gallery page by
  "per-page state that visibly survives (each page holds an entry)", which the fix round's N3
  corrected in `examples/gallery.ml`. A record, not code. task-8 N10.

## Tests worth adding

- **No synthetic click or key press exists in the pinned ocgtk binding, so no test anywhere
  delivers one.** There is no `GdkEvent` constructor for any event subtype (checked every
  `*event*.mli` under `gdk/generated/` for `new_`/`alloc`); `Gobject.Signal.emit_by_name` and
  `.notify` take no arguments and return unit, so neither can carry a click's
  `~n_press ~x ~y` or a key press's `~keyval ~keycode ~state`; and
  `Event_controller_key.forward` only re-routes an event a controller is already processing.
  What is covered instead, and what the gap therefore is:
  - the *plumbing* — that `Attr.on_click` attaches a `GtkGestureClick` with the right `button`
    and `phase`, that dropping the attr removes it, that GTK and this library agree on what is
    attached — is `test/live/live_controllers.ml`, counting by the debugging name `Controllers`
    sets on each controller;
  - the same *plumbing* for keys — one shared `GtkEventControllerKey`, carrying the phase the
    attrs asked for (read back off the live controller), dropping one attr empties one slot
    while dropping both removes the controller, and two attrs asking for different phases are
    rejected at mount and at patch — is `test/live/live_controllers.ml` too. `armed=` on every
    line is what distinguishes an attached controller from one that would actually call a
    handler, which is otherwise unobservable for an event nothing can deliver;
  - the *handler* — that a middle click with shift reaches the application's closure with the
    right `Click_event.t`, and that a key handler consumes Escape and lets `x` through — is
    `test/handle/test_handle.ml`, headlessly, through
    `Bonsai_gtk_test.Action.{Click_at,Key_press,Key_release}`. `Key_press` prints the
    `Key_response.t` the handler answered, because that half of a key press is a value GTK
    reads synchronously and there is no GTK headless;
  - the *trampoline* between them — slots, the `in_patch` guard, the exception guard, and the
    value `Payload` hands back to GTK on each of those three paths — is
    `test/live/live_signals.ml`, which calls the callback `Signals.connect_all` built rather
    than emitting through GTK; and the key spec's own mapping from `Key_response.t` to that
    value is `Controllers.key_pressed_answer`, called directly in `live_controllers.ml` over
    all four constructors.
  - ~~**Not covered:** that GTK actually routes a real button press, or a real keystroke, to
    the controller this library attached — and, for keys specifically, **that propagation
    works**.~~ **Closed on `xtest-input` (`d0a761e`)** by `test/live/live_input.ml`, the twelfth
    live executable, which delivers both through XTEST. It needed no fork patch and no new
    binding: what the routing had to be driven *from* was the X server, not the OCaml side.
    See the closed item below for what its golden proves. Tasks 4 and 5, then the XTEST
    bead.
- ~~**A synthetic click or key press is reachable through XTEST rather than through the
  binding**, and this is the single most valuable follow-up in the file.~~ **Closed on
  `xtest-input` (`d0a761e`)**: `test/live/live_input.ml`, a twelfth live executable that is both
  the application and the driver. It builds a small tree of its own, presents it, drains
  until mapped, computes its own target coordinates from the binding, spawns `xdotool` with
  `Unix.create_process`, pumps its own main loop until the handler's counter moves, and diffs
  a readout against `expected_input.txt` like every other rule in the directory — with
  `(locks x-display)`, the `BONSAI_GTK_LIVE_TESTS` gate, and `%{bin:xdotool}`, which both
  declares the dependency and hands the executable an absolute path. `xdotool` is in the
  devShell now, so the hardcoded store path is gone from the by-hand scripts too.

  What the golden proves: buttons 1, 2 and 3 each reported as themselves; `n_press` 2 on the
  second press of a double click; widget-local coordinates that match the point the click was
  aimed at and lie inside the target; `ctrl` carried through a click; a printable key
  propagating past a `Capture`-phase handler into the entry's text; F1 propagating all the way
  to the entry's own `Bubble`-phase controller (the control for the next one); Escape
  `Handled` in the capture phase and reaching neither; focus enter/leave on a click and on
  Tab; and the negative — a click 10 px past the target's bottom edge moves nothing, which is
  what makes the coordinates real rather than lucky.

  Three corrections to what this entry used to say, all measured rather than argued:

  - **The estimate here was too pessimistic.** "Mapping a widget to screen coordinates" never
    needed a fork patch: `Widget.compute_bounds`, `compute_point` and `translate_coordinates`
    are all bound in the pin.
  - **But `compute_bounds` is the wrong call for aiming a click.** It answers with the region
    the widget *draws in* — which its own documentation says, and which CSS can put outside
    the widget's box. Measured: a themed `GtkButton` allocated 320x120 has a widget box of
    286x110 inset by (17,5), and `compute_bounds` answers 320x120. A gesture reports
    coordinates in the *box*, so aiming at the centre of the bounds lands 17 px off — the
    same shape of miss that made a working handler look broken in the by-hand run. The right
    pair is `translate_coordinates` of (0,0) plus `get_width`/`get_height`, and
    `live_input.ml` reports `bounds-is-box` per target so the difference is on the record.
  - **The `graphene_rect_t` `compute_bounds` answers with points into a destroyed stack
    frame.** One more call into the binding and its accessors return zeros; reading a width
    off a kept rect gave 0 where the widget is 320 wide. It is undefined behaviour rather
    than a stale buffer, it is generator-wide rather than specific to this method, and
    `live_input.ml` pins it with a golden line — see "Still open on the fork" below, where
    it is now a scoped fork item rather than an audit.

  Two facts about GTK the file also records, because both would otherwise read as bugs in
  this library: an `Attr.on_click` on a `GtkButton` *does* see the press, despite the
  button's own gesture claiming the sequence; and a `GtkEntry`'s bubble-phase key controller
  never sees a printable key, because the `GtkText` inside consumes it to insert it — which
  is why the propagation proof uses F1 as its control and the entry's *text* as the evidence
  that the printable arrived.

  Determinism: 10/10 clean runs of `BONSAI_GTK_LIVE_TESTS=1 xvfb-run -a dune build
  @test/live/runtest`, 5/5 with 48 spinners on 24 cores (2x oversubscription, load average
  ~50), and two consecutive green `nix develop -c ./scripts/ci.sh`.

  **What is still open** is the residual Task 16 named and this does not touch: a *real*
  display — an X server with a window manager and a compositor, or Wayland, where GTK takes
  the `gdk_wayland` input path rather than the X11 one exercised here.

- Focus is the exception and *is* covered end to end: `Widget.grab_focus` on a presented window
  really drives `GtkEventControllerFocus`, and `live_controllers.ml` asserts the handler fires,
  that the reentrancy guard drops a focus change made during a patch, and that a removed
  controller stops firing. Task 4.
- **Click-through of `examples/gallery.exe`** — **Task 13 built the page** (the gallery's
  *Input* tab): a click card reporting button, press count, widget-local coordinates and
  modifiers; a `Capture`-phase key controller that consumes Escape (`Handled_and`, with a
  counter) and observes every other key without consuming it (`Propagate_and`, with an entry
  below it that must still receive the text); and two entries whose focus enter/leave name
  which one has it. **Task 16 drove all of it** — the machine is a headless server, so under
  `xvfb` with `xdotool` rather than on a real display — and every readout moved: button 1/2/3
  each reported as itself, a double click as `press 2`, a ctrl-held click as `ctrl`, `hello`
  typed into the first entry with the last keyval reported per keystroke, Escape counted and
  consumed with the entry keeping its text, and focus moving to the second entry on Tab.
  Screenshots were read, not just captured. That run is now a demonstration with a test
  behind it: `test/live/live_input.ml` (closed above) re-proves the same routing on every CI
  run, against a tree of its own rather than against the gallery, and the two by-hand scripts
  under the SDD workspace stay only as the human-facing screenshot walk. **What is still not
  done is a real display**: an X server with a window manager and a compositor, or Wayland,
  where GTK takes a different input path (`gdk_wayland`) than the one exercised here. That is
  now a small residual rather than the whole check.
- **GC/lifetime**: remove a keyed child, `Gc.full_major`, assert the widget was finalized — the
  spec's central ownership assumption, still unwritten (carried from M0). M2 makes it more
  interesting, not less: `Child_keys` is an ephemeron table on exactly those widgets, and the
  controller GClosure cycle above is a second root per controller.
- **After-display spin regression** (needs a frame counter under `Private`) — carried from M0.
- `Driver.schedule_event`'s broken guard is exercised but not asserted: nothing public observes
  the Bonsai action queue's length. Task 1.
- **No live per-kind `update` sweep.** Task 13's headless sweep proves the patcher will not
  *skip* an impl's `update` (`props_changed=true`); it says nothing about whether `update`
  writes anything, and `test/handle/` links no ocgtk. There is still no single live
  `Live_tree.dump` golden over the whole catalogue. Tasks 10 and 13.
- **`forget_children`/`forget_rows` are unpinned** — see the `Child_keys` item under "Do first
  in M3"; the closing shape is a `Child_keys.length` for tests. task-7 M4.
- **`Reconcile`'s two theorems live only in one widget's comment**: `Reconcile.diff` emits every
  `Move` with `from > to_`, and it can never emit `to_ = n-1`, so no container's `move` ever
  needs `reorder_child`'s past-the-end clamp. Recorded in `w_notebook.ml`; they are theorems,
  not measurements, and would otherwise be re-derived. task-8 carry 4.
- **`Live_tree`'s notebook dump cannot show page order** (the internal `GtkStack` holds its
  children in insertion order), and more generally any container that holds widgets on a
  child's behalf — a stack's switcher buttons, a list box's placeholder — has the same "the
  dump is the only independent reading" problem. task-8 carries 2 and 5.
- **The text-view cache's invariant has no independent idle-frame test**, and cannot have one:
  reading the buffer to check that nothing read the buffer would itself leak and would defeat
  the thing under test. What defends it is the ratio bench. Worth knowing before anything
  relaxes that bench. task-9 carry 4.
- **The month-and-year heading walk (Dec → Jan) is absent from the calendar golden** — it is the
  case the day-selected dedup's safety argument rests on most. Behaviour probed and correct;
  one more `walk` line would put it in the golden. task-11 re-review M1.
- **`live_text.ml`'s "showing today" assertion can flake across midnight** — it compares against
  a `Date.today` computed after the mount. Capturing `today` once before is free.
  task-11 re-review M2.
- **Teardown of all three calendar connections is unasserted.** Low risk (the type forces the
  list, and a surviving handler on a destroyed widget finds a cleared slot), but it is the one
  property of the connection-list change that no test observes. task-11 re-review M3.
- **The text view's repeat-report suppression for a *rebuilt* equal string is untested** —
  `already_refused`'s `String.equal` arm suppresses a duplicate report, which is `node.mli`'s
  "once per offending text" promise, and the suite pins only the physically-same-string case.
  One extra line patching a `String.copy` closes it, and it is the arm a later "simplify this to
  `phys_equal`" would silently break. task-9 re-review 2 RR1.
- **Nested `Attr.many` has no golden** — `test/test_attrs.ml` covers one level, and `flatten`'s
  documented depth-first left-to-right order is what makes `Attrs.of_list`'s last-write-wins
  meaningful. One extra attr in the existing test closes it. task-1 Minor 10.
- **Three expect tests pass props the sexp then drops** (`test/test_widgets.ml`'s
  `~content_fit:Contain`, `~can_shrink:true`, `~vpolicy:Automatic`, `~step:1.` are all defaults,
  erased by `[@sexp_drop_if]`), so they look like coverage and are not. Carried from M1.
- **`examples/gallery.ml` writes its sample PNG to a fixed path in `$TMPDIR`**, so
  `Out_channel.write_all` follows whatever is already there. Example-only, and the fixed name is
  what stops the per-run litter. Carried from M1.
- `Live_tree.dump` collapses a placeholder `""`, and truncates text at 60 characters.
  `focusable`/`can_focus` are absent from it. Carried from M1 and Task 9.
- **`Bonsai_gtk_vtree.Placement`'s granularity is the parent's *kind*, not its slot**, so
  `Attr.measure_overlay` on a `Node.overlay`'s **main** child, and a `row_*` attr on a list
  box's `?placeholder`, are both accepted and both stay inert. Tightening it means threading the
  slot name in beside the kind; worth doing when a slot container reads two different placement
  attrs on two different slots, and not before. M2 task-3 M6, task-6 M7.
- **Nothing distinguishes `Driver.frame`'s phys-equal fast path from the slow one.** Replacing
  `phys_equal node live.Patcher.node` with `false` used to leave the whole suite green because
  the two paths were behaviourally identical by design. Task 2 made the fast path *narrower*
  (`reassert_only`) rather than merely equal, so the flip is now a performance change rather
  than a no-op — but still not a behavioural one, so the guard remains unpinned.
  M2 task-2 Minor 1.
- Untested-but-implemented update branches: `Frame.label_align`, `Expander.use_markup`,
  `Revealer.transition`/`transition_duration` (none is printed by `Live_tree.dump`), and
  `W_image.update` writing `pixel_size` back to `-1`. Carried from M1.

## Known-and-accepted dump quirks

Do not "fix" these when an expected file surprises you:

- `Live_tree` prints `opacity` as GTK reports it (8-bit storage), so `Attr.opacity 0.5` reads
  back `0.501961`.
- Every `GtkSpinButton` dump carries a constant `numeric` line: the node default is `true` where
  GTK's own is `false`.
- GTK's icon-name resolution for `GtkImage` can churn across GTK versions, so image dumps may
  need re-promoting on a GTK bump.
- A `Grid` child whose `Attr.grid_cell` changes is re-attached, which moves it to the end of
  GTK's child list; the cell is the placement, so nothing moves on screen — but the dump order
  changes.
- GTK 4.22 leaves `gtk_root_get_focus` pointing into a widget across an unparent and a
  re-parent, so the save/restore in `w_grid.ml`'s `updated` hook is insurance rather than a
  repair.
- **`set_current_page` on a page whose child is hidden emits `switch-page` and leaves the
  current page unchanged** — which is why `w_notebook.ml`'s select fixup reads the live widget
  back rather than trusting the index it wrote. Task 8.
- **`GtkFlowBox.remove` *does* emit `selected-children-changed` on 4.22.** The M2 plan called it
  a documented quirk that it does not; that was stale. Task 7.
- **The live suite has two stderr producers**, not one — the "the one stderr line is …"
  convention three M2 reports used no longer holds. task-7 re-review N2.
- ~~**`test/live/expected_controllers.txt` has been seen to flake under Xvfb**, with
  `focus-enter,focus-leave` arriving one frame early — a timing flake, not a regression.~~
  **Diagnosed and fixed in M2's Task 16, and no longer a quirk to accept.** It was not timing
  and nothing arrived "one frame early": the eleven live executables shared one X display, and
  a neighbour's toplevel mapping took the input focus away before the `grab_focus` that was
  meant to move it. `(locks x-display)` on the nine rules that present a toplevel is the fix
  (it was `-j 1` on the live alias until the final review's fix wave). **If you see this diff
  again, the serialisation has been lost** — check `test/live/dune` before you touch the
  golden. See *Plumbing / hygiene*, "The live tests share one X display".
  task-14 M11, closed by task-16.
- `expected_controllers.txt`'s `gtk=` name lists follow attach order, so reordering
  `Events.Family.t` for tidiness reorders them even though every `armed=` assertion holds.

## Plumbing / hygiene

- ~~**The live tests share one X display, and one of them cares who has the focus.**~~
  **Closed by the final review's fix wave**, with `(locks x-display)` on the nine rules whose
  executable presents a toplevel — dune's own answer to "these must not run at once", binding
  the constraint to the rules instead of to one `-j 1` on one call site, so every invocation
  inherits it and a cold tree no longer pays 26 s to serialise eleven compiles as well
  (59 s → 33 s; warm, where ci.sh always is, the two are indistinguishable). Measured
  unserialised at 4 focus failures in 7 loaded runs; with the lock, 0 in 6. The phenomenon:
  another live executable presenting its toplevel takes the input focus away, so a
  `focus-leave` arrives before the `grab_focus` meant to cause it and the golden diff reads as
  a regression in the focus controller. What is still *not* taken, and is the honest fix if
  this ever comes back: **making the block not depend on toplevel focus at all**, since what it
  wants to assert is that `Widget.grab_focus` drives the controller, not that nothing else on
  the display ever takes the focus. This entry is the same phenomenon as the struck one under
  *Known-and-accepted dump quirks*, which is where a maintainer hitting the diff is most likely
  to land first.
- **`live_text.exe` is 25 s of the live section's 29** (the other ten are 24–563 ms each,
  measured 2026-08-30). It is the 100 000-character editable-label bench and the 1 MB text-view
  ones. Nothing is wrong with it, but the whole gate is now shaped by one file, and
  serialising the display costs nothing precisely because of that; if the section ever needs to
  be faster, that is the only place to look.
- **`dune build @test/live/runtest --force` does not re-run these rules** — each declares a
  target (`with-stdout-to output_*.txt`), so `--force` returns in 3 s having done nothing, and
  a loop of them will report a flaky test as green ten times running. Delete
  `_build/default/test/live/output_*.txt` between runs instead, which is what `scripts/ci.sh`
  now does before its live step: the same trap applied to the plain gate command, so a second
  `ci.sh` in one tree exercised the live suite not at all (final review, live I1). Cost M2's
  Task 16 an hour;
  written down so it costs the next person nothing.
- **The gallery's click card is not a click target; the words inside it are.** `Attr.on_click`
  sits on the `Node.label`, and `Attr.margin 24` is space *outside* a widget's allocation, so
  the padding that makes the card read as a button is inert — a click 14px below the text moved
  no readout in Task 16's run, and a reader debugging their own gesture would have no way to
  tell that from a broken handler. Task 16 corrected the page's instruction to say "the words"
  rather than "the card". The alternative is to move the gesture onto the `Node.frame`, which
  would make the whole card live and would demonstrate "legal on any node" better than a label
  does; which of the two the page should show is a choice, so it is here rather than done.
- ~~`scripts/ci.sh`'s generated-opam check is `git diff --exit-code -- '*.opam'`; add `HEAD` so
  *staged* drift is caught too.~~ **Done** in the M2 clean-tree pass (Task 16).
- `scripts/setup-switch.sh`: the reinstall stamp keys on `rev`, so a dirty `.ocgtk-src` at the
  pinned rev is not rebuilt — add a `git status --porcelain` check. **And `opam reinstall ocgtk`
  does not update `bonsai-gtk-ocgtk-rev`**, which is worse than no evidence because it looks like
  evidence: either have `setup-switch.sh` document it or have the reinstall path clear the stamp.
  Task 14.
- **Flake: a `gir_gen`-capable shell**, so the fork's generator work does not depend on
  `nix develop ~/src/stavekeeper#girgen`. Every generator command in Task 14 ran through that.
- Node paths are frozen at mount, so `on_exn` logs name a stale path after a move.
- `Signals.slots`' outer `ref` is built by mutation and never re-assigned afterwards.
- **A `Driver` is never reclaimed, stopped or not**: a `Driver.create` that is stopped without
  ever being framed still retains ~39k live words, and a failed `Expert.embed` about ~10k, on a
  heap settled through two full majors. It is the Bonsai graph rather than anything GTK —
  Incremental's state is global and outlives the observer invalidation `stop` performs — so an
  application that builds a driver per dialog grows without bound. The lever is Bonsai's, not
  this library's; if M3 wants defence in depth, it is disconnecting the patcher's signal closures
  from a finalizer-safe place, or holding the driver from the `ctx` weakly. `Driver.stop` does
  now drop `on_root_widget_changed`. Task 12.
- **`Bonsai_gtk.start`'s `on_window_created` has the same shape** and is not dropped by
  `Driver.stop`: it closes over the `GtkApplication`. Harmless today, one line to fix the day it
  is not.
- **`drain`-shaped loops (`while Glib.Main.pending () do …`) can fail to terminate** right after
  a major collection that finalizes many wrappers (reproduced twice by the Task 12 reviewer).
  `test/live/live_embed.ml`'s `drain` is bounded for that reason; every other live test's is not.
- The 16 ms tickless cadence is hard-coded (`src/scheduler.ml`), and `request_frame` does not
  cancel a pending `request_frame_soon`.
- `after_of` is `O(index)` per op and the surrounding `cur` bookkeeping `O(n)` per op — see "Do
  first in M3" for what actually showed up in a measurement instead.
- The `Update` kind-change arm still removes a child after `patch` destroyed the old live widget
  — latent until M3's `Node.windows` puts a `Window` in a list.
- `Widget_impl.snapshot` is 17 getter calls per widget creation and grows with every widget-wide
  attr; the shape to reach for is lazy per-field capture on first `Set`.
- The `page` helper is duplicated across the Task 5 live tests.
- Redundant `(deps …)` in `test/live/dune`.
- **`Bonsai_gtk` re-exports four enum modules the M2 plan never listed** — `Selection_mode`,
  `Tab_position`, `Wrap_mode`, `Level_bar_mode` — plus the six event-value modules. They are in
  the README and in spec §7 now; spec §5.1's constructor sketch is still M0's and does not show
  `?tab_pos`, `?wrap` or `?mode`. Tasks 8–10 carries, routed to Task 16's spec sweep.
- **The port's shell-side gap** (stavekeeper, not this repo): `app#quit` bypasses
  `on_close_request`, so the port needs an embed-side equivalent of `Viewer_window.teardown_all
  ()` or it will skip `Embedded.stop` on the quit path. Task 12.
- **The Stavekeeper pin bump is outstanding**: `ocgtk-pin.json`, `flake.nix`'s
  `fetchFromGitHub` hash `sha256-0q4wCAXgYenhKwSobYJ1wVgs/ZptWeCp9UPipzTJ/Z0=` and
  `scripts/setup-ocgtk.sh` all still point at the pre-M2 fork commit; then `nix build` and the
  smoke test. This repository's pin has moved (`3a87d1c`); Stavekeeper's has not.

## ocgtk fork

The pin is `649498b4` (`ocgtk-pin.json`), the head of the fork's `m2-bindings` branch, which is
pushed and to which fork `main` has been fast-forwarded. Twelve commits sit on it beyond M1's
pin. `ci.sh` is green against it.

### Fixed in M2's fork round — do not re-file these

- **`gtk_list_box_get_selected_rows`'s missing `g_object_ref_sink`**, and the other 23
  transfer-container list returns with the same shape. The M1 backlog carried this as the most
  valuable fork patch M2 had found, and it was: the stub handed out one unbalanced unref per
  selected row, which disposed still-parented rows within a few frames of a major collection
  and segfaulted. Fixed in the generator rather than by hand, with a refcount-invariant
  regression test.
- **`g_object_ref_sink` on a constructor's return, for a type that is not
  `GInitiallyUnowned`** — `GtkStringList` and its kin held two references and dropped one.
- **The three nullable string bindings** M1 wanted: `Widget.set_name`,
  `Password_entry.get_placeholder_text`/`set_placeholder_text` (the getter was a *crash*, not a
  wrong value), and `Stack_page.set_title`. The library has not taken the behavioural benefit —
  see "Do first in M3".
- **`gtk_drop_down_get_selected_item`'s missing sink** (as a side effect of the transfer sweep).
  Its other half is not fixed — see below.
- **A GObject handler reached from OCaml's finaliser re-entering the runtime.** The M1 entry
  called it a hang; it is a **memory-safety bug** — measured as a segfault as soon as the
  callback allocates, with no bonsai_gtk involved at all, and reachable by any downstream
  application that connects `destroy` and lets the widget be collected. The fork now guards all
  three finalisers and reports once, non-fatally. The consequence a consumer inherits is that a
  handler reached during finalisation no longer runs at all; `signals.mli` states the rule.
- `pango_glyph_item_apply_attrs`'s aliased transfer-full instance, and `gtk_builder_get_objects`'
  bare-GObject elements.

### Still open on the fork

- **153 generated stubs return a pointer to a destroyed stack frame.** The highest-value
  *correctness* item on the fork after the `char*` leak below, and the one with the
  smallest fix. Found by `test/live/live_input.ml`, which was bitten by it in
  `Widget.compute_bounds`: read the rectangle's width immediately and it is 320, make one
  more call into the binding and read it again and it is 0.

  It is not a lifetime convention and not a stale-but-defined buffer — it is undefined
  behaviour. The stub declares the out-parameter as a C stack local and wraps its
  *address*:

  ```c
  /* src/gtk/generated/ml_widget_gen.c */
  CAMLexport CAMLprim value ml_gtk_widget_compute_bounds(value self, value arg1)
  {
    CAMLparam2(self, arg1);
    graphene_rect_t out2;                                /* a C stack local */
    gboolean result = gtk_widget_compute_bounds(…, &out2);
    …
    Store_field(ret, 1, Val_graphene_rect_t(&out2));     /* wraps the pointer, no copy */
    CAMLreturn(ret);
  }
  ```

  `Val_graphene_rect_t` is `ml_gir_record_val_ptr_with_type(graphene_rect_get_type(), ptr)`
  (`src/graphene/generated/ml_rect_gen.c:24`) — a *val_ptr* wrapper. So the OCaml value
  points into a frame `CAMLreturn` destroys, and every read through it is a
  read-after-return. `live_input.ml`'s workaround (read all four fields before touching
  ocgtk again) is **stack-layout luck, not a rule**: each accessor is itself a C call that
  pushes a frame which may or may not land on the same bytes. Its comment says so, so that
  nobody adopts the pattern on the strength of it working here.

  **The shape is generator-wide.** Swept the generated C for a local `<type> outN;` handed
  to `Val_<type>(&outN)` — **153 stubs across 22 files** (counted at the fork's `4ae6698c`;
  the pinned `649498b4` is not in the local checkout, but this is generator output and the
  generator did not change between them):

  ```
  graphene_vec3_t 28 · graphene_rect_t 22 · graphene_point3d_t 18 · graphene_vec4_t 17
  graphene_vec2_t 16 · graphene_point_t 13 · graphene_matrix_t 10 · graphene_box_t 8
  graphene_quaternion_t 8 · graphene_plane_t 4 · graphene_sphere_t 3 · graphene_quad_t 2
  graphene_size_t 2 · graphene_euler_t 1 · graphene_ray_t 1
  ```

  That number is what makes this scoped work rather than an open-ended audit: **one
  generator change** — allocate and copy on the way out, the way the record converters
  already do for transfer-full returns — **plus a regeneration**, and all 153 close at
  once. A per-call-site fix would be 153 patches for the same bug.

  Two golden lines in `live_input.ml` are the canaries: `bounds-is-box=…` on each geometry
  line, and `compute_bounds rect survives a later ocgtk call: false`. Both are reading
  undefined behaviour, so both could move on an ocgtk rebuild with no change in this
  repository — and neither is load-bearing for what the test asserts, since the aim comes
  from `translate_coordinates` and `get_width`/`get_height`. When the generator is fixed,
  the `survives` line flips to `true` and the workaround comment in `box_of` can go.

- **No transfer-full `char*` return is freed anywhere in the generated stubs** — a memory leak in
  every one of them, and **the highest-value remaining fork item**. The one M2 walks into is
  `gtk_text_buffer_get_text`: `ml_text_buffer_gen.c` copies the result and never `g_free`s it,
  while the method is `transfer-ownership="full"`. Reproduced: 200 whole-buffer reads of a 1 MB
  `GtkTextBuffer` grow RSS by 201 MB and a `Gc.full_major` reclaims none of it.
  `get_slice`, `gtk_text_iter_get_text` and `gtk_text_iter_get_slice` are the same shape, so
  there is **no** way to read a text buffer through this binding without leaking it.
  `w_text_view.ml` works around it on the *frame* path only (a cache invalidated from
  `GtkTextBuffer::changed`, so an idle frame reads nothing) — **it does not fix the edit path and
  cannot**, because `Attr.on_changed`'s contract is to hand the handler the buffer's full text.
  Each keystroke in a 1 MB document costs 0.42 ms and leaks 1 MB; sustained typing leaks several
  MB a second. That is the number to weigh. The generator already emits `g_free (result)` after
  copying a transfer-full *array*; the single-`char*` path is the miss, so this is a small
  `gir_gen` change plus a regeneration — genuine new work, not a re-run. Task 9, Task 14 item 4d
  #4.
- **Transfer-full GObject in-parameters, ~30 sites.** The generator now emits `g_object_ref` on a
  `transfer-ownership="full"` in-param, which closes a real double-drop — **held back** because at
  least six of those sites would `g_object_ref` a `GtkExpression`
  (`gtk_string_filter_new`, `gtk_bool_filter_new`, `gtk_numeric_sorter_new`,
  `gtk_string_sorter_new`, `gtk_property_expression_new`, `gtk_drop_down_new`), and a
  `GtkExpression` **is not a `GObject`**: it has its own `gtk_expression_ref`/`unref`. Applying it
  wholesale would trade a leak for a probable `G_OBJECT` cast critical. Needs a generator change
  that recognises the ref-counted non-GObject types, then regeneration. Task 14 item 4d #1.
- **31 constructors build non-GObject fundamentals and wrap them through
  `ml_gobject_val_of_ext`**, whose finaliser is `g_object_unref (G_OBJECT (ptr))` — an invalid
  cast critical plus a leak on every collection.
  `ml_constant_expression_gen.c`, `ml_object_expression_gen.c`, `ml_property_expression_gen.c`
  and 28 `GskRenderNode` subclasses. Not caused by the M2 round, which removes one bogus critical
  per construction and leaves the leak. **Same root cause as the in-param item above, and it
  should be one issue with it rather than two.** Related: 9 constructors (not the 11 the report
  says) keep a sink on a non-`GInitiallyUnowned` type even after regeneration, and 9 of those 11
  sink lines are in files in no `dune-generated.inc` — dead code. A tighter rule would be "sink
  iff `GInitiallyUnowned`". Task 14 item 4d #3, review M10.
- **GBytes returns, 6 sites**, want `g_boxed_copy` because `Val_GBytes` adopts. Well covered by
  `gir_gen`'s tests; held back only to keep the M2 branch to the two classes audited by hand.
  Task 14 item 4d #2.
- **`gtk_drop_down_get_selected_item` still returns a bare custom block where the `.mli` promises
  an `option`** — so a `Some` with the raw pointer word as its payload, and `caml_failwith` on a
  NULL return rather than `None`. The missing sink half is fixed; this half is not.
  `ml_gobject_val_of_ext_option` exists two functions away in `wrappers.c`. Nothing here calls it,
  and it is worth fixing because it is the *obvious* call for "what is selected".
- **`gtk_drop_down_get_expression` answers `None` on a drop-down that has one**, and its stub
  `g_object_ref_sink`s a `GtkExpression`, which is not a `GObject`. Measured on GTK 4.22. Nothing
  here calls it, but it means this library cannot assert that `~enable_search:true` will actually
  filter — the expression is what the popup's filter reads.
- **`Gobject.unref` is not exposed** (it exists as `ml_g_object_unref` in `ml_gobject.c` with no
  `val` in `gobject.mli`), and **`Widget.destroy` is not bound either** — there is no
  `gtk_widget_destroy` in GTK 4, but `gtk_window_destroy` and `g_object_run_dispose` are unbound
  too. Noted because `test_dispose_reentry.ml` had to emit `destroy` by hand rather than drop a
  reference, and a control that disposes deliberately is a better test than one that emits.
  Task 14 items 4d #6 and #7.
- **`g_object_ref_sink` is still the wrong primitive on the borrowed-return path.** For a borrowed
  reference you want `g_object_ref`; `ref_sink` differs only on a floating object, and then it
  *claims the float* instead of adding a reference, so the wrapper's finaliser would destroy an
  object the container still points at. Nothing reachable is floating today (measured), but
  `generate_ref_sink_stmt`'s borrowed-return branch would be correct by construction with
  `g_object_ref`. task-14 re-review N2.
- **`test_transfer_container_lists.ml` pins 3 of the 24 sites** (ListBox, FlowBox, Builder). The
  remaining 21 — `text_iter`, `tree_view`, `cell_layout`, `size_group`, `window_group`,
  `accessible_list`, `application`, `gesture`, `emblemed_icon`, the four GDK sites and all three
  Pango sites — are unpinned, which is why C1 got through the first round. All of them sit behind
  `require_gtk`, which `Alcotest.skip ()`s without a display, so on a display-less runner the file
  pins nothing at all. Table-driving it properly is a task, not a fix-round minor. task-14 M9.
- **The generated tree is 34 files behind its own generator** (28 files / 31 sites of the
  transfer-full GObject in-param class, and 6 borrowed-`GBytes` returns) — disclosed rather than
  hidden, since both are the held-back items above. When the first is taken up, that inventory is
  the place to start. task-14 re-review N6.
- **`docs/dev-notes.md` does not exist**, though ten generated ocgtk files point at it as the
  authoritative "re-apply on any vendor re-sync" list. Pre-existing, and now load-bearing: the M2
  round adds more hand-applied hunks whose survival depends on exactly that discipline.
  task-14 re-review N3.
- **`GList*` is declared for 13 GSList-returning stubs.** It works because both structs lead with
  `data`/`next`, but the types are incompatible and `-Wincompatible-pointer-types` is an error by
  default in GCC 14+ and Clang 16+. Builds clean on this toolchain. Pre-existing and systemic.
  task-14 re-review N4.
- **The `caml_remove_global_root`-from-a-finaliser residual** in `ml_closure_invalidate`
  (`ml_gobject.c`): it does not allocate, and the counting case exercises it, but nothing asserts
  it.
- **Two commit messages on the pushed branch are wrong and cannot be fixed**: `4ea70268` says
  "190 files" where the figure is 206 generated `.c` files, and lists `gtk gio gdk gsk pango`
  while 19 of the 279 removals are in `gdkpixbuf`; `a913c307` misclassifies 7 of the 24 sites it
  touches (four are `transfer-ownership="none"`, the three Pango ones are `"full"`) and says 21
  where it is 24. The substantive halves were repaired in the code, the override comment and
  `overrides.md`. task-14 M3, M4.
- **`task-14-report.md`'s 4b regression paragraph overstates the reproduction** — it says removing
  the sink leaves the suite hanging, where the reviewer got a clean `[FAIL]` in seconds; it should
  say "hangs *or* fails" and give the condition. A record, not code. task-14 M7.
- **The aliasing audit's headline count is 93 where it should be 75** (`overrides/pango.sexp`,
  `architecture/gir_gen/overrides.md`): restricted to methods, functions and constructors as the
  sentence states, 93 both double-counts one representation and omits the other. The safety
  conclusion is unaffected. task-14 re-review N1.
- **A stray `transfer_strategy = Ts_none;` sits mid-sentence inside a doc comment**
  (`gir_gen/lib/type_mappings.ml:256`). Harmless, pre-existing, worth deleting while nearby.
  task-14 re-review N5.
- **Handler ids come from one global counter, not a per-instance one** (measured on this GLib:
  two handlers on two different `GtkTextBuffer`s and one on a `GtkTextView` got 118/119/120). So
  `signals.mli`'s worse case for disconnecting a handler id from the wrong object — "at worst
  disconnects an unrelated handler that happens to share the number" — cannot happen here: the
  wrong disconnect logs `instance '0x…' has no handler with id 'N'` and leaves the real handler
  connected. Still a bug, and still the one `Signals.connection` exists to prevent; the doc's
  second clause is the theoretical half and should say so if it is ever rewritten.
- **The fork has no working `dune build @fmt`**: `gir_gen/.ocamlformat` pins 0.29.0 and the
  `#girgen` shell ships a different build. The fork's problem, not the branch's, and a bead of its
  own.
- **`test_glyph_item_alias` needs a display** (`require_gtk`), so on a display-less runner it
  skips — and so does the C1 regression it exists to pin.
- **Six upstream PRs are open as drafts** (#173–#178, `docs/upstream/README.md`) pending
  maintainer-side review; topic branches are pushed, each a single scrubbed commit cherry-picked
  onto `upstream/main`. **The twelve `m2-bindings` commits have no topic branch or PR yet** and
  need the same treatment — and the scrub grep must be re-run over all of them, because
  `a913c307`, `4ea70268` and `95c1d6e8` edit generated files that still carry `score-library-*`
  comments in their diff context. Once anything merges upstream, rebase `bonsai-gtk`, re-run
  `nix build .#ocgtk`, move the pin.
- ocgtk's commit 2 hand-patches stubs commit 3's generator now emits; upstream may prefer
  regeneration (said in the PR text).
- The OxCaml `caml_alloc_custom_dep` branch of the GBytes accounting is only exercised in the opam
  switch, not in the stock-OCaml Nix build.

### Confirmed out of reach, and routed around

Each is a milestone of its own rather than a patch, and M2's workaround stands:

- **`List_box.set_header_func` / `set_sort_func` / `set_filter_func`** — the generator emits no
  GIR-callback-taking method at all. Sort and filter in the model; a header is an ordinary
  non-selectable, non-activatable row.
- **`GLib.DateTime`** — there is no `GLib-2.0.gir` in the checkout to generate one from, which is
  why `Node.calendar` takes a `Core.Date.t` and converts to GTK's three integers in one place.
- **`gdk_keyval_name` / `gdk_keyval_from_name`** — no namespace-level function is generated, which
  is why `Keyval` is a curated table of `int`s.

### The rule this established

For any new binding call that returns objects: **read the *stub*, not the GIR.** A
`Val_GList_with` site without `g_object_ref_sink`, or any `Val_*` wrapping a transfer-none
pointer, is an unbalanced unref that GC turns into a use-after-free — and neither the type checker
nor a short-lived test will show it, because nothing collects before exit.
`test/live/live_lists.ml`'s first block is the shape of test that does: N frames, a
`Gc.full_major`, and an assertion that the widgets are still there.
