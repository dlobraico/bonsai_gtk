open! Core

(** Which event attributes each kind can carry.

    Pure data, in [vtree] rather than in the runtime, because two things need it and only
    one of them may link ocgtk: [Signals.require_specs] rejects an unsupported event attr
    at mount, and [Bonsai_gtk_test] must reject the same tree at handle time — otherwise a
    suite that is entirely headless certifies an application that raises the moment it is
    shown, which is exactly what M1 shipped (see [bonsai_gtk_test.mli]'s warning, which
    this table rewrites).

    This table and each widget impl's [Widget_impl.signals] are two statements of one
    fact. [test/live/live_events.ml] compares them for every kind and fails the build if
    they disagree — "every kind" being enforced by an assertion against
    [Kind.Variants.descriptions], so a kind nobody added to that test's list is a failure
    rather than a gap. That test runs only under [BONSAI_GTK_LIVE_TESTS=1], because it
    links ocgtk; [Signals.require_slots] is the unconditional backstop under it, raising
    at mount if the two ever do drift. Do not weaken either. *)
val for_kind : Kind.t -> Attr.Name.t list

(** One [GtkEventController] the runtime attaches on demand. A family, rather than one per
    attr, because {!Attr.on_focus_enter} and {!Attr.on_focus_leave} share a single
    [GtkEventControllerFocus] -- a widget carrying either pays for one -- and
    {!Attr.on_key_pressed} and {!Attr.on_key_released} share a [GtkEventControllerKey] the
    same way. *)
module Family : sig
  type t =
    | Click (** [GtkGestureClick] *)
    | Focus (** [GtkEventControllerFocus] *)
    | Key (** [GtkEventControllerKey] *)
  [@@deriving sexp_of, equal, compare, enumerate]
end

(** Which controller an event attr asks for; [None] for every ordinary widget property and
    every attr that is some widget class's own signal.

    The single point of truth for the controller carve-out, and the reason it is a table
    rather than a predicate. Three things read it and would otherwise drift:
    {!is_supported} admits exactly the names with a family (they are legal on every kind,
    so they never appear in {!for_kind}); [Signals.require_slots] skips exactly those
    names, because their slots belong to [Controllers] rather than to the widget; and
    [Controllers.update] dispatches on {!Family.t} with an exhaustive match, so a family
    named here that nothing attaches is a compile error.

    Without that last link a controller attr could be accepted on every node by both the
    runtime and the headless handle, skipped by every mount-time check, and wired to
    nothing -- silent inertness, which is the failure [Signals.require_specs] exists to
    prevent. Exhaustive over [Attr.Name.t] with no wildcard, so a new attr cannot skip the
    decision either.

    [test/live/live_controllers.ml] closes the loop from the other end: it mounts a node
    carrying each name this gives a family to, and asserts a controller of ours appears. *)
val controller_family : Attr.Name.t -> Family.t option

(** [true] for the event attrs {!controller_family} gives a family, derived from it so the
    two cannot disagree: {!Attr.on_click}, {!Attr.on_focus_enter}, {!Attr.on_focus_leave}.
    No widget impl declares one -- [test/live/live_events.ml] asserts that, because an
    impl that did would connect a second handler nobody removes. *)
val is_controller_attr : Attr.Name.t -> bool

(** The attr names belonging to one family, in [Attr.Name] order. [Controllers] asks this
    whether a family's controller should exist at all: it should, exactly while at least
    one of these attrs is present. *)
val family_attrs : Family.t -> Attr.Name.t list

(** The propagation phase the [GtkEventControllerKey] shared by {!Attr.on_key_pressed} and
    {!Attr.on_key_released} should be given; [None] when the node carries neither.

    Both attrs carry a phase, because either may appear alone, but there is only one
    controller and therefore only one phase to write. When both are present and agree,
    this is that phase. When they disagree this answers with {!Attr.on_key_pressed}'s,
    which is a value no caller ever reaches: {!key_phase_rejection} is non-[None] for
    exactly those attrs, and both consumers check it first. *)
val key_phase : Attrs.t -> Phase.t option

(** The [Invalid_argument] message for a node whose two key attrs ask for different
    propagation phases; [None] otherwise.

    Rendered here rather than at either call site, and for the reason
    {!Placement.rejection} is: [Controllers] raises it at mount and at patch, when it has
    to pick a phase and cannot, and [Bonsai_gtk_test] raises the same string at handle
    time so that a headless suite cannot certify a view the runtime refuses. Picking one
    of the two silently is the alternative, and it would give one of the attrs a routing
    phase its author did not ask for -- in the [Capture]/[Bubble] case, the difference
    between a dialog that takes Escape and one whose child swallows it. *)
val key_phase_rejection : path:string -> Attrs.t -> string option

(** [is_supported kind name] is [true] if [name] is not an event name, is a controller
    attr (legal everywhere), or is a signal this kind emits. A non-event name is always
    supported: this answers "may this attr be here", and layout attrs may be anywhere. *)
val is_supported : Kind.t -> Attr.Name.t -> bool

(** The first event attr in [attrs] that [kind] cannot emit, in [Attr.Name] order. [None]
    when every event attr present is one this kind emits. *)
val unsupported : Kind.t -> Attrs.t -> Attr.Name.t option
