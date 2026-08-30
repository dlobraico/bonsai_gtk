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
