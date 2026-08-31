# Task 7 report — FlowBox: keyed children, controlled selection, geometry as a prop diff

**Commit:** `3d05a83` on `m2`, base `f573799`. 34 files, +2027/−81.
**Gate:** `nix develop -c ./scripts/ci.sh` → `all green` (the one stderr line is
`live_driver.ml`'s deliberate raise, as in Tasks 4–6).

---

## The binding-safety check the brief asked for, answered

**`gtk_flow_box_get_selected_children` is safe in the pinned fork.**
`.ocgtk-src/ocgtk/src/gtk/generated/ml_flow_box_gen.c:216-233` wraps each element as
`Val_GtkFlowBoxChild(g_object_ref_sink((gpointer)_tmp->data))`, with a comment saying it
is transfer-container and must sink. This is the hand patch Task 6's C1 pointed at as the
precedent the `GtkListBox` twin is missing; the `_opam` copy the build actually links is
byte-identical to `.ocgtk-src`'s (both checked).

I checked **every** getter this impl calls, in the stub rather than in the GIR, per Task
6's rule of thumb — all four sink:

| Stub | Sinks | File |
|---|---|---|
| `gtk_flow_box_get_selected_children` | yes (hand patch) | `ml_flow_box_gen.c:233` |
| `gtk_flow_box_get_child_at_index` | yes | `ml_flow_box_gen.c:292` |
| `gtk_flow_box_child_get_child` | yes | `ml_flow_box_child_gen.c` |
| `gtk_widget_get_parent` | yes | `ml_widget_gen.c:871-878` |

**`W_flow_box.selected_keys` walks `get_child_at_index` + `is_selected` anyway**, and the
reasons are written into the code so nobody "simplifies" it back: (a) the `children` walk
is needed for `child_by_key` and `forget_children` regardless, so using it for the
selection too is one shape rather than two; (b) it depends on no hand patch to a generated
file — the real fix belongs in ocgtk's generator (backlog), and a regenerated stub could
drop the sink silently; (c) it makes the file read like `w_list_box.ml`, where the walk is
mandatory. The comment says outright that this is *not* a workaround for a broken binding,
so the two files' identical shapes do not imply an identical defect.

`Live_tree`'s `selected-children` count walks too, matching the `GtkListBox` arm.

---

## Per-step summary

**Step 1 (failing tests first).** `test/test_widgets.ml` (constructors, defaults, the
unkeyed-child rejection, the geometry rejections), `test/handle/test_handle.ml` (the
library grid in miniature; the two activate actions' kind check; the `Events` and
`Placement` negatives), `test/live/live_lists.ml` appended. Verified failing —
`Unbound value "Node.flow_box"`.

**Steps 2–5 (implement).** `Defaults.Flow_box`; `Kind.flow_box_props` + the variant, `name`,
`same_kind`, `equal_props` arms; `Node.flow_box` with `require_child_keys` and the two
geometry checks; `Attr.{On_child_activated, On_selected_children_changed}` through all six
exhaustive matches in `attr.ml`; `src/widgets/w_flow_box.ml`.

**Step 6 (`Events`, `Registry`, `Live_tree`, placement).** `Events.for_kind` gains
`| Flow_box _ -> [ On_child_activated; On_selected_children_changed ]` — its own pair, so a
line copied from a list box is *rejected* rather than accepted and inert.
`Placement.read_by` has **no** `Flow_box` arm and falls into the wildcard, which is correct
and is now pinned rather than merely true (below). `Live_tree` gains `GtkFlowBox` (the
seven props against their defaults plus the selection count) and `GtkFlowBoxChild`
(`selected`).

**Step 7 (`test_lib`).** `Activate_child of string * Key.t` added; `Set_selection` shared
and dispatching on the kind it finds; **both** activate actions now check the kind and fail
naming it (`node grid is a FlowBox, not a ListBox`). Adding the check to `Activate_row` is
a small change to Task 6's action — see deviation 4.

**Step 8 (run, promote, gate, commit).** `dune fmt` per directory, criticals sweep,
`./scripts/ci.sh` → `all green`, one commit.

---

## GTK facts established empirically, and two corrections to what the plan carried

Two throwaway probe executables under `test/live/`, run under xvfb and deleted.

| Fact | Consequence |
|---|---|
| `max-children-per-line` defaults to a real **7** | `Defaults.Flow_box.max_children_per_line = 7`; `Live_tree` prints it against 7, so a golden showing nothing is showing seven per line |
| `set_max_children_per_line 0` is `g_return_if_fail (n_children > 0)` — a critical, old value kept | `Node.flow_box` rejects `< 1` at the constructor |
| All four geometry ints are unsigned in C: `min = -1` reads back **65535**, `row_spacing = -5` reads back **4294967291** | the constructor rejects negatives; there is no other diagnostic at all |
| `selection-mode` defaults to `SINGLE`; `activate-on-single-click` to `true`; min 0, spacings 0, homogeneous false, orientation horizontal | the rest of `Defaults.Flow_box`, all read off a fresh widget |
| `gtk_flow_box_insert` **auto-wraps** a plain widget in a `GtkFlowBoxChild` | tempting, and wrong for `move` — see below |
| `gtk_flow_box_remove` accepts an **inner** child (unlike `gtk_list_box_remove`, which warns and does nothing) | noted in `child_of`'s comment so the asymmetry with Task 6 is not read as a copy error |
| `gtk_flow_box_select_child` on a child **not in the box** neither warns nor refuses — it sets the child's flag, and `is_selected` then answers `true` | the argument against the reverse map M6 carries: `child_by_key` walks the box, so a key naming a departed card simply does not resolve |
| `get_selected_children` answers in **widget** order | what `Attr.on_selected_children_changed` promises |
| `MULTIPLE → SINGLE` clears the whole selection; `unselect_all` is a no-op in `BROWSE`; `get_index` on an unparented child is `-1`; insert past the end clamps | as for `GtkListBox` |

**Correction 1 — the brief's "documented quirk" does not exist in GTK 4.22.** The brief
(and the commit message it proposed) says `GtkFlowBox.remove` does *not* emit
`selected-children-changed`. Measured: **it does**, and so does `remove_all`. stavekeeper's
own comment is about `remove_all`, and it is either stale for this GTK version or was a
mis-diagnosis of a different failure. I did not write the quirk into the impl's comments,
because it is not true. What I wrote instead is the stronger claim the case actually
supports: *it does not matter which way GTK goes*, because the selection is re-derived from
the widget on every pass rather than cached beside it — so the removed-selected-child case
recovers within a frame whether or not GTK announces it, and the test asserts the recovery.
That is still the strongest single argument for the declarative version; it just is not the
argument the brief expected.

**Correction 2 — `Child_keys.remove` before the GTK remove is belt-and-braces, not
load-bearing.** Task 6's Minor M2 established the ordering and `w_list_box.ml`'s comment
claimed that moving the line down "reintroduces exactly" a handler being handed the key of
a departed row. Mutation-tested here, on **both** containers: moving it changes nothing.
`selected_keys` answers by walking the children the container still holds, so a departed
child cannot appear in the answer whatever the table remembers. The ordering is kept (it is
free, and it keeps the table matching the tree at every point a handler could look) and
both comments are corrected to say so. New golden lines
(`the handler saw, as the row left: (none)` / `fb the handler saw, as the card left:
(none)`) pin the guarantee that *is* real — the handler is told the reduced selection, and
never the departing key — which neither container tested before.

---

## Deviations from the brief, with reasons

1. **`?orientation` added** (the task message named it; the brief's `Interfaces` block did
   not). `GtkFlowBox` is a `GtkOrientable` and the orientation is what makes
   `min/max_children_per_line` mean anything, so it is a prop like the rest. Default
   `Horizontal`, confirmed live, dropped from the sexp. The live test changes six props in
   one patch rather than the brief's five.

2. **Two geometry rejections at the constructor** (`max < 1`, and any negative), which the
   brief did not ask for. Both mistakes have no diagnostic worth the name — a critical on
   stderr with the old value silently kept, and a silent wrap to a huge unsigned number —
   which is exactly the test `Node.scrolled_window`'s min/max rejection already passes. Say
   if this should be documentation instead.

3. **No child attrs, and the "one naming scheme" question is moot.** The task message asked
   for `child_selectable`/`activatable` "or whatever Task 6's row attrs generalise to".
   They generalise to nothing: **`GtkFlowBoxChild` has neither property** — the binding's
   whole surface for it is `set_child`, `get_child`, `get_index`, `is_selected`, `changed`
   — so there is nothing for such an attr to write, and `Placement.read_by`'s `Flow_box`
   arm is `[]` exactly as the brief predicted. The scheme that *is* shared, and is now
   stated in `attr.ml`, is that **the attr is named after the GTK signal it carries**:
   `on_row_activated`/`on_selected_rows_changed` for `row-activated`/`selected-rows-changed`,
   `on_child_activated`/`on_selected_children_changed` for `child-activated`/
   `selected-children-changed`. The alternative — one shared `on_item_activated` — would
   have to be accepted on both kinds by `Events.for_kind`, and a line copied between the two
   containers would then be inert rather than rejected. `test_placement.ml` now lists the
   flow box among the containers *although it reads nothing*, so the empty list is a pinned
   decision rather than an omission.

4. **`Activate_row` gained a kind check too.** The brief specified the check for
   `Activate_child`; applying it to only one of a matched pair would have been the odd
   thing. Task 6's M5 carry (that `Activate_child` and `Set_page` should follow
   `Activate_row` in consulting *nothing* on the node) is untouched and honoured: the kind
   is not a fact about the user's action, it is which action this is. Neither the child list
   nor `~selected` nor any per-child flag is consulted.

