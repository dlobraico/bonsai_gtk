# Task 11 report — Calendar and EditableLabel

**Commit:** `179e70a` on `m2`, base `b863bb2`. One commit; no push, no merge, no `bd`.

**Gate:** `nix develop -c ./scripts/ci.sh` → `all green`, exit 0, on a clean tree (re-run
after the final formatting pass and again after the commit).

---

## Headline: the plan's write order for the calendar is wrong, and the live suite says so

The brief's `write_date` writes year, then month, then day, on the reasoning that "month
before day means the day is validated against the right month's length". That reasoning
assumes GTK **clamps**. It does not: each of `set_year` / `set_month` / `set_day` rebuilds
the whole date with `g_date_time_new_local` and, when the result is not a real day, trips
`g_return_if_fail (date != NULL)` — a critical on stderr and **no write at all**.

So the naive order silently strands the calendar on the old month for any date whose
day-of-month does not exist in it:

```
from 2026-12-31 to 2026-02-15, written year, month, day:
  set_year 2026   ok (no change)
  set_month 1     REFUSED -- 31 February is not a day
  set_day 15      ok
  -> 2026-12-15, which is neither date
```

`test/live/live_text.ml` runs this as a matrix against a raw `GtkCalendar`. Measured:

| from | want | year,month,day | day-1-first |
|---|---|---|---|
| 2026-12-31 | 2026-02-15 | **2026-12-15 WRONG** | 2026-02-15 ok |
| 2024-02-29 | 2025-02-28 | **2024-02-28 WRONG** | 2025-02-28 ok |
| 2026-01-31 | 2026-04-30 | **2026-01-30 WRONG** | 2026-04-30 ok |
| 2026-01-01 | 2026-01-01 | 2026-01-01 ok | 2026-01-01 ok |
| 2023-03-31 | 2024-02-29 | **2024-03-29 WRONG** | 2024-02-29 ok |

Four of five. The fifth is in the matrix deliberately — it is the transition the naive
order gets right (nothing moves), so a matrix of failures alone would prove nothing about
the order that works.

**The shipped order is `set_day 1`, then year, then month, then the real day.** Day 1
exists in every month of every year, so no intermediate state is invalid and every date
inside GTK's year range lands. This is a **deviation from the brief's code block**, taken
with the measurement above; it is recorded in `w_calendar.ml`'s header, in
`node.mli`'s `val calendar` doc, and in the golden.

The matrix also puts four `Gtk-CRITICAL`s on stderr during the live run. They are the naive
column being refused — the point of the block, not a fault in it — and an `eprintf` says so
immediately before them so a CI reader is not misled.

---

## GTK facts measured (not read from docs)

Everything below was measured in a throwaway probe under `xvfb-run` at `b863bb2`, and every
claim is now pinned by a golden line.

### `GtkCalendar`

| fact | measurement |
|---|---|
| `day-selected` fires **only when the day-of-month changes**, synchronously | `set_year 2020` +0, `set_month 5` +0, `set_day 11` +1, `set_day 11` again +0 |
| Each setter emits its own `notify::<prop>` **twice** per changed component | `notify (day day)`, `notify (month month)`, `notify (year year)` |
| `freeze_notify` does **not** suppress `day-selected` (it is a signal, not a notification) | `+1` before the thaw and `+1` after; `Widget_impl.batch` here is about `notify::` round trips only |
| A setter whose result is not a real day writes **nothing** and logs a critical | `set_month 1` with day 31, `set_year 2025` on 2024-02-29 |
| Out-of-range `day` / `month` / `year` are criticals + no write | `day >= 1 && day <= 31`, `month 0..11`, `year 1..9999` |
| `mark_day 0` and `mark_day 40` are **silent** no-ops — no critical | `get_day_is_marked` false, nothing on stderr |
| Marks are per day-of-month and **survive a month change** | day 31 marked while June shows is still marked in January |
| An insensitive calendar still takes writes | `set_day 7` lands |
| GTK's defaults | `show_day_names=true show_heading=true show_week_numbers=false` |
| `Core.Date` vs GTK | `Date.create_exn` admits year 0 and rejects 10000; GTK admits 1-9999 — they differ in exactly one place |
| The shipped write emits 1-2 `day-selected` per date change | golden: "a programmatic date change: GTK emitted 2, reached Bonsai 0" |

### `GtkEditableLabel`

