# Task 10 review — DropDown and LevelBar (`ce6497d`, base `d9f9d93`)

**Verdict: Approved with follow-ups.** No Critical. Four Important, seven Minor.

Gate re-run independently: `nix develop -c ./scripts/ci.sh` → `all green`, exit 0, on a
clean tree. Every claim below that says "measured" was measured by this review in a
throwaway worktree at `ce6497d` (since removed; the checkout is unmodified).

---

## Summary

The drop-down is the strongest widget in M2 so far. The three findings the implementer
volunteered — autoselect making `set_selected invalid_list_position` a silent no-op, a
model rebuild resetting to item **0** rather than to "nothing", and `String_list.new_`
reference-sinking a non-floating object — are all real; I re-derived the first two from the
golden's own emission counts and the third from the stub. The refusal machinery is the text
view's, correctly transplanted: memo consulted *before* the widget comparison (task-9 R1),
cleared by a landed write and by a rebuild, reported once through `ctx.report` with the
node's path, and pinned by a bench that would blow up to 20 001 reports without it. The
model-identity claim is real and load-bearing, and the ordering that makes a rebuild safe
(`update` writes the model, `reassert` re-applies the selection, `enqueue_fixups` reports —
all inside one patch, all inside `in_patch`) holds on every path including the mount path
and `reassert_only`.

Four mutations I ran confirm the tests bite where the report says they do:

| mutation | caught by | outcome |
|---|---|---|
| `if not (same_items …)` → `if not false` (always rebuild) | `same model: true` → `false` on "selection alone" | **caught** |
| delete `forget_refusal w` after a rebuild | "items again" stops reporting | **caught** |
| delete the `already_refused` memo | `refusals … : 1` → `20001` | **caught** |
| delete `old.min <> new_.min` from the value rewrite | `(value 0.5)` → `(value 0.8)` | **caught** |

Two more mutations found holes, and they are I2 and I3 below.

The level bar is four properties and is right, but its coverage is thinner than the
drop-down's and its report contains a claim that is factually wrong in the direction that
would let someone break it.

---

## Per-deviation judgement

**D1 — `on_selected_changed` is `Read_back`, not `Payload`. Accepted.** The task message
was wrong and the brief was right. `notify::selected` goes through GLib's generic
marshaller (`Signals.notify`, `src/signals.ml:143`, `connect_simple`), which carries no
arguments and wants no return value; a `Payload` spec has nothing to carry and nothing to
answer with. Nor is it object-carrying — the signal is on the drop-down itself, unlike the
text view's buffer. Following the brief was correct.

**D2 — the handler carries the index only. Accepted.** The brief's interface says
`int Handler.t`. The stated reasons hold: the items are props, so the handler already holds
the list; and `notify::selected` reports a position, so carrying a string would have the
attr claim more than GTK says. `attr.mli:515` documents `List.nth items i` as the intended
idiom, which is exactly what `examples/gallery.ml` then does.

**D3 — `Node.level_bar` also rejects a negative bound. Accepted.** Not in the brief, but
measured (`gtk_level_bar_set_min_value` asserts `value >= 0.0`: `Gtk-CRITICAL` and *no
write*, so the bar silently keeps its old range), the same shape as `Node.flow_box`'s
negative geometry, decidable in the same place, and tested (`test_widgets.ml`, both the
rejection and the legal negative *value*). Right call.

**D4 — `Live_tree` suppresses a `GtkDropDown`'s children. Accepted.** A `GtkListView`
whose `GtkListItemWidget` count follows the model and realization would make the golden
churn on an item being added and say nothing. Printing the items from the model instead is
strictly more informative *and* stable, and it is what makes the rebuild assertions
possible at all. Carry 3 (make the suppression a list before it has three entries) is the
right note.

**D5 — two model-construction paths (`new_from_strings` in `create`, `String_list.new_` +
`set_model` in `update`). Accepted as written, but see I1.** Both stated reasons are true
(`new_from_strings` builds the model inside GTK and installs the `expression` the popup's
search filter reads). The asymmetry exists *only* to keep the mount path off the leaking
constructor — which is an argument for removing the leaking call from the update path too,
not for keeping two paths.

