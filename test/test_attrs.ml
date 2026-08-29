open! Core
open Bonsai_gtk_vtree

let noop = Ui_effect.Ignore

let%expect_test "of_list merges by name, last wins, css classes accumulate in order" =
  let attrs =
    Attrs.of_list
      [ Attr.css_class "a"
      ; Attr.margin_start 4
      ; Attr.css_class "b"
      ; Attr.margin_start 8
      ; Attr.css_class "a"
      ; Attr.many [ Attr.sensitive false; Attr.test_id "btn" ]
      ]
  in
  print_s [%sexp (attrs : Attrs.t)];
  [%expect
    {|
    ((css_classes (a b)) (Margin_start 8) (Sensitive false) (Test_id btn))
    |}];
  print_s [%sexp (Attrs.css_classes attrs : string list)];
  [%expect {| (a b) |}];
  print_s [%sexp (Attrs.test_id attrs : string option)];
  [%expect {| (btn) |}]
;;

let%expect_test "diff emits set/unset/add/remove; unchanged attrs produce nothing" =
  let old =
    Attrs.of_list
      [ Attr.css_class "a"; Attr.css_class "b"; Attr.margin_start 4; Attr.visible false ]
  in
  let new_ =
    Attrs.of_list
      [ Attr.css_class "b"; Attr.css_class "c"; Attr.margin_start 4; Attr.tooltip "hi" ]
  in
  print_s [%sexp (Attrs.diff ~old ~new_ : Attrs.op list)];
  [%expect
    {|
    ((Remove_css_class a) (Add_css_class c) (Unset Visible) (Set (Tooltip hi)))
    |}]
;;

let%expect_test "handlers compare physically" =
  let h = Attr.on_clicked noop in
  let old = Attrs.of_list [ h ] in
  print_s [%sexp (Attrs.diff ~old ~new_:(Attrs.of_list [ h ]) : Attrs.op list)];
  [%expect {| () |}];
  print_s
    [%sexp
      (Attrs.diff ~old ~new_:(Attrs.of_list [ Attr.on_clicked noop ]) : Attrs.op list)];
  [%expect {| ((Set (On_clicked <handler>))) |}]
;;

let%expect_test "M1 widget-wide attrs round-trip through of_list and diff" =
  let attrs =
    Attrs.of_list
      [ Attr.opacity 0.5
      ; Attr.focusable true
      ; Attr.can_focus false
      ; Attr.widget_name "sidebar"
      ; Attr.cursor_name "pointer"
      ]
  in
  print_s [%sexp (attrs : Attrs.t)];
  [%expect
    {|
    ((Opacity 0.5) (Focusable true) (Can_focus false) (Widget_name sidebar)
     (Cursor_name pointer))
    |}];
  print_s
    [%sexp
      (Attrs.diff ~old:attrs ~new_:(Attrs.of_list [ Attr.opacity 1.0 ]) : Attrs.op list)];
  [%expect
    {|
    ((Set (Opacity 1)) (Unset Focusable) (Unset Can_focus) (Unset Widget_name)
     (Unset Cursor_name))
    |}]
;;
