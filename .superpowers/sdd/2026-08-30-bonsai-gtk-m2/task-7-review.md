# Task 7 review — FlowBox: keyed children, controlled selection, geometry as a prop diff

**Commit reviewed:** `3d05a83` on `m2`, base `f573799` (34 files, +2027/−81).
**Gate re-run by the reviewer:** `nix develop -c ./scripts/ci.sh` → `all green`, exit 0.
The one stderr line is `live_driver.ml`'s deliberate raise, as the report says.
Mutation work done in a throwaway worktree at `3d05a83`, since removed; the checkout is
unmodified.

---

## Summary

This is the cleanest task in the milestone so far. Every rule Task 6 established is
carried over deliberately rather than by copy: `Child_keys` is keyed on the card the
patcher retains (C1b) and the GC-churn regression test proves it; the ghost key is
narrowed out before the comparison (I1) and the write-count line bites; the same-frame
rule is pinned from both directions; `move` wraps explicitly and the mutation that does
not segfaults. The three N-carries from `task-6-review.md` all landed. The binding-safety
check the brief asked for is right, and I re-read all four stubs myself rather than
taking the table: `gtk_flow_box_get_selected_children` (`ml_flow_box_gen.c:216-233`),
`get_child_at_index` (`:285-293`), `gtk_flow_box_child_get_child`
(`ml_flow_box_child_gen.c:53-60`) and `gtk_widget_get_parent` (`ml_widget_gen.c:871-878`)
all `g_object_ref_sink`. The decision to walk anyway, and the three reasons for it, are
sound.

I re-measured every GTK fact the report claims. All of them hold, including both
corrections, which is the part of the report I was most inclined to doubt:

| Claim | Measured |
|---|---|
| `max-children-per-line` defaults to a real 7 | `fresh: max=7` |
| the four geometry ints are unsigned | `set_min (-1)` → `65535`; `set_row_spacing (-5)` → `4294967291` |
| **Correction 1:** `gtk_flow_box_remove` *does* emit `selected-children-changed` | fires once, and only when the removed child was selected |
| ...and so does `remove_all` | fires once *per selected child* (2 of 2, 1 of 1, 0 when nothing was selected) |
| the emission happens *after* the child is unparented | signal handler walking the box sees `a*,c` — the departing `d` is already gone |
| `MULTIPLE → SINGLE` clears the whole selection | both selected children come back `false` |
| `select_child` on a detached child sets its flag silently | `is_selected` → `true` for a widget the box never held |
| `get_index` on an unparented child is `-1`; insert past the end clamps | `-1`; `insert … 99` lands at index 2 of 3 |
| `gtk_flow_box_remove` accepts an inner child | yes (the `GtkListBox` twin does not) |
| `unselect_all` is a no-op in `BROWSE` | selection survives |

