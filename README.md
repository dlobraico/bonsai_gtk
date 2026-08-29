# bonsai_gtk

Build GTK4 desktop applications with [Bonsai](https://github.com/janestreet/bonsai), in the
spirit of `bonsai_web` and `bonsai_term`. An app is a pure function
`local_ Bonsai.graph -> Node.t Bonsai.t`; the library owns the GTK main loop, turns GTK
signals into Bonsai events, and keeps a live GTK widget tree in sync with the declarative
`Node.t` the app computes.

Status: pre-alpha (M0) — four widgets (`Label`, `Button`, `Box`, `Window`), the `Native`
escape hatch, the runtime loop, and headless testing. See [Limitations](#limitations)
below.

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
  `Click of test_id` as the one action so far.

## Headless testing

Apps that keep their view function in a `bonsai_gtk.vtree`-only module (the same rule
`bonsai_web` apps already follow) can be tested with `Bonsai_gtk_test`, no display required.
From `test/test_handle.ml`:

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

`do_actions` dispatches every action in one call against a single view snapshot, so a second
click that depends on the state the first click just set needs a `recompute_view` between
them — see the doc comment on `Bonsai_gtk_test.create` for why.

## Development

    nix develop                 # dev shell (GTK4 stack, opam, xvfb)
    ./scripts/setup-switch.sh   # once: creates ./_opam (OxCaml) and pins ocgtk
    dune build && dune runtest
    BONSAI_GTK_LIVE_TESTS=1 xvfb-run -a dune build @test/live/runtest  # live GTK tests
    ./scripts/ci.sh             # everything above, plus the ocgtk pin and the example smoke test

`dune runtest` alone only runs the pure and headless suites (`test/`, ocgtk-free); the live
tests under `test/live/` drive a real GTK display via `xvfb-run` and are opt-in through
`BONSAI_GTK_LIVE_TESTS=1`, which is what `scripts/ci.sh` sets.

See `docs/superpowers/specs/2026-08-28-bonsai-gtk-design.md` for the design.

## ocgtk fork

`bonsai_gtk` pins a commit on a fork of [`ocgtk`](https://github.com/chris-armstrong/ocgtk)
that carries GC-safety and ownership fixes upstream doesn't have yet (the signal-closure
marshaller crash alone is load-bearing for a library whose whole job is connecting
signals). See `docs/upstream/README.md` for the fork, the fixes, and their upstreaming
status.

## Limitations

M0 covers four widgets (`Label`, `Button`, `Box`, `Window`) plus the `Native` escape hatch
for anything else, a single window per app, no custom Cairo drawing
(`DrawingArea.set_draw_func` is unbound in ocgtk), and no `ListView`/`ColumnView`/`GridView`
(ocgtk generates no `SignalListItemFactory` signals, so they can't be populated without new
C stubs — out of scope until a follow-up design). See §7 of the design doc for the full
widget catalogue and milestone plan (M1 core & layout, M2 lists & text, M3 chrome &
popups).
