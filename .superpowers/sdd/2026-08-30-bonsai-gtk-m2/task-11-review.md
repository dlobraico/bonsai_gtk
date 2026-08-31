# Task 11 review — Calendar and EditableLabel (`179e70a` on `b863bb2`)

## Summary

The diff is careful, well-measured and mostly right. The headline deviation is correct and
important: the brief's `year, month, day` write order really is wrong, GTK really does
refuse rather than clamp, and `set_day 1` first really is both necessary and sufficient —
day 1 exists in every month of every year in GTK's range, so no intermediate state is
invalid, and every `Date.t` GTK will hold lands. I re-derived that and then mutated it
(`set_day c 1` removed): the golden moves in two places, including a real wrong date
(`the day after a leap year ends: 2024-03-01`). The zero-based month is genuinely
defended — three independent legs (the `read_date`-printed dump, the raw-property line,
the every-month-of-2026 round-trip whose *input* is the node's `Date.t`) — and a
consistent-lie mutation (write `to_int m`, read `get_month`) is caught by two of them. The
`stop_editing true` ruling is pinned hard (mutating it to `false` moves five golden
lines, and reveals the extra fact that a `false` there would undo the text `reassert` had
just written in the same frame). The stub-safety table checks out against the generated
C: both constructors are floating `GInitiallyUnowned`s so `g_object_ref_sink` is right,
`ml_gtk_editable_from_gobject` does `g_type_is_a` then `g_object_ref` before wrapping, and
neither class has an object-returning getter, so there is no `get_selected_rows` shape
here. `gtk_calendar_get_date` / `select_day` are indeed absent from the generated `.mli`,
so the brief's "is the transfer-full `GDateTime` freed?" question is moot. `dune build`,
`dune test`, the live suite under xvfb and `./scripts/ci.sh` are all green on a clean
tree, and `test_gallery.ml` now really does cover every `Node` constructor (checked
mechanically: the only `node.mli` `val` missing from it is `find_by_test_id`, which is not
a constructor).

One finding blocks. The task exposes exactly one of `GtkCalendar`'s five signals on the
stated ground that "walking to another month moves the day too, so `day-selected` fires
for all four anyway". That claim is false, and the implementer's own golden line
(`set_month 5 -> 2020-06-10, day-selected +0`) is the proof they already had. Measured:
clicking any of the four heading buttons emits **zero** `day-selected`, and end-to-end the
user's walk to September is silently reverted to August by the next `reassert`. The
calendar cannot be browsed at all — which is the one thing the shipped gallery page tells
the user to do.

## Per-deviation judgement

1. **Day-1-first write order** — **sound, and the best thing in the diff.** Necessary
   (some reset is required; every "careful" order strands the widget) and sufficient (day
   1 is valid in every month of years 1–9999, and the final `set_day d` is valid because
   the target is a real `Date.t`). Mutation-verified. Documented in `w_calendar.ml:23-54`,
   `node.mli` and the golden matrix.
2. **`~marked_days` outside 1–31 rejected at the constructor** — **sound.** GTK's own
   answer is a silent no-op with no critical, and no later date makes day 0 a day; that is
   exactly `Node.level_bar`'s test for raising. `node.ml:661-706`.
3. **A year-0 `~date` *not* rejected at the constructor** — **sound.** It is a value
   carrying model state, so `w_text_view.ml`'s refuse–record–report is the right shape, and
   `node.mli`'s "an `Invalid_argument` in the computation ends the application" note
   settles it. Pinned in `test_widgets.ml` and in the live golden both directions
   (refused → parked five frames silently → written on the frame a holdable date arrives →
   a *different* year-0 date reported again).
4. **Reusing `W_entry.changed` as well as `set_text_if_needed`** — **sound.** The spec's
   `connect` does `let e = editable w in Signals.connected e (W.Editable.on_changed e ...)`,
   so the connection names the `GtkEditable` the widget *is* (`from_gobject` is a checked
   cast to the same GObject, not the internal `GtkText` delegate), and `Signals.connected`
   stores that object, so the disconnect object is correct and kept alive. The extra ref
   the stub takes is paired by the wrapper's unref, pinned by the new GC-churn block
   (`references 3 -> 3` over 500 wrappers and 5 000 idle frames).
5. **`create` passes `""` and writes the text through `reassert`** — **sound, no
   one-frame blank.** `Patcher.mount` runs `create` before the widget is parented or the
   window presented, so nothing is on screen between the two; and `connect_all` runs
   *after* `create`, so the two `changed` emissions the constructor-time `set_text`
   provokes reach no slot at all. The gain (one implementation of the controlled prop,
   including its refusal) is real.
6. **`update` a no-op with the `match` kept** — **the code is right, the stated reason is
   false.** See Minor 1.
7. **`test_gallery.ml` gained four constructors, not two** — **sound and welcome.** Task
   10's omission was real, and the file is now genuinely complete (verified
   mechanically). Outside the brief's file list but strictly additive and called out.
