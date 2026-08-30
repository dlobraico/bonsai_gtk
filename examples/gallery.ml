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

(* A fixed name rather than [Filename.temp_file]'s unique one: nothing removes this file,
   and nothing can -- GTK holds the path for as long as the picture might reload it, and
   the process is normally ended by a window close or a signal rather than by anything
   that would run an [at_exit]. A fixed name means one file in the temp directory however
   many times the gallery is run, instead of one per run. *)
let sample_png_path =
  lazy
    (let path =
       Stdlib.Filename.concat
         (Stdlib.Filename.get_temp_dir_name ())
         "bonsai_gtk_gallery.png"
     in
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

(* Page 3: a keyed list. Every row's identity is its [~key], which is what both handlers
   speak in -- there is no array of rows beside the widget and no index to translate. The
   header row is an ordinary row that refuses selection and activation. *)
let lists (graph @ local) =
  let chosen, set_chosen = Bonsai.state "sonatas" graph in
  let starred, set_starred = Bonsai.state [ "sonatas" ] graph in
  let%arr chosen and set_chosen and starred and set_starred in
  let row key label = Node.label ~key ~xalign:0. ~attrs:[ Attr.margin 8 ] label in
  Node.box
    ~orientation:Horizontal
    ~spacing:12
    ~attrs:[ Attr.margin 12 ]
    [ Node.frame
        ~label:"Single, activated"
        (Node.list_box
           ~attrs:[ Attr.on_row_activated set_chosen; Attr.width_request 200 ]
           ~selection_mode:Single
           ~show_separators:true
           ~selected:[ chosen ]
           [ Node.label
               ~key:"hdr"
               ~xalign:0.
               ~attrs:
                 [ Attr.margin 8
                 ; Attr.row_selectable false
                 ; Attr.row_activatable false
                 ; Attr.css_class "dim-label"
                 ]
               "COLLECTIONS"
           ; row "sonatas" "Sonatas"
           ; row "etudes" "Études"
           ; row "preludes" "Preludes"
           ])
    ; Node.frame
        ~label:"Multiple, selected"
        (Node.list_box
           ~attrs:[ Attr.on_selected_rows_changed set_starred; Attr.width_request 200 ]
           ~selection_mode:Multiple
           ~placeholder:(Node.label ~attrs:[ Attr.margin 12 ] "nothing to show")
           ~selected:starred
           [ row "sonatas" "Sonatas"; row "etudes" "Études"; row "preludes" "Preludes" ])
    ; Node.box
        ~orientation:Vertical
        ~spacing:8
        [ Node.label ~xalign:0. (sprintf "activated: %s" chosen)
        ; Node.label
            ~xalign:0.
            (sprintf
               "starred: %s"
               (if List.is_empty starred
                then "(none)"
                else String.concat ~sep:", " starred))
        ]
    ]
;;

(* Page 4: the same keyed machinery as a grid of cards, and the one thing a list cannot
   show -- the geometry is a prop, so "grid view" and "list view" are one toggle in the
   model rather than four setters and a CSS class. The grid activates on a double click,
   which is what lets a single click drive the toolbar and a double click open a card. *)
let grid (graph @ local) =
  let selected, set_selected = Bonsai.state [] graph in
  let opened, set_opened = Bonsai.state "(nothing)" graph in
  let as_list, set_as_list = Bonsai.state false graph in
  let%arr selected
  and set_selected
  and opened
  and set_opened
  and as_list
  and set_as_list in
  let card key label =
    Node.frame
      ~key
      (Node.label ~xalign:0. ~attrs:[ Attr.margin 12; Attr.width_request 120 ] label)
  in
  Node.box
    ~orientation:Vertical
    ~spacing:12
    ~attrs:[ Attr.margin 12 ]
    [ Node.box
        ~orientation:Horizontal
        ~spacing:8
        [ Node.toggle_button
            ~label:"List view"
            ~active:as_list
            ~attrs:[ Attr.on_toggled set_as_list ]
            ()
        ; Node.button
            ~label:"Edit"
              (* The selection {i is} the model, so a selection-dependent toolbar is an
                 expression rather than a callback that reaches over and sets properties. *)
            ~attrs:[ Attr.sensitive (not (List.is_empty selected)) ]
            ()
        ; Node.label (sprintf "%d selected, opened: %s" (List.length selected) opened)
        ]
    ; Node.flow_box
        ~attrs:
          [ Attr.on_child_activated set_opened
          ; Attr.on_selected_children_changed set_selected
          ; Attr.vexpand true
          ]
        ~selection_mode:Single
        ~activate_on_single_click:false
        ~min_children_per_line:1
        ~max_children_per_line:(if as_list then 1 else 4)
        ~homogeneous:as_list
        ~row_spacing:(if as_list then 0 else 12)
        ~column_spacing:(if as_list then 0 else 12)
        ~selected
        [ card "sonata" "Sonata in C"
        ; card "etude" "Étude Op. 10"
        ; card "nocturne" "Nocturne No. 2"
        ; card "prelude" "Prelude in E"
        ; card "waltz" "Waltz in A♭"
        ]
    ]
;;

(* Page 5: the containers, including the overlay-over-a-spacer trick that caps a picture's
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
  let lists = lists graph in
  let grid = grid graph in
  let layout = layout graph in
  let%arr page and set_page and controls and numbers and lists and grid and layout in
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
                   ~key:"lists"
                   ~attrs:[ Attr.page_title "Lists" ]
                   ~orientation:Vertical
                   [ lists ]
               ; Node.box
                   ~key:"grid"
                   ~attrs:[ Attr.page_title "Grid" ]
                   ~orientation:Vertical
                   [ grid ]
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
