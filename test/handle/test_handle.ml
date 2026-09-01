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
  [%expect
    {|
    ((kind (Window ((title (Counter))))) (attrs ())
     (children
      (Single
       (((kind (Box ((orientation Vertical)))) (attrs ())
         (children
          (List
           (((kind (Label ((text "Count: 0")))) (attrs ((Test_id count)))
             (children No_children))
            ((kind (Button ((label (+)))))
             (attrs ((Test_id inc) (On_clicked <handler>)))
             (children (Single ())))))))))))
    |}];
  Bonsai_gtk_test.Handle.do_actions handle [ Click "inc" ];
  Bonsai_gtk_test.Handle.recompute_view handle;
  Bonsai_gtk_test.Handle.do_actions handle [ Click "inc" ];
  Bonsai_gtk_test.Handle.show_diff handle;
  [%expect
    {|
      ((kind (Window ((title (Counter))))) (attrs ())
       (children
        (Single
         (((kind (Box ((orientation Vertical)))) (attrs ())
           (children
            (List
    -|       (((kind (Label ((text "Count: 0")))) (attrs ((Test_id count)))
    +|       (((kind (Label ((text "Count: 2")))) (attrs ((Test_id count)))
               (children No_children))
              ((kind (Button ((label (+)))))
               (attrs ((Test_id inc) (On_clicked <handler>)))
               (children (Single ())))))))))))
    |}]
;;

let%expect_test "clicking an unknown test id raises" =
  let handle = Bonsai_gtk_test.create counter in
  Expect_test_helpers_core.require_does_raise (fun () ->
    Bonsai_gtk_test.Handle.do_actions handle [ Click "nope" ]);
  [%expect {| (Failure "Bonsai_gtk_test: no node with test_id nope") |}]
;;

let toggler (graph @ local) =
  let on, set_on = Bonsai.state false graph in
  let%arr on and set_on in
  Node.window
    ~title:"Toggler"
    (Node.box
       ~orientation:Vertical
       [ Node.switch ~attrs:[ Attr.test_id "sw"; Attr.on_toggled set_on ] ~active:on ()
       ; Node.label ~attrs:[ Attr.test_id "state" ] (if on then "on" else "off")
       ])
;;

let%expect_test "Toggle fires the handler with the value the widget would take" =
  let handle = Bonsai_gtk_test.create toggler in
  Bonsai_gtk_test.Handle.show handle;
  [%expect
    {|
    ((kind (Window ((title (Toggler))))) (attrs ())
     (children
      (Single
       (((kind (Box ((orientation Vertical)))) (attrs ())
         (children
          (List
           (((kind (Switch ((active false))))
             (attrs ((Test_id sw) (On_toggled <handler>)))
             (children No_children))
            ((kind (Label ((text off)))) (attrs ((Test_id state)))
             (children No_children))))))))))
    |}];
  Bonsai_gtk_test.Handle.do_actions handle [ Toggle "sw" ];
  Bonsai_gtk_test.Handle.show_diff handle;
  [%expect
    {|
      ((kind (Window ((title (Toggler))))) (attrs ())
       (children
        (Single
         (((kind (Box ((orientation Vertical)))) (attrs ())
           (children
            (List
    -|       (((kind (Switch ((active false))))
    +|       (((kind (Switch ((active true))))
               (attrs ((Test_id sw) (On_toggled <handler>)))
               (children No_children))
    -|        ((kind (Label ((text off)))) (attrs ((Test_id state)))
    +|        ((kind (Label ((text on)))) (attrs ((Test_id state)))
               (children No_children))))))))))
    |}]
;;

(* [Attr.on_toggled] on a label is [Invalid_argument] the moment it is mounted, but a
   headless handle never mounts anything, so this is the shape [Bonsai_gtk_test] has to
   refuse on its own. *)
let mislabelled (_graph @ local) =
  Bonsai.return
    (Node.window
       ~title:"Mislabelled"
       (Node.label
          ~attrs:[ Attr.test_id "lbl"; Attr.on_toggled (fun _ -> Ui_effect.Ignore) ]
          "x"))
;;

let%expect_test "Toggle needs a handler, and a node with toggle state to read" =
  let handle = Bonsai_gtk_test.create toggler in
  Bonsai_gtk_test.Handle.recompute_view handle;
  Expect_test_helpers_core.require_does_raise (fun () ->
    Bonsai_gtk_test.Handle.do_actions handle [ Toggle "state" ]);
  [%expect {| (Failure "Bonsai_gtk_test: node state has no on_toggled handler") |}];
  (* The second half never reaches the action now, and that is the {i fix}: the tree is
     refused when it is built, which is what [mislabelled]'s comment above always claimed
     and what this test was written to assert.

     It was not asserting that until Task 13's fix round. [Handle.recompute_view] used to
     run the computation without building the view, so the [Events] check in
     [Result_spec.view] never ran and the illegal tree sailed through to [do_actions],
     where [Toggle] failed for a second, weaker reason -- "has no toggle state" -- that a
     reader would take as the point of the test. This file was the one place in the suite
     where the non-checking [recompute_view] was certifying a tree the runtime refuses,
     and the shadow found it on the first run.

     [current_active]'s "has no toggle state" arm has no legal path to it any more: the
     three kinds [Events.for_kind] says emit [On_toggled] are exactly the three that carry
     toggle state, so a node that reaches the action has state to read. The arm stays as a
     defensive one and says so where it lives. *)
  let handle = Bonsai_gtk_test.create mislabelled in
  Expect_test_helpers_core.require_does_raise (fun () ->
    Bonsai_gtk_test.Handle.recompute_view handle);
  [%expect {| (Invalid_argument "root/0: Label does not emit On_toggled") |}]
;;

(* The test that pins the controlled-text semantics headlessly: [Set_text] means "the user
   made the text be this", the model rewrites it, and the rewrite comes back as the node's
   [text] prop -- never the raw string the "user" typed. *)
let shouty (graph @ local) =
  let text, set_text = Bonsai.state "" graph in
  let submitted, set_submitted = Bonsai.state "-" graph in
  let%arr text and set_text and submitted and set_submitted in
  Node.window
    ~title:"Shouty"
    (Node.box
       ~orientation:Vertical
       [ Node.entry
           ~attrs:
             [ Attr.test_id "e"
             ; Attr.on_changed (fun s -> set_text (String.uppercase s))
             ; Attr.on_activate (set_submitted text)
             ]
           ~placeholder:"type"
           ~text
           ()
       ; Node.label ~attrs:[ Attr.test_id "echo" ] text
       ; Node.label ~attrs:[ Attr.test_id "submitted" ] submitted
       ])
;;

let%expect_test "Set_text runs the model, and the model's rewrite comes back as the prop" =
  let handle = Bonsai_gtk_test.create shouty in
  Bonsai_gtk_test.Handle.show handle;
  [%expect
    {|
    ((kind (Window ((title (Shouty))))) (attrs ())
     (children
      (Single
       (((kind (Box ((orientation Vertical)))) (attrs ())
         (children
          (List
           (((kind (Entry ((text "") (placeholder (type)))))
             (attrs ((Test_id e) (On_changed <handler>) (On_activate <handler>)))
             (children No_children))
            ((kind (Label ((text "")))) (attrs ((Test_id echo)))
             (children No_children))
            ((kind (Label ((text -)))) (attrs ((Test_id submitted)))
             (children No_children))))))))))
    |}];
  Bonsai_gtk_test.Handle.do_actions handle [ Set_text ("e", "hello") ];
  Bonsai_gtk_test.Handle.show_diff handle;
  [%expect
    {|
      ((kind (Window ((title (Shouty))))) (attrs ())
       (children
        (Single
         (((kind (Box ((orientation Vertical)))) (attrs ())
           (children
            (List
    -|       (((kind (Entry ((text "") (placeholder (type)))))
    +|       (((kind (Entry ((text HELLO) (placeholder (type)))))
               (attrs ((Test_id e) (On_changed <handler>) (On_activate <handler>)))
               (children No_children))
    -|        ((kind (Label ((text "")))) (attrs ((Test_id echo)))
    +|        ((kind (Label ((text HELLO)))) (attrs ((Test_id echo)))
               (children No_children))
              ((kind (Label ((text -)))) (attrs ((Test_id submitted)))
               (children No_children))))))))))
    |}]
;;

let%expect_test "Activate fires on_activate, which sees the text the model settled on" =
  let handle = Bonsai_gtk_test.create shouty in
  Bonsai_gtk_test.Handle.recompute_view handle;
  Bonsai_gtk_test.Handle.do_actions handle [ Set_text ("e", "hello") ];
  Bonsai_gtk_test.Handle.show handle;
  [%expect
    {|
    ((kind (Window ((title (Shouty))))) (attrs ())
     (children
      (Single
       (((kind (Box ((orientation Vertical)))) (attrs ())
         (children
          (List
           (((kind (Entry ((text HELLO) (placeholder (type)))))
             (attrs ((Test_id e) (On_changed <handler>) (On_activate <handler>)))
             (children No_children))
            ((kind (Label ((text HELLO)))) (attrs ((Test_id echo)))
             (children No_children))
            ((kind (Label ((text -)))) (attrs ((Test_id submitted)))
             (children No_children))))))))))
    |}];
  Bonsai_gtk_test.Handle.do_actions handle [ Activate "e" ];
  Bonsai_gtk_test.Handle.show_diff handle;
  [%expect
    {|
      ((kind (Window ((title (Shouty))))) (attrs ())
       (children
        (Single
         (((kind (Box ((orientation Vertical)))) (attrs ())
           (children
            (List
             (((kind (Entry ((text HELLO) (placeholder (type)))))
               (attrs ((Test_id e) (On_changed <handler>) (On_activate <handler>)))
               (children No_children))
              ((kind (Label ((text HELLO)))) (attrs ((Test_id echo)))
               (children No_children))
    -|        ((kind (Label ((text -)))) (attrs ((Test_id submitted)))
    +|        ((kind (Label ((text HELLO)))) (attrs ((Test_id submitted)))
               (children No_children))))))))))
    |}]
;;

let%expect_test "Set_text, Activate and Set_value need the matching handler" =
  let handle = Bonsai_gtk_test.create shouty in
  Bonsai_gtk_test.Handle.recompute_view handle;
  Expect_test_helpers_core.require_does_raise (fun () ->
    Bonsai_gtk_test.Handle.do_actions handle [ Set_text ("echo", "x") ]);
  [%expect {| (Failure "Bonsai_gtk_test: node echo has no on_changed handler") |}];
  Expect_test_helpers_core.require_does_raise (fun () ->
    Bonsai_gtk_test.Handle.do_actions handle [ Activate "echo" ]);
  [%expect {| (Failure "Bonsai_gtk_test: node echo has no on_activate handler") |}];
  Expect_test_helpers_core.require_does_raise (fun () ->
    Bonsai_gtk_test.Handle.do_actions handle [ Set_value ("echo", 1.) ]);
  [%expect {| (Failure "Bonsai_gtk_test: node echo has no on_value_changed handler") |}]
;;

let clamped (graph @ local) =
  let v, set_v = Bonsai.state 5. graph in
  let%arr v and set_v in
  Node.window
    ~title:"Clamped"
    (Node.scale
       ~attrs:
         [ Attr.test_id "s"; Attr.on_value_changed (fun x -> set_v (Float.min x 8.)) ]
       ~orientation:Horizontal
       ~min:0.
       ~max:10.
       ~value:v
       ())
;;

let%expect_test "Set_value goes through the model, which may refuse it" =
  let handle = Bonsai_gtk_test.create clamped in
  Bonsai_gtk_test.Handle.show handle;
  [%expect
    {|
    ((kind (Window ((title (Clamped))))) (attrs ())
     (children
      (Single
       (((kind (Scale ((orientation Horizontal) (value 5) (min 0) (max 10))))
         (attrs ((Test_id s) (On_value_changed <handler>)))
         (children No_children))))))
    |}];
  Bonsai_gtk_test.Handle.do_actions handle [ Set_value ("s", 9.5) ];
  Bonsai_gtk_test.Handle.show_diff handle;
  [%expect
    {|
      ((kind (Window ((title (Clamped))))) (attrs ())
       (children
        (Single
    -|   (((kind (Scale ((orientation Horizontal) (value 5) (min 0) (max 10))))
    +|   (((kind (Scale ((orientation Horizontal) (value 8) (min 0) (max 10))))
           (attrs ((Test_id s) (On_value_changed <handler>)))
           (children No_children))))))
    |}]
;;

(* [Search_changed] and [Set_expanded] are the two M2 actions. Both models are real state
   so that a golden here would change if the handler were not reached -- an action wired
   to a handler that ignores its argument would print the same diff either way. *)
let searcher (graph @ local) =
  let query, set_query = Bonsai.state "" graph in
  let expanded, set_expanded = Bonsai.state false graph in
  let%arr query and set_query and expanded and set_expanded in
  Node.window
    ~title:"Search"
    (Node.box
       ~orientation:Vertical
       [ Node.search_entry
           ~attrs:[ Attr.test_id "q"; Attr.on_search_changed set_query ]
           ~text:query
           ()
       ; Node.expander
           ~attrs:[ Attr.test_id "adv"; Attr.on_expanded_changed set_expanded ]
           ~expanded
           ~label:"advanced"
           (Node.label ~attrs:[ Attr.test_id "hits" ] query)
       ])
;;

let%expect_test "Search_changed and Set_expanded reach their handlers" =
  let handle = Bonsai_gtk_test.create searcher in
  Bonsai_gtk_test.Handle.show handle;
  [%expect
    {|
    ((kind (Window ((title (Search))))) (attrs ())
     (children
      (Single
       (((kind (Box ((orientation Vertical)))) (attrs ())
         (children
          (List
           (((kind (Search_entry ((text ""))))
             (attrs ((Test_id q) (On_search_changed <handler>)))
             (children No_children))
            ((kind (Expander ((label (advanced)) (expanded false))))
             (attrs ((Test_id adv) (On_expanded_changed <handler>)))
             (children
              (Single
               (((kind (Label ((text "")))) (attrs ((Test_id hits)))
                 (children No_children))))))))))))))
    |}];
  Bonsai_gtk_test.Handle.do_actions handle [ Search_changed ("q", "bach") ];
  Bonsai_gtk_test.Handle.show_diff handle;
  [%expect
    {|
      ((kind (Window ((title (Search))))) (attrs ())
       (children
        (Single
         (((kind (Box ((orientation Vertical)))) (attrs ())
           (children
            (List
    -|       (((kind (Search_entry ((text ""))))
    +|       (((kind (Search_entry ((text bach))))
               (attrs ((Test_id q) (On_search_changed <handler>)))
               (children No_children))
              ((kind (Expander ((label (advanced)) (expanded false))))
               (attrs ((Test_id adv) (On_expanded_changed <handler>)))
               (children
                (Single
    -|           (((kind (Label ((text "")))) (attrs ((Test_id hits)))
    +|           (((kind (Label ((text bach)))) (attrs ((Test_id hits)))
                   (children No_children))))))))))))))
    |}];
  Bonsai_gtk_test.Handle.do_actions handle [ Set_expanded ("adv", true) ];
  Bonsai_gtk_test.Handle.show_diff handle;
  [%expect
    {|
      ((kind (Window ((title (Search))))) (attrs ())
       (children
        (Single
         (((kind (Box ((orientation Vertical)))) (attrs ())
           (children
            (List
             (((kind (Search_entry ((text bach))))
               (attrs ((Test_id q) (On_search_changed <handler>)))
               (children No_children))
    -|        ((kind (Expander ((label (advanced)) (expanded false))))
    +|        ((kind (Expander ((label (advanced)) (expanded true))))
               (attrs ((Test_id adv) (On_expanded_changed <handler>)))
               (children
                (Single
                 (((kind (Label ((text bach)))) (attrs ((Test_id hits)))
                   (children No_children))))))))))))))
    |}]
;;

let%expect_test "Search_changed and Set_expanded on a node that carries no handler" =
  let no_handlers (_graph @ local) =
    Bonsai.return
      (Node.window
         ~title:"bare"
         (Node.box
            ~orientation:Vertical
            [ Node.search_entry ~attrs:[ Attr.test_id "q" ] ~text:"" ()
            ; Node.expander
                ~attrs:[ Attr.test_id "adv" ]
                ~expanded:false
                ~label:"advanced"
                (Node.label "x")
            ]))
  in
  let handle = Bonsai_gtk_test.create no_handlers in
  Bonsai_gtk_test.Handle.show handle;
  [%expect
    {|
    ((kind (Window ((title (bare))))) (attrs ())
     (children
      (Single
       (((kind (Box ((orientation Vertical)))) (attrs ())
         (children
          (List
           (((kind (Search_entry ((text "")))) (attrs ((Test_id q)))
             (children No_children))
            ((kind (Expander ((label (advanced)) (expanded false))))
             (attrs ((Test_id adv)))
             (children
              (Single
               (((kind (Label ((text x)))) (attrs ()) (children No_children))))))))))))))
    |}];
  Expect_test_helpers_core.require_does_raise (fun () ->
    Bonsai_gtk_test.Handle.do_actions handle [ Search_changed ("q", "x") ]);
  [%expect {| (Failure "Bonsai_gtk_test: node q has no on_search_changed handler") |}];
  Expect_test_helpers_core.require_does_raise (fun () ->
    Bonsai_gtk_test.Handle.do_actions handle [ Set_expanded ("adv", true) ]);
  [%expect {| (Failure "Bonsai_gtk_test: node adv has no on_expanded_changed handler") |}]
;;

(* The whole point of [Events]: a handle that would have gone green on a tree the runtime
   refuses at mount now refuses it here, with the same message shape. *)
let%expect_test "an event attr the kind cannot emit is rejected by the handle" =
  let bad (_graph @ local) =
    Bonsai.return
      (Node.window
         ~title:"bad"
         (Node.label
            ~attrs:[ Attr.on_toggled (fun _ -> Ui_effect.Ignore) ]
            "not a switch"))
  in
  Expect_test_helpers_core.require_does_raise (fun () ->
    let handle = Bonsai_gtk_test.create bad in
    Bonsai_gtk_test.Handle.show handle);
  [%expect {| (Invalid_argument "root/0: Label does not emit On_toggled") |}]
;;

(* The same point for [Placement], and it is the sharper one: a misplaced placement attr
   is applied by nobody and read by nobody, so before this check a headless suite was the
   only place it could have been caught -- and it passed. Both messages are the string
   [Placement.rejection] builds, so they are the runtime's byte for byte rather than a
   second spelling of them. *)
let%expect_test "a placement attr the parent does not read is rejected by the handle" =
  let misplaced_title (_graph @ local) =
    Bonsai.return
      (Node.window
         ~title:"bad"
         (Node.box
            ~orientation:Vertical
            [ Node.label ~attrs:[ Attr.page_title "Library" ] "not a stack page" ]))
  in
  Expect_test_helpers_core.require_does_raise (fun () ->
    let handle = Bonsai_gtk_test.create misplaced_title in
    Bonsai_gtk_test.Handle.show handle);
  [%expect
    {|
    (Invalid_argument
     "root/0/0: Attr.page_title is not read by Box (a placement attribute is read by the container, and this one holds children for Stack)")
    |}];
  let misplaced_cell (_graph @ local) =
    Bonsai.return
      (Node.window
         ~title:"bad"
         (Node.box
            ~orientation:Vertical
            [ Node.label ~attrs:[ Attr.grid_cell ~column:0 ~row:0 () ] "not a grid child"
            ]))
  in
  Expect_test_helpers_core.require_does_raise (fun () ->
    let handle = Bonsai_gtk_test.create misplaced_cell in
    Bonsai_gtk_test.Handle.show handle);
  [%expect
    {|
    (Invalid_argument
     "root/0/0: Attr.grid_cell is not read by Box (a placement attribute is read by the container, and this one holds children for Grid)")
    |}];
  (* The root has no container above it, so every placement attr is misplaced there. *)
  let on_the_root (_graph @ local) =
    Bonsai.return
      (Node.window ~title:"bad" ~attrs:[ Attr.measure_overlay true ] (Node.label "x"))
  in
  Expect_test_helpers_core.require_does_raise (fun () ->
    let handle = Bonsai_gtk_test.create on_the_root in
    Bonsai_gtk_test.Handle.show handle);
  [%expect
    {|
    (Invalid_argument
     "root: Attr.measure_overlay is on the root node, which has no container to read it (a placement attribute is read by the container, and this one holds children for Overlay)")
    |}]
;;

(* ... and the containers that do read one accept it, which is what stops the check above
   from being a table of names nothing satisfies. *)
let%expect_test "a placement attr the parent does read passes validation" =
  let placed (_graph @ local) =
    Bonsai.return
      (Node.window
         ~title:"ok"
         (Node.box
            ~orientation:Vertical
            [ Node.grid
                [ Node.label ~attrs:[ Attr.grid_cell ~column:1 ~row:2 () ] "cell" ]
            ; Node.stack
                ~name:"nav"
                ~visible_child:"p"
                [ Node.label ~key:"p" ~attrs:[ Attr.page_title "P" ] "p" ]
            ; Node.overlay
                ~overlays:[ Node.label ~attrs:[ Attr.measure_overlay true ] "over" ]
                (Node.label "under")
            ]))
  in
  let handle = Bonsai_gtk_test.create placed in
  Bonsai_gtk_test.Handle.show handle;
  [%expect
    {|
    ((kind (Window ((title (ok))))) (attrs ())
     (children
      (Single
       (((kind (Box ((orientation Vertical)))) (attrs ())
         (children
          (List
           (((kind (Grid ())) (attrs ())
             (children
              (List
               (((kind (Label ((text cell))))
                 (attrs ((Grid_cell ((column 1) (row 2) (width 1) (height 1)))))
                 (children No_children))))))
            ((kind (Stack ((name nav) (visible_child p)))) (attrs ())
             (children
              (List
               (((kind (Label ((text p)))) (key p) (attrs ((Page_title P)))
                 (children No_children))))))
            ((kind (Overlay ())) (attrs ())
             (children
              (Slots
               ((child
                 (Single
                  (((kind (Label ((text under)))) (attrs ())
                    (children No_children)))))
                (overlays
                 (List
                  (((kind (Label ((text over)))) (attrs ((Measure_overlay true)))
                    (children No_children)))))))))))))))))
    |}]
;;

(* ... and one the kind *can* emit is not, however deep it sits. *)
let%expect_test "a supported event attr passes validation at every depth" =
  let ok (_graph @ local) =
    Bonsai.return
      (Node.window
         ~title:"ok"
         (Node.box
            ~orientation:Vertical
            [ Node.switch
                ~attrs:[ Attr.on_toggled (fun _ -> Ui_effect.Ignore) ]
                ~active:false
                ()
            ]))
  in
  let handle = Bonsai_gtk_test.create ok in
  Bonsai_gtk_test.Handle.show handle;
  [%expect
    {|
    ((kind (Window ((title (ok))))) (attrs ())
     (children
      (Single
       (((kind (Box ((orientation Vertical)))) (attrs ())
         (children
          (List
           (((kind (Switch ((active false)))) (attrs ((On_toggled <handler>)))
             (children No_children))))))))))
    |}]
;;

(* [Events.for_kind (Native _) = []] is load-bearing (spec §6.6): a native impl declares
   no signal specs, so a native widget that wants to reach Bonsai connects its own GTK
   handler in [create] rather than carrying an event attr. Pinned here because the
   rejection tests above are all [Label], and a wildcard slipping into the table would not
   move them. *)
let%expect_test "a Node.native carrying any event attr is rejected by the handle" =
  let native (_graph @ local) =
    Bonsai.return
      (Node.window
         ~title:"native"
         (Node.native
            ~attrs:[ Attr.on_clicked Ui_effect.Ignore ]
            { Native.name = "thing"; payload = Native.Unit }))
  in
  Expect_test_helpers_core.require_does_raise (fun () ->
    let handle = Bonsai_gtk_test.create native in
    Bonsai_gtk_test.Handle.show handle);
  [%expect {| (Invalid_argument "root/0: Native:thing does not emit On_clicked") |}]
;;

(* The controller attrs are legal on every kind -- they are not any impl's signal, they
   are a [GtkEventController] the runtime attaches to whatever widget carries the attr --
   so a [Node.label] carrying one is accepted where [Attr.on_clicked] on the same node is
   not. *)
let%expect_test "a controller attr is accepted on a kind that emits no signals" =
  let app (_graph @ local) =
    Bonsai.return
      (Node.window
         ~title:"controllers"
         (Node.label
            ~attrs:
              [ Attr.on_click (fun _ -> Click_response.Continue)
              ; Attr.on_focus_enter (fun () -> Ui_effect.Ignore)
              ]
            "card"))
  in
  let handle = Bonsai_gtk_test.create app in
  Bonsai_gtk_test.Handle.show handle;
  [%expect
    {|
    ((kind (Window ((title (controllers))))) (attrs ())
     (children
      (Single
       (((kind (Label ((text card))))
         (attrs
          ((On_click (button 0) (phase Bubble) (handler <handler>))
           (On_focus_enter (phase Bubble) (handler <handler>))))
         (children No_children))))))
    |}]
;;

(* This is stavekeeper's [library_window.ml:166-185] in miniature -- middle click, or
   button 1 with shift, pops the piece out -- and it is the whole reason the payload
   carries [button] and [modifiers].

   The click is delivered to the *handler*, not through GTK: there is no synthetic click
   in the binding (see [test/live/live_controllers_util.ml]), so what a headless suite
   proves is the half an application actually writes. *)
let%expect_test "a click action carries the button and the modifiers" =
  let app (graph @ local) =
    let log, set_log = Bonsai.state [] graph in
    let%arr log and set_log in
    Node.window
      ~title:"clicks"
      (Node.box
         ~orientation:Vertical
         [ Node.label
             ~attrs:
               [ Attr.test_id "card"
               ; Attr.on_click (fun (e : Click_event.t) ->
                   Click_response.Claim_and
                     (set_log
                        (sprintf "b%d n%d shift=%b" e.button e.n_press e.modifiers.shift
                         :: log)))
               ]
             "card"
         ; Node.label ~attrs:[ Attr.test_id "log" ] (String.concat ~sep:"," log)
         ])
  in
  let handle = Bonsai_gtk_test.create app in
  Bonsai_gtk_test.Handle.show handle;
  [%expect
    {|
    ((kind (Window ((title (clicks))))) (attrs ())
     (children
      (Single
       (((kind (Box ((orientation Vertical)))) (attrs ())
         (children
          (List
           (((kind (Label ((text card))))
             (attrs
              ((Test_id card)
               (On_click (button 0) (phase Bubble) (handler <handler>))))
             (children No_children))
            ((kind (Label ((text "")))) (attrs ((Test_id log)))
             (children No_children))))))))))
    |}];
  Bonsai_gtk_test.Handle.do_actions
    handle
    [ Click_at
        ( "card"
        , { Click_event.button = 2
          ; n_press = 1
          ; x = 0.
          ; y = 0.
          ; modifiers = { Modifiers.none with shift = true }
          } )
    ];
  Bonsai_gtk_test.Handle.show_diff handle;
  [%expect
    {|
    on_click card -> (Claim_and <effect>)

      ((kind (Window ((title (clicks))))) (attrs ())
       (children
        (Single
         (((kind (Box ((orientation Vertical)))) (attrs ())
           (children
            (List
             (((kind (Label ((text card))))
               (attrs
                ((Test_id card)
                 (On_click (button 0) (phase Bubble) (handler <handler>))))
               (children No_children))
    -|        ((kind (Label ((text "")))) (attrs ((Test_id log)))
    +|        ((kind (Label ((text "b2 n1 shift=true")))) (attrs ((Test_id log)))
               (children No_children))))))))))
    |}]
;;

(* Focus in and out of a node, headlessly. Both attrs ride on one controller live, but
   headless they are two independent handlers and the actions are two. *)
let%expect_test "focus actions fire the focus handlers" =
  let app (graph @ local) =
    let log, set_log = Bonsai.state [] graph in
    let%arr log and set_log in
    Node.window
      ~title:"focus"
      (Node.box
         ~orientation:Vertical
         [ Node.button
             ~attrs:
               [ Attr.test_id "target"
               ; Attr.on_focus_enter (fun () -> set_log ("enter" :: log))
               ; Attr.on_focus_leave (fun () -> set_log ("leave" :: log))
               ]
             ~label:"target"
             ()
         ; Node.label ~attrs:[ Attr.test_id "log" ] (String.concat ~sep:"," log)
         ])
  in
  let handle = Bonsai_gtk_test.create app in
  Bonsai_gtk_test.Handle.show handle;
  [%expect
    {|
    ((kind (Window ((title (focus))))) (attrs ())
     (children
      (Single
       (((kind (Box ((orientation Vertical)))) (attrs ())
         (children
          (List
           (((kind (Button ((label (target)))))
             (attrs
              ((Test_id target)
               (On_focus_enter (phase Bubble) (handler <handler>))
               (On_focus_leave (phase Bubble) (handler <handler>))))
             (children (Single ())))
            ((kind (Label ((text "")))) (attrs ((Test_id log)))
             (children No_children))))))))))
    |}];
  Bonsai_gtk_test.Handle.do_actions handle [ Focus_enter "target" ];
  Bonsai_gtk_test.Handle.recompute_view handle;
  Bonsai_gtk_test.Handle.do_actions handle [ Focus_leave "target" ];
  Bonsai_gtk_test.Handle.show_diff handle;
  [%expect
    {|
      ((kind (Window ((title (focus))))) (attrs ())
       (children
        (Single
         (((kind (Box ((orientation Vertical)))) (attrs ())
           (children
            (List
             (((kind (Button ((label (target)))))
               (attrs
                ((Test_id target)
                 (On_focus_enter (phase Bubble) (handler <handler>))
                 (On_focus_leave (phase Bubble) (handler <handler>))))
               (children (Single ())))
    -|        ((kind (Label ((text "")))) (attrs ((Test_id log)))
    +|        ((kind (Label ((text leave,enter)))) (attrs ((Test_id log)))
               (children No_children))))))))))
    |}]
;;

(* The [contains_focus] query as an event: the model owns the bit without deriving it from
   enter/leave pairs, and the action drives both directions. *)
let%expect_test "a Focus_contains action fires on_contains_focus_changed" =
  let app (graph @ local) =
    let inside, set_inside = Bonsai.state false graph in
    let%arr inside and set_inside in
    Node.window
      ~title:"contains"
      (Node.box
         ~orientation:Vertical
         [ Node.entry
             ~attrs:[ Attr.test_id "field"; Attr.on_contains_focus_changed set_inside ]
             ~text:""
             ()
         ; Node.label
             ~attrs:[ Attr.test_id "state" ]
             (if inside then "inside" else "outside")
         ])
  in
  let handle = Bonsai_gtk_test.create app in
  Bonsai_gtk_test.Handle.store_view handle;
  Bonsai_gtk_test.Handle.do_actions handle [ Focus_contains ("field", true) ];
  Bonsai_gtk_test.Handle.show_diff handle;
  [%expect
    {|
      ((kind (Window ((title (contains))))) (attrs ())
       (children
        (Single
         (((kind (Box ((orientation Vertical)))) (attrs ())
           (children
            (List
             (((kind (Entry ((text ""))))
               (attrs ((Test_id field) (On_contains_focus_changed <handler>)))
               (children No_children))
    -|        ((kind (Label ((text outside)))) (attrs ((Test_id state)))
    +|        ((kind (Label ((text inside)))) (attrs ((Test_id state)))
               (children No_children))))))))))
    |}];
  Bonsai_gtk_test.Handle.do_actions handle [ Focus_contains ("field", false) ];
  Bonsai_gtk_test.Handle.show_diff handle;
  [%expect
    {|
      ((kind (Window ((title (contains))))) (attrs ())
       (children
        (Single
         (((kind (Box ((orientation Vertical)))) (attrs ())
           (children
            (List
             (((kind (Entry ((text ""))))
               (attrs ((Test_id field) (On_contains_focus_changed <handler>)))
               (children No_children))
    -|        ((kind (Label ((text inside)))) (attrs ((Test_id state)))
    +|        ((kind (Label ((text outside)))) (attrs ((Test_id state)))
               (children No_children))))))))))
    |}]
;;

(* An action naming a node that carries no such attr fails rather than doing nothing --
   the same rule every other action follows. *)
let%expect_test "a click action on a node with no click handler fails" =
  let app (_graph @ local) =
    Bonsai.return
      (Node.window ~title:"no click" (Node.label ~attrs:[ Attr.test_id "plain" ] "plain"))
  in
  let handle = Bonsai_gtk_test.create app in
  Bonsai_gtk_test.Handle.show handle;
  [%expect
    {|
    ((kind (Window ((title ("no click"))))) (attrs ())
     (children
      (Single
       (((kind (Label ((text plain)))) (attrs ((Test_id plain)))
         (children No_children))))))
    |}];
  Expect_test_helpers_core.require_does_raise (fun () ->
    Bonsai_gtk_test.Handle.do_actions
      handle
      [ Click_at
          ( "plain"
          , { Click_event.button = 1
            ; n_press = 1
            ; x = 0.
            ; y = 0.
            ; modifiers = Modifiers.none
            } )
      ];
    Bonsai_gtk_test.Handle.recompute_view handle);
  [%expect {| (Failure "Bonsai_gtk_test: node plain has no on_click handler") |}]
;;

(* Stavekeeper's [dialog.ml:37-51] in miniature: a sheet that consumes Escape in the
   capture phase and lets everything else through. This is the shape that forced
   [Key_response.t] -- closing the dialog is an effect, but "GTK, stop routing this" is an
   answer that has to be given synchronously, and the handler has to give both.

   The printed line is the answer; the diff is the effect. A headless test can see both,
   and between them they are the whole of what an application writes. What it cannot see
   is the routing itself -- see [Key_press]'s doc. *)
let%expect_test "Escape is handled, other keys propagate" =
  let app (graph @ local) =
    let open_, set_open = Bonsai.state true graph in
    let%arr open_ and set_open in
    Node.window
      ~title:"dialog"
      (Node.box
         ~orientation:Vertical
         ~attrs:
           [ Attr.test_id "sheet"
           ; Attr.on_key_pressed ~phase:Capture (fun (e : Key_event.t) ->
               if e.keyval = Keyval.escape
               then Key_response.Handled_and (set_open false)
               else Propagate)
           ]
         [ Node.label ~attrs:[ Attr.test_id "state" ] (if open_ then "open" else "closed")
         ])
  in
  let handle = Bonsai_gtk_test.create app in
  Bonsai_gtk_test.Handle.show handle;
  [%expect
    {|
    ((kind (Window ((title (dialog))))) (attrs ())
     (children
      (Single
       (((kind (Box ((orientation Vertical))))
         (attrs
          ((Test_id sheet) (On_key_pressed (phase Capture) (handler <handler>))))
         (children
          (List
           (((kind (Label ((text open)))) (attrs ((Test_id state)))
             (children No_children))))))))))
    |}];
  let press keyval =
    Bonsai_gtk_test.Handle.do_actions
      handle
      [ Key_press ("sheet", { keyval; keycode = 0; modifiers = Modifiers.none }) ]
  in
  press (Keyval.of_char 'x');
  Bonsai_gtk_test.Handle.show_diff handle;
  [%expect {| key_pressed sheet -> Propagate |}];
  press Keyval.escape;
  Bonsai_gtk_test.Handle.show_diff handle;
  [%expect
    {|
    key_pressed sheet -> (Handled_and <effect>)

      ((kind (Window ((title (dialog))))) (attrs ())
       (children
        (Single
         (((kind (Box ((orientation Vertical))))
           (attrs
            ((Test_id sheet) (On_key_pressed (phase Capture) (handler <handler>))))
           (children
            (List
    -|       (((kind (Label ((text open)))) (attrs ((Test_id state)))
    +|       (((kind (Label ((text closed)))) (attrs ((Test_id state)))
               (children No_children))))))))))
    |}]
;;

(* [Propagate_and] is the constructor a reader asks about, and the one that has no shorter
   spelling: observing a key without consuming it. Without it an observer would have to
   answer [Handled] and the keystroke would stop reaching whatever was meant to receive
   it. *)
let%expect_test "a key press can be observed without being consumed" =
  let app (graph @ local) =
    let log, set_log = Bonsai.state [] graph in
    let%arr log and set_log in
    Node.window
      ~title:"observer"
      (Node.box
         ~orientation:Vertical
         [ Node.label
             ~attrs:
               [ Attr.test_id "watched"
               ; Attr.on_key_pressed (fun (e : Key_event.t) ->
                   Key_response.Propagate_and
                     (set_log (sprintf "%#x ctrl=%b" e.keyval e.modifiers.control :: log)))
               ; Attr.on_key_released (fun (e : Key_event.t) ->
                   set_log (sprintf "up %#x" e.keyval :: log))
               ]
             "watched"
         ; Node.label ~attrs:[ Attr.test_id "log" ] (String.concat ~sep:"," log)
         ])
  in
  let handle = Bonsai_gtk_test.create app in
  Bonsai_gtk_test.Handle.show handle;
  [%expect
    {|
    ((kind (Window ((title (observer))))) (attrs ())
     (children
      (Single
       (((kind (Box ((orientation Vertical)))) (attrs ())
         (children
          (List
           (((kind (Label ((text watched))))
             (attrs
              ((Test_id watched)
               (On_key_pressed (phase Bubble) (handler <handler>))
               (On_key_released (phase Bubble) (handler <handler>))))
             (children No_children))
            ((kind (Label ((text "")))) (attrs ((Test_id log)))
             (children No_children))))))))))
    |}];
  Bonsai_gtk_test.Handle.do_actions
    handle
    [ Key_press
        ( "watched"
        , { Key_event.keyval = Keyval.of_char 'w'
          ; keycode = 25
          ; modifiers = { Modifiers.none with control = true }
          } )
    ];
  Bonsai_gtk_test.Handle.recompute_view handle;
  (* No line is printed for the release: [key-released] returns [unit] to GTK, so there is
     no answer to record. *)
  Bonsai_gtk_test.Handle.do_actions
    handle
    [ Key_release
        ( "watched"
        , { Key_event.keyval = Keyval.of_char 'w'
          ; keycode = 25
          ; modifiers = Modifiers.none
          } )
    ];
  Bonsai_gtk_test.Handle.show_diff handle;
  [%expect
    {|
    key_pressed watched -> (Propagate_and <effect>)

      ((kind (Window ((title (observer))))) (attrs ())
       (children
        (Single
         (((kind (Box ((orientation Vertical)))) (attrs ())
           (children
            (List
             (((kind (Label ((text watched))))
               (attrs
                ((Test_id watched)
                 (On_key_pressed (phase Bubble) (handler <handler>))
                 (On_key_released (phase Bubble) (handler <handler>))))
               (children No_children))
    -|        ((kind (Label ((text "")))) (attrs ((Test_id log)))
    -|         (children No_children))))))))))
    +|        ((kind (Label ((text "up 0x77,0x77 ctrl=true"))))
    +|         (attrs ((Test_id log))) (children No_children))))))))))
    |}]
;;

(* The two key attrs share one [GtkEventControllerKey] and so one propagation phase.
   Asking for two is a node the runtime cannot mount, and this is the check that stops a
   headless suite certifying it anyway: [Controllers.configure_phase] and this handle both
   render [Events.family_phase_rejection], so the message is identical rather than merely
   similar. *)
let%expect_test "two key attrs with different phases are rejected by the handle" =
  let app (_graph @ local) =
    Bonsai.return
      (Node.window
         ~title:"phases"
         (Node.label
            ~attrs:
              [ Attr.on_key_pressed ~phase:Capture (fun _ -> Key_response.Propagate)
              ; Attr.on_key_released ~phase:Bubble (fun _ -> Ui_effect.Ignore)
              ]
            "sheet"))
  in
  Expect_test_helpers_core.require_does_raise (fun () ->
    let handle = Bonsai_gtk_test.create app in
    Bonsai_gtk_test.Handle.show handle);
  [%expect
    {|
    (Invalid_argument
     "root/0: Attr.on_key_pressed asks for Capture and Attr.on_key_released for Bubble, but they share one GtkEventControllerKey and so one propagation phase")
    |}];
  (* The same two attrs agreeing is fine, and either one alone is fine -- the phase only
     has to be single-valued, not present twice. *)
  let ok (_graph @ local) =
    Bonsai.return
      (Node.window
         ~title:"phases"
         (Node.label
            ~attrs:
              [ Attr.on_key_pressed ~phase:Capture (fun _ -> Key_response.Propagate)
              ; Attr.on_key_released ~phase:Capture (fun _ -> Ui_effect.Ignore)
              ]
            "sheet"))
  in
  let handle = Bonsai_gtk_test.create ok in
  Bonsai_gtk_test.Handle.show handle;
  [%expect
    {|
    ((kind (Window ((title (phases))))) (attrs ())
     (children
      (Single
       (((kind (Label ((text sheet))))
         (attrs
          ((On_key_pressed (phase Capture) (handler <handler>))
           (On_key_released (phase Capture) (handler <handler>))))
         (children No_children))))))
    |}]
;;

(* The generalisation the focus [?phase] forced: the same rejection, from the same
   [Events.family_phase_rejection], over the Focus family -- naming the family's
   controller class, so the message says which controller the two attrs share. *)
let%expect_test "two focus attrs with different phases are rejected by the handle" =
  let app (_graph @ local) =
    Bonsai.return
      (Node.window
         ~title:"focus phases"
         (Node.label
            ~attrs:
              [ Attr.on_focus_enter ~phase:Capture (fun () -> Ui_effect.Ignore)
              ; Attr.on_focus_leave ~phase:Bubble (fun () -> Ui_effect.Ignore)
              ]
            "sheet"))
  in
  Expect_test_helpers_core.require_does_raise (fun () ->
    let handle = Bonsai_gtk_test.create app in
    Bonsai_gtk_test.Handle.show handle);
  [%expect
    {|
    (Invalid_argument
     "root/0: Attr.on_focus_enter asks for Capture and Attr.on_focus_leave for Bubble, but they share one GtkEventControllerFocus and so one propagation phase")
    |}];
  (* [on_contains_focus_changed] carries no phase, so it does not vote: beside one phased
     attr it is not a disagreement, whatever the phase. *)
  let ok (_graph @ local) =
    Bonsai.return
      (Node.window
         ~title:"focus phases"
         (Node.label
            ~attrs:
              [ Attr.on_focus_enter ~phase:Capture (fun () -> Ui_effect.Ignore)
              ; Attr.on_contains_focus_changed (fun _ -> Ui_effect.Ignore)
              ]
            "sheet"))
  in
  let handle = Bonsai_gtk_test.create ok in
  Bonsai_gtk_test.Handle.recompute_view handle;
  print_s [%sexp "accepted"];
  [%expect {| accepted |}]
;;

(* [Attr.autofocus] is fire-once -- a grab at mount, or on a false-to-true flip -- and at
   most one may fire per frame per toplevel. The handle tracks the same edges the patcher
   does and renders the same [Events.autofocus_rejection] string, so a headless suite
   cannot certify the tree the runtime's fixup queue refuses. *)
let%expect_test "two autofocus grabs in one frame are rejected; one per frame is fine" =
  let both (_graph @ local) =
    Bonsai.return
      (Node.window
         ~title:"af"
         (Node.box
            ~orientation:Vertical
            [ Node.entry ~attrs:[ Attr.autofocus true ] ~text:"" ()
            ; Node.entry ~attrs:[ Attr.autofocus true ] ~text:"" ()
            ]))
  in
  Expect_test_helpers_core.require_does_raise (fun () ->
    let handle = Bonsai_gtk_test.create both in
    Bonsai_gtk_test.Handle.recompute_view handle);
  [%expect
    {|
    (Invalid_argument
     "root/0/0 and root/0/1 both ask Attr.autofocus to grab focus in this frame, but at most one autofocus may fire per frame per toplevel")
    |}];
  (* The fire-once half: a widget that keeps rendering [true] has already fired, so a
     second widget flipping false-to-true on a later frame is the only grab of that frame
     -- accepted, though the tree then carries two [true]s. This is exactly the ported
     palette shape: the dialog's entry autofocused on open, and a later panel's entry
     autofocused when it appears. *)
  let staged (graph @ local) =
    let second, set_second = Bonsai.state false graph in
    let%arr second and set_second in
    Node.window
      ~title:"af"
      (Node.box
         ~orientation:Vertical
         [ Node.entry ~attrs:[ Attr.autofocus true ] ~text:"" ()
         ; Node.entry ~attrs:[ Attr.autofocus second ] ~text:"" ()
         ; Node.button
             ~attrs:[ Attr.test_id "later"; Attr.on_clicked (set_second true) ]
             ~label:"later"
             ()
         ])
  in
  let handle = Bonsai_gtk_test.create staged in
  Bonsai_gtk_test.Handle.recompute_view handle;
  Bonsai_gtk_test.Handle.do_actions handle [ Click "later" ];
  Bonsai_gtk_test.Handle.recompute_view handle;
  print_s [%sexp "accepted"];
  [%expect {| accepted |}]
;;

(* Same rule as every other action: a node that carries no such handler fails rather than
   quietly doing nothing. *)
let%expect_test "a key action on a node with no key handler fails" =
  let app (_graph @ local) =
    Bonsai.return
      (Node.window ~title:"no keys" (Node.label ~attrs:[ Attr.test_id "plain" ] "plain"))
  in
  let handle = Bonsai_gtk_test.create app in
  Bonsai_gtk_test.Handle.show handle;
  [%expect
    {|
    ((kind (Window ((title ("no keys"))))) (attrs ())
     (children
      (Single
       (((kind (Label ((text plain)))) (attrs ((Test_id plain)))
         (children No_children))))))
    |}];
  Expect_test_helpers_core.require_does_raise (fun () ->
    Bonsai_gtk_test.Handle.do_actions
      handle
      [ Key_press
          ( "plain"
          , { Key_event.keyval = Keyval.escape; keycode = 0; modifiers = Modifiers.none }
          )
      ];
    Bonsai_gtk_test.Handle.recompute_view handle);
  [%expect {| (Failure "Bonsai_gtk_test: node plain has no on_key_pressed handler") |}];
  Expect_test_helpers_core.require_does_raise (fun () ->
    Bonsai_gtk_test.Handle.do_actions
      handle
      [ Key_release
          ( "plain"
          , { Key_event.keyval = Keyval.escape; keycode = 0; modifiers = Modifiers.none }
          )
      ];
    Bonsai_gtk_test.Handle.recompute_view handle);
  [%expect {| (Failure "Bonsai_gtk_test: node plain has no on_key_released handler") |}]
;;

(* stavekeeper's [sidebar.ml] in miniature: a rail of keyed rows, a header row that is
   neither selectable nor activatable, and a model whose selection is the key the last
   activation handed it. The parallel [rows]/[row_widgets] arrays that file keeps -- and
   the [get_index]-into-an-array bridge beside them -- exist only because GTK's
   [row-activated] offers an index; [Attr.on_row_activated] offers the node's key, so
   there is nothing to keep in parallel. *)
let filter_list (graph @ local) =
  let chosen, set_chosen = Bonsai.state "all" graph in
  let%arr chosen and set_chosen in
  Node.window
    ~title:"Sidebar"
    (Node.box
       ~orientation:Vertical
       [ Node.list_box
           ~attrs:[ Attr.test_id "rail"; Attr.on_row_activated set_chosen ]
           ~selection_mode:Single
           ~selected:[ chosen ]
           [ Node.label
               ~key:"hdr"
               ~attrs:[ Attr.row_selectable false; Attr.row_activatable false ]
               "FILTERS"
           ; Node.label ~key:"all" "All pieces"
           ; Node.label ~key:"recent" "Recent"
           ]
       ; Node.label ~attrs:[ Attr.test_id "chosen" ] chosen
       ])
;;

let%expect_test "activating a row hands the model the row's key" =
  let handle = Bonsai_gtk_test.create filter_list in
  Bonsai_gtk_test.Handle.show handle;
  [%expect
    {|
    ((kind (Window ((title (Sidebar))))) (attrs ())
     (children
      (Single
       (((kind (Box ((orientation Vertical)))) (attrs ())
         (children
          (List
           (((kind (List_box ((selected (all)))))
             (attrs ((Test_id rail) (On_row_activated <handler>)))
             (children
              (Slots
               ((placeholder (Single ()))
                (rows
                 (List
                  (((kind (Label ((text FILTERS)))) (key hdr)
                    (attrs ((Row_selectable false) (Row_activatable false)))
                    (children No_children))
                   ((kind (Label ((text "All pieces")))) (key all) (attrs ())
                    (children No_children))
                   ((kind (Label ((text Recent)))) (key recent) (attrs ())
                    (children No_children)))))))))
            ((kind (Label ((text all)))) (attrs ((Test_id chosen)))
             (children No_children))))))))))
    |}];
  Bonsai_gtk_test.Handle.do_actions handle [ Activate_row ("rail", "recent") ];
  Bonsai_gtk_test.Handle.show_diff handle;
  [%expect
    {|
      ((kind (Window ((title (Sidebar))))) (attrs ())
       (children
        (Single
         (((kind (Box ((orientation Vertical)))) (attrs ())
           (children
            (List
    -|       (((kind (List_box ((selected (all)))))
    +|       (((kind (List_box ((selected (recent)))))
               (attrs ((Test_id rail) (On_row_activated <handler>)))
               (children
                (Slots
                 ((placeholder (Single ()))
                  (rows
                   (List
                    (((kind (Label ((text FILTERS)))) (key hdr)
                      (attrs ((Row_selectable false) (Row_activatable false)))
                      (children No_children))
                     ((kind (Label ((text "All pieces")))) (key all) (attrs ())
                      (children No_children))
                     ((kind (Label ((text Recent)))) (key recent) (attrs ())
                      (children No_children)))))))))
    -|        ((kind (Label ((text all)))) (attrs ((Test_id chosen)))
    +|        ((kind (Label ((text recent)))) (attrs ((Test_id chosen)))
               (children No_children))))))))))
    |}]
;;

(* [Set_selection] is the other half: a click that changes the selection without
   activating a row (a ctrl-click in [Multiple], a keyboard move in [Browse]), reported by
   [selected-rows-changed] as the whole selection rather than as one row. Like every other
   action, the node's own [~selected] is not consulted -- the action means "the user made
   the selection be this", which is what the real widget reports whatever the model was
   rendering. *)
let multi_list (graph @ local) =
  let picked, set_picked = Bonsai.state [ "b" ] graph in
  let%arr picked and set_picked in
  Node.window
    ~title:"Picker"
    (Node.box
       ~orientation:Vertical
       [ Node.list_box
           ~attrs:[ Attr.test_id "grid"; Attr.on_selected_rows_changed set_picked ]
           ~selection_mode:Multiple
           ~selected:picked
           [ Node.label ~key:"a" "A"; Node.label ~key:"b" "B"; Node.label ~key:"c" "C" ]
       ; Node.label ~attrs:[ Attr.test_id "picked" ] (String.concat ~sep:"," picked)
       ])
;;

let%expect_test "a selection change hands the model every selected key" =
  let handle = Bonsai_gtk_test.create multi_list in
  Bonsai_gtk_test.Handle.show handle;
  [%expect
    {|
    ((kind (Window ((title (Picker))))) (attrs ())
     (children
      (Single
       (((kind (Box ((orientation Vertical)))) (attrs ())
         (children
          (List
           (((kind (List_box ((selection_mode Multiple) (selected (b)))))
             (attrs ((Test_id grid) (On_selected_rows_changed <handler>)))
             (children
              (Slots
               ((placeholder (Single ()))
                (rows
                 (List
                  (((kind (Label ((text A)))) (key a) (attrs ())
                    (children No_children))
                   ((kind (Label ((text B)))) (key b) (attrs ())
                    (children No_children))
                   ((kind (Label ((text C)))) (key c) (attrs ())
                    (children No_children)))))))))
            ((kind (Label ((text b)))) (attrs ((Test_id picked)))
             (children No_children))))))))))
    |}];
  Bonsai_gtk_test.Handle.do_actions handle [ Set_selection ("grid", [ "a"; "c" ]) ];
  Bonsai_gtk_test.Handle.show_diff handle;
  [%expect
    {|
      ((kind (Window ((title (Picker))))) (attrs ())
       (children
        (Single
         (((kind (Box ((orientation Vertical)))) (attrs ())
           (children
            (List
    -|       (((kind (List_box ((selection_mode Multiple) (selected (b)))))
    +|       (((kind (List_box ((selection_mode Multiple) (selected (a c)))))
               (attrs ((Test_id grid) (On_selected_rows_changed <handler>)))
               (children
                (Slots
                 ((placeholder (Single ()))
                  (rows
                   (List
                    (((kind (Label ((text A)))) (key a) (attrs ())
                      (children No_children))
                     ((kind (Label ((text B)))) (key b) (attrs ())
                      (children No_children))
                     ((kind (Label ((text C)))) (key c) (attrs ())
                      (children No_children)))))))))
    -|        ((kind (Label ((text b)))) (attrs ((Test_id picked)))
    +|        ((kind (Label ((text a,c)))) (attrs ((Test_id picked)))
               (children No_children))))))))))
    |}];
  (* Emptying it is a state the widget can reach, so it is one the action can deliver. *)
  Bonsai_gtk_test.Handle.do_actions handle [ Set_selection ("grid", []) ];
  Bonsai_gtk_test.Handle.show_diff handle;
  [%expect
    {|
      ((kind (Window ((title (Picker))))) (attrs ())
       (children
        (Single
         (((kind (Box ((orientation Vertical)))) (attrs ())
           (children
            (List
    -|       (((kind (List_box ((selection_mode Multiple) (selected (a c)))))
    +|       (((kind (List_box ((selection_mode Multiple) (selected ()))))
               (attrs ((Test_id grid) (On_selected_rows_changed <handler>)))
               (children
                (Slots
                 ((placeholder (Single ()))
                  (rows
                   (List
                    (((kind (Label ((text A)))) (key a) (attrs ())
                      (children No_children))
                     ((kind (Label ((text B)))) (key b) (attrs ())
                      (children No_children))
                     ((kind (Label ((text C)))) (key c) (attrs ())
                      (children No_children)))))))))
    -|        ((kind (Label ((text a,c)))) (attrs ((Test_id picked)))
    +|        ((kind (Label ((text "")))) (attrs ((Test_id picked)))
               (children No_children))))))))))
    |}]
;;

(* Same rule as every other action. *)
let%expect_test "a list action on a node with no list handler fails" =
  let app (_graph @ local) =
    Bonsai.return
      (Node.window
         ~title:"bare"
         (Node.list_box
            ~attrs:[ Attr.test_id "plain" ]
            ~selected:[]
            [ Node.label ~key:"a" "A" ]))
  in
  let handle = Bonsai_gtk_test.create app in
  Bonsai_gtk_test.Handle.show handle;
  [%expect
    {|
    ((kind (Window ((title (bare))))) (attrs ())
     (children
      (Single
       (((kind (List_box ((selected ())))) (attrs ((Test_id plain)))
         (children
          (Slots
           ((placeholder (Single ()))
            (rows
             (List
              (((kind (Label ((text A)))) (key a) (attrs ())
                (children No_children)))))))))))))
    |}];
  Expect_test_helpers_core.require_does_raise (fun () ->
    Bonsai_gtk_test.Handle.do_actions handle [ Activate_row ("plain", "a") ]);
  [%expect {| (Failure "Bonsai_gtk_test: node plain has no on_row_activated handler") |}];
  Expect_test_helpers_core.require_does_raise (fun () ->
    Bonsai_gtk_test.Handle.do_actions handle [ Set_selection ("plain", [ "a" ]) ]);
  [%expect
    {|
    (Failure
     "Bonsai_gtk_test: node plain has no on_selected_rows_changed handler")
    |}]
;;

(* The [Events] negative for the two list-box signals: they are the list box's own, so
   neither is legal anywhere else, and the handle refuses the tree the runtime would. *)
let%expect_test "the list box's event attrs are rejected on other kinds" =
  let bad attr (_graph @ local) =
    Bonsai.return (Node.window ~title:"bad" (Node.label ~attrs:[ attr ] "not a list"))
  in
  Expect_test_helpers_core.require_does_raise (fun () ->
    let handle =
      Bonsai_gtk_test.create (bad (Attr.on_row_activated (fun _ -> Ui_effect.Ignore)))
    in
    Bonsai_gtk_test.Handle.show handle);
  [%expect {| (Invalid_argument "root/0: Label does not emit On_row_activated") |}];
  Expect_test_helpers_core.require_does_raise (fun () ->
    let handle =
      Bonsai_gtk_test.create
        (bad (Attr.on_selected_rows_changed (fun _ -> Ui_effect.Ignore)))
    in
    Bonsai_gtk_test.Handle.show handle);
  [%expect
    {| (Invalid_argument "root/0: Label does not emit On_selected_rows_changed") |}]
;;

(* And the [Placement] negative for the two row attrs, which is the sharper one: nothing
   applies them to the child, so a row attr on a box child is read by nobody and would
   otherwise have no diagnostic at all. *)
let%expect_test "the row attrs are rejected outside a list box" =
  let bad attr (_graph @ local) =
    Bonsai.return
      (Node.window
         ~title:"bad"
         (Node.box ~orientation:Vertical [ Node.label ~attrs:[ attr ] "not a row" ]))
  in
  Expect_test_helpers_core.require_does_raise (fun () ->
    let handle = Bonsai_gtk_test.create (bad (Attr.row_selectable false)) in
    Bonsai_gtk_test.Handle.show handle);
  [%expect
    {|
    (Invalid_argument
     "root/0/0: Attr.row_selectable is not read by Box (a placement attribute is read by the container, and this one holds children for ListBox)")
    |}];
  Expect_test_helpers_core.require_does_raise (fun () ->
    let handle = Bonsai_gtk_test.create (bad (Attr.row_activatable false)) in
    Bonsai_gtk_test.Handle.show handle);
  [%expect
    {|
    (Invalid_argument
     "root/0/0: Attr.row_activatable is not read by Box (a placement attribute is read by the container, and this one holds children for ListBox)")
    |}];
  (* ... and a list box's own child carries them happily, which is what stops the check
     above from being a name nothing satisfies. *)
  let ok (_graph @ local) =
    Bonsai.return
      (Node.window
         ~title:"ok"
         (Node.list_box
            ~selected:[]
            [ Node.label
                ~key:"hdr"
                ~attrs:[ Attr.row_selectable false; Attr.row_activatable false ]
                "HEADER"
            ]))
  in
  let handle = Bonsai_gtk_test.create ok in
  Bonsai_gtk_test.Handle.show handle;
  [%expect
    {|
    ((kind (Window ((title (ok))))) (attrs ())
     (children
      (Single
       (((kind (List_box ((selected ())))) (attrs ())
         (children
          (Slots
           ((placeholder (Single ()))
            (rows
             (List
              (((kind (Label ((text HEADER)))) (key hdr)
                (attrs ((Row_selectable false) (Row_activatable false)))
                (children No_children)))))))))))))
    |}]
;;

(* stavekeeper's library grid in miniature ([library_window.ml]'s [build_grid] and the two
   handlers around it): a flow box of keyed cards, [on_child_activated] opening one, and
   [on_selected_children_changed] driving both a "1 selected" label and the toolbar
   buttons' [Attr.sensitive].

   That last part is the argument for the port. The imperative version keeps a [selected]
   ref, a [selected_widget] ref, a [card_entries] array to map a [GtkFlowBoxChild] index
   back to a piece, and three [set_sensitive] calls in the selection handler -- and a
   comment about the dangling widget that arrangement produced when a rebuild destroyed
   the widget the ref still held. Here the selection {i is} the model, the key {i is} the
   identity, and "the Edit button is sensitive when something is selected" is an
   expression rather than a callback. *)
let library_grid (graph @ local) =
  let selected, set_selected = Bonsai.state [] graph in
  let opened, set_opened = Bonsai.state "(nothing)" graph in
  let%arr selected and set_selected and opened and set_opened in
  Node.window
    ~title:"Library"
    (Node.box
       ~orientation:Vertical
       [ Node.button
           ~attrs:
             [ Attr.test_id "edit"
             ; Attr.sensitive (not (List.is_empty selected))
             ; Attr.on_clicked Ui_effect.Ignore
             ]
           ~label:"Edit"
           ()
       ; Node.label
           ~attrs:[ Attr.test_id "count" ]
           (sprintf "%d selected" (List.length selected))
       ; Node.label ~attrs:[ Attr.test_id "opened" ] opened
       ; Node.flow_box
           ~attrs:
             [ Attr.test_id "grid"
             ; Attr.on_child_activated set_opened
             ; Attr.on_selected_children_changed set_selected
             ]
           ~selection_mode:Single
           ~activate_on_single_click:false
           ~min_children_per_line:1
           ~max_children_per_line:10
           ~row_spacing:28
           ~column_spacing:20
           ~selected
           [ Node.label ~key:"sonata" "Sonata"
           ; Node.label ~key:"etude" "Etude"
           ; Node.label ~key:"nocturne" "Nocturne"
           ]
       ])
;;

let%expect_test "a card grid: selection drives the toolbar, activation opens a card" =
  let handle = Bonsai_gtk_test.create library_grid in
  Bonsai_gtk_test.Handle.show handle;
  [%expect
    {|
    ((kind (Window ((title (Library))))) (attrs ())
     (children
      (Single
       (((kind (Box ((orientation Vertical)))) (attrs ())
         (children
          (List
           (((kind (Button ((label (Edit)))))
             (attrs ((Sensitive false) (Test_id edit) (On_clicked <handler>)))
             (children (Single ())))
            ((kind (Label ((text "0 selected")))) (attrs ((Test_id count)))
             (children No_children))
            ((kind (Label ((text "(nothing)")))) (attrs ((Test_id opened)))
             (children No_children))
            ((kind
              (Flow_box
               ((activate_on_single_click false) (min_children_per_line 1)
                (max_children_per_line 10) (row_spacing 28) (column_spacing 20)
                (selected ()))))
             (attrs
              ((Test_id grid) (On_child_activated <handler>)
               (On_selected_children_changed <handler>)))
             (children
              (List
               (((kind (Label ((text Sonata)))) (key sonata) (attrs ())
                 (children No_children))
                ((kind (Label ((text Etude)))) (key etude) (attrs ())
                 (children No_children))
                ((kind (Label ((text Nocturne)))) (key nocturne) (attrs ())
                 (children No_children))))))))))))))
    |}];
  (* A single click selects. The button becomes sensitive and the label counts, both
     because the selection is a value the view reads -- not because a handler reached over
     and set three properties. *)
  Bonsai_gtk_test.Handle.do_actions handle [ Set_selection ("grid", [ "etude" ]) ];
  Bonsai_gtk_test.Handle.show_diff handle;
  [%expect
    {|
      ((kind (Window ((title (Library))))) (attrs ())
       (children
        (Single
         (((kind (Box ((orientation Vertical)))) (attrs ())
           (children
            (List
             (((kind (Button ((label (Edit)))))
    -|         (attrs ((Sensitive false) (Test_id edit) (On_clicked <handler>)))
    +|         (attrs ((Sensitive true) (Test_id edit) (On_clicked <handler>)))
               (children (Single ())))
    -|        ((kind (Label ((text "0 selected")))) (attrs ((Test_id count)))
    +|        ((kind (Label ((text "1 selected")))) (attrs ((Test_id count)))
               (children No_children))
              ((kind (Label ((text "(nothing)")))) (attrs ((Test_id opened)))
               (children No_children))
              ((kind
                (Flow_box
                 ((activate_on_single_click false) (min_children_per_line 1)
                  (max_children_per_line 10) (row_spacing 28) (column_spacing 20)
    -|            (selected ()))))
    +|            (selected (etude)))))
               (attrs
                ((Test_id grid) (On_child_activated <handler>)
                 (On_selected_children_changed <handler>)))
               (children
                (List
                 (((kind (Label ((text Sonata)))) (key sonata) (attrs ())
                   (children No_children))
                  ((kind (Label ((text Etude)))) (key etude) (attrs ())
                   (children No_children))
                  ((kind (Label ((text Nocturne)))) (key nocturne) (attrs ())
                   (children No_children))))))))))))))
    |}];
  (* A double click (or Enter) activates, which is a different signal and a different
     handler: the grid sets [activate_on_single_click] to [false] exactly so that these
     two are separable. *)
  Bonsai_gtk_test.Handle.do_actions handle [ Activate_child ("grid", "etude") ];
  Bonsai_gtk_test.Handle.show_diff handle;
  [%expect
    {|
      ((kind (Window ((title (Library))))) (attrs ())
       (children
        (Single
         (((kind (Box ((orientation Vertical)))) (attrs ())
           (children
            (List
             (((kind (Button ((label (Edit)))))
               (attrs ((Sensitive true) (Test_id edit) (On_clicked <handler>)))
               (children (Single ())))
              ((kind (Label ((text "1 selected")))) (attrs ((Test_id count)))
               (children No_children))
    -|        ((kind (Label ((text "(nothing)")))) (attrs ((Test_id opened)))
    +|        ((kind (Label ((text etude)))) (attrs ((Test_id opened)))
               (children No_children))
              ((kind
                (Flow_box
                 ((activate_on_single_click false) (min_children_per_line 1)
                  (max_children_per_line 10) (row_spacing 28) (column_spacing 20)
                  (selected (etude)))))
               (attrs
                ((Test_id grid) (On_child_activated <handler>)
                 (On_selected_children_changed <handler>)))
               (children
                (List
                 (((kind (Label ((text Sonata)))) (key sonata) (attrs ())
                   (children No_children))
                  ((kind (Label ((text Etude)))) (key etude) (attrs ())
                   (children No_children))
                  ((kind (Label ((text Nocturne)))) (key nocturne) (attrs ())
    |}];
  (* Clicking the background clears it, and the toolbar goes back. *)
  Bonsai_gtk_test.Handle.do_actions handle [ Set_selection ("grid", []) ];
  Bonsai_gtk_test.Handle.show_diff handle;
  [%expect
    {|
      ((kind (Window ((title (Library))))) (attrs ())
       (children
        (Single
         (((kind (Box ((orientation Vertical)))) (attrs ())
           (children
            (List
             (((kind (Button ((label (Edit)))))
    -|         (attrs ((Sensitive true) (Test_id edit) (On_clicked <handler>)))
    +|         (attrs ((Sensitive false) (Test_id edit) (On_clicked <handler>)))
               (children (Single ())))
    -|        ((kind (Label ((text "1 selected")))) (attrs ((Test_id count)))
    +|        ((kind (Label ((text "0 selected")))) (attrs ((Test_id count)))
               (children No_children))
              ((kind (Label ((text etude)))) (attrs ((Test_id opened)))
               (children No_children))
              ((kind
                (Flow_box
                 ((activate_on_single_click false) (min_children_per_line 1)
                  (max_children_per_line 10) (row_spacing 28) (column_spacing 20)
    -|            (selected (etude)))))
    +|            (selected ()))))
               (attrs
                ((Test_id grid) (On_child_activated <handler>)
                 (On_selected_children_changed <handler>)))
               (children
                (List
                 (((kind (Label ((text Sonata)))) (key sonata) (attrs ())
                   (children No_children))
                  ((kind (Label ((text Etude)))) (key etude) (attrs ())
                   (children No_children))
                  ((kind (Label ((text Nocturne)))) (key nocturne) (attrs ())
                   (children No_children))))))))))))))
    |}]
;;

(* [Activate_child] and [Activate_row] name a {i kind} of container, and the handle knows
   the kind of the node it found -- so asking a flow box to activate a row is caught with
   a message naming both, rather than reported as a missing handler (which it also is, and
   which is the less useful half of the truth). [Set_selection] is deliberately shared: it
   is the same question of both kinds, and it dispatches on the kind it finds. *)
let%expect_test "the two activate actions each name their own container kind" =
  let app (_graph @ local) =
    Bonsai.return
      (Node.window
         ~title:"kinds"
         (Node.box
            ~orientation:Vertical
            [ Node.flow_box
                ~attrs:
                  [ Attr.test_id "grid"
                  ; Attr.on_child_activated (fun _ -> Ui_effect.Ignore)
                  ]
                ~selected:[]
                [ Node.label ~key:"a" "A" ]
            ; Node.list_box
                ~attrs:
                  [ Attr.test_id "rail"
                  ; Attr.on_row_activated (fun _ -> Ui_effect.Ignore)
                  ]
                ~selected:[]
                [ Node.label ~key:"a" "A" ]
            ]))
  in
  let handle = Bonsai_gtk_test.create app in
  Bonsai_gtk_test.Handle.recompute_view handle;
  Expect_test_helpers_core.require_does_raise (fun () ->
    Bonsai_gtk_test.Handle.do_actions handle [ Activate_row ("grid", "a") ]);
  [%expect {| (Failure "Bonsai_gtk_test: node grid is a FlowBox, not a ListBox") |}];
  Expect_test_helpers_core.require_does_raise (fun () ->
    Bonsai_gtk_test.Handle.do_actions handle [ Activate_child ("rail", "a") ]);
  [%expect {| (Failure "Bonsai_gtk_test: node rail is a ListBox, not a FlowBox") |}];
  (* Each on its own kind is fine. *)
  Bonsai_gtk_test.Handle.do_actions
    handle
    [ Activate_child ("grid", "a"); Activate_row ("rail", "a") ];
  Bonsai_gtk_test.Handle.recompute_view handle
;;

let%expect_test "a flow box action on a node with no handler fails" =
  let app (_graph @ local) =
    Bonsai.return
      (Node.window
         ~title:"bare"
         (Node.flow_box
            ~attrs:[ Attr.test_id "plain" ]
            ~selected:[]
            [ Node.label ~key:"a" "A" ]))
  in
  let handle = Bonsai_gtk_test.create app in
  Bonsai_gtk_test.Handle.recompute_view handle;
  Expect_test_helpers_core.require_does_raise (fun () ->
    Bonsai_gtk_test.Handle.do_actions handle [ Activate_child ("plain", "a") ]);
  [%expect
    {| (Failure "Bonsai_gtk_test: node plain has no on_child_activated handler") |}];
  Expect_test_helpers_core.require_does_raise (fun () ->
    Bonsai_gtk_test.Handle.do_actions handle [ Set_selection ("plain", [ "a" ]) ]);
  [%expect
    {|
    (Failure
     "Bonsai_gtk_test: node plain has no on_selected_children_changed handler")
    |}]
;;

(* The [Events] negative for the flow box's two signals. *)
let%expect_test "the flow box's event attrs are rejected on other kinds" =
  let bad attr (_graph @ local) =
    Bonsai.return (Node.window ~title:"bad" (Node.label ~attrs:[ attr ] "not a grid"))
  in
  Expect_test_helpers_core.require_does_raise (fun () ->
    let handle =
      Bonsai_gtk_test.create (bad (Attr.on_child_activated (fun _ -> Ui_effect.Ignore)))
    in
    Bonsai_gtk_test.Handle.show handle);
  [%expect {| (Invalid_argument "root/0: Label does not emit On_child_activated") |}];
  Expect_test_helpers_core.require_does_raise (fun () ->
    let handle =
      Bonsai_gtk_test.create
        (bad (Attr.on_selected_children_changed (fun _ -> Ui_effect.Ignore)))
    in
    Bonsai_gtk_test.Handle.show handle);
  [%expect
    {| (Invalid_argument "root/0: Label does not emit On_selected_children_changed") |}];
  (* And they are rejected on a *list box*, which is the near miss worth pinning: the two
     containers are alike enough that a copied line is a plausible mistake, and the two
     signals really are different GTK signals. *)
  let swapped (_graph @ local) =
    Bonsai.return
      (Node.window
         ~title:"bad"
         (Node.list_box
            ~attrs:[ Attr.on_child_activated (fun _ -> Ui_effect.Ignore) ]
            ~selected:[]
            []))
  in
  Expect_test_helpers_core.require_does_raise (fun () ->
    let handle = Bonsai_gtk_test.create swapped in
    Bonsai_gtk_test.Handle.show handle);
  [%expect {| (Invalid_argument "root/0: ListBox does not emit On_child_activated") |}]
;;

(* A flow box reads {i no} placement attrs, and that is a fact about GTK rather than a gap
   in this library: [GtkFlowBoxChild] has no [selectable] and no [activatable] -- the
   binding's whole surface for it is [set_child], [get_child], [get_index], [is_selected]
   and [changed] -- so there is nothing for a [flow_child_selectable] to write. The list
   box's two row attrs are therefore rejected on a flow box child, from the wildcard arm
   of [Placement.read_by]. *)
let%expect_test "the row attrs are rejected on a flow box child" =
  let bad attr (_graph @ local) =
    Bonsai.return
      (Node.window
         ~title:"bad"
         (Node.flow_box ~selected:[] [ Node.label ~key:"a" ~attrs:[ attr ] "A" ]))
  in
  Expect_test_helpers_core.require_does_raise (fun () ->
    let handle = Bonsai_gtk_test.create (bad (Attr.row_selectable false)) in
    Bonsai_gtk_test.Handle.show handle);
  [%expect
    {|
    (Invalid_argument
     "root/0/0: Attr.row_selectable is not read by FlowBox (a placement attribute is read by the container, and this one holds children for ListBox)")
    |}];
  Expect_test_helpers_core.require_does_raise (fun () ->
    let handle = Bonsai_gtk_test.create (bad (Attr.row_activatable false)) in
    Bonsai_gtk_test.Handle.show handle);
  [%expect
    {|
    (Invalid_argument
     "root/0/0: Attr.row_activatable is not read by FlowBox (a placement attribute is read by the container, and this one holds children for ListBox)")
    |}]
;;

(* The third keyed container, headless: a notebook whose current page is model state.
   [Set_page] is the user clicking a tab, and the model is free to decline it -- which is
   the whole of what "controlled" means and is what the live test then checks against the
   real widget. *)
let tabbed (graph @ local) =
  let page, set_page = Bonsai.state "score" graph in
  let%arr page and set_page in
  Node.window
    ~title:"Editor"
    (Node.notebook
       ~attrs:[ Attr.test_id "tabs"; Attr.on_page_changed set_page ]
       ~current_page:page
       [ Node.label ~key:"score" ~attrs:[ Attr.tab_label "Score" ] page
       ; Node.label ~key:"parts" ~attrs:[ Attr.tab_label "Parts" ] page
       ])
;;

let%expect_test "switching a notebook page hands the model the page's key" =
  let handle = Bonsai_gtk_test.create tabbed in
  Bonsai_gtk_test.Handle.show handle;
  [%expect
    {|
    ((kind (Window ((title (Editor))))) (attrs ())
     (children
      (Single
       (((kind (Notebook ((current_page score))))
         (attrs ((Test_id tabs) (On_page_changed <handler>)))
         (children
          (List
           (((kind (Label ((text score)))) (key score)
             (attrs ((Tab_label Score))) (children No_children))
            ((kind (Label ((text score)))) (key parts)
             (attrs ((Tab_label Parts))) (children No_children))))))))))
    |}];
  Bonsai_gtk_test.Handle.do_actions handle [ Set_page ("tabs", "parts") ];
  Bonsai_gtk_test.Handle.show_diff handle;
  [%expect
    {|
      ((kind (Window ((title (Editor))))) (attrs ())
       (children
        (Single
    -|   (((kind (Notebook ((current_page score))))
    +|   (((kind (Notebook ((current_page parts))))
           (attrs ((Test_id tabs) (On_page_changed <handler>)))
           (children
            (List
    -|       (((kind (Label ((text score)))) (key score)
    +|       (((kind (Label ((text parts)))) (key score)
               (attrs ((Tab_label Score))) (children No_children))
    -|        ((kind (Label ((text score)))) (key parts)
    +|        ((kind (Label ((text parts)))) (key parts)
               (attrs ((Tab_label Parts))) (children No_children))))))))))
    |}]
;;

(* A model that {i declines} the change renders the page it was already rendering, so the
   node is unchanged -- which headless is the whole of the claim, and live is the frame on
   which the notebook is put back. *)
let%expect_test "a declined page change leaves the node where it was" =
  (* The model has a real setter and refuses exactly one page, so the empty diff below is
     bracketed by two non-empty ones -- which is what tells "the model declined" apart
     from "the action never ran". Before the fix wave this model had no setter and a
     constant [Ui_effect.Ignore] handler, so replacing [Set_page]'s implementation with a
     no-op left the test green: the empty golden recorded only that the tree did not move.
     [test_handle.ml]'s date picker and text view were already written this way. *)
  let declining (graph @ local) =
    let page, set_page = Bonsai.state "score" graph in
    let%arr page and set_page in
    Node.window
      ~title:"Editor"
      (Node.notebook
         ~attrs:
           [ Attr.test_id "tabs"
             (* A tab the model will not leave the editor for -- the shape of a page with
                unsaved work, or one a licence gates. *)
           ; Attr.on_page_changed (fun key ->
               if String.equal key "settings" then Ui_effect.Ignore else set_page key)
           ]
         ~current_page:page
         [ Node.label ~key:"score" ~attrs:[ Attr.tab_label "Score" ] "S"
         ; Node.label ~key:"parts" ~attrs:[ Attr.tab_label "Parts" ] "P"
         ; Node.label ~key:"settings" ~attrs:[ Attr.tab_label "Settings" ] "C"
         ])
  in
  let handle = Bonsai_gtk_test.create declining in
  Bonsai_gtk_test.Handle.show handle;
  [%expect
    {|
    ((kind (Window ((title (Editor))))) (attrs ())
     (children
      (Single
       (((kind (Notebook ((current_page score))))
         (attrs ((Test_id tabs) (On_page_changed <handler>)))
         (children
          (List
           (((kind (Label ((text S)))) (key score) (attrs ((Tab_label Score)))
             (children No_children))
            ((kind (Label ((text P)))) (key parts) (attrs ((Tab_label Parts)))
             (children No_children))
            ((kind (Label ((text C)))) (key settings)
             (attrs ((Tab_label Settings))) (children No_children))))))))))
    |}];
  (* Accepted. *)
  Bonsai_gtk_test.Handle.do_actions handle [ Set_page ("tabs", "parts") ];
  Bonsai_gtk_test.Handle.show_diff handle;
  [%expect
    {|
      ((kind (Window ((title (Editor))))) (attrs ())
       (children
        (Single
    -|   (((kind (Notebook ((current_page score))))
    +|   (((kind (Notebook ((current_page parts))))
           (attrs ((Test_id tabs) (On_page_changed <handler>)))
           (children
            (List
             (((kind (Label ((text S)))) (key score) (attrs ((Tab_label Score)))
               (children No_children))
              ((kind (Label ((text P)))) (key parts) (attrs ((Tab_label Parts)))
               (children No_children))
              ((kind (Label ((text C)))) (key settings)
               (attrs ((Tab_label Settings))) (children No_children))))))))))
    |}];
  (* Declined: the handler ran, the model kept the page it had, and the node it renders is
     the one it rendered last frame. Live, this is the frame on which the notebook is
     showing the tab the user clicked and only the fixup pass puts it back. *)
  Bonsai_gtk_test.Handle.do_actions handle [ Set_page ("tabs", "settings") ];
  Bonsai_gtk_test.Handle.show_diff handle;
  [%expect {| |}];
  (* And the model is still live afterwards: a decline is not a wedge. *)
  Bonsai_gtk_test.Handle.do_actions handle [ Set_page ("tabs", "score") ];
  Bonsai_gtk_test.Handle.show_diff handle;
  [%expect
    {|
      ((kind (Window ((title (Editor))))) (attrs ())
       (children
        (Single
    -|   (((kind (Notebook ((current_page parts))))
    +|   (((kind (Notebook ((current_page score))))
           (attrs ((Test_id tabs) (On_page_changed <handler>)))
           (children
            (List
             (((kind (Label ((text S)))) (key score) (attrs ((Tab_label Score)))
               (children No_children))
              ((kind (Label ((text P)))) (key parts) (attrs ((Tab_label Parts)))
               (children No_children))
              ((kind (Label ((text C)))) (key settings)
               (attrs ((Tab_label Settings))) (children No_children))))))))))
    |}]
;;

(* [Set_page] names a kind, like the two activate actions and unlike [Set_selection]: a
   notebook shows exactly one page, so there is no shared question to fold into
   [Set_selection] and a copied line should fail loudly. *)
let%expect_test "a notebook action on the wrong kind, and on a node with no handler" =
  let app (_graph @ local) =
    Bonsai.return
      (Node.window
         ~title:"kinds"
         (Node.box
            ~orientation:Vertical
            [ Node.list_box
                ~attrs:
                  [ Attr.test_id "rail"
                  ; Attr.on_row_activated (fun _ -> Ui_effect.Ignore)
                  ]
                ~selected:[]
                [ Node.label ~key:"a" "A" ]
            ; Node.notebook
                ~attrs:[ Attr.test_id "plain" ]
                ~current_page:"a"
                [ Node.label ~key:"a" "A" ]
            ]))
  in
  let handle = Bonsai_gtk_test.create app in
  Bonsai_gtk_test.Handle.recompute_view handle;
  Expect_test_helpers_core.require_does_raise (fun () ->
    Bonsai_gtk_test.Handle.do_actions handle [ Set_page ("rail", "a") ]);
  [%expect {| (Failure "Bonsai_gtk_test: node rail is a ListBox, not a Notebook") |}];
  Expect_test_helpers_core.require_does_raise (fun () ->
    Bonsai_gtk_test.Handle.do_actions handle [ Set_page ("plain", "a") ]);
  [%expect {| (Failure "Bonsai_gtk_test: node plain has no on_page_changed handler") |}]
;;

(* The [Events] negative: [switch-page] is the notebook's own signal, so the attr is
   rejected everywhere else -- including on a {!Node.stack}, which is the near miss worth
   pinning, since a stack is the other container that shows exactly one child and emits
   [on_visible_child_changed] instead. *)
let%expect_test "the notebook's event attr is rejected on other kinds" =
  let bad node (_graph @ local) = Bonsai.return (Node.window ~title:"bad" node) in
  Expect_test_helpers_core.require_does_raise (fun () ->
    let handle =
      Bonsai_gtk_test.create
        (bad
           (Node.label
              ~attrs:[ Attr.on_page_changed (fun _ -> Ui_effect.Ignore) ]
              "not a notebook"))
    in
    Bonsai_gtk_test.Handle.show handle);
  [%expect {| (Invalid_argument "root/0: Label does not emit On_page_changed") |}];
  Expect_test_helpers_core.require_does_raise (fun () ->
    let handle =
      Bonsai_gtk_test.create
        (bad
           (Node.stack
              ~attrs:[ Attr.on_page_changed (fun _ -> Ui_effect.Ignore) ]
              ~name:"s"
              ~visible_child:"a"
              [ Node.label ~key:"a" "A" ]))
    in
    Bonsai_gtk_test.Handle.show handle);
  [%expect {| (Invalid_argument "root/0: Stack does not emit On_page_changed") |}];
  (* And the stack's own on a notebook, which is the same mistake the other way. *)
  Expect_test_helpers_core.require_does_raise (fun () ->
    let handle =
      Bonsai_gtk_test.create
        (bad
           (Node.notebook
              ~attrs:[ Attr.on_visible_child_changed (fun _ -> Ui_effect.Ignore) ]
              ~current_page:"a"
              [ Node.label ~key:"a" "A" ]))
    in
    Bonsai_gtk_test.Handle.show handle);
  [%expect
    {| (Invalid_argument "root/0: Notebook does not emit On_visible_child_changed") |}]
;;

(* The [Placement] negative, which is the sharper one: nothing applies [Attr.tab_label] to
   the page, so outside a notebook it is read by nobody and would have no diagnostic at
   all. The pair with {!Attr.page_title} is worth pinning in both directions -- the two
   attrs mean nearly the same thing to a reader and belong to two different containers. *)
let%expect_test "tab_label is rejected outside a notebook, and page_title inside one" =
  let bad node (_graph @ local) = Bonsai.return (Node.window ~title:"bad" node) in
  Expect_test_helpers_core.require_does_raise (fun () ->
    let handle =
      Bonsai_gtk_test.create
        (bad
           (Node.box
              ~orientation:Vertical
              [ Node.label ~attrs:[ Attr.tab_label "Score" ] "not a page" ]))
    in
    Bonsai_gtk_test.Handle.show handle);
  [%expect
    {|
    (Invalid_argument
     "root/0/0: Attr.tab_label is not read by Box (a placement attribute is read by the container, and this one holds children for Notebook)")
    |}];
  Expect_test_helpers_core.require_does_raise (fun () ->
    let handle =
      Bonsai_gtk_test.create
        (bad
           (Node.stack
              ~name:"s"
              ~visible_child:"a"
              [ Node.label ~key:"a" ~attrs:[ Attr.tab_label "Score" ] "A" ]))
    in
    Bonsai_gtk_test.Handle.show handle);
  [%expect
    {|
    (Invalid_argument
     "root/0/0: Attr.tab_label is not read by Stack (a placement attribute is read by the container, and this one holds children for Notebook)")
    |}];
  Expect_test_helpers_core.require_does_raise (fun () ->
    let handle =
      Bonsai_gtk_test.create
        (bad
           (Node.notebook
              ~current_page:"a"
              [ Node.label ~key:"a" ~attrs:[ Attr.page_title "Score" ] "A" ]))
    in
    Bonsai_gtk_test.Handle.show handle);
  [%expect
    {|
    (Invalid_argument
     "root/0/0: Attr.page_title is not read by Notebook (a placement attribute is read by the container, and this one holds children for Stack)")
    |}];
  (* ... and a notebook's own page carries it happily, which is what stops the checks
     above from being a name nothing satisfies. *)
  let handle =
    Bonsai_gtk_test.create
      (bad
         (Node.notebook
            ~current_page:"a"
            [ Node.label ~key:"a" ~attrs:[ Attr.tab_label "Score" ] "A" ]))
  in
  Bonsai_gtk_test.Handle.show handle;
  [%expect
    {|
    ((kind (Window ((title (bad))))) (attrs ())
     (children
      (Single
       (((kind (Notebook ((current_page a)))) (attrs ())
         (children
          (List
           (((kind (Label ((text A)))) (key a) (attrs ((Tab_label Score)))
             (children No_children))))))))))
    |}]
;;

(* The controlled buffer, headlessly. A model that refuses anything over ten characters:
   the state does not change, so the view does not change, so the {i only} thing that puts
   the widget back is [Widget_impl.reassert] -- which is what makes the second half of
   this the interesting test and not a formality. Headless there is no widget to put back,
   so what this pins is the node: a refused edit leaves it exactly where it was, and
   [test/live/live_text.ml] is where the same refusal is shown correcting a real
   [GtkTextBuffer].

   [Set_text] needs no new action for a text view. It means "the user made the text be
   this" and fires whatever [Attr.on_changed] the node carries, which is the same attr the
   entries use and the same one a [GtkTextBuffer]'s [changed] fills in live. *)
let notes (graph @ local) =
  let text, set_text = Bonsai.state "" graph in
  let%arr text and set_text in
  Node.window
    ~title:"Notes"
    (Node.text_view
       ~attrs:
         [ Attr.test_id "body"
         ; Attr.on_changed (fun s ->
             if String.length s <= 10 then set_text s else Ui_effect.Ignore)
         ]
       ~wrap:Word_char
       ~text
       ())
;;

let%expect_test "a text view's model accepts one edit and refuses the next" =
  let handle = Bonsai_gtk_test.create notes in
  Bonsai_gtk_test.Handle.show handle;
  [%expect
    {|
    ((kind (Window ((title (Notes))))) (attrs ())
     (children
      (Single
       (((kind (Text_view ((text "") (wrap Word_char))))
         (attrs ((Test_id body) (On_changed <handler>))) (children No_children))))))
    |}];
  Bonsai_gtk_test.Handle.do_actions handle [ Set_text ("body", "a note") ];
  Bonsai_gtk_test.Handle.show_diff handle;
  [%expect
    {|
      ((kind (Window ((title (Notes))))) (attrs ())
       (children
        (Single
    -|   (((kind (Text_view ((text "") (wrap Word_char))))
    +|   (((kind (Text_view ((text "a note") (wrap Word_char))))
           (attrs ((Test_id body) (On_changed <handler>))) (children No_children))))))
    |}];
  (* Eleven characters: the model declines, its state does not move, and the node it
     renders is the one it rendered last frame -- no diff at all. Live, this is the frame
     on which the buffer still holds the eleven the user typed and only [reassert] takes
     them out. *)
  Bonsai_gtk_test.Handle.do_actions handle [ Set_text ("body", "far too long") ];
  Bonsai_gtk_test.Handle.show_diff handle;
  [%expect {| |}];
  (* And the model is still live afterwards: a decline is not a wedge. *)
  Bonsai_gtk_test.Handle.do_actions handle [ Set_text ("body", "ok") ];
  Bonsai_gtk_test.Handle.show_diff handle;
  [%expect
    {|
      ((kind (Window ((title (Notes))))) (attrs ())
       (children
        (Single
    -|   (((kind (Text_view ((text "a note") (wrap Word_char))))
    +|   (((kind (Text_view ((text ok) (wrap Word_char))))
           (attrs ((Test_id body) (On_changed <handler>))) (children No_children))))))
    |}]
;;

(* The other event attrs a text view cannot emit. [On_activate] is the one worth naming:
   an entry has it and a text view does not -- Enter inserts a newline rather than
   submitting -- so it is exactly the line a reader copies across from an entry. *)
let%expect_test "a text view rejects the entry attrs it does not have" =
  List.iter
    [ Attr.on_activate Ui_effect.Ignore
    ; Attr.on_search_changed (fun _ -> Ui_effect.Ignore)
    ; Attr.on_toggled (fun _ -> Ui_effect.Ignore)
    ]
    ~f:(fun attr ->
      Expect_test_helpers_core.require_does_raise (fun () ->
        let handle =
          Bonsai_gtk_test.create (fun (_graph @ local) ->
            Bonsai.return
              (Node.window ~title:"n" (Node.text_view ~attrs:[ attr ] ~text:"" ())))
        in
        Bonsai_gtk_test.Handle.show handle));
  [%expect
    {|
    (Invalid_argument "root/0: TextView does not emit On_activate")
    (Invalid_argument "root/0: TextView does not emit On_search_changed")
    (Invalid_argument "root/0: TextView does not emit On_toggled")
    |}]
;;

(* The drop-down, headless. [Set_selected] is the user picking an item, and it carries an
   index rather than a key because a drop-down's items are props rather than children --
   the model already holds the list the index points into, and takes the string out of it
   itself, which is what the [tempo] state below is doing. *)
let tempos = [ "60"; "90"; "120"; "144" ]

let picker (graph @ local) =
  let selected, set_selected = Bonsai.state 2 graph in
  let%arr selected and set_selected in
  Node.window
    ~title:"Tempo"
    (Node.box
       ~orientation:Vertical
       [ Node.drop_down
           ~attrs:[ Attr.test_id "tempo"; Attr.on_selected_changed set_selected ]
           ~items:tempos
           ~selected
           ()
       ; Node.label (List.nth_exn tempos selected ^ " bpm")
       ])
;;

let%expect_test "choosing a drop-down item hands the model the index" =
  let handle = Bonsai_gtk_test.create picker in
  Bonsai_gtk_test.Handle.show handle;
  [%expect
    {|
    ((kind (Window ((title (Tempo))))) (attrs ())
     (children
      (Single
       (((kind (Box ((orientation Vertical)))) (attrs ())
         (children
          (List
           (((kind (Drop_down ((items (60 90 120 144)) (selected 2))))
             (attrs ((Test_id tempo) (On_selected_changed <handler>)))
             (children No_children))
            ((kind (Label ((text "120 bpm")))) (attrs ()) (children No_children))))))))))
    |}];
  Bonsai_gtk_test.Handle.do_actions handle [ Set_selected ("tempo", 0) ];
  Bonsai_gtk_test.Handle.show_diff handle;
  [%expect
    {|
      ((kind (Window ((title (Tempo))))) (attrs ())
       (children
        (Single
         (((kind (Box ((orientation Vertical)))) (attrs ())
           (children
            (List
    -|       (((kind (Drop_down ((items (60 90 120 144)) (selected 2))))
    +|       (((kind (Drop_down ((items (60 90 120 144)) (selected 0))))
               (attrs ((Test_id tempo) (On_selected_changed <handler>)))
               (children No_children))
    -|        ((kind (Label ((text "120 bpm")))) (attrs ()) (children No_children))))))))))
    +|        ((kind (Label ((text "60 bpm")))) (attrs ()) (children No_children))))))))))
    |}]
;;

(* A model that {i declines} the choice renders the index it was already rendering, so the
   node does not move -- which headless is the whole of the claim. Live, that same frame
   is the one where nothing is diffed at all and [Widget_impl.reassert] is the only thing
   left to put the widget back; [test/live/live_text.ml] makes that half. *)
let%expect_test "a declined drop-down choice leaves the node where it was" =
  (* A real setter that refuses one index, so the empty diff is bracketed by two non-empty
     ones. Written this way for the reason the notebook's twin above is: with a constant
     [Ui_effect.Ignore] handler and no setter, an empty golden says only that the tree did
     not move, which a [Set_selected] that never ran would satisfy too. *)
  let declining (graph @ local) =
    let selected, set_selected = Bonsai.state 1 graph in
    let%arr selected and set_selected in
    Node.window
      ~title:"Tempo"
      (Node.drop_down
         ~attrs:
           [ Attr.test_id "tempo"
             (* 144 is the tempo this model will not take -- a limit the score imposes. *)
           ; Attr.on_selected_changed (fun i ->
               if i = 3 then Ui_effect.Ignore else set_selected i)
           ]
         ~items:tempos
         ~selected
         ())
  in
  let handle = Bonsai_gtk_test.create declining in
  Bonsai_gtk_test.Handle.show handle;
  [%expect
    {|
    ((kind (Window ((title (Tempo))))) (attrs ())
     (children
      (Single
       (((kind (Drop_down ((items (60 90 120 144)) (selected 1))))
         (attrs ((Test_id tempo) (On_selected_changed <handler>)))
         (children No_children))))))
    |}];
  (* Accepted. *)
  Bonsai_gtk_test.Handle.do_actions handle [ Set_selected ("tempo", 2) ];
  Bonsai_gtk_test.Handle.show_diff handle;
  [%expect
    {|
      ((kind (Window ((title (Tempo))))) (attrs ())
       (children
        (Single
    -|   (((kind (Drop_down ((items (60 90 120 144)) (selected 1))))
    +|   (((kind (Drop_down ((items (60 90 120 144)) (selected 2))))
           (attrs ((Test_id tempo) (On_selected_changed <handler>)))
           (children No_children))))))
    |}];
  (* Declined: the handler ran and chose to keep the index it had. *)
  Bonsai_gtk_test.Handle.do_actions handle [ Set_selected ("tempo", 3) ];
  Bonsai_gtk_test.Handle.show_diff handle;
  [%expect {| |}];
  (* Still live. *)
  Bonsai_gtk_test.Handle.do_actions handle [ Set_selected ("tempo", 0) ];
  Bonsai_gtk_test.Handle.show_diff handle;
  [%expect
    {|
      ((kind (Window ((title (Tempo))))) (attrs ())
       (children
        (Single
    -|   (((kind (Drop_down ((items (60 90 120 144)) (selected 2))))
    +|   (((kind (Drop_down ((items (60 90 120 144)) (selected 0))))
           (attrs ((Test_id tempo) (On_selected_changed <handler>)))
           (children No_children))))))
    |}]
;;

(* A model may render [-1] over a non-empty list and the constructor accepts it: it is a
   reasonable thing to ask (nothing chosen yet), and it is {i GTK} that declines it, at
   mount, with the node's path -- see [test/live/live_text.ml]. Headless there is no GTK,
   so what a suite can see here is that the node is legal and that the handler still
   reaches the model. That asymmetry is worth pinning: it is one of the six places where a
   headless suite going green does not mean the runtime will hold the state -- this
   comment used to call it the only one, and the backlog called a different case the only
   one, which is how two mutually exclusive superlatives ended up in one repository. The
   list lives on [Bonsai_gtk_test.create], once. This case is on the deliberate half of
   it, and the runtime says so out loud rather than silently. *)
let%expect_test "nothing selected is a legal node, whatever GTK does with it" =
  let unset (graph @ local) =
    let selected, set_selected = Bonsai.state (-1) graph in
    let%arr selected and set_selected in
    Node.window
      ~title:"Tempo"
      (Node.drop_down
         ~attrs:[ Attr.test_id "tempo"; Attr.on_selected_changed set_selected ]
         ~items:tempos
         ~selected
         ())
  in
  let handle = Bonsai_gtk_test.create unset in
  Bonsai_gtk_test.Handle.show handle;
  [%expect
    {|
    ((kind (Window ((title (Tempo))))) (attrs ())
     (children
      (Single
       (((kind (Drop_down ((items (60 90 120 144)) (selected -1))))
         (attrs ((Test_id tempo) (On_selected_changed <handler>)))
         (children No_children))))))
    |}];
  Bonsai_gtk_test.Handle.do_actions handle [ Set_selected ("tempo", 3) ];
  Bonsai_gtk_test.Handle.show_diff handle;
  [%expect
    {|
      ((kind (Window ((title (Tempo))))) (attrs ())
       (children
        (Single
    -|   (((kind (Drop_down ((items (60 90 120 144)) (selected -1))))
    +|   (((kind (Drop_down ((items (60 90 120 144)) (selected 3))))
           (attrs ((Test_id tempo) (On_selected_changed <handler>)))
           (children No_children))))))
    |}];
  (* The second instance of the same asymmetry, next to the first (task-10-review.md R2).
     An index {i past the end} is a legal node too -- the constructor accepts it by
     design, because [~items] and [~selected] come from different Bonsai state and a
     shrinking list leaves the index stale for a frame -- and headless it produces no
     signal at all: [Events] has nothing to say about it and there is no list model to
     ask. Only the live runtime reports it, once, with the node's path. *)
  let handle =
    Bonsai_gtk_test.create (fun (_graph @ local) ->
      Bonsai.return
        (Node.window
           ~title:"Tempo"
           (Node.drop_down ~attrs:[ Attr.test_id "tempo" ] ~items:tempos ~selected:9 ())))
  in
  Bonsai_gtk_test.Handle.show handle;
  [%expect
    {|
    ((kind (Window ((title (Tempo))))) (attrs ())
     (children
      (Single
       (((kind (Drop_down ((items (60 90 120 144)) (selected 9))))
         (attrs ((Test_id tempo))) (children No_children))))))
    |}]
;;

(* [Set_selected] names a kind, like [Set_page] and the two activate actions: a
   drop-down's selection is an index into its own props, so there is nothing to share with
   the containers' key-based selections and a line copied from one should fail loudly. *)
let%expect_test "a drop-down action on the wrong kind, and on a node with no handler" =
  let app (_graph @ local) =
    Bonsai.return
      (Node.window
         ~title:"kinds"
         (Node.box
            ~orientation:Vertical
            [ Node.list_box
                ~attrs:
                  [ Attr.test_id "rail"
                  ; Attr.on_row_activated (fun _ -> Ui_effect.Ignore)
                  ]
                ~selected:[]
                [ Node.label ~key:"a" "A" ]
            ; Node.drop_down ~attrs:[ Attr.test_id "plain" ] ~items:[ "a" ] ~selected:0 ()
            ]))
  in
  let handle = Bonsai_gtk_test.create app in
  Bonsai_gtk_test.Handle.recompute_view handle;
  Expect_test_helpers_core.require_does_raise (fun () ->
    Bonsai_gtk_test.Handle.do_actions handle [ Set_selected ("rail", 0) ]);
  [%expect {| (Failure "Bonsai_gtk_test: node rail is a ListBox, not a DropDown") |}];
  Expect_test_helpers_core.require_does_raise (fun () ->
    Bonsai_gtk_test.Handle.do_actions handle [ Set_selected ("plain", 0) ]);
  [%expect
    {| (Failure "Bonsai_gtk_test: node plain has no on_selected_changed handler") |}]
;;

(* The [Events] negatives, both directions. [notify::selected] is the drop-down's alone,
   so the attr is rejected everywhere else -- including on a {!Node.stack} and a
   {!Node.list_box}, the two near misses, since all three are "one of these is showing"
   controls whose handlers are spelled differently. And a drop-down emits none of theirs. *)
let%expect_test "the drop-down's event attr, and other kinds'" =
  let bad node (_graph @ local) = Bonsai.return (Node.window ~title:"bad" node) in
  let refuse node =
    Expect_test_helpers_core.require_does_raise (fun () ->
      let handle = Bonsai_gtk_test.create (bad node) in
      Bonsai_gtk_test.Handle.show handle)
  in
  let picked = Attr.on_selected_changed (fun _ -> Ui_effect.Ignore) in
  refuse (Node.label ~attrs:[ picked ] "x");
  refuse (Node.stack ~attrs:[ picked ] ~name:"s" ~visible_child:"a" []);
  refuse (Node.list_box ~attrs:[ picked ] ~selected:[] []);
  [%expect
    {|
    (Invalid_argument "root/0: Label does not emit On_selected_changed")
    (Invalid_argument "root/0: Stack does not emit On_selected_changed")
    (Invalid_argument "root/0: ListBox does not emit On_selected_changed")
    |}];
  List.iter
    [ Attr.on_visible_child_changed (fun _ -> Ui_effect.Ignore)
    ; Attr.on_selected_rows_changed (fun _ -> Ui_effect.Ignore)
    ; Attr.on_page_changed (fun _ -> Ui_effect.Ignore)
    ; Attr.on_activate Ui_effect.Ignore
    ]
    ~f:(fun attr -> refuse (Node.drop_down ~attrs:[ attr ] ~items:[ "a" ] ~selected:0 ()));
  [%expect
    {|
    (Invalid_argument "root/0: DropDown does not emit On_visible_child_changed")
    (Invalid_argument "root/0: DropDown does not emit On_selected_rows_changed")
    (Invalid_argument "root/0: DropDown does not emit On_page_changed")
    (Invalid_argument "root/0: DropDown does not emit On_activate")
    |}];
  (* And the level bar, which emits nothing at all: it has no interaction, so every event
     attr on one is a mistake. *)
  refuse
    (Node.level_bar
       ~attrs:[ Attr.on_value_changed (fun _ -> Ui_effect.Ignore) ]
       ~value:0.5
       ());
  refuse (Node.level_bar ~attrs:[ picked ] ~value:0.5 ());
  [%expect
    {|
    (Invalid_argument "root/0: LevelBar does not emit On_value_changed")
    (Invalid_argument "root/0: LevelBar does not emit On_selected_changed")
    |}]
;;

(* A date picker whose model will not accept a weekend, which is the declined-edit shape
   for a calendar and which no other test in this suite has. The two other declining
   models here are a drop-down refusing an odd index and a text view rewriting text; a
   date is the case where the {i value} the user produced is legal and the {i model} is
   the only thing that can say no.

   Headless this is the whole claim: the handler runs, the model keeps the Friday, and the
   node does not move. Live it is the harder half -- the frame Bonsai runs hands back the
   physically same node, so nothing is diffed and [Widget_impl.reassert] is the only thing
   that can put the calendar back; [test/live/live_text.ml] makes that one. *)
let%expect_test "a date picker that declines weekends" =
  let picker (graph @ local) =
    let date, set_date = Bonsai.state (Date.of_string "2026-08-28") graph in
    let%arr date and set_date in
    Node.window
      ~title:"When"
      (Node.box
         ~orientation:Vertical
         [ Node.calendar
             ~attrs:
               [ Attr.test_id "when"
               ; Attr.on_day_selected (fun d ->
                   match Date.day_of_week d with
                   | Sat | Sun -> Ui_effect.Ignore
                   | Mon | Tue | Wed | Thu | Fri -> set_date d)
               ]
             ~marked_days:[ 28 ]
             ~date
             ()
         ; Node.label
             ~attrs:[ Attr.test_id "chosen" ]
             (sprintf !"%{Date} is a %{sexp: Day_of_week.t}" date (Date.day_of_week date))
         ])
  in
  let handle = Bonsai_gtk_test.create picker in
  Bonsai_gtk_test.Handle.show handle;
  [%expect
    {|
    ((kind (Window ((title (When))))) (attrs ())
     (children
      (Single
       (((kind (Box ((orientation Vertical)))) (attrs ())
         (children
          (List
           (((kind (Calendar ((date 2026-08-28) (marked_days (28)))))
             (attrs ((Test_id when) (On_day_selected <handler>)))
             (children No_children))
            ((kind (Label ((text "2026-08-28 is a FRI"))))
             (attrs ((Test_id chosen))) (children No_children))))))))))
    |}];
  (* A weekday: taken. *)
  Bonsai_gtk_test.Handle.do_actions
    handle
    [ Select_day ("when", Date.of_string "2026-08-31") ];
  Bonsai_gtk_test.Handle.show_diff handle;
  [%expect
    {|
      ((kind (Window ((title (When))))) (attrs ())
       (children
        (Single
         (((kind (Box ((orientation Vertical)))) (attrs ())
           (children
            (List
    -|       (((kind (Calendar ((date 2026-08-28) (marked_days (28)))))
    +|       (((kind (Calendar ((date 2026-08-31) (marked_days (28)))))
               (attrs ((Test_id when) (On_day_selected <handler>)))
               (children No_children))
    -|        ((kind (Label ((text "2026-08-28 is a FRI"))))
    +|        ((kind (Label ((text "2026-08-31 is a MON"))))
               (attrs ((Test_id chosen))) (children No_children))))))))))
    |}];
  (* The Saturday after it: declined, and the node does not move at all -- which is what
     makes the live frame a no-diff one. *)
  Bonsai_gtk_test.Handle.do_actions
    handle
    [ Select_day ("when", Date.of_string "2026-09-05") ];
  Bonsai_gtk_test.Handle.show_diff handle;
  [%expect {| |}];
  (* And December, because January is the month a zero-based conversion gets right by
     accident. Nothing in the vtree can convert anything, which is the point: the date the
     handler was handed is the date the model holds. *)
  Bonsai_gtk_test.Handle.do_actions
    handle
    [ Select_day ("when", Date.of_string "2026-12-31") ];
  Bonsai_gtk_test.Handle.show_diff handle;
  [%expect
    {|
      ((kind (Window ((title (When))))) (attrs ())
       (children
        (Single
         (((kind (Box ((orientation Vertical)))) (attrs ())
           (children
            (List
    -|       (((kind (Calendar ((date 2026-08-31) (marked_days (28)))))
    +|       (((kind (Calendar ((date 2026-12-31) (marked_days (28)))))
               (attrs ((Test_id when) (On_day_selected <handler>)))
               (children No_children))
    -|        ((kind (Label ((text "2026-08-31 is a MON"))))
    +|        ((kind (Label ((text "2026-12-31 is a THU"))))
               (attrs ((Test_id chosen))) (children No_children))))))))))
    |}]
;;

(* The editable label's two controlled props, and the asymmetry between them.

   The text arrives through [Set_text] because live it arrives through [Attr.on_changed]
   -- a [GtkEditableLabel] reaches its text through [GtkEditable] exactly as an entry does
   -- and the mode arrives through [Set_editing], which live is a [notify::editing] rather
   than a signal at all. A model that trims what it is given is the declining shape for
   the text half. *)
let%expect_test "an editable label's text and its editing mode" =
  let titled (graph @ local) =
    let title, set_title = Bonsai.state "Set One" graph in
    let editing, set_editing = Bonsai.state false graph in
    let%arr title and set_title and editing and set_editing in
    Node.window
      ~title:"Setlist"
      (Node.editable_label
         ~attrs:
           [ Attr.test_id "title"
           ; Attr.on_changed (fun t -> set_title (String.strip t))
           ; Attr.on_editing_changed set_editing
           ]
         ~editing
         ~text:title
         ())
  in
  let handle = Bonsai_gtk_test.create titled in
  Bonsai_gtk_test.Handle.show handle;
  [%expect
    {|
    ((kind (Window ((title (Setlist))))) (attrs ())
     (children
      (Single
       (((kind (Editable_label ((text "Set One") (editing false))))
         (attrs
          ((Test_id title) (On_changed <handler>) (On_editing_changed <handler>)))
         (children No_children))))))
    |}];
  (* The user double-clicks: editing becomes true and the text has not moved. *)
  Bonsai_gtk_test.Handle.do_actions handle [ Set_editing ("title", true) ];
  Bonsai_gtk_test.Handle.show_diff handle;
  [%expect
    {|
      ((kind (Window ((title (Setlist))))) (attrs ())
       (children
        (Single
    -|   (((kind (Editable_label ((text "Set One") (editing false))))
    +|   (((kind (Editable_label ((text "Set One") (editing true))))
           (attrs
            ((Test_id title) (On_changed <handler>) (On_editing_changed <handler>)))
           (children No_children))))))
    |}];
  (* Typing, which live is one [changed] per keystroke on the [GtkEditable]. *)
  Bonsai_gtk_test.Handle.do_actions handle [ Set_text ("title", "Set Two  ") ];
  Bonsai_gtk_test.Handle.show_diff handle;
  [%expect
    {|
      ((kind (Window ((title (Setlist))))) (attrs ())
       (children
        (Single
    -|   (((kind (Editable_label ((text "Set One") (editing true))))
    +|   (((kind (Editable_label ((text "Set Two") (editing true))))
           (attrs
            ((Test_id title) (On_changed <handler>) (On_editing_changed <handler>)))
           (children No_children))))))
    |}];
  (* Leaving editing mode. The model's [~editing:false] is what the widget is then made to
     obey, and live that is [stop_editing ~commit:true] -- the text the user typed is
     {i kept}, which it must be: the model has already seen it above and accepted the
     trimmed form. *)
  Bonsai_gtk_test.Handle.do_actions handle [ Set_editing ("title", false) ];
  Bonsai_gtk_test.Handle.show_diff handle;
  [%expect
    {|
      ((kind (Window ((title (Setlist))))) (attrs ())
       (children
        (Single
    -|   (((kind (Editable_label ((text "Set Two") (editing true))))
    +|   (((kind (Editable_label ((text "Set Two") (editing false))))
           (attrs
            ((Test_id title) (On_changed <handler>) (On_editing_changed <handler>)))
           (children No_children))))))
    |}]
;;

(* The text view's caret as an event: [Move_cursor] delivers the offset the user put the
   caret at, and the model owns it from there. Headless there is no buffer to clamp
   against -- the mli says so -- and what a test can show is the handler's decision. *)
let%expect_test "a Move_cursor action fires on_cursor_moved" =
  let app (graph @ local) =
    let caret, set_caret = Bonsai.state 0 graph in
    let%arr caret and set_caret in
    Node.window
      ~title:"caret"
      (Node.box
         ~orientation:Vertical
         [ Node.text_view
             ~attrs:[ Attr.test_id "note"; Attr.on_cursor_moved set_caret ]
             ~text:"hello world"
             ()
         ; Node.label ~attrs:[ Attr.test_id "at" ] (sprintf "caret at %d" caret)
         ])
  in
  let handle = Bonsai_gtk_test.create app in
  Bonsai_gtk_test.Handle.store_view handle;
  Bonsai_gtk_test.Handle.do_actions handle [ Move_cursor ("note", 5) ];
  Bonsai_gtk_test.Handle.show_diff handle;
  [%expect
    {|
      ((kind (Window ((title (caret))))) (attrs ())
       (children
        (Single
         (((kind (Box ((orientation Vertical)))) (attrs ())
           (children
            (List
             (((kind (Text_view ((text "hello world"))))
               (attrs ((Test_id note) (On_cursor_moved <handler>)))
               (children No_children))
    -|        ((kind (Label ((text "caret at 0")))) (attrs ((Test_id at)))
    +|        ((kind (Label ((text "caret at 5")))) (attrs ((Test_id at)))
               (children No_children))))))))))
    |}];
  (* Aimed at anything that is not a text view, it names what it found. *)
  let wrong (_graph @ local) =
    Bonsai.return
      (Node.window ~title:"caret" (Node.label ~attrs:[ Attr.test_id "plain" ] "plain"))
  in
  let handle = Bonsai_gtk_test.create wrong in
  Bonsai_gtk_test.Handle.recompute_view handle;
  (match Bonsai_gtk_test.Handle.do_actions handle [ Move_cursor ("plain", 3) ] with
   | () -> print_s [%sexp "fired"]
   | exception e -> printf "%s\n" (Exn.to_string e));
  [%expect {| (Failure "Bonsai_gtk_test: node plain is a Label, not a TextView") |}]
;;

(* The popover's one legal position, refused headlessly with the mount-time strings: a
   popover anywhere but a menu button's ~popover slot is a tree the runtime rejects, and
   this is what stops a headless suite certifying it. *)
let%expect_test "a popover outside a menu button is rejected by the handle" =
  let in_box (_graph @ local) =
    Bonsai.return
      (Node.window
         ~title:"pop"
         (Node.box ~orientation:Vertical [ Node.popover (Node.label "body") ]))
  in
  Expect_test_helpers_core.require_does_raise (fun () ->
    let handle = Bonsai_gtk_test.create in_box in
    Bonsai_gtk_test.Handle.recompute_view handle);
  [%expect
    {|
    (Invalid_argument
     "root/0/0: a Node.popover may only be a Node.menu_button's ~popover slot, not a child of Box")
    |}];
  let at_root (_graph @ local) = Bonsai.return (Node.popover (Node.label "body")) in
  Expect_test_helpers_core.require_does_raise (fun () ->
    let handle = Bonsai_gtk_test.create ~root_kind:`Not_window at_root in
    Bonsai_gtk_test.Handle.recompute_view handle);
  [%expect
    {|
    (Invalid_argument
     "root: a Node.popover may only be a Node.menu_button's ~popover slot, not the root")
    |}]
;;

(* The converse hole the review found: the constructor rejects a non-popover in the
   ~popover slot, but a tree assembled by record update never ran the constructor -- and
   the runtime would hand the impostor to set_popover through an unchecked downcast. The
   walk is the backstop, with the runtime's string, so the handle cannot certify what GTK
   would crash on. *)
let%expect_test "a non-popover smuggled into the slot by record update is rejected" =
  let smuggled =
    let mb = Node.menu_button ~label:"menu" () in
    { mb with children = Children.Slots [ "popover", Single (Some (Node.label "x")) ] }
  in
  let app (_graph @ local) = Bonsai.return (Node.window ~title:"pop" smuggled) in
  Expect_test_helpers_core.require_does_raise (fun () ->
    let handle = Bonsai_gtk_test.create app in
    Bonsai_gtk_test.Handle.recompute_view handle);
  [%expect
    {|
    (Invalid_argument
     "root/0/popover/0: Node.menu_button's ~popover slot must hold a Node.popover, not a Label")
    |}]
;;

(* The action system, headless (M3 Task 6): [Activate_action] reaches the right handler; a
   radio's target rides the reference; and a toggle's checkmark is the controlled story --
   an activation moves nothing until the model's next render does. *)
let%expect_test "actions activate, radios carry targets, toggles stay controlled" =
  let app (graph @ local) =
    let log, set_log = Bonsai.state [] graph in
    let dark, (_ : (bool -> unit Ui_effect.t) Bonsai.t) = Bonsai.state false graph in
    let%arr log and set_log and dark in
    Node.window
      ~title:"actions"
      (Node.box
         ~orientation:Vertical
         ~attrs:
           [ Attr.test_id "holder"
           ; Attr.actions
               ~scope:"app"
               [ Action_spec.simple ~name:"ping" (set_log ("ping" :: log))
               ; Action_spec.toggle
                   ~name:"dark"
                   ~state:dark
                   (set_log (sprintf "dark-requested (now %b)" dark :: log))
               ; Action_spec.radio ~name:"theme" ~state:"light" (fun target ->
                   set_log (("theme:" ^ target) :: log))
               ]
           ]
         [ Node.menu_button
             ~label:"menu"
             ~menu:
               [ Menu.item ~label:"Ping" ~action:"app.ping" ~accel:"<Control>p" ()
               ; Menu.item ~label:"Dark" ~action:"app.dark" ()
               ; Menu.item ~label:"Solar" ~action:"app.theme::solar" ()
               ]
             ()
         ; Node.label ~attrs:[ Attr.test_id "log" ] (String.concat ~sep:"," log)
         ])
  in
  let handle = Bonsai_gtk_test.create app in
  Bonsai_gtk_test.Handle.store_view handle;
  Bonsai_gtk_test.Handle.do_actions handle [ Activate_action ("holder", "app.ping") ];
  Bonsai_gtk_test.Handle.recompute_view handle;
  Bonsai_gtk_test.Handle.do_actions
    handle
    [ Activate_action ("holder", "app.theme::solar") ];
  Bonsai_gtk_test.Handle.recompute_view handle;
  (* The toggle: the activation is a request. The model here logs it and does not move
     [dark], so the spec's [state] stays [false] -- the declined checkmark. *)
  Bonsai_gtk_test.Handle.do_actions handle [ Activate_action ("holder", "app.dark") ];
  Bonsai_gtk_test.Handle.show_diff handle;
  [%expect
    {|
            ((Actions (scope app)
              (specs
               (((name ping) (Simple <effect>))
                ((name dark) (Toggle ((state false))))
                ((name theme) (Radio ((state light)))))))
             (Test_id holder)))
           (children
            (List
             (((kind
                (Menu_button
                 ((label (menu))
                  (menu
                   (((Item ((label Ping) (action app.ping) (accel (<Control>p))))
                     (Item ((label Dark) (action app.dark) (accel ())))
                     (Item ((label Solar) (action app.theme::solar) (accel ())))))))))
               (attrs ()) (children (Slots ((popover (Single ()))))))
    -|        ((kind (Label ((text "")))) (attrs ((Test_id log)))
    -|         (children No_children))))))))))
    +|        ((kind
    +|          (Label ((text "dark-requested (now false),theme:solar,ping"))))
    +|         (attrs ((Test_id log))) (children No_children))))))))))
    |}]
;;

(* A menu naming an action nobody provides is rejected headlessly with the runtime's
   string -- the walk is one function in vtree, so the two cannot drift. *)
let%expect_test "a dangling menu action reference is rejected by the handle" =
  let app (_graph @ local) =
    Bonsai.return
      (Node.window
         ~title:"dangling"
         (Node.menu_button
            ~label:"menu"
            ~menu:[ Menu.item ~label:"Lost" ~action:"app.missing" () ]
            ()))
  in
  Expect_test_helpers_core.require_does_raise (fun () ->
    let handle = Bonsai_gtk_test.create app in
    Bonsai_gtk_test.Handle.recompute_view handle);
  [%expect
    {|
    (Invalid_argument
     "root/0: menu item action \"app.missing\" resolves to no Attr.actions here or on an ancestor (scopes in reach: none)")
    |}]
;;

(* The popover's controlled ~open_ from the model's side: Close_popover fires
   [Attr.on_closed] and the model that follows flips [open_]; Open_popover fires nothing
   (live, opening emits nothing this library exposes), so the prop stands wherever the
   model holds it -- the headless face of the next-frame popdown. *)
let%expect_test "popover actions: a dismissal is heard, an opening is not" =
  let app (graph @ local) =
    let open_, set_open = Bonsai.state true graph in
    let%arr open_ and set_open in
    Node.window
      ~title:"pop"
      (Node.menu_button
         ~label:"menu"
         ~popover:
           (Node.popover
              ~open_
              ~attrs:[ Attr.test_id "pop"; Attr.on_closed (set_open false) ]
              (Node.label "body"))
         ())
  in
  let handle = Bonsai_gtk_test.create app in
  Bonsai_gtk_test.Handle.store_view handle;
  (* The user opened it? Nothing to hear; with the model already holding [true] the diff
     is empty. *)
  Bonsai_gtk_test.Handle.do_actions handle [ Open_popover "pop" ];
  Bonsai_gtk_test.Handle.show_diff handle;
  [%expect {| |}];
  (* The user dismissed it: on_closed fires, the model follows, open_ flips. *)
  Bonsai_gtk_test.Handle.do_actions handle [ Close_popover "pop" ];
  Bonsai_gtk_test.Handle.show_diff handle;
  [%expect
    {|
      ((kind (Window ((title (pop))))) (attrs ())
       (children
        (Single
         (((kind (Menu_button ((label (menu))))) (attrs ())
           (children
            (Slots
             ((popover
               (Single
    -|          (((kind (Popover ((open_ true))))
    +|          (((kind (Popover ((open_ false))))
                  (attrs ((Test_id pop) (On_closed <handler>)))
                  (children
                   (Single
                    (((kind (Label ((text body)))) (attrs ())
                      (children No_children)))))))))))))))))
    |}]
;;

(* The negatives for the two new kinds, both directions, on the rule the drop-down block
   above follows: an attr copied onto a widget that does not emit it is rejected rather
   than accepted and never firing.

   [On_changed] is the interesting near miss and it goes the other way from the rest: an
   editable label {i does} emit it, because it reaches its text through the same
   [GtkEditable] an entry does, so the line a reader copies across from an entry works. A
   calendar does not. *)
let%expect_test "the calendar's and the editable label's event attrs, and other kinds'" =
  let bad node (_graph @ local) = Bonsai.return (Node.window ~title:"bad" node) in
  let refuse node =
    Expect_test_helpers_core.require_does_raise (fun () ->
      let handle = Bonsai_gtk_test.create (bad node) in
      Bonsai_gtk_test.Handle.show handle)
  in
  let day = Attr.on_day_selected (fun _ -> Ui_effect.Ignore) in
  let mode = Attr.on_editing_changed (fun _ -> Ui_effect.Ignore) in
  let changed = Attr.on_changed (fun _ -> Ui_effect.Ignore) in
  let date = Date.of_string "2026-08-30" in
  refuse (Node.label ~attrs:[ day ] "x");
  refuse (Node.entry ~attrs:[ day ] ~text:"" ());
  refuse (Node.editable_label ~attrs:[ day ] ~text:"" ());
  [%expect
    {|
    (Invalid_argument "root/0: Label does not emit On_day_selected")
    (Invalid_argument "root/0: Entry does not emit On_day_selected")
    (Invalid_argument "root/0: EditableLabel does not emit On_day_selected")
    |}];
  refuse (Node.label ~attrs:[ mode ] "x");
  refuse (Node.entry ~attrs:[ mode ] ~text:"" ());
  refuse (Node.calendar ~attrs:[ mode ] ~date ());
  [%expect
    {|
    (Invalid_argument "root/0: Label does not emit On_editing_changed")
    (Invalid_argument "root/0: Entry does not emit On_editing_changed")
    (Invalid_argument "root/0: Calendar does not emit On_editing_changed")
    |}];
  (* And what a calendar does not emit, including the two an author reaches for first. *)
  List.iter
    [ changed
    ; Attr.on_value_changed (fun _ -> Ui_effect.Ignore)
    ; Attr.on_selected_changed (fun _ -> Ui_effect.Ignore)
    ]
    ~f:(fun attr -> refuse (Node.calendar ~attrs:[ attr ] ~date ()));
  [%expect
    {|
    (Invalid_argument "root/0: Calendar does not emit On_changed")
    (Invalid_argument "root/0: Calendar does not emit On_value_changed")
    (Invalid_argument "root/0: Calendar does not emit On_selected_changed")
    |}];
  (* An editable label emits [changed], so this is the one line in the block that must
     {i not} raise. *)
  let handle =
    Bonsai_gtk_test.create
      (bad (Node.editable_label ~attrs:[ changed; mode ] ~text:"t" ()))
  in
  Bonsai_gtk_test.Handle.show handle;
  [%expect
    {|
    ((kind (Window ((title (bad))))) (attrs ())
     (children
      (Single
       (((kind (Editable_label ((text t) (editing false))))
         (attrs ((On_changed <handler>) (On_editing_changed <handler>)))
         (children No_children))))))
    |}]
;;

(* ------------------------------------------------------------------------------------ *)

(* The three structural rules the fix wave taught the handle, all decidable from pure
   vtree data and all previously listed in the mli as things only a mount could catch.

   Each is checked against the runtime's own message: the patcher's and the driver's
   strings are copied into [Bonsai_gtk_test] rather than shared (the test library cannot
   link [bonsai_gtk], which is what keeps it and the view functions written against it
   free of ocgtk), so these goldens are what keeps the two spellings the same. *)

let%expect_test "the root must be the kind the entry point requires" =
  let box_root (_graph @ local) =
    Bonsai.return (Node.box ~orientation:Vertical [ Node.label "x" ])
  in
  let window_root (_graph @ local) =
    Bonsai.return (Node.window ~title:"W" (Node.label "x"))
  in
  (* The default is [`Window], mirroring [Driver.create]'s, because that is what
     [Bonsai_gtk.start] requires. This is the mistake the report called the most likely to
     reach a running app: the window forgotten, or lost in a refactor that hoisted the
     root into a component. Headless it renders a complete and correct-looking tree; live
     it raises out of the first frame and marks the driver broken for good. *)
  Expect_test_helpers_core.require_does_raise (fun () ->
    let handle = Bonsai_gtk_test.create box_root in
    Bonsai_gtk_test.Handle.show handle);
  [%expect
    {|
    (Invalid_argument
     "Bonsai_gtk: the root node must be a Node.window, got Box. A tree started this way shows its own root, and a GtkWindow is the only thing GTK can show on its own. Use Bonsai_gtk.Expert.embed for a tree parented into a container you already own.")
    |}];
  (* And the mirror image, which is the rule for a component destined for [Expert.embed]:
     a [GtkWindow] is a toplevel that cannot be parented at all. *)
  Expect_test_helpers_core.require_does_raise (fun () ->
    let handle = Bonsai_gtk_test.create ~root_kind:`Not_window window_root in
    Bonsai_gtk_test.Handle.show handle);
  [%expect
    {|
    (Invalid_argument
     "Bonsai_gtk.embed: the root node is a Node.window, but an embedded tree is parented into a container the caller owns and a GtkWindow is a toplevel that cannot be parented. Use Bonsai_gtk.start for a tree that owns its window, or make the root a container.")
    |}];
  (* An embedded component with a container root is exactly what [embed] wants. *)
  let handle = Bonsai_gtk_test.create ~root_kind:`Not_window box_root in
  Bonsai_gtk_test.Handle.show handle;
  [%expect
    {|
    ((kind (Box ((orientation Vertical)))) (attrs ())
     (children
      (List (((kind (Label ((text x)))) (attrs ()) (children No_children))))))
    |}];
  (* The check reaches the entry points that print nothing, which is the property the
     shadowed [Handle] exists for: this one advances without ever building a view. *)
  Expect_test_helpers_core.require_does_raise (fun () ->
    let handle = Bonsai_gtk_test.create box_root in
    Bonsai_gtk_test.Handle.recompute_view handle);
  [%expect
    {|
    (Invalid_argument
     "Bonsai_gtk: the root node must be a Node.window, got Box. A tree started this way shows its own root, and a GtkWindow is the only thing GTK can show on its own. Use Bonsai_gtk.Expert.embed for a tree parented into a container you already own.")
    |}]
;;

let%expect_test "two siblings with one key, and a window below the root" =
  let show node =
    Expect_test_helpers_core.require_does_raise (fun () ->
      let handle = Bonsai_gtk_test.create (fun (_graph @ local) -> Bonsai.return node) in
      Bonsai_gtk_test.Handle.show handle)
  in
  (* [Reconcile.check_unique_keys], the same function [Patcher.mount_list] calls, under
     the container's path. Live this is caught at mount -- and for a [Node.stack] it
     matters more than it looks, since GTK would have been handed two pages with one name
     and [get_child_by_name] would already be ambiguous. *)
  show
    (Node.window
       ~title:"W"
       (Node.box
          ~orientation:Vertical
          [ Node.label ~key:"a" "one"; Node.label ~key:"a" "two" ]));
  [%expect
    {|
    (Invalid_argument
     "root/0: duplicate key a among one container's children (a key identifies a child among its siblings, so no two of them may share one)")
    |}];
  (* Through a slot, where the path is the slot's rather than the container's. *)
  show
    (Node.window
       ~title:"W"
       (Node.overlay
          ~overlays:[ Node.label ~key:"o" "one"; Node.label ~key:"o" "two" ]
          (Node.label "main")));
  [%expect
    {|
    (Invalid_argument
     "root/0/overlays: duplicate key o among one container's children (a key identifies a child among its siblings, so no two of them may share one)")
    |}];
  (* A [GtkWindow] is a toplevel: parenting one makes GTK log a critical and leaves a
     silently broken tree, so the patcher refuses it and now so does the handle. *)
  show
    (Node.window
       ~title:"outer"
       (Node.box ~orientation:Vertical [ Node.window ~title:"inner" (Node.label "x") ]));
  [%expect
    {|
    (Invalid_argument
     "root/0/0: a Node.window may only be the root node, not a child of another node")
    |}]
;;

(* ------------------------------------------------------------------------------------ *)

(* The three actions M2 shipped without. Each one fires a handler that no headless test
   could reach before -- the attrs sweep is satisfied by the attr appearing in a tree, and
   every handler sexps as [<handler>], so for these three there was no headless evidence
   of any kind that the right closure was behind the right name. *)

let%expect_test "Set_revealed, Set_position and Set_visible_child reach their handlers" =
  let app (graph @ local) =
    let revealed, set_revealed = Bonsai.state true graph in
    let position, set_position = Bonsai.state 120 graph in
    let page, set_page = Bonsai.state "score" graph in
    let%arr revealed
    and set_revealed
    and position
    and set_position
    and page
    and set_page in
    Node.window
      ~title:"Panels"
      (Node.box
         ~orientation:Vertical
         [ Node.revealer
             ~attrs:[ Attr.test_id "rev"; Attr.on_revealed set_revealed ]
             ~reveal:revealed
             (Node.label "hidden things")
         ; Node.paned
             ~attrs:[ Attr.test_id "split"; Attr.on_position_changed set_position ]
             ~position
             ~orientation:Horizontal
             ~start:(Node.label "left")
             ~end_:(Node.label "right")
             ()
         ; Node.stack
             ~attrs:[ Attr.test_id "pages"; Attr.on_visible_child_changed set_page ]
             ~name:"main"
             ~transition:None_
             ~visible_child:page
             [ Node.label ~key:"score" "S"; Node.label ~key:"parts" "P" ]
         ])
  in
  let handle = Bonsai_gtk_test.create app in
  Bonsai_gtk_test.Handle.show handle;
  [%expect
    {|
    ((kind (Window ((title (Panels))))) (attrs ())
     (children
      (Single
       (((kind (Box ((orientation Vertical)))) (attrs ())
         (children
          (List
           (((kind (Revealer ((reveal true))))
             (attrs ((Test_id rev) (On_revealed <handler>)))
             (children
              (Single
               (((kind (Label ((text "hidden things")))) (attrs ())
                 (children No_children))))))
            ((kind (Paned ((orientation Horizontal) (position (120)))))
             (attrs ((Test_id split) (On_position_changed <handler>)))
             (children
              (Slots
               ((start
                 (Single
                  (((kind (Label ((text left)))) (attrs ())
                    (children No_children)))))
                (end
                 (Single
                  (((kind (Label ((text right)))) (attrs ())
                    (children No_children)))))))))
            ((kind (Stack ((name main) (visible_child score))))
             (attrs ((Test_id pages) (On_visible_child_changed <handler>)))
             (children
              (List
               (((kind (Label ((text S)))) (key score) (attrs ())
                 (children No_children))
                ((kind (Label ((text P)))) (key parts) (attrs ())
                 (children No_children))))))))))))))
    |}];
  (* All three at once, and the diff is the whole claim: each handler ran, each was handed
     the value the action carried, and each model moved. Before these actions existed
     there was no way to make any of that happen headlessly. *)
  Bonsai_gtk_test.Handle.do_actions
    handle
    [ Set_revealed ("rev", false)
    ; Set_position ("split", 240)
    ; Set_visible_child ("pages", "parts")
    ];
  Bonsai_gtk_test.Handle.show_diff handle;
  [%expect
    {|
      ((kind (Window ((title (Panels))))) (attrs ())
       (children
        (Single
         (((kind (Box ((orientation Vertical)))) (attrs ())
           (children
            (List
    -|       (((kind (Revealer ((reveal true))))
    +|       (((kind (Revealer ((reveal false))))
               (attrs ((Test_id rev) (On_revealed <handler>)))
               (children
                (Single
                 (((kind (Label ((text "hidden things")))) (attrs ())
                   (children No_children))))))
    -|        ((kind (Paned ((orientation Horizontal) (position (120)))))
    +|        ((kind (Paned ((orientation Horizontal) (position (240)))))
               (attrs ((Test_id split) (On_position_changed <handler>)))
               (children
                (Slots
                 ((start
                   (Single
                    (((kind (Label ((text left)))) (attrs ())
                      (children No_children)))))
                  (end
                   (Single
                    (((kind (Label ((text right)))) (attrs ())
                      (children No_children)))))))))
    -|        ((kind (Stack ((name main) (visible_child score))))
    +|        ((kind (Stack ((name main) (visible_child parts))))
               (attrs ((Test_id pages) (On_visible_child_changed <handler>)))
               (children
                (List
                 (((kind (Label ((text S)))) (key score) (attrs ())
                   (children No_children))
                  ((kind (Label ((text P)))) (key parts) (attrs ())
                   (children No_children))))))))))))))
    |}]
;;
