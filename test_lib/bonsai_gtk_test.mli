open! Core
open Bonsai_gtk_vtree

module Action : sig
  type t = Click of string (** test_id of a node carrying [Attr.on_clicked] *)
  [@@deriving sexp_of]
end

val result_spec : (Node.t, Action.t) Bonsai_test.Result_spec.t

module Handle = Bonsai_test.Handle

(** Builds a headless test handle for [app]: no GTK, no display, just the [Node.t] sexp
    tree and [Action.t] actions dispatched against it by [test_id].

    [Handle.do_actions] looks up every action in the call against *one* view snapshot —
    the tree [Handle.show]/[Handle.recompute_view] last computed — not the tree as it
    would be after each prior action in the same call takes effect. So
    [do_actions handle [ Click "inc"; Click "inc" ]] finds "inc" against the same node
    both times; if the second click is meant to see whatever the first click's effect
    changed (a different label becoming clickable, an attribute the click flips), call
    [Handle.recompute_view handle] between the two actions to force a fresh snapshot
    first. See [test/test_handle.ml] for the pattern: two single-click [do_actions] calls
    separated by [recompute_view], rather than one call with both clicks. *)
val create
  :  here:[%call_pos]
  -> ?start_time:Time_ns.t
  -> ?optimize:bool
  -> (local_ Bonsai.graph -> Node.t Bonsai.t)
  -> (Node.t, Action.t) Handle.t
