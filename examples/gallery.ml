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

(* Page 1: the toggle family and the entries, all controlled by one record of state.

   {b Every controlled prop on this page is backed by a piece of state and by the attr
     that writes it},
   and that is not decoration. A controlled prop is re-asserted on every frame
   ([Widget_impl.reassert], run by [Patcher.reassert_only] on every node of every frame
   including a no-change one), and [Bonsai_gtk.start]'s scheduler ticks at 16 ms -- so a
   [~text] the model never learns about is written back over what the user typed about
   sixty times a second. Measured: an entry, password entry, search entry or editable
   label pinned to [""] with no [Attr.on_changed] shows [""] again one idle frame after a
   keystroke. The same holds for [~selected], [~active], [~value] and the rest. The audit
   is in task-13-report.md; the rule is one line:
   {i if a prop names something the user can change, the attr that reports the change must
     write the state the prop reads}. *)
let controls (graph @ local) =
  let toggled, set_toggled = Bonsai.state false graph in
  let checked, set_checked = Bonsai.state true graph in
  let switched, set_switched = Bonsai.state false graph in
  let text, set_text = Bonsai.state "" graph in
  let password, set_password = Bonsai.state "" graph in
  (* Two states for the one search box, because it has two signals. [search] is the text,
     written by [Attr.on_changed] on every keystroke -- which is what [~text] has to read,
     since the widget's text changes on every keystroke too. [query] is the {i debounced}
     [search-changed], [search_delay] ms after typing stops, which is what an application
     actually runs a search on. Wiring [~text] to the debounced one instead is the bug
     this page had: for the 150 ms before the debounce fires the model holds the old text,
     and the idle frame in between writes it back over what was typed. *)
  let search, set_search = Bonsai.state "" graph in
  let query, set_query = Bonsai.state "" graph in
  let note, set_note = Bonsai.state "" graph in
  let%arr toggled
  and set_toggled
  and checked
  and set_checked
  and switched
  and set_switched
  and text
  and set_text
  and password
  and set_password
  and search
  and set_search
  and query
  and set_query
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
        ~attrs:
          [ Attr.grid_cell ~column:1 ~row:4 ()
          ; Attr.hexpand true
          ; Attr.on_changed set_password
          ]
        ~placeholder:"passphrase"
        ~text:password
        ()
    ; Node.label ~attrs:[ Attr.grid_cell ~column:0 ~row:5 () ] ~xalign:0. "Search"
    ; Node.search_entry
        ~attrs:
          [ Attr.grid_cell ~column:1 ~row:5 ()
          ; Attr.hexpand true
          ; Attr.on_changed set_search
          ; Attr.on_search_changed set_query
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
        (* [search] follows every keystroke and [query] lags it by the debounce, so typing
           in the search box and stopping is how the two are told apart on screen. *)
        (sprintf
           "text=%S password=%d characters search=%S query=%S note=%d characters"
           text
           (String.length password)
           search
           query
           (String.length note))
    ]
;;

(* Page 2: numbers and feedback, where one value drives six widgets -- and where the two
   ways of showing a number sit next to each other. A [progress_bar] shows how far along
   an operation is, in fractions of itself; a [level_bar] shows a level in the
   application's own units, and can draw it as discrete segments, which is the thing a
   progress bar cannot do at all.

   The drop-down is here rather than on the Lists page for the same reason it is not a
   container: its items are props. The "add a preset" button is what that costs and what
   it buys -- it changes the {i item list}, which is the one thing that writes GTK's
   model, and the selection survives it because a whole-content splice carries the
   position across. Choosing a scale with the drop-down changes no items at all, so the
   model is not touched. *)
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
              (* No guard on [~selected]: an index the list does not (yet) hold is inert
                 and reported, not an exception, so the view says what the model means. *)
            ~items:scale_names
            ~selected:scale
            ()
        ; Node.button
            ~attrs:
              [ Attr.on_clicked
                  (set_scale_names
                     (scale_names @ [ sprintf "preset %d" (List.length scale_names - 2) ]))
              ]
            ~label:"Add a preset (writes the model, keeps the selection)"
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
         (* Both attrs, and the second is not optional. [~selected] is a controlled prop,
            re-asserted on every frame, and [row-activated] is not the signal that reports
            a {i selection}: a click emits both, but the arrow keys move the selection
            without activating anything. Wired to activation alone, the fixup pass puts
            the selection back on the next idle frame and the list cannot be browsed from
            the keyboard at all. Measured: select row 1 without activating it, and one
            [reassert_only] restores row 0. *)
           ~attrs:
             [ Attr.on_row_activated set_chosen
             ; Attr.on_selected_rows_changed (fun keys ->
                 match keys with
                 | key :: _ -> set_chosen key
                 | [] -> Ui_effect.Ignore)
             ; Attr.width_request 200
             ]
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

