# Task 6 report: Image, Picture, Separator — and `Native.Picture`

**Status:** complete. Commit `5ae4aa4` on `m1` (parent `c0ba9fd`). `scripts/ci.sh` → `all green`. No push.

## What landed

Four deliverables, all four with headless and live tests.

### `Node.image` — `GtkImage`

`vtree/image_source.ml` gives it a closed source variant (`Empty | Icon_name | File | Resource`)
plus `vtree/icon_size.ml` (`Inherit | Normal | Large`). `Kind.image_props` is
`{ source; pixel_size; icon_size }`, with `pixel_size = -1` and `icon_size = Inherit` as the
`[@sexp_drop_if]`-dropped defaults, both GTK's own.

`src/widgets/w_image.ml` routes every source through its own setter and `Empty` through
`gtk_image_clear`, which is the only call that actually un-sets a source — `set_from_icon_name
w None` leaves a previously set file in place. Uncontrolled (`reassert = None`), no signals.

`set_from_gicon` / `set_from_pixbuf` / `set_from_paintable` are deliberately absent and named
as such in `node.mli`: all three take ocgtk values the vtree may not mention.

### `Node.picture` — `GtkPicture` (filename/resource)

`vtree/picture_source.ml` (`Empty | Filename | Resource`) and `vtree/content_fit.ml`
(`Fill | Contain | Cover | Scale_down`). `Kind.picture_props` is
`{ source; content_fit; can_shrink; alternative_text }`; `Contain` and `can_shrink = true` are
GTK's defaults and are dropped from the sexp.

`src/widgets/w_picture.ml` clears through `set_paintable None` (`GtkPicture` has no `clear`).
`w_picture.content_fit` is deliberately left non-private: `Paintable_picture` maps the same enum.

`Node.picture`'s doc comment carries stavekeeper's hard-won sizing note verbatim in substance —
`width_request`/`height_request` raise minimum but not natural size, so capping the *allocated*
size means an unmeasured overlay (`Attr.measure_overlay false`) over a sized spacer with
`~can_shrink:true ~content_fit:Contain`. That is exactly `cards.ml`'s trick, and Task 8's
`Overlay` is the other half.

### `Node.separator` — `GtkSeparator`

Orientation-only, per the ambiguity resolution. `gtk_separator_new` takes the orientation and
`GtkSeparator` has no setter for it, so a change goes through `GtkOrientable`.

### `Bonsai_gtk.Native.Picture` — `src/paintable_picture.ml(i)`

The library's first shipped `Node.native` widget: a `GtkPicture` fed a
`Ocgtk_gdk.Gdk.Wrappers.Paintable.t option`. Input is `{ paintable; content_fit; can_shrink }`,
compared with `Gobject.same` rather than `phys_equal` — every C-to-OCaml crossing allocates a
fresh wrapper block for the same pointer, so two handles to one texture are never physically
equal (spec §2.2). `update` runs on every re-render (the patcher compares native payloads
physically and a fresh payload is allocated each frame), hence the explicit `Input.equal` guard.
`impl` is built once at the top level. `destroy` is a no-op: the widget's reference to the
paintable is GTK's business.

Exposed as `Bonsai_gtk.Native.Picture`; `Content_fit`, `Icon_size`, `Image_source` and
`Picture_source` are re-exported from `Bonsai_gtk` alongside `Ellipsize`.

### `Live_tree` arms

- `GtkImage` → icon name (when set) + `pixel-size`
- `GtkPicture` → `has-paintable` (never the paintable itself: a texture's identity is not stable
  across runs and its pixels are not what the test claims) + non-default `content-fit`,
  `no-shrink`, `alt`
- `GtkSeparator` → `orientation`

## Deviations from the brief

1. **`Node.separator` takes a trailing `unit`.** The brief's
   `?key -> ?attrs -> orientation:Orientation.t -> t` does not compile: warning 16,
   `unerasable-optional-argument`, because the last parameter is labelled, so `?key`/`?attrs`
   never get their defaults. Shipped as
   `?key -> ?attrs -> orientation:Orientation.t -> unit -> t`, which is the shape every other
   labelled-argument constructor in `node.mli` already uses (`spinner`, `switch`, `scale`, …).
   Both tests call `Node.separator ~orientation:Horizontal ()`.

