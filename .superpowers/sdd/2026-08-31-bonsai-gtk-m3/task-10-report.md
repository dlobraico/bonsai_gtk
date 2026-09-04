# Task 10 report — alert and file dialogs as effects

Commits `fbb8dee..6838142` (3): the Task 9 review Important + minors (`fbb8dee`), the
implementation + flake fix (`dc6e1a2`), the live suites (`6838142`). ci.sh green after
each; live suite forced 3× clean after the goldens landed.

## The Task 9 review first (`fbb8dee`) — the mandatory Important

**The fix that was almost silently not a fix**: my first application of the resolver
rewrite never reached disk (the editing script died on a later hunk after reporting the
early one), and the live pins I then wrote reproduced the review's bug *exactly* —
raising continuation silently swallowed, frame request skipped, pin TIMED OUT. With the
rewrite actually applied, both pins went green on the next run. The final shape:
`resolve_from_glib` runs `respond_to` under its own `try` (respond_to IS the
continuation run; a production raise arrives out of it via `Bonsai_driver`'s re-raising
perform-time on_exn), logs the named line on either path, and **falls through to the
frame request regardless** — injects that landed before the raise get their flushing
frame. The comment now states the real mechanism; `Expert.handle`'s `~on_exn` stays as
a backstop. Pinned live twice in `live_effects.ml`: the production path
(`schedule_event`; golden shows the continuation running up to the raise, the
`Reraised`-wrapped log line, a survivor effect after) and the route (a printing
re-raising on_exn sees the failure first; the frame-request counter still moves).

The four minors: `For_runtime`'s mli documents the single slot's converse (last
registrant's stop leaves earlier live drivers hookless; observable only under
`fps <= 0`), with a backlog line in `docs/m2-backlog.md` that also records the
advisory-frame-request note (review Out-of-scope 5); the resolver's `None` arm says "no
hooks at all" is not "this driver's hooks are gone"; the no-hooks `present` and
`set_text` miss logs are executed after stop inside the stderr capture (the under-embed
arm stays unexecuted — it genuinely needs an embed); `after (-5 ms)` resolving pins the
clamp.

## What changed (`dc6e1a2`)

**`flake.nix`** (pre-flight 2, the one-line fix the assignment hands me):
`GSETTINGS_SCHEMA_DIR = "${pkgs.gtk4}/share/gsettings-schemas/${pkgs.gtk4.name}/glib-2.0/schemas"`
on the default dev shell, with a comment saying why — `GtkFileChooserNative` reads
`org.gtk.gtk4.Settings.FileChooser` at construction and aborts the whole process
without it. Verified in-shell before use.

**`Alert_dialog.show ?detail ?cancel ~buttons message : int t`** — a real `GtkDialog`
(the §8 contingency: `AlertDialog` has no constructor in the pin), built at perform
time: coerced to `Window` for `set_transient_for` (the active window via
`Application.get_active_window` when under `start`, else none) and `set_modal true`;
content area gets plain-text labels with the `heading` css class and margins — never
markup, per the plan's injection note; `add_button label i` per button;
`set_default_response` to the last (skipped for `~buttons:[]`, which is legal and
dismissal-only). `on_response` maps every non-button id — Escape's DELETE_EVENT (-4,
pre-flight 2's measurement), the close button, any reserved negative — to `?cancel`
(default 0), removes the table entry, destroys, then resolves. Destroy-before-resolve
is a deliberate ordering choice against the plan's prose ordering ("resolves …, then
destroy"): a continuation that shows the next dialog never sees this one still up, and
pre-flight 6 measured destroy-inside-on_response clean.

**`File_dialog.{open_file,save_file,select_folder}`** — one shared builder over
`FileChooserNative` (the §8 contingency: `GtkFileDialog` cannot be launched in the
pin), one `filechooseraction` each; modal, transient the same way; `?initial_name` on
save via `File_chooser.set_current_name`; no initial-folder anywhere (`Gio.File` has no
constructor — documented omission in both mlis). `on_response`: ACCEPT →
`File_chooser.from_gobject` → `get_file` → `Gio.File.get_path` → `Some path`; anything
else → `None`; then `Native_dialog.destroy` and resolve.

