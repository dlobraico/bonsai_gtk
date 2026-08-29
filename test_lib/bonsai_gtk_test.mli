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

(** Every action names its node by [Attr.test_id]. Two nodes carrying one id — what
    rendering the same sub-view twice produces — raises [Invalid_argument] naming both
    paths rather than acting on whichever the walk reaches first
    ({!Bonsai_gtk_vtree.Node.find_by_test_id}); an id no node carries raises [Failure]. *)
val result_spec : (Node.t, Action.t) Bonsai_test.Result_spec.t

module Handle = Bonsai_test.Handle

(** Builds a headless test handle for [app]: no GTK, no display, just the [Node.t] sexp
    tree and [Action.t] actions dispatched against it by [test_id].

    {b Structural validation happens at mount, not here.} This library depends on
    [bonsai_gtk.vtree] alone -- that is what keeps it, and the view functions written
    against it, free of ocgtk -- so it cannot see the widget implementations, and it does
    not know which signals a kind can emit. The runtime does, and rejects the rest with
    [Invalid_argument] on the first frame ([Signals.require_specs], spec §11): an
    [Attr.on_clicked] on a [Node.label], an event attr on a [Node.native], a [Node.grid]
    child with no [Attr.grid_cell], a [Node.stack] page with no [~key], two stacks under
    one [~name], duplicate keys among siblings. None of those stops a handle here, and an
    action that names such a node fires its handler and the expect test goes green -- so a
    suite that is entirely headless can certify an application that raises the moment it
    is shown. The escape from that is a live test, or running the app; the vtree-level
    table that would let the handle check the event half of it is on the M2 backlog.

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