(* Page 7: the two widgets whose GTK API is not the one you would look for, and the two
   places that shows.

   The calendar's date is a [Date.t] and the model {i declines weekends} -- so picking a
   Saturday is the live demonstration of a controlled prop: the handler runs, the model
   keeps the Friday, Bonsai hands back a node that has not moved, nothing is diffed, and
   [Widget_impl.reassert] is the only thing left to put the calendar back. Click a
   Saturday and watch it snap.

   Walking with the heading arrows works too, and it is worth knowing why that is a claim
   rather than an obvious truth: a walk emits no [day-selected] at all, only
   [notify::month] or [notify::year], so [Attr.on_day_selected] is connected to all three
   and the model follows the walk. Wire only the day signal and the calendar snaps back to
   the model's month on the next frame -- which is what the first round of this widget
   did.

   The marks are the other half and are deliberately {i not} controlled: nothing the user
   does marks a day, so the button is how one gets marked. They are days of the month and
   survive a month change, which is visible by marking a day and then walking to another
   month with the heading arrows.

   The editable label is the page's own heading. Double-click it to edit; the model
   uppercases the first letter of every word as you type, which is the same "model
   rewrites what you typed" demonstration the Notes box on the Controls page makes and is
   worth making again here because the widget writes through [GtkEditable] rather than
   having a [set_text] of its own. Pressing Enter leaves editing mode and {i keeps} the
   text: [stop_editing ~commit:true] is the library's only choice, and the checkbox below
   drives the same state from the model side. *)
let dates (graph @ local) =
  let date, set_date = Bonsai.state (Date.of_string "2026-08-28") graph in
  let marks, set_marks = Bonsai.state [ 1 ] graph in
  let title, set_title = Bonsai.state "Rehearsal" graph in
  let editing, set_editing = Bonsai.state false graph in
  let%arr date
  and set_date
  and marks
  and set_marks
  and title
  and set_title
  and editing
  and set_editing in
  let day = Date.day date in
  Node.box
    ~orientation:Vertical
    ~spacing:8
    ~attrs:[ Attr.margin 12 ]
    [ Node.editable_label
        ~attrs:
          [ Attr.halign Start
          ; Attr.on_changed (fun t ->
              set_title
                (String.concat
                   ~sep:" "
                   (List.map (String.split t ~on:' ') ~f:String.capitalize)))
          ; Attr.on_editing_changed set_editing
          ]
        ~editing
        ~text:title
        ()
    ; Node.check_button
        ~attrs:[ Attr.on_toggled set_editing ]
        ~label:"Editing (the model drives it; leaving commits)"
        ~active:editing
        ()
    ; Node.separator ~orientation:Horizontal ()
    ; Node.calendar
        ~attrs:
          [ Attr.halign Start
          ; Attr.on_day_selected (fun d ->
              match Date.day_of_week d with
              | Sat | Sun -> Ui_effect.Ignore
              | Mon | Tue | Wed | Thu | Fri -> set_date d)
          ]
        ~show_week_numbers:true
        ~marked_days:marks
        ~date
        ()
    ; Node.box
        ~orientation:Horizontal
        ~spacing:8
        [ Node.button
            ~attrs:
              [ Attr.on_clicked
                  (set_marks
                     (if List.mem marks day ~equal:Int.equal
                      then List.filter marks ~f:(fun d -> d <> day)
                      else List.sort (day :: marks) ~compare:Int.compare))
              ]
            ~label:
              (if List.mem marks day ~equal:Int.equal
               then sprintf "Unmark day %d" day
               else sprintf "Mark day %d" day)
            ()
        ; Node.button ~attrs:[ Attr.on_clicked (set_marks []) ] ~label:"Clear marks" ()
        ]
    ; Node.label
        ~xalign:0.
        (sprintf
           !"%{Date} is a %{sexp: Day_of_week.t}; marked %s%s"
           date
           (Date.day_of_week date)
           (if List.is_empty marks
            then "nothing"
            else String.concat ~sep:", " (List.map marks ~f:Int.to_string))
           (if editing then "; editing" else ""))
    ; Node.label
        ~xalign:0.
        ~ellipsize:End
        "Weekends are declined by the model: pick a Saturday and the calendar snaps back."
    ]