2. **`Gdk.Memory_texture.new_` takes five arguments, not four.** ocgtk's signature is
   `int -> int -> memoryformat -> Glib_bytes.t -> Gsize.t -> t`; the fifth is the row stride
   (`Gsize.of_int 8` for 2 px of RGBA). Format is `` `R8G8B8A8 `` (opaque test pixels; the
   premultiplied variant would be a lie about the data).

3. **`Stdlib.Filename.temp_file` / `Stdlib.Sys.remove`** instead of `Core_unix.unlink`, per the
   brief's own note — it keeps the dune stanza to one added library (`ocgtk.gdk`).

4. **The live test has a third render the brief did not ask for.** The brief's two renders show
   the paintable going away but never show one being *replaced*, which is the whole claim of
   `Native.Picture` for stavekeeper's viewer (a new `Gdk.Memory_texture` per frame). The third
   render installs a second texture and asserts both halves explicitly:

   ```
   same widget across the swap: true
   shows the new texture: true
   ```

   `Gobject.same` on the widget before/after the patch, and `Gobject.same` on
   `W.Picture.get_paintable` against the new texture.

## Test results

- Headless (`test/test_widgets.ml`, `"images, pictures and separators"`): the four nodes' sexps,
  with defaults correctly dropped — `(Picture ((source (Filename /tmp/thumb.png))))` prints
  neither `content_fit` nor `can_shrink`.
- Live (`test/live/live_containers.ml` → `expected_containers.txt`), three renders:
  - Render 1 confirms the brief's watch-list: the filename-backed picture reports
    `has-paintable` (GTK loads the file into a texture), the paintable-backed one reports
    `has-paintable (content-fit cover)`.
  - Render 2 shows every swap landing in GTK: image 1 gains a file and so loses its `icon`,
    image 2 gains an icon, picture 1 loses its paintable and gains `no-shrink`, the native
    picture loses its paintable, and the separator flips to `vertical` (its `css` class flips
    with it, which is the `GtkOrientable` write proving itself).
  - Render 3 is the identity/swap check above.

`scripts/ci.sh`: `nix build .#ocgtk`, format, build, opam files, headless, live under xvfb,
example smoke — `all green`.

## Collateral: `expected_controls.txt` churn

The new `GtkImage` `Live_tree` arm made GTK's *internal* images legible, so Task 4/5's expected
file gained icon names it previously printed as bare `(GtkImage)`:
`switch-on-symbolic`/`switch-off-symbolic` inside `GtkSwitch`, `caps-lock-symbolic` inside
`GtkPasswordEntry`, `system-search-symbolic`/`edit-clear-symbolic` inside `GtkSearchEntry`,
`value-increase-symbolic`/`value-decrease-symbolic` inside `GtkSpinButton`, and
`list-add-symbolic` inside the icon `GtkButton`. Promoted deliberately: it is a strict
improvement under the plan's ruling 6 (keep GTK's internal children), and it makes those dumps
assert something they previously could not — that the right internal icon is present.

## Downstream fit (stavekeeper)

- `viewer_window.ml`'s `build_texture` + `Picture.set_paintable` per frame → `Native.Picture`,
  which swaps the paintable in place (render 3 proves it) and costs nothing when the texture is
  unchanged.
- `cards.ml`'s `Picture.new_for_filename` + `set_can_shrink` + `set_content_fit` →
  `Node.picture ~content_fit:Contain ~can_shrink:true (Filename path)`.
- The spacer-under-overlay sizing trick needs Task 8's `Overlay` and `Attr.measure_overlay`;
  `Node.picture`'s doc comment names it so the caller is not left to rediscover it.

## Concerns / follow-ups

- None blocking. `Node.image` has no paintable source by design (it would be a second native
  widget); nothing in stavekeeper wants one — its paintables all go to `GtkPicture`.
- `W_image`'s `update` writes `pixel_size` unconditionally when it differs, including back to
  `-1`. That is correct (GTK reads `-1` as "derive from icon size") and is exercised by neither
  test, since no render goes back to `-1`; noted rather than filed.
