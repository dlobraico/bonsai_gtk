# Task 10 report — DropDown and LevelBar

**Commit:** `ce6497d` on `m2`, base `d9f9d93`. 32 files, +2137/−53.
**Gate:** `nix develop -c ./scripts/ci.sh` → `all green`, exit 0.

Both widgets landed with everything the brief lists. Three things came out of the probing
that the brief did not anticipate and that changed the design; they are the first three
sections below, because the rest only makes sense after them.

---

## What the probe found before any code was written

Everything below was measured on GTK 4.22 through the pinned binding, not read out of the
docs. Each one changed a decision.

| Question | Answer | Consequence |
|---|---|---|
| `set_selected invalid_list_position` over a **non-empty** model | **no-op.** Selection unchanged, and GTK emits *nothing at all* — zero `notify::selected` | `~selected:(-1)` over a non-empty list is a state the widget will not hold → `Patcher.ctx.report` + a refusal memo |
| What a **model rebuild** resets the selection to | **item 0**, not `invalid_list_position`, and it emits exactly one `notify::selected` | the brief's premise was half right; the same-frame re-apply is needed either way |
| `set_selected` out of range (5 over 3 items) | silently ignored | the constructor check is the only diagnostic there will ever be |
| `String_list.new_` reference count | **2** (should be 1) | a leaked `GtkStringList` per items change — binding defect, pinned in the golden |
| `Drop_down.get_selected_item` | stub is broken twice over | never called; recorded |
| `Drop_down.get_expression` on a `new_from_strings` result | `None` | `~enable_search`'s filtering cannot be asserted; recorded |
| `set_min_value 2.` on a bar whose max is 1. | `min=2 max=1`, value clamped up to 2, **no diagnostic**, even realized and in `DISCRETE` | write order rule; and `Node.level_bar` rejects `~min > ~max` |
| `set_min_value (-5.)` | `Gtk-CRITICAL`, **no write** | `Node.level_bar` rejects a negative bound too (not in the brief) |
| `set_value` below the minimum | stored, not clamped | the value must be rewritten whenever a bound moved |
| A `GtkDropDown`'s live children | ~25 widgets incl. a `GtkListView` whose item widgets vary with the model | `Live_tree` prints the drop-down's props and **no children** |

---

## The out-of-range / "nothing selected" rule, as shipped

Two different mistakes, decided in two different places, and the split is the point.

**An index that names no item is `Invalid_argument` at the constructor.** `Node.drop_down`
holds both the list and the index, so this is decidable at the line that made it — unlike a
stack's `~visible_child` or a list box's `~selected`, where "not there yet" and "never" are
the same thing until the tree exists, which is why those are inert-or-deferred (Tasks 6–8's
ghost-key rule). The asymmetry is the items' doing: they are **props, not children**. The
message names the index and the item count.

**`-1` is the one out-of-range value with a meaning, and GTK will not hold it over a
non-empty list.** This is the finding above. A `GtkDropDown` selects through an internal
`GtkSingleSelection` whose `autoselect` is on and which no drop-down method exposes, so the
write is a silent no-op. It gets the text view's treatment exactly:

- written once; the widget is read back; the refusal is recorded against the *index*;
- reported once through `Patcher.ctx.report` with the node's path (`Drop_down` is now a
  patcher `interest`, the hook's **second** caller — the ledger's carry asked for this);
- the memo makes every later idle frame an integer comparison — it is consulted *before*
  the comparison with the widget, which is task-9-review.md R1's ordering applied here;
- cleared by any write that lands **and by any model rebuild**, because a rebuild changes
  what GTK will accept (an emptied list will now take it; a refilled one will not);
- `~items:[] ~selected:(-1)` is honoured — GTK has nothing to autoselect.

So: clamp — no; inert — no; **report** — yes, and only for the case the constructor cannot
see. Documented on `Node.drop_down` in the application's vocabulary, with the fix
("render `~items:[]`, or select an item") in the message itself.

The live golden pins all five states, each followed by five idle frames that say and cost
nothing:

```
mounted asking for none: selected=0 (reports ((none/0"~selected:-1 asks for nothing ... item 0 is still selected...")))
mounted asking for none, five idle frames later: selected=0 (reports ())
then item 1: selected=1 (reports ())
asking for none again: selected=1 (reports (( ... item 1 is still selected...)))
no items at all: selected=-1 (reports ())
items again: selected=0 (reports (( ... item 0 is still selected...)))
```

