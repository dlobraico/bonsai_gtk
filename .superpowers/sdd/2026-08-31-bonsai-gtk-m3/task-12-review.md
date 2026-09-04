# Task 12 review — gallery, examples, and the sweeps

Range `002599f..353cc96` (4e22ea0 the Task-11 review items, a9baba5 the re-exports,
74851ac the gallery reconciliation, 353cc96 chrome.ml + smoke), reviewed against the
plan's "### Task 12", task-11-review.md's three Importants + three Minors, the ledger's
Task 2/Task 4 carries, and task-12-report.md. Claims verified against the code, the
sweeps' own derivation, and one full ci.sh run at 353cc96.

**Verdict: APPROVE — the reconciliation is real on both sides, the re-export gap is
closed and proven by the examples themselves, chrome.ml is exactly the plan's M3
counter, and all six Task-11 items landed with nothing extra — with three Minors, all
comment/doc scale, and three of-record notes.**

## The assigned scrutiny, point by point

**1. The re-exports (a9baba5).** Complete, and proven the strong way.

- *Checklist*: `Action_spec`, `Menu`, `Trigger`, `Position` join the module as four
  module equations (`src/bonsai_gtk.mli:56-64`), style-identical to the input-type
  re-exports above them (no signature duplication). The types those four need are
  already public: `Trigger.create` takes `Modifiers` + `Keyval` (both re-exported since
  M2), `Action_spec.kind` carries only `Ui_effect` (via Bonsai), `Menu` is
  self-contained, `Click_response`/`Key_response`/`Phase` were already exported. The
  effects half was never gapped: `Effect.Alert_dialog.show`, `Effect.Window.present`
  etc. live in `bonsai_gtk.mli:89-136`. Vtree modules still not re-exported —
  `Handler`, `Attrs`, `Events`, `Placement`, `Action_resolution`, `Kind`, `Children`,
  `Reconcile` — appear in no public constructor signature; they are machinery.
- *The examples are the proof*: `grep Bonsai_gtk_vtree examples/` is empty, and both
  no-ocgtk executables link `(libraries core bonsai bonsai_gtk)` only
  (`examples/dune`). gallery + chrome use every M3 feature (point 2) and build under
  `dune build @all` — so every needed name is reachable through `Bonsai_gtk` alone.

**2. The gallery reconciliation (74851ac).** Both trees verified by count.

- *M3 surface, from the diff against the M2 base (`c2580b5`)*: 5 kinds (Windows,
  Header_bar, Action_bar, Popover, Menu_button) and 8 attrs (autofocus, actions,
  css_provider, shortcut, on_cursor_moved, on_closed, on_close_request,
  on_contains_focus_changed).
- *Example tree, hand-counted at 353cc96*: all 13 appear in `examples/gallery.ml`
  (chrome.ml independently covers windows/header_bar/menu_button, autofocus, actions,
  shortcut, on_close_request). The Chrome page carries the bars and both menu-button
  modes; the root is `Node.windows` with the about window in the dialog-shell shape;
  the caret readout, the coarse focus signal, and the class-keyed `css_provider` (with
  the dark-blocks-belong-in-`?global_css` note) sit where the report says.
