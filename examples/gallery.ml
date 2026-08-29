open! Core
open Bonsai_gtk
open Bonsai.Let_syntax

(* An 8x8 greyscale PNG, inlined as bytes and written to a temp file at startup. The
   gallery ships no data files, and [Node.picture]'s [Filename] source wants a real path;
   an application points this at a file it owns. *)
let sample_png =
  String.concat
    [ "\137PNG\013\010\026\010\000\000\000\013IHDR\000\000\000"
    ; "\008\000\000\000\008\008\000\000\000\000\225d\225W\000"
    ; "\000\0008IDATx\218%\202A\001\0000\008\195\192HA\010R\144"
    ; "\130\020\164 \165R\182n\207\246\002\145\213\179\034\168"
    ; "\156\214\146E\172z\238\014\180\211|\191\191\221\029vw"
    ; "\207\221\029\240u\028\001\130z\003p\000\000\000\000IEND"
    ; "\174B`\130"
    ]
;;

let sample_png_path =
  lazy
    (let path = Stdlib.Filename.temp_file "bonsai_gtk_gallery" ".png" in
     Out_channel.write_all path ~data:sample_png;
     path)
;;

(* Page 1: the toggle family and the entries, all controlled by one record of state. *)
let controls (graph @ local) =
  let toggled, set_toggled = Bonsai.state false graph in
  let checked, set_checked = Bonsai.state true graph in
  let switched, set_switched = Bonsai.state false graph in
  let text, set_text = Bonsai.state "" graph in
  let search, set_search = Bonsai.state "" graph in
  let%arr toggled
  and set_toggled
  and checked
  and set_checked
  and switched
  and set_switched
  and text
  and set_text
  and search
  and set_search in
  Node.grid
    ~row_spacing:8
    ~column_spacing:12
    ~attrs:[ Attr.margin 12 ]
    [ Node.label ~attrs:[ Attr.grid_cell ~column:0 ~row:0 () ] ~xalign:0. "Toggle"
    ; Node.toggle_button
        ~attrs:[ Attr.grid_cell ~column:1 ~row:0 (); Attr.on_toggled set_toggled ]
        ~label:(if toggled then "on" else "off")
        ~active:toggled
        ()
    ; Node.label ~attrs:[ Attr.grid_cell ~column:0 ~row:1 () ] ~xalign:0. "Check"
    ; Node.check_button
        ~attrs:[ Attr.grid_cell ~column:1 ~row:1 (); Attr.on_toggled set_checked ]
        ~label:"agree"
        ~active:checked
        ()
    ; Node.label ~attrs:[ Attr.grid_cell ~column:0 ~row:2 () ] ~xalign:0. "Switch"
    ; Node.switch
        ~attrs:
          [ Attr.grid_cell ~column:1 ~row:2 ()
          ; Attr.halign Start
          ; Attr.on_toggled set_switched
          ]
        ~active:switched
        ()
    ; Node.label ~attrs:[ Attr.grid_cell ~column:0 ~row:3 () ] ~xalign:0. "Entry"
    ; Node.entry
        ~attrs:
          [ Attr.grid_cell ~column:1 ~row:3 ()
          ; Attr.hexpand true
          ; Attr.on_changed set_text
          ]
        ~placeholder:"type here"
        ~text
        ()
    ; Node.label ~attrs:[ Attr.grid_cell ~column:0 ~row:4 () ] ~xalign:0. "Password"
    ; Node.password_entry
        ~attrs:[ Attr.grid_cell ~column:1 ~row:4 (); Attr.hexpand true ]
        ~placeholder:"passphrase"
        ~text:""
        ()
    ; Node.label ~attrs:[ Attr.grid_cell ~column:0 ~row:5 () ] ~xalign:0. "Search"
    ; Node.search_entry
        ~attrs:
          [ Attr.grid_cell ~column:1 ~row:5 ()
          ; Attr.hexpand true
          ; Attr.on_search_changed set_search
          ]
        ~text:search
        ()
    ; Node.label
        ~attrs:[ Attr.grid_cell ~column:0 ~row:6 ~width:2 () ]
        ~xalign:0.
        ~ellipsize:End
        (sprintf "text=%S search=%S" text search)
    ]
;;

(* Page 2: numbers and feedback, where one value drives four widgets. *)
let numbers (graph @ local) =
  let value, set_value = Bonsai.state 40. graph in
  let%arr value and set_value in
  Node.box
    ~orientation:Vertical
    ~spacing:8
    ~attrs:[ Attr.margin 12 ]
    [ Node.scale
        ~attrs:[ Attr.on_value_changed set_value; Attr.hexpand true ]
        ~orientation:Horizontal
        ~min:0.
        ~max:100.
        ~value
        ()
    ; Node.spin_button
        ~attrs:[ Attr.on_value_changed set_value; Attr.halign Start ]
        ~min:0.
        ~max:100.
        ~value
        ()
    ; Node.progress_bar ~fraction:(value /. 100.) ~show_text:true ()
    ; Node.separator ~orientation:Horizontal ()
    ; Node.box
        ~orientation:Horizontal
        ~spacing:8
        [ Node.spinner ~spinning:Float.(value > 50.) ()
        ; Node.label (sprintf "spinning above 50 (value = %.0f)" value)
        ]
    ]
