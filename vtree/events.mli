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

(** [true] for the event attrs that are not any widget class's signal but an event
    controller the runtime attaches to whatever widget carries the attr: {!Attr.on_click},
    {!Attr.on_focus_enter}, {!Attr.on_focus_leave}.

    They are legal on every kind, so they never appear in {!for_kind} and {!is_supported}
    short-circuits on them. They are also not connected by any widget impl --
    [Controllers] creates their slots from the attr itself, on the frame the attr appears
    -- so [Signals.require_slots] skips them, and [test/live/live_events.ml] asserts that
    no impl declares one. *)
val is_controller_attr : Attr.Name.t -> bool

(** [is_supported kind name] is [true] if [name] is not an event name, is a controller
    attr (legal everywhere), or is a signal this kind emits. A non-event name is always
    supported: this answers "may this attr be here", and layout attrs may be anywhere. *)
val is_supported : Kind.t -> Attr.Name.t -> bool

(** The first event attr in [attrs] that [kind] cannot emit, in [Attr.Name] order. [None]
    when every event attr present is one this kind emits. *)
val unsupported : Kind.t -> Attrs.t -> Attr.Name.t option