- *Handle tree*: untouched this task (no `test/handle` file in the diff — "needed
  nothing" is true), and its coverage is enforced, not asserted: the two sweeps derive
  their lists from `Kind.Variants.descriptions` and `Attr.Name.all` and golden an empty
  `missing` list (`test_gallery_sweeps.ml:46-73`) — no hand count anywhere, per the
  plan's verification line. ci green at 353cc96 is the handle-side count.
- *Autofocus placement*: on the two dialog-shaped windows, and the reasoning is TRUE —
  `Attr.autofocus` fires once on the mount frame from the fixup queue
  (`vtree/attr.mli:269-280`), and every stack page mounts on frame one, so an autofocus
  inside a hidden page would take (or waste, unretried) its one grab at app start. But
  the example's comment carries only the positive half ("the fire-once grab a freshly
  opened dialog wants", `gallery.ml:1060-1063`); the why-not-a-stack-page half lives
  only in the untracked report (Minor 1).

**3. chrome.ml as the plan's M3 counter.** Exactly the shape.

- *One list, visibly*: a single `Attr.actions ~scope:"app"` list of four specs
  (`chrome.ml:56-62`) is the only place handlers live; the GMenu's items name
  `app.increment`/`app.reset`/`app.notes`/`app.quit` and the two chords name
  `app.notes`/`app.quit` — menu, chords, and handlers off one `Action_spec` list, the
  Task 6 Command.Registry thesis made visible (and the header comment says so).
- *Totality*: `Alert_dialog.show ~cancel:0` with the pressed index bound back
  (`chrome.ml:31-41`); dismissal answers 0 → "kept", so the bind is total.
- *The raise path*: `if notes_open then Effect.Window.present "notes" else
  set_notes_open true` (`chrome.ml:45`) — model opens, effect raises.
- *Every close handled*: main's `on_close_request Effect.quit`, notes'
  `set_notes_open false`. No inert X anywhere (the always-veto migration honored); the
  gallery's two windows likewise.
- *What the smoke exercises*: mount under xvfb builds the whole tree — both bars, the
  GMenu (GtkMenuButton builds its PopoverMenu at `set_menu_model`, i.e. at mount), and
  action resolution, which raises at mount for a name resolving to nothing — plus the
  `?global_css` activate-time install and the veto wiring. It asserts exit 124 only
  ("came up and stayed up 3 s"); ci.sh's own comment states the limit honestly ("a
  'did not crash on startup' check, not a liveness assertion"). See of-record note 4
  on the "menus-crash-on-open" phrase.

**4. The smoke integration (353cc96).** The ci.sh diff is exactly the plan's step 3:
chrome.exe joins the pre-built list and the loop (`for ex in counter gallery embed
chrome`), nothing else. Bounded and headless-safe: `xvfb-run -a timeout -k 2 3` is the
watchdog, same as the other three. Census consistent: 21 `(alias runtest)` rules, 17
real `(locks x-display)` (19 grep hits minus the two in the header comment), matching
both "seventeen of the twenty-one" comments — and the taxonomy clause added in 4e22ea0
makes the header's stated rule actually derive 17 (toplevel-presenters + the two
dump-only suites + live_css), closing Task 11's Minor 4 arithmetic gap. chrome.ml adds
no live rule, so the census is untouched by the additions themselves.

**5. The Task-11 items (4e22ea0).** All six, nothing more — the diffstat maps
one-to-one onto the items:

- *I1*: `vtree/attr.mli` now says GTK clears the provider on every load (invalid CSS
  strips, not keeps), and the live suite dumps the emptied provider — goldened as
  `after the invalid load the provider holds: "" (cleared, not the previous sheet)`.
  The dump line is exactly the pin the review asked for.
- *I2*: the public `?global_css` paragraph on `start` (what it installs, dark blocks
  work via the mirror, activate timing, accumulation on a second start), with
  `Expert.embed` and `embed.mli` each deferring to it plus their two honest additions —
  default-display-only and create-time install. The deferral sentences are honest:
  embed's "the caller's GTK is up by this function's contract, so the
  raises-before-init hazard start dodges does not arise" is the true reason the timing
  differs.
- *I3*: the dead-dark-blocks paragraph at `Attr.css_provider` ("a dark block here is
  effectively always light; scheme-dependent styling belongs in [?global_css]").
- *M4*: the dune header's lock taxonomy gains live_css's clause (presents nothing,
  mutates the default `GtkSettings`) — and the count now derives (point 4).
- *M5*: the consumption pin is real and discriminating — the probe substring is
  `margin-top: 2px`, produced only by the dark block's `margin: 2px` expansion (light
  is `margin: 1px` → `margin-top: 1px`), goldened materialising on the flip and
  dropping on the flip back.
