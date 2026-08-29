open! Core
open Bonsai_gtk_vtree

module Action : sig
  type t = Click of string (** test_id of a node carrying [Attr.on_clicked] *)
  [@@deriving sexp_of]
end

val result_spec : (Node.t, Action.t) Bonsai_test.Result_spec.t

module Handle = Bonsai_test.Handle

val create
  :  here:[%call_pos]
  -> ?start_time:Time_ns.t
  -> ?optimize:bool
  -> (local_ Bonsai.graph -> Node.t Bonsai.t)
  -> (Node.t, Action.t) Handle.t
