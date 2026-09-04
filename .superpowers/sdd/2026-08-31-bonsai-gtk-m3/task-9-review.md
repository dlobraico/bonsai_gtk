# Task 9 review — timing, clipboard, and `Window.present` effects

Range `48c7562..d0a9d36` (a100495 the Task-8 minors, a527da2 the implementation,
d0a9d36 the live suite), reviewed against the plan's "### Task 9" (the async-pattern
paragraph as contract, the in-flight-after-stop pin as the named first stop),
task-9-report.md, and docs/m2-backlog.md:708-717. Every claim below was verified
against the sources — including the ui_effect and ocgtk library sources in `_opam`,
not just this repo's code.

**Verdict: APPROVE, with one Important.** The Important is a reporting-silence +
false-comment defect inside the very pattern Task 10 reuses — no crash, no leak,
no golden touched — so it can be a targeted fix at the Task 10 start (it lives in
the function Task 10 will be reading anyway) rather than a fix round here, at the
team lead's option. Everything the plan pinned is real and lands as ordered.

## The assigned scrutiny, point by point

**1. The first stop: the in-flight-after-stop pin.** Sound, and the golden means what
it says. The GLib timeout source is **not** removed at `Driver.stop` — nothing tracks
effect-armed sources, deliberately — so it stays armed and fires. Until it fires it
retains: source → callback closure → `Ui_effect` continuation → the bind chain →
(via the perform-time plumbing) the driver's graph. That retention is bounded by the
source's own life, and **every effect-armed source is one-shot**: both `after`'s and
`on_idle`'s callbacks return `false` unconditionally (gtk_effect.ml), so the source
is destroyed after one fire and the closure freed. No periodic effect source exists;
the scheduler's repeating tick is driver-owned and removed by `Scheduler.stop`.

What "log-and-resolve" resolves *into*: `Callback.respond_to callback ()` runs the
rest of the bind chain **synchronously on the GLib frame** (see ui_effect.ml's
`Private.make`: `on_response = fun r -> callback r; Ignore` — the continuation runs
during that call, not inside `Expert.handle`; see Important 1). A plain inject
enqueues an action into `Bonsai_driver`'s queue — after stop the observers are
invalidated but enqueue touches none of them, so it is silently absorbed (queue
grows once, bounded, nothing stabilizes; the schedule_event doc's "a value nothing
will ever read"). An observer-reading effect (a `peek`) would raise, be routed to
the perform-time on_exn, and end in the resolver's backstop — swallowed, nothing
crosses into C. No frame is scheduled into the stopped scheduler: the hooks are
already gone so `request_frame` is never called, and even called directly,
`Driver.request_frame` guards on `stopped || broken` (driver.ml:31-34) and
`Scheduler.request_frame` on `stopped` again. The live pin drives exactly this:
armed 40 ms `after`, `stop`, `resolved yet: false`, the dropped-hooks stderr line,
`resolved after stop: true` — the ref moved, nothing raised, nothing was requested.

Why this cannot recreate the m2-backlog:708-717 leak: that shape is a
*process-lifetime* global (the hooks cell) holding a closure over a stopped driver
forever. Here the global half is dropped first thing in `Driver.stop`
(`t.drop_effect_hooks ()`, then reset so a second stop cannot touch a successor's
registration — driver.ml:288-292), and the only post-stop retention is the armed
one-shot source, gone at first fire. Confirmed both registrars hand the drop over
(loop.ml:70, embed.ml:136) before the first frame.

**2. The hook cell.** Last-wins register, `phys_equal`-guarded unregister on a
`unit ref` token (gtk_effect.ml `For_runtime`) — the guard is exactly the
`unregister_stack`/`unregister_window` discipline the comment cites (remove only
while the entry is still yours; the "stack" in "stack registry" is GtkStack, not a
LIFO — there is no restore-on-pop anywhere in that discipline, so the analogy is
accurate). A-then-B, A stops: A's drop no-ops on the identity guard, B's hooks
survive — **pinned** in live_effects' last block (reg1 displaced, reg1's drop run,
`on_idle` resolving through reg2, `frame requests = 1`; the count also proves reg1's
`ignore` requester was not the one used). B stops: cell cleared. The converse gap is
Minor 1.

Embed-inside-start: whoever registered last wins the slot; the loser's stop cannot
clobber (guard), but see Minor 1 for what the *winner's* stop leaves behind.

The implementer's deviation (drop at `Driver.stop`, not literally at
`For_start.clear_app`): the reasoning holds on every path. `clear_app` has exactly
one call site in the tree (loop.ml:88), immediately preceded by
`Option.iter !driver ~f:Driver.stop` (loop.ml:87). If activate never ran, `driver`
is `None` and nothing was ever registered — `set_app` at loop.ml:19 precedes
registration and touches only the quit cell. So there is no `clear_app` execution
where hooks outlive the app cell. A literal clear at that site would indeed be
wrong — it would take a concurrently-live embed's hooks down, which the identity
guard exists to prevent.

