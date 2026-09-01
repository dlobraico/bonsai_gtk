open! Core
open Bonsai_gtk
open Bonsai.Let_syntax

(* The M3 counter: the smallest program that exercises every headline M3 feature at once,
   and the smoke run that would catch a menus-crash-on-open. One tree, two toplevels; a
   header bar whose menu button drives a real GMenu over real GActions; a chord and a menu
   item firing the same action; an alert shown as an effect and its answer read back into
   the model; a second window opened by the model and raised by [Effect.Window.present]
   when it is already open; and every close request handled, because since M3 the runtime
   vetoes them all -- a window closes when its node leaves the tree.

   The [Command.Registry] shape on purpose: one list of [Action_spec]s serves the menu's
   item names, the shortcut's target, and the handlers, which is the composition the
   action system is designed around. *)

let app (graph @ local) =
  let count, set_count = Bonsai.state 0 graph in
  let notes_open, set_notes_open = Bonsai.state false graph in
  let last_answer, set_last_answer = Bonsai.state "(not asked yet)" graph in
  let%arr count
  and set_count
  and notes_open
  and set_notes_open
  and last_answer
  and set_last_answer in
  let confirm_reset =
    (* An alert as an effect: show, bind the pressed index, act on it. Dismissal (Escape,
       the close button) answers the [~cancel] index, so the bind is total. *)
    let open Ui_effect.Let_syntax in
    let%bind answer =
      Effect.Alert_dialog.show
        ~detail:(sprintf "The count is %d." count)
        ~cancel:0
        ~buttons:[ "Keep counting"; "Reset" ]
        "Reset the count?"
    in
    Ui_effect.Many
      [ set_last_answer (if answer = 1 then "reset" else "kept")
      ; (if answer = 1 then set_count 0 else Ui_effect.Ignore)
      ]
  in
  let open_notes =
    (* The model opens the window; the effect raises it when it is already there. *)
    if notes_open then Effect.Window.present "notes" else set_notes_open true
  in
  let main_window =
    Node.window
      ~key:"main"
      ~title:"bonsai_gtk chrome"
      ~default_size:(420, 260)
      ~attrs:
        [ Attr.on_close_request Effect.quit
          (* The one action list: menu items and the chord below both resolve against it,
             GTK's own way -- from the referencing node upward. *)
        ; Attr.actions
            ~scope:"app"
            [ Action_spec.simple ~name:"increment" (set_count (count + 1))
            ; Action_spec.simple ~name:"reset" confirm_reset
            ; Action_spec.simple ~name:"notes" open_notes
            ; Action_spec.simple ~name:"quit" Effect.quit
            ]
        ; Attr.shortcut
            ~trigger:
              (Trigger.create
                 ~modifiers:{ Modifiers.none with control = true }
                 (Keyval.of_char 'n'))
            ~action:"app.notes"
            ()
        ; Attr.shortcut
            ~trigger:
              (Trigger.create
                 ~modifiers:{ Modifiers.none with control = true }
                 (Keyval.of_char 'q'))
            ~action:"app.quit"
            ()
        ]
      (Node.box
         ~orientation:Vertical
         [ Node.header_bar
             ~title:(Node.label ~attrs:[ Attr.css_class "title-4" ] "chrome")
             ~end_:
               [ Node.menu_button
                   ~key:"menu"
                   ~icon_name:"open-menu-symbolic"
                   ~primary:true
                   ~menu:
                     [ Menu.item ~label:"Increment" ~action:"app.increment" ()
                     ; Menu.item ~label:"Reset…" ~action:"app.reset" ()
                     ; Menu.section
                         ~label:""
                         [ Menu.item
                             ~label:"Notes window"
                             ~action:"app.notes"
                             ~accel:"<Control>n"
                             ()
                         ; Menu.item
                             ~label:"Quit"
                             ~action:"app.quit"
                             ~accel:"<Control>q"
                             ()
                         ]
                     ]
                   ()
               ]
             ()
         ; Node.box
             ~orientation:Vertical
             ~spacing:8
             ~attrs:[ Attr.margin 16; Attr.vexpand true ]
             [ Node.label ~attrs:[ Attr.css_class "title-2" ] (sprintf "Count: %d" count)
             ; Node.label (sprintf "last reset dialog: %s" last_answer)
             ; Node.button
                 ~attrs:[ Attr.halign Start; Attr.on_clicked (set_count (count + 1)) ]
                 ~label:"Increment (also in the menu)"
                 ()
             ; Node.button
                 ~attrs:[ Attr.halign Start; Attr.on_clicked open_notes ]
                 ~label:"Notes (Ctrl+N raises it once open)"
                 ()
             ]
         ])
  in
  let notes_window =
    Node.window
      ~key:"notes"
      ~title:"notes"
      ~default_size:(300, 200)
      ~transient_for:"main"
      ~attrs:[ Attr.on_close_request (set_notes_open false) ]
      (Node.box
         ~orientation:Vertical
         ~spacing:8
         ~attrs:[ Attr.margin 12 ]
         [ Node.entry ~attrs:[ Attr.autofocus true ] ~placeholder:"a note" ~text:"" ()
         ; Node.label "Closing this window removes its node; nothing else does."
         ])
  in
  Node.windows (main_window :: (if notes_open then [ notes_window ] else []))
;;

let () =
  exit
    (Bonsai_gtk.start
       ~application_id:"org.bonsai_gtk.examples.chrome"
       ~global_css:".title-2 { letter-spacing: 1px; }"
       app)
;;