| fact | measurement |
|---|---|
| `changed` fires **per keystroke** while editing | one `insert_text` of one character → 1 `changed` |
| `set_text` emits `changed` **twice** (delete + insert) | golden: "GTK emitted 2 changed" |
| `stop_editing true` emits **0** `changed` and 1 `notify::editing` | the text was already there |
| `stop_editing false` emits **2** `changed` undoing the edit, and reverts the text | golden: raw widget, `"Xbefore"` → `"before"` |
| `start_editing` / `stop_editing` both emit `notify::editing` **synchronously** | counted before any drain |
| `start_editing` on an already-editing label, and `stop_editing` when not editing, are silent no-ops | notify delta 0 / 1 |
| `start_editing` selects the text (position moves to the end) on a realized widget | position 5 on `"hello"` — the ordering hazard is real |
| `set_text` resets the position to 0 | why `W_entry.set_text_if_needed`'s save/restore is needed here too |
| **There is no `editing` value the widget refuses** | it enters editing mode while insensitive, hidden, unrealized, and with `GtkEditable`'s `editable = false` — all measured |
| A text with an embedded NUL is stored **up to the NUL**, silently | `"aa\0bb"` → `"aa"` |
| **Invalid UTF-8 is stored and read back unchanged** | `"caf\xe9 latte"` round-trips — unlike a `GtkTextBuffer`, which empties itself |

The brief's guess for the unholdable EditableLabel value ("an `editing:true` on an
insensitive label?") **does not exist**. The real one is `text` with a NUL. Both answers are
in the golden and in `node.mli`.

---

## Unholdable-value rules (the refuse–record–report pattern)

Both widgets follow `w_text_view.ml`'s shape: **refused before the write** (so the widget is
left exactly as it was), memoised against the exact value, reported once through
`Patcher.ctx.report` with the node's path from `enqueue_fixups`, and written on the frame
the model offers something holdable.

| widget | unholdable | why pre-write rather than read-back | same-frame rule |
|---|---|---|---|
| `Calendar` | `~date` in year < 1 (GTK asserts 1-9999; `Core.Date` admits 0) | the write is four calls — letting it through would land `set_day 1` and fail the other three, leaving a date **neither** the model nor the user asked for | golden: "year 1, the first GTK holds: showing 0001-01-01 (reports ())" — written on that frame |
| `EditableLabel` | `~text` containing NUL | `gtk_editable_set_text` truncates silently; a post-write read-back would work but the text view's pre-write check is the established shape and costs the same | golden: "and a text GTK does take: text=…" with no report |

Both memos are cleared by every write that lands. Neither is cleared by anything else,
because unlike the drop-down's items nothing else changes GTK's answer: `unholdable` /
`unwritable` are pure.

