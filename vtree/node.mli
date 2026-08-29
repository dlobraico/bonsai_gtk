open! Core

type t =
  { kind : Kind.t
  ; key : Key.t option [@sexp.option]
  ; attrs : Attrs.t
  ; children : t Children.t
  }
[@@deriving sexp_of]

(** A [GtkLabel]. Every optional property defaults to GTK's own default, so a label built
    from text alone is a plain [GtkLabel].

    [xalign] is horizontal alignment of the text {i within} the label's allocation ([0.]
    left, [0.5] centred, [1.] right) — distinct from [Attr.halign], which places the label
    within its parent. [ellipsize] absent means "do not ellipsize". [max_width_chars] and
    [width_chars] are [-1] for "no request". [use_markup] parses the text as Pango markup;
    malformed markup is GTK's problem — it logs and shows the raw string. *)
val label
  :  ?key:Key.t
  -> ?attrs:Attr.t list
  -> ?wrap:bool
  -> ?xalign:float
  -> ?ellipsize:Ellipsize.t
  -> ?max_width_chars:int
  -> ?width_chars:int
  -> ?selectable:bool
  -> ?use_markup:bool
  -> string
  -> t

(** A [GtkButton]. [label], [icon_name] and [child] are alternatives: giving more than one
    is a GTK warning, and the last one GTK applies wins. [has_frame:false] is the
    flat/ghost button stavekeeper spells [stk-btn-ghost].

    An icon is set but never cleared — [Button.set_icon_name] takes a plain [string], so
    there is no "no icon" value to write. Going from an icon back to text is expressed by
    setting [label], which replaces the icon child. *)
val button
  :  ?key:Key.t
  -> ?attrs:Attr.t list
  -> ?label:string
  -> ?icon_name:string
  -> ?has_frame:bool
  -> ?child:t
  -> unit
  -> t

(** A [GtkToggleButton]: a {!button} that stays pressed in.

    [active] is {i controlled}: the widget is written only when the model's value differs
    from what the widget currently shows, so a model that ignores {!Attr.on_toggled} pins
    the widget rather than fighting the user. Pair it with {!Attr.on_toggled} or the
    control is inert.

    Radio groups ([Toggle_button.set_group]) are deliberately absent: a group is a
    reference to a {i sibling widget}, which the vtree cannot name. Model "which of these
    is chosen" in Bonsai state and render N toggle buttons instead. *)
val toggle_button
  :  ?key:Key.t
  -> ?attrs:Attr.t list
  -> ?label:string
  -> ?icon_name:string
  -> ?has_frame:bool
  -> ?child:t
  -> active:bool
  -> unit
  -> t

(** A [GtkCheckButton].

    [active] is controlled on the same rule as {!toggle_button}'s, and wants an
    {!Attr.on_toggled} for the same reason. [inconsistent] renders the third, "mixed"
    state; it is purely visual and GTK does not clear it when the user clicks, so a model
    that uses it has to.

    There is no [?child]: GTK allows one, but a check button carrying both a label and a
    child is a GTK warning, and [?label] covers every real use.

    Radio groups ([Check_button.set_group]) are out of scope for the same reason as
    {!toggle_button}'s. *)
val check_button
  :  ?key:Key.t
  -> ?attrs:Attr.t list
  -> ?label:string
  -> ?inconsistent:bool
  -> active:bool
  -> unit
  -> t

(** A [GtkSwitch].

    [active] is controlled on the same rule as {!toggle_button}'s, and wants an
    {!Attr.on_toggled} for the same reason.

    GTK's [state-set] signal is deliberately not exposed. Its callback returns a [bool]:
    returning [true] means "handled", which suppresses GTK's own update of the switch's
    [state] and leaves it out of step with [active] — the pending look a switch shows
    while an asynchronous confirmation is outstanding. bonsai_gtk has no such confirmation
    step, so it keeps the two equal and reports changes through [notify::active] instead,
    which is what {!Attr.on_toggled} connects. *)
val switch : ?key:Key.t -> ?attrs:Attr.t list -> active:bool -> unit -> t

val box
  :  ?key:Key.t
  -> ?attrs:Attr.t list
  -> ?spacing:int
  -> ?homogeneous:bool
  -> orientation:Orientation.t
  -> t list
  -> t

val window
  :  ?key:Key.t
  -> ?attrs:Attr.t list
  -> ?title:string
  -> ?default_size:int * int
  -> t
  -> t

val native : ?key:Key.t -> ?attrs:Attr.t list -> Native.t -> t

(** Depth-first search for a node whose attrs carry [Test_id id]. *)
val find_by_test_id : t -> string -> t option