5. **The `Selection_mode` and `Orientation` converters lifted to `Gtk_import`.** The first
   is Task 6's explicit carry ("lift when the second consumer arrives"), and I am it. The
   second was already duplicated four times from M1 (`w_box`, `w_separator`, `w_scale`,
   `w_paned`) and this task would have made a fifth copy; the four are deduped in the same
   commit. Not asked for, and I would revert it on request.

6. **A `Grid` page added to `examples/gallery.ml` now** rather than in Task 13, matching
   what Task 6 did for `Lists`. It is the geometry-as-a-prop demonstration: one
   `Node.toggle_button` drives `max_children_per_line`, `homogeneous` and both spacings, and
   a selection-dependent `Attr.sensitive` on a button beside it.
   `test/handle/test_gallery.ml`'s every-constructor sweep gains a `Node.flow_box`
   exercising every optional argument.

7. **An end-to-end activation test, for both containers, and it is new evidence rather than
   a scope change I could avoid.** `GtkFlowBoxChild::activate` is an action signal and it is
   what a click ends in, so `Gobject.Signal.emit_by_name … ~name:"activate"` — the idiom
   `live_driver.ml` already uses for `clicked` — makes GTK emit `child-activated` on the
   flow box, through this library's trampoline, through `Child_keys`, to the attr's handler.
   That checks the `Payload` spec's actual claim (*the key an application receives is the
   key of the card that was activated*) rather than only that a handler exists. The same
   works for `GtkListBoxRow::activate` → `row-activated`, so I added the list box's half in
   the same file: `task-6-report.md` recorded "what no test delivers is GTK's own
   click-to-activate" as an open gap, and it is closed for both containers now. It is *not*
   a synthetic click — GTK's pointer routing is still untested, and the backlog entry for
   that stands unchanged.