The third line is "the model is not wedged"; the fourth is "the memory is of an index, not
of a widget"; the last is "a rebuild forgets".

---

## The model-rebuild strategy, and the idle-frame numbers

**Rebuilt, not spliced**, as the brief rules. `set_items` builds a fresh `GtkStringList`
and hands it to `set_model` — one call, obviously correct, and expensive (it closes an open
popup, re-lays-out the button and resets the selection), so what makes it affordable is
that it happens only when the items really differ.

**The comparison and its cost.** `same_items a b = phys_equal a b || List.equal String.equal a b`.

- `phys_equal` first: a view that computes its items once and hands back the same list
  answers in a pointer comparison.
- Otherwise *n* string comparisons, short-circuiting at the first difference.
- **Either way it is paid only on a frame where something about the node already
  differed**: the patcher compares `Kind.equal_props` first and skips `update` entirely
  when the props are equal, and `reassert_only` (the whole of an idle frame) never calls
  `update` at all. An idle frame does not look at the items.

**An idle frame is `get_selected` plus an integer compare**, whatever the list holds. The
bench measures that directly, as a ratio (machine- and contention-independent):

```
bench: 0.00013 ms at 4 items, 0.00013 ms at 1000 items, ratio 0.98 (bound 5)
bench: 0.00013 ms parked on a refused selection, ratio 0.96 (bound 5)
```

The second arm is the R1 shape from Task 9 — a controlled prop the widget refuses, parked
on forever. Without the memo each of those 20 000 frames would set the property and take a
`freeze_notify`/`thaw_notify` pair for a write GTK throws away. `refusals reported across
every frame above: 1` is in the golden, over 20 000 parked frames.

**Mutation-checked, both directions.** Replacing `same_items old.items new_.items` with
`true`:

```
                    shipped                              unconditional rebuild
selection alone     same model: true                     same model: false     <- test fails
nothing at all      same model: true                     same model: true      (update not called)
```

The second row is worth keeping in mind when reading the test: `Kind.equal_props` is the
outer guard and `same_items` the inner one, and only the first row distinguishes them.

---

## Reentrancy: what GTK emits and what Bonsai hears

The golden accounts for every emission rather than asserting silence, because "Bonsai heard
nothing" is only interesting while GTK is emitting something:

```
selection alone:                    GTK emitted 1, reached Bonsai 0
nothing at all:                     GTK emitted 0, reached Bonsai 0
items changed:                      GTK emitted 2, reached Bonsai 0   (set_model, then set_selected)
items changed, selection unchanged: GTK emitted 2, reached Bonsai 0
after a drain:                      GTK emitted 5 in all, Bonsai heard 0
user picked (outside a patch):      reached Bonsai 1
model declines:                     GTK emitted 1, reached Bonsai 0   (reassert put it back)
```

A model rebuild *does* emit `notify::selected` — the reset to item 0 — and so does the
re-apply, and both are inside the patch, so `in_patch` covers them. **Nothing is deferred**
(this is not the search entry's debounced signal): the `after a drain` line is the check
that draining the main loop produces no late arrival.

---

## Stub safety table

Every generated stub this task calls, read in `.ocgtk-src` rather than inferred from the
GIR — the rule Task 6's C1 established.

| Call | Transfer | Stub | Verdict |
|---|---|---|---|
| `Drop_down.new_from_strings` | full, floating (`GtkWidget`) | `g_object_ref_sink` | **safe** — sinks a floating ref; measured refcount 1 |
| `Drop_down.set_model` / `set_selected` / `set_enable_search` / `set_show_arrow` | — | plain calls | safe |
| `Drop_down.get_selected` | value | `Val_int` | safe |
| `Drop_down.get_model` | none | `g_object_ref_sink` + `Val_option` | **safe** — the sink balances the wrapper's unref; 500 wrappers + `Gc.full_major` pinned in the golden |
| `Drop_down.get_selected_item` | none | `ml_gobject_val_of_ext`, **no sink**, and returns a bare block where the `.mli` says `option` | **UNUSABLE — not called.** Backlogged |
| `Drop_down.get_expression` | none | `g_object_ref_sink` on a `GtkExpression` (not a `GObject`); answers `None` regardless | **not called.** Backlogged |
| `String_list.new_` | full, **not** floating | `g_object_ref_sink` | **LEAKS one GObject per call.** Used; refcount 2 pinned in the golden; backlogged |
| `String_list.get_string` | none (`const char *`) | `Val_option_string` (copies, no free) | safe — not called on a frame path |
| `List_model.from_gobject` | — | type-checked, `g_object_ref` | safe |
| `List_model.get_n_items` | value | `Val_int` | safe |
| `List_model.get_object` | **full** | no ref (correct for full), `Val_option` | safe |
| `String_object.get_string` | none | `caml_copy_string` | safe |
| `Level_bar.new_` / `new_for_interval` | full, floating | `g_object_ref_sink` | safe; measured refcount 1 |
| `Level_bar.set_*` / `get_*` | — | plain calls | safe |

`get_selected_item` is the one worth flagging loudest: it is the *obvious* call for "what
is selected", it is broken in two independent ways (unbalanced unref **and** a type
confusion that reads a raw pointer word as an `option` payload), and nothing but reading the
stub would show it.

