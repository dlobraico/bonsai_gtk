# Task 2 report — cross-cutting attrs, Label text properties, per-widget defaults snapshot

Branch `m1`, on top of `8381f7e`. Status: **complete, `scripts/ci.sh` green.**

## What changed

### New files

- **`vtree/ellipsize.ml:1-11`** — `type t = Start | Middle | End [@@deriving sexp_of, equal, compare]`.
  Deliberately no `None` constructor: absence of ellipsization is `None : t option`, so the
  constructors never shadow `Option.None`. Shape matches `vtree/align.ml` (no `.mli`).
- **`test/test_widgets.ml:1-42`** — the home for "does this constructor make the node I meant"
  tests. Two expect tests for `Node.label`: defaults, and every text property; plus one that
  `xalign` participates in `Kind.equal_props` while `same_kind` ignores it.

### `vtree/` — the GTK-free side

- **`vtree/attr.ml:19-23`** (`Name.t`), **`:48-52`** (`t`), **`:73-77`** (`name`),
  **`:84-104`** (`equal`), **`:123-127`** (constructors) — five new attrs: `Opacity of float`,
  `Focusable of bool`, `Can_focus of bool`, `Widget_name of string`, `Cursor_name of string`.
  Placed in `Name.t` immediately after `Height_request` and before `Test_id`, so the order
  `Attrs.diff` emits `Set`s in keeps the widget-wide attrs adjacent.
  Per the REVISED ruling 1, `Attr.t` is **not** sealed — the concrete variant stays public.
- **`vtree/attr.mli:82-99`** — doc comments on each of the five (the opacity/`visible`
  distinction; `focusable` vs `can_focus` and why unset is per-class; unknown cursor names).
- **`vtree/kind.ml:1-65` / `vtree/kind.mli:1-49`** — every kind's props became a **named**
  record with `[@@deriving sexp_of, equal]`: `label_props`, `button_props`, `box_props`,
  `window_props`. `equal_props` (`:57-64`) is now one derived call per kind. `label_props`
  gains `wrap`, `xalign`, `ellipsize : Ellipsize.t option`, `max_width_chars`, `width_chars`,
  `selectable`, `use_markup`.
- **`vtree/node.ml:17-45`** — `Node.label` takes the seven new optional arguments, each
  defaulting to GTK's own default (`wrap=false`, `xalign=0.5`, no ellipsize,
  `max_width_chars=-1`, `width_chars=-1`, `selectable=false`, `use_markup=false`), so
  `Node.label "x"` still describes exactly the widget M0 produced.
  **`vtree/node.mli:11-33`** carries the doc comment, including the `xalign` vs `Attr.halign`
  distinction.
- **`vtree/bonsai_gtk_vtree.ml:4`** — `module Ellipsize = Ellipsize`.

### `src/` — the GTK side

- **`src/attr_apply.ml:14-56`** — the defaults snapshot. `type defaults` is a 17-field record
  (`margin_*`, `halign`/`valign`, `hexpand`/`vexpand`, `sensitive`, `visible`, `tooltip`,
  `size_request`, `opacity`, `focusable`, `can_focus`, `widget_name`, `cursor`); `snapshot`
  reads all of it off a freshly created widget with the matching `Widget.get_*`.
  Every value `unset` can restore has a real ocgtk getter — nothing falls back to a
  documented constant.
- **`src/attr_apply.ml:70-95`** (`set`) — the five new `Set` arms
  (`set_opacity`, `set_focusable`, `set_can_focus`, `set_name`, `set_cursor_from_name`).
- **`src/attr_apply.ml:97-120`** (`unset`) — now `unset : defaults -> Widget.t -> Name.t -> unit`
  and **every** arm restores from the snapshot rather than a guessed constant. This is the
  M0-backlog bug (`Unset Visible -> true` is wrong for a `GtkWindow`) fixed generically.
  `Cursor_name` unsets through `Widget.set_cursor` with the snapshotted
  `Gdk.Wrappers.Cursor.t option`, not through `set_cursor_from_name`.
