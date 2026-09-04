# Task 9 report — timing, clipboard, and `Window.present` effects

Commits `a100495..d0a9d36` (3): the Task 8 review minors, the implementation
(`a527da2`), the live suite (`d0a9d36`). ci.sh green after each.

## The Task 8 minors first (`a100495`)

All six: the dead `before_keys` pair deleted from live_input; the unhandled-close line
reworded to claim only "unhandled" (the raised-handler and in-patch paths reach the
latch too) and swallow-guarded (it runs on a C-called frame); `resolve_window`'s
missing-key raise executed by a new hand-driven live_windows block (mount succeeds,
`run_fixups` throws the shared string, the emptied queue leaves the tree destroyable);
the after-stop probe covers `tools` too; the attr-side divergence sentence taken in
`Attr.on_close_request`'s doc. Goldens updated (live_windows: three changed/new lines).

## What changed (`a527da2`)

**`Gtk_effect.For_runtime`** — the `app` cell's shape generalised: one process-global
registration `{ request_frame; lookup_window option; context_widget }`, read at perform
time. Last-wins register; **identity-guarded unregister** (the stack registry's
discipline) so the first of two embeds stopping cannot take the second's hooks down.
Exposed in gtk_effect.mli as not-part-of-the-public-API (For_start's arrangement) and
through `Bonsai_gtk.Private.Gtk_effect` for the live suite; **not** in the public
`Bonsai_gtk.Effect` mli.

**The hook lifecycle**, exactly as the plan orders it:
- `Loop.start`'s activate registers all three **before the first frame** (so an effect
  that frame performs already finds them): `request_frame` = the driver's,
  `lookup_window` reads `Driver.windows`, `context_widget` answers `root_widget` or the
  first live window — covering both root shapes, with `windows []` answering `None`
  (clipboard then logs-and-resolves).
- `Embed.create` registers two (no `lookup_window`); context is the wrapper, the one
  widget whose identity never changes.
- Both hand `Gtk_effect.For_runtime.unregister reg` to the new
  `Driver.set_effect_hooks_drop`; **`Driver.stop` runs it first thing** and resets it,
  so a second stop cannot unregister a later driver's hooks. This is the plan's "every
  hook … dropped by Driver.stop" (m2-backlog leak shape). The "cleared where
  `For_start.clear_app` is called" half is satisfied through the same mechanism:
  `Loop.start`'s exit path runs `Driver.stop` immediately before `clear_app`, and an
  activate that never built a driver registered nothing. A literal clear at the
  `clear_app` site would be wrong — it could take a live embed's hooks down.
- `Driver.request_frame` added beside `schedule_event`, guarded the same way.

**The async pattern** (written once; Task 10's contract): `Ui_effect.Private.make` arms
the GLib source at perform time; the source's callback runs `resolve_from_glib` — 
`Ui_effect.Expert.handle` on `Callback.respond_to` (continuation's injects enqueue into
the graph as a signal handler's would), then the registered `request_frame`. The whole
resolver is swallow-guarded (C-called frame); a missing frame-requester is
**log-and-resolve**: the continuation still runs, a stderr line says no frame is coming,
nothing raises.

**The four effects**: `after` (Timeout-backed; negative spans clamp to 0; the
label/terminator asymmetry quoted in the impl per the plan), `on_idle` (Idle-backed),
`Clipboard.set_text` (string `GValue` → `Gdk.Clipboard.set_value` on
`Widget.get_clipboard (context_widget ())`; no-context logs-and-resolves; the
no-`get_text` omission stated in both mlis), `Window.present` (synchronous `of_thunk`
through `lookup_window`; the three miss paths — no app, under embed, missing key — each
log-and-resolve on `quit`'s precedent; `close`/`set_title` deliberately unshipped with
the §8 deviation stated in both mlis, spec amendment deferred to Task 13).
`gtk_import` gains the `Gdk` wrappers alias (the every-ocgtk-reference-goes-through-here
rule).

## The live suite (`d0a9d36`) — what the tests prove

`live_effects.ml`, `(locks x-display)`, census counts updated (fifteen of nineteen; ci.sh
comment matches). Written first, failing (`Unbound module Bonsai_gtk.Private.Gtk_effect`)
before the implementation existed. The suite registers the hooks exactly as
`Loop.start`'s activate does — it drives its own loop, so `start` cannot be used — with a
comment saying so. Golden pins:

- `resolved in order: after(16ms),on_idle` — from a button's effect; the **bind** is the
  ordering claim (on_idle is not armed until after resolved), no wallclock in the golden.
- `set_text: ok` — deliberately thin, with the comment the plan asks for: no bound read,
  the honest round trip arrives with a fork-round-3 read.
- `Window.present "a"` flips `is_active` from the mount-order winner (`b`) to `a`;
  a missing key's log line captured via the scoped stderr→stdout dup2.
- **Step 3, the review's first stop**: a 40 ms `after` orphaned by `Driver.stop` —
  golden shows `resolved yet: false` at stop, then the
  `resolved after the runtime's hooks were dropped (Driver.stop); no frame was requested`
  line, then `resolved after stop: true`. The continuation ran (the ref moved), nothing
  raised, nothing was requested.
- The identity-guarded unregister: reg2 displaces reg1, reg1's drop runs, `on_idle`
  still requests a frame through reg2 (`frame requests = 1`).

Two forced full-suite re-runs after the golden landed: 0 diffs each; full ci green.

## Deviations

1. **The plan's test/handle line cannot be implemented as written**: "test/handle/
   test_handle.ml (effects are opaque values headlessly — pin only that they exist and
   sexp as `<effect>`)". `test/handle` links `bonsai_gtk_test` + vtree and *cannot* link
   `bonsai_gtk` (the no-straddling rule in Global Constraints), so `Gtk_effect` is
   unreachable from every headless suite by package design. What the line wants is
   covered where it can be: existence-and-type is pinned by compilation of
   `live_effects.ml` on every ci run (`dune build @all` compiles the live executables
   regardless of the runtest gate), and the opaque-`<handler>` sexp rendering of attrs
   carrying effects is long-pinned across the handle goldens. Flagged to the team lead
   rather than worked around silently.
2. `Loop.start`'s literal registration lines are exercised indirectly (the live suite
   registers identically; `set_effect_hooks_drop` + `Driver.stop` are the shared
   mechanism and are what the orphan pin drives). A `start`-driven effects test would
   need input into a running `g_application_run` — the same residual live_windows
   recorded for its quit pin.
3. The "cleared where For_start.clear_app is called" reading above (via the adjacent
   `Driver.stop`, not a literal clear at that site) — reasoning in the mli and this
   report; a literal clear would break a concurrently-live embed.

## Deliberately not done

- No dialog effects (Task 10 reuses `resolve_from_glib`'s pattern).
- No `Clipboard.get_text`, no `Window.close`/`set_title` — documented omissions/
  deviations in both mlis; spec amendment is Task 13's.
- Cancellable/re-armable timers stay app-side (the mli says why: gating the continuation
  on model state is the declarative cancel).

## ci.sh

`all green` after each commit (three full runs this task, plus two forced live re-runs
after the effects golden landed). The bd hook's `.beads/issues.jsonl` change remains
uncommitted, as before.
