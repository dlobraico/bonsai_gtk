### Task 10: The gallery example, and a headless sweep over every M1 widget

Spec §10 lists `examples/` as growing per milestone (`counter, todo, gallery`). The gallery is not decoration: it is the only place every M1 widget is instantiated together, under the real runtime, with a real GTK theme — which catches the class of mistake no unit test does (a widget that mounts fine and lays out at zero height, a container whose child never becomes visible, a signal that fires at 60 Hz because a prop is written unconditionally).

**Files:**
- Create: `examples/gallery.ml`, `test/test_gallery.ml`
- Modify: `examples/dune`, `scripts/ci.sh`

- [ ] **Step 1: `examples/dune`**

```lisp
(executables
 (names counter gallery)
 (libraries core bonsai bonsai_gtk)
 (preprocess
  (pps ppx_jane bonsai.ppx_bonsai)))
```

- [ ] **Step 2: `examples/gallery.ml`**

Structure it as a `Node.stack` with a `Node.stack_switcher` above it — which exercises the two widgets that are hardest to get right — and one page per task group. Every control is wired to real state, because an unwired control proves nothing: the point is that clicking, typing and dragging move a model and the model moves the widgets back.

```ocaml
open! Core
open Bonsai_gtk
open Bonsai.Let_syntax

(* Page 1: the toggle family and the entries, all controlled by one record of state. *)
let controls (graph @ local) =
  let toggled, set_toggled = Bonsai.state false graph in
  let checked, set_checked = Bonsai.state true graph in
  let switched, set_switched = Bonsai.state false graph in
  let text, set_text = Bonsai.state "" graph in
  let search, set_search = Bonsai.state "" graph in
  let%arr toggled and set_toggled and checked and set_checked and switched and set_switched
  and text and set_text and search and set_search in
  Node.grid
    ~row_spacing:8
    ~column_spacing:12
    ~attrs:[ Attr.margin 12 ]
    [ Node.label ~attrs:[ Attr.grid_cell ~column:0 ~row:0 (); Attr.xalign 0. ] "Toggle"
    ; Node.toggle_button
        ~attrs:[ Attr.grid_cell ~column:1 ~row:0 (); Attr.on_toggled set_toggled ]
        ~label:(if toggled then "on" else "off")
        ~active:toggled
        ()
    ; Node.label ~attrs:[ Attr.grid_cell ~column:0 ~row:1 (); Attr.xalign 0. ] "Check"
    ; Node.check_button
        ~attrs:[ Attr.grid_cell ~column:1 ~row:1 (); Attr.on_toggled set_checked ]
        ~label:"agree"
        ~active:checked
        ()
    ; Node.label ~attrs:[ Attr.grid_cell ~column:0 ~row:2 (); Attr.xalign 0. ] "Switch"
    ; Node.switch
        ~attrs:
          [ Attr.grid_cell ~column:1 ~row:2 ()
          ; Attr.halign Start
          ; Attr.on_toggled set_switched
          ]
        ~active:switched
        ()
    ; Node.label ~attrs:[ Attr.grid_cell ~column:0 ~row:3 (); Attr.xalign 0. ] "Entry"
    ; Node.entry
        ~attrs:[ Attr.grid_cell ~column:1 ~row:3 (); Attr.hexpand true; Attr.on_changed set_text ]
        ~placeholder:"type here"
        ~text
        ()
    ; Node.label ~attrs:[ Attr.grid_cell ~column:0 ~row:4 (); Attr.xalign 0. ] "Password"
    ; Node.password_entry
        ~attrs:[ Attr.grid_cell ~column:1 ~row:4 (); Attr.hexpand true ]
        ~placeholder:"passphrase"
        ~text:""
        ()
    ; Node.label ~attrs:[ Attr.grid_cell ~column:0 ~row:5 (); Attr.xalign 0. ] "Search"
    ; Node.search_entry
        ~attrs:
          [ Attr.grid_cell ~column:1 ~row:5 ()
          ; Attr.hexpand true
          ; Attr.on_search_changed set_search
          ]
        ~text:search
        ()
    ; Node.label
        ~attrs:[ Attr.grid_cell ~column:0 ~row:6 ~width:2 (); Attr.xalign 0.; Attr.ellipsize End ]
        (sprintf "text=%S search=%S" text search)
    ]
;;

(* Page 2: numbers and feedback, where one value drives four widgets. *)
let numbers (graph @ local) =
  let value, set_value = Bonsai.state 40. graph in
  let%arr value and set_value in
  Node.box
    ~orientation:Vertical
    ~spacing:8
    ~attrs:[ Attr.margin 12 ]
    [ Node.scale
        ~attrs:[ Attr.on_value_changed set_value; Attr.hexpand true ]
        ~orientation:Horizontal
        ~min:0.
        ~max:100.
        ~value
        ()
    ; Node.spin_button
        ~attrs:[ Attr.on_value_changed set_value; Attr.halign Start ]
        ~min:0.
        ~max:100.
        ~value
        ()
    ; Node.progress_bar ~fraction:(value /. 100.) ~show_text:true ()
    ; Node.separator ~orientation:Horizontal
    ; Node.box
        ~orientation:Horizontal
        ~spacing:8
        [ Node.spinner ~spinning:Float.(value > 50.) ()
        ; Node.label (sprintf "spinning above 50 (value = %.0f)" value)
        ]
    ]
;;

(* Page 3: the containers, including the overlay-over-a-spacer trick that caps a
   picture's allocated size. *)
let layout (graph @ local) =
  let expanded, set_expanded = Bonsai.state false graph in
  let revealed, set_revealed = Bonsai.state true graph in
  let%arr expanded and set_expanded and revealed and set_revealed in
  Node.paned
    ~orientation:Horizontal
    ~position:220
    ~start:
      (Node.scrolled_window
         ~hpolicy:Never
         ~vpolicy:Automatic
         (Node.box
            ~orientation:Vertical
            ~spacing:8
            ~attrs:[ Attr.margin 12 ]
            [ Node.frame ~label:"Frame" (Node.label ~attrs:[ Attr.margin 8 ] "framed")
            ; Node.expander
                ~attrs:[ Attr.on_expanded_changed set_expanded ]
                ~label:"Expander"
                ~expanded
                (Node.label ~attrs:[ Attr.margin 8 ] "detail")
            ; Node.button
                ~attrs:[ Attr.on_clicked (set_revealed (not revealed)) ]
                ~label:(if revealed then "Hide" else "Show")
                ()
            ; Node.revealer
                ~transition:Slide_down
                ~reveal:revealed
                (Node.label ~attrs:[ Attr.margin 8 ] "revealed")
            ]))
    ~end_:
      (Node.center_box
         ~attrs:[ Attr.margin 12 ]
         ~start:(Node.label "start")
         ~center:
           (Node.overlay
              ~overlays:
                [ Node.image
                    ~attrs:[ Attr.measure_overlay false; Attr.halign Center; Attr.valign Center ]
                    ~pixel_size:48
                    (Icon_name "image-x-generic-symbolic")
                ]
              (Node.box
                 ~orientation:Vertical
                 ~attrs:[ Attr.width_request 150; Attr.height_request 194 ]
                 []))
         ~end_:(Node.label "end")
         ())
;;

let app (graph @ local) =
  let page, set_page = Bonsai.state "controls" graph in
  let controls = controls graph in
  let numbers = numbers graph in
  let layout = layout graph in
  let%arr page and set_page and controls and numbers and layout in
  Node.window
    ~title:"bonsai_gtk gallery"
    ~default_size:(900, 560)
    (Node.box
       ~orientation:Vertical
       [ Node.stack_switcher
           ~attrs:[ Attr.halign Center; Attr.margin 8 ]
           ~stack:"gallery"
           ()
       ; Node.stack
           ~name:"gallery"
           ~visible_child:page
           ~transition:Crossfade
           ~attrs:[ Attr.vexpand true; Attr.on_visible_child_changed set_page ]
           [ Node.box
               ~key:"controls"
               ~attrs:[ Attr.page_title "Controls" ]
               ~orientation:Vertical
               [ controls ]
           ; Node.box
               ~key:"numbers"
               ~attrs:[ Attr.page_title "Numbers" ]
               ~orientation:Vertical
               [ numbers ]
           ; Node.box
               ~key:"layout"
               ~attrs:[ Attr.page_title "Layout" ]
               ~orientation:Vertical
               [ layout ]
           ]
       ])
;;

let () = exit (Bonsai_gtk.start ~application_id:"org.bonsai_gtk.examples.gallery" app)
```

