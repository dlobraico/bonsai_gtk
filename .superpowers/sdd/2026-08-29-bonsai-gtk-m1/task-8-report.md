# Task 8 report: named slots — CenterBox, Paned, Overlay

**Status:** complete. Commit `7323228` on `m1`. `scripts/ci.sh` ends `all green`.

## What landed

New files:

- `vtree/children.mli` — the mli M0 never wrote, documenting the shape/`child_ops`
  agreement invariant that makes the patcher's slot matching sound
- `src/widgets/w_center_box.ml`, `w_paned.ml`, `w_overlay.ml`

Modified: `vtree/children.ml`, `vtree/node.ml(i)`, `vtree/kind.ml(i)`, `vtree/attr.ml(i)`,
`src/widget_impl.ml(i)`, `src/patcher.ml`, `src/attr_apply.ml`, `src/widgets/w_box.ml`,
`src/widgets/registry.ml`, `src/live_tree.ml`, `test/test_widgets.ml`,
`test/live/live_containers.ml`, `test/live/expected_containers.txt`, and the
`Children.t` matches in `test/live/live_controls.ml` and `live_patcher.ml`.

`test/test_reconcile.ml` needed nothing, as the brief predicted: it works over plain node
lists and never names `Children.t`.

### `Children.Slots`

```ocaml
type 'a t =
  | No_children
  | Single of 'a option
  | List of 'a list
  | Slots of (string * 'a t) list
```

plus `iter` and `find_map`, both recursing through slots. `Node.find_by_test_id` is now
three lines over `Children.find_map`, and `Patcher.destroy` / `Patcher.disarm` recurse
with `Children.iter`, so both handle `Slots` for free.

### `Widget_impl`: named op records, `~node`, `updated`

The inline records became named types (`single_ops`, `list_ops`, `slot_ops`) so a slot can
name the shape it holds:

```ocaml
type list_ops =
  { insert : Widget.t -> after:Widget.t option -> node:Node.t -> Widget.t -> unit
  ; move : Widget.t -> child:Widget.t -> after:Widget.t option -> unit
  ; remove : Widget.t -> Widget.t -> unit
  ; updated : Widget.t -> old:Node.t -> node:Node.t -> Widget.t -> unit
  }
```

`Widget_impl.no_list_update` is the do-nothing `updated`; `w_box.ml` is the only existing
`List` impl and takes it, with `~node:_` on `insert`.

### Patcher

`mount` and `patch_children` are now dispatch over per-shape helpers — `mount_single`,
`mount_list`, `mount_slots`, `mount_children`; `patch_single`, `patch_list`,
`patch_slots`, `patch_children` — so a slot runs *exactly* the code a top-level shape
runs, under a longer path (`root/0/start/0`).

Per the plan's pre-flight correction, `~node` is threaded through every branch that
inserts: `mount_list`'s fold (`~node:l.node`), the op loop's `Insert`, and the op loop's
kind-changed `Update`.

`Update` on a child that stayed in place calls `ops.updated parent ~old ~node`, with
`old_node` captured **before** `patch` writes `live.node <- node`. That was the brief's
flagged likely bug; it is verified by mutation — moving the `let old_node = l.node in`
below the `patch` call makes the live test's second dump keep `(unmeasured (1))` instead
of dropping it, i.e. the flip is silently lost. Reverted and re-checked green.

Slot lists are zipped and required to agree on length *and* name order, with distinct
`Invalid_argument` messages for a length mismatch, an unknown slot name, and a slot whose
shape does not match its ops (spec §11). All three are unreachable from the public API —
every `Slots` node comes from a constructor written beside its impl — which the live test
notes rather than tries to provoke.

### Kinds and constructors

`center_box_props { shrink_center_last }`, `paned_props { orientation; position;
wide_handle; resize_{start,end}; shrink_{start,end} }`, `overlay_props = unit`, each with
`[@sexp_drop_if]` on the fields that carry the constructor default, per the repo
convention.

```ocaml
Node.center_box ?shrink_center_last ?start ?center ?end_ ()
  -> Slots [ "start", Single start; "center", Single center; "end", Single end_ ]
Node.paned ?position ?wide_handle ?resize_start ?resize_end ?shrink_start ?shrink_end
  ~orientation ~start ~end_ ()
  -> Slots [ "start", Single (Some start); "end", Single (Some end_) ]
Node.overlay ?overlays child
  -> Slots [ "child", Single (Some child); "overlays", List overlays ]
```