- *M6*: `set_gtk_interface_color_scheme` drives the primary mirror arm, its notify
  connection, and the precedence line (`interface-color-scheme light beats prefer-dark
  true: light`), all goldened.
- *The confession*: the briefly-committed red-format state is not reachable — the
  range contains exactly these four commits, and the format gate
  (`dune build @vtree/fmt @src/fmt @test/fmt @test_lib/fmt @test/live/fmt
  @examples/fmt`) passes at each of the four, checked one commit at a time. No red
  state survives for bisect; the amend landed before push as claimed.

**6. The Task 13 residual.** Stands correctly: `docs/m2-backlog.md:304-310` is
untouched by the range (no docs/ file in the diff), the report re-states "nothing
sweeps this file — the m2-backlog line stands and Task 13 re-records it", and the
commit message says the same. Not silently fixed, not silently dropped. Its "36
constructors against 38" figures are now stale — deliberately, per the plan's "do not
fix here" (of-record note 5).

**7. The run.** ci.sh at 353cc96 (inside `nix develop`, the only way xvfb-run is on
PATH): exit 0, tail `all green`. All sections green — nix pin, format, build, opam
files, pure+headless, per-package, live (xvfb; live_css demonstrably re-executed, its
invalid-CSS parser warnings are in the output), and the example smoke with four
launches (counter, gallery, embed, chrome), each required to hit 124. Only the usual
libEGL noise.

## Findings

### Minor

1. **The autofocus placement reasoning is half in-tree.** The choice (dialog windows,
   not a stack page) is right and the semantics back it — every stack page mounts on
   frame one, so a hidden-page autofocus spends its fire-once grab at app start — but
   the gallery's comment states only the dialog-wants-this half; the why-not-elsewhere
   half exists only in the untracked task report. One sentence in the about-window
   comment (or beside the stack) keeps the reasoning where the next reader of the
   example is.

2. **`Menu.section ~label:""` in both examples** (`gallery.ml`, `chrome.ml`) passes
   `Some ""` to `g_menu_append_section`, where omitting the optional `?label` passes
   `None` — the plain-separator shape the API already has. `Some ""` risks an empty
   header row and, in the examples meant to be copied, teaches the wrong idiom. Drop
   the `~label:""`.

3. **`examples/dune`'s header comment is one example stale**: "[counter] and [gallery]
   deliberately link no ocgtk … these two are where that is demonstrated" — chrome
   joined that stanza and demonstrates the same property. "These three", or name the
   stanza rather than the count.

### Out-of-scope / of record

4. **What "the run that would catch a menus-crash-on-open" precisely covers**: the
   smoke exercises mount — GMenu/PopoverMenu construction (GtkMenuButton builds its
   popover at `set_menu_model`) and action resolution (dangling names raise at mount) —
   so a startup crash anywhere in the menu machinery is caught; a crash strictly on a
   user popping the menu open would not be (nothing clicks under the smoke). ci.sh's
   comment already states the limit; the report's phrase is the plan's own. No action.

5. **`docs/m2-backlog.md`'s 36/38 constructor counts are stale** now that both trees
   grew — left deliberately per the plan's "re-record in Task 13, do not fix here".
   Task 13 owns the rewrite; recording here so it is not mistaken for drift.

6. **The re-export comment is a plain `(* *)` where the neighbouring group headers are
   odoc `(** *)`** — invisible to generated docs, which suits its process-narrative
   content ("found by Task 12's reconciliation"); noted only so the inconsistency is a
   choice of record rather than an accident.

## Process

Tree left as found (the pre-existing `.beads/issues.jsonl` delta and untracked SDD
reports untouched; this file is the review's one addition, per series convention). No
commits, no pushes, no bd operations. Builds one at a time in this checkout: the
per-commit format gates (four short `dune build @…/fmt` runs across a detached-HEAD
walk, restored to `m3` after), then ci.sh once at 353cc96.
