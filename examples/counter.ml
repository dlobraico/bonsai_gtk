open! Core
open Bonsai_gtk
open Bonsai.Let_syntax

let app (graph @ local) =
  let count, set_count = Bonsai.state 0 graph in
  let%arr count and set_count in
  Node.window
  (* Since M3 the runtime vetoes every close request -- a window closes only when its node
     leaves the tree -- so the X button needs a handler to mean anything. For a one-window
     app, quitting is what the user asked for. *)
    ~attrs:[ Attr.on_close_request Effect.quit ]
    ~title:"bonsai_gtk counter"
    ~default_size:(240, 120)
    (Node.box
       ~orientation:Vertical
       ~spacing:8
       ~attrs:[ Attr.margin 12 ]
       [ Node.label ~attrs:[ Attr.css_class "title-2" ] (sprintf "Count: %d" count)
       ; Node.box
           ~orientation:Horizontal
           ~spacing:8
           ~attrs:[ Attr.halign Center ]
           [ Node.button ~attrs:[ Attr.on_clicked (set_count (count - 1)) ] ~label:"−" ()
           ; Node.button
               ~attrs:
                 [ Attr.on_clicked (set_count (count + 1))
                 ; Attr.css_class "suggested-action"
                 ]
               ~label:"+"
               ()
           ; Node.button
               ~attrs:[ Attr.on_clicked (set_count 0); Attr.sensitive (count <> 0) ]
               ~label:"Reset"
               ()
           ]
       ; Node.button
           ~attrs:[ Attr.on_clicked Effect.quit; Attr.halign End ]
           ~label:"Quit"
           ()
       ])
;;

let () = exit (Bonsai_gtk.start ~application_id:"org.bonsai_gtk.examples.counter" app)
