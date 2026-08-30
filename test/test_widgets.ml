open! Core
open Bonsai_gtk_vtree

let%expect_test "label defaults match GTK's, and every text property reaches the kind" =
  print_s [%sexp (Node.label "plain" : Node.t)];
  [%expect {| ((kind (Label ((text plain)))) (attrs ()) (children No_children)) |}];
  print_s
    [%sexp
      (Node.label
         ~wrap:true
         ~xalign:0.
         ~ellipsize:End
         ~max_width_chars:14
         ~width_chars:6
         ~selectable:true
         ~use_markup:true
         "styled"
       : Node.t)];
  [%expect
    {|
    ((kind
      (Label
       ((text styled) (wrap true) (xalign 0) (ellipsize (End))
        (max_width_chars 14) (width_chars 6) (selectable true) (use_markup true))))
     (attrs ()) (children No_children))
    |}]
;;

let%expect_test "label props take part in equal_props" =
  let a = (Node.label ~xalign:0. "x").kind in
  let b = (Node.label ~xalign:1. "x").kind in
  print_s [%sexp ((Kind.same_kind a b, Kind.equal_props a b) : bool * bool)];
  [%expect {| (true false) |}]
;;

let%expect_test "the toggle family's constructors" =
  print_s
    [%sexp
      (Node.box
         ~orientation:Vertical
         [ Node.button ~label:"go" ()
         ; Node.button ~icon_name:"list-add-symbolic" ~has_frame:false ()
         ; Node.button ~child:(Node.label "boxed") ()
         ; Node.toggle_button ~label:"bold" ~active:true ()
         ; Node.check_button ~label:"agree" ~active:false ()
         ; Node.switch ~active:true ()
         ]
       : Node.t)];
  [%expect
    {|
    ((kind (Box ((orientation Vertical)))) (attrs ())
     (children
      (List
       (((kind (Button ((label (go))))) (attrs ()) (children (Single ())))
        ((kind (Button ((icon_name (list-add-symbolic)) (has_frame false))))
         (attrs ()) (children (Single ())))
        ((kind (Button ())) (attrs ())
         (children
          (Single
           (((kind (Label ((text boxed)))) (attrs ()) (children No_children))))))
        ((kind (Toggle_button ((label (bold)) (active true)))) (attrs ())
         (children (Single ())))
        ((kind (Check_button ((label (agree)) (active false)))) (attrs ())
         (children No_children))
        ((kind (Switch ((active true)))) (attrs ()) (children No_children))))))
    |}]
;;

let%expect_test "is_event classifies the handler-carrying attr names" =
  print_s [%sexp (Attr.Name.is_event Attr.Name.On_toggled : bool)];
  [%expect {| true |}];
  print_s [%sexp (Attr.Name.is_event Attr.Name.Tooltip : bool)];
  [%expect {| false |}]
;;

let%expect_test "the entry family's constructors" =
  print_s
    [%sexp
      (Node.box
         ~orientation:Vertical
         [ Node.entry ~placeholder:"name" ~text:"" ()
         ; Node.entry ~text:"x" ~width_chars:6 ~xalign:1. ~editable:false ()
         ; Node.password_entry ~text:"" ~placeholder:"passphrase" ()
         ; Node.search_entry ~text:"bach" ~search_delay:150 ()
         ]
       : Node.t)];
  [%expect
    {|
    ((kind (Box ((orientation Vertical)))) (attrs ())
     (children
      (List
       (((kind (Entry ((text "") (placeholder (name))))) (attrs ())
         (children No_children))
        ((kind (Entry ((text x) (editable false) (width_chars 6) (xalign 1))))
         (attrs ()) (children No_children))
        ((kind (Password_entry ((text "") (placeholder (passphrase)))))
         (attrs ()) (children No_children))
        ((kind (Search_entry ((text bach) (search_delay (150))))) (attrs ())
         (children No_children))))))
    |}]
;;

let%expect_test "the numeric family's constructors" =
  print_s
    [%sexp
      (Node.box
         ~orientation:Vertical
         [ Node.spin_button ~min:40. ~max:280. ~value:120. ~step:1. ()
         ; Node.scale
             ~orientation:Horizontal
             ~min:1.
             ~max:32.
             ~value:7.
             ~draw_value:false
             ()
         ; Node.progress_bar ~fraction:0.25 ~text:"loading" ~show_text:true ()
         ; Node.spinner ~spinning:true ()
         ]
       : Node.t)];
  [%expect
    {|
    ((kind (Box ((orientation Vertical)))) (attrs ())
     (children
      (List
       (((kind (Spin_button ((value 120) (min 40) (max 280)))) (attrs ())
         (children No_children))
        ((kind
          (Scale
           ((orientation Horizontal) (value 7) (min 1) (max 32)
            (draw_value false))))
         (attrs ()) (children No_children))
        ((kind
          (Progress_bar ((fraction 0.25) (text (loading)) (show_text true))))
         (attrs ()) (children No_children))
        ((kind (Spinner ((spinning true)))) (attrs ()) (children No_children))))))
    |}]
