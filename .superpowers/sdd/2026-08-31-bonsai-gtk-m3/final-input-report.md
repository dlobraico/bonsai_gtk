# M3 final review — menus & input lens

Reviewer: m3-final-input. Read: the full branch diff `c2580b5..9ee1fd6` restricted to
this lens (vtree/menu.ml(i), action_spec.ml(i), action_resolution.ml, trigger.ml,
click_response.ml, keyval.ml, events.ml(i), attr.ml(i), attrs.ml; src/actions.ml(i),
src/controllers.ml, src/w_menu_button.ml's menu/repair halves, the patcher's resolution
wrappers and window fixup; test_lib's require_supported/check_frame/Activate_action/
Fire_shortcut/Close_request; live_menus' shadowing and rebind blocks), the plan
("How to execute", Global Constraints, Pre-flight corrections), the ledger, and task
reviews 2, 5, 6, 7, 8 (ruled items not re-reported). READ-ONLY: no builds or live runs;
findings that need GTK ground truth are marked **needs probe**.

## Verdict

The name-resolution architecture is sound and the task-review rulings held up under the
whole-branch read: one shared walk (`vtree/action_resolution.ml`) raising one string from
the runtime's mount/patch wrappers (`src/patcher.ml:785`, `:813`) and the handle
(`test_lib/bonsai_gtk_test.ml:386`), the union env matching GTK's measured muxer
fall-through, the shortcut family deterministic by sorted full-rebuild, action
slot/handler lifetime clean at all four patcher points plus the mount unwind. Two
Importants, both in the gap between what the walk certifies and what GTK then does with
the certified strings; both need a probe in the fix wave.

## Important

### I1. Unvalidated action-name/scope characters reach GLib's detailed-action parser — the walk certifies a tree that live aborts or silently retargets. **Needs probe.**

Nothing validates the *characters* of an action name or scope beyond
`vtree/attr.ml:534-551`'s two checks (scope non-empty and dot-free; duplicate spec
names). `Action_spec.simple ~name:"my act"` (space), `~name:""`, or a scope with a space
all construct fine, and the resolution walk certifies any menu/shortcut reference that
string-equals `scope ^ "." ^ name` — declared and referenced are the same string, so a
malformed pair *resolves*.

Live, a non-`::` menu item goes through `Gio.Menu_item.set_detailed_action`
(`src/widgets/w_menu_button.ml:122`), which calls `g_action_parse_detailed_name` and —
in GLib as I know it — **`g_error`s (process abort) on a parse failure**. The parser
accepts only `[A-Za-z0-9.-]` in names, so:

- name or scope containing a space (the natural typo): parse fails → abort at mount,
  after the walk said yes;
- name containing `(`: either aborts, or (with valid GVariant text inside) parses as a
  *targeted* activation of a different action — a silent retarget;
- name `""` (reference `"app."`): dots are legal in detailed names, so no abort — the
  muxer splits `"app."` into prefix `"app"` + name `""`, which the group can't serve:
  a certified item that renders inert. `Gio.Simple_action.new_ ""` is also presumably
  accepted silently.

The `::` path is safe (`set_action_and_target_value`, no parser), and shortcut firing
(`Named_action`) doesn't parse — so only the menu-item path aborts, which makes the
failure mode inconsistent across the two reference sources the walk deliberately unified.

This is the certify-then-grey-out (here: certify-then-abort) gap `action_resolution.ml`'s
header claims to close, and by the codebase's own rejection rule ("reject only what no
later frame could make valid" — an invalid character never becomes valid) it belongs at
the constructor. Fix: validate name charset + non-emptiness in the three `Action_spec`
constructors and scope charset in `Attr.actions` (scope already rejects `.`; add the
`g_action_name_is_valid` class), with the strings pinned. Probe first: confirm
`g_menu_item_set_detailed_action`'s failure mode on the pinned GLib (g_error vs
g_critical — the finding stands either way, the grade of the symptom differs), and what
`Simple_action.new_` does with an invalid name.

### I2. Patch-path within-node ordering defeats the documented re-bind workaround when the late `Attr.actions` sits on the menu button itself. **Needs probe.**

