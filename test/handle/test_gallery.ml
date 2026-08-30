open! Core
open Bonsai_gtk_vtree
open Bonsai.Let_syntax

(* The view half of [examples/gallery.ml], reproduced as a component that mentions no
   ocgtk type -- which is the rule the README states about keeping view functions in a
   vtree-only library, worked through on the largest tree this repository has.

   Every M1 and M2 [Node] constructor appears here exactly once, and its value is
   coverage: a constructor whose defaults change, or a children shape that stops being
   legal, shows up as a diff in this one snapshot rather than as a runtime failure in
   somebody's app. *)
let every_widget (graph @ local) =
  let n, set_n = Bonsai.state 0 graph in
  let%arr n and set_n in
  Node.window
    ~title:"every widget"
    ~default_size:(900, 560)
    (Node.box
       ~orientation:Horizontal
       [ Node.stack_sidebar ~attrs:[ Attr.width_request 140 ] ~stack:"all" ()
       ; Node.separator ~orientation:Vertical ()
       ; Node.box
           ~orientation:Vertical
           ~attrs:[ Attr.hexpand true ]
           [ Node.stack_switcher ~attrs:[ Attr.halign Center ] ~stack:"all" ()
           ; Node.stack
               ~name:"all"
               ~visible_child:"leaves"
               ~transition:Crossfade
               ~attrs:[ Attr.vexpand true ]
               [ Node.box
                   ~key:"leaves"
                   ~attrs:[ Attr.page_title "Leaves" ]
                   ~orientation:Vertical
                   ~spacing:8
                   [ Node.label
                       ~xalign:0.
                       ~ellipsize:End
                       ~max_width_chars:14
                       ~wrap:true
                       ~width_chars:10
                       ~selectable:true
                       ~use_markup:true
                       "label"
                   ; Node.button
                       ~attrs:[ Attr.test_id "inc"; Attr.on_clicked (set_n (n + 1)) ]
                       ~label:"button"
                       ()
                   ; Node.button ~icon_name:"list-add-symbolic" ~has_frame:false ()
                   ; Node.button ~child:(Node.label "child") ()
                   ; Node.toggle_button
                       ~attrs:[ Attr.on_toggled (fun _ -> Ui_effect.Ignore) ]
                       ~label:"toggle"
                       ~active:(n % 2 = 0)
                       ()
                   ; Node.check_button
                       ~attrs:[ Attr.on_toggled (fun _ -> Ui_effect.Ignore) ]
                       ~label:"check"
                       ~inconsistent:true
                       ~active:false
                       ()
                   ; Node.switch
                       ~attrs:[ Attr.on_toggled (fun _ -> Ui_effect.Ignore) ]
                       ~active:true
                       ()
                   ; Node.entry
                       ~attrs:
                         [ Attr.on_changed (fun _ -> Ui_effect.Ignore)
                         ; Attr.on_activate Ui_effect.Ignore
                         ]
                       ~placeholder:"entry"
                       ~text:""
                       ()
                   ; Node.password_entry ~show_peek_icon:false ~text:"" ()
                   ; Node.search_entry
                       ~attrs:[ Attr.on_search_changed (fun _ -> Ui_effect.Ignore) ]
                       ~search_delay:200
                       ~text:""
                       ()
                   ; Node.spin_button
                       ~attrs:[ Attr.on_value_changed (fun _ -> Ui_effect.Ignore) ]
                       ~digits:2
                       ~min:0.
                       ~max:10.
                       ~value:(Float.of_int n)
                       ()
                   ; Node.scale
                       ~attrs:[ Attr.on_value_changed (fun _ -> Ui_effect.Ignore) ]
                       ~orientation:Horizontal
                       ~min:0.
                       ~max:10.
                       ~value:0.
                       ()
                   ; Node.progress_bar ~fraction:0.5 ~show_text:true ()
                   ; Node.spinner ~spinning:true ()
                   ; Node.image ~pixel_size:24 (Icon_name "list-add-symbolic")
                   ; Node.picture ~alternative_text:"nothing" Empty
                   ; Node.separator ~orientation:Horizontal ()
                   ]
               ; Node.box
                   ~key:"containers"
                   ~attrs:[ Attr.page_title "Containers" ]
                   ~orientation:Vertical
                   ~spacing:8
                   [ Node.scrolled_window
                       ~hpolicy:Never
                       ~min_content_height:120
                       (Node.label "scrolled")
                   ; Node.frame ~label:"frame" (Node.label "framed")
                   ; Node.expander
                       ~attrs:[ Attr.on_expanded_changed (fun _ -> Ui_effect.Ignore) ]
                       ~label:"expander"
                       ~expanded:false
                       (Node.label "detail")
                   ; Node.revealer
                       ~attrs:[ Attr.on_revealed (fun _ -> Ui_effect.Ignore) ]
                       ~transition:Slide_down
                       ~reveal:true
                       (Node.label "revealed")
                   ; Node.grid
                       ~row_spacing:8
                       ~column_spacing:12
                       [ Node.label
                           ~key:"cell"
                           ~attrs:[ Attr.grid_cell ~column:0 ~row:0 () ]
                           "cell"
                       ]
                     (* Every row keyed, both handlers speaking in keys, both row
                        placement attrs on the header, and a placeholder that is a child
                        but not a row. *)
                   ; Node.list_box
                       ~attrs:
                         [ Attr.on_row_activated (fun _ -> Ui_effect.Ignore)
                         ; Attr.on_selected_rows_changed (fun _ -> Ui_effect.Ignore)
                         ]
                       ~selection_mode:Multiple
                       ~activate_on_single_click:false
                       ~show_separators:true
                       ~placeholder:(Node.label "empty")
                       ~selected:[ "row" ]
                       [ Node.label
                           ~key:"hdr"
                           ~attrs:
                             [ Attr.row_selectable false; Attr.row_activatable false ]
                           "header"
                       ; Node.label ~key:"row" "row"
                       ]
                     (* Every optional argument of the other keyed container, including
                        the two whose defaults are surprises ([~max_children_per_line] is
                        7, not unlimited; [~activate_on_single_click] is [true]). No
                        per-child attrs, because a [GtkFlowBoxChild] has none. *)
                   ; Node.flow_box
                       ~attrs:
                         [ Attr.on_child_activated (fun _ -> Ui_effect.Ignore)
                         ; Attr.on_selected_children_changed (fun _ -> Ui_effect.Ignore)
                         ]
                       ~selection_mode:Single
                       ~activate_on_single_click:false
                       ~min_children_per_line:1
                       ~max_children_per_line:4
                       ~row_spacing:12
                       ~column_spacing:12
                       ~homogeneous:true
                       ~orientation:Horizontal
                       ~selected:[ "card" ]
                       [ Node.label ~key:"card" "card" ]
                     (* Every prop, and the one per-page attr. The notebook is the only
                        container here whose children are reconciled with real [Move] ops,
                        so its page list is also the coverage for
                        [Widget_impl.list_ops.move] being [Some]. *)
                   ; Node.notebook
                       ~attrs:[ Attr.on_page_changed (fun _ -> Ui_effect.Ignore) ]
                       ~scrollable:true
                       ~show_tabs:true
                       ~show_border:false
                       ~tab_pos:Bottom
                       ~current_page:"page"
                       [ Node.label ~key:"page" ~attrs:[ Attr.tab_label "Page" ] "page" ]
                   ]
               ; Node.box
                   ~key:"slots"
                   ~attrs:[ Attr.page_title "Slots" ]
                   ~orientation:Vertical
                   ~spacing:8
                   [ Node.center_box
                       ~start:(Node.label "start")
                       ~center:(Node.label "center")
                       ~end_:(Node.label "end")
                       ()
                   ; Node.paned
                       ~attrs:[ Attr.on_position_changed (fun _ -> Ui_effect.Ignore) ]
                       ~orientation:Vertical
                       ~position:120
                       ~start:(Node.label "top")
                       ~end_:(Node.label "bottom")
                       ()
                   ; Node.overlay
                       ~overlays:
                         [ Node.label
                             ~key:"badge"
                             ~attrs:[ Attr.measure_overlay false ]
                             "over"
                         ]
                       (Node.box
                          ~orientation:Vertical
                          ~attrs:[ Attr.width_request 150; Attr.height_request 60 ]
                          [])
                     (* The escape hatch is a [Node] constructor like any other, so it
                        belongs in the sweep. Headless it needs no widget module: the
                        placeholder payload is enough to print and to diff. *)
                   ; Node.native { Native.name = "Placeholder"; payload = Native.Unit }
                   ]
               ]
           ]
       ])
;;

let%expect_test "every M1 and M2 widget builds a legal node" =
  let handle = Bonsai_gtk_test.create every_widget in
  Bonsai_gtk_test.Handle.show handle;
  [%expect
    {|
    ((kind (Window ((title ("every widget")) (default_size ((900 560))))))
     (attrs ())
     (children
      (Single
       (((kind (Box ((orientation Horizontal)))) (attrs ())
         (children
          (List
           (((kind (Stack_sidebar ((stack all)))) (attrs ((Width_request 140)))
             (children No_children))
            ((kind (Separator ((orientation Vertical)))) (attrs ())
             (children No_children))
            ((kind (Box ((orientation Vertical)))) (attrs ((Hexpand true)))
             (children
              (List
               (((kind (Stack_switcher ((stack all)))) (attrs ((Halign Center)))
                 (children No_children))
                ((kind
                  (Stack
                   ((name all) (visible_child leaves) (transition Crossfade))))
                 (attrs ((Vexpand true)))
                 (children
                  (List
                   (((kind (Box ((orientation Vertical) (spacing 8))))
                     (key leaves) (attrs ((Page_title Leaves)))
                     (children
                      (List
                       (((kind
                          (Label
                           ((text label) (wrap true) (xalign 0) (ellipsize (End))
                            (max_width_chars 14) (width_chars 10)
                            (selectable true) (use_markup true))))
                         (attrs ()) (children No_children))
                        ((kind (Button ((label (button)))))
                         (attrs ((Test_id inc) (On_clicked <handler>)))
                         (children (Single ())))
                        ((kind
                          (Button
                           ((icon_name (list-add-symbolic)) (has_frame false))))
                         (attrs ()) (children (Single ())))
                        ((kind (Button ())) (attrs ())
                         (children
                          (Single
                           (((kind (Label ((text child)))) (attrs ())
                             (children No_children))))))
                        ((kind (Toggle_button ((label (toggle)) (active true))))
                         (attrs ((On_toggled <handler>))) (children (Single ())))
                        ((kind
                          (Check_button
                           ((label (check)) (active false) (inconsistent true))))
                         (attrs ((On_toggled <handler>))) (children No_children))
                        ((kind (Switch ((active true))))
                         (attrs ((On_toggled <handler>))) (children No_children))
                        ((kind (Entry ((text "") (placeholder (entry)))))
                         (attrs ((On_changed <handler>) (On_activate <handler>)))
                         (children No_children))
                        ((kind
                          (Password_entry ((text "") (show_peek_icon false))))
                         (attrs ()) (children No_children))
                        ((kind (Search_entry ((text "") (search_delay (200)))))
                         (attrs ((On_search_changed <handler>)))
                         (children No_children))
                        ((kind
                          (Spin_button ((value 0) (min 0) (max 10) (digits 2))))
                         (attrs ((On_value_changed <handler>)))
                         (children No_children))
                        ((kind
                          (Scale
                           ((orientation Horizontal) (value 0) (min 0) (max 10))))
                         (attrs ((On_value_changed <handler>)))
                         (children No_children))
                        ((kind (Progress_bar ((fraction 0.5) (show_text true))))
                         (attrs ()) (children No_children))
                        ((kind (Spinner ((spinning true)))) (attrs ())
                         (children No_children))
                        ((kind
                          (Image
                           ((source (Icon_name list-add-symbolic))
                            (pixel_size 24))))
                         (attrs ()) (children No_children))
                        ((kind
                          (Picture ((source Empty) (alternative_text (nothing)))))
                         (attrs ()) (children No_children))
                        ((kind (Separator ((orientation Horizontal)))) (attrs ())
                         (children No_children))))))
                    ((kind (Box ((orientation Vertical) (spacing 8))))
                     (key containers) (attrs ((Page_title Containers)))
                     (children
                      (List
                       (((kind
                          (Scrolled_window
                           ((hpolicy Never) (min_content_height 120))))
                         (attrs ())
                         (children
                          (Single
                           (((kind (Label ((text scrolled)))) (attrs ())
                             (children No_children))))))
                        ((kind (Frame ((label (frame))))) (attrs ())
                         (children
                          (Single
                           (((kind (Label ((text framed)))) (attrs ())
                             (children No_children))))))
                        ((kind (Expander ((label (expander)) (expanded false))))
                         (attrs ((On_expanded_changed <handler>)))
                         (children
                          (Single
                           (((kind (Label ((text detail)))) (attrs ())
                             (children No_children))))))
                        ((kind
                          (Revealer ((reveal true) (transition Slide_down))))
                         (attrs ((On_revealed <handler>)))
                         (children
                          (Single
                           (((kind (Label ((text revealed)))) (attrs ())
                             (children No_children))))))
                        ((kind (Grid ((row_spacing 8) (column_spacing 12))))
                         (attrs ())
                         (children
                          (List
                           (((kind (Label ((text cell)))) (key cell)
                             (attrs
                              ((Grid_cell
                                ((column 0) (row 0) (width 1) (height 1)))))
                             (children No_children))))))
                        ((kind
                          (List_box
                           ((selection_mode Multiple)
                            (activate_on_single_click false)
                            (show_separators true) (selected (row)))))
                         (attrs
                          ((On_row_activated <handler>)
                           (On_selected_rows_changed <handler>)))
                         (children
                          (Slots
                           ((placeholder
                             (Single
                              (((kind (Label ((text empty)))) (attrs ())
                                (children No_children)))))
                            (rows
                             (List
                              (((kind (Label ((text header)))) (key hdr)
                                (attrs
                                 ((Row_selectable false) (Row_activatable false)))
                                (children No_children))
                               ((kind (Label ((text row)))) (key row) (attrs ())
                                (children No_children)))))))))
                        ((kind
                          (Flow_box
                           ((activate_on_single_click false)
                            (min_children_per_line 1) (max_children_per_line 4)
                            (row_spacing 12) (column_spacing 12)
                            (homogeneous true) (selected (card)))))
                         (attrs
                          ((On_child_activated <handler>)
                           (On_selected_children_changed <handler>)))
                         (children
                          (List
                           (((kind (Label ((text card)))) (key card) (attrs ())
                             (children No_children))))))
                        ((kind
                          (Notebook
                           ((current_page page) (scrollable true)
                            (show_border false) (tab_pos Bottom))))
                         (attrs ((On_page_changed <handler>)))
                         (children
                          (List
                           (((kind (Label ((text page)))) (key page)
                             (attrs ((Tab_label Page))) (children No_children))))))))))
                    ((kind (Box ((orientation Vertical) (spacing 8))))
                     (key slots) (attrs ((Page_title Slots)))
                     (children
                      (List
                       (((kind (Center_box ())) (attrs ())
                         (children
                          (Slots
                           ((start
                             (Single
                              (((kind (Label ((text start)))) (attrs ())
                                (children No_children)))))
                            (center
                             (Single
                              (((kind (Label ((text center)))) (attrs ())
                                (children No_children)))))
                            (end
                             (Single
                              (((kind (Label ((text end)))) (attrs ())
                                (children No_children)))))))))
                        ((kind (Paned ((orientation Vertical) (position (120)))))
                         (attrs ((On_position_changed <handler>)))
                         (children
                          (Slots
                           ((start
                             (Single
                              (((kind (Label ((text top)))) (attrs ())
                                (children No_children)))))
                            (end
                             (Single
                              (((kind (Label ((text bottom)))) (attrs ())
                                (children No_children)))))))))
                        ((kind (Overlay ())) (attrs ())
                         (children
                          (Slots
                           ((child
                             (Single
                              (((kind (Box ((orientation Vertical))))
                                (attrs ((Width_request 150) (Height_request 60)))
                                (children (List ()))))))
                            (overlays
                             (List
                              (((kind (Label ((text over)))) (key badge)
                                (attrs ((Measure_overlay false)))
                                (children No_children)))))))))
                        ((kind (Native (native Placeholder))) (attrs ())
                         (children No_children))))))))))))))))))))))
    |}]
;;
