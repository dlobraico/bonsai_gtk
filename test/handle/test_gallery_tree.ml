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
   asserted: the sweeps in [test_gallery_sweeps.ml] derive what they expect from
   [Kind.Variants.descriptions] and [Attr.Name.all], so the header cannot drift away from
   the tree again without a test going red. The golden that pins the tree's sexp is
   [test_gallery.ml]. *)
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
                         [ Attr.autofocus true
                         ; Attr.on_changed (fun _ -> Ui_effect.Ignore)
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
                         ; Attr.on_click ~button:1 (fun _ -> Click_response.Continue)
                         ]
                       (Node.label "click me")
                   ; Node.label
                       ~attrs:
                         [ Attr.test_id "focus"
                         ; Attr.focusable true
                         ; Attr.on_focus_enter (fun () -> Ui_effect.Ignore)
                         ; Attr.on_focus_leave (fun () -> Ui_effect.Ignore)
                         ; Attr.on_contains_focus_changed (fun _ -> Ui_effect.Ignore)
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
