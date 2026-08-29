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

(** A [GtkEntry], the plain single-line text field.

    [text] is {i controlled}, and required for that reason: on every patch the widget is
    written only when the model's text differs from what the widget currently shows — not
    from what the previous node said, which is stale the moment the user types. A model
    that echoes what was typed causes no write and so no caret jump; a model that rewrites
    it (uppercasing, clamping, rejecting) still wins, and the caret is put back where it
    was. There is no uncontrolled mode: an entry whose text no [Attr.on_changed] feeds
    back into the model resets to the model's value the next time anything re-renders,
    which is the bug the required argument exists to make impossible to write by accident.

    [placeholder] is the grey prompt shown while the entry is empty. [visibility:false] is
    password-style masking — prefer {!password_entry}, which is the accessible widget for
    that. [editable:false] keeps the text selectable but read-only. [width_chars] and
    [max_width_chars] are size requests in characters ([-1] for none); [xalign] positions
    the text within the entry when it is shorter than the widget ([0.] left, [1.] right).
    [activates_default:true] makes Enter activate the window's default widget instead of
    only emitting [Attr.on_activate].

    Not exposed: [GtkEntry]'s icon API ([set_icon_from_icon_name] and friends), whose
    [icon-press]/[icon-release] signals carry a [GtkEntryIconPosition] and so make a
    per-icon handler story better designed alongside M3's action routing; and
    [GtkEditable::insert-text], which ocgtk does not bind (it has an in-out [int] position
    parameter). *)
val entry
  :  ?key:Key.t
  -> ?attrs:Attr.t list
  -> ?placeholder:string
  -> ?editable:bool
  -> ?visibility:bool
  -> ?width_chars:int
  -> ?max_width_chars:int
  -> ?xalign:float
  -> ?activates_default:bool
  -> text:string
  -> unit
  -> t

(** A [GtkPasswordEntry]: the masked field, with the accessibility and input-method hints
    that {!entry} with [visibility:false] does not carry.

    [text] is controlled on the same rule as {!entry}'s, and required for the same reason.
    [show_peek_icon] is the eye icon that reveals the text while held; it defaults to
    GTK's own [true]. *)
val password_entry
  :  ?key:Key.t
  -> ?attrs:Attr.t list
  -> ?placeholder:string
  -> ?show_peek_icon:bool
  -> ?activates_default:bool
  -> text:string
  -> unit
  -> t

(** A [GtkSearchEntry]: an {!entry} with the magnifier and clear icons, and a debounced
    signal.

    [text] is controlled on the same rule as {!entry}'s. Both change signals are available
    and a search entry may carry either or both: {!Attr.on_changed} fires immediately on
    every keystroke and is what a model that owns the text wants, while
    {!Attr.on_search_changed} fires [search_delay] ms after typing stops and is what a
    filter-as-you-type query against a store wants. [search_delay] left absent keeps GTK's
    own (150 ms).

    [set_key_capture_widget] — which makes typing anywhere in a window focus the search
    box — is deliberately absent: it names another {i live widget}, which a virtual tree
    cannot. {!native} is the escape hatch until a later milestone designs cross-node
    references. *)
val search_entry
  :  ?key:Key.t
  -> ?attrs:Attr.t list
  -> ?placeholder:string
  -> ?search_delay:int
  -> text:string
  -> unit
  -> t

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
