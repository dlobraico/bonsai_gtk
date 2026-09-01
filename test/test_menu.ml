open! Core
open Bonsai_gtk_vtree

let noop = Ui_effect.Ignore

(* The menu is pure data: it sexps with everything a reader needs (labels, action
   references, display accels) and equals structurally, which is what lets it be a prop
   [Kind.equal_props] diffs. *)
let%expect_test "a menu sexps and equals as plain data" =
  let menu =
    [ Menu.item ~label:"Open" ~action:"app.open" ~accel:"<Control>o" ()
    ; Menu.section
        ~label:"View"
        [ Menu.item ~label:"Zoom In" ~action:"view.zoom-in" ()
        ; Menu.item ~label:"Dark" ~action:"view.theme::dark" ()
        ]
    ; Menu.submenu ~label:"Export" [ Menu.item ~label:"PNG" ~action:"app.export-png" () ]
    ]
  in
  print_s [%sexp (menu : Menu.t)];
  [%expect
    {|
    ((Item ((label Open) (action app.open) (accel (<Control>o))))
     (Section (label (View))
      (entries
       ((Item ((label "Zoom In") (action view.zoom-in) (accel ())))
        (Item ((label Dark) (action view.theme::dark) (accel ()))))))
     (Submenu (label Export)
      (entries ((Item ((label PNG) (action app.export-png) (accel ())))))))
    |}];
  print_s [%sexp (Menu.equal menu menu : bool)];
  [%expect {| true |}];
  (* The references the resolution walk checks: depth-first, radio targets stripped. *)
  print_s [%sexp (Menu.action_references menu : string list)];
  [%expect {| (app.open view.zoom-in view.theme app.export-png) |}]
;;

(* The two constructor rejections on [Attr.actions]: duplicate names (two GSimpleActions
   fighting over one lookup) and a dotted or empty scope (resolution splits on the first
   dot, so either would make every reference ambiguous). *)
let%expect_test "Attr.actions rejects duplicate names and bad scopes" =
  Expect_test_helpers_core.require_does_raise (fun () ->
    Attr.actions
      ~scope:"app"
      [ Action_spec.simple ~name:"open" noop; Action_spec.simple ~name:"open" noop ]);
  [%expect
    {|
    (Invalid_argument
     "Attr.actions: two specs are named \"open\" in scope \"app\"")
    |}];
  Expect_test_helpers_core.require_does_raise (fun () ->
    Attr.actions ~scope:"a.b" [ Action_spec.simple ~name:"open" noop ]);
  [%expect
    {|
    (Invalid_argument
     "Attr.actions: scope \"a.b\" must be non-empty and contain no '.' (action references split on the first dot)")
    |}];
  Expect_test_helpers_core.require_does_raise (fun () ->
    Attr.actions ~scope:"" [ Action_spec.simple ~name:"open" noop ]);
  [%expect
    {|
    (Invalid_argument
     "Attr.actions: scope \"\" must be non-empty and contain no '.' (action references split on the first dot)")
    |}]
;;

(* The resolution walk, over the four shapes that decide it: an action on the menu button
   itself, one on an ancestor, one that is absent, and one that exists only on a sibling
   -- which is absent, because GTK resolves a popover's names against the button and its
   ancestors and nothing wider. *)
let%expect_test "action references resolve against self and ancestors only" =
  let menu_with action = [ Menu.item ~label:"x" ~action () ] in
  let button ?attrs action = Node.menu_button ?attrs ~menu:(menu_with action) () in
  let app_actions = Attr.actions ~scope:"app" [ Action_spec.simple ~name:"open" noop ] in
  (* On the button itself. *)
  Action_resolution.check
    ~path:"root"
    (Node.window (button ~attrs:[ app_actions ] "app.open"));
  print_s [%sexp "self resolves"];
  [%expect {| "self resolves" |}];
  (* On an ancestor. *)
  Action_resolution.check
    ~path:"root"
    (Node.window
       (Node.box ~orientation:Vertical ~attrs:[ app_actions ] [ button "app.open" ]));
  print_s [%sexp "ancestor resolves"];
  [%expect {| "ancestor resolves" |}];
  (* Absent altogether. *)
  Expect_test_helpers_core.require_does_raise (fun () ->
    Action_resolution.check
      ~path:"root"
      (Node.window
         (Node.box ~orientation:Vertical ~attrs:[ app_actions ] [ button "app.close" ])));
  [%expect
    {|
    (Invalid_argument
     "root/0/0: menu item action \"app.close\" resolves to no Attr.actions here or on an ancestor (scopes in reach: app)")
    |}];
  (* Present on a sibling, which is not in GTK's resolution path and so not in ours. *)
  Expect_test_helpers_core.require_does_raise (fun () ->
    Action_resolution.check
      ~path:"root"
      (Node.window
         (Node.box
            ~orientation:Vertical
            [ Node.label ~attrs:[ app_actions ] "holder"; button "app.open" ])));
  [%expect
    {|
    (Invalid_argument
     "root/0/1: menu item action \"app.open\" resolves to no Attr.actions here or on an ancestor (scopes in reach: none)")
    |}];
  (* A radio reference resolves by its "scope.name" half; the "::target" rides along. *)
  Action_resolution.check
    ~path:"root"
    (Node.window
       (button
          ~attrs:
            [ Attr.actions
                ~scope:"view"
                [ Action_spec.radio ~name:"theme" ~state:"light" (fun _ -> noop) ]
            ]
          "view.theme::dark"));
  print_s [%sexp "radio resolves"];
  [%expect {| "radio resolves" |}]
;;
