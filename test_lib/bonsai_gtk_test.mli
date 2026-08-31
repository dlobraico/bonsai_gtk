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
    (** test_id of a node carrying [Attr.on_changed] — any of the three entries or a
        [text_view] — and the text the user typed. Fires that handler with exactly that
        string — the node's own [text] prop is never consulted, because "the user made the
        text be this" is what a real edit produces whatever the widget was showing. What
        the model does with it (echo, uppercase, reject) then shows up as the next
        render's [text] prop, which is the whole of what a controlled text widget
        guarantees.

        Nor is anything about the {i widget} consulted, which is worth naming for two
        cases the runtime treats specially: a string longer than an [entry]'s
        [~max_length] reaches the handler in full (live, GTK truncates it), and a string
        containing a NUL reaches it in full (live, the write is refused and reported, and
        the widget keeps what it had). Rows 14 and 15 of the table on {!create}. *)
    | Activate of string
    (** test_id of a node carrying [Attr.on_activate] — the user pressed Enter in it. *)
    | Set_value of string * float
    (** test_id of a [scale] or [spin_button] carrying [Attr.on_value_changed], and the
        value the user moved it to. Fires that handler with exactly that float — the
        node's own [value] prop is never consulted, for the same reason [Set_text] does
        not consult [text]. Nor are [min]/[max]: there is no GTK adjustment headless, so
        an out-of-range value reaches the handler unclamped, which is what lets a test
        show the {i model} clamping it. Nor is a [spin_button]'s [~digits], which GTK
        rounds a real value to: [3.14159] delivered to a [~digits:2] button reaches the
        handler whole here and would arrive as [3.14] live. What the model does then shows
        up as the next render's [value] prop, which is the whole of what a controlled
        value guarantees. *)
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
    | Set_revealed of string * bool
    (** test_id of a [revealer] carrying [Attr.on_revealed], and the state GTK reports at
        the end of its transition. Same shape as [Set_expanded], including that the node's
        own [reveal_child] is not consulted. *)
    | Set_position of string * int
    (** test_id of a [paned] carrying [Attr.on_position_changed], and the divider position
        the user dragged it to, in pixels. The node's own [position] is not consulted --
        which matters here more than elsewhere, since it is the one controlled prop that
        is erased from the sexp at its default ([None], "GTK decides"), so an action is
        the only way a headless test can see this handler at all. *)
    | Set_visible_child of string * Key.t
    (** test_id of a [stack] carrying [Attr.on_visible_child_changed], and the key of the
        page the user switched to -- through a [stack_switcher] or a [stack_sidebar],
        since a stack has no controls of its own. The node's own [visible_child] is not
        consulted, so a model that declines the navigation is testable; the key need not
        name a page, for the reason [Set_page] gives. *)
    | Click_at of string * Click_event.t
    (** test_id of a node carrying [Attr.on_click], and the click to deliver. Fires that
        handler with exactly that event; nothing is derived from the node, and in
        particular the [button] the attr was constructed with is {i not} consulted — a
        headless test that delivers button 3 to a [~button:1] gesture is testing its own
        handler, not GTK's filtering, and pretending otherwise would make the action's
        behaviour depend on a detail no headless model has. Build the event with
        {!Bonsai_gtk_vtree.Click_event}'s record and {!Bonsai_gtk_vtree.Modifiers.none}.

        {b This is the only test there is for a click handler.} The pinned ocgtk binding
        can neither construct a [GdkEvent] nor emit a signal with arguments, so no live
        test can deliver a real click; what a live test proves is that the gesture is
        attached and detached (see [test/live/live_controllers.ml]). The gap between "this
        handler does the right thing" and "GTK routes a real button-2 press to it" is
        real, and is in the backlog. *)
    | Focus_enter of string
    | Focus_leave of string
    (** test_id of a node carrying the matching attr. Two actions rather than one for a
        focus {i move}: the handlers are independent, and a test that cares about the
        order of a leave and an enter says so by ordering the actions.

        Unlike the click pair, focus {i is} genuinely drivable live ([Widget.grab_focus]
        on a presented window), so these have a live counterpart. *)
    | Key_press of string * Key_event.t
    (** test_id of a node carrying [Attr.on_key_pressed], and the key to deliver. Fires
        that handler with exactly that event, prints the
        {!Bonsai_gtk_vtree.Key_response.t} it answered, and performs the effect that
        response carries (if any). The answer is printed because it is the half of a key
        press that cannot be returned: [Handled] is a value GTK reads synchronously, and
        headless there is no GTK — so without the print, [Handled] and [Propagate] would
        be indistinguishable in a golden whenever the handler schedules the same effect
        for both.

        What this {i cannot} model is propagation. A real key press walks GTK's capture
        and bubble chains and stops where a handler says [Handled]; here it is delivered
        to one node, by [test_id], and the [Handled]/[Propagate] half of the answer is not
        acted on — there is no chain to act on it in. So a test can show that a handler
        decided to consume Escape and what that decision did to the model; it cannot show
        that the keystroke then failed to reach a sibling. That half is a live test, or
        the application.

        {b And, as with the click pair, this is the only test there is for a key handler}:
        the pinned ocgtk binding can synthesise no key press
        ([Event_controller_key.forward] only re-routes an event a controller is already
        handling), so what a live test proves is that the controller is attached, named,
        detached, and given the phase the attr asked for — see
        [test/live/live_controllers.ml]. The gap is in the backlog. *)
    | Key_release of string * Key_event.t
    (** test_id of a node carrying [Attr.on_key_released], and the key. Fires that handler
        with exactly that event. Nothing is printed: [key-released] returns [unit] to GTK,
        so there is no answer to record. *)
    | Activate_row of string * Key.t
    (** test_id of a [list_box] carrying [Attr.on_row_activated], and the {!Key.t} of the
        row the user activated. Fires that handler with exactly that key.

        Nothing is derived from the node: neither its row list nor its [~selected] is
        consulted, for the reason [Set_text] does not consult [text]. In particular a key
        no row carries, and a row carrying [Attr.row_activatable false], both reach the
        handler here — the real widget would emit neither, but modelling that would make
        the action's behaviour depend on a detail and would hide the more useful failure,
        which is a model that mishandles a key it did not expect.

        Unlike the click and key actions, this one has a live counterpart that goes most
        of the way: [test/live/live_lists.ml] drives the selection through the real widget
        and reads the keys back through the same table this handler is fed from. What no
        test delivers is GTK's own click-to-activate, for the reason [Click_at] documents. *)
    | Activate_child of string * Key.t
    (** test_id of a [flow_box] carrying [Attr.on_child_activated], and the {!Key.t} of
        the card the user activated — a double click, or Enter, on a grid that sets
        [~activate_on_single_click:false]. Fires that handler with exactly that key.

        Its own action rather than [Activate_row] reused, on the same rule the attrs
        follow: [row-activated] and [child-activated] are different GTK signals on
        different widgets, and one action for both would read wrong in whichever test used
        the other noun.

        Both activate actions check the {i kind} of the node they find and fail naming it,
        because the handle knows it and "node grid is a FlowBox, not a ListBox" is a more
        useful failure than "node grid has no on_row_activated handler" — which is also
        true and is the less informative half. Nothing {i else} about the node is
        consulted: as with [Activate_row], neither the child list nor [~selected], so a
        key no card carries reaches the handler here. *)
    | Set_selection of string * Key.t list
    (** test_id of a [list_box] carrying [Attr.on_selected_rows_changed] {i or} a
        [flow_box] carrying [Attr.on_selected_children_changed], and the keys of every
        child now selected. Fires that handler with exactly that list.

        Shared between the two kinds, unlike the pair of activate actions, because it is
        the same question of both — "the selection is now these keys" — and the two GTK
        signals differ only in the noun. Which attr it looks for follows from the kind of
        the node it finds; a node that is neither kind reports that it has no
        [on_selected_rows_changed] handler.

        The whole selection, not a delta: that is what [selected-rows-changed] and
        [selected-children-changed] both report off the real widget, so an action that
        took one row would be modelling a signal that does not exist. [[]] is a state the
        widget can reach and so a state the action can deliver.

        [~selection_mode] is not consulted either, and that is the same decision as
        [Click_at]'s [~button] rather than an oversight: a test may hand two keys to a
        [~selection_mode:Single] list box, or any key at all to a [None_] one, and certify
        a model handling a selection GTK could never report. Filtering it would be the
        only piece of widget behaviour this harness models. As with [Activate_row], the
        node's own [~selected] is not consulted. *)
    | Set_page of string * Key.t
    (** test_id of a [notebook] carrying [Attr.on_page_changed], and the {!Key.t} of the
        page the user switched to. Fires that handler with exactly that key.

        Its own action rather than [Set_selection] reused: a notebook shows exactly one
        page, so the question is "which page" rather than "which set", and an action
        carrying a list would be modelling a signal that does not exist. Like the two
        activate actions it checks the node's {i kind} and fails naming it.

        Nothing else about the node is consulted, as ever: neither its page list nor its
        [~current_page], so a key no page carries reaches the handler here. The real
        widget would not emit that, and modelling it would hide the more useful failure --
        a model that mishandles a key it did not expect. What a live test adds is the
        other half: [test/live/live_lists.ml] drives the current page through the real
        widget and reads the key back through the same table this handler is fed from. *)
    | Set_selected of string * int
    (** test_id of a [drop_down] carrying [Attr.on_selected_changed], and the {i index} of
        the item the user chose — or [-1] for none, the same number [Node.drop_down]'s
        [~selected] takes. Fires that handler with exactly that index.

        The one action carrying an index rather than a key, because a drop-down's items
        are props rather than children and a position is the only name an item has. Like
        the two activate actions it checks the node's {i kind} and fails naming it.

        Nothing else about the node is consulted, as ever — neither [~items] nor
        [~selected]. Declining is the interesting case and it needs exactly that: a model
        that answers a [Set_selected 2] by re-rendering [~selected:0] is the headless
        statement of what [test/live/live_text.ml] proves against the real widget, where
        [Widget_impl.reassert] puts the drop-down back.

        The index is not range-checked either, and the honest reason is the one the [-1]
        case already has: headless there is no list model to ask, and GTK is what decides.
        [Node.drop_down] deliberately does {i not} check that [~selected] indexes [~items]
        — an index past the end is a state a correct model passes through — so the props
        this handle sees are {i not} in range by construction, and a check here would be
        inventing a rule the runtime does not have. What a test can reach is its own
        handler's behaviour, which is its business. (task-10-review.md R2.) *)
    | Select_day of string * Date.t
    (** test_id of a [calendar] carrying [Attr.on_day_selected], and the day the user
        picked. Fires that handler with exactly that date.

        A [Date.t], which is what the attr carries: GTK's [day-selected] has no payload
        and its date is three integers with a zero-based month, and none of that reaches a
        test. Like the two activate actions it checks the node's {i kind} and fails naming
        what it found.

        The node's own [~date] is not consulted, as ever, and the declining case is why: a
        model that answers a [Select_day] on a Saturday by re-rendering the Friday it was
        already showing is the headless statement of what [test/live/live_text.ml] proves
        against the real widget. *)
    | Set_editing of string * bool
    (** test_id of an [editable_label] carrying [Attr.on_editing_changed], and whether the
        user has entered or left editing mode. Fires that handler with exactly that.

        Live this is a [notify::editing] rather than a signal — [editing] is read-only in
        GTK and the class binds no signals at all — and headless that distinction does not
        exist, which is the point.

        Not derived from the node's [~editing], and deliberately not a toggle: leaving
        editing mode is not the inverse of entering it (Enter commits, Escape abandons, a
        click elsewhere takes the focus away), so a test says which happened. The {i text}
        of the edit arrives through {!Set_text}, because live it arrives through
        [Attr.on_changed] — per keystroke, on the [GtkEditable] the label implements. *)
  [@@deriving sexp_of]
end

(** Every action names its node by [Attr.test_id]. Two nodes carrying one id — what
    rendering the same sub-view twice produces — raises [Invalid_argument] naming both
    paths rather than acting on whichever the walk reaches first
    ({!Bonsai_gtk_vtree.Node.find_by_test_id}); an id no node carries raises [Failure]. *)
val result_spec : (Node.t, Action.t) Bonsai_test.Result_spec.t

(** {!Bonsai_test.Handle}, with the two entry points that did not check the tree replaced
    by ones that do.

    Everything here is [Bonsai_test.Handle]'s, unchanged, except [recompute_view] and
    [recompute_view_until_stable]. [t] is that module's type rather than a new one, so a
    handle passes freely between the two and a test needing something not re-exported here
    can call [Bonsai_test.Handle] directly.

    {b Why the two are shadowed.} The [Placement] / [Events] / key-phase checks below live
    in this library's [Result_spec.view], and only the entry points that
    {i build the view} call it: [show], [show_into_string], [show_diff], [store_view].
    [Bonsai_test.Handle.recompute_view] runs the computation and never builds a view, and
    [recompute_view_until_stable] is that function in a loop. So a test that advances with
    either and prints once at the end used to validate exactly one of its trees — while
    this file recommended exactly that idiom for seeing one action's effect before the
    next, and [test/handle/] followed the recommendation twenty times. A guarantee that
    holds only if you avoid the documented idiom is not a guarantee.

    Both now run the view for its exceptions and discard the string, through
    [Bonsai_test.Handle]'s own [?simulate_diff_patch] hook, which is handed the computed
    result. A [?simulate_diff_patch] the caller passes still runs, after the check.

    {b They are monomorphic in [Node.t] where the functions they shadow are polymorphic in
      the result.}
    The check is a function of a [Node.t]; a polymorphic ['result] has nothing to apply it
    to. Every handle {!create} hands out is a [(Node.t, Action.t) Handle.t], so this costs
    nothing in practice. *)
module Handle : sig
  type ('result, 'incoming) t = ('result, 'incoming) Bonsai_test.Handle.t

  (** {2 Checked already, and unchanged: these build the view} *)

  val show : ?simulate_diff_patch:('result -> unit) -> ('result, _) t -> unit

  val show_into_string
    :  ?simulate_diff_patch:('result -> unit)
    -> ('result, _) t
    -> string

  val show_diff
    :  ?location_style:Patdiff_kernel.Format.Location_style.t
    -> ?diff_context:int
    -> ?simulate_diff_patch:('result -> unit)
    -> ('result, _) t
    -> unit

  (** {2 Shadowed: these did not check, and now do} *)

  (** One frame of a Bonsai app, as [Bonsai_test.Handle.recompute_view] — flush the time
      source, flush the action queue, stabilize, trigger lifecycles — and then the tree it
      produced is checked, exactly as a [show] would check it. The view is not printed and
      not stored for [show_diff]; use [show] for that. *)
  val recompute_view : ?simulate_diff_patch:(Node.t -> unit) -> (Node.t, _) t -> unit

  (** [recompute_view] until there are no after-display lifecycle events left, or
      [max_computes] (default 100) is reached. Every intermediate tree is checked, not
      just the last. *)
  val recompute_view_until_stable
    :  ?max_computes:int
    -> ?simulate_diff_patch:(Node.t -> unit)
    -> (Node.t, _) t
    -> unit

  (** [show] without the printing: the frame is computed and the view stored for a later
      [show_diff]. The third entry point that did not check, and the least obvious one --
      it {i does} build a view, but lazily, so an illegal tree stored and never diffed was
      never seen. The check runs on the tree it just stored, after it is stored, since
      this function has no [?simulate_diff_patch] to hang it on. *)
  val store_view : (Node.t, _) t -> unit

  (** {2 The rest, unchanged} *)

  val last_result : ('result, _) t -> 'result
  val do_actions : (_, 'incoming) t -> 'incoming list -> unit
  val time_source : _ t -> Bonsai.Time_source.t
  val advance_clock_by : _ t -> Time_ns.Span.t -> unit
  val advance_clock : to_:Time_ns.t -> _ t -> unit

  (** Prefer {!Bonsai_gtk_test.create}, which supplies this library's [Result_spec]. This
      is here so that the re-export is complete; a handle built with some other spec is
      one the checks above cannot see. *)
  val create
    :  here:[%call_pos]
    -> ?start_time:Time_ns.t
    -> ?optimize:bool
    -> ('result, 'incoming) Bonsai_test.Result_spec.t
    -> (local_ Bonsai.graph -> 'result Bonsai.t)
    -> ('result, 'incoming) t

  val has_after_display_events : ('result, 'incoming) t -> bool
  val print_actions : _ t -> unit
  val print_stabilizations : _ t -> unit
  val print_stabilization_tracker_stats : _ t -> unit
  val print_computation_structure : _ t -> unit

  (** [show_model], [result_incr], [lifecycle_incr] and [action_input_incr] are not
      re-exported: they expose Bonsai internals ([show_model] carries a
      [rampantly_nondeterministic] alert of its own) and re-stating that alert here would
      duplicate a warning whose wording is [bonsai_test]'s to change. [t] is
      [Bonsai_test.Handle.t], so a test that wants one calls it there. *)
end

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
    - [Bonsai_gtk_vtree.Events.key_phase_rejection], so a node whose [Attr.on_key_pressed]
      and [Attr.on_key_released] ask for different propagation phases raises here too.
      They share one [GtkEventControllerKey] and therefore one phase, so there is nothing
      the runtime could mount; both sides call the same function for the string.

    {b All three are checked by every entry point that advances a handle} --
    [Handle.show], [Handle.show_into_string], [Handle.show_diff], [Handle.store_view],
    [Handle.recompute_view] and [Handle.recompute_view_until_stable] -- on the first call
    and on every later one. So there is no way to advance a handle {i through this module}
    past a tree without checking it, and no idiom a test has to avoid. The scope matters:
    {!Handle.t} is [Bonsai_test.Handle.t], deliberately (it is what lets the four values
    named below be used unchanged), so [Bonsai_test.Handle.recompute_view handle] still
    typechecks and still skips the check. Nothing in [test/], [src/] or [examples/] calls
    it that way, and making [t] abstract to close the hole would cost the interop the
    omissions depend on.

    That took work, and the history is worth a sentence because it is the reason {!Handle}
    is a hand-written signature rather than an alias for [Bonsai_test.Handle]. The checks
    live in this [Result_spec]'s [view], and three of those six entry points did not call
    it: [recompute_view] and [recompute_view_until_stable] run the computation without
    building a view at all, and [store_view] builds one lazily, so a tree stored and never
    diffed was never seen. [recompute_view] in particular is the idiom this very file
    recommends below for advancing between actions, and [test/handle/] takes that advice
    twenty times -- one of which was certifying a tree the runtime refuses
    ([test/handle/test_handle.ml]'s "Toggle needs a handler"). All three are shadowed here
    now. [test/handle/test_gallery.ml] pins all six.

    Three more structural rules are checked here as of the M2 fix wave, all of them from
    pure vtree data and none of them needing a widget:

    - {b duplicate keys among siblings}, through the same
      [Bonsai_gtk_vtree.Reconcile.check_unique_keys] the patcher calls at mount, with the
      container's path prefixed the same way;
    - {b a [Node.window] below the root}, which the patcher refuses because a [GtkWindow]
      is a toplevel that cannot be parented;
    - {b the root's own kind}, against {!create}'s [?root_kind] — [`Window] by default,
      mirroring [Bonsai_gtk.Expert.Driver.create], because [Bonsai_gtk.start] requires a
      [Node.window] root and this is the mistake most likely to reach a running app: a
      view function that lost its window in a refactor renders a complete and
      correct-looking tree headlessly and breaks the driver permanently on frame 1. Pass
      [~root_kind:`Not_window] for a component destined for [Bonsai_gtk.Expert.embed],
      which refuses a window root for the mirror-image reason. Unlike the others this rule
      is not a property of the tree at all -- it is a property of the entry point the tree
      is destined for -- so it is remembered from the most recent {!create} rather than
      carried on the handle, which has nowhere to put it. A test that interleaves two
      handles with {i different} root kinds therefore checks the older one against the
      newer one's rule; because the two rules are opposites rather than one being weaker,
      the cost of that is a loud rejection of a legal tree and never a silent acceptance
      of an illegal one.

    {2 What this handle checks, against what the runtime refuses}

    The table below is the whole of it, and it exists because three places in this
    repository used to say something weaker and different — all of them explaining the
    remaining gap with a reason that was false: "needs the widget implementations or the
    live tree". Most of what is still unchecked is decidable from [bonsai_gtk.vtree]
    alone, which this library already links; the honest reason is that nobody has written
    those checks yet. This is the one copy, and [README.md] points at it rather than
    restating it.

    "vtree" means decidable from [bonsai_gtk.vtree] alone.

    {v
 #  what the runtime refuses                              vtree  checked here
 1  event attr the kind cannot emit                        yes    yes
 2  placement attr the parent does not read                yes    yes
 3  two key attrs with different ~phase                    yes    yes
 4  root is not a Node.window (or is one, under embed)     yes    yes  (?root_kind)
 5  Node.window below the root                             yes    yes
 6  duplicate keys among siblings                          yes    yes
 7  stack/list_box/flow_box/notebook child with no ~key     -     yes, at the constructor
 8  Node.grid child with no Attr.grid_cell                  yes    no
 9  ~visible_child naming no page                           yes    no
10  ~current_page naming no page                            yes    no
11  two Node.stacks under one ~name                         yes    no
12  stack_switcher/_sidebar naming no stack                 yes    no
13  slot/children shape mismatch                            no     no   (no constructor builds one)
14  a NUL in any text, or invalid UTF-8 in a text_view      yes    no   (refused live)
15  entry ~text longer than ~max_length                     yes    no   (truncated live)
16  a Move to a container with no reorder primitive         yes    n/a  (this handle never diffs)
    v}

    Rows 8-12 are the ones that could still be closed cheaply: they are tree walks over
    data this library already has. Rows 14 and 15 are {i refusals} rather than rejections
    — live the write is declined, the widget keeps what it had, and the runtime says so
    once through the patcher's report channel — so a green headless test over such a tree
    is not certifying a crash; it is certifying a value the widget will never show.

    {3 Where a green headless suite does not mean the runtime will hold the state}

    Two places in this repository each used to call themselves "the one place" this
    happens. There are six, and four of them are deliberate:

    - rows 14 and 15 above: text the runtime refuses or truncates, which an action
      delivers verbatim;
    - a [drop_down ~selected] of [-1] over a non-empty list, or past the end — GTK
      declines it and reports it, and headless there is no GTK ({i deliberate}: see
      [Action.Set_selected]);
    - [Action.Activate_row] on a row carrying [Attr.row_activatable false], and
      [Activate_child]/[Set_page] after it — GTK would never emit the signal
      ({i deliberate}: filtering it would be the only event routing this harness
      implements; see [docs/m2-backlog.md]);
    - [Action.Set_selection] delivering more keys than a [~selection_mode] allows, or any
      key at all to a [None_] one — GTK would never report it ({i deliberate}, on the same
      argument as [Click_at]'s [~button]);
    - a [list_box]/[flow_box] [~selected] naming keys with no rows — inert live until the
      row arrives, shown as selected headlessly ({i deliberate}, and documented on
      [Bonsai_gtk_vtree.Node.list_box]);
    - a [notebook ~current_page] naming a page whose child is hidden, and the same for a
      [stack ~visible_child] — GTK leaves the page alone, so the model and the screen
      diverge with nothing said (on the backlog for the report hook).

    The second known gap is {i routing}. Every action here is delivered to one node, named
    by [Attr.test_id]; there is no widget hierarchy for an event to travel through. So a
    [Click_at] on a card does not also reach the container that would have handled it, a
    [Key_press] that answers [Key_response.Handled] does not stop a sibling from seeing
    the key, and [Attr.on_key_pressed]'s [~phase] — which decides only who sees a key
    {i first} — has no effect at all here. What a test can show is that a handler made the
    right decision and what that decision did to the model; that GTK then routes the event
    accordingly is GTK's, and is not checked anywhere (see [docs/m2-backlog.md]), because
    the pinned ocgtk binding can synthesise neither a click nor a key press.

    [Handle.do_actions] looks up every action in the call against *one* view snapshot —
    the tree [Handle.show]/[Handle.recompute_view] last computed — not the tree as it
    would be after each prior action in the same call takes effect. So
    [do_actions handle [ Click "inc"; Click "inc" ]] finds "inc" against the same node
    both times; if the second click is meant to see whatever the first click's effect
    changed (a different label becoming clickable, an attribute the click flips), call
    [Handle.recompute_view handle] between the two actions to force a fresh snapshot
    first. See [test/test_handle.ml] for the pattern: two single-click [do_actions] calls
    separated by [recompute_view], rather than one call with both clicks. The intermediate
    tree that produces is checked like any other -- {!Handle}'s [recompute_view] is this
    library's, not [bonsai_test]'s, for exactly that reason. *)
val create
  :  here:[%call_pos]
  -> ?start_time:Time_ns.t
  -> ?optimize:bool
  -> ?root_kind:[ `Window | `Not_window ]
  -> (local_ Bonsai.graph -> Node.t Bonsai.t)
  -> (Node.t, Action.t) Handle.t