In `patch`, `live.impl.update` runs at `src/patcher.ml:503` and `Actions.update` at
`:515`. So when an already-mounted, already-rooted menu button gains `~menu` and
`Attr.actions` (its own scope) *in the same frame* — the first frame the walk permits the
menu to name that scope — the rows are built (`set_menu_model`, or `remove_all`+refill)
**before** the group is inserted. Per pre-flight correction 1, a group inserted
post-rooting never notifies already-built rows: the menu renders insensitive, silently,
while the walk certified it.

The Task 6 fix-round argument that closed I1 there ("in that frame the top-down patch
inserts the group (window first) before the button's rows rebuild") is correct only for
*ancestor*-held groups, which is what the live_menus rebind block measured. For the
same-node case the within-node order inverts it, and the mli caveat's escape hatch
("Changing the menu … rebuilds the model and re-binds", vtree/attr.mli ~317) is then
false for exactly the frame the caveat tells the user to produce: an app that follows
the documented workaround by shipping the attr and a menu edit together stays grey; it
works only if the menu edit comes one frame *later*.

Reachable shape: a button mounted early (no menu, no actions) that gains both when data
arrives — a plausible dynamic UI, not a record-update trick. Candidate fix, two lines:
move `Actions.update` above `live.impl.update` in `patch` ("groups before rows",
matching the top-down rule between nodes). Mount needs no change — `Actions.update` at
`:209` runs after `impl.create`'s model build, but the widget is unrooted there and
pre-flight 1 measured every pre-rooting order safe. Probe: the rebind live block's
same-node variant (attr on the button itself, arriving with the menu edit), before and
after the reorder.

## Minor

**M1. `action_resolution.ml:52` is a wildcard over `Kind.t`.** `node_references`' menu
half reads `| Menu_button { menu = Some menu; _ } -> … | _ -> []`. A future
menu-carrying kind — the menubar is already a fork-round-3/M4 candidate — silently
escapes the resolution walk, reopening the certify-then-grey-out gap for that kind with
no diagnostic. The codebase's own doctrine (events.ml's `for_kind` header; attr.ml's
"Exhaustive on purpose, never `_ -> false`") says spell the arms; this is the one
load-bearing vtree match over `Kind.t` the branch added that doesn't.

**M2. `Events.is_actions_attr` ends in `| _ -> false`** (vtree/events.ml:191-194),
against the same doctrine its neighbours state. Low stakes — a new carve-out attr that
forgets it fails `is_supported` loudly rather than going inert — so a nit: spell it out
or say in place why the wildcard is safe here when it wasn't for `attr_phase`.