**Rejected at the constructor instead** (permanently invalid, and a typo in the call rather
than a value carrying model state — `Node.level_bar`'s rule):
`~marked_days` holding a day outside 1-31. GTK's own answer is a *silent* no-op, so a bad
day would simply never appear with nothing anywhere saying why. A day out of range for the
month *showing* is legal and stays marked.

**Deliberately not rejected at the constructor:** a year-0 `~date`. It is a value carrying
model state in the same position an unstorable `~text` is on a text view, and
`node.mli`'s "what a constructor's `Invalid_argument` costs" section says raising there ends
the application rather than reporting anything. `test_widgets.ml` pins that decision
explicitly.

---

## `in_patch` and programmatic writes: nothing deferred

Both widgets' writes emit **synchronously** and inside the patch, so the reentrancy guard
drops all of it and nothing is deferred:

- calendar: `a programmatic date change: GTK emitted 2, reached Bonsai 0`, and
  `the same write outside a patch: reached Bonsai 1`;
- editable label: `a programmatic write of both props: GTK emitted 2 changed and 1
  notify::editing, reached Bonsai 0`, and `the same writes outside a patch: reached Bonsai 3`.

The "outside a patch" halves are what make the "reached Bonsai 0" lines non-vacuous.

---

## Controlled props: O(1) idle frames, no per-frame rewrite

| prop | idle-frame comparison | cost |
|---|---|---|
| `Calendar ~date` | `Date.equal (read_date c) p.date` | three int getters + `Date.create_exn`; `Date.t` is an immediate, so **no allocation**. No cache is needed and none is added. |
| `EditableLabel ~text` | `W_entry.needs_text` against `W.Editable.get_text` | one short-string copy per frame — exactly what `w_entry.ml` already pays for every entry in the tree. `gtk_editable_get_text` is transfer-none and does **not** leak, which is why the text view's cache has no counterpart here. This is O(len) rather than O(1); the property that matters — **no write** — holds. |
| `EditableLabel ~editing` | one `get_editing` + `Bool.equal` | O(1). |

Pinned: "and a patch that changes nothing writes nothing: GTK emitted 0", "five idle frames
later: GTK emitted 0 in total", "a no-op patch and five idle frames: 0 changed, 0
notify::editing", and "five idle frames parked on it (reports ())" for both refusals.

**Write order inside `reassert` for the editable label: text first, then editing.** Entering
edit mode selects the whole text; a text write after `start_editing` collapses that
selection. Golden: "both props at once: … position after it: 9".

---

## Stub-safety table

Every generated stub this task calls, checked in `.ocgtk-src/ocgtk/src/gtk/generated/`.

| call | C transfer | stub does | verdict |
|---|---|---|---|
| `gtk_calendar_new` | transfer none, **floating** (`GInitiallyUnowned`) | `g_object_ref_sink` | **correct** — sinks the float; the wrapper's unref balances |
| `gtk_editable_label_new` | transfer none, **floating** | `g_object_ref_sink` | **correct**, same reason |
| `Calendar.{set,get}_{year,month,day}` | ints | `Int_val` / `Val_int` | no object, nothing to leak |
| `Calendar.{set,get}_show_{day_names,heading,week_numbers}` | bools | `Bool_val` / `Val_bool` | ditto |
| `Calendar.{mark_day,unmark_day,clear_marks,get_day_is_marked}` | ints / bool | ditto | ditto |
| `Calendar.on_day_selected` | signal | generated `on_*` helper | ditto |
| `Editable_label.{start,stop}_editing`, `get_editing` | unit / bool | ditto | ditto |
| `Editable.from_gobject` | checked interface cast | `g_type_is_a` then `g_object_ref` before wrapping | **correct** — the ref pairs with the wrapper's unconditional unref. Called once per reassert, so it is on the frame path; pinned by a GC-churn regression (500 wrappers + `Gc.full_major`, then 5 000 real idle frames: ref count flat at 3, text readable) |
| `Editable.{set,get}_text`, `{set,get}_position`, `insert_text`, `on_changed` | `const char*` in/out | `caml_copy_string` of a transfer-none return | **correct**, and no leak — unlike `gtk_text_buffer_get_text`, which never `g_free`s |
| `Gobject.Signal.connect_simple "notify::editing"` | generic marshaller | existing `Signals.notify` | unchanged |

**No new binding defects found.** Neither widget has a `get_*` returning an object, so
neither can reach the `get_selected_rows` shape that cost Task 6 a segfault; and neither
constructor is the `String_list.new_` shape (a `ref_sink` on a non-floating plain `GObject`)
that Task 10 recorded — both are `GtkWidget`s, so the sink is exactly right. Nothing new for
the fork list.

---

## Per-step summary

**Step 1 — failing tests first.** Written before any impl existed, in this order:
`test/test_widgets.ml` (the December case from the brief, plus constructors, defaults, the
`marked_days` rejection, the accepted year-0 node, and `equal_props`); `test/test_events.ml`
and `test/live/live_events.ml` (`all_kinds` rows — the `Kind.Variants.descriptions` count
assertion fired first, which is what it is for); `test/handle/test_handle.ml` (the
weekend-declining picker, the editable label's two props, and the `Events` negatives both
directions); `test/live/live_text.ml` (the five cases, plus the raw write-order matrix, the
`Driver.frame` round trip and the GC-churn block).

**Steps 2–6 — implement, run, promote, gate.**

- `vtree/attr.ml(i)`: `On_day_selected of Date.t Handler.t`, `On_editing_changed of bool
  Handler.t`, both placed after `On_selected_changed` and before the controller attrs so no
  existing `Attrs.diff` output reorders. `vtree/placement.ml`'s exhaustive `None` list
  updated (and `test_placement.ml`'s count 40 → 42).
- `vtree/kind.ml(i)`, `defaults.ml`, `node.ml(i)`: `calendar_props` (`date`,
  three `show_*`, `marked_days`) and `editable_label_props` (`text`, `editing`). Defaults
  read off fresh widgets, not out of the docs.
- `vtree/events.ml`: `Calendar -> [On_day_selected]`,
  `Editable_label -> [On_changed; On_editing_changed]`. The editable label's `On_changed` is
  the *entry's* name deliberately: it is literally the same `GtkEditable` interface signal,
  so a line copied from an entry works. `GtkCalendar`'s other four signals
  (`next-month`/`prev-month`/`next-year`/`prev-year`) are not exposed and the table says why.
- `src/widgets/w_calendar.ml`, `w_editable_label.ml`; `registry.ml`; `patcher.ml` gains
  `Calendar` and `Editable_label` interest arms (both carrying nothing — they exist only to
  turn a refusal into a report with a path).
- `src/live_tree.ml`: `GtkCalendar` prints `date` **through `W_calendar.read_date`** plus the
  marks read back per day and the three flags; `GtkEditableLabel` prints the text through
  `GtkEditable` and `editing` when on. The children carve-out that was drop-down-only is now
  a three-name list: a calendar's internals are 49 day labels whose text is the month showing
  (a golden would churn on every date change, which is the one thing a calendar test always
  does) and an editable label's are a whole `GtkPopoverMenu`.
- `test_lib`: `Select_day of string * Date.t` and `Set_editing of string * bool`, both
  kind-checked like the activate actions, neither consulting the node's own props.
- `examples/gallery.ml`: a seventh page, **Dates** — a calendar whose model declines
  weekends (click a Saturday and watch it snap back), mark/unmark/clear buttons driving the
  uncontrolled `marked_days`, and an editable label as the page heading whose model
  title-cases what you type, with a check button driving `editing` from the model side.

**Step 7 — commit.** `179e70a`. Message rewritten from the brief's, because the brief's body
asserts the write order the matrix disproves.

---

## The review focus, answered

- **A December date round-trips.** `test_widgets.ml` prints December from the node;
  `live_text.ml` dumps a January calendar and a December one, prints the raw properties
  beside the December dump (`year=2026 month=11 day=31`), and then round-trips **every month
  of 2026** through the widget comparing the read-back against the `Date.t` the node carried:
  `every month of 2026 round-tripped, mismatches: ()`. Plus the leap day and the day after a
  leap year ends.
- **Would a test catch a conversion wrong in both places?** Yes, and this is the reason the
  round-trip exists. `Live_tree` prints through `read_date` on purpose (a second conversion
  in the dump would print a consistent lie), so the dump alone could not catch it — but the
  round-trip's *input* is the node's `Date.t` and its output is the three properties read
  back, so a `+1`/`-1` pair that cancels in the dump does not cancel there. The raw-property
  line is the third leg.
- **Leaving edit mode commits.** `the model then left editing mode: text="Set Two!!"` and
  `the text the user typed survived leaving edit mode: true`, with the alternative measured
  on a raw widget beside it (`stop_editing false: text="before" (2 changed emitted undoing
  the edit)`), so the golden holds both the choice and what the other choice costs.
- **`reassert` writes text before editing.** By construction in `w_editable_label.ml`, and
  visible in "both props at once … position after it: 9".

---

## Deviations, with reasons

1. **The calendar's write order** — day-1-first rather than the brief's year/month/day. The
   brief's order is wrong; measured, pinned, documented in three places. (Above.)
2. **`Node.calendar` rejects `~marked_days` outside 1-31**, which the brief did not ask for.
   GTK's answer is a silent no-op, so nothing else would ever say why a mark did not appear,
   and no later date could make the day valid — `node.mli`'s own test for raising.
3. **`Node.calendar` does *not* reject a year-0 `~date`.** The brief hypothesised "a date GTK
   clamps"; GTK does not clamp, it refuses the whole write. Treated as `w_text_view.ml`
   treats unstorable text rather than as `Node.level_bar` treats inverted bounds, because it
   is a value carrying model state.
4. **`w_editable_label.ml` reuses `W_entry.changed` as well as `set_text_if_needed`.** The
   brief asked only for the latter. The spec connects to the `GtkEditable` the widget *is*
   and its `fire` reads `W.Editable.get_text` — nothing in it mentions an entry, and copying
   it would be a second place for the connection-names-the-Editable rule to be got wrong.
   `w_entry.ml`'s header now says "four kinds, not three" and names the second caller, as the
   brief asked.
5. **`create` passes `""` to `gtk_editable_label_new` and writes the text through
   `reassert`.** Passing `p.text` to the constructor would leave an unstorable text
   half-applied at mount and refused at patch; this way the one controlled prop has exactly
   one implementation including its refusal.
6. **`w_editable_label.ml`'s `update` does nothing** (both props are controlled). The `match`
   is kept rather than collapsed to `fun _ ~old:_ _ -> ()` so that a prop added to this kind
   is a compile error here rather than a silently ignored field.
7. **`test_gallery.ml` gained four constructors, not two.** `Node.drop_down` and
   `Node.level_bar` were never added by Task 10 although that file's header claims every M1
   and M2 constructor appears — so a change to either's defaults showed up in no snapshot at
   all. Fixed while adding mine; called out here because it is outside Task 11's file list.
8. **`Bonsai_gtk.Private` gained `W_calendar`**, so `live_text.ml` can print dates through
   the same `read_date` the impl uses rather than writing a second conversion in the test.

---

## Carries taken from `task-10-review.md` (re-review)

- **R1 — taken.** `w_drop_down.ml`'s `update` comment said the model rebuild "has just reset
  the widget's selection to item 0", which the splice made false and which is the headline
  result of that round. Rewritten to say what is actually load-bearing about the
  `update`-then-`reassert` ordering: the cases where the new contents *force* the selection
  to move (the selected item deleted, the list emptied, the list grown past a stale index).
  The `:333` comment's "a rebuild" / "the old model" wording is now "an items change" / "the
  old contents", matching the parallel comments that round already updated.
- **R2 — taken, both halves.** `bonsai_gtk_test.mli` no longer claims `Node.drop_down` has
  range-checked the props the handle sees (it deliberately has not since I4). The honest
  reason — headless there is no list model to ask, and GTK is what decides — replaces it. And
  `test_handle.ml`'s `-1` asymmetry block gained the second instance the review asked for: a
  permanently out-of-range `~selected:9` that produces **no headless signal at all**, next to
  the `-1` case.
- **N1 — taken.** `live_tree.ml`'s `GtkStringObject` lookup is now a module-level `lazy`,
  written the same way `w_drop_down.ml` writes its `GtkStringList` twin.
- **N2 — taken.** The stale-index live block gained `~items:[] ~selected:0`, which reaches the
  `refusal` branch no other case did: `"~selected:0 names no item: the list holds 0. … so
  nothing is selected"`.
- **N3 — taken (this report).** The review is right that the level bar's `mode` and
  `inverted` do not enter `w_level_bar.ml`'s value-write condition, so the ruling's literal
  `bar ~min:0. ~max:5. ~value:4.` **would** have caught the mutation. The stated reason in
  task-10-report.md ("would not have isolated the value") does not hold and is withdrawn. The
  shipped case remains the better one, on the merits the reviewer named: nothing else moves
  at all, and the discrete blocks make the change visible in the dump.

---

## Carries to Task 12

1. **`Node.editable_label` has no `~editable` / `~width_chars` / `~xalign`.** All three exist
   on `GtkEditable` and `w_entry.ml` already writes them; a setlist rename field will want at
   least `~width_chars`. Left out because the brief's interface names two props and widening
   it unasked is the wrong call — but it is two lines per prop and the impl already holds the
   `GtkEditable`.
2. **`Node.calendar` cannot be told to show a month without selecting a day.** GTK has no
   such API either (the date *is* the selection), so an application that wants a
   month-browser rather than a picker has to move `~date` as the user walks. Worth a sentence
   in the README's Limitations (Task 15) beside the others.
3. **The editable label's `~text` is compared O(len) per idle frame**, like every entry's.
   Fine for a label; if a profile ever shows entries dominating an idle frame, the fix is
   `w_text_view.ml`'s cache generalised over `GtkEditable`, in one place for all four kinds.
4. **`test_gallery.ml`'s "every constructor" claim is enforced by nothing.** Task 10's two
   were missing and only a manual read found it. A count assertion against
   `Kind.Variants.descriptions` — the trick `test_events.ml` already uses — would make it a
   failure rather than a discovery.
5. **The calendar's four unexposed signals** (`next-month`, `prev-month`, `next-year`,
   `prev-year`) are a decision recorded in `vtree/events.ml` and nowhere a user reads. If any
   application ever wants "the user is browsing" separately from "the date changed", that is
   the hook, and it needs no new machinery.

---

## Test / CI tails

```
== live tests (xvfb)
...
live_text: the four Gtk-CRITICALs that follow are expected -- they are the naive write
order below being refused by GTK, which is what this block measures
(process:27016): Gtk-CRITICAL **: gtk_calendar_set_month: assertion 'date != NULL' failed
(process:27016): Gtk-CRITICAL **: gtk_calendar_set_year: assertion 'date != NULL' failed
(process:27016): Gtk-CRITICAL **: gtk_calendar_set_month: assertion 'date != NULL' failed
(process:27016): Gtk-CRITICAL **: gtk_calendar_set_month: assertion 'date != NULL' failed
== example smoke
all green
```

Selected golden lines (`test/live/expected_text.txt`):

```
write order (GTK's raw zero-based month, +1 for printing):
  2026-12-31 -> 2026-02-15 : year,month,day gives 2026-12-15 (WRONG); day-1-first gives 2026-02-15 (ok)
  ...
  transitions the naive order gets wrong: 4 of 5
per-call emissions:
  set_year 2020            -> 2020-01-10, day-selected +0
  set_month 5              -> 2020-06-10, day-selected +0
  set_day 11               -> 2020-06-11, day-selected +1
  inside freeze_notify: day-selected +1 before the thaw, +1 after
  mark_day 40 and mark_day 0 are silent no-ops: false false
raw properties for 2026-12-31: year=2026 month=11 day=31
every month of 2026 round-tripped, mismatches: ()
the user picked the 29th: 2026-08-29
the model rendered the 28th again: 2026-08-28 (reports ())
asked for year 0: showing 2026-04-15 (reports ((cal/0"~date:0000-01-01 is in year 0, ...")))
five idle frames parked on it: showing 2026-04-15 (reports ())
year 1, the first GTK holds: showing 0001-01-01 (reports ())
a programmatic date change: GTK emitted 2, reached Bonsai 0
the same write outside a patch: reached Bonsai 1
two single-character insertions emitted 2 changed
the text the user typed survived leaving edit mode: true
raw widget, stop_editing false: text="before" (2 changed emitted undoing the edit)
raw widget, stop_editing true: text="Xbefore" (0 changed emitted committing it)
a no-op patch and five idle frames: 0 changed, 0 notify::editing
asked for a text with a NUL: text="Programmatic" (reports ((lbl/0"text contains a NUL byte, ...")))
invalid UTF-8 is stored rather than refused: true (reports ())
driver, user picked the 29th (a Saturday), before the frame: 2026-08-29
driver, after the frame the refusal armed: 2026-08-31 (handler saw (2026-08-31 2026-08-29))
driver, one more frame: 2026-08-31 (handler saw 0 more)
after 500 from_gobject wrappers and a full major: text="Rehearsal", references 3 -> 3
after 5000 idle frames: text="Rehearsal", references 3
an index into an empty list: selected=-1 (reports ((none/0"~selected:0 names no item: the list holds 0. ... so nothing is selected ...")))
```

`test/live/expected_events.txt`: `kinds checked: 35` → `37`, still `agreed` and `no impl
declares a controller attr`.

---

# Fix round 1 — `2f8eeb9` (base `179e70a`)

**Gate:** `nix develop -c ./scripts/ci.sh` → `all green`, exit 0, clean tree.

## C1 — a heading walk emits no `day-selected`, and `reassert` reverted it

**Commit:** `2f8eeb9`. **Accepted without argument.** The reviewer is right, the defect is
user-visible, and the evidence was already in my own golden (`set_month 5 -> 2020-06-10,
day-selected +0`) — I wrote that line and then wrote the opposite premise in four places.

**What I measured before fixing.** Emitting `clicked` on the calendar's own heading buttons
(the path a real click takes — `GtkCalendar` connects `calendar_set_month_prev`/`_next` to
that signal), logging the date *from inside each callback*:

```
heading walks (buttons found: 4):
  prev-month              2026-07-15 -> 2026-06-15 | notify::month@2026-06-15
  next-month              2026-06-15 -> 2026-07-15 | notify::month@2026-07-15
  prev-year               2026-07-15 -> 2025-07-15 | notify::year@2025-07-15
  next-year               2025-07-15 -> 2026-07-15 | notify::year@2026-07-15
  next-month off Jan 31   2026-01-31 -> 2026-02-28 | notify::day@2026-02-28 notify::month@2026-02-28
```

Two facts, both new and both load-bearing:

1. **The heading path never emits `day-selected` — not even when it moves the day.** The
   Jan 31 → February walk changes the day-of-month to 28 and still emits only
   `notify::day` + `notify::month`. So the premise was not merely optimistic; it was wrong
   in the one case it was least wrong about.
2. **Every emission in a burst already reads the final date.** `calendar_set_date` updates
   its date before notifying anything, so the `@`-suffixed dates above are all post-walk.
   That is what makes deduping against the last date delivered *exact* rather than a
   heuristic — a dedup that could fire with a stale date and then swallow the correct one
   would be worse than no dedup.

**The fix, per the ruling — the first shape, one attr, one slot.**

`Signals.read_back.connect` now returns a `connection list`. Every existing spec returns a
singleton (17 call sites, mechanically wrapped; `Signals.notify` returns the singleton
itself so the seven `connect = Signals.notify ~prop:"…"` sites are unchanged, and a new
`Signals.notify_connection` exposes the single connection for a spec that builds its own
list). The calendar returns three:

```ocaml
[ Signals.connected c (W.Calendar.on_day_selected c ~callback)
; Signals.notify_connection ~prop:"month" c ~callback
; Signals.notify_connection ~prop:"year" c ~callback
]
```

They share **one** `Attr.Name.t` and therefore **one** slot, so `update_slots`, `armed`,
`require_slots` and `live_events.ml`'s comparison against `Events.for_kind` are all
untouched and no duplicate name reaches the slot list — which was the machinery constraint
the review named. What the list buys is only that all three are disconnected at teardown.

**Why three is complete.** The date *is* the three integer properties, and every write goes
through `calendar_set_date`, which notifies each component that changed. `day-selected`
covers a day-only change (it is what the grid path emits — measured: `set_day 11 ->
day-selected +1`), `notify::month` and `notify::year` cover the two a heading walk moves. A
fourth connection, `notify::day`, would make that argument structural rather than measured;
it is not added because no reachable path changes the day alone without `day-selected` (the
heading buttons cannot, the grid emits it), it is one line if one is ever found, and the
dedup already absorbs the extra emission. That reasoning is written into `w_calendar.ml`
rather than left here.

**Coalescing — exact, and stated.** `fire` deduplicates against `last_fired`, a `Date.t
option` on the existing per-widget cached record. **The handler sees a burst's date exactly
once — never zero times and never twice.** That is stronger than the ruling's "at most
twice", and it is safe for the reason measured above (every emission in a burst reads the
same final date). The memo is cleared by `set_date`'s write branch and nowhere else, which
is what keeps a date the model *declined* choosable again: without that line the handler
fires for the day, `reassert` puts the model's date back, and a second attempt at the same
day would be coalesced away against a memo that no longer describes anything on screen.
Pinned in the golden:

