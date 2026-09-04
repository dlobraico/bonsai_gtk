# Task 6 report — Actions and Node.menu: GAction routing as data

Branch `m3`, commits `681c5dd..a79981a`: the headless half (`bb5452e`) and the
live half (`a79981a`). `nix develop -c ./scripts/ci.sh`: **all green** at
`a79981a`; live_input/live_menus forced re-runs 10/10.

## The design, as landed

Three layers, exactly the plan's:

1. **`vtree/menu.ml(i)`** — pure data: `Item` (label, `"scope.name"` or
   `"scope.name::target"`, display-only accel with stavekeeper's key-truth rule
   in the doc), `Section`, `Submenu`; sexp/equal derived, so a menu is a **prop**
   of `menu_button_props` and `Menu.equal` is what triggers rebuilds.
   `action_references` (targets stripped) feeds the resolution walk.
2. **`vtree/action_spec.ml(i)`** — the handlers: `Simple`/`Toggle`/`Radio`, the
   plan's constructors, states structural + handlers physical, sexp hiding
   effects but showing states (which is what the declined-checkmark golden
   reads). The mli carries the Command.Registry field-for-field mapping.
   **`Attr.actions ~scope specs`**: one attr per node (Attrs is name-keyed; more
   scopes live on ancestors, which is where GTK looks anyway), rejecting
   duplicate names and dotted/empty scopes at the constructor. It is `is_event`
   (honest: it carries handlers) with a new one-constructor carve-out,
   `Events.is_actions_attr`, threaded through `is_supported` and
   `require_slots`' skip — the controller carve-out's shape.
