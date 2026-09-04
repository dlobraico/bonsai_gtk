# Task 10 review — alert and file dialogs as effects

Range `2d92604..6838142` (fbb8dee the Task-9 review fixes, dc6e1a2 the implementation +
flake, 6838142 the live suites), reviewed against the plan's "### Task 10", pre-flight
corrections 2 and 6, task-9-review.md's Important + four minors, the ledger's Task 9
entry, and task-10-report.md. Claims verified against the code, the pin's stubs in
`.ocgtk-src/`, and — for the one behavioral question nothing written down answers — a
throwaway probe run under xvfb at the pin.

**Verdict: APPROVE.** No Importants. The Task-9 Important lands in exactly the
prescribed shape, both §8 contingencies are implemented and documented quotably, the
keep-alive is real and pinned, and the destroy-before-resolve deviation is safe on the
evidence. Two minors, both one-sentence/one-wrapper class.

## The assigned scrutiny, point by point

**1. The resolver fix (fbb8dee) is genuinely the prescribed shape.** `resolve_from_glib`
now runs `Expert.handle ~on_exn:log_exn (respond_to callback response)` under its own
inner `try`, catches the re-raise out of `respond_to` with the same named
`exception resolving Effect.%s` eprintf (itself swallow-guarded), and falls through to
the `hooks ()` match unconditionally; the outer backstop `try … with _ -> ()` remains.
That is the review's fix shape verbatim: own try, log on either path, frame request
regardless, and the block comment now states the real mechanism (respond_to IS the
continuation run; `Expert.handle`'s `~on_exn` stays as backstop for a deferring
respond_to). The two pins both distinguish fix from no-fix:

- *Production path*: `schedule_event` performs, so the raise comes back wrapped in
  Bonsai_driver's `Reraised "Unhandled exception raised in effect"` — that exact wrapper
  is in the golden. Against the unfixed resolver this line simply never prints → golden
  diff, loud red.