;;

(* Page 3: the containers, including the overlay-over-a-spacer trick that caps a picture's
   allocated size. *)
let layout (graph @ local) =
  let expanded, set_expanded = Bonsai.state false graph in
  let revealed, set_revealed = Bonsai.state true graph in
  let%arr expanded and set_expanded and revealed and set_revealed in
  Node.paned
    ~orientation:Horizontal
    ~position:220
    ~start:
      (Node.scrolled_window
         ~hpolicy:Never
         ~vpolicy:Automatic
         (Node.box
            ~orientation:Vertical
            ~spacing:8
            ~attrs:[ Attr.margin 12 ]
            [ Node.frame ~label:"Frame" (Node.label ~attrs:[ Attr.margin 8 ] "framed")
            ; Node.expander
                ~attrs:[ Attr.on_expanded_changed set_expanded ]
                ~label:"Expander"
                ~expanded
                (Node.label ~attrs:[ Attr.margin 8 ] "detail")
            ; Node.button
                ~attrs:[ Attr.on_clicked (set_revealed (not revealed)) ]
                ~label:(if revealed then "Hide" else "Show")
                ()
            ; Node.revealer
                ~transition:Slide_down
                ~reveal:revealed
                (Node.label ~attrs:[ Attr.margin 8 ] "revealed")
            ; Node.box
                ~orientation:Horizontal
                ~spacing:8
                [ Node.image ~pixel_size:24 (Icon_name "image-x-generic-symbolic")
                ; Node.label "an icon, at 24px"
                ]
            ]))
    ~end_:
      (Node.center_box
         ~attrs:[ Attr.margin 12 ]
         ~start:(Node.label "start")
         ~center:
           (* A picture's natural size is its image's, so the only way to cap it is to
              measure something else: an unmeasured overlay over a spacer that asks for
              the size the picture is allowed to have. *)
           (Node.overlay
              ~overlays:
                [ Node.picture
                    ~attrs:[ Attr.measure_overlay false ]
                    ~content_fit:Contain
                    ~can_shrink:true
                    ~alternative_text:"a sample image"
                    (Filename (force sample_png_path))
                ]
              (Node.box
                 ~orientation:Vertical
                 ~attrs:[ Attr.width_request 150; Attr.height_request 194 ]
                 []))
         ~end_:(Node.label "end")
         ())
    ()
;;

let app (graph @ local) =
  let page, set_page = Bonsai.state "controls" graph in
  let controls = controls graph in
  let numbers = numbers graph in
  let layout = layout graph in
  let%arr page and set_page and controls and numbers and layout in
  Node.window
    ~title:"bonsai_gtk gallery"
    ~default_size:(900, 560)
    (* Both the sidebar and the switcher are declared *above* the stack they drive, and
       neither holds a widget: each names a stack that does not exist yet when it is
       mounted. That works because names are resolved in a fixup pass after the whole tree
       exists, so this layout is also that feature's demonstration. *)
    (Node.box
       ~orientation:Horizontal
       [ Node.stack_sidebar ~attrs:[ Attr.width_request 140 ] ~stack:"gallery" ()
       ; Node.separator ~orientation:Vertical ()
       ; Node.box
           ~orientation:Vertical
           ~attrs:[ Attr.hexpand true ]
           [ Node.stack_switcher
               ~attrs:[ Attr.halign Center; Attr.margin 8 ]
               ~stack:"gallery"
               ()
           ; Node.stack
               ~name:"gallery"
               ~visible_child:page
               ~transition:Crossfade
               ~attrs:[ Attr.vexpand true; Attr.on_visible_child_changed set_page ]
               [ Node.box
                   ~key:"controls"
                   ~attrs:[ Attr.page_title "Controls" ]
                   ~orientation:Vertical
                   [ controls ]
               ; Node.box
                   ~key:"numbers"
                   ~attrs:[ Attr.page_title "Numbers" ]
                   ~orientation:Vertical
                   [ numbers ]
               ; Node.box
                   ~key:"layout"
                   ~attrs:[ Attr.page_title "Layout" ]
                   ~orientation:Vertical
                   [ layout ]
               ]
           ]
       ])
;;

let () = exit (Bonsai_gtk.start ~application_id:"org.bonsai_gtk.examples.gallery" app)
