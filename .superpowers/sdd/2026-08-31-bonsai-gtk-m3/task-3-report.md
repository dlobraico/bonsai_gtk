# Task 3 report — report-once memos, Child_keys.length, and the text view's caret

Branch `m3`, commits `028d150..accd8d9` (four). `nix develop -c ./scripts/ci.sh`:
**all green** at `accd8d9`.

## What changed

**`b550f8c` — the hidden-page divergence is reported once (step 1).**
Both select fixups (`w_stack.ml`, `w_notebook.ml`) gain one memo shape —
`Refusal.Make (String) (No_extra)`, keyed on the offending page key. The fixup
still *tries* on every frame (compare, write, read back), so the frame that makes
the page visible is the frame the model's choice finally lands; what the memo stops
is the noise. Read-back decides "did GTK take it" — GTK's visibility guard is its
only refusal path on both widgets — and a write that did not land is reported once:
`~visible_child names the hidden page %S; GTK will not switch to it` (notebook:
`~current_page …`). `landed` clears the memo, so a later re-hide is a new report and
a different hidden page is a new datum. The patcher polls `take_report` inside the
fixup closure, right after the attempt, which is the one place holding both the
widget and the node's path. Constructor docs on `Node.stack`/`Node.notebook`
updated from "on the backlog for the report hook" to the report they now get.
Live (`live_lists.ml`): one report at mount, none across five parked frames, the
landing on the visibility flip, the re-hide re-report — for both widgets.
**Parked-frame cost, measured as the backlog asked:** sub-microsecond-to-few-
microsecond per idle frame in every run; the parked/settled *ratio* is
machine-dependent and not a property of the code (my run read 0.0090 ms parked vs
0.0007 ms settled; the reviewer's re-run of the same build read ~1.1×, noise-bound
— review Minor 1, amended here so the ratio is not quoted onward). What both runs
agree on is the conclusion: a parked frame is well under 0.1% of a 16.7 ms budget,
and the attempt-per-frame policy costs nothing worth optimising.

**`1fee718` — a duplicated `~selected` is deduped, and reported once (step 2).**
The ruling takes both halves the backlog said to decide together. `apply_selection`
dedupes the wanted list (order-preserving, first occurrence wins) before the
comparison — `["a"]` vs `["a";"a"]` never compared equal, so every frame ran
`unselect_all` plus the redundant re-select, forever — and a list that needed
deduping is reported once per distinct value, keyed on the whole list:
`~selected lists "a" more than once; a selection holds each key at most once, and
the duplicates were ignored`. A clean list clears the memo. Same change in both
`w_list_box.ml` and `w_flow_box.ml`; the patcher polls after each fixup. Live pins
the full cycle (mount-with-dup → parked frames → different dup → clean → dup again)
over **both** copies, taking the final review's mutation lesson: a fix landed in one
file only now fails a golden.

**`d362157` — `Child_keys.length`, and the teardown paths pinned (step 3).**
`Child_keys.length` counts live bindings (`clean` first, so the answer is exact
after a `Gc.full_major`); `W_list_box`/`W_flow_box`/`W_notebook` each expose
`tracked_keys ()` over their module table. Live, per container: mounting 5 keyed
children registers 5; a patch removing 2 drops them eagerly (the `list_ops.remove`
path); the teardown drops the rest through the `forget_*` hook — with the `live`
record kept reachable across the GC (`Sys.opaque_identity` after the read), so the
zero is the hook's doing and not the ephemeron's. **Mutation-verified:** replacing
the patcher's `| Flow_box _ -> W_flow_box.forget_children widget` with
`| Flow_box _ -> ()` — the exact task-7-M4 mutation that used to leave every golden
byte-identical — now reads "flow box tracks 3 keys after the teardown" instead
of 0. (Run, observed, reverted.)

