open! Core
open Bonsai_gtk_vtree

let%expect_test "constructors and sexp" =
  let view =
    Node.window
      ~title:"Counter"
      ~default_size:(200, 100)
      (Node.box
         ~orientation:Vertical
         ~spacing:6
         [ Node.label ~key:"count" "Count: 0"
         ; Node.button
             ~attrs:[ Attr.test_id "inc"; Attr.on_clicked Ui_effect.Ignore ]
             ~label:"+"
             ()
         ])
  in
  print_s [%sexp (view : Node.t)];
  [%expect
    {|
    ((kind (Window ((title (Counter)) (default_size ((200 100)))))) (attrs ())
     (children
      (Single
       (((kind (Box ((orientation Vertical) (spacing 6)))) (attrs ())
         (children
          (List
           (((kind (Label ((text "Count: 0")))) (key count) (attrs ())
             (children No_children))
            ((kind (Button ((label (+)))))
             (attrs ((Test_id inc) (On_clicked <handler>)))
             (children (Single ())))))))))))
    |}]
;;

let%expect_test "find_by_test_id" =
  let view =
    Node.box
      ~orientation:Horizontal
      [ Node.label "a"; Node.button ~attrs:[ Attr.test_id "b" ] ~label:"B" () ]
  in
  print_s
    [%sexp
      (Option.map (Node.find_by_test_id view "b") ~f:(fun n -> n.kind) : Kind.t option)];
  [%expect {| ((Button ((label (B))))) |}];
  print_s [%sexp (Node.find_by_test_id view "zzz" : Node.t option)];
  [%expect {| () |}]
;;

let%expect_test "same_kind ignores props; native compares by name" =
  let open Kind in
  let label text = (Node.label text).Node.kind in
  print_s [%sexp (same_kind (label "a") (label "b") : bool)];
  [%expect {| true |}];
  print_s
    [%sexp
      (same_kind (label "a") (Button { label = None; icon_name = None; has_frame = true })
       : bool)];
  [%expect {| false |}];
  let n name = Native { Native.name; payload = Native.Unit } in
  print_s
    [%sexp
      ((same_kind (n "canvas") (n "canvas"), same_kind (n "canvas") (n "other"))
       : bool * bool)];
  [%expect {| (true false) |}]
;;

(* A [test_id] is how a headless action names the node it acts on, so two nodes carrying
   one is not a search to resolve by walk order -- it is the mistake of rendering the same
   sub-view twice (two rows, both with a "delete" button), and a test that acted on
   whichever came first would pass without asserting which. *)
let%expect_test "find_by_test_id insists on one match, and names the paths otherwise" =
  let view ~second_id =
    Node.window
      ~title:"t"
      (Node.box
         ~orientation:Vertical
         [ Node.label "heading"
         ; Node.button ~attrs:[ Attr.test_id "delete" ] ~label:"row 1" ()
         ; Node.button ~attrs:[ Attr.test_id second_id ] ~label:"row 2" ()
         ])
  in
  print_s
    [%sexp
      (Option.map
         (Node.find_by_test_id (view ~second_id:"other") "delete")
         ~f:(fun n -> Kind.name n.Node.kind)
       : string option)];
  [%expect {| (Button) |}];
  print_s
    [%sexp (Node.find_by_test_id (view ~second_id:"other") "missing" : Node.t option)];
  [%expect {| () |}];
  Expect_test_helpers_core.require_does_raise (fun () ->
    Node.find_by_test_id (view ~second_id:"delete") "delete");
  [%expect
    {|
    (Invalid_argument
     "Node.find_by_test_id: 2 nodes carry the test_id delete (root/0/1, root/0/2); a test_id has to identify one node")
    |}]
;;