The `stack_switcher` above the `stack` is deliberate: it is the layout that only works because the fixup pass resolves names after the whole tree exists (Task 9), so the example doubles as that feature's demonstration.

- [ ] **Step 3: `test/test_gallery.ml` — the headless sweep**

The gallery links ocgtk, so it cannot be expect-tested. Reproduce the *view* half of it — the part that is pure `bonsai_gtk.vtree` — as a component in `test/` and snapshot it, which is both a coverage check that every M1 constructor still builds a legal node and a worked example of the rule the README states ("keep your view functions in a vtree-only library and they are testable").

```ocaml
open! Core
open Bonsai_gtk_vtree
open Bonsai.Let_syntax

(* Every M1 node constructor, once, in one tree. Its value is coverage: a constructor
   whose defaults change, or a children shape that stops being legal, shows up here as a
   diff rather than as a runtime failure in somebody's app. *)
let every_widget (graph @ local) =
  let n, set_n = Bonsai.state 0 graph in
  let%arr n and set_n in
  Node.window
    ~title:"every widget"
    (Node.stack
       ~name:"all"
       ~visible_child:"a"
       [ Node.box
           ~key:"a"
           ~attrs:[ Attr.page_title "A" ]
           ~orientation:Vertical
           [ Node.label ~xalign:0. ~ellipsize:End ~max_width_chars:14 "label"
           ; Node.button ~attrs:[ Attr.on_clicked (set_n (n + 1)) ] ~label:"button" ()
           ; Node.button ~icon_name:"list-add-symbolic" ~has_frame:false ()
           ; Node.toggle_button ~label:"toggle" ~active:(n % 2 = 0) ()
           ; Node.check_button ~label:"check" ~active:false ()
           ; Node.switch ~active:true ()
           ; Node.entry ~placeholder:"entry" ~text:"" ()
           ; Node.password_entry ~text:"" ()
           ; Node.search_entry ~text:"" ()
           ; Node.spin_button ~min:0. ~max:10. ~value:(Float.of_int n) ()
           ; Node.scale ~orientation:Horizontal ~min:0. ~max:10. ~value:0. ()
           ; Node.progress_bar ~fraction:0.5 ()
           ; Node.spinner ~spinning:true ()
           ; Node.image (Icon_name "list-add-symbolic")
           ; Node.picture Empty
           ; Node.separator ~orientation:Horizontal
           ]
       ; Node.box
           ~key:"b"
           ~attrs:[ Attr.page_title "B" ]
           ~orientation:Vertical
           [ Node.scrolled_window (Node.label "scrolled")
           ; Node.frame ~label:"frame" (Node.label "framed")
           ; Node.expander ~label:"expander" ~expanded:false (Node.label "detail")
           ; Node.revealer ~reveal:true (Node.label "revealed")
           ; Node.grid [ Node.label ~attrs:[ Attr.grid_cell ~column:0 ~row:0 () ] "cell" ]
           ; Node.center_box ~start:(Node.label "s") ~end_:(Node.label "e") ()
           ; Node.paned ~orientation:Vertical ~start:(Node.label "t") ~end_:(Node.label "b")
           ; Node.overlay ~overlays:[ Node.label "over" ] (Node.label "under")
           ; Node.stack_switcher ~stack:"all" ()
           ; Node.stack_sidebar ~stack:"all" ()
           ]
       ])
;;

let%expect_test "every M1 widget builds a legal node" =
  let handle = Bonsai_gtk_test.create every_widget in
  Bonsai_gtk_test.Handle.show handle;
  [%expect {| |}]
;;
```

