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
       (((kind (Box ((orientation Vertical) (spacing 6) (homogeneous false))))
         (attrs ())
         (children
          (List
           (((kind
              (Label
               ((text "Count: 0") (wrap false) (xalign 0.5) (ellipsize ())
                (max_width_chars -1) (width_chars -1) (selectable false)
                (use_markup false))))
             (key count) (attrs ()) (children No_children))
            ((kind (Button ((label (+)))))
             (attrs ((Test_id inc) (On_clicked <handler>)))
             (children No_children))))))))))
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
  print_s [%sexp (same_kind (label "a") (Button { label = None }) : bool)];
  [%expect {| false |}];
  let n name = Native { Native.name; payload = Native.Unit } in
  print_s
    [%sexp
      ((same_kind (n "canvas") (n "canvas"), same_kind (n "canvas") (n "other"))
       : bool * bool)];
  [%expect {| (true false) |}]
;;
