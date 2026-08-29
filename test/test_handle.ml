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

let%expect_test "Set_text and Activate need the matching handler" =
  let handle = Bonsai_gtk_test.create shouty in
  Bonsai_gtk_test.Handle.recompute_view handle;
  Expect_test_helpers_core.require_does_raise (fun () ->
    Bonsai_gtk_test.Handle.do_actions handle [ Set_text ("echo", "x") ]);
  [%expect {| (Failure "Bonsai_gtk_test: node echo has no on_changed handler") |}];
  Expect_test_helpers_core.require_does_raise (fun () ->
    Bonsai_gtk_test.Handle.do_actions handle [ Activate "echo" ]);
  [%expect {| (Failure "Bonsai_gtk_test: node echo has no on_activate handler") |}]
;;
