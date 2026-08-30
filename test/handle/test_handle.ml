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
  let handle = Bonsai_gtk_test.create mislabelled in
  Bonsai_gtk_test.Handle.recompute_view handle;
  Expect_test_helpers_core.require_does_raise (fun () ->
    Bonsai_gtk_test.Handle.do_actions handle [ Toggle "lbl" ]);
  [%expect {| (Failure "Bonsai_gtk_test: Label (test_id lbl) has no toggle state") |}]
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
              [ Attr.on_click (fun _ -> Ui_effect.Ignore)
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
           (On_focus_enter <handler>)))
         (children No_children))))))
    |}]
;;

(* This is stavekeeper's [library_window.ml:166-185] in miniature -- middle click, or
   button 1 with shift, pops the piece out -- and it is the whole reason the payload
   carries [button] and [modifiers].

   The click is delivered to the *handler*, not through GTK: there is no synthetic click
   in the binding (see [test/live/live_controllers.ml]), so what a headless suite proves
   is the half an application actually writes. *)
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
                   set_log
                     (sprintf "b%d n%d shift=%b" e.button e.n_press e.modifiers.shift
                      :: log))
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
              ((Test_id target) (On_focus_enter <handler>)
               (On_focus_leave <handler>)))
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
                ((Test_id target) (On_focus_enter <handler>)
                 (On_focus_leave <handler>)))
               (children (Single ())))
    -|        ((kind (Label ((text "")))) (attrs ((Test_id log)))
    +|        ((kind (Label ((text leave,enter)))) (attrs ((Test_id log)))
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
   headless suite certifying it anyway: [Controllers.configure_key] and this handle both
   render [Events.key_phase_rejection], so the message is identical rather than merely
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