;;

(* The [Resource] sources and a non-default [icon_size] have no live test: a resource is
   whatever the application compiled into its binary, and there is none here to name. What
   is checkable headlessly is that both reach the kind and print -- which is what says the
   constructor did not quietly drop them. *)
let%expect_test "images, pictures and separators" =
  print_s
    [%sexp
      (Node.box
         ~orientation:Vertical
         [ Node.image ~pixel_size:16 (Icon_name "list-add-symbolic")
         ; Node.image Empty
         ; Node.image ~icon_size:Large (Resource "/org/example/app/icons/add.svg")
         ; Node.image ~icon_size:Normal (File "/tmp/add.png")
         ; Node.picture ~content_fit:Contain ~can_shrink:true (Filename "/tmp/thumb.png")
         ; Node.picture ~content_fit:Cover (Resource "/org/example/app/thumb.png")
         ; Node.separator ~orientation:Horizontal ()
         ]
       : Node.t)];
  [%expect
    {|
    ((kind (Box ((orientation Vertical)))) (attrs ())
     (children
      (List
       (((kind (Image ((source (Icon_name list-add-symbolic)) (pixel_size 16))))
         (attrs ()) (children No_children))
        ((kind (Image ((source Empty)))) (attrs ()) (children No_children))
        ((kind
          (Image
           ((source (Resource /org/example/app/icons/add.svg)) (icon_size Large))))
         (attrs ()) (children No_children))
        ((kind (Image ((source (File /tmp/add.png)) (icon_size Normal))))
         (attrs ()) (children No_children))
        ((kind (Picture ((source (Filename /tmp/thumb.png))))) (attrs ())
         (children No_children))
        ((kind
          (Picture
           ((source (Resource /org/example/app/thumb.png)) (content_fit Cover))))
         (attrs ()) (children No_children))
        ((kind (Separator ((orientation Horizontal)))) (attrs ())
         (children No_children))))))
    |}]
;;

let%expect_test "single-child containers" =
  print_s
    [%sexp
      (Node.scrolled_window
         ~vpolicy:Automatic
         ~hpolicy:Never
         ~propagate_natural_height:true
         (Node.box
            ~orientation:Vertical
            [ Node.frame ~label:"Group" (Node.label "framed")
            ; Node.expander ~label:"More" ~expanded:false (Node.label "hidden")
            ; Node.revealer ~reveal:true ~transition:Slide_down (Node.label "shown")
            ])
       : Node.t)];
  [%expect
    {|
    ((kind (Scrolled_window ((hpolicy Never) (propagate_natural_height true))))
     (attrs ())
     (children
      (Single
       (((kind (Box ((orientation Vertical)))) (attrs ())
         (children
          (List
           (((kind (Frame ((label (Group))))) (attrs ())
             (children
              (Single
               (((kind (Label ((text framed)))) (attrs ())
                 (children No_children))))))
            ((kind (Expander ((label (More)) (expanded false)))) (attrs ())
             (children
              (Single
               (((kind (Label ((text hidden)))) (attrs ())
                 (children No_children))))))
            ((kind (Revealer ((reveal true) (transition Slide_down)))) (attrs ())
             (children
              (Single
               (((kind (Label ((text shown)))) (attrs ()) (children No_children))))))))))))))
    |}]
;;