- **`src/attr_apply.mli:5-27`** — `type defaults` (abstract) + `val snapshot`, and
  `val apply : defaults:defaults -> Widget.t -> Attrs.op -> unit`.
- **`src/patcher.ml:10-18`** — `live` gains `defaults : Attr_apply.defaults`;
  **`:38-42`** `mount` calls `Attr_apply.snapshot widget` between `impl.create` and
  `apply_all`, i.e. before any attr has touched the widget; **`:118`** `patch` passes
  `~defaults:live.defaults`. **`src/patcher.mli:17-27`** mirrors the field with a doc comment.
- **`src/widgets/w_label.ml:1-56`** — rewritten around `Kind.label_props`. `apply_props` writes
  only the props that differ (`old:None` on the create path means "everything differs").
  `set_text`/`set_markup` reset the label's attribute list, so text and `use_markup` are
  treated as one unit: whichever of the two changed, the text is rewritten through the
  setter `use_markup` selects. `create` now builds `W.Label.new_ None` and applies props,
  rather than `new_ (Some text)`.
- **`src/live_tree.ml:18-23`** `ellipsize_name` (the pattern `align_name` already set —
  the Pango polymorphic variant has no `sexp_of`); **`:29-37`** `float_prop`/`string_prop`;
  **`:63-73`** `layout_props` gains opacity, widget name and cursor; **`:86-97`** the
  `"GtkLabel"` arm prints `wrap`, `xalign`, `ellipsize`, `max-width-chars`, `width-chars`,
  `selectable`, `markup`.
  **`focusable`/`can_focus` are deliberately not printed** (comment at `src/live_tree.ml:75-79`):
  their defaults are per widget class, so there is no constant to suppress against; the live
  test reads them back instead.
- **`src/bonsai_gtk.ml:8` / `src/bonsai_gtk.mli:24`** — `module Ellipsize = Bonsai_gtk_vtree.Ellipsize`.
- **`src/dune:13`** — `ocgtk.pango` added (needed by `w_label.ml` and `live_tree.ml` for
  `Pango.ellipsizemode`). No `dune-project` change: dune's `ocgtk.*` public names all belong
  to the one `ocgtk` opam package, confirmed by CI's `git diff --exit-code -- '*.opam'` gate
  passing untouched.

### Tests

- **`test/test_attrs.ml:56-79`** — the new round-trip/diff expect test.
- **`test/test_widgets.ml`** — new, as above.
- **`test/test_node.ml:51-56`** — `Label { text = "a" }` no longer typechecks against a named
  `label_props` (all fields required), so the `same_kind` test builds its kinds through
  `(Node.label text).Node.kind`. Its sexp expectations were re-promoted: a named record
  argument prints with one more paren level than an inline record
  (`(Button ((label (+))))` vs `(Button (label (+)))`), so the brief's "expect files are
  unaffected" note is wrong — three headless expect blocks changed shape and were promoted
  after reading. `test/test_handle.ml` likewise.
- **`test/live/live_patcher.ml:132-249`** — the attr section now sets and drops the five new
  attrs; then three added blocks:
  1. a `focusable`/`can_focus` read-back against a pristine `GtkLabel` (they are not in the
     dump), printing `focus restored: true true`;
  2. the case the snapshot exists for — a window created hidden with `Attr.visible true` and a
     label created visible with `Attr.visible false`; after both attrs are dropped the *same*
     `Unset Visible` op restores different values (window `hidden` again, label visible);
  3. every `Node.label` text property set, then switched to `use_markup`, then dropped back
     to defaults.
- **`test/live/expected_patcher.txt`** — promoted after reading.
  `expected_driver.txt`/`expected_signals.txt` are unchanged (see the `get_name` note below).

## TDD

### RED (verbatim)

