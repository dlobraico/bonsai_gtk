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

(* The charset rejections. GLib validates action names nowhere the runtime touches
   ([g_simple_action_new] accepts anything, probed), so a bad name's first parser is
   [g_menu_item_set_detailed_action] -- whose answer to a parse failure is [g_error], a
   process abort ("Detailed action name 'app.my act' has invalid format", SIGABRT under
   xvfb). The resolution walk cannot catch it: declared and referenced are the same
   string, so a malformed pair *resolves*. Hence the constructors reject GLib's
   [g_action_name_is_valid] class violations where the typo is. *)
let%expect_test "Action_spec names and Attr.actions scopes are held to GTK's charset" =
  (* The natural typo: a space. Live this is the aborting case. *)
  Expect_test_helpers_core.require_does_raise (fun () ->
    Action_spec.simple ~name:"my act" noop);
  [%expect
    {|
    (Invalid_argument
     "Action_spec: name \"my act\" must be non-empty and contain only [A-Za-z0-9.-] (GTK's action-name charset -- anything else aborts in GLib's detailed-action parser)")
    |}];
  (* Empty: parses live ("app." splits at the first dot) but no group can serve the empty
     name -- a certified item that renders inert. *)
  Expect_test_helpers_core.require_does_raise (fun () ->
    Action_spec.toggle ~name:"" ~state:false noop);
  [%expect
    {|
    (Invalid_argument
     "Action_spec: name \"\" must be non-empty and contain only [A-Za-z0-9.-] (GTK's action-name charset -- anything else aborts in GLib's detailed-action parser)")
    |}];
  (* Parentheses: "app.do('x')" parses live as a *targeted* activation of "app.do" -- a
     silent retarget, not an abort. *)
  Expect_test_helpers_core.require_does_raise (fun () ->
    Action_spec.radio ~name:"do('x')" ~state:"x" (fun _ -> noop));
  [%expect
    {|
    (Invalid_argument
     "Action_spec: name \"do('x')\" must be non-empty and contain only [A-Za-z0-9.-] (GTK's action-name charset -- anything else aborts in GLib's detailed-action parser)")
    |}];
  (* The scope half of the same abort ("my app.act" dies in the same parser). *)
  Expect_test_helpers_core.require_does_raise (fun () ->
    Attr.actions ~scope:"my app" [ Action_spec.simple ~name:"act" noop ]);
  [%expect
    {|
    (Invalid_argument
     "Attr.actions: scope \"my app\" must contain only [A-Za-z0-9-] (GTK's action-name charset -- anything else aborts in GLib's detailed-action parser)")
    |}];
  (* Dots and dashes are inside the class, and dotted names really do resolve (the walk
     splits references at the first dot only). *)
  ignore
    (Attr.actions ~scope:"app-2" [ Action_spec.simple ~name:"file.open-recent" noop ]
     : Attr.t);
  print_s [%sexp "dots and dashes pass"];
  [%expect {| "dots and dashes pass" |}]
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
     "root/0/0: action reference \"app.close\" resolves to no Attr.actions here or on an ancestor (scopes in reach: app)")
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
     "root/0/1: action reference \"app.open\" resolves to no Attr.actions here or on an ancestor (scopes in reach: none)")
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

(* The trigger is plain data with a display label -- GTK's accelerator spelling, never
   parsed by anything ([Shortcut_trigger.parse_string] wraps NULL on garbage; pre-flight
   correction 7 is why the runtime builds triggers from this record instead). *)
let%expect_test "a trigger sexps and labels" =
  let t =
    Trigger.create ~modifiers:{ Modifiers.none with control = true } (Keyval.of_char 'k')
  in
  print_s [%sexp (t : Trigger.t)];
  [%expect
    {|
    ((key 107)
     (modifiers
      ((shift false) (control true) (alt false) (super false) (hyper false)
       (meta false))))
    |}];
  printf "%s\n" (Trigger.to_label t);
  [%expect {| <Control>k |}];
  printf
    "%s\n"
    (Trigger.to_label
       (Trigger.create
          ~modifiers:{ Modifiers.none with shift = true; alt = true }
          Keyval.escape));
  [%expect {| <Shift><Alt>Escape |}];
  printf "%s\n" (Trigger.to_label (Trigger.create Keyval.comma));
  [%expect {| , |}]
;;

(* The attr is repeatable: every [Attr.shortcut] on a node accumulates into one keyed
   entry, which is what lets them share the node's one controller and lets the phase
   rejection see them all. The whole record is structural (an action is a name, not a
   closure), so an unchanged frame diffs to nothing -- unlike every other event attr. *)
