# Backlog carried out of M3

Items deferred by the M3 task reviews, their rulings, and whatever M2 left open that M3
did not close. The ledger with every ruling is
`.superpowers/sdd/2026-08-31-bonsai-gtk-m3/progress.md`; per-task detail is in the
`task-N-report.md` and `task-N-review.md` files beside it. Nothing here blocks M3.

Renamed from `docs/m2-backlog.md` on M2's own reasoning (a file named for the previous
milestone describing this one's leftovers is a trap). As with the last rename, the
rewrite is total enough that `git log --follow` will not reach past it: the M2 history is
under `docs/m2-backlog.md`, the M1 history under `docs/m1-backlog.md`. File names from M2
entries are translated where M3's Task 1 split the files: `test/live/live_controllers.ml`
became `live_controllers_click.ml` / `_focus.ml` / `_key.ml` (and, since Task 7,
`_shortcut.ml`), its golden became the per-family `expected_controllers_*.txt`, and
`test/handle/test_gallery.ml` became `test_gallery_tree.ml` + `test_gallery_sweeps.ml`
(the golden stayed in `test_gallery.ml`).

## Closed during M3 (was "do first in M3")

Every bullet from m2-backlog's list, accounted for by name:

- **`Attr.on_click` can claim the event sequence.** `on_click`'s handler now returns a
  `Click_response.t` (`Continue`/`Claim`, each with an `_and` carrying an effect), and
  `Claim` runs `Gesture.set_state `CLAIMED` on the C stack while the sequence is current
  — the source-breaking retype was taken cleanly, no compat shim. Proven with real XTEST
  input: the claim silences the outer gesture, `Continue` reaches both
  (`test/live/live_input.ml`). Task 2.
- **The `contains_focus` query exists**: `Attr.on_contains_focus_changed`, the coarse
  focus signal beside the two fine ones — fires once when focus enters the subtree and
  once when it leaves, where enter/leave fire on every hop. Task 2.
- **The focus attrs take `?phase`**, and the asymmetry's real prize was taken with it:
  `Events.key_phase_rejection` generalised into `family_phase_rejection`, one rule over
  every controller family (the old name is deleted — it had no external caller). Task 2.
- **`TextView` exposes the cursor**: `Attr.on_cursor_moved` (a `notify::cursor-position`
  read-back on the buffer), which closes the controlled write's "approximate caret"
  caveat for a model that owns the caret. Task 3.
- **`Child_keys.length` exists** (clean-first counting), and the teardown paths it was
  wanted for are pinned live for all three containers — mutation-verified: the
  `| Flow_box _ -> ()` substitution that used to leave the goldens byte-identical now
  reads 3-not-0. Task 3.
- **The hidden-page divergences report once.** A `~visible_child`/`~current_page` naming
  a page GTK will not switch to (hidden child) is reported once through
  `Patcher.ctx.report` from a shared `Select_memo` (one memo shape serving stack and
  notebook), with the parked-frame cost measured sub-microsecond. Task 3.
- **A duplicate key in `~selected` is deduped and reported once** — the `Refusal`
  machinery reused for both list containers, and the report-once behaviour goldened.
  Task 3.
- **The list-pair functorise trigger fired.** The `Selection_memo` + `dedup_selected`
  block was the third byte-identical copy across `w_list_box.ml`/`w_flow_box.ml`
  (after the key→child map and the final-review containers I1). **Ruling of record:
  promoted from declined to scheduled — an early-M4 motion-only task**, deliberately not
  done inside M3 (no churn under the review lenses' feet); the both-copy goldens Task 3
  added are the safety net that makes the motion cheap. See "Do first in M4".
- **`require_slots` runs on the patch path** — an event attr a later frame adds
  conditionally onto a widget whose impl declared no spec for it now raises instead of
  silently never firing (`src/patcher.ml`'s patch, beside `require_specs`; the in-code
  comment cites the M2 entry). Task 2.
- **`close-request` exists on `Node.window`** — as `Attr.on_close_request`, under the
  always-veto ruling (see the README's migration note: this changes M2 behaviour).
  Task 8.
- The `after_of`-is-`O(index)` entry asked for nothing beyond remembering where the
  numbers had actually been; nothing in M3's measurements moved it. Carried under
  "Plumbing / hygiene".
- **Not taken, still open**: `Bonsai_gtk_test.Key_press` still models no propagation
  (unchanged by design — the handle has no hierarchy; live_input is where routing is
  real); `Keyval` is still curated (Task 7 added the punctuation the chords needed:
  comma, question, grave, brackets, minus, equal); **the behavioural half of the three
  nullable bindings is still untaken** (the library still writes `Some` — see "Do first
  in M4"); the `Activate_row`-class handle-honesty revisit is still owed (see "Do first
  in M4").

## Closed during M3 from other M2 carries

- **The `Update` kind-change arm's remove-after-destroy** (m2-backlog's "latent until
  `Node.windows` puts a `Window` in a list") — the arm now runs mount-first, then
  disarm → remove → destroy → insert, M2's Remove-op discipline; a `windows` child
  cannot in fact change kind, so the regression pin is a box in
  `test/live/live_lists.ml`. Task 8.
- **`Bonsai_gtk.start`'s `on_window_created` closing over the `GtkApplication`** —
  `Driver.stop` drops it beside `on_root_widget_changed`, through
  `Patcher.drop_on_window_created`. Task 8.
- **The two oversized test files split** — `live_controllers.ml` into per-family files
  and `test_gallery.ml` into tree + sweeps, as pure motion before M3 grew them (goldens
  byte-identical by concatenation/multiset). Task 1. The m2-backlog's five references to
  `live_controllers.ml` (its "Tests worth adding" plumbing entries and the XTEST
  close-out) should be read against the split files; the *content* of those entries is
  carried below unchanged.
- **`Expert.Driver.root_widget` cannot survive `Node.windows`** — it did not: it answers
  `None` for a `Windows` root (the documented M3 break; `Driver.windows` is the
  replacement), and every M2 caller renders a `Window` root and still gets `Some`.
  Task 8.
- **The paned-golden prediction was wrong** and the drop-removal is pinned by one new
  `(position ())` golden instead (no existing golden had a droppable `None`). Task 1.

## Do first in M4

- **The declarative focus model** — the largest named gap, again, and now with a
  concrete interim floor to build from: `Attr.autofocus` (fire-once, at most one per
  frame per toplevel) shipped in M3 for the palette/dialog open-grab — with one known
  hole: the mount-frame grab is a rootless silent no-op under `Expert.embed` (the tree
  is parented after the frame), ruled doc-only for M3 with the real fix filed as bead
  `bonsai_gtk-vdy` (a map/`notify::root` retry candidate) — and everything
  beyond it — who holds focus as *state*, `set_focus None` on page swaps,
  `select_region`, `~default_widget` — stays app-side or impossible. The port's
  remaining imperative focus calls are enumerated in the M3 plan's stavekeeper section.
- **The list-pair functorise** — scheduled, early-M4, motion-only (see above). The
  stack/notebook `Select_memo` pair is *not* a fourth instance; their drive blocks
  differ in the read-back and already share the machinery that should be shared.
- **An enabled-state story for conditional chords.** stavekeeper's `text_input_active`
  arms and `on_library` gates (shell.ml:601-648) need per-frame `Action_spec.enabled`
  recomputation semantics stated (and the disabled-chord fall-through measurement M3
  goldened is the routing half of the answer: a chord on a disabled action falls through
  to capture handlers and the focused widget). Named beside targeted shortcuts because a
  port meets them together. task-7 review, out-of-scope.
- **Targeted shortcuts** — feasible and deliberately unshipped: `Shortcut.set_arguments`
  is bound, so a shortcut could carry a `GVariant` and fire a radio action with a
  target. M3 rejects `"::target"` at `Attr.shortcut` and refuses a shortcut resolving to
  a `Radio` spec at the resolution walk; shipping removes both rejections and adds the
  argument in `Controllers.make_shortcut`. task-7 review I2/I3.
- **Popover user-*open* reporting** — nothing reports a user opening a popover
  (`Attr.on_closed` covers only dismissal), so a model rendering `~open_:false` forever
  pops a toggle-opened popover back down on the next frame (documented on
  `Node.popover`). `notify::visible` on the popover, filtered to the opening edge, is
  the closing hook — a `Read_back` in `w_popover.ml`'s spec shape. task-5 review.
- **A free-floating popover** — needs the `GdkRectangle` constructor (fork round 3) and
  a placement design; stavekeeper's only popover is the menu button's, so M3 ships
  `Node.popover` only as that slot.
- **`Window.set_titlebar` wiring (`~titlebar` on `Node.window`)** — deliberately
  unshipped in M3: Task 4 deferred it, Task 8 reconfirmed the deferral (plan step 4's
  ruling), and until the final-review fix wave nothing in-tree recorded that. In M3 a
  header bar is an ordinary first child (`examples/chrome.ml`), which is exact under
  X11 — GTK 4.22.4 adds its default title bar only where it draws CSD *and* the display
  is composited (`gtkwindow.c` realize; probed under xvfb with and without `GTK_CSD=1`:
  no default bar either way). On a Wayland desktop the default bar appears above a
  first-child header bar, which is what shipping `~titlebar`
  (`Window.set_titlebar : t -> Widget.t option`, bound) fixes. The bar becomes a window
  *slot* rather than a child then — the slot machinery is `w_header_bar`'s.
  final-review chrome lens, I1.
- **The named-widget registry generalisation** — `SearchEntry.set_key_capture_widget`
  and `Attr.mnemonic_widget` both need the vtree to name a widget; the stack-name
  registry (and now the window-key registry) is the pattern to generalise.
- **The gallery-twin sweep.** `examples/gallery.ml` is still a hand-maintained twin of
  `test/handle/test_gallery_tree.ml` and only the handle tree is under the sweeps.
  Task 12 hand-reconciled the example (every M3 kind and attr is now in both — the M2
  entry's 36/38 constructor counts are stale; the catalogue is 42 kinds and the sweeps
  derive their count from `Kind.Variants.descriptions` rather than a literal), but
  nothing keeps the example's *content* aligned going forward: a new M4 constructor
  turns the sweeps red and says nothing about the example. Closing shape unchanged: a
  shared module, or a sweep over the example's own tree.
- **The `Activate_row`-class handle honesty revisit** — the deliberate once-for-all-three
  reconsideration of the places the headless handle certifies what the runtime will not
  do (`Activate_row` on `row_activatable false` and its two siblings; the list lives on
  `Bonsai_gtk_test.create`). M3 added a documented sibling rather than resolving the
  class: headless `Close_request` on a handler-less window fails loudly where the
  runtime swallows-and-reports (divergence documented at the action and the attr).
- **The behavioural half of the fork's nullable bindings** — the library still writes
  `Some`: `Unset Widget_name` restores `Some d.widget_name`, a dropped
  `Attr.page_title` writes `Some ""` (the blank clickable switcher button), and
  `w_password_entry.ml` forces `""` (invisible in practice; GTK normalises). Behaviour
  changes with goldens attached, unchanged since M2.
- **A real multi-driver effect-hook story, if ever wanted.** The `Gtk_effect`
  hook slot is single and last-wins: with two live drivers the earlier one's async
  resolutions ride the later one's hooks, and the later one's stop leaves the survivor
  hookless (its resolutions then log as outside a running app). Masked at the default
  60 fps tick, real under `fps <= 0` — the only regime where the async pattern's
  frame-request is more than advisory. Fix shape: per-driver hooks captured at perform
  time. task-9 review, Minor 1 + out-of-scope 5.

## Input residuals

Three, and they are one family — what a WM-less Xvfb X11 path cannot reach:

- **The M2 residual stands**: everything is proven on Xvfb's X11 input path; a real
  display (a window manager, a compositor, or Wayland's `gdk_wayland` path) is exercised
  nowhere. M3 widened what rides on it: popover opening, menu item activation, shortcut
  chords and dialog dismissal all inherit it.
- **Keyboard never reaches a popup surface under WM-less Xvfb** (Down+Return on an open
  `GtkPopoverMenu`: measured — sensitive item, no activation; Escape works only because
  the *toplevel* dismisses its own grab). Menu item activation is therefore proven by
  the pointer path only (`live_input.ml`'s PopoverMenu block, which is also what proved
  the focus repair after real activation). task-6 carry.
- **The file chooser's ACCEPT half is undrivable**: choosing a real file needs a click
  inside GTK-internal chooser furniture whose geometry nothing can name, so
  `test/live/live_input.ml` proves only the Escape/dismissal half (`None`, with the
  keep-alive count returning to zero). The accept path runs only by hand. task-10
  review.

## API shape decisions before they become breaking

- **`Bonsai_gtk_test.Action.t` is now a public variant with twenty-nine constructors**
  (nineteen at M2's close), still unsealed, still the exhaustive-match exposure `Attr.t`
  had before it was sealed.
- **The M3 chrome types are public API now**: `Action_spec`, `Menu`, `Trigger` and
  `Position` are re-exported from `Bonsai_gtk` (Task 12 found no app could write
  `~menu` or `Attr.actions` without them). `Trigger.t` and `Action_spec.t` are this
  library's own shapes and can grow; `Menu.entry` is a variant.
- `Key_response.t`, `Click_response.t`, `Phase.t`, the GTK enums, `Click_event.t`,
  `Key_event.t`, `Modifiers.t` — unchanged from the M2 entry.
- **`Kind.t` still derives `variants`** wholesale where only `Variants.descriptions` is
  wanted. task-1 (M2) Minor 9, untouched.
- **`Placement.is_read_by`'s name** answers a broader question than it reads as asking.
  Unchanged from M2.
- **`Controllers.key_pressed_answer`/`key_pressed_declined` are still test-facing
  exports**, and live_input can now deliver a real key — the reason they exist is
  narrower than it was; retiring them is a candidate the next controllers change should
  take in passing.
- `start ?flags` (spec §4.1) is still unimplemented; `NON_UNIQUE` is needed for two
  instances of one app.
- `Kind.t`'s sexps are still lossy by design (`sexp_of` only, defaults dropped).
- **`Node.editable_label` still has no `~editable`/`~width_chars`/`~xalign`**;
  `Node.flow_box` still accepts `min > max` per line (documented: the maximum wins);
  `W_spin_button` still rejects `Attr.on_changed` undocumented at the constructor. All
  unchanged from M2.
- **`Attr.shortcut`'s first-match rule is documented at the attr** (same-trigger
  conflicts on one node are rejected outright; cross-node order is the deterministic
  sorted rebuild) — recorded here because shipping targeted shortcuts must not disturb
  either property.

## Carried out of M3's task reviews

New items M3's own reviews chose not to take, each citing its review under
`.superpowers/sdd/2026-08-31-bonsai-gtk-m3/`:

- **A doubly-degenerate transient self-reference splits the twin strings**: a *keyed*
  `Node.window` **root** record-updated to be transient for its own key raises the
  self-reference string headlessly but the missing-key string (empty registry) at the
  runtime fixup. Both are correct refusals; only the strings differ, and only on a tree
  no constructor can build. Beside the other identical-by-construction claims if a
  future sweep audits strings. task-8 review, out-of-scope 7.
- **Presentation precedes transient resolution**: `on_window_created` presents each
  window during the mount walk and `set_transient_for` lands in the fixup pass after
  it, so on a real WM a dialog could flash unparented for one frame (invisible under
  xvfb). Cosmetic if ever visible; belongs to the real-display residual above.
  task-8 review, out-of-scope 8.
- **Global-vs-per-widget CSS provider precedence at equal priority is unestablished** —
  neither the task nor its review pinned GTK's cross-cascade tie-break; authors resolve
  conflicts with selector specificity regardless. A doc sentence is only worth writing
  once someone pins the truth. task-11 review, out-of-scope 7.
- **`prefers-contrast` is unmirrored** on the global CSS provider — deliberate; the
  enum and setters are bound if a high-contrast story is ever wanted. task-11 review.
- **The `Gtk_effect` settings connections are permanent by design** (bounded per
  `Global_css.install`, consistent with the accumulate-and-keep provider contract).
  task-11 review, out-of-scope 8.
- **What the chrome smoke covers, precisely**: mount-time menu machinery (GMenu
  construction, action resolution) — a crash strictly on a user popping the menu open
  is not covered by any smoke (nothing clicks under it); the live suites cover opening.
  task-12 review, out-of-scope 4.
- **`Attr.on_closed` takes the effect directly** (`unit Ui_effect.t`, not a thunk) —
  deliberate, consistent with the payload being nothing. task-5 review.
- **A handlerless popover dismissal schedules nothing**, so the declined-dismissal
  reopen waits for the next frame from any source — the latency every controlled prop
  has for handlerless edits. Not new, not wrong. task-5 review.
- **Destroying an OPEN slot popover, then popping up a new one in the same window,
  emits one GTK critical** (`gtk_widget_is_ancestor: assertion 'GTK_IS_WIDGET
  (widget)' failed`) during the later popup — GTK-internal stale-focus bookkeeping.
  Probed during the fix wave with a bare-button control: the critical appears whether
  or not `~menu` is involved, so it is *not* the popover↔menu swap path (whose both
  directions are now pinned convergent in `live_chrome.ml`); the runtime's own repair
  connection was instrumented and exonerated. One line of stderr noise, no crash, no
  behavioural consequence observed. If it ever warrants closing, the shape to try is a
  `popdown` before a visible popover's destroy. final-review fix wave, chrome M2 probe.

