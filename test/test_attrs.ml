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

(* The controller attrs are values before they are behaviour: they round-trip through
   [Attrs.of_list], they sexp with their controller-level settings visible (a reader of a
   golden has to be able to see that [~button:2] made it in, since nothing else prints
   it), and they diff on the same physical-handler rule as every other event attr. *)
let%expect_test "controller attrs round-trip and diff" =
  let click = Attr.on_click ~button:2 (fun _ -> noop) in
  let attrs = Attrs.of_list [ click; Attr.on_focus_enter (fun () -> noop) ] in
  print_s [%sexp (attrs : Attrs.t)];
  [%expect
    {|
    ((On_click (button 2) (phase Bubble) (handler <handler>))
     (On_focus_enter <handler>))
    |}];
  (* A handler that changed is a Set; a handler that is physically the same is not.
     Handlers compare physically (spec §5.2), so a view that rebuilds its closures every
     frame writes the slot every frame -- which is a slot write, not a GTK call. *)
  print_s [%sexp (Attrs.diff ~old:attrs ~new_:(Attrs.of_list [ click ]) : Attrs.op list)];
  [%expect {| ((Unset On_focus_enter)) |}];
  (* Physically the same attr value diffs to nothing at all. *)
  print_s
    [%sexp
      (Attrs.diff ~old:(Attrs.of_list [ click ]) ~new_:(Attrs.of_list [ click ])
       : Attrs.op list)];
  [%expect {| () |}]
;;

(* [button] and [phase] are properties of the *controller*, not of the handler, so a
   change in either has to be a [Set] even when the handler is physically unchanged --
   that is what [Controllers.update] re-reads them from. *)
let%expect_test "a click attr's button and phase are part of its identity" =
  let h : Click_event.t Handler.t = fun _ -> noop in
  let base = Attrs.of_list [ Attr.on_click h ] in
  print_s
    [%sexp
      (Attrs.diff ~old:base ~new_:(Attrs.of_list [ Attr.on_click h ]) : Attrs.op list)];
  [%expect {| () |}];
  print_s
    [%sexp
      (Attrs.diff ~old:base ~new_:(Attrs.of_list [ Attr.on_click ~button:3 h ])
       : Attrs.op list)];
  [%expect {| ((Set (On_click (button 3) (phase Bubble) (handler <handler>)))) |}];
  print_s
    [%sexp
      (Attrs.diff ~old:base ~new_:(Attrs.of_list [ Attr.on_click ~phase:Capture h ])
       : Attrs.op list)];
  [%expect {| ((Set (On_click (button 0) (phase Capture) (handler <handler>)))) |}]
;;

(* [Modifiers.none] is what a headless test builds an event with, and what a real click
   with nothing held down produces. *)
let%expect_test "a click event sexps with its modifiers" =
  print_s
    [%sexp
      ({ Click_event.button = 1
       ; n_press = 2
       ; x = 3.5
       ; y = 4.5
       ; modifiers = Modifiers.none
       }
       : Click_event.t)];
  [%expect
    {|
    ((button 1) (n_press 2) (x 3.5) (y 4.5)
     (modifiers
      ((shift false) (control false) (alt false) (super false) (hyper false)
       (meta false))))
    |}];
  print_s [%sexp ({ Modifiers.none with control = true; shift = true } : Modifiers.t)];
  [%expect
    {|
    ((shift true) (control true) (alt false) (super false) (hyper false)
     (meta false))
    |}]
;;
