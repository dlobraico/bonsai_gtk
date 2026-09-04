# Task 12 report — gallery, examples, and the sweeps

Commits `4e22ea0..353cc96` (4): the Task 11 review items (`4e22ea0`), the re-exports
(`a9baba5`), the gallery reconciliation (`74851ac`), chrome.ml + smoke (`353cc96`).
ci.sh green after the stretch (runs at `4e22ea0` and at `353cc96`).

## The Task 11 review first (`4e22ea0`)

All three Importants and all three minors:

- **I1** — the attr mli's "keeps the previous ruleset" was false: GTK clears a provider
  on every load before parsing, so an invalid string *strips* the widget's styling. The
  sentence now says so, and the live suite dumps the emptied provider (`""`, goldened)
  — the line that would have caught the claim.
- **I2** — `?global_css` is now publicly documented: a paragraph on `start` (what it
  installs, that dark `@media` blocks work via the mirrored color scheme, activate
  timing, accumulation on a second start), with `Expert.embed` and `embed.mli` deferring
  to it plus their default-display-only limit and create-time install.
- **I3** — the honest sentence at `Attr.css_provider`: per-widget providers stay at
  `` `DEFAULT``, so a dark block there is effectively always light; scheme-dependent
  styling belongs in `?global_css` (the documentation resolution the review calls
  proportionate).
- **M4** — the dune header's lock taxonomy gains live_css's clause (presents nothing,
  mutates the default `GtkSettings`). **M5** — the mirror pin now proves consumption:
  `to_string` materialises the dark block's rules on the flip and drops them on the flip
  back, goldened at every step. **M6** — `set_gtk_interface_color_scheme` runs: the
  primary mirror arm, its notify connection, and its precedence over prefer-dark
  (`interface-color-scheme light beats prefer-dark true: light`), all goldened.

Process note: my first application of I2 stacked new doc comments on the existing ones
(warning 50, the Task 5 mis-attachment trap a third time) and a masked pipeline exit
let a red-format state get committed; caught within minutes by re-running the gate
un-piped, fixed by merging the paragraphs into the existing docs, and amended into the
same unpushed commit.

## The re-exports (`a9baba5`) — found by the reconciliation

`Bonsai_gtk` never re-exported `Action_spec`, `Menu`, `Trigger` or `Position`: an
application writing `~menu`, `Attr.actions` or `Attr.shortcut` could not name its own
argument types without reaching into `Bonsai_gtk_vtree` — breaking the "an app never
names the vtree library" property the examples exist to demonstrate. Surfaced the
moment the gallery tried to express its chrome page; fixed as four lines beside the
input-type re-exports, with the discovery noted in the mli comment.

## The gallery reconciliation (`74851ac`, step 1)

The ledger's carry since Task 2, closed. `examples/gallery.ml` gains:

- a ninth page, **Chrome**: in-page `header_bar` (title widget, packs) and `action_bar`
  (revealed toggled live); a `menu_button ~menu` over `Attr.actions ~scope:"page"`
  (simple + toggle specs) with `Attr.shortcut` Ctrl+P firing the same action as the
  menu item; a `menu_button ~popover` with controlled `~open_` and `Attr.on_closed`;
- the root becomes **`Node.windows`**: main keyed `"main"`, plus an about window in the
  dialog-shell shape — keyed, `~transient_for:"main"`, modal, not resizable,
  `Attr.on_close_request`, `Attr.autofocus` on its entry (the fire-once open grab);
- `Attr.on_cursor_moved` on the controls page's text view feeding a caret readout
  (beside the caret-policy demo it completes);
- `Attr.on_contains_focus_changed` on the input page's entry row (the coarse signal
  demonstrated beside the two fine per-entry ones), and `Attr.css_provider` on the
  click card, keyed by its own css class, with the dark-blocks note.

Every M3 kind and every M3 attr now appears in both trees. The handle tree needed
nothing — the sweeps have kept it green task by task; the sweeps enumerate all
constructors from `Kind.Variants.descriptions` with no hand count, per the plan's
verification line. The two trees remain organizationally different (they always were);
nothing sweeps the example — the m2-backlog line stands, re-recorded by Task 13, not
fixed here (per the plan's "do not fix here").

## chrome.ml (`353cc96`, steps 2–3)

The M3 counter, exactly the plan's shape: a `Node.windows` app whose main window
carries **one `Action_spec` list** (the `Command.Registry` composition) serving a
header-bar menu button's GMenu (with display accels), two chords (Ctrl+N, Ctrl+Q), and
the handlers; **Reset…** goes through `Effect.Alert_dialog.show` with the pressed index
bound back into the model (dismissal answers `~cancel`, so the bind is total); the
**notes window** is opened by the model and *raised* by `Effect.Window.present` when
already open, transient for main, entry autofocused; every close request handled
(main's quits, notes' removes the node). `?global_css` on `start`. `ci.sh` smokes it
beside counter/gallery/embed (step 3: only the smoke-list change) — the run that would
catch a menus-crash-on-open, and it passed (124 = came up and stayed up).

## Deviations

1. The re-exports commit touches `src/bonsai_gtk.ml(i)`, which the plan's Task 12 file
   list does not name — but without it steps 1–2 are unwritable as real apps; the
   discovery is the reconciliation working as intended.
2. `Attr.autofocus` lives on the two dialog-shaped windows rather than a main-window
   entry: every stack page mounts on frame one, so an autofocus inside a hidden page
   would grab at app start — the dialog placement is the pattern the attr was built for.
3. The handle gallery tree was not restructured to mirror the example's new page
   layout; the reconciliation contract is coverage (every kind/attr in both), which the
   sweeps enforce on one side and this task's hand-pass on the other.

## ci.sh

`all green` (final run after `353cc96`'s content, including the four-example smoke).
The bd hook's `.beads/issues.jsonl` delta remains uncommitted, as always.