**Deviation from the brief's signature:** `Node.paned` gained a trailing `unit`. Without
it every optional argument is unerasable and the build fails on warning 16 — the same
reason `scale`, `separator` and the rest carry one.

### The two ambiguity resolutions

**`measure_overlay` as a per-child attr.** `Attr.measure_overlay : bool -> t`, classified
`is_event = false`, and inert in `Attr_apply.set`/`unset` — with a comment there naming it
as the first of the "container-placement" group (grid cells, stack page titles) whose
defining property is that the *parent* applies them. `w_overlay.ml` reads it off the child
node in `insert` and re-applies it from `updated` when it changes. `clip_overlay` is the
same mechanism and is deliberately not shipped; the mli says so and says it is three lines
if wanted.

**`Attr.on_position_changed : (int -> unit Ui_effect.t) -> t`**, connected in `w_paned.ml`
as `notify::position` reading `W.Paned.get_position` back off the widget. Documented as
informative rather than corrective, since `position` is ruling 2's exception.

### The two rulings

- **Ruling 2** — `Paned`'s `position` is *not* controlled: `reassert = None`, and the
  position is written in `create` and then only when the node's `position` actually
  changes. Documented on `Node.paned` and in the `update` body.
- **Ruling 4** — `Overlay`'s `move` is `fun _ ~child:_ ~after:_ -> ()`, with the reason
  (GTK has no positional overlay insert; `after` is unusable) on the op and on
  `Node.overlay`. `Widget_impl.list_ops.move`'s mli doc now carries the general note.

### `Live_tree.dump`

- `GtkCenterBox`: prints `no-shrink-center-last` only when set; which slots are filled is
  already visible in the children.
- `GtkPaned`: `(position N)`, `position-set`, `wide-handle`, and the resize/shrink flags.
  `position-set` is what distinguishes a divider the node pinned from one GTK computed —
  and this is the read-back for the one prop in the library that is deliberately
  uncontrolled.
- `GtkOverlay`: `(unmeasured (<idx> ...))`. The main child is **skipped**: it is not an
  overlay, and `gtk_overlay_get_measure_overlay` reports `false` for it unconditionally,
  so including it printed `(unmeasured (0 ...))` on every overlay in the first run.

## Tests

Headless (`test/test_widgets.ml`): the sexp of all three slotted nodes pinned (this is a
new `Children.t` constructor, so every expect file that ever prints one depends on the
shape), and `find_by_test_id` descending into slots.

Live (`test/live/live_containers.ml`), one paned holding a centre box and an overlay,
mounted then patched:

- **slot clear** — the centre box's `center` empties; `start` and `end` are untouched.
- **slot replace** — the centre box's `end` child changes kind (Button -> Label), so the
  patcher mounts a replacement and the slot's `set` installs it. Added beyond the brief:
  the brief's version only exercised clear.
- **overlay measure flag** — the badge overlay flips `measure_overlay false -> true`
  through the `updated` hook (`(unmeasured (1))` -> nothing), and a second overlay is
  inserted at the same time.
- **paned position read-back** — `(position 120) position-set` in both dumps.
- **`on_position_changed` connected** — a `notify::position` outside a patch reaches
  Bonsai exactly once.

`scripts/ci.sh`: format, `@all`, opam files, `@test/runtest`, live under xvfb, example
smoke — `all green`.

## Notes for later tasks

- Task 9's `Grid` and `Stack` are the reason `insert` takes `~node` and `updated` exists;
  both hooks are in place and `w_overlay.ml` is the worked example of using them.
- `Node.paned`'s `shrink_start`/`shrink_end` default to `false`. The mli documents what
  the flags mean and notes that all six are written at creation, so the node's value
  stands whatever GTK's own property default is — no claim is made about that default.
- `Attr.t` gained two more constructors, which is more fuel for the deferred sealing item
  (ruling 1, recorded for the M2 backlog in Task 11).

---

# Fix report — review round 1