8. **No functor over `w_list_box.ml`**, per the brief, argued in a 20-line comment at the
   top of `w_flow_box.ml` naming what a functor would have to be parameterised on and where
   the two genuinely differ. The comment says explicitly that it is a judgement rather than
   a law and that Task 8's `GtkNotebook` is the point at which to settle it.

---

## Carries taken from `task-6-review.md`

All three, as instructed.

- **N1** — `node.mli`'s stack side now uses the same words the list-box side does ("inert",
  dropped before the comparison, selected on the frame it arrives) and names `flow_box`
  alongside `list_box`, so the cross-reference stays maintained as a pair.
- **N2** — "costs nothing and provokes no write" → "provokes no write". The narrowing is an
  O(children) scan per key per frame, which is M6's carried item; "costs nothing" was not
  literally true.
- **N3** — `w_list_box.ml`'s `row_activated` no longer upcasts in `connect` and downcasts in
  `fire`. `Signals`' `'p` is existential, so `connect` hands the callback a
  `W.List_box_row.t` and the bare `cast` is gone — which is the asymmetry the review
  flagged, since `row_of` two functions up goes to the trouble of a type-name check for
  exactly that reason. `w_flow_box.ml` was written this way from the start.

---

## What the tests prove, and the mutations that confirm they bite

`test/live/expected_lists.txt` gains 34 flow-box lines plus four dumps, pinning in order:
the `Child_keys` GC regression (250 frames + five `Gc.full_major`s); the mount golden; the
grid→list→grid geometry round trip (six props each way, one batch); a keyed reorder moving
the same `GtkFlowBoxChild` GObjects, where they moved to, and that the selection survived
it; a middle insert and a middle removal; the declined selection; add-and-select in one
frame; the selected card removed *and what the handler was told while it left*; the stale
key held beside a live one, with a write count of 0; the card coming back selected on the
frame it returns; a multi-selection listed the other way round with a write count of 0;
three keys in `Single`; a `None_` grid refusing a selection; activation delivering the key
through GTK's own emission; teardown firing no handler; and the whole declined-selection
cycle through a real `Driver.frame`.

Six mutations run against the committed tree:

| Mutation | Caught by |
|---|---|
| `Child_keys` keyed on the `GtkFlowBoxChild` wrapper instead of the card | `fb gc: … selected a,b` → `(none)` at all five checkpoints |
| ghost-key narrowing dropped from `apply_selection` | `fb writes on an identical frame with the removed key held: 0` → `2` |
| `apply_selection` compares unsorted | `fb writes for a re-ordered but equal selection: 0` → `3` |
| `move` re-inserts the inner card and lets GTK auto-wrap | **SIGSEGV, exit 139**, preceded by `gtk_flow_box_child_set_child: assertion … failed`; the golden truncates at `fb after mount: b` |
| the `Flow_box` arm of `enqueue_fixups` removed | five lines move, from `fb gc: mounted, selected (none)` to `fb driver, after mount: (none)` |
| `Child_keys.remove` moved after the GTK remove (both containers) | **not caught, and correctly so** — see Correction 2; the comments claiming otherwise are fixed |

Two of these are worth a sentence. The `move` mutation is the reason this impl wraps
explicitly even though `GtkFlowBox` auto-wraps: re-inserting the inner card makes GTK build
a *second* wrapper, and the first is freed while the tree still points at it. And the
ghost-key mutation only bites when the model holds a stale key **beside a live one** — my
first version of that case held only the stale key, so `unselect_all` on an already-empty
selection emitted nothing and the write count stayed 0 either way. The case was
restructured; that is a shape worth copying into Task 8.

Zero GTK criticals, warnings or assertion failures across all nine live executables,
individually checked (Task 6's M1 habit):

```
live_patcher 0 · live_driver 0 · live_signals 0 · live_controls 0 · live_containers 0
live_events 0 · live_controllers 0 · live_keyvals 0 · live_lists 0
```

Counts updated: `test_events.ml` / `live_events.ml` `all_kinds` 30 → 31 (asserted against
`Kind.Variants.descriptions`); `test_placement.ml`'s non-placement name count 36 → 38.

**Not pinned:** `Child_keys.remove` in `list_ops.remove` (a bounded leak into a
process-wide table, not a behaviour — same position as Task 6); and `Live_tree`'s
`GtkFlowBox` orientation atom is redundant with the `horizontal`/`vertical` CSS class GTK
maintains beside it, which is noted in the code as deliberate.

## Test/CI tails

```
$ nix develop -c ./scripts/ci.sh
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