**D6 — no offsets, no drop-down `mode`, `offset-changed` omitted from `Events.for_kind`.
Accepted.** Spec §11: a handler nothing can provoke is worse than no handler. Both
`Events.for_kind`'s `Level_bar _ -> []` arm and `w_level_bar.ml`'s `signals = []` say why.

---

## Critical

None.

---

## Important

### I1 — the `GtkStringList` leak is real, and it is avoidable in this file today

`src/widgets/w_drop_down.ml:51`.

The leak is confirmed, not merely reported. `ml_string_list_gen.c:35-36` is
`GtkStringList *obj = gtk_string_list_new (c_arg1); if (obj) g_object_ref_sink (obj);`, and
`GtkStringList` derives from `GObject`, not `GInitiallyUnowned`, so `ref_sink` degenerates
to a plain `ref` on top of the ownership the constructor already transferred. The wrapper's
finaliser drops one; the other is never dropped. `Gobject.mli` exposes no `unref`, so
nothing in OCaml can compensate. **One `GtkStringList` plus its copied strings is leaked
per items change, permanently — including after the drop-down is destroyed.** For a
drop-down whose list is recomputed per keystroke (a filtered picker), that is per keystroke.

What makes this a finding rather than a note is that the brief's reason for choosing
replacement over mutation does not apply to the alternative that removes the leak.
Ruling 2 rejects "computing a minimal splice from two string lists", and it is right to.
But `String_list.splice` (bound, correct stub, `ml_string_list_gen.c:50`) takes a
*whole-content* replacement in exactly one call — `splice model 0 n_old (Some new_array)` —
with no diff to compute, no new GObject, and no `from_gobject` cast.

I ran it. Replacing `set_items`' body with a splice on the model read back from
`get_model`, everything else untouched:

```
PROBE splice: model refcount 14, n now 4, selected 2
items changed: items=(60 90 120 144) selected=3 (same model: true,  GTK emitted: 1, ...)
PROBE splice: model refcount 18, n now 2, selected 1
items changed, selection unchanged: items=(50 70) selected=1 (same model: true, GTK emitted: 1, ...)
```

Against the shipped `same model: false, GTK emitted: 2`. So a splice is not merely
leak-free: it emits **half** the `notify::selected` traffic, because `GtkSingleSelection`
carries the selection across a splice instead of resetting it to 0 — which also means the
"never left showing the wrong item for a frame" property becomes true by construction
rather than by the `update`→`reassert` ordering. It skips the popup close and the model
swap as well.

Costs of switching, honestly: the model must be cast back from `List_model.t` to
`String_list.t` (safe here — this library only ever installs a `GtkStringList`, via
`new_from_strings` at create — but it deserves a `Gobject.Type.is_a` guard or a fallback to
replacement rather than a bare `cast`); and the live test's claim changes shape from "the
model is rebuilt only when the items differ" to the stronger and simpler "the model object
is never replaced", so the `same model:` column and the surrounding prose need rewriting.

**This contradicts an explicit ruling, so it is the lead's call, not mine.** Recorded as a
finding because the brief asked whether a reference is actually leaked (it is) and because
the alternative is one call rather than the diff the ruling refused. If the ruling stands,
the current handling — backlog entry with the generator rule spelled out, refcount pinned
in the golden — is the right way to stand it.

### I2 — the level bar's write order *is* observable, and the report says it is not

`src/widgets/w_level_bar.ml:33-44`; `task-10-report.md`, "LevelBar: the write order".

The report states: *"the ordering makes no difference to the final state, and I verified
that rather than assuming it … there is no golden that can distinguish them."* That is
wrong. The shipped golden already distinguishes them.

Mutation: change only the `then` branch of `set_bounds` from `write_max (); write_min ()`
to `write_min (); write_max ()`, so that the one patch whose new minimum exceeds the old
maximum (`live_text.ml:1048`, `0–1` → `2–10`) passes through `min=2 max=1`. Result,
reproduced twice:

```
-|     (children (GtkGizmo (css (high filled))) (GtkGizmo (css (empty)))))))))
+|     (children (GtkGizmo (css (low filled)))  (GtkGizmo (css (empty)))))))))
```

