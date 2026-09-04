# Task 7 review — Attr.shortcut, the fourth controller family

Reviewer: m3-review7 (this file). Diff reviewed: `92e5184..e4076ae` (8c422b4 headless,
e4076ae live), against the plan's "### Task 7", "Global Constraints", pre-flight
correction 7, the ledger (Task 2's exhaustive-attr_phase carry, Task 6's
one-function-one-string ruling), and the consumer shape at
`~/src/stavekeeper/lib/stavekeeper_app/shell.ml:576-652`.

**Verdict: fix round needed.** The architecture is right and well-proven — the keyed
accumulation, the no-slot/no-trampoline family, the attr_phases migration, and the live
capture-vs-entry chord are all sound and the evidence is real. But one deviation's factual
justification is wrong (the binding *can* pass a shortcut parameter), one silent-inertness
hole the deviation claims to close is still open (a radio named without `::`), and
same-trigger/different-action ordering is nondeterministic across patch history and
disagrees between headless and live.

## Verification of the report's claims

- `nix develop -c ./scripts/ci.sh` at `e4076ae`: **exit 0, "all green"** (tail recorded in
  my run log; ends `== example smoke` → `all green`). One additional forced full live run
  (`BONSAI_GTK_LIVE_TESTS=1 xvfb-run -a dune build @test/live/runtest --force`): exit 0.
  The report's 10/10 forced re-runs were not re-executed; one forced run confirmed.
- `Shortcut_trigger.parse_string` appears only in comments; the runtime builds
  `Keyval_trigger.new_` from vtree data via `gdk_of_modifiers`
  (`src/controllers.ml` `make_shortcut`, `src/gtk_import.ml`). Confirmed.
- The seven punctuations (comma, question, grave, both brackets, minus, equal) are
  correct ASCII keysyms and live-pinned against `Gdk_constants` in `live_keyvals.ml`.
- attr_phase → attr_phases: internal to `vtree/events.ml` (never in the mli, no external
  callers), exhaustive with no wildcard — the Task 2 carry honoured. No existing
  key-family golden changed anywhere in the diff, so the Key message is byte-identical.
  The Shortcut disagreement message is pinned in `test_handle.ml` with `Attr.shortcut` on
  both sides.
- Partition/family coverage: `test_events.ml`'s is_event and controller-attr goldens grew
  `Shortcut`; `live_controllers_click.ml`'s sweep gained the `Shortcut` row
  (`attached=(bonsai_gtk.shortcut)`) with the ride-along `Attr.actions` inert beside every
  other row (the `attached=` lists are unchanged); `Family.all` is derived by enumerate
  and every consumer match was forced (controller_family, controller_class, update,
  release, attached_count all have explicit Shortcut arms).
- The live chord proof is genuine and strong: the shortcut is `~phase:Capture` on the
  window; the golden shows `capture Control_L` (the box's *ancestor-level* capture key
  handler saw the ctrl press) and `entry1 Control_L`, then `chord` — and **no `capture k`
  line**, so the window's shortcut consumed the `k` before even the box's capture-phase
  key controller, let alone the entry's GtkText; `entry 1 text after the chord: "x"`
  pins the entry unchanged. Phase is explicitly set at attach (every entry carries a
  phase, so `family_phase` is always `Some` when any shortcut exists). Scope is GTK's
  default (see Minor 3).
- Teardown: `Controllers.release` detaches the controller and nulls the state;
  `Controllers.clear` is a deliberate no-op for the family (no slots), and the
  pre-unparent `disarm` walk clears the **Actions** slots — the family's only handler
  path — in the same pass, with the activate trampoline's `in_patch` check
  (`src/actions.ml:62`) *dropping* (not deferring) anything that fires during a patch.
  The mount-failure `unwind` also releases. I found no path that leaves a dead controller
  attached.
- Structural diffing: the shortcut record is `{trigger = {key:int; modifiers}; phase;
  action:string}` — handler-free data throughout; `Attrs.diff` of two identical
  multi-shortcut frames is pinned to `()` in `test_menu.ml`. On patches where the entry
  is unchanged, `sync_shortcuts` computes keep=all/drop=[]/added=[] — no GTK mutation
  (phase is rewritten, harmlessly).
- Exact-duplicate collapse: `Attrs.of_list` keeps both entries in the merged list (the
  sexp shows both); `wanted_shortcuts` dedups before install; pinned live
  (`exact duplicate collapsed: … shortcuts=1`).

## Important

