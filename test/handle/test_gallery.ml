open! Core

(* The one golden over [Test_gallery_tree.gallery_tree]: the whole M1+M2 catalogue, sexped
   once. The sweeps that keep the tree honest -- that it still names every constructor and
   every attr -- live in [test_gallery_sweeps.ml]. *)
let%expect_test "every M1 and M2 widget builds a legal node" =
  let handle = Bonsai_gtk_test.create Test_gallery_tree.every_widget in
  Bonsai_gtk_test.Handle.show handle;
  [%expect
    {|
    ((kind (Window ((title ("every widget")) (default_size ((900 560))))))
     (attrs ((Widget_name every-widget-root)))
     (children
      (Single
       (((kind (Box ((orientation Horizontal))))
         (attrs
          ((Margin_start 4) (Margin_end 4) (Margin_top 4) (Margin_bottom 4)))
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
                 (attrs ((Vexpand true) (On_visible_child_changed <handler>)))
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
                        ((kind (Button ()))
                         (attrs ((Sensitive false) (Opacity 0.6)))
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
                         (attrs
                          ((Autofocus true) (On_changed <handler>)
                           (On_activate <handler>)))
                         (children No_children))
                        ((kind
                          (Password_entry ((text "") (show_peek_icon false))))
                         (attrs ()) (children No_children))
                        ((kind (Search_entry ((text "") (search_delay (200)))))
                         (attrs ((On_search_changed <handler>)))
                         (children No_children))
                        ((kind
                          (Text_view
                           ((text note) (wrap Word_char) (monospace true)
                            (accepts_tab false) (left_margin 6))))
                         (attrs
                          ((On_changed <handler>) (On_cursor_moved <handler>)))
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
                        ((kind
                          (Drop_down
                           ((items (one two)) (selected 1) (enable_search true))))
                         (attrs ((On_selected_changed <handler>)))
                         (children No_children))
                        ((kind (Level_bar ((value 3) (max 5) (mode Discrete))))
                         (attrs ()) (children No_children))
                        ((kind
                          (Calendar
                           ((date 2026-12-31) (show_week_numbers true)
                            (marked_days (1 15)))))
                         (attrs ((On_day_selected <handler>)))
                         (children No_children))
                        ((kind
                          (Editable_label ((text editable) (editing false))))
                         (attrs
                          ((On_changed <handler>) (On_editing_changed <handler>)))
                         (children No_children))
                        ((kind (Spinner ((spinning true))))
                         (attrs ((Valign Center) (Tooltip working)))
                         (children No_children))
                        ((kind
                          (Image
                           ((source (Icon_name list-add-symbolic))
                            (pixel_size 24))))
                         (attrs ()) (children No_children))
                        ((kind
                          (Picture ((source Empty) (alternative_text (nothing)))))
                         (attrs ()) (children No_children))
                        ((kind (Separator ((orientation Horizontal))))
                         (attrs ((Visible false))) (children No_children))))))
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
                            (show_tabs false) (show_border false)
                            (tab_pos Bottom))))
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
                        ((kind
                          (Header_bar
                           ((show_title_buttons false)
                            (decoration_layout (:close)))))
                         (attrs ())
                         (children
                          (Slots
                           ((title
                             (Single
                              (((kind (Label ((text "title widget")))) (attrs ())
                                (children No_children)))))
                            (start
                             (List
                              (((kind (Button ((label (Back))))) (key back)
                                (attrs ()) (children (Single ()))))))
                            (end
                             (List
                              (((kind (Button ((label (Menu))))) (key menu)
                                (attrs ()) (children (Single ()))))))))))
                        ((kind (Action_bar ())) (attrs ())
                         (children
                          (Slots
                           ((center
                             (Single
                              (((kind (Label ((text status)))) (attrs ())
                                (children No_children)))))
                            (start
                             (List
                              (((kind (Button ((label (Add))))) (key add)
                                (attrs ()) (children (Single ()))))))
                            (end
                             (List
                              (((kind (Button ((label (Delete))))) (key del)
                                (attrs ()) (children (Single ()))))))))))
                        ((kind
                          (Menu_button
                           ((icon_name (open-menu-symbolic)) (primary true))))
                         (attrs
                          ((Actions (scope gallery)
                            (specs (((name noop) (Simple <effect>)))))))
                         (children
                          (Slots
                           ((popover
                             (Single
                              (((kind (Popover ((open_ false) (position Top))))
                                (attrs ((On_closed <handler>)))
                                (children
                                 (Single
                                  (((kind (Label ((text "menu body"))))
                                    (attrs ()) (children No_children)))))))))))))
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
                         (children No_children))))))
                    ((kind (Box ((orientation Vertical) (spacing 8))))
                     (key input) (attrs ((Page_title Input)))
                     (children
                      (List
                       (((kind (Box ((orientation Vertical))))
                         (attrs
                          ((Focusable true) (Can_focus true) (Test_id keys)
                           (On_key_pressed (phase Bubble) (handler <handler>))
                           (On_key_released (phase Bubble) (handler <handler>))))
                         (children
                          (List
                           (((kind (Label ((text keys))))
                             (attrs ((css_classes (dim-label))))
                             (children No_children))))))
                        ((kind (Frame ()))
                         (attrs
                          ((Cursor_name pointer) (Test_id card)
                           (On_click (button 1) (phase Bubble)
                            (handler <handler>))))
                         (children
                          (Single
                           (((kind (Label ((text "click me")))) (attrs ())
                             (children No_children))))))
                        ((kind (Label ((text focus))))
                         (attrs
                          ((Focusable true) (Test_id focus)
                           (On_focus_enter (phase Bubble) (handler <handler>))
                           (On_focus_leave (phase Bubble) (handler <handler>))
                           (On_contains_focus_changed <handler>)))
                         (children No_children))))))))))))))))))))))
    |}]
;;
