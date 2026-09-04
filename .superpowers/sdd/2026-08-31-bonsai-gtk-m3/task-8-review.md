# Task 8 review — `Node.windows`: many toplevels, one tree

Range `26e7bee..1c85260` (6 commits). Reviewed against the plan's Task 8 section,
Pre-flight corrections 3/4/5 + static answers, Global Constraints, the ledger, and
task-8-report.md. `nix develop -c ./scripts/ci.sh` re-run once at `1c85260` by this
review: exit 0, tail `all green` (the only stderr noise is the pre-existing expected
lines: the calendar bench's Gtk-CRITICALs, live_embed's announced frame exception, and
libEGL/DRI3 warnings).

## Verdict

**APPROVED.** No Important findings. The design rulings landed as written, the report's
claims checked out everywhere I traced them (including its own finding 1, which the
golden really does pin), and the one deviation the plan delegated ("implementer states
which, reviewer checks it") is stated and correct. Minors below; none needs a fix round —
they can fold into the Task 9 start like Task 7's did.

## The assigned scrutiny, point by point

**1. The always-veto implementation.** Sound. The GTK-facing `bool` is produced by
`w_window.ml`'s own connect wrapper and is constant `true` on *every* path: the wrapper
calls the generic trampoline first, pattern-matches its `` `Handled/`Unhandled `` result
(reporting on `` `Unhandled ``), and only then returns `true`. No double signal is
possible — GTK receives exactly one value per emission, and never `false`. An exception
in `fire` is caught inside `Signals.dispatch_payload` (src/signals.ml:78-95), reported
through `ctx.on_exn` with the node path, and surfaces as `` `Unhandled ``; the veto still
holds. (For this attr the raise path is close to unreachable anyway — the handler slot
holds `fun () -> eff`, pure construction.)

The latch is a per-*connection* ref created in `connect`, which runs once per widget at
mount — so it is per GtkWindow instance. A remove+re-add of the same key is a fresh
GtkWindow, a fresh connection, a fresh latch: the report re-arms. That is the right
semantic — the mli promises "a single stderr line per window", and a re-created window is
a new window.

"Stated in the mli": met. `Attr.on_close_request`'s doc (vtree/attr.mli:747-759) states
the veto, the once-per-window report, and that it is a stderr line because the trampoline
has no reporting channel. I confirmed `Signals.ctx` has `{schedule; in_patch; on_exn}`
and no report field, and signals.ml is untouched in the range — the report's claim is
accurate, and threading `Patcher.ctx.report` into `Signals.ctx` for one attr would have
been the larger change; the sanctioned stderr line is the plan's own named fallback.

**2. `release_kind` takes the node.** Exactly two call sites, both correct:
`src/patcher.ml:176` (mount's unwind — the node being mounted; registration is
`Gobject.same`-guarded on the widget, so an unwind before/after registration is safe
either way) and `src/patcher.ml:408` (`destroy` — `live.node`, the node the widget was
last patched to, whose key is the registered one since a key can never change while a
live lives; see 4). The Update kind-change arm never calls `release_kind` directly — it
goes through `destroy ctx l`, which carries `l`'s own node; the freshly mounted
replacement is a different `live` entirely. Teardown-during-mount-unwind: `unwind`
closes over the mounting `node`, and `unregister_window` removes the entry only while it
still maps to *this* widget, so a half-mounted windows child cannot drop a sibling's key.
No path hands `release_kind` the wrong node.

**3. The Update kind-change reorder.** No transient duplicate anywhere:

- *windows registry*: only children of a `Windows` parent register, and a windows child
  can never take the kind-change arm — every child is `Window` and `Kind.same_kind`
  ignores props, so a keyed match is always same-kind. (And `Reconcile`'s `Update` pairs
  identical keys only — reconcile.mli's matching rule — so no same-key remove+insert
  overlap exists either; removals are emitted before inserts besides.)
- *Child_keys*: keyed on the **widget**, not the key (child_keys.mli), and set/removed
  from `ops.insert`/`ops.remove` — which the new arm still orders remove-before-insert.
  The mount that precedes them creates the widget without touching any container table.

The mount-first ordering also loses no checking: `mount` runs `check_placement` itself
(patcher.ml:154), so bypassing `patch`'s kind-change arm skips nothing.

The live_lists pin: the golden proves the two siblings kept their GObjects AND the new
child is a fresh widget in the right position with the right content (the dumped tree
shows `before / "mid, reborn" button / after`). One honest caveat the block's own comment
already makes: for a box the old and new op orders are *observationally identical*, so
the golden pins in-place-semantics-plus-identity, not the disarm→remove→destroy order
itself — that part is certified by reading the arm. This is exactly what the plan asked
for ("the fix is general, the window was just the finder"); noted, not held against it.

**4. `ctx.windows` lifecycle.** The "a live child's key cannot change" invariant is real:
`Reconcile.diff` matches by key (`Update` only ever pairs an old and new item with the
same `Some` key; a rename is Remove+Insert), windows children are all keyed (constructor
+ walk + the runtime backstop), and `patch` never rewrites `live.node.key` outside that
matching. So no claims pass is needed, and both `register_window`'s defensive
`` `Duplicate`` raise and the mli comment say why. `unregister_window` is
identity-guarded like the stacks'.

`transient_for` as a fixup: enqueued on mount, patch AND reassert-only passes (the three
coverages: `note_interest` from mount/patch, `reassert_only` directly), enqueued even for
`None` so a dropped prop clears the widget, compared against `get_transient_for` (no
cache — fact-table Window row honored), written only on difference by `Gobject.same`.
The dialog-precedes-parent frame is pinned twice: live (`live_windows.ml` puts `prefs`
with `~transient_for:"main"` *first* in the list, and the golden asserts the transient
parent is `main`'s GtkWindow by identity) and headless (the gallery tree lists the
transient dialog before its referent; test_handle's windows-root test likewise).
Missing-key and self-reference strings are rendered by one `Events` function each and
raised by both the runtime fixup (`resolve_window`) and the handle (`check_window_refs`),
with the existing keys sorted for determinism — checked both constructions side by side.

**5. `Driver.windows` order (report finding 1).** The golden does pin it: after the flip
the model order is `tools,main` while the patcher's live list — insertion order for a
`move = None` container — would still say `main,tools` (the exact wrong output the report
says the first draft printed). `Driver.stop` is untouched by the accessor fix: it walks
the patcher's shadow tree, and the golden's `after stop: windows = 0, main visible=false`
plus the walk's structure cover it (see Minor 5).

**6. Placement, both sides.** Runtime: `check_placement`'s widened Window arm (legal at
root or under `Some Windows`, with the "Some Windows implies root" argument, which holds —
a below-root `Windows` is itself rejected before its children are visited), the `Windows`
root-only arm, and the converse block (non-window child; keyless child). Handle:
`require_supported` carries the same four rules with the same strings; I checked the
match-arm *ordering* on both sides for consistency (e.g. a Popover under Windows hits the
popover arm first in both copies, same message). The smuggling tests are real: nesting,
a non-window child, and a keyless child are each record-updated past the constructor and
rejected by the walk with the runtime's strings (test_handle.ml). Embed rejects both root
kinds with the updated message, pinned in test_handle, expected_embed.txt and
expected_driver.txt.

**7. `live_windows.ml` vs pre-flight 3/4/5.** All honored: destruction asserted only via
`get_visible`/`get_mapped` on held wrappers (no destroy-signal assertion anywhere in the
file); last-present-wins after the mount burst (`tools` active) and re-present taking it
back (`main` active), both behind `pump_until` watchdogs; both autofocus probes via
`Window.get_focus` + a descendant check (`Gobject.same f entry || Widget.is_ancestor f
entry`), one per toplevel in one frame. The veto both ways: two swallowed closes on
handler-less `tools` (still `visible=true mapped=true`, stderr dup2'd to stdout around
the closes and flushed at the seams — report line appears exactly once), and `prefs`'
handled close destroying nothing itself with the model's patch destroying for real.
`start` over `windows []` returns 0 under a 20 s watchdog that exits 3 on hang. The
golden's key lines each trace to one cause; the `(locks x-display)` rule is present and
the dune/ci.sh census comments say fourteen of eighteen, which matches.

**8. Headless `Close_request` divergence (position taken).** Loud-fail is the right
headless answer. Every other handle action fails loudly on a missing handler; a test
firing `Close_request` at a window with no `on_close_request` is exercising a handler
that is not there, which is a test bug the suite should name, not swallow — and the
failure message itself teaches the live behavior ("live, the runtime swallows the request
and reports once — the window stays open"). Documentation: the divergence is stated at
the **action** (bonsai_gtk_test.mli's `Close_request` doc) but the **attr**'s mli
describes only the runtime side. I judge that division acceptable — the attr documents
the runtime contract and the divergence belongs to the testing surface — but if the
team lead wants it at both, it is one sentence in attr.mli (Minor 6).

**9. Process.** Clean. `git log --name-only` over all six commits shows only
src/, test/, test_lib/, vtree/, examples/ plus a one-line ci.sh comment catch-up
(the locks census, belonging to step 7). No `.beads/issues.jsonl`, no `.superpowers`
files. The report's commit-accident story (47a4b87 reset and recommitted) left no residue
in the range.

**10. ci.sh** at `1c85260`: exit 0, `all green` (run by this review; log tail recorded
above).

## Findings

### Important

None.

### Minor

1. **Task-7 nit half-closed.** `33ee075` fixes both ordered comment nits exactly (and
   nothing more), but task-7-review.md's residual-nit text also named the adjacent
   `ignore (before_keys : int)` as a dead leftover — it is still there
   (test/live/live_input.ml:903,908). One-line deletion, next task's start.
2. **The unhandled-close report can misstate its cause.** The latched line says "no
   Attr.on_close_request on this window's node", but `` `Unhandled `` also reaches the
   wrapper on the other two declined paths — a handler that raised (already reported via
   `on_exn`, so the latched line is then a redundant, wrong-cause second report that also
   consumes the latch) and an in-patch emission. Both are practically unreachable today
   (the handler closure is pure construction; nothing emits close-request inside a
   patch), so this is a comment/wording tweak, not a behavior bug.
3. **`eprintf` on a C-called frame outside the catch.** The wrapper's report runs after
   `dispatch_payload` returns, directly on the frame GTK called; an `Out_channel` raise
   (e.g. EPIPE on stderr) would cross into C. Marginal, but the codebase rule is absolute
   — wrapping the report in the same swallow `ctx.on_exn` gets (`try … with _ -> ()`)
   would close it.
4. **The runtime's missing-key fixup raise is never executed.** `resolve_window`'s
   `None` arm (and what a raise inside `run_fixups` does to the frame — driver broken,
   queue cleared) is pinned headlessly via the shared string but driven by no live or
   hand-driven-patcher test. The string identity is by construction, so this is coverage
   of the *raise path*, not the message. A three-line hand-driven block in live_windows
   or live_patcher would close it.
5. **`stop` destruction probed for one window.** The golden asserts `windows = 0` and
   `main visible=false` after stop, but `tools_before` is in scope and unprobed; one more
   printf would make "stop takes all windows down" fully literal.
6. **Attr-side note of the headless divergence** (see point 8 above) — optional one
   sentence in `Attr.on_close_request`'s doc if both-sides documentation is wanted.

### Out-of-scope (backlog)

7. **Handle/runtime string divergence on a doubly-degenerate tree**: a *keyed*
   `Node.window` **root** record-updated to be transient for its own key raises the
   self string headlessly but the missing-key string ("keys that exist: none") at the
   runtime fixup — the registry is empty for a Window root, so `Gobject.same` never gets
   to answer. Requires record-update on a Window root; both raises are correct refusals,
   only the strings differ. Note beside the other identical-by-construction claims if the
   backlog sweeps strings.
8. **Presentation precedes transient resolution**: `on_window_created` presents each
   window during the mount walk, and `set_transient_for` lands in the fixup pass after
   it. Under xvfb the golden proves the end state is right; on a real WM a dialog could
   flash unparented for one frame. Purely cosmetic if ever visible; recording it here so
   the M4/real-display residual list can name it.

## What I verified beyond the assignment

- `drop_on_window_created`: the mutable-field + private-type + function arrangement is
  sound, `Driver.stop` calls it beside the `on_root_widget_changed` drop, and the mli
  reasoning (stopped driver never collectable, callback closes over the GtkApplication)
  matches m2-backlog's one-liner.
- The root `Window ↔ Windows` flip claim in driver.ml's updated comment: traced through
  `patch`'s kind-change arm — mount-first presents the new toplevels, destroy takes the
  old down and (Windows side) unregisters every child; `on_root_widget_changed` is a
  no-op under `start`.
- Sweeps: the `Root_windows` row's `child_ops=1I/0M/0R/1U` and `props_changed=false`
  are right for a nullary kind, and `Windows` joining `Overlay` in the named
  never-updates list keeps that list loud.
- `Kind.Windows` nullary: the deviation is documented at the constructor in both kind.ml
  and kind.mli, and `equal_props Windows Windows = true` keeps the sweep honest.
- teardown order: `Signals.disconnect` runs before `release_kind`'s `W.Window.destroy`
  (destroy stages, patcher.ml:398-408), so no close-request connection survives to a
  disposed window — the global signal-lifetime constraint holds for the new signal.