8. **`Bonsai_gtk.Private` gained `W_calendar`** — **acceptable.** `Private` already
   exports `W_drop_down`, `W_list_box`, `W_flow_box`, `W_button`; the surface is
   documented as unstable and test-only, and the alternative (a second month conversion
   written out in `live_text.ml`) is the thing the whole widget is trying to prevent.

## Critical

### C1 — the calendar cannot be browsed: a heading walk emits no `day-selected`, and `reassert` reverts it

`vtree/events.ml:56-59`, `vtree/attr.mli:554-560`, `src/widgets/w_calendar.ml:209-213`
all record the same justification for exposing only `day-selected`:

> `next-month`, `prev-month`, `next-year` and `prev-year` report that the heading was
> clicked rather than what the calendar now shows, and walking to another month moves the
> day, so `day-selected` fires for all four anyway.

The second half is false. Measured on GTK 4.22 by emitting `clicked` on the calendar's own
heading buttons (the exact path a user click takes — the calendar connects its
`calendar_set_month_prev/next` handlers to that signal):

```
PROBE heading buttons: 4
PROBE button 0 (pan-start-symbolic): 2026-7-15 -> 2026-6-15, day-selected +0
PROBE button 1 (pan-end-symbolic):   2026-6-15 -> 2026-7-15, day-selected +0
PROBE button 2 (pan-start-symbolic): 2026-7-15 -> 2025-7-15, day-selected +0
PROBE button 3 (pan-end-symbolic):   2025-7-15 -> 2026-7-15, day-selected +0
```

The month and year move; the day-of-month survives the walk, so `day-selected` does not
fire — which is precisely what the diff's *own* golden already says about the property
setters (`set_year 2020 -> day-selected +0`, `set_month 5 -> day-selected +0`).

**Failure scenario, measured end to end through a real `Driver`** (a calendar whose model
holds `2026-08-15` and whose `on_day_selected` accepts every day):

```
PROBE2 before the walk:                  2026-08-15
PROBE2 the user clicked next-month:      2026-09-15 (handler saw 0)
PROBE2 after a frame:                    2026-08-15 (handler saw 0)
```

The user walks to September. `on_day_selected` never runs, so the model still holds
August. On the next frame — any event, or the tick — `w_calendar.ml:245-246`'s
`Date.equal (read_date c) p.date` is false, `reassert` writes the model's date back, and
the calendar snaps to August. There is no attr through which an application could learn
that the walk happened, so no model can be written that would keep up. The only way to
reach another month is the accident where the walk *does* change the day (e.g. Jan 31 →
Feb, where GTK clamps to the 28th).

This is not a theoretical limitation. `examples/gallery.ml:513-516` instructs the reader
to do exactly this and says it works:

> They are days of the month and survive a month change, which is visible by marking a day
> and then walking to another month with the heading arrows.

It does not. The report's "Carries to Task 12" #2 gestures at the shape of the problem
("an application that wants a month-browser has to move `~date` as the user walks") but
understates it: the application is never told, so it cannot.

All four signals *are* bound (`calendar.mli`: `on_next_month`, `on_next_year`,
`on_prev_month`, `on_prev_year`), so the fix is available. Two shapes, for the lead to
pick:

- Connect the existing `On_day_selected` read-back to `notify::month` and `notify::year`
  as well as `day-selected` — the `fire` already reassembles the whole date from the three
  getters, so nothing else changes and the attr's contract ("the date the calendar now
  shows") becomes true. Note the machinery constraint: `Signals.read_back.connect` returns
  one `connection`, so this needs either `connection list` or three specs sharing one attr
  name (the latter puts a duplicate name in `slots`, which `live_events.ml`'s comparison
  against `Events.for_kind` would have to tolerate).
- Or expose the four walk signals as their own attr(s) and let the application move
  `~date` itself.

Whichever is chosen, the four places quoted above and the gallery comment need correcting,
and the fix needs the measurement above as a live regression: a heading click followed by
a frame, asserting the calendar did *not* snap back.

