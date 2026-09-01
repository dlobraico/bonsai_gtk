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
  ; (Node.text_view ~text:"" ()).kind
  ; (Node.spin_button ~min:0. ~max:1. ~value:0. ()).kind
  ; (Node.scale ~orientation:Horizontal ~min:0. ~max:1. ~value:0. ()).kind
  ; (Node.progress_bar ~fraction:0. ()).kind
  ; (Node.spinner ~spinning:false ()).kind
  ; (Node.level_bar ~value:0. ()).kind
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
  ; (Node.list_box ~selected:[] []).kind
  ; (Node.flow_box ~selected:[] []).kind
  ; (Node.notebook ~current_page:"a" []).kind
  ; (Node.drop_down ~items:[] ~selected:(-1) ()).kind
  ; (Node.calendar ~date:(Date.of_string "2026-08-30") ()).kind
  ; (Node.editable_label ~text:"" ()).kind
  ; (Node.center_box ()).kind
  ; (Node.paned ~orientation:Horizontal ~start:(child ()) ~end_:(child ()) ()).kind
  ; (Node.overlay (child ())).kind
  ; (Node.header_bar ()).kind
  ; (Node.action_bar ()).kind
  ; (Node.popover (child ())).kind
  ; (Node.menu_button ()).kind
  ; (Node.window (child ())).kind
  ; (Node.native { Native.name = "thing"; payload = Native.Unit }).kind
  ]
;;

(* The list above is hand-maintained; [Kind.Variants.descriptions] is not. A kind added to
   [Kind.t] without a row here fails this rather than quietly going unchecked -- which
   matters because [Events.for_kind]'s missing wildcard forces a *decision* for a new kind
   but nothing forces that decision to be *tested*.

   By {i name} and not by count, and so is [test/live/live_events.ml]'s twin: a count is
   satisfied by a duplicated row plus an omitted one, which is exactly the drift Task 1
   recorded as a carry when it left these two lists duplicated. (task-13-review.md N6.) *)
let%expect_test "all_kinds names every kind" =
  let covered = List.map all_kinds ~f:Kind.Variants.to_name in
  let missing =
    List.filter_map Kind.Variants.descriptions ~f:(fun (name, _) ->
      if List.mem covered name ~equal:String.equal then None else Some name)
  in
  print_s [%sexp (missing : string list)];
  [%expect {| () |}]
;;

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
    (TextView (On_changed On_cursor_moved))
    (SpinButton (On_value_changed))
    (Scale (On_value_changed))
    (ProgressBar ())
    (Spinner ())
    (LevelBar ())
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
    (ListBox (On_row_activated On_selected_rows_changed))
    (FlowBox (On_child_activated On_selected_children_changed))
    (Notebook (On_page_changed))
    (DropDown (On_selected_changed))
    (Calendar (On_day_selected))
    (EditableLabel (On_changed On_editing_changed))
    (CenterBox ())
    (Paned (On_position_changed))
    (Overlay ())
    (HeaderBar ())
    (ActionBar ())
    (Popover (On_closed))
    (MenuButton ())
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
     (Actions On_clicked On_toggled On_changed On_activate On_search_changed
      On_value_changed On_expanded_changed On_revealed On_position_changed
      On_visible_child_changed On_row_activated On_selected_rows_changed
      On_child_activated On_selected_children_changed On_page_changed
      On_selected_changed On_day_selected On_editing_changed On_cursor_moved
      On_closed On_click On_focus_enter On_focus_leave On_contains_focus_changed
      On_key_pressed On_key_released))
    |}];
  print_s [%sexp `plain (plain : Attr.Name.t list)];
  [%expect
    {|
    (plain
     (Margin_start Margin_end Margin_top Margin_bottom Halign Valign Hexpand
      Vexpand Sensitive Visible Tooltip Width_request Height_request Opacity
      Focusable Can_focus Autofocus Widget_name Cursor_name Test_id
      Measure_overlay Grid_cell Page_title Row_selectable Row_activatable
      Tab_label))
    |}]
;;

(* Every event name some kind can carry has to be one [Attr.Name.is_event] agrees is an
   event, or [Events.unsupported] would never look at it and the table entry would be
   dead. The converse -- an event name no kind emits -- is legal only until the widget
   that emits it lands, so it is printed rather than asserted.

   The controller attrs are the third case and are excluded from both halves: they are
   events that appear in no [for_kind] row *by design*, because they are legal everywhere.
   Excluding them here rather than widening the golden is the point -- a real signal name
   that fell out of every row would still show up. *)
let%expect_test "the table and [is_event] cover the same names" =
  let in_table =
    List.concat_map all_kinds ~f:Events.for_kind |> Attr.Name.Set.of_list |> Set.to_list
  in
  print_s
    [%sexp
      `not_events (List.filter in_table ~f:(Fn.non Attr.Name.is_event) : Attr.Name.t list)];
  [%expect {| (not_events ()) |}];
  print_s
    [%sexp
      `controller_attrs_in_a_for_kind_row
        (List.filter in_table ~f:Events.is_controller_attr : Attr.Name.t list)];
  [%expect {| (controller_attrs_in_a_for_kind_row ()) |}];
  let emitted_by_nobody =
    List.filter Attr.Name.all ~f:(fun n ->
      Attr.Name.is_event n
      && (not (Events.is_controller_attr n))
      && not (List.mem in_table n ~equal:Attr.Name.equal))
  in
  print_s [%sexp `signal_names_no_kind_emits (emitted_by_nobody : Attr.Name.t list)];
  [%expect {| (signal_names_no_kind_emits (Actions)) |}]
;;

(* The other half of the same fact, and the one an application depends on: a controller
   attr is accepted on *every* kind, including the ones that emit no signal at all and
   including [Node.native], where every signal attr is rejected (spec §6.6). Asserted over
   the full kind list rather than a sample, so a kind added with a hand-written
   [is_supported] arm could not slip past. *)
let%expect_test "every controller attr is supported on every kind" =
  let controller_attrs = List.filter Attr.Name.all ~f:Events.is_controller_attr in
  print_s [%sexp (controller_attrs : Attr.Name.t list)];
  [%expect
    {|
    (On_click On_focus_enter On_focus_leave On_contains_focus_changed
     On_key_pressed On_key_released)
    |}];
  let refused =
    List.concat_map all_kinds ~f:(fun kind ->
      List.filter_map controller_attrs ~f:(fun name ->
        if Events.is_supported kind name then None else Some (Kind.name kind, name)))
  in
  print_s [%sexp `refused (refused : (string * Attr.Name.t) list)];
  [%expect {| (refused ()) |}];
  (* And a click attr on a label -- which emits nothing -- really does pass the same
     [unsupported] gate the runtime and the handle both call. *)
  let attrs = Attrs.of_list [ Attr.on_click (fun _ -> Click_response.Continue) ] in
  print_s [%sexp (Events.unsupported (Node.label "x").kind attrs : Attr.Name.t option)];
  [%expect {| () |}];
  print_s
    [%sexp
      (Events.unsupported
         (Node.native { Native.name = "thing"; payload = Native.Unit }).kind
         attrs
       : Attr.Name.t option)];
  [%expect {| () |}]
;;