let%expect_test "shortcuts accumulate, sexp, and diff structurally" =
  let ctrl c =
    Trigger.create ~modifiers:{ Modifiers.none with control = true } (Keyval.of_char c)
  in
  let attrs =
    Attrs.of_list
      [ Attr.shortcut ~trigger:(ctrl 'k') ~action:"app.pick" ()
      ; Attr.shortcut ~phase:Capture ~trigger:(ctrl 'o') ~action:"app.open" ()
      ]
  in
  print_s [%sexp (attrs : Attrs.t)];
  [%expect
    {|
    ((Shortcut
      (((trigger
         ((key 107)
          (modifiers
           ((shift false) (control true) (alt false) (super false) (hyper false)
            (meta false)))))
        (phase Bubble) (action app.pick))
       ((trigger
         ((key 111)
          (modifiers
           ((shift false) (control true) (alt false) (super false) (hyper false)
            (meta false)))))
        (phase Capture) (action app.open)))))
    |}];
  let same =
    Attrs.of_list
      [ Attr.shortcut ~trigger:(ctrl 'k') ~action:"app.pick" ()
      ; Attr.shortcut ~phase:Capture ~trigger:(ctrl 'o') ~action:"app.open" ()
      ]
  in
  print_s [%sexp (Attrs.diff ~old:attrs ~new_:same : Attrs.op list)];
  [%expect {| () |}];
  (* A "::target" is rejected at the constructor: the shipped path activates through a
     parameterless GtkNamedAction, so the syntax would promise a parameter it cannot pass.
     Targeted shortcuts are feasible (ocgtk binds [Shortcut.set_arguments]) and
     deliberately unshipped -- see docs/m3-backlog.md. *)
  Expect_test_helpers_core.require_does_raise (fun () ->
    Attr.shortcut ~trigger:(ctrl 't') ~action:"app.theme::dark" ());
  [%expect
    {|
    (Invalid_argument
     "Attr.shortcut: action \"app.theme::dark\" carries a \"::target\", but targeted shortcuts are not shipped in M3 (activation goes through a parameterless GtkNamedAction; Shortcut.set_arguments is the unshipped path)")
    |}]
;;

(* A shortcut's reference goes through the same walk, and the same string, as a menu
   item's. *)
let%expect_test "a shortcut naming a missing action is rejected by the walk" =
  Expect_test_helpers_core.require_does_raise (fun () ->
    Action_resolution.check
      ~path:"root"
      (Node.window
         (Node.label
            ~attrs:
              [ Attr.shortcut
                  ~trigger:(Trigger.create Keyval.escape)
                  ~action:"app.missing"
                  ()
              ]
            "sheet")));
  [%expect
    {|
    (Invalid_argument
     "root/0: action reference \"app.missing\" resolves to no Attr.actions here or on an ancestor (scopes in reach: none)")
    |}]
;;

(* Fix round: the two new rejections. One trigger naming two actions on one node is an
   order accident (which one ran would depend on install history), refused with one string
   from the runtime and the handle; and a shortcut resolving to a radio is refused by the
   walk -- targeted shortcuts are feasible (Shortcut.set_arguments is bound) and
   deliberately unshipped. *)
let%expect_test "shortcut conflicts and radio targets are rejected" =
  let ctrl c =
    Trigger.create ~modifiers:{ Modifiers.none with control = true } (Keyval.of_char c)
  in
  let conflicted =
    Attrs.of_list
      [ Attr.shortcut ~trigger:(ctrl 'k') ~action:"app.a" ()
      ; Attr.shortcut ~trigger:(ctrl 'k') ~action:"app.b" ()
      ]
  in
  print_s
    [%sexp (Events.shortcut_conflict_rejection ~path:"root/0" conflicted : string option)];
  [%expect
    {|
    ("root/0: two Attr.shortcuts share the trigger <Control>k but name different actions (\"app.a\" and \"app.b\"); which one ran would be an accident of order, so the node is rejected")
    |}];
  (* Same trigger, same action: legal, and collapses to one installed shortcut. *)
  let doubled =
    Attrs.of_list
      [ Attr.shortcut ~trigger:(ctrl 'k') ~action:"app.a" ()
      ; Attr.shortcut ~trigger:(ctrl 'k') ~action:"app.a" ()
      ]
  in
  print_s
    [%sexp (Events.shortcut_conflict_rejection ~path:"root/0" doubled : string option)];
  [%expect {| () |}];
  (* The walk refuses a shortcut resolving to a radio spec outright. *)
  Expect_test_helpers_core.require_does_raise (fun () ->
    Action_resolution.check
      ~path:"root"
      (Node.window
         (Node.label
            ~attrs:
              [ Attr.actions
                  ~scope:"view"
                  [ Action_spec.radio ~name:"theme" ~state:"light" (fun _ -> noop) ]
              ; Attr.shortcut ~trigger:(ctrl 't') ~action:"view.theme" ()
              ]
            "sheet")));
  [%expect
    {|
    (Invalid_argument
     "root/0: shortcut action \"view.theme\" names a radio action; targeted shortcuts are not shipped in M3 (wrap the choice in a Simple action, or see the backlog entry on Shortcut.set_arguments)")
    |}];
  (* A MENU item naming the radio stays legal -- the refusal is the shortcut's. *)
  Action_resolution.check
    ~path:"root"
    (Node.window
       (Node.menu_button
          ~attrs:
            [ Attr.actions
                ~scope:"view"
                [ Action_spec.radio ~name:"theme" ~state:"light" (fun _ -> noop) ]
            ]
          ~menu:[ Menu.item ~label:"Dark" ~action:"view.theme::dark" () ]
          ()));
  print_s [%sexp "menu radio still resolves"];
  [%expect {| "menu radio still resolves" |}]
;;