## Carried forward from M2 (still open)

The M2 lists below are carried with their original citations; entries closed in M3 are
noted above and struck in `docs/m2-backlog.md` itself. File names translated per the
header. Highlights rather than a verbatim copy — m2-backlog remains the authoritative
text for each, and none has changed state unless listed in "Closed" above:

- *Left by the M2 final review's fix wave*: `Events.family_attrs` rebuilds its filter
  per call (now over **seven** controller-attr names and four families — the measure
  -first ruling stands); the placement seam still has no drift check; `Signals.spec`'s
  connection-arity asymmetry; `Controllers.update`'s two raise paths; `W_editable_label`
  absent from `Private`; the paned-position sexp erasure; "props take part in
  equal_props" naming; the opam `ppx_expect` over-declaration; the six-entry-point test
  breadth.
- *Diagnostics and contracts*: notebook keyless message has no path (by design); a
  `row_*` attr on a `?placeholder` is silently inert (slot-granularity, unchanged —
  M3's windows converse checks are kind-granular too); `Controllers.update`'s
  unconditional `clear`/re-arm coupling; `Click_event` doc claims now largely *proven*
  by live_input but the multi-click `n_press` beyond 2 and `~button:0`'s full range
  remain untested; per-controller GClosure roots (now four families wide); the
  `patch_children` catch-all message; `Native_gtk.S.destroy` ordering doc; grid cell
  occupancy.
- *Behaviour*: the search-entry empty-write echo record; one failing fixup drops the
  pass's rest (now including transient_for and popover-open fixups — still bounded by
  the broken frame); `drop_stack_names` before the kind-change mount; overlay
  kind-change z-order jump; switch `state`/`active`; spin-button uncommitted display;
  calendar `same_marks` order-sensitivity; text-view repeat-report edge.