let%expect_test "slot containers print their slots by name" =
  print_s
    [%sexp
      (Node.center_box
         ~start:(Node.label "l")
         ~center:(Node.label "c")
         ~end_:(Node.button ~label:"r" ())
         ()
       : Node.t)];
  [%expect
    {|
    ((kind (Center_box ())) (attrs ())
     (children
      (Slots
       ((start
         (Single (((kind (Label ((text l)))) (attrs ()) (children No_children)))))
        (center
         (Single (((kind (Label ((text c)))) (attrs ()) (children No_children)))))
        (end
         (Single
          (((kind (Button ((label (r))))) (attrs ()) (children (Single ()))))))))))
    |}];
  print_s
    [%sexp
      (Node.paned
         ~orientation:Horizontal
         ~position:240
         ~start:(Node.label "sidebar")
         ~end_:(Node.label "content")
         ()
       : Node.t)];
  [%expect
    {|
    ((kind (Paned ((orientation Horizontal) (position (240))))) (attrs ())
     (children
      (Slots
       ((start
         (Single
          (((kind (Label ((text sidebar)))) (attrs ()) (children No_children)))))
        (end
         (Single
          (((kind (Label ((text content)))) (attrs ()) (children No_children)))))))))
    |}];
  print_s
    [%sexp
      (Node.overlay
         ~overlays:
           [ Node.picture ~attrs:[ Attr.measure_overlay false ] (Filename "/tmp/t.png") ]
         (Node.box ~orientation:Vertical ~attrs:[ Attr.width_request 150 ] [])
       : Node.t)];
  [%expect
    {|
    ((kind (Overlay ())) (attrs ())
     (children
      (Slots
       ((child
         (Single
          (((kind (Box ((orientation Vertical)))) (attrs ((Width_request 150)))
            (children (List ()))))))
        (overlays
         (List
          (((kind (Picture ((source (Filename /tmp/t.png)))))
            (attrs ((Measure_overlay false))) (children No_children)))))))))
    |}]
;;

let%expect_test "find_by_test_id descends into slots" =
  let view =
    Node.overlay
      ~overlays:[ Node.label ~attrs:[ Attr.test_id "badge" ] "9" ]
      (Node.label "under")
  in
  print_s [%sexp (Option.is_some (Node.find_by_test_id view "badge") : bool)];
  [%expect {| true |}]
;;

let%expect_test "grid children carry their cells; stack pages carry their keys" =
  print_s
    [%sexp
      (Node.grid
         ~row_spacing:6
         ~column_spacing:12
         [ Node.label ~attrs:[ Attr.grid_cell ~column:0 ~row:0 () ] "Name"
         ; Node.entry ~attrs:[ Attr.grid_cell ~column:1 ~row:0 () ] ~text:"" ()
         ; Node.label
             ~attrs:[ Attr.grid_cell ~column:0 ~row:1 ~width:2 () ]
             "spans both columns"
         ]
       : Node.t)];
  [%expect
    {|
    ((kind (Grid ((row_spacing 6) (column_spacing 12)))) (attrs ())
     (children
      (List
       (((kind (Label ((text Name))))
         (attrs ((Grid_cell ((column 0) (row 0) (width 1) (height 1)))))
         (children No_children))
        ((kind (Entry ((text ""))))
         (attrs ((Grid_cell ((column 1) (row 0) (width 1) (height 1)))))
         (children No_children))
        ((kind (Label ((text "spans both columns"))))
         (attrs ((Grid_cell ((column 0) (row 1) (width 2) (height 1)))))
         (children No_children))))))
    |}];
  print_s
    [%sexp
      (Node.box
         ~orientation:Vertical
         [ Node.stack_switcher ~stack:"nav" ()
         ; Node.stack
             ~name:"nav"
             ~visible_child:"library"
             [ Node.label ~key:"library" ~attrs:[ Attr.page_title "Library" ] "L"
             ; Node.label ~key:"practice" ~attrs:[ Attr.page_title "Practice" ] "P"
             ]
         ]
       : Node.t)];
  [%expect
    {|
    ((kind (Box ((orientation Vertical)))) (attrs ())
     (children
      (List
       (((kind (Stack_switcher ((stack nav)))) (attrs ()) (children No_children))
        ((kind (Stack ((name nav) (visible_child library)))) (attrs ())
         (children
          (List
           (((kind (Label ((text L)))) (key library)
             (attrs ((Page_title Library))) (children No_children))
            ((kind (Label ((text P)))) (key practice)
             (attrs ((Page_title Practice))) (children No_children))))))))))
    |}]
;;

