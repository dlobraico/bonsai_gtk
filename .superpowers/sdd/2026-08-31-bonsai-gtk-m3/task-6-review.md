# Task 6 review — Actions and Node.menu (681c5dd..a79981a)

Reviewer ran `nix develop -c ./scripts/ci.sh` once at `a79981a`: exit 0, tail
`== example smoke` … `all green`. One forced re-run of the whole live suite
(`BONSAI_GTK_LIVE_TESTS=1 xvfb-run -a dune build @test/live/runtest --force`)
also passed — consistent with the report's 10/10 claim, not a re-measurement of it.

## Verdict

**APPROVED after one fix round.** The design is what the plan asked for, the
deviations are each argued and (four of five) verified sound, the mandatory
Task 5 carry is genuinely proven by real input, and the controlled-prop story is
pinned against GAction read-backs. One Important: a doc-comment behaviour claim
(the item-tracker workaround) that no test exercises and that names the wrong
code path. Everything else is Minor.

## What was verified (the brief's nine points)

1. **Lifetime and dispose — traced clean.** The four `Patcher.live` points all
   present: `Actions.create`+`update` in `mount` (src/patcher.ml:192-198, before
   the caller parents the widget — pre-flight 1 met by construction, and the
   in-code comment says exactly why), `update` in `patch` (:496), `clear` in
   `disarm` (:409), `release` in `destroy` (:384) and in `mount`'s `unwind`
   (:162). `forget_menu` is release_kind's new arm (:75-77), placed above the
   or-pattern chain, and `destroy` runs release_kind before the caller removes
   or destroys the widget — so the internal-popover repair is disconnected while
   the popover is still alive. The freed-handle question: it cannot fire against
   freed memory on any path — `Signals.connected` stores the coerced wrapper
   (src/signals.ml:20), whose GObject ref keeps the popover's C object (and its
   handler table) alive until the disconnect. Paths traced: menu edit in place
   (same model, repair survives — correct), menu→None, menu appearing,
   cross-frame ~popover→~menu and ~menu→~popover (impl.update runs before the
   slot patch, so the orders work out), destroy-with-open-popover (unparent may
   emit `closed` before forget_menu; the repair then runs its predicate against
   a rootless popover and returns — benign, and the repair is deliberately
   self-guarded, w_menu_button.ml:44-66). One ordering nit is Minor 2 below.
   The slot guard (`set_popover None` skipped while a model is present,
   w_menu_button.ml:244-254) is right and is actually load-bearing at mount
   (the always-empty slot beside `~menu`).

