open! Core
open Bonsai_gtk_vtree

module Action = struct
  type t =
    | Click of string
    | Toggle of string
    | Set_text of string * string
    | Activate of string
    | Set_value of string * float
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

module Result_spec = struct
  type t = Node.t
  type incoming = Action.t

  let view node = Sexp.to_string_hum (Node.sexp_of_t node)

  let incoming node (action : Action.t) =
    match action with
    | Click id ->
      let n = node_exn node id in
      (match Attrs.find n.attrs On_clicked with
       | Some (On_clicked h) -> h ()
       | _ -> failwithf "Bonsai_gtk_test: node %s has no on_clicked handler" id ())
    | Toggle id ->
      let n = node_exn node id in
      (match Attrs.find n.attrs On_toggled with
       | Some (On_toggled h) -> h (not (current_active n id))
       | _ -> failwithf "Bonsai_gtk_test: node %s has no on_toggled handler" id ())
    (* Deliberately does not consult the node's [text] prop: the action means "the user
       made the text be this", which is what a real edit produces regardless of what the
       widget was showing before. *)
    | Set_text (id, text) ->
      let n = node_exn node id in
      (match Attrs.find n.attrs On_changed with
       | Some (On_changed h) -> h text
       | _ -> failwithf "Bonsai_gtk_test: node %s has no on_changed handler" id ())
    | Activate id ->
      let n = node_exn node id in
      (match Attrs.find n.attrs On_activate with
       | Some (On_activate h) -> h ()
       | _ -> failwithf "Bonsai_gtk_test: node %s has no on_activate handler" id ())
    (* Like [Set_text], and unlike [Toggle]: the node's own [value] is never consulted,
       because "the user moved it to here" is what a drag or a spin produces whatever the
       widget was showing. Headless, there is also no adjustment to clamp or round it, so
       a value outside the node's [min]/[max] reaches the handler as written -- which is
       the point, since clamping is the model's job to demonstrate. *)
    | Set_value (id, value) ->
      let n = node_exn node id in
      (match Attrs.find n.attrs On_value_changed with
       | Some (On_value_changed h) -> h value
       | _ -> failwithf "Bonsai_gtk_test: node %s has no on_value_changed handler" id ())
  ;;
end

let result_spec : (Node.t, Action.t) Bonsai_test.Result_spec.t = (module Result_spec)

module Handle = Bonsai_test.Handle

let create ~(here : [%call_pos]) ?start_time ?optimize app =
  Handle.create ~here ?start_time ?optimize result_spec app
;;
