# bonsai_gtk

Build GTK4 desktop applications with [Bonsai](https://github.com/janestreet/bonsai), in the
spirit of `bonsai_web` and `bonsai_term`. An app is a pure function
`local_ Bonsai.graph -> Node.t Bonsai.t`; the library owns the GTK main loop, turns GTK
signals into Bonsai events, and keeps a live GTK widget tree in sync with the declarative
`Node.t` the app computes.

Status: pre-alpha (M3) — 42 `Node.*` constructors covering displays, controls, text
entry, layout, stack-based navigation, the three keyed containers, and the M3 chrome:
header/action bars, menu buttons over real GMenu/GAction routing, popovers, and
multi-window trees (see [Widgets](#widgets)); seven event-controller attributes over
four controller families — clicks that can claim, keys, focus with phases, and keyboard
shortcuts (see [Input](#input)); timing, clipboard, window and dialog [Effects](#effects);
display-wide and per-widget [CSS](#css); `Expert.embed`, for rendering a Bonsai tree into
a container an existing GTK application owns (see [Embedding](#embedding)); the `Native`
escape hatch, the runtime loop, and headless testing. See [Limitations](#limitations)
below — including the one behaviour change for M2 apps: **the window close button is
vetoed unless the model handles it**.

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
    ~attrs:[ Attr.on_close_request Effect.quit ]
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
looks like on screen; its *Chrome* page holds the M3 bars, menus and the about dialog,
and its *Input* page exercises the click/key/focus attrs against a real pointer and
keyboard. `examples/chrome.ml` is the M3 counter — the smallest program using every
headline M3 feature at once: a `Node.windows` tree, a header-bar menu over one
`Action_spec` list that also serves two keyboard chords, an alert dialog whose answer
binds back into the model, and a second window the model opens and
`Effect.Window.present` raises.

## Libraries

- **`bonsai_gtk.vtree`** (`vtree/`) — the virtual widget tree (`Node`, `Attr`, `Key`,
  `Align`, `Orientation`) and the pure keyed-list diff (`Reconcile`) it patches with.
  Depends on nothing GTK-specific, so it links into `ppx_expect` test executables.
- **`bonsai_gtk`** (`src/`) — the GTK4 runtime: `start` runs an app as a `GtkApplication`
  and keeps a live widget tree in sync with the `Node.t` it computes each frame. Re-exports
  `vtree`'s modules plus `Widget` (the live GTK widget type), `Native` (the escape hatch for
  widgets this library has no `Node` constructor for), `Effect` (`Ui_effect` plus `quit`,
  the timing/clipboard/window effects and the dialogs — see [Effects](#effects)), and
  `Expert.Driver` for callers that want to drive frames by hand, plus `Expert.embed`
  for rendering into a container the caller owns ([Embedding](#embedding)).
- **`bonsai_gtk_test`** (`test_lib/`) — a headless test handle built on `bonsai_gtk.vtree`
  only (no GTK, no display needed): `Bonsai_test.Handle` over the `Node.t` sexp tree, with
  twenty-nine actions dispatched by `test_id` (see [Headless testing](#headless-testing)).

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
| **Chrome** | `header_bar` (a *widget* title slot plus keyed `start`/`end` packs — GTK 4 has no title-string setter on the bar), `action_bar` (`center` slot, keyed packs, plain `revealed`), `menu_button` with either `~menu` (a pure-data `Menu.t` whose items name actions an `Attr.actions` declares — display accels included) or `~popover` (the popover's one legal position; controlled `~open_`, `Attr.on_closed`) |
| **Window** | `window` (`~title`, `~default_size`, `~transient_for`/`~modal`/`~resizable`, `Attr.on_close_request` — see the migration note under [Limitations](#limitations)), `windows` (a virtual root of keyed windows: many toplevels, one tree; rendering `windows []` exits the app) |
| **Escape hatch** | `Node.native` for anything else, plus `Native.Picture` for a widget fed from a `GdkPaintable` |

That is all 42 `Node.*` constructors; `vtree/node.mli` is the reference, and each
constructor's doc comment names the properties it does *not* bind.
`test/handle/test_gallery_sweeps.ml` checks the claim against `Kind.Variants.descriptions`,
so a constructor added and never put in the gallery fails the suite rather than quietly
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
`opacity`, `focusable`/`can_focus`, `widget_name`, `cursor_name`, `test_id`, and since
M3 `css_provider` (a per-widget stylesheet — see [CSS](#css)), `autofocus` (a fire-once
focus grab at mount, at most one per frame per toplevel — the dialog-open pattern) and
`actions`/`shortcut` (see [Input](#input)). Dropping an attribute restores the value that
widget was created with, not a global default.

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

Twenty-one event attributes are *signals* of some widget class: M1's `on_clicked`,
`on_toggled`, `on_changed`, `on_activate`, `on_search_changed`, `on_value_changed`,
`on_expanded_changed`, `on_revealed`, `on_position_changed` and
`on_visible_child_changed`, M2's `on_row_activated`, `on_selected_rows_changed`,
`on_child_activated`, `on_selected_children_changed`, `on_page_changed`,
`on_selected_changed`, `on_day_selected` and `on_editing_changed`, and M3's
`on_cursor_moved` (a text view's caret), `on_closed` (a popover's dismissal) and
`on_close_request` (a window's close request — always vetoed; see
[Limitations](#limitations)). Attaching one to a widget that has no such signal raises at
mount and at patch, rather than silently doing nothing. The seven *controller*
attributes are the other kind and are legal everywhere — see [Input](#input).

See §7 of the design doc for the milestone history; `docs/m3-backlog.md` is what M3
leaves behind.

## Input

Clicks, keys and focus are not signals of any widget class, so they are not in the table
above. They are GTK *event controllers*, and this library attaches one on demand to
whatever node carries the attribute:

- `Attr.on_click ?button ?phase` attaches a `GtkGestureClick` and hands the handler a
  `Click_event.t` — the button that was pressed, the press count, the coordinates in the
  widget's own space, and the modifiers held. `?button:0` (the default) listens for all of
  them. The handler returns a `Click_response.t`: `Continue` lets the click also reach
  whatever else would have handled it (a card's handler beside its list box's
  click-to-select), `Claim` consumes the sequence on the spot (`Gesture.set_state
  \`CLAIMED`, on GTK's own stack), and either can carry an effect.
- `Attr.on_key_pressed ?phase` and `Attr.on_key_released ?phase` share one
  `GtkEventControllerKey`. The *pressed* handler is not an ordinary handler: it returns a
  `Key_response.t` (`Handled`, `Propagate`, or either carrying an effect) rather than an
  effect, because GTK asks a key press whether anything handled it and routes the event on
  that answer synchronously, on its own stack, long before the frame an effect would run
  in. A release cannot be consumed, so `on_key_released` is an ordinary handler.
- `Attr.on_focus_enter ?phase`, `Attr.on_focus_leave ?phase` and
  `Attr.on_contains_focus_changed` share one `GtkEventControllerFocus`. The first two
  fire on every hop of focus into or out of the widget or its children;
  `on_contains_focus_changed` is the coarse query — once when focus enters the subtree,
  once when it leaves — which is the bit an "is the focus anywhere in this panel?" model
  wants without bookkeeping.
- `Attr.shortcut ?phase ~trigger ~action ()` is the fourth family: a keyboard chord
  (`Trigger.create ~modifiers (Keyval.of_char 'k')`) that fires a **named action** an
  `Attr.actions` on the same node or an ancestor declares — GTK's own
  `ShortcutController → NamedAction → GAction` routing, which is also why a shortcut
  cannot hold a closure directly (the binding has no `GtkCallbackAction`; the named-action
  design turned out the better shape anyway — one `Action_spec` list serves the menu, the
  chord and the palette). Repeatable on one node; two shortcuts sharing a trigger but
  naming different actions on one node are rejected outright, and cross-node contention
  is deterministic. A chord whose action is disabled *falls through* to capture handlers
  and the focused widget (measured, goldened) — the shape a "text input active" gate
  needs.

All seven are legal on any node, and each family's controller exists exactly as long as
its attrs do: a frame that drops the last one removes the controller, and a later frame
that adds one back gets a fresh one. `?phase` defaults to `Phase.Bubble`, GTK's own;
`Phase.Capture` is what a window-wide Escape or chord wants, because in bubble phase a
child's controller sees the event first. A family's attrs asking for two different
phases on one node is `Invalid_argument` — one controller, one phase, the same rule for
all four families (`Events.family_phase_rejection`) — and is rejected by the headless
handle too.

Keyvals are plain `int`s. `Keyval` names the couple of dozen worth naming
(`Keyval.escape`, `Keyval.tab`, the punctuation chords use, …) plus `Keyval.f n` for the
function keys and `Keyval.of_char 'w'`; anything else is a raw number. That is
deliberate: it keeps a view function free of ocgtk, and therefore headless-testable.

Since M3 all of this *is* tested against a real button press and a real keystroke —
`test/live/live_input.ml` drives the X server with XTEST, chords and menu activations
included — on the one input path a WM-less Xvfb has; see [Limitations](#limitations) for
the real-display residual.

## Effects

`Bonsai_gtk.Effect` is `Ui_effect` plus the GTK-shaped effects (each documents what a
perform outside a running app does — always log-and-resolve, never a raise):

- `quit` ends the application `start` is running.
- `after span` and `on_idle` resolve on the GLib main loop (one-shot per perform) and
  then request the frame that shows what their continuation did. The *cancellable* timer
  stays app-side: gate what the continuation does on model state.
- `Clipboard.set_text` writes the display's clipboard. There is no `get_text`: the
  binding has no synchronous read and no bound async one (a documented omission).
- `Window.present key` raises the window keyed `key` in the root `Node.windows` list —
  the one window operation with no prop equivalent (`close` and `set_title` are the
  node's existence and `~title`; an effect duplicating a prop would be a second writer
  fighting the runtime).
- `Alert_dialog.show ?detail ?cancel ~buttons message` shows a modal alert and resolves
  with the index of the button pressed; every dismissal (Escape, the close button)
  resolves `?cancel` (default 0), so a `let%bind` over it is total. It is a real
  `GtkDialog` under the hood — the binding cannot construct `GtkAlertDialog`.
- `File_dialog.open_file` / `save_file ?initial_name` / `select_folder` resolve
  `Some path` on accept and `None` on any dismissal, on `GtkFileChooserNative`
  (`GtkFileDialog` cannot be launched in the binding). No initial-folder argument:
  `Gio.File` has no constructor.

Shown dialogs are held by the runtime until answered, so the effect value can be
dropped freely, and two alerts at once are two dialogs.

## CSS

`start ?global_css` (and `Expert.embed ?global_css`) installs one application-wide
stylesheet on the default display. Dark-mode `@media (prefers-color-scheme: dark)`
blocks work: the runtime mirrors the desktop's color scheme onto the provider and
follows changes — GTK 4.20+ evaluates that query per provider, and an unmirrored
provider would never match it. `Attr.css_provider` styles one widget (and its subtree):
the runtime owns the provider for the widget's life, a changed string restyles in
place, dropping the attr removes it. Two caveats worth reading before use: an *invalid*
stylesheet never raises but leaves the provider empty (GTK clears before parsing — the
widget goes un-styled, it does not keep the previous sheet), and a per-widget provider's
media queries evaluate against its own unset preference — effectively always light — so
scheme-dependent styling belongs in `?global_css`.

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
  -> ?global_css:string
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

There are twenty-nine actions, each naming a node by `test_id` (or, for `Close_request`,
a window by its key) and each failing loudly if that node carries no matching handler:

| | |
|---|---|
| **M1** | `Click` (fires `Attr.on_clicked`), `Toggle` (a `toggle_button`/`check_button`/`switch`, fired with the negation of the `active` the node currently renders), `Set_text of test_id * string` and `Set_value of test_id * float` (the text the user typed / the value they moved to, passed through verbatim so the test can watch the *model* clamp or rewrite it), `Activate` (Enter pressed in a text widget) |
| **M2 signals** | `Search_changed`, `Set_expanded`, `Set_revealed`, `Set_position`, `Set_visible_child`, `Activate_row`, `Activate_child`, `Set_selection of test_id * Key.t list`, `Set_page`, `Set_selected of test_id * int`, `Select_day of test_id * Date.t`, `Set_editing` |
| **M2 controllers** | `Click_at of test_id * Click_event.t`, `Key_press of test_id * Key_event.t` (whose `Key_response.t` the handle prints, because that half of a key press is a value GTK reads synchronously and there is no GTK here), `Key_release`, `Focus_enter`, `Focus_leave` |
| **M3** | `Focus_contains`, `Move_cursor`, `Open_popover` (an honest no-op: opening emits no signal this library exposes), `Close_popover`, `Activate_action of test_id * reference` (`"scope.name"`, or `::target` for a radio), `Fire_shortcut of test_id * Trigger.t` (resolved against the node's shortcuts and the ancestor action scopes, in the same order the live controller uses), `Close_request of Key.t` (the close veto in headless form — the handler fires, and the window stands until the model drops its node) |

Since M2 the handle also *validates* the tree it is shown, from the same tables the runtime
uses — and M3 widened both sides in step: an event attr on a widget that cannot emit it
(`Bonsai_gtk_vtree.Events`), a placement attr on a container that does not read it
(`Placement`), a controller family's attrs asking for different phases
(`Events.family_phase_rejection`, over all four families), a menu item or shortcut whose
action reference resolves to no `Attr.actions` in scope (`Action_resolution`, the same
walk the runtime runs per frame), same-trigger shortcut conflicts, the windows-root
shape (children all keyed windows; `windows` only at the root), a `~transient_for`
naming no sibling window, popover placement, and two autofocus grabs in one frame per
toplevel — all raise here exactly as they do at mount, with the same message. Every entry point that advances a handle checks — `show`,
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
`docs/m3-backlog.md` (the "ocgtk fork" section, with the round-3 candidate list) for what
the fork still owes.

## Limitations

M3 covers the widgets listed under [Widgets](#widgets), the input attributes under
[Input](#input), the [Effects](#effects) and [CSS](#css); anything else is a
`Node.native` case. What is deliberately still out — starting with the one thing an M2
app must change:

### Migration note: the close button is vetoed (M2 → M3)

Since M3 the runtime answers **every** window close request "handled": the X button (and
Alt+F4, and `Window.close`) destroys nothing — a window closes when, and only when, the
model stops rendering its node, and `Attr.on_close_request` is how the model hears the
request. **An M2 app that adds no handler has an inert X button** (the request is
swallowed and reported once per window on stderr). For a one-window app the migration is
one attr — `Attr.on_close_request Effect.quit`, as `examples/counter.ml` now shows; a
multi-window app removes the keyed window from its `Node.windows` list instead. The
alternative — letting GTK destroy a window behind the runtime's back — leaves the
runtime patching widgets that no longer exist, which is why the veto is unconditional
rather than a default.

The one state the veto does not govern is a **broken driver** (a frame raised): there is
no model left to hear the request, so instead of leaving frozen windows that refuse to
close, `start` ends the run itself — one error on stderr, the windows torn down, and
`start` returns status 2. "Structure and lifecycle" below has the full story.

### The input path, and the parts of it still untested

- **What remains uncovered is a real display.** The live suites run under `xvfb` with no
  window manager and no compositor, so the X11 input path is exercised and Wayland's
  (`gdk_wayland`) is not — and M3 widened what rides on that residual: popover opening,
  menu item activation, shortcut chords and dialog dismissal all inherit it.
- **Two inputs are unreachable even on that path.** A WM-less Xvfb never gives a popup
  surface keyboard focus, so no keyboard path reaches an open menu (Down+Return on a
  `GtkPopoverMenu`: measured, sensitive item, no activation — menu activation is proven
  by pointer); and choosing a file in the chooser fallback needs a click inside
  GTK-internal furniture whose geometry nothing can name, so only the Escape/dismissal
  half of the file dialogs is driven. Both run only by hand on a real display.
  Everything below is what *is* covered.

- **A real click and a real keystroke are delivered by the X server, not by the binding.**
  The pinned ocgtk binding can synthesise neither: there is no `GdkEvent` constructor for
  any event subtype, `Gobject.Signal.emit_by_name` takes no arguments, and no `gtk_test_*`
  entry point is bound. So the plumbing and the handler are tested from either side — that
  `Attr.on_click` attaches a `GtkGestureClick` with the button and phase it asked for, that
  the key attrs attach one shared `GtkEventControllerKey` carrying the phase read back off
  the live controller, that dropping an attr empties one slot and removes the controller
  (`test/live/live_controllers_key.ml` and its `_click`/`_focus` siblings, which print
  `armed=` on every line for exactly this reason); and that a middle click with Shift reaches the application's closure with the
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

- **No focus model — the largest named gap.** Who holds focus is not state this library
  can express: there is no `set_focus`-as-prop, no focus-follows-model, no
  `~default_widget`. `Attr.autofocus` is the deliberate interim floor (a fire-once grab
  when a window or panel appears — the dialog-open pattern) and the focus attrs report
  what happened; everything beyond that stays app-side until the focus design is done
  (`docs/m3-backlog.md`, "Do first in M4").
- **Shortcuts are untargeted.** `Attr.shortcut` rejects `"::target"` and a shortcut
  resolving to a radio action: activation goes through a parameterless `GtkNamedAction`.
  Targeted shortcuts are *feasible* (the binding has `Shortcut.set_arguments`) and
  deliberately unshipped; the backlog names shipping's exact removals.
- **Menu accels are display, not installation.** `Menu.item ~accel` renders the chord in
  the menu row; it installs nothing. Install the binding with `Attr.shortcut` naming the
  same action — the separation stavekeeper's own menu code insists on ("the key handler
  stays the single source of key truth").
- **`Keyval` is a curated list**, not a table of every X keysym: a couple of dozen names
  plus `Keyval.f` and `Keyval.of_char`. Anything else is a raw `int`, which works and
  reads badly.

### Widgets

- **`ListBox`/`FlowBox` sorting, filtering and header functions are unreachable.** ocgtk
  binds none of the callback-taking methods (`set_sort_func`, `set_filter_func`,
  `set_header_func`) — the generator emits no GIR-callback-taking method at all — so sort
  and filter in the model, and render a header as an ordinary row carrying
  `Attr.row_selectable false` and `Attr.row_activatable false`.
- **`TextView`'s controlled write preserves the caret as a *character offset***: exact
  for a rewrite that does not change the text's length before the caret, approximate for
  one that does. Since M3 `Attr.on_cursor_moved` reports the caret, so a model that
  wants to own it can close that approximation itself.
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

- **No free-floating popover.** `Node.popover` ships only as a `menu_button`'s slot:
  anchoring one to an arbitrary node needs `Popover.set_pointing_to`, whose
  `GdkRectangle` the binding cannot construct (fork round 3), and a placement design of
  its own.
- **No clipboard read** (`Effect.Clipboard.get_text`): no synchronous read exists and
  the async one is unbound. `set_text` ships.
- **No menubar** (`Application.set_menubar` / `PopoverMenuBar`) — the menu story is the
  menu button's.
- **No file-dialog initial folder** — `Gio.File` has no constructor in the binding.
- **Out of scope until a follow-up design.** `ListView`/`ColumnView`/`GridView` (ocgtk
  generates no `SignalListItemFactory` signals, so they can't be populated without new C
  stubs); custom Cairo drawing (`DrawingArea.set_draw_func` is unbound in ocgtk); drag and
  drop.

### Structure and lifecycle

- **A `Node` constructor's `Invalid_argument` costs the whole application, not the widget.**
  Constructors run inside the Bonsai computation, so the exception comes out of
  `Driver.frame`, which marks the driver broken, abandons the pending fixups and re-raises:
  every later frame is a no-op. Under `start` the app then **quits** — one clear error on
  stderr, the windows torn down through the normal stop path, `start` returning status 2 —
  because a broken driver's windows could never close otherwise: the close-request veto
  answers every request and no handler's effect can reach a dead driver. Under
  `Expert.embed` the widgets stay (frozen at their last good state) and the embedder,
  which owns the main loop, hears the raise itself. The checks therefore
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
- **`Bonsai_gtk_test.Action.t` is an unsealed public variant** with twenty-nine constructors,
  so every action a later milestone adds is a breaking change for a downstream exhaustive
  match. So are `Key_response.t`, `Selection_mode.t` and the other small enums. Sealing is
  on the backlog (`docs/m3-backlog.md`). `Attr.t` no longer is: its constructors moved to
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

`docs/m3-backlog.md` is the full list of what M3 leaves behind, with the review each item
came from (`docs/m2-backlog.md` stays as the M2 record, closures struck). See §7 of the
design doc for the widget catalogue and the milestone history.