let%expect_test "a scrolled window rejects a min content bound above its max" =
  Expect_test_helpers_core.require_does_raise (fun () ->
    Node.scrolled_window ~min_content_width:400 ~max_content_width:200 (Node.label "x"));
  [%expect
    {|
    (Invalid_argument
     "Node.scrolled_window: min_content_width (400) is above max_content_width (200)")
    |}];
  Expect_test_helpers_core.require_does_raise (fun () ->
    Node.scrolled_window ~min_content_height:400 ~max_content_height:200 (Node.label "x"));
  [%expect
    {|
    (Invalid_argument
     "Node.scrolled_window: min_content_height (400) is above max_content_height (200)")
    |}];
  (* [-1] is "no bound" on either side and never conflicts, however large the other is --
     which is what stops the check firing on the defaults. *)
  print_s [%sexp (Node.scrolled_window ~min_content_width:400 (Node.label "x") : Node.t)];
  [%expect
    {|
    ((kind (Scrolled_window ((min_content_width 400)))) (attrs ())
     (children
      (Single (((kind (Label ((text x)))) (attrs ()) (children No_children))))))
    |}];
  print_s [%sexp (Node.scrolled_window ~max_content_width:200 (Node.label "x") : Node.t)];
  [%expect
    {|
    ((kind (Scrolled_window ((max_content_width 200)))) (attrs ())
     (children
      (Single (((kind (Label ((text x)))) (attrs ()) (children No_children))))))
    |}];
  (* Equal bounds are a fixed size, not a conflict. *)
  print_s
    [%sexp
      (Node.scrolled_window ~min_content_width:200 ~max_content_width:200 (Node.label "x")
       : Node.t)];
  [%expect
    {|
    ((kind (Scrolled_window ((min_content_width 200) (max_content_width 200))))
     (attrs ())
     (children
      (Single (((kind (Label ((text x)))) (attrs ()) (children No_children))))))
    |}];
  (* The two axes are independent: a conflict on one is not read off the other. *)
  print_s
    [%sexp
      (Node.scrolled_window
         ~min_content_width:100
         ~max_content_width:400
         ~min_content_height:100
         ~max_content_height:400
         (Node.label "x")
       : Node.t)];
  [%expect
    {|
    ((kind
      (Scrolled_window
       ((min_content_width 100) (min_content_height 100) (max_content_width 400)
        (max_content_height 400))))
     (attrs ())
     (children
      (Single (((kind (Label ((text x)))) (attrs ()) (children No_children))))))
    |}]
;;

let%expect_test "entry max_length reaches the kind and defaults away" =
  print_s [%sexp (Node.entry ~text:"a" () : Node.t)];
  [%expect {| ((kind (Entry ((text a)))) (attrs ()) (children No_children)) |}];
  print_s [%sexp (Node.entry ~text:"a" ~max_length:8 () : Node.t)];
  [%expect
    {| ((kind (Entry ((text a) (max_length 8)))) (attrs ()) (children No_children)) |}];
  (* GTK's own default is [0] -- "no limit" -- rather than the [-1] the size requests
     beside it use, so a caller asking for [0] explicitly is asking for GTK's default and
     the sexp drops it. *)
  print_s [%sexp (Node.entry ~text:"a" ~max_length:0 () : Node.t)];
  [%expect {| ((kind (Entry ((text a)))) (attrs ()) (children No_children)) |}];
  print_s
    [%sexp
      (( Kind.equal_props
           (Node.entry ~text:"a" ()).kind
           (Node.entry ~text:"a" ~max_length:8 ()).kind
       , Kind.equal_props
           (Node.entry ~text:"a" ~max_length:8 ()).kind
           (Node.entry ~text:"a" ~max_length:8 ()).kind )
       : bool * bool)];
  [%expect {| (false true) |}]
;;

let%expect_test "list box constructors and defaults" =
  print_s
    [%sexp
      (Node.list_box
         ~selected:[]
         [ Node.label ~key:"a" "Alpha"; Node.label ~key:"b" "Beta" ]
       : Node.t)];
  [%expect
    {|
    ((kind (List_box ((selected ())))) (attrs ())
     (children
      (Slots
       ((placeholder (Single ()))
        (rows
         (List
          (((kind (Label ((text Alpha)))) (key a) (attrs ())
            (children No_children))
           ((kind (Label ((text Beta)))) (key b) (attrs ())
            (children No_children)))))))))
    |}];
  print_s
    [%sexp
      (Node.list_box
         ~selection_mode:Browse
         ~activate_on_single_click:true
         ~show_separators:true
         ~placeholder:(Node.label "nothing here")
         ~selected:[ "b" ]
         [ Node.label ~key:"a" ~attrs:[ Attr.row_selectable false ] "Header"
         ; Node.label ~key:"b" "Beta"
         ]
       : Node.t)];
  [%expect
    {|
    ((kind
      (List_box ((selection_mode Browse) (show_separators true) (selected (b)))))
     (attrs ())
     (children
      (Slots
       ((placeholder
         (Single
          (((kind (Label ((text "nothing here")))) (attrs ())
            (children No_children)))))
        (rows
         (List
          (((kind (Label ((text Header)))) (key a)
            (attrs ((Row_selectable false))) (children No_children))
           ((kind (Label ((text Beta)))) (key b) (attrs ())
            (children No_children)))))))))
    |}]
