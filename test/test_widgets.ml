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

let%expect_test "is_event classifies the handler-carrying attr names" =
  print_s [%sexp (Attr.Name.is_event Attr.Name.On_toggled : bool)];
  [%expect {| true |}];
  print_s [%sexp (Attr.Name.is_event Attr.Name.Tooltip : bool)];
  [%expect {| false |}]
;;

let%expect_test "the entry family's constructors" =
  print_s
    [%sexp
      (Node.box
         ~orientation:Vertical
         [ Node.entry ~placeholder:"name" ~text:"" ()
         ; Node.entry ~text:"x" ~width_chars:6 ~xalign:1. ~editable:false ()
         ; Node.password_entry ~text:"" ~placeholder:"passphrase" ()
         ; Node.search_entry ~text:"bach" ~search_delay:150 ()
         ]
       : Node.t)];
  [%expect
    {|
    ((kind (Box ((orientation Vertical)))) (attrs ())
     (children
      (List
       (((kind (Entry ((text "") (placeholder (name))))) (attrs ())
         (children No_children))
        ((kind (Entry ((text x) (editable false) (width_chars 6) (xalign 1))))
         (attrs ()) (children No_children))
        ((kind (Password_entry ((text "") (placeholder (passphrase)))))
         (attrs ()) (children No_children))
        ((kind (Search_entry ((text bach) (search_delay (150))))) (attrs ())
         (children No_children))))))
    |}]
;;

let%expect_test "the numeric family's constructors" =
  print_s
    [%sexp
      (Node.box
         ~orientation:Vertical
         [ Node.spin_button ~min:40. ~max:280. ~value:120. ~step:1. ()
         ; Node.scale
             ~orientation:Horizontal
             ~min:1.
             ~max:32.
             ~value:7.
             ~draw_value:false
             ()
         ; Node.progress_bar ~fraction:0.25 ~text:"loading" ~show_text:true ()
         ; Node.spinner ~spinning:true ()
         ]
       : Node.t)];
  [%expect
    {|
    ((kind (Box ((orientation Vertical)))) (attrs ())
     (children
      (List
       (((kind (Spin_button ((value 120) (min 40) (max 280)))) (attrs ())
         (children No_children))
        ((kind
          (Scale
           ((orientation Horizontal) (value 7) (min 1) (max 32)
            (draw_value false))))
         (attrs ()) (children No_children))
        ((kind
          (Progress_bar ((fraction 0.25) (text (loading)) (show_text true))))
         (attrs ()) (children No_children))
        ((kind (Spinner ((spinning true)))) (attrs ()) (children No_children))))))
    |}]
;;
