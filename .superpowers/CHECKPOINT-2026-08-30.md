# Checkpoint before the server reboot — 2026-08-30

Everything durable is on disk: git branches, the SDD workspaces under `.superpowers/sdd/`
(briefs, reports, reviews, ledgers), beads (Dolt DB in `.beads/`), and this file. Only the
in-memory agents are lost; a fresh session recreates them from the ledgers and briefs.

## How work is run (so a fresh session can continue the same way)

Subagent-driven development: per task an implementer (opus) works from a brief, a reviewer
(opus) writes `…-review.md`, fix rounds answer every Important, a scoped re-review checks
just the fix commits, then the controller merges. Scripts:
`/home/dlobraico/.claude/plugins/cache/claude-plugins-official/superpowers/6.3.0/skills/subagent-driven-development/scripts/{task-brief,review-package,sdd-workspace}`.
Only ONE agent may build in a checkout at a time (`dune`/smoke collide). Stavekeeper's smoke
is `nix develop -c scripts/smoke-gui.sh` (Xvfb :99, ~5 min); bonsai_gtk's gate is
`nix develop -c ./scripts/ci.sh` (~1 min). Commit trailers:
`Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>` /
`Claude-Session: https://claude.ai/code/session_01Sg3Ci8U8kUKR8C3PL1pNSs`.

## Standing user rulings

- Commits on branches; local ff-merges to `main`; **push Stavekeeper main** and **push
  bonsai_gtk main/branches** are authorized. **The ocgtk fork may be pushed and the pins
  bumped** for M2 Task 14's binding fixes (ruling 2026-08-30) — never for anything else
  without asking.
- bonsai_gtk tracks its own beads (`bonsai_gtk-811` = M2 epic; `bonsai_gtk-5qv` = XTEST
  real-input tests follow-up). Stavekeeper epic for the port: `score-library-9ob`.
- User preferences: keyboard-friendly UX, single-window navigation, pages abutting in
  multi-up, Settings dialog for AI creds/model (stored in the config file, 0600; env
  overrides).

## Stavekeeper (`/home/dlobraico/src/stavekeeper`)

- `main` = `1622a82`, pushed. Contains today's merged work: Space-in-search fix, two-up
  spine, app icon + `co.lobrai.Stavekeeper` desktop entry, 3-up, Shell single-window
  navigation (Back/pop-out/Ctrl+W), Ctrl+K palette + `?` sheet + `/` + Ctrl+Q.
- **In flight: `feat/pieces`** (edit metadata from the viewer + piece editor; beads
  `score-library-bag`, `score-library-o8b`). Workspace `.superpowers/sdd/2026-08-30-pieces/`
  — brief, report, `review.md` ("Request changes": C1 stale piece record on second Ctrl+E;
  I1 unconfirmed cascading delete; I2 default piece deletable → whole-score delete
  re-pointed; I3 two 1-based page scales unlabelled; I4 last-piece guard missing in DB).
  **The fix round is committed**: `a50480b` (DB refuses to delete a score's only piece —
  I4), `be7689d` (viewer keeps the piece row current — C1; pending deletes with Undo and a
  Save confirmation — I1; default piece guarded with a DEFAULT chip — I2), `f5b4784` (smoke:
  stale-piece regression; Xvfb `-nolisten tcp`), `44af904` (docs: page scale — I3, pending
  delete, default-piece rule). HEAD `44af904`, tracked tree clean. Whether the full smoke
  ran on `44af904` is NOT recorded (the agent was stopped before writing its checkpoint
  section) — run it first. **Next**: scoped re-review of `git diff 89ef8b6..44af904` against
  `review.md`'s C1/I1–I4 (fresh reviewer; also look at the re-taken screenshots under
  `shots/` if present) → fix anything open → ff-merge to `main` → push → smoke on main.
- **Queued, briefs written, not started** (in this order; each branches from `main` after
  the previous merged): `.superpowers/sdd/2026-08-30-combine/task-brief.md`
  (`score-library-l89`, qpdf physical merge), `.superpowers/sdd/2026-08-30-settings/task-brief.md`
  (`score-library-8tp`, Settings dialog incl. AI page),
  `.superpowers/sdd/2026-08-30-ai-fill/task-brief.md` (`score-library-qhf`, reuses
  `stavekeeper_enrich`; reads provider/key from Settings).
- Open follow-up beads: `score-library-zmn` (palette subtitle query per keystroke),
  `score-library-1lf` (smoke run-2 timing fragility), plus older `xww orw 9bq yw4 b7r e38 fo8 1af bc2`.