2. **Controlled props — pinned against the read-backs.** `sync_surviving`
   compares `Gio.Action.get_enabled`/`get_state` through `from_gobject` and
   writes only on difference; a `None` state read-back counts as "differs"
   (repairing write). Activation never touches state — the trampoline only
   schedules. Golden mapping (expected_menus.txt): dump shows `dark … state
   false` before AND after `activate app.dark resolves: true` +
   `dark-requested (model holds false)` — the declined checkmark standing
   still; `state true` appears only after the model's patch; `ping (enabled
   false)` only after the enabled patch; `app.nope` resolves `false`. **State
   TYPE mismatch: unrepresentable, not rejected.** Shape (Simple/Toggle/Radio)
   is stored per action and a same-name shape change rebuilds the GTK action in
   the survivor diff (actions.ml `update`), so `sync_surviving` can never read
   a wrong-typed variant; there is no rejection message because parameter type
   and statefulness are construction-time and the runtime owns the object. The
   radio trampoline's no-parameter arm is inert per the trampoline rule, with
   the unreachability argued in place.

3. **Resolution — one function, one string, four shapes.**
   `vtree/action_resolution.ml` threads the scope environment down (self added
   before the node's own references are checked — self resolves; siblings never
   enter the env). Called from both patcher wrappers (patcher.ml:741-749, :773)
   and from `Bonsai_gtk_test.check_frame` (test_lib :277-283, same position
   relative to the other checks as the runtime's). test_menu.ml pins
   self/ancestor/absent/sibling, the radio's `::target` stripping, and both
   constructor rejections; test_handle pins the handle-side raise with the
   quoted string. **Across-frames: raise, not heal** — the patch wrapper checks
   every changed frame, so a menu naming "x" before the `Attr.actions` carrying
   "x" arrives dies on that frame. That is what the plan and the plan-time
   ruling of record ("menu/shortcut names that resolve to nothing raise at
   fixup") asked for. Note the tension with node.mli's "reject only what no
   later frame could make valid" — the ledger ruling settled it the strict way;
   flagging only so the controller knows it was seen, not contested.

4. **Wrapper-not-fixup deviation — holds.** The argued equivalence is real
   because a menu's referents are confined to the root-to-node path, which a
   top-down walk over the tree-as-data has in hand at wrapper time; the
   transient_for/stack-registry precedent needed fixups because those names
   resolve against a registry of referents *anywhere* in the tree, populated
   during the walk itself. No mount-order counterexample exists for
   ancestor-only references. The "reassert frames skip it" claim is true:
   driver.ml:89-90 routes phys-equal roots to `Patcher.reassert_only`, which
   never enters the wrapper. Kind-change remounts are subtrees of the checked
   tree (inner `mount` carries no check — correct, it would be redundant).

5. **`activate_action_variant` deviation — fact-checked, holds.** The pin's
   Widget module binds `activate_action_variant : t -> string -> Gvariant.t
   option -> bool` and has **no** `get_action_group` (GTK3-only API; grep over
   the merged-cycle widget mlis confirms). The replacement goes through GTK's
   muxer resolution from the widget through ancestors — the same walk a menu
   item's activation takes from one hop further down — and the true item path
   is separately exercised by live_input's real click. The report's claim that
   it is the stronger probe is right.

6. **The carry — proven.** live_input.ml's new block: real click on `menu2`
   opens the *internal* PopoverMenu (`get_popover` on the button — GTK's own,
   no Node.popover), `menu item sensitive (the tracker bound): true` pins
   pre-flight 1's good half, a real click on the found GtkModelButton fires the
   handler through GTK's menu machinery (`(picked)`), `mapped after
   activation: false`, stranding probe `false` using the repair's exact
   predicate *with* the task-5 same-widget check (`Gobject.same f
   internal_popover || is_ancestor`), and `(capture F1 mods=none)` afterwards.
   The repair connection is confirmed to be the internal popover's `closed`
   (`W.Popover.on_closed` on `get_popover`'s result inside `set_menu`, stored
   beside the model handle in the ephemeron entry — not the spec list, which
   cannot reach a popover w_popover never mounted). No idle fallback was
   needed, and the golden is the evidence. Stability: my one forced re-run
   passed.

7. **Down+Return residual — measured, stated, but not yet where Task 13 will
   find it.** The live_input comment records the measurement (Down+Return with
   pumps moved nothing; same session's Escape worked) and the mechanism claim
   (the toplevel dismisses its own grab for Escape; popup surfaces never get X
   focus WM-less). The reasoning is consistent with the goldens (F1 reaches
   the window capture handler before and after, so keys do reach the toplevel;
   they die only en route to the popup's focus). I cannot refute the causal
   story without new experiments and it is presented as measurement, which is
   honest. But the report's "Task 13 should record it beside [the M2 README
   residual]" lives only in the report — see Minor 4.

8. **`Events.is_actions_attr` — honest, one framing gap.** `is_event` true
   (it carries handlers), `attr_phase` gained the `Actions _ -> None` row,
   the gallery sweep table gained `Actions -> Some "Activate_action"`,
   `is_supported` and `require_slots` skip through the one-constructor
   carve-out. The partition test still covers all names — but see Minor 3 on
   its comment now mischaracterizing the `(Actions)` golden.

9. **ci.sh** at a79981a: exit 0, `all green` (log tail: example smoke — the
   three examples each held their 3 s timeout). Live-rule counts in ci.sh and
   the dune header updated 12/15 → 13/16; the live_menus rule carries
   `(locks x-display)` (it presents a toplevel).

**Consumer mapping** (design brief): `id`→`name`, `label`/`accel`→`Menu.Item`
(accel display-only, stavekeeper's key-truth rule adopted verbatim),
`enabled`→`enabled` (ownership deliberately inverted, documented), `run`→the
effect (and stavekeeper's own `run` activates the GAction, which is exactly
what a live activation does here). `scope` lands on `Attr.actions ~scope` —
but the mli's field-for-field sentence never says so; see Minor 1.

## Findings

### Important

**I1. The item-tracker workaround is a doc claim no test exercises, and it
names the wrong mechanism.** `Attr.actions`'s mli caveat ends: "Changing the
menu (any [Menu.equal]-visible change) rebuilds the model and re-binds", and
the report repeats it ("the workaround … falls out of the design"). But a
Menu.equal change on a button that *already has* a menu takes w_menu_button's
`Some entry` arm — `remove_all` + re-fill on the same GMenu, **no
`set_menu_model`** — precisely so the open popover and the repair connection
survive. The internal PopoverMenu was built before the late group existed, so
per the caveat's own logic its tracker never bound; whether items-changed row
recreation re-queries the muxer and picks the late group up was measured by
nobody (pre-flight 1 measured post-rooting insertion never binding; pre-flight
9 measured remove_all-while-open crash-safety, not re-binding). Only a menu
*appearing* (None→Some, the `None -> set_menu` arm) demonstrably re-sets the
model. Pre-flight 1's either/or was "force a re-set, or document **and test**
the limitation" — the limitation's activation half is tested (live_menus block
2), the workaround half is not. Fix: either a small live block (mount without
the attr, patch it in, then patch a Menu.equal-visible edit, probe
`get_sensitive` on the rebuilt item) that turns the sentence into a fact — or
temper the mli to the mechanism that is actually built ("a menu appearing
re-sets the model and re-binds; an edit to an existing menu rebuilds items in
place on the same model, which has not been measured to re-bind").

### Minor

**M1. The field-for-field mapping omits `scope` (and label/accel).**
action_spec.mli quotes stavekeeper's six-field record and maps three fields
explicitly. `scope` maps onto `Attr.actions ~scope` and label/accel onto
`Menu.Item`; one sentence closes the gap in a doc whose whole point is that
the mapping is total.

**M2. w_menu_button update, menu Some→None: `set_menu_model mb None` runs
before `Menus.remove w`.** Every other path (set_menu, forget_menu)
disconnects the repair *before* GTK can tear the popover down; this one leaves
the handler connected across the popdown/teardown the model clear provokes.
Benign today (the wrapper ref makes the disconnect safe and the repair is
self-guarded and idempotent), but swapping the two lines makes the discipline
uniform and the window zero.

**M3. test_events' partition-test comment now mislabels its golden.** The
comment says an emitted-by-nobody event name is "legal only until the widget
that emits it lands", and explains why controller attrs are excluded *by
design*. `Actions` is the controller attrs' case (permanently no one's
signal), yet it lands in the printed golden under the pending-widget rubric.
Exclude it via `is_actions_attr` beside `is_controller_attr` (with the same
one-line reason), or extend the comment; as landed, `(Actions)` reads as
unfinished work.

**M4. The Down+Return residual has no ledger/backlog carrier.** The
measurement lives in a live_input comment and the report says Task 13 should
record it beside the M2 input residual — but no ledger carry or backlog line
exists for Task 13 to sweep. Controller: add it to the Task 6 ledger entry as
a named carry.

**M5. Same-scope shadowing edge in the resolution walk (unmeasured).** The
env is a union: a node with `Attr.actions ~scope:"app" [y]` under an ancestor
with `~scope:"app" [x]` certifies a menu naming `"app.x"` on the descendant.
If GTK's action muxer resolves prefix-first (nearest group registered under
"app" wins and a miss inside it does not fall through to the ancestor's
"app"), that menu item greys out — the exact gap the module header says the
check closes. I could not verify GTK's fall-through behaviour from the pin
(the muxer is internal C). A throwaway measurement, or a documented
same-scope-on-an-ancestor-path caveat, would settle it. Obscure shape; not
blocking.

### Out-of-scope (backlog, per the review protocol)

- Menubar (`set_menubar`/PopoverMenuBar) — already on the fork-round-3 list.
- `Clipboard`-style read of `enabled` from GTK — deliberate inversion,
  documented; nothing to do.
- No live tree puts `Attr.actions` on the menu button *itself* (all three live
  trees scope on an ancestor). Pre-flight 1's "every ordering tested" covers
  the model-before-group create order, so this is an observation, not a gap
  demanding a test.
- The ~selected/list-pair functorisation standing trigger is untouched by this
  task (no new copy introduced).

## Evidence pointers

- src/patcher.ml:192-198 (mount ordering), :384, :409, :741-749, :773
- src/actions.ml (survivor diff, shape rebuild, sync_surviving read-backs)
- src/widgets/w_menu_button.ml:70-165 (Menus table, set_menu, forget_menu),
  :210-231 (rebuild arms — I1's subject), :244-254 (slot guard)
- vtree/action_resolution.ml; test/test_menu.ml (four shapes + rejections)
- test/live/live_input.ml new block + expected_input.txt lines 33-39 (carry)
- test/live/expected_menus.txt (declined checkmark, next-frame write, enabled,
  unresolved name, late-attr activation half)
- Pin fact-check: event_controller_and__…__widget.mli:864, :1611 —
  insert_action_group and activate_action_variant bound; no get_action_group.

# Re-review (fix round 1) — bc0adc6

Scoped to the five findings. Live alias run once at `bc0adc6`: exit 0; headless
`@test/runtest @fmt` also 0.

**I1 — CLOSED, by measurement rather than by tempering.** The new live_menus
rebind block exercises exactly the contested path: the menu exists from mount
(so `Menus.find` holds the entry), the late group arrives on the already-rooted
window in the same patch as a `Menu.equal`-visible edit, which takes the
`Some entry` arm — `remove_all` + refill on the *same* GMenu, no
`set_menu_model` — and the probe (popup, walk to the labelled GtkModelButtons,
`get_sensitive`) answers `item Y sensitive=true`. The full-re-set control
(menu `None` for a frame, then back — fresh `set_menu_model`) agrees, and the
mount-time item is the baseline control. So the mli's untouched sentence is now
a measured fact, which is the stronger resolution of the either/or I offered.
One honest note on the golden's discrimination: after `remove_all` every row is
rebuilt, so "rows built before the late group" exist only in the baseline probe
— but that is the point, and it is also why the limitation is nearly
unreachable through the vtree at all: the resolution walk means a menu can
never name a scope before the frame its `Attr.actions` arrives, and in that
frame the top-down patch inserts the group (window first) before the button's
rows rebuild. Wording nuance, not blocking: the edit rebuilds the model's
*contents*, not the model — the mli's "rebuilds the model" is loose by one
word, and the measurement makes it harmless.

**M5 — CLOSED, the union vindicated.** The shadowing block puts `app:[x]` on an
ancestor and `app:[y]` on a descendant and probes from the leaf through
`activate_action_variant` — GTK's own walk: `app.y` true and `app.x` true, so
the muxer falls through same-named prefixes and the walk's union env matches
GTK. The action_resolution.ml comment now states this and cites the golden.

**M1 — CLOSED.** action_spec.mli maps all six fields: `scope` →
`Attr.actions`' `~scope`, `label`/`accel` → `Menu.Item` (accel display-only,
stavekeeper's rule), beside the original three.

**M2 — CLOSED.** Menu Some→None now disconnects the repair before
`set_menu_model None`, with the rule stated in place ("repair first, model
second"); the rebind block's `Absent` frame exercises the reordered path live.

**M3 — CLOSED.** `Actions` is excluded from the partition's emitted-by-nobody
filter through `is_actions_attr`, the golden is back to `()`, and the comment
names the identical by-design reason.

M4 (the Down+Return ledger carry) is the controller's ledger edit, not this
diff's — still owed there.

**Verdict: APPROVED.**
