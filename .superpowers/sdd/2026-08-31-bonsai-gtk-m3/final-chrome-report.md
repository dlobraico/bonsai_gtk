# M3 final whole-branch review — CHROME lens

Reviewer scope: `w_header_bar`, `w_action_bar`, `w_popover`, `w_menu_button`, the slots
plumbing, the popover focus repair, plus `Attr.css_provider`/`attr_apply` and the
autofocus fixup as they touch chrome. Read-only; diff `c2580b5..9ee1fd6` plus the plan,
pre-flight corrections, ledger and all task reviews. Runtime-dependent claims are graded
and marked **needs probe** for the fix wave.

## Important

### I1. `node.mli:1509` still promises `Window.set_titlebar` "lands with the window props (Task 8)" — it never landed, and no backlog entry records it

- `vtree/node.mli:1509` (the `header_bar` doc): "**Where the bar goes is the
  application's choice in M3.** [Window.set_titlebar] wiring lands with the window props
  (Task 8); until then a header bar is an ordinary first child…". Written in Task 4;
  task-4-review item 7 accepted this sentence *as the deferral record* ("`Window.set_titlebar`
  → Task 8").
- The plan's Task 8 step 4 (plan line 586) then ruled the other way: "`set_titlebar`
  wiring… — **no**: `~titlebar` stays unshipped (Task 4's note), reconfirm and move on",
  and task-8-report.md:101/154 reconfirmed "unshipped". The node.mli sentence was never
  updated: on the merged branch it points readers at a Task 8 that already happened
  without the wiring.
- `set_titlebar` appears nowhere in the codebase and **"titlebar" appears nowhere in
  `docs/m3-backlog.md`** — the deliberately-unshipped decision has no in-tree record
  anywhere except a plan file and an untracked SDD report. Every other named deferral in
  this milestone (native controls, popover free anchoring, user-open reporting, targeted
  shortcuts, the ACCEPT-half gap) got a doc-comment or backlog line; this one fell
  between three tasks: Task 4 wrote a forward promise, Task 8 declined without touching
  the doc, Task 13's sweep verified the backlog against its strike list and this was
  never on it.
- This is exactly the doc-scale class task 11's Importants were graded as. **Fix wave:**
  rewrite the node.mli sentence (deliberately unshipped in M3, cite the ruling) and add
  the `~titlebar` wiring to `docs/m3-backlog.md`.
- **Needs probe** (adjacent, same fix's honesty check): without `set_titlebar`, a GTK4
  window draws its own default CSD titlebar, so `examples/chrome.ml`'s
  header-bar-as-first-child (`examples/chrome.ml:80`) most likely renders **two** title
  bars, and node.mli's "a plain titled header is `Node.header_bar ()` under a
  `Node.window ~title`" reads better than it looks. The 3-second smoke cannot see this.
  One screenshot under Xvfb settles whether the doc sentence needs a caveat.

## Minor

### M1. `Attr.autofocus` inside a popover: the named cross-widget scenario is unaddressed and untested

The lens scenario — a header bar packing a menu button whose popover holds an autofocus
node — traces as follows against the code:

- **Ordering is right where it matters:** `Patcher_fixups.run_fixups` runs the generic
  queue (which holds `W_popover.apply_open`, so the `popup`) before `apply_autofocus`
  (`src/patcher_fixups.ml:214-224`), so a same-frame open-then-grab lands in that order,
  and the focus repair (which runs synchronously inside a fixup-driven `popdown`) can
  never clobber a same-frame grab. No finding there.
- **(a) The consumed grab:** a popover slot child is mounted even when the popover is
  closed (`mount_slots` walks every slot), so `autofocus true` inside an
  initially-closed popover fires its one mount-frame grab against a hidden, unmapped
  subtree and never fires again when the popover later opens (no false→true edge).
  `examples/gallery.ml:1079-1082` documents the identical trap for hidden stack pages;
  neither `attr.mli`'s autofocus doc (which enumerates its other no-op case, Expert.embed)
  nor `node.mli`'s popover doc mentions the popover copy. The working pattern (render
  the attr `open_`-conditionally) is nowhere stated.
- **(b) The surprising rejection:** `apply_autofocus`'s per-toplevel check keys on
  `Widget.get_root` (`src/patcher_fixups.ml:96-118`); a popover's root is the window, so
  one autofocus in the window body plus one inside a *closed* popover in the same mounted
  tree is `Invalid_argument` at mount — the dormant claim counts. As-designed under the
  single-referent rule, but undocumented and easy to hit once (a) sends users toward
  putting the attr inside popovers.
- **(c)** Whether a grab fired just after `popup` survives GTK's own map-time focus
  handling for an autohide popover is unmeasured.
- No test anywhere places `autofocus` inside any popover (grep: live/handle/examples).
  **Needs probe** for (a) and (c) — one live block (menu button, popover holding an
  autofocus entry, model-opened) answers both; (a)+(b) also want one doc sentence each at
  `Attr.autofocus` and/or `Node.popover`.

### M2. The popover-slot ↔ `~menu` swap in one frame is untested, and bypasses the disarm-before-unparent doctrine

- Transition old node `~popover:(…open…)` → new node `~menu:(…)` on one `Menu_button`:
  `patch` runs `impl.update` **before** `patch_children` (`src/patcher.ml:497-527`), so
  `w_menu_button`'s update calls `set_menu` → `set_menu_model` and **GTK unparents the
  still-armed slot popover** (its `closed`/repair connections live, slots armed) before
  `patch_single`'s `disarm` ever runs. The slot's guarded `set` then correctly skips
  (`None when Option.is_some get_menu_model` — the guard doing its job), and `destroy`
  disconnects afterwards.
- Traced safe: every trampoline drops emissions under `in_patch`, the repair is
  exception-guarded and tolerates a rootless popover, and the OCaml wrapper's ref keeps
  the popover un-disposed until `destroy` has disconnected. But the safety rests wholly
  on `in_patch` — the disarm-first ordering `disarm`'s own comment calls the point
  (`src/patcher.ml:412-419`) is bypassed on this one path.
- Coverage: the guard's **mount** half is pinned (the always-empty slot beside `~menu`;
  sweeps + live_menus), and live_menus pins menu→Absent→menu — but neither headless nor
  live suite exercises popover→menu or menu→popover **in one frame**, with the popover
  open. **Needs probe**: one headless patch pair (both directions, `~open_:true`)
  turns the analysis above into a pin.

### M3. `Attr.visible` on a `Node.popover` fights the controlled `~open_`, and nothing says so

- `apply_open` compares `open_` against `Widget.get_visible` and writes with
  `popup`/`popdown` (`src/widgets/w_popover.ml:23-27`) — the same GTK bit `Attr.visible`
  writes. A popover carrying `Attr.visible true` at mount has the attr applied at
  `create` time, **before the slot parents it** (`src/patcher.ml:183`), and showing an
  unparented popover is the exact GTK critical the impl's own comment defers `popup` to
  the fixups to avoid (`w_popover.ml:71-74`). After mount, the attr and the fixup
  silently fight over one bit.
- `action_bar`'s doc handles its `Attr.visible` interplay explicitly (`node.mli`
  `~revealed` paragraph); `popover`'s doc says nothing. Candidate fix: a
  `Placement.rejection` row (Visible-on-Popover, matching how placement attrs are
  policed) or one doc sentence. **Needs probe** for the mount-time critical.

