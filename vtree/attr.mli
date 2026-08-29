open! Core

module Name : sig
  type t =
    | Margin_start
    | Margin_end
    | Margin_top
    | Margin_bottom
    | Halign
    | Valign
    | Hexpand
    | Vexpand
    | Sensitive
    | Visible
    | Tooltip
    | Width_request
    | Height_request
    | Opacity
    | Focusable
    | Can_focus
    | Widget_name
    | Cursor_name
    | Test_id
    | On_clicked
    | On_toggled
    | On_changed
    | On_activate
    | On_search_changed
    | On_value_changed
    | On_expanded_changed
    | On_revealed
  [@@deriving sexp_of, compare, equal]

  (** [true] for the handler-carrying names — the ones a widget impl must declare a signal
      spec for, and which the patcher rejects at mount on a widget that declares none. *)
  val is_event : t -> bool

  include Comparable.S_plain with type t := t
end

type t =
  | Css_class of string
  | Margin_start of int
  | Margin_end of int
  | Margin_top of int
  | Margin_bottom of int
  | Halign of Align.t
  | Valign of Align.t
  | Hexpand of bool
  | Vexpand of bool
  | Sensitive of bool
  | Visible of bool
  | Tooltip of string
  | Width_request of int
  | Height_request of int
  | Opacity of float
  | Focusable of bool
  | Can_focus of bool
  | Widget_name of string
  | Cursor_name of string
  | Test_id of string
  | On_clicked of unit Handler.t
  | On_toggled of bool Handler.t
  | On_changed of string Handler.t
  | On_activate of unit Handler.t
  | On_search_changed of string Handler.t
  | On_value_changed of float Handler.t
  | On_expanded_changed of bool Handler.t
  | On_revealed of bool Handler.t
  | Many of t list
[@@deriving sexp_of]

(** [None] for [Css_class] (accumulates, not keyed) and [Many]. *)
val name : t -> Name.t option

(** Structural, except handlers compare physically. *)
val equal : t -> t -> bool

val css_class : string -> t
val margin_start : int -> t
val margin_end : int -> t
val margin_top : int -> t
val margin_bottom : int -> t

(** all four sides *)
val margin : int -> t

val halign : Align.t -> t
val valign : Align.t -> t
val hexpand : bool -> t
val vexpand : bool -> t
val sensitive : bool -> t
val visible : bool -> t
val tooltip : string -> t
val width_request : int -> t
val height_request : int -> t

(** [0.] is fully transparent, [1.] fully opaque; GTK clamps anything outside that range.
    GTK still lays the widget out and still routes input to it — use [visible false] to
    take it out of the layout. *)
val opacity : float -> t