;;

(* [selection_mode] and [activate_on_single_click] are GTK's own defaults, so the sexp
   drops a caller who asks for them explicitly -- which is the [@sexp_drop_if] rule, and
   the one that is easy to get backwards here because [Single] is not the first
   constructor of {!Selection_mode.t} and [true] is not the usual "off" default. *)
let%expect_test "a list box's props take part in equal_props, and GTK's defaults drop" =
  print_s
    [%sexp
      (Node.list_box
         ~selection_mode:Single
         ~activate_on_single_click:true
         ~show_separators:false
         ~selected:[]
         []
       : Node.t)];
  [%expect
    {|
    ((kind (List_box ((selected ())))) (attrs ())
     (children (Slots ((placeholder (Single ())) (rows (List ()))))))
    |}];
  let a = (Node.list_box ~selected:[ "a" ] []).kind in
  let b = (Node.list_box ~selected:[ "b" ] []).kind in
  let c = (Node.list_box ~selection_mode:Multiple ~selected:[ "a" ] []).kind in
  print_s
    [%sexp
      (( Kind.same_kind a b
       , Kind.equal_props a b
       , Kind.equal_props a c
       , Kind.equal_props a a )
       : bool * bool * bool * bool)];
  [%expect {| (true false false true) |}]
;;

(* Unlike a stack page, whose missing key M1 caught at mount, this is caught where the
   children are already in hand. The four keyed containers share the rule, so they share
   the message shape. *)
let%expect_test "a list box child without a key is rejected at the constructor" =
  Expect_test_helpers_core.require_does_raise (fun () ->
    Node.list_box ~selected:[] [ Node.label "unkeyed" ]);
  [%expect
    {|
    (Invalid_argument
     "Node.list_box: child 0 has no ~key (a row's key is the identity every handler receives)")
    |}];
  (* The placeholder is not a row, so it needs no key. *)
  print_s
    [%sexp (Node.list_box ~placeholder:(Node.label "empty") ~selected:[] [] : Node.t)];
  [%expect
    {|
    ((kind (List_box ((selected ())))) (attrs ())
     (children
      (Slots
       ((placeholder
         (Single
          (((kind (Label ((text empty)))) (attrs ()) (children No_children)))))
        (rows (List ()))))))
    |}]
;;

let%expect_test "a stack page without a key is rejected at the constructor" =
  Expect_test_helpers_core.require_does_raise (fun () ->
    Node.stack ~name:"nav" ~visible_child:"a" [ Node.label "unkeyed" ]);
  [%expect
    {|
    (Invalid_argument
     "Node.stack: child 0 has no ~key (a stack page's key is its GTK page name)")
    |}];
  (* The index is the caller's, so a keyed page beside an unkeyed one names the right one. *)
  Expect_test_helpers_core.require_does_raise (fun () ->
    Node.stack
      ~name:"nav"
      ~visible_child:"a"
      [ Node.label ~key:"a" "keyed"; Node.label "unkeyed" ]);
  [%expect
    {|
    (Invalid_argument
     "Node.stack: child 1 has no ~key (a stack page's key is its GTK page name)")
    |}]
;;

(* The same machinery as the list box, over [GtkFlowBoxChild], with geometry props in
   place of [show_separators]. Every default below was read off a live [GtkFlowBox] rather
   than out of the GTK docs -- [max_children_per_line] in particular, which is a real 7
   and not "unlimited". *)
let%expect_test "flow box constructors and defaults" =
  print_s
    [%sexp
      (Node.flow_box
         ~selected:[]
         [ Node.label ~key:"a" "Alpha"; Node.label ~key:"b" "Beta" ]
       : Node.t)];
  [%expect
    {|
    ((kind (Flow_box ((selected ())))) (attrs ())
     (children
      (List
       (((kind (Label ((text Alpha)))) (key a) (attrs ()) (children No_children))
        ((kind (Label ((text Beta)))) (key b) (attrs ()) (children No_children))))))
    |}];
  (* Stavekeeper's library grid, prop for prop (library_window.ml's [build_grid]). *)
  print_s
    [%sexp
      (Node.flow_box
         ~selection_mode:Single
         ~activate_on_single_click:false
         ~min_children_per_line:1
         ~max_children_per_line:10
         ~row_spacing:28
         ~column_spacing:20
         ~homogeneous:false
         ~selected:[ "b" ]
         [ Node.label ~key:"a" "A"; Node.label ~key:"b" "B" ]
       : Node.t)];
  [%expect
    {|
    ((kind
      (Flow_box
       ((activate_on_single_click false) (min_children_per_line 1)
        (max_children_per_line 10) (row_spacing 28) (column_spacing 20)
        (selected (b)))))
     (attrs ())
     (children
      (List
       (((kind (Label ((text A)))) (key a) (attrs ()) (children No_children))
        ((kind (Label ((text B)))) (key b) (attrs ()) (children No_children))))))
    |}];
  (* The list view the same grid switches to, which is four props in one diff. *)
  print_s
    [%sexp
      (Node.flow_box
         ~max_children_per_line:1
         ~homogeneous:true
         ~orientation:Vertical
         ~selected:[]
         []
       : Node.t)];
  [%expect
    {|
    ((kind
      (Flow_box
       ((max_children_per_line 1) (homogeneous true) (orientation Vertical)
        (selected ()))))
     (attrs ()) (children (List ())))
    |}]