**M3. `Attr.actions` migrating between ancestors with an unchanged menu greys a
previously-working menu, and the mli's framing hides it. Needs probe.** Frame N: group
on ancestor A, menu bound and working. Frame N+1: A drops the attr, B (previously
attr-less) gains it, menu `Menu.equal`-unchanged. The walk certifies; live, A's removal
de-binds the rows (or leaves them bound to a dead group — the probe should say which)
and B's post-rooting insert never notifies them (pre-flight 1), with no menu edit to
trigger the measured re-bind. The mli caveat covers this by letter ("first appearing on
an already-mounted node") but its reassurance — "Mount the actions with the tree (the
normal shape) and this never arises" — is defeated by a move in which every individual
frame looks like the normal shape. One honest sentence at the caveat (a *move* is an
appearance, and the removal half actively breaks bound rows), plus optionally a live pin
of the removal half, which no block currently measures.

**M4. Confirming a known residual rather than new:** the cross-node shortcut-contention
golden pins the winner's determinism (`the contending inner shortcut fired: 0 times`)
but nothing pins the *handover* when the winning node's shortcut is removed mid-session
(task-7 re-review named this "residual, not blocking"). The within-node removal case I
verified in code is sound: any key-list change discards the whole installed list and
reinstalls in the stable (trigger, action) sort (`src/controllers.ml:449-461`), so
post-removal order is a function of frame content, never patch history, and
`Fire_shortcut` sorts identically. If the fix wave is touching live_menus/live_input
anyway, one frame dropping the window's chord and re-firing it is a cheap pin;
otherwise leave as the recorded residual.

## Brief questions with no finding (verified, for the record)

- **Resolution at mount / patch / referent-not-yet-there.** Both wrappers check the
  whole tree as data before anything is built or written (`patcher.ml:785`, `:813`);
  reassert-only frames soundly skip (phys-same node); kind-change remounts are subtrees
  of a checked tree. A referent arriving one frame late raises by the plan-time ruling
  of record (strict single-referent), same string headlessly (`bonsai_gtk_test.ml:386`).
  `transient_for` resolves at fixup time against a registry the whole walk populated, so
  dialog-precedes-parent works within a frame and is pinned live and headless; missing
  key and self-reference render the shared `Events` strings with sorted keys. The
  Window-root degenerate-string divergence is already on record (task 8, out-of-scope 7).
- **Action slot/handler lifetime.** All four points present and ordered
  (create+update `patcher.ml:207-209` pre-parenting; patch `:515`; `clear` in disarm
  `:427`; `release` in destroy `:403` and mount unwind `:173`); `release_group` empties
  slots and disconnects before `insert_action_group scope None`; the activate trampoline
  drops in-patch emissions and double-guards `on_exn`; a shape-changed name is
  removed-then-rebuilt so `sync_surviving` can never read a wrong-typed variant; the
  ephemeron menu table's repair connection leaves before the model on every path
  (repair-first-model-second, task-6 M2's fix confirmed in the final tree).
- **Union env vs muxer, edge cases.** Prefixes are exact-match on both sides (walk:
  string equality; muxer: first-dot split + hash lookup), dotted *names* split
  consistently at the first dot on both sides (attr.ml documents it), same-scope
  fall-through is measured at two group-bearing depths from a third-depth leaf
  (live_menus:328-388). Three depths is unmeasured but follows from the muxer's
  recursive one-link parent fall-through — each added depth is the measured link again;
  I did not find a mechanism for GTK to special-case depth. An empty-spec-list group
  falls through identically on both sides. The scope/name *charset* is the one real
  edge — that is I1.
- **Click claim vs a shortcut on the same widget.** No interaction path exists by
  construction: `Claim` acts on the click gesture's pointer event sequence
  (`Gesture.set_state \`CLAIMED`, controllers.ml:196), while the shortcut family builds
  `Keyval_trigger`s only (`make_shortcut`, :390-398) — key events never enter a gesture
  sequence, and no mnemonic/gesture trigger is constructible from the vtree. The three
  no-handler click paths still claim nothing (`declined = ()`), preserving M2 behaviour.
- **Table exhaustiveness.** `for_kind`, `controller_family`, `attr_phases`,
  `Attr.Name.is_event`, `Attr.name`, `attr.mli`'s equal — all wildcard-free over their
  variants; `attr_phases` handles the repeatable `Shortcut` per-entry, so
  `family_phase_rejection` sees every entry's phase (two same-(trigger,action) entries
  with different phases are rejected before `wanted_shortcuts`' dedup could pick one);
  `shortcut_conflict_rejection`'s sorted-adjacent scan is correct (equal triggers are
  adjacent under the (trigger, action) sort). `autofocus_rejection` and the
  `transient_for` strings render from one place for both callers. The two wildcards that
  remain are M1 and M2; `kind.ml:668`'s and `attrs.ml`'s are guarded or name-dispatched
  and fine.
- **Headless/live agreement.** `Fire_shortcut` sorts before matching and walks
  self-then-nearest-ancestors with per-holder miss continuing past a same-scope holder —
  the same union order as `Action_resolution.check`'s env and the runtime's install
  order. `Activate_action`'s node-local lookup, radio `::target` handling, and the
  enabled-ignored divergence are as ruled in tasks 6/7.

## Out of scope (backlog)

- Targeted shortcuts (`Shortcut.set_arguments`), the menubar, and the enabled-state
  story for conditional chords — already recorded (task 7, m3-backlog).
- `Menu.Item.accel` display strings are unvalidated free text handed to the
  PopoverMenu's accel renderer (`gtk_accelerator_parse` on GTK's side); a garbage accel
  silently renders nothing. Display-only, no routing consequence; worth a backlog line
  only if someone hits it. `Trigger.to_label`'s hex fallback
  (`"0x…"`) may be in that class if fed to `~accel`.
