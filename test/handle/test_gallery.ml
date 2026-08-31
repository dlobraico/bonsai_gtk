open! Core
open Bonsai_gtk_vtree
open Bonsai.Let_syntax

(* The view half of [examples/gallery.ml], reproduced as a component that mentions no
   ocgtk type -- which is the rule the README states about keeping view functions in a
   vtree-only library, worked through on the largest tree this repository has.

   Every M1 and M2 [Node] constructor appears here {i at least} once -- [Node.button] and
   [Node.label] appear many times, because the containers need children -- and every
   [Attr] constructor does too. That is the coverage: a constructor whose defaults change,
   or a children shape that stops being legal, shows up as a diff in this one snapshot
   rather than as a runtime failure in somebody's app.

   "At least once" and not "exactly once", which is what this comment used to claim and
   what [docs/m2-backlog.md] recorded as inaccurate. The claim is now checked rather than
   asserted: the three sweeps at the bottom of this file derive what they expect from
   [Kind.Variants.descriptions] and [Attr.Name.all], so the header cannot drift away from
   the tree again without a test going red. *)
let gallery_tree ~n ~set_n =
  Node.window
    ~attrs:[ Attr.widget_name "every-widget-root" ]
    ~title:"every widget"
    ~default_size:(900, 560)
    (Node.box
       ~orientation:Horizontal
       ~attrs:[ Attr.margin 4 ]
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
               ~attrs:
                 [ Attr.vexpand true
                 ; Attr.on_visible_child_changed (fun _ -> Ui_effect.Ignore)
                 ]
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
                   ; Node.button
                       ~attrs:[ Attr.sensitive false; Attr.opacity 0.6 ]
                       ~child:(Node.label "child")
                       ()
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
                   ; Node.text_view
                       ~attrs:[ Attr.on_changed (fun _ -> Ui_effect.Ignore) ]
                       ~wrap:Word_char
                       ~monospace:true
                       ~accepts_tab:false
                       ~left_margin:6
                       ~text:"note"
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
                     (* Task 10's two, which its own task did not add here although this
                        file claims every constructor: without them a change to
                        [Node.drop_down]'s or [Node.level_bar]'s defaults showed up in no
                        snapshot at all. *)
                   ; Node.drop_down
                       ~attrs:[ Attr.on_selected_changed (fun _ -> Ui_effect.Ignore) ]
                       ~enable_search:true
                       ~items:[ "one"; "two" ]
                       ~selected:1
                       ()
                   ; Node.level_bar ~min:0. ~max:5. ~mode:Discrete ~value:3. ()
                     (* The date is a literal rather than [Date.today], which would make
                        this snapshot change once a day. *)
                   ; Node.calendar
                       ~attrs:[ Attr.on_day_selected (fun _ -> Ui_effect.Ignore) ]
                       ~show_week_numbers:true
                       ~marked_days:[ 1; 15 ]
                       ~date:(Date.of_string "2026-12-31")
                       ()
                   ; Node.editable_label
                       ~attrs:
                         [ Attr.on_changed (fun _ -> Ui_effect.Ignore)
                         ; Attr.on_editing_changed (fun _ -> Ui_effect.Ignore)
                         ]
                       ~text:"editable"
                       ()
                   ; Node.spinner
                       ~attrs:[ Attr.valign Center; Attr.tooltip "working" ]
                       ~spinning:true
                       ()
                   ; Node.image ~pixel_size:24 (Icon_name "list-add-symbolic")
                   ; Node.picture ~alternative_text:"nothing" Empty
                     (* [false], not [true]: [true] is GTK's own default, so the write
                        would be a no-op and no wrong value of this attr could change the
                        golden -- name coverage that pins nothing, which is the shape of
                        the M1 backlog's "three expect tests pass props the sexp then
                        drops". This tree is never displayed, so hiding a separator in it
                        costs nothing. *)
                   ; Node.separator
                       ~attrs:[ Attr.visible false ]
                       ~orientation:Horizontal
                       ()
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
                     (* Every prop, each set {i away} from GTK's default so that the sexp
                        pins it rather than dropping it, and the one per-page attr. The
                        notebook is the only container here whose children are reconciled
                        with real [Move] ops, so its page list is also the coverage for
                        [Widget_impl.list_ops.move] being [Some]. *)
                   ; Node.notebook
                       ~attrs:[ Attr.on_page_changed (fun _ -> Ui_effect.Ignore) ]
                       ~scrollable:true
                       ~show_tabs:false
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
                 (* The five controller attrs, which no other page here carries.

                    They are legal on every kind ([Events.is_controller_attr]), so this
                    page puts them on the plainest nodes there are rather than on a widget
                    that might be read as owning them -- a box, a frame and a label. The
                    two key attrs share one [GtkEventControllerKey] and therefore one
                    phase, so they are both left at the default [Bubble]; asking for two
                    phases on one node is what [Events.key_phase_rejection] refuses, and
                    [test/handle/test_handle.ml] is where that is pinned.

                    What this page is coverage {i for} is narrow and worth saying: that
                    the attrs exist, are accepted on these kinds, and survive into the
                    sexp. That a real click or a real keystroke reaches the handler is
                    demonstrated nowhere in any test suite -- the pinned binding can
                    synthesise neither -- and the compensating control is the Input page
                    of [examples/gallery.ml], clicked through by hand on a real display. *)
               ; Node.box
                   ~key:"input"
                   ~attrs:[ Attr.page_title "Input" ]
                   ~orientation:Vertical
                   ~spacing:8
                   [ Node.box
                       ~orientation:Vertical
                       ~attrs:
                         [ Attr.test_id "keys"
                         ; Attr.focusable true
                         ; Attr.can_focus true
                         ; Attr.on_key_pressed (fun _ -> Key_response.Propagate)
                         ; Attr.on_key_released (fun _ -> Ui_effect.Ignore)
                         ]
                       [ Node.label ~attrs:[ Attr.css_class "dim-label" ] "keys" ]
                   ; Node.frame
                       ~attrs:
                         [ Attr.test_id "card"
                         ; Attr.cursor_name "pointer"
                         ; Attr.on_click ~button:1 (fun _ -> Ui_effect.Ignore)
                         ]
                       (Node.label "click me")
                   ; Node.label
                       ~attrs:
                         [ Attr.test_id "focus"
                         ; Attr.focusable true
                         ; Attr.on_focus_enter (fun () -> Ui_effect.Ignore)
                         ; Attr.on_focus_leave (fun () -> Ui_effect.Ignore)
                         ]
                       "focus"
                   ]
               ]
           ]
       ])
