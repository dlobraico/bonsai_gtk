# M3 final whole-branch review — tests lens

Reviewer lens: `test/`, `test/handle/`, `test/live/`, `test_lib/`, `examples/` over
`c2580b5..9ee1fd6` (the branch's full diff; HEAD `3f09c7a` adds only the ledger entry —
`git show --stat` confirms progress.md is its whole content, so the code reviewed and the
code built are the same tree). The only reviewer permitted to build. Host: 24 cores.

Every mutation below was applied in the working tree, run, and reverted with
`git checkout <file>`; after the last revert `git status` showed only the pre-existing
untracked `.superpowers/` files and the pre-existing `.beads/issues.jsonl` modification,
and a cached re-run of the live alias exited 0. The tree is exactly as found.

## CI at 9ee1fd6

`nix develop -c ./scripts/ci.sh`, exit 0. Tail (elided libEGL/DRI3 noise is the
environment's, present in every prior run):

```
== example smoke
libEGL warning: DRI3 error: Could not get DRI3 device
libEGL warning: Ensure your X server supports DRI3 to get accelerated rendering
  (x4, one pair per smoke example)
all green
```

The two expected mid-run exception lines Task 14's report documents (the Theme parser
error from live_css's invalid-stylesheet case, the GtkDialog transient-parent Gtk-Message
from live_dialogs) both appeared, both inside compared golden output.

## Loaded-run evidence (the Task 14 gap, closed here)

The ledger records Task 14 has NO surviving loaded-run evidence. Per the final-review
instruction I ran the live suite ONCE under load, M2's recipe (48 spinning shells against
24 cores, started before and killed after — the "2x oversubscription" of
`final2-tests-live-report.md`):

```
BONSAI_GTK_LIVE_TESTS=1 xvfb-run -a dune build @test/live/runtest   (via nix develop)
```

**PASS.** Elapsed 100 s (vs ~31 s unloaded); load average reached 44.06 during the run.
All 21 rules green, benches inside their bounds under load:

```
bench: flow box 1.458 ms at sel=1, 1.058 ms at sel=200, ratio 0.73 (bound 5)
bench: list box 1.861 ms at sel=1, 1.828 ms at sel=200, ratio 0.98 (bound 5)
bench: stack 0.00122 ms per idle frame parked on a hidden page, 0.00594 ms settled
```

Precision limit, stated as Task 14's review did for its evidence: this is one loaded run,
not the plan's original 5/5 bar; green was confirmed by a cached re-invocation of the
alias exiting 0 immediately after (nothing rebuilt, so the loaded run is the run that
produced every compared output). One run is what the final-review protocol asked this
reviewer to produce; if the close wants the 5/5 bar restored, that is four more runs of
~100 s each, not a code change.

## Lock census (every `test/live/dune` rule read)

21 rules; 17 carry `(locks x-display)`; the header comment's census ("Seventeen of the
twenty-one") matches the rules exactly. The four unlocked, each verified against its
source:

- `live_events`, `live_keyvals` — never call `GMain.init`; run with DISPLAY unset
  (pure-table sweeps that live here only because they link ocgtk).
- `live_controllers_click`, `live_controllers_shortcut` — init GTK but mount bare labels
  through `Patcher.mount` with a no-op `on_window_created`; nothing is presented or
  mapped. Both files say so in their headers, and the dune comment repeats it.