```
$ dune build @test/runtest
File "test/test_attrs.ml", line 58, characters 8-20:
58 |       [ Attr.opacity 0.5
             ^^^^^^^^^^^^
Error: Unbound value "Attr.opacity"
File "test/test_widgets.ml", line 10, characters 15-19:
10 |          ~wrap:true
                    ^^^^
Error: The function applied to this argument has type
         ?key:Bonsai_gtk_vtree.Key.t ->
         ?attrs:Bonsai_gtk_vtree.Attr.t list -> Node.t
This argument cannot be applied with label "~wrap"
```

### GREEN — headless

The corrected blocks dune produced, read and promoted verbatim:

```
 |  print_s [%sexp (attrs : Attrs.t)];
-|  [%expect {| |}];
+|  [%expect {|
+|    ((Opacity 0.5) (Focusable true) (Can_focus false) (Widget_name sidebar)
+|     (Cursor_name pointer))
+|    |}];
 |  print_s
 |    [%sexp
 |      (Attrs.diff ~old:attrs ~new_:(Attrs.of_list [ Attr.opacity 1.0 ]) : Attrs.op list)];
-|  [%expect {| |}]
+|  [%expect {|
+|    ((Set (Opacity 1)) (Unset Focusable) (Unset Can_focus) (Unset Widget_name)
+|     (Unset Cursor_name))
+|    |}]
```

```
 |  print_s [%sexp (Node.label "plain" : Node.t)];
-|  [%expect {| |}];
+|  [%expect {|
+|    ((kind
+|      (Label
+|       ((text plain) (wrap false) (xalign 0.5) (ellipsize ())
+|        (max_width_chars -1) (width_chars -1) (selectable false)
+|        (use_markup false))))
+|     (attrs ()) (children No_children))
+|    |}];
...
-|  [%expect {| |}]
+|  [%expect {|
+|    ((kind
+|      (Label
+|       ((text styled) (wrap true) (xalign 0) (ellipsize (End))
+|        (max_width_chars 14) (width_chars 6) (selectable true) (use_markup true))))
+|     (attrs ()) (children No_children))
+|    |}]
```

```
 |  let a = (Node.label ~xalign:0. "x").kind in
 |  let b = (Node.label ~xalign:1. "x").kind in
 |  print_s [%sexp (Kind.same_kind a b, Kind.equal_props a b : bool * bool)];
-|  [%expect {| |}]
+|  [%expect {| (true false) |}]
```

```
$ dune promote && dune build @test/runtest
Promoting _build/default/test/test_attrs.ml.corrected to test/test_attrs.ml.
Promoting _build/default/test/test_handle.ml.corrected to
  test/test_handle.ml.
Promoting _build/default/test/test_node.ml.corrected to test/test_node.ml.
Promoting _build/default/test/test_widgets.ml.corrected to
  test/test_widgets.ml.
HEADLESS_GREEN
```

### GREEN — live

First live run surfaced a real bug in the `Live_tree` sketch: `string_prop "name" ... ~default:""`
churned **every** dump in **every** expected file, because GTK's `gtk_widget_get_name` falls back
to the widget's *class* name when no name was set — it never returns `""`:

```
-|(GtkWindow (title (drv)) (css (background)) hidden
+|(GtkWindow (title (drv)) (css (background)) (name GtkWindow) hidden
 | (children
-|  (GtkBox (spacing 0) (css (vertical))
-|   (children (GtkLabel (text "Count: 0"))
+|  (GtkBox (spacing 0) (css (vertical)) (name GtkBox)
+|   (children (GtkLabel (text "Count: 0") (name GtkLabel))
```

Fixed at `src/live_tree.ml:64-66` by suppressing against `type_name w` instead. After that,
`expected_driver.txt` and `expected_signals.txt` need no change at all, and the only live diff
is the one the new test asks for:

