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
  let note, set_note = Bonsai.state "" graph in
  let%arr toggled
  and set_toggled
  and checked
  and set_checked
  and switched
  and set_switched
  and text
  and set_text
  and search
  and set_search
  and note
  and set_note in
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
        ~attrs:[ Attr.grid_cell ~column:0 ~row:6 (); Attr.valign Start ]
        ~xalign:0.
        "Notes"
      (* The multi-line editor, in the scrolled window a text view belongs in: a bare one
         grows without limit and pushes the rest of the page off screen. Its text is
         controlled exactly as the entry's above is. *)
    ; Node.scrolled_window
        ~attrs:
          [ Attr.grid_cell ~column:1 ~row:6 ()
          ; Attr.hexpand true
          ; Attr.height_request 90
          ]
        ~has_frame:true
        (Node.text_view
           ~attrs:[ Attr.on_changed set_note ]
           ~wrap:Word_char
           ~left_margin:6
           ~right_margin:6
           ~top_margin:6
           ~bottom_margin:6
           ~text:note
           ())
      (* The caret policy, demonstrated rather than described: type a few words, put the
         caret in the middle of one of them, and press this. The model rewrites the whole
         text to something of the same length, the buffer is written, and the caret is
         still where it was -- which is the case the offset policy is exactly right about
         and the one that makes a model that rewrites as you type usable at all. *)
    ; Node.button
        ~attrs:
          [ Attr.grid_cell ~column:1 ~row:7 ()
          ; Attr.halign Start
          ; Attr.on_clicked (set_note (String.uppercase note))
          ]
        ~label:"Shout the note (the caret stays put)"
        ()
    ; Node.label
        ~attrs:[ Attr.grid_cell ~column:0 ~row:8 ~width:2 () ]
        ~xalign:0.
        ~ellipsize:End
        (sprintf "text=%S search=%S note=%d characters" text search (String.length note))
    ]
;;

(* Page 2: numbers and feedback, where one value drives six widgets -- and where the two
   ways of showing a number sit next to each other. A [progress_bar] shows how far along
   an operation is, in fractions of itself; a [level_bar] shows a level in the
   application's own units, and can draw it as discrete segments, which is the thing a
   progress bar cannot do at all.

   The drop-down is here rather than on the Lists page for the same reason it is not a
   container: its items are props. The "add a preset" button is what that costs and what
   it buys -- it changes the {i item list}, which is the one thing that rebuilds GTK's
   model, and the selection survives it because the library re-applies it in the same
   frame. Choosing a scale with the drop-down changes no items at all, so the model is
   left alone. *)
let scales = [ "percent (0-100)"; "rating (0-5)"; "eighths (0-8)" ]

let numbers (graph @ local) =
  let value, set_value = Bonsai.state 40. graph in
  let scale_names, set_scale_names = Bonsai.state scales graph in
  let scale, set_scale = Bonsai.state 0 graph in
  let%arr value
  and set_value
  and scale_names
  and set_scale_names
  and set_scale
  and scale in
  (* The chosen scale, as a range and a mode. [scale] is an index into [scale_names],
     which is exactly what [Attr.on_selected_changed] hands back -- there is no lookup
     table beside the widget and no key to translate. *)
  let top, mode =
    match List.nth scale_names scale with
    | Some "rating (0-5)" -> 5., Bonsai_gtk.Level_bar_mode.Discrete
    | Some "eighths (0-8)" -> 8., Bonsai_gtk.Level_bar_mode.Discrete
    | Some _ | None -> 100., Bonsai_gtk.Level_bar_mode.Continuous
  in
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
        [ Node.drop_down
            ~attrs:[ Attr.on_selected_changed set_scale ]
            ~items:scale_names
            ~selected:(if List.is_empty scale_names then -1 else scale)
            ()
        ; Node.button
            ~attrs:
              [ Attr.on_clicked
                  (set_scale_names
                     (scale_names @ [ sprintf "preset %d" (List.length scale_names - 2) ]))
              ]
            ~label:"Add a preset (rebuilds the model, keeps the selection)"
            ()
        ]
    ; Node.level_bar
        ~attrs:[ Attr.hexpand true ]
        ~min:0.
        ~max:top
        ~mode
        ~value:(value /. 100. *. top)
        ()
    ; Node.label
        ~xalign:0.
        (sprintf
           "level bar: %.2f of %.0f, %s"
           (value /. 100. *. top)
           top
           (match mode with
            | Discrete -> "discrete"
            | Continuous -> "continuous"))
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

