# Task 6 review — ListBox: keyed rows, a key in every handler, and `Child_keys`

**Commit reviewed:** `cd2f446` on `m2`, base `7ba161a` (39 files, +1925/−60).
**Gate re-run by the reviewer:** `nix develop -c ./scripts/ci.sh` → `all green`, exit 0.
The one stderr line is `live_driver.ml`'s deliberate raise, as the report says.

---

## Summary

The task's stated main hazard — whether the patcher's list ops point at the wrapper or at
the inner widget — is resolved correctly and completely. The patcher does keep `l.widget`
(the application's child) in `cur` and computes `~after` from that same list
(`src/patcher.ml:611-613`, `:625`, `:642-647`), and all five sites in `w_list_box.ml` go
through one `row_of ~what` (`src/widgets/w_list_box.ml:73-83`) that climbs
`Widget.get_parent` with a `Gobject.Type.name` check rather than a bare downcast. I
verified the ownership premise that makes that safe: `ml_gtk_widget_get_parent`
(`.ocgtk-src/ocgtk/src/gtk/generated/ml_widget_gen.c:871-878`) does `g_object_ref_sink`
its result, so the `row` value `move` holds really does keep the wrapper alive across the
unparenting, and the "remove and re-insert preserves the row" claim is sound rather than
lucky.

The rest of the ruling surface is in good shape: keys are required at the constructor with
a message naming the constructor and the child index; both handlers speak in keys; the
selection is controlled from the fixup queue and comes back after a declined click through
a real `Driver.frame`; the two row attrs are placement attrs with a `Placement` arm, a
`reader` entry, both negatives tested, and the count assertions updated; `Live_tree` prints
no keys; the ignored-ghost-key asymmetry with `~visible_child` is documented on both
constructors, in both directions, with an explicit "do not fix one of them". The live
golden pins fourteen distinct claims and the report's five mutations are real ones.

Two things stop this from being an approval.

The first is a **use-after-free**. `selected_keys` reads the selection with
`W.List_box.get_selected_rows`, and that binding stub does not reference the rows it wraps
while the wrapper's finaliser unconditionally unrefs them. `apply_selection` calls it once
per list box **per frame**, so an idle application destroys its own selected rows within a
few frames of a major GC. I reproduced both the silent-selection-loss and the segfault. The
fix does not need a fork change and is four lines.

The second is that `apply_selection` compares the widget against the model's *unfiltered*
`~selected`, so the one case ruling 4 exists to bless — a model holding a selected id
across a filter change — rewrites the entire selection on every frame forever. That is the
failure the sort-before-compare was added to prevent, arriving through a different door,
and it multiplies the rate of the first finding.

---

## Per-deviation judgement

**1. `Child_keys.find_exn` called from the spec's `fire`, not from its `connect` — sound.**
The argument is correct and checkable: `connect_all`'s `Payload` arm deliberately has no
`try` around the callback because `dispatch_payload` owes GTK a value
(`src/signals.ml:112-117`), and `dispatch_payload` catches, reports through `on_exn` and
returns `declined` (`:78-93`). A raise inside `connect`'s closure would be outside all of
that and would cross into C. Nothing is lost: the row is an ordinary callback argument, and
the lookup is not reached when the slot is empty. The `'p` widening to `Widget.t` is
invisible to applications, which still receive a `Key.t`. Recorded in `row_activated`'s
comment and in `child_keys.mli`'s `find_exn` doc, and carried to Tasks 7–8 as the one thing
to copy verbatim. Accept.

**2. Row flags as plain `bool`s defaulting to GTK's `true`, not `Option.iter` — sound, and
the brief's sketch was wrong.** With `Option.iter`, a row that *drops*
`Attr.row_selectable false` writes nothing and stays non-selectable forever;
`w_list_box.ml:29-45` answers `true` on absence and `updated` re-reads both flags
(`:296-304`). Pinned by `after the flags swapped: hdr` plus the dump, and the report's
mutation (`updated` does not re-read) is caught. Accept.

**3. The placeholder as a `Slots` container rather than a bare list — sound, and better
than the brief.** `Node.list_box` builds `Slots [ "placeholder", Single …; "rows", List … ]`
(`vtree/node.ml:427-435`), which keeps three facts structural rather than conventional: the
placeholder is outside `require_child_keys`, outside `Reconcile.check_unique_keys`, and
outside the row list ops, so `row_of` can never be handed it. I confirmed the index claim
holds in practice — the live golden mounts with a placeholder present and then does a
rightward move, a middle insert and a middle removal, all with correct row order — so
`get_row_at_index`/`get_index` really do ignore it. Accept.

**4. The required-key check at the constructor; the *duplicate*-key check left at mount and
patch — sound, and the right reading.** The brief and plan author's note 4 both specify a
missing-key check, which is what landed as `Node.require_child_keys ~which ~why`
(`vtree/node.ml:15-34`), retrofitted to `Node.stack`. Declining to move the duplicate check
is correct on its own merits and not just on precedent: `Reconcile.check_unique_keys` runs
at mount *and* at patch and its message carries the container's node path
(`src/patcher.ml:343-345`), which a constructor cannot produce, and three live cases
(`dupkey`, `duppage`, `patchdup`) already pin the pathful form. Accept as landed; the
task message's "duplicate" was a slip.

**5. `w_stack`'s `keyless` live case now reports the constructor's message — sound
consequence of 4.** The impl-side raise is kept with a comment saying why it is
unreachable-but-kept, which is what the brief asked for. See Minor M4 for the one thing
this costs.

**6. `move` reads the predecessor's index after the removal — sound, and honestly
reported.** I checked the invariant the report leans on: `vtree/reconcile.mli:36-38` states
"every emitted `Move` has `from > to_`", and `patch_list`'s `Move` arm computes `after` over
`!cur` with the moved child already taken out (`src/patcher.ml:642-647`), so the
predecessor is always before the moved row and its index is untouched either way. The
report says outright that the mutation is *not* caught and that this is an assumption not
made rather than a bug fixed — which is the correct way to write that up. Accept.

**7. The driver-level declined-selection test in `live_lists.ml` rather than
`live_driver.ml` — sound.** It keeps `expected_driver.txt` untouched and puts the evidence
beside the rest of the list-box evidence. The three lines it prints
(`after the user clicked: b` → `after the frame the click armed: a (Bonsai saw 1)` →
`after one more frame: a (Bonsai saw 1)`) are the strongest single assertion in the diff:
they pin the snap-back, the `in_patch` guard, and idempotence in one sequence. Accept.

**8. The gallery entry landing now rather than in Task 13 — acceptable creep.** It is
additive, the task message did ask for it, `test/handle/test_gallery.ml`'s sweep exercises
every optional argument and both row attrs, and the report flags it as done for Task 13.
Accept.

---

## Critical

### C1. `selected_keys` destroys the rows it reads: `get_selected_rows`'s binding stub does not reference its elements, and `apply_selection` calls it every frame

`src/widgets/w_list_box.ml:93-96`

```ocaml
let selected_keys (w : Widget.t) =
  W.List_box.get_selected_rows (cast w)
  |> List.filter_map ~f:(fun row -> Child_keys.find row_keys (row :> Widget.t))
;;
```

`gtk_list_box_get_selected_rows` is `transfer-ownership="container"`
(`.ocgtk-src/gir/Gtk-4.0.gir:89573`): the caller owns the `GList` but **not** the rows in
it. The generated stub frees the list and wraps each element with no reference:

```c
/* .ocgtk-src/ocgtk/src/gtk/generated/ml_list_box_gen.c:229-238 */
Val_GList_with(c_result, result, item, cell, Val_GtkListBoxRow((gpointer)_tmp->data));
g_list_free(c_result);
```

`Val_GtkListBoxRow` is `ml_gobject_val_of_ext` (`gtk_decls.h:762`), and that function's
contract is stated in the fork's own words at `ml_gobject.c:373-388`: the caller *must*
`g_object_ref_sink` a transfer-none pointer first, "since the wrapper's finalizer
unconditionally `g_object_unrefs` on GC", and missing it is "capable of disposing a
still-parented widget … out from under its container the moment GC collects the wrapper".
That comment describes the identical bug on `GtkFlowBoxChild`, and the fork fixed it — one
file over. `ml_flow_box_gen.c:233` has the `g_object_ref_sink`; `ml_list_box_gen.c:235`
does not. Task 6 is the first consumer of the unfixed twin.

**Why it is reachable rather than theoretical.** `apply_selection` opens with
`let current = selected_keys w`, unconditionally, before it decides whether to write
(`w_list_box.ml:130-133`), and the patcher enqueues that fixup on every mount, every patch
*and* every no-change frame through `reassert_only` (`src/patcher.ml:216-222`, `:795-799`).
So a list box with one selected row queues one unbalanced unref per frame — 60 a second
under a ticking driver.

**Reproduced**, on the committed tree, with a throwaway executable that only drives the
patcher the way `Driver.frame` does (`Scheduler.with_patch_guard` around
`reassert_only` + `run_fixups`), on a three-row `Multiple` list box with `~selected:["a"]`:

```
mounted, selected: a
after 10 no-change frames + GC, selected: (none)
after 20 no-change frames + GC, selected: (none)
...
```

with `Gtk-CRITICAL: GtkListBoxRow 0x… has a parent GtkListBox 0x… during dispose. Parents
hold a reference, so this should not happen.` on stderr, followed by a run of
`g_object_unref: assertion 'G_IS_OBJECT (object)' failed` — unrefs landing on freed memory.
Ten idle frames and one major GC is enough. With two rows selected and 200 reads the
process takes `SIGSEGV` (exit 139) inside `Live_tree.dump`.

The user-visible failure is: *a selection silently empties itself while the user is not
touching anything, and the application then crashes at an unrelated moment.* For
stavekeeper's `sidebar.ml` that is the navigation rail losing its highlight after a few
seconds idle.

**Why CI is green.** The live suite reads the selection about twenty times in one short
process and never forces a major collection while wrappers are outstanding, so no finaliser
runs before exit. Nothing in the diff would ever go red on this.

**Fix, needing no fork change.** Read the selection by walking the rows, which is what
`row_by_key` (`:98-109`) already does and what `Live_tree`'s `GtkListBoxRow` arm already
relies on — `ml_gtk_list_box_get_row_at_index` *does* `g_object_ref_sink`
(`ml_list_box_gen.c:258-265`), as does `gtk_list_box_row_is_selected`'s object argument:

```ocaml
let selected_keys (w : Widget.t) =
  let b : W.List_box.t = cast w in
  let rec go i acc =
    match W.List_box.get_row_at_index b i with
    | None -> List.rev acc
    | Some row when W.List_box_row.is_selected row ->
      go (i + 1) (Option.to_list (Child_keys.find row_keys (row :> Widget.t)) @ acc)
    | Some _ -> go (i + 1) acc
  in
  go 0 []
;;
```

I verified the replacement empirically: 2000 walks plus two full major collections leave
both selected rows intact and the dump correct, where 200 `get_selected_rows` calls
segfault. Note it also answers in widget order, which is what
`Attr.on_selected_rows_changed`'s doc already promises.

`src/live_tree.ml:420-424` has the same call for its `selected-rows` count and should move
to the same walk (or to counting `is_selected`), for the same reason and because
`Live_tree.dump` is the one function a debugging session calls repeatedly.

**Please also add the regression test**, because nothing else will hold this: the pattern
already exists in this repository — Task 4 fix round 1's heap-churn test in
`live_controllers.ml`, which reproduces the old `set_static_name` bug exactly when the call
is put back. The list-box equivalent is a loop of `selected_keys` reads, a
`Gc.full_major ()`, and a line printing the selection, at the top of `live_lists.ml`.

**Carry for Tasks 7 and 8.** `gtk_flow_box_get_selected_children` is already correct in the
pinned fork, so `W_flow_box` may use it; but check the stub, not the GIR, before trusting
any other `GList`-returning getter — `Val_GList_with` sites without a `ref_sink` are the
general shape of this bug, and `ml_list_box_gen.c:235` is not the only one in the file list.
The real fix belongs in the generator and is a fourth candidate for Task 14's fork patches,
alongside the three nullable ones; it is larger and more valuable than any of them.

---

## Important

### I1. `apply_selection` compares against the unfiltered `~selected`, so a key naming no row rewrites the whole selection on every frame

`src/widgets/w_list_box.ml:130-143`

```ocaml
let current = selected_keys w in
if not (List.equal String.equal (sorted current) (sorted selected))
then (… unselect_all …; List.iter selected ~f:(… row_by_key …))
```

`current` can only contain keys of rows that exist; `selected` is whatever the model said.
When the two differ *only* by a key no row carries, the comparison is false forever, so
every frame does `unselect_all` and then re-selects the whole surviving selection.

Measured on the committed tree, `Multiple`, rows `[a; c]`, model `~selected:["a"; "b"]`
(i.e. `b` filtered out), counting scheduled effects from `selected-rows-changed`:

```
after the filter hid b: a
identical next frame: a
writes on the identical frame (ghost key held): 2
writes on a third identical frame: 2
writes from reassert_only with the ghost key: 2
control, no ghost key, writes on an identical frame: 0
```

Two emissions per frame, indefinitely, against zero for the same shape without the ghost
key. This is the case ruling 4 exists to make comfortable — "a model that keeps a selected
id through a filter change is doing something reasonable" — and `Node.list_box`'s doc tells
the reader that such a key "is ignored", which reads as inert. The per-frame-rewrite caveat
in that doc is attached only to the `~selection_mode` disagreement, three paragraphs down.

It also matters because it is the accelerant for C1: two `get_selected_rows` reads and two
selection writes per frame instead of one read, on precisely the list a real application
filters.

And it is the failure the sorting was added to prevent, arriving by another route: the
comment at `:126-129` says sorting exists "or this would write on every frame and the user
could never keep a multi-selection", which is exactly what a held ghost key restores.

**Fix:** compare against `selected` narrowed to the keys that resolve to a row, e.g.

```ocaml
let wanted = List.filter selected ~f:(fun k -> Option.is_some (row_by_key w k)) in
if not (List.equal String.equal (sorted current) (sorted wanted)) then …
```

writing `selected` (not `wanted`) in the loop, so nothing about ruling 5's "write what was
asked, read back what GTK kept" changes.

The residual after this fix is the genuinely-unachievable cases — three keys in `Single`
mode, a key on a `row_selectable false` row — which still rewrite every frame. Those *are*
documented on the constructor as "a model that should be brought into line with its mode",
and I am not asking for them to be solved here; but the ghost key is documented as ignored
and should be.

**Test:** the existing `writes for a re-ordered but equal selection: 0` line is the right
instrument — add the same two-frame write count with a ghost key held. It goes `0` with the
fix and `2` without, so it bites.

---

## Minor

**M1. `child_keys.mli:29-33` overstates when entries are dropped.** `Child_keys.remove` is
called from `list_ops.remove` only. When a whole list box is unmounted — a stack page
patched away, a window closed — `Patcher.destroy`'s `List_box _` arm is inert
(`src/patcher.ml:449`) and the rows never pass through `ops.remove`, so every row's entry
survives until the wrapper is collected. The ephemeron makes that bounded rather than a
leak, but the doc's stated reason ("'the next GC' is not a bound worth relying on for a
list the user filters") applies just as much to a page the user switches away from. One
sentence, or a `Child_keys.remove` sweep in the `List_box` destroy arm.

**M2. The ordering in `remove` is load-bearing and uncommented.**
`w_list_box.ml:288-295` drops the `Child_keys` entry *before* `W.List_box.remove`. That
order is what stops a handler reporting the key of a row that has just left the tree: GTK
emits `selected-rows-changed` synchronously from the remove, and `selected_keys` drops rows
it cannot find. I confirmed it — driving the patcher outside the patch guard, a frame that
removes the selected row delivers `a | (none) | a` and never the removed key `c`; under a
real `Driver.frame` the guard drops all three, and the handler is not called at all. The
existing comment explains only *that* the entry is dropped (the shared-table argument), not
*when*. Worth the second sentence, because the obvious tidy-up — dropping the entry after
the GTK call, beside the rest of the teardown — silently reintroduces a stale key.

**M3. Two `Live_tree` branches have no golden.** `activate-on-double-click` and the
non-`multiple`, non-default `selection-mode` spellings (`none`, `browse`, and an explicit
`single`) are never printed by `expected_lists.txt` — `live_lists.ml` uses only `Multiple`,
`Single` and the default. I checked by probe that `Browse` + `~activate_on_single_click:false`
prints `(selection-mode browse) activate-on-double-click` correctly, so this is untested
rather than wrong; the report's own table calls out that both defaults are the ones a reader
guesses backwards, which is the argument for pinning them. One extra frame in
`live_lists.ml`.

**M4. The `keyless` live case no longer proves the patcher prefixes a child path.**
`expected_containers.txt:451` moved from `rejected: keyless/0/0: Stack child has no ~key …`
to `rejected: Node.stack: child 0 has no ~key …`, which is the intended trade (plan note 4)
and a better message at the point of the mistake — but the new one carries no node path,
because the constructor raises before a tree exists. The `child_op` path-prefixing claim is
still covered by `rejected: root/0/0: Grid child has no Attr.grid_cell …` on the same
golden, so nothing is lost; noting it so a later reader does not conclude the prefixing was
dropped.

**M5. `Action.Activate_row` fires on a row carrying `Attr.row_activatable false`.**
`test_lib/bonsai_gtk_test.ml:180-187`, documented as deliberate in the mli. The reasoning
(don't model a detail; don't hide a model that mishandles an unexpected key) is defensible,
but it is the one place the headless handle certifies something the runtime will not do —
elsewhere in this diff (`Events`, `Placement`) considerable trouble is taken so that it
cannot. It is documented, so Minor; flagging because the same choice is about to be made
twice more for `FlowBox` and `Notebook` and should be made once, deliberately.

**M6. `apply_selection` is O(|selected| × rows) per frame.** `row_by_key` (`:98-109`) is a
linear `get_row_at_index` scan per key. Fine at sidebar scale, and irrelevant once I1 stops
it running on unchanged frames — but `W_flow_box` in Task 7 will have the same shape over
many more children, and a `Child_keys`-shaped reverse map (key → row, per container) is the
obvious answer if it ever matters. Not for this task.

**M7. A `row_*` attr on the *placeholder* is accepted and silently inert.**
`Placement.read_by`'s granularity is the parent's kind, not the parent's slot
(`vtree/placement.ml:12-16`), so `Attr.row_selectable` on the `?placeholder` node passes the
check and is read by nobody. Identical to `Attr.measure_overlay` on an overlay's main child,
and the header comment already says why the granularity is what it is. Noting only.

---

## Checks that came back clean

Recorded so a later reader knows they were looked at rather than skipped.

- **Row identity across list ops.** Insert at head (`after = None` → index 0), middle
  (predecessor's `get_index + 1`) and tail; remove; move as remove-and-re-insert; kind
  change in place (old wrapper removed and its `Child_keys` entry dropped, fresh wrapper
  made). `Move` is `Some`, so `~ordered:true` and no `Unordered` marker is involved — the
  golden pins both that the four original GObjects survive a reorder (`Gobject.same` as a
  set) and where each one landed (`0,2,3,1`), which is what stops a patch that moved
  nothing from passing.
- **A child removed while selected.** Under a real frame: no handler call, and the model is
  never handed the removed key (see M2). GTK drops the selection, `apply_selection` cannot
  find the row, nothing raises, `selected row removed: (none)`.
- **Programmatic writes do not fire the user handler.** Mounting with `~selected:["b"]`
  selects the row and calls no handler; the declining frame's write does not increment the
  driver test's `Bonsai saw 1`.
- **The placeholder is excluded from the index arithmetic**, structurally (a separate slot)
  and in fact (moves and inserts stay correct with one mounted).
- **`Node.require_child_keys`** message shape, both containers, both indices tested.
- **Counts.** `Events.for_kind` gains its arm and `test_events.ml`'s `all_kinds` asserts
  against `Kind.Variants.descriptions`; `live_events.ml` 29 → 30 with "agreed";
  `test_placement.ml` 34 → 36 and the "read by exactly one container" assertion gains a real
  `List_box` row rather than staying vacuous; `is_event` partition updated in both halves.
- **`require_specs` negatives** for both new events, and **`Placement` negatives** for both
  row attrs, plus the positive that stops the negative being a name nothing satisfies.
- **`Live_tree` prints no keys**, on the list box or on a row; the live test prints
  `W_list_box.selected_keys`, which is a read *through* `Child_keys`.
- **Lifetimes.** Rows carry no handlers of their own; a wrapper dies with its child (nothing
  holds it after `remove` but the transient OCaml wrapper); teardown clears slots before
  anything is unparented and `handlers fired during teardown: 0` pins it.
- **Task 5 Minors.** M1–M4 all landed as described (`key_event.ml`'s `~state` sentence,
  all four "Task 5 will…" forward references including the public `events.mli:23` one,
  `attr.mli`'s three-places phase rejection, `live_keyvals.ml`'s duplicate-declaration
  caveat). M5 and M6 are argued down in the report on the terms the review itself offered.
- **Out-of-scope creep.** None beyond deviation 8, which is judged above.

---

## Verdict

**Request changes.** One Critical (C1 — `selected_keys` disposes the rows it reads; a
verified use-after-free reachable within ten idle frames, with a four-line fix that needs no
fork change, plus the same call in `Live_tree` and a GC-churn regression test) and one
Important (I1 — the ghost key rewrites the whole selection on every frame, defeating the
sort-before-compare and accelerating C1). Both are local to `w_list_box.ml`.

Everything else is Minor or noting, all eight deviations are sound, and the design work —
the wrapper/inner-widget resolution, the placeholder-as-a-slot, the constructor-time key
check, the two documented asymmetries — is the strongest part of the milestone so far. With
C1 and I1 fixed and pinned, this is an approval.

---

# Re-review — fix round 1 (`cd2f446..f573799`)

Scoped to C1, C1b and I1, plus the Minors taken. I re-ran the gate and re-derived every
claim rather than reading the report for them.

**Gate:** `nix develop -c ./scripts/ci.sh` → `all green`, exit 0.
**Baseline:** `live_lists.exe` reproduces `expected_lists.txt` exactly, with **zero bytes on
stderr**.

## C1 — the `get_selected_rows` use-after-free: fixed

`selected_keys` and `row_by_key` now go through one `rows` walk over `get_row_at_index` +
`is_selected` (`src/widgets/w_list_box.ml:118-126`, `:150-157`), and `Live_tree`'s
`selected-rows` count has its own `selected_row_count` walk (`src/live_tree.ml:67-76`).
`grep` confirms no live call site of `get_selected_rows` remains anywhere in `src/`,
`test/`, `test_lib/`, `examples/` or `vtree/` — the seven hits are all comment text.

**Is the walk correct with a placeholder present?** Yes, and I checked it directly rather
than inferring it from the golden. On a list box with three row nodes and a placeholder,
`get_row_at_index` enumerates exactly the three rows and never the placeholder; the same
box with no placeholder reports `rows = 2` and `widget_children = 2`, so the walk is
indexing GTK's row sequence rather than the box's child list. The golden's existing
rightward move, middle insert and middle removal all run with a placeholder mounted, so
the index arithmetic is pinned as well as spot-checked.

**Is it correct with hidden rows?** Yes. I hid a row wrapper outright with
`Widget.set_visible false` — the closest reachable analogue of a filtered row, since
`set_filter_func` is not bound — including a *selected* one, and compared the two readers:

```
placeholder present          rows=3 [A,B-invisible-child,C]
                             walk-selected = A,C   get_selected_rows = A,C   agree = true
after hiding row 1           rows=3 [A,B-invisible-child,C]
                             walk-selected = A,C   get_selected_rows = A,C   agree = true
after hiding row 2 (selected) rows=3 [A,B-invisible-child,C]
                             walk-selected = A,C   get_selected_rows = A,C   agree = true
```

`agree` is `Gobject.same` pairwise, not a length check. Neither reader is
visibility-filtered and the two are pointer-for-pointer identical in every configuration,
so the replacement is faithful as well as safe — which is the part a "it no longer crashes"
argument would not establish.

**Does the regression test really fail on the old code?** Yes; I mutated rather than
reasoned. Restoring `get_selected_rows` in `selected_keys` and rebuilding:

```
EXIT=139
gc: mounted, selected a,b
gc: after 50 frames + full_major, selected (none)
--- stderr: Gtk-CRITICAL: GtkListBoxRow 0x… has a parent GtkListBox 0x… during dispose.
            Did you call g_object_unref() instead of gtk_widget_unparent()?
```

SIGSEGV, output truncated after two lines, golden differs. The per-batch
`Out_channel.flush` earns its comment exactly as claimed: what survives the crash is *how
far it got*, not nothing.

The backlog entry (`docs/m1-backlog.md`) is accurate on every citation I checked — the GIR
line, both stub ranges, the fork's own contract comment, and the FlowBox precedent.

## C1b — the ephemeron keyed on an unretained value: fixed, and the diagnosis is right

This one was in my Critical and I missed it: I attributed the whole `(none)` symptom to row
destruction, and there were two independent causes behind it. The report's separation is
correct.

**What it is keyed on now, and does the lifetime match?** The row's *child*
(`w_list_box.ml:68`, `Child_keys.set row_keys child …`), which is the `Widget.t` the
patcher passes to `insert` and stores in `live.widget`. That is the whole point:
`Ephemeron.K1` is weak in the **OCaml value**, and the wrapper `wrap` builds is unreachable
the moment `wrap` returns, so the old keying dropped every entry at the first major
collection while GTK kept the rows perfectly alive. `live.widget` is reachable for exactly
as long as the node is in the live tree, which is the lifetime wanted.

- **No early drop.** Nothing mutates `live.widget`, and the live record is held by its
  parent's `live.children` up to the driver's root. Mutation B below is the empirical
  converse: with the old keying the entries die, with the new one they survive 250 frames
  and five `Gc.full_major`s.
- **No leak.** Both teardown paths now drop entries — the per-child `list_ops.remove`
  (`:376-390`) and `W_list_box.forget_rows` from `Patcher.destroy`'s new `List_box` arm
  (`src/patcher.ml:424-427`). I checked the third path too: `patch_list`'s kind-change
  branch reaches `ops.remove parent l.widget` with the *old* child, so that entry goes as
  well. And the fix makes the whole question strictly bounded rather than merely tidy —
  keyed on `live.widget`, an entry now dies with the live record even if a path were
  missed, which was not true before.
- **`forget_rows` cannot drop a live entry**: `destroy` runs only on a dying subtree, and
  the comment correctly notes that children detach from Bonsai without unparenting, so the
  rows are still there to walk.

**Does the test fail on the old keying, independently of C1?** Yes. With C1's walk left in
place and only the keying reverted to the wrapper (`set`, `key_of_row`, `key_of_row_exn`,
`remove`, `forget_rows` all moved back together):

```
EXIT=0        stderr: 0 bytes
gc: mounted, selected a,b
gc: after 50 frames + full_major, selected (none)
gc: after 100 frames + full_major, selected (none)   … and 150, 200, 250
(GtkWindow … (GtkListBox … (selected-rows 2) … GtkListBoxRow selected … GtkListBoxRow selected …
```

That is a *different* failure signature from C1's — no crash, no GTK critical, and the dump
still shows both rows correctly selected while the lookups answer nothing. So the one test
catches both bugs and tells them apart by symptom, which is better than the report claims
for it.

The `child_keys.mli` invariant is stated as a requirement on callers rather than a note,
which is the right form given Tasks 7 and 8 inherit it and the types cannot express it.

## I1 — the ghost-key rewrite: fixed

`apply_selection` narrows to `wanted` before comparing and still writes `selected`
(`w_list_box.ml:216-221`), so ruling 5 is untouched.

**Does the ghost rule match Stack's same-frame semantics?** Yes, on the axis that matters,
and the doc is precise about which axis that is. Both are applied from the post-pass fixup,
so both resolve against the tree *this frame renders* — a page or row added this frame is
selectable this frame. `live_lists.ml` now pins that from both directions for the list box:
`add-and-select` (the row is new and the model asked for it) and `the ghost row arrived:
a,ghost` (the model never changed its mind; the filter lifted). What deliberately differs
is the absent case — Stack raises, ListBox is inert — and that asymmetry is still stated on
both constructors with "do not fix one of them".

**Mutation:** dropping the narrowing turns
`writes on an identical frame with a ghost key held: 0` into `2`, and **moves nothing else
in the golden** — a precisely targeted assertion rather than one that happens to shift.

The residual is correctly scoped and correctly documented: three keys in `Single`, or a key
on a `row_selectable false` row, still rewrite every frame, and `apply_selection`'s comment
now distinguishes "a model to bring into line with its mode" from "a row that is not here
yet" so the next reader does not narrow the write.

## The sweep for remaining `get_selected_rows`-class calls — independently redone

I did not take the report's grep on trust. I parsed all **6644** generated stubs and looked
for any that wrap a GObject (`Val_Gtk*`, `Val_G*`, `ml_gobject_val_of_ext`, `Val_GList_with`,
`Val_GSList_with`) around a C result without a `g_object_ref_sink`, then intersected that
with every `W.*`/`Gio.*`/`Gdk.*`/`Gobject.*` call in `src/`, `test/`, `test_lib/` and
`examples/` with comments stripped.

- **201** stubs wrap an object without a sink.
- **Exactly 1** of them is called by this library: `gtk_widget_observe_controllers`.
- That one is a **false positive**, and I verified it rather than assuming: it is
  `<return-value transfer-ownership="full">` (`gir/Gtk-4.0.gir:177105`), so the wrapper
  correctly adopts the caller's reference; and `g_list_model_get_object`, the other half of
  that path, is `transfer-ownership="full"` too (`gir/Gio-2.0.gir:75583`). Both balanced.
  The report's conclusion is right.

The `Val_GList_with|Val_GSList_with` count reproduces exactly: **47 sites, 1 sinks** (the
hand-patched FlowBox). Script validated against known answers — it flags
`get_selected_rows` as unsinked and confirms `get_selected_children`,
`get_row_at_index`, `list_box_row_get_child` and `widget_get_parent` as sinked.

**Conclusion: no remaining defect of this class in M1/M2 code.** The generator fix, and the
"read the stub, not the GIR" rule of thumb, are the right things to have written down.

## Minors taken

- **M1** — `forget_rows` from `Patcher.destroy`, arm placed **above** the or-pattern chain.
  I checked the near-miss the report describes has really gone, by the test it would fail:
  stderr across all nine live executables, individually.

  ```
  live_patcher 0 · live_driver 0 · live_signals 0 · live_controls 0 · live_containers 0
  live_events 0 · live_controllers 0 · live_keyvals 0 · live_lists 0
  ```

  Zero critical/warning/assertion lines anywhere. Worth keeping as a habit — it is the only
  check that would have caught that mistake, and it caught it.
- **M2** — the load-bearing ordering in `remove` now says why, and says that moving the line
  down reintroduces the bug. Accurate.
- **M3** — the `Browse` + `activate-on-double-click` frame lands and its dump pins both
  spellings.
- **M4, M7** — agreed as noting, no change, correctly.
- **M5** — argued, not fixed, and the argument is a good one: `Events`/`Placement` reject a
  *tree* (static, in the view, the handle must refuse it), while `row_activatable false`
  refuses an *event* (dynamic, on data) and `Bonsai_gtk_test` models no routing at all, so
  filtering this one case would be the only routing it implements. I accept it. The carry
  to Tasks 7–8 — that `Activate_child` and `Set_page` follow `Activate_row`, and that all
  three change together if the controller decides otherwise — is the right way to close it.
- **M6** — carried, correctly, with the honest note that I1's fix makes the per-write cost
  slightly worse in exchange for running on far fewer frames.

## New minors (none blocking)

**N1. The two halves of the cross-reference now use different words.** `node.mli:561` (the
stack side) still says list_box "ignores a key no row carries"; the list_box side was
upgraded to "inert, not an error — and inert in the strong sense". Not a contradiction, but
this pair is explicitly maintained *as a pair* ("both asymmetries are documented on both
constructors"), and a reader arriving from the stack side gets the weaker word for the
property that just became precise. One-line edit.

**N2. "costs nothing" is a shade stronger than what was fixed.** `node.mli` says holding a
ghost key "costs nothing and provokes no write". "Provokes no write" is exactly right and
now pinned at `0`. "Costs nothing" is not literally true: the narrowing runs `row_by_key`,
an O(rows) scan, per key per frame — which is M6's carried item arriving in the doc.
"Provokes no write" alone would be exact.

**N3. `row_activated`'s `fire` now does an unchecked downcast.**
`w_list_box.ml:258` is `key_of_row_exn (cast row)`, casting the payload `Widget.t` back to
`W.List_box_row.t`. It is provably safe — a round-trip of the upcast `connect` performs two
lines away — but `row_of` (`:88-95`) goes to the trouble of a `Gobject.Type.name` check
precisely because "a wrong downcast is undefined behaviour, not an exception", and the
asymmetry now reads as an oversight rather than a decision. `Signals.payload`'s `'p` is
existential, so `connect` could hand the callback a `W.List_box_row.t` directly and delete
both the upcast and the downcast. Cosmetic — but Tasks 7 and 8 will copy this spec verbatim,
which is the reason to say it now.

## Verdict

**Approved.** C1 is fixed at the call site, swept for siblings, recorded for Task 14, and
pinned by a test that genuinely segfaults on the old code. C1b is a real second bug the
implementer found while writing that test, correctly diagnosed, fixed at the right level
(the ephemeron is keyed on a value the patcher retains), and independently mutation-caught
with a distinct symptom. I1 is fixed without disturbing ruling 5, and the same-frame rule it
implies is pinned from both directions. Every Minor is taken or argued down on its merits,
and the argument for the one that was not fixed is better than the finding.

N1–N3 are documentation and cosmetics; take them here or fold them into the Task 7 brief,
whichever the controller prefers. Nothing is left open.