The `remove_all` measurement is the one that matters beyond this repo: stavekeeper's
`library_window.ml:88-97` comment ("GTK's FlowBox does not appear to fire that signal from
`remove_all`") is stale for GTK 4.22, and the report is right to refuse to write it into
the impl. The emission ordering (signal *after* unparent, in both containers) is what
makes Correction 2 true, and I confirmed Correction 2 the way the report says it should be
confirmed — see the mutation table.

Two things are worth acting on. One is a measured performance pathology in
`apply_selection` that is inherited verbatim from `w_list_box.ml` and was deferred by Task
6's review on a scale argument that this task's container invalidates; I have numbers and a
verified 12-line fix. The other is that the one public-facing doc paragraph in the diff
still states the claim the rest of the commit exists to correct.

---

## Per-deviation judgement

**1. `?orientation` added — sound.** `GtkFlowBox` is a `GtkOrientable`, the orientation is
what makes `min/max_children_per_line` mean anything, and it is defaulted to the measured
`Horizontal` and dropped from the sexp like the rest. `Live_tree` reads the property
directly rather than inferring it from the `horizontal`/`vertical` CSS class GTK maintains
beside it, and says why (`src/live_tree.ml:481-486`); that is the right call — the class is
GTK's bookkeeping, not the property. The live test's grid→list→grid round trip moves it
with the other five. Accept.

**2. Two geometry rejections at the constructor — sound, and better than documentation.**
Both mistakes really do have no diagnostic worth the name: a `0` maximum is a
`g_return_if_fail` critical with the old value silently kept, and a negative reaches GTK as
a very large positive with nothing on stderr at all (I reproduced both). `Node.scrolled_window`
is the right precedent and the messages name the argument and the value. Accept — with one
gap in the analogy, see **M2**.

**3. No child attrs, and the naming scheme stated — sound, and the argument is the right
one.** `GtkFlowBoxChild` genuinely has no `selectable` and no `activatable`, so there is
nothing for such an attr to write; `Placement.read_by` has no `Flow_box` arm and the
wildcard rejects `Attr.row_selectable` on a flow box child with a message naming both
containers (`test/handle/test_handle.ml`, "the row attrs are rejected on a flow box
child"). Listing the flow box in `test_placement.ml`'s `read_by and reader agree` although
it reads nothing — so `(FlowBox ())` is printed — is the right way to make an empty list a
decision. The naming rule ("the attr is named after the GTK signal it carries") is stated
in `vtree/attr.ml:173-179` and enforced by `Events.for_kind` giving each container its own
pair, which the near-miss test pins (`ListBox does not emit On_child_activated`). This
answers the brief's "one naming scheme" question in the only way GTK allows. Accept.

**4. `Activate_row` gained a kind check too — sound.** Applying it to one of a matched pair
would have been the odd thing, and Task 6's M5 carry is honoured exactly: the kind is
consulted, nothing else on the node is. `test_lib/bonsai_gtk_test.mli:106-131` says so and
the failure messages are the more useful half of the truth
(`node grid is a FlowBox, not a ListBox`). `Set_selection` staying shared and dispatching
on the kind it finds is right — it is the same question of both containers. Accept.

**5. The `Selection_mode` and `Orientation` converters lifted to `Gtk_import` — accept.**
The first is Task 6's explicit carry and the second was a fourth copy about to become a
fifth. Both are pure moves (I diffed the bodies); the four call sites lose a shadowing
local and nothing else. Mild creep, clearly net-positive, and offered for reversion.
Accept.

**6. A `Grid` page in `examples/gallery.ml` now — accept**, on Task 6's precedent. It is
the geometry-as-a-prop demonstration and it is the only place in the repo where one toggle
drives four props of one widget. `test/handle/test_gallery.ml`'s sweep exercises every
optional argument including `~orientation`. See **M6** for a stale comment it leaves.

**7. End-to-end activation for both containers — accept, and this is the best thing in the
diff.** `Gobject.Signal.emit_by_name … ~name:"activate"` on the wrapper drives
`GtkFlowBoxChild::activate` → `child-activated` → this library's `Payload` trampoline →
`Child_keys` → the attr's handler, which is the first test in the milestone that checks
the *value* an application receives rather than that a handler exists. Adding the list
box's half in the same commit closes a gap `task-6-report.md` recorded as open. The report
is careful to say this is not a synthetic click and that the pointer-routing backlog entry
stands; that framing is correct. Accept.

**8. No functor over `w_list_box.ml` — agree, and I am saying so now rather than at the
final review, as the brief asked.** I read both files side by side. The genuinely shared
part is `apply_selection` (~14 lines), the `children` walk (~7), and the shape of
`insert`/`move` (~12) — and a functor over them would need the container type, the wrapper
type, six method names, two signal names, two attr names and the props record. The two also
diverge structurally in ways a functor would have to paper over: the list box has a
placeholder *slot* and per-row flags with a real `updated`, the flow box has neither and
seven geometry props; `gtk_list_box_remove` refuses an inner child and `gtk_flow_box_remove`
accepts one. The 20-line header comment names all of this and flags itself as a judgement.
The one thing I would ask for is that whatever fix lands for **I1** below lands in *both*
files, because that is the first change that has had to be made twice — and if Task 8
produces a third, that is the evidence the header comment says would settle it.

---

## Critical

None.

---

## Important

### I1. `apply_selection` is O(|selected| × children) and runs on every frame: a `Multiple` grid of 1000 cards with 200 selected costs 16 ms per idle frame, and 500-of-500 costs 24 ms

`src/widgets/w_flow_box.ml:187-201` (and, identically, `src/widgets/w_list_box.ml:211-225`)

```ocaml
let current = selected_keys w in                                   (* one walk: O(n) *)
let wanted = List.filter selected ~f:(fun key -> Option.is_some (child_by_key w key)) in
                                                                   (* O(|selected| * n) *)
if not (…) then (… List.iter selected ~f:(fun key ->
  Option.iter (child_by_key w key) …))                             (* O(|selected| * n) again *)
```

`child_by_key` (`:149-153`) is a linear `get_child_at_index` scan per key, and
`apply_selection` runs from the fixup queue on every mount, every patch **and** every
no-change frame through `reassert_only` (`src/patcher.ml:222-228`, `:812-815`). So the
per-frame cost is `n + |selected| × n`, plus another `|selected| × n` on the frames it
writes.

**Measured** on the committed tree, driving the patcher exactly the way `Driver.frame`
does (`Scheduler.with_patch_guard` around `reassert_only` + `run_fixups`), 200 frames
averaged, `Multiple`:

```
n=1000 sel=   1   idle frame:  0.286 ms   (apply_selection alone:  0.171 ms)
n=1000 sel=  50   idle frame:  4.192 ms   (                        4.060 ms)
n=1000 sel= 200   idle frame: 16.464 ms   (                       14.513 ms)
n= 500 sel= 500   idle frame: 23.871 ms   (                       23.696 ms)
```

At 200-of-1000 an **idle** frame consumes the whole 16.7 ms budget doing nothing; at
500-of-500 the driver cannot reach 60 fps at all while the selection is held, and a ticking
driver burns a core continuously. The user-visible failure is: *a grid becomes unusable
after the user selects a few hundred cards, and stays unusable until they deselect.*

**Why I am raising it here rather than treating it as the carried M6.** Task 6's review
graded the identical shape Minor with the reason "fine at sidebar scale … but `W_flow_box`
in Task 7 will have the same shape over many more children". Task 7 is where the scale
arrives — a library grid is the one container in the plan with hundreds of children — and
the report itself says "for a library grid of several hundred cards this is the thing to
revisit", then defers it to Task 8, which is a `GtkNotebook` and will not have the
evidence. The premise of the deferral has expired.

**Why the fix is not the reverse map the impl argues against, and is safe.** The impl's
objection to a key→child map (`:143-148`) is exactly right and I confirmed the measurement
behind it — `gtk_flow_box_select_child` on a detached child silently sets its flag, so a
map that *outlives a removal* is worse than the walk. But that objection is about a
**persistent** map. A map built fresh inside `apply_selection`, from the one walk it
already performs, cannot outlive anything:

```ocaml
let apply_selection (w : Widget.t) ~selected =
  let sorted = List.sort ~compare:String.compare in
  let all = children (cast w) in
  let by_key = Hashtbl.create (module String) in
  List.iter all ~f:(fun c ->
    Option.iter (key_of_child c) ~f:(fun k -> Hashtbl.set by_key ~key:k ~data:c));
  let current =
    List.filter all ~f:W.Flow_box_child.is_selected |> List.filter_map ~f:key_of_child
  in
  let wanted = List.filter selected ~f:(Hashtbl.mem by_key) in
  if not (List.equal String.equal (sorted current) (sorted wanted))
  then (
    let fb : W.Flow_box.t = cast w in
    W.Flow_box.unselect_all fb;
    List.iter selected ~f:(fun key ->
      Option.iter (Hashtbl.find by_key key) ~f:(W.Flow_box.select_child fb)))
;;
```

`current` still answers in widget order (`all` is in widget order), the sort-before-compare
is untouched, the narrowing is untouched, and the write still iterates the unnarrowed
`selected` — so ruling 5 is unchanged. I applied this in the worktree and re-measured:

```
n=1000 sel=   1   idle frame: 0.349 ms      n=1000 sel= 200   idle frame: 0.386 ms
n=1000 sel=  50   idle frame: 0.358 ms      n= 500 sel= 500   idle frame: 0.269 ms
```

`test/live/expected_lists.txt` is **byte-identical** with the fix in place, i.e. every
claim the golden pins — the ghost-key inertness, the write counts, the sorted comparison,
the same-frame rule, the `Single`/`None_` arbitration — survives it unchanged. Single
selection gets ~0.06 ms slower at n=1000 from building the table; that is a good trade for
removing the quadratic term, and not worth guarding.

**Please land it in `w_list_box.ml` too** — the code is the same and the sidebar merely
happens to be small.

**Test:** the existing write-count instrument is the wrong shape for this (it counts
emissions, not time). A frame-time assertion would be flaky. I would pin it structurally
instead: a live case with `Multiple`, ~50 cards, all selected, asserting the golden's
selection and letting the fix stand on the measurement recorded here — or, if the lead
prefers, no test at all and a sentence in the code saying the map is per-call *because* a
persistent one is unsafe, which is the fact a later reader most needs.

**If the lead judges `Multiple`-at-scale out of scope for M2**, the acceptable alternative
is to re-defer explicitly with the numbers: record the measurement in
`docs/m1-backlog.md` and add one sentence to `Node.flow_box`'s and `Node.list_box`'s docs
saying that a large `Multiple` selection costs O(|selected| × children) per frame. What
should not happen is a third silent deferral on a scale argument.

---

## Minor

**M1. `Attr.on_selected_children_changed`'s doc still gives the ordering as the reason —
the exact claim this commit corrects in all three other places.** `vtree/attr.mli:455-457`:

> It fires when a selected child is *removed*, too, with the reduced selection; the key of
> the departing child is gone from the table before GTK is told to remove it, **so** a
> handler is never handed the name of a child that has just left the tree.

Both halves are individually true, but the "so" is the false causal link Correction 2
exists to remove. I verified Correction 2 the hard way: moving `Child_keys.remove` after
the GTK call in **both** `w_flow_box.ml:311-325` and `w_list_box.ml:383-395` leaves
`expected_lists.txt` byte-identical, and the reason is measurable —
`gtk_flow_box_remove` and `gtk_list_box_remove` both emit their selection signal *after*
`gtk_widget_unparent`, so a walk-based `selected_keys` cannot see the departing child
whatever the table remembers (probe output: the handler fired mid-remove sees `a*,c`, with
`d` already gone). This is the one public-facing doc in the diff, `on_selected_rows_changed`
makes no such claim, and leaving it invites a maintainer to conclude the ordering is
load-bearing somewhere else. One clause: "…because the selection is read by walking the
children the box still holds".

**M2. `Node.flow_box` does not reject `~min_children_per_line > ~max_children_per_line`,
though the precedent it cites does.** `vtree/node.ml:449-495` rejects a `< 1` maximum and
any negative, and the rationale is `Node.scrolled_window`'s min/max bound — but the thing
`scrolled_window` actually checks (`vtree/node.ml:290-300`: "GTK calls a min above a max a
programming error and checks nothing at runtime") is the cross-check that is missing here.
Measured: `min=9 max=3` is accepted silently, and the layout takes the maximum — six cards
in a 1200px window lay out three per line with `min=6 max=3`, identically to `min=0 max=3`.
So the resolution is deterministic and usually what the caller meant (a "list view" that
sets `max:1` while leaving an old `min:2` behind gets its list view), which is why this is
Minor rather than part of the deviation-2 judgement. Either add the check or say in the
doc which one wins; silently ignoring one of two numbers the caller wrote is the shape the
other two rejections exist to prevent.

**M3. The removed-selected-child assertion is single-selection only, so it cannot tell
"the reduced selection" from "the empty selection".** `test/live/live_lists.ml:825-841`
removes card `d` with `~selected:["d"]`, and the golden reads
`fb the handler saw, as the card left: (none)` — which is also what a broken handler that
reported nothing would print. `Multiple` with `~selected:["a";"d"]` removing `d` should
report `a`, which distinguishes them; I confirmed GTK delivers exactly that. Same shape in
the list box's half (`:327-336`). The report tells Task 8 to copy the *ghost-key* case's
restructuring for the same reason ("the first version could not move"); this case wants
the same treatment. One line each.

**M4. `forget_children`'s destroy arm is unpinned.** Replacing
`src/patcher.ml:438` with `| Flow_box _ -> ()` leaves `expected_lists.txt` byte-identical
(verified). The arm is correct, correctly placed, and carefully commented about *why* it
must sit above the or-pattern chain — but nothing would catch its removal, and the same is
true of `forget_rows`. This is the same position as Task 6's M1 and the report's own "not
pinned" note about `Child_keys.remove`; recording it so the pair stays a known gap rather
than an assumed test. A `Child_keys.find` count exposed for tests would close both, and is
not worth doing for one container.

**M5. `Browse` is untested for the flow box, and so is the explicit `single` `Live_tree`
spelling.** `live_lists.ml`'s flow-box block uses `Multiple`, `Single` and `None_`, so
`(selection-mode browse)` never appears in a golden — and `Browse` is the mode with the
behaviour worth pinning, because `unselect_all` is a no-op there (measured) and a model
asking for an empty selection therefore disagrees with the widget forever. This is Task 6's
M3, partially closed: `(selection-mode none)`, `(selection-mode multiple)` and
`activate-on-double-click` *are* now pinned, which the list box's golden did not manage.
One extra frame.

**M6. `examples/gallery.ml:199` and `:261` are both commented "Page 4".** The new grid page
took the number and `layout` is now page 5. Cosmetic.

---

## Checks that came back clean

Recorded so a later reader knows they were looked at rather than skipped.

- **The four binding stubs**, read in the stub rather than the GIR as Task 6's rule
  requires. All four sink; the `get_selected_children` hand patch carries a comment naming
  the bug it fixes. The decision to walk anyway is argued on three grounds that are not
  "the getter is unsafe", and the comment says so outright — which is what stops a reader
  inferring an identical defect from the two files' identical shapes.
- **`Child_keys` keyed on the retained child (C1b).** Keying on the wrapper instead makes
  `fb gc: … selected a,b` become `(none)` at all five checkpoints. The regression runs
  first in its block, as it must.
- **The ghost key is inert (I1's rule).** Dropping the narrowing takes
  `fb writes on an identical frame with the removed key held` from `0` to `2`; the case
  correctly holds a live key beside the stale one, without which it cannot move.
- **The sort before the comparison.** Making it the identity takes
  `fb writes for a re-ordered but equal selection` from `0` to `3`.
- **`move` holds the wrapper.** Re-inserting the inner card instead is **SIGSEGV (139)**,
  preceded by `gtk_flow_box_child_set_child: assertion … failed`; the golden truncates at
  `fb after mount: b`. This is the load-bearing difference from GTK's auto-wrapping and it
  is pinned.
- **The fixup arm.** Removing `Flow_box` from `enqueue_fixups` moves five GC lines and the
  mount golden and empties every selection.
- **Insert index arithmetic.** Dropping the `+ 1` reorders the mount golden and the GC
  block. `after = None` → index 0; the predecessor's own `get_index` is GTK's answer, which
  is correct because a flow box interposes nothing but the wrappers this impl made.
- **Identity across list ops.** Reorder (same GObjects, `Gobject.same` as a set, and where
  each landed: `1,2,0`), middle insert, middle removal, and a selection surviving the
  reorder. `move = Some`, so `~ordered:true` and no `Unordered` marker — parity with the
  list box, and correct: `GtkFlowBox` has no `reorder_child_after`, so remove-and-re-insert
  is the only implementation and it preserves identity because the wrapper is held across
  the unparenting.
- **Kind change in place** goes through `patch_list`'s `ops.remove; ops.insert` pair
  (`src/patcher.ml:703-706`), which for this container removes the old wrapper, drops its
  `Child_keys` entry and builds a fresh one — the same path the list box's `kind change
  kept the selection` case exercises. Untested for the flow box; the path is shared and
  the arithmetic is pinned by the middle-insert case, so I am not filing it.
- **A child removed while selected.** GTK emits `selected-children-changed` after
  unparenting; the handler is given the reduced selection and never the departing key; the
  fixup finds a key naming no child, treats it as inert, and writes nothing. The model
  never sees a dead key. Under a real `Driver.frame` the emission is dropped entirely.
- **`in_patch` on programmatic writes.** `Patcher.run_fixups` is *inside*
  `Scheduler.with_patch_guard` (`src/driver.ml:61-71`), and the driver-level case pins the
  consequence: `fb driver, after the frame the click armed: a (Bonsai saw 1)` — Bonsai saw
  the user's click and not the fixup's write, and one more frame does not move it.
- **Mode changes.** `Multiple → Single` clears GTK's selection inside `update`, and the
  fixup that runs after the pass puts the model's back — pinned by the grid→list patch,
  whose dump shows `(selected-children 1)` on B after the mode moved. The residual
  (three keys in `Single`, any key in `None_`) rewrites every frame and is the documented
  "a model that disagrees with its mode" case; `fb three keys in Single mode: b` and
  `fb asking a None_ grid for a selection: (none)` pin what GTK arbitrates.
- **Geometry as a prop diff.** Six props change in one patch and six change back, and the
  third dump is identical to the first — which is what makes it a diff rather than a
  one-way trip. `update` writes only the fields that moved, inside one
  `Widget_impl.batch`; the unconditional `batch` (rather than `batch_if`) is correct here
  because `update` runs only when `Kind.equal_props` is false (`src/patcher.ml:533-534`),
  i.e. at least one prop moved. Write order matches `write_props`, and no intermediate is
  reachable outside the freeze/thaw. `reassert = None`, so `batch_if` has no role.
- **`Live_tree`'s `GtkFlowBox` arm** prints all seven props against their defaults plus the
  selection count, reads the orientation from the property rather than from the CSS class
  beside it, and prints no keys. `W.Orientable.from_gobject` refs its result
  (`ml_orientable_gen.c:46`), so the repeated call in a dump loop is balanced.
- **Counts and negatives.** `all_kinds` 30 → 31 in both lists, asserted against
  `Kind.Variants.descriptions`; `test_placement.ml` 36 → 38; `is_event` partition updated
  in both halves; `require_specs` negatives for both new attrs including the near-miss on a
  `ListBox`; `Placement` negatives for both row attrs on a flow box child, plus the pinned
  empty `read_by` arm.
- **Lifetimes.** Children carry no handlers of their own; the wrapper dies with its card;
  `fb handlers fired during teardown: 0`; `forget_children` drops every entry for a
  container going away whole, above the or-pattern chain (see M4 for what tests it).
- **Task 6's N1–N3.** N1: `node.mli`'s stack paragraph now uses the list box's words and
  names `flow_box` alongside `list_box`, so the asymmetry stays documented as a pair.
  N2: "costs nothing and provokes no write" → "provokes no write" — the right narrowing,
  given I1 above. N3: `w_list_box.ml`'s `row_activated` no longer upcasts in `connect` and
  downcasts in `fire`, and `w_flow_box.ml` was written that way.
- **The stavekeeper consumer.** `build_grid` (`library_window.ml:227-241`) uses
  `selection_mode SINGLE`, `activate_on_single_click false`, both spacings, min 1, max 10,
  `homogeneous false` — all seven are props on `Node.flow_box`, and the two remaining calls
  (`add_css_class`, `set_valign`) are ordinary attrs. `configure_grid_for_view`
  (`:243-256`) moves four of them plus a CSS class, which is the diff the live test
  performs. `on_child_activated` and `on_selected_children_changed` are the two signals it
  connects (`:726`, `:754`). `set_sort_func`/`set_filter_func`/`bind_model` are not used
  and are correctly documented as unbound. The port is covered.
- **Out-of-scope creep.** None beyond deviations 5, 6 and 7, judged above.

---

## Verdict

**Request changes**, narrowly.

One Important (**I1** — `apply_selection`'s O(|selected| × children) per-frame cost, now
measured at 16 ms per idle frame for a 200-of-1000 `Multiple` grid and 24 ms for
500-of-500, with a verified 12-line per-call-map fix that leaves the golden byte-identical
and belongs in `w_list_box.ml` as well) and one doc correction that is Minor by size but
sits in the one place applications read (**M1** — `attr.mli:455` still attributes the
"never handed a departed key" guarantee to the `Child_keys.remove` ordering that this very
commit demotes to belt-and-braces everywhere else). If the lead prefers to keep I1 as a
carry, re-defer it explicitly with the numbers rather than silently for a third time.

Everything else is Minor. All eight deviations are sound, all three N-carries landed, both
of the report's corrections to the plan are correct and I verified them independently, and
the mutation set is real — five of the six bite, and the sixth is honestly reported as not
biting. The end-to-end activation test and the geometry round trip are the strongest new
evidence in the milestone. With I1 settled and M1's clause fixed, this is an approval.

---

# Re-review — fix round 1 (`e9e7793`)

**Scope:** `git diff 3d05a83..e9e7793` only (7 files, +224/−35).
**Gate re-run by the reviewer:** `nix develop -c ./scripts/ci.sh` → `all green`, exit 0.
Mutation work in a throwaway worktree at `e9e7793`, since removed; the checkout is
unmodified.

## Summary

I1 and M1 are fixed, and M2, M3, M5 and M6 landed too. The I1 fix is better than the
sketch I supplied: `Hashtbl.add` with the result ignored (first-wins) rather than
`Hashtbl.set` (last-wins), which preserves `List.find`'s old resolution — a correctness
detail my version got wrong, and the comment says why it matters even though
`Reconcile.check_unique_keys` makes it unreachable today.

**The map's lifetime is right, and is now documented better than I asked.** Both tables are
created inside `apply_selection`, populated from the single walk the function already
performed, and dropped at return; nothing else in either module holds a reference. The
warning that made this safe has been moved to where a future optimiser will read it:
`w_flow_box.ml:141-153` now says outright "**Never cache this into a table that outlives
the call**", with the measured reason (`gtk_flow_box_select_child` accepts a detached
child silently), and `w_list_box.ml:148-150` cross-references it. That is the distinction
the fix rests on, stated at the point of temptation.

**Ruling 5 and the write order are unchanged.** `current` is still derived in widget order
from the same walk (`List.filter all ~f:is_selected |> List.filter_map ~f:key_of_child`,
identical to the old `selected_keys`); the sort-before-compare is untouched; the write
still iterates the **unnarrowed** `selected`, now with a comment saying so. Confirmed
empirically rather than by reading: reverting `apply_selection` in both containers to the
quadratic shape leaves `expected_lists.txt` **byte-identical apart from the bench's verdict
line**, so the fix changes cost and nothing else.

## Regressions re-checked — all still bite, two of them harder

| Mutation | Result |
|---|---|
| `Child_keys` keyed on the wrapper (C1b) | `fb gc: … selected a,b` → `(none)`, all five checkpoints |
| ghost-key narrowing dropped, flow box | **two** lines: `fb the handler saw…: a` → `a \| (none) \| a`, and `writes…: 0` → `2` |
| ghost-key narrowing dropped, list box | **two** lines, same shape |
| `apply_selection` compares unsorted | `fb writes for a re-ordered but equal selection: 0` → `3` |
| `apply_selection` reverted to the quadratic shape | `bench: … under 2 ms each: true` → `false`, stderr `21.251 ms` |

M3's restructure had a side effect worth recording: because the removal frame now renders
`~selected:["a";"d"]` from the start, dropping the narrowing no longer only moves the write
count — it also makes the handler print `a | (none) | a`, i.e. the fixup unselecting
everything and re-selecting the survivor mid-frame is now visible in the golden. The
ghost-key case is strictly stronger than it was, in both containers.

## Per-minor judgement

**M1 — fixed, and better than asked.** `vtree/attr.mli:455-460` now attributes the
guarantee to the walk *and* states the emission-ordering fact that makes it true ("GTK
emits this signal after unparenting the departing one"), then demotes the `Child_keys`
ordering to belt-and-braces in a parenthesis. That matches what I measured. Accept.

**M2 — resolved as a documented decision rather than a check, and the reasoning is
right.** `vtree/node.mli:729-736` says the maximum wins, gives `~min:6 ~max:3` ≡
`~min:0 ~max:3` (which is exactly what I measured: three per line in both cases), and
argues that the arrangement producing it — a list view setting `~max:1` over a grid view's
minimum — is a working pattern that should not become an exception. I prefer this to the
check. Accept.

**M3 — fixed in both containers.** `two selected before the removal: a,d` followed by
`selected row removed: a` / `the handler saw, as the row left: a` distinguishes the reduced
selection from the empty one, which the old `(none)` could not. The now-redundant
`fb selection with the removed key still held` line is correctly deleted rather than kept
— the removal frame *is* the ghost-key-beside-a-live-key frame now, and the write-count
frame immediately follows it. Accept.

**M5 — fixed.** `(selection-mode browse)` reaches a dump, and the case that matters is
pinned: a `Browse` grid handed `~selected:[]` keeps its selection
(`fb Browse asked for an empty selection: a`), which is the documented
"a model that disagrees with its mode" behaviour. I checked that this leaves no per-frame
emission that could contaminate the later `handlers fired during teardown` count —
`gtk_flow_box_unselect_all` returns early in `BROWSE` without emitting, and the golden was
stable across ~25 runs. Accept.

**M6 — fixed.** Accept.

**M4 — not addressed, correctly.** It was noting-only.

## New — Minor

### N1. The bench's 2 ms bound is not robust to CPU contention: I reproduced a false failure

`test/live/live_lists.ml:1029-1032` (`bound_ms = 2.0`)

The bound has ~5× headroom over an idle machine but only ~1.03× over a contended one.
Measured on this 24-core box, `live_lists.exe` unmodified:

```
idle                             0.382  0.385  0.389
under ci.sh                      0.503
12 spinners (half load)          0.873  0.925  0.928  0.940  0.951  0.975
24 spinners (full load)          0.775  0.841  0.848  0.884  0.886  0.894
48 spinners (2x oversubscribed)  0.783  0.855  1.572  1.633  1.713  1.868  1.946  2.312
```

The last sample is **over the bound** — `Float.(2.312 < 2.0)` is `false`, the golden reads
`false`, and `dune diff` fails. That is 1 of 8 at 2× oversubscription, with three more
within 3% of the line; a separate 3-run sample earlier gave `2.010`. Full load is fine
(~2.1× margin); 2× oversubscription is not, and a CI runner sharing a host or running
`dune build -j` alongside other jobs reaches it.

Nothing about the fix is wrong — this is the test's bound, not the code. There is plenty of
room to move it: the quadratic shape measures **21.25 ms**, so an **8 ms** bound still
separates linear from quadratic by 2.6× while giving ~3.5× over the worst contended sample
I could produce. One line.

**A better instrument, if you want one (not required).** The property under test is that
cost does not scale with `|selected|`, and that can be asserted load-invariantly by timing
the *same* fixup at two selection sizes instead of against wall-clock: at n=1000, sel=1 vs
sel=200 the fixed code is 0.349 / 0.386 ms (ratio 1.1) and the quadratic code is 0.286 /
16.464 ms (ratio 57). A "ratio under 5" bound is an order of magnitude clear of both ends
and cancels machine load, because contention scales both measurements. Costs one extra
mount. Either fix is fine; the 8 ms bound is the cheap one.

The rest of the bench's design is good and I want to say so: printing the *verdict* to the
golden and the *number* to stderr is the right split, asserting `selected 200 of 200` stops
it from timing a fixup that has quietly stopped working, and spreading the selection
through the list (`i * (n / sel)`) keeps neither shape flattered by locality.

### N2. Two small accuracy points

- **`child_by_key` and `row_by_key` now have no in-impl callers.** After this diff their
  only callers are `live_lists.ml` (three and three). `w_flow_box.ml:141-142`'s "For the
  callers that ask about a single key" reads as if the impl still uses one. They are
  legitimately part of the `Private` surface and the tests need them — this is a word, not
  a change.
- **The live suite now has a second stderr producer.** `ci.sh` prints
  `bench: 0.503 ms per idle frame (bound 2)` beside `live_driver.ml`'s deliberate raise, so
  the "the one stderr line is …" convention that three reports have used is now two lines.
  Worth a clause in the ledger so a later reader does not read the extra line as a
  regression.

## Verdict

**Approved.**

I1 is fixed correctly in both containers, the fix is behaviour-preserving under a
byte-identical golden, the map is per-call with the safety property documented at the point
of temptation, and every regression in the suite still bites — two of them harder than
before. M1, M2, M3, M5 and M6 all landed, and M2's resolution (document the deterministic
winner rather than reject) is better than what I asked for.

One thing to change before the milestone closes, and it is a test bound rather than shipped
code: **N1** — raise `bound_ms` from 2.0 to ~8.0, or convert the assertion to the
selection-size ratio. I reproduced a false failure at 2× CPU oversubscription and the
quadratic shape measures 21 ms, so there is an order of magnitude of room to take. N2 is two
words.