## Important

### I1 — "text before editing" is not pinned; the line offered as its pin is insensitive

`src/widgets/w_editable_label.ml:157-171` states the ordering rule and the report answers
the brief's review focus with "By construction … and visible in `both props at once …
position after it: 9`". I swapped the two writes in `reassert` and rebuilt: **every byte
of every golden is identical** and the live suite passes.

The reason the pin is vacuous is that `W_entry.set_text_if_needed` saves and restores the
caret position around the write, so `get_position` reads 9 under either order. What the
order actually changes is the *selection*, which nothing reads. Measured on a realized
widget:

```
PROBE text-then-editing (shipped): text="Rewritten" pos=9 sel=true  0 9
PROBE editing-then-text (swapped): text="Rewritten" pos=9 sel=false 9 9
```

So the invariant is real and worth having — `start_editing` selects the whole text, and a
text write after it collapses that to a bare caret — and it is currently defended by a
comment alone. `W.Editable.get_selection_bounds : t -> bool * int * int` is bound
(`editable.mli:91`), so the fix is one extra printed value on the existing "both props at
once" line. Without it a later refactor can reverse the order and stay green.

## Minor

1. **Deviation 6's rationale does not hold.** `w_editable_label.ml:232` is
   `| Editable_label _, Editable_label _ -> ()`, which binds no fields; adding a prop to
   `editable_label_props` is not a compile error there. The comment at
   `w_editable_label.ml:227-231` claims it is. Either destructure the record
   (`Editable_label { text = _; editing = _ }`, which does error under warning 9) or drop
   the claim. `w_calendar.ml`'s `update` has the same property but does not claim
   otherwise.
2. **The NUL diagnostic is ungrammatical.** `w_editable_label.ml:54-56`: "text contains a
   NUL byte, which GTK would silently truncate at (gtk_editable_set_text takes a
   NUL-terminated string)" — "truncate at" has no object. It reaches users through
   `ctx.report` and is in the golden. Probably "truncate the text at".
3. **No mount-time refusal is exercised.** The path is wired (`mount` → `note_interest` →
   `enqueue_fixups` → `take_report`, and `create` calls `reassert`), but every live case
   mounts something holdable and only *patches* to the unholdable value. Worth one case
   each, because mounting a calendar with a year-0 date leaves it showing **today** — a
   value nothing chose and which moves while the application runs — and neither `node.mli`
   ("the calendar was left showing the date it had") nor the report says so.
4. **`~editing:true` at mount is never exercised through the library.** `create` would
   call `start_editing` on an unparented, unrealized widget. The report measures that this
   works on a raw widget; the library path is untested.
5. **The other editing-decline direction is untested.** The golden covers "user entered
   editing, model says false → `stop_editing`". The reverse — the user leaves editing
   (Escape/Enter/focus loss) while the model still renders `~editing:true`, so `reassert`
   must re-enter — is not exercised, and it is the direction where the text write ordering
   (I1) matters most.
6. **`same_marks` is order- and duplicate-sensitive; the write is not.**
   `w_calendar.ml:202`. `[1; 2]` → `[2; 1]` costs a `clear_marks` plus a re-mark and a
   redraw for no visible change. The comment at `kind.ml:392-396` says order and
   duplicates make no difference "to the result", which is true and slightly oversells it.
   Cheap either way; worth a word if a view is likely to rebuild in a different order.
7. **No idle-frame bench for either widget.** Tasks 9 and 10 both added one (`bench:`
   lines in `expected_text.txt`); Task 11 pins "GTK emitted 0" over five idle frames,
   which is the property that matters, but not the cost. `read_date` is three getters plus
   `Date.create_exn` and the editable label's compare is O(len) per frame per label (the
   report's own Carry #3), so a ratio bench would be consistent with the two rounds before
   it.

## Carries checked

Task 10's re-review N1–N3 and R1–R2 are all taken and correct: `live_tree.ml:142`'s
`GtkStringObject` type is now a module-level `lazy` (N1); the `~items:[] ~selected:0` case
is present and reaches the previously-unexercised "nothing is selected" wording (N2);
`w_drop_down.ml`'s `update` comments no longer describe the model replacement that the
splice removed (R1); `bonsai_gtk_test.mli`'s `Set_selected` doc gives the honest reason and
`test_handle.ml` gained the permanently-out-of-range `~selected:9` instance (R2); N3 is
withdrawn in the report as the reviewer asked.

`Events`/`Placement`/`Kind` counts all move by exactly two and the derived assertions hold
(`kinds checked: 35 → 37`, placement `40 → 42`, `is_event` list, both `all_kinds` lists).
`require_specs` negatives are tested in both directions, including the near miss that must
*not* raise (`On_changed` on an editable label). Headless `Select_day` / `Set_editing`
kind-check like the activate actions and do not consult the node's props, consistently with
the rest of the table.

## Verdict

**Request changes.** C1 is a user-visible functional defect in the task's headline widget,
with a false premise recorded in four places and a shipped example that documents the
broken behaviour as working; it needs a fix and a live regression. I1 is a one-line test
addition that turns a stated invariant from a comment into a pin. Everything else is
Minor and can travel to Task 12. The write-order deviation, the month-conversion defence,
the `stop_editing true` ruling, the refusal machinery for both widgets, the stub-safety
audit and the `test_gallery.ml` completion are all correct and well evidenced.

---

# Re-review — fix round 1 (`2f8eeb9` on `179e70a`)

Scoped to C1 and I1, plus the machinery the C1 fix touches. `./scripts/ci.sh` is green on a
clean tree; the only golden lines that move are the intended ones.

## C1 — fixed, and the fix is pinned three ways

**The connection-list change is correct.** `Signals.connect_all` now `List.concat_map`s, so
every connection a spec makes lands in `live.connections`, and `Signals.disconnect`
(`signals.ml:210`) disconnects each from its own `c.source`. All three of the calendar's
connections name the calendar itself (`Signals.connected c …` and two
`notify_connection ~prop:… c`), so teardown at `patcher.ml:497` reaches all three from the
right object. The `slots` list is still built one entry per *spec*, so one attr name still
means one slot: `update_slots`, `armed`, `require_slots` and `live_events.ml`'s comparison
(which maps `impl.signals` through `Signals.spec_attr`, `live_events.ml:80-84`) are
untouched, and `expected_events.txt` is unchanged. The 17 other call sites are mechanical
`[ … ]` wraps; `notify` keeps returning the singleton so the seven `connect = Signals.notify
~prop:…` sites are unchanged, and `notify_connection` is the escape hatch, correctly
polymorphic in the object rather than fixed to `Widget.t`.

**Each connection is independently load-bearing.** Deleting one at a time and re-running the
live suite:

| deleted | golden lines that move |
|---|---|
| `on_day_selected` | `a day click … reached Bonsai 1 → 0`, `the same day picked, declined, and picked again: 1 then 1 → 0 then 0`, the whole driver decline block (`the refusal armed: 2026-08-31 → 2026-08-29`) |
| `notify::month` | `next-month`/`prev-month`/`two months forward` routes → 0, `driver, after the frame the walk armed … saw 1 more → 0 more` |
| `notify::year` | `next-year`/`prev-year` routes → 0, `driver, and a year forward … 1 more → 0 more`, and the settling frame `2027-09-30 → 2026-09-30` — the snap-back itself |

So the regression is real, it fails on the old code, and no one of the three is redundant.

**The coalescing memo cannot suppress a genuine change — and I pushed harder on the safety
claim than the golden does.** The dedup is exact only because every emission in a burst
already reads the *final* date. The golden establishes that for single-component walks and
for Jan 31 → Feb. The case it omits is the one where it would break first: a walk that moves
the month **and** the year. Probed:

```
Dec 2026 -> next-month     -> 2027-01-15 | notify::month@2027-01-15 notify::year@2027-01-15 | all-agree=true
Jan 2026 -> prev-month     -> 2025-12-15 | notify::month@2025-12-15 notify::year@2025-12-15 | all-agree=true
Dec 31 2026 -> next-month  -> 2027-01-31 | notify::month@2027-01-31 notify::year@2027-01-31 | all-agree=true
Feb 29 2024 -> next-year   -> 2025-02-28 | notify::day@2025-02-28  notify::year@2025-02-28  | all-agree=true
Feb 29 2024 -> prev-year   -> 2023-02-28 | notify::day@2023-02-28  notify::year@2023-02-28  | all-agree=true
Mar 31 2026 -> prev-month  -> 2026-02-28 | notify::day@2026-02-28  notify::month@2026-02-28 | all-agree=true
```

Every callback in every burst reads the post-walk date, so a burst delivers once and never
delivers a bogus intermediate. Reasoned through the rest: the library's own writes emit
inside the patch and are dropped by `dispatch`'s `in_patch` check *before* `fire` runs, so
they never pollute the memo; `set_date` is the only path that writes the date and it clears
the memo; the refusal branch correctly does *not* clear it (the widget did not move); a
walk out and back fires both ways because the memo tracks the last date, not a set. I could
not construct a false suppression.

**The four false-premise sites and the gallery comment are corrected**, and `node.mli` now
carries the consequence the first round did not state — a calendar with no
`on_day_selected` cannot be browsed.

## I1 — fixed

`selection=true 0 9` is now printed on the "both props at once" line. Swapping the two
writes in `reassert` moves exactly that one line to `selection=false 9 9` and nothing else,
which is what makes it the pin the position line was not.

## Important (new)

### I2 — the memo reset is unpinned, and the block that claims to pin it is inert

`w_calendar.ml:185` (`st.last_fired <- None` in `set_date`'s write branch) is the line the
report singles out as what "keeps a date the model *declined* choosable again". **Deleting
it changes no golden byte.**

The block labelled `the same day picked, declined, and picked again: 1 then 1`
(`live_text.ml`, "every route the date moves by") does not exercise it, for two independent
reasons:

- the intermediate patch renders `Date.to_string (read_date (calendar live))` — the date
  the widget *already shows* — so `reassert`'s `writes` is false, `set_date` is never
  called, and the memo is never cleared. That is an accepted pick, not a declined one;
- the next patch then moves the date to `2026-02-15`, so the second `set_day 5` produces a
  date in a different month, which differs from the memo whether or not it was cleared.

The invariant is real and the shipped code is right. Probed with a model that genuinely
declines (always re-renders the same date), picking the same day three times:

```
shipped:            picked 20 -> reached Bonsai 1, then 1, then 1
reset line removed: picked 20 -> reached Bonsai 1, then 0, then 0
```

Without the reset, the user's second and third attempts at a day the model declined are
silently swallowed — they click and nothing happens, in exactly the decline scenario the
controlled-prop story is built on, and one deleted line away with the suite green.

Fix is small: make the intermediate patch a genuine decline (render a fixed date rather
than the widget's own) and pick the same day twice, so the second pick's date is equal to
the memo. That turns the existing block into the pin it is labelled as.

## Minor

1. The heading-walk table in the golden covers only single-component walks plus Jan 31 →
   Feb. The month-and-year walk (Dec → Jan) is the case the dedup's safety argument rests
   on most and is absent; behaviour is correct (probed above), but one more `walk` line
   would put it in the golden.
2. `mounted with a year-0 date: showing today: %b` compares against a `Date.today` computed
   after the mount. A run crossing midnight between the two would flake. Capturing `today`
   once before the mount is free.
3. Nothing pins that *all three* connections are torn down. Low risk — the type forces the
   list, and a surviving handler on a destroyed widget finds a cleared slot rather than
   crashing — so probably not worth a test, but it is the one property of the
   connection-list change that no test observes.
4. Minor 6 argued rather than taken: **accepted.** Sorting or set-ifying on every comparison
   to serve a view that rebuilds its marks in a different order each frame — a view nobody
   writes — is the wrong trade, and `kind.ml` now states the cost and names the escape hatch
   (fix it in the view).
5. Minor 7's bench now records that an editable label at 100 000 characters costs **1.22 ms
   per idle frame** — about 7% of a 60 fps budget, for one widget. That is correct and is
   every `Node.entry`'s existing behaviour, and Carry 3 is the right home for it; worth the
   lead seeing the number now that it is measured rather than assumed.

Minors 1–5 from the first round are all taken and verified: the `update` match now
destructures both records (warning 9 makes the claim true), the NUL diagnostic reads
"truncate the text at", both mount-time refusals are in the golden (the calendar's putting
the "left showing **today**" fact on the record), `~editing:true` at mount goes through the
library, and the user-leaves-while-the-model-says-stay direction is covered with the
selection assertion that makes it the strongest I1 case in the file.

## Verdict

**Approve with one Important test fix (I2).** C1 is properly fixed — the right shape, all
three connections independently pinned, teardown correct, the slot machinery genuinely
untouched, and the dedup's exactness verified past what the golden covers. I1 is fixed and
mutation-verified. The one thing outstanding is that the guard protecting a re-pick of a
declined day is defended by a comment rather than by the test that names it; that is a
few-line change to an existing block and does not need another review round.
