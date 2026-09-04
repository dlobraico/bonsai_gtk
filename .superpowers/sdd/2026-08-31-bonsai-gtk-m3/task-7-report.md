# Task 7 report — Attr.shortcut: a fourth controller family

Branch `m3`, commits `92e5184..e4076ae`: the headless half (`8c422b4`) and the
live half (`e4076ae`). `nix develop -c ./scripts/ci.sh`: **all green** at
`e4076ae`; live_input + the new shortcut suite forced re-runs 10/10.

## What changed

**`8c422b4` — the vtree and the family.**
- `vtree/trigger.ml`: `{ key : int; modifiers : Modifiers.t }`, sexp/equal/compare,
  and `to_label` (GTK accelerator spelling, display-only). No GTK parse syntax
  enters the vtree, and the runtime builds `Keyval_trigger.new_` from this data —
  `Shortcut_trigger.parse_string` (pre-flight 7's NULL wrap) is never called.
- **`Attr.shortcut ?phase ~trigger ~action ()` is repeatable**: `Attrs.of_list`
  merges every call on one node into a single keyed `Shortcut` entry (the
  css-class accumulation, keyed — a new `Attr.merge_shortcuts` internal makes the
  private-type merge possible), so all of a node's shortcuts share its one
  `GtkShortcutController` and the phase machinery sees them together. The attr is
  **fully structural** — an action is a name, not a closure — so an unchanged
  frame diffs to nothing, alone among the event attrs. A `"::target"` is rejected
  at the constructor: `GtkNamedAction` passes no parameter, so a radio cannot be
  fired by a shortcut (the mli tells the caller to wrap it in a `Simple`).
- **The Task 2 carry honoured with a refactor**: `Events.attr_phase` became
  `attr_phases : Attr.t -> Phase.t list` — a repeatable attr carries one phase per
  entry, which an option could not say — exhaustive with no wildcard, and
  `family_phases` concat-maps. The Key family's message text is unchanged
  (goldens hold); the Shortcut disagreement message reads
  `Attr.shortcut asks for Capture and Attr.shortcut for Bubble, but they share one
  GtkShortcutController and so one propagation phase` — the same attr name on both
  sides, correctly, because the entries live under one name.
- **`Events.Family.Shortcut`**: the enumerate-driven matches (`controller_family`,
  `controller_class`, `Controllers`' `attached`/`update`/`release`/counts, the
  test partitions) were each a compile error until answered — the M2 design paying
  off exactly as the plan predicted.
- **The family has no slot and no trampoline** (the design's point): firing goes
  GTK → `GtkNamedAction` → the `Actions` group's activate trampoline, which
  already obeys the five rules. `Controllers` keeps a
  `((Trigger.t * string) * Shortcut.t) list` because `remove_shortcut` needs the
  very object added; sync is attach-on-first / diff-by-pair / detach-on-last, with
  the phase re-applied from the attrs and `family_phase_rejection` refusing a
  disagreement. `armed` reports `Shortcut` from the family's own state (no slots
  to ask). Exact duplicate entries collapse to one installed shortcut. Scope stays
  GTK's `LOCAL` default, per the attr's documented rule.
- **Resolution reuses Task 6's one function**: a shortcut's action joins
  `node_references`, so the walk — and its exact message — covers menus and
  shortcuts alike, runtime and headless (pinned).
- `Keyval` gains the seven chord punctuations (comma, question, grave, both
  brackets, minus, equal), named so a chord table reads as prose; the table stays
  curated per the backlog's rule.
- `Bonsai_gtk_test.Fire_shortcut (id, trigger)`: the trigger resolves on the
  node's shortcut attrs, the named action on the node or an ancestor (the muxer
  union Task 6 measured), pure table lookups, with M2's no-routing honesty
  paragraph in the mli; radios fail loudly.

**`e4076ae` — the live half.**
- `live_controllers_shortcut.ml` (new; unlocked — no toplevel, the click file's
  arrangement, with the dune census updated): attach/detach, the diff leaving one
  survivor + one arrival, phase moved to CAPTURE on patch, `armed=(Shortcut)`,
  and the count from **GTK's own `get_n_items`** (the controller is a
  `GListModel`) rather than this library's bookkeeping; plus the
  duplicate-collapse golden.
- `live_keyvals` pins the seven new constants against `Gdk_constants`.
- The click file's every-controller-attr sweep gains the `Shortcut` row (its
  assertion against `filter Name.all is_controller_attr` forced it), with the
  actions attr riding on the sweep node so the mount wrapper's resolution walk
  accepts the row — inert beside every other row's attr, stated in the comment.
- **`live_input`: the chord, end to end** — the case stavekeeper's `arm_keys`
  ordering dance exists for. With entry 1 focused, a real XTEST
  `keydown ctrl; key k; keyup ctrl` fires the window's capture-phase shortcut
  through GTK's whole routing into the named action's handler. The golden's three
  lines are the proof: the `Control_L` press reaching the key controllers, then
  `chord` — and **no `capture k` line and an unchanged entry text**, because the
  window's capture shortcut consumed the `k` before the entry's `GtkText` or even
  the box's own capture-phase key handler saw it. Declarative `arm_keys`.

