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
    | Search_changed of string * string
    (** test_id of a [search_entry] carrying [Attr.on_search_changed], and the text the
        user typed. Fires that handler with exactly that string.

        Distinct from [Set_text] on the same node, which fires [Attr.on_changed]: the two
        are different signals on the real widget — [changed] is immediate,
        [search-changed] arrives [search_delay] ms after typing stops — and an app that
        attaches both wants to test them apart. Neither consults the node's own [text]
        prop, for the reason [Set_text] documents. *)
    | Set_expanded of string * bool
    (** test_id of an [expander] carrying [Attr.on_expanded_changed], and the state the
        user dragged it to. Fires that handler with exactly that bool; the node's own
        [expanded] prop is not consulted, so a test can show a model that declines to
        open. *)
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

    {b Event attrs and container-placement attrs are validated here; the rest of the
      structural checking still is not.}
    This library depends on [bonsai_gtk.vtree] alone -- that is what keeps it, and the
    view functions written against it, free of ocgtk -- so it cannot see the widget
    implementations. It can, however, see the two pure tables the runtime consults:

    - [Bonsai_gtk_vtree.Events], so an event attr the kind cannot emit ([Attr.on_toggled]
      on a [Node.label], any event attr on a [Node.native]) raises [Invalid_argument] here
      as well, with the message and the node path the patcher would have produced — the
      widget is named by [Kind.name] on both sides, so the two messages are identical by
      construction. When the handle accepts an event attr, the runtime will connect
      {i that attr}: [test/live/live_events.ml] checks the table against every widget
      impl's own signal list, and [Signals.require_slots] raises at mount if the two ever
      drift. (That live test runs only under [BONSAI_GTK_LIVE_TESTS=1]; the mount
      assertion is unconditional.)
    - [Bonsai_gtk_vtree.Placement], so a container-placement attr on a child whose parent
      does not read it ([Attr.grid_cell] on a box child, [Attr.page_title] anywhere but a
      stack page, [Attr.measure_overlay] outside an overlay) raises here too. Both sides
      call [Placement.rejection] for the string, so these messages are identical outright
      rather than by convention. This one matters more than it looks: a misplaced
      placement attr is applied by nobody and read by nobody, so without this check a
      headless suite is the {i only} place it could ever have been caught, and it passed.

    Both are checked on the first [Handle.show]/[Handle.recompute_view], and on every
    later one.

    What is still only checked at mount is the structural half that needs the widget
    implementations or the live tree: a [Node.grid] child with no [Attr.grid_cell], a
    [Node.stack] page with no [~key] or a [~visible_child] naming no page, two stacks
    under one [~name], a [stack_switcher] naming no stack, duplicate keys among siblings,
    a [Node.window] anywhere but the root. None of those stops a handle here, so a suite
    that is entirely headless can still certify a tree that raises the moment it is shown.
    The escape from that is a live test, or running the app.

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
