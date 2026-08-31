open! Core
open Bonsai_gtk_vtree
open Gtk_import

(** What a signal trampoline needs from the app runtime. *)
type ctx =
  { schedule : unit Ui_effect.t -> unit
  (** Hand a fired handler's effect to the Bonsai driver. *)
  ; in_patch : unit -> bool
  (** [true] while the patcher is mutating the widget tree. GTK emits signals
      synchronously from calls like [set_child]/[remove], and re-entering Bonsai from
      inside a patch would corrupt it, so callbacks are dropped then. *)
  ; on_exn : node_path:string -> exn -> unit
  (** Reports an exception raised while dispatching. Must not raise; if it does, the
      trampoline swallows it. *)
  }

(** {1 The rule about dispose-time signals}

    {b Never connect a handler to a signal a GObject's dispose can emit} -- [destroy],
    [unrealize], a [notify::] on a property a widget clears on the way down -- and if one
    is unavoidable, {b disconnect it before that object can become collectable}, in the
    same call that makes it collectable.

    The reason is not tidiness. ocgtk's wrapper finaliser unrefs the widget, GTK's dispose
    emits [destroy], and the generic marshaller calls back into OCaml
    {i from inside the collector}. Measured with plain ocgtk and no bonsai_gtk involved: a
    callback that allocates segfaults (three runs of three), and one that does not may
    survive -- a threshold no author can reason about and none should try to. Until the
    fork's marshaller refuses to call back during finalisation (the binding fix, and the
    plan's Global Constraints addendum), the rule is the whole of the protection.

    This library obeys it. [src/embed.ml] holds the only [destroy] connection in [src/],
    [vtree/] and [test_lib/], and [Embed.stop] disconnects it in the same call that drops
    the driver's [on_root_widget_changed] -- which is precisely what makes the wrapper
    finalisable, because while the backstop is connected the closure cycle (wrapper -> the
    handler's GClosure -> the driver -> [on_root_widget_changed] -> wrapper) holds it
    alive. Everything else this module connects -- the [notify::] read-backs, the
    connections that name a [GtkTextBuffer], a [GtkStringList] or an event controller --
    is disconnected by [Patcher.destroy] before its widget can be collected, and could not
    be reached from the collector anyway: a connected closure roots the driver, which
    roots the widget.

    A new signal added to a widget impl's [Widget_impl.signals] is safe by construction --
    [Patcher.destroy] disconnects the whole list. A connection made anywhere {i else} is
    the one to check against this paragraph. *)

(** One connected GTK handler: the id, and the object it is connected {i to}.

    Both halves are needed, and the second is the one that is easy to lose.
    [g_signal_handler_disconnect] takes the object the id was issued for, and a handler id
    is only unique per object — so disconnecting from the widget an id that belongs to
    some other GObject is at best a GLib critical and at worst disconnects an unrelated
    handler that happens to share the number, leaving the real one connected and its slot
    pinned alive as a GC root. *)
type connection

(** [connected obj id] pairs the id a connection returned with the object it was made on.
    Every {!spec.connect} ends in this. *)
val connected : 'a Gobject.obj -> Gobject.Signal.handler_id -> connection

(* The two arms' records share [attr], [connect] and [fire] deliberately: they are two
   spellings of one concept and renaming either set would make the pair harder to read
   than the shadowing is. Warning 30 says so, and is switched off over the declaration
   rather than library-wide. *)
[@@@warning "-30"]

(** One GTK signal a widget impl (or an event controller) knows how to connect, and the
    attr that carries its handler.

    [Read_back] is the ordinary shape: GTK's callback carries nothing and the value the
    user just changed lives on the widget, so [fire] reads it back with the class getter.
    Every M1 signal is one of these, and so is every [notify::] one, whose generic
    marshaller carries nothing at all.

    [Payload] is for the signals whose arguments cannot be recovered afterwards, and which
    ones those are is two rules rather than a list -- stated as rules so that a milestone
    which adds a signal does not have to remember to update a count. Every signal whose
    argument is a {b child widget}, because the child is gone by the time anything could
    look for it ([GtkListBox::row-activated] and its two siblings). And every
    {b controller} signal, because a controller remembers nothing about the event it has
    just delivered: [GtkGestureClick::pressed]'s coordinates are stored nowhere,
    [GtkEventControllerKey::key-pressed] carries the keyval and wants a [bool] back, and
    [GtkEventControllerKey::key-released] carries the keyval and answers [unit]. A new
    signal of either shape is a [Payload], not a [Read_back]; the specs themselves are the
    enumeration, in the widget impls and in [Controllers]. ['p] is the payload the
    [connect] closure assembles — it may combine the callback's arguments with things read
    off the object, which is how a click's [button] and [modifiers] get in — and ['r] is
    what the callback returns to GTK. Both are existential: a [spec list] holds specs with
    different payloads and different return types, and nothing outside the spec ever names
    either.

    [fire] returning ['r * unit Ui_effect.t option] rather than ['r Ui_effect.t] is the
    load-bearing shape. The return value has to reach GTK {i synchronously}, on the C
    stack, and a Bonsai effect is scheduled and performed later; so the decision ("do I
    consume this key") is made from the event, purely, in the trampoline, and the
    consequence (a state update) is an effect like any other.

    [declined] is the return value for the emissions that reach no handler: an empty slot,
    an emission during a patch, or a [fire] that raised. It must be the {i inert} answer
    for the signal — [false] ("not handled") for a key controller — because those three
    cases are precisely the ones where the application has said nothing, and the opposite
    answer would make a widget with no handler swallow every key it sees. It is data on
    the spec because the safe answer differs per signal and nothing else knows it. *)
type spec =
  | Read_back of read_back
  | Payload : ('p, 'r) payload -> spec

and read_back =
  { attr : Attr.Name.t
  ; connect : Widget.t -> callback:(unit -> unit) -> connection list
  (** Connect [callback] and return the resulting {!connection}s.

      The object connected to need {i not} be the widget: it is whatever GObject actually
      emits the signal — a [GtkEditable] delegate, an event controller [Controllers]
      attached, a [GtkTextBuffer] or a list model. What is required is that each returned
      {!connection} name the object it was made on, because that is what teardown
      disconnects from. Build them with {!connected} and the returned ids, never by
      pairing an id with a different object.

      {b A list, because one attr may need more than one GTK emission.} Almost every spec
      returns a singleton. The exception is a controlled prop whose value the user can
      change by more than one route that GTK reports differently: a [GtkCalendar]'s date
      moves by a day click ([day-selected]) {i or} by a heading walk (which emits only
      [notify::month] or [notify::year] and no [day-selected] at all — measured), and an
      attr that heard about one and not the other would be a prop the application cannot
      keep up with. All of them share {i one} attr name and therefore {i one} slot, so
      [update_slots], {!armed} and {!require_slots} are unchanged and no duplicate name
      reaches the slot list; what changes is only how many places the same callback is
      wired to. The consequent duplicate deliveries are the spec's own to coalesce in
      {!read_back.fire}. *)
  ; fire : Widget.t -> Attr.t -> unit Ui_effect.t option
  (** Turn the attr currently in the slot into the effect to schedule. [None] if the attr
      is not the one this spec handles, or if this particular emission is not one the
      application should hear about — a [GtkSearchEntry]'s debounced [search-changed]
      arriving after a write the library itself made, say.

      The widget is passed because GTK's callbacks mostly carry no payload — the value the
      user just changed lives on the widget — so a handler that takes an argument builds
      it by reading the property back with the class getter (spec §6.4). That is the only
      way to build one at all for the [notify::] family, whose generic marshaller carries
      nothing. *)
  }

and ('p, 'r) payload =
  { attr : Attr.Name.t
  ; connect : Widget.t -> callback:('p -> 'r) -> connection
  (** Connect [callback] and return the resulting {!connection}, as {!read_back.connect}
      does — and additionally {i assemble the payload}. Anything the event carries that is
      not a callback argument has to be read here, while the event is still current: a
      click's button and modifier state are on the gesture and its controller during the
      emission and gone the moment the callback returns, so a [fire] that tried to read
      them would get nothing. That is why this half of the spec is a closure over the
      object rather than a pure function of the arguments. *)
  ; fire : Widget.t -> Attr.t -> 'p -> 'r * unit Ui_effect.t option
  (** The value to hand back to GTK now, and the effect to schedule (if any). [None] for
      the effect on the same terms as {!read_back.fire}'s: the attr is not the one this
      spec handles, or this emission is not one the application should hear about. *)
  ; declined : 'r
  }

[@@@warning "+30"]

(** The mutable cells the connected callbacks read their handler out of. Kept per widget
    for the widget's lifetime: GTK handlers are connected exactly once, at creation, and a
    re-render only rewrites the cells. *)
type slots

(** Connects every spec to [w], returning the slots and the connections to {!disconnect}
    on destruction. The slots start empty, so callbacks are inert until the first
    {!update_slots} — call it with the node's attrs right after creating the widget.

    Each callback is exception-guarded: nothing raised by [in_patch], [fire], or
    [schedule] escapes into GTK's C frame. A {!Payload} spec's callback additionally
    returns its [declined] value on that path, since the frame owes GTK an answer whatever
    happened.

    Used for a widget's own signals (from [Widget_impl.signals], at mount) and for the
    signals of an event controller [Controllers] attached (whose [connect] ignores the
    widget it is handed and connects to the controller instead). *)
val connect_all
  :  ctx
  -> node_path:string
  -> Widget.t
  -> spec list
  -> slots * connection list

(** Points each slot at the matching attr in [attrs] (or empties it when absent). *)
val update_slots : slots -> Attrs.t -> unit

(** Empties every slot, making the still-connected GTK callbacks no-ops. Called when a
    widget is detached, so a signal GTK emits during teardown cannot fire a stale handler. *)
val clear_slots : slots -> unit

(** Which slots currently hold a handler, in {!Attr.Name} order.

    Introspection for tests, and the only way to see the difference between a connected
    callback that will fire and one that is inert: an emptied slot is not observable from
    GTK's side at all, and for a signal that cannot be synthesised (a click, a key press)
    it is not observable from the handler's side either.
    [test/live/live_controllers_focus.ml] uses it to assert that one controller family
    being removed does not disarm another's slots. *)
val armed : slots -> Attr.Name.t list

(** Connects to the detailed signal [notify::<prop>], which GTK emits whenever that
    property changes — however it changed, so a spec built on this fires for the library's
    own writes as well as the user's, and relies on the {!ctx.in_patch} guard to drop the
    former.

    This is the connector for properties whose class has no dedicated signal
    ([GtkSwitch]'s [active], for instance, whose [state-set] is the wrong hook for a
    controlled widget). *)
val notify : prop:string -> Widget.t -> callback:(unit -> unit) -> connection list

(** {!notify}'s single connection, for a spec that connects to more than one thing and so
    has to build its own list — and for one made on an object other than the widget. *)
val notify_connection
  :  prop:string
  -> 'a Gobject.obj
  -> callback:(unit -> unit)
  -> connection

(** The {!Attr.Name.t} a spec carries, whichever arm it is. Readers that only want the
    name go through this rather than matching, so the variant stays inside this module. *)
val spec_attr : spec -> Attr.Name.t

(** Raises [Invalid_argument] if [attrs] carries an event attr ({!Attr.Name.is_event})
    that this {!Kind.t} does not emit — [Attr.on_toggled] on a [Node.label], say. Such an
    attr is inert rather than wrong-looking: no slot is created for it, so the handler
    simply never runs. [node_path] and [impl_name] name the offending node in the message.

    The verdict comes from {!Bonsai_gtk_vtree.Events}, which lives in [vtree] rather than
    here precisely so that [Bonsai_gtk_test] can reach the same table and refuse the same
    trees headlessly. The impl's own [spec list] is the second statement of that fact, and
    [test/live/live_events.ml] is what holds the two together.

    The widget is named in the message by [Kind.name], not by the impl's own [name]: that
    is what makes this message and {!Bonsai_gtk_test}'s identical by construction rather
    than by convention, since the test harness has no impl to ask.

    Called by the patcher at mount, and again on any patch that changed the node's attrs —
    an event attr a later render adds conditionally lands on a widget mounted without it,
    and only the patch is in a position to see it (handlers are connected once, at mount,
    so no slot exists for a name no spec claims). *)
val require_specs : node_path:string -> Kind.t -> Attrs.t -> unit

(** Raises [Invalid_argument] if [attrs] carries an event attr — other than a controller
    attr, whose slots belong to [Controllers] rather than to the widget — for which
    [slots] holds no slot — that is, if {!Bonsai_gtk_vtree.Events} says this kind emits
    the signal but the widget impl declared no {!spec} for it.

    That combination cannot happen while the two agree, and [test/live/live_events.ml]
    checks that they do — but only under [BONSAI_GTK_LIVE_TESTS=1]. This runs on every
    mount, so a drift that slipped past the live gate raises here instead of leaving a
    handler silently unconnected, which is the failure {!require_specs} exists to prevent.
    [impl_name] rather than [Kind.name] here, because the impl is the thing at fault. *)
val require_slots : node_path:string -> impl_name:string -> slots -> Attrs.t -> unit

(** Disconnects each handler from the object it was connected to. *)
val disconnect : connection list -> unit
