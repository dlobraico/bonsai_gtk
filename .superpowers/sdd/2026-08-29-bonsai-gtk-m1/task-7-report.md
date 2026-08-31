# Task 7 report: single-child containers — ScrolledWindow, Frame, Expander, Revealer

**Status:** complete. Commit `e33a69b` on `m1`. `scripts/ci.sh` ends `all green`.

## What landed

New files:

- `vtree/policy.ml` — `Always | Automatic | Never | External_`
- `vtree/reveal_transition.ml` — `None_ | Crossfade | Slide_{right,left,up,down} | Swing_{right,left,up,down}`
- `src/widgets/w_scrolled_window.ml`, `w_frame.ml`, `w_expander.ml`, `w_revealer.ml`

Modified: `vtree/bonsai_gtk_vtree.ml`, `vtree/attr.ml(i)`, `vtree/kind.ml(i)`, `vtree/node.ml(i)`,
`src/attr_apply.ml`, `src/patcher.ml`, `src/widgets/registry.ml`, `src/live_tree.ml`,
`src/bonsai_gtk.ml(i)`, `test/test_widgets.ml`, `test/live/live_containers.ml`,
`test/live/expected_containers.txt`.

All four kinds use `Children.Single (Some child)` — the child is a required positional
argument, as on `Node.window` — and `Widget_impl.Single { set = ... set_child }`.

### Controlled props, via `reassert`

The brief predates the `reassert` hook and says "controlled = true"; both controlled props
are implemented as `Widget_impl.reassert` with a shared `*_if_needed` helper, matching
`w_toggle_button.ml` and `w_entry.ml`:

- `w_expander.ml`: `set_expanded_if_needed` compares against `W.Expander.get_expanded`.
  `expanded` is deliberately absent from `update`.
- `w_revealer.ml`: `set_reveal_if_needed` compares against `get_reveal_child` — the *input*
  property. Comparing against `child_revealed` (the outcome) would read "not yet" for the
  whole of a transition and rewrite on every frame.

`ScrolledWindow` and `Frame` have `reassert = None`: neither has user-driven state that a
model can decline. A scrolled window's only such state is its scroll position, which is
deliberately not a prop (documented in the mli, with `Key.t` named as the way to preserve
it across re-renders, and `edge-reached`/`edge-overshot` deferred to M2 with `ListBox`).

### Signals

`Attr.on_expanded_changed` / `Attr.on_revealed`, both `bool Handler.t`, both classified
`is_event = true`, both with inert `Attr_apply` arms. Connected with `Signals.notify`:

- Expander: `notify::expanded` (not `GtkExpander::activate`, which fires before the
  property settles).
- Revealer: `notify::child-revealed` (read-only, flips when the *animation* finishes —
  the moment a hidden subtree can be dropped from the model).

`Signals.require_specs` covers them for free: `on_revealed` on a `Frame` (which declares no
specs) raises `Invalid_argument` at mount and at patch, on the existing mechanism.

### `Live_tree.dump` arms

`GtkFrame` (label), `GtkExpander` (label + `expanded`), `GtkRevealer` (`reveal` and
`revealed`, both halves), `GtkScrolledWindow`.

**Deviation from the brief, deliberate:** the brief's `GtkScrolledWindow` arm prints only
the two content minima. That leaves `hpolicy`/`vpolicy` — the props stavekeeper leans on
hardest — unobservable, because both `GtkScrollbar` children are present in the tree
whatever the policy says and a `NEVER` one differs only in child visibility, which the dump
does not descend into. The arm therefore also prints the policies (suppressed at
`AUTOMATIC`), the two content maxima, both propagate flags, `no-kinetic`/`no-overlay` and
`framed`. That is what makes the live test an actual check that `set_policy` landed.

GTK's internal children are kept, per plan ruling 6: the two scrollbars, and the
`GtkViewport` GTK interposes around a non-scrollable child — whose presence in the expected
file is itself the check that the child landed *inside* the scroller.

## Tests

- **Headless** (`test/test_widgets.ml`, "single-child containers"): the brief's tree,
  promoted. Confirms the `[@sexp_drop_if]` defaults — GTK's own throughout (`Automatic`
  policies, `-1` content sizes, `false` propagate/`has_frame`, `true` kinetic/overlay,
  `label_align = 0.`, `use_markup = false`, `None_`, 250 ms).
- **Live** (`test/live/live_containers.ml`), appended to the media half; its `ctx` now uses
  a real `Scheduler` and counts `schedule` calls, which the media half does not exercise:
  1. Mount and patch of the brief's `containers` tree. The patch flips `expanded`,
     `reveal`, the frame's and expander's labels, the frame's child *kind*
     (label → button, so the widget is replaced in the slot), and — added — every
     scrolled-window prop at once via a `~clipped` flag, so each setter in the impl's
     `update` is covered rather than only the ones the node happens to name.
     `~transition:None_` throughout, so nothing races the animation.
  2. `notify reaching Bonsai outside a patch: 2` — both specs are connected at all.
  3. **The two declines:** `W.Expander.set_expanded false` and
     `W.Revealer.set_reveal_child false` behind the model's back, then a patch with the
     *same* props. `update` is skipped (nothing moved), so only `reassert` runs.
     Output: `declined expander true, revealer true (revealed true); reached Bonsai: 0`.
  4. A `slots` section that swaps the child's kind under each of the four containers in
     one tree, proving each `Single { set }` puts the replacement in.

## Notes and concerns

- **Child *removal* is not reachable, so it is not tested.** All four constructors take the
  child positionally (like `Node.window`), so none can produce `Single None`; the slot can
  be replaced but never emptied. Noted in a comment in the live test and in `node.mli`. If
  a later task wants an emptiable slot it is an `?child` argument away.
- **A collapsed `GtkExpander` does not parent its child at all** — GTK adds and removes it
  from the internal box as the expander opens and closes, so the first dump shows the
  expander's title row and no `detail` label. That is GTK's own behaviour, visible in the
  expected file, and is why the `slots` test opens the expander (a collapsed one would make
  the child swap unobservable). The patcher's order (`update` → `reassert` → attrs →
  children) means an expander opening *and* swapping its child in one patch re-parents the
  old child and then replaces it; correct, but that specific combination is not covered by
  a test.
- **`min_content_*` before `max_content_*`.** GTK's docs call it "a programming error" to
  set a minimum above the current maximum. Both `create` and `update` write min then max,
  and no ordering is safe in both directions (the reverse breaks when a maximum shrinks).
  GTK4 has no runtime check and the live test (min 80 / max 300, min 60 / max 400) produces
  no criticals, so this is left as-is.
- **Untested-but-implemented update branches:** `Frame.label_align`, `Expander.use_markup`,
  `Revealer.transition`/`transition_duration`. None is printed by `Live_tree.dump`, so
  exercising them live would have meant adding dump props beyond what the brief specifies —
  and flipping `transition` on the same patch that flips `reveal` would reintroduce exactly
  the animation race `~transition:None_` exists to avoid. The headless test covers them at
  the node level; each is a one-line per-field diff in the impl.
- `Bonsai_gtk_test.Action.t` gained nothing: the brief's file list does not include
  `test_lib/`, and there is no headless action for "the user opened an expander". Worth a
  backlog line if Task 10's sweep wants one.

## Verification

```
nix develop -c ./scripts/ci.sh
...
== pure + headless tests
== live tests (xvfb)
== example smoke
all green
```