- *Consistency*: `enqueue_fixups`' report-only arms are now five kinds wide and the
  `notify_interests`/`enqueue` rename question stands; the calendar's connection-list
  dedup placement; unexposed heading signals; the `GtkEditable` `O(len)` idle compare
  (unchanged; the cache generalisation is still the fix if a profile ever asks);
  the M1 create-path inconsistencies (`apply_button_props`, placeholder labels,
  `w_entry` comment, `Paintable_picture.apply`, `Native.Picture.alternative_text`,
  three default-write conventions, unbatched writes in `w_frame`/`w_center_box`);
  the two `all_kinds` lists are still duplicated verbatim (both grew `Windows` by hand
  in M3 — each is count-checked against `Kind.t`, neither against the other).

## Tests worth adding

- **GC/lifetime** (carried from M0, more interesting every milestone): remove a keyed
  child, `Gc.full_major`, assert finalisation. M3 adds the dialog keep-alive tables and
  the css-provider ephemeron to the inventory of things it would exercise.
- **After-display spin regression** (needs a frame counter under `Private`) — carried.
- **A live per-kind `update` sweep** — still no single `Live_tree.dump` golden over the
  whole 42-kind catalogue; the headless lifecycle sweep proves `update` is not skipped,
  not that it writes.
- The M2 items unchanged: `Driver.schedule_event`'s broken-guard observability;
  `Reconcile`'s two theorems living in one comment; `Live_tree`'s order-blind dumps for
  interposing containers; the text-view cache's bench-only defence; the calendar
  Dec→Jan walk line; `live_text.ml`'s midnight flake; calendar teardown assertions; the
  rebuilt-equal-string repeat report; nested `Attr.many`; the three default-erased
  expect tests; gallery PNG path; `Live_tree` truncation quirks; slot-granular
  placement.
