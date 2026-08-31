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
  let click = Attr.on_click ~button:2 (fun _ -> Click_response.Continue) in
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
  let h : Click_response.handler = fun _ -> Click_response.Continue in
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

(* The key attrs are values too, and the one thing a reader of a golden has to be able to
   see is the [~phase]: it decides whether a dialog's Escape handler runs before or after
   whatever its children attached, and nothing else prints it. *)
let%expect_test "key attrs round-trip and diff" =
  let pressed : Key_response.handler = fun _ -> Key_response.Propagate in
  let released : Key_event.t Handler.t = fun _ -> noop in
  let attrs =
    Attrs.of_list
      [ Attr.on_key_pressed ~phase:Capture pressed; Attr.on_key_released released ]
  in
  print_s [%sexp (attrs : Attrs.t)];
  [%expect
    {|
    ((On_key_pressed (phase Capture) (handler <handler>))
     (On_key_released (phase Bubble) (handler <handler>)))
    |}];
  (* Physically the same attrs diff to nothing; the handler alone changing is a Set. *)
  let base = Attrs.of_list [ Attr.on_key_pressed pressed ] in
  print_s
    [%sexp
      (Attrs.diff ~old:base ~new_:(Attrs.of_list [ Attr.on_key_pressed pressed ])
       : Attrs.op list)];
  [%expect {| () |}];
  print_s
    [%sexp
      (Attrs.diff
         ~old:base
         ~new_:(Attrs.of_list [ Attr.on_key_pressed (fun _ -> Key_response.Handled) ])
       : Attrs.op list)];
  [%expect {| ((Set (On_key_pressed (phase Bubble) (handler <handler>)))) |}];
  (* And [~phase] is part of the attr's identity, like [on_click]'s [~button]: it is a
     property of the controller that [Controllers.update] re-reads, so moving it has to be
     a [Set] even though the handler is physically unchanged. *)
  print_s
    [%sexp
      (Attrs.diff
         ~old:base
         ~new_:(Attrs.of_list [ Attr.on_key_pressed ~phase:Capture pressed ])
       : Attrs.op list)];
  [%expect {| ((Set (On_key_pressed (phase Capture) (handler <handler>)))) |}]
;;

(* [Key_response.sexp_of_t] prints the effect as [<effect>] rather than trying to describe
   it, which is what makes a golden comparing two responses compare the decision and not
   two closures. The four constructors are the whole of what a handler can answer. *)
let%expect_test "a key response sexps its decision and hides its effect" =
  List.iter
    [ Key_response.Propagate; Handled; Propagate_and noop; Handled_and noop ]
    ~f:(fun r ->
      print_s
        [%sexp
          (r : Key_response.t)
          , `handled (Key_response.handled r : bool)
          , `has_effect (Option.is_some (Key_response.effect r) : bool)]);
  [%expect
    {|
    (Propagate (handled false) (has_effect false))
    (Handled (handled true) (has_effect false))
    ((Propagate_and <effect>) (handled false) (has_effect true))
    ((Handled_and <effect>) (handled true) (has_effect true))
    |}]
;;

