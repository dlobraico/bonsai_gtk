# Task 5 review — MenuButton + Popover (`eabcd47..aca5db6`)

**Verdict: FIX ROUND REQUIRED.** The mechanism is sound — the controlled `~open_` from
the fixup queue is correct and verified on all three pass types, the two-connection
teardown story holds under every path I traced, and the live goldens each map to their
stated cause. Two Importants: a reachable type hole in the `~popover` slot (a
non-popover node reaches `set_popover` through an unchecked cast, violating the
guarded-call-site constraint), and the report's headline claim — "stavekeeper's
port-blocking bug proven fixed at the library layer" — asserting coverage of a failure
mode whose own cited evidence (the stavekeeper comment's measurements) says the
stranding lands *after* the only moment this repair runs. Plus the mutual-exclusion
test the report itself offered.

ci.sh at `aca5db6`: **exit 0, "all green"** (my run; tail below). Live suite forced
twice more after: green both times. `ddb6173` verified against task-4-review.md's four
Minors: covers all four exactly — overlay precedent (node.mli), the true lock census
with the conservative reasoning (test/live/dune), cross-area key semantics in the
header_bar doc plus the optional duplicate-key acceptance pin (test_widgets.ml), and
the live_chrome identity comment now citing test_reconcile + the sweep's 1U — and
nothing more (4 files, all in the Minors' footprint).

## Important

### 1. The `~popover` slot accepts any node; a non-popover reaches GTK through an unchecked cast

`Node.menu_button`'s `?popover` is a plain `t` (vtree/node.ml:869) and nothing
downstream checks its kind in the accepting direction. `check_placement`
(src/patcher_checks.ml:34-49) and `require_supported`
(test_lib/bonsai_gtk_test.ml:124-138) both police only "a `Popover` somewhere else";
a `Node.label` (or box, or anything) in the slot falls through both wildcards. It then
reaches `w_menu_button.ml:104` — `W.Menu_button.set_popover (cast w) (Option.map c
~f:cast)` — where `cast` is `Gobject.unsafe_cast` (src/gtk_import.ml:34). GTK4's
`gtk_menu_button_set_popover` precondition-checks `GTK_IS_POPOVER`, so live this is a
GTK critical and a silently absent child while the shadow tree believes the slot is
filled — a desync, with no `Invalid_argument` and no node path. Headlessly the same
tree is *certified*: the handle mounts it happily, breaking the "refuses the same
trees" promise the placement pair was built on. The slot-set comment's justification —
"is a popover by construction -- the placement check ran before this" — is false as
written: the placement check is one-directional.

The kind-change teardown path compounds it: `Popover` → non-popover in the slot goes
through `patch_single`'s replace arm and hands the new widget to the same cast.

**Fix:** reject a non-`Popover` in the slot before any GTK call, with the node path.
Cheapest and strongest is the constructor (`Node.menu_button` can match
`popover.kind` — pure `Kind.t` data, headless for free, kills mount/patch/replace
paths at once, in the keyed-children rejection family); if the implementer prefers the
placement-pair arrangement instead (check_placement + require_supported, strings
copied, goldens holding them together), that works too but needs both mirrors. Either
way the decision on `Native` payloads in the slot (a native node wrapping a real
`GtkPopover` would satisfy GTK but not a kind check) should be stated — refusing it in
M3 is fine, but say so. Pin the rejection string.

### 2. The focus-repair claim overreaches its evidence; Task 6 must not inherit it untested

What Task 5 proves (live_input, verified green, stable): after a real click-open and a
real Escape dismissal of a plain `GtkPopover`, focus is not in the popover and a
window-level F1 reaches its capture handler. That is real and worth having.

What the report claims: "That last line is stavekeeper's port-blocking bug proven
fixed at the library layer." The stavekeeper comment this repair cites as its
authority (viewer_window.ml:750-770) says the bug is specific to **GtkPopoverMenu
after an item is activated** ("the old PopoverMenuBar never did this"), and that the
focus restore into the dead popover "lands well after the popover's `closed` and even
after its `unmap` (**both measured**)". A synchronous-on-`closed` repair runs once, at
`closed`. A stranding that lands after `closed` is missed by construction — no timing
luck involved; stavekeeper's own measurements are the counterexample. So one of two
things is true of the live block: either the Escape path strands focus synchronously
by a different mechanism (and the repair caught it), or — more likely, given
"PopoverMenuBar never did this" — GTK restores focus itself on plain-popover Escape
and the repair never fired at all. Nothing in the golden distinguishes these; the
live_input comment's counterfactual ("without the repair, focus stays on the
popped-down popover's child") is asserted, not shown. (I attempted the neutered-repair
counterfactual run; the permission layer declined source edits, so this stands on the
cited measurements, which suffice.)

The trigger the bug actually needs — item activation in a menu-model popover — does
not exist until Task 6. The report's "no idle fallback was needed, so there is no
measurement to record on that branch" reached its conclusion on a trigger the cited
evidence says is not the stranding one.

**Fix (doc + ledger, no code):** temper the report's and live_input's claims to what
was shown (the Escape/click-away path is clean end to end); soften
`w_menu_button.ml`'s "so no port carries a timer for it again" to name the open
question; and record a **carry to Task 6**: the live proof must be re-run with a real
*item activation* on the `PopoverMenu`, and if the F1-afterward line then fails, the
plan's fallback branch (one-shot idle — though stavekeeper's 60ms×8 window suggests
even that may be short; a bounded per-frame check is the shape that fits this
codebase) gets designed with the measurement the plan asked for. The repair as shipped
is correct and harmless for everything M3 exposes; the claim is what must not travel.