```
 |(GtkWindow (title (attrs)) (css (background)) hidden
 | (children
 |  (GtkLabel (text styled) (margin-start 1) (margin-end 2) (margin-top 3)
 |   (margin-bottom 4) (halign start) (valign center) hexpand vexpand
-|   (tooltip hi) (width-request 20) (height-request 30) hidden insensitive)))
+|   (tooltip hi) (width-request 20) (height-request 30) (opacity 0.501961)
+|   (name styled-label) (cursor pointer) hidden insensitive)))
 |(GtkWindow (title (attrs)) (css (background)) hidden
 | (children (GtkLabel (text styled))))
+|focus restored: true true
+|window created
+|(GtkWindow (title (vis)) (css (background))
+| (children (GtkLabel (text l) hidden)))
+|(GtkWindow (title (vis)) (css (background)) hidden
+| (children (GtkLabel (text l))))
+|window created
+|(GtkWindow (title (label)) (css (background)) hidden
+| (children
+|  (GtkLabel (text text) wrap (xalign 0) (ellipsize middle)
+|   (max-width-chars 14) (width-chars 6) selectable (cursor text))))
+|(GtkWindow (title (label)) (css (background)) hidden
+| (children (GtkLabel (text bold) markup)))
+|(GtkWindow (title (label)) (css (background)) hidden
+| (children (GtkLabel (text text))))
```

Reading that before promoting, in order:

- the styled label carries all five new attrs; after the patch that drops every attr, the
  second dump is a bare `(GtkLabel (text styled))` — every one restored.
- `focus restored: true true` — `focusable`/`can_focus` were set to non-default values and,
  after unset, match a `GtkLabel` that never had them touched.
- the window/label pair: on mount the window is visible (no `hidden`) and the label is
  `hidden`; after both `Attr.visible`s are dropped, the **window** is `hidden` and the label
  is not. That is the M0-backlog bug, fixed: one `Unset Visible` op, two different restored
  values, decided per widget rather than per attribute.
- every label text property lands and then comes back to GTK's default. `(cursor text)` on the
  selectable label is GTK's own doing (a selectable `GtkLabel` installs a text cursor) and
  disappears with `selectable`; `use_markup` shows as `markup` with `get_text` reporting the
  rendered `bold`.

```
$ dune promote && BONSAI_GTK_LIVE_TESTS=1 xvfb-run -a dune build @test/live/runtest
Promoting _build/default/test/live/output_patcher.txt to
  test/live/expected_patcher.txt.
LIVE_GREEN
```

## `scripts/ci.sh` tail

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

(The `Invalid_argument` line is `live_driver`'s own broken-driver case printing to stderr —
pre-existing, unchanged by this task.)

## Self-review against the contract

| Requirement | Where |
|---|---|
| `opacity` apply + unset + test | `attr_apply.ml:87,113`; live dump `(opacity 0.501961)` → gone |
| `focusable` apply + unset + test | `attr_apply.ml:88,114`; live `focus restored: true …` |
| `can_focus` apply + unset + test | `attr_apply.ml:89,115`; live `focus restored: … true` |
| `widget_name` apply + unset + test | `attr_apply.ml:90,116`; live `(name styled-label)` → gone |
| `cursor_name` apply + unset + test | `attr_apply.ml:91,117`; live `(cursor pointer)` → gone |
| Layout attrs Stavekeeper uses (`margin_*`, size requests, `halign`/`valign`, `hexpand`/`vexpand`, `tooltip`, `sensitive`, `visible`, `css_class`) | all present from M0; every one's `unset` now restores the snapshot (`attr_apply.ml:97-120`), exercised by the live attr block |
| Label `wrap`/`xalign`/`ellipsize`/`max_width_chars`/`width_chars`/`selectable`/`use_markup` | `kind.ml:7-20`, `node.ml:17-45`, `w_label.ml:16-36`; headless `test_widgets.ml`, live label block |
| Unset restores a per-widget creation-time snapshot | `patcher.ml:38-42` (snapshot taken between `create` and `apply_all`), `attr_apply.ml:97-120` |
| Headless tests for the vtree side | `test/test_widgets.ml`, `test/test_attrs.ml:56-79` |
| A live test that reads a property back after unset | `live_patcher.ml:163-181` (focus read-back) + the window/label `visible` block + all three dumps |
| `scripts/ci.sh` green | yes, tail above |
| Ruling 1: do **not** seal `Attr.t` | `vtree/attr.mli:25-56` still exposes the concrete variant |
| Ambiguity resolution: creation-time value read off the widget, stored on the live node | `patcher.ml:41`, `patcher.mli:21-23` |
| Ambiguity resolution: ellipsize takes the Pango enum | `w_label.ml:5-10` maps `Ellipsize.t option -> Pango.ellipsizemode` (`` `NONE/`START/`MIDDLE/`END ``) |