(* The click twin, on the same terms: [claim] is the whole of what reaches GTK
   ([Gesture.set_state] with [`CLAIMED]), and the effect hides behind [<effect>].
   [Continue] is what a missing handler produces, so its row is the [declined] path's
   contract as well as the constructor's. *)
let%expect_test "a click response sexps its decision and hides its effect" =
  List.iter
    [ Click_response.Continue; Claim; Continue_and noop; Claim_and noop ]
    ~f:(fun r ->
      print_s
        [%sexp
          (r : Click_response.t)
          , `claim (Click_response.claim r : bool)
          , `has_effect (Option.is_some (Click_response.effect r) : bool)]);
  [%expect
    {|
    (Continue (claim false) (has_effect false))
    (Claim (claim true) (has_effect false))
    ((Continue_and <effect>) (claim false) (has_effect true))
    ((Claim_and <effect>) (claim true) (has_effect true))
    |}]
;;

(* A key event carries the logical keyval, the hardware keycode and the modifier state,
   and [Keyval] is how a view names the first of the three without linking ocgtk. *)
let%expect_test "a key event sexps with its keyval" =
  print_s
    [%sexp
      ({ Key_event.keyval = Keyval.escape
       ; keycode = 9
       ; modifiers = { Modifiers.none with control = true }
       }
       : Key_event.t)];
  [%expect
    {|
    ((keyval 65307) (keycode 9)
     (modifiers
      ((shift false) (control true) (alt false) (super false) (hyper false)
       (meta false))))
    |}];
  (* The named keysyms, so that a change to one of them is a diff here as well as a
     MISMATCH in [test/live/live_keyvals.ml] -- this file runs without a display and is
     what a reader checks against X11's keysymdef.h. *)
  print_s
    [%sexp
      (List.map
         [ "escape", Keyval.escape
         ; "return", Keyval.return
         ; "kp_enter", Keyval.kp_enter
         ; "tab", Keyval.tab
         ; "iso_left_tab", Keyval.iso_left_tab
         ; "space", Keyval.space
         ; "backspace", Keyval.backspace
         ; "delete", Keyval.delete
         ; "up", Keyval.up
         ; "down", Keyval.down
         ; "left", Keyval.left
         ; "right", Keyval.right
         ; "home", Keyval.home
         ; "end_", Keyval.end_
         ; "page_up", Keyval.page_up
         ; "page_down", Keyval.page_down
         ; "slash", Keyval.slash
         ; "f1", Keyval.f 1
         ; "f12", Keyval.f 12
         ; "of_char 'w'", Keyval.of_char 'w'
         ; "of_char 'W'", Keyval.of_char 'W'
         ; "of_char '/'", Keyval.of_char '/'
         ]
         ~f:(fun (name, v) -> name, sprintf "%#x" v)
       : (string * string) list)];
  [%expect
    {|
    ((escape 0xff1b) (return 0xff0d) (kp_enter 0xff8d) (tab 0xff09)
     (iso_left_tab 0xfe20) (space 0x20) (backspace 0xff08) (delete 0xffff)
     (up 0xff52) (down 0xff54) (left 0xff51) (right 0xff53) (home 0xff50)
     (end_ 0xff57) (page_up 0xff55) (page_down 0xff56) (slash 0x2f) (f1 0xffbe)
     (f12 0xffc9) ("of_char 'w'" 0x77) ("of_char 'W'" 0x57) ("of_char '/'" 0x2f))
    |}]
;;

(* Both halves of {!Keyval}'s two partial functions raise rather than returning a keysym
   that is merely plausible: outside printable ASCII a character's keysym is not its code
   point, and an application comparing against a wrong one would simply never match. *)
let%expect_test "Keyval.of_char and Keyval.f reject what they cannot answer" =
  Expect_test_helpers_core.require_does_raise (fun () -> Keyval.of_char '\n');
  [%expect
    {|
    (Invalid_argument
     "Keyval.of_char: 0xa is not printable ASCII (0x20..0x7e), and its keysym is not its code point")
    |}];
  Expect_test_helpers_core.require_does_raise (fun () -> Keyval.of_char '\255');
  [%expect
    {|
    (Invalid_argument
     "Keyval.of_char: 0xff is not printable ASCII (0x20..0x7e), and its keysym is not its code point")
    |}];
  Expect_test_helpers_core.require_does_raise (fun () -> Keyval.f 0);
  [%expect {| (Invalid_argument "Keyval.f: 0 is not in 1..12") |}];
  Expect_test_helpers_core.require_does_raise (fun () -> Keyval.f 13);
  [%expect {| (Invalid_argument "Keyval.f: 13 is not in 1..12") |}]
;;