;;

(* GTK's own defaults drop from the sexp, and the two that are easy to get backwards are
   [selection_mode = Single] (not [None_]) and [max_children_per_line = 7] (not
   "unlimited"). Both were confirmed against a fresh [GtkFlowBox]. *)
let%expect_test "a flow box's props take part in equal_props, and GTK's defaults drop" =
  print_s
    [%sexp
      (Node.flow_box
         ~selection_mode:Single
         ~activate_on_single_click:true
         ~min_children_per_line:0
         ~max_children_per_line:7
         ~row_spacing:0
         ~column_spacing:0
         ~homogeneous:false
         ~orientation:Horizontal
         ~selected:[]
         []
       : Node.t)];
  [%expect {| ((kind (Flow_box ((selected ())))) (attrs ()) (children (List ()))) |}];
  let a = (Node.flow_box ~selected:[ "a" ] []).kind in
  let b = (Node.flow_box ~selected:[ "b" ] []).kind in
  let c = (Node.flow_box ~max_children_per_line:3 ~selected:[ "a" ] []).kind in
  let d = (Node.list_box ~selected:[ "a" ] []).kind in
  print_s
    [%sexp
      (( Kind.same_kind a b
       , Kind.equal_props a b
       , Kind.equal_props a c
       , Kind.equal_props a a
       , Kind.same_kind a d )
       : bool * bool * bool * bool * bool)];
  [%expect {| (true false false true false) |}]
;;

let%expect_test "a flow box child without a key is rejected at the constructor" =
  Expect_test_helpers_core.require_does_raise (fun () ->
    Node.flow_box ~selected:[] [ Node.label "unkeyed" ]);
  [%expect
    {|
    (Invalid_argument
     "Node.flow_box: child 0 has no ~key (a child's key is the identity every handler receives)")
    |}];
  Expect_test_helpers_core.require_does_raise (fun () ->
    Node.flow_box ~selected:[] [ Node.label ~key:"a" "keyed"; Node.label "unkeyed" ]);
  [%expect
    {|
    (Invalid_argument
     "Node.flow_box: child 1 has no ~key (a child's key is the identity every handler receives)")
    |}]
;;