~~The "if ocgtk lacks a getter, document the GTK default fallback" escape was **not needed**:
every one of the seventeen snapshot fields has a real ocgtk getter, so `unset` is exact for
all of them.~~ **Corrected in fix round 1 — this overclaimed.** Every one of the seventeen
fields does have a real ocgtk *getter*, but `widget_name` lacks a NULL-accepting *setter*
(`Widget.set_name : t -> string -> unit`), so `Unset Widget_name` cannot restore "this
widget has no name" and instead writes back the class name `get_name` reported. Sixteen of
seventeen are exact; see fix round 1 below.

## Concerns / notes for later tasks

1. **The named-props migration is a small breaking change for anyone writing `Kind.t` literals.**
   `Label { text = "a" }` no longer typechecks (a named record needs every field). Only
   `test/test_node.ml` was affected in-tree. Tasks 3–9 should build their kinds through `Node.*`
   constructors rather than literals.
2. **`Kind.t`'s sexp gained a paren level for every kind**, contrary to the brief's note. Any
   future task that hand-writes an expected `Kind.t` sexp should copy it from a promoted run.
3. **`Live_tree` prints `opacity` as GTK reports it, not as set**: GTK stores opacity in 8 bits,
   so `Attr.opacity 0.5` reads back `0.501961`. Expected files will always show the quantised
   value; do not "fix" it to `0.5`.
4. **`focusable`/`can_focus` remain absent from `Live_tree.dump`.** Any later task that wants
   them visible needs the per-class default to compare against, which the dump has no access to
   — the read-back-against-a-pristine-widget pattern in `live_patcher.ml:163-181` is the
   available technique.
5. **`snapshot` is 17 getter calls per widget creation.** Fine at M1 scale (it is once per mount,
   never per patch), but it grows with every attr M1 adds. If it becomes a concern the shape to
   reach for is lazy per-field capture on first `Set`, not a per-kind table.
6. **`Attr.t` stays unsealed** per ruling 1; Task 11 records the seal as an M2 backlog item.

---

# Fix round 1 of 5 — review response

Approved with two Important items. All three (two Important + one Minor) addressed; nothing
deferred. Commit `09f0a5a`, on top of `b477828`.

## 1. `unset widget_name` is not exact — documented (Important)

The gap: ocgtk exposes `Widget.set_name : t -> string -> unit`, with no `string option`
overload, so there is no way to write NULL back. `Widget.get_name` on an unnamed widget
returns the widget's *class* name (`"GtkLabel"`), so the snapshot stores that string and
`Unset Widget_name` writes it back as a real name. The widget therefore ends up carrying an
explicit CSS id it did not have before the attr was ever applied, and a `#GtkLabel` selector
would start matching it. Harmless unless a stylesheet uses class names as ids — but it is the
one place "unset means put back exactly what GTK had" is not literally true, so it is now
said out loud in both places a reader would look:

- **`vtree/attr.mli:100-110`** — a paragraph on `Attr.widget_name` stating the cause
  (`set_name` takes a `string`, not a `string option`), the effect (unset writes the class
  name, an explicit id where there was none), the practical consequence (`#GtkLabel` would
  match), and the fix (a NULL-accepting `set_name` in the ocgtk fork).
- **`src/attr_apply.mli:5-22`** — the `defaults` doc comment ends with the same caveat,
  cross-referencing `Bonsai_gtk_vtree.Attr.widget_name`.