...on `live_text.ml:1050` **and** `:1059` — two patches *after* the one that was
mis-ordered. The numeric props (`value`/`min`/`max`) are indeed identical, which is what
the report checked; GTK's offset CSS class (`low`/`high`/`full`) is not, and the wrong
class persists through subsequent patches. So the transient inverted range is not
transient: it leaves a durable, visible defect in the widget's rendering two frames later.

This is good news for the code — the rule is enforced by a test, which the report says it
cannot be. The problem is the record: a maintainer told the ordering is untestable will
read that golden churn as noise and promote it. Fix is cheap: correct the report and the
paragraph in `w_level_bar.ml:22-32`, and add an explicit line to the live block asserting
the class, so the guard is legible rather than incidental.

### I3 — the level bar's ordinary case is not covered by any live test

`test/live/live_text.ml:1044-1062`.

Every one of the five level-bar patches in the live block changes a bound. The case a real
application spends all its time in — `~value` moving with `~min`/`~max` fixed — is never
patched. Mutation: delete the `Float.( <> ) old.value new_.value` disjunct at
`w_level_bar.ml:89`, keeping only the two bound disjuncts, so a value-only change writes
nothing at all. **Every test in the repository still passes**, live suite included.

That is the widget's whole purpose going unasserted. `test_widgets.ml` only checks the node
sexp, and the gallery smoke run asserts nothing. One more `patch live (bar ~min:0. ~max:5.
~value:4. ())` after `:1061` closes it.

### I4 — an out-of-range `~selected` kills the application, and nothing says so

`vtree/node.ml:640-652`; `src/driver.ml:109-115`.

First, a correction to the review brief's premise: the constructor check *does* catch a
`~selected` that goes out of range because the items shrank. `Node.drop_down` holds both
values and runs on **every** render, so the shrink is caught the moment it happens. That is
the problem, not the reassurance.

`Node.drop_down` raises `Invalid_argument` from inside the Bonsai computation, which runs
inside `frame_body` (`driver.ml:41-43`, `Bonsai_driver.flush` / `result`). `Driver.frame`
catches it, calls `Scheduler.mark_broken`, `Patcher.abandon_fixups`, and re-raises
(`driver.ml:109-115`); every later frame is a silent no-op. **The whole application is dead
and does not repaint again.**