## The five deviations, judged

**Deviation 1 (`~open_` from the fixup queue): ACCEPTED.** The parenting precondition
is real — `create` runs before the slot `set` in the mount walk, and `popup`
unparented is a GTK critical (w_popover.ml:70-72 defers correctly). The controlled
rule is preserved where it matters: `apply_open` compares against
`Widget.get_visible`, the widget's current value, not the previous node
(w_popover.ml:25). Coverage verified in code on all three pass types: mount
(patcher.ml:202), patch (patcher.ml:493), and reassert-only
(patcher.ml:775-781 calls `enqueue_fixups` directly). The guard story is identical:
`Driver.frame_body` wraps mount/patch/reassert *and* `Patcher.run_fixups` in one
`Scheduler.with_patch_guard` (driver.ml:87-110). The plan's fixups-vs-reassert split
put child-naming props in fixups; `~open_` is a value prop with a child-naming prop's
*precondition* (needs the tree assembled), so the placement is the split's own logic,
not a breach of it. On the declined-open/retry-forever question: there is no decline
path — `popup`/`popdown` write the readable `visible` bit synchronously and
unconditionally once parented, so the comparison converges after one write and a
parked frame costs one `get_visible`. No refusal exists for the Task-3 memo machinery
to report. (A popover opened inside an unmapped subtree reads `visible=true` without
being on screen — GTK's own semantics of the bit, converged, not a retry.)

**Deviation 2 (repair connection in `w_popover`'s spec): ACCEPTED.** The stated hazard
is real: a connection made from the slot's `set` would be recorded nowhere `destroy`
walks — teardown destroys subtrees by walking them (`Some o, None` in `patch_single`
is the only path that calls `set parent None`), so a slot-`set`-made connection
survives its widget into dispose. Riding the `closed` spec's connection list is the
designed alternative: `Signals.connect_all` (signals.ml:104-111) hands the spec its
guarded trampoline and takes back a list, and both connections land in the popover
live's `connections`. Traced paths: (a) **menu_button destroyed with the popover
open** — `destroy` disconnects the popover's connections (patcher.ml:372) before
`release_kind` and before GTK dispose can emit anything; the popover is never
unparented on this path; live_chrome exercises exactly this (its final destroy runs
with `open=true`) and is green. (b) **slot emptied** — `disarm` clears the trampoline
slot, `set_popover None` pops down and unparents (the emitted `closed` finds a cleared
slot and, in a patch, the guard; the still-connected repair fires, which is *intended*
— a patch-removed open popover strands focus the same way — and is
exception-guarded, touching only the popover's own root), then `destroy` disconnects
both. Nothing fires against a destroyed button: the repair closes over the popover
widget and reaches the window only through `get_root` at fire time. (c) replacement
by kind change is unreachable for popover-to-popover (same kind patches in place) and
otherwise lands in Important 1. Module dependency is acyclic (`w_popover` →
`W_menu_button`, not back). `Widget.is_ancestor f popover` is self-first
(`ml_gtk_widget_is_ancestor`), so the predicate reads "f is inside the popover" —
correct, and the `same f popover ||` half covers the popover itself.

**Deviation 3 (`Open_popover` honest no-op; no user-open reporting): ACCEPTED.** The
asymmetry is documented where a user will meet it: `Node.popover`'s doc states the
open direction has no event, names the built-in-toggle-vs-pinned-`false` fight, and
names `notify::visible` as the hook; the `Open_popover` mli restates it;
`Events.for_kind`'s Menu_button comment records why `activate` stayed out ("half an
opening story is worse than none" — right call). `Attr.on_closed`'s own doc covers
the dismissal half and points at `Node.popover` rather than restating the asymmetry —
adequate by reference. The kind-check-then-`Ignore` shape keeps a mis-aimed id loud
while the empty diff *is* the headless face of the next-frame popdown; the
popover-actions test shows both halves. One gap, folded into Important 2's ledger
item as a second line: `notify::visible` is recorded on the node doc but in no
location Task 13's step-3 enumeration will sweep (docs/m2-backlog.md untouched, and
the plan's Task 13 list predates this deferral) — the task-log entry should carry it
by name so the m3-backlog rewrite cannot miss it.

**Deviation 4 (no mutual-exclusion constructor test): TEST REQUIRED.** The rejection
is reachable, constructor-time, and its string is API surface; this codebase pins
every sibling rejection (pack-area no-key, window-as-child, both popover placements)
with the exact string. Nothing currently executes the `Some, Some` arm at all. The
three-line expect test the report offered — take it in the fix round, beside the
pack-area one in test_widgets.ml.

**Deviation 5 (`In_menu_button` sweep placement): ACCEPTED.** The row is a genuine
lifecycle through the slot, not construction: mount fills the scaffold button's slot
(`?popover:subject`), the patch phase updates the same popover in place
(props_changed=true), and the step-2 click empties the slot, driving
`patch_single`'s `Some o, None` arm — disarm, `set_popover None`, destroy — with
`unmount=ok` asserting the subject is gone. The `Root` precedent ("the one legal
position dictates the scaffold") transfers exactly.

## The live goldens, line by cause

`live_chrome` popover block (verified against the code, not the comments):
- `popover mounted closed: open=false closes=0` — mount + fixup; `open_=false`
  equals `get_visible=false`, no write.
- `model opened it: open=true closes=0` — patch pass, fixup `popup` inside the guard;
  `popup` emits no `closed`.
- `model closed it: open=false closes=0` — the load-bearing line: fixup `popdown`
  inside the guard; `closed` emitted synchronously inside it (pre-flight 8);
  trampoline sees `in_patch` and drops it. The helper's comment records the
  first-draft trap (fixups outside the guard heard their own close) — the exact
  regression this golden now pins.
- `user dismissed it: open=false closes=1` — raw `popdown` outside any guard;
  trampoline fires the handler once.
- `the model declined: open=true closes=1` — **the reopen is next-pass, not
  re-entrant**: nothing in the codebase reacts to `closed` synchronously (the handler
  only schedules an effect; the runtime's answer lives solely in the *next* pass's
  fixup). The `idle live` helper is `reassert_only` + `run_fixups` under the guard —
  exactly `Driver.frame`'s parked-frame path — and `closes` staying at 1 proves the
  re-opening `popup` ran guarded. No GTK re-entry inside the `closed` emission.

`live_input`: click → `pump_until get_mapped` (real map, not just visible=true);
Escape → the golden's `(focus-leave e2 popover-closed)` with **no capture-Escape
line** — the popover's own surface took the key, as attr.mli's phase doc promises;
`stranded: false`; `(capture F1 mods=none)` afterwards. The F1 line is the
keys-alive-after-menu-use assertion — for the Escape trigger (see Important 2 for
what it does and does not prove).

## Minor

1. **The mutual-exclusion constructor test** (Deviation 4 above) — required, fix
   round.
2. **`repair_focus_after_popdown` swallows exceptions silently** (`with _ -> ()`,
   w_menu_button.ml:45-46). The signal-slot constraint's shape is caught *and
   logged with the node path*; this handler has neither ctx nor path, and the body
   (two getters, one setter) can't realistically raise, so the swallow is defensible
   — but the comment should say "silently, because no reporting channel reaches
   here" rather than implying the backstop matches the trampolines' contract.
   Doc-only.
3. **live_input's stranded-focus probe is weaker than the repair's predicate**: it
   prints `is_ancestor f popover` only (live_input.ml:696-698), so focus sitting on
   the popover *itself* would print `false` — indistinguishable from clean. One
   `|| same f popover` (or reusing the repair's predicate shape) makes the printed
   evidence match the claim. Two tokens, fix round or fold into Task 6's re-proof.
4. **Ledger carry for the deferrals** (fold into Important 2's fix): the
   `notify::visible` open-event hook and the Task-6 item-activation re-proof both
   need to be in the Task 5 task-log entry by name; neither is anywhere Task 13's
   enumerated sweep will look.

## Out of scope / for the ledger

- `examples/gallery.ml` still lacks every M3 kind including these two — the existing
  Task 12 carry, reconfirmed (test_gallery_tree gained them; the example didn't).
- A user dismissal on a popover with **no** `on_closed` handler schedules nothing, so
  the declined-dismissal reopen waits for the next frame from any other source
  (tick/event) — the same latency every controlled prop already has for handlerless
  edits (entries behave identically). Not new, not wrong; noting it so nobody reads
  "re-opened on the next frame" as "a frame is requested".
- `Attr.on_closed` takes the effect directly (`unit Ui_effect.t`, not `unit -> _`) —
  consistent with the payload being nothing; just flagging the signature is
  deliberate.
- The pre-flight-8 dependency is correctly load-bearing in three places (apply_open's
  comment, attr.mli, the live_chrome golden) and was CONFIRMED by the scout; nothing
  further needed.

## Verification transcript

- Read in full: w_popover.ml, w_menu_button.ml, the complete `eabcd47..aca5db6` diff
  (36 files), driver.ml's guard region, patcher.ml's destroy/disarm/patch_single/
  patch_slots/release_kind/reassert_only, signals.ml's connect_all/dispatch,
  patcher_fixups.ml's popover arm, gtk_import.ml's cast, the stavekeeper reference
  viewer_window.ml:740-800 (read-only), task-4-review.md's Minors, the plan's
  pre-flight 5/8, Global Constraints, and Task 5 section, progress.md.
- `nix develop -c ./scripts/ci.sh` at `aca5db6`: exit 0. Tail:
  `bench: 0.0084 ms embedded, 0.0084 ms windowed, ratio 1.00 (bound 1.2)` /
  `== example smoke` / `all green`.
- `BONSAI_GTK_LIVE_TESTS=1 xvfb-run -a dune build --force @test/live/runtest`: two
  further forced runs, exit 0 both.
- Tree left as found: no source modified (the one attempted counterfactual edit was
  declined by the permission layer and abandoned); only this review file written.

# Re-review (fix round 1)

**Verdict: APPROVED.** `aca5db6..f268f39` (one commit) answers both Importants and all
three Minors; ci.sh exit 0 at `f268f39` ("all green", my run). Scope clean — every hunk
traces to a finding.

- **Important 1 closed on all three layers.** The constructor rejection
  (vtree/node.ml:884-890) matches `popover.kind` against `Popover _`, so mount, patch,
  and kind-change-replace die at tree build; the message is pinned in test_widgets.ml.
  The **record-update smuggling test is the real thing**: it builds a legal
  `Node.menu_button ~label:"menu" ()` and then replaces `children` by record update —
  the constructor genuinely never sees the Label — and the handle raises
  `require_supported`'s converse arm with the walk string
  (`root/0/popover/0: Node.menu_button's ~popover slot must hold a Node.popover, not a
  Label`), proving the walk-level backstop is load-bearing, not decorative.
  `check_placement` (src/patcher_checks.ml:51-66) carries the identical string and its
  arm ordering is right (the `Some (Menu_button _), Popover _ -> ()` arm shadows the
  reject arm; `require_supported`'s new arm sits after the Popover arms so it only
  catches impostors). The **Native-in-slot ruling is stated** at the rejection site
  (and echoed in check_placement): a native popover surface is a native *menu
  button*'s business, one payload owning both halves — a defensible ruling, recorded
  where a future consumer will trip on it. Residual note, not a finding: the runtime
  copy of the converse string is comment-held against the handle's pinned copy, the
  same arrangement the original placement pair shipped with.
- **Important 2 tempered consistently.** `w_menu_button.ml`'s repair doc now carries
  the full statement (what live_input proves, what the bug actually is, the predicate
  most likely never reading true on the Escape path) and names both Task 6
  obligations: re-prove keys-alive after a real item activation, and design the
  fallback there with the 60 ms × 8 caveat against a one-shot idle. `w_popover.ml` and
  `live_input.ml` point at it rather than restating; live_input's false counterfactual
  ("without the repair, focus stays…") is gone. The report is amended in place
  (untracked, so correctly outside the commit) with the same content. The one place
  the carry does not yet exist is `progress.md` — the controller's Task 5 log entry
  must name the Task 6 re-proof obligation so it survives into that task's inputs;
  flagged here so it cannot be dropped.
- **Minors: all three landed.** The mutual-exclusion test pins both constructor
  strings in one block beside its sibling rejections; the silent catch now explains
  the missing reporting channel and names the future change (threading `on_exn` into
  the spec's `connect`); the stranding probe spells `Gobject.same f popover ||
  is_ancestor f popover`, the repair's exact predicate.
- **notify::visible is sweepable.** docs/m2-backlog.md gains "Recorded during M3,
  input to the Task 13 rewrite" with the open-event entry naming the hook and the
  spec shape. The section also records the Task-3 functorise trigger — beyond my
  findings but exactly what the Task-3 ruling ("promoted to scheduled in Task 13's
  backlog rewrite") needed a sweepable home for; accepted. One nit, not worth a
  round: the entry says "the constructor doc names this paragraph" — node.mli names
  the hook and "backlog", not this paragraph specifically.
- Verification: full `nix develop -c ./scripts/ci.sh` at `f268f39`, exit 0, tail
  "all green". Tree left as found.
