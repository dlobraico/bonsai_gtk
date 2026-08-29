open! Core
open Bonsai_gtk_vtree

module Action = struct
  type t = Click of string [@@deriving sexp_of]
end

module Result_spec = struct
  type t = Node.t
  type incoming = Action.t

  let view node = Sexp.to_string_hum (Node.sexp_of_t node)

  let incoming node (Action.Click id) =
    match Node.find_by_test_id node id with
    | None -> failwithf "Bonsai_gtk_test: no node with test_id %s" id ()
    | Some n ->
      (match Attrs.find n.attrs On_clicked with
       | Some (On_clicked h) -> h ()
       | _ -> failwithf "Bonsai_gtk_test: node %s has no on_clicked handler" id ())
  ;;
end

let result_spec : (Node.t, Action.t) Bonsai_test.Result_spec.t = (module Result_spec)

module Handle = Bonsai_test.Handle

let create ~(here : [%call_pos]) ?start_time ?optimize app =
  Handle.create ~here ?start_time ?optimize result_spec app
;;