- *The route + frame request*: performed under a printing re-raising on_exn; the golden
  pins the on_exn seeing it first, the resolver's log, and `frame requested despite the
  raise: true` gated by `pump_until ~ready:(!hits > before)`. Against the unfixed
  resolver `hits` never moves; `pump_until` is triple-bounded (10 s GLib timeout that
  wakes the blocking iteration, 100 k iteration cap, and a printed `TIMED OUT` line) —
  so the implementer's reported TIMED OUT during development was the watchdog turning
  the stall into a golden diff. CI catches it; no silent hang is possible.

The generalisation to carry the response value (`callback response` instead of
`callback ()`) changes nothing about the guarantees: same catch structure, same
unconditional frame request; `after`/`on_idle` pass `()`, the dialogs pass the
`int` / `string option` answer. All four call sites verified.

The four minors each land where the review asked: the For_runtime mli paragraph + the
m2-backlog entry (Minor 1 + Out-of-scope 5 together); the None-arm comment (Minor 2);
the post-stop `present`/`set_text` miss logs executed inside the dup2 capture with
their golden lines (Minor 3; the under-embed arm stays unexecuted, as allowed);
`after (-5 ms)` pinning the clamp (Minor 4). fbb8dee's diffstat contains nothing else.

**2. The keep-alive tables.** Held from `Hashtbl.set` (before the response connect)
until the `on_response` callback removes the entry — removal before destroy, so a
re-entrant show from the continuation cannot collide with a half-dead entry, and the
key is a process-monotonic int (`next_dialog_id`), so two dialogs are always two
entries; the two-alerts golden answers the *second*-shown first and prints
`first=pending second=1` — the first's entry intact and its own continuation resolving
`0` afterwards. Two tables (alerts, choosers), probed insertion-ordered.

*Every exit path goes through `on_response`* — verified empirically, because the
worrying alternative doesn't exist: a throwaway at the pin (xvfb) measured that (a) a
WM/user close lands as close-request → response DELETE_EVENT (the pre-flight 2/6
measurement, re-exercised live by the suite's real `Window.close`), (b) direct
`Window.destroy` on a shown GtkDialog emits **no** response, but nothing in the runtime
or any app can reach the dialog to destroy it — the handle lives only in the private
table — and (c) destroying the transient **parent** does *not* destroy the dialog
(GTK4's destroy-with-parent defaults off, and this code never sets it): the dialog
stays visible and answerable. So no reachable path kills a dialog responseless; no
entry or continuation can leak. `Driver.stop` with a dialog showing: the dialog is
untouched (stop destroys only driver-owned windows; under Expert/embed the dialog has
no transient parent at all), stays up, and its eventual answer resolves under the
dropped-hooks log-and-resolve contract from Task 9. Coherent — but undocumented
(Minor 1).

**3. Destroy-before-resolve (the flagged deviation): safe.** In the chooser handler the
`result` is computed *before* `Native_dialog.destroy`: ACCEPT →
`File_chooser.from_gobject` → `get_file` → `Gio.File.get_path`, and per the pin's stubs
`ml_gtk_file_chooser_get_file` wraps `gtk_file_chooser_get_file`'s transfer-full return
(the wrapper owns the GFile, whose life is independent of the dialog) and
`ml_g_file_get_path` copies the path into an OCaml string via
`copy_string_g_free_option` — so by the time destroy runs, the answer is a plain OCaml
value with no GTK lifetime attached. No use-after-free shape. The alert's `answer` is
an int computed before destroy. The deviation's rationale (the continuation may show
the next dialog and must not see this one still up) holds, and pre-flight 6 measured
destroy-inside-on_response clean.

**4. Alert semantics.** The mapping is a range check, not a table:
`response_id >= 0 && response_id < List.length buttons` → the index, *anything else* →
`cancel`. Buttons are added with ids 0..n−1, so every reserved negative (−4
DELETE_EVENT, −5 OK, −6 CANCEL, −7 CLOSE, −8 YES, …) and every stray positive maps to
`cancel` — total by construction, no enumeration to be incomplete. Pinned: a raw
DELETE_EVENT id (via `responsetype_to_int`, no magic −4 in source) with `~cancel:2`,
and a real `Window.close` with the default. Button indices in order: `add_button
label i` under `List.iteri`, each of the three buttons pinned resolving its index.
Transient parent: `Option.bind !app ~f:get_active_window` — no window → `None` →
`set_transient_for None`, GTK-legal (the harmless "mapped without a transient parent"
Gtk-Message in headless runs is this arm). Plain text enforced by construction:
`Label.new_ (Some text)` (use-markup defaults false); no `set_markup` anywhere in the
dialog code — grep confirms the only `set_markup` in src/ is w_label's prop-driven one.
`set_default_response` to the last button, skipped for `~buttons:[]` (accepted,
dismissal-only — documented deviation).

**5. FileChooserNative specifics.** One shared builder, one `filechooseraction` per
entry point; `save_file`'s `?initial_name` goes through `File_chooser.set_current_name`
on the interface cast; modal via `Native_dialog.set_modal`, transient via the
constructor's parent argument (same `transient_parent ()`), so Native_dialog's own
transient handling is fed at construction — `set_transient_for` not needed. The flake's
`GSETTINGS_SCHEMA_DIR` is one attribute on the default dev shell pointing at gtk4's
compiled schemas, with a comment carrying pre-flight 2's measurement. Dev shell only is
right: ci.sh's header requires the dev shell for the whole gate, so the live and smoke
steps inherit it; `nix build .#ocgtk` is a separate derivation that was green before
this task; the `-p` builds only compile. No ci.sh step exercised a chooser before this
task (no example uses File_dialog; grep confirms), and the report states where the
variable is needed and that it was verified in-shell.

**6. The XTEST Escape block.** `select_folder` presented (count 1 in the golden), a
real `xdotool key Escape` in a retry loop — 40 attempts × 200 non-blocking iterations
plus a bounded `drain`, no sleeps, no blocking waits — resolves `Some None` printed as
a count-stable `Escape resolved None (attempts: bounded)` line, count back to 0. A
stall prints `select_folder: TIMED OUT` into the compared output. The ACCEPT-half gap
is stated in the block comment and in the report (the plan's "gap stated in the golden"
sentence was attached to the show-then-destroy downgrade path, which the working Escape
made unnecessary — see observations). Pre-flight 2's literal "the test asserts −4" is
discharged one level up: through the effect API the raw id is invisible, so the block
pins Escape → `None` while live_dialogs pins the raw DELETE_EVENT id mapping directly.
Intent covered.

