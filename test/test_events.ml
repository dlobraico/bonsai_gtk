open! Core
open Bonsai_gtk_vtree

(* One row per kind, so that adding a kind without an [Events] arm is a compile error
   ([Events.for_kind] has no wildcard) and adding one with the wrong arm is a diff here.
   The kinds are built with their cheapest constructor; only the constructor, not the
   props, decides the answer.

   The list is spelled out rather than derived because there is no exhaustive-match trick
   that produces a *value* per constructor. A kind missing from here is caught by
   [test/live/live_events.ml]'s count assertion, which walks the same territory against
   the widget impls. *)
let all_kinds : Kind.t list =
  let child () = Node.label "x" in
  [ (Node.label "x").kind
  ; (Node.button ()).kind
  ; (Node.toggle_button ~active:false ()).kind
  ; (Node.check_button ~active:false ()).kind
  ; (Node.switch ~active:false ()).kind
  ; (Node.entry ~text:"" ()).kind
  ; (Node.password_entry ~text:"" ()).kind
  ; (Node.search_entry ~text:"" ()).kind
  ; (Node.spin_button ~min:0. ~max:1. ~value:0. ()).kind
  ; (Node.scale ~orientation:Horizontal ~min:0. ~max:1. ~value:0. ()).kind
  ; (Node.progress_bar ~fraction:0. ()).kind
  ; (Node.spinner ~spinning:false ()).kind
  ; (Node.image (Icon_name "x")).kind
  ; (Node.picture (Filename "x")).kind
  ; (Node.separator ~orientation:Horizontal ()).kind
  ; (Node.scrolled_window (child ())).kind
  ; (Node.frame (child ())).kind
  ; (Node.expander ~expanded:false ~label:"e" (child ())).kind
  ; (Node.revealer ~reveal:false (child ())).kind
  ; (Node.box ~orientation:Vertical []).kind
  ; (Node.grid []).kind
  ; (Node.stack ~name:"s" ~visible_child:"a" []).kind
  ; (Node.stack_switcher ~stack:"s" ()).kind
  ; (Node.stack_sidebar ~stack:"s" ()).kind
  ; (Node.center_box ()).kind
  ; (Node.paned ~orientation:Horizontal ~start:(child ()) ~end_:(child ()) ()).kind
  ; (Node.overlay (child ())).kind
  ; (Node.window (child ())).kind
  ; (Node.native { Native.name = "thing"; payload = Native.Unit }).kind
  ]
;;

(* The list above is hand-maintained; [Kind.Variants.descriptions] is not. A kind added to
   [Kind.t] without a row here fails this assertion rather than quietly going unchecked --
   which matters because [Events.for_kind]'s missing wildcard forces a *decision* for a
   new kind but nothing forces that decision to be *tested*. *)
let () = assert (List.length all_kinds = List.length Kind.Variants.descriptions)

let%expect_test "every kind's event attrs" =
  List.iter all_kinds ~f:(fun kind ->
    print_s [%sexp (Kind.name kind : string), (Events.for_kind kind : Attr.Name.t list)]);
  [%expect
    {|
    (Label ())
    (Button (On_clicked))
    (ToggleButton (On_toggled))
    (CheckButton (On_toggled))
    (Switch (On_toggled))
    (Entry (On_changed On_activate))
    (PasswordEntry (On_changed On_activate))
    (SearchEntry (On_changed On_activate On_search_changed))
    (SpinButton (On_value_changed))
    (Scale (On_value_changed))
    (ProgressBar ())
    (Spinner ())
    (Image ())
    (Picture ())
    (Separator ())
    (ScrolledWindow ())
    (Frame ())
    (Expander (On_expanded_changed))
    (Revealer (On_revealed))
    (Box ())
    (Grid ())
    (Stack (On_visible_child_changed))
    (StackSwitcher ())
    (StackSidebar ())
    (CenterBox ())
    (Paned (On_position_changed))
    (Overlay ())
    (Window ())
    (Native:thing ())
    |}]
;;

