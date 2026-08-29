open! Core
open Bonsai_gtk_vtree

let%expect_test "label defaults match GTK's, and every text property reaches the kind" =
  print_s [%sexp (Node.label "plain" : Node.t)];
  [%expect
    {|
    ((kind
      (Label
       ((text plain) (wrap false) (xalign 0.5) (ellipsize ())
        (max_width_chars -1) (width_chars -1) (selectable false)
        (use_markup false))))
     (attrs ()) (children No_children))
    |}];
  print_s
    [%sexp
      (Node.label
         ~wrap:true
         ~xalign:0.
         ~ellipsize:End
         ~max_width_chars:14
         ~width_chars:6
         ~selectable:true
         ~use_markup:true
         "styled"
       : Node.t)];
  [%expect
    {|
    ((kind
      (Label
       ((text styled) (wrap true) (xalign 0) (ellipsize (End))
        (max_width_chars 14) (width_chars 6) (selectable true) (use_markup true))))
     (attrs ()) (children No_children))
    |}]
;;

let%expect_test "label props take part in equal_props" =
  let a = (Node.label ~xalign:0. "x").kind in
  let b = (Node.label ~xalign:1. "x").kind in
  print_s [%sexp ((Kind.same_kind a b, Kind.equal_props a b) : bool * bool)];
  [%expect {| (true false) |}]
;;