- **New in M3**: the equal-priority CSS precedence pin (above); a real-WM transient
  flash check (above); keyboard-on-popup and chooser-ACCEPT (the input residuals);
  `Effect.Window.present` under a `Window` (non-windows) root is exercised nowhere (the
  runtime answers the missing-key log; one live line would pin it).

## Known-and-accepted dump quirks

Unchanged from M2 (opacity 8-bit read-back, spin-button `numeric`, icon churn, grid
re-attach ordering, `gtk_root_get_focus` across re-parents, hidden-page
`set_current_page`, flow-box remove emissions, two stderr producers, controller-name
attach order), plus:

- **A `GtkWindow` dump shows `transient_for` by the parent's *title*** — identity is
  unprintable, and a dump naming the wrong window is what the windows suite wants to
  see fail.
- **`Css_provider.to_string` renders the rules for the provider's current
  color-scheme**, so the same provider dumps differently after the mirror flips — which
  is the consumption proof `live_css.ml` uses, and a surprise if met unprepared.
- **An invalid CSS load leaves the provider *empty*** (GTK clears before parsing), not
  holding the previous sheet. The attr's mli says so; the golden pins it.

## Plumbing / hygiene

Carried from M2 unless noted: the live-display lock story (now **seventeen of
twenty-one** rules, with the census and its two deliberate exceptions in
`test/live/dune`'s header — including `live_css`, locked because it mutates the default
display's `GtkSettings`); `live_text.exe` still dominating the live section's wall
clock; the `--force`-does-not-re-run trap (ci.sh deletes `output_*.txt`, which now
covers all twenty-one); the gallery click-card-vs-words choice; `setup-switch.sh`'s
stamp caveats; the `gir_gen`-capable-shell wish; frozen node paths in `on_exn` logs;
`Signals.slots`' outer ref; **a `Driver` is never reclaimed, stopped or not** (the
Bonsai/Incremental global-state item, unchanged and still the reason `stop` drops every
caller closure it can — M3 added `on_window_created` and the effect hooks to the
dropped set); unbounded `drain` loops in most live tests; the hard-coded 16 ms cadence;
`after_of`'s `O(index)`; `Widget_impl.snapshot`'s per-creation getter count (unchanged
by M3: `css_provider` deliberately has no snapshot field); the duplicated `page`
helper; redundant `(deps …)`; the stavekeeper port's shell-side quit gap; **the
stavekeeper pin bump, still outstanding** (its `ocgtk-pin.json`/flake hash predate even
M2's fork round).

New in M3:

- **`GSETTINGS_SCHEMA_DIR` is dev-shell-only** (`flake.nix`): a packaged consumer of the
  file-dialog effects needs gtk4's schemas reachable by its own means, or
  `FileChooserNative` aborts the process at construction. Right for this repo; worth a
  README line the day anyone packages an app.
- **The alert's `heading` css class is theme-dependent styling** — plain GTK renders it
  bold; a theme without the class shows plain text. Cosmetic by construction (never
  markup).

## ocgtk fork

The pin is `72cc75f2`, the post-fork-round-2 head, standing since before this
milestone's first task (`ocgtk-pin.json` is the authority); `ci.sh` is green against
it. **M3 shipped no fork round** — every
binding gap met a chosen workaround or documented omission — so m2-backlog's fork
section remains the authoritative ledger for what is fixed and what is still open
there (the 153 stack-frame record returns, the transfer-full `char*` leak, the
in-param/expression classes, the upstreaming state). What M3 adds is the **round 3
candidate list**, aggregated by the M3 plan and confirmed against the pin by its
pre-flight scout; no M3 task blocked on any of these:

1. **`GtkAlertDialog` constructor + async `choose`** (hand stubs; `new` is varargs) —
   would replace the deprecated-GtkDialog alert path with the modern one §8 named
   first.
2. **`GtkFileDialog` async launchers** (`open`/`save`/`select_folder`, pairing the
   already-generated `*_finish` halves) — would replace `FileChooserNative` and
   un-deprecate the file path.
3. **`GdkClipboard.set_text` + `read_text_async`** — unblocks `Effect.Clipboard.
   get_text` and turns the thin `set_text` assertion into a round trip.
4. **`GdkRectangle` constructor/accessors** — unblocks `Popover.set_pointing_to` and
   the free-floating popover design.
5. **`GtkCallbackAction`** — a shortcut holding a closure without a named action.
   Evaluate *after* the port: the action-routing design may prove the better shape
   anyway (one `Action_spec` list serving menu, chord and palette is what M3's examples
   demonstrate).
6. **`Shortcut_trigger.parse_string` / `Simple_action_group.lookup` NULL returns** —
   the M1 nullable class, new instances; M3 avoids both calls (`Trigger.create` from
   vtree data, the runtime's own name table).
7. **`Gio.File.new_for_path`** — unblocks file-dialog initial folders.
8. **`Display.get_default` / `Display_manager.get`** — would free the effects from the
   `context_widget` hook for display access.
9. **`Application.set_menubar` + `PopoverMenuBar`** — the menubar the README's "no
   menubar" limitation records. Added here at Task 13's review: the task-6 review
   disposed of it as "already on the fork-round-3 list", and it was not — this line is
   what makes that disposal true.
10. Known carries from the round-2 close-out (do not re-derive): the borrowed-return
   `ref_sink`→`ref` correctness-by-construction change; `GList*` declared for
   GSList-returning stubs (an error on GCC 14+/Clang 16+); the dead sink-on-non-
   `GInitiallyUnowned` constructor stubs; the fork's unformattable `gir_gen`
   (`.ocamlformat` pin vs the `#girgen` shell).

The rule the fork work established stands verbatim: for any new binding call that
returns objects, **read the stub, not the GIR** — `test/live/live_lists.ml`'s first
block is the shape of test that catches what a short-lived one cannot.