**3. Perform-time arming.** Verified against ui_effect.ml itself: `Private.make`
builds an `of_fun` effect; **each** perform (`eval` of the `Fun` node) runs
`run_custom_function` afresh, constructing a fresh wrapped callback and a fresh
`Callback.t`, and calls the evaluator once. Two performs of the same effect value
(`on_idle` is one shared value) arm two independent sources, each closing over its
own callback; the only mutable state (`primary_cb_filled`, `raised_from_callback`)
is per-eval, created inside `run_custom_function`. No shared mutable state.

**4. The swallow-guard — where the Important lives.** The hard half of the
trampoline doctrine holds: the whole resolver body is `try … with _ -> ()`, both
eprintfs are individually swallow-guarded, and no path lets an exception cross into
C. But the comment's claim that "[Expert.handle] routes the continuation's
exceptions to [on_exn]" is **false for this ui_effect**: see Important 1. A raising
continuation is swallowed *silently*, and skips the frame request.

**5. `Clipboard.set_text`.** Leak-checked to the C stubs. ocgtk's `Value.create`
allocates a custom block whose finalizer runs `g_value_unset` when initialized
(ml_gobject.c `finalize_gvalue`, with the finalizer-depth guard) — the GValue and
its copied string are reclaimed by GC. `g_value_set_string` copies the OCaml string;
`gdk_clipboard_set_value` copies out of the GValue (transfer none) — this is the
plain copy-in path, not the fork-round GValue-copy defect (that was signal-marshal
territory; no marshalling here). `ml_gtk_widget_get_clipboard` refs the
transfer-none return before wrapping, balanced by the wrapper's unref finalizer,
and the clipboard is a display-owned singleton besides. No-context =
log-and-resolve: in the code (gtk_effect.ml `Clipboard.set_text`'s `None` arm);
the *log* is not goldened (Minor 3) — the golden pins only the success line, with
the plan-ordered comment saying why the assertion is thin.

**6. `Window.present`.** Synchronous `of_thunk` through `lookup_window`; the three
miss arms are all present and each logs-and-resolves (no hooks / `lookup_window =
None` under embed / key misses), on quit's precedent as the mli says. Pinned live:
the missing-key arm (its stderr line is in the golden, captured by the scoped dup2)
and the is_active flip. Golden lines to causes: `before present: active = a:false
b:true` — b is mount-order winner because `on_window_created` presents during the
mount walk and b is presented last (Task 8's last-present-wins pin, reconfirmed by
the `pump_until ~ready:(active "b")` gate); `after Window.present "a"` — the effect
through `lookup_window` → `W.Window.present`; the `"zzz"` line — the missing-key
arm verbatim. The no-hooks and under-embed logs are code-read only (Minor 3).

**7. The plan's test/handle line.** The implementer's call is right and the flag was
the right move. Verified: `test/handle/dune` links `bonsai_gtk.vtree` +
`bonsai_gtk_test` (+ bonsai/bonsai_test), not `bonsai_gtk`; the dune header and the
plan's own Global Constraints state the no-straddling rule; ci.sh's per-package
`-p` builds (lines 73-83) are what would break a straddling directory. The
compensating pins exist: the `executables` stanza in test/live/dune is ungated, so
`dune build @all` (ci.sh line 54) compiles live_effects.ml — existence and types —
on every run; and the opaque `<handler>` sexp rendering of effect-carrying attrs is
pinned across the handle goldens (test_handle.ml, test_node.ml, test_attrs.ml,
gallery sweeps). Nothing in the plan's intent is left uncovered; the spec-amendment
note belongs to Task 13 as the report says.

**8. Can live_effects wedge CI?** No. `drain` is non-blocking and bounded (10k
iterations); `pump_until` uses blocking iteration but is triple-bounded — a 10 s
GLib timeout watchdog (which wakes the blocking iteration when it fires), a 100k
iteration cap, and a `TIMED OUT` print that turns a stall into a golden diff, i.e.
a loud red, not a hang. No sleeps anywhere (the live_input doctrine). The suite
registers hooks exactly as `Loop.start`'s activate does (shape-identical closures:
`Driver.request_frame` / `List.Assoc.find (Driver.windows d)` / root-or-first-
window) with the comment saying why `start` cannot be used. The census is right:
19 rules, 15 locked, the new rule carries `(locks x-display)` (it presents and
reads focus), and both the dune header and ci.sh comment were updated to
fifteen-of-nineteen.

**9. Clamp, after(0), determinism.** The clamp is `Int.max 0
(Time_ns.Span.to_int_ms span)` — present, untested (Minor 4). `after 0` arms a 0 ms
timeout (G_PRIORITY_DEFAULT), which outranks idle sources — but nothing in the
golden depends on relative source priority: the ordering claim is carried entirely
by `bind` (`on_idle` is not armed until `after` has resolved), the `order` list is
appended at resolution, and `pump_until` gates on count, not time. Deterministic
under load by construction, not by luck. Forced re-runs: the implementer's two plus
**two more by this review** under `nix develop -c` (`rm -f output_*.txt` +
`BONSAI_GTK_LIVE_TESTS=1 xvfb-run -a dune build @test/live/runtest`), both 0 diffs
— four total.

