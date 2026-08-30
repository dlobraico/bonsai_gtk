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
    | Click_at of string * Click_event.t
    | Focus_enter of string
    | Focus_leave of string
    | Key_press of string * Key_event.t
    | Key_release of string * Key_event.t
    | Activate_row of string * Key.t
    | Set_selection of string * Key.t list
  [@@deriving sexp_of]
end

let node_exn (node : Node.t) id =
  match Node.find_by_test_id node id with
  | Some n -> n
  | None -> failwithf "Bonsai_gtk_test: no node with test_id %s" id ()
;;

(* The value a real toggle would take: whatever the node is *not* showing now. Reading it
   off the node rather than taking it as an argument is what makes the action mean "the
   user clicked this", which is the only thing a test can honestly claim. *)
let current_active (node : Node.t) id =
  match node.kind with
  | Toggle_button { active; _ } | Check_button { active; _ } | Switch { active } -> active
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
let rec require_supported ~path ~parent (node : Node.t) =
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
  (* The third thing the runtime refuses that is decidable from pure vtree data: the two
     key attrs share one [GtkEventControllerKey] and so one propagation phase, and a node
     asking for two is one [Controllers] cannot mount. Same function, same string, so the
     two messages are identical rather than merely similar. Last of the three because it
     is last at mount too -- [Controllers.update] runs after [Signals.require_specs] -- so
     a node carrying more than one mistake reports the same one here and there. *)
  Option.iter (Events.key_phase_rejection ~path node.attrs) ~f:invalid_arg;
  Children.iteri node.children ~path ~f:(fun path child ->
    require_supported ~path ~parent:(Some node.kind) child)
;;

module Result_spec = struct
  type t = Node.t
  type incoming = Action.t

  let view node =
    require_supported ~path:"root" ~parent:None node;
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
    (* Nothing is derived from the node, and in particular the [button] the attr was
       constructed with is *not* consulted: a headless test that delivers button 3 to a
       [~button:1] gesture is testing its own handler, not GTK's filtering, and pretending
       otherwise would make the action's behaviour depend on a detail no headless model
       has. The same reason [Set_text] does not consult [text]. *)
    | Click_at (id, event) ->
      let n = node_exn node id in
      (match (Attrs.find n.attrs On_click :> Attr.Private.t option) with
       | Some (On_click { handler; _ }) -> handler event
       | _ -> failwithf "Bonsai_gtk_test: node %s has no on_click handler" id ())
    (* Two actions rather than one for a focus *move*, because the two handlers are
       independent: the widget focus leaves and the widget focus enters are different
       nodes, and a test that cares about the order says so by ordering the actions. *)
    | Focus_enter id ->
      let n = node_exn node id in
      (match (Attrs.find n.attrs On_focus_enter :> Attr.Private.t option) with
       | Some (On_focus_enter h) -> h ()
       | _ -> failwithf "Bonsai_gtk_test: node %s has no on_focus_enter handler" id ())
    | Focus_leave id ->
      let n = node_exn node id in
      (match (Attrs.find n.attrs On_focus_leave :> Attr.Private.t option) with
       | Some (On_focus_leave h) -> h ()
       | _ -> failwithf "Bonsai_gtk_test: node %s has no on_focus_leave handler" id ())
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
       not consult [text]. *)
    | Activate_row (id, key) ->
      let n = node_exn node id in
      (match (Attrs.find n.attrs On_row_activated :> Attr.Private.t option) with
       | Some (On_row_activated h) -> h key
       | _ -> failwithf "Bonsai_gtk_test: node %s has no on_row_activated handler" id ())
    (* Likewise: the keys given are the whole selection the user has made, not a delta
       against the node's [~selected]. A real [selected-rows-changed] reports the whole
       selection too, which is what makes the two the same shape. *)
    | Set_selection (id, keys) ->
      let n = node_exn node id in
      (match (Attrs.find n.attrs On_selected_rows_changed :> Attr.Private.t option) with
       | Some (On_selected_rows_changed h) -> h keys
       | _ ->
         failwithf
           "Bonsai_gtk_test: node %s has no on_selected_rows_changed handler"
           id
           ())
  ;;
end

let result_spec : (Node.t, Action.t) Bonsai_test.Result_spec.t = (module Result_spec)

module Handle = Bonsai_test.Handle

let create ~(here : [%call_pos]) ?start_time ?optimize app =
  Handle.create ~here ?start_time ?optimize result_spec app
;;
