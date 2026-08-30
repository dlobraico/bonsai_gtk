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
    they disagree; that test is the only thing keeping them honest, so do not weaken it. *)
val for_kind : Kind.t -> Attr.Name.t list

(** [is_supported kind name] is [true] if [name] is not an event name, or is one this kind
    emits. A non-event name is always supported: this answers "may this attr be here", and
    layout attrs may be anywhere. *)
val is_supported : Kind.t -> Attr.Name.t -> bool

(** The first event attr in [attrs] that [kind] cannot emit, in [Attr.Name] order. [None]
    when every event attr present is one this kind emits. *)
val unsupported : Kind.t -> Attrs.t -> Attr.Name.t option