;;

let every_widget (graph @ local) =
  let n, set_n = Bonsai.state 0 graph in
  let%arr n and set_n in
  gallery_tree ~n ~set_n
;;

let%expect_test "every M1 and M2 widget builds a legal node" =
  let handle = Bonsai_gtk_test.create every_widget in
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
                         (attrs ((On_changed <handler>) (On_activate <handler>)))
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
                         (attrs ((On_changed <handler>))) (children No_children))
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
                           (On_focus_enter <handler>) (On_focus_leave <handler>)))
                         (children No_children))))))))))))))))))))))
    |}]
;;

(* ------------------------------------------------------------------------------ *)
(* The nets under the golden above.

   The golden says "this exact tree still sexps this way". What it cannot say is "this
   tree is still {i everything}" -- a constructor or an attribute added in a later
   milestone and never put here would leave the golden green and the coverage claim in
   this file's header false. Task 11 found exactly that: Task 10 had added
   [Node.drop_down] and [Node.level_bar] and neither was in this file, so their defaults
   were pinned by no snapshot at all.

   So the three sweeps below derive their expectations from the compiler --
   [Kind.Variants.descriptions] and [Attr.Name.all] -- rather than from a list somebody
   has to remember to grow. *)

let rec fold_nodes (node : Node.t) ~init ~f =
  let acc = ref (f init node) in
  Children.iter node.children ~f:(fun child -> acc := fold_nodes child ~init:!acc ~f);
  !acc
;;

(* The tree as a value rather than through a handle: a sweep has to walk it, and
   [Handle.show] only prints it. [~n] is the one piece of state it reads. *)
let sweep_tree = gallery_tree ~n:0 ~set_n:(fun _ -> Ui_effect.Ignore)

let kinds_in_tree tree =
  fold_nodes tree ~init:[] ~f:(fun acc (node : Node.t) ->
    Kind.Variants.to_name node.kind :: acc)
;;

let names_in_tree tree =
  fold_nodes tree ~init:[] ~f:(fun acc (node : Node.t) ->
    List.filter_map (Attrs.to_list node.attrs) ~f:Attr.name @ acc)
;;

(* Every [Node.t] constructor appears somewhere in this tree.

   Counted against [Kind.Variants.descriptions], which the compiler writes, so a kind
   added to [Kind.t] fails here until someone puts a node of it in the tree above -- which
   is the check this file claimed to be and was not. The names are
   [Kind.Variants.to_name]'s (the OCaml constructor) rather than [Kind.name]'s (the GTK
   class), because only the former is derived from the type. *)
let%expect_test "the gallery names every Node constructor" =
  let used = kinds_in_tree sweep_tree in
  let missing =
    List.filter_map Kind.Variants.descriptions ~f:(fun (name, _) ->
      if List.mem used name ~equal:String.equal then None else Some name)
  in
  print_s [%sexp (missing : string list)];
  [%expect {| () |}]
;;