## Out-of-scope (recorded, no action urged)

- **No-handler dismissal schedules no frame.** `Signals.dispatch` with an empty slot
  returns unit — no `schedule`, no frame (`src/signals.ml:56-66`). A user dismissal of a
  popover whose node carries no `Attr.on_closed` therefore leaves `open_:true`
  contradicted on screen until an unrelated frame arrives; `node.mli`'s "re-opened on
  the next frame" assumes a frame source. This is structurally identical to every M2
  controlled prop with no handler (an entry with no `on_changed`) — doctrine-consistent,
  recorded here only because the popover is the most visible instance of the shape.
- **Ruled items verified in place, not re-reported:** the Expert.embed rootless-grab
  no-op (doc + bead `bonsai_gtk-vdy`); user-open reporting via `notify::visible`
  (m2-backlog "Recorded during M3"); the Down+Return WM-less residual; equal-priority
  CSS precedence unestablished; the `Attr.actions`-first-appearing-post-mount limitation
  (documented at the attr, workaround arm in `w_menu_button` update, activation half
  pinned in live_menus:146ff).

## Positive verifications (cross-task claims re-proved from the diff)

- **Pre-flight 1 met by construction, including the ancestor case my lens asked about:**
  `Actions.update` runs inside `mount` before children mount and before the caller
  parents the widget (`src/patcher.ml:204-210`), so an `Attr.actions` on a header bar
  packing a menu button inserts its group on the *header bar's* widget while the whole
  subtree is unrooted — the good ordering for the item tracker. Resolution path matches
  on both sides: `Action_resolution.check` threads the env through slot children
  (`Children.iteri` covers slots), and GTK's widget-side walk (popover → button →
  header bar) reaches the group; the muxer's ancestor fall-through is measured in
  live_menus' shadowing block.
- **The focus repair's two copies are both teardown-clean:** the slot path rides
  `w_popover`'s spec (both connections named for the popover, disconnected in `destroy`
  step 4 before the wrapper is released); the menu path's copy is dropped by
  `Menus.drop_repair` before every `set_menu_model` replacement and by `forget_menu`
  from `release_kind` at teardown — repair-before-model in both Some→None
  (`w_menu_button.ml` update) and rebuild paths. Repair-before-autofocus ordering inside
  one frame is correct (see M1 bullet 1).
- **Declined dismissal reopen is genuinely pinned:** `live_chrome.ml:91-173` drives the
  outside-the-guard `popdown` and asserts the reassert-only frame's fixup pops it back
  up; the `interest` arm's comment (`patcher_fixups.ml` Popover) states the coverage
  reason correctly (fixups run on mount, patch *and* reassert-only passes).
- **Title-slot kind change under a same-frame window retitle converges:** the window is
  patched before the header bar's slots (parent `update` precedes `patch_children`), a
  kind-changed title child is destroyed-then-replaced with all slots already cleared,
  and GTK's fallback label is property-bound to the root's title, so either write order
  lands the same screen. Task 4's Some→None live dump plus the sweeps' None→Some row
  cover the halves.
- **Cross-area pack moves are order-safe:** slots patch in declared order (title, start,
  end); a key moving start→end is remove-then-fresh-insert, end→start briefly holds the
  same key in both areas (legal, two widgets, documented at the constructor).
- **`Attr.css_provider` across slot replacement is safe by construction:** the provider
  is keyed weakly on the widget wrapper (`src/attr_apply.ml`), a replaced slot child is
  a new widget with a fresh provider applied by `apply_all` at mount, and the old
  provider dies with its widget's style context; the ephemeron entry lingers only until
  GC and references nothing shared. The task-11 Importants (clears-on-load sentence,
  per-widget dark-block honesty) verified landed at `vtree/attr.mli:341-357`.
