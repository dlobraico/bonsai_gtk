open! Core
open Bonsai_gtk_vtree

module Action = struct
  type t =
    | Click of string
    | Toggle of string
    | Set_text of string * string
    | Activate of string
    | Set_value of string * float
    | Search_changed of string * string
    | Set_expanded of string * bool
    | Set_revealed of string * bool
    | Set_position of string * int
    | Set_visible_child of string * Key.t
    | Click_at of string * Click_event.t
    | Focus_enter of string
    | Focus_leave of string
    | Focus_contains of string * bool
    | Key_press of string * Key_event.t
    | Key_release of string * Key_event.t
    | Activate_row of string * Key.t
    | Activate_child of string * Key.t
    | Set_selection of string * Key.t list
    | Set_page of string * Key.t
    | Set_selected of string * int
    | Select_day of string * Date.t
    | Set_editing of string * bool
  [@@deriving sexp_of]
end

let node_exn (node : Node.t) id =
  match Node.find_by_test_id node id with
  | Some n -> n
  | None -> failwithf "Bonsai_gtk_test: no node with test_id %s" id ()
;;

(* The node an action found, checked to be the container kind the action names.

   [Activate_row] and [Activate_child] each name a {i kind}: they are two different GTK
   signals on two different widgets, and a test reading [Activate_row ("grid", ...)]
   against a flow box is confusing however it fails. The handle has the node in hand and
   can therefore say which kind it found, which is strictly more useful than the "no
   on_row_activated handler" it would otherwise report -- true, but the less informative
   half of the truth. *)
let of_kind_exn (n : Node.t) id ~expected ~is_expected =
  if not (is_expected n.kind)
  then
    failwithf
      "Bonsai_gtk_test: node %s is a %s, not a %s"
      id
      (Kind.name n.kind)
      expected
      ()
;;

