# bonsai_gtk

Build GTK4 desktop applications with [Bonsai](https://github.com/janestreet/bonsai), in the
spirit of `bonsai_web` and `bonsai_term`. An app is a pure function
`local_ Bonsai.graph -> Node.t Bonsai.t`; the library owns the GTK main loop, turns GTK
signals into Bonsai events, and keeps a live GTK widget tree in sync with the declarative
`Node.t` the app computes.

Status: pre-alpha (M1) — 29 `Node.*` constructors covering displays, controls, text
entry, layout and stack-based navigation (see [Widgets](#widgets)), the `Native` escape
hatch, the runtime loop, and headless testing. See [Limitations](#limitations) below.

## Example

The counter example (`examples/counter.ml`), verbatim:

```ocaml
open! Core
open Bonsai_gtk
open Bonsai.Let_syntax

let app (graph @ local) =
  let count, set_count = Bonsai.state 0 graph in
  let%arr count and set_count in
  Node.window
    ~title:"bonsai_gtk counter"
    ~default_size:(240, 120)
    (Node.box
       ~orientation:Vertical
       ~spacing:8
       ~attrs:[ Attr.margin 12 ]
       [ Node.label ~attrs:[ Attr.css_class "title-2" ] (sprintf "Count: %d" count)
       ; Node.box
           ~orientation:Horizontal
           ~spacing:8
           ~attrs:[ Attr.halign Center ]
           [ Node.button ~attrs:[ Attr.on_clicked (set_count (count - 1)) ] ~label:"−" ()
           ; Node.button
               ~attrs:
                 [ Attr.on_clicked (set_count (count + 1))
                 ; Attr.css_class "suggested-action"
                 ]
               ~label:"+"
               ()
           ; Node.button
               ~attrs:[ Attr.on_clicked (set_count 0); Attr.sensitive (count <> 0) ]
               ~label:"Reset"
               ()
           ]
       ; Node.button
           ~attrs:[ Attr.on_clicked Effect.quit; Attr.halign End ]
           ~label:"Quit"
           ()
       ])
;;

let () = exit (Bonsai_gtk.start ~application_id:"org.bonsai_gtk.examples.counter" app)
```

Run it with `dune exec examples/counter.exe` (needs a display; under `nix develop` you also
have `xvfb-run -a dune exec examples/counter.exe` for a headless one).

`examples/gallery.ml` renders one of every M1 widget in a `Stack` with a sidebar —
`dune exec examples/gallery.exe` — and is the quickest way to see what a constructor
looks like on screen.

## Libraries

- **`bonsai_gtk.vtree`** (`vtree/`) — the virtual widget tree (`Node`, `Attr`, `Key`,
  `Align`, `Orientation`) and the pure keyed-list diff (`Reconcile`) it patches with.
  Depends on nothing GTK-specific, so it links into `ppx_expect` test executables.
- **`bonsai_gtk`** (`src/`) — the GTK4 runtime: `start` runs an app as a `GtkApplication`
  and keeps a live widget tree in sync with the `Node.t` it computes each frame. Re-exports
  `vtree`'s modules plus `Widget` (the live GTK widget type), `Native` (the escape hatch for
  widgets this library has no `Node` constructor for), `Effect` (`Ui_effect` plus `quit`),
  and `Expert.Driver` for callers that want to drive frames by hand.
- **`bonsai_gtk_test`** (`test_lib/`) — a headless test handle built on `bonsai_gtk.vtree`
  only (no GTK, no display needed): `Bonsai_test.Handle` over the `Node.t` sexp tree, with
  `Click`, `Toggle`, `Set_text`, `Activate` and `Set_value` actions dispatched by
  `test_id`.

## Widgets

| | |
|---|---|
| **Display** | `label` (wrap, xalign, ellipsize, max-width-chars, markup), `image`, `picture`, `separator`, `progress_bar`, `spinner` |
| **Controls** | `button` (label / icon / arbitrary child / frameless), `toggle_button`, `check_button`, `switch`, `spin_button`, `scale` |
| **Text** | `entry`, `password_entry`, `search_entry` — controlled: the widget is written only when the model disagrees with what it currently shows, so echoing what the user typed never moves the caret. `on_search_changed` reports only searches the *user* produced: GTK arms its debounce from any text change, so the library filters out the emission carrying back a write it made itself |
| **Layout** | `box`, `grid` (`Attr.grid_cell`), `center_box`, `paned`, `overlay` (`Attr.measure_overlay`), `frame`, `expander`, `revealer`, `scrolled_window` |
| **Navigation** | `stack` + `stack_switcher` + `stack_sidebar` (pages keyed by `Key.t`, switchers name their stack) |
| **Window** | `window` (one per app until M3) |
| **Escape hatch** | `Node.native` for anything else, plus `Native.Picture` for a widget fed from a `GdkPaintable` |

That is all 29 `Node.*` constructors; `vtree/node.mli` is the reference, and each
constructor's doc comment names the properties it does *not* bind.

Shared attributes on every widget: `css_class`, `margin_*`, `halign`/`valign`,
`hexpand`/`vexpand`, `width_request`/`height_request`, `sensitive`, `visible`, `tooltip`,
`opacity`, `focusable`/`can_focus`, `widget_name`, `cursor_name`, `test_id`. Dropping an
attribute restores the value that widget was created with, not a global default.

Container-specific attributes are inert elsewhere: `Attr.grid_cell` (a `grid` child's
column/row/span), `Attr.measure_overlay` (whether an `overlay` child counts towards the
overlay's size request), `Attr.page_title` (a `stack` page's switcher label).

Event attributes are `on_clicked`, `on_toggled`, `on_changed`, `on_activate`,
`on_search_changed`, `on_value_changed`, `on_expanded_changed`, `on_revealed`,
`on_position_changed` and `on_visible_child_changed`. Attaching one to a widget that has
no such signal raises at mount and at patch, rather than silently doing nothing.

See §7 of the design doc for what M2 (lists & text) and M3 (chrome & popups) add.

## Headless testing

Apps that keep their view function in a `bonsai_gtk.vtree`-only module (the same rule
`bonsai_web` apps already follow) can be tested with `Bonsai_gtk_test`, no display required.
From `test/handle/test_handle.ml`:

```ocaml
open! Core
open Bonsai_gtk_vtree
open Bonsai.Let_syntax

let counter (graph @ local) =
  let count, set_count = Bonsai.state 0 graph in
  let%arr count and set_count in
  Node.window
    ~title:"Counter"
    (Node.box
       ~orientation:Vertical
       [ Node.label ~attrs:[ Attr.test_id "count" ] (sprintf "Count: %d" count)
       ; Node.button
           ~attrs:[ Attr.test_id "inc"; Attr.on_clicked (set_count (count + 1)) ]
           ~label:"+"
           ()
       ])
;;

let%expect_test "clicking the button re-renders the label" =
  let handle = Bonsai_gtk_test.create counter in
  Bonsai_gtk_test.Handle.show handle;
  [%expect {| ... |}];
  Bonsai_gtk_test.Handle.do_actions handle [ Click "inc" ];
  Bonsai_gtk_test.Handle.recompute_view handle;
  Bonsai_gtk_test.Handle.do_actions handle [ Click "inc" ];
  Bonsai_gtk_test.Handle.show_diff handle;
  [%expect {| ... |}]
;;
```

The actions are `Click of test_id` (fires `Attr.on_clicked`), `Toggle of test_id` (a
`toggle_button`/`check_button`/`switch`, fired with the negation of the `active` the node
currently renders), `Set_text of test_id * string` and `Set_value of test_id * float` (the
text the user typed / the value they moved to, passed through verbatim so the test can
watch the *model* clamp or rewrite it), and `Activate of test_id` (Enter pressed in a text
widget). Each fails loudly if the node it names carries no matching handler.

`do_actions` dispatches every action in one call against a single view snapshot, so a second
click that depends on the state the first click just set needs a `recompute_view` between
them — see the doc comment on `Bonsai_gtk_test.create` for why.

The handle validates nothing structural. It depends on `bonsai_gtk.vtree` alone — that is
what keeps it and your view functions free of ocgtk — so it cannot see which signals a
widget can emit, and an `Attr.on_clicked` on a `Node.label` takes a `Click` and goes green
while mounting the same tree raises on the first frame. Same for a `grid` child with no
`Attr.grid_cell`, duplicate sibling keys, and the rest of the list under
[Limitations](#limitations). A headless suite is not a substitute for running the app.

## Development

    nix develop                 # dev shell (GTK4 stack, opam, xvfb)
    ./scripts/setup-switch.sh   # once: creates ./_opam (OxCaml) and pins ocgtk
    dune build && dune runtest
    BONSAI_GTK_LIVE_TESTS=1 xvfb-run -a dune build @test/live/runtest  # live GTK tests
    ./scripts/ci.sh             # everything above, plus the ocgtk pin, the per-package
                                # `-p` builds and the example smoke test

`dune runtest` alone only runs the pure and headless suites (`test/` and `test/handle/`,
both ocgtk-free); the live tests under `test/live/` drive a real GTK display via `xvfb-run`
and are opt-in through `BONSAI_GTK_LIVE_TESTS=1`, which is what `scripts/ci.sh` sets.

The two suites are split across the two packages on purpose: `dune build -p <pkg> @runtest`
is what `opam install <pkg> --with-test` runs, and it hides every library belonging to the
*other* package, so no test directory may depend on both. `scripts/ci.sh` runs both `-p`
builds so that cannot regress.

See `docs/superpowers/specs/2026-08-28-bonsai-gtk-design.md` for the design.

## ocgtk fork

`bonsai_gtk` pins a commit on a fork of [`ocgtk`](https://github.com/chris-armstrong/ocgtk)
that carries GC-safety and ownership fixes upstream doesn't have yet (the signal-closure
marshaller crash alone is load-bearing for a library whose whole job is connecting
signals). See `docs/upstream/README.md` for the fork, the fixes, and their upstreaming
status.

## Limitations

M1 covers the widgets listed under [Widgets](#widgets); anything else is a `Node.native`
case. What is deliberately still out:

- **Not bound yet.** `ListBox`, `FlowBox`, `DropDown`, `TextView`, `Notebook`, `LevelBar`,
  `Calendar` and `EditableLabel` are M2; `HeaderBar`, `ActionBar`, `Popover`,
  `MenuButton` + `Node.menu`, alert/file dialogs, multi-window (`Node.windows`) and
  `Attr.shortcut` are M3. One window per app until then.
- **Out of scope until a follow-up design.** `ListView`/`ColumnView`/`GridView` (ocgtk
  generates no `SignalListItemFactory` signals, so they can't be populated without new C
  stubs); custom Cairo drawing (`DrawingArea.set_draw_func` is unbound in ocgtk); drag and
  drop.
- **`Stack`, `Grid` and `Overlay` children are never reordered.** GTK exposes no reorder
  API for them, so a keyed `Move` within those containers is a no-op: children stay in the
  order they were first added. Keys still preserve identity, so state is not lost — but if
  the order is meaningful, change the placement (`Attr.grid_cell`) or the keys. Changing a
  `Grid` child's cell re-attaches it, which also moves it to the end of GTK's child list;
  the cell is the placement, so nothing moves on screen.
- **No radio groups** (`CheckButton.set_group` is unbound): model the exclusive choice in
  Bonsai state and render the `active` flags from it.
- **Per-widget gaps**, each a `Node.native` case and each named in its constructor's doc
  comment: no `Scale` marks, no `ProgressBar.pulse`, no `Entry` icons, no
  `SearchEntry.set_key_capture_widget`, no `Frame.set_label_widget`.
- **`Paned`'s position is uncontrolled** — writing it every frame would fight the drag
  handle. `Attr.on_position_changed` reports where the user left it.
- **`Bonsai_gtk_test.Action.t` is an unsealed public variant**, so every action a later
  milestone adds is a breaking change for a downstream exhaustive match. Sealing it is on
  the backlog (`docs/m1-backlog.md`). `Attr.t` no longer is: its constructors moved to
  `Attr.Private` and `Attr.t` is a private abbreviation of it, so an application can
  neither build one from a raw constructor nor match on one without writing
  `(a :> Attr.Private.t)` — which is supported, carries no stability promise, and is
  where a milestone's new constructors will land. Build attrs with `Attr.css_class` and
  friends. `Attr.Name.t` stays a concrete variant, deliberately: `Attr_apply.unset`'s
  exhaustive match over it is what makes "unset restores the creation-time default"
  impossible to forget.
- **Structural mistakes are caught at mount, not by `Bonsai_gtk_test`** — a non-window
  root, a `Node.window` below the root, duplicate keys among siblings, an event attribute
  on a widget with no such signal, a `grid` child with no `Attr.grid_cell`, a `stack` page
  with no key, two `stack`s under one name, a `stack_switcher` naming a stack that does not
  exist. All are `Invalid_argument` carrying the node path, raised on the frame that builds
  or patches that node; none of them stops a headless test.
- **Every frame patches**, including frames on which Bonsai hands back the physically
  identical root — that is what puts a widget back after the model declines the user's
  edit. An idle frame walks the shadow tree and makes no GTK call; a walk restricted to
  the re-assert and fixup passes is on the backlog.

See §7 of the design doc for the full widget catalogue and milestone plan (M2 lists &
text, M3 chrome & popups).
