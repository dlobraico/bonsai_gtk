open! Core
open Bonsai_gtk_vtree

let%expect_test "label defaults match GTK's, and every text property reaches the kind" =
  print_s [%sexp (Node.label "plain" : Node.t)];
  [%expect {| ((kind (Label ((text plain)))) (attrs ()) (children No_children)) |}];
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

let%expect_test "the toggle family's constructors" =
  print_s
    [%sexp
      (Node.box
         ~orientation:Vertical
         [ Node.button ~label:"go" ()
         ; Node.button ~icon_name:"list-add-symbolic" ~has_frame:false ()
         ; Node.button ~child:(Node.label "boxed") ()
         ; Node.toggle_button ~label:"bold" ~active:true ()
         ; Node.check_button ~label:"agree" ~active:false ()
         ; Node.switch ~active:true ()
         ]
       : Node.t)];
  [%expect
    {|
    ((kind (Box ((orientation Vertical)))) (attrs ())
     (children
      (List
       (((kind (Button ((label (go))))) (attrs ()) (children (Single ())))
        ((kind (Button ((icon_name (list-add-symbolic)) (has_frame false))))
         (attrs ()) (children (Single ())))
        ((kind (Button ())) (attrs ())
         (children
          (Single
           (((kind (Label ((text boxed)))) (attrs ()) (children No_children))))))
        ((kind (Toggle_button ((label (bold)) (active true)))) (attrs ())
         (children (Single ())))
        ((kind (Check_button ((label (agree)) (active false)))) (attrs ())
         (children No_children))
        ((kind (Switch ((active true)))) (attrs ()) (children No_children))))))
    |}]
;;

let%expect_test "an on_* attr the widget cannot emit is rejected at mount, not ignored" =
  print_s [%sexp (Attr.Name.is_event Attr.Name.On_toggled : bool)];
  [%expect {| true |}];
  print_s [%sexp (Attr.Name.is_event Attr.Name.Tooltip : bool)];
  [%expect {| false |}]
;;