---

## LevelBar: the write order, and what is actually observable

`set_bounds` writes whichever bound moves outward first: `if new_min > old_max then (max;
min) else (min; max)`. The proof is in the comment — since `old_min ≤ old_max` and
`new_min ≤ new_max` (the constructor guarantees the second), at most one of the two orders
is unsafe, so testing either condition picks a safe one. `create` sidesteps it entirely
with `new_for_interval`, which sets both at `g_object_new` time.

**Honest limitation, stated because a reviewer will look for the test:** the ordering makes
**no difference to the final state**, and I verified that rather than assuming it. Both
orders converge, because the value is rewritten last and GTK's clamping is idempotent; and
GTK logs *nothing* in either order, realized, with a main loop running, in `DISCRETE` mode.
So there is no golden that can distinguish them. What the golden carries instead is:

- the **measurement** on a raw widget (`raw widget, minimum written first: min=2 max=1
  value=2`), so the reason the rule exists is data rather than a comment — and it is the
  same measurement `Node.level_bar`'s `~min > ~max` rejection rests on;
- the case that **is** observable, which is the *other* half of the rule: a bar moved from
  `0–1` to `0.8–1` with its value standing at `0.5` has that `0.5` clamped up to `0.8` by
  the bound write, and only the unconditional value rewrite puts the model's number back.
  Mutation-checked: deleting the `old.min <> new_.min` disjunct makes the golden print
  `(value 0.8)` instead of `(value 0.5)`.

The asymmetry behind that: `set_min_value`/`set_max_value` drag the live value into the new
range; `set_value` does **not** clamp at all (a level bar can hold a value below its
minimum and draws empty). Measured.

---

## Per-step summary

**Step 1 — tests first.** `test/test_widgets.ml` (5 blocks), `test/handle/test_handle.ml`
(6 blocks), `test/live/live_text.ml` (6 blocks). Written before the impls; the live blocks
were then run red against the plumbing where that was meaningful (the two mutation checks
above are the recorded reds).

**Steps 2–5 — the vtree and the impls.**
- `vtree/level_bar_mode.ml` (`Continuous | Discrete`), re-exported from
  `Bonsai_gtk_vtree` and `Bonsai_gtk`.
- `Kind.drop_down_props` / `level_bar_props`, `Node.drop_down` / `level_bar`,
  `Defaults.Drop_down` / `Level_bar` (all read off fresh widgets).
- `Attr.on_selected_changed : int Handler.t`, inserted after `On_page_changed` so no
  existing `Attrs.diff` order moves.
- `src/widgets/w_drop_down.ml`, `src/widgets/w_level_bar.ml`; `registry.ml`;
  `Gtk_import` gained `Gtk_constants` and `List_model` aliases.
- `Patcher`: `Drop_down` is an `interest` whose `enqueue_fixups` arm reports; `Level_bar`
  is `Nothing`.

