# M3 fix-wave re-review

Reviewer: the re-reviewer agent, over `git diff 3f09c7a..3e46d7a` (nine commits) against
the four final reports and `fix-wave-report.md`. Method: a checklist built from the four
reports first (16 findings + 2 ledger residuals), then every hunk of the diff walked
against it; every code claim below verified by reading the committed code, not the wave's
report. Builds: one full `nix develop -c ./scripts/ci.sh` at `3e46d7a` plus one forced
extra live re-run (evidence at the bottom).

## Verdict

**Done.** Every finding in the four final reports is fixed, argued down in writing, or
deferred to an existing record — nothing silently dropped. Every hunk in the diff traces
to a finding, its pin, or its documentation. The two arguments the wave made instead of
code changes (input I2's no-reorder, core M4's no-hardening) are both sound and both
backed by measurements now pinned or recorded. Two residual observations below (neither
blocks the wave): the `Action_spec` record-literal bypass of the new charset validation,
and input M4's cheap pin whose stated precondition was actually met.

## Disposition table

| Finding | Wave's claim | Re-review verdict | Evidence |
|---|---|---|---|
| input I1 charset | FIXED `5b94923` | **FIXED, verified** | `vtree/action_spec.ml` `validate_name` (non-empty, `Char.is_alphanum ∨ '.' ∨ '-'` — exactly `g_action_name_is_valid`'s class) in all three constructors; `vtree/attr.ml` scope check (same class minus dot, after the existing empty/dot rejection). Four rejection strings pinned in `test/test_menu.ml` (space name, empty name, `"do('x')"`, space scope) + the passing `~scope:"app-2"`/`~name:"file.open-recent"` case. Parens are outside the class, so the probe's silent-retarget name is rejected. Census: every `Action_spec.simple/toggle/radio` name in tree is legal except the three deliberate pins; all in-tree scopes legal except the pinned rejects. Nothing legal newly rejected. |
| core I1 unquittable | FIXED `42a8302` | **FIXED, verified end to end** | Mechanism: `Driver.t.on_broken` (default no-op) run in `frame`'s catch *after* `mark_broken`/`abandon_fixups`, swallow-guarded so it cannot displace the frame's own raise; `Loop.start` points it at `Gio_application.quit gapp` (`src/loop.ml:67`). Fires once: `frame` on an already-broken driver returns before the catch. Embed cannot quit the host: `embed.ml` never calls `set_on_broken`, and its own break path is `mark_broken` (a callback), which never runs the hook — the hook lives only in `frame`'s catch. Quit-races-teardown: quit only makes `run` return; `broke` is read before `Driver.stop`, stop walks still-live windows, `start` returns `broken_driver_status = 2`. Live pin verified: `live_windows.ml`'s new block drives a real `start` whose frame 2 renders duplicate sibling keys, watchdog-guarded, golden `start over a raising app returned 2`; the `windows []` block's watchdog is now disarmed after use. Docs verified in all five places (start's mli, `driver.mli` `broken`/`set_on_broken`, scheduler rationale rewritten, README migration note + broken-driver bullet split by entry point). |
| input I2 same-node late menu+actions | ARGUED DOWN (no reorder) + measured + pinned `46dd2e0` | **ACCEPTED** | The pin covers the exact feared case: `live_menus.ml`'s same-node block mounts a bare rooted button, then one patch adds `~menu` and the button's *own* `Attr.actions`, pops open post-frame, reads `sensitive=true` and activation. The no-reorder argument is right: the probe refuted the prediction, so the two-line reorder would be churn. The mli caveat now states the measured rule (re-bind holds same-frame, ancestor or same node; only an *unchanged* menu stays stuck) — accurate against the pins. The wave's own precision limit (popover held open across the frame) is honestly recorded and is not the report's scenario. |
| chrome I1 set_titlebar record | FIXED `f61b9c4` | **FIXED, verified** | `node.mli` header_bar doc rewritten (deliberately unshipped, Task 4 deferred / Task 8 reconfirmed); `docs/m3-backlog.md` carries the `~titlebar` entry with the probe result and the fix shape; `examples/chrome.ml` comment added. The honesty probe went beyond the ask: one bar under xvfb both with and without `GTK_CSD=1`, explained from GTK 4.22.4's `gtkwindow.c` (default bar needs CSD *and* composited), Wayland caveat stated in doc, example, and backlog. |
| chrome M3 visible-on-popover | FIXED (rejection) `26405b1` | **FIXED, verified** | Probe upgraded the finding from "silent fight" to segfault (`gdk_surface_new_popup` on no parent surface → SIGSEGV), which killed the doc-sentence option. Rejected in `Node.popover` (vtree/node.ml) — the constructor, so runtime and handle both, both polarities; pinned headlessly in `test_widgets.ml` (both strings); `node.mli` documents it. Message honest: names the one-bit fight *and* the crash. Constructor over `Placement` is the right call — `Visible` is not a parent-held attr. |
| core M1 abandonment comment | FIXED `c385d4d` | **FIXED, verified** | `run_fixups`'s raise path now clears `ctx.autofocus_claims` locally (with the hand-driven-caller rationale in place) and re-raises with backtrace; the overstating comment is gone; success path unchanged. |
| core M2 grab-vs-popup | PROBED BENIGN + doc `c385d4d` | **ACCEPTED** | The benign result (popover stays up, no `closed`, stable steady state) is recorded as the review asked: one ordering paragraph at `Attr.autofocus` (attr.mli). The probe itself was throwaway per the wave's rules; chrome M1's live_chrome block additionally pins the grab-inside-popover surviving the popup ((c)'s cousin), so the doc is not evidence-free. |
| core M3 `?cancel` | FIXED `c385d4d` | **FIXED, verified** | `gtk_effect.ml`: `cancel < 0 || cancel >= List.length buttons` → `Invalid_argument` at effect-build time, before any GTK object — also rejects the buttonless alert. Both strings pinned in `live_dialogs.ml`/golden; mli documents the raise and the buttonless corollary. |
| core M4 late resolutions vs destroyed windows | PROBED BENIGN, ARGUED DOWN `c385d4d` | **ACCEPTED** | The unmeasured half (clipboard on a destroyed window) probed silently benign; present-after-destroy was already pre-flight 3's warning. The argument against hardening is sound on both legs: core I1's fix shrinks the under-`start` exposure to the mark-broken→run-returns instant, and hooks-answer-`None`-when-broken would be wrong for `Expert.embed`, whose broken-but-alive widgets legitimately accept presents and clipboard writes. |
| chrome M1 autofocus in popover | PROBED, PINNED, DOCUMENTED `cfb840c` | **ACCEPTED (premise corrected)** | The probe corrected the report's (a): the mount-frame grab against the closed popover's subtree *lands* (window focus = popover entry before the open), not consumed-and-lost. Both renderings pinned in `live_chrome.ml` (four golden lines: unconditional/open-conditional × closed/opened); (b)'s dormant-claim rule and (c)'s survives-the-popup both documented at `Attr.autofocus`, `Node.popover` points at it. |
| chrome M2 popover↔menu swap | PROBED, PINNED `26405b1` | **ACCEPTED** | Both directions pinned open in `live_chrome.ml` (slot popover gone + model set / fresh popover parented and up), `closes=0` pinning no spurious `on_closed`. The adjacent GTK critical was isolated by a bare-button control and the repair connection instrumented and exonerated — recorded in `docs/m3-backlog.md` with the minimal trigger and fix shape. Model of how to handle an adjacent discovery. |
| input M1 `Kind.t` wildcard | FIXED `aac56ed` | **FIXED, verified** | `action_resolution.ml`'s menu half spells all 42 constructors (plus `Menu_button { menu = None; _ }`), doctrine comment in place; a future menu-carrying kind is a compile error. |
| input M2 `is_actions_attr` wildcard | JUSTIFIED IN PLACE `aac56ed` | **ACCEPTED** | The written justification holds: the match is definitional (is it the `Actions` constructor), a second carve-out cannot arise from a `Name` row alone, and a wrong `false` fails loudly via `is_supported` — the stated asymmetry with `attr_phase` is real. |
| input M3 moving `Attr.actions` | PROBED (confirmed), PINNED, DOCUMENTED `aac56ed` | **FIXED, verified** | `live_menus.ml` move block: box→window, menu `Menu.equal`-unchanged; golden is the honest record (item `sensitive=false`, activation still resolving — also answering the report's de-bound-vs-dead-group sub-question: de-bound and grey). attr.mli caveat now says a move counts as an appearance, the removal half de-binds working rows, and the re-bind rule is the exit. |
| input M4 shortcut handover | DEFERRED (recorded residual) | **ACCEPTED, with a note** | The residual is on record (task-7 re-review, "residual, not blocking") and re-confirmed sound by code-read in the final input report. Note: the report's condition for the cheap pin ("if the wave is touching live_menus anyway") was in fact met — the wave added two live_menus blocks — so a stricter reading pointed at adding the pin. Not blocking: the report's own grading was confirmatory-Minor, and the deferral target exists. |
| tests minor per-toplevel sentence | FIXED `3e46d7a` | **FIXED, verified** | `test_lib/bonsai_gtk_test.mli` row 17's closing now states the implemented per-window rule, names the grouping key and the existing test. |
| ledger residual: fork pin hash | FIXED `3e46d7a` | **FIXED, verified** | `docs/m3-backlog.md` fork section says `72cc75f2`; `ocgtk-pin.json` rev is `72cc75f2a591…` — matches. Stale `649498b4` gone. |
| ledger residual: task-13 step-2 hash | FIXED (workspace edit) | **FIXED, verified** | `task-13-report.md` heading cites `db26888` with the `8132f44` orphan called what it is, in three places. |

## Nothing snuck in

Every file in the diffstat was read hunk-by-hunk; each traces to a finding, its pin, or
its documentation: `action_spec.ml(i)`/`attr.ml`/`test_menu.ml` (input I1),
`driver.ml(i)`/`loop.ml`/`scheduler.ml`/`bonsai_gtk.mli`/`README.md`/`live_windows.ml`+golden
(core I1), `live_menus.ml`+golden/`attr.mli` (input I2+M3), `node.mli`/`examples/chrome.ml`/
`m3-backlog.md` (chrome I1 + the M2-adjacent critical), `patcher_fixups.ml` (core M1),
`gtk_effect.ml(i)`/`live_dialogs.ml`+golden (core M3), `live_chrome.ml`+golden (chrome
M1+M2), `node.ml`/`test_widgets.ml` (chrome M3), `action_resolution.ml`/`events.ml`
(input M1+M2), `bonsai_gtk_test.mli` (tests minor). The watchdog-disarm in the
pre-existing `windows []` block is the one hunk not named by a finding, and it is the
wave's own pin-hygiene (two `start` blocks in one executable under load) — accepted.

The wave's throwaway `probe/` directory is gone; `git status` shows only the
pre-existing `.beads/issues.jsonl` modification and the untracked `.superpowers/` files.

## Residual observations (for the close or the backlog, not the wave)

1. **`Action_spec` record-literal bypass.** `Action_spec.t` is an exposed record
   (deliberately — the mli's stavekeeper mapping note even shows the row shape), and the
   public API re-exports it (`src/bonsai_gtk.mli:59`), so
   `{ name = "my act"; enabled = true; kind = Simple eff }` skips `validate_name`
   entirely, and `Attr.actions` checks only duplicates and scope, not the specs' name
   charset. The final report's prescription (constructors + scope) is implemented
   verbatim, so the finding is fixed as written; but the complete choke point is
   `Attr.actions`, where re-validating each spec's name is two lines against an existing
   message. Worth a backlog line or a two-line follow-up.
2. **input M4's cheap pin.** See the table row — the "touching live_menus anyway"
   condition was met. If anyone re-opens live input tests, the one-frame
   drop-the-winner's-chord pin is still the cheap close.

## Build evidence

Run by this re-review at `3e46d7a`, 2026-09-04, one build at a time:

1. `nix develop -c ./scripts/ci.sh` — **exit 0** (`rereview-ci.log`, 102 lines). Tail:

   ```
   == example smoke
   libEGL warning: DRI3 error: Could not get DRI3 device
   libEGL warning: Ensure your X server supports DRI3 to get accelerated rendering
     (x4, one pair per smoke example — the environment's standing noise)
   all green
   CI_EXIT=0
   ```

   The expected mid-run stderr lines all appeared beside green goldens: live_css's Theme
   parser error, live_dialogs' GtkDialog transient-parent message, and the two the wave
   added by design (live_embed's announced frame exception, live_windows' raising-app
   "exception in frame" report).

2. Forced extra live re-run: `rm -f _build/default/test/live/output_*.txt`, then
   `BONSAI_GTK_LIVE_TESTS=1 xvfb-run -a dune build @test/live/runtest` under
   `nix develop` — **exit 0** (`rereview-live2.log`); all 21 rules' output files
   regenerated (counted), so nothing was served from cache. The new pins (raising-app
   start=2, same-node bind, group move, popover autofocus ×4, swap ×3, `?cancel` ×2,
   charset rejections headless) are all inside compared golden output on this run.