**7. The For_live_tests rename: justified and consistent.** `ui_effect_intf.ml:257`
exports `module For_testing`, which `include Ui_effect` / `include module type of`
carries into Gtk_effect's signature — a second `For_testing` in the same signature
cannot exist. Grep: `For_testing` appears in src/ nowhere; the only uses are
live_dialogs.ml's local alias `module For_testing = …For_live_tests` (test-local,
legal, mildly cheeky) and the ui_effect sources.

**8. Out-of-order two-alerts.** Covered under §2 above: independent keys, independent
continuations, golden shows the second answered first with the first still pending,
then the first resolving its own answer.

**9. Runs.** ci.sh at 6838142 by this review: exit 0, tail `all green` (only the usual
libEGL noise plus the expected transient-parent Gtk-Messages from the headless dialog
suites). One additional forced live re-run (`rm -f output_*.txt` +
`BONSAI_GTK_LIVE_TESTS=1 xvfb-run -a dune build @test/live/runtest` in the dev shell):
0 diffs — with the implementer's three that makes five clean passes of the Escape
retry loop and the dialog goldens. Census verified by count: 20 `(alias runtest)`
rules in test/live/dune, 16 `(locks x-display)` lines, live_dialogs' rule locked;
dune header and ci.sh comment both say sixteen-of-twenty.

## Findings

### Important

None.

### Minor

1. **The dialog-outlives-everything story is real but untold.** Measured (probe, at the
   pin): a shown dialog survives both `Driver.stop` and its transient parent's
   destruction — destroy-with-parent is never set — staying up, still modal against the
   application's remaining windows, until answered; the answer then resolves under the
   dropped-hooks contract. Nothing leaks (no reachable path destroys it responseless),
   but the mlis say only "held from show until response". One sentence at
   `Alert_dialog`/`File_dialog` (or beside For_runtime's teardown paragraph) — "a shown
   dialog outlives Driver.stop and its parent; it resolves whenever finally answered" —
   would complete the teardown story the way Task 9's effects have theirs.
2. **The response trampolines run unguarded GTK calls before the guarded resolve.**
   Both `on_response` callbacks execute `Hashtbl.remove` + `Window.destroy` /
   `Native_dialog.destroy` (and the chooser's `from_gobject`/`get_file`/`get_path`
   chain) outside any try; only `resolve_from_glib` is guarded. A raise there would
   cross into C — the doctrine's hard rule. In practice none of these can raise on this
   path (the cast target is definitionally a FileChooser; destroy-inside-on_response is
   pre-flight-6-measured clean), so this is a uniformity nit, not a bug: wrapping each
   callback body in the same report-then-swallow shape the other trampolines use would
   make the invariant syntactic instead of argued.

### Out-of-scope / of record

3. **Headless/Expert runs print `GtkDialog mapped without a transient parent. This is
   discouraged.`** once per alert — inherent to the documented no-parent arm (deviation
   4), stderr-only, not in any golden. Cosmetic; a backlog line only if it ever annoys.
4. **The plan's "gap stated in the golden" phrase** belonged to the downgrade path
   (show-then-destroy) that the working Escape made unnecessary; the taken path's gap
   (no ACCEPT coverage) is stated in the block comment and the report. No action.
5. **The report's "written first, failing"** for live_dialogs is process narrative the
   commit range cannot show (suite commit lands after the implementation commit, per
   the branch's squash convention) — same note as Task 9's review, for the record.

## Process

Tree left as found (the untracked SDD reports and the bd-hook's `.beads/issues.jsonl`
delta predate this review). No commits, no pushes, no bd operations. Builds one at a
time in this checkout: ci.sh once at 6838142, then the throwaway probe (built and run
in the session scratchpad, not the repo), then the forced live re-run.