**`accd8d9` — `Attr.on_cursor_moved` (steps 4–5).**
`(int -> unit Ui_effect.t) -> t`, on `text_view`: `notify::cursor-position` on the
**buffer** (the view has no such property), so the connection names the buffer
exactly as `On_changed`'s does; the offset is read back with `get_cursor_position`.
The `in_patch` guard keeps the library's own caret motion — a controlled `~text`
write's delete/insert/restore — out of the handler. Threaded through every
exhaustive table (`Name`, `is_event`, `controller_family`, `attr_phase`,
`placement`, `attr_apply`, the gallery sweeps' `action_for`); the gallery text_view
carries it so the attr sweep pins it; `Events.for_kind`'s TextView row gains it and
the `live_events` agreement sweep stays green. `Bonsai_gtk_test` gains
`Move_cursor of string * int` (kind-checked; the offset is unclamped headlessly and
the mli says so, `Set_value`'s deliberate weakness). The "approximate caret"
paragraphs on `Node.text_view` and in `w_text_view.ml` now end with the attr that
closes them. Live: three `place_cursor` calls outside the guard arrive as
`(5 0 11)` through GTK's own synchronous notify; a controlled rewrite delivers
nothing and the restored offset reads back 11. Headless: `Move_cursor` drives the
handler; a mis-aimed one names the kind it found.

## The verification clause: every "Do first in M3" bullet, by name

- on_click cannot claim — **closed** (Task 2).
- focus events vs the `contains_focus` query — **closed** (Task 2).
- focus attrs take no `?phase` — **closed** (Task 2).
- TextView exposes no cursor position — **closed** (this task, step 4).
- `Key_press` cannot model propagation — **absorbed**: routing coverage grows in
  Task 7's live_input block (Task 2's capture/bubble and claim blocks already cover
  the key and click halves live).
- Keyval table curated, not complete — **absorbed** into Task 7.
- no live test delivers a synthetic click or key press — **closed** by
  `live_input.ml` (M2 task 16, extended by Task 2's claim block); the bullet
  predates that file.
- Child_keys never compacted / `forget_*` unpinned — **closed** (this task,
  step 3, mutation-verified).
- `after_of` O(index) — **deliberately carried**: the backlog itself says spend
  where the measurements are, and none point here.
- hidden `~current_page` / stack twin — **closed** (this task, step 1, both).
- duplicate key in `~selected` — **closed** (this task, step 2, both copies).
- list_box/flow_box two copies — see the trigger answer below.
- behavioural half of the nullable bindings — **carried to Task 13**, which
  decides it.
- `require_slots` not on the patch path — **closed** (Task 2, step 4).
- `Activate_row` on non-activatable rows — **deliberately carried**
  (revisit-once-deliberately; Task 13 re-records it).

## The standing trigger: is the third copy the evidence?

Yes. The dedup is the **third fix made identically twice** in `w_list_box.ml` and
`w_flow_box.ml` (after the O(n) selection map and review I1), which is exactly the
evidence the M2 review said would settle the functorise question. Not done in this
task — it is a structural refactor with no behaviour change, mid-milestone, in the
two files Task 3 just touched — but the report's answer to the trigger is: on the
table, and the backlog rewrite (Task 13) should promote it from "declined" to
"scheduled", with the shared `dedup_selected`/`Selection_memo` block (now the third
near-identical pair) as exhibit.

## Deviations from the plan

1. **The memo trigger is read-back, not a visibility pre-check.** The plan's text
   implies "names a hidden page" is known a priori; the implementation writes and
   reads back, because "did GTK take it" is the question and the visibility guard
   is GTK's only refusal path on both widgets (cited in the comments). The message
   still says "hidden page", which is therefore accurate.
2. **The parked-frame pin is the report count plus the measured cost**, not a
   golden over GTK writes — a write per frame is not observable from outside GTK.
   The one-attempt-per-frame property is structural (the fixup body), the
   report-once property is goldened, and the cost is measured (stderr + this
   report).
3. **`dedup_selected` is a copied block, not shared code** — deliberately, since
   sharing it would be pre-judging the functorise question the trigger sends to the
   controller; it is flagged above as the third copy.
4. **Step 3's "pump" is a `Gc.full_major`** — removal is eager and teardown is
   synchronous, so there is no main-loop work to pump; the GC is what makes the
   ephemeron count exact, and `Child_keys.length` cleans first so the assertion is
   deterministic.

## Deliberately left undone

- Functorising the two list containers (above — controller's call).
- Writing the caret back (`on_cursor_moved` is the read; a controlled caret is part
  of the focus/selection-is-state design on the backlog, and the mli says so).
- `examples/gallery.ml` demonstrating the new attr — Task 12 owns the examples
  (same ruling as Task 2's Minor 5).

## ci.sh tail

```
== example smoke
(counter, gallery, embed each held for their 3 s timeout)
all green
```

Full gate at `accd8d9`. The mutation check ran between the step-3 golden landing
and its commit, and was reverted before it (verified: `git status` clean apart
from the pre-existing `.beads` drift and the sdd reports).
