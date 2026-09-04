# Task 8 report — `Node.windows`: many toplevels, one tree

Commits `33ee075..1c85260` (6): the Task 7 re-review comment nits, steps 1–5 (vtree +
runtime + headless twins), step 6 (the Update kind-change arm), the five-golden
catch-up, step 7 (`live_windows.ml`), step 8 (examples + bookkeeping).

## What changed

**Task 7 nits first** (`33ee075`): live_input's disabled-chord probe comment now says the
log line is the evidence (a Control-modified key never inserts, so the entry's text
could not distinguish consumed from fall-through); test_menu.ml:194's "a radio cannot be
fired by a shortcut" absolute replaced with the feasible-but-unshipped wording.

**vtree** (`0e2e10b`): `Kind.Windows` is a nullary constructor — the one deviation from
the named-props-records constraint, documented on the constructor: OCaml has no empty
record, and a `unit` payload would be a third spelling of "nothing". `window_props`
grows `transient_for : Key.t option`, `modal` (false), `resizable` (true), defaults in
`Defaults.Window`, sexp-dropped. `Node.windows` rejects non-window children (naming the
index) and keyless ones (`require_child_keys`); `Node.window` gains the three args and
rejects `~transient_for` naming its own `~key` at the constructor. `Attr.on_close_request`
with the veto documented in the mli (including the once-latched stderr line).
`Events.for_kind`: `Window → [On_close_request]`, `Windows → []`.
`Events.transient_for_rejection` / `transient_for_self_rejection` sit beside
`autofocus_rejection` for the identical-by-construction property.

**Runtime** (`0e2e10b`):
- `w_windows.ml`: the anchor ruling as planned — a bare never-parented `GtkBox`, list ops
  all no-ops with each no-op's reason on the impl, `move = None`.
- `w_window.ml`: the close-request `Payload` whose GTK-facing bool is **constant true**
  (the veto on every path). The trampoline's `'r` is `` `Handled/`Unhandled `` rather than
  the bool itself, so the connect wrapper — which produces the `true` — can see the three
  no-handler paths (`declined = `Unhandled``) and report once per window: the latch is a
  per-connection ref, and `connect` runs once per widget. The plan left the channel open
  ("through the signals ctx … if nothing, a once-latched stderr line"); `Signals.ctx`
  has no report field, so it is the sanctioned stderr line, stated in the attr's mli.
  `modal`/`resizable` plain props at create/update; `transient_for` never written from
  create/update.
- `ctx.windows : (Key.t, Widget.t) Hashtbl.t`. Registration happens in `Patcher.mount`
  when `parent_kind = Some Windows` (the plan said "registered by w_windows's child
  mounts"; a `list_ops` closure has no ctx access, so the registration lives where the
  ctx does, keyed off the same mounts). No claims pass, unlike stacks — a live child's
  key cannot change (reconcile-by-key makes a rename a remove+insert), stated on
  `register_window`. Unregistration rides `release_kind`, which now takes the **node**
  rather than the kind (the key lives on the node); widget-guarded like the stacks', so
  a `Window` root (never registered) is a no-op.
- `transient_for` resolves in `enqueue_fixups`' Window arm — mount, patch *and*
  reassert-only passes, enqueued even for `None` so a dropped prop clears the widget —
  against `get_transient_for` (no cache, per the fact table). Missing key raises the
  Events string with the sorted existing keys; a record-update self-reference raises the
  self string (`Gobject.same` against the referencing widget).
- Placement: `Window` legal at root or under the root `Windows` (with the key backstop);
  `Windows` legal only at root; the non-window-child converse — all with one string each,
  copied into the handle.
- `Driver`: `check_root`'s `` `Window`` arm accepts both kinds, both messages updated
  (embed's rejection names them too); `root_widget` → `None` for a `Windows` root (the
  documented break; the M2 consumers all use `Window` roots and compile untouched);
  `Driver.windows` in the **model's** list order; `stop` drops `on_window_created` via
  `Patcher.drop_on_window_created` (the ctx is private, so the mutation is a function),
  closing the m2-backlog "closes over the GtkApplication" one-liner.
- `driver.ml`'s root kind-change comment updated: under `start` the `Window ↔ Windows`
  flip is now a reachable kind change at the root and works through the existing arm.