Every rule whose executable presents a toplevel is locked, plus the three conservative
locks the header defends (`live_containers`, `live_chrome` create-without-presenting;
`live_css` mutates the default display's GtkSettings). **PASS.**

## Mutations (3 applied, 3 caught, all reverted)

1. **Action-resolution walk neutered** (`vtree/action_resolution.ml`: `check` made a
   no-op). Caught headlessly in both packages: `test/test_menu.ml` (3 expect blocks —
   the resolution walk, the shortcut walk, radio-target rejection) and
   `test/handle/test_handle.ml` ("a dangling menu action reference is rejected by the
   handle"). The certify-then-grey-out gap the walk exists to close is really pinned on
   both the wrapper and the handle side.
2. **Close-request veto flipped** (`src/widgets/w_window.ml:68`: the always-`true`
   answer made `false`). Caught by `expected_windows.txt` line 32 exactly:
   `tools after two swallowed close requests: visible=true` → `false`. The plan's most
   user-visible ruling is golden-locked.
3. **Claim made inert** (`src/controllers.ml:195`: `Gesture.set_state \`CLAIMED`
   skipped). Caught by `expected_input.txt` line 27 exactly: the nested-targets block's
   `inner claims the sequence:` line grew `outer b1` — the XTEST test is the only test
   that could see this, and it does.

## Golden honesty (read, not just run)

- `live_menus`'s state/enabled dumps are `Actions.dump` — GAction-interface read-backs,
  not the model echoed back — so the controlled-write claims (declined toggle's checkmark
  standing still, `enabled` greying) are pinned against GTK. The menu-structure golden
  dumps the internal `GtkPopoverMenu` tree including the display-only accel labels
  (`Ctrl+P` as a rendered `GtkLabel`), so a broken menu builder cannot pass it.
- `expected_input.txt` covers every real-input claim the plan demanded: popover maps on a
  real click, Escape dismissal, focus-not-stranded after BOTH plain-popover close and
  real menu-item activation (the Task 5/6 carry), window chord with an entry focused,
  disabled-action chord falling through to capture/widget, dialog Escape resolving None.
- `expected_effects.txt` pins ordering (`after` then `on_idle` resolved in order), the
  in-flight-`after`-after-stop line (Task 9's review's "first stop"), both raise pins
  from the Task 9 Important (pre-boom/pre-boom-2 with the watchdog printing into compared
  output), the displaced-registration drop, and the negative-span clamp.
- `expected_dialogs.txt` pins the mid-show `Gc.full_major` keep-alive, per-button
  response, DELETE_EVENT→`?cancel` mapping, default cancel = 0, and two-alerts-at-once.
- `expected_windows.txt` pins `root_widget = None`, model-order keys, transient
  read-back via `get_transient_for`, last-present-wins ordering, the once-latched
  unhandled report, GObject identity across reorder, stop-destroys-all, the missing-key
  fixup raise executed (a Task 8 carry, done), and `windows []` exiting 0.
- `live_controllers_shortcut` pins attach/detach/phase-move/duplicate-collapse with
  controller counts by name — the no-slot family's whole surface.

## Handle-suite certification audit

`test_lib/bonsai_gtk_test.mli`'s 17-row table was read against the implementation; the
checks it claims (rows 1–7, 17) all exist in `check` (`bonsai_gtk_test.ml:377-392`), run
in the runtime's order, and every entry point that advances a handle runs them —
the shadowed-entry-point story holds (`recompute_view`/`_until_stable`/`store_view` all
check). 67 expect tests in `test/handle/test_handle.ml` alone; every M3 action has both a
fires-the-handler test and a loud-failure test.

The two cross-suite divergences the ledger flags are stated where a user of the suite
will see them, and both are *tested*, not just documented:

- **`Close_request` loud-fail**: the `Action.Close_request` doc says "fails loudly:
  live, the request would be swallowed and reported once", and the failure message
  itself carries the divergence ("live, the runtime swallows the request and reports
  once -- the window stays open") — pinned in test_handle.ml's Close_request test.
- **Autofocus path-keyed approximation**: both directions (keyed move re-fires here not
  live; kind-change re-fires live not here) documented at mli row 17 and in the ml
  comment, with "no tree in this repository does either". Per-window grouping under a
  windows root is implemented (`toplevel_of`), tested ("autofocus is per window under a
  windows root", test_handle.ml:3537) and matched live (`live_windows.ml`'s two
  autofocused entries, one per window).

Spot-checked mli claims, all with tests: `Trigger.to_label` (test_menu.ml:142-151), all
four `Click_response` variants printed (test_attrs.ml:225), `Attr.actions` duplicate-name
and bad-scope rejection (test_menu.ml:41), `menu_button` label/icon mutual exclusion
(test_widgets.ml:420-424), css_provider unset restoring no-provider and invalid-CSS
clearing (expected_css.txt), `family_phase_rejection` for each family where a conflict is
expressible (key, focus, shortcut — the click family carries one phased attr, so no
conflict can be built, which is why no such test exists).

`examples/`: `chrome` is in ci.sh's smoke list (line 113, `counter gallery embed
chrome`); `rm -f _build/default/test/live/output_*.txt` (line 102) covers every new
suite's output by construction. No test directory straddles the two packages (test/dune
= bonsai_gtk, test/handle/dune = bonsai_gtk_test, both with the explanatory header).

## Findings

### Important

None.

### Minor

1. **Stale sentence in `test_lib/bonsai_gtk_test.mli:526-527`** (row 17's closing): "Per
   toplevel is per tree here, until [Node.windows] widens it." Written in Task 2's fix
   round (`6869497`, 2026-08-31), before Task 8 existed; Task 8 then widened the
   implementation (per-window `toplevel_of`), updated the .ml comment
   (bonsai_gtk_test.ml:275-278 states both halves correctly) and added the test — but
   this mli sentence still reads as if the widening is future work. A reader of the mli
   alone would expect two windows' autofocuses in one frame to be rejected; they are
   accepted, correctly. One-sentence fix: "Per toplevel is per window under a
   [Node.windows] root (the grouping key is the child); per tree under any other root."

### Out-of-scope (for the backlog, not the fix wave)

- The loaded-run bar: the plan's Task 14 wrote "5/5 under load"; the milestone now has
  1/1 (this report) plus M2's historical 5/5 on the same recipe. If the close wants the
  original bar re-established as a standing gate, that is a process decision (a ci.sh
  `--loaded` mode or a documented manual recipe), not an M3 code change — the recipe
  currently lives only in M2's final review report and this one.

## Verdict

The suite certifies nothing it should not that is not already a documented, deliberate,
and tested divergence; the three mutations each failed exactly one golden, in three
different suites (headless expect, live dump, live XTEST); the lock census is accurate to
the rule; the loaded run is green. One Minor doc fix for the wave. This lens is clean.
