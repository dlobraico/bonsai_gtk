# Task 8 review — Notebook: the first container with a real reorder

**Commit reviewed:** `0a4d11d` on `m2`, base `e9e7793` (33 files, +1902/−75).
**Gate re-run by the reviewer:** `nix develop -c ./scripts/ci.sh` → `all green`, exit 0.
The bench's new instrument reported `bench: 0.364 ms at sel=1, 0.394 ms at sel=200, ratio
1.08 (bound 5)` on this machine.
**Mutation testing:** five mutations built and run in a throwaway worktree at `0a4d11d`
(`git worktree add /tmp/m2-t8-verify`, removed afterwards; the checkout is untouched, and
`git status` is clean apart from the pre-existing untracked `.beads/issues.jsonl`).

---

## Summary

The widget is correct. I worked the reorder arithmetic by hand against every op shape
`Reconcile.diff` can emit and it is right in all of them — in fact it is *provably* right,
which the implementation does not claim and which is worth recording: given the patcher's
`after_of without to_` and GTK's `reorder_child` semantics, `w_notebook.ml`'s computed
`position` is identically equal to the reconciler's `to_`, for `to_ = 0`, for a move with
removes and inserts in the same patch, and for a kind change in place. `reorder_child`'s
clamp is never reached, because `Reconcile.diff` can never emit `to_ = n-1`. The keyed-child
bar Tasks 6 and 7 set is met: `Child_keys` is keyed on the widget the patcher retains, the
ordering of `Child_keys.set` against `insert_page` is load-bearing and mutation-proven, the
GC-churn block is a genuine regression (I broke it deliberately and it fired), and nothing
here is O(x×n) per frame.

Three claims in the report and in the source comments do **not** survive mutation testing.
None of them is a behavioural bug — in every case the shipped code is correct — but two of
them are the *recorded reasons* for non-obvious decisions, and the ledger would inherit
them:

1. `select`'s comment says comparing keys rather than indices "would read the write back as
   having landed" on a hidden page. It would not: a key comparison built from
   `W_notebook.current_key` is exactly equivalent to the index comparison, and I verified
   that by substituting one for the other and getting a byte-identical golden.
2. The `move` conditional's `if from < a then a` branch is unreachable under today's
   reconciler. Deleting it changes nothing in the golden, so the report's "Verified against
   GTK in both directions by the four live moves" is false. (The branch is still *correct*,
   and keeping it is the right call; only the coverage claim is wrong.)
3. Everything else in the report's mutation table reproduced exactly.

The judgement call in case 5 is right, and the implementer's extra argument for it — a
notebook with no `on_page_changed` has no way back from a clamp, where a list box's
"ignore what you cannot find" converges on its own — is the strongest one available and
should go in the ledger.

**Verdict: Approved**, with one Important (a comment correction) to land before the ledger
inherits the claim.

---

## What I verified independently

**The reorder, by hand.** GTK's `gtk_notebook_reorder_child` deletes the page's link and
`g_list_insert`s it at `position`, clamping `position < 0 || position > n-1` to `n-1`. So
`position` is the index in the *resulting* list, as the report says.

The patcher hands `move` a `~after` that is the element at `to_ - 1` of `without` (the live
list with the child removed) — `src/patcher.ml:642` and `:682-686`. Let `from` be the
child's index in the list GTK still holds and `a = page_num after`. Because removing index
`from` shifts every later index down by one, `a = to_-1` when `to_-1 < from` and `a = to_`
otherwise. Then `w_notebook.ml`'s `if from < a then a else a + 1` gives:

- `to_-1 < from` → `a = to_-1`, `from < a` false → `a+1 = to_` ✓
- `to_-1 ≥ from` → `a = to_`, `from ≤ to_-1 < a` so `from < a` true → `a = to_` ✓
- `to_ = 0` → `after = None` → `0 = to_` ✓

So `position ≡ to_` unconditionally. I checked the same identity holds for `insert`
(`page_num after + 1 = index`) and `remove` (`page_num child = index`), which is what keeps
GTK's page list in lockstep with the patcher's `!cur` at every step — including the
kind-change branch at `src/patcher.ml:710-720`, where the remove precedes the insert so
`after_of without index` still lands at `index`.

Two consequences the code does not state:

- `Reconcile.diff` processes new items left-to-right and always finds the match at an index
  `≥ i`, so **every `Move` has `from > to_`** — which is what makes finding (2) below true.
- `to_ = n-1` requires `from = n-1 = i`, which emits no `Move` at all, so **`Move` never
  targets the tail** and `reorder_child`'s clamp is never relied on. `live_lists.ml`'s
  comment on the head-to-tail case half-guesses this ("checked by the two moves either
  side of it"); it is actually a theorem.

**Mutations run (all rebuilt and re-run under xvfb, diffed against
`test/live/expected_lists.txt`):**

| Mutation | Result |
|---|---|
| `if from < a then a - 1 else a` (the report's off-by-one) | **10 golden lines change** — all four reorders, the middle insert, `add-and-select`, and the tab order inside a `Live_tree` dump. Non-vacuous in both halves. |
| `if from < a then a else a + 1` → `a + 1` (delete the conditional) | **no change at all.** The branch is dead. |
| `Child_keys.set` moved after `insert_page` | `EXN at root/0: (Invalid_argument "GtkLabel: this notebook page was not made by this library …")`, exactly as reported. |
| mount taken out of `Scheduler.with_patch_guard` | `handlers fired during the mount: 0` → `1`. The `in_patch` guard is what swallows GTK's first-page `switch-page`, as the brief asked to be proven. |
| `select` comparing `current_key nb` against `current_page` instead of the index | **no change at all** — see Important I1. |
| `Child_keys` entry rebound onto the transient wrapper `get_nth_page` returns | `nb gc: after 50 frames + full_major, current (none)` and the run dies at the next fixup (exit 2). The GC block is a real regression, not a decoration. |

**Other spot checks.** The one-sentence rule is present verbatim three times in
`vtree/node.mli` (lines 559, 635, 808) and nowhere else, as deviation 5 says.
`Signals.dispatch_payload` (`src/signals.ml:78-95`) checks `in_patch` and then the empty
slot *before* calling `fire`, so `key_of_page_exn` can only ever reach `on_exn` and never
GTK's C frame. `Patcher.destroy` clears slots before `forget_pages`, and the `Notebook _`
arm sits above the or-pattern chain (`src/patcher.ml:449`). `Attr.Name.all` is
`[@@deriving enumerate]`, so the two new names are counted rather than hand-listed; the
kind count moves 31→32 and the placement count 38→39, both pinned. The gallery's new page
really is exercised: `scripts/ci.sh`'s three-second example smoke mounts every stack page,
so the notebook's `select` fixup runs there for real.

---

## Per-deviation judgement

1. **`?tab_pos` and the new `vtree/tab_position.ml` — sound, mild scope creep.** The plan's
   Task 8 interface block (plan line 2498-2510), its `Consumes` list, and the milestone
   summary at line 3394 all omit `tab_pos`; I cannot check the task message the report
   cites. Judged acceptable on Task 7's `?orientation` precedent: it is defaulted, sexp-
   dropped, pinned in `test_widgets.ml` and in a live dump, documented, and derives the
   same `sexp_of, equal, compare` as its four sibling enum modules. But it adds a **public
   module to `Bonsai_gtk`** that was not in the plan, so Task 15's docs and Task 16's
   spec §7 sweep need to know. Recorded as a carry below.
2. **`set_tab_label … None` for a dropped attr — sound, and better than the brief.** `""`
   would draw a blank tab; `None` restores the state `insert_page` with no label leaves.
   Pinned by `after a tab rename and a tab dropped: Renamed,<none>`. The opposite direction
   (`None → Some`) is also covered, though not by the line that says so: the next patch
   gives `score` a tab for the first time and the following `Live_tree` dump shows
   `(GtkLabel (text Score))` in the header box.
3. **`if from < a then a else a + 1` — sound code, unsound claim.** The formula is right
   (proof above) and hedging against `Reconcile.diff`'s `from > to_` invariant is the right
   instinct; the in-file comment is honest that it is a hedge. What is wrong is the
   report's "Verified against GTK in both directions by the four live moves" — mutation
   testing shows the `from < a` arm is never taken, so no live test distinguishes the
   hedged formula from the brief's naive `a + 1`. See Minor N1.
4. **`page_num_exn` — sound.** Unreachable from any `Node.notebook`-built tree (every
   widget it is handed comes from the patcher's own `!cur`, which mirrors GTK's page list),
   so it is a guard rather than a diagnostic, and `child_op` prefixes the node path onto
   its message, which keeps it §11-shaped. `page_key` says "unreachable" about its own
   guard; this one should too. See Minor N5.
5. **The rule in three constructors and not `flow_box` — sound, verified verbatim.**
6. **A sixth gallery page — sound.** It could not have gone inside Lists or Grid, and it is
   really mounted by the smoke test.
7. **Live tests in `live_lists.ml`, bench moved last — sound.**

**Carry N1 (the bench), taken as a ratio rather than a raised bound — sound, and the
better of the two options the review offered.** It measures the property under test
(cost does not scale with `|selected|`) instead of a wall clock, and contention cancels.
Measured 1.08 here against a bound of 5, with the quadratic shape at ~57. The extra ~0.4 s
mount is worth it. **Carry N2 — done, both points.**

**The judgement call in case 5 — I agree, and so does the implementer.** Raising is right,
and the argument the brief did not make is the decisive one: `~current_page` is required
while `Attr.on_page_changed` is optional, so a clamp would leave a perfectly ordinary
handler-less notebook permanently diverged with no way back, where a list box's "ignore the
keys you cannot find" converges on its own. Worth putting in the ledger in those words.

---

## Critical

None.

---

## Important

### I1. `select`'s stated reason for comparing indices rather than keys is false, and it is "measured" in three places

`src/widgets/w_notebook.ml:167-172` (the `select` docstring):

> The comparison is against `[get_current_page]`, not against the key: a page whose child
> is hidden *cannot* be made current […] so comparing keys would read the write back as
> having landed. Comparing indices reports the truth, at the price of rewriting on every
> frame […]

This is wrong. `W_notebook.current_key` is *derived from* `get_current_page`
(`w_notebook.ml:139-143`: `get_current_page` → `get_nth_page` → `Child_keys.find`), and
keys are unique among a notebook's pages, so `current_key nb = Some current_page` holds
exactly when `get_current_page nb = index`. The two comparisons are the same predicate.

I replaced the index comparison with

```ocaml
if not (Option.equal String.equal (current_key nb) (Some current_page))
then W.Notebook.set_current_page nb index
```

rebuilt, and re-ran the live suite: the golden is **byte-identical**, including
`and it is rewritten on every identical frame: 2`, which is the very line the comment
claims a key comparison would break.

The same false claim appears twice more:

- `test/live/live_lists.ml`, in the hidden-page block: *"A comparison against the `key`
  would read `[false]` here and report success."* It would read `true` and write, like the
  shipped code.
- `task-8-report.md`, "GTK facts established empirically", the `set_current_page on a
  hidden page` row: *"`select` compares indices, not keys, so this reports the truth"* —
  true of the shipped code, but not because of the contrast it draws.

**Concrete consequence.** No runtime failure: the shipped comparison is correct. The damage
is to the next reader. The comparison that really *would* "read the write back as having
landed" is the one against the **previous node's** `current_page` — i.e. an `update`-style
comparison, which is precisely the `reassert = None` / fixup-queue decision documented
twenty lines above. A maintainer who takes the comment at face value will believe
`current_key` caches something, or that `Child_keys` is authoritative over
`get_current_page`; both are wrong, and the second is the kind of belief that produces a
stale-map bug of exactly the sort `page_index_by_key`'s own comment warns against.

**Suggested fix**, three edits, no code change: say that the comparison is against the
widget rather than against the previous node (which is the real content of the paragraph),
and that reading the key back instead of the index would be equivalent but slower —
delete the "would report success" sentence in all three places. If the lead prefers, a
one-line note in `select` that `current_key` is a view of `get_current_page` and not an
independent source of truth would carry the same warning forward.

---

## Minor

### N1. The `move` conditional's second branch is unreachable, and the report says otherwise

`src/widgets/w_notebook.ml:350-356`. Deleting the conditional (`position = a + 1`
unconditionally) leaves the golden unchanged, because `Reconcile.diff` only ever emits
`Move` with `from > to_` (it scans left-to-right and the match is always at an index `≥ i`),
which forces `a = to_-1 < from`. So the four live moves exercise one arm.

Keep the branch — it is correct, it is the right hedge, and the in-file comment is honest
about being one. What should not survive is deviation 3's "Verified against GTK in both
directions by the four live moves" and the mutation table's implication of coverage; the
ledger should say instead that the hedge is currently unreachable and untested, and that the
`from < a` arm becomes live only if `Reconcile.diff` ever emits a forward `Move`. A one-line
addition to the comment ("today `from > to_` always, so the first arm is unreachable; it is
here so that a reconciler change cannot break this silently") would close it.

### N2. `Set_page`'s arm is inserted between `Set_selection`'s explanatory comment and `Set_selection`

`test_lib/bonsai_gtk_test.ml`. The pre-existing comment that ends

> …the action needs no kind check of its own: a node that is neither reports that it has no
> selection handler, naming both spellings.

now sits immediately above the `| Set_page` arm, which *does* do a kind check
(`of_kind_exn … ~expected:"Notebook"`). A reader hits a comment that contradicts the four
lines under it. Move the `Set_page` arm below `Set_selection` — which also matches the
constructor order in `bonsai_gtk_test.mli` and in `Action.t` — or move the comment down
with its arm.

### N3. `examples/gallery.ml`'s new page does not demonstrate what its comment claims

`examples/gallery.ml:261-265`: *"The pages hold state (an entry each) so that the reorder
visibly keeps it."* All three pages' entries are bound to the same Bonsai state (`notes`,
with `Attr.on_changed set_notes` and `~text:notes`), so the text would survive a
destroy-and-rebuild too — it lives in the model, not in the widget. What the reorder
actually preserves that a rebuild would not is widget-local state: the cursor position, the
selection, the scroll offset. Either give each page its own `Bonsai.state` (which also
stops typing on one tab from echoing into the other two, which is currently a slightly
confusing demo) or reword the comment to say "the cursor and selection survive".

### N4. `test/handle/test_gallery.ml` says "every prop" but passes `~show_tabs:true`

The default, so it drops from the sexp and the headless golden pins nothing for it. Pass
`~show_tabs:false` and let `~show_border` be the one that stays at GTK's value, or drop the
"every prop" claim. (`show_tabs:false` *is* pinned live, via the `no-tabs` dump.)

### N5. `page_num_exn` should say it is unreachable

`src/widgets/w_notebook.ml:214-220`. Every widget it is handed comes from the patcher's
`!cur`, which mirrors GTK's page list at every op, so `-1` cannot occur in a tree built by
`Node.notebook`. `page_key` five lines up documents exactly this about its own guard
("Unreachable through `Node.notebook`, which rejects…"); this one reads as if it expects to
fire. Also, the message it builds is prefixed by `child_op` into
`root/0/2: notebook: the preceding page is not a page of this notebook`, which repeats the
noun; dropping the leading `notebook: ` would read better.

### N6. `Live_tree`'s notebook arm prints `(current-page -1)` for an empty notebook, unpinned

`src/live_tree.ml:508-511` prints `current-page` unconditionally as an int, so an empty
notebook dumps `(current-page -1)` — the only place a raw GTK sentinel reaches a dump. The
live suite exercises an empty notebook (`an empty notebook: pages=0 current=(none)`) but
never dumps one, so nothing pins it. Either print `(current-page ())`/`(current-page none)`
for `-1`, matching how the notebook's own `current_key` and the stack's `(visible ())`
spell "nothing", or add a dump to the empty-notebook block.

### N7. Only the first of four reorders is checked against a `Live_tree.dump`

The remaining three assert `page_labels` and `tab_texts`, both of which are indexed *by
page*, so neither can catch a tab order that failed to follow its page. GTK moves both
together (`reorder_child` acts on the page struct), so the risk is low and the first dump
covers the mechanism; noted only because the brief asked for tab order to be asserted via
the dump. One extra `print_s (Live_tree.dump live.widget)` after the "middle page moved to
index 0" case would close it for the `after = None` arm specifically.

### N8. Nothing asserts that `remove`/`forget_pages` actually empties `Child_keys`

There is no test for `forget_rows`, `forget_children` or `forget_pages` anywhere in the
suite, so this is a pre-existing shape rather than a Task 8 regression — but the notebook's
own GC block, which I confirmed is a real regression, tests the opposite direction (entries
*surviving*). If M2 ever grows an entry-count introspection on `Child_keys`, a
"destroy the notebook, count zero" line is one assertion in three containers.

---

## Carries to Task 9 (in addition to the report's five)

1. **I1's comment correction** — three sites, no code change.
2. **N1's ledger correction** — the `move` hedge is unreachable today; do not carry the
   "verified in both directions" claim forward.
3. **`Tab_position` is a new public module in `Bonsai_gtk` that the plan does not list.**
   Task 15's docs and Task 16's spec §7 / §5.1 sweep should account for it, along with the
   `?tab_pos` argument on `Node.notebook`.
4. **Two facts worth recording because they are theorems, not measurements**, and both
   would otherwise be re-derived: `Reconcile.diff` emits every `Move` with `from > to_`,
   and it can never emit `to_ = n-1`, so no container's `move` ever needs
   `reorder_child`'s past-the-end clamp.

---

# Re-review — fix round 1 (`ced908d`)

**Scope:** `git diff 0a4d11d..ced908d` only (7 files, +298/−59), against the findings above.
**Gate re-run by the reviewer:** `nix develop -c ./scripts/ci.sh` → `all green`, exit 0
(`bench … ratio 1.08 (bound 5)`).
**Mutation testing:** four mutations built and run in a throwaway worktree at `ced908d`,
plus one probe experiment. Worktree removed; `git status` clean apart from the
pre-existing untracked `.beads/issues.jsonl`.

## Verdict: Approved.

Every finding was taken, and the two overturned claims were re-derived by the implementer
before being edited rather than accepted on trust — which is the right instinct and is
visible in the report. All three new assertions bite. One new stated reason is wrong; it is
cosmetic and is the only thing outstanding.

## Findings taken — verified

**I1 (Important) — closed, and the replacement text is accurate.** `w_notebook.ml`'s
`select` docstring now says the comparison is against the *widget* rather than against the
previous node (which is the real content of the paragraph), states outright that
indices-vs-keys is a spelling and not a decision, gives the equivalence, and names the
retraction. The implementer's own derivation is right in the corner I did not spell out:
`page_index_by_key` answers `None` on an empty notebook, so `-1` never reaches the `Some`
branch, and the two predicates agree there too. The alternative fix I offered was also
taken — `current_key`'s docstring now says it is `get_current_page` with two lookups on top
and **not an independent source of truth**, which puts the warning where the temptation is.
`live_lists.ml`'s hidden-page comment and the report's "GTK facts" row are corrected, and
both now point at the comparison that really would report a false success (one against the
previous node). No code changed, correctly.

**N1 — resolved better than either option I offered.** The branch is kept, the report and
the in-file comment are corrected, *and* the coverage gap is closed by a new block that
calls `list_ops.move` out of `Registry` with a `~after` sitting after the child. I checked
the call shape is faithful rather than merely plausible: for `Move {from = 0; to_ = 1}` on
`[A;B;C;D]`, `Patcher.patch_list` computes `after_of without 1` = `B`, so the patcher would
call exactly `move ~child:A ~after:(Some B)`, and `Reconcile.apply` gives `B,A,C,D` — which
is what the golden asserts. Mutation: replacing the conditional with an unconditional
`a + 1` changes **exactly the two `forward move:` lines and nothing else in the suite**,
confirming both halves of the report's claim in one experiment. The three reasons given for
rejecting an `assert` are sound, and (b) — three containers should not disagree about whose
invariant `from > to_` is — is the strongest.

**N7 — the gap was closed at the right level.** `tabs_in_dump` walks `Live_tree.dump`'s
sexp for the header `GtkBox` subtree's `GtkLabel` texts, which is a genuinely independent
reading: the golden proves it, since the tabs come out `Score,Notes,Parts` while
`page_labels` reads `SCORE,NOTES,PARTS` off different widgets. Mutation: the off-by-one
`if from < a then a - 1 else a` moves three of the four dump lines (the fourth is the
`~after = None` case, which that mutation cannot perturb) and the forward-move line too.
The judgement call — one derived line per move rather than four 60-line dumps — is right:
the instruction's substance was "assert the tab order via the dump", and it is met at every
case while keeping the golden readable. The scroll-button caveat in the helper's comment is
correct by inspection (`(label ())` is a field, not a `GtkLabel` node, and the buttons hold
`GtkImage`s) though no test calls it on a scrollable notebook; if the header/stack child
order ever flipped, the helper would read the stack's page labels and the golden would fail
loudly rather than silently pass, which is the right failure mode.

**N8 — both directions now asserted, both mutation-verified by me.**

| Mutation | Result |
|---|---|
| drop `Child_keys.remove` from `list_ops.remove` | `the removed page is still remembered: 0 of 1` → `1 of 1` |
| drop `Patcher.destroy`'s `Notebook _ -> forget_pages` arm (folded into the or-chain so it still compiles) | `pages still remembered after teardown: 0 of 2` → `2 of 2` |

Asking through `key_of_page` on a handle taken before the removal is the right shape given
`Child_keys` exposes no size. One robustness note, not a defect: the entries are held only
by the ephemeron, so a major collection landing between the removal and the read would make
the *mutated* run pass too. It cannot make the shipped code pass falsely — it can only blunt
the mutation — and there is almost no allocation in that window, so this is worth knowing
rather than changing. The report's method note (a mutation that produces no golden change
must be confirmed to have compiled first) is a good one and I applied it here.

**N6, N2, N3, N4, N5 — all taken and all correct.** `(current-page ())` matches the stack's
`(visible ())` and `current_key`'s `None`, and the empty-notebook frame now dumps so the
line is pinned. `Set_page` sits below `Set_selection`, matching `Action.t` and the mli, and
its comment names the contrast that the misplacement had made contradictory. The gallery's
three pages get a `String.Map` of their own state, the header comment now claims what the
reorder actually preserves (cursor, selection, focus) and says explicitly that the typed
text is not the demonstration, and the placeholder tells the reader what to do. All five
notebook props in `test_gallery.ml` are now set away from GTK's defaults and every one is
pinned by the sexp. `page_num_exn` documents its unreachability on `page_key`'s pattern and
drops the redundant noun.

## New — Minor

### N9. The stated reason for using four pages in the forward-move test is false

`test/live/live_lists.ml`, the forward-move block's header, and the corresponding paragraph
in `task-8-report.md`:

> Four pages rather than three, because `reorder_child` clamps a position past the end —
> with only three, the wrong index and the right one both land on the same order and the
> test would pass either way.

They do not. I mounted a three-page notebook in the worktree and ran both formulas against
GTK:

```
PROBE 3-page shipped move (a after b): B,A,C
PROBE 3-page restored:                 A,B,C
PROBE 3-page naive a+1=2 by hand:      B,C,A
```

GTK computes `max_pos = g_list_length (children) - 1` over the list that **still contains**
the child, so with three pages `max_pos = 2` and `position = 2` is not clamped. The real
constraint is not the page count at all: it is that **`~after` must not be the last page**.
If `after` is last then `a = n-1`, the correct position is `a` and the naive `a + 1 = n`
clamps back to `n-1`, so the two agree — for any `n`. With `~after` at index 1 of three,
they differ.

No consequence for the test, which is correct and which mutation testing shows is
non-vacuous; four pages is a harmless over-provision. But it is a third stated-reason defect
of exactly the species this round existed to fix, and the ledger would inherit it. Suggested
wording: *"`~after` is deliberately not the last page: `reorder_child` clamps a position past
the end, so a move that lands last cannot tell the right index from an over-large one. Four
pages rather than three only so that there is a page behind the destination as well as in
front of it."*

### N10. `task-8-report.md`'s deviation 6 is now stale

It still justifies the sixth gallery page by "per-page state that visibly survives (each
page holds an entry)", which is the claim N3 corrected in `examples/gallery.ml`. One
sentence, for consistency with the fix round's own note.

## Nothing regressed

`ci.sh` is green end to end on `ced908d`, the live golden matches on a clean rebuild, and
the only lines that moved in `expected_lists.txt` are the eight new assertions plus the
empty-notebook dump. `Registry` and `Widget_impl` were already in `Bonsai_gtk.Private`, so
the new test's imports add no public surface. The `Live_tree` change is confined to the
`GtkNotebook` arm's `-1` case.

## Carries to Task 9 — unchanged from the report's revised list

Its six items subsume mine; N9's wording correction is the only addition, and it belongs in
this task rather than being carried.