let%expect_test "unsupported finds the offending name, and only event names" =
  let attrs =
    Attrs.of_list
      [ Attr.css_class "c"
      ; Attr.test_id "t"
      ; Attr.on_toggled (fun _ -> Ui_effect.Ignore)
      ]
  in
  print_s [%sexp (Events.unsupported (Node.label "x").kind attrs : Attr.Name.t option)];
  [%expect {| (On_toggled) |}];
  print_s
    [%sexp
      (Events.unsupported (Node.switch ~active:false ()).kind attrs : Attr.Name.t option)];
  [%expect {| () |}]
;;

(* The mli promises "the first ... in [Attr.Name] order", which a single offending attr
   cannot pin -- any answer would look the same. [On_clicked] is declared before
   [On_toggled] in [Attr.Name.t], and the attrs are passed in the other order. *)
let%expect_test "unsupported answers in Attr.Name order, not argument order" =
  let attrs =
    Attrs.of_list
      [ Attr.on_toggled (fun _ -> Ui_effect.Ignore); Attr.on_clicked Ui_effect.Ignore ]
  in
  print_s [%sexp (Events.unsupported (Node.label "x").kind attrs : Attr.Name.t option)];
  [%expect {| (On_clicked) |}];
  (* On a button [On_clicked] is fine, so the answer moves to the next offender. *)
  print_s [%sexp (Events.unsupported (Node.button ()).kind attrs : Attr.Name.t option)];
  [%expect {| (On_toggled) |}]
;;

(* A non-event name is supported everywhere -- [is_supported] answers "may this attr be
   here", and a layout attr may be anywhere -- while an event name is supported only where
   the table says so. *)
let%expect_test "is_supported over a kind that emits nothing and one that emits something"
  =
  let show kind =
    print_s
      [%sexp
        (Kind.name kind : string)
        , `test_id (Events.is_supported kind Test_id : bool)
        , `on_toggled (Events.is_supported kind On_toggled : bool)
        , `on_clicked (Events.is_supported kind On_clicked : bool)]
  in
  show (Node.label "x").kind;
  show (Node.switch ~active:false ()).kind;
  show (Node.button ()).kind;
  [%expect
    {|
    (Label (test_id true) (on_toggled false) (on_clicked false))
    (Switch (test_id true) (on_toggled true) (on_clicked false))
    (Button (test_id true) (on_toggled false) (on_clicked true))
    |}]
;;

(* [Attr.Name.all] exists so that [is_event]'s classification is pinned rather than
   assumed -- the M1 final review found it tested on 2 names of 32, and adding an [On_foo]
   to the wrong branch compiles. *)
let%expect_test "is_event over every name" =
  let events, plain = List.partition_tf Attr.Name.all ~f:Attr.Name.is_event in
  print_s [%sexp `events (events : Attr.Name.t list)];
  [%expect
    {|
    (events
     (On_clicked On_toggled On_changed On_activate On_search_changed
      On_value_changed On_expanded_changed On_revealed On_position_changed
      On_visible_child_changed))
    |}];
  print_s [%sexp `plain (plain : Attr.Name.t list)];
  [%expect
    {|
    (plain
     (Margin_start Margin_end Margin_top Margin_bottom Halign Valign Hexpand
      Vexpand Sensitive Visible Tooltip Width_request Height_request Opacity
      Focusable Can_focus Widget_name Cursor_name Test_id Measure_overlay
      Grid_cell Page_title))
    |}]
;;

(* Every event name some kind can carry has to be one [Attr.Name.is_event] agrees is an
   event, or [Events.unsupported] would never look at it and the table entry would be
   dead. The converse -- an event name no kind emits -- is legal only until the widget
   that emits it lands, so it is printed rather than asserted. *)
let%expect_test "the table and [is_event] cover the same names" =
  let in_table =
    List.concat_map all_kinds ~f:Events.for_kind |> Attr.Name.Set.of_list |> Set.to_list
  in
  print_s
    [%sexp
      `not_events (List.filter in_table ~f:(Fn.non Attr.Name.is_event) : Attr.Name.t list)];
  [%expect {| (not_events ()) |}];
  let emitted_by_nobody =
    List.filter Attr.Name.all ~f:(fun n ->
      Attr.Name.is_event n && not (List.mem in_table n ~equal:Attr.Name.equal))
  in
  print_s [%sexp `event_names_no_kind_emits (emitted_by_nobody : Attr.Name.t list)];
  [%expect {| (event_names_no_kind_emits ()) |}]
;;