- [ ] **Step 4: `scripts/ci.sh`** — smoke the gallery beside the counter

Factor the existing smoke block into a loop, so a third example costs one word:

```bash
echo "== example smoke"
for ex in counter gallery; do
  set +e
  xvfb-run -a timeout -k 2 3 dune exec "examples/$ex.exe"
  code=$?
  set -e
  # 124 is timeout's "still running when time ran out", which is what a GUI that
  # came up and stayed up looks like. Anything else means it fell over.
  [ "$code" = 124 ] || { echo "$ex example exited with $code"; exit 1; }
done
```
Also add `@examples/fmt` — it is already in the `dune build @...` line; confirm rather than assume.

- [ ] **Step 5: Run it for real, and look at it**

```
dune build @test/runtest && dune promote
xvfb-run -a timeout -k 2 5 dune exec examples/gallery.exe
```
Under Xvfb there is nothing to see, so also run it on a real display if one is available (`dune exec examples/gallery.exe`) and click through all three pages. Things this catches that nothing else does: a page that renders at zero height (a missing `vexpand`), a switcher with no buttons (the fixup never ran), a scale that jumps back to its old value when released (the controlled rule applied against the node rather than the widget), a spinner that never spins, an overlay that sizes to its image rather than its spacer.

Fix what it shows *in the widget impl*, and add a live-test line for whatever was wrong — a bug the gallery can find and the suite cannot is a hole in the suite.

- [ ] **Step 6: `./scripts/ci.sh`, then commit**

```bash
dune fmt 2>/dev/null; git add examples test scripts
GIT_EDITOR=true git commit -F - <<'MSG'
Gallery example, and a headless sweep over every M1 widget

The gallery is the only place every M1 widget is instantiated together under
the real runtime and a real theme, which is what catches the mistakes unit
tests do not: zero-height pages, controls that fight the user, a switcher
whose stack never got wired up.

test/test_gallery.ml mirrors its view half in a vtree-only component, so the
constructors are covered headlessly too -- and it is the worked example of the
rule the README states about keeping view functions ocgtk-free.

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01Sg3Ci8U8kUKR8C3PL1pNSs
MSG
```

---