- **`src/attr_apply.ml:14-28`** — the same, in the implementation comment beside `snapshot`.
- The report's "exact for all seventeen" claim above is struck through and corrected in place.

**Backlog item for Task 11 to collect (ocgtk fork):** widen
`Gtk.Wrappers.Widget.set_name` to `t -> string option -> unit`, matching
`set_cursor_from_name`/`set_tooltip_text`, so `Unset Widget_name` can restore "unnamed".
The C side is a plain `gtk_widget_set_name(w, NULL)`; the binding is the only thing missing.
Once that lands, the two doc paragraphs above and this caveat come out. Nothing in
`bonsai_gtk` needs restructuring for it — `defaults.widget_name` just becomes a
`string option`.

## 2. `[@sexp_drop_if]` on default-valued props (Important, ruling adopted)

**`vtree/kind.ml:1-38`** and **`vtree/kind.mli:1-40`** — every prop field whose value equals
GTK's default is now dropped from the sexp:

| record | field | dropped when |
|---|---|---|
| `label_props` | `wrap` | `false` |
| | `xalign` | `Float.equal 0.5` |
| | `ellipsize` | `Option.is_none` |
| | `max_width_chars` | `Int.equal (-1)` |
| | `width_chars` | `Int.equal (-1)` |
| | `selectable` | `false` |
| | `use_markup` | `false` |
| `button_props` | `label` | `Option.is_none` |
| `box_props` | `spacing` | `Int.equal 0` |
| | `homogeneous` | `false` |
| `window_props` | `title` | `Option.is_none` |
| | `default_size` | `Option.is_none` |

`label_props.text` and `box_props.orientation` are never dropped: neither has a default —
both are required arguments of their `Node` constructor.

The attributes are written on both the `.ml` and the `.mli` (ppx_sexp_conv accepts them in an
interface and generates only the `val`, so the two type declarations stay textually
identical and a reader of the `.mli` can see which fields are print-suppressed).

**Equality is unaffected**, as required: `[@sexp_drop_if]` is consumed by `sexp_of` only, and
`equal_label_props` and friends still compare every field. The existing
`test/test_widgets.ml` assertion `(Kind.same_kind a b, Kind.equal_props a b) = (true, false)`
for two labels differing only in `xalign` — a field that is now *dropped* when it equals
`0.5` — is exactly the test that pins this, and it still passes unchanged.

### The expect files got shorter, and still pin the same behaviour

```
$ dune runtest    # before promotion, the corrected blocks
 |  print_s [%sexp (Node.label "plain" : Node.t)];
 |  [%expect
-|    {|
-|    ((kind
-|      (Label
-|       ((text plain) (wrap false) (xalign 0.5) (ellipsize ())
-|        (max_width_chars -1) (width_chars -1) (selectable false)
-|        (use_markup false))))
-|     (attrs ()) (children No_children))
-|    |}];
+|    {| ((kind (Label ((text plain)))) (attrs ()) (children No_children)) |}];
```

```
-|    ((kind (Window ((title (Counter)) (default_size ())))) (attrs ())
+|    ((kind (Window ((title (Counter))))) (attrs ())
 |     (children
 |      (Single
-|       (((kind (Box ((orientation Vertical) (spacing 0) (homogeneous false))))
-|         (attrs ())
+|       (((kind (Box ((orientation Vertical)))) (attrs ())
 |         (children
 |          (List
-|           (((kind
-|              (Label
-|               ((text "Count: 0") (wrap false) (xalign 0.5) (ellipsize ())
-|                (max_width_chars -1) (width_chars -1) (selectable false)
-|                (use_markup false))))
-|             (attrs ((Test_id count))) (children No_children))
+|           (((kind (Label ((text "Count: 0")))) (attrs ((Test_id count)))
+|             (children No_children))
```

The `show_diff` block in `test/test_handle.ml` — the one that has to keep pinning the same
behaviour — went from a four-line intra-record diff back to the single-line diff it was
before this task, and still pins precisely `Count: 0` → `Count: 2` with everything else
unchanged:

