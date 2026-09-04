# Task 14 review — verifying the report against the recovered logs

**Verdict: the evidence supports the substance — two green end-to-end gates from a
genuinely cold switch — with four precision corrections; nothing the logs contradict is
claimed, but three claims are recovered-context rather than log-borne facts and should
read that way.** The cold tree is deleted; what survives is `ci-run1.log` /
`ci-run2.log` (96 lines each) and `setup-switch.log` (854 lines), preserved beside the
report.

## Verified against the logs (my reads and diffs)

- **Both runs end `all green`** — literal final line of each log — after the full stage
  list the report names, in order: nix ocgtk pin build + tests, format, build,
  committed opam files, pure + headless, per-package `-p` builds, live under xvfb,
  example smoke.
- **The run-to-run diff is exactly what the report says**: bench-timing lines (the
  quoted flow-box 0.434-vs-0.357 example is real), plus PIDs and wall-clock timestamps
  inside the Gtk stderr noise — no assertion or content line differs. Every bench ratio
  in both logs is inside its stated bound (list/flow/stack/text ratios ≤1.16 vs bound
  5; embed 0.99 vs bound 1.2).
- **The cold switch was real**: `setup-switch.log` builds the opam switch from scratch
  inside the scratchpad clone (`…/scratchpad/bonsai_gtk-cold/` throughout), pins ocgtk
  from the checkout's `.ocgtk-src`, and ends "Switch ready." The pin hash the report
  names (`72cc75f2`) matches `ocgtk-pin.json` at head and the ledger header.
- **The timeline is consistent**: `9ee1fd6` committed 2026-09-01 17:32:30; run 1's
  in-log timestamps span 17:50:03–17:50:33, run 2's 17:51:11–17:51:40 — after the fix
  round, ~1 minute each, back to back.

## Corrections (precision, not substance)

1. **"The one mid-log `exception in frame`" is two, per run** — at two paths
   (`root/0/1` and `root/1`), both the Task-8 placement-rejection message. Both appear
   byte-identically in both runs and both runs end `all green`, so both are expected
   rejection-test output, not failures — but the report's count is wrong, and "the
   golden's expected line" is more than the logs can show (they show the lines are
   stable across runs and non-fatal; whether a golden compares them is a code fact, not
   a log fact).
2. **"Fresh clone at `9ee1fd6`" is consistent with, not proven by, the evidence.** No
   surviving log names a commit. The timeline (clone after 17:32's `9ee1fd6`), the
   Task-8-era exception message, Task 10's dialog messages and Task 11's CSS parser
   warnings all corroborate an M3-head clone; and since `db26888..9ee1fd6` is
   docs-and-comments only, the build facts proven are the same either way. Reword as
   "at the branch head (corroborated; the log carries no hash)".
3. **The mtime claim is dead.** "The log mtimes bound the ci.sh runs at ~1 minute" —
   the preserved copies are all mtime 2026-09-04 16:36 (the recovery); whatever the
   originals said is gone. The *in-log* Gtk timestamps independently support ~1 minute
   per run; cite those instead. Likewise the stated completion times (17:50:59,
   17:52:06) appear in no log and should be attributed to the recovery context.
4. **No exit codes survive.** The logs end `all green` with no recorded `$?`; the
   report's framing (final line as the success criterion) is the right one — just note
   that "exit 0" for these two runs is inferred from the script's success tail, unlike
   Task 13's directly-checked run.

## Against the plan's own bar

The plan asked: scratch clone + setup-switch at the pin, ci.sh twice back to back
(golden-caching asymmetry), and the loaded-run 5/5 determinism bar. The first two are
evidenced (run 2's byte-identical assertion lines are exactly what the second-run
caching check wants to see). **The loaded-run 5/5 line has no surviving evidence and
the report — correctly — does not claim it**; the controller's cold-then-warm reading
is recorded as the deviation. Flagging so the milestone close does not later cite
Task 14 for the 5/5 bar: what stands for load determinism is the M2 record plus run 2.

## Process

Read: task-14-report.md, both ci logs in full, setup-switch.log head/tail/pin region,
the plan's Task 14 section. Diffed the run logs myself; checked bench bounds line by
line; checked pin hashes across ocgtk-pin.json history (`3a87d1c` → `6a00f3e`). One
side-finding routed to task-13-review's re-review section: `docs/m3-backlog.md:348`
names the stale pre-round-2 pin hash. No builds beyond the Task-13 re-review's fmt +
headless at `9ee1fd6`; tree left as found.
