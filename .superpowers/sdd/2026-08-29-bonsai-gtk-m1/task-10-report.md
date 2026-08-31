# Task 10 report: the gallery example, the headless sweep, and the deferred coverage items

Branch `m1`, two commits on top of 545c67d:

- `082f12a` Gallery example, and a headless sweep over every M1 widget
- `5db453e` coverage sweep: shared prop defaults, sources, scrolled bounds, expander swap

`./scripts/ci.sh` is green.

---

## 1. The gallery (`examples/gallery.ml`, 247 lines)

Three pages behind a `Node.stack`, each wired to real state, as the brief lays out:

- **Controls** — a `Node.grid` of the toggle family (`toggle_button`, `check_button`,
  `switch`) and the entry family (`entry`, `password_entry`, `search_entry`), all
  controlled, with an echo label showing what the model settled on.
- **Numbers** — one `value` driving `scale`, `spin_button`, `progress_bar` and `spinner`,
  across a `separator`.
- **Layout** — a `paned`: a `scrolled_window` of `frame` / `expander` / `revealer` /
  `image` on the left, a `center_box` on the right whose centre is the overlay-over-a-spacer
  trick.

Two deliberate departures from the brief's sketch, both to make the gallery actually
contain every M1 widget:

- **`Node.picture` rather than `Node.image` in the overlay** (examples/gallery.ml:180).
  The brief's own comment on that page says the overlay trick "caps a *picture's* allocated
  size", and a picture is the widget whose natural size comes from its image, so it is the
  one that needs the spacer. The gallery ships no data files, so it writes one 8x8
  greyscale PNG — inlined as bytes at examples/gallery.ml:8-18 — to a temp file at startup.
  An `Node.image (Icon_name …)` still appears on the same page.
- **A `Node.stack_sidebar` beside the `stack_switcher`** (examples/gallery.ml:211). Both
  name `"gallery"` and both are declared *above* the stack, so the example now demonstrates
  the fixup pass twice over rather than once, and covers the second of the two name-resolving
  widgets.

