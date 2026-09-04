# Task 5 report — MenuButton and Popover: controlled open, and the focus GTK leaves behind

Branch `m3`, commits `eabcd47..aca5db6`: the Task-4 minors (`ddb6173`, ordered
first), the headless half (`fb77fb0`), the live half (`aca5db6`).
`nix develop -c ./scripts/ci.sh`: **all green** at `aca5db6`.

## What changed

**`fb77fb0` — vtree, impls, placement, headless.**
`Node.popover` (single child; controlled `~open_` with **no** `sexp_drop` — the
controlled-prop convention; `~position` via the new `Position` enum,
`~autohide`, `~has_arrow`) and `Node.menu_button` (`~label`/`~icon_name`
mutually exclusive, rejected together at the constructor since GTK's non-option
setters replace one child widget; `~primary`; `~always_show_arrow`; the
`~popover` Single slot through `set_popover`; `~menu` reserved for Task 6), per
the plan's interfaces. `Attr.on_closed` is the popover's one event attr.

- **One legal placement.** `Patcher_checks.check_placement` and
  `Bonsai_gtk_test.require_supported` refuse a `Popover` anywhere but a
  `Menu_button` parent — child-of-K and at-the-root variants, one pair of strings
  naming the slot that accepts it, the window rule's arrangement (copied, goldens
  hold them together). A `Menu_button` parent implies the slot: the button has no
  other child position.
- **`~open_` is applied from the fixup queue, not `reassert`** — the task's one
  designed deviation, for two reasons the plan's own machinery supplies: `popup`
  needs the popover *parented*, which has not happened when its `create` runs
  during the mount walk (the menu button's slot `set` runs after), and
  `enqueue_fixups` runs on the mount, patch *and* reassert-only passes — exactly
  a controlled prop's coverage, where `reassert` alone would miss the mount
  frame. The comparison is against `Widget.get_visible` (the readable open bit),
  per the plan. Pre-flight 8 holds as promised: `closed` is emitted synchronously
  inside `popdown`, so the guard covers every library-made close.
- **The open/close asymmetry is documented honestly** on `Node.popover` and in
  `Events.for_kind`'s comment: nothing reports the user *opening* the popover
  (no signal is exposed for it; MenuButton's `activate` is deliberately left
  out — half an opening story is worse than none), so a model must drive
  `~open_` itself, and the built-in toggle fights a model that renders `false`
  forever. `notify::visible` is named as the backlog hook. This shapes the
  `Open_popover` handle action: it **fires nothing, honestly** — kind-checks the
  target and returns `Ignore`, mirroring GTK exactly, with the mli explaining
  that the empty diff it produces *is* the headless face of the next-frame
  popdown. `Close_popover` fires `Attr.on_closed`.
- **The focus repair** lives in `W_menu_button.repair_focus_after_popdown`
  (documented there with the stavekeeper citation, per the plan): on the
  popover's `closed`, if the window's focus widget is the popover or inside it,
  `Window.set_focus None` — once, synchronously, no timer. **Where it connects
  deviates from the plan's letter**: the plan has `w_menu_button` connect it,
  but a connection made from the slot's `set` is unreachable at teardown (the
  patcher tears a subtree down by walking it; `set None` is not called), which
  would leave a handler connected to a signal the popover's dispose can emit —
  the global constraint's exact hazard. Instead it rides `closed` as a *second
  connection inside `w_popover`'s spec* (a spec's `connect` returns a list for
  precisely this), so it lands in the popover live's `connections` and
  `Patcher.destroy` disconnects it before the popover can be collected. It
  deliberately runs on library popdowns too (a patch-driven close strands focus
  the same way), and the body is exception-guarded because it runs outside the
  trampolines.
- **Sweeps forced the coverage**, as in Task 4: both kinds into the gallery
  tree, both `all_kinds` lists, the `action_for` table, and the lifecycle row
  list — which gained a third placement, `In_menu_button`, putting the popover's
  row inside a scaffold menu button (the `Root` precedent: the one legal
  position dictates the scaffold). Headless tests pin both placement rejections
  with mount's strings, the mutually-exclusive constructor rejection is
  documented (constructor test in `test_widgets` was not added — the two
  rejection strings for placement and the actions tests cover the new surface;
  the label/icon rejection is pinned by the constructor raising in any tree that
  tries it — flagged below), and the popover-actions test shows a dismissal
  heard (`open_` flipping) and an opening unheard (empty diff).