```
$ BONSAI_GTK_LIVE_TESTS=1 nix develop -c xvfb-run -a dune build @test/live/runtest
(clean; the one stderr line above is live_driver.ml's deliberate raise)
```

---

## Carries for Task 8 (Notebook)

- **`Child_keys`' lifetime rule is the one to get right first.** Key on the widget the
  patcher stores in `live.widget`. Task 6 established that a notebook is *not* a wrapper
  case: `gtk_notebook_remove_page` takes a page index and the page's content is a direct
  child of the notebook, so `Widget.get_parent` gives the notebook. Confirm against the
  binding before writing; the flow box's `child_of` is the wrong template there.
- **Read the stub, not the GIR**, for every object-returning getter. 46 of the binding's 47
  `Val_GList_with` sites do not sink; the flow box's is the one that does.
- **`Node.require_child_keys ~which ~why`** is the shared constructor-time check; the
  notebook adds one call. There is now a second precedent for constructor-time *value*
  checks too (`Node.flow_box`'s geometry bounds) if `GtkNotebook` has a similar trap.
- **The ghost-key test needs a live key beside the stale one** or the write count cannot
  move — see above. Copy the restructured shape, not the first one.
- **`Set_page`'s decision is pre-made:** follow `Activate_row`/`Activate_child` — consult
  nothing on the node except the kind, and check the kind. `Set_selection` stays shared
  between the two selection containers; a notebook's current page is singular and is
  `Set_page`'s.
- **`move = Some …` with `~ordered:true`** for the notebook: it has a real
  `reorder_child`, unlike the list box and the flow box, which both implement `move` as
  remove-and-re-insert.
- **`GtkNotebookPage::activate`-style end-to-end emission** is worth checking for: the
  `emit_by_name ~name:"activate"` trick that closed the activation gap for both containers
  here may have an equivalent for `switch-page`.
- **M6 (perf) is still carried and is now sharper.** `apply_selection` is
  O(|selected| × children) and runs `child_by_key` twice per key on the frames it writes.
  For a library grid of several hundred cards this is the thing to revisit; the answer is a
  per-container reverse map, and the measurement above is the constraint on it —
  `gtk_flow_box_select_child` silently "selects" a detached child, so a reverse map that
  outlives a removal is worse than the walk, not just faster.
- **`Live_tree` prints no keys**, here or in Task 8; print `W_<container>.selected_keys`
  from the live test instead, which is a read *through* the table.
- **The no-functor decision is deliberately unsettled.** `w_flow_box.ml`'s header argues it
  and says Task 8 is where to have the argument. If the reviewer disagrees, now is the time.

---

# Fix round 1 — review `task-7-review.md`

**Commit:** `e9e7793` on `m2`, base `3d05a83`. 7 files, +224/−35.
**Gate:** `nix develop -c ./scripts/ci.sh` → `all green`.

I1 accepted without argument — the reviewer's diagnosis, numbers and fix are all correct,
and the deferral I proposed had a premise that had already expired. M1 accepted. Of the
five Minors, four are taken and one (M4) is agreed as a recorded gap.

---

## I1 — `apply_selection` cost a whole frame budget to decide that nothing had changed

**Accepted; ruled fix-now rather than carry, and the ruling is right.** My report said "for
a library grid of several hundred cards this is the thing to revisit" and then carried it
to Task 8 — which is a `GtkNotebook` and would never have had the evidence. That is the
third deferral the review names, and it was mine.

**Reproduced before touching anything.** The regression the lead asked for went in first,
against the shipped code, so the "before" is this repository's own instrument rather than
the reviewer's worktree:

```
bench: 24.171 ms per idle frame (bound 2)     <- shipped code, three runs
bench: 20.104 ms per idle frame (bound 2)
bench: n=1000, selected 200 of 200
bench: 200 idle frames, under 2 ms each: false
```

**After**, three consecutive runs plus the two the gate performed under CI load:

```
bench: 0.392 / 0.400 / 0.394 ms per idle frame     (isolated)
bench: 0.494 / 0.411 ms per idle frame             (inside ./scripts/ci.sh)
bench: 200 idle frames, under 2 ms each: true
```

0.39 ms matches the reviewer's independently measured 0.386 ms. **A 50x improvement at
n=1000/sel=200**, and the bound has ~4x headroom even under a loaded gate, which is what
keeps the assertion from being flaky.

**The fix is the reviewer's, in both files.** One walk of the container; a
`Hashtbl` built from it; `current` filtered out of the same list so there is no second
walk. `current` still answers in widget order (`all` is in widget order), the
sort-before-compare is untouched, the narrowing is untouched, and the write still iterates
the **unnarrowed** `selected`, so ruling 5 is unchanged.

Two details beyond the sketch:

- **First-key-wins is preserved.** `List.find` answered with the first matching child;
  `Hashtbl.set` would answer with the last. Duplicate sibling keys are rejected by
  `Reconcile.check_unique_keys` at mount *and* at patch, so the two cannot differ today —
  but `Hashtbl.add` with the `` `Duplicate `` ignored costs one line and keeps that from
  mattering if the invariant ever moves. Commented as such.
- **The comment carries the safety argument, not just the speed one**, which is the fact
  the reviewer said a later reader most needs. `child_by_key`/`row_by_key` keep the walk
  and now say outright: *never cache this into a table that outlives the call*, with the
  measurement behind it (`gtk_flow_box_select_child` on a detached child neither warns nor
  refuses — it sets the flag, and `is_selected` then answers `true` for a widget the box
  never held). `apply_selection`'s comment then says why a **per-call** table is a
  different thing: built from the walk it already does, dead at the end of the call, so a
  key naming a child that left between two frames is absent from the *next* frame's table,
  resolves to nothing, and is inert.

**Landed in `w_list_box.ml` too**, per the ruling. The reviewer's note under deviation 8 is
the one I would flag for Task 8: this is the first change that has had to be made twice,
and a third would be the evidence the no-functor header comment says would settle it.

**Goldens.** With I1 alone applied, `test/live/expected_lists.txt` was **byte-identical** —
verified by diffing the run against the committed golden, whose only difference was the two
new `bench:` lines. Every claim the golden pins (ghost-key inertness, both write counts,
the sorted comparison, the same-frame rule, `Single`/`None_` arbitration) survives the
rewrite untouched. The golden lines that *did* move in this commit are all from M3 and M5
below, itemised there.

**Mutations re-run against the rewritten function**, because a faster implementation that
is no longer pinned would be a bad trade:

| Mutation | Caught by |
|---|---|
| narrowing dropped (`wanted = selected`), flow box | `fb writes on an identical frame with the removed key held: 0` → `2` |
| narrowing dropped, list box | `writes on an identical frame with a ghost key held: 0` → `2` |
| comparison unsorted, flow box | `fb writes for a re-ordered but equal selection: 0` → `3` |
| comparison unsorted, list box | `writes for a re-ordered but equal selection: 0` → `3` |
| `Child_keys` keyed on the wrapper | `fb gc: … selected a,b` → `(none)` at all five checkpoints |

**The benchmark's shape.** `n=1000`, `sel=200` spread through the list (`i * (n / sel)`)
rather than taken from the front, so neither the walk nor the table is flattered by
locality; 200 frames of `reassert_only` + `run_fixups` inside `Scheduler.with_patch_guard`,
which is what `Driver.frame` runs on a physically-same-node frame. The golden gets the
**verdict** and the selection count (`selected 200 of 200` — so a fixup that had quietly
stopped doing anything could not pass); the **number** goes to stderr, which dune does not
compare, so a future failure says how far over it went rather than only `false`.

---

## M1 — the one public-facing doc still gave the ordering as the reason

**Accepted.** `vtree/attr.mli`'s `on_selected_children_changed` said the departing key is
gone from the table "**so** a handler is never handed" it — the exact causal link
Correction 2 removes, in the one place applications read. Now:

> …a handler is never handed the name of a child that has just left the tree, because the
> selection is read by walking the children the flow box still holds and GTK emits this
> signal after unparenting the departing one. (The implementation also drops the child's
> key before telling GTK to remove it, but that ordering is belt-and-braces — it is the
> walk that makes the guarantee.)

The reviewer's independent confirmation of the mechanism (the mid-remove handler sees
`a*,c`, with `d` already gone) is the same thing my `the handler saw, as the … left` lines
now pin, and M3 below makes those lines able to tell the two outcomes apart.

---

## Minors

**M2 (taken — documented rather than rejected).** `~min_children_per_line` above
`~max_children_per_line` is now covered by `Node.flow_box`'s doc, which says the maximum
wins and that `~min:6 ~max:3` lays out three per line exactly as `~min:0 ~max:3` does. I
chose the doc over a rejection on the reviewer's own evidence: the resolution is
deterministic and in the caller's favour, and the arrangement that produces it is a working
pattern — a view that switches to a list by setting `~max_children_per_line:1` while a
minimum from the grid view is still in scope gets its list. A rejection would turn that
into an exception for tidiness, which is not what the other two checks are for (those catch
a value GTK *discards*, silently). Say if the check is preferred; it is four lines.

**M3 (taken).** The removed-selected-child case could not distinguish "the reduced
selection" from "the empty selection" — with only `d` selected, both print `(none)`. Both
containers now hold a live key beside the departing one:

```
two selected before the removal: a,d          fb two selected before the removal: a,d
selected row removed: a                       fb selected card removed: a
the handler saw, as the row left: a           fb the handler saw, as the card left: a
```

`a` rather than `(none)` is the line a handler reporting nothing at all cannot produce.
This is the same restructuring the ghost-key case needed in the first round, applied to the
second case that had the same weakness — and the general lesson for Task 8 is now stated
twice in the report: *a case whose expected output is the empty/absent value usually cannot
move*.

**M5 (taken).** `Browse` was untested for the flow box. One frame selecting `a` in `Browse`
(with its dump, which is the only route to `(selection-mode browse)`) and one asking for an
empty selection:

```
fb in Browse mode: a
fb Browse asked for an empty selection: a
```

The second is the documented "a model that disagrees with its mode" case reached from the
mode where it is unavoidable: `unselect_all` is a no-op in `Browse`, so the write goes out
as asked, GTK keeps what it kept, and the comparison differs again next frame. Nothing
raises and the selection does not empty — which is what the constructor's doc promises and
what nothing pinned before.

**M6 (taken).** `examples/gallery.ml`'s `layout` is now "Page 5".

**M4 (agreed, no change).** `forget_children`'s and `forget_rows`' destroy arms are
unpinned — removing either leaves the golden byte-identical. The reviewer files this as a
recorded gap rather than a request ("not worth doing for one container"), and I agree with
both halves: it is a bounded leak into a process-wide table rather than a behaviour, and
the only way to observe it is to expose the table's size, which is a test-only hole in
`Child_keys`' interface. It joins the report's existing "not pinned" note about
`Child_keys.remove`. If the lead wants it closed, the shape is a `Child_keys.length`
exposed for tests and one live case per container, and it should be done for all three
containers at once in Task 8.

---

## Golden changes in this round, itemised

Every line that moved, and why — the lead asked specifically:

| Change | Cause |
|---|---|
| `selected row removed: (none)` → `a`, and the same for `fb` | M3 — the case is now `Multiple` with a live key beside the departing one |
| `the handler saw, as the … left: (none)` → `a` (both) | M3 |
| `two selected before the removal: a,d` (both, new) | M3 — the setup frame |
| `fb selection with the removed key still held: a` removed | M3 — the removal frame now renders that selection, so the line was a duplicate of it; the write-count pair below it is unchanged and still reads `0` |
| `fb in Browse mode: a` + its dump, `fb Browse asked for an empty selection: a` (new) | M5 |
| two `bench:` lines (new) | I1's regression |

**No line moved because of the I1 fix itself**, which was the point of checking it
separately.

## Test/CI tails

```
$ nix develop -c ./scripts/ci.sh
== nix: ocgtk pin builds and passes its tests
== format
== build
== generated opam files are committed
== pure + headless tests
== per-package builds, the way opam --with-test runs them
== live tests (xvfb)
bonsai_gtk: exception in frame, stopping the driver: (Invalid_argument
  "root/0/1: a Node.window may only be the root node, not a child of another node")
bench: 0.411 ms per idle frame (bound 2)
== example smoke
all green
```

## Carries updated for Task 8

- **`apply_selection` is no longer the carried M6.** It is fixed in both containers and
  regression-tested; a notebook's current page is singular, so the shape does not recur —
  but the *rule* does: **never cache a key→widget map beyond the call**, because
  `select_child` accepts a detached child silently. Stated on `child_by_key` and
  `row_by_key`.
- **The no-functor decision has its first piece of contrary evidence.** I1 is the first
  change that had to be made twice, identically. If Task 8 produces a third, the header
  comment in `w_flow_box.ml` says that is when to have the argument.
- **A case whose expected output is empty usually cannot move.** Two cases in this task
  (the ghost key, then the removed selected child) needed restructuring for exactly that
  reason. Check the shape before writing the golden, not after.
- **`Child_keys` has no size accessor**, which is what leaves both containers' teardown
  sweeps unpinned (M4). Close it for all three containers at once or not at all.