```
every route the date moves by:
  a day click            -> 2026-02-21, reached Bonsai 1
  next-month             -> 2026-03-21, reached Bonsai 1
  prev-month             -> 2026-02-21, reached Bonsai 1
  next-year              -> 2027-02-21, reached Bonsai 1
  prev-year              -> 2026-02-21, reached Bonsai 1
  two months forward     -> 2026-04-21, reached Bonsai 2
  the same day picked, declined, and picked again: 1 then 1
```

**The live regression, and its failure on the old code.** Two heading walks through a real
`Driver`, each followed by a drain, then a settling frame. Deleting the two
`notify_connection` lines and re-running:

```
-|  next-month             -> 2026-03-21, reached Bonsai 1
+|  next-month             -> 2026-03-21, reached Bonsai 0
-|  prev-month             -> 2026-02-21, reached Bonsai 1
+|  prev-month             -> 2026-02-21, reached Bonsai 0
-|  next-year              -> 2027-02-21, reached Bonsai 1
+|  next-year              -> 2027-02-21, reached Bonsai 0
-|  prev-year              -> 2026-02-21, reached Bonsai 1
+|  prev-year              -> 2026-02-21, reached Bonsai 0
-|  two months forward     -> 2026-04-21, reached Bonsai 2
+|  two months forward     -> 2026-04-21, reached Bonsai 0
-|driver, after the frame the walk armed: 2026-09-30 (handler saw 1 more)
+|driver, after the frame the walk armed: 2026-09-30 (handler saw 0 more)
-|driver, and a year forward: 2027-09-30 (handler saw 1 more)
+|driver, and a year forward: 2027-09-30 (handler saw 0 more)
-|driver, one more frame after the walks: 2027-09-30 (handler saw 0 more)
+|driver, one more frame after the walks: 2026-08-31 (handler saw 0 more)
```