(* The geometry numbers GTK will not take. [gtk_flow_box_set_max_children_per_line] is
   [g_return_if_fail (n_children > 0)] -- a critical on stderr and the old value kept --
   and every one of these properties is unsigned in C, so a negative reaches GTK as a very
   large positive number with no complaint at all (measured: a minimum of [-1] reads back
   as 65535, a row spacing of [-5] as 4294967291). Neither has a diagnostic worth the
   name, which is the test {!Node.scrolled_window}'s min/max rejection already passes. *)
let%expect_test "a flow box's geometry numbers are checked at the constructor" =
  Expect_test_helpers_core.require_does_raise (fun () ->
    Node.flow_box ~max_children_per_line:0 ~selected:[] []);
  [%expect
    {|
    (Invalid_argument
     "Node.flow_box: ~max_children_per_line is 0, but GTK requires at least 1 (a flow box has no \"unlimited\"; its own default is 7)")
    |}];
  Expect_test_helpers_core.require_does_raise (fun () ->
    Node.flow_box ~min_children_per_line:(-1) ~selected:[] []);
  [%expect
    {|
    (Invalid_argument
     "Node.flow_box: ~min_children_per_line is -1, but GTK reads it as an unsigned number (a negative one arrives as a very large positive one, with no error)")
    |}];
  Expect_test_helpers_core.require_does_raise (fun () ->
    Node.flow_box ~row_spacing:(-5) ~selected:[] []);
  [%expect
    {|
    (Invalid_argument
     "Node.flow_box: ~row_spacing is -5, but GTK reads it as an unsigned number (a negative one arrives as a very large positive one, with no error)")
    |}];
  Expect_test_helpers_core.require_does_raise (fun () ->
    Node.flow_box ~column_spacing:(-1) ~selected:[] []);
  [%expect
    {|
    (Invalid_argument
     "Node.flow_box: ~column_spacing is -1, but GTK reads it as an unsigned number (a negative one arrives as a very large positive one, with no error)")
    |}];
  (* [0] is legal for the minimum ("no minimum") and for both spacings; only the maximum
     has a floor. *)
  print_s
    [%sexp
      (Node.flow_box
         ~min_children_per_line:0
         ~max_children_per_line:1
         ~row_spacing:0
         ~selected:[]
         []
       : Node.t)];
  [%expect
    {|
    ((kind (Flow_box ((max_children_per_line 1) (selected ())))) (attrs ())
     (children (List ())))
    |}]
;;

(* The third keyed container, and the only one whose children really move: [GtkNotebook]
   has [reorder_child], so [Node.notebook] is an {i ordered} container and the reconciler
   emits [Move] for it. Every default below was read off a live [GtkNotebook] rather than
   out of the docs -- and unlike the flow box's, none of them is a surprise: tabs and
   border are on, scrolling arrows are off, and the tabs are at the top. *)
let%expect_test "notebook constructors and defaults" =
  print_s
    [%sexp
      (Node.notebook
         ~current_page:"a"
         [ Node.label ~key:"a" ~attrs:[ Attr.tab_label "Alpha" ] "Alpha"
         ; Node.label ~key:"b" ~attrs:[ Attr.tab_label "Beta" ] "Beta"
         ]
       : Node.t)];
  [%expect
    {|
    ((kind (Notebook ((current_page a)))) (attrs ())
     (children
      (List
       (((kind (Label ((text Alpha)))) (key a) (attrs ((Tab_label Alpha)))
         (children No_children))
        ((kind (Label ((text Beta)))) (key b) (attrs ((Tab_label Beta)))
         (children No_children))))))
    |}];
  (* A page with no [Attr.tab_label] is legal: GTK draws an unnamed tab for it (measured
     -- [get_tab_label] answers [None] and there is no label widget at all), which is what
     [~show_tabs:false] wants and what dropping the attr restores. *)
  print_s
    [%sexp
      (Node.notebook
         ~scrollable:true
         ~show_tabs:false
         ~show_border:false
         ~tab_pos:Left
         ~current_page:"b"
         [ Node.label ~key:"a" "Alpha"; Node.label ~key:"b" "Beta" ]
       : Node.t)];
  [%expect
    {|
    ((kind
      (Notebook
       ((current_page b) (scrollable true) (show_tabs false) (show_border false)
        (tab_pos Left))))
     (attrs ())
     (children
      (List
       (((kind (Label ((text Alpha)))) (key a) (attrs ()) (children No_children))
        ((kind (Label ((text Beta)))) (key b) (attrs ()) (children No_children))))))
    |}]
;;

(* GTK's own defaults drop from the sexp; [current_page] never does, because it is a
   required labelled argument and so always something the caller asked for. *)
let%expect_test "a notebook's props take part in equal_props, and GTK's defaults drop" =
  print_s
    [%sexp
      (Node.notebook
         ~scrollable:false
         ~show_tabs:true
         ~show_border:true
         ~tab_pos:Top
         ~current_page:"a"
         []
       : Node.t)];
  [%expect {| ((kind (Notebook ((current_page a)))) (attrs ()) (children (List ()))) |}];
  let a = (Node.notebook ~current_page:"a" []).kind in
  let b = (Node.notebook ~current_page:"b" []).kind in
  let c = (Node.notebook ~scrollable:true ~current_page:"a" []).kind in
  let d = (Node.stack ~name:"s" ~visible_child:"a" []).kind in
  print_s
    [%sexp
      (( Kind.same_kind a b
       , Kind.equal_props a b
       , Kind.equal_props a c
       , Kind.equal_props a a
       , Kind.same_kind a d )
       : bool * bool * bool * bool * bool)];
  [%expect {| (true false false true false) |}]
;;

(* The same rule as the other three keyed containers, with the notebook's own reason: a
   page's key is what [~current_page] names and what [Attr.on_page_changed] hands back. *)
let%expect_test "a notebook page without a key is rejected at the constructor" =
  Expect_test_helpers_core.require_does_raise (fun () ->
    Node.notebook ~current_page:"a" [ Node.label "unkeyed" ]);
  [%expect
    {|
    (Invalid_argument
     "Node.notebook: child 0 has no ~key (a page's key is what ~current_page names and every handler receives)")
    |}];
  Expect_test_helpers_core.require_does_raise (fun () ->
    Node.notebook ~current_page:"a" [ Node.label ~key:"a" "keyed"; Node.label "unkeyed" ]);
  [%expect
    {|
    (Invalid_argument
     "Node.notebook: child 1 has no ~key (a page's key is what ~current_page names and every handler receives)")
    |}]
;;

(* [Attr.tab_label] is a [string] rather than a node, and that is a decision rather than a
   limitation: the tab label is a widget GTK owns and rebuilds, so a node there would mean
   a second child list, a second patch path and a second lifetime for something that is
   always a label. A tab that needs an icon is a [Node.native]. *)
let%expect_test "tab_label rides on the page node" =
  print_s
    [%sexp
      (Node.notebook
         ~current_page:"a"
         [ Node.label ~key:"a" ~attrs:[ Attr.tab_label "Alpha" ] "A" ]
       : Node.t)];
  [%expect
    {|
    ((kind (Notebook ((current_page a)))) (attrs ())
     (children
      (List
       (((kind (Label ((text A)))) (key a) (attrs ((Tab_label Alpha)))
         (children No_children))))))
    |}]
;;

(* [~text] is a labelled {i non-optional} argument, exactly as on the three entries: a
   text view whose text nothing feeds back into the model is an uncontrolled widget that
   snaps back to the model's value the next time anything re-renders, and making the
   argument required is what stops that being written by accident. There is no runtime
   assertion to make here -- [Node.text_view ()] is a type error -- so what this pins is
   the other half: every optional prop is GTK's own default and drops out of the sexp. *)
let%expect_test "text view constructor and defaults" =
  print_s [%sexp (Node.text_view ~text:"note" () : Node.t)];
  [%expect {| ((kind (Text_view ((text note)))) (attrs ()) (children No_children)) |}];
  print_s
    [%sexp
      (Node.text_view
         ~wrap:Word_char
         ~editable:false
         ~monospace:true
         ~cursor_visible:false
         ~accepts_tab:false
         ~left_margin:6
         ~right_margin:7
         ~top_margin:8
         ~bottom_margin:9
         ~text:"styled"
         ()
       : Node.t)];
  [%expect
    {|
    ((kind
      (Text_view
       ((text styled) (wrap Word_char) (editable false) (monospace true)
        (cursor_visible false) (accepts_tab false) (left_margin 6)
        (right_margin 7) (top_margin 8) (bottom_margin 9))))
     (attrs ()) (children No_children))
    |}];
  (* Every default written out explicitly is GTK's own, so the sexp drops all nine. Read
     off a fresh [GtkTextView] rather than out of the docs: [accepts_tab] and
     [cursor_visible] are [true], which is not what a reader guesses for either. *)
  print_s
    [%sexp
      (Node.text_view
         ~wrap:None_
         ~editable:true
         ~monospace:false
         ~cursor_visible:true
         ~accepts_tab:true
         ~left_margin:0
         ~right_margin:0
         ~top_margin:0
         ~bottom_margin:0
         ~text:"note"
         ()
       : Node.t)];
  [%expect {| ((kind (Text_view ((text note)))) (attrs ()) (children No_children)) |}]
;;

let%expect_test "text view props take part in equal_props" =
  let props ?wrap ?monospace ?left_margin () =
    (Node.text_view ?wrap ?monospace ?left_margin ~text:"a" ()).kind
  in
  print_s
    [%sexp
      (( Kind.equal_props (props ()) (props ())
       , Kind.equal_props (props ()) (props ~wrap:Word ())
       , Kind.equal_props (props ()) (props ~monospace:true ())
       , Kind.equal_props (props ()) (props ~left_margin:4 ()) )
       : bool * bool * bool * bool)];
  [%expect {| (true false false false) |}];
  (* Same constructor, different props: the patcher's [update] runs, [create] does not. *)
  print_s [%sexp (Kind.same_kind (props ()) (props ~wrap:Word ()) : bool)];
  [%expect {| true |}]
;;