**Headless twins** (`0e2e10b`): `check_root` widened; `require_supported` walks the new
placement rules (the keyless check rides the window arm — one match cannot re-inspect a
pair the way the runtime's two blocks do, noted in place); `check_window_refs` resolves
`transient_for` against the tree between the walk and autofocus, matching the runtime's
fixup order; `check_autofocus` groups per toplevel — path prefix `root/i` under a
`Windows` root, whole tree otherwise; `Close_request key` fires the handler (missing key
and missing handler both fail loudly; the mli documents the divergence from the
runtime's swallow-and-report). Gallery tree wrapped in a windows root with a transient
modal dialog (`~transient_for` listed **before** its referent, pinning order-freedom);
sweeps gain a `Root_windows` placement and a Windows row — `props_changed=false`, so
Windows joins Overlay in the named never-updates list (it is nullary), comment updated.

**Step 6** (`5838cd1`): the `Update` kind-change arm no longer routes through `patch`'s
kind-change arm (destroy-before-remove); it spells out mount-first, then disarm →
remove → destroy → insert, M2's Remove-op discipline. The regression pin is
`live_lists.ml`'s new block — a keyed box child flips label→button in place, both
siblings keep their GObjects, the replacement is fresh. (A `windows` child cannot change
kind; the fix is general, the window was the finder, as the plan says.)

**Step 7** (`607264b` + `2ea89eb`): `live_windows.ml`, `(locks x-display)`, census
comments updated to fourteen of eighteen. Golden pins: creation order; `root_widget`
None; `Driver.windows` keys `prefs,main,tools`; dumps showing `modal`, `not-resizable`
and `(transient_for (main))`; transient parent by `Gobject.same`; **both** autofocus
grabs in one frame, one per toplevel, probed via `Window.get_focus` + descendant check
(pre-flight 5); last-present-wins after the mount burst and re-present taking it back
(pre-flight 4); the veto both ways — two swallowed closes on the handler-less window,
still `visible=true mapped=true`, report exactly once (stderr dup2'd to stdout around
the closes, flushed at the seams); a handled close destroying nothing itself, the
model's patch destroying for real, asserted by `get_visible`/`get_mapped` (pre-flight 3
— no destroy-signal assertions anywhere); identity across a list flip; `stop` taking
all windows down; and `Bonsai_gtk.start` over `Node.windows []` returning **0** under a
20 s watchdog — the declarative quit at the real GtkApplication boundary. The five other
suites' goldens caught up with the widened message spellings (comment-free diffs, one
count line in live_events).

**Step 8** (`1c85260`): `examples/counter.ml` and `examples/gallery.ml` gain
`Attr.on_close_request Effect.quit` with a comment saying why the X button now needs
one. `examples/embed.ml` untouched — its window is imperative, not a `Node`. Step 4's
question ("set_titlebar wiring?") reconfirmed **no**: `~titlebar` stays unshipped,
node.mli:1509's Task 4 note stands.

## What the tests prove

- Pure: constructor rejections (non-window child, keyless child, self-transient), the
  sexp drops, `equal_props` over the three new fields, `windows []` as a legal value.
- Handle: windows root accepted/rejected by root kind with the runtime's strings; the
  three record-update backstops; transient missing-key (with sorted existing keys) and
  self strings; per-window autofocus both directions; `Close_request` end to end
  including both failure modes; the whole gallery census (every kind incl. `Windows`,
  every attr incl. `On_close_request`, a lifecycle row per kind).
- Live: everything in the step 7 list above, plus the step 6 kind-change pin and the
  `Driver.windows` model-order pin.

## Deviations and findings

1. **`Driver.windows` order bug, found by its own test**: the first draft read the
   patcher's live list, which keeps insertion order for a `move = None` container — the
   flip block printed `main,tools`. The accessor now takes order from the node's child
   list, honoring its mli; the golden's `tools,main` line is the pin. (Insertion order
   was defensible doctrine, but the mli said "model's own list order" and that is the
   useful answer for an accessor no GTK semantics constrain.)
2. **Registration site**: in `Patcher.mount` under `parent_kind = Some Windows`, not in
   `w_windows`'s ops (no ctx there). Same mounts, same lifetime; `release_kind` takes
   the node to reach the key.
3. **`` `Handled/`Unhandled ``** as the payload's `'r`: the mechanism that lets the
   generic trampoline stay untouched while the spec's own wrapper implements both the
   constant-true veto and the once-per-window report. No changes to `signals.ml`.
4. **`windows []` pinned at the boundary only**: `start` over an empty list returns 0.
   A live drop-to-empty *transition* under `start`'s own loop is not driven (no input
   path into a running `g_application_run` without a WM); each window's destroy-on-drop
   is proven under the hand-driven driver, and zero-windows→release is the same GTK
   accounting either way.
5. **`Kind.Windows` nullary** — the named-props-records deviation, documented in kind.ml.
6. **Headless `Close_request` on a handler-less window fails loudly** where the runtime
   swallows-and-reports; divergence documented in the action's mli (matches every other
   action's missing-handler behavior).
7. The transient **self**-rejection (constructor + Events string + fixup + walk) is not
   in the plan's text; added because `set_transient_for (w, w)` is a GTK critical no
   later frame could make good — the reject-only-what-no-frame-could-fix rule.
8. First commit accident: a `git add -A` swept the untracked task-N report/review files
   and the hook's beads export into `47a4b87`; reset and recommitted as `0e2e10b` before
   anything built on it (the SDD files stay untracked, matching the branch's convention
   that only ledger entries are committed). `.beads/issues.jsonl` remains modified in
   the working tree by the bd hook — left uncommitted, not mine.

## Deliberately not done

- No `Effect.Window.present` / `lookup_window` (Task 9 reads `Driver.windows`).
- No README migration note for the veto (Task 13, per assignment).
- `examples/gallery.ml` not reconciled with the gallery *tree* (Task 12 carry stands);
  it gained only the close handler the ruling requires.
- `~titlebar` unshipped (reconfirmed).

## ci.sh

Full `nix develop -c ./scripts/ci.sh` green after the final commit (`all green`), all
sections; live suite additionally re-run 3× forced (rm outputs) — 0 diffs each, and the
new suite's focus-ordering lines were stable across all runs.