(* Every attr constructor appears somewhere in this tree. Not "every attr is exercised" --
   the sexp cannot say that -- but "no attr was added and then forgotten", which is the
   failure this file is a net under. The list is derived from [Attr.Name.all], so a new
   name fails here until someone puts it in the gallery.

   No name is exempt. Two of them are only legal in one place -- [Grid_cell] on a grid
   child, [Row_selectable] and [Row_activatable] on a list-box row, [Tab_label] on a
   notebook page, [Page_title] on a stack page, [Measure_overlay] on an overlay child --
   and the tree has one of each container for exactly that reason. If a future name
   genuinely cannot be placed, exempt it here by name with the reason rather than
   weakening the check. *)
let%expect_test "the gallery names every attr" =
  let used = names_in_tree sweep_tree in
  let missing =
    List.filter Attr.Name.all ~f:(fun n -> not (List.mem used n ~equal:Attr.Name.equal))
  in
  print_s [%sexp (missing : Attr.Name.t list)];
  [%expect {| () |}]
;;

(* Every event attr can be fired by some [Action].

   The gap this closes is the one none of the other three sweeps can see. The attrs sweep
   above is satisfied by an attr {i appearing} in the tree, and every handler sexps as
   [<handler>], so for an attr with no action there is no headless evidence of any kind
   that the right closure is behind the right name -- not the sweeps, not the goldens, not
   the actions. Three attrs were in exactly that state for the whole of M2 ([On_revealed],
   [On_position_changed], [On_visible_child_changed]) and nothing noticed.

   The mapping below is hand-maintained, and that is the point: the
   {i list of event names} is [Attr.Name.all] filtered by [Attr.Name.is_event], which the
   compiler writes, so a new event attr fails here until someone either gives it an action
   or exempts it with a reason. Naming the action per attr rather than counting them also
   documents which action fires what, which the [Action.t] doc gives from the other side.

   [Action.t] itself is not walked -- it has no [enumerate], and an action carries
   arguments -- so this is a check on the attrs, not on the actions: an [Action] with no
   attr would be a constructor nobody can dispatch, which the compiler catches at its own
   [match]. *)
let%expect_test "every event attr has an action that fires it" =
  let action_for : Attr.Name.t -> string option = function
    | On_clicked -> Some "Click"
    | On_toggled -> Some "Toggle"
    | On_changed -> Some "Set_text"
    | On_activate -> Some "Activate"
    | On_search_changed -> Some "Search_changed"
    | On_value_changed -> Some "Set_value"
    | On_expanded_changed -> Some "Set_expanded"
    | On_revealed -> Some "Set_revealed"
    | On_position_changed -> Some "Set_position"
    | On_visible_child_changed -> Some "Set_visible_child"
    | On_row_activated -> Some "Activate_row"
    | On_selected_rows_changed -> Some "Set_selection"
    | On_child_activated -> Some "Activate_child"
    | On_selected_children_changed -> Some "Set_selection"
    | On_page_changed -> Some "Set_page"
    | On_selected_changed -> Some "Set_selected"
    | On_day_selected -> Some "Select_day"
    | On_editing_changed -> Some "Set_editing"
    | On_click -> Some "Click_at"
    | On_focus_enter -> Some "Focus_enter"
    | On_focus_leave -> Some "Focus_leave"
    | On_key_pressed -> Some "Key_press"
    | On_key_released -> Some "Key_release"
    (* Not event attrs; [is_event] filters them out before this is reached, and they are
       spelled out rather than wildcarded so that a name added to [Attr.Name.t] is a
       compile error here and its author has to say which half it is in. *)
    | Margin_start
    | Margin_end
    | Margin_top
    | Margin_bottom
    | Halign
    | Valign
    | Hexpand
    | Vexpand
    | Sensitive
    | Visible
    | Tooltip
    | Width_request
    | Height_request
    | Opacity
    | Focusable
    | Can_focus
    | Widget_name
    | Cursor_name
    | Test_id
    | Measure_overlay
    | Grid_cell
    | Page_title
    | Row_selectable
    | Row_activatable
    | Tab_label -> None
  in
  let unfireable =
    List.filter Attr.Name.all ~f:(fun name ->
      Attr.Name.is_event name && Option.is_none (action_for name))
  in
  print_s [%sexp (unfireable : Attr.Name.t list)];
  [%expect {| () |}]
;;

