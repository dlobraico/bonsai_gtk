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
  ;;
end

let result_spec : (Node.t, Action.t) Bonsai_test.Result_spec.t = (module Result_spec)

module Handle = Bonsai_test.Handle

let create ~(here : [%call_pos]) ?start_time ?optimize app =
  Handle.create ~here ?start_time ?optimize result_spec app
;;
