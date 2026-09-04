# Task 14 — scripts/ci.sh end to end from a clean tree

Written by the controller from the implementer's completed runs: the implementer (who
carried Tasks 1–13) executed both passes on 2026-09-01 but stalled twice before writing
this report; the evidence was recovered from the cold checkout on 2026-09-04.

## What ran

A genuinely cold reproduction, stricter than the plan's minimum:

1. Fresh clone of the repo at `9ee1fd6` (the branch head) into the session scratchpad
   (`bonsai_gtk-cold`), no shared `_opam`, no shared `_build`.
2. `./scripts/setup-switch.sh` built the local opam switch **from scratch** — OxCaml
   compiler, dune bootstrap, every dependency, the pinned ocgtk fork (`72cc75f2`) —
   ending "Switch ready." (`setup-switch.log`, preserved in this directory).
3. `nix develop -c ./scripts/ci.sh` — **run 1**, completing 2026-09-01 17:50:59 local:
   every stage ran (nix ocgtk pin build + its tests, format, build, committed opam
   files, pure + headless tests, per-package `-p` builds, live tests under xvfb, the
   four example smokes), final line **"all green"** (`ci-run1.log`, 96 lines).
4. `nix develop -c ./scripts/ci.sh` — **run 2**, warm re-run in the same checkout,
   completing 2026-09-01 17:52:06: identical stage list, **"all green"**
   (`ci-run2.log`).

## Evidence

- `ci-run1.log` / `ci-run2.log` / `setup-switch.log` preserved beside this report.
- The two run logs differ ONLY in bench timings (e.g. flow box 0.434 vs 0.357 ms at
  sel=1) — all within their stated bounds (ratio bound 5; embedded/windowed bound 1.2);
  every assertion line is byte-identical between runs.
- The TWO mid-log `exception in frame` lines per run are `live_embed`'s deliberate
  rejection tests, printing Task 8's updated placement message ("a Node.window may only
  be the root node or a child of the root Node.windows…") — deliberate rejections, not
  failures (that they match the goldens is the suite's claim; the logs alone show the
  suite passed).

## What Task 14 proved

- The repository at the M3 head builds and passes its whole gate from nothing on a
  machine with only nix + the repo: no hidden dependency on the developer's warm switch,
  caches, or environment. (GSETTINGS_SCHEMA_DIR, added by Task 10, is exercised on this
  path — the file-dialog live tests would abort without it.)
- The gate is stable across cold and warm runs (run 2's only deltas are timing noise).

## Cleanup

The 15 GB cold tree was deleted after the logs were preserved.

## Deviations and evidence limits (per task-14-review.md)

- Timings for the switch build were not captured stage-by-stage (the implementer's
  stall lost them). The preserved copies carry recovery mtimes, so mtimes prove
  nothing; the in-log Gtk timestamps independently support ~1 minute per ci.sh run.
  The 17:50:59/17:52:06 completion times come from the original files' mtimes read
  before recovery, and appear in no log.
- Exit codes are inferred from the success tails ("all green" after the full stage
  list), not separately recorded.
- No log names the commit; "clone at 9ee1fd6" is corroborated by the timeline
  (9ee1fd6 committed 17:32; runs 17:50/17:52) and by the cold checkout's HEAD as read
  before deletion.
- The plan's loaded-run (5/5 under load) bar has NO surviving evidence for this task;
  the milestone close must not cite Task 14 for it.
- The plan's "twice" is satisfied as cold-then-warm in one cold checkout, per the
  controller's reading recorded in the Task 14 dispatch.