(* The half of the attr surface [Attr.Name.all] cannot reach.

   [Attr.name] answers [None] for two constructors, [Css_class] and [Many] -- but [Many]
   never reaches [Attrs.to_list], because [Attr.flatten] walks it away first. So
   [Attr.css_class] is the only nameless attr this sweep can {i encounter}, which is not
   the same claim as "the only nameless attr" and matters to whoever adds a second
   combinator.

   It has no [Name.t] because a css class is a member of a set the patcher adds to and
   removes from ([Attrs.diff]'s [Add_css_class]/[Remove_css_class]) rather than a keyed
   property it sets and unsets -- so the test above would pass with no css class anywhere
   in the tree. This is that missing half, spelled out rather than left to a reader to
   notice. *)
let%expect_test "the gallery uses the one attr with no name" =
  let classes =
    fold_nodes sweep_tree ~init:[] ~f:(fun acc (node : Node.t) ->
      Attrs.css_classes node.attrs @ acc)
  in
  print_s [%sexp (classes : string list)];
  [%expect {| (dim-label) |}]
;;

(* ------------------------------------------------------------------------------ *)
(* Mount, patch, unmount -- once per kind, headless.

   The golden above is one tree, shown once. This is the other axis: every kind put
   through the three things that happen to a node in its life, with the row list counted
   against [Kind.Variants.descriptions] so a new kind has no row until someone writes one.

   What it proves, and the list is short and worth being exact about:

   - Each phase's tree is one [Bonsai_gtk_test] accepts -- the [Placement], [Events] and
     key-phase checks the runtime also makes, from the same two tables. A kind whose node
     is legal to build and illegal to mount fails here.
   - A prop change is not [Kind.equal_props], so the patcher does not skip the update. A
     kind [equal_props] answers [true] for never updates at all, and no per-widget test
     asks this of every kind at once. This is the column that can fail, and it is
     mutation-verified: forcing [Kind.equal_props]'s [Text_view] arm to [true] moves
     [Text_view] into the [skipped] list below.
   - A container's children really diff: the op counts come from [Reconcile.diff] over the
     subject's own child lists. No row {i reorders} its children, so no [Move] is produced
     and [?ordered] never arises -- which container drops a [Move] is
     [test/test_reconcile.ml]'s and [test/live/live_containers.ml]'s question.

   {b Two of the printed columns cannot fail, and are the record of an invariant rather
     than a test of it.}
   Saying so is cheaper than leaving a reader to work out how much the other three are
   worth:

   - [same_kind] is a {i tautology} given [Kind.name]. [Kind.same_kind] is
     [String.equal (name a) (name b)] and [name] is a total function of the constructor,
     so two nodes built from one constructor always agree, and no single wrong arm can
     make a kind differ from itself. It meant something against the 32-arm matrix with the
     [_ -> false] wildcard that [vtree/kind.ml] describes as removed, and it would mean
     something again if [same_kind] ever stopped being a [name] comparison -- which is why
     the column stays.
   - [unmount] checks this file's own scaffold: [STILL THERE] can print only if
     [subject_of] disagrees with [lifecycle_app]'s [step] arithmetic. What is not vacuous
     about the phase is the third [show_into_string], which re-validates the tree the
     subject was removed from.

   What it does not prove: anything GTK's. There is no widget here, so "unmount" is the
   node leaving the tree and nothing more -- no [destroy], no disconnected signal, no
   removed controller. The real create/update/destroy sweep is [test/live/live_patcher.ml]
   and the per-widget files beside it. *)

(* A window is legal only at the root ([Patcher] raises for one anywhere else, and this
   handle is documented not to check that), so the window row puts its subject {i at} the
   root and has no unmount phase -- a tree with no root is not a tree. Named here rather
   than quietly skipped, on the rule the attr sweep above follows. *)
type placement =
  | Child
  | Root

let lifecycle_app ~placement ~before ~after (graph @ local) =
  let step, set_step = Bonsai.state 0 graph in
  let%arr step and set_step in
  let scaffold subject =
    Node.box
      ~orientation:Vertical
      ([ Node.button
           ~attrs:[ Attr.test_id "step"; Attr.on_clicked (set_step (step + 1)) ]
           ~label:"step"
           ()
         (* Two real stacks, so that the [Stack_switcher] and [Stack_sidebar] rows can
            name one that exists and then name the other: [~stack] naming no stack is
            refused at mount and not here, and a sweep that certified a tree the runtime
            refuses would be worse than no sweep at all. *)
       ; Node.stack
           ~name:"sweep-1"
           ~visible_child:"p"
           [ Node.label ~key:"p" ~attrs:[ Attr.page_title "P" ] "p" ]
       ; Node.stack
           ~name:"sweep-2"
           ~visible_child:"p"
           [ Node.label ~key:"p" ~attrs:[ Attr.page_title "P" ] "p" ]
       ]
       @ Option.to_list subject)
  in
  let subject = if step = 0 then Some before else if step = 1 then Some after else None in
  match placement with
  | Child -> Node.window (scaffold subject)
  | Root ->
    (* Record update rather than [Node.window]: the subject's own props are what this row
       is about, so the node the row built is the node that is shown, with the scaffold
       put underneath it. *)
    let window = Option.value subject ~default:before in
    { window with children = Single (Some (scaffold None)) }
;;

let subject_of ~placement (tree : Node.t) =
  match placement with
  | Root -> Some tree
  | Child ->
    (match tree.children with
     | Single (Some box) ->
       (match box.children with
        | List [ _step; _stack; _stack2 ] -> None
        | List [ _step; _stack; _stack2; subject ] -> Some subject
        | _ -> failwith "lifecycle sweep: unexpected scaffold")
     | _ -> failwith "lifecycle sweep: unexpected scaffold")
;;

let child_ops (before : Node.t) (after : Node.t) =
  let summary old new_ =
    let ops =
      Reconcile.diff
        ~key:(fun (n : Node.t) -> n.key)
        ~same_kind:(fun (a : Node.t) (b : Node.t) -> Kind.same_kind a.kind b.kind)
        ~old
        ~new_
        ()
    in
    let count f = List.count ops ~f in
    sprintf
      "%dI/%dM/%dR/%dU"
      (count (function
        | Reconcile.Insert _ -> true
        | _ -> false))
      (count (function
        | Reconcile.Move _ -> true
        | _ -> false))
      (count (function
        | Reconcile.Remove _ -> true
        | _ -> false))
      (count (function
        | Reconcile.Update _ -> true
        | _ -> false))
  in
  (* Descends through [Slots], because the three containers whose child list is the
     interesting one -- a list box's rows, a flow box's children, an overlay's layers --
     reach it under a slot name rather than at the top. A first cut of this stopped at
     [List] and reported "-" for all three, which is a sweep that says nothing about
     exactly the containers M2 added. *)
  let rec go label (old : Node.t Children.t) (new_ : Node.t Children.t) =
    match old, new_ with
    | List old, List new_ -> [ label ^ summary old new_ ]
    | Slots old, Slots new_ ->
      List.concat_map old ~f:(fun (name, old_slot) ->
        match List.Assoc.find new_ name ~equal:String.equal with
        | None -> []
        | Some new_slot -> go (name ^ "=") old_slot new_slot)
    | _ -> []
  in
  match go "" before.children after.children with
  | [] -> "-"
  | summaries -> String.concat ~sep:" " summaries
;;

type outcome =
  { name : string
  ; same_kind : bool
  ; props_changed : bool
  }

let run_row (placement, before, after) =
  let handle = Bonsai_gtk_test.create (lifecycle_app ~placement ~before ~after) in
  (* [show_into_string] and not [recompute_view]: the checks live in the [Result_spec]'s
     [view], which only the printing entry points call -- see the test below, which pins
     that. Discarding the string is the point; the tree it prints is the scaffold's, and
     what is wanted is the exception it would have raised. *)
  let phase () =
    ignore (Bonsai_gtk_test.Handle.show_into_string handle : string);
    subject_of ~placement (Bonsai_gtk_test.Handle.last_result handle)
  in
  let mounted = phase () in
  Bonsai_gtk_test.Handle.do_actions handle [ Click "step" ];
  let patched = phase () in
  let unmounted =
    match placement with
    | Root -> None
    | Child ->
      Bonsai_gtk_test.Handle.do_actions handle [ Click "step" ];
      phase ()
  in
  match mounted, patched with
  | Some mounted, Some patched ->
    let name = Kind.Variants.to_name mounted.kind in
    let same_kind = Kind.same_kind mounted.kind patched.kind in
    let props_changed = not (Kind.equal_props mounted.kind patched.kind) in
    printf
      "%-15s mount=ok patch=ok unmount=%-9s same_kind=%-5b props_changed=%-5b child_ops=%s\n"
      name
      (match placement, unmounted with
       | Root, _ -> "n/a(root)"
       | Child, None -> "ok"
       | Child, Some _ -> "STILL THERE")
      same_kind
      props_changed
      (child_ops mounted patched);
    { name; same_kind; props_changed }
  | _ -> failwith "lifecycle sweep: the subject did not survive its own mount"
;;

(* One row per [Kind.t] constructor, in [Kind.t]'s own order. Each [after] differs from
   its [before] in a property the kind really has -- which is the whole point, so the two
   exceptions are named:

   - [Overlay]'s props are [unit] ("a [GtkOverlay] has no properties of its own: it is
     entirely its children"), so its row can only change children and reports
     [props_changed=false]. That is the correct answer, and the summary test below is what
     stops a second kind joining it silently.
   - [Stack_switcher] and [Stack_sidebar] hold only the {i name} of the stack they drive,
     so their rows move between the scaffold's two stacks. *)
(* [Kind.equal_props]'s [Native] arm compares payloads with [phys_equal], and
   [Native.Unit] is a constant constructor -- one shared value -- so two nodes carrying it
   are equal and the row would have changed no prop at all. A payload of this test's own,
   carrying a string, is what makes the native row say something. *)
type Native.payload += Payload of string

let sweep_rows : (placement * Node.t * Node.t) list =
  let child () = Node.label "x" in
  let keyed k = Node.label ~key:k k in
  let cell k row = Node.label ~key:k ~attrs:[ Attr.grid_cell ~column:0 ~row () ] k in
  let page k = Node.label ~key:k ~attrs:[ Attr.page_title k ] k in
  let tab k = Node.label ~key:k ~attrs:[ Attr.tab_label k ] k in
  [ Child, Node.label "a", Node.label "b"
  ; Child, Node.button ~label:"a" (), Node.button ~label:"b" ()
  ; Child, Node.toggle_button ~active:false (), Node.toggle_button ~active:true ()
  ; Child, Node.check_button ~active:false (), Node.check_button ~active:true ()
  ; Child, Node.switch ~active:false (), Node.switch ~active:true ()
  ; Child, Node.entry ~text:"a" (), Node.entry ~text:"b" ()
  ; Child, Node.password_entry ~text:"a" (), Node.password_entry ~text:"b" ()
  ; Child, Node.search_entry ~text:"a" (), Node.search_entry ~text:"b" ()
  ; Child, Node.text_view ~text:"a" (), Node.text_view ~text:"b" ()
  ; ( Child
    , Node.spin_button ~min:0. ~max:10. ~value:1. ()
    , Node.spin_button ~min:0. ~max:10. ~value:2. () )
  ; ( Child
    , Node.scale ~orientation:Horizontal ~min:0. ~max:10. ~value:1. ()
    , Node.scale ~orientation:Horizontal ~min:0. ~max:10. ~value:2. () )
  ; Child, Node.progress_bar ~fraction:0.1 (), Node.progress_bar ~fraction:0.9 ()
  ; Child, Node.spinner ~spinning:false (), Node.spinner ~spinning:true ()
  ; Child, Node.level_bar ~value:1. (), Node.level_bar ~value:2. ()
  ; Child, Node.image (Icon_name "a"), Node.image (Icon_name "b")
  ; Child, Node.picture (Filename "a"), Node.picture (Filename "b")
  ; ( Child
    , Node.separator ~orientation:Horizontal ()
    , Node.separator ~orientation:Vertical () )
  ; ( Child
    , Node.scrolled_window ~hpolicy:Never (child ())
    , Node.scrolled_window ~hpolicy:Always (child ()) )
  ; Child, Node.frame ~label:"a" (child ()), Node.frame ~label:"b" (child ())
  ; ( Child
    , Node.expander ~label:"e" ~expanded:false (child ())
    , Node.expander ~label:"e" ~expanded:true (child ()) )
  ; Child, Node.revealer ~reveal:false (child ()), Node.revealer ~reveal:true (child ())
  ; ( Child
    , Node.box ~orientation:Vertical ~spacing:0 [ keyed "a" ]
    , Node.box ~orientation:Vertical ~spacing:4 [ keyed "a"; keyed "b" ] )
  ; ( Child
    , Node.grid ~row_spacing:0 [ cell "a" 0 ]
    , Node.grid ~row_spacing:4 [ cell "a" 0; cell "b" 1 ] )
  ; ( Child
    , Node.stack ~name:"s" ~visible_child:"a" [ page "a" ]
    , Node.stack ~name:"s" ~visible_child:"b" [ page "a"; page "b" ] )
  ; ( Child
    , Node.stack_switcher ~stack:"sweep-1" ()
    , Node.stack_switcher ~stack:"sweep-2" () )
  ; Child, Node.stack_sidebar ~stack:"sweep-1" (), Node.stack_sidebar ~stack:"sweep-2" ()
  ; ( Child
    , Node.list_box ~selected:[] [ keyed "a" ]
    , Node.list_box ~selected:[ "a" ] [ keyed "a"; keyed "b" ] )
  ; ( Child
    , Node.flow_box ~selected:[] [ keyed "a" ]
    , Node.flow_box ~selected:[ "a" ] [ keyed "a"; keyed "b" ] )
  ; ( Child
    , Node.notebook ~current_page:"a" [ tab "a" ]
    , Node.notebook ~current_page:"b" [ tab "a"; tab "b" ] )
  ; ( Child
    , Node.drop_down ~items:[ "a" ] ~selected:0 ()
    , Node.drop_down ~items:[ "a"; "b" ] ~selected:1 () )
  ; ( Child
    , Node.calendar ~date:(Date.of_string "2026-08-30") ()
    , Node.calendar ~date:(Date.of_string "2026-09-01") () )
  ; Child, Node.editable_label ~text:"a" (), Node.editable_label ~text:"b" ()
  ; ( Child
    , Node.center_box ~shrink_center_last:false ~center:(child ()) ()
    , Node.center_box ~shrink_center_last:true ~center:(child ()) () )
  ; ( Child
    , Node.paned
        ~orientation:Horizontal
        ~position:100
        ~start:(child ())
        ~end_:(child ())
        ()
    , Node.paned
        ~orientation:Horizontal
        ~position:200
        ~start:(child ())
        ~end_:(child ())
        () )
  ; ( Child
    , Node.overlay ~overlays:[ keyed "a" ] (child ())
    , Node.overlay ~overlays:[ keyed "a"; keyed "b" ] (child ()) )
  ; Root, Node.window ~title:"a" (child ()), Node.window ~title:"b" (child ())
  ; ( Child
    , Node.native { Native.name = "thing"; payload = Payload "a" }
    , Node.native { Native.name = "thing"; payload = Payload "b" } )
  ]
;;

(* Named for what it checks rather than for the three phases it runs: [test/handle/dune]
   links no ocgtk, so there is no widget and nothing here shows that an impl's [update]
   {i writes} anything. A per-kind live [Live_tree.dump] sweep is still the gap
   [docs/m2-backlog.md] records. *)
let%expect_test "every kind is diffed, and no kind is skipped" =
  let outcomes = List.map sweep_rows ~f:run_row in
  (* The row list is hand-maintained; [Kind.Variants.descriptions] is not. A kind added to
     [Kind.t] without a row here has no lifecycle coverage at all, and this is what says
     so -- the same idiom [test/test_events.ml] uses for its own list, and for the same
     reason. *)
  let covered = List.map outcomes ~f:(fun o -> o.name) in
  let missing =
    List.filter_map Kind.Variants.descriptions ~f:(fun (name, _) ->
      if List.mem covered name ~equal:String.equal then None else Some name)
  in
  print_s [%message "kinds with no row" (missing : string list)];
  (* A kind whose prop change is not [same_kind] is remounted on every frame that touches
     it; a kind whose prop change is [equal_props] never updates at all. [Overlay] is the
     one correct member of the second list -- its props are [unit] -- and its being named
     here is what stops a second kind joining it in silence. *)
  print_s
    [%message
      "a prop change is not an update"
        ~remounted:
          (List.filter_map outcomes ~f:(fun o ->
             if o.same_kind then None else Some o.name)
           : string list)
        ~skipped:
          (List.filter_map outcomes ~f:(fun o ->
             if o.props_changed then None else Some o.name)
           : string list)];
  [%expect
    {|
    Label           mount=ok patch=ok unmount=ok        same_kind=true  props_changed=true  child_ops=-
    Button          mount=ok patch=ok unmount=ok        same_kind=true  props_changed=true  child_ops=-
    Toggle_button   mount=ok patch=ok unmount=ok        same_kind=true  props_changed=true  child_ops=-
    Check_button    mount=ok patch=ok unmount=ok        same_kind=true  props_changed=true  child_ops=-
    Switch          mount=ok patch=ok unmount=ok        same_kind=true  props_changed=true  child_ops=-
    Entry           mount=ok patch=ok unmount=ok        same_kind=true  props_changed=true  child_ops=-
    Password_entry  mount=ok patch=ok unmount=ok        same_kind=true  props_changed=true  child_ops=-
    Search_entry    mount=ok patch=ok unmount=ok        same_kind=true  props_changed=true  child_ops=-
    Text_view       mount=ok patch=ok unmount=ok        same_kind=true  props_changed=true  child_ops=-
    Spin_button     mount=ok patch=ok unmount=ok        same_kind=true  props_changed=true  child_ops=-
    Scale           mount=ok patch=ok unmount=ok        same_kind=true  props_changed=true  child_ops=-
    Progress_bar    mount=ok patch=ok unmount=ok        same_kind=true  props_changed=true  child_ops=-
    Spinner         mount=ok patch=ok unmount=ok        same_kind=true  props_changed=true  child_ops=-
    Level_bar       mount=ok patch=ok unmount=ok        same_kind=true  props_changed=true  child_ops=-
    Image           mount=ok patch=ok unmount=ok        same_kind=true  props_changed=true  child_ops=-
    Picture         mount=ok patch=ok unmount=ok        same_kind=true  props_changed=true  child_ops=-
    Separator       mount=ok patch=ok unmount=ok        same_kind=true  props_changed=true  child_ops=-
    Scrolled_window mount=ok patch=ok unmount=ok        same_kind=true  props_changed=true  child_ops=-
    Frame           mount=ok patch=ok unmount=ok        same_kind=true  props_changed=true  child_ops=-
    Expander        mount=ok patch=ok unmount=ok        same_kind=true  props_changed=true  child_ops=-
    Revealer        mount=ok patch=ok unmount=ok        same_kind=true  props_changed=true  child_ops=-
    Box             mount=ok patch=ok unmount=ok        same_kind=true  props_changed=true  child_ops=1I/0M/0R/1U
    Grid            mount=ok patch=ok unmount=ok        same_kind=true  props_changed=true  child_ops=1I/0M/0R/1U
    Stack           mount=ok patch=ok unmount=ok        same_kind=true  props_changed=true  child_ops=1I/0M/0R/1U
    Stack_switcher  mount=ok patch=ok unmount=ok        same_kind=true  props_changed=true  child_ops=-
    Stack_sidebar   mount=ok patch=ok unmount=ok        same_kind=true  props_changed=true  child_ops=-
    List_box        mount=ok patch=ok unmount=ok        same_kind=true  props_changed=true  child_ops=rows=1I/0M/0R/1U
    Flow_box        mount=ok patch=ok unmount=ok        same_kind=true  props_changed=true  child_ops=1I/0M/0R/1U
    Notebook        mount=ok patch=ok unmount=ok        same_kind=true  props_changed=true  child_ops=1I/0M/0R/1U
    Drop_down       mount=ok patch=ok unmount=ok        same_kind=true  props_changed=true  child_ops=-
    Calendar        mount=ok patch=ok unmount=ok        same_kind=true  props_changed=true  child_ops=-
    Editable_label  mount=ok patch=ok unmount=ok        same_kind=true  props_changed=true  child_ops=-
    Center_box      mount=ok patch=ok unmount=ok        same_kind=true  props_changed=true  child_ops=-
    Paned           mount=ok patch=ok unmount=ok        same_kind=true  props_changed=true  child_ops=-
    Overlay         mount=ok patch=ok unmount=ok        same_kind=true  props_changed=false child_ops=overlays=1I/0M/0R/1U
    Window          mount=ok patch=ok unmount=n/a(root) same_kind=true  props_changed=true  child_ops=-
    Native          mount=ok patch=ok unmount=ok        same_kind=true  props_changed=true  child_ops=-
    ("kinds with no row" (missing ()))
    ("a prop change is not an update" (remounted ()) (skipped (Overlay)))
    |}]
;;

(* {b Every entry point that advances a handle checks the tree}, which is the guarantee
   [Bonsai_gtk_test]'s header rests on: "so that a headless suite cannot certify a tree
   the runtime refuses".

   It did not hold when this test was first written. The [Placement]/[Events]/key-phase
   checks live in the [Result_spec]'s [view], and only the entry points that {i build} the
   view call it -- so [Handle.recompute_view], which runs the computation and never builds
   one, waved an illegal tree straight through. That mattered because [recompute_view] is
   not an obscure corner: it is the idiom this library's own mli recommends for seeing one
   action's effect before dispatching the next, and [test/handle/] takes that advice
   twenty times. A guarantee that holds only if you avoid the documented idiom is not a
   guarantee, so [Bonsai_gtk_test.Handle] now shadows [recompute_view] and
   [recompute_view_until_stable] with checking versions (through [bonsai_test]'s own
   [?simulate_diff_patch] hook, which is handed the computed result).

   The first run of that shadow found one call site that had been certifying a tree the
   runtime refuses -- [test/handle/test_handle.ml]'s "Toggle needs a handler", whose
   second half asserted a weaker failure than the one its own comment claimed. It is fixed
   there.

   This test is the regression: if [Handle] ever goes back to being a plain alias for
   [Bonsai_test.Handle], the first line below reverts to [accepted] and this goes red. *)
let%expect_test "every entry point that advances a handle checks the tree" =
  let app (_graph @ local) =
    Bonsai.return
      (Node.window
         (Node.box
            ~orientation:Vertical
            [ Node.label ~attrs:[ Attr.on_toggled (fun _ -> Ui_effect.Ignore) ] "bad" ]))
  in
  let report name f =
    (* A fresh handle each time: the check raises out of the frame, and a handle that has
       raised is not one the next entry point should be asked about. *)
    let handle = Bonsai_gtk_test.create app in
    match f handle with
    | () -> printf "%s: accepted\n" name
    | exception e -> printf "%s: %s\n" name (Exn.to_string e)
  in
  report "recompute_view" Bonsai_gtk_test.Handle.recompute_view;
  report "recompute_view_until_stable" (fun handle ->
    Bonsai_gtk_test.Handle.recompute_view_until_stable handle);
  report "show_into_string" (fun handle ->
    ignore (Bonsai_gtk_test.Handle.show_into_string handle : string));
  report "show" Bonsai_gtk_test.Handle.show;
  report "show_diff" Bonsai_gtk_test.Handle.show_diff;
  report "store_view" Bonsai_gtk_test.Handle.store_view;
  [%expect
    {|
    recompute_view: (Invalid_argument "root/0/0: Label does not emit On_toggled")
    recompute_view_until_stable: (Invalid_argument "root/0/0: Label does not emit On_toggled")
    show_into_string: (Invalid_argument "root/0/0: Label does not emit On_toggled")
    show: (Invalid_argument "root/0/0: Label does not emit On_toggled")
    show_diff: (Invalid_argument "root/0/0: Label does not emit On_toggled")
    store_view: (Invalid_argument "root/0/0: Label does not emit On_toggled")
    |}]
;;
