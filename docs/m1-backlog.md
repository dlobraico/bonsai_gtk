# Backlog carried out of M0

Items deferred by the M0 task reviews and the final whole-branch review
(`docs/superpowers/plans/2026-08-28-bonsai-gtk-m0.md`). None blocks M0; the
first three should land before M1 adds widgets.

## Do first in M1
- **Child ops: replace `~index` + `sibling_before` with `~after:(Widget.t option)`** fed
  from the `cur` list `Patcher.patch_children` already maintains. `sibling_before` reads
  GTK's live child list back, which breaks for containers that interpose children
  (`GtkListBox` rows, `GtkNotebook`/`GtkStack` pages). Gets more expensive per container
  added. (`src/widget_impl.ml`, `src/widgets/w_box.ml`, `src/patcher.ml`)
- **`Driver.frame` guards `stopped`, not `broken`**; `driver.mli` promises "nothing updates
  it again" after a frame exception. One-line fix. Also make `Driver.schedule_event` a
  no-op once broken so a frozen window doesn't grow the effect queue.
- **Reentrancy-guard test** (`in_patch`): a `Native` impl whose `update` emits a signal on
  itself, patched under `Expert.Driver`, asserting nothing was scheduled. Load-bearing once
  `Entry`/`Switch` exist.

## API shape decisions before they become breaking
- Seal `Attr.t`/`Attr.Name.t` (and `Bonsai_gtk_test.Action.t`) in the public surface —
  every M1 attr is otherwise a breaking change for exhaustive matches.
- `Expert.Driver.root_widget : Widget.t option` cannot survive `Node.windows` (M3).
- `start ?flags` (spec §4.1) is unimplemented; `NON_UNIQUE` is needed for two instances.
- Per-kind unset defaults: `Unset Visible -> true` is wrong for `GtkWindow`.

## Tests worth adding
- GC/lifetime: remove a keyed child, `Gc.full_major`, assert the widget was finalized
  (weak pointer or a `Native` finalizer) — the spec's central ownership assumption.
- After-display spin regression (needs a frame counter under `Private`).
- Attr coverage is now live-tested; `Live_tree.dump` grows per widget.

## Plumbing / hygiene
- `scripts/ci.sh`: `git diff HEAD --exit-code -- '*.opam'` (staged drift).
- `scripts/setup-switch.sh`: the reinstall stamp keys on `rev`; a dirty `.ocgtk-src` at
  the pinned rev is not rebuilt — add a `git status --porcelain` check (also protects
  against the re-clone `rm -rf`). Spec §2.1's "local fork edits testable without a push"
  needs "then `opam reinstall ocgtk`".
- Flake: a gir_gen-capable shell so the fork's generator tests don't depend on
  `~/src/stavekeeper#girgen`.
- Node paths frozen at mount (stale in `on_exn` logs after moves); `Signals.slots` dead
  `ref`; `Driver.t.last` duplicates `root.node`; `mount` not exception-safe (bounded);
  `vtree/children.ml` has no mli; redundant `(deps …)` in `test/live/dune`; 16 ms tickless
  cadence hard-coded; `request_frame` doesn't cancel a pending `request_frame_soon`.

## ocgtk fork
- Six upstream PR drafts in `docs/upstream/` await approval; topic branches are pushed.
  Once merged upstream, rebase `bonsai-gtk`, re-run `nix build .#ocgtk`, move the pin.
- ocgtk's commit 2 hand-patches stubs commit 3's generator now emits; upstream may prefer
  regeneration (said in the PR text).
- The OxCaml `caml_alloc_custom_dep` branch of the GBytes accounting is only exercised in
  the opam switch, not in the stock-OCaml Nix build.