**The keep-alive** (§2.2 by hand, the plan's boldface): each shown dialog lives in a
table from show until its response — the effect value is dropped at perform, and a
wrapper held only by C would be collected mid-show, the finaliser unref'ing the dialog
out from under the user. Tables, not slots (both families serially reentrant), keyed by
a monotonic id so re-entrant shows can never collide. `For_live_tests` (renamed from
the planned nondescript probe because `Ui_effect` already exports a `For_testing` the
include must keep) exposes the live alerts insertion-ordered plus a total count, via
`Bonsai_gtk.Private.Gtk_effect`.

**`resolve_from_glib` generalised** to carry the response value — the reuse Task 9's
pattern promised; `after`/`on_idle` pass `()`.

**Step 4**: the contingency documentation is the module docs themselves —
`Alert_dialog`'s header says "a real GtkDialog because AlertDialog cannot be
constructed in the pin", `File_dialog`'s says "FileChooserNative because GtkFileDialog
cannot be launched" — written to be quotable by Task 13's spec amendment, and the
public `Bonsai_gtk.Effect` mli carries user-facing versions.

## What the tests prove (`6838142`)

`live_dialogs.ml` (`(locks x-display)`; census sixteen of twenty, ci.sh comment
matches). No XTEST: `Dialog.response` fires `on_response` synchronously on the caller's
stack (pre-flight 6), so the suite drives everything programmatically:

- each of three buttons resolves its index; the dialog is destroyed after
  (`get_visible` on the held wrapper — pre-flight 3's rule, no destroy signals);
- **the keep-alive**: a `Gc.full_major` *between* show and response, dialog still alive
  and visible, then answerable; a second full major after response with the table
  empty and no criticals (golden cleanliness is the assertion) — the plan's
  "mid-show full_major line is in the golden";
- both dismissal routes map to `?cancel`: a raw DELETE_EVENT id with `~cancel:2` → 2,
  and a real `Window.close` with the default → 0;
- serial reentrancy: two alerts at once, answered out of show order, each resolving its
  own effect;
- three frame requests through the registered hook (the Task 9 pattern end to end).

`live_input.ml`'s dialog block (step 3): `select_folder` presented — the portal-less
fallback is a real X window, count 1 in the keep-alive — then a real XTEST Escape
(retry loop bounded, for the show-to-map race; a fresh toplevel takes focus on this
WM-less display) resolves `None` and the count returns to 0. The ACCEPT half is not
drivable — a click inside GTK-internal chooser furniture whose geometry nothing can
name — and the gap is stated in the block comment beside the golden, as the plan asks.

## Deviations

1. Destroy-before-resolve in both response handlers (above; plan prose ordered them
   the other way; pre-flight 6 measured the destroy clean).
2. The probe module is `For_live_tests`, not `For_testing`: `include Ui_effect` already
   provides a `For_testing` that the public `Effect` sig re-exports, and shadowing it
   broke the narrowed-module match.
3. `~buttons:[]` is accepted (dismissal-only dialog resolving `cancel`); nothing
   validates `cancel` against the button count — the int is the caller's index either
   way, and an effect never raises at perform. Documented.
4. The alert's transient parent under `Expert.Driver`/embed is none (free-standing
   toplevel); only `start` has an active window to name.

## Deliberately not done

- No `AlertDialog.choose` (fork-round-3 candidate, per the fact table).
- No file-accept live coverage (the stated gap).
- No spec amendment text (Task 13 quotes the mlis).

## ci.sh

`all green` (twice this stretch: after `fbb8dee` and after the Task 10 commits), plus
three forced live re-runs on the final goldens — 0 diffs, the Escape retry loop stable.
The bd hook's `.beads/issues.jsonl` delta remains uncommitted, as always.