(** Whether the widget takes keyboard focus itself. GTK's defaults differ per widget class
    (a [GtkButton] is focusable, a [GtkLabel] is not), so unsetting this restores that
    widget's own class default rather than a constant. *)
val focusable : bool -> t

(** Whether focus may travel {i into} this widget or its children. As with {!focusable},
    the default is per widget class and unsetting restores that class's own. *)
val can_focus : bool -> t

(** [GtkWidget]'s [name] — the CSS "#id" selector. Called [widget_name] rather than [name]
    because {!name} already means "which attribute is this".

    Dropping this attribute is the one [Unset] that is not exact: ocgtk's [set_name] takes
    a [string], not a [string option], so there is no way to pass NULL and restore "this
    widget has no name". Unset therefore writes back what [get_name] reported at creation,
    which for an unnamed widget is its class name (["GtkLabel"]) — so the widget ends up
    with an explicit CSS id it did not have before, and a [#GtkLabel] selector would match
    it. Harmless unless a stylesheet uses class names as ids; a NULL-accepting [set_name]
    in the ocgtk fork would remove the caveat. *)
val widget_name : string -> t

(** A CSS cursor name — ["pointer"], ["text"], ["not-allowed"], ["default"]. An unknown
    name is GTK's problem, not ours: it logs and falls back. *)
val cursor_name : string -> t

val test_id : string -> t
val on_clicked : unit Ui_effect.t -> t

(** Fires when the user flips a [toggle_button], [check_button] or [switch], carrying the
    value the widget now has.

    Programmatic changes — the ones a re-render makes — do not fire it: the patcher's
    reentrancy guard drops every signal GTK emits while a patch is running, because the
    model is already the source of that value.

    Attaching it to a widget that emits no such signal raises [Invalid_argument] when the
    node is mounted, rather than being silently inert. *)
val on_toggled : (bool -> unit Ui_effect.t) -> t

(** Fires on every edit of a text widget — each keystroke, a paste, an undo — carrying the
    widget's full text afterwards, not the characters that were inserted.

    This is [GtkEditable::changed], which GTK also emits for the library's own writes; the
    patcher's reentrancy guard is what keeps a re-render from feeding itself. Pair it with
    the widget's [~text] argument or the entry is uncontrolled: the model never learns
    what was typed, and the next unrelated re-render puts the old text back.

    Attaching it to a widget that emits no such signal raises [Invalid_argument] when the
    node is mounted or patched, rather than being silently inert. *)
val on_changed : (string -> unit Ui_effect.t) -> t

(** Fires when the user presses Enter in a text entry. Carries nothing: read the text out
    of the model that {!on_changed} has been feeding. *)
val on_activate : unit Ui_effect.t -> t

(** [search_entry] only: GTK's debounced [search-changed], emitted [search_delay] ms after
    typing stops rather than on every keystroke. Use it for "filter as you type" against a
    store; use {!on_changed} when the model owns the text. A search entry that carries
    both fires both — immediately, then again once typing settles. *)
val on_search_changed : (string -> unit Ui_effect.t) -> t

(** Fires when a [scale]'s or [spin_button]'s value changes, carrying the value the widget
    now holds — read back off the widget, so it is GTK's own clamped and rounded number
    rather than whatever a drag notionally aimed at.

    As with the toggles, only user-driven changes reach the handler: the value a patch
    writes is emitted inside the patcher's reentrancy guard and dropped there, because the
    model is already the source of it.

    Both widgets' values are {i controlled} (spec §6.5), so a scale or spin button that
    carries no [on_value_changed] — or whose model ignores it — snaps back to the model's
    value on the next render. Attaching it to a widget that emits no such signal raises
    [Invalid_argument] when the node is mounted or patched. *)
val on_value_changed : (float -> unit Ui_effect.t) -> t

(** Fires when the user opens or closes an [expander], carrying its new state.

    This is [notify::expanded] rather than [GtkExpander::activate], which fires {i before}
    the property settles and so would hand the handler the old value (spec 6.4).

    [expanded] is {i controlled} on the same rule as the toggles' [active], so an expander
    whose model never learns it was opened snaps shut on the next unrelated re-render.
    Attaching this to a widget that emits no such signal raises [Invalid_argument] when
    the node is mounted or patched. *)
val on_expanded_changed : (bool -> unit Ui_effect.t) -> t

(** Fires when a [revealer]'s {i animation} finishes, carrying whether the child ended up
    revealed. This is what to hang "now that it has slid away, drop it from the model" on;
    the [reveal] argument itself is the input, not the outcome.

    It connects [notify::child-revealed]: [child-revealed] is a read-only property that
    flips when the transition completes, unlike [reveal-child], which moves the instant
    the animation is asked to start. A revealer with no transition settles both at once.

    Unlike the other event attrs here, this one is not the write-back half of a controlled
    prop -- [reveal] is controlled against [reveal-child], which the user cannot move on
    their own. It is a notification, and a revealer that carries none is not broken. *)
val on_revealed : (bool -> unit Ui_effect.t) -> t

val many : t list -> t
val empty : t
