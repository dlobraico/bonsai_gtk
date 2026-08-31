# bonsai_gtk

Build GTK4 desktop applications with [Bonsai](https://github.com/janestreet/bonsai), in the
spirit of `bonsai_web` and `bonsai_term`. An app is a pure function
`local_ Bonsai.graph -> Node.t Bonsai.t`; the library owns the GTK main loop, turns GTK
signals into Bonsai events, and keeps a live GTK widget tree in sync with the declarative
`Node.t` the app computes.

Status: pre-alpha (M2) — 37 `Node.*` constructors covering displays, controls, text
entry, layout, stack-based navigation and the three keyed containers (see
[Widgets](#widgets)); five event-controller attributes for clicks, keys and focus (see
[Input](#input)); `Expert.embed`, for rendering a Bonsai tree into a container an existing
GTK application owns (see [Embedding](#embedding)); the `Native` escape hatch, the runtime
loop, and headless testing. See [Limitations](#limitations) below.

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

`examples/gallery.ml` renders one of every widget in a `Stack` with a sidebar —
`dune exec examples/gallery.exe` — and is the quickest way to see what a constructor
looks like on screen. Its *Input* page is the one to run by hand: it is where
`Attr.on_click`, `Attr.on_key_pressed` and the focus attrs are exercised against a real
pointer and a real keyboard, which is the half of [Input](#input) no test in this
repository can reach (see [Limitations](#limitations)).

## Libraries

- **`bonsai_gtk.vtree`** (`vtree/`) — the virtual widget tree (`Node`, `Attr`, `Key`,
  `Align`, `Orientation`) and the pure keyed-list diff (`Reconcile`) it patches with.
  Depends on nothing GTK-specific, so it links into `ppx_expect` test executables.
- **`bonsai_gtk`** (`src/`) — the GTK4 runtime: `start` runs an app as a `GtkApplication`
  and keeps a live widget tree in sync with the `Node.t` it computes each frame. Re-exports
  `vtree`'s modules plus `Widget` (the live GTK widget type), `Native` (the escape hatch for
  widgets this library has no `Node` constructor for), `Effect` (`Ui_effect` plus `quit`),
  and `Expert.Driver` for callers that want to drive frames by hand, plus `Expert.embed`
  for rendering into a container the caller owns ([Embedding](#embedding)).
- **`bonsai_gtk_test`** (`test_lib/`) — a headless test handle built on `bonsai_gtk.vtree`
  only (no GTK, no display needed): `Bonsai_test.Handle` over the `Node.t` sexp tree, with
  nineteen actions dispatched by `test_id` (see [Headless testing](#headless-testing)).

## Widgets

| | |
|---|---|
| **Display** | `label` (wrap, xalign, ellipsize, max-width-chars, markup), `image`, `picture`, `separator`, `progress_bar`, `spinner`, `level_bar` (continuous or discrete, `Level_bar_mode`) |
| **Controls** | `button` (label / icon / arbitrary child / frameless), `toggle_button`, `check_button`, `switch`, `spin_button`, `scale` |
| **Lists** | `list_box` (keyed rows, controlled selection, per-row `Attr.row_selectable`/`row_activatable`, `?placeholder`), `flow_box` (keyed children, controlled selection, geometry as props), `notebook` (keyed pages, `Attr.tab_label`, controlled `~current_page`, real reordering — with `box`, one of the two containers whose children move in place, since it has `gtk_notebook_reorder_child`). Every child needs a `~key`, and every handler speaks in keys |
| **Text** | `entry`, `password_entry`, `search_entry`, `text_view` (controlled buffer, `Wrap_mode`, caret preserved as a character offset), `editable_label` — controlled: the widget is written only when the model disagrees with what it currently shows, so echoing what the user typed never moves the caret. Text GTK cannot hold is handled differently by each of the five — see Limitations. `on_search_changed` reports only searches the *user* produced: GTK arms its debounce from any text change, so the library filters out the emission carrying back a write it made itself |
| **Pickers** | `drop_down` (string list, controlled `~selected`), `calendar` (controlled `Core.Date.t`, marked days) |
| **Layout** | `box`, `grid` (`Attr.grid_cell`), `center_box`, `paned`, `overlay` (`Attr.measure_overlay`), `frame`, `expander`, `revealer`, `scrolled_window` |
| **Navigation** | `stack` + `stack_switcher` + `stack_sidebar` (pages keyed by `Key.t`, switchers name their stack) |
| **Window** | `window` (one per app until M3) |
| **Escape hatch** | `Node.native` for anything else, plus `Native.Picture` for a widget fed from a `GdkPaintable` |

That is all 37 `Node.*` constructors; `vtree/node.mli` is the reference, and each
constructor's doc comment names the properties it does *not* bind.
`test/handle/test_gallery.ml` checks the claim against `Kind.Variants.descriptions`, so a
constructor added and never put in the gallery fails the suite rather than quietly
escaping this table.

Four small enum modules come with the M2 widgets and are re-exported from `Bonsai_gtk`
beside M1's `Align`, `Ellipsize`, `Content_fit`, `Icon_size`, `Image_source`,
`Picture_source`, `Policy`, `Reveal_transition`, `Stack_transition`, `Orientation` and
`Grid_cell`: `Selection_mode` (a `list_box`'s or `flow_box`'s `?selection_mode`),
`Tab_position` (a `notebook`'s `?tab_pos`), `Wrap_mode` (a `text_view`'s `?wrap`) and
`Level_bar_mode` (a `level_bar`'s `?mode`). Each is a plain variant with a doc comment
saying which GTK default it carries.

Shared attributes on every widget: `css_class`, `margin_*`, `halign`/`valign`,
`hexpand`/`vexpand`, `width_request`/`height_request`, `sensitive`, `visible`, `tooltip`,
`opacity`, `focusable`/`can_focus`, `widget_name`, `cursor_name`, `test_id`. Dropping an
attribute restores the value that widget was created with, not a global default.

Six *placement* attributes are held by the parent rather than applied to the child, and
each is read by exactly one container: `Attr.grid_cell` (a `grid` child's
column/row/span), `Attr.measure_overlay` (whether an `overlay` child counts towards the
overlay's size request), `Attr.page_title` (a `stack` page's switcher label),
`Attr.row_selectable` and `Attr.row_activatable` (a `list_box` row's), and
`Attr.tab_label` (a `notebook` page's tab text). Since M2 they are no longer silently
inert elsewhere: a placement attr on a container that does not read it is
`Invalid_argument` with the node path, naming the container that *does* read it — at
mount, at patch, and in `Bonsai_gtk_test`, all three from the same string. The check's
granularity is the parent's *kind*, not its slot, so an `Attr.measure_overlay` on an
`overlay`'s main child (rather than one of its `~overlays`) is still accepted and still
inert; tightening that means threading the slot name in, and is on the backlog.

Eighteen event attributes are *signals* of some widget class: M1's `on_clicked`,
`on_toggled`, `on_changed`, `on_activate`, `on_search_changed`, `on_value_changed`,
`on_expanded_changed`, `on_revealed`, `on_position_changed` and
`on_visible_child_changed`, plus M2's `on_row_activated`, `on_selected_rows_changed`,
`on_child_activated`, `on_selected_children_changed`, `on_page_changed`,
`on_selected_changed`, `on_day_selected` and `on_editing_changed`. Attaching one to a
widget that has no such signal raises at mount and at patch, rather than silently doing
nothing. The five *controller* attributes are the other kind and are legal everywhere —
see [Input](#input).

See §7 of the design doc for what M3 (chrome & popups) adds.

## Input

Clicks, keys and focus are not signals of any widget class, so they are not in the table
above. They are GTK *event controllers*, and this library attaches one on demand to
whatever node carries the attribute:

- `Attr.on_click ?button ?phase` attaches a `GtkGestureClick` and hands the handler a
  `Click_event.t` — the button that was pressed, the press count, the coordinates in the
  widget's own space, and the modifiers held. `?button:0` (the default) listens for all of
  them.
- `Attr.on_key_pressed ?phase` and `Attr.on_key_released ?phase` share one
  `GtkEventControllerKey`. The *pressed* handler is not an ordinary handler: it returns a
  `Key_response.t` (`Handled`, `Propagate`, or either carrying an effect) rather than an
  effect, because GTK asks a key press whether anything handled it and routes the event on
  that answer synchronously, on its own stack, long before the frame an effect would run
  in. A release cannot be consumed, so `on_key_released` is an ordinary handler.
- `Attr.on_focus_enter` and `Attr.on_focus_leave` share one `GtkEventControllerFocus`.
  They fire for focus moving into or out of the widget *or any of its children*, which is
  the useful sense for a composite like a `GtkSearchEntry` whose own `has_focus` is always
  false.

All five are legal on any node, and the controller exists exactly as long as the attribute
does: a frame that drops it removes the controller, and a later frame that adds it back
gets a fresh one. `?phase` defaults to `Phase.Bubble`, GTK's own; `Phase.Capture` is what a
window-wide Escape wants, because in bubble phase a child's controller added later sees the
key first. Giving `on_key_pressed` and `on_key_released` different phases is
`Invalid_argument` — one controller, one phase — and is rejected by the headless handle
too.

Keyvals are plain `int`s. `Keyval` names the seventeen worth naming (`Keyval.escape`,
`Keyval.tab`, `Keyval.page_down`, …) plus `Keyval.f n` for the function keys and
`Keyval.of_char 'w'`; anything else is a raw number. That is deliberate: it keeps a view
function free of ocgtk, and therefore headless-testable.

What none of this is tested against end to end is a real button press or a real keystroke —
see [Limitations](#limitations) before relying on it.

## Embedding

`Expert.embed` renders a Bonsai tree into a container an existing GTK application owns, so
a GTK4 codebase can be ported one screen at a time instead of all at once. Its root node
must *not* be a `Node.window` — the result is parented into something you already have —
and it parents nothing for you: `Embedded.widget` is a container `embed` owns and holds the
rendered tree, and you put that wherever your own container puts children. `Embedded.stop`
tears the tree down and empties that container but does not unparent it, and calling it
before you drop the host is a real obligation rather than tidiness: an embed dropped
without `stop` is permanently unreclaimable.

```ocaml
val embed
  :  ?time_source:Bonsai.Time_source.t
  -> ?optimize:bool
  -> ?target_frames_per_second:float
  -> (local_ Bonsai.graph -> Node.t Bonsai.t)
  -> Embedded.t
```

Everything else is a windowed tree's: the same attribute and placement checks at the same
points, the same `Invalid_argument` with the same paths, and the same "a frame that raised
stops this driver for good" rule. `src/embed.mli` is the contract, including why `widget`
is a wrapper rather than the rendered root (the root node's *kind* may change between
frames, and a caller holding the old root would be holding a widget nothing renders into
again).

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

There are nineteen actions, each naming a node by `test_id` and each failing loudly if
that node carries no matching handler:

| | |
|---|---|
| **M1** | `Click` (fires `Attr.on_clicked`), `Toggle` (a `toggle_button`/`check_button`/`switch`, fired with the negation of the `active` the node currently renders), `Set_text of test_id * string` and `Set_value of test_id * float` (the text the user typed / the value they moved to, passed through verbatim so the test can watch the *model* clamp or rewrite it), `Activate` (Enter pressed in a text widget) |
| **M2 signals** | `Search_changed`, `Set_expanded`, `Activate_row`, `Activate_child`, `Set_selection of test_id * Key.t list`, `Set_page`, `Set_selected of test_id * int`, `Select_day of test_id * Date.t`, `Set_editing` |
| **M2 controllers** | `Click_at of test_id * Click_event.t`, `Key_press of test_id * Key_event.t` (whose `Key_response.t` the handle prints, because that half of a key press is a value GTK reads synchronously and there is no GTK here), `Key_release`, `Focus_enter`, `Focus_leave` |

Since M2 the handle also *validates* the tree it is shown, from the same tables the runtime
uses: an event attr on a widget that cannot emit it (`Bonsai_gtk_vtree.Events`), a
placement attr on a container that does not read it (`Placement`), and two key attrs asking
for different phases (`Events.key_phase_rejection`) all raise here exactly as they do at
mount, with the same message. Every entry point that advances a handle checks — `show`,
`show_into_string`, `show_diff`, `store_view`, `recompute_view` and
`recompute_view_until_stable` — which is why `Bonsai_gtk_test.Handle` is a hand-written
signature rather than an alias for `Bonsai_test.Handle`. The guarantee is about *this*
module: the underlying type is `Bonsai_test.Handle.t`, so reaching for a `Bonsai_test.Handle`
entry point this signature does not re-export gets an unchecked handle.

`do_actions` dispatches every action in one call against a single view snapshot, so a second
click that depends on the state the first click just set needs a `recompute_view` between
them — see the doc comment on `Bonsai_gtk_test.create` for why.

Two gaps remain, and both are why a headless suite is not a substitute for running the
app. The first is *structural*, and the honest version of it is a table rather than a
sentence: the doc comment on `Bonsai_gtk_test.create` lists, row by row, everything the
runtime refuses against what this handle checks, which of it is decidable without GTK
(most of it), and the six places where a green headless suite does not mean the runtime
will hold the state. That table is the single copy; earlier versions of this paragraph
gave a shorter list and explained it with a reason — "needs the widget implementations or
a live tree" — that was false for every item on it. Since the M2 fix wave the root's kind,
a `Node.window` below the root and duplicate sibling keys *are* checked here; a `grid`
child with no `Attr.grid_cell`, a `~visible_child`/`~current_page` naming no page, two
stacks under one `~name` and a `stack_switcher` naming no stack are not, and could be.

The second is *routing*. Every action is delivered to one node, named by `test_id`; there
is no widget hierarchy for an event to travel through. So a `Click_at` on a card does not
also reach the container that would have handled it, a `Key_press` answering
`Key_response.Handled` does not stop a sibling from seeing the key, and
`Attr.on_key_pressed`'s `~phase` — which decides only who sees a key *first* — has no
effect here at all. What a test can show is that a handler made the right decision and what
that decision did to the model. See [Limitations](#limitations).

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

The consequence a downstream packager should know: **neither per-package `@runtest` runs
both directories.** `dune build -p bonsai_gtk @runtest` masks `test/handle/`, so the sweeps
that guarantee "a kind added to `Kind.t` fails until someone puts a node of it in the
gallery", the same for `Attr.Name.t`, and "every event attr has an action" do *not* run when
`bonsai_gtk` is installed with tests — even though `Kind.t` and `Attr.Name.t` are
`bonsai_gtk`'s own types. The mirror holds too: `-p bonsai_gtk_test @runtest` masks `test/`,
so the two shared tables (`test/test_events.ml`, `test/test_placement.ml`) that the handle
depends on are unchecked when the handle package is tested. Both run under a bare
`dune runtest` and under `scripts/ci.sh`. Moving the vtree-only sweeps into `test/` would
close half of it, and was looked at in the M2 fix wave: they read `gallery_tree`, which the
handle-based lifecycle sweep in the same file also reads, so it is a rewrite rather than a
file move and was left alone.

See `docs/superpowers/specs/2026-08-28-bonsai-gtk-design.md` for the design.

## ocgtk fork

`bonsai_gtk` pins a commit on a fork of [`ocgtk`](https://github.com/chris-armstrong/ocgtk)
that carries GC-safety and ownership fixes upstream doesn't have yet (the signal-closure
marshaller crash alone is load-bearing for a library whose whole job is connecting
signals). M2 added a second round: every transfer-container `GList`/`GSList` return now
reference-sinks its elements, non-`GInitiallyUnowned` constructors no longer over-ref their
result, three nullable string bindings take and return `string option`, and a GObject
handler reached from OCaml's finaliser no longer re-enters the runtime from the collector.
See `docs/upstream/README.md` for the fork, the fixes, and their upstreaming status, and
`docs/m2-backlog.md` for what the fork still owes.

## Limitations

M2 covers the widgets listed under [Widgets](#widgets) and the input attributes under
[Input](#input); anything else is a `Node.native` case. What is deliberately still out:

### The input path, and the one part of it still untested

- **What remains uncovered is a real display.** `test/live/live_input.ml` runs under `xvfb`
  with no window manager and no compositor, so the X11 input path is exercised and
  Wayland's (`gdk_wayland`) is not. That residual is on the backlog. Everything below it is
  what *is* covered, and is here because this section is where a reader comes looking for
  the gap.

- **A real click and a real keystroke are delivered by the X server, not by the binding.**
  The pinned ocgtk binding can synthesise neither: there is no `GdkEvent` constructor for
  any event subtype, `Gobject.Signal.emit_by_name` takes no arguments, and no `gtk_test_*`
  entry point is bound. So the plumbing and the handler are tested from either side — that
  `Attr.on_click` attaches a `GtkGestureClick` with the button and phase it asked for, that
  the key attrs attach one shared `GtkEventControllerKey` carrying the phase read back off
  the live controller, that dropping an attr empties one slot and removes the controller
  (`test/live/live_controllers.ml`, which prints `armed=` on every line for exactly this
  reason); and that a middle click with Shift reaches the application's closure with the
  right `Click_event.t`, and that a key handler consumes Escape and lets `x` through
  (`test/handle/test_handle.ml`, headlessly) — and GTK's routing *in between* is tested by
  driving the X server the live suite already runs on. `test/live/live_input.ml` is both the
  application and the driver: it presents a small tree, computes its own target coordinates
  from the widget geometry, and has `xdotool` issue XTEST button and key events, which the
  server delivers to it as ordinary input. Its golden covers buttons 1/2/3 reported as
  themselves, `n_press` 2 on a double click, widget-local coordinates matching the point the
  click was aimed at, `ctrl` carried through a click, a printable key propagating past a
  `Capture`-phase handler into the entry's text, focus enter/leave on a click and on Tab,
  and — as the check that the coordinates are real — a click 10 px outside the target
  moving nothing. Propagation is a matched pair rather than a bare negative: F1 propagates
  out of the capture handler and *does* reach the entry's own bubble-phase controller,
  Escape is `Handled` in the capture phase and does not, and those two golden lines differ
  in exactly that. There are no sleeps and no screenshots in it: it pumps its own main
  loop until the handler's counter moves. Focus was covered end to end before this too —
  `Widget.grab_focus` on a presented window really drives `GtkEventControllerFocus`.

### Input

- **`Attr.on_click`'s gesture does not claim the event sequence**, so a click also reaches
  whatever else would have handled it. That is what lets a card carry a middle-click
  handler without breaking its list box's click-to-select — but an application that wants
  to *consume* a click has no way to say so in M2.
- **`Attr.on_focus_enter`/`on_focus_leave` are events, not a `contains_focus` query.** An
  app that needs the bit ("is the focus anywhere in this panel right now?") keeps it in its
  own model, fed by the two attrs. They also take no `?phase`, unlike the click and key
  attrs; the focus controller stays in GTK's default bubble phase.
- **`Keyval` is a curated list**, not a table of every X keysym: seventeen names, plus
  `Keyval.f` and `Keyval.of_char`. Anything else is a raw `int`, which works and reads
  badly.

### Widgets

- **`ListBox`/`FlowBox` sorting, filtering and header functions are unreachable.** ocgtk
  binds none of the callback-taking methods (`set_sort_func`, `set_filter_func`,
  `set_header_func`) — the generator emits no GIR-callback-taking method at all — so sort
  and filter in the model, and render a header as an ordinary row carrying
  `Attr.row_selectable false` and `Attr.row_activatable false`.
- **`TextView` does not expose the cursor position**, and its controlled write preserves
  the caret as a *character offset*: exact for a rewrite that does not change the text's
  length before the caret, approximate for one that does (an autocompleter inserting six
  characters at the start leaves the caret six characters early). `notify::cursor-position`
  is the hook for an app that wants to own the caret; it is on the backlog.
- **Text GTK cannot hold: two rules across the five text widgets.** Where a write *is*
  refused it is refused *before* it happens — the widget keeps what it had, the refusal is
  remembered so the frames after it cost a pointer comparison, and it is reported once per
  distinct text through the patcher's channel. Unlike the two states above, no later frame
  makes the value valid, so the widget and the model stay diverged until the model offers
  text GTK will take.
  - **Every `GtkEditable` widget refuses a NUL and nothing else** — `Entry`,
    `PasswordEntry`, `SearchEntry` and `EditableLabel`, from one place
    (`W_entry.set_text_if_needed`), because they all write their text through it.
    `gtk_editable_set_text` takes a NUL-terminated string, so GTK would store the prefix
    silently and the widget would then be rewritten on every idle frame for the life of the
    tree; on a `SearchEntry` each of those writes re-armed the debounce, so
    `Attr.on_search_changed` never fired at all. Invalid UTF-8 is written rather than
    refused, deliberately: a `GtkEditable` stores the bytes and reads them back unchanged
    (measured — `"caf\xe9 latte"` round-trips), so there is nothing to refuse and the
    controlled comparison settles on the first frame.
  - **`TextView` refuses that and invalid UTF-8 too**, because a `GtkTextBuffer` empties
    itself and *then* declines the insert. Its cached copy of the buffer text is left
    untouched along with the buffer.

  **While a write is parked like that, the prop is not being enforced** — for all five text
  widgets, and for `Calendar` and `DropDown`, which refuse a date and an index on the same
  machinery. The remembered refusal is consulted *before* the widget is read, which is what
  makes a parked frame cost a pointer comparison; the consequence is that whatever the user
  does to the widget meanwhile is left standing rather than snapped back. That is the honest
  behaviour rather than an oversight — the model asked for a state the widget cannot hold, so
  there is nothing to snap back *to* — and the change attr still reports what the user did, so
  a model that wants to take it can. Control resumes on the first frame the model offers
  something the widget will take. `Node.drop_down`'s doc states it at length; the same
  paragraph is true of the others. One widget is half-enforced and says so: an
  `EditableLabel` parked on a text still has its `~editing` enforced, because the two
  decisions are independent.
- **`Calendar` has no date range and no "no date selected"** — `~date` is always a real
  `Core.Date.t`. GTK's own year range is 1–9999, so a `Date.t` in year 0 is refused,
  reported once, and written on the first later frame that offers a date GTK will hold.
- **`EditableLabel` commits on leaving edit mode; there is no discard.** Rendering
  `~editing:false` calls `stop_editing ~commit:true`, because the edit already reached the
  model keystroke by keystroke through `Attr.on_changed` and a model that wanted to reject
  it has already done so in `~text`.
- **A `DropDown`'s `~selected` past the end of `~items` is not an error.** The items and
  the index come from different Bonsai state in any real view, so a stale index is a state
  a correct model passes *through*: it is inert while it names nothing, applied on the
  frame the list grows to reach it, and reported once through the patcher's channel so a
  permanently wrong one is not silent. Only `~selected < -1` raises.
- **A `SearchEntry`'s `on_search_changed` filters the library's own writes.** GTK arms the
  debounce from *any* text change, including a controlled write, so without the filter a
  model that normalises input would hear its own write back as a search the user never
  performed. The widget records what the library last wrote and declines the next emission
  if the text still equals it — which means the record is consumed either way and cannot
  suppress more than the one signal the write armed, with one exception: a write that
  *empties* the box makes GTK emit `search-changed` synchronously inside the patch, where
  the emission is dropped before it can consume the record, so a `""` record survives to
  meet a later `""`. It is on the backlog.
- **No radio groups.** `CheckButton.set_group` *is* bound, but GTK's grouping is a mutable
  pointer from one live widget to another rather than a prop of either, which is not a
  thing a declarative tree can express: `Node.check_button` therefore exposes no `~group`.
  Model the exclusive choice in Bonsai state and render the `active` flags from it — which
  is the better shape anyway, since the model then holds the choice rather than inferring
  it from three widgets.
- **Per-widget gaps**, each a `Node.native` case and each named in its constructor's doc
  comment: no `Scale` marks, no `ProgressBar.pulse`, no `Entry` icons, no
  `SearchEntry.set_key_capture_widget`, no `Frame.set_label_widget`, no `TextView` tags or
  marks, no `LevelBar` offsets.
- **`Paned`'s position is uncontrolled** — writing it every frame would fight the drag
  handle. `Attr.on_position_changed` reports where the user left it.

### Not bound yet

- `HeaderBar`, `ActionBar`, `Popover`, `MenuButton` + `Node.menu`, alert/file dialogs,
  multi-window (`Node.windows`) and `Attr.shortcut` are M3. **One window per app until
  then.**
- **Out of scope until a follow-up design.** `ListView`/`ColumnView`/`GridView` (ocgtk
  generates no `SignalListItemFactory` signals, so they can't be populated without new C
  stubs); custom Cairo drawing (`DrawingArea.set_draw_func` is unbound in ocgtk); drag and
  drop.

### Structure and lifecycle

- **A `Node` constructor's `Invalid_argument` costs the whole application, not the widget.**
  Constructors run inside the Bonsai computation, so the exception comes out of
  `Driver.frame`, which marks the driver broken, abandons the pending fixups and re-raises:
  every later frame is a no-op and the window never repaints again. The checks therefore
  follow one rule — *reject only what no later frame could make valid* — and a state a
  correct model passes through (a stale index, a key whose child has not arrived) is inert,
  applied on the frame it becomes meaningful, and reported once through the patcher's
  channel instead. `vtree/node.mli` opens with the full statement.
- **Some structural mistakes are caught only at mount** — a `grid` child with no
  `Attr.grid_cell`, a `~visible_child`/`~current_page` naming no child, two `stack`s under
  one name, a `stack_switcher` naming a stack that does not exist. All are
  `Invalid_argument` carrying the node path, raised on the frame that builds or patches
  that node, and none of them stops a headless test — though all of them could, since each
  is decidable from `bonsai_gtk.vtree` alone. What *is* checked headlessly: event attrs,
  placement attrs and mismatched key phases (since M2), and the root's kind, a
  `Node.window` below the root and duplicate sibling keys (since the M2 fix wave). A
  `list_box`/`flow_box`/`notebook`/`stack` child with no key is rejected earlier still, by
  the constructor, so it stops a headless test too. The row-by-row version is the table on
  `Bonsai_gtk_test.create`; see [Headless testing](#headless-testing).
- **`Stack`, `Grid` and `Overlay` children are never reordered.** GTK exposes no reorder API
  for them, so their `list_ops.move` is `None` and `Reconcile.diff` emits no `Move` at all
  rather than emitting one that is ignored. Keys still preserve identity, so state is not
  lost — but if the order is meaningful, change the placement (`Attr.grid_cell`) or the
  keys. Changing a `Grid` child's cell re-attaches it, which also moves it to the end of
  GTK's child list; the cell is the placement, so nothing moves on screen. `Notebook` is
  the exception and does reorder in place: it has `gtk_notebook_reorder_child`.
- **`Expert.embed` hands back a wrapper, not the rendered root.** The root node's *kind* may
  change between frames, so a caller holding the rendered root would afterwards be holding a
  widget nothing renders into again — silently. The wrapper is a layout-transparent
  `GtkOverlay` that will show up in a `Live_tree` dump and in GTK Inspector. `Embedded.stop`
  empties it but does not unparent it.
- **`Bonsai_gtk_test.Action.t` is an unsealed public variant** with nineteen constructors,
  so every action a later milestone adds is a breaking change for a downstream exhaustive
  match. So are `Key_response.t`, `Selection_mode.t` and the other small enums. Sealing is
  on the backlog (`docs/m2-backlog.md`). `Attr.t` no longer is: its constructors moved to
  `Attr.Private` and `Attr.t` is a private abbreviation of it, so an application can
  neither build one from a raw constructor nor match on one without writing
  `(a :> Attr.Private.t)` — which is supported, carries no stability promise, and is
  where a milestone's new constructors will land. Build attrs with `Attr.css_class` and
  friends. `Attr.Name.t` stays a concrete variant, deliberately: `Attr_apply.unset`'s
  exhaustive match over it is what makes "unset restores the creation-time default"
  impossible to forget.
- **Every frame renders**, including frames on which Bonsai hands back the physically
  identical root — that is what puts a widget back after the model declines the user's
  edit. Such a frame no longer walks the whole shadow tree: since M2 it runs
  `Patcher.reassert_only`, which is the re-assert and fixup passes and nothing else,
  because with the node physically identical there is nothing for `Attrs.diff` to find and
  nothing for `Kind.equal_props` to admit.

`docs/m2-backlog.md` is the full list of what M2 leaves behind, with the review each item
came from. See §7 of the design doc for the widget catalogue and the milestone plan (M3
chrome & popups).