(* The value a real toggle would take: whatever the node is *not* showing now. Reading it
   off the node rather than taking it as an argument is what makes the action mean "the
   user clicked this", which is the only thing a test can honestly claim. *)
let current_active (node : Node.t) id =
  match node.kind with
  | Toggle_button { active; _ } | Check_button { active; _ } | Switch { active } -> active
  (* Defensive, and with no legal path to it: the three kinds [Events.for_kind] says emit
     [On_toggled] are exactly the three matched above, and a node carrying
     [Attr.on_toggled] on any other kind is refused by [require_supported] before an
     action can be dispatched against it. Kept because it is the arm that would fire if
     those two lists ever drifted apart, and a [match] failure here would be a far worse
     diagnostic. *)
  | k ->
    failwithf "Bonsai_gtk_test: %s (test_id %s) has no toggle state" (Kind.name k) id ()
;;

(* The two halves of what the runtime checks from pure vtree data, checked here from the
   same two tables ([Events] and [Placement]) so that a headless suite cannot certify a
   tree the runtime refuses. The message shape and the path spelling are the patcher's:
   [Kind.name] is what [Widget_impl.name] is set to for every impl, [Children.iteri] walks
   the paths the patcher builds, and the root is ["root"] because that is what [Driver]
   mounts under.

   Placement first, then events, because that is the order a mount reaches them --
   [Patcher.check_placement] runs at the top of [mount] and [Signals.require_specs]
   further down -- so a node carrying both mistakes reports the same one here and there.

   [~parent] is the kind of the node above, [None] at the root: a placement attr is read
   by the container, so it is the parent that decides. The event half does not need it. *)
(* The container's path prefixed onto a rejection its own child list produced, which is
   what [Patcher.child_op] does at mount and for the same reason: the check knows nothing
   about where in the tree it is. *)
let child_op ~path f =
  try f () with
  | Invalid_argument msg -> invalid_argf "%s: %s" path msg ()
;;

(* Two siblings with one key, from the same function the patcher calls at mount
   ([Patcher.mount_list] -> [Reconcile.check_unique_keys]) and with the same path
   prefixing, so the two messages are identical by construction. A [Slots] container is
   walked into rather than through: each slot has a child list of its own, and the path a
   slot's list is checked under is the one the patcher spells for it. *)
let rec require_unique_keys ~path (children : Node.t Children.t) =
  match children with
  | No_children | Single _ -> ()
  | List cs ->
    child_op ~path (fun () ->
      Reconcile.check_unique_keys ~key:(fun (n : Node.t) -> n.key) cs)
  | Slots slots ->
    List.iter slots ~f:(fun (name, slot) ->
      require_unique_keys ~path:(sprintf "%s/%s" path name) slot)
;;

let rec require_supported ~path ~parent (node : Node.t) =
  (* A [GtkWindow] is a toplevel and cannot be parented, so the patcher refuses one below
     the root -- with this message, which is copied rather than shared because [Patcher]
     is in the package this library cannot link. [~parent] is [None] at the root only,
     which is exactly the distinction the rule needs. *)
  (match node.kind, parent with
   | Window _, Some _ ->
     invalid_argf
       "%s: a Node.window may only be the root node, not a child of another node"
       path
       ()
   | (Window _ | _), _ -> ());
  (* Unlike the event message below, this one is built by [Placement] itself and not
     rebuilt here: it has two shapes and names three things, which is more than two
     consumers can be trusted to spell the same way twice. *)
  Option.iter (Placement.rejection ~path ~parent node.attrs) ~f:invalid_arg;
  (match Events.unsupported node.kind node.attrs with
   | None -> ()
   | Some name ->
     invalid_argf
       "%s: %s does not emit %s"
       path
       (Kind.name node.kind)
       (Attr.Name.to_string name)
       ());
  (* The third thing the runtime refuses that is decidable from pure vtree data: a
     family's attrs share one controller and so one propagation phase, and a node asking
     for two is one [Controllers] cannot mount. Same function, same string, so the two
     messages are identical rather than merely similar -- and over every family, in
     [Family.all] order, which is the order [Controllers.update] configures them in, so a
     node carrying two families' disagreements reports the same one here and there. Last
     of the three because it is last at mount too -- [Controllers.update] runs after
     [Signals.require_specs]. *)
  List.iter Events.Family.all ~f:(fun family ->
    Option.iter (Events.family_phase_rejection ~path family node.attrs) ~f:invalid_arg);
  require_unique_keys ~path node.children;
  Children.iteri node.children ~path ~f:(fun path child ->
    require_supported ~path ~parent:(Some node.kind) child)
;;

(* Which entry point the tree under test is destined for, set by {!create}.

   The root rule is the {i runtime's} rather than the tree's, and the two halves are
   opposites: [Bonsai_gtk.start] shows the root itself and a [GtkWindow] is the only thing
   GTK can show on its own, while [Bonsai_gtk.Expert.embed] parents the root into a
   container the caller owns and a [GtkWindow] is a toplevel that cannot be parented. So
   the check needs to know something no [Node.t] carries, and [create] is the only place
   that is told.

   A mutable global rather than a field of the handle, and the reason is that [Handle.t]
   {i is} [Bonsai_test.Handle.t] -- deliberately, so that the four values this library
   re-exports unchanged still work -- and there is nowhere on it to put one. Two
   consequences, both worth stating: the rule checked is the most recently created
   handle's, so a test that creates two handles with {i different} root kinds and then
   advances the older one is checked against the wrong rule; and because the two rules are
   opposites rather than one being weaker, getting it wrong always produces a loud
   rejection of a legal tree and never a silent acceptance of an illegal one. Nothing in
   this repository interleaves two handles at all.

   Wrapping the computation instead was tried and is worse: raising from inside a
   [Bonsai.map] poisons Incremental for the rest of the process ("cannot stabilize --
   stabilize previously raised"), so one root-kind failure would break every later test in
   the same executable. *)
let current_root_kind = ref `Window

(* [Driver.check_root]'s match, and its messages, copied because the runtime lives in the
   package this library cannot link. The goldens in [test/handle/test_handle.ml] are what
   keeps the two spellings the same. *)
let check_root (node : Node.t) =
  match !current_root_kind, node.kind with
  | `Window, Window _ -> ()
  | `Window, k ->
    invalid_argf
      "Bonsai_gtk: the root node must be a Node.window, got %s. A tree started this way \
       shows its own root, and a GtkWindow is the only thing GTK can show on its own. \
       Use Bonsai_gtk.Expert.embed for a tree parented into a container you already own."
      (Kind.name k)
      ()
  | `Not_window, Window _ ->
    invalid_arg
      "Bonsai_gtk.embed: the root node is a Node.window, but an embedded tree is \
       parented into a container the caller owns and a GtkWindow is a toplevel that \
       cannot be parented. Use Bonsai_gtk.start for a tree that owns its window, or make \
       the root a container."
  | `Not_window, _ -> ()
;;

module Result_spec = struct
  type t = Node.t
  type incoming = Action.t

  (* Everything this library checks about a tree, and nothing about printing it. Separate
     from [view] because the three shadowed entry points below want the checks without the
     string: [with_check] used to call [view] and discard its result, which rendered the
     whole tree's sexp -- up to [max_computes] (default 100) times per
     [recompute_view_until_stable] -- for an exception. *)
  let check node =
    (* Root first, because it is first at mount too: [Driver.frame] checks the root before
       the patcher walks anything, so a tree with both mistakes reports the same one here
       and there. *)
    check_root node;
    require_supported ~path:"root" ~parent:None node
  ;;

  let view node =
    check node;
    Sexp.to_string_hum (Node.sexp_of_t node)
  ;;

  let incoming node (action : Action.t) =
    match action with
    | Click id ->
      let n = node_exn node id in
      (match (Attrs.find n.attrs On_clicked :> Attr.Private.t option) with
       | Some (On_clicked h) -> h ()
       | _ -> failwithf "Bonsai_gtk_test: node %s has no on_clicked handler" id ())
    | Toggle id ->
      let n = node_exn node id in
      (match (Attrs.find n.attrs On_toggled :> Attr.Private.t option) with
       | Some (On_toggled h) -> h (not (current_active n id))
       | _ -> failwithf "Bonsai_gtk_test: node %s has no on_toggled handler" id ())
    (* Deliberately does not consult the node's [text] prop: the action means "the user
       made the text be this", which is what a real edit produces regardless of what the
       widget was showing before. *)
    | Set_text (id, text) ->
      let n = node_exn node id in
      (match (Attrs.find n.attrs On_changed :> Attr.Private.t option) with
       | Some (On_changed h) -> h text
       | _ -> failwithf "Bonsai_gtk_test: node %s has no on_changed handler" id ())
    | Activate id ->
      let n = node_exn node id in
      (match (Attrs.find n.attrs On_activate :> Attr.Private.t option) with
       | Some (On_activate h) -> h ()
       | _ -> failwithf "Bonsai_gtk_test: node %s has no on_activate handler" id ())
    (* Like [Set_text], and unlike [Toggle]: the node's own [value] is never consulted,
       because "the user moved it to here" is what a drag or a spin produces whatever the
       widget was showing. Headless, there is also no adjustment to clamp or round it, so
       a value outside the node's [min]/[max] reaches the handler as written -- which is
       the point, since clamping is the model's job to demonstrate. *)
    | Set_value (id, value) ->
      let n = node_exn node id in
      (match (Attrs.find n.attrs On_value_changed :> Attr.Private.t option) with
       | Some (On_value_changed h) -> h value
       | _ -> failwithf "Bonsai_gtk_test: node %s has no on_value_changed handler" id ())
    (* Like [Set_text] and for the same reason, the node's own [text] is not consulted.
       Distinct from [Set_text] on the same node: [changed] and [search-changed] are
       different signals on the real widget. *)
    | Search_changed (id, text) ->
      let n = node_exn node id in
      (match (Attrs.find n.attrs On_search_changed :> Attr.Private.t option) with
       | Some (On_search_changed h) -> h text
       | _ -> failwithf "Bonsai_gtk_test: node %s has no on_search_changed handler" id ())
    (* The node's own [expanded] prop is not consulted, so a test can show a model that
       declines to open. Unlike [Toggle], which reads the widget's current state because
       "the user clicked it" has no other meaning, an expander is dragged to a state. *)
    | Set_expanded (id, expanded) ->
      let n = node_exn node id in
      (match (Attrs.find n.attrs On_expanded_changed :> Attr.Private.t option) with
       | Some (On_expanded_changed h) -> h expanded
       | _ ->
         failwithf "Bonsai_gtk_test: node %s has no on_expanded_changed handler" id ())
    (* The three actions the milestone shipped without, each on the shape above: a value
       the user's action produced, handed to the attr that reports it, with the node's own
       prop deliberately not consulted. Until they existed, a handler attached with
       [Attr.on_revealed], [Attr.on_position_changed] or [Attr.on_visible_child_changed]
       could not be fired by any headless test at all -- and no sweep could see that,
       because the attrs sweep is satisfied by the attr being present in a tree. The
       coverage sweep in [test/handle/test_gallery.ml] is what makes the next omission a
       failure. *)
    | Set_revealed (id, revealed) ->
      let n = node_exn node id in
      (match (Attrs.find n.attrs On_revealed :> Attr.Private.t option) with
       | Some (On_revealed h) -> h revealed
       | _ -> failwithf "Bonsai_gtk_test: node %s has no on_revealed handler" id ())
    | Set_position (id, position) ->
      let n = node_exn node id in
      (match (Attrs.find n.attrs On_position_changed :> Attr.Private.t option) with
       | Some (On_position_changed h) -> h position
       | _ ->
         failwithf "Bonsai_gtk_test: node %s has no on_position_changed handler" id ())
    | Set_visible_child (id, key) ->
      let n = node_exn node id in
      (match (Attrs.find n.attrs On_visible_child_changed :> Attr.Private.t option) with
       | Some (On_visible_child_changed h) -> h key
       | _ ->
         failwithf
           "Bonsai_gtk_test: node %s has no on_visible_child_changed handler"
           id
           ())
    (* Nothing is derived from the node, and in particular the [button] the attr was
       constructed with is *not* consulted: a headless test that delivers button 3 to a
       [~button:1] gesture is testing its own handler, not GTK's filtering, and pretending
       otherwise would make the action's behaviour depend on a detail no headless model
       has. The same reason [Set_text] does not consult [text].

       The response is printed, on [Key_press]'s rule and for its reason: the claim
       decision reaches GTK synchronously and headless there is no GTK, so the golden is
       the only place it can land -- without it, [Claim_and eff] and [Continue_and eff]
       would be indistinguishable. *)
    | Click_at (id, event) ->
      let n = node_exn node id in
      (match (Attrs.find n.attrs On_click :> Attr.Private.t option) with
       | Some (On_click { handler; _ }) ->
         let response = handler event in
         printf !"on_click %s -> %{sexp: Click_response.t}\n" id response;
         Option.value (Click_response.effect response) ~default:Ui_effect.Ignore
       | _ -> failwithf "Bonsai_gtk_test: node %s has no on_click handler" id ())
    (* Two actions rather than one for a focus *move*, because the two handlers are
       independent: the widget focus leaves and the widget focus enters are different
       nodes, and a test that cares about the order says so by ordering the actions. *)
    | Focus_enter id ->
      let n = node_exn node id in
      (match (Attrs.find n.attrs On_focus_enter :> Attr.Private.t option) with
       | Some (On_focus_enter { handler; _ }) -> handler ()
       | _ -> failwithf "Bonsai_gtk_test: node %s has no on_focus_enter handler" id ())
    | Focus_leave id ->
      let n = node_exn node id in
      (match (Attrs.find n.attrs On_focus_leave :> Attr.Private.t option) with
       | Some (On_focus_leave { handler; _ }) -> handler ()
       | _ -> failwithf "Bonsai_gtk_test: node %s has no on_focus_leave handler" id ())
    (* The bit is an argument rather than derived, on [Set_expanded]'s rule: "the focus is
       now inside / no longer inside" is what the real controller's [notify] reports, and
       there is no node prop to negate. *)
    | Focus_contains (id, contains) ->
      let n = node_exn node id in
      (match (Attrs.find n.attrs On_contains_focus_changed :> Attr.Private.t option) with
       | Some (On_contains_focus_changed h) -> h contains
       | _ ->
         failwithf
           "Bonsai_gtk_test: node %s has no on_contains_focus_changed handler"
           id
           ())
    (* The answer is printed rather than returned, because it is the half of a key press
       that has nowhere else to go: [incoming] hands back an effect, and
       [Handled]/[Propagate] is not one -- it is a value that reaches GTK synchronously,
       and headless there is no GTK. Printing it is what puts the decision in the golden;
       without it a test could only see the effect, and [Handled] and [Propagate] would be
       indistinguishable whenever the handler schedules the same effect for both. *)
    | Key_press (id, event) ->
      let n = node_exn node id in
      (match (Attrs.find n.attrs On_key_pressed :> Attr.Private.t option) with
       | Some (On_key_pressed { handler; _ }) ->
         let response = handler event in
         printf !"key_pressed %s -> %{sexp: Key_response.t}\n" id response;
         Option.value (Key_response.effect response) ~default:Ui_effect.Ignore
       | _ -> failwithf "Bonsai_gtk_test: node %s has no on_key_pressed handler" id ())
    | Key_release (id, event) ->
      let n = node_exn node id in
      (match (Attrs.find n.attrs On_key_released :> Attr.Private.t option) with
       | Some (On_key_released { handler; _ }) -> handler event
       | _ -> failwithf "Bonsai_gtk_test: node %s has no on_key_released handler" id ())
    (* The node's own row list is not consulted, and neither is its [~selected]: the
       action means "the user activated the row with this key", which is what the real
       widget reports whatever the model was rendering. The same reason [Set_text] does
       not consult [text]. The {i kind} is consulted, which is a different thing -- it is
       not a fact about the user's action but about which action this is. *)
    | Activate_row (id, key) ->
      let n = node_exn node id in
      of_kind_exn n id ~expected:"ListBox" ~is_expected:(function
        | Kind.List_box _ -> true
        | _ -> false);
      (match (Attrs.find n.attrs On_row_activated :> Attr.Private.t option) with
       | Some (On_row_activated h) -> h key
       | _ -> failwithf "Bonsai_gtk_test: node %s has no on_row_activated handler" id ())
    (* The flow box's own, and deliberately not [Activate_row] reused: [row-activated] and
       [child-activated] are different signals on different widgets, so one action for
       both would have to accept either attr and would read wrong in whichever test used
       the other name. *)
    | Activate_child (id, key) ->
      let n = node_exn node id in
      of_kind_exn n id ~expected:"FlowBox" ~is_expected:(function
        | Kind.Flow_box _ -> true
        | _ -> false);
      (match (Attrs.find n.attrs On_child_activated :> Attr.Private.t option) with
       | Some (On_child_activated h) -> h key
       | _ -> failwithf "Bonsai_gtk_test: node %s has no on_child_activated handler" id ())
    (* Likewise: the keys given are the whole selection the user has made, not a delta
       against the node's [~selected]. A real [selected-rows-changed] reports the whole
       selection too, which is what makes the two the same shape.

       Shared between the two containers, unlike the pair above, because it is the same
       question of both -- "the selection is now these keys" -- and the two signals differ
       only in the noun. Which attr it looks for is decided by the kind it found, so the
       action needs no kind check of its own: a node that is neither reports that it has
       no selection handler, naming both spellings. *)
    | Set_selection (id, keys) ->
      let n = node_exn node id in
      let name, attr =
        match n.kind with
        | Kind.Flow_box _ ->
          "on_selected_children_changed", Attr.Name.On_selected_children_changed
        | _ -> "on_selected_rows_changed", Attr.Name.On_selected_rows_changed
      in
      (match (Attrs.find n.attrs attr :> Attr.Private.t option) with
       | Some (On_selected_rows_changed h) -> h keys
       | Some (On_selected_children_changed h) -> h keys
       | _ -> failwithf "Bonsai_gtk_test: node %s has no %s handler" id name ())
    (* The notebook's own, and neither of the two above reused: a page change is singular
       where a selection is plural, and it is the {i user} switching tabs rather than
       activating anything. Like every other action the node's own [~current_page] is not
       consulted -- "the user is now on this page" is what the real widget reports
       whatever the model was rendering -- and, unlike [Set_selection] directly above, the
       {i kind} is checked, as the two activate actions do, so that the failure names it. *)
    | Set_page (id, key) ->
      let n = node_exn node id in
      of_kind_exn n id ~expected:"Notebook" ~is_expected:(function
        | Kind.Notebook _ -> true
        | _ -> false);
      (match (Attrs.find n.attrs On_page_changed :> Attr.Private.t option) with
       | Some (On_page_changed h) -> h key
       | _ -> failwithf "Bonsai_gtk_test: node %s has no on_page_changed handler" id ())
    (* The drop-down's own, and the only one of these actions that carries an index rather
       than a key -- because a drop-down's items are props rather than children, so a
       position is the only name an item has. Like every other action the node's own
       [~selected] is not consulted: "the user is now showing this item" is what the real
       widget reports whatever the model was rendering, and a test that wants to show a
       model {i declining} the choice needs exactly that.

       The index is {i not} checked against the node's [~items] either, and that is the
       one place this action is deliberately weaker than the live widget. A real
       [notify::selected] can only carry a position GTK holds, so it is always in range or
       [-1]; headless there is no model to ask, and inventing a range check here would
       duplicate [Node.drop_down]'s -- which has already run on the node the handle is
       looking at, so the props the test can see are in range by construction. What a test
       {i can} do with an out-of-range index is discover what its own handler does with
       one, which is its business. *)
    | Set_selected (id, index) ->
      let n = node_exn node id in
      of_kind_exn n id ~expected:"DropDown" ~is_expected:(function
        | Kind.Drop_down _ -> true
        | _ -> false);
      (match (Attrs.find n.attrs On_selected_changed :> Attr.Private.t option) with
       | Some (On_selected_changed h) -> h index
       | _ ->
         failwithf "Bonsai_gtk_test: node %s has no on_selected_changed handler" id ())
    (* The calendar's own. Like every other action the node's own [~date] is not
       consulted: "the user is now on this day" is what the real widget reports whatever
       the model was rendering, which is exactly what a test showing a model that
       {i declines} a day needs.

       A [Date.t] rather than three integers, because that is what the attr carries and
       because GTK's zero-based month has no business anywhere near a test. And the
       {i kind} is checked, as the two activate actions and [Set_page] do, so that a
       [Select_day] aimed at something else names what it found rather than reporting a
       missing handler. *)
    | Select_day (id, date) ->
      let n = node_exn node id in
      of_kind_exn n id ~expected:"Calendar" ~is_expected:(function
        | Kind.Calendar _ -> true
        | _ -> false);
      (match (Attrs.find n.attrs On_day_selected :> Attr.Private.t option) with
       | Some (On_day_selected h) -> h date
       | _ -> failwithf "Bonsai_gtk_test: node %s has no on_day_selected handler" id ())
    (* The editable label's, and the one action in this list whose live counterpart is not
       a signal at all: [editing] is a read-only GTK property observed through
       [notify::editing]. Headless that distinction does not exist, which is the point --
       what a test can see is that the user entered or left editing mode and what the
       model did about it.

       Not [Toggle] reused, and the node's own [~editing] is deliberately not consulted:
       leaving editing mode is not the inverse of entering it (a user commits with Enter,
       abandons with Escape, and loses focus by clicking elsewhere), so a test says which
       of the two happened rather than asking the node to guess. The {i text} of the edit
       arrives through [Set_text], because live it arrives through [Attr.on_changed]. *)
    | Set_editing (id, editing) ->
      let n = node_exn node id in
      of_kind_exn n id ~expected:"EditableLabel" ~is_expected:(function
        | Kind.Editable_label _ -> true
        | _ -> false);
      (match (Attrs.find n.attrs On_editing_changed :> Attr.Private.t option) with
       | Some (On_editing_changed h) -> h editing
       | _ -> failwithf "Bonsai_gtk_test: node %s has no on_editing_changed handler" id ())
  ;;
end

let result_spec : (Node.t, Action.t) Bonsai_test.Result_spec.t = (module Result_spec)

(* [Bonsai_test.Handle] with the two non-checking entry points replaced by checking ones.

   The checks this library adds live in [Result_spec.view], which only the {i printing}
   entry points call -- [show], [show_into_string], [show_diff], [store_view]. So a test
   that advances with [recompute_view] and prints once at the end validated exactly one of
   its trees, and every tree that existed only between two prints went unchecked. That is
   not a hazard a caller might one day hit: it is the idiom this library's own mli
   recommends for seeing one action's effect before the next, and [test/handle/] takes
   that advice twenty times.

   [Bonsai_test.Handle.recompute_view] takes a [?simulate_diff_patch] and hands it the
   computed result, which is exactly the hook needed: run the view for its exceptions and
   throw the string away, then pass the result on to whatever the caller asked for.

   Monomorphic in [Node.t], unlike the function it shadows. It has to be: the check is
   [Result_spec.view], which is a function of a [Node.t], and a polymorphic
   ['result -> unit] has nothing to apply it to. Every handle this library hands out is a
   [(Node.t, Action.t) Handle.t] anyway ([create] below is the only constructor an
   application should use); a caller who really wants a handle over some other result type
   still has [Bonsai_test.Handle] itself, since the [t] below is that module's type and
   not a new one. *)
module Handle = struct
  include Bonsai_test.Handle

  let with_check ~f (simulate_diff_patch : (Node.t -> unit) option) node =
    (* The exception is the product, and [f] is [Result_spec.check] rather than
       [Result_spec.view]: the checks are what these entry points were missing, and
       rendering the tree to a string to throw it away was the rest of what [view] does. *)
    f node;
    Option.iter simulate_diff_patch ~f:(fun g -> g node)
  ;;

  let recompute_view ?simulate_diff_patch (handle : (Node.t, _) t) =
    Bonsai_test.Handle.recompute_view
      handle
      ~simulate_diff_patch:(with_check ~f:Result_spec.check simulate_diff_patch)
  ;;

  let recompute_view_until_stable
    ?max_computes
    ?simulate_diff_patch
    (handle : (Node.t, _) t)
    =
    Bonsai_test.Handle.recompute_view_until_stable
      ?max_computes
      handle
      ~simulate_diff_patch:(with_check ~f:Result_spec.check simulate_diff_patch)
  ;;

  (* The third one, and the surprise: [store_view] {i does} build a view -- it is [show]
     without the printing -- but it builds it lazily, so the [Result_spec]'s [view] is not
     called until a later [show_diff] asks for the text, and an illegal tree stored and
     never diffed was never checked. Measured; it is why the golden in
     [test/handle/test_gallery.ml] lists it beside the other two.

     No [?simulate_diff_patch] to hang the check on here, so it goes after: [store_view]
     has already computed the frame, and [last_result] is the very tree it stored. Same
     tree, same frame, no second stabilization. *)
  let store_view (handle : (Node.t, _) t) =
    Bonsai_test.Handle.store_view handle;
    Result_spec.check (Bonsai_test.Handle.last_result handle)
  ;;
end

let create ~(here : [%call_pos]) ?start_time ?optimize ?(root_kind = `Window) app =
  (* Set before the handle exists, so the first frame is checked against it like every
     later one. See {!current_root_kind}. *)
  current_root_kind := root_kind;
  Handle.create ~here ?start_time ?optimize result_spec app
;;
