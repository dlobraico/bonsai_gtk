open! Core
open Bonsai_gtk_vtree

module Action : sig
  type t =
    | Click of string (** test_id of a node carrying [Attr.on_clicked] *)
    | Toggle of string
    (** test_id of a [toggle_button], [check_button] or [switch] carrying
        [Attr.on_toggled]. Fires that handler with the negation of the [active] prop the
        node currently renders — what clicking the real widget would produce. Fails if the
        node is not one of those three, or carries no handler. *)
    | Set_text of string * string
    (** test_id of a node carrying [Attr.on_changed], and the text the user typed. Fires
        that handler with exactly that string — the node's own [text] prop is never
        consulted, because "the user made the text be this" is what a real edit produces
        whatever the widget was showing. What the model does with it (echo, uppercase,
        reject) then shows up as the next render's [text] prop, which is the whole of what
        a controlled text widget guarantees. *)
    | Activate of string
    (** test_id of a node carrying [Attr.on_activate] — the user pressed Enter in it. *)
    | Set_value of string * float
    (** test_id of a [scale] or [spin_button] carrying [Attr.on_value_changed], and the
        value the user moved it to. Fires that handler with exactly that float — the
        node's own [value] prop is never consulted, for the same reason [Set_text] does
        not consult [text]. Nor are [min]/[max]: there is no GTK adjustment headless, so
        an out-of-range value reaches the handler unclamped, which is what lets a test
        show the {i model} clamping it. What the model does then shows up as the next
        render's [value] prop, which is the whole of what a controlled value guarantees. *)
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