;;

(* Page 8: the event controllers -- and the only place in this repository where a real
   click or a real keystroke is shown reaching a handler at all.

   {b This page is load-bearing rather than decorative.} The pinned ocgtk binding can
   construct no [GdkEvent] and can emit no signal carrying arguments, so no automated test
   in this repository delivers a real click or a real key press. What
   [test/live/live_controllers_*.ml] proves is that the controller is attached, named,
   given the phase the attr asked for, and removed again; what
   [Bonsai_gtk_test.Action.Click_at] and [Key_press] prove is that the handler does the
   right thing when something calls it. The step in between -- GTK routing a real button
   press or a real keystroke into that handler -- is demonstrated here and nowhere else,
   by a person clicking and typing on a real display. [docs/m2-backlog.md] carries the gap
   with the condition that would close it.

   So the check, and it is worth doing by hand before the milestone closes: click the card
   with each mouse button and with modifiers held, then double-click it. Type in the entry
   and watch the key readout follow every keystroke {i while the text still arrives} --
   that is [Propagate_and], observing without consuming. Press Escape and watch the
   counter move and the entry not receive it -- that is [Handled_and], on a controller in
   the CAPTURE phase, which is what a window-wide shortcut needs and what stavekeeper's
   [dialog.ml] learned the hard way. Tab between the two entries and watch the focus
   readout name which one has it. If any of those readouts does not move, the controller
   machinery is broken however green the suite is. *)
