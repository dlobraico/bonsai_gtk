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
    | Move_cursor of string * int
    | Open_popover of string
    | Close_popover of string
    | Activate_action of string * string
    | Fire_shortcut of string * Trigger.t
    | Close_request of Key.t
  [@@deriving sexp_of]
end

(* The target and its ancestor chain (outermost first), for the actions that resolve names
   the way GTK does -- from the node upward. Same duplicate-id rejection as
   [find_by_test_id], through it. *)
let node_with_ancestors_exn (root : Node.t) id =
  (* [find_by_test_id] settles existence and uniqueness; the walk below re-finds the path
     to collect the chain. *)
  (match Node.find_by_test_id root id with
   | Some _ -> ()
   | None -> failwithf "Bonsai_gtk_test: no node with test_id %s" id ());
  let result = ref None in
  let rec go ancestors (node : Node.t) =
    if Option.equal String.equal (Attrs.test_id node.attrs) (Some id)
    then result := Some (node, List.rev ancestors)
    else
      Children.iteri node.children ~path:"" ~f:(fun _ child ->
        go (node :: ancestors) child)
  in
  go [] root;
  Option.value_exn !result
;;

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
   (* [Some Windows] implies "child of the root", exactly as it does at the runtime's copy
      of this check: a [Windows] below the root is itself rejected two arms down. The key
      requirement rides the same arm -- one [match] cannot say "legal here" and then
      re-inspect the pair below the way the runtime's two blocks do. *)
   | Window _, Some Kind.Windows ->
     if Option.is_none node.key
     then
       invalid_argf
         "%s: a Node.windows child carries no ~key (the window's identity: what \
          ~transient_for names and what keeps the GtkWindow across reorders)"
         path
         ()
   | Window _, Some _ ->
     invalid_argf
       "%s: a Node.window may only be the root node or a child of the root Node.windows, \
        not a child of any other node"
       path
       ()
   | Windows, Some _ ->
     invalid_argf
       "%s: a Node.windows may only be the root node (the one virtual root holding every \
        toplevel), not a child of another node"
       path
       ()
   (* The popover's one legal position, [Patcher_checks.check_placement]'s strings copied
      on the window rule's arrangement. *)
   | Popover _, Some (Kind.Menu_button _) -> ()
   | Kind.Popover _, Some k ->
     invalid_argf
       "%s: a Node.popover may only be a Node.menu_button's ~popover slot, not a child \
        of %s"
       path
       (Kind.name k)
       ()
   | Popover _, None ->
     invalid_argf
       "%s: a Node.popover may only be a Node.menu_button's ~popover slot, not the root"
       path
       ()
   (* The converse, [Patcher_checks.check_placement]'s string: everything under a menu
      button is its ~popover slot, and a non-popover there hits an unchecked downcast
      live. The constructor already rejects it; this is the backstop for a record-update
      tree, so the handle cannot certify what the runtime would crash on. *)
   | k, Some (Kind.Menu_button _) ->
     invalid_argf
       "%s: Node.menu_button's ~popover slot must hold a Node.popover, not a %s"
       path
       (Kind.name k)
       ()
   (* The windows root's converse, [Patcher_checks.check_placement]'s string: the
      constructor rejects it, and this is the record-update backstop, so the handle cannot
      certify what the runtime would crash on (an unchecked downcast to [W.Window.t] at
      teardown). The keyless-window half of that backstop rides the window arm above. *)
   | k, Some Kind.Windows ->
     (match k with
      | Window _ -> ()
      | k ->
        invalid_argf
          "%s: Node.windows children must all be Node.window, not a %s"
          path
          (Kind.name k)
          ())
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
  (* Beside the phase doctrine, as at runtime: one trigger naming two actions on one node
     is an order accident waiting to happen, refused with the runtime's string. *)
  Option.iter (Events.shortcut_conflict_rejection ~path node.attrs) ~f:invalid_arg;
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

(* Which nodes' [Attr.autofocus true] had already fired as of the last checked frame, by
   path, for the fire-once half of that attr's contract: a grab fires at mount or on a
   false-to-true flip, and the runtime rejects two firing in one frame per toplevel. The
   handle tracks the same edges over the same attrs -- a path is "firing" exactly when it
   carries [true] and did not in the previous frame (the first frame is a mount, so
   everything [true] in it fires) -- and raises the same [Events.autofocus_rejection]
   string, so a headless suite cannot certify the tree the runtime refuses.

   By {i path} rather than by widget, and the approximation shows in both directions: a
   keyed child that moves keeps its widget (no re-fire live) but changes its path, so the
   handle counts it as firing again; a kind change at the same path with a steady [true]
   is a remount that re-fires live but is no edge to the path, so it goes uncounted here.
   No tree in this repository does either; if one ever does, this is the comment to
   revisit. Per toplevel is per {i window}: under a [Node.windows] root each keyed child
   is its own toplevel (the runtime groups grabs by [Widget.get_root], and a windows
   child's root is itself), so the grouping key is the child's path prefix ["root/i"];
   under any other root the whole tree is one toplevel, as it was before Task 8.

   A global beside [current_root_kind], for its reasons and with its caveat: the state is
   the most recently created handle's, and interleaving two handles would confuse them.
   Nothing in this repository interleaves two handles at all. *)
let autofocus_fired = ref String.Set.empty

let autofocus_paths (node : Node.t) =
  let acc = ref [] in
  let rec go ~path (node : Node.t) =
    if Events.autofocus_requested node.attrs then acc := path :: !acc;
    Children.iteri node.children ~path ~f:(fun path child -> go ~path child)
  in
  go ~path:"root" node;
  List.rev !acc
;;

let check_autofocus (node : Node.t) =
  let requested = autofocus_paths node in
  let toplevel_of path =
    match node.kind with
    | Windows ->
      (match String.split path ~on:'/' with
       | root :: child :: _ -> root ^ "/" ^ child
       | _ -> path)
    | _ -> "root"
  in
  let fresh =
    List.filter requested ~f:(fun path -> not (Set.mem !autofocus_fired path))
  in
  (* Walk order, as the runtime's claim queue is: the first pair that shares a toplevel is
     the pair the fixup pass would name. *)
  List.iteri fresh ~f:(fun i second ->
    match
      List.find (List.take fresh i) ~f:(fun first ->
        String.equal (toplevel_of first) (toplevel_of second))
    with
    | Some first -> invalid_arg (Events.autofocus_rejection ~first ~second)
    | None -> ());
  autofocus_fired := String.Set.of_list requested
;;

(* [Driver.check_root]'s match, and its messages, copied because the runtime lives in the
   package this library cannot link. The goldens in [test/handle/test_handle.ml] are what
   keeps the two spellings the same. *)
let check_root (node : Node.t) =
  match !current_root_kind, node.kind with
  | `Window, (Window _ | Windows) -> ()
  | `Window, k ->
    invalid_argf
      "Bonsai_gtk: the root node must be a Node.window or a Node.windows, got %s. A tree \
       started this way shows its own root, and a GtkWindow is the only thing GTK can \
       show on its own (Node.windows is the virtual root holding several of them). Use \
       Bonsai_gtk.Expert.embed for a tree parented into a container you already own."
      (Kind.name k)
      ()
  | `Not_window, (Window _ | Windows) ->
    invalid_arg
      "Bonsai_gtk.embed: the root node is a Node.window (or a Node.windows), but an \
       embedded tree is parented into a container the caller owns and a GtkWindow is a \
       toplevel that cannot be parented. Use Bonsai_gtk.start for a tree that owns its \
       windows, or make the root a container."
  | `Not_window, _ -> ()
;;

(* The [~transient_for] resolutions, from the same tree the runtime's fixup resolves from
   its registry: under a [Node.windows] root the registry holds exactly the keyed
   children, so the two walks reject the same trees with the same [Events] strings. The
   self-reference is the record-update backstop ([Node.window] rejects the pair at the
   constructor). *)
let check_window_refs (root : Node.t) =
  let existing =
    match root.kind, root.children with
    | Windows, Children.List cs -> List.filter_map cs ~f:(fun (c : Node.t) -> c.key)
    | _ -> []
  in
  let sorted = List.sort existing ~compare:Key.compare in
  let rec go ~path (n : Node.t) =
    (match n.kind with
     | Window { transient_for = Some key; _ } ->
       if Option.exists n.key ~f:(Key.equal key)
       then invalid_arg (Events.transient_for_self_rejection ~path ~key)
       else if not (List.mem existing key ~equal:Key.equal)
       then invalid_arg (Events.transient_for_rejection ~path ~key ~existing:sorted)
     | _ -> ());
    Children.iteri n.children ~path ~f:(fun path child -> go ~path child)
  in
  go ~path:"root" root
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
       and there. The autofocus check is last, as its runtime twin is -- the patcher
       raises it from the fixup queue, after the whole walk. *)
    check_root node;
    (* Second, as at runtime: [Patcher]'s mount/patch wrappers run this before their walk,
       so a tree with several mistakes reports the same one here and there. Same function,
       same string. *)
    Action_resolution.check ~path:"root" node;
    require_supported ~path:"root" ~parent:None node;
    (* After the walk and before autofocus, as at runtime: the transient resolutions ride
       the generic fixup queue, which [run_fixups] drains before [apply_autofocus]. *)
    check_window_refs node;
    check_autofocus node
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
    (* The text view's caret, and like [Set_position] the offset is the action's to say:
       "the user put the caret here" is what a real click or arrow produces, and there is
       no headless buffer to clamp it -- an offset past the text's end reaches the handler
       as written, which live GTK would clamp. The {i kind} is checked so a [Move_cursor]
       aimed elsewhere names what it found. *)
    | Move_cursor (id, offset) ->
      let n = node_exn node id in
      of_kind_exn n id ~expected:"TextView" ~is_expected:(function
        | Kind.Text_view _ -> true
        | _ -> false);
      (match (Attrs.find n.attrs On_cursor_moved :> Attr.Private.t option) with
       | Some (On_cursor_moved h) -> h offset
       | _ -> failwithf "Bonsai_gtk_test: node %s has no on_cursor_moved handler" id ())
    (* The user opened the popover -- and, honestly, nothing fires: live, opening emits no
       signal this library exposes (see [Node.popover]'s ~open_ doc), so the headless
       action mirrors that exactly. It kind-checks the target and hands back [Ignore], so
       a script reads as the user's session and a mis-aimed id still fails loudly. The
       diff a test takes after it is the point: the model heard nothing, so the [open_]
       prop stands wherever the model holds it. *)
    | Open_popover id ->
      let n = node_exn node id in
      of_kind_exn n id ~expected:"Popover" ~is_expected:(function
        | Kind.Popover _ -> true
        | _ -> false);
      Ui_effect.Ignore
    (* The user dismissed it -- click-away or Escape, GTK's autohide -- which live emits
       [closed]; fires [Attr.on_closed]'s effect. A popover with no handler fails like
       every other action, which is exactly the tree whose declined-dismissal reopen the
       runtime documents. *)
    | Close_popover id ->
      let n = node_exn node id in
      of_kind_exn n id ~expected:"Popover" ~is_expected:(function
        | Kind.Popover _ -> true
        | _ -> false);
      (match (Attrs.find n.attrs On_closed :> Attr.Private.t option) with
       | Some (On_closed h) -> h ()
       | _ -> failwithf "Bonsai_gtk_test: node %s has no on_closed handler" id ())
    (* The user activated an action -- through a menu item, or (Task 7) a shortcut. The id
       names the node {i carrying the [Attr.actions]}, and the reference is "scope.name"
       (or "scope.name::target" for a radio, whose handler receives the target). The
       activation reaches the handler and nothing else: a [Toggle]'s state moves only when
       the model's next render moves it, which is the controlled story the runtime tells
       and the diff a test takes shows. *)
    | Activate_action (id, reference) ->
      let n = node_exn node id in
      let reference, target =
        match String.substr_index reference ~pattern:"::" with
        | None -> reference, None
        | Some i -> String.prefix reference i, Some (String.drop_prefix reference (i + 2))
      in
      let scope, name =
        match String.index reference '.' with
        | None ->
          failwithf
            "Bonsai_gtk_test: action reference %S has no scope (expected \"scope.name\")"
            reference
            ()
        | Some i -> String.prefix reference i, String.drop_prefix reference (i + 1)
      in
      (match (Attrs.find n.attrs Actions :> Attr.Private.t option) with
       | Some (Actions { scope = s; specs }) when String.equal s scope ->
         (match
            List.find specs ~f:(fun (spec : Action_spec.t) -> String.equal spec.name name)
          with
          | None ->
            failwithf
              "Bonsai_gtk_test: node %s's Attr.actions scope %S has no action %S"
              id
              scope
              name
              ()
          | Some spec ->
            (match spec.kind, target with
             | Simple eff, None -> eff
             | Toggle { on_activate; _ }, None -> on_activate
             | Radio { on_activate; _ }, Some target -> on_activate target
             | Radio _, None ->
               failwithf
                 "Bonsai_gtk_test: %S is a radio action; activate it with \
                  \"%s.%s::target\""
                 name
                 scope
                 name
                 ()
             | (Simple _ | Toggle _), Some _ ->
               failwithf
                 "Bonsai_gtk_test: %S takes no ::target (it is not a radio)"
                 name
                 ()))
       | Some (Actions { scope = s; _ }) ->
         failwithf
           "Bonsai_gtk_test: node %s's Attr.actions scope is %S, not %S"
           id
           s
           scope
           ()
       | _ -> failwithf "Bonsai_gtk_test: node %s carries no Attr.actions" id ())
    (* The user pressed the chord. Pure table lookups, per the design: the trigger is
       matched against the node's own shortcut attrs, and the named action is resolved
       against the node and its ancestors -- the union GTK's muxer implements (measured,
       Task 6). The mli repeats M2's honesty paragraph: this models no routing at all --
       who sees the chord first is [?phase]'s business and [live_input.ml]'s to prove. *)
    | Fire_shortcut (id, trigger) ->
      let n, ancestors = node_with_ancestors_exn node id in
      let action_ref =
        match (Attrs.find n.attrs Shortcut :> Attr.Private.t option) with
        | Some (Shortcut shortcuts) ->
          (* First match in (trigger, action) order -- the same sorted order the live
             controller installs, so the two resolve identically. (With the same-trigger
             conflict rejected at the walk, the sort is belt-and-braces here.) *)
          (match
             List.sort shortcuts ~compare:(fun (a : Attr.shortcut) b ->
               [%compare: Trigger.t * string] (a.trigger, a.action) (b.trigger, b.action))
             |> List.find ~f:(fun (s : Attr.shortcut) -> Trigger.equal s.trigger trigger)
           with
           | Some s -> s.action
           | None ->
             failwithf
               !"Bonsai_gtk_test: node %s has no shortcut for %{sexp: Trigger.t}"
               id
               trigger
               ())
        | Some _ | None ->
          failwithf "Bonsai_gtk_test: node %s carries no Attr.shortcut" id ()
      in
      let scope, name =
        match String.index action_ref '.' with
        | None ->
          failwithf "Bonsai_gtk_test: shortcut action %S has no scope" action_ref ()
        | Some i -> String.prefix action_ref i, String.drop_prefix action_ref (i + 1)
      in
      let spec =
        List.find_map (n :: List.rev ancestors) ~f:(fun holder ->
          match (Attrs.find holder.attrs Actions :> Attr.Private.t option) with
          | Some (Actions { scope = s; specs }) when String.equal s scope ->
            List.find specs ~f:(fun (spec : Action_spec.t) -> String.equal spec.name name)
          | Some _ | None -> None)
      in
      (match spec with
       | None ->
         (* Unreachable through [create]: the resolution walk certified every shortcut
            reference before any action could be dispatched. Kept loud for a tree built
            behind its back. *)
         failwithf
           "Bonsai_gtk_test: shortcut action %S resolves to nothing (the walk should \
            have refused this tree)"
           action_ref
           ()
       | Some { kind = Simple eff; _ } -> eff
       | Some { kind = Toggle { on_activate; _ }; _ } -> on_activate
       | Some { kind = Radio _; name; _ } ->
         (* Unreachable through [create]: the walk refuses a shortcut resolving to a
            radio. Kept loud, with the honest wording -- targeted shortcuts are feasible
            ([Shortcut.set_arguments] is bound) and deliberately unshipped. *)
         failwithf
           "Bonsai_gtk_test: %S is a radio action; targeted shortcuts are not shipped in \
            M3"
           name
           ())
    (* The user asked the window to close (the X button, Alt+F4) -- which live is a
       [close-request] the runtime always vetoes; fires [Attr.on_close_request]'s effect.
       By {i key} rather than test_id, because the key is the window's identity in the
       [Node.windows] list (a [Node.window] root joins in when it carries one). A window
       with no handler fails like every other action: live, the runtime swallows the
       request and reports once, so the model heard nothing and the test asked to exercise
       a handler that is not there. *)
    | Close_request key ->
      let windows =
        match node.kind, node.children with
        | Windows, Children.List cs ->
          List.filter_map cs ~f:(fun (c : Node.t) -> Option.map c.key ~f:(fun k -> k, c))
        | Window _, _ ->
          (match node.key with
           | Some k -> [ k, node ]
           | None -> [])
        | _ -> []
      in
      (match List.Assoc.find windows key ~equal:Key.equal with
       | None ->
         failwithf
           "Bonsai_gtk_test: no window is keyed %S (keys that exist: %s)"
           (key : Key.t)
           (match List.map windows ~f:fst with
            | [] -> "none"
            | keys -> String.concat ~sep:", " (List.map keys ~f:(sprintf "%S")))
           ()
       | Some (w : Node.t) ->
         (match (Attrs.find w.attrs On_close_request :> Attr.Private.t option) with
          | Some (On_close_request h) -> h ()
          | _ ->
            failwithf
              "Bonsai_gtk_test: window %S has no on_close_request handler (live, the \
               runtime swallows the request and reports once -- the window stays open)"
              (key : Key.t)
              ()))
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
     later one. See {!current_root_kind}; the autofocus memo starts empty for the same
     reason -- the new handle's first frame is a mount, and everything [true] in it fires. *)
  current_root_kind := root_kind;
  autofocus_fired := String.Set.empty;
  Handle.create ~here ?start_time ?optimize result_spec app
;;