The last line is the defect exactly as the review described it: the settling frame writes
the model's stale August date back over two walks the user made. Worth noting *where* the
failure surfaces — not on the line right after the walk, because with nothing scheduled
there is no idle frame for `drain` to run, but on the next frame from any source. That is
why the trailing `Driver.frame` line is the load-bearing one and why "before the frame"
would pass on the broken code; the test comment says so.

**The four false-premise sites and the gallery comment, corrected:**

| where | now says |
|---|---|
| `vtree/events.ml` (`Calendar` arm) | one attr over three emissions, why, and what the first round got wrong |
| `vtree/attr.mli` (`on_day_selected`) | "fires whenever the date the calendar shows changes — a day click or a heading walk", plus the dedup contract |
| `vtree/node.mli` (`val calendar`) | a walk emits no `day-selected`, so a calendar with no `on_day_selected` cannot be browsed either — worth knowing before rendering one as a read-only display |
| `src/widgets/w_calendar.ml` | rewritten with the measurement table |
| `examples/gallery.ml` (Dates page) | walking works, why that is a claim rather than an obvious truth, and what happens if only the day signal is wired |

## I1 — "text before editing" is now pinned by the thing the order changes

**Commit:** `2f8eeb9`. **Accepted.** The reviewer is right that the pin I offered was
vacuous: `W_entry.set_text_if_needed` saves and restores the caret, so `get_position` reads
9 under either order. The **selection** is what the order changes — `start_editing` selects
the whole text and a later text write collapses it to a bare caret.