let input (graph @ local) =
  let key, set_key = Bonsai.state "(nothing yet)" graph in
  let escapes, set_escapes = Bonsai.state 0 graph in
  let click, set_click = Bonsai.state "(nothing yet)" graph in
  let focus, set_focus = Bonsai.state "(neither)" graph in
  let text, set_text = Bonsai.state "" graph in
  let second, set_second = Bonsai.state "" graph in
  let%arr key
  and set_key
  and escapes
  and set_escapes
  and click
  and set_click
  and focus
  and set_focus
  and text
  and set_text
  and second
  and set_second in
  let modifiers (m : Modifiers.t) =
    match
      List.filter_map
        [ "ctrl", m.control; "shift", m.shift; "alt", m.alt; "super", m.super ]
        ~f:(fun (name, held) -> if held then Some name else None)
    with
    | [] -> "no modifiers"
    | held -> String.concat ~sep:"+" held
  in
  Node.box
    ~orientation:Vertical
    ~spacing:8
    ~attrs:
      [ Attr.margin 12
        (* CAPTURE, so this box sees a key before the entry inside it does. The two key
           attrs share one [GtkEventControllerKey] and therefore one phase; a node that
           asks for two different ones is refused before anything is mounted. *)
      ; Attr.on_key_pressed ~phase:Capture (fun (event : Key_event.t) ->
          if event.keyval = Keyval.escape
          then
            (* Consume the key {i and} do something: the entry never sees this one. *)
            Key_response.Handled_and
              (Ui_effect.Many
                 [ set_escapes (escapes + 1); set_key "Escape -- consumed here" ])
          else
            (* Observe without consuming, so every other key still reaches the entry. *)
            Key_response.Propagate_and
              (set_key
                 (sprintf "keyval 0x%x, %s" event.keyval (modifiers event.modifiers))))
      ; Attr.on_key_released ~phase:Capture (fun _ -> Ui_effect.Ignore)
      ]
    [ Node.label
        ~xalign:0.
        (* "the words", not "the card": [Attr.on_click] is on the label, and a widget's
           [Attr.margin] is space outside its allocation, so the 24px of padding that
           makes the card look like a target is not one. Measured with xdotool under Xvfb
           in M2's Task 16 -- a click 14px below the text moved no readout. Putting the
           gesture on the frame instead would make the whole card live; it is on the
           backlog, because which of the two the page should demonstrate is a choice and
           not a bug. *)
        "Click the words below, type in the entries, press Escape, and Tab between them."
    ; Node.frame
        ~label:"A click gesture, any button"
        (* [~button] defaults to 0, which is "any of them", so the readout can show which
           button actually fired -- the middle and secondary buttons included, which a
           [GtkButton] would never report. *)
        (Node.label
           ~attrs:
             [ Attr.margin 24
             ; Attr.cursor_name "pointer"
             ; Attr.on_click (fun (event : Click_event.t) ->
                 Click_response.Continue_and
                   (set_click
                      (sprintf
                         "button %d, press %d, at (%.0f, %.0f), %s"
                         event.button
                         event.n_press
                         event.x
                         event.y
                         (modifiers event.modifiers))))
             ]
           "click me")
    ; Node.box
        ~orientation:Horizontal
        ~spacing:8
        [ Node.entry
            ~attrs:
              [ Attr.hexpand true
              ; Attr.on_changed set_text
              ; Attr.on_focus_enter (fun () -> set_focus "first entry")
              ; Attr.on_focus_leave (fun () -> set_focus "(neither)")
              ]
            ~placeholder:"type here; Escape never arrives"
            ~text
            ()
          (* Its own state, not a second view of the first entry's: [~text] is controlled
             and re-asserted every frame, so an entry pinned to a constant erases whatever
             is typed into it on the next idle tick -- and on {i this} page more surely
             than anywhere else, because the capture-phase handler above schedules an
             effect for every key, which guarantees a frame per keystroke. A page whose
             whole job is to be believed by a person cannot contain a box that eats
             typing. *)
        ; Node.entry
            ~attrs:
              [ Attr.hexpand true
              ; Attr.on_changed set_second
              ; Attr.on_focus_enter (fun () -> set_focus "second entry")
              ; Attr.on_focus_leave (fun () -> set_focus "(neither)")
              ]
            ~placeholder:"Tab to me"
            ~text:second
            ()
        ]
    ; Node.separator ~orientation:Horizontal ()
    ; Node.label ~xalign:0. (sprintf "last key:   %s" key)
    ; Node.label
        ~xalign:0.
        (sprintf "escapes:    %d (consumed in the capture phase)" escapes)
    ; Node.label ~xalign:0. (sprintf "last click: %s" click)
    ; Node.label ~xalign:0. (sprintf "focus:      %s" focus)
    ]
;;

let app (graph @ local) =
  let page, set_page = Bonsai.state "controls" graph in
  let controls = controls graph in
  let numbers = numbers graph in
  let lists = lists graph in
  let grid = grid graph in
  let tabs = tabs graph in
  let layout = layout graph in
  let dates = dates graph in
  let input = input graph in
  let%arr page
  and set_page
  and controls
  and numbers
  and lists
  and grid
  and tabs
  and layout
  and dates
  and input in
  Node.window
  (* The counter's close handler, for the counter's reason: the runtime vetoes every close
     request, so the X button quits only because this says so. *)
    ~attrs:[ Attr.on_close_request Effect.quit ]
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
               ; Node.box
                   ~key:"dates"
                   ~attrs:[ Attr.page_title "Dates" ]
                   ~orientation:Vertical
                   [ dates ]
               ; Node.box
                   ~key:"input"
                   ~attrs:[ Attr.page_title "Input" ]
                   ~orientation:Vertical
                   [ input ]
               ]
           ]
       ])
;;

let () = exit (Bonsai_gtk.start ~application_id:"org.bonsai_gtk.examples.gallery" app)