`Node.native` is the one constructor the gallery does not use: its input is an ocgtk value,
and `examples/dune` links `core bonsai bonsai_gtk` only (the brief's dune). It is covered
headlessly in `test/test_gallery.ml` and live in `test/live/live_containers.ml` through
`Native.Picture`.

`examples/dune` is the brief's `(executables (names counter gallery) …)`. `scripts/ci.sh:43`
smokes both examples in a loop; `@examples/fmt` was already in the fmt line (confirmed, not
assumed).

## 2. The headless sweep (`test/test_gallery.ml`, 342 lines)

One vtree-only component, one `[%expect]`. Constructor checklist against `vtree/node.mli`
(`grep '^val' vtree/node.mli`) — every one appears in the sweep:

| constructor | in sweep | constructor | in sweep |
| --- | --- | --- | --- |
| `label` | yes (all seven optional props non-default) | `frame` | yes |
| `button` | yes ×3 — `~label`, `~icon_name ~has_frame:false`, `~child` | `expander` | yes |
| `toggle_button` | yes | `revealer` | yes |
| `check_button` | yes (`~inconsistent:true`) | `box` | yes |
| `switch` | yes | `grid` | yes (child carries `Attr.grid_cell`) |
| `entry` | yes | `stack` | yes |
| `password_entry` | yes | `stack_switcher` | yes |
| `search_entry` | yes | `stack_sidebar` | yes |
| `spin_button` | yes | `center_box` | yes |
| `scale` | yes | `paned` | yes |
| `progress_bar` | yes | `overlay` | yes |
| `spinner` | yes | `window` | yes |
| `image` | yes | `native` | yes (`Native.Unit` payload) |
| `picture` | yes | | |
| `separator` | yes ×2 (both orientations) | | |

(`find_by_test_id` is a query, not a constructor; it is covered in `test/test_widgets.ml`
and `test/test_node.ml`.)

The brief's second `[%expect]` — a click plus `show_diff` — was dropped. `show_diff` prints
the whole tree with markers, so on a tree this size it is a second 200-line copy of the same
snapshot for one changed line. The state is still real (`n` drives the toggle's `active` and
the spin button's `value`, and the button holds `set_n`), so the sweep is a computation
rather than a constant; it is just snapshotted once.

## 3. The deferred sweep items

### Item 1 — shared default constants

`vtree/defaults.ml` (new, 141 lines, no mli, matching the other small vtree modules) names
GTK's default for each of the 64 optional properties that has one, grouped per widget
(`Defaults.Label.xalign`, `Defaults.Scrolled_window.min_content_width`, …). Option-typed
props are excluded: their default is `None` and is passed straight through, so there is
nothing to keep in step.

Three sites now read it instead of repeating a literal:

- `vtree/node.ml` — every `?(x = …)` optional-argument default (64 of them; comment at
  vtree/node.ml:15-19).
- `vtree/kind.ml` — every `[@sexp_drop_if]` (64; comment at vtree/kind.ml:7-16).
- `vtree/kind.mli` — the same 64, in the mirrored type definitions (comment at
  vtree/kind.mli:5-9).

`grep sexp_drop_if` over kind.ml and kind.mli now differs only by the one comment line, so
the ml/mli mirror is exact. No expect output moved, which is the check that the refactor
was value-preserving.

### Item 2 — `Resource` sources, a non-default `Icon_size`, and an unchanged picture filename

- Headless (`test/test_widgets.ml:139`): the "images, pictures and separators" case gains
  `Node.image ~icon_size:Large (Resource …)`, `Node.image ~icon_size:Normal (File …)` and
  `Node.picture ~content_fit:Cover (Resource …)`. Live coverage is deliberately absent and
  the comment says why: a `Resource` is whatever the application compiled into its binary,
  and there is none here to name.
- Live (`test/live/live_containers.ml:120-144`): a `Node.picture` whose `Filename` is
  unchanged across a patch that moves `alternative_text`. `gtk_picture_set_filename` builds
  a fresh `GdkTexture`, so the paintable's identity is the observable —
  `same paintable across a patch that left the filename alone: true`.

### Item 3 — ScrolledWindow `min_content_*` / `max_content_*` write order (behaviour change, TDD)

This is worse than a warning. `gtk_scrolled_window_set_min_content_width` asserts
`width <= max_content_width` and **drops the write** when it fails: the widget keeps its old
bound and only a `Gtk-CRITICAL` on stderr says so. The impl wrote both minima before both
maxima, so any patch moving a window's bounds up past where they were lost the minimum
outright.

The live case (test/live/live_containers.ml:244-282) crosses the old bounds in *both*
directions in one patch — the width moves up (needs max first), the height moves its max
down below the old min (needs min first) — so neither fixed order passes it.

**RED** (expected file written first, impl unchanged):

```
(process:3179530): Gtk-CRITICAL **: 17:40:56.850: gtk_scrolled_window_set_min_content_width: assertion 'width == -1 || priv->max_content_width == -1 || width <= priv->max_content_width' failed

(process:3179530): Gtk-CRITICAL **: 17:40:56.850: gtk_scrolled_window_set_min_content_height: assertion 'height == -1 || priv->max_content_height == -1 || height <= priv->max_content_height' failed
File "test/live/expected_containers.txt", line 85, characters 0-1:
 |mounted: width 80..300, height 100..500
-|crossed: width 400..600, height 20..60
-|back: width 80..300, height 100..500
+|crossed: width 80..600, height 20..60
+|back: width 80..300, height 20..500
```

**GREEN** after `set_bounds` (src/widgets/w_scrolled_window.ml:12-35, called twice at
:72 and :79 — once per axis): `BONSAI_GTK_LIVE_TESTS=1 xvfb-run -a dune build
@test/live/runtest` passes with no `Gtk-CRITICAL` on stderr.

```ocaml
let set_bounds ~set_min ~set_max ~old_min ~old_max ~new_min ~new_max =
  let write_min () = if old_min <> new_min then set_min new_min in
  let write_max () = if old_max <> new_max then set_max new_max in
  if new_min >= 0 && old_max >= 0 && new_min > old_max
  then (write_max (); write_min ())
  else (write_min (); write_max ())
```

The `old_max >= 0` guard matters: `-1` is GTK's "unset" and asserts against nothing, so
flipping to max-first on an unset old maximum would break the case where the *new* maximum
is below the old minimum. `create` is unchanged — a fresh `GtkScrolledWindow` has both
bounds unset, so nothing can be in the way.

### Item 4 — expander that opens and swaps its child in one patch

test/live/live_containers.ml:307-326. A collapsed `GtkExpander` does not parent its child at
all, so this is the one child swap GTK reparents underneath the patcher. Behaviour is
correct as it stands — the expected dump goes from a collapsed expander with no child in its
GTK tree to `(GtkExpander (label (detail)) expanded … (GtkButton (label (after))))`. No impl
change was needed; the case is now pinned.

### Item 5 — `require_specs` rejection for `on_expanded_changed` / `on_revealed`

test/live/live_controls.ml:174-190, immediately after the existing `on_toggled`-on-`Label`
pair. Both are mounted on a label:

```
rejected: root/0: Label does not emit On_expanded_changed
rejected: root/0: Label does not emit On_revealed
```

## 4. `scripts/ci.sh` tail

```
== nix: ocgtk pin builds and passes its tests
== format
== build
== generated opam files are committed
== pure + headless tests
== live tests (xvfb)
bonsai_gtk: exception in frame, stopping the driver: (Invalid_argument
  "root/0/1: a Node.window may only be the root node, not a child of another node")
== example smoke
all green
```

(The `exception in frame` line is `live_driver`'s own expected output, unchanged from before
this task.)

## 5. Concerns

1. **The gallery has not been looked at on a real display.** Step 5 asks for it and there is
   none here: no X display, and the dev shell has no screenshot tool (`xwd`, `import`,
   `magick`, `scrot`, `ffmpeg` all absent), so there was nothing to capture from Xvfb
   either. What *is* verified: it mounts, stays up for the smoke timeout, and writes nothing
   at all to stderr — no `Gtk-CRITICAL`, no `Gtk-WARNING`, no failed image load. The
   failure modes the brief names that this cannot rule out are the visual ones: a page that
   renders at zero height, an overlay that sizes to its picture rather than its spacer. A
   pass on a real display is still owed.
2. **The inlined PNG in `examples/gallery.ml`.** 113 bytes as seven escaped string literals
   is not beautiful in a file whose job is to be exemplary. The alternatives were worse: a
   binary fixture in `examples/`, or linking `ocgtk.gdk` into the example to build a texture
   in memory (which would have changed the brief's `examples/dune` and made the example
   about ocgtk). It is commented as what it is.
3. **`vtree/defaults.ml` is not exported** from `bonsai_gtk_vtree.ml`. Applications cannot
   ask "what is the default for `min_content_width`" in code; `node.mli` documents them in
   prose. Exporting it is a one-line change if that is wanted, but it widens the public API
   and Task 11 owns the docs.
4. **`kind.mli`'s `[@sexp_drop_if]` payloads are inert** — ppx generates `sexp_of_t` from the
   ml only, so the mli copies are documentation the compiler does not check. They now name
   the same `Defaults` constants, so textual drift is visible rather than silent, but the
   real belt-and-braces fix would be to drop them from the mli entirely. Left alone because
   the repository's style is to mirror the type definitions exactly.
5. **The scrolled-window fix assumes self-consistent nodes.** If a caller passes
   `~min_content_width:400 ~max_content_width:300`, GTK will still reject one of the two
   writes and log. That is the caller's bug and surfacing it is right, but nothing in
   `Node.scrolled_window` rejects it up front; a `min <= max` check in the constructor would
   be a cheap follow-up if it is wanted.