(* Page 5: the one container whose children really move. A [GtkNotebook] has
   [reorder_child], so the page order is reconciled with real [Move] ops -- and the two
   buttons here are what that is for: they change the model's page {i list}, and the
   notebook reorders the pages in place rather than rebuilding them.

   What that preserves, and what a rebuild would lose, is {i widget-local} state: the
   entry on each page keeps its cursor position, its text selection and its focus across a
   move. The typed text itself would survive a rebuild too -- it lives in the model, like
   everything else here -- so it is not the demonstration; each page has its own state
   only so that typing on one tab does not echo into the other two. *)
let tabs (graph @ local) =
  let current, set_current = Bonsai.state "score" graph in
  let order, set_order = Bonsai.state [ "score"; "parts"; "notes" ] graph in
  (* One piece of state per page rather than one shared between them: three entries bound
     to a single string would echo each other, which reads as a bug in the demo. *)
  let texts, set_texts =
    Bonsai.state (String.Map.of_alist_exn [ "score", ""; "parts", ""; "notes", "" ]) graph
  in
  let%arr current and set_current and order and set_order and texts and set_texts in
  let title = function
    | "score" -> "Score"
    | "parts" -> "Parts"
    | _ -> "Notes"
  in
  let page key =
    Node.box
      ~key
      ~attrs:[ Attr.tab_label (title key) ]
      ~orientation:Vertical
      ~spacing:8
      [ Node.label ~attrs:[ Attr.margin 12 ] (sprintf "This is the %s page." (title key))
      ; Node.entry
          ~attrs:
            [ Attr.margin 12
            ; Attr.on_changed (fun text -> set_texts (Map.set texts ~key ~data:text))
            ]
          ~placeholder:"type here, put the cursor mid-word, then move the tab"
          ~text:(Map.find_exn texts key)
          ()
      ]
  in
  (* Move the current page one place in the list. The notebook does the rest, in one
     [reorder_child]: the page keeps its widgets, and the entry keeps its cursor and its
     selection -- neither of which is in the model and neither of which would survive the
     remove-and-re-insert an unkeyed list, or a container without a reorder primitive,
     would do instead. *)
  let move delta =
    match List.findi order ~f:(fun _ k -> String.equal k current) with
    | None -> Ui_effect.Ignore
    | Some (i, _) ->
      let j = i + delta in
      if j < 0 || j >= List.length order
      then Ui_effect.Ignore
      else (
        let without = List.filteri order ~f:(fun k _ -> k <> i) in
        set_order (List.take without j @ [ current ] @ List.drop without j))
  in
  Node.box
    ~orientation:Vertical
    ~spacing:12
    ~attrs:[ Attr.margin 12 ]
    [ Node.box
        ~orientation:Horizontal
        ~spacing:8
        [ Node.button ~label:"Move left" ~attrs:[ Attr.on_clicked (move (-1)) ] ()
        ; Node.button ~label:"Move right" ~attrs:[ Attr.on_clicked (move 1) ] ()
        ; Node.label (sprintf "order: %s" (String.concat ~sep:", " order))
        ]
    ; Node.notebook
        ~attrs:[ Attr.on_page_changed set_current; Attr.vexpand true ]
        ~current_page:current
        (List.map order ~f:page)
    ]
;;

(* Page 6: the containers, including the overlay-over-a-spacer trick that caps a picture's
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
  let tabs = tabs graph in
  let layout = layout graph in
  let%arr page
  and set_page
  and controls
  and numbers
  and lists
  and grid
  and tabs
  and layout in
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
                   ~key:"tabs"
                   ~attrs:[ Attr.page_title "Tabs" ]
                   ~orientation:Vertical
                   [ tabs ]
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
