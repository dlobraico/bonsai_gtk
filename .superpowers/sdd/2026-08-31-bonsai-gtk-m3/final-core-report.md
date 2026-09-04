# Final whole-branch review — CORE lens

Branch `m3`, full diff `c2580b5..9ee1fd6`. Read-only review; no builds run (the gate is
Task 14's). Files read in full: `src/patcher.ml`, `patcher_checks.ml`,
`patcher_fixups.ml`, `driver.ml`, `scheduler.ml`, `loop.ml`, `actions.ml`,
`gtk_effect.ml`(+mli), `global_css.ml`, `embed.ml`, `widgets/w_windows.ml`,
`w_window.ml`, plus the popover/menu-button focus-repair path where it crosses into
lifetimes. Inputs honored: the plan (incl. pre-flight corrections), the full ledger,
and all fourteen task reviews — nothing below re-reports what a task review already
ruled on; every finding is an interaction no single task saw whole.

## Verdict in one paragraph

The per-task rulings hold up under the whole-branch read: the dialog keep-alive, the
stop-with-effect-in-flight contract, the destroy-order that keeps handlers off
destroyed windows, and the stop() ordering across hooks/actions/windows/css are all
implemented as ruled and I found nothing new inside any one of them. What the
per-task reviews could not see is the frame that raises meeting Task 8's
unconditional close veto: that interaction produces an application that can never be
closed or exited, which is a real M2→M3 regression on a path the docs describe as
"frozen but closable". One Important, four Minors (two needing probes), and a set of
verified-clean notes so the fix wave does not re-derive them.

## Important

### I1. A broken driver's app is unquittable: the always-veto survives the frame that raises

**Interaction:** Task 8's close-request veto × the M0 "a raising frame breaks the
driver for good" contract × `Loop.start`'s exit path. No single task saw all three.

The chain, each link verified by code-read:

1. A frame that raises marks the driver broken and abandons fixups
   (`src/driver.ml:167-173`); the scheduler's tick wrapper swallows the exception so
   the GLib main loop keeps running (`src/scheduler.ml:76-84`). Nothing notifies
   `Loop.start` — it learns of breakage only after `Gio_application.run` returns
   (`src/loop.ml:91-102`).
2. Breaking disconnects nothing: every signal connection, the close-request veto
   included, stays armed (`Driver.stop` is the only disconnector, and under `start`
   it runs only after `run` returns — `src/loop.ml:94`).
3. `w_window.ml`'s close-request wrapper answers `true` on **every** path
   (`src/widgets/w_window.ml:66-68`). With a handler armed, the fired effect is
   scheduled through `ctx.schedule` → `Driver.schedule_event`, which is a guarded
   no-op on a broken driver (`src/driver.ml:46-49`) — so even
   `Attr.on_close_request Effect.quit`, the README's own migration recipe, performs
   nothing.
4. Every window was `add_window`ed (`src/loop.ml:23-27`), so `g_application_run`
   holds while any exists. No window can ever be destroyed again: the model will
   never render another frame, and the X button / Alt+F4 / `Window.close` are all
   vetoed.

Net: any of M3's *designed* patch-time raises — a duplicate sibling key, a
`~transient_for` naming a key the same frame removed, a dangling action name
(`Action_resolution.check` runs per changed frame, `src/patcher.ml:809-817`) —
leaves the user with frozen windows that refuse to close and a `Bonsai_gtk.start`
that never returns; the only exit is a signal. In M2 the identical raise left a
frozen window the user could close, after which `run` returned
`broken_driver_status` — a status code (`src/loop.ml:9`) that M3 has made
unreachable in practice for any app whose windows are on screen. The README's
broken-driver paragraph (README.md:597-599, "the window never repaints again") and
the scheduler's own rationale (`src/scheduler.ml:52-58`, "a frozen (but still
displayed) window beats a live app") were both written when frozen still implied
closable; the migration note (README.md:429-441) says "the veto is unconditional"
without confronting this case. Neither docs/m3-backlog.md nor any task review
records it.

**Needs probe** (the fix wave should confirm end-to-end under xvfb): drive a `start`
app to raise on frame 2 (e.g. render a duplicate key), then deliver a close — expect
the window to survive, the unhandled-close report or a swallowed handled-close, and
`run` never returning.

**Fix shape (for the wave to choose, not prescribed):** the veto should collapse
when the driver is dead — the desync argument for the veto is void once no frame
will ever read the shadow tree again, which is `mark_broken`'s own reasoning. Either
(a) thread a `dead : unit -> bool` into `Signals.ctx` beside `in_patch` and have the
close-request wrapper answer `false` when it fires, or (b) give `Driver` an
on-broken hook that `Loop.start` points at `Application.quit`, restoring "one clear
error, then the app exits with status 2". (b) also revives `broken_driver_status`.

## Minor

### M1. `run_fixups`'s abandonment comment overstates itself; stale autofocus claims on the hand-driven path

