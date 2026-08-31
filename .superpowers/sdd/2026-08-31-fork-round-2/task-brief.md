# Task: ocgtk fork round 2 — generator copy-out and ownership, then regenerate (bonsai_gtk bead TBD)

The fork checkout is `/home/dlobraico/src/bonsai_gtk/.ocgtk-src` (branch from `main` =
`649498b4`, which is also both apps' pin). Work on branch `r2-bindings`. Commit in logical
steps with the trailers `Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>` and
`Claude-Session: https://claude.ai/code/session_01Sg3Ci8U8kUKR8C3PL1pNSs`. **No push, no
merge, no `bd`, no pin bumps committed in the app repos** — you prepare patches; the
controller pushes and bumps after review. You have both checkouts to yourself, but only ONE
build at a time across them.

## Context — read these first

- `docs/m2-backlog.md` in bonsai_gtk, section "Still open on the fork" (~line 774 to the
  end): every item below is specified there in detail, with counts, file references and the
  review rulings that shaped it. Treat it as part of this brief.
- `.superpowers/sdd/2026-08-30-bonsai-gtk-m2/task-14-report.md` — how round 1 was done, and
  its "Checkpoint (reboot)" section has the exact opam-switch commands for testing bonsai_gtk
  against a patched fork vs. the pin (`_opam/.opam-switch/bonsai-gtk-ocgtk-rev` marker).
- The fork's `architecture/gir_gen/overrides.md` and `overrides/*.sexp` — the override
  mechanism round 1 used; extend it rather than hand-editing generated files.
- Upstream engagement is PAUSED by the user (PRs #173–#178 were closed 2026-08-31). Keep
  each fix a clean, self-contained commit so it can be cherry-picked into an upstream PR
  later, but open nothing upstream. Update the fork's `docs/upstream/README.md` to record
  the withdrawal and that the topic branches remain.

## The fixes (all generator changes + ONE regeneration at the end)

1. **Copy-out for by-value record out-params (the headline).** 153 stubs across 22 files
   declare a C stack local (`graphene_rect_t out2;`) and wrap its *address* via
   `Val_<type>(&outN)` — a read-after-return, i.e. UB (`m2-backlog.md:776`). Fix in the
   generator: allocate-and-copy on the way out, the way record converters already handle
   transfer-full returns. All 153 must close at once; a per-site fix is wrong.
2. **Free transfer-full `char*` returns.** The generator already `g_free`s transfer-full
   *arrays* after copying; the single-`char*` path leaks every call
   (`gtk_text_buffer_get_text` reproduced at 1 MB leaked per keystroke path;
   `m2-backlog.md:831`). Fix the generator's single-`char*` branch.
3. **Ref-counted non-GObject types.** The generator's transfer-full in-param `g_object_ref`
   (round 1, held back from the tree) would cast-critical on `GtkExpression` (6 sites) —
   which has `gtk_expression_ref/unref`, not GObject's. Likewise the 31 constructors
   (3 Expression + 28 `GskRenderNode` subclasses) wrapping fundamentals through
   `ml_gobject_val_of_ext` whose finaliser is `g_object_unref` — invalid cast + leak. One
   fix: teach `gir_gen` a table of ref-counted fundamentals (GtkExpression, GskRenderNode —
   check GIR for others reachable in the bound namespaces) with their own ref/unref, used by
   the in-param path, the constructor/return wrap path, and the finaliser
   (`m2-backlog.md:846,854`). This is a PREREQUISITE for regenerating at all: the generated
   tree is 34 files behind the generator, and regeneration drags the in-param class in
   (`m2-backlog.md:894`).
4. **GBytes returns (6 borrowed sites)** — `g_boxed_copy` because `Val_GBytes` adopts
   (`m2-backlog.md:864`). Already covered by gir_gen tests; falls out of regeneration.
5. **`gtk_drop_down_get_selected_item`** returns a bare custom block where the `.mli`
   promises an option — use `ml_gobject_val_of_ext_option` (`m2-backlog.md:867`). And
   `gtk_drop_down_get_expression` must stop `ref_sink`ing a GtkExpression (falls out of
   item 3) and answer `Some` when one is set — verify on GTK 4.22 (`m2-backlog.md:872`).
6. **Sink rule tightened to `GInitiallyUnowned` only** (9 stray sinks survive regeneration
   today, most in dead files; `m2-backlog.md:860`), and **borrowed-return path uses
   `g_object_ref`, not `g_object_ref_sink`** (correct by construction; task-14 re-review N2,
   `m2-backlog.md:882`).
7. **Expose `Gobject.unref` and bind `gtk_window_destroy` / `g_object_run_dispose`**
   (`ml_g_object_unref` exists with no `val`; `m2-backlog.md:876`). Small, unblocks better
   dispose tests.
8. Ride-alongs while in the area: delete the stray `transfer_strategy = Ts_none;` inside the
   doc comment at `gir_gen/lib/type_mappings.ml:256`; create the fork's `docs/dev-notes.md`
   that ten generated files already cite as the "re-apply on any vendor re-sync" list
   (collect the hand-applied hunks from round 1 + this round).

Explicitly OUT of this round: the GSList-as-GList typing (N4, pre-existing, builds clean),
the fork's ocamlformat pin, table-driving `test_transfer_container_lists.ml`, and anything
upstream-facing beyond the README note.

## Order and discipline

Generator fixes first, each with a gir_gen test where the harness supports it; then ONE
regeneration commit (generated churn isolated from hand-written changes so review can diff
the generator and spot-check the output); then the hand-verification commits. Check every
regenerated file you rely on for the known failure shapes (stray ref_sink, missing g_free,
val_ptr wrap of a stack local). Round 1's standing rule applies: check generated stubs
before trusting them.

## Verification you owe

- ocgtk's own suite at least as green as `main` (33/388 skips-adjusted at round 1 — record
  the numbers), incl. the display tests under xvfb.
- A minimal C-level or test-level proof for each class: the graphene copy-out (a rect read
  after a subsequent ocgtk call keeps its width — this is the `live_input.ml` canary
  flipping), the `char*` free (RSS flat over 200 whole-buffer reads of a 1 MB buffer —
  the reproduction in `m2-backlog.md:834`), the Expression constructor (no GLib critical,
  no leak under `Gc.full_major`), `get_selected_item` returning `None`/`Some` correctly.
- bonsai_gtk: reinstall the switch onto the patched fork per the task-14 report's commands,
  `nix develop -c ./scripts/ci.sh` green, AND `BONSAI_GTK_LIVE_TESTS=1` live suite green —
  then flip the two canary lines in `test/live/live_input.ml` (`survives` → true, drop the
  `box_of` workaround comment) as a *patch file* (`r2-canary.patch`), not a commit, since
  bonsai_gtk only takes it with the pin bump.
- Prepare `r2-pin-bump.patch` for bonsai_gtk (`ocgtk-pin.json` + `flake.nix` hash) and
  `r2-pin-bump-stavekeeper.patch` for Stavekeeper (`ocgtk-pin.json`, `flake.nix`,
  `scripts/setup-ocgtk.sh` if it embeds the rev) against the branch tip. Do NOT commit them.
- Restore the switch to the pin afterwards (the marker file tells you which state it is in);
  leave both app checkouts clean.

## Report

`.superpowers/sdd/2026-08-31-fork-round-2/report.md`: commits, the generator changes (each
with the rule it encodes), regeneration stats (files/sites per class), the proofs above with
their numbers, suite tallies before/after, deviations with reasons, patch file paths, and a
checkpoint section with the switch state. Write the report BEFORE your final message; return
its summary.