`~items` and `~selected` are not one value. In a real app they come from separate Bonsai
state — a list from a query, an index from a `Bonsai.state` the user's picks feed. Delete
the last row of a four-row list and the index is stale for exactly one frame: the frame
that renders it is the last frame that app ever runs. Every other selection in M2 chose
inert-or-deferred to survive precisely this transient (Tasks 6–8's ghost-key rule); the
drop-down is the one that made it fatal, and the justification given ("it is decidable
here") argues for a diagnostic, not for a kill.

The gallery already pays this tax: `examples/gallery.ml` writes
`~selected:(if List.is_empty scale_names then -1 else scale)` — a guard whose only purpose
is to keep the constructor from raising.

The ruling is the brief's and I am not asking to reverse it. What is missing is that
`node.mli`'s paragraph on the check says "is `Invalid_argument` from this constructor" and
stops, without saying that under `Driver` that ends the process's UI, and without naming
the pattern that avoids it (clamp at the view: `~selected:(Int.min selected (n - 1))`, or
derive the index from the list). One paragraph in `node.mli` plus a sentence in the README
Limitations carry (Task 15) closes it. If the lead would rather soften the check, the
`ctx.report` channel this very task added is the obvious home for it — the `-1` case is
already handled that way.

---

## Minor

**M1 — the "structural, not physical" items test is vacuous.** `test/test_widgets.ml:1041`:

```ocaml
let a = [ "a"; "b" ] in
let b = [ "a"; "b" ] in
print_s [%sexp ((phys_equal a b, Kind.equal_props … ) : bool * bool)];
[%expect {| (true true) |}];
```

The promoted output is `(true true)` — the compiler shares the two structured constants, so
`a` and `b` *are* physically equal and the comparison the comment is about never runs. Use
`List.map [ "a"; "b" ] ~f:Fn.id` or `String.copy` for one of them, and assert
`(false true)`.

**M2 — the case labelled "items changed, selection unchanged" changes the selection.**
`test/live/live_text.ml:853`: the previous node is `~selected:3` and this one is
`~selected:1`. (It has to be — the new list holds two items and the constructor would
reject 3.) The label should say what it does, and the genuine "items change, `~selected`
stays put and stays in range" case is worth a line of its own.

**M3 — the report's mutation table names the wrong literal.** `task-10-report.md`, "The
model-rebuild strategy": *"Replacing `same_items old.items new_.items` with `true`"* under a
column headed "unconditional rebuild". `true` gives the opposite (never rebuild); the
mutation that reproduces the table is `false`, which I ran and which produces exactly the
diff shown. Substance is right, the recipe is not.

**M4 — `Kind.same_kind` now allocates for every `Native` node, every patch.**
`vtree/kind.ml:480` is `String.equal (name a) (name b)`, and `name` at `:458` is
`"Native:" ^ n.name` — two fresh strings per comparison, on every patch of every native
node, where the old matrix compared `a.name` to `b.name` with no allocation. The cost
comment at `:470-478` accounts for the string comparison but not for this. It is small and
the exhaustiveness is worth far more; it should be *written down*, since the comment
currently reads as though the only cost is the compare.

**M5 — parked on a refused `-1`, the drop-down is effectively uncontrolled.**
`w_drop_down.ml:236`. Once `st.refused = Some (-1)`, `reassert` short-circuits before
reading the widget, so a selection the *user* changes afterwards is never corrected and the
already-emitted message's "item %d is still selected" is stale. This is defensible — the
model asked for a state no index satisfies, so there is nothing to snap back *to*, and
`on_selected_changed` still tells the model what happened — but `node.mli`'s "It does not
fight the widget" sentence is the place to say that the prop is not being enforced while
parked, which is not the same as "the frames after it cost nothing".

**M6 — `String_list.get_string` is listed as "not called on a frame path".** It is not
called at all (`git grep` over `src/` and `test/` at `ce6497d` finds only `new_`). Harmless,
but the stub table reads as though it is used somewhere.

**M7 — `Live_tree`'s item read casts the model's objects unchecked.** `src/live_tree.ml`,
`drop_down_items`: `W.String_object.get_string (cast o)`. Sound today (only a
`GtkStringList` is ever installed) and test-only, but it is the one place in the new code
where a wrong model type would be type confusion rather than a `Failure`. The `from_gobject`
idiom used on the way in has no counterpart on the way out; worth a comment saying why the
invariant holds.

---

## What was checked and found correct

Recorded so the next reviewer does not redo it.

- **Controlled `selected` through the real driver.** `expected_text.txt`: `driver, user
  picked 3, before the frame: 3` → `after the frame the refusal armed: 2 (handler saw
  (2 3))` → `one more frame: 2 (handler saw 0 more)`. The declined edit snaps back on a
  frame Bonsai hands back the physically same node, i.e. through `reassert_only`, and the
  correcting write does not feed itself back in.
- **Rebuild inside a patch.** GTK emits `notify::selected` twice (the autoselect reset from
  `set_model`, then the re-apply), both inside `Widget_impl.batch`'s freeze/thaw, both
  inside the patch guard; `reached Bonsai: 0` on every such line, and `after a drain: GTK
  emitted 5 in all, Bonsai heard 0` proves nothing is deferred.
- **Order after a rebuild.** `patcher.ml:591-600`: `update` (model) then `reassert`
  (selection), unconditionally, then `note_interest` → `enqueue_fixups` → `take_report`.
  Same frame on all three paths — mount (`create` calls `reassert` itself, `patcher.ml:380`
  reports after), patch, and `reassert_only` (`patcher.ml:873-876`).
- **The refusal memo** is keyed on the vtree index (`cached.refused : int option`), consulted
  *before* the widget read (`&&` short-circuit at `:236`, so a parked frame pays neither the
  getter nor the freeze/thaw), cleared by every landed write (`select`, `:147`) and by every
  model rebuild (`forget_refusal`, `:291`), and reported exactly once per decision. All four
  properties are pinned by goldens that I broke and re-verified.
- **Idle-frame cost.** `0.00013 ms at 4 items, 0.00013 ms at 1000 items, ratio 0.98`, and
  `0.00013 ms parked on a refused selection, ratio 0.96`, bound 5 — an order of magnitude of
  margin at both ends. Re-measured on this machine: `1.01` and `0.92`.
- **Stub safety, every call, read in `.ocgtk-src`.** `new_from_strings` (floating widget,
  `ref_sink`) safe; `get_model` (transfer-none, `ref_sink` balances the wrapper's unref)
  safe — and the 500-wrapper + `Gc.full_major` regression is the right shape, since this is
  exactly where Task 6's `get_selected_rows` segfaulted; `List_model.get_object`
  (transfer-full, correctly *not* reffed) safe; `String_object.get_string`
  (`caml_copy_string`) safe; `List_model.from_gobject` (type-checked + `g_object_ref`) safe;
  `Level_bar.new_for_interval` (floating, `ref_sink`) safe. `get_selected_item` is broken in
  both ways the report claims — `ml_gobject_val_of_ext` neither refs a transfer-none return
  nor builds an `option` (`wrappers.c:163`), so the `.mli`'s `option` reads a raw pointer
  word as a `Some` payload, and a NULL return `caml_failwith`s instead of answering `None` —
  and is correctly never called. `get_expression` `ref_sink`s a `GtkExpression`, which is not
  a `GObject`; correctly never called.
- **Task 1's carry** (`Events.for_kind` gains `Level_bar`) taken, with a reason. `Kind`
  counts: 35 in both `all_kinds` lists, both `assert`ed against
  `Kind.Variants.descriptions`; `test_placement.ml` 39 → 40.
- **`require_specs` negatives**: six, including the two near misses (`Stack`, `ListBox`) and
  four refused *on* a drop-down, plus two on a level bar.
- **Task 9 carries**: carry 1 taken in both halves the review suggested (`same_kind` via the
  wildcard-free `Kind.name`, `equal_props`'s remaining wildcard guarded by `same_kind` and
  raising); carry 2 noted for Task 15/16 (`Level_bar_mode` is the third undocumented public
  module); the ledger's `ctx.report` note taken, with the parked frames measured as asked.
  Carries 3–6 are text-view-specific and correctly untouched. Task 8's hidden-page
  divergence is left for a later task and recorded as carry 6 — acceptable, it was named as
  one of two candidates and one was taken.
- **Out-of-scope creep**: none. The `Kind` rewrite is a named carry; the `Live_tree` child
  suppression is new but is what makes the drop-down's golden stable.

---

# Re-review — fix round 1 (`b863bb2`, base `ce6497d`)

**Verdict: Approved.** All four Important and all seven Minor are taken, and each one was
re-verified here rather than read. Two new Important, both stale prose introduced by this
round and both one edit; three Minor. Nothing regressed.

`nix develop -c ./scripts/ci.sh` re-run on a clean tree → `all green`, exit 0. Benches
unmoved (`0.00013 ms at 4 items / at 1000 items, ratio 1.00`), as they must be — a splice is
an items-change cost and an idle frame does not reach it. Scope is tight: eleven files, and
`patcher.ml`, `attr.ml`, `events.ml`, `placement.ml`, `registry.ml`, `expected_events.txt`,
`test_events.ml`, `test_placement.ml` and `test/handle/test_handle.ml` are all untouched.

## I1 — the splice: correct on every transition, and the leak is gone

**The arithmetic is right, and right for the reason given.** `position` is `0` and
`n_removals` is `List_model.get_n_items model` — read off the *model*, not off the previous
node — so `position + n_removals = length` exactly, satisfying
`gtk_string_list_splice`'s precondition on every transition. Checked by hand for all five
the brief names, including the two edges: `Array.of_list [] = [||]` has `Wosize_val = 0`, so
the stub builds a one-element NULL-terminated array and GTK adds nothing (non-empty → empty),
and a model spliced to empty is still installed, so the next change splices `0 0 additions`
rather than taking the `None` branch (empty → non-empty). Both run in the existing `-1`
block, which still passes.

**Mutation-checked.** Replacing `n_removals` with the *additions* length — the plausible
version of this bug — is caught loudly in both directions:

```
Gtk-CRITICAL: gtk_string_list_splice: assertion 'position + n_removals <= ...' failed   (grow)
-|items shrank under the selection: items=(50 70)     …
+|items shrank under the selection: items=(50 70 120) …                                  (shrink)
```

The `items=` column read back through the model is what catches it; five criticals and three
wrong item lists.

**The type guard is sound and degrades rather than corrupts.** `g_type_is_a` against a
`lazy` `from_name "GtkStringList"`, forced only from `set_items`, which is only reachable
from `update`, which is only reachable after `create` instantiated a `GtkStringList` — so
the type is registered before the `lazy` is forced. Even if it were not, `from_name` answers
`G_TYPE_INVALID`, `is_a` answers false, and the fallback takes over: correct for any model,
merely leaking. That is the right failure direction for an unchecked downcast.

**The fallback is not dead code that only looks correct.** Forcing it (`when false && …`)
still produces the right items and the right selection on every line — it just replaces the
model and emits two notifications instead of one. So the degradation the comment promises is
real.

**No leak remains on any reachable path.** `create` → `new_from_strings` (model built inside
GTK, no OCaml wrapper, nothing sunk); `update` → splice into the object already installed.
`String_list.new_` is reachable only from the defensive fallback. The backlog entry correctly
stays and is correctly rewritten — the generator defect covers every non-widget `*_new`, so
this library no longer walking into it does not close it.

**The claim is asserted, not merely stated.** "The model object is never replaced" is carried
by the `same model:` column on every line in the block plus
`four items changes later: same model object throughout: true, references 4 -> 4`. Forcing
the fallback turns those into `false` / `false, references 4 -> 5`. The refcount is a
secondary check and the report is right to say so: it is meaningful only because the object
is the same one, and the identity assertion is what carries the weight.

**The selection is carried where GTK carries it and re-applied where it does not.** The
three items-change lines now read: grew with the selection moving → 1 emission; changed with
`~selected` unchanged and in range → **0 emissions, nothing written at all**; shrank under
the selection → 1 emission, the node's index landing. `after a drain: GTK emitted 3 in all,
Bonsai heard 0` accounts for every one of them, and the reentrancy guarantee is unweakened.
The middle line is the strongest in the file and did not exist before.

## I2, I3, I4 — checked by mutation, all now bite

**I2.** The `offsets:` line does what it was added for. Flipping only the `then` branch of
`set_bounds` back to the unsafe order:

```
-|     (children (GtkGizmo (css (high filled))) …        -|offsets: high filled empty
+|     (children (GtkGizmo (css (low filled)))  …        +|offsets: low filled empty
```

— on two patches *after* the mis-ordered one, exactly as before, but now legible on a line of
its own instead of two levels into a sexp. The impl comment, the live block and the report
section all say the damage outlives the call. Correction accepted without reservation; the
report's own account of how the first round got it wrong (checked the properties it chose to
print, not the widget) is the useful part.

**I3.** The value-only patch is added and the mutation is caught:
`(value 4)` → `(value 3)` plus the discrete block row that stops filling. The widget's
principal behaviour is now asserted.

**I4.** `Node.drop_down` raises only for `~selected < -1`. The stale-index rule matches
Tasks 6–8's ghost key on every point: inert while the index names nothing, written and
read back, remembered against the index, reported once with the node's path, cleared by any
items change, re-decided when the index changes, and applied **on the frame** the list grows
(the golden prints `list grew back to include it: selected=2` before the idle frames, not
after). Six golden lines cover both directions plus "wrong again" and "wrong differently".
`node.mli`'s new opening section — what an `Invalid_argument` costs, and *reject only what no
later frame could make valid* — is the right generalisation and the right place for it; the
backlog carry for Task 15 is right too, since a rule that lives only in a report is read once.
The gallery guard is gone, which was the point.

Minors M1–M7 all taken. M1's golden is now `(false true)`, which is what that case was always
trying to say.

## Deviation in this round

**The I3 strengthening. Accepted, with the reason corrected.** Keeping `~mode:Discrete
~inverted:true` fixed so that only the value moves is better than the ruling's literal
`bar ~min:0. ~max:5. ~value:4.`, and it should stay. But the stated reason — that the literal
version "would not have isolated the value" — does not hold: `mode` and `inverted` are not in
`w_level_bar.ml`'s value-write condition, so the literal version would have caught the same
mutation. The real merits are that nothing else moves at all and that the discrete blocks make
the change visible in the dump. See N3.

## Important

### R1 — `update`'s comments still describe the replaced model, and one now says the opposite of the code

`src/widgets/w_drop_down.ml:333` and `:344-345`.

```
(* [selected] is deliberately absent: … including this one, where the model rebuild
   above has just reset the widget's selection to item 0. That ordering is the whole
   reason a rebuild is safe … *)
```

The splice does not reset the selection to item 0. That is the headline result of this round:
`items changed, selection unchanged and still in range … GTK emitted: 0` is a line that exists
*because* the selection is carried across. So the comment a maintainer reads while standing
inside `update` now states the inverse of what `update` does, and it presents the
`update`-then-`reassert` ordering as load-bearing for a mechanism that no longer happens. The
ordering is still needed — for the cases where the content genuinely forces the selection to
move — and that is what the comment should say.

The comment at `:333` is less wrong but still stale: its substance holds (an items change
changes what GTK will accept, so the memo must not outlive it) while its wording — "a
rebuild", "the old model" — describes a replacement that no longer occurs. The parallel
comments elsewhere in the file *were* updated in this round (`already_refused`'s "every model
rebuild" → "every items change", `selected_changed`'s likewise), so these two are an
oversight rather than a decision. This is the same failure mode as I2, in the same file, one
round later.

### R2 — `Bonsai_gtk_test`'s public doc asserts an invariant I4 removed

`test_lib/bonsai_gtk_test.mli:170-171`, mirrored at `bonsai_gtk_test.ml:274`. Neither file was
touched this round.

```
The index is not range-checked either: [Node.drop_down] has already checked the props
this handle is looking at, so what a test can reach here is its own handler's behaviour…
```

`Node.drop_down` no longer checks that, by design. This is published API documentation
telling a reader that the props a headless handle sees are in range by construction, which is
now false — and it is the load-bearing half of the justification for `Set_selected` doing no
range check of its own. (The decision not to range-check is still right; only its stated
reason is gone. The honest reason is the one the `-1` case already uses: headless has no model
to ask, and GTK is what decides.)

Worth fixing together with the gap behind it: a permanently out-of-range `~selected` now
produces **no signal at all** headlessly — the constructor accepts it, `Events` has nothing to
say, and only the live runtime reports it. That is precisely the "a green headless suite does
not mean the runtime will hold the state" asymmetry that `test/handle/test_handle.ml:2139`
already pins, in words, for `-1`. Extending that block with an out-of-range node costs three
lines and puts the second instance of the asymmetry next to the first.

## Minor

**N1 — the mirrored type check is memoised on one side only.** `w_drop_down.ml:60` forces a
module-level `lazy` for `GtkStringList`; `src/live_tree.ml`'s new item read calls
`Gobject.Type.from_name "GtkStringObject"` inside the per-item loop. A `g_type_from_name`
string lookup per item, on a test-only dump — harmless, but the two ends of an invariant that
are deliberately checked independently read better when they are written the same way.

**N2 — an index into an empty list has no live line.** `~items:[] ~selected:0` is now a legal
node (and is the shape a picker renders while its query is still running — `test_widgets.ml`
says exactly that). It reaches a branch of `refusal` no live case does: `live` is `-1`, so the
message reads *"~selected:0 names no item: the list holds 0. … so nothing is selected"*. Both
live cases have a non-empty list, so that wording is unexercised. One patch in the stale-index
block.

**N3 — the round's deviation is justified by a reason that does not hold.** See "Deviation in
this round" above: `mode` and `inverted` do not enter the value-write condition, so the
ruling's literal case would have caught the mutation too. The shipped case is still the better
one; only the argument for it needs correcting, in the report.