**Step 6 — `Live_tree`.** `GtkDropDown` prints `(items …)` and `(selected …)`
unconditionally (`()` for none, the notebook's spelling), plus `enable-search`/`no-arrow`
when not GTK's; **and no children**, which is the one kind whose internals are suppressed,
with the reason written down. `GtkLevelBar` prints `value`, `min`/`max` when not `0.`/`1.`,
`mode` when discrete, `inverted`.

**Step 7 — gate.** Below.

**`Events`/`Placement`/counts.** `Events.for_kind` gained `Drop_down _ -> [ On_selected_changed ]`
and `Level_bar _ -> []` (the arm Task 1 left; the comment says why a level bar emits nothing
we can expose — `offset-changed` exists but this library exposes no offsets to change).
`controller_family` and `Placement.reader` gained their `On_selected_changed` arms (both
wildcard-free). `kinds checked: 33 → 35` in both `all_kinds` lists;
`test_placement.ml`'s non-placement count `39 → 40`.

**`require_specs` negatives.** Six in `test_handle.ml`: `on_selected_changed` refused on
`Label`, `Stack` and `ListBox` (the two near misses — all three are "one of these is
showing" controls with differently spelled handlers); `on_visible_child_changed`,
`on_selected_rows_changed`, `on_page_changed` and `on_activate` refused on a `DropDown`;
two event attrs refused on a `LevelBar`.

**Headless action.** `Bonsai_gtk_test.Action.Set_selected of string * int` — kind-checked
like `Set_page`, consults nothing about the node (so a *declined* choice is expressible),
and carries an index because a drop-down's items are props. Three blocks: the choice
landing, the choice declined, and a `-1` node (legal headless; GTK is what declines it —
the one place in M2 where a green headless suite does not mean the runtime holds the state,
which the block says out loud).

**Gallery.** The Numbers page gained a drop-down of scales driving a level bar's range and
mode, plus an "Add a preset" button that changes the *item list* — the one thing that
rebuilds GTK's model — so the selection surviving a rebuild is visible by hand. The page
comment says what a level bar is for that a progress bar is not.

---

## Carries taken from Task 9

1. **Taken (carry 1): the wildcards.** `Kind.same_kind` is now
   `String.equal (name a) (name b)`. `name` is exhaustive with no wildcard, so a kind added
   without a decision there is a compile error and `same_kind` inherits it — closing the
   worst silent failure in that file (a missing arm made the patcher destroy and remount the
   widget on every frame). It also handles `Native` by construction. `equal_props` keeps its
   wildcard (34² arms is not a real option) but **raises** when `same_kind a b` is true
   there, which is exactly the reviewer's suggested guard; across kinds it still answers
   `false`. Both pinned by a new test.
2. **Noted (carry 2): the public-module list.** `Level_bar_mode` is a **third** public
   module beside `Wrap_mode` and `Tab_position` that the plan does not list; Task 15's docs
   and Task 16's §7/§5.1 sweep need all three, plus `?mode`.
3. **Taken (the ledger's note): `Patcher.ctx.report` has its second caller**, and it is the
   shape the note predicted — "a `~selected` the mode cannot hold". Its parked frames were
   measured at the same time, as asked (the bench's third arm).
4. Carries 3–6 (text-buffer reads, the cache invariant, `notify::cursor-position`,
   `Attr.on_changed` covering two signals) are text-view-specific and untouched here.

---

## Deviations, with reasons

1. **`on_selected_changed` is a `Read_back` spec, not `Payload`.** The task message said
   "via the object-carrying/`Payload` spec"; the brief's ruling 4 says `Signals.notify
   ~prop:"selected"` + `get_selected`, which is a `Read_back` by construction — a `notify::`
   goes through the generic marshaller and carries no payload, so there is nothing for a
   `Payload` spec to carry and no return value GTK wants. Nor is it object-carrying: the
   signal is on the widget, unlike the text view's buffer. I followed the brief.
2. **The handler carries the index only, not the index *and* the item string.** The task
   message suggested both; the brief's interface says `int Handler.t`. Two reasons beside
   the brief: the items are props, so the handler already holds the list it indexes into
   (the gallery does exactly this); and `notify::selected` reports a position, so carrying a
   string would make the attr claim more than GTK says. Documented on the attr.
3. **`Node.level_bar` also rejects a negative bound**, which the brief does not mention. GTK
   answers a negative `min` or `max` with a `Gtk-CRITICAL` and *no write*, so a node with
   one would silently keep the previous range — same shape as `Node.flow_box`'s negative
   geometry, checkable in the same place. Measured, tested, documented.
4. **`Live_tree` suppresses a `GtkDropDown`'s children**, which is a first for the dump. Its
   internals are ~25 widgets including a `GtkListView` whose child count follows the model,
   so a golden holding them would churn on an item being added and would say nothing. The
   items are printed from the model instead. Reason written at the suppression.
5. **`create` uses `new_from_strings`, `update` uses `String_list.new_` + `set_model`.** Two
   paths for one thing, deliberately: `new_from_strings` builds the model inside GTK (so the
   mount path never pays the leaked reference) and installs the `expression` the popup's
   search filter needs. Both reasons are in the comment.
6. **No offsets, no `mode` on the drop-down, no `Node.level_bar ~offsets`.** The brief's
   signatures list neither; `GtkLevelBar::offset-changed` is therefore omitted from
   `Events.for_kind` rather than bound to something nothing can provoke (spec §11).

No silent scope changes.

---

## Test and CI tails

```
== live tests (xvfb)
bench: 0.387 ms at sel=1, 0.440 ms at sel=200, ratio 1.14 (bound 5)
bench: 0.00020 ms at 16 chars, 0.00012 ms at 1 MB, ratio 0.61 (bound 5)
bench: 0.00015 ms parked on a refused 1 MB write, ratio 1.18 (bound 5)
bench: 0.00013 ms at 4 items, 0.00013 ms at 1000 items, ratio 0.98 (bound 5)
bench: 0.00013 ms parked on a refused selection, ratio 0.96 (bound 5)
== example smoke
all green
```

(The `exception in frame, stopping the driver` line in the gate's live section is
`live_driver.ml`'s deliberate negative and predates this task — verified by stashing the
whole change and re-running.)

Goldens that moved: `expected_text.txt` (appended only — every existing line byte-identical)
and `expected_events.txt` (`kinds checked: 33 → 35`). No other live golden changed.
`dune test` gained the new expect blocks and moved nothing else except
`test_placement.ml`'s count.

---

## Carries to Task 11

1. **Three binding defects are recorded in `docs/m1-backlog.md`'s ocgtk-fork section**, all
   for Task 14 and all *generator* fixes rather than hand patches: `ref_sink` on a
   non-floating constructor return (`String_list.new_` and every `*_new` of a non-widget
   class — `GtkStringObject`, `GtkStringFilter`, `GtkStringSorter`, `GListStore`-shaped
   classes), `get_selected_item`'s double defect, and `get_expression`. The first is the
   same audit as the `Val_GList_with` sweep already there, from the other end: the rule is
   *`ref_sink` iff the type is `GInitiallyUnowned` or the transfer is none/floating*, and
   the generator currently applies it to every constructor.
2. **`Kind.equal_props`'s wildcard now raises.** If a later task adds a kind and forgets the
   arm, the failure is a `Failure` naming the kind rather than a silent re-`update` — but it
   raises *at runtime*, so a kind added with no test that patches it still slips through.
   The compile-time half is `Kind.name`, which `same_kind` now depends on.
3. **`Live_tree` now has a kind whose children it does not print.** If a later task wants a
   second one, the suppression is a `String.equal ty` in one place and should probably
   become a list before it has three entries.
4. **`Attr.on_selected_changed` is the first handler in the container-ish family carrying an
   index rather than a `Key.t`.** If a later widget's selection is also positional, the name
   is available to share — but sharing it would need an `Events.for_kind` arm on both kinds,
   and a copied line would then be inert rather than rejected, which is the trap
   `Attr.on_child_activated` exists to avoid. Prefer a new name.
5. **The refusal-plus-report pattern now has two instances** (`w_text_view.ml`,
   `w_drop_down.ml`) with the same four moving parts: an ephemeron cache, a memo consulted
   before the comparison, an `unreported` slot the patcher drains, and a bench arm proving
   the parked frame is cheap. A third would be worth factoring; two is not.
6. **Task 8's hidden-page divergence still has no `report` hook** — it was the other
   candidate the ledger named, and this task only took the drop-down one. It is an
   `interest` already, so it is one line from a message.

---

# Task 10 report — Fix round 1

**Commit:** `b863bb2` on `m2`, base `ce6497d`. 11 files, +442/−175.
**Gate:** `nix develop -c ./scripts/ci.sh` → `all green`, exit 0.

All four Important taken as ruled, all seven Minor taken (none needed arguing). Every
finding was reproduced against the shipped code before anything was changed; two of them
correct claims the first round's report made confidently and wrongly, and those are marked.

---

## I1 — the model is spliced, and is never replaced

**Commit** `b863bb2`, `src/widgets/w_drop_down.ml:20-72`.

The ruling is right and the first round's reasoning was too narrow: the brief refused
computing a **diff**, and `splice model 0 n_old additions` is not one. It is the same "no
diff, one call" property a replacement has, and better on four counts — three of which I
measured rather than took from the review.

```ocaml
let string_list_type = lazy (Gobject.Type.from_name "GtkStringList")

let set_items (d : W.Drop_down.t) items =
  let additions = Array.of_list items in
  match W.Drop_down.get_model d with
  | Some model when Gobject.Type.is_a (Gobject.get_type model) (force string_list_type) ->
    W.String_list.splice (cast model) 0 (List_model.get_n_items model) (Some additions)
  | Some _ | None -> (* replacement, defensive *) …
```

`n_removals` is read off the **model**, not off the previous node —
`gtk_string_list_splice` requires `position + n_removals <= length`, which is the same
reason every controlled prop compares against the widget. The downcast is guarded with
`g_type_is_a` as ruled (there is no checked downcast in the binding; `from_gobject` is an
*interface* cast and runs the other way), and a model this library did not install falls
back to replacement, which is correct for any model and merely leaks.

**What changed in the golden**, and it is the whole evidence:

| line | before (`ce6497d`) | after (`b863bb2`) |
|---|---|---|
| selection alone | same model: true, emitted 1 | same model: true, emitted 1 |
| **items grew, selection moved** | **same model: false, emitted 2** | **same model: true, emitted 1** |
| **items changed, selection unchanged and in range** | same model: false, emitted 2 | **same model: true, emitted 0** |
| items shrank under the selection | same model: false, emitted 2 | same model: true, emitted 1 |
| after a drain | GTK emitted **5** in all | GTK emitted **3** in all |

The third row is stronger than the review predicted: with the selection in range on both
sides, a splice means **nothing at all is written** — no `set_selected`, no emission —
where a replacement had to reset to 0 and re-apply.

**The live claim was rewritten**, not merely re-promoted. It is now *"the model object is
never replaced"*, which is stronger and simpler than *"rebuilt only when the items
differ"*, and it is carried in the `same model:` column of every line in the block
(`true` everywhere, including the three that change the items).

**The refcount is pinned flat**, as ruled, and it needed care to be meaningful:

```
four items changes later: same model object throughout: true, references 4 -> 4, items=(a b c)
```

Each read is taken after a `Gc.full_major`, because every `get_model` in the test leaves a
wrapper holding a reference until collection — an unstable number here would be the test's
own noise rather than a leak. (The review's probe printed 14 and then 18 for exactly that
reason.) Under replacement this figure was not measurable at all: each items change
stranded a whole model at count 1, unreachable and uncounted.

**The backlog entry stays**, reworded: the defect is the generator's and covers every
non-widget `*_new` in the binding, so it is not closed by this library no longer walking
into it. The golden still prints `a fresh GtkStringList holds 2 references`, with the line
now saying that nothing on a reachable path pays it — `create` goes through
`new_from_strings` (model built inside GTK, no wrapper) and items changes splice, so the
only caller left is the defensive fallback.

**Correction to the first round's D5.** The two model-construction paths were justified as
keeping the mount path off the leaking constructor. The review's read was right: that was
an argument for removing the leaking call from the *update* path too. It is gone.

---

## I2 — the write order is observable, and the first round's report was wrong

**Commit** `b863bb2`, `src/widgets/w_level_bar.ml:22-44`, `test/live/live_text.ml`.

**Reproduced before believing it.** Flipping only the `then` branch of `set_bounds` to the
unsafe order, on the shipped tree:

```
                          shipped              unsafe order
offsets (mount, 0-1)      high filled empty    high filled empty
offsets (2-10)            filled empty         filled empty
offsets (back to 0-1)     high filled empty    low filled empty   <- wrong, two patches later
offsets (0.8-1)           high filled empty    low filled empty   <- still wrong
```

The review's finding is exactly right, including the part that matters most: the wrong
class appears on patches *after* the mis-ordered one and persists. While the bounds are
crossed GTK recomputes the bar's offset style class (`low`/`high`/`full` — the one that
colours the filled part) from a range that never existed, and nothing recomputes it
afterwards. So the inverted range is not transient at all; it leaves a durable, visible
rendering defect while every number on the widget is correct.

**What I got wrong and why it matters.** The first round checked the numeric props, found
them identical in both orders, and concluded "there is no golden that can distinguish
them". The conclusion was drawn from the properties I had chosen to print rather than from
the widget — the CSS classes were already in the dump, two levels into a nested sexp, and I
read past them. A maintainer told the ordering is untestable would have promoted that churn
as noise, which is the failure mode the review names.

**Fixed three ways**, since the point is that the guard should be legible rather than
incidental:

- the impl comment now says the damage outlives the call, names the style class, and names
  the mutation that demonstrates it;
- the live block prints an `offsets:` line of its own beside each dump, so the guard is one
  line rather than a diff buried in a sexp;
- the report section above ("LevelBar: the write order") is superseded by this one.

---

## I3 — the value-only patch

**Commit** `b863bb2`, `test/live/live_text.ml`.

Confirmed exactly as described: every level-bar patch in the block changed a bound, so
deleting `Float.( <> ) old.value new_.value` from the write condition left the entire suite
green — the widget's whole purpose unasserted.

The new case keeps `~min`, `~max`, `~mode` and `~inverted` fixed and moves only the value
(`~min:0. ~max:5. ~mode:Discrete ~inverted:true`, `~value:3.` → `4.`), which is stricter
than the ruling's `bar ~min:0. ~max:5. ~value:4.` — that one would also have changed `mode`
and `inverted` back to their defaults and so would not have isolated the value.

Mutation-checked: with the value disjunct deleted, `(value 4)` appears nowhere in the
output; the discrete block row that fills is the visible half.

---

## I4 — a stale index no longer ends the application

**Commit** `b863bb2`, `vtree/node.ml`, `vtree/node.mli`, `src/widgets/w_drop_down.ml`,
`test/test_widgets.ml`, `test/live/live_text.ml`, `examples/gallery.ml`.

Taken as ruled, and the review's framing of the risk is correct: `Node.drop_down` runs on
every render, so a list shrinking under an index is caught the moment it happens, and
"caught" meant `Driver.frame` marking the driver broken and the window never repainting
again. The justification the first round gave — "it is decidable here" — argues for a
diagnostic, not for an outage. The first round also inherited the brief's ruling without
weighing what a raise costs at that call site, which was the mistake.

**What raises now:** `~selected < -1`, and nothing else. That is the number no list of
items could make valid.

**What an out-of-range index does now**, which is the ghost-key rule over a different kind
of ghost:

- written to the widget; GTK ignores a position outside its model, silently and with no
  notification (measured);
- the read-back sees it, the refusal is remembered **against the index**, and the message
  is reported once through `ctx.report` with the node's path — and it names the fix
  (`clamp the index where the view builds the node`);
- GTK's own selection is left exactly where it was;
- the memo is cleared by any items change, so the frame the list grows to include the
  index is the frame it is selected — **that frame, not the next**.

Both directions are in the golden, in the order a real application meets them:

```
three items, item 2 chosen: selected=2 (reports ())
list shrank under the index: selected=0 (reports ((none/0"~selected:2 names no item: the list holds 1. …")))
list shrank under the index, five idle frames later: selected=0 (reports ())
list grew back to include it: selected=2 (reports ())
wrong again:       … reports once …
wrong differently: … a different index is a new decision, reported again …
```

**`node.mli` opens with a new section**, "What a constructor's `Invalid_argument` costs",
because the review is right that this applies to every constructor check in M2 and belongs
in one place. It states what the exception does under `Driver` (leaves the Bonsai
computation, marks the driver broken, abandons fixups, re-raises; no later frame repaints)
and the rule the checks follow: **reject only what no later frame could make valid**. A
state a correct model passes through is inert, applied on the frame it becomes meaningful,
and reported once. `Node.drop_down`'s paragraph now points at it and names the clamp.

**The gallery's guard is gone**: `~selected:scale` with a comment saying why no guard is
needed. It was, as the review says, a tax the constructor was charging.

**README carry for Task 15** is recorded in `docs/m1-backlog.md` under a new heading
*"Documentation M2 owes M3 (Task 15)"* — the backlog is the file Task 15 rewrites, so a
carry that lives only in a report would be read once and lost.

---

## Minors

**M1 taken.** Confirmed vacuous — the compiler shares the two structured constants, so
`phys_equal a b` was `true` and the structural comparison never ran. `b` is now built
(`List.map … ~f:String.capitalize |> List.map ~f:String.uncapitalize`), and the golden is
`(false true)`.

**M2 taken, both halves.** The case labelled "items changed, selection unchanged" moved the
selection from 3 to 1. It is now "items shrank under the selection", which is what it does,
and a genuine "items changed, selection unchanged and still in range" case sits above it —
which turned out to be the strongest line in the block after I1, since it is the one where
a splice writes *nothing at all*.

**M3 taken (report correction).** The first round's mutation table said *"Replacing
`same_items old.items new_.items` with `true`"* under a column headed "unconditional
rebuild". The mutation I actually ran replaced the whole condition `not (same_items …)`
with `true` — the substance was right, the recipe as written gives the opposite. Corrected
here rather than by editing history.

**M4 taken.** `Kind.same_kind`'s cost comment now says that a `Native` node allocates two
strings per comparison (`"Native:" ^ n.name` on each side), where the old matrix compared
the two `n.name`s with none — and names the fix if native nodes ever become common enough
to matter (an exhaustive allocation-free `tag` function, not a return to the matrix).

**M5 taken.** `Node.drop_down` now says that while a selection is parked on a refusal **the
prop is not being enforced**: the memo is consulted before the widget is read, so a choice
the user makes afterwards is left standing. With the reason (there is nothing to snap back
*to*), what still works (`on_selected_changed` reports it), and when control resumes.

**M6 taken (report correction).** `String_list.get_string` is not called anywhere, not
merely off the frame path. The stub-safety table's row should read *not called*; it is
still worth having in the table, since it is the obvious way to read an item back and its
stub is the one shape in that family that is correct.

**M7 taken.** `Live_tree`'s item read now checks `g_type_is_a … GtkStringObject` and prints
`<not a string>` otherwise, rather than an unchecked `cast`. One type check per item in a
test-only dump, and it keeps the two ends of the invariant honest independently of each
other — the write side enforces the same thing with the same call.

---

## Deviations in this round

One, and it is a strengthening rather than a substitution. I3's ruling names
`bar ~min:0. ~max:5. ~value:4.`; the case I added keeps `~mode:Discrete ~inverted:true`
from the preceding patch as well, so that the *only* thing changing is the value. The
ruling's literal version would have changed three props and so would not have isolated the
one the mutation removes.

---

## CI tail

```
== live tests (xvfb)
bench: 0.367 ms at sel=1, 0.417 ms at sel=200, ratio 1.14 (bound 5)
bench: 0.00020 ms at 16 chars, 0.00013 ms at 1 MB, ratio 0.63 (bound 5)
bench: 0.00013 ms parked on a refused 1 MB write, ratio 1.02 (bound 5)
bench: 0.00013 ms at 4 items, 0.00013 ms at 1000 items, ratio 1.00 (bound 5)
bench: 0.00012 ms parked on a refused selection, ratio 0.92 (bound 5)
== example smoke
all green
```

The drop-down bench is unmoved, as it must be: a splice is an items-change cost and an idle
frame does not reach it. `expected_text.txt` is the only live golden that changed; the text
view's half of it is byte-identical.

---

## Carries to Task 11 — revised

Items 1–6 of the first report's list stand, with these changes:

- **Item 1 is narrower.** The `String_list.new_` leak is no longer reachable through this
  library, so the backlog entry is now purely a generator fix for the binding rather than
  something bonsai_gtk pays. `get_selected_item` and `get_expression` are unchanged.
- **New: the constructor-raise rule is written down but only enforced by review.** `node.mli`
  says "reject only what no later frame could make valid", and nothing checks it. The
  remaining M2 constructor checks were each re-read against it during this round and all
  hold (a content minimum above a maximum, a missing `~key`, an inverted or negative level
  bar range are all permanently wrong) — but the next constructor check should be argued
  against that sentence before it is written, and Task 15's README carry is what makes the
  rule visible to a reader who is not reading `node.mli`.
- **New: two of this task's four Important findings were claims the first round made with
  confidence.** I2 (the order is untestable) was drawn from the properties I chose to print
  rather than from the widget; I4 inherited a ruling without weighing what the raise costs
  at that call site. Both were reproducible in minutes. The general lesson for the next
  round is the cheaper one: when a report says "X cannot be tested", the next step is a
  mutation, not a paragraph.
