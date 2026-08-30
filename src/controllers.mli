open! Core
open Bonsai_gtk_vtree
open Gtk_import

(** The [GtkEventController]s attached to one widget on account of its attributes.

    Unlike a widget's own signals — connected once at [create] for every spec its impl
    declares — a controller exists only while an attribute asks for one. Three reasons it
    is not simply "attach all of them to every widget": three GObjects per widget is a
    real cost on a library whose claim is that a frame is cheap; a controller's
    propagation phase is part of the attribute, so there is no phase to pick before the
    attribute exists; and a widget with no key handler should not appear in GTK's capture
    chain at all.

    What it is {i not} is a second signal mechanism. The connecting, the slots, the
    [in_patch] guard, the exception guard and the disconnect-from-the-object-that-issued-
    the-id rule are all {!Signals}; this module decides only which controllers should
    exist and owns their attach/detach. *)
type t

(** Attaches nothing. Call once per widget, at mount, right after [Signals.connect_all];
    the first {!update} creates whatever the attrs ask for. *)
val create : Signals.ctx -> node_path:string -> Widget.t -> t

(** Brings the attached controllers into line with [attrs]: creates one whose attrs have
    appeared, removes one whose attrs have all gone, re-points the handler slots, and
    re-applies the propagation phase and the gesture's button.

    A phase or button change re-applies the setter rather than rebuilding the controller —
    both are plain properties and GTK re-reads them per event. Cheap enough to do
    unconditionally, which is what this does: comparing first would mean storing the old
    attr, and the setter on an unchanged value is free.

    Called at mount after {!create}, and on every patch. Unconditional for the same reason
    [Signals.update_slots] is: every frame rebuilds its closures, so "the attrs changed"
    is true of any node carrying a handler at all, and the two calls sit together.

    Every slot is emptied once up front and re-armed per family, so no slot is armed while
    a controller is being removed (removal can provoke a leave or a cancel), and every
    family that survives the frame ends it armed whatever order the families are visited
    in. Both matter: a removed family must not disarm the ones beside it. *)
val update : t -> Attrs.t -> unit

(** Empties every slot, leaving the controllers attached and connected — so a signal GTK
    emits while a subtree is being unparented cannot reach a handler.

    The counterpart of [Signals.clear_slots], and called from the same place: the
    patcher's [disarm], on the paths where a subtree is unparented {i before} it is
    destroyed. *)
val clear : t -> unit

(** Empties every slot, disconnects, and removes every controller from the widget.

    The slot-emptying is first and is the load-bearing half:
    [gtk_widget_remove_controller] can itself provoke a leave or a cancel, and a slot
    still armed then would reach Bonsai from inside teardown. Same rule, same reason, as
    [Signals.clear_slots].

    Leaves [t] empty rather than unusable: a later {!update} would attach afresh. Nothing
    does that today — teardown is the end of a live node. It is the same three steps in
    the same order as {!update}'s attr-removal path, run for every family at once. *)
val release : t -> unit

(** How many controllers are attached, for tests. Counts what {i this} module attached,
    not what GTK reports: [Widget.observe_controllers] is the other half of that assertion
    and is what [test/live/live_controllers.ml] compares this against. *)
val attached_count : t -> int

(** Which controller-attr slots currently hold a handler, across every attached family, in
    {!Attr.Name} order.

    Introspection for tests, and the only evidence there is that a click slot is armed: no
    click can be synthesised through this binding, so "the gesture is attached" and "the
    gesture will call anything" are two different facts and only this one says the second.
    [test/live/live_controllers.ml] uses it to assert that removing one family does not
    disarm another's slots. *)
val armed : t -> Attr.Name.t list

(** Whether a controller [Widget.observe_controllers] reported is one this module
    attached, by the debugging name it sets on every controller it creates.

    A widget class attaches controllers of its own — a [GtkButton] ships with a
    [GtkGestureClick], a [GtkEventControllerKey] and a [GtkShortcutController] — so a live
    test that counted by class would be counting GTK's as well as ours, and one that
    counted the total would break the day a GTK release changes how many a button has.
    Exposed for [test/live/live_controllers.ml], which is the only caller. *)
val is_ours : Gtk_import.W.Event_controller.t -> bool