```
-|             (((kind
-|                (Label
-|    -|           ((text "Count: 0") (wrap false) (xalign 0.5) (ellipsize ())
-|    +|           ((text "Count: 2") (wrap false) (xalign 0.5) (ellipsize ())
-|                  (max_width_chars -1) (width_chars -1) (selectable false)
-|                  (use_markup false))))
-|               (attrs ((Test_id count))) (children No_children))
+|    -|       (((kind (Label ((text "Count: 0")))) (attrs ((Test_id count)))
+|    +|       (((kind (Label ((text "Count: 2")))) (attrs ((Test_id count)))
+|               (children No_children))
```

Confirmed shorter, not longer — and back to the pre-task baseline:

```
                              before fix   after fix   baseline @8381f7e
test/test_node.ml                 68           63            63
test/test_handle.ml               73           63            65
test/test_widgets.ml              42           35             —  (new file)
```

Every other assertion in those three files is byte-identical apart from the dropped fields:
`find_by_test_id` still returns the button, the unknown-test-id failure still raises, and
`same_kind`/`equal_props` still answer `(true, false)`.

`Live_tree.dump` is untouched by this — it reads GTK, not `Kind.t` — so
`test/live/expected_*.txt` needed no change and the live suite passed with no diff.

## 3. Minor items, folded in

- **"class defaults" → creation-time values.** The snapshot is taken *after*
  `Widget_impl.create` has applied the kind's props, so it is not the widget class's
  pristine default — it is what this particular widget looks like before any *attribute*
  has been applied. Corrected at **`src/attr_apply.ml:14-28`**, **`src/patcher.ml:39-41`**,
  **`src/patcher.mli:21-24`** and **`src/attr_apply.mli:5-22`**.
- **The `selectable` + `cursor_name` interplay**, named in all four places as the concrete
  consequence: a `Node.label ~selectable:true` has already had GTK install a text cursor by
  the time `snapshot` runs, so `Unset Cursor_name` on that label restores the *text* cursor
  rather than no cursor. That is the intended reading of "put back what this widget had" —
  and it is visible in the promoted live dump, where the selectable label shows
  `(cursor text)` with no `cursor_name` attr anywhere in the test.
- **`Attr.opacity` clamping** — `vtree/attr.mli:82-85` now says GTK clamps anything outside
  `0. .. 1.`.

## Verification (verbatim)

```
$ dune build @check
CHECK_OK
```

```
$ dune runtest
$ dune build @vtree/fmt @src/fmt @test/fmt @test_lib/fmt @test/live/fmt @examples/fmt
STABLE after round 1
--- runtest ---
--- fmt ---
DONE
```
(both aliases silent = clean)

```
$ BONSAI_GTK_LIVE_TESTS=1 xvfb-run -a dune build @test/live/runtest
bonsai_gtk: exception in frame, stopping the driver: (Invalid_argument
  "root/0/1: a Node.window may only be the root node, not a child of another node")
LIVE_DONE
```
(no diff; the `Invalid_argument` line is `live_driver`'s own broken-driver case on stderr)

```
$ ./scripts/ci.sh
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

## Carried forward (not done here, per the review)

- `w_label.ml`'s multi-prop writes get `freeze_notify`/`thaw_notify` via `Widget_impl.batch`
  in Task 3.
- ocgtk-fork backlog: NULL-accepting `Widget.set_name` (item 1 above), for Task 11 to collect.

## Concerns after this round

1. `[@sexp_drop_if]` means a node's printed form no longer round-trips to the record — there
   is no `t_of_sexp` on `Kind.t` and none is wanted, but anyone tempted to add one later must
   know the sexps are lossy by design.
2. The drop predicates duplicate the defaults in `Node.label`'s optional arguments
   (`0.5`, `-1`, `false`). They can drift apart: a future change to a `Node` default without
   the matching `sexp_drop_if` edit would print a field the caller never set. Two lines apart
   in two files; worth a glance in Task 10's sweep, not worth a shared constant now.
