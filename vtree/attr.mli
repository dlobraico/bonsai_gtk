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
  [@@deriving sexp_of, compare, equal]

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
val many : t list -> t
val empty : t