`W.Editable.get_selection_bounds` is now printed on the existing "both props at once" line.
Verified by swapping the two writes in `reassert` and re-running:

```
-|  position after it: 9, selection=true 0 9
+|  position after it: 9, selection=false 9 9
```

That is the only golden line that moves, which is what the review predicted and is why the
first round's pin was insensitive.

## Minors

| # | verdict | what changed |
|---|---|---|
| 1 | **taken** | `w_editable_label.ml`'s `update` now matches `Editable_label { text = _; editing = _ }` on both sides. Warning 9 is on in `src/dune`, so a prop added to `editable_label_props` is now genuinely a compile error there. The first round wrote `Editable_label _` and claimed the same thing, which binds nothing. |
| 2 | **taken** | "truncate the text at" (golden updated). |
| 3 | **taken** | A mount-time refusal for each widget. Both are worth more than the symmetry: the calendar one prints `mounted with a year-0 date: showing today: true`, which puts the fact the review named — that a refused mount leaves the calendar on **today**, a value nothing chose — into the golden rather than into a sentence. Compared against `Date.today` rather than printed, so the golden does not change tomorrow. `node.mli`'s "left showing the date it had" is accurate as written (at mount, what it had *is* today), and the new case is what makes that legible. |
| 4 | **taken** | `~editing:true` at mount, through the library: `(GtkEditableLabel (text "Straight in") editing (css (editing)))`. |
| 5 | **taken** | The other decline direction: the user leaves editing mode, the model still renders `~editing:true`, `reassert` re-enters — and the selection comes back (`and the selection came back: true 0 9`), which is where the I1 ordering matters most, as the review said. |
| 6 | **argued, with the word taken** | `same_marks` stays order- and duplicate-sensitive. Making `[1; 2]` equal `[2; 1]` means sorting or set-ifying on every comparison — an allocation per calendar per differing frame — to save one `clear_marks` + ≤31 `mark_day`s + a redraw, for a view that rebuilds its marks in a different order each frame. No such view exists, and if one appears the fix belongs in the view (hand a sorted list), not in a comparison every calendar pays. The reviewer's point that `kind.ml`'s comment slightly oversells it is fair and is now written out there, including the escape hatch. |
| 7 | **taken** | An idle-frame bench for both widgets, in Tasks 9/10's ratio-based shape. Both pin the *memo*: a frame parked on a refused value against a settled one, bound 5. Measured `0.00023 → 0.00015 ms` (calendar, ratio 0.67) and `0.00027 → 0.00021 ms` (label, ratio 0.93). The absolute numbers go to stderr, and they carry the third fact deliberately: the label at 100 000 characters costs **1.22 ms** per idle frame, because the compare is `String.equal` against a fresh copy — O(len), exactly as every `Node.entry` in the tree already is. That was Carry #3 in the first round; it is now a printed number rather than a claim. |