## Verification clause

`Events.Family.all` enumerates four families (the derive did it; the partition
goldens moved and were promoted deliberately), and `live_events`' 
no-impl-declares-a-controller-attr sweep holds — no impl declares `Shortcut`, and
the click sweep's new row proves the family attaches from the attr alone.

## Deviations from the plan

1. **The repeatable-attr mechanics are keyed accumulation, not css-class-style
   side storage**: one `Shortcut of shortcut list` entry under one `Attr.Name`,
   merged by `Attrs.of_list`. This keeps `family_phase_rejection`, `Attrs.find`,
   and the diff machinery uniform — the alternative (a separate `shortcuts` field
   on `Attrs.t`) would have needed parallel plumbing in every consumer. The plan
   named the css-class precedent for *repeatability*, which this preserves.
2. **`attr_phase` → `attr_phases`** — forced by (1) plus the Task 2 carry: an
   option cannot carry a repeatable attr's phases, and a wildcard was forbidden.
3. **The `"::target"` constructor rejection** is machinery the plan did not name:
   without it, a shortcut naming a radio would be silently inert live (GTK refuses
   a parameterless activation of a parameterised action) — the exact
   silent-inertness the diagnostics exist to prevent. The mli documents the
   wrap-it-in-a-Simple recipe.
4. **Exact duplicate shortcut entries collapse** (deduped before install) — two
   identical entries would be one diff key anyway. What the live golden pins is the
   {i count} (GTK's `get_n_items` reads 1); that GTK would otherwise have run the
   action twice per press is inferred, not measured. [Fix round 1 note: distinct
   actions on one trigger are now rejected outright — see I1.]
5. The sweep node in `live_controllers_click` now carries a constant
   `Attr.actions` beside each row's attr — required for the Shortcut row to pass
   the resolution walk, inert for every other row (stated in the comment; the
   goldens confirm the `attached=` lists unchanged).

## Deliberately left undone

- `Shortcut_controller.set_scope` (`GTK_SHORTCUT_SCOPE_MANAGED`/`GLOBAL`) — the
  attr's scope is deliberately local; a managed-scope story belongs with a real
  consumer.
- Modelling who-sees-the-chord-first headlessly — impossible and documented
  (`Fire_shortcut`'s mli); `live_input` is where phase is real.
- Chord *display* in menus is already Task 6's (`Menu.Item.accel` +
  `Trigger.to_label` compose; nothing more to build).

## ci.sh tail

```
== example smoke
(counter, gallery, embed each held for their 3 s timeout)
all green
```

Full gate at `e4076ae`; 10/10 forced re-runs of live_input + the shortcut suite.

## Fix round 1

One commit, `c0532f8`; ci.sh all green; live_input forced re-runs 10/10.

- **I1(a)**: one trigger naming two different actions on one node is rejected
  beside the phase doctrine — `Events.shortcut_conflict_rejection`, one string
  from `Controllers.sync_shortcuts` and the handle's walk, naming the trigger's
  label and both actions; same trigger + same action stays legal (and still
  collapses to one installed shortcut). Pinned headlessly, both directions.
- **I1(b)**: the controller's shortcut list is **rebuilt in the stable
  (trigger, action) sort on any change** — the list order is the match order, so
  first-match is a function of the frame's content, never patch history — and
  `Fire_shortcut` matches in the same sorted order (with (a) in force, the sort
  is belt-and-braces within a node, stated in its comment). The attr documents
  the rule. Cross-node contention is GTK's routing, deterministic by phase and
  tree position, **pinned live**: an inner same-trigger capture shortcut exists
  through the whole chord block and fires zero times while the window's wins.
- **I2**: the resolution walk carries spec kinds and **refuses a shortcut
  resolving to a Radio** with the feasible-but-unshipped wording; a menu item
  naming the same radio stays legal. Both pinned headlessly with the walk's
  strings.
- **I3**: every "cannot at all" claim reworded — targeted shortcuts are feasible
  (`Shortcut.set_arguments` is bound) and deliberately unshipped; the backlog
  entry is in `docs/m2-backlog.md`'s "Recorded during M3" with the exact
  removals shipping them requires (both rejections, plus the argument in
  `make_shortcut`).
- **Minors**: the shared resolution string's noun generalized to
  `action reference` (one string, all callers, both sources — goldens moved
  deliberately); **the disabled-action chord measured, and the answer is
  FALL-THROUGH**: the shortcut does not consume the key, which continues to the
  capture-phase key handlers and the focused widget (the golden shows
  `capture g mods=control` and `entry1 g`; the entry's text stays clean only
  because Ctrl+g is not printable input) — the attr doc states the measured
  behaviour and its consequence (disabling the action re-opens the key's normal
  routing, which is what stavekeeper's `text_input_active` arms want; a chord
  that must go dead needs the handler side to say so); `set_scope LOCAL` written
  explicitly with the contract-not-default comment; the duplicate-collapse
  sentence above tempered in place; **trigger.mli's absence** is deliberate on
  the named precedent — `key_response.ml`, `click_response.ml` and `position.ml`
  are ml-only vtree data modules with doc comments in the ml, and `Trigger` is
  their shape exactly.