**10. ci.sh at d0a9d36**: exit 0, tail ends `all green` (run by this review; bench
lines nominal, e.g. `bench: 0.0084 ms embedded, 0.0084 ms windowed, ratio 1.00
(bound 1.2)`; only the usual xvfb libEGL noise). **a100495**: diffstat is exactly
the five files of the six minors and each maps one-to-one — before_keys pair
deleted (minor 1), latch line reworded to claim only "unhandled" (minor 2) and
wrapped in `try … with _ -> ()` (minor 3), the hand-driven `run_fixups` block
executing the missing-key raise with the emptied-queue destroy (minor 4),
`tools_before` in the after-stop probe (minor 5), the attr-side divergence sentence
(minor 6). Nothing more in the commit.

## Findings

### Important

1. **A raising continuation is swallowed silently, and the resolver's comment
   misstates the mechanism — in the exact pattern Task 10 reuses.** In this
   ui_effect, `Ui_effect.Private.Callback.respond_to callback ()` *is* the
   continuation run: `on_response` invokes the perform-time callback chain before
   returning `Ignore`, so by the time `Ui_effect.Expert.handle ~on_exn` is applied
   there is nothing left to evaluate but `Ignore`, and that `~on_exn` (the
   "exception resolving Effect.%s" line) is unreachable for continuation raises.
   A raise in application bind code is routed to the *perform-time* on_exn instead
   — which for every production perform path is `Bonsai_driver.schedule_event`'s
   `Exn.reraise` (bonsai_driver.ml:248-251, and the same in `flush`'s
   apply_action) — re-raised out of `respond_to`, and eaten by the resolver's
   outer `try … with _ -> ()` with **no log line**, also skipping
   `hooks () → request_frame` for that resolution (injects that landed before the
   raise wait for the 60 fps tick; under an `fps <= 0` "never tick" driver they
   wait forever). The doctrine's hard half holds — nothing crosses into C, the
   loop survives — but the codebase's swallows are report-then-swallow everywhere
   else (`Signals.dispatch_payload` → `on_exn` with the node path;
   `guarded_frame`'s eprintf; the w_window latch), and this one is silent. Fix
   shape (small, contained in `resolve_from_glib`): run `respond_to` under its own
   `try`, log via the existing named eprintf on catch, and fall through to the
   `hooks ()` match either way — the comment then becomes true. Fine to land at
   the Task 10 start, since Task 10 edits this file and inherits the pattern for
   dialog continuations, which run much heavier application code.

### Minor

1. **The surviving registrant is orphaned when the last registrant stops.** With
   two live drivers (two embeds, or embed-inside-start), the single global slot
   means: while both live, the earlier one's async resolutions request frames on
   the *later* one's driver and its `Window.present` gets the embed answer; when
   the later one stops, the cell clears and the survivor's effects log "outside a
   running Bonsai_gtk app" while its app is still running. Masked at the default
   60 fps tick (both entry points), real under `fps <= 0`. The guarded pin covers
   first-stops (the plan's order); the converse is undocumented. One sentence at
   `For_runtime`'s mli ("the slot is single: the most recent registrant owns
   effect resolution, and its stop leaves earlier live drivers hookless") — plus a
   backlog line if a real multi-embed story is ever wanted.
2. **The orphan log means "no hooks at all", not "this driver's hooks are gone".**
   If a *later* driver's hooks are current when an orphaned effect fires, the
   resolution silently requests a frame on the wrong driver and prints nothing
   (harmless: `request_frame` is guarded and cheap, injects went to the dead
   graph). Worth one comment sentence at the `None` arm in `resolve_from_glib`,
   since Task 10 copies this resolver.
3. **Two of the three `present` miss logs and the clipboard no-context log are
   code-read only.** The no-hooks arm is one `Ui_effect.Expert.handle` line in
   live_effects' tail (after stop, inside the dup2), if wanted; the under-embed
   arm genuinely needs an embed and can stay unexecuted.
4. **The negative-span clamp is untested.** `after (-5ms)` resolving is one golden
   line; the clamp is one `Int.max` and low-risk either way.

### Out-of-scope (backlog)

5. **The pattern's frame-request is advisory under ticking drivers.** Both entry
   points tick at 60 fps by default, so `request_frame`'s absence (Important 1's
   skip, Minor 1's misdirection) is only observable under `fps <= 0` — worth
   remembering when someone proposes making the default tickless (m2-backlog
   already carries the 16 ms cadence line).
6. **The report's "written first, failing" is process narrative the range cannot
   show** — the suite commit lands after the implementation commit, per this
   branch's squash convention. Noted for the record, not against anyone.

## Process

Tree left as found (the untracked SDD reports and the bd-hook's
`.beads/issues.jsonl` delta predate this review; nothing else changed). No
commits, no pushes, no bd operations. Builds run one at a time in this checkout:
ci.sh once at d0a9d36, then the two forced live re-runs.