## Files touched

`src/signals.ml(i)` (the `connection list`), the 17 `connect` sites across
`src/widgets/*.ml` and `src/controllers.ml` (mechanical singleton wrap),
`src/widgets/w_calendar.ml` (the spec, `last_fired`, `set_date`),
`src/widgets/w_editable_label.ml` (Minors 1–2), `vtree/events.ml`, `vtree/attr.mli`,
`vtree/node.mli`, `vtree/kind.ml` (Minor 6's word), `examples/gallery.ml`,
`test/live/live_text.ml` + `expected_text.txt`.

## Carries to Task 12 (updated)

Carries 1, 3, 4 and 5 from the first round stand. Carry 2 is **withdrawn**: it said an
application wanting a month-browser "has to move `~date` as the user walks", which
understated the defect (it was never told) and is now simply how the widget works —
`Attr.on_day_selected` reports the walk and the model moves `~date`. Two new ones:

6. **`Signals.read_back.connect`'s list has exactly one user.** Every other spec returns a
   singleton. If a second multi-emission prop appears (a `GtkPaned`'s position, which moves
   by drag *and* by `set_position`, is the likely next one), the dedup this round wrote for
   the calendar is the pattern — but it lives in `w_calendar.ml`, not in `Signals`. A third
   user is the point at which it should move.
7. **`notify::day` is the unconnected fourth.** Adding it would make the calendar's
   completeness argument structural rather than measured, at the cost of one more emission
   the dedup already absorbs. Worth doing if a GTK upgrade ever changes which paths emit
   what; the reasoning is in `w_calendar.ml`.
