# Task 8 report — Notebook: the first container with a real reorder

**Commit:** `0a4d11d` on `m2`, base `e9e7793`. 33 files, +1902/−75.
**Gate:** `nix develop -c ./scripts/ci.sh` → `all green`, exit 0.
**Stderr during the live suite is now two lines**, not one — see "A note for the ledger"
below.

---

## The stub-safety table the brief asked for, for every getter reached

Read in the generated stub rather than in the GIR, on Task 6's rule. The `_opam` copy the
build actually links is byte-identical to the `.ocgtk-src` one (`md5sum` on both
`ml_notebook_gen.c` and `ml_gobject.c`).

| Call | Returns | Sinks | Where | Called by |
|---|---|---|---|---|
| `gtk_notebook_get_nth_page` | `GtkWidget*` | **yes** | `ml_notebook_gen.c:303-310` | `W_notebook.pages` (every frame) |
| `gtk_notebook_page_num` | `int` | n/a | `:189-195` | `insert`, `move`, `remove` |
| `gtk_notebook_get_n_pages` | `int` | n/a | `:312-318` | `Live_tree` |
| `gtk_notebook_get_current_page` | `int` | n/a | `:345-351` | `select`, `current_key`, `Live_tree` |
| `gtk_notebook_get_tab_label_text` | `const char*` | n/a | `:237-243` | `live_lists.ml` |
| `gtk_notebook_get_show_tabs` / `get_show_border` / `get_scrollable` | `gboolean` | n/a | `:262`, `:270`, `:278` | `Live_tree` |
| `gtk_notebook_get_tab_pos` | enum | n/a | `:229-235` | `Live_tree` |
| `g_value_get_object` (the `switch-page` marshaller's `page`) | `GObject*` | **yes** | `ml_gobject.c:362-391` | the `Payload` spec's `connect` |

Two entries that are *not* in the table, deliberately:

- **`gtk_notebook_get_tab_label`** sinks (`:245-252`) and is **not called** by shipped
  code. Named in the file comment so that a later reader who reaches for it does not have
  to re-check.
- **`gtk_notebook_get_pages`** does **not** sink — correctly, since it is transfer-full
  (it returns a fresh `GListModel`). Nothing here calls it, and a future reader who
  "simplifies" the `get_nth_page` walk into it needs to know that its `GListModel` holds
  `GtkNotebookPage`s rather than pages' children, which is a different object again.

No walk-instead-of-getter workaround was needed here: unlike `GtkListBox`, the notebook
has no transfer-container getter this impl wants. The `get_nth_page` walk is used because
it is the *only* way to reach a notebook's pages — `Widget.get_first_child` gives an
internal `GtkBox` of tabs and an internal `GtkStack` of pages (see "GTK facts").

---

## Per-step summary

**Step 1 (failing tests first).** `test/test_widgets.ml` — four blocks (constructors and
defaults, `equal_props` + defaults dropping, the unkeyed-page rejection at both indices,
`tab_label` riding on the page node). Verified failing: `Unbound value "Node.notebook"`.
Then `test/handle/test_handle.ml` (five blocks) and `test/live/live_lists.ml` (three
blocks) were added against the implementation as it came up.

**Steps 2–6 (implement).** `vtree/tab_position.ml` (new); `Defaults.Notebook`;
`Kind.notebook_props` + the variant, `name`, `same_kind`, `equal_props` arms;
`Attr.{Tab_label, On_page_changed}` through every exhaustive match that names them
(`attr.ml`'s `is_event`, `name` and `equal`; `events.ml`'s `controller_family`;
`placement.ml`'s `reader`; `attr_apply.ml`'s `apply` and `unset`); `Node.notebook`; `src/widgets/w_notebook.ml`;
`Registry`; `Patcher` (`interest`, `enqueue_fixups`, `note_interest`, `destroy`,
`drop_stack_names` — five exhaustive matches, all five flagged by the compiler).

**Step 7 (`Placement`).** `read_by` gains `| Notebook _ -> [ Tab_label ]` and `reader`
gains `| Tab_label -> Some "Notebook"`. The stale "`[Notebook -> [ Tab_label ]]` is the
next one" note in `placement.ml`'s header is now removed rather than left pointing at
itself. `test_placement.ml`'s `containers` list gains the notebook, so the two tables are
checked to be inverses over it.

**Step 8 (`Live_tree`).** A `"GtkNotebook"` arm printing `(pages N)` and `(current-page i)`
unconditionally (they are what the node asked for, like a stack's `visible`) and
`no-tabs` / `no-border` / `scrollable` / `(tab-pos …)` only when they are not GTK's own.
Note the polarity: `show-tabs` and `show-border` default to **true**, so it is the
negatives that appear.

**Step 9 (run, read, promote, gate, commit).** `dune fmt` per directory, `./scripts/ci.sh`
→ `all green`, one commit. Two throwaway probe executables under `test/live/` were used to
establish the GTK facts below and were deleted; `test/live/dune` is back to its committed
list.

---

## GTK facts established empirically

Everything below was measured under `xvfb` on GTK 4.22, not read out of the docs.

| Fact | Consequence |
|---|---|
| Defaults on a fresh `GtkNotebook`: `show-tabs` **true**, `show-border` **true**, `scrollable` false, `tab-pos` `TOP`, `current-page` **−1**, pages 0 | `Defaults.Notebook`, and `Live_tree` prints the negatives |
| **`reorder_child`'s `position` is the page's index in the _resulting_ list**, clamped to `n-1`. `A,B,C,D` + D→1 = `A,D,B,C`; `D,B,A,C` + head→3 = `B,A,C,D`; + index 2→0 = `C,B,A,D`; + head→99 = last | the `move` arithmetic, and the four moves in the live test |
| **GTK emits `switch-page` while the _first_ page is inserted**, naming the page being inserted; later inserts emit nothing | `Child_keys.set` must precede `insert_page`; the `in_patch` guard is what swallows it at mount |
| `switch-page` fires **through `freeze_notify`** — it is a signal, not a `notify::` | `Widget_impl.batch` is *not* what suppresses the mount emission; only the guard is |
| `page_num` of a widget the notebook does not hold is **−1**; `remove_page` with a bad index silently does nothing; `reorder_child` and `set_tab_label_text` on a stranger log a `Gtk-CRITICAL` | `page_num_exn` raises instead, naming which page |
| `insert_page` with a `None` tab label leaves **no label widget at all** (`get_tab_label` → `None`), not a "page N" label | dropping `Attr.tab_label` writes `set_tab_label … None`, which restores exactly that |
| The current page **follows its widget** across an insert before it, a removal before it, and a reorder — GTK emits no `switch-page` for any of those | the fixup's index is re-derived from the key each frame, so none of this needs handling |
| Removing the current page: GTK switches to a neighbour and **does** emit `switch-page`, naming the neighbour (never the departing page) | `Child_keys.remove`-before-`remove_page` is belt-and-braces here too |
| **`set_current_page` on a page whose child is hidden emits `switch-page` and then leaves `get_current_page` where it was** | documented on `Node.notebook`; `select` reads the live widget back rather than comparing against the previous node, so it reports the truth (and rewrites every frame). Indices vs. keys is *not* the distinction — see Fix round 1, I1 |
| A `GtkNotebook`'s widget children are an internal `GtkBox` (tabs) and an internal `GtkStack` (pages), and **the stack's child order does not follow the page order** — a reorder moves the tabs and leaves the stack's children alone | `Live_tree.dump` shows the *tab* order; the live test prints the page order separately from `W_notebook.pages` |

---

## The judgement call in case 5: I agree that raising is right

The brief asked me to say so either way after writing it. Raising, and for the brief's own
reason plus one it did not make:

- The model's state is inconsistent with the tree it rendered *this frame*, and it will be
  inconsistent on every frame after, because nothing about the next render will fix it.
  Clamping would make the notebook show GTK's choice while `~current_page` says otherwise —
  §6.5's divergence, permanently, silently.
- The extra argument: the "clamp and let the model hear about it through
  `on_page_changed`" alternative **does not close the loop for a notebook that has no
  handler**. `~current_page` is required and `Attr.on_page_changed` is optional, so the
  clamp would leave a perfectly ordinary tree permanently diverged with no way back. A
  list box's `~selected` has no equivalent hole, because "ignore the keys that are not
  there" converges on its own.
- It is also the same rule as `Node.stack ~visible_child`, and the one-sentence statement
  the brief asked for only exists because the two behave identically.

The cost is real and is documented: a `~current_page` fed by state that can lag the page
list by a frame (closing a tab, where one effect rewrites the list and another the
selection) must render the two together. That is stated on `Node.notebook` and cross-
referenced from `Node.stack`.

---

## Mutation testing — what actually bites

| Mutation | Result |
|---|---|
| `move`'s index off by one (`if from < a then a - 1 else a`) | **nine golden lines change**, including all four reorder cases, the middle insert, and `add-and-select`'s page list. Note this perturbs the arm the reconciler *does* reach; the other arm is covered separately (Fix round 1, N1) |
| `Child_keys.set` moved *after* `insert_page` | `EXN at root/0: (Invalid_argument "GtkLabel: this notebook page was not made by this library …")` — caught by the frame that inserts the first page into an emptied notebook, which is outside a patch guard |
| the mount taken out of `Scheduler.with_patch_guard` | `handlers fired during the mount: 0` → `1`, which is the brief's proof that the guard is what swallows GTK's `switch-page` |

The reorder assertions were written to be non-vacuous in both directions: `same GObjects
after the reorder: true` alone is satisfied by a patch that moved nothing, and the page
order alone is satisfied by a patch that destroyed and rebuilt every page. Both are
printed, plus `the original pages are now at: 0,2,1` (a position list taken over the
pre-patch widget handles).

---

## Deviations from the brief, with reasons

1. **`?tab_pos` added, with a new `vtree/tab_position.ml`.** The task message named
   `tab_pos` among the props; the brief's `Interfaces` block and `Consumes` list did not
   (nor `set_tab_pos`). Taken from the task message, on Task 7's `?orientation`
   precedent. `Tab_position.t = Top | Bottom | Left | Right`, mapping to GTK's
   `positiontype`. Named for the notebook rather than for the C enum because the notebook
   is its only reader; a second reader would generalise it.

2. **`Attr.tab_label` absent is written back as `set_tab_label nb child None`**, not as an
   empty string. The brief's `Consumes` names only `set_tab_label_text`. `""` would draw a
   blank tab; `None` restores the state GTK is in when `insert_page` was given no label,
   which is what "the attr went away" means. `set_tab_label` is one extra binding call.
   (`w_stack.ml` writes `""` for a dropped `page_title` because `set_title` is not
   nullable — here it is.)

3. **`move`'s index does not assume `from > to_`.** The brief's sketch is
   `index_after parent after = page_num parent w + 1`, which is correct only while
   `Reconcile.diff` emits every `Move` with `from > to_`. `w_list_box.ml` and
   `w_flow_box.ml` both go out of their way *not* to make that assumption (they read the
   predecessor's index after the removal); a notebook cannot do that, because
   `reorder_child` does the removal internally. So the impl asks the question directly:
   `if from < a then a else a + 1`. Same answer today, and the file says why rather than
   depending on an invariant stated elsewhere. **Correction (Fix round 1, N1): the four
   live moves exercise only the `else` arm** — `Reconcile.diff` never emits a forward
   `Move`, so the `from < a` arm is unreachable through the patcher. It is now exercised
   against GTK by a test that calls `list_ops.move` directly.

4. **`page_num_exn` raises where the brief let GTK answer.** `page_num` answers −1 for a
   stranger, and the three methods that take an index disagree about what to do with a bad
   one (`remove_page` no-ops, `reorder_child` logs a critical). One check, named per call
   site — this file's counterpart to `W_list_box.row_of`'s type-name check.

5. **The one-sentence rule is in the three constructors the brief named** (`Node.stack`,
   `Node.list_box`, `Node.notebook`) and not in `Node.flow_box`, which already says "on
   exactly `{!list_box}`'s rules, and every paragraph there applies here". The three
   blocks are byte-identical after `ocamlformat` (checked: `grep -c` → 3, and the diff
   hunks are the same four lines).

6. **A sixth gallery page rather than an addition to an existing one.** The notebook's
   headline feature is the reorder, and showing it needs buttons that change the *page
   list* plus per-page state that visibly survives (each page holds an entry). It did not
   fit inside the Lists or Grid page. `test/handle/test_gallery.ml` gains the constructor
   too, with every prop set, since that file's rule is one appearance per constructor.

7. **The live tests live in `live_lists.ml`**, as the brief said, and the flow box's bench
   block was **moved to the end of the file** so that the notebook blocks sit with the
   other two containers' and the odd-one-out timing test stays last.

---

## Carries taken from `task-7-review.md`

**N1 — taken in its second form (the ratio), not the one-line bound raise.** The reviewer
offered "raise `bound_ms` 2.0 → ~8.0" or "assert the ratio between two selection sizes",
and called the first the cheap one. I took the second, because the property under test is
that cost does not scale with `|selected|` and the ratio measures exactly that while
cancelling machine load, where an 8 ms bound still fails on a machine 4× worse than the
one the reviewer contended. The bench now mounts twice (n=1000 at sel=1 and at sel=200),
times 200 idle frames each, and the golden gets `cost ratio under 5: true`. Measured here:
**1.12–1.14** on an idle machine and under `ci.sh`; the reviewer measured 1.1 fixed and
**57** quadratic, so the bound is an order of magnitude clear of both ends. The stderr line
now carries both numbers and the ratio. Cost: one extra mount (~0.4 s).

**N2 — both points.** `w_flow_box.ml`'s "For the callers that ask about a single key" now
names its actual caller (`test/live/live_lists.ml`), and `w_list_box.ml`'s twin was
reworded the same way, since after Task 7 neither has an in-impl caller. The second point
(the live suite's stderr) is recorded below rather than in a comment.

---

## A note for the ledger

**The live suite has two stderr producers, and the second one's text has changed.** Three
task reports have used the phrase "the one stderr line is `live_driver.ml`'s deliberate
raise". Since Task 7 there are two, and as of this commit the second reads

```
bench: 0.446 ms at sel=1, 0.511 ms at sel=200, ratio 1.14 (bound 5)
```

rather than the old `bench: N ms per idle frame (bound 2)`. Both lines are expected; the
golden compares stdout only.

---

## Test / CI tails

`nix develop -c ./scripts/ci.sh`:

```
== nix: ocgtk pin builds and passes its tests
== format
== build
== generated opam files are committed
== pure + headless tests
== per-package builds, the way opam --with-test runs them
== live tests (xvfb)
bonsai_gtk: exception in frame, stopping the driver: (Invalid_argument
  "root/0/1: a Node.window may only be the root node, not a child of another node")
bench: 0.446 ms at sel=1, 0.511 ms at sel=200, ratio 1.14 (bound 5)
== example smoke
all green
```

The notebook's slice of `test/live/expected_lists.txt` (the six cases the brief named, in
its numbering — 6 first, because it is a claim about the mount):

```
handlers fired during the mount: 0                              (6)
pages: SCORE,PARTS,NOTES | tabs: Score,Parts,Notes | current: score   (1)
same GObjects after the reorder: true                           (2)
the original pages are now at: 0,2,1
pages: SCORE,NOTES,PARTS | tabs: Score,Notes,Parts
after the head moved to the tail: NOTES,PARTS,SCORE
after a middle page moved to index 0: PARTS,NOTES,SCORE
after a rightward move with a page behind it: PARTS,SCORE,NOTES
current survived every reorder: score
after a middle insert: PARTS,SCORE,DRAFT,NOTES | tabs: Parts,Score,Draft,Notes
after the middle page went away: PARTS,SCORE,NOTES
after the user clicked a tab: notes                             (3)
after the declining frame: score
add-and-select: draft (pages PARTS,SCORE,NOTES,DRAFT)           (4)
kind change replaced the page widget: true
kind change kept the tab and the current page: Parts,Score | parts
after a tab rename and a tab dropped: Renamed,<none>
the page change delivered the key: score
asking for a hidden page: parts
and it is rewritten on every identical frame: 2
back to a visible page: parts
the page was removed: PARTS,NOTES                               (5)
the fixup raised: (Invalid_argument
  "root/0: Node.notebook ~current_page:\"score\" names no page (a page's key is its ~key; this notebook has parts, notes)")
GTK picked: notes
after the model moved its selection: notes
an empty notebook: pages=0 current=(none) (no raise)
the first page arrived: notes
handlers fired during teardown: 0
nb driver, after mount: score (Bonsai saw 0)
nb driver, after the user clicked a tab: parts
nb driver, after the frame the click armed: score (Bonsai saw 1)
nb driver, after one more frame: score (Bonsai saw 1)
```

plus the GC-churn block (`nb gc: after 250 frames + full_major, current b`) and the
`Live_tree` dumps.

---

## Carries to Task 9

1. **The notebook's `Child_keys` GC regression is weaker than the other two containers'.**
   Keying on the page's content widget is satisfied *by construction* here (there is no
   wrapper to get wrong), so the block guards against a different mistake — keying on the
   transient value `get_nth_page` hands back. The test's comment says so; a reviewer
   expecting the Task 6/7 shape should read it as intentionally different rather than as a
   copy.

2. **`w_flow_box.ml`'s functor question is now closed in `w_notebook.ml`'s header
   comment**, with the reasons. If a later task disagrees, that is the paragraph to argue
   with rather than re-deriving it.

3. **`Live_tree`'s `GtkNotebook` dump cannot show page order** (the internal `GtkStack`
   holds its children in insertion order, not page order). Any later test whose claim is
   the page order must go through `W_notebook.pages`, as `live_lists.ml` does. Worth
   knowing before Task 15's docs describe what a dump shows.

4. **The hidden-page divergence is real and documented but not diagnosable.** A page
   carrying `Attr.visible false` that is also `~current_page` makes the fixup write on
   every frame forever, with no error. It is the same category as a `~selected` its list
   box's mode cannot hold, and both are "a model to bring into line". If M2 ever grows a
   development-mode warning for repeated no-op controlled writes, these two are its first
   customers.

5. **`Tab_position` has one reader.** If another widget needs `GtkPositionType`
   (`GtkScale`'s value position, `GtkPaned`'s nothing, `GtkPopover`), generalise the
   module rather than adding a second copy.

---

# Task 8 report — Fix round 1

**Commit:** `ced908d` on `m2`, base `0a4d11d`. 7 files, +298/−59.
**Gate:** `nix develop -c ./scripts/ci.sh` → `all green`, exit 0.

Everything in `task-8-review.md` was taken. The two claims the reviewer overturned are both
genuinely wrong, and I checked each myself before editing rather than taking the finding on
trust — the verification is written out under each heading.

---

## I1 (Important, doc-only) — `select`'s stated reason was not the reason

**Verified independently before fixing.** `current_key nb` is
`get_current_page` → `get_nth_page i` → `Child_keys.find`, and sibling keys are unique
(`Reconcile.check_unique_keys`, at mount and at patch). So
`current_key nb = Some current_page` holds exactly when `get_current_page nb = index`, for
every index the `Some` branch can see — including the `-1` case, which cannot reach that
branch because `page_index_by_key` answers `None` on an empty notebook. The two
comparisons are the same predicate; the reviewer's byte-identical golden is what that
predicate identity looks like from outside. The comment I wrote was wrong.

Fixed in the three places the review named, plus the one it offered as an alternative:

1. **`w_notebook.ml`'s `select` docstring** now says the comparison is against the
   **widget** rather than against the previous node — which is the real content of the
   paragraph and is spec §6.5's rule — and states outright that indices-vs-keys is *a
   spelling and not a decision*, with the equivalence spelled out and the retraction
   named ("An earlier version of this comment claimed …; it would not, and substituting
   one for the other leaves the live golden byte-identical"). What the read-back actually
   buys is kept and sharpened: the hidden-page case, which cannot be made to converge at
   all.
2. **`w_notebook.ml`'s `current_key` docstring** gains the note the review offered as an
   alternative: it is `get_current_page` with two lookups on top, **not an independent
   source of truth**, and `Child_keys` is never authoritative over the notebook. That is
   the belief the review identified as one step from a stale-map bug, so it is stated
   where the temptation is rather than only where the consequence is.
3. **`test/live/live_lists.ml`**'s hidden-page comment: the "would report success"
   sentence is gone, replaced by "this line reads 2 either way" and a pointer to the
   comparison that really *would* report success — one against the previous node, i.e. an
   `update`-style comparison, which is what makes this a fixup instead.
4. **This report's "GTK facts" row**, corrected in place with a pointer here.

No code changed. The shipped comparison was and is correct.

---

## N1 — the unreachable `move` arm: branch kept, and now actually exercised

The lead's ruling was "assert, or keep the branch and correct the report; pick one and say
why". **I kept the branch, corrected the report, and closed the coverage gap** rather than
only documenting it.

**Why not an `assert`.** Three reasons, in order of weight. (a) It would turn a reconciler
change into a crash at exactly the point where this arithmetic already handles it
correctly — the branch is not a guess, it is the right answer for a forward move. (b) It
would make the notebook the one container that encodes `Reconcile.diff`'s `from > to_` as
a hard dependency, while `w_list_box.ml` and `w_flow_box.ml` quietly survive a forward
move by reading the predecessor's index *after* their removal. Three containers should not
disagree about whether that invariant is theirs to rely on. (c) `from > to_` is a property
of a module in another library; a widget impl asserting it is a dependency stated in the
wrong direction.

**What replaced the false coverage claim.** A new live block calls
`(Registry.for_kind kind).children`'s `list_ops.move` **directly**, with a `~after` that
sits *after* the page being moved — the shape a forward `Move` would produce and the
reconciler never does. `~after` is deliberately not the last page: `reorder_child` clamps
a position past the end, so a move that lands last cannot tell the right index from an
over-large one. Four pages rather than three only so that there is a page behind the
destination as well as in front of it. (This paragraph originally blamed the page count,
which task-8-review.md N9 showed to be false; corrected in Task 9 along with the comment
in `live_lists.ml` it was copied from.)

```
forward move: before A,B,C,D
forward move: after B,A,C,D
forward move: tabs, from the dump: B,A,C,D
```

Mutation-checked: replacing the conditional with an unconditional `a + 1` changes
**exactly these two lines and nothing else in the suite** — which is the review's finding
(no reconciler-driven move reaches the arm) and the new coverage (the arm is now checked
against GTK), in one experiment.

The in-file comment now says the arm is unreachable through the reconciler, why the
deletion is invisible in the golden, why an `assert` was rejected, and that the live test
reaches it directly. Deviation 3 and the mutation table in the report above are corrected
in place.

---

## N7 (required) — tab order from the dump, at all four reorders

The gap was real and sharper than "only the first one has a dump": `page_labels` and
`tab_texts` are **both** indexed by page (`get_nth_page` then `get_tab_label_text page`),
so the two would agree with each other on a notebook whose header was in a completely
different order. Neither is evidence about the header.

New helper `tabs_in_dump`, which walks `Live_tree.dump`'s sexp, takes the notebook's first
child (the header `GtkBox`) and collects its `GtkLabel` texts in order. That is the only
independent answer available, and it is the reading the brief asked for. Printed after all
four moves:

```
tabs, from the dump: Score,Notes,Parts
  tabs, from the dump: Notes,Parts,Score
  tabs, from the dump: Parts,Notes,Score      <- the move to index 0 (~after = None)
  tabs, from the dump: Parts,Score,Notes
```

**Why one line rather than four full dumps** (a deliberate departure from the literal
instruction, and the one judgement call in this round): four `Live_tree.dump`s of a
notebook are ~60 lines of golden, and a golden nobody reads is not a test. The full dump
is kept once, after the first reorder, for the shape; the four one-liners are what pin the
order, and they are derived from the same `Live_tree.dump` call, so the instruction's
substance — *assert the tab order via the dump* — is met at every case. The helper's
comment explains why the header box's other children (the scroll `GtkButton`s, which hold
`GtkImage`s) cannot contaminate the reading.

---

## N8 (required) — `Child_keys` is now asserted to be emptied, in both paths

The review is right that this is a pre-existing shape rather than a Task 8 regression, and
right that the GC block tests the opposite direction. Rather than wait for an entry-count
introspection on `Child_keys`, the question is asked with what is already public:
`W_notebook.key_of_page` on a widget handle taken **before** the removal.

```
the removed page is still remembered: 0 of 1        (list_ops.remove)
pages still remembered after teardown: 0 of 2       (Patcher.destroy's forget_pages)
```

Both bite, mutation-checked:

| Mutation | Result |
|---|---|
| drop `Child_keys.remove` from `list_ops.remove` | `the removed page is still remembered: 1 of 1` |
| drop `Patcher.destroy`'s `Notebook _ -> forget_pages` arm | `pages still remembered after teardown: 2 of 2` |

(The second mutation had to be redone: my first attempt put the arm in
`interest_of_kind`'s chain instead of `destroy`'s, the build failed, and the grep I was
filtering with hid the compiler errors as "no diff". Worth recording as a method note —
a mutation that produces *no* golden change should be confirmed to have compiled before it
is read as "the assertion is vacuous".)

The same two lines are one assertion each in `w_list_box` and `w_flow_box`; carried to
Task 9 below.

---

## N6 (required) — the empty notebook's `current-page`

Both halves taken. `Live_tree` now prints `(current-page ())` where `get_current_page`
answers `-1`, matching the stack's `(visible ())` and `W_notebook.current_key`'s `None` —
a dump is the wrong place to make a reader know that `-1` is not an index. And the
empty-notebook frame now dumps, so the line is pinned:

```
an empty notebook: pages=0 current=(none) (no raise)
(GtkNotebook (pages 0) (current-page ()) (css (frame)) …
```

---

## N2–N5, all taken (each under ten lines)

**N2.** The `Set_page` arm moved below `Set_selection`, so the shared-selection comment
sits with its own arm again. Its own comment now names the contrast explicitly ("unlike
`Set_selection` directly above, the *kind* is checked"), which is the fact the misplacement
made contradictory. This also matches the constructor order in `Action.t` and in the mli,
both of which already had `Set_page` last.

**N3.** The gallery's three pages get a state each — a `String.Map` keyed by page key —
so typing on one tab no longer echoes into the other two. The header comment is corrected
to claim what the reorder actually preserves: *widget-local* state (cursor position, text
selection, focus), with an explicit note that the typed text would survive a rebuild too
because it lives in the model, so it is not the demonstration. The entry's placeholder now
says "type here, put the cursor mid-word, then move the tab", which is the interaction that
shows it.

**N4.** `~show_tabs:false` in `test/handle/test_gallery.ml`, so all five props are set away
from GTK's defaults and every one of them is pinned by the sexp. The comment says so
rather than claiming "every prop" and leaving one dropping silently.

**N5.** `page_num_exn` now documents that it is unreachable in a tree `Node.notebook`
built — every widget it sees comes from `Patcher.patch_list`'s `!cur`, which mirrors GTK's
page list after every op — on `page_key`'s pattern, and says why it is kept anyway (GTK
answers `-1` rather than raising, and the three index-taking methods disagree about what to
do with a bad one, so the failure mode without it is a patch that quietly did not happen).
The leading `notebook: ` is dropped from the message, since `child_op` already prefixes the
node path: `root/0/2: the preceding page is not a page of this notebook`.

---

## Gate

```
== nix: ocgtk pin builds and passes its tests
== format
== build
== generated opam files are committed
== pure + headless tests
== per-package builds, the way opam --with-test runs them
== live tests (xvfb)
bonsai_gtk: exception in frame, stopping the driver: (Invalid_argument
  "root/0/1: a Node.window may only be the root node, not a child of another node")
bench: 0.370 ms at sel=1, 0.410 ms at sel=200, ratio 1.11 (bound 5)
== example smoke
all green
```

---

## Carries to Task 9 (revised — supersedes the five above where they overlap)

1. **`still_remembered` is one line in each of the other two containers.** The pattern
   (`key_of_row` / `key_of_child` on a handle taken before the removal) needs no new
   `Child_keys` API, and neither `w_list_box` nor `w_flow_box` has any test that their
   `remove` / `forget_*` actually forget. Two assertions each.
2. **`tabs_in_dump` is a notebook-shaped helper of a general kind.** Any container that
   holds widgets on a child's behalf (a stack's switcher buttons, a list box's
   placeholder) has the same "the dump is the only independent reading" problem.
3. **`Tab_position` is a new public module in `Bonsai_gtk`** that the plan does not list
   (the review's carry 3). Task 15's docs and Task 16's spec §7 / §5.1 sweep should
   account for it and for `?tab_pos`.
4. **Two theorems worth recording rather than re-deriving** (the review's carry 4):
   `Reconcile.diff` emits every `Move` with `from > to_`, and it can never emit
   `to_ = n-1` — so no container's `move` ever reaches `reorder_child`'s past-the-end
   clamp. Both are now written into `w_notebook.ml`'s `move` comment; the first is also
   why that file's forward arm needs its own test.
5. **`Live_tree`'s notebook dump still cannot show page order** (unchanged from the first
   report): the internal `GtkStack` holds its children in insertion order. Any later
   page-order claim goes through `W_notebook.pages`; any later *tab*-order claim goes
   through `tabs_in_dump`.
6. **The hidden-page divergence** and **the notebook's GC block being weaker by
   construction** carry forward unchanged from the first report's items 1 and 4.