**1. Same-trigger/different-action ordering is nondeterministic across patch history,
undocumented, unpinned, and headless disagrees with live.**
`wanted_shortcuts` (`src/controllers.ml`) uses `List.dedup_and_sort` keyed on
`(trigger, action)`, so a fresh mount installs shortcuts in *compare* order, not the
order the caller wrote. The patch arm then sets `f.installed <- keep @ added`, so after a
drop-and-re-add the controller's GTK order differs from what the same final vtree would
get on a fresh mount. GTK's shortcut controller fires the first matching shortcut in list
order, so for two entries with the *same trigger and different actions* (legal — nothing
rejects it) the winner is: lexicographically-least action on mount, patch-history-
dependent afterwards. Headless `Fire_shortcut` meanwhile takes `List.find` over the
vtree-ordered list — a third answer. The live comment ("first-match-wins being GTK's
business") glosses over the library scrambling the order the caller gave, and the
report's "Pinned live" in deviation 4 covers only the duplicate collapse — the
distinct-action case is pinned nowhere. `vtree/events.ml`'s own doctrine for the phase
vote applies verbatim: "picking either silently gives one of them behaviour its author
did not ask for — so it is a rejection". Fix: reject same-trigger-different-action
entries on one node at merge/sync (my recommendation), or else preserve add-order
deterministically end to end (stable dedup, order-preserving patch), pin the winner
live, and make `Fire_shortcut` agree.

**2. A shortcut naming a radio *without* `::target` is still silently inert live — the
exact hole deviation 3 claims to close.** The constructor rejects only the `"::"`
spelling. `Attr.shortcut ~action:"app.theme"` where `app.theme` is a `Radio` passes the
constructor, and `Action_resolution.check` resolves it (the env carries names only —
`node_actions` drops the spec kinds), so mount certifies a chord that live activation
refuses (parameterless activation of a parameterised action — the report's own words),
leaving at most a GLib warning. Headless `Fire_shortcut` is loud, but only for an app
with a headless test on that chord; the walk runs on every mount/patch and has (one field
away) the spec kinds to refuse this always. Fix: carry the kind (or an is-radio bit) in
the walk's env and refuse a shortcut reference that resolves to a radio, same message
discipline as the rest.

**3. The `"::target"` rejection's stated rationale is factually wrong: ocgtk *can* carry
a parameter through a shortcut.** `.ocgtk-src/ocgtk/src/gtk/generated/shortcut.mli` binds
`set_arguments : t -> Gvariant.t option -> unit` (and `get_arguments`); GTK's
`GtkShortcut.arguments` is precisely the mechanism by which a `GtkNamedAction` activation
receives a parameter (the shortcut passes its arguments to
`gtk_widget_activate_action_variant`), and `Gvariant.of_string` exists per the fact
table. So the mli's "a Radio cannot be fired by a shortcut at all", the constructor
message's "GtkNamedAction … passes no parameter", and the report's "the binding's only
option" are all over-broad. The *rejection itself* can stand as M3 scoping (no GVariant
in the vtree is a defensible line), but per the review protocol the foreclosed feature is
a backlog/fork-round item, not an impossibility: re-word the mli, the constructor
message, and the comments to "not plumbed in M3" rather than "cannot", and file the
targeted-shortcut (set_arguments) item so Task 13's backlog carries it as feasible.

## Minor

1. **The resolution message calls a shortcut a menu item.** `action_resolution.ml`'s one
   string is `"… menu item action %S resolves to no Attr.actions …"`, and the new
   `test_menu.ml` golden shows exactly that raised for a chord typo on a label with no
   menu anywhere. Task 6's one-function-one-string ruling is honoured, but the ruling
   fixed the *sharing*, not this noun — "action reference %S" keeps one string and stops
   misdirecting the chord author.
2. **A disabled action's chord is unpinned, and the half that matters is unmeasured.**
   Nothing (live or headless) exercises `Action_spec.simple ~enabled:false` behind a
   shortcut. That the handler won't run is GTK's guarantee; whether the chord is
   *consumed* (swallowed doing nothing) or *falls through* to the key controllers below
   is unmeasured — and stavekeeper's controller this family replaces treats
   swallow-without-acting as a bug of record (shell.ml:625-648, "an unclaimed key must
   fall through", review M2). Headless `Fire_shortcut` ignores `enabled` — consistent
   with the pre-existing `Activate_action`, so acceptable for now, but the live
   consume-vs-fall-through answer should be pinned before the consumer port leans on
   enabled-gated chords.
3. **Scope is GTK's default rather than set.** Phase is explicitly written at attach; the
   LOCAL scope the mli documents is GTK's (documented) default, never written. One
   `set_scope … `LOCAL` at attach would make the documented contract the code's doing
   rather than GTK's, matching the "not by luck" standard the phase handling meets.
4. **Report wording:** deviation 4's "distinct actions on one trigger remain two
   shortcuts with GTK's first-match semantics. Pinned live." — only the exact-duplicate
   collapse is pinned; the distinct-action case has no pin (see Important 1).
5. **Cross-node collisions undocumented.** Two *different* nodes carrying the same
   trigger resolve by GTK propagation (capture: outermost first; bubble: innermost
   first), deterministically, with nothing reporting the collision — consistent with the
   key attrs, but the mli's scope paragraph is one sentence short of saying so.
6. **`vtree/trigger.mli` was not created** though the plan's file list says
   `trigger.ml(i)`. The ml-only shape follows the `phase.ml`/`key_event.ml` precedent and
   the record is deliberately fully exposed, but the deviation is undeclared in the
   report.

## Out of scope (backlog)

- The consumer's conditional chords (`on_library`, `text_input_active`, the
  Escape/Ctrl+Return fall-through arms in shell.ml:601-648) need an enabled-state story
  (per-frame `Action_spec.enabled` recomputation) plus the Minor-2 answer before the
  stavekeeper port; nothing in M3's task text owes this, but Task 13's backlog should
  name it next to the targeted-shortcut item from Important 3.
- The gallery-tree vs `examples/gallery.ml` drift (Task 2 carry, Task 12) grows by one
  attr with the gallery's new chord; already covered by the standing carry.

## Deviation rulings requested by the task

1. Keyed accumulation into one `Shortcut of shortcut list` entry: **accepted** — it keeps
   `family_phase_rejection`, `Attrs.find`, and the diff machinery uniform, order is
   preserved at the vtree level, and the entry is handler-free data (diff-to-nothing
   pinned). Important 1 attaches to what `Controllers` then does with the order.
2. `attr_phases` list migration: **accepted** — forced, internal, exhaustive, goldens
   byte-identical.
3. `"::target"` constructor rejection: **accepted as scoping, rationale rejected** — see
   Important 3; and it only half-closes the silent-inertness it cites — see Important 2.
4. Duplicate collapse: **accepted** (pinned); the distinct-action half is Important 1.
5. The `Attr.actions` rider on the click sweep: **accepted** — golden shows every other
   row's `attached=` unchanged.

# Re-review (fix round 1)

One commit, `e4076ae..c0532f8`, checked against my findings only. `nix develop -c
./scripts/ci.sh` at `c0532f8`: **exit 0, "all green"**.

**Verdict: APPROVED.** All three Importants and all six Minors are closed as asked.

- **I1(a) closed.** `Events.shortcut_conflict_rejection` (`vtree/events.ml`, doc'd in the
  mli): sort + adjacent-pair scan, same-trigger/different-action refused, same-trigger/
  same-action explicitly legal. One string from both callers — `Controllers.sync_shortcuts`
  (before the phase check) and the handle's per-frame `require_supported` (test_lib line
  198, on the walk every `recompute_view` runs). Pinned both ways in `test_menu.ml`
  (conflict → the string with the trigger label and both actions; doubled identical → `()`).
- **I1(b) closed.** The patch arm no longer does keep@added: any key-list change removes
  everything and reinstalls in the stable (trigger, action) sort — both sides sorted, so
  the equality guard is exact and unchanged frames still touch nothing. First-match is now
  a function of frame content, never patch history. `Fire_shortcut` sorts before matching,
  so headless agrees with live (belt-and-braces given (a), stated in its comment). The
  attr doc states the within-node rule and the across-nodes rule. Cross-node contention
  pinned live: the box carries the same Ctrl+k naming `win.chord2` through the whole
  block, the window's fires, and the golden pins `the contending inner shortcut fired: 0
  times`. (Residual, not blocking: nothing shows the inner shortcut *would* fire absent
  the window's — the zero pins determinism, not the counterfactual.)
- **I2 closed.** The walk's env now carries the spec kind per name with
  nearest-holder-of-the-name deciding it (union fall-through preserved — `find_map` +
  `Assoc.find` continues past a same-scope miss). A shortcut resolving to a `Radio`
  raises the feasible-but-unshipped message; a menu item naming the same radio (with
  `::target`) stays legal — both pinned in `test_menu.ml`.
- **I3 closed.** Every "cannot at all" claim reworded (constructor message + its golden,
  attr.ml comment, attr.mli doc, the test_lib radio arm); the backlog entry in
  `docs/m2-backlog.md` "Recorded during M3" names the exact removals shipping targeted
  shortcuts requires (both rejections + the argument in `Controllers.make_shortcut`).
- **Minors closed.** (1) The shared string's noun is now `action reference` — one string,
  both callers, both sources; the three old goldens moved deliberately. (2) The
  disabled-action chord is measured live and the answer is **fall-through**: the golden's
  `capture g mods=control` / `entry1 g` lines show the key reaching the capture handler
  and the entry after the disabled `win.gated` shortcut declined it, and the attr doc
  states the behaviour and its consequence for the consumer's `text_input_active` arms.
  (3) `set_scope LOCAL` written explicitly with the contract-not-default comment.
  (4) Report's deviation-4 overclaim tempered in place. (5) Cross-node ordering documented
  in the attr doc ("Across nodes, GTK's routing decides… deterministic by construction")
  and pinned by the contention golden. (6) trigger.mli's absence declared in the report
  with the named precedent (key_response/click_response/position, ml-only vtree data).

Residual nits, comment-only, fold into the next task's start; no round needed:
- `test/live/live_input.ml:896-899`: the block comment says the probe is the entry's
  text ("fall-through inserts the g") — Ctrl+g is not printable input, so the text stays
  `"x"` either way (the report says exactly this); the real proof is the two log lines.
  The comment should say so. The adjacent `ignore (before_keys : int)` is a dead
  leftover.
- `test/test_menu.ml:194-195`: the comment above the reworded `"::target"` golden still
  carries the old claim ("a radio cannot be fired by a shortcut"), contradicting the
  golden one line below it.
