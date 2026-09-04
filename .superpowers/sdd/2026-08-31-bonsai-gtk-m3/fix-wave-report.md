# M3 final-review fix wave

Implementer: the fix-wave agent, over the union of the four final reports
(`final-core-report.md`, `final-chrome-report.md`, `final-input-report.md`,
`final-tests-report.md`), the ledger's Task 13/14 residuals, and the plan's Global
Constraints. Base `3f09c7a`; every probe ran as a throwaway under `xvfb-run -a`
(a `probe/` directory, deleted before the last commit; findings recorded here, per the
wave's rules). One build at a time, everything through `nix develop -c`.

Commits, in order:

| Commit | What |
|---|---|
| `5b94923` | input I1 — action-name/scope charset validated at the constructors |
| `42a8302` | core I1 — a broken driver under `start` quits (on-broken hook → `Application.quit`) |
| `46dd2e0` | input I2 — same-node late menu+actions measured: it binds; pin + doc |
| `f61b9c4` | chrome I1 — set_titlebar record corrected, double-titlebar probed |
| `c385d4d` | core M1–M4 — fixup abandonment made local; grab-vs-popup benign; `?cancel` validated; clipboard-after-destroy benign |
| `cfb840c` | chrome M1 — popover autofocus measured, pinned, documented |
| `26405b1` | chrome M2+M3 — open-popover swap pinned; `Attr.visible` on a popover rejected (measured segfault) |
| `aac56ed` | input M1–M4 — walk match spelled out; wildcard justified; moving group measured grey + pinned |
| `3e46d7a` | tests minor + ledger residuals — per-toplevel sentence; pin hash |
| `c338951` | re-review (a) — `Attr.actions` re-runs `Action_spec.validate_name` on every spec, closing the record-literal bypass (same string as the constructors', stated in a comment; pinned headlessly); re-review (b) stays deferred per instructions |

---

## Important findings

### input I1 — unvalidated action-name charset (FIXED, `5b94923`)

**Probe** (throwaway, each case its own process under xvfb):
- `Gio.Menu_item.set_detailed_action mi "app.my act"` (space in name):
  `GLib-GIO-ERROR **: g_menu_item_set_detailed_action: Detailed action name 'app.my
  act' has invalid format` → **process abort** (exit 134, core dumped). Same for a
  space in the scope (`"my app.act"`). So the failure mode is `g_error`, the worse of
  the two grades the review offered.
- `"app."` (empty name): accepted silently — dots are legal in detailed names, so it
  parses and the item renders inert (no group can serve the empty name).
- `"app.do('x')"`: accepted silently — parses as a *targeted* activation of `app.do`,
  the silent retarget.
- `Gio.Simple_action.new_ "my act"` and `new_ ""`: both accepted silently; GLib
  validates nothing on the declaration side.

**Fix**: `Action_spec.simple/toggle/radio` hold `name` to `g_action_name_is_valid`'s
class (non-empty, `[A-Za-z0-9.-]`); `Attr.actions` holds `scope` to the same class
minus the already-banned dot. Both at the constructor, per the "reject only what no
later frame could make valid" rule — the resolution walk cannot catch these because
declared and referenced are the same string, so a malformed pair *resolves*. All four
rejection strings pinned in `test/test_menu.ml`, plus a passing case proving dots and
dashes stay legal (`~scope:"app-2"`, `~name:"file.open-recent"`). A repo-wide grep
found no existing name outside the class, so nothing broke.

### core I1 — unquittable broken app (FIXED, `42a8302`)

**Probe**, both halves of the chain:
- Driver-level: mount, then a scheduled frame renders duplicate sibling keys → driver
  broken (the live "exception in frame" report). Two `W.Window.close` calls later the
  window is still `visible=true` — **even with `Attr.on_close_request Effect.quit`
  armed** (the README's own migration recipe): the fired effect dies in
  `schedule_event`'s broken-driver guard.
- `start`-level: the same raise under real `Bonsai_gtk.start`; a 4-second watchdog
  fired (`exit 42`) — **`start` never returns**. The whole chain the core report traced
  is real end to end.

**Fix shape — (b), the on-broken hook, chosen on the merits over (a), collapsing the
veto for a dead driver.** The merits, as asked:

- Both shapes keep the veto doctrine intact for healthy drivers; the difference is what
  a *dead* app does.
- (b) keeps `Driver.stop`'s teardown walking windows that still exist. Under (a) the
  user destroys windows one by one through the collapsed veto, and `stop` then runs its
  destroy walk against a shadow tree describing windows that are already gone — a fresh
  hazard of exactly the class the core report's M4 flags, which would itself have
  needed probing.
- (b) gives multi-window apps one uniform story and returns from `start` promptly with
  `broken_driver_status = 2` (revived — the review noted M3 had made it unreachable in
  practice), where (a) returns only after the user hunts down every frozen window.
- (b) is also the honest UX: a frozen app that ignores every click except close is a
  confusing corpse; one clear error then exit is ordinary crash semantics. The
  scheduler's "frozen but still displayed beats a live app" sentence predates the veto
  (the review's own observation) and has been rewritten either way.
- Cost check on (a) for the record: threading `dead` through `Signals.ctx` breaks all
  50 literal ctx constructions across the live suites, mid-final-review.

**Implementation**: `Driver.t` gains `on_broken : unit -> unit` (default no-op —
hand-driven callers and embedders hear the raise straight out of `frame` and keep
their frozen widgets); the raising frame runs it after `mark_broken`/`abandon_fixups`,
swallow-guarded so it cannot displace the frame's own exception; `Loop.start` points
it at `Gio.Application.quit gapp`. Post-fix probe: same raising app, `start returned
2`, no hang, clean teardown (no criticals).

**Pinned live** (`live_windows.ml` + golden): a `start` over an app that raises on a
later frame returns 2 under a watchdog. (The instruction's "close succeeds" phrasing
belonged to shape (a); under (b) the honest pin is "the app quits on its own and
start returns", which is what the golden says.) The `windows []` block's watchdog is
now disarmed after use so the two `start` blocks cannot trip each other under load.

**Docs caught up**: `start`'s mli (quits, non-zero status, why nothing less would do),
`Driver.broken` and `set_on_broken`, the scheduler's rationale comment, README's
migration note (the one state the veto does not govern) and the broken-driver bullet
under Structure and lifecycle (split by entry point: `start` quits, `embed` freezes).

### input I2 — same-node late menu+actions in one frame (NO BUG — measured, pinned, `46dd2e0`)

**Probe**: the review's exact reachable shape (button mounted bare, gains `~menu` +
its own `Attr.actions` in one frame) **binds**: item sensitive, activation resolves.
The stronger variant (existing menu refilled in-place in the frame the button's own
scope appears — rows rebuilt *before* the group insert) **also binds**. The predicted
inversion doesn't manifest because the PopoverMenu's item tracker binds late enough
that within-frame write order is invisible; the ancestor case was already golden
(`expected_menus.txt` lines 101-104, same-frame late group + edit → sensitive).

**No reorder** of `impl.update`/`Actions.update` — the code is correct as it stands
and the reorder would have been churn justified by a prediction the probe refuted.

**Taken instead**: the fresh-model same-node shape is now a `live_menus` block
("same-node menu+actions in one frame: item X sensitive=true"), and the
`Attr.actions` caveat states the measured fact — the re-bind holds even when the menu
change and the attr's first appearance land in the same frame, ancestor or same node;
only an *unchanged* menu stays stuck.

**Precision limit, for the record**: both probes pop the menu open *after* the patch
frame. A popover held open across the in-place-edit-plus-new-scope frame could in
principle show a transient mis-bind until reopen; that is not the review's scenario
(its shape starts menu-less, so nothing can be open) and was not measured.

### chrome I1 — the set_titlebar stale promise (FIXED, `f61b9c4`)

- `node.mli`'s header_bar doc now says the wiring is *deliberately unshipped* (Task 4
  deferred, Task 8 reconfirmed) instead of pointing readers at a Task 8 that happened
  without it; `docs/m3-backlog.md` carries the `~titlebar` entry (the in-tree record
  that was missing everywhere).
- **Double-titlebar probe**: `examples/chrome.ml` under xvfb renders **one** bar
  (screenshot, read and looked at); `GTK_CSD=1` produces a byte-identical image, and a
  widget-tree walk shows no titlebar child of the window in either state. Then the
  pinned GTK's own source (`gtk-4.22.4/gtk/gtkwindow.c`, realize) explains it exactly:
  the default title bar is created only when CSD is in use **and**
  `gtk_window_is_composited` — on X11 CSD needs `GTK_CSD=1`, and xvfb is never
  composited, so the doubling is unreachable in every environment this repo tests. On
  a Wayland desktop (CSD on, composited by definition) it is real: GTK's default bar
  renders above a first-child header bar until `~titlebar` ships.
- Recorded in all three places: the header_bar doc (the platform honesty note), a
  comment at the example's header bar, and the backlog entry. `set_titlebar` stays
  unshipped, as instructed.

---

## Minors

### core M1 — `run_fixups` abandonment comment (FIXED, `c385d4d`)

The overstating comment is gone; the raise path now clears `autofocus_claims` in
`run_fixups` itself (not only one layer up in `Driver.frame`), so the hand-driven
caller its own doc invites cannot catch the raise, pump another pass, and fire the
dead pass's grabs against possibly-destroyed widgets. Success path unchanged
(`apply_autofocus` still consumes and clears its own queue).

### core M2 — autofocus after a same-frame popover popup (PROBED BENIGN, doc added, `c385d4d`)

Probe: a frame that opens an autohide popover and fires an autofocus grab elsewhere in
the same toplevel lands popup-first, grab-second; the popover **stays up**, no
`closed` is emitted, and the steady state (open popover, focus in the grabbed widget)
is stable across a reassert frame. GTK does not treat the programmatic grab as leaving
the popover. One ordering paragraph at `Attr.autofocus` records it, as the review
asked for the benign case.

### core M3 — `Alert_dialog.show ?cancel` unvalidated (FIXED, `c385d4d`)

`cancel < 0 || cancel >= List.length buttons` is now `Invalid_argument` at
effect-build time (M2's constructor-arithmetic family) — which also rejects the
buttonless alert, whose only resolution would be the dismissal that must name a
button. No existing caller used empty buttons (grepped). Both rejection strings pinned
in `live_dialogs` (effects cannot be tested headlessly — the Task 9 plan error); the
mli documents the raise.

### core M4 — late resolutions against destroyed windows (PROBED BENIGN, argued down, `c385d4d` message + here)

Probe: `Widget.get_clipboard` on a destroyed GtkWindow, then `Clipboard.set_value` —
**silently benign**, no warning, no crash (a destroyed window still has a display).
Present-after-destroy was already measured as a warning (pre-flight 3). Argued down
rather than hardened: with core I1's fix the under-`start` exposure is the instant
between `mark_broken` and `run` returning (then `stop` drops the hooks first thing),
and the offered hooks-answer-`None`-when-broken hardening would be *wrong* for
`Expert.embed` — a broken-but-alive embedded tree's widgets are intact, and clipboard
writes and presents against them are legitimate.

### chrome M1 — autofocus inside a popover (PROBED, PINNED, DOCUMENTED, `cfb840c`)

The probe corrected the review's premise: the unconditional attr's one mount-frame
grab against the hidden (closed-popover) subtree is **not** consumed-and-lost — it
lands, setting the window's focus widget to the popover's entry before and after the
open. The cost is that until the open, the window's focus sits on an unmapped widget;
the `open_`-conditional rendering lands the grab in the frame that pops up (and the
popover survives it — (c) answered). Both renderings pinned in `live_chrome`
(four golden lines); `Attr.autofocus` documents the measured facts plus the
dormant-claim half of the per-toplevel rule ((b) — a window-body autofocus plus one
inside a *closed* popover is the two-claims `Invalid_argument`); `Node.popover` points
at it.

### chrome M2 — the open-popover ↔ `~menu` swap (PROBED, PINNED, `26405b1`)

Both directions with the popover open converge — slot popover gone + model set one
way, fresh popover parented and popped up the other — with no spurious `on_closed`
(the unparent's synchronous `closed` lands inside the patch guard). Pinned in
`live_chrome` ("swap …" golden lines).

**Adjacent discovery, isolated by control experiment**: the menu→popover frame emits
one GTK critical (`gtk_widget_is_ancestor: assertion 'GTK_IS_WIDGET (widget)'
failed`). A bare-button control (no `~menu` anywhere) reproduces it identically, so it
is **not** the swap path: the minimal trigger is "destroy an open slot popover, then
pop up a new one in the same window" — GTK-internal stale-focus bookkeeping. The
runtime's own repair connection was instrumented (temporary eprintf) and exonerated:
it runs once, in the *other* frame, and not when the critical fires. One stderr line,
no crash, no behavioural consequence. Recorded in `docs/m3-backlog.md` with the
minimal trigger and the shape a fix would take (popdown before a visible popover's
destroy).

### chrome M3 — `Attr.visible` on `Node.popover` (PROBED: SEGFAULT; REJECTED AT THE CONSTRUCTOR, `26405b1`)

The probe upgraded this finding: `Attr.visible true` at mount is applied at `create`
time, before the slot parents the popover, and GTK **segfaults** (the
`gtk_widget_realize`-outside-a-toplevel warning, three criticals ending in
`gdk_surface_new_popup: assertion 'GDK_IS_SURFACE (parent)' failed`, then SIGSEGV,
core dumped) — not the deferred-popup critical the impl comment anticipates, and not
the review's "silent fight". The doc-sentence option was therefore off the table.

Fix: rejection in `Node.popover` (both polarities — the fight is the same bit
whichever way it points), pinned headlessly in `test_widgets.ml`, documented in the
mli. Constructor rather than `Placement` because `Visible` is not a parent-held attr —
shoehorning it into Placement's table would corrupt that module's meaning; the
constructor is where the popover's other structural rules already live, and it covers
runtime and handle both (vtree is shared).

### input M1 — `action_resolution.ml`'s wildcard over `Kind.t` (FIXED, `aac56ed`)

`node_references`' menu half now matches all 42 constructors by name; a future
menu-carrying kind is a compile error at exactly the point the walk must learn about
it. Comment states why (events.ml's doctrine, the menubar as the live candidate).

### input M2 — `Events.is_actions_attr`'s wildcard (JUSTIFIED IN PLACE, `aac56ed`)

Kept, with the reason the review asked for written at the site: the question is
definitional ("is it the `Actions` constructor"), a second carve-out cannot arise by
only adding a `Name` row (it needs its own runtime machinery and predicate), and a new
attr wrongly answering `false` here fails loudly through `is_supported` — the
asymmetry with `attr_phase`, where a forgotten arm mis-phased silently.

### input M3 — the moving `Attr.actions` (PROBED: CONFIRMED; PINNED + DOCUMENTED, `aac56ed`)

Probe: group on the box, menu bound and working; one frame later the box drops the
attr and the window gains it, menu `Menu.equal`-unchanged. Result: **the item greys**
(`sensitive=false`) while activation still resolves (`activate_action` true — the
union env and the muxer agree, so the walk is not wrong, the item tracker is simply
de-bound with nothing to re-bind it). Also answers the review's sub-question: the
removal leaves the rows *de-bound and grey*, not bound to a dead group.

Pinned in `live_menus` (the four-line "move measurement" golden — the honest record:
insensitive item, resolving activation). The attr's caveat now says a *move* counts as
an appearance, that the removal half actively de-binds working rows even though every
individual frame looks like the normal shape, and that the re-bind rule (ship any menu
change with or after the move) is the way out.

### input M4 — cross-node shortcut handover (LEFT AS RECORDED RESIDUAL)

Per the wave's instructions: it stays the task-7 re-review residual ("residual, not
blocking"). The within-node half was verified sound by code-read in the final report
(stable sorted rebuild, `Fire_shortcut` agreeing).

### tests minor — the stale per-toplevel sentence (FIXED, `3e46d7a`)

`test_lib/bonsai_gtk_test.mli` row 17's closing now states the implemented rule (per
window under a `Node.windows` root, the windows child as grouping key, matching live
and tested; per tree otherwise) instead of describing the widening as future work.

### Ledger residuals (`3e46d7a` + untracked workspace edit)

- `docs/m3-backlog.md`'s fork section: the pin is stated as `72cc75f2` (verified
  against `ocgtk-pin.json`, named as the authority), standing since fork round 2 —
  the stale `649498b4` is gone.
- `task-13-report.md`'s step-2 heading now cites `db26888`, with a parenthetical
  recording that `8132f44` was a red off-branch orphan from an amend, not
  bisect-reachable. (SDD workspace file — untracked on the branch by the fork-round-2
  convention; commits as evidence at milestone close.)

---

## Suite status

Headless (`@test/runtest`), `@all`, and the live suite
(`BONSAI_GTK_LIVE_TESTS=1 xvfb-run -a dune build @test/live/runtest`) were run green
after every fixing commit. New pins added by the wave: 3 headless expect tests
(charset rejections ×2 blocks, visible-on-popover), 2 live_dialogs golden lines
(`?cancel`), 1 live_windows golden line (start returns 2 on a raising app), 3
live_menus blocks' worth of lines (same-node bind, group move), 2 live_chrome blocks
(popover autofocus ×4 lines, swap ×3 lines + done markers).

`nix develop -c ./scripts/ci.sh` at the wave head:

```
== example smoke
libEGL warning: DRI3 error: Could not get DRI3 device
libEGL warning: Ensure your X server supports DRI3 to get accelerated rendering
  (x4, one pair per smoke example -- the environment's noise, present in every prior run)
all green
CI_EXIT=0
```

Exit 0, run 2026-09-04 at the wave head `3e46d7a`. The two expected mid-run exception
lines (live_css's Theme parser error, live_dialogs' GtkDialog transient-parent
message) appeared inside compared output as in every prior run, plus the two the wave
added by design: live_embed's announced frame exception and live_windows' raising-app
"exception in frame" report (both stderr, both beside green goldens).