- Tools preserved from the session scratchpad: `.superpowers/tools/spine-shot.sh` (Xvfb
  screenshot recipe: scratch HOME, import fixture, seed resume, Xvfb :98, ImageMagick
  `import`), `.superpowers/tools/icon-source.svg`.
- Known nuisance: orphaned `Xvfb` servers from reviewer probes squat displays; the smoke needs
  `:99` free (`pgrep -a Xvfb`; kill only orphans).

## bonsai_gtk (`/home/dlobraico/src/bonsai_gtk`)

- `main` = M1 (`86224d9`), pushed. **Branch `m2`** = M2 in progress; ledger
  `.superpowers/sdd/2026-08-30-bonsai-gtk-m2/progress.md` (one entry per task with rulings
  and carries — read it first), plan `docs/superpowers/plans/2026-08-29-bonsai-gtk-m2.md`
  (with "Pre-flight corrections" and the "Global Constraints addendum" at the top).
- Tasks 1–13 approved and on `m2` (last: `e7a1e7e` Task 13 fix; then plan commit
  `cff9914`… check `git log`). Briefs for Tasks 14–16 are generated in the workspace
  (`task-14/15/16-brief.md`).
- **Task 14 (fork patches) is COMPLETE** (report `task-14-report.md`, incl. a "Checkpoint
  (reboot)" section with exact commands). Fork checkout `.ocgtk-src`, branch `m2-bindings`
  on the pin `d98d9397`, five commits, **pushed to GitHub (`m2-bindings` at `4ea70268`)** at checkpoint time — the fork's
  `origin` is an HTTPS URL with no credentials, so push with the SSH URL explicitly
  (`git push git@github.com:dlobraico/ocgtk.git <branch>`) rather than changing the remote,
  which `setup-switch.sh` keys on: `7619876c` finaliser re-entry guard (marshaller refuses OCaml callbacks reached from
  a GObject finalizer); `e281d8f3` gir_gen `(nullable)` override + nullable-property class
  wrapper fix; `bcd39f14` nullable `Widget.set_name`/`Stack_page.set_title`/`Password_entry`
  placeholder; `a913c307` transfer-container list returns sink their elements (21 sites,
  incl. `gtk_list_box_get_selected_rows`); `4ea70268` 279 constructors stop ref_sinking
  already-transferred refs. ocgtk suite 33/388 green; bonsai_gtk `ci.sh` green against the
  patched fork (with `task-14-pin-bump.patch` applied) and against the pin. **The opam
  switch is on the PIN** (`_opam/.opam-switch/bonsai-gtk-ocgtk-rev`); a git bundle of the
  branch is at `task-14-ocgtk-m2-bindings.bundle`. bonsai_gtk `m2` HEAD `cc762d1`.
  Item 4d (transfer-full `char*` leak e.g. `gtk_text_buffer_get_text`; ~30 transfer-full
  in-params; GBytes; 11 more constructors; `get_selected_item`; `Gobject.unref`) is
  reported as findings for a later fork round.
  **Next**: review Task 14 (a reviewer over `git -C .ocgtk-src diff d98d9397..4ea70268` +
  the bonsai_gtk docs commit) → fast-forward the fork's `main` to `m2-bindings` and push →
  bump `ocgtk-pin.json` + `flake.nix` hash in bonsai_gtk (apply `task-14-pin-bump.patch`,
  reinstall the switch per the report's commands, `ci.sh`) → the same pin bump in
  Stavekeeper (`ocgtk-pin.json`, `flake.nix`, `scripts/setup-ocgtk.sh`; `nix build .#`,
  smoke) → drop the `get_selected_rows` prohibition note.
- Then Task 15 (docs; carries: task-13-review N8/N9, README Limitations, backlog roll-forward
  to `docs/m2-backlog.md`), Task 16 (clean-tree CI incl. `-p` builds and the real-display
  click-through of the gallery Input page), final whole-branch review split by area
  (core / controls / containers / tests — the plan's "How to execute" names the lenses),
  one fix wave, re-review, ff-merge `m2` → `main`, push.
- Standing rules learned this milestone (all in the ledger): check every generated stub for
  `g_object_ref_sink` before use; `Child_keys` keyed on the retained child widget; ghost
  keys inert until their child arrives (same-frame rule); no O(n) work on idle frames
  (bench-pinned); refuse–record–report via `Patcher.ctx.report` for unholdable values; never
  connect dispose-time handlers; `set_name` not `set_static_name`.

## Design canvas

https://claude.ai/code/artifact/7250f789-fb13-4249-bd36-0deb5e159d6e (pages: Stavekeeper,
Explorations, Dialogs, States).