`src/patcher_fixups.ml:219-222` claims a raise in the generic queue "abandons" the
autofocus claims — but the `finally` there clears only `ctx.fixups`; the claims are
actually cleared one layer up, by `Driver.frame`'s catch calling `abandon_fixups`
(`src/driver.ml:172`). Under the driver the net behavior is right. A hand-driven
caller — the mode `run_fixups`'s own doc invites (`src/patcher_fixups.ml:209-211`)
— that catches the raise and pumps another pass would fire the dead pass's grabs:
`apply_autofocus` calls `Widget.grab_focus` on widgets captured by the failed pass
(`src/patcher_fixups.ml:115`), possibly destroyed ones. Fix: correct the comment,
and (cheap, makes it true locally) clear `autofocus_claims` in the same `finally`.
No probe needed.

### M2. Autofocus firing after a same-frame popover popup — order unproven (needs probe)

`run_fixups` runs the generic queue first — which includes `W_popover.apply_open`'s
`popup` (`src/patcher_fixups.ml:375-379`) — then `apply_autofocus`
(`src/patcher_fixups.ml:215-222`). A frame that both opens an autohide popover and
fires an autofocus grab in the same toplevel therefore grabs focus *after* the
popup. If GTK treats that focus move as leaving the popover, the autohide popover
pops down; the provoked `closed` is emitted synchronously inside the patch guard, so
the trampoline drops it (by design — `src/widgets/w_popover.ml:20-22`) and the
model never hears the dismissal; with `~open_:true` still rendered, the next
frame's fixup re-opens it. Whether GTK actually popdowns on a programmatic
`grab_focus`, and what the steady state is (open popover vs. focused entry), nobody
has measured — the pre-flight probes covered grab-vs-present, not grab-vs-popup.
The converse ordering that does occur (popdown, focus repair clears, then grab) is
correct. **Needs probe**; if benign, one ordering sentence at `Attr.autofocus`'s
doc closes it.

### M3. `Alert_dialog.show ?cancel` is unvalidated against `buttons`

`src/gtk_effect.ml:215,256-259`: a dismissal resolves the raw `cancel` int, so
`~cancel:5 ~buttons:["OK"]` (or a negative) resolves an index naming no button —
the mli's "the index answered on dismissal" and the totality claim both quietly
assume it is in range. One `Invalid_argument` at effect-build time (constructor
arithmetic, M2's family) or a documented clamp. No probe needed.

### M4. After a mid-frame raise, the still-live hooks can hand destroyed windows to late effect resolutions (needs probe)

Hooks drop at `stop`, not at break (`src/driver.ml:287-292`). A driver broken
mid-`patch_list` has destroyed some Remove-op children (`src/patcher.ml:613-618`)
without the windows root's `live.children` being rewritten (that assignment,
`src/patcher.ml:516`, is only reached on success), so `Driver.windows`
(`src/driver.ml:256-273`) can still list a destroyed GtkWindow. An in-flight
`after`/`on_idle` chain resolving later can then reach it: `Window.present`
through `lookup_window` (`src/gtk_effect.ml:363-366`), or the clipboard through
`context_widget` (first live window under a Windows root, `src/loop.ml:71-74`).
Pre-flight 3 measured present-after-destroy as a GTK warning rather than a crash,
and the app is already dead (see I1), so Minor — but the clipboard path
(`get_clipboard` on a destroyed widget) is unmeasured, hence the probe flag.
Optional hardening: the hooks answer `None` when `Driver.broken`.

## Out-of-scope / verified clean (so the fix wave does not re-derive)

- **stop() ordering across hooks / actions / windows / css** — sound end to end:
  effect hooks dropped first with the reset that protects a successor's
  registration (`src/driver.ml:287-292`); caller callbacks dropped next; the
  destroy walk disconnects each window's connections before `release_kind`'s
  `W.Window.destroy` (stage order, `src/patcher.ml:398-408`), so no close-request
  handler can run against a destroyed window; `global_css`'s Settings connections
  are process-permanent by Task 11's ruling and hold only the provider.
- **Dialog lifetimes mid-effect, stop-with-effect-in-flight,
  destroy-before-resolve** — all match the task-9/10 rulings exactly; the mlis
  carry the outlives-stop story (task-10 Minor 1 landed). Nothing new found.
- **Report-once memos vs. windows fixups sharing the queue** — the
  one-failing-fixup-drops-the-rest interaction is already recorded at
  docs/m3-backlog.md:266-267; the memos that ride inside queued fixups lose at most
  one frame's report and re-mint next frame. No action.
- **Action-group insertion order on the kind-change remount** — pre-flight 1's
  before-rooting requirement holds on the `patch_list` Update arm too: the remount's
  `mount` inserts the group while the widget is unparented
  (`src/patcher.ml:203-209`), and `ops.insert` roots it only afterwards
  (`src/patcher.ml:699-700`).
- **A window destroyed in the same frame an effect resolves against it** — effects
  perform during flush, before the walk, against last frame's registry: present on
  a window the pending state drops is present-then-destroy (harmless); present on a
  window the pending state adds misses and logs (the mli's miss contract,
  `src/gtk_effect.mli:101-105`, whose "already has this score" wording carries the
  timing). Eventual-consistent and documented; no action.
- **`transient_for` naming a same-frame-removed sibling raises at fixup** — the
  designed single-referent refusal (Task 8 review point 4); noted here only because
  it is one of the ordinary model bugs that feeds I1's blast radius.