3. **`src/actions.ml(i)`** — `Controllers`-shaped, wired into `Patcher.live` at
   the same four points (create/update in mount+patch, clear in disarm, release
   in destroy and the unwind). New/departed/surviving names diffed by name; a
   shape change (Simple/Toggle/Radio) rebuilds that action (parameter type and
   statefulness are construction-time); a renamed scope rebuilds the group.
   `enabled`/`state` written **only when the `GAction` read-back differs**; an
   activation never touches state — scheduled effect, model decides, next
   frame's controlled write. No `change-state` connected; `lookup` never called
   (the fact table's NULL crash); the activate trampoline spells the five rules
   with the `in_patch` belt. **Pre-flight 1 is met by construction**: mount
   inserts the group while the widget is still unparented (rooting happens when
   the parent's insert runs, after the whole mount returns).

**Name resolution** (`vtree/action_resolution.ml`): one function walks the tree
threading the scope environment down — self-or-ancestor, exactly GTK's popover
path; sibling scopes deliberately out of reach — and raises with the path, the
reference, and the scopes in reach. The patcher runs it in the **mount/patch
wrappers** and `Bonsai_gtk_test` runs the identical call per frame. Both
messages, quoted as the verification asks, are one string:

```
root/0: menu item action "app.missing" resolves to no Attr.actions here or on an ancestor (scopes in reach: none)
```

(handle test) and the same shape from the runtime (`test_menu.ml` pins all four
shapes: self, ancestor, absent, sibling-therefore-absent).

**`w_menu_button ~menu`**: the `GMenu` is built per widget (ephemeron-held),
rebuilt **in place** by `remove_all` + re-append (an open PopoverMenu tracks it —
pre-flight 9, relied on); radio targets go through `set_action_and_target_value`
(the fact-table ruling — GTK's detailed-action parser is never fed our strings);
accels render via the `"accel"` attribute. `~menu`/`~popover` are mutually
exclusive at the constructor (`set_menu_model` builds its own popover), and the
popover slot's `set None` is guarded against wiping a present menu model — GTK's
`set_popover NULL` clears the model, and the always-empty slot beside a `~menu`
would otherwise destroy what the same mount just built.

**The Task 5 carry (mandatory), resolved.** A `~menu` button's popover is
GTK-internal — no `Node.popover`, so `w_popover`'s spec-borne repair never
connects there, and the stavekeeper bug is exactly that popover after item
activation. `w_menu_button` now connects the repair to the **internal**
PopoverMenu's `closed` when it sets a model, tracked beside the menu handle,
disconnected before replacement and at teardown through a new
`release_kind` hook (`forget_menu`) — the dispose rule honoured on this second
path too. Live proof (`live_input`): real click opens the PopoverMenu, the item
is **sensitive** (pre-flight 1's tracker bound — the group went in before
rooting), a real click on the item activates it through GTK's own menu machinery
(the handler fires — the only test in the repository that proves a human can
operate a menu), the popover closes itself, the stranding probe (the repair's
exact predicate) reads **false**, and **F1 reaches the window's capture
handler**. The synchronous repair suffices; **no idle fallback was needed**.

## What the goldens prove (live_menus)

Activation goes through `Widget.activate_action_variant` on the menu button —
GTK's own resolution walk from the widget through ancestors, the exact path a
menu item takes. The `Actions.dump` read-backs (GAction interface — the only
honest source for a controlled claim) pin: the **declined toggle's checkmark
standing still** across an activation (`state false` before and after); the
model's next-frame write moving it (`state true`); the radio's target riding the
activation and its state following the model; `enabled` controlled the same way;
an unprovided name resolving `false`; and pre-flight 1's activation half — an
`Attr.actions` appearing post-mount resolves and fires (the item-tracker half
stays the documented limitation on `Attr.actions`, with the menu-rebuild
workaround stated).

## Deviations from the plan, each argued

1. **The resolution check runs in the mount/patch wrappers, not the fixup
   queue.** The fixup placement bought refer-in-any-order; at the wrapper the
   whole tree is already in hand *as data*, which has that property a walk
   earlier — and a rejected tree costs nothing to unwind (nothing was built).
   Reassert frames skip it (same node); inner kind-change remounts are subtrees
   of the already-checked tree. Cost: one O(nodes) walk per changed frame,
   `check_placement`'s class.
2. **`Action_group.activate_action` on a "read-back" group is unimplementable**:
   GTK4 has no read-back for inserted groups (`gtk_widget_get_action_group` was
   GTK3). `Widget.activate_action_variant` is the replacement and the stronger
   probe — it exercises GTK's resolution from the widget, ancestors included.
3. **Pre-flight 1's choice, stated**: the post-mount-appearing attr is
   **documented + tested** (the activation half live; the insensitive-items half
   cited to the pre-flight's measurement) rather than force-re-setting
   descendant menu models — that repair would need ancestor-to-descendant
   machinery no other attr has, and the workaround (any `Menu.equal` change
   rebuilds and re-binds) falls out of the design. The limitation paragraph
   lives on `Attr.actions`.
4. **Keyboard activation (step 7's Down+Return) is not attempted**, with the
   measurement in the comment: under WM-less Xvfb a popup surface never receives
   X focus, so arrows/Return never reach the menu — Down then Return (with
   pumps) moved nothing while the same session's Escape dismissed the plain
   popover, because the *toplevel* handles Escape by dismissing its own grab, no
   popup routing needed. The pointer path exercises everything past the routing
   (ModelButton → menu item → GAction → trampoline). This is the M2 README's
   input residual in one more shape, and Task 13 should record it beside it.
5. **`Actions.dump`** is a small test-facing addition (GAction read-backs,
   sorted) exported through `Private` — the controlled-prop goldens have no
   other honest source.
6. **The internal-popover repair connection** (the carry's fix) is machinery the
   plan's Task 6 text didn't name but its carry demanded; it mirrors the
   `w_popover` spec connection on the menu path, with `forget_menu` as the
   teardown hook.
7. One evaluation-order bug in my own test was caught by its first run (printf's
   right-to-left argument order reading a counter before the activation) — fixed
   with a bound intermediate and a comment.

## Deliberately left undone

- `Attr.shortcut` and the shared handler table's fourth consumer — Task 7
  (the resolution walk's `node_references` is already a function so shortcuts
  join in one arm).
- `enabled` read *from* GTK (stavekeeper's `enabled = fun () -> action#get_enabled`)
  — inverted here by design: the model owns `enabled`, GTK mirrors it.
- Menubar (`set_menubar`/`PopoverMenuBar`) — named binding gap, fork-round-3
  list.
- The item-tracker limitation repair (above).

## ci.sh tail

```
== example smoke
(counter, gallery, embed each held for their 3 s timeout)
all green
```

Full gate at `a79981a`. Stability: 10/10 forced re-runs of live_input +
live_menus.

## Fix round 1

One commit, `bc0adc6`; ci.sh all green after.

- **I1, measured (the answer): the in-place menu edit re-binds.** live_menus'
  rebind block lands a "late" group on the already-rooted window (pre-flight 1's
  bad ordering), edits the menu in place (remove_all + refill on the same GMenu
  — the path the reviewer showed never calls set_menu_model), and probes
  `get_sensitive` per item: the late item reads **sensitive** after the in-place
  edit, and after a full model re-set — items-changed row recreation re-queries
  the muxer. The mli's workaround claim was right and now has the golden behind
  it; the caveat is rewritten to the measured shape (rows built *before* the
  group existed are the insensitive ones; rows built after — any
  Menu.equal-visible change — bind fine; mount actions with the tree and none of
  it arises).
- **M5, also measured: GTK's muxer unions.** A descendant "app" group under an
  ancestor's "app": a name the nearer group lacks **still resolves** against the
  ancestor's (`activate_action_variant` from the leaf, both probes true). The
  resolution walk's union env matches GTK exactly; the walk's comment cites the
  golden.
- **M1**: action_spec.mli's Command.Registry mapping completed (`scope` →
  `Attr.actions ~scope`; `label`/`accel` → `Menu.Item`).
- **M2**: the menu→None teardown drops the repair connection *before*
  `set_menu_model None` destroys the popover it is connected to, with the
  ordering rule stated in the comment.
- **M3**: `test_events` excludes `Actions` through `is_actions_attr` beside the
  controller carve-out (same one-line reason), so `signal_names_no_kind_emits`
  reads `()` again instead of mislabelling `(Actions)` as a pending widget.
- **M4** is the controller's (ledger carrier for the Down+Return residual).
