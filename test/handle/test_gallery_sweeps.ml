open! Core
open Bonsai_gtk_vtree
open Bonsai.Let_syntax

(* The nets under [test_gallery.ml]'s golden.

   The golden says "this exact tree still sexps this way". What it cannot say is "this
   tree is still {i everything}" -- a constructor or an attribute added in a later
   milestone and never put in [test_gallery_tree.ml] would leave the golden green and the
   coverage claim in that file's header false. Task 11 found exactly that: Task 10 had
   added [Node.drop_down] and [Node.level_bar] and neither was in the tree, so their
   defaults were pinned by no snapshot at all.

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
let sweep_tree = Test_gallery_tree.gallery_tree ~n:0 ~set_n:(fun _ -> Ui_effect.Ignore)

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
    | On_cursor_moved -> Some "Move_cursor"
    | On_closed -> Some "Close_popover"
    | Actions -> Some "Activate_action"
    | Shortcut -> Some "Fire_shortcut"
    | On_click -> Some "Click_at"
    | On_focus_enter -> Some "Focus_enter"
    | On_focus_leave -> Some "Focus_leave"
    | On_contains_focus_changed -> Some "Focus_contains"
    | On_key_pressed -> Some "Key_press"
    | On_key_released -> Some "Key_release"
    (* Not event attrs; [is_event] filters them out before this is reached, and they are
       spelled out rather than wildcarded so that a name added to [Attr.Name.t] is a
       compile error here and its author has to say which half it is in. *)
    | Autofocus
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
  (* The popover's row: a [Node.popover] is legal only as a menu button's [~popover] slot,
     so its subject sits inside a scaffold menu button rather than beside the scaffold --
     the same reason the window's sits at the root. *)
  | In_menu_button

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
  | In_menu_button ->
    (* The menu button is the scaffold's, always present; the {i subject} is the slot, so
       its unmount phase is the slot emptying. *)
    Node.window (scaffold (Some (Node.menu_button ?popover:subject ())))
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
  | In_menu_button ->
    (match tree.children with
     | Single (Some box) ->
       (match box.children with
        | List [ _step; _stack; _stack2; mb ] ->
          (match mb.children with
           | Slots [ ("popover", Single subject) ] -> subject
           | _ -> failwith "lifecycle sweep: unexpected menu button shape")
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
    | Child | In_menu_button ->
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
       | (Child | In_menu_button), None -> "ok"
       | (Child | In_menu_button), Some _ -> "STILL THERE")
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
  ; ( Child
    , Node.header_bar ~show_title_buttons:false ~start:[ keyed "a" ] ()
    , Node.header_bar ~title:(child ()) ~start:[ keyed "a"; keyed "b" ] () )
  ; ( Child
    , Node.action_bar ~revealed:false ~center:(child ()) ~start:[ keyed "a" ] ()
    , Node.action_bar ~center:(child ()) ~start:[ keyed "a"; keyed "b" ] () )
  ; ( Child
    , Node.menu_button ~label:"a" ()
    , Node.menu_button ~icon_name:"open-menu-symbolic" ~always_show_arrow:true () )
  ; ( In_menu_button
    , Node.popover ~open_:false (child ())
    , Node.popover ~open_:true ~position:Top (child ()) )
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
    Header_bar      mount=ok patch=ok unmount=ok        same_kind=true  props_changed=true  child_ops=start=1I/0M/0R/1U end=0I/0M/0R/0U
    Action_bar      mount=ok patch=ok unmount=ok        same_kind=true  props_changed=true  child_ops=start=1I/0M/0R/1U end=0I/0M/0R/0U
    Menu_button     mount=ok patch=ok unmount=ok        same_kind=true  props_changed=true  child_ops=-
    Popover         mount=ok patch=ok unmount=ok        same_kind=true  props_changed=true  child_ops=-
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