**Status:** complete. Commit `ff8edea` on `m1`, "overlay: measure_overlay defaults to
false, matching GTK". `scripts/ci.sh` ends `all green`.

## 1 (Important) — `measure_overlay` now defaults to `false`

The review is right and the brief was wrong: `GtkOverlayLayoutChild:measure` is FALSE by
default, so a plain `gtk_overlay_add_overlay` leaves the child unmeasured. Shipping `true`
inverted GTK for every overlay child that names no attr — including the Stavekeeper
overlays (`crop_mode.ml`, `ink_mode.ml`, `text_annot.ml`) that add overlays and rely on
the GTK default.

Changed:

- `src/widgets/w_overlay.ml` — the `measure` helper's fallback is `false`, with the
  comment now naming `GtkOverlayLayoutChild:measure` as the source of the default. The
  flag is still written explicitly on every insert, so the library never depends on GTK's
  default holding.
- `vtree/attr.mli` — `false` documented as "GTK's own default, and this library's";
  `true` reframed as the opt-in ("the overlay then requests at least as much room as this
  child needs") rather than the thing being turned off.
- `vtree/node.mli` (the `overlay` doc) — "by default is also measured, so a large overlay
  child grows the whole overlay" → "by default is *not* measured (GTK's default), so the
  overlay stays the size of its main child however large the layers over it are", with
  `Attr.measure_overlay true` named as the opt-back-in.

**One correction to the ruling's mechanics:** there is no prop record or `drop_if` to
change. `measure_overlay` is an `Attr.t` constructor (`Measure_overlay of bool`), not a
field of a `Kind.*_props` record — `overlay_props` is `unit`, precisely because the flag
lives on the *child* node. `Attr.t` has no `[@sexp_drop_if]` anywhere (attrs print what
the caller wrote), so the node-level sexp is unchanged by this flip and the headless
expect blocks needed no re-promotion. The only place the default lived was
`w_overlay.ml`'s fallback.

**Live test**, now three renders so the hook is seen writing in both directions:

| render | `badge` attr | `extra` present | dump |
|---|---|---|---|
| mount | `measure_overlay false` | no | `(unmeasured (1))` |
| patch 1 | `measure_overlay true` | yes, no attr | `(unmeasured (2))` |
| patch 2 | `measure_overlay false` | no | `(unmeasured (1))` |

Patch 1 is the load-bearing one twice over: the badge drops out of `unmeasured` (the
`updated` hook writing `true`), and `extra` — which names no attr at all — appears in it,
which is the new default asserted directly. Patch 2 writes `false` back. Expected block
re-promoted.

## 2 — the overlay paint-order advice was wrong

`vtree/node.mli` said a stack whose paint order must change should "give each layer its
own key and accept a remount". That does not work: a keyed reorder is a `Move`, and
`Move` is exactly what the overlay's op swallows. Replaced with the two things that do
work — *change* the keys, so the reconciler emits remove + insert rather than a move, or
use a `native` node — and the text now says outright that keys are no way around this.

## 3 — `Live_tree` comment on the `unmeasured` indices

They are indices into the whole child list, main child included at 0, so the first overlay
child is 1 — which is why the flipped badge reads `(unmeasured (2))` above. The comment
said only that the main child is skipped, which invited reading the indices as
overlay-relative. Both facts are now stated.

## 4 — slot-mismatch message names the side that mismatched

`src/patcher.ml`'s `patch_slots` said only `slot %s does not exist on %s` using the node's
name, which does not say which of the three lists disagreed. `List.map` → `List.mapi`, and
the message is now:

```
%s: slot %d is %s in the live tree, %s in the node, %s on %s
```

(path, index, live name, node name, ops name, impl). Still unreachable from the public
API; it is the message someone gets while writing a new slot container.

## Verification

- `dune build @check` — clean.
- `dune build @test/runtest` — clean, no re-promotion needed (see the correction under 1).
- `BONSAI_GTK_LIVE_TESTS=1 xvfb-run -a dune build @test/live/runtest` — one expected diff,
  read and promoted; clean on re-run.
- `./scripts/ci.sh` tail, verbatim:

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

(The `Invalid_argument` line is `live_driver`'s own expected output — the nested-window
placement check — not a failure.)
