# M2 final whole-branch review — containers lens

Scope: `86224d9..f06a615`, package `final-containers.diff` (`src/live_tree.ml`,
`src/widgets/w_{flow_box,grid,list_box,notebook,overlay,stack}.ml`), read at HEAD together
with `src/patcher.ml`, `src/child_keys.{ml,mli}`, `src/signals.ml`, `src/widget_impl.mli`,
`vtree/{reconcile,placement,node}.ml{,i}` and the live goldens. Backlog items in
`docs/m2-backlog.md` are not re-reported. Read-only: nothing was built, nothing was changed.

GTK claims below were checked against the pinned toolchain's own source
(`/nix/store/kf64y6s024nzcynaihhy12h82142g800-gtk-4.22.4.tar.xz`, extracted to a scratch dir),
not from memory; ocgtk stub claims against `_opam/.opam-switch/sources/ocgtk/src/gtk/generated/`.

## Summary

The three keyed containers really are one machine, and the parts that matter are shared
rather than parallel: one `Child_keys` module with the "key on the widget the patcher
retains" invariant stated once and satisfied by all three (`w_list_box.ml:21`,
`w_flow_box.ml:36`, `w_notebook.ml:56`); one `interest`/`enqueue_fixups` arm apiece with
identical shape (`patcher.ml:158-166`, `:281-296`); every selection read is a walk of the
live container, in all four readers per container plus both `Live_tree` arms, so no cached
key→widget map exists anywhere to go stale; `Child_keys.set` before the GTK call and
`Child_keys.remove` before it in all three; `forget_rows`/`forget_children`/`forget_pages`
all placed *above* the or-pattern chain in `release_kind` (`patcher.ml:387/391/393`) and
reached on both teardown paths (`destroy` and `mount`'s `unwind`). I traced the four ways a
wrapper can leave — `list_ops.remove`, the `Update` kind-change arm, subtree teardown, and a
part-way `mount_list` raise — and found no path that leaks or orphans a `Child_keys` entry.

The `?ordered` change is correct. I hand-executed `Reconcile.diff ~ordered:false` against the
patcher's `cur` bookkeeping on mixed remove/insert/reorder cases and the reconciler's
`current` stays in lockstep with `cur`; every `Update`'s index names the live record it means,
and `List.take !current i` can never exceed the list (at step `i`, `|current| = |kept| +
inserts_so_far >= i`). `Move` reaches only the three containers that declare `move`, and all
three honour `widget_impl.mli:22-37`'s single statement of the `~after` contract — the two
remove-and-re-insert containers by reading the predecessor's index *after* their removal, the
notebook by the `from < a` compensation, whose arithmetic I checked in both directions.

No dead key reaches the model. Under `Driver` every emission during a pass is dropped by
`Signals.dispatch`/`dispatch_payload`'s `in_patch` guard (`signals.ml:57`, `:80`), fixups run
inside the same guard (`driver.ml:87-108`), and outside a pass every payload is resolved by a
walk of what the container still holds. `key_of_page_exn`'s raise is unreachable because
`destroy` empties slots and disconnects before `forget_pages` runs. All container getters this
code calls (`get_row_at_index`, `get_child_at_index`, `get_nth_page`, `list_box_row_get_child`,
`flow_box_child_get_child`, `stack_get_child_by_name`, `stack_get_page`, `overlay_get_child`,
`widget_get_parent`) `g_object_ref_sink` in the pinned stubs — Task 6's rule holds branch-wide,
including for `Widget.get_parent`, which is what makes both `move` implementations' "this scope
holds a reference across the unparenting" true.

Three Important findings, all verified against GTK's source rather than inferred: a reorder of
a *selected* child leaves GTK's own single-selection/anchor pointer NULL in both
remove-and-re-insert containers, and the library's walk-based reads are structurally unable to
see it (I1); a notebook page with no `Attr.tab_label` does not get an "unnamed tab" but a
*positional* `"Page N"` tab that renumbers on reorder, contradicting five places in the repo,
one of which records it as measured (I2); and `Node.stack ~visible_child` has the identical
never-lands-on-a-hidden-page divergence the notebook documents at length and the backlog
records, with nothing saying so anywhere (I3). Four Minors, all documentation or diagnostics.
No Critical.

## Critical

None.

## Important

### I1 — A reorder of a *selected* row/child leaves GTK's selection pointer NULL, and a later `select_row`/`select_child` cannot repair it

`src/widgets/w_list_box.ml:373-401` and `src/widgets/w_flow_box.ml:374-398` implement `move` as
`remove` + `insert`, holding the wrapper alive across the unparenting. That preserves the
GObject, the key, and the child's own `selected` flag — but not GTK's container-side selection
state:

- `gtk_list_box_remove` (gtklistbox.c:2485-2486) does `if (row == box->selected_row)
  box->selected_row = NULL;` and **never clears `ROW_PRIV(row)->selected`**.
- `gtk_flow_box_remove` (gtkflowbox.c:3136-3137) does the same with `priv->selected_child`.
- Neither `gtk_list_box_insert` (gtklistbox.c:3060-3090) nor `gtk_flow_box_insert` restores it.

So after moving the selected row, the box holds a row whose `selected` flag is `TRUE` with
`box->selected_row == NULL`. Everything this library reads agrees the row is selected —
`is_selected` is exactly `ROW_PRIV(row)->selected` — so `selected_keys`, `apply_selection`'s
`current`, and `Live_tree`'s `selected_row_count`/`selected-children` counts all report the
pre-move selection, `current = wanted`, and `apply_selection` writes nothing. The divergence is
invisible to every reader the branch has.

This is not a hypothetical arrangement: `test/live/expected_lists.txt:28-40` is precisely it.
The list box is `selection-mode multiple`, `after mount: b`, B is moved from index 1 to 3
("the original rows are now at: 0,2,3,1"), and the golden then shows `(selected-rows 1)` and
`GtkListBoxRow selected` on B — both read from the flag. `expected_lists.txt:134-137` ("fb
selection survived the reorder: b") is the flow-box twin. The tests confirm the premise; they
cannot see the consequence.

Concrete failures, all with the moved row still looking and reporting selected:

1. **Multiple mode, shift-click range selection degrades to a single row.** `box->selected_row`
   is the range anchor (gtklistbox.c:1853-1868; gtkflowbox.c:1105-1111). With it NULL, a
   shift-click takes the `selected_row == NULL` branch: it calls `unselect_all_internal` —
   discarding the user's whole multi-selection — and then selects only the clicked row instead
   of the range between anchor and click. A library grid the user sorted while cards were
   selected (the flow box's own showcase use in `w_flow_box.ml:320-326`) reproduces it.
2. **Keyboard navigation enters at the wrong row.** With no focus row, GTK starts from
   `box->selected_row` and falls back to first/last when it is NULL
   (gtklistbox.c:2118/2127; gtkflowbox.c:3210-3211), so Tab/Down after a reorder lands on row 0
   rather than on the selected row.
3. **`gtk_list_box_get_selected_row` / the single-selection API answers NULL** for a box that is
   painting a selected row — visible to any `Expert.embed` consumer or GtkBuilder-side code
   holding the same `GtkListBox`.

Severity: Important rather than Critical because it self-heals — the next ordinary click takes
`select_row_internal`'s `mode != MULTIPLE` branch (gtklistbox.c:1758-1760) or `unselect_all`,
both of which walk `box->children` and re-normalise (gtklistbox.c:1707-1726) — and because no
state is corrupted, only degraded until then.

The obvious repair does not work and is worth stating so nobody tries it: re-issuing
`W.List_box.select_row` after the re-insert is a **no-op**, because `select_row_internal`
returns early on `if (ROW_PRIV (row)->selected) return;` (gtklistbox.c:1754-1755; identically
`gtk_flow_box_select_child_internal`, gtkflowbox.c:1013-1014). What does work is
`unselect_row` then `select_row` on a row that was selected before the removal (in `MULTIPLE`
`unselect_row_internal` clears just this row and `select_row` restores flag *and* anchor
without touching the siblings; in `SINGLE`/`BROWSE` the unselect-all-then-select-one round trip
lands on the same single selection). Alternatively the patcher could force
`apply_selection` to write after any `Move` on these two kinds. Either way the fix belongs in
both `move`s and wants a live case that asserts through `get_selected_row`/`get_selected_children`
rather than through the flag walk — today nothing in the repo reads GTK's side of the selection
at all, which is exactly why this got through.

### I2 — A notebook page with no `Attr.tab_label` does not get an "unnamed tab"; it gets a *positional* `"Page N"` tab that renumbers on reorder

Five places in the branch state that dropping (or omitting) `Attr.tab_label` leaves the page
with GTK's "unnamed tab":

- `vtree/attr.mli:313-314` — "A page without one gets GTK's own unnamed tab"
- `vtree/attr.mli:320-321` — "dropping the attr puts the unnamed tab back"
- `src/widgets/w_notebook.ml:74-76` — "`gtk_notebook_set_tab_label` with NULL, which draws an
  unnamed tab"
- `src/widgets/w_notebook.ml:419-422` — "what makes dropping the attr restore GTK's unnamed tab
  instead of drawing a blank one"
- `test/test_widgets.ml:768-770` — "**measured** — `get_tab_label` answers `None` and there is
  no label widget at all" (and `test/live/live_lists.ml:1378-1380` repeats the claim)

GTK 4.22 does the opposite. `gtk_notebook_set_tab_label`'s own docstring says so —
"If %NULL is specified for @tab_label, then the page will have the label “page N”"
(gtknotebook.c:6592-6594) — and the code builds it: with `show_tabs` true it does
`g_snprintf (string, ..., _("Page %u"), g_list_position (notebook->children, list));
page->tab_label = gtk_label_new (string);` (gtknotebook.c:6627-6641), and
`gtk_notebook_update_labels` (gtknotebook.c:4410-4448) rewrites every default tab's text from
its **current position** on every insert, remove and reorder (call sites at :4159, :6267,
:6508, :6871).

The measurement that produced "there is no label widget at all" was taken through
`gtk_notebook_get_tab_label`, which returns NULL for a default tab *even though the label
exists and is drawn* (gtknotebook.c:6578-6580) — and every notebook golden that drops a tab
label is either read through `get_tab_label_text` (`test/live/live_lists.ml:1033-1039`, giving
`after a tab rename and a tab dropped: Renamed,<none>` at `expected_lists.txt:244`) or dumped
with `no-tabs` set (`expected_lists.txt:247`, where GTK never builds the default label at all).
So the repo has never observed the state it documents.

Why it matters for this lens rather than only as a doc bug: it puts a **positional** label on
the one keyed container whose whole premise is that position is not identity. `Node.notebook
~current_page:"b" [a; b; c]` with no `Attr.tab_label` shows tabs reading "Page 0", "Page 1",
"Page 2"; the model reorders the child list, `reorder_child` correctly keeps every page's
identity, its scroll position and its focus chain — and the tab captions renumber underneath,
so the tab that said "Page 1" is now over a different page. That is the exact failure the
container exists to prevent, arriving through the one child GTK owns rather than the library.

Fix is documentation plus a decision: correct all five sites to say GTK draws a positional
`"Page N"` (with `show_tabs` on), and either say on `Attr.tab_label` that a page in a
tab-showing notebook should always carry one, or have `w_notebook.ml`'s `insert`/`updated`
write `Some ""` for the `None` case (which the M1/M2 "blank clickable switcher button"
precedent in `w_stack.ml` argues against) — the choice wants the lead. `test_widgets.ml:768`'s
"measured" claim must lose the word or be re-measured with `show_tabs` true.

### I3 — `Node.stack ~visible_child` has the notebook's hidden-page divergence, documented nowhere

`docs/m2-backlog.md:122-127` records, as a "Do first in M3" item, that a page carrying
`Attr.visible false` which is also `~current_page` makes the notebook's fixup write on every
frame forever with no diagnostic; `vtree/node.mli` spends a paragraph on it under
`Node.notebook` ("A page carrying `Attr.visible false` is the other way to make
`~current_page` unable to land"), and `w_notebook.ml:184-189` explains the read-back exists
for it.

`Node.stack` has the identical hole and nothing in the branch says so.
`gtk_stack_set_visible_child_full` ends with
`if (gtk_widget_get_visible (child_info->widget)) set_visible_child (...);`
(gtkstack.c:2309-2310) — **no else, no warning**. So for a stack whose `~visible_child` names a
page carrying `Attr.visible false`:

- `W_stack.select` (`src/widgets/w_stack.ml:79-105`) finds the child by name, so it does not
  take the raising branch;
- `get_visible_child_name` keeps answering with whatever page is actually showing (or `None`),
  so the comparison is unequal on every frame;
- `set_visible_child_name` is called on every frame, forever, and silently does nothing.

Failure scenario: a wizard step or a detail pane hidden behind `Attr.visible` while it loads,
named as `~visible_child` for the same frame. The stack shows the previous page indefinitely,
the model believes it navigated, and there is no message anywhere — the case §6.5 exists to
prevent, in the container §6.5 was first written for.

`Node.stack`'s docstring is otherwise written as a deliberate mirror of `Node.notebook`'s (it
even says "Both asymmetries are documented on both constructors; do not 'fix' one of them"), so
the missing paragraph reads as an oversight rather than a decision. At minimum: the paragraph
on `Node.stack`, a sentence in `w_stack.ml`'s `select`, and the backlog item at
`docs/m2-backlog.md:122` extended to name `w_stack.ml` — it is the same defect and should be
fixed once, in whichever task takes the `Patcher.ctx.report` hook the item already proposes.

## Minor

### N1 — `apply_selection`'s "the write is deliberately not narrowed" argument is vacuous

`w_list_box.ml:212-217` (and `w_flow_box.ml:177-179`, `:232-235`) argue at length that the
write iterates the *unnarrowed* `selected` rather than `wanted`, "so that what the model asked
for reaches GTK and what GTK kept is what the next frame reads back", and cite ruling 5.

The two are the same program. The write is
`List.iter selected ~f:(fun key -> Option.iter (Hashtbl.find by_key key) ~f:...)`
(`w_list_box.ml:249-251`, `w_flow_box.ml:234-235`) and `wanted = List.filter selected ~f:
(Hashtbl.mem by_key)` (`:240` / `:225`) — so a key naming no row is skipped by the `Hashtbl.find`
either way, and iterating `wanted` would emit a byte-identical sequence of `select_row` calls.
The distinction only exists for duplicate keys (see N4). As written it invites a future reader
to believe unresolvable keys are handed to GTK, which is the belief `child_by_key`'s "never
cache this" comment exists to stamp out. Three or four sentences to delete in two files.

### N2 — `w_notebook.ml:349` contradicts `w_box.ml:39-40` about how many real reorders exist

`w_notebook.ml:349` opens `move` with "**The one real reorder in the library.**"
`w_box.ml:39-40`, in the same branch, says "A box is one of the two containers that can really
reorder (the other is M2's notebook)" and uses `W.Box.reorder_child_after`
(`w_box.ml:41-44`). The box is right; the notebook's superlative is wrong. Since the notebook's
header comment (`:13-23`) is where the functor question is settled by counting what the
containers share, an inaccurate count there is worth one word: "the one real reorder among the
keyed containers".

### N3 — Two of the three containers say a handler runs mid-patch; under `Driver` it does not

`w_list_box.ml:411-415` ("GTK does emit `selected-rows-changed` synchronously from the remove,
so a handler really does run mid-patch") and `w_flow_box.ml:405-408` ("a handler really does run
while this patch is half-done") state it flatly. Under the runtime it does not: `Driver.frame_body`
wraps the whole pass and `run_fixups` in `Scheduler.with_patch_guard` (`driver.ml:87-108`), and
`Signals.dispatch` returns before touching the slot when `ctx.in_patch ()` (`signals.ml:57-58`).
The C callback runs; the application's handler does not. Only `w_notebook.ml:332-335` states the
distinction correctly ("Inside a patch the reentrancy guard swallows it; outside one — a test
driving `Patcher.mount` by hand — the handler really runs").

The claim is true of the context that *measured* it: `test/live/live_lists.ml:334-351` drives
`patch` by hand with no guard, which is why `expected_lists.txt:51` can print "the handler saw,
as the row left: a". Both comments should say so the way the notebook's does — otherwise a
reader concludes the model is notified when a selected row is removed by a render, and under
the driver it is never notified at all.

### N4 — A duplicate key in `~selected` makes `apply_selection` write on every frame

`~selected:["a"; "a"]` with `a` present gives `current = ["a"]` and `wanted = ["a"; "a"]`
(`w_list_box.ml:238-241`, `w_flow_box.ml:222-225`); the sorted lists never compare equal, so
every frame runs `unselect_all` plus a redundant `select_row`, forever, with no diagnostic. It
is the same "a model to bring into line" family as a `~selected` the mode cannot hold, which
`Node.list_box` documents — but duplicates are not mentioned there, and unlike the mode case
this one is a pure model typo with a one-line fix (`List.dedup_and_sort`). Either dedupe
`wanted` and `selected` in `apply_selection` or add it to the constructor's list of models to
bring into line.

## Out-of-scope observations

- **Verified, not a finding:** every container getter reached from a per-frame path
  `g_object_ref_sink`s in the pinned stubs — `list_box_get_row_at_index` (ml_list_box_gen.c:263),
  `flow_box_get_child_at_index` (:291), `notebook_get_nth_page` (:308),
  `stack_get_child_by_name` (:188), `stack_get_page` (:163), `list_box_row_get_child` (:99),
  `flow_box_child_get_child` (:58), `overlay_get_child` (:82), and `widget_get_parent`
  (ml_widget_gen.c:877). That last one is what makes both remove-and-re-insert `move`s safe:
  `row_of`/`child_of` hand back a strongly-referenced wrapper, so `gtk_list_box_remove` dropping
  the container's ref cannot free it before the re-insert.
- **Verified, not a finding:** `gtk_list_box_remove` does *not* auto-select a neighbour
  (gtklistbox.c:2482-2492 clears `selected_row` and emits, nothing more), so removing the
  selected row in `BROWSE` mode leaves `current = []` and, with the model's dead key narrowed
  away, `wanted = []` — equal, no write. The "removed while selected → inert" claim holds for
  both plural containers, in every selection mode.
- **Verified, not a finding:** the placeholder is invisible to the index arithmetic. GTK keeps
  it outside `box->children` (gtklistbox.c:2436-2444), so `rows`, `get_row_at_index` and
  `gtk_list_box_insert`'s position all agree with the patcher's `cur`, and `patch_slots`
  processes "placeholder" before "rows".
- **Verified, not a finding:** kind-change-in-place through the wrapper is right on all three.
  `patch_list`'s `Update` arm (`patcher.ml:893-906`) removes the old widget and re-inserts the
  fresh one, and each container's `insert` re-reads every parent-held setting from the new node
  — `wrap` re-reads `selectable`/`activatable`, the notebook re-reads `tab_label`, the stack
  `page_title`, the grid its cell, the overlay its measure flag — so nothing is lost by
  `updated` being skipped on that path.
- The `Live_tree` notebook arm prints `current-page` as an *index* while the list box and flow
  box print per-child `selected` flags, so no golden can pin "which page is current" by key.
  Already on the backlog (task-8 carries 2 and 5); noted only because it is the reason I1 and
  I2 have no golden that would have caught them.
- The `w_list_box`/`w_flow_box` duplication item on the backlog gains a third data point: N1
  and N3 are each present twice, in copies that differ only in nouns. The standing trigger the
  task-7 review left ("if M3 produces a third") is arguably already met by the fix wave for
  those two.

## Verdict

**Approve with fixes.** No Critical; the container machinery is sound and genuinely unified,
the `?ordered` change is correct, and `Child_keys` hygiene holds on every path I could reach.
I1 is the one behavioural defect and should be fixed in this wave — it is small (a
`is_selected` read before the removal and an `unselect`/`select` pair after the re-insert, in
two files) and it is user-visible in a container whose showcase use is a sortable grid; it also
wants the live assertion through GTK's own selection getters that nothing in the repo currently
makes. I2 and I3 are documentation-and-backlog corrections that state facts the branch
currently gets wrong (I2 records a false claim as measured), and both are cheap. The four
Minors are comment and diagnostic work. Nothing here blocks the merge once I1 lands.

## Re-review (fix wave)

Re-checked at `36aa26c` against `f06a615..36aa26c`. Scope: only my own findings, plus the one
place another commit in the wave could have moved a conclusion in my Summary. No builds; every
GTK claim below re-derived from gtk-4.22.4's source, every binding claim from the pinned stubs.

**I1 — fixed, and fixed correctly, including the mode question I had left open.**
`src/widgets/w_list_box.ml:417-441` and `src/widgets/w_flow_box.ml:392-423` read
`is_selected` on the wrapper *before* the removal, guard the repair on it, and apply
`unselect_row`/`unselect_child` then `select_row`/`select_child` after the re-insert. Checked:

- *Applied only when the moved child was selected* — yes, `if was_selected then (...)`, and
  `was_selected` is read off the wrapper before `remove`. An unselected row is untouched, so the
  common reorder costs nothing.
- *The early-out I documented is really the reason the pair is needed* — yes, and the fix cites
  it (gtklistbox.c:1754-1755, gtkflowbox.c:1012-1013). A plain re-select would still be a no-op.
- *Single vs Multiple vs Browse* — this is the part I flagged as subtle and it is right in all
  four modes. `MULTIPLE`: `unselect_row_internal` takes its `else` branch and clears **this row
  only** (gtklistbox.c:1740-1741; gtkflowbox.c:995-996), so siblings' selection survives; the
  select then restores flag *and* anchor. `SINGLE`: the round trip is unselect-all-then-select-one
  and lands where it started. `BROWSE`: **works, and only because the fix chose `unselect_row`
  rather than `unselect_all`** — `gtk_list_box_unselect_all` returns early on `BROWSE`
  (gtklistbox.c:998-1013) and `gtk_flow_box_unselect_all` likewise (gtkflowbox.c:4806-4819), but
  neither `gtk_list_box_unselect_row` (:960-968) nor `gtk_flow_box_unselect_child` (:4766-4774)
  has that guard — each calls its `_internal` directly. Had the repair gone through `unselect_all`
  it would have silently done nothing in `BROWSE`. `NONE`: both internals return early, and the
  guard cannot be true anyway (setting the mode to `NONE` runs `unselect_all_internal`, and
  `update` runs before children are patched).
- *Does the anchor really survive* — yes, and it is now asserted through GTK's own side rather
  than through the flag. `gtk_selected_row` (`test/live/live_lists.ml:67-77`) calls
  `W.List_box.get_selected_row`, which is `return box->selected_row` (gtklistbox.c:846-851) — the
  exact pointer that was being lost. New golden lines: `GTK's own selected row after mount: b`,
  `GTK's own selected row after the reorder: b`, `after moving the selected row: HEADER,B,C,A` /
  `GTK's own selected row, having moved it: b` / `the library still reads: b`
  (`expected_lists.txt:29,31-32,46-48`). The binding exists and is ref-safe
  (`ml_list_box_gen.c:240-247`, `g_object_ref_sink`), as do `unselect_row` (:29) and
  `unselect_child` (`ml_flow_box_gen.c:29`).
- *The new case really exercises `move` on the selected child* — yes, and this was the trap. I
  hand-ran the reconciler on the new patch: `[hdr;c;a;b] → [hdr;b;c;a]` yields exactly one `Move`,
  `{from = 3; to_ = 1}`, and it is `b`, the selected row. The pre-existing reorder cases moved `c`
  and merely *shifted* `b`, so they never entered `move` for a selected child — which is precisely
  why the suite could not see the bug, and the commit says so.
- *The flow box's assertion is weaker and admits it* — correct and correctly explained.
  `gtk_flow_box_get_selected_children` walks `CHILD_PRIV(child)->selected` (gtkflowbox.c:4720-4738),
  so it agrees with this library either way and cannot see the anchor; the flow box's
  `selected_child` has no getter. The test therefore goes through the one reachable consequence,
  `gtk_widget_child_focus` with no focus child taking `BOX_PRIV(box)->selected_child` and falling
  back to the first focusable (gtkflowbox.c:3208-3221) — verified at those lines — giving
  `fb keyboard focus enters at: b` (`expected_lists.txt:145`). It is one step removed from the
  anchor and would go green if GTK ever changed that fallback; the test's own comment says as
  much. Acceptable as the best available reading, not a gap.

**I2 — fixed at all five sites, and the re-measurement is right.** `vtree/attr.mli:319-337`
(rewritten, with the `~show_tabs:false` carve-out and a `{b Give every page of a tab-showing
notebook one.}`), `w_notebook.ml:77-85`, `:346-350` (`insert`), `:429-434` (`updated`), and
`test/test_widgets.ml:768-778` — the last now scopes its claim to the `~show_tabs:false` node it
sits beside and explains why the original measurement could not have seen otherwise. The new
golden `what GTK draws for the dropped tab: Renamed,Page 2` (`expected_lists.txt:255`) is read
from the header's widget tree rather than through `get_tab_label`, which is the only way to see
it. The carve-out is correct: `gtk_notebook_update_labels` returns early on
`!show_tabs && !menu` (gtknotebook.c:4416-4417) and `set_tab_label`'s NULL branch builds the
label only `if (notebook->show_tabs)` (:6631). **One correction to my own report, which the fix
got right and I did not**: the numbering is 1-based, not 0-based — `update_labels` starts at
`int page_num = 1` (gtknotebook.c:4415), so the second page reads `Page 2`. (The NULL branch's
own `g_list_position` is 0-based, but `update_labels` runs after it and overwrites; the golden
records what is actually drawn.) Keeping the impl on NULL rather than `Some ""` is the right
call and matches the `w_stack.ml` precedent it cites.

**I3 — documented in all three places I asked for, and the backlog entry is better than what I
proposed.** `vtree/node.mli:768-783` gains the `Attr.visible false` paragraph under
`Node.stack`, restoring the deliberate mirror with `Node.notebook`; `w_stack.ml:78-90` states it
at the `select` fixup with the gtkstack.c:2308-2310 citation; and `docs/m2-backlog.md:128-135`
folds it into the existing notebook item rather than opening a second one, with the reason ("one
memo shape serving both"). The residual is exactly what the item says it is — the report-once
half is deferred, deliberately, to whichever task takes the `Patcher.ctx.report` hook.

**Minors.** N1 taken in both files (`w_list_box.ml:212-219`, `w_flow_box.ml:177-181`, `:234-236`)
— the comments now say the two spellings emit the same calls and name the duplicate-key case as
the only difference, which is the accurate statement. N2 taken: `w_notebook.ml:359` now reads
"The one real reorder among the keyed containers" with a parenthetical pointing at `Node.box`,
and no longer contradicts `w_box.ml:39-40`. N3 taken in both files (`w_list_box.ml:451-463`,
`w_flow_box.ml:428-440`) — both now distinguish the driver path (guard swallows it, handler never
runs) from the hand-driven patch the measurement came from, matching what `w_notebook.ml:342-344`
already said. N4 declined into `docs/m2-backlog.md:136-144` with the reasoning and the one-line
fix named; I agree with deferring it — it is a behaviour change on the selection path and belongs
with the report-once decision above.

**One Summary claim re-checked because another commit touched it.** `8bd5df9` rewrote
`Patcher.destroy` to collect-and-re-raise (`patcher.ml:667-690`). The *stage order* is unchanged
— slots, controllers, connections, children, `release_kind` — so `forget_rows`/`forget_children`/
`forget_pages` still run last, on a container whose wrappers are still parented, and `mount`'s
`unwind` still ends at `release_kind` (`patcher.ml:478`). My "no path leaks or orphans a
`Child_keys` entry" conclusion still holds, and is now strictly stronger: a `Native` child whose
`destroy` raises no longer skips its container's `release_kind`, so it can no longer strand a
notebook's or a list box's table entries. Nothing else in the wave touches the container paths.

**Verdict: approved.** All three Important findings are closed — I1 in code with a repair that is
correct in every selection mode (including the `BROWSE` case that a natural-looking alternative
would have got wrong) and pinned by a mutation-verified assertion through GTK's own selection
getter, I2 and I3 as documentation with the re-measurement actually taken rather than asserted.
All four Minors are taken or deferred with stated reasons. I have no new findings and nothing
outstanding on this lens.