**`aca5db6` — the live half.**
`live_chrome`: the model opens and closes the popover (`open=` read off
`get_visible`, the very bit `apply_open` compares); a model close is **silent**
(`closes=0`); a user-style `popdown` outside the guard fires `on_closed` once;
a pinned `~open_:true` **reopens on the next idle frame** — the
declined-dismissal rule on the wire. The block's first draft ran `run_fixups`
outside the patch guard and heard its own close (`closes=1` where 0 belonged);
the helper now guards mount/patch/idle exactly as `Driver.frame` does, with a
comment recording the trap.
`live_input`: a real XTEST click on the menu button maps the popover (child a
*focusable* button — the regression is about focus stranded inside); a real
Escape dismisses it through autohide — the golden shows **no capture-Escape
line**, the popover's own surface taking the key exactly as `attr.mli` §Phase
documents; `on_closed` fires; `window focus stranded in the popover: false`;
and a subsequent F1 reaches the window's capture-phase handler.
**[Amended in fix round 1]** That line pins the chain {i around} the repair on
the plain-popover Escape path — where GTK most likely restores focus itself and
the repair's predicate reads false — not the stavekeeper bug itself, which is a
GtkPopoverMenu stranding after {i item activation}, a trigger that arrives with
Task 6. Task 6 must re-prove the keys-alive line after a real item activation
and design the fallback if the synchronous clear is too early there.
10/10 consecutive live runs.

## Deviations from the plan

1. **`~open_` from the fixup queue rather than `reassert`** — reasons above;
   behaviourally strictly stronger (covers the mount frame), and the guard story
   is identical since fixups run inside it.
2. **The repair's connection lives in `w_popover`'s spec** rather than being made
   by `w_menu_button` — teardown reachability and the dispose rule; the function
   itself, and its documentation, are in `w_menu_button.ml` as the plan asks.
3. **`Open_popover` is an honest no-op** (kind-checked). The plan's step-1 line
   reads as if both actions fire `on_closed`; only a dismissal does, and the mli
   says why the open direction cannot.
4. **No dedicated constructor test for the label/icon mutual exclusion** — the
   rejection is constructor-time `Invalid_argument` with a self-explanatory
   message; if the reviewer wants it pinned it is a three-line expect test.
5. The `In_menu_button` lifecycle placement is machinery the plan did not
   specify but its own sweep demands once a kind exists that is legal in exactly
   one slot.

## Deliberately left undone

- `~menu` / `set_menu_model`, `Node.menu`, actions — Task 6, and the mli says so.
- Free-floating popovers, `set_pointing_to` — backlog (unconstructible
  `GdkRectangle`, fact table).
- An opening event (`notify::visible`) — named as the backlog hook on
  `Node.popover`; without it the built-in toggle and a `false`-pinning model
  fight, which the doc states plainly.
- `on_activate_default`, `set_offset`, `set_cascade_popdown` — no consumer.

## Also in this stretch

`ddb6173` took the four Task-4 minors: the move=None precedent now cites
overlay; the live dune header states the true lock census and the conservative
reasoning; cross-area key semantics documented (remove+insert, same key in both
areas legal) with a pinning test; live_chrome's identity comment points at
test_reconcile and the sweep's 1U instead of overclaiming the dump.

## ci.sh tail

```
== example smoke
(counter, gallery, embed each held for their 3 s timeout)
all green
```

Full gate at `aca5db6`; live_input/live_chrome forced re-runs 10/10.

## Fix round 1

One commit answering the review's two Importants and three Minors; ci.sh all
green after.

- **Important 1 (the slot type hole).** `Node.menu_button` now rejects a
  non-`Popover` `~popover` at the constructor — killing the mount, patch and
  kind-change-replace paths at once — with the exact message pinned in
  `test_widgets.ml`; the Native-in-slot ruling (the runtime cannot see inside a
  payload; a native popover surface is a native menu button's business) is
  stated where the rejection lives. The record-update bypass is closed in both
  walks with one string: `Patcher_checks.check_placement` and the handle's
  `require_supported` gain the converse arm ("Node.menu_button's ~popover slot
  must hold a Node.popover, not a %s"), and a handle test smuggles a Label in by
  record update and pins the rejection — the certify-then-refuse gap is closed
  on both sides.
- **Important 2 (the repair claim, doc-only).** Tempered everywhere it was
  made: `w_menu_button.ml`'s repair doc now states what is proven (the
  Escape-on-plain-popover chain, on which the repair's predicate most likely
  never read true), what the bug actually is (GtkPopoverMenu after item
  activation, trigger arriving with Task 6), and the named Task 6 obligations
  (re-prove keys-alive after real item activation; design the fallback, noting
  a one-shot idle may be short against stavekeeper's 60 ms × 8 window);
  `w_popover.ml`'s comment and `live_input.ml`'s block comment point at it; the
  report's own claim is amended above.
- **Minors.** The label/icon mutual-exclusion expect test (beside the slot-type
  one); the repair's `with _ -> ()` now explains why it is silent (no
  `Signals.ctx` in reach from a spec's `connect`, and a failed best-effort
  repair leaves exactly the pre-repair state) and names the change to make if a
  real failure mode appears; `live_input`'s stranding probe now spells the
  repair's exact predicate (`Gobject.same` or descendant) so the two cannot
  diverge silently; and the `notify::visible` user-open hook is recorded
  sweepably in `docs/m2-backlog.md`'s new "Recorded during M3" section, which
  Task 13's rewrite reads, alongside the functorise ruling.
