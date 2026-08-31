open! Core

type t =
  { kind : Kind.t
  ; key : Key.t option [@sexp.option]
  ; attrs : Attrs.t
  ; children : t Children.t
  }
[@@deriving sexp_of]

(** {1 What a constructor's [Invalid_argument] costs}

    Several constructors below reject a node they can prove is wrong — a
    {!scrolled_window} whose minimum content size exceeds its maximum, a {!list_box} child
    with no [~key], a {!level_bar} whose [~min] is above its [~max]. Each of those is a
    mistake no model state can make correct, and rejecting it at the line that made it is
    worth far more than a GTK critical nobody reads.

    {b The cost of getting that judgement wrong is the whole application.} These
    constructors run inside the Bonsai computation, so the exception comes out of
    [Bonsai_gtk.Expert.Driver.frame], which marks the driver broken, abandons the pending
    fixups and re-raises; every frame after it is a no-op and the window never repaints
    again. There is no recovery and no partial render — it is not a widget that fails, it
    is the process's UI.

    So the rule these checks follow, and which a new one should follow:
    {b reject only what no later frame could make valid.} A state a correct model passes
    {i through} — an index that is stale for the one frame between a list shrinking and
    the index being recomputed, a key naming a child that has not been added yet — is not
    rejected here. It is inert while it names nothing, applied on the frame it becomes
    meaningful, and reported once through the patcher's channel so that a model which is
    {i permanently} wrong is not silent. That is Tasks 6–8's ghost-key rule, and
    {!drop_down}'s [~selected] follows it.

    A view that would rather fail loudly than render something odd can still assert
    whatever it likes in its own code; what it cannot do is un-break the driver. *)

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
    was. A write-back is not free when it does happen: GTK replaces the whole text, so the
    caret lands at the end whenever the model shortened it past the old position, the
    selection is dropped, and an input method's in-flight preedit (a half-composed CJK or
    accented character) is disturbed. That is the price of a model that rewrites as you
    type, and the reason the widget is left alone whenever it already agrees. There is no
    uncontrolled mode: an entry whose text no [Attr.on_changed] feeds back into the model
    resets to the model's value the next time anything re-renders.

    {b The required argument does not prevent that, and it is worth being exact about what
      it does prevent.}
    It makes the {i prop} impossible to forget; the {i attr} is still an ordinary
    attribute a caller can leave off, and "the next time anything re-renders" is about
    sixty times a second — [Bonsai_gtk.start]'s scheduler holds a 16 ms tick and
    [Patcher.reassert_only] re-asserts every node on every frame, changed or not. So the
    failure is not a stale value that appears after some later unrelated render: it is
    typing that vanishes as it is typed. Measured, mounting the node and running one
    [reassert_only]: text typed into an [entry], {!password_entry}, {!search_entry} or
    {!editable_label} whose prop is pinned to [""] is [""] again one frame later.
    [examples/gallery.ml] had three of these and none was noticed until somebody typed
    into it, which is the shape of the mistake — it is invisible to every automated test,
    because a test that never types sees a widget agreeing with its model.

    The same holds for every other controlled prop: a {!list_box}'s [~selected] fed only
    by [Attr.on_row_activated] is restored on the next idle frame whenever the selection
    moved without activating (the arrow keys), and a {!search_entry}'s [~text] fed by the
    {i debounced} [Attr.on_search_changed] rather than by [Attr.on_changed] is written
    back over during the debounce window. The rule in one line:
    {b if a prop names something the user can change, the attr that reports that change
      must write the state the prop reads}
    — the same attr, not a related one.

    [placeholder] is the grey prompt shown while the entry is empty. [visibility:false] is
    password-style masking — prefer {!password_entry}, which is the accessible widget for
    that. [editable:false] keeps the text selectable but read-only. [width_chars] and
    [max_width_chars] are size requests in characters ([-1] for none); [xalign] positions
    the text within the entry when it is shorter than the widget ([0.] left, [1.] right).
    [activates_default:true] makes Enter activate the window's default widget instead of
    only emitting [Attr.on_activate].

    [max_length] is the number of characters (not bytes) the widget will accept, [0]
    (GTK's own) for no limit. Unlike [text] it is {i not} controlled: it constrains what
    the user can put in the widget rather than naming a value the model owns, so it is
    written when it changes and left alone otherwise. It is a [GtkEntry] property, so
    {!password_entry} and {!search_entry} do not have it -- neither is a [GtkEntry]
    subclass in GTK4 and [GtkEditable] has no [set_max_length].

    {b A [text] longer than [max_length] is an inconsistency in the application, and the
      library tolerates it silently.}
    GTK truncates the widget's contents to [max_length] characters, and nothing tells the
    model: the truncation happens inside the patch, and the patcher's reentrancy guard
    drops every signal GTK emits there, so no [Attr.on_changed] fires. The node keeps the
    value it was rendered with, so the model and the screen disagree until some later
    render or some user edit resolves it — the widget shows the first [max_length]
    characters and the model still holds all of them. The library does not write the text
    again on every subsequent frame (it compares against what the widget can hold, not
    against the full string), so this costs correctness rather than performance. If the
    model must see the truncated value, clamp the text where the model owns it rather than
    relying on the widget.

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
  -> ?max_length:int
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

    {!Attr.on_search_changed} reports only searches the {i user} produced. GTK arms the
    debounce from any text change, this library's own [text] writes included, and the
    emission lands after the patch that made the write is long over — so the runtime
    records what it last wrote and drops the emission that carries it back. Without that,
    a model which rewrites what was typed (uppercasing it, trimming it) or which clears
    the box from elsewhere in the UI would see a search it never performed, once per
    write. The one edit this cannot distinguish is a user who types the box back to
    exactly what the library last wrote, within [search_delay] of the write; that search
    is dropped, and it would have reported the text the model already holds.

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

(** A [GtkTextView]: the multi-line editor, with its text held in a [GtkTextBuffer] the
    view creates and owns.

    [text] is controlled on the same rule as {!entry}'s (spec §6.5): on every patch the
    buffer is written only when what it currently holds differs from the model's text --
    not from the previous node's, which is stale the moment the user types. A model that
    echoes what was typed causes no write; a model that rewrites or refuses it pulls the
    buffer back. It is required for the reason {!entry}'s is: a text view whose text no
    {!Attr.on_changed} feeds back into the model resets to the model's value the next time
    anything re-renders.

    {b The caret is preserved as a character offset, and that is a policy rather than an
      accident.}
    Writing a buffer replaces all of it, which leaves the caret at the end; the offset it
    had is saved across the write and put back. That is exactly right when the model
    echoed what was typed (nothing is written, so nothing moves) and when the model
    rewrote the text in place -- uppercasing it, trimming a trailing space -- because the
    offset still means what it meant. It is {i approximate} when the model changed the
    text's length {i before} the caret: an autocompleter that inserts six characters at
    the start leaves the caret six characters early. When the model shortened the text
    past the old offset GTK clamps to the end, which is the right answer there.

    The alternatives are both worse. Preserving the caret by diffing the old text against
    the new would be a general text diff inside a widget implementation, for a guess that
    is still a guess; preserving nothing would put the caret at the end of the document on
    every write, which makes a note field that echoes as you type unusable. An application
    that needs better owns the caret itself, which M2 does not expose --
    [notify::cursor-position] is the hook, and it is on the backlog.

    {b The selection is not preserved.} Writing the buffer collapses it, and restoring it
    would mean restoring an anchor the model may have invalidated. An application that
    programmatically rewrites text out from under a selection is doing something the user
    will notice however this behaves.

    [wrap] is how lines too wide for the view are broken: {!Wrap_mode.Word_char} is what a
    notes field usually wants and {!Wrap_mode.None_} -- GTK's own default -- is what a
    code field wants. [editable:false] leaves the text selectable and copyable but
    read-only. [monospace:true] asks for the system's fixed-width font. [cursor_visible]
    and [accepts_tab] are both GTK's own [true]; [accepts_tab:false] makes Tab move the
    focus on instead of inserting a tab, which is what a text view inside a form wants.
    The four margins are GTK's, and are padding inside the view rather than margin outside
    it -- {!Attr.margin} is the outside one.

    {b [text] must be valid UTF-8 and must not contain a NUL byte.} A [GtkTextBuffer] can
    hold nothing else, and the two ways of asking it to fail differently and badly: GTK
    empties the buffer and then refuses to insert text that is not valid UTF-8 (so the
    previous contents are lost and a [Gtk-CRITICAL] appears on stderr), and it silently
    stores only the prefix before a NUL. So the library validates first and {i refuses}
    the write: the view keeps what it was showing, and the runtime reports the node's path
    and the reason once — once per offending text, not once per frame. The model is not
    wedged; the next text GTK will take is written normally.

    That matters most where it is least visible. A read-only pane rendering bytes off disk
    — a log tail, a file preview — is both the likeliest source of such text and the one
    place no user edit can ever correct it. Decode at the edge where the bytes enter the
    application rather than relying on the widget.

    There is no [Attr.on_activate]: Enter inserts a newline in a text view rather than
    submitting, and GTK emits nothing for it. {!Attr.on_changed} is the only signal, and
    it is emitted by the {i buffer} rather than by the view -- which is invisible from
    here and is the whole of what a handler receives: the buffer's full text, as of the
    edit.

    Not exposed: the buffer itself (an application that wants to hold one across renders
    is asking for a widget this library does not model), tags and marks, [set_buffer]
    (swapping the buffer would strand the [changed] connection on the old one), and the
    scrolling API -- put a text view in a {!scrolled_window}, which is where a multi-line
    editor belongs. *)
val text_view
  :  ?key:Key.t
  -> ?attrs:Attr.t list
  -> ?wrap:Wrap_mode.t
  -> ?editable:bool
  -> ?monospace:bool
  -> ?cursor_visible:bool
  -> ?accepts_tab:bool
  -> ?left_margin:int
  -> ?right_margin:int
  -> ?top_margin:int
  -> ?bottom_margin:int
  -> text:string
  -> unit
  -> t

(** A [GtkSpinButton]: a numeric field with a pair of steppers.

    [value] is {i controlled}, on the identical rule to {!entry}'s [text] (spec §6.5, and
    the plan's Open Question 2): on every patch the widget is written only when the
    model's value differs from the one the widget currently holds — not from the previous
    node's, which is stale the moment the user spins it. A model that follows the user
    causes no write; a model that clamps or refuses pulls the widget back. Pair it with
    {!Attr.on_value_changed} or the control is inert: a spin button whose model never
    learns what was typed resets to the model's value on the next unrelated re-render.

    [min], [max] and [value] are required for that reason and because an implicit 0–100
    range is a bug generator; every real use names its own. GTK clamps [value] into
    [[min, max]] and rounds it to [digits], so the value read back by
    {!Attr.on_value_changed} — and dumped by the live tree — is GTK's, not necessarily the
    one that was written.

    [step] is the increment one stepper click applies. GTK also needs a {i page}
    increment, for Page Up/Down; it is [step *. 10.] rather than a prop of its own,
    because [new_with_range] has to pick something and no caller has wanted to name it
    separately. [digits] is the number of decimal places shown ([0], whole numbers, is
    GTK's own). [numeric:true] — the default here, though GTK's own is [false] — refuses
    non-numeric keystrokes: a spin button whose text can be arbitrary is a trap.
    [wrap:true] makes the value roll around between the bounds. [activates_default:true]
    makes Enter activate the window's default widget.

    Not exposed: [climb_rate], [snap_to_ticks] and [update_policy] (M2 at the earliest —
    none has a caller), and the adjustment itself, which [new_with_range] builds and every
    prop that touches it is re-derived from the node. *)
val spin_button
  :  ?key:Key.t
  -> ?attrs:Attr.t list
  -> ?digits:int
  -> ?numeric:bool
  -> ?wrap:bool
  -> ?step:float
  -> ?activates_default:bool
  -> min:float
  -> max:float
  -> value:float
  -> unit
  -> t

(** A [GtkScale]: the slider.

    [value] is controlled on the same rule as {!spin_button}'s, and wants an
    {!Attr.on_value_changed} for the same reason. The consequence is worth stating
    plainly: a drag the model declines snaps back, because the alternative — letting the
    widget and the model diverge silently — is the bug §6.5 exists to prevent. (The
    deliberate exception elsewhere in this library is a paned handle's position, which is
    dragged continuously and would be immovable if re-asserted every frame.)

    [step] is the arrow-key increment (the page increment is [step *. 10.], as on
    {!spin_button}). [digits] is the number of decimals shown beside the slider, and GTK
    rounds the value to it — [1] is GTK's own default. [draw_value:false] hides that
    number. [has_origin:false] stops the trough being filled from the bottom/left up to
    the slider. [inverted:true] puts the high end at the top/left.

    Marks ([gtk_scale_add_mark]) are deliberately absent: they are a list-valued property
    with no "remove one" operation — only [clear_marks] — so diffing them means clearing
    and re-adding the whole set on any change. That is implementable and was not worth
    M1's budget; a scale with marks is a {!native} node until it is. *)
val scale
  :  ?key:Key.t
  -> ?attrs:Attr.t list
  -> ?step:float
  -> ?digits:int
  -> ?draw_value:bool
  -> ?has_origin:bool
  -> ?inverted:bool
  -> orientation:Orientation.t
  -> min:float
  -> max:float
  -> value:float
  -> unit
  -> t

(** A [GtkProgressBar]. [fraction] is [0.]–[1.]; GTK clamps anything outside.

    Nothing here is controlled: a progress bar has no user input to decline, so [fraction]
    is an ordinary prop written whenever it changes.

    [show_text:true] prints [text] beside the bar — or, when [text] is absent, the
    percentage. [ellipsize] applies to that text. [inverted:true] fills from the
    right/bottom.

    [gtk_progress_bar_pulse] is deliberately absent: pulsing is a stateful animation the
    widget owns, advanced by repeated calls on a timer, which is not something a
    declarative tree can describe. An indeterminate progress indicator is {!spinner}; a
    pulsing bar is a {!native} node. *)
val progress_bar
  :  ?key:Key.t
  -> ?attrs:Attr.t list
  -> ?text:string
  -> ?show_text:bool
  -> ?inverted:bool
  -> ?ellipsize:Ellipsize.t
  -> fraction:float
  -> unit
  -> t

(** A [GtkSpinner]: the indeterminate "working" indicator. [spinning:false] leaves it in
    the tree, stopped and invisible — use [Attr.visible false] to take it out of the
    layout. *)
val spinner : ?key:Key.t -> ?attrs:Attr.t list -> spinning:bool -> unit -> t

(** A [GtkLevelBar]: a filled bar showing where [~value] sits between [~min] and [~max].

    The other bar, beside {!progress_bar}, and the difference is what it is {i for}. A
    progress bar shows how far along one operation is, in fractions of itself, and can
    pulse when it does not know. A level bar shows a level in the application's own units
    — a disk 43 GB into 512, a battery, a signal strength, four takes recorded out of five
    — and it can draw that level as discrete segments, which is the thing a progress bar
    cannot do at all.

    [~min] and [~max] default to GTK's [0.]–[1.], so a level bar given only a [~value]
    behaves as a fraction and reads exactly like a progress bar's. A [~min] above [~max]
    is [Invalid_argument] from this constructor: GTK keeps both numbers as written and
    clamps the value up to the minimum, so the bar draws full and never moves, with no
    warning anywhere (measured). So is a {i negative} bound, for the opposite reason — GTK
    refuses one with a critical and leaves the range it had, so the bar would go on
    showing the previous scale with only a line on stderr to say why.

    A [~value] outside the range is {i not} rejected, and neither is a negative one. GTK
    clamps a value the {i bounds} move over, which is what a ratio that occasionally
    exceeds 1 wants, and stores a value written directly whatever it is (a bar below its
    minimum draws empty).

    In [~mode:Discrete] the bar is drawn as [max -. min] equal segments and fills whole
    segments only, so the two bounds choose the number of blocks: [~min:0. ~max:5.] is a
    rating out of five, and leaving the default [0.]–[1.] draws a single block that is
    either empty or full. There is no separate segment count.

    [~inverted] fills from the other end (right to left, or top to bottom).

    {b Nothing here is controlled}, because nothing here is an input: a level bar has no
    interaction at all — no drag, no scroll, no keyboard — so GTK never changes [value]
    behind the model's back and there is no signal to carry a change. It is the one widget
    in the library with a value prop and no handler to pair it with, and the asymmetry is
    GTK's rather than an omission. (GTK does emit [offset-changed], for the named offset
    markers that colour a bar's zones; this library exposes no offsets, so it binds no
    handler for them — spec §11.) *)
val level_bar
  :  ?key:Key.t
  -> ?attrs:Attr.t list
  -> ?min:float
  -> ?max:float
  -> ?mode:Level_bar_mode.t
  -> ?inverted:bool
  -> value:float
  -> unit
  -> t

(** A [GtkImage]: an icon, at icon sizes. Its [source] is a closed variant rather than a
    set of optional arguments because GTK's setters do not compose -- [set_from_file]
    after [set_from_icon_name] silently wins, and there is no "which one is set" to diff
    -- so exclusivity is a type error here instead. [Empty] goes through
    [gtk_image_clear], the only call that actually un-sets a source.

    [pixel_size] fixes the icon's size in pixels; [-1], GTK's own, means "derive it from
    [icon_size]". [icon_size] is the theme-level hint ([Inherit] takes it from the
    surrounding context).

    An image is for icons and small decorations, and scales its content to a square. A
    photograph or a rendered page wants {!picture}, which keeps the image's aspect ratio
    and can be told how to fit.

    [set_from_gicon], [set_from_pixbuf] and [set_from_paintable] are deliberately absent:
    a [GIcon], a [GdkPixbuf] and a [GdkPaintable] are all ocgtk values, and the vtree may
    not name those. They belong on the native side, as [Bonsai_gtk.Native.Picture] does
    for paintables. *)
val image
  :  ?key:Key.t
  -> ?attrs:Attr.t list
  -> ?pixel_size:int
  -> ?icon_size:Icon_size.t
  -> Image_source.t
  -> t

(** A [GtkPicture]: an image at its own size and aspect ratio. [source] is a closed
    variant for the same reason as {!image}'s; [Empty] is [set_paintable None], since
    [GtkPicture] has no [clear].

    [content_fit] is how the image is scaled into the allocation ([Contain], GTK's own,
    letterboxes) and [can_shrink] (also GTK's own [true]) is what allows the widget to be
    smaller than its image at all. [alternative_text] is the accessible description, the
    "alt" attribute's equivalent.

    Sizing, which is the part that surprises everyone: [Attr.width_request] and
    [Attr.height_request] raise a picture's {i minimum} size but not its {i natural} one,
    which GTK derives from the image's own pixel dimensions -- so a homogeneous container
    still sizes to the image. To cap the {i allocated} size, put the picture in an
    [Overlay] as an unmeasured overlay ([Attr.measure_overlay false]) over a spacer sized
    with [width_request]/[height_request], and use
    [~can_shrink:true ~content_fit:Contain].

    A paintable source -- a texture the application rendered itself -- is not expressible
    here, because the vtree may not name ocgtk types. Use [Bonsai_gtk.Native.Picture]. *)
val picture
  :  ?key:Key.t
  -> ?attrs:Attr.t list
  -> ?content_fit:Content_fit.t
  -> ?can_shrink:bool
  -> ?alternative_text:string
  -> Picture_source.t
  -> t

(** A [GtkSeparator]: the rule between things. [orientation] is the whole of it -- a
    [Horizontal] separator is a horizontal line, drawn across a vertical stack. *)
val separator : ?key:Key.t -> ?attrs:Attr.t list -> orientation:Orientation.t -> unit -> t

(** A [GtkScrolledWindow]: a viewport onto a child too big for the space it is given.

    [hpolicy] and [vpolicy] say when each scrollbar appears. The two are set through one
    GTK call, so changing either rewrites both. [Never] means "no scrollbar, and the
    content dictates the size" -- the child's full natural size is requested, which is
    what you want for a vertically scrolling list whose width should still fit its rows
    ([~hpolicy:Never ~vpolicy:Automatic]). [External_] means "no scrollbar, and do not let
    the content dictate the size either", which is how a widget is clipped to whatever
    space it is given.

    [min_content_width]/[min_content_height] are the size the viewport keeps visible
    ([-1], GTK's own, for none); [max_content_width]/[max_content_height] cap how far it
    grows before it starts scrolling. [propagate_natural_width]/[..._height] let the
    child's natural size through to the scrolled window's own request -- the pairing that
    makes a scroller size itself to its content up to the maximum.

    [has_frame] draws a border around the contents. [kinetic_scrolling] (GTK's own [true])
    is touchscreen flick-and-glide. [overlay_scrolling] (also [true]) is the thin
    scrollbar that floats over the content instead of taking layout space.

    Scroll {i position} is deliberately not a prop. It lives on the two adjustments, moves
    continuously while the user scrolls, and a controlled version would fight every scroll
    event -- the same reason a paned handle's position is not controlled. Preserving a
    position across re-renders is what {!Key.t} is for: keep the node's identity and GTK
    keeps its adjustments. Scrolling {i to} somewhere is an imperative action, and belongs
    with M3's effects rather than in a tree.

    [edge-reached] and [edge-overshot] -- the signals an infinite list hangs its "load
    more" on -- are left to M2, alongside [ListBox]. The adjustments themselves, and
    [placement], are not exposed; a scroller that needs them is a {!native} node.

    @raise Invalid_argument
      if [min_content_width] is above [max_content_width], or [min_content_height] above
      [max_content_height]. This is the one constructor in this module that raises: GTK
      calls the pair a programming error and has no runtime check of its own, so the
      viewport silently sizes itself to whichever bound the layout reaches first and the
      mistake surfaces as a layout bug a long way from the call that caused it. [-1] is
      "no bound" on either side and never conflicts; equal bounds are a fixed size. *)
val scrolled_window
  :  ?key:Key.t
  -> ?attrs:Attr.t list
  -> ?hpolicy:Policy.t
  -> ?vpolicy:Policy.t
  -> ?min_content_width:int
  -> ?min_content_height:int
  -> ?max_content_width:int
  -> ?max_content_height:int
  -> ?propagate_natural_width:bool
  -> ?propagate_natural_height:bool
  -> ?has_frame:bool
  -> ?kinetic_scrolling:bool
  -> ?overlay_scrolling:bool
  -> t
  -> t

(** A [GtkFrame]: a border around one child, optionally titled.

    [label] is the title GTK embeds in the top edge; absent means an untitled border.
    [label_align] positions it along that edge ([0.], GTK's own, is at the start).

    [set_label_widget] -- an arbitrary widget as the frame's title, rather than a string
    -- is deliberately not exposed: it is a second child slot, which the children
    machinery could express, but no caller wants one. A frame with a widget for a title is
    a {!native} node. *)
val frame
  :  ?key:Key.t
  -> ?attrs:Attr.t list
  -> ?label:string
  -> ?label_align:float
  -> t
  -> t

(** A [GtkExpander]: a disclosure triangle that shows or hides its child.

    [expanded] is {i controlled} on the same rule as {!toggle_button}'s [active] (spec
    6.5): on every patch the widget is written only when the model's value differs from
    the one the widget currently shows, so a model that declines the user's click pins the
    expander rather than letting the two diverge. It is required for that reason, and
    wants an {!Attr.on_expanded_changed} or the control is inert -- an expander whose
    model never learns it was opened snaps shut on the next unrelated re-render.

    [label] is the text beside the triangle and [use_markup] parses it as Pango markup.
    [set_label_widget] is not exposed, for the reason {!frame}'s is not.

    The child is built and mounted whether or not the expander is open -- GTK hides it, it
    does not drop it. An expensive subtree that should not exist while collapsed is
    something the model expresses, by rendering a placeholder until [expanded] is true. *)
val expander
  :  ?key:Key.t
  -> ?attrs:Attr.t list
  -> ?label:string
  -> ?use_markup:bool
  -> expanded:bool
  -> t
  -> t

(** A [GtkRevealer]: a container that animates its child in and out.

    [reveal] is controlled on the same rule as {!expander}'s [expanded], though it is the
    gentler case: nothing the user does moves it, so the re-assertion only ever corrects
    the library's own writes. It is compared against GTK's [reveal-child] -- the input
    property, which moves the moment an animation is asked to start -- and not against
    [child-revealed], which is the outcome and does not settle until the animation ends.

    [transition] and [transition_duration] (250 ms, GTK's own) describe that animation.
    {!Attr.on_revealed} fires when it finishes, which is the moment a hidden subtree can
    be dropped from the model.

    A revealer whose child is expensive still builds it: like {!expander}, concealing is
    GTK's job and pruning is the model's. And note that a test which dumps the tree
    immediately after flipping [reveal] should use [~transition:None_], or it races the
    animation. *)
val revealer
  :  ?key:Key.t
  -> ?attrs:Attr.t list
  -> ?transition:Reveal_transition.t
  -> ?transition_duration:int
  -> reveal:bool
  -> t
  -> t

val box
  :  ?key:Key.t
  -> ?attrs:Attr.t list
  -> ?spacing:int
  -> ?homogeneous:bool
  -> orientation:Orientation.t
  -> t list
  -> t

(** A [GtkGrid]: children placed by {i coordinates} rather than by order.

    Every child needs an {!Attr.grid_cell}; a child without one is [Invalid_argument] at
    mount, naming its path. There is no default cell -- defaulting to (0,0) would stack
    the whole grid in one place and read as a layout bug rather than as the missing
    attribute it is.

    Child {i order} carries no meaning here: the cell is the placement, so reordering the
    list without changing the cells does not touch GTK (the reconciler's [Move] ops are
    dropped). {!Key.t} still governs identity, which is what preserves a cell's widget --
    and its focus, and its entry text -- across a re-render. A child whose cell changes is
    detached and re-attached at the new coordinates, because GTK has no "move an attached
    child"; it is the same widget afterwards.

    The spacings ([0]) are the gaps between rows and columns in pixels; the homogeneous
    flags ([false]) make every row the same height or every column the same width. Row
    baselines ([gtk_grid_set_row_baseline_position]) are not exposed; a grid that needs
    them is a {!native} node. *)
val grid
  :  ?key:Key.t
  -> ?attrs:Attr.t list
  -> ?row_spacing:int
  -> ?column_spacing:int
  -> ?row_homogeneous:bool
  -> ?column_homogeneous:bool
  -> t list
  -> t

(** A [GtkStack]: one child visible at a time, selected by name.

    Every child needs a [~key]: it is the GTK page name, it is what [~visible_child]
    selects by, and it is what preserves a page's widgets across a re-render. A child
    without one is [Invalid_argument] {i from this constructor}, naming the child's index.

    Child {i order} is not reconciled: GTK offers no way to insert a page at a position or
    to reorder pages, so pages land in the order they are first added and reordering the
    list does nothing (M1 ruling 4, as for {!overlay}). Order only affects the button
    order in a {!stack_switcher}; identity and selection are entirely by key.

    [~name] is how a {!stack_switcher} or {!stack_sidebar} elsewhere in the tree finds
    this stack. Two stacks with the same name in one tree is [Invalid_argument].

    [~visible_child] is {i controlled} (spec §6.5): it is compared against the page the
    widget is actually showing, so a user who clicked a switcher button the model then
    ignored is put back. It is applied once the whole tree exists rather than while the
    stack is being built -- a page GTK does not have yet cannot be selected -- so a test
    driving the patcher by hand must call [Patcher.run_fixups] before reading the
    selection back. Pair it with {!Attr.on_visible_child_changed} or the control is inert.

    {b The rule the three keyed containers share}:
    {i a container that shows exactly one of its children raises when told to show one
      that does not exist; a container with a plural selection ignores the keys it cannot
      find.}
    {!stack} and {!notebook} are the first half, {!list_box} and {!flow_box} the second.

    {b Naming a page this stack does not have is [Invalid_argument]}, raised from that
    same fixup pass and carrying the stack's node path and the page names it does have.
    This is deliberately {i unlike} the [~selected] of {!list_box} and {!flow_box}, where
    a key naming no child is {i inert} -- not merely tolerated: it is dropped before the
    model's selection is compared with the widget's, so holding one provokes no write, and
    the child is selected on the frame it arrives if it ever does. A stack shows exactly
    one page, so a name that never resolves is a typo with no other symptom, while a
    selection is plural and a model that keeps a selected id across a filter change is
    doing something reasonable. Both asymmetries are documented on both constructors; do
    not "fix" one of them. The fixup pass is the earliest point at which the mistake is
    knowable: it runs after the whole tree exists, so every page {i this frame renders} is
    already added, and a name absent there is absent from the rendered tree rather than
    merely not added yet. A page that arrives on a {i later} frame is therefore not the
    case being rejected — but a page that arrives later than the frame naming it is, so a
    [~visible_child] fed by state that can lag the page list by a frame (closing a tab,
    where one effect rewrites the list and another the selection) must render the two
    together. It stops the driver for good, like any exception from a frame.

    The one exception is a stack with {b no pages at all}, which is left alone:
    [~visible_child] is a required argument, so a model rendering an empty page list has
    no name it could pass that would be right, and the frame that adds the first page
    selects it.

    {b A page carrying [Attr.visible false] cannot be shown}, which is the other way to
    make [~visible_child] unable to land — and unlike a name that resolves to nothing,
    this one is silent. [gtk_stack_set_visible_child_full] ends with
    [if (gtk_widget_get_visible (child_info->widget)) set_visible_child (...)]: no [else],
    no warning. So the name resolves and nothing is raised, the write is made and nothing
    happens, [get_visible_child_name] goes on answering with the page that really is
    showing, the comparison is unequal again next frame, and the write is repeated forever
    with no diagnostic. The stack shows the previous page while the model believes it
    navigated. A wizard step or a detail pane hidden behind [Attr.visible] while it loads,
    and named as [~visible_child] on the same frame, is the shape that reaches it: make
    the page visible on the frame that selects it.

    {!notebook}'s [~current_page] has the identical divergence for a different GTK reason
    and says so. Both are on the backlog for the [Patcher.ctx.report] hook {!text_view}
    and {!drop_down} already use: a write that can never land ought to say so once rather
    than be repeated in silence.

    [~transition] ([None_]) and [~transition_duration] (200 ms, GTK's own) describe the
    animation between pages; a test that dumps the tree straight after a selection change
    should keep [None_] or it races it. [~hhomogeneous] and [~vhomogeneous] (both [true],
    GTK's own) make the stack request the size of its largest page in that direction, so
    it does not resize as pages change. *)
val stack
  :  ?key:Key.t
  -> ?attrs:Attr.t list
  -> ?transition:Stack_transition.t
  -> ?transition_duration:int
  -> ?hhomogeneous:bool
  -> ?vhomogeneous:bool
  -> name:string
  -> visible_child:string
  -> t list
  -> t

(** A [GtkListBox]: a vertical list of rows, each of which can be selected, activated, or
    both.

    Children are ordinary nodes -- a label, a box of a check button and two labels -- and
    the implementation wraps each one in a [GtkListBoxRow] it owns. There is no
    [Node.list_box_row] to remember to use, and the settings that belong to the wrapper
    ride on the child node's attrs instead: {!Attr.row_selectable} and
    {!Attr.row_activatable}, both read by the list box exactly as {!Attr.page_title} is
    read by a {!stack}. A header row is a child carrying both as [false].

    {b Every child needs a [~key]}, and a child without one is [Invalid_argument] from
    this constructor, naming the child's index. The key is the row's identity: it is what
    [~selected] names, it is what {!Attr.on_row_activated} and
    {!Attr.on_selected_rows_changed} hand back, and it is what preserves a row's widgets
    (and its GObject) across a re-render. There is nothing else a handler could be given
    -- GTK offers the row widget, which the application has never seen, and an index that
    moves. Rows without a natural id get a synthetic one (["header-instruments"]).

    Row {i order} is reconciled: [GtkListBox] has no reorder primitive, so a moved row is
    removed and re-inserted, which preserves its widgets and its identity. A [remove] can
    drop the selection; the selection is re-applied after every pass, so it comes back.

    [~selected] is {i controlled} (spec §6.5): it is compared against the rows the widget
    actually has selected, so a user who clicked a row the model then ignored is put back.
    It is applied once the whole tree exists rather than while the list is being built --
    a row GTK does not have yet cannot be selected, which is exactly the frame that adds a
    row and selects it -- so a test driving the patcher by hand must call
    [Patcher.run_fixups] before reading the selection back. Pair it with
    {!Attr.on_row_activated} or {!Attr.on_selected_rows_changed}, or the control is inert.

    {b The rule the three keyed containers share}:
    {i a container that shows exactly one of its children raises when told to show one
      that does not exist; a container with a plural selection ignores the keys it cannot
      find.}
    {!stack} and {!notebook} are the first half, {!list_box} and {!flow_box} the second.

    {b A key in [~selected] that no row carries is inert}, not an error -- and inert in
    the strong sense: it is dropped before the model's selection is compared with the
    widget's, so holding one provokes no write. If the row later arrives, it is selected
    {i on the frame it arrives}, without the model having to change its mind; that is the
    same-frame rule that makes this a post-pass fixup rather than a [reassert].

    A selection is plural, and a model that holds a selected id through a filter change is
    doing something reasonable -- the row comes back when the filter does. Selecting
    nothing is a legitimate state; selecting a row that is not there is not expressible.
    This is deliberately {i unlike} {!stack}'s [~visible_child], which raises; both
    asymmetries are documented on both constructors.

    [~selection_mode] and [~selected] can disagree, and {b GTK arbitrates}: three keys
    handed to a [Single] list box leaves whichever one GTK kept, and any key at all handed
    to a [None_] one leaves nothing selected. Nothing is clamped here -- what was asked
    for is written, and what GTK kept is what the next frame compares against. The cost of
    asking for something the mode cannot hold is that the comparison differs on every
    frame and the selection is rewritten on every frame; it is not a loop and not an
    error, but it is a model that should be brought into line with its mode.

    [~selection_mode] ([Single]), [~activate_on_single_click] ([true]) and
    [~show_separators] ([false]) are GTK's own defaults -- note that the first two are not
    the "off" value they look like. [?placeholder] is the node GTK shows in place of an
    empty list; it is not a row, needs no key, and is patched like any other child.

    Sorting, filtering and headers stay in the model: ocgtk binds none of [GtkListBox]'s
    callback-taking methods ([set_sort_func], [set_filter_func], [set_header_func],
    [bind_model]), so the row list this constructor is handed is the row list GTK shows,
    in that order. *)
val list_box
  :  ?key:Key.t
  -> ?attrs:Attr.t list
  -> ?selection_mode:Selection_mode.t
  -> ?activate_on_single_click:bool
  -> ?show_separators:bool
  -> ?placeholder:t
  -> selected:Key.t list
  -> t list
  -> t

(** A [GtkFlowBox]: a grid of children that reflows to the available width, each of which
    can be selected, activated, or both. The same machinery as a {!list_box} over a
    different GTK widget — keyed children, auto-wrapping, a controlled selection — with
    the geometry of a grid in place of a list's separators.

    Children are ordinary nodes and the implementation wraps each one in a
    [GtkFlowBoxChild] it owns; there is no [Node.flow_box_child]. Unlike a list box's rows
    there are {b no per-child attrs to go with them}: [GtkFlowBoxChild] has neither
    [selectable] nor [activatable] (its whole surface is a child, an index, and whether it
    is selected), so a flow box holds nothing on behalf of an individual child and
    {!Attr.row_selectable} on one of these children is rejected like any other misplaced
    placement attr. A card that should not be selectable is one the model does not put in
    the grid.

    {b Every child needs a [~key]}, and a child without one is [Invalid_argument] from
    this constructor, naming the child's index. The key is the card's identity: it is what
    [~selected] names, it is what {!Attr.on_child_activated} and
    {!Attr.on_selected_children_changed} hand back, and it is what preserves a card's
    widgets across a re-render. GTK offers a [GtkFlowBoxChild] the application has never
    seen and an index that moves whenever the grid does, which is why an application
    written against GTK directly keeps an array of cards beside the flow box and looks up
    by index.

    Child {i order} is reconciled: [GtkFlowBox] has no reorder primitive, so a moved child
    is removed and re-inserted, which preserves its widgets and its identity.

    [~selected] is {i controlled}, on exactly {!list_box}'s rules, and every paragraph
    there applies here: it is compared against the widget rather than against the previous
    node, so a click the model declines is put back; it is applied from the fixup pass
    once the whole tree exists, so a test driving the patcher by hand must call
    [Patcher.run_fixups] before reading it back; a key naming no child is {b inert}, not
    an error — dropped before the comparison, so holding one provokes no write — and the
    child is selected {i on the frame it arrives} if it ever does; and [~selection_mode]
    and [~selected] can disagree, with GTK arbitrating and nothing clamped here. Pair it
    with {!Attr.on_child_activated} or {!Attr.on_selected_children_changed}, or the
    control is inert.

    Removing a selected child is worth one sentence of its own, because the imperative
    version of this screen has a crash comment about it: GTK drops the child from its
    selection and emits [selected-children-changed] while doing so, so an application
    holding the selected {i widget} in a ref is holding a widget that is about to be
    destroyed. Here the selection is re-derived from the widget on the next pass and the
    model's answer is put back, so the divergence lasts less than a frame and nothing
    reads it in between.

    [~activate_on_single_click] defaults to GTK's [true], and a grid of cards usually
    wants [false]: with [false] a single click selects and a double click (or Enter)
    activates, which is what lets one grid drive both a selection-dependent toolbar and an
    "open this" action. stavekeeper's library grid sets it to [false] for exactly that.

    [~selection_mode] ([Single]), [~min_children_per_line] ([0]), [~row_spacing] and
    [~column_spacing] ([0]), [~homogeneous] ([false]) and [~orientation] ([Horizontal])
    are GTK's own. So is [~max_children_per_line], whose default is a real {b 7} rather
    than "unlimited" — a grid that never mentions it lays out seven per line however wide
    the window is, which is a surprise worth having in one place. It must be at least 1
    ([gtk_flow_box_set_max_children_per_line] refuses 0 with a critical and keeps the old
    value), and none of the four numbers may be negative: they are unsigned in C, so a
    negative arrives as a very large positive one and nothing complains. Both are
    [Invalid_argument] from this constructor.

    A [~min_children_per_line] {i above} the maximum is {b not} rejected, unlike the pair
    {!scrolled_window} checks. GTK resolves it deterministically and in the caller's
    favour -- the maximum wins, so [~min:6 ~max:3] lays out three per line, exactly as
    [~min:0 ~max:3] does (measured) -- and the arrangement that produces it is a
    reasonable one: a view that switches to a list by setting [~max_children_per_line:1]
    while leaving a minimum from the grid view behind gets its list. Rejecting it would
    turn a working pattern into an exception for the sake of tidiness.

    The geometry props are ordinary props, which is the point: switching one grid between
    a grid view and a list view is [~max_children_per_line:1 ~homogeneous:true] and two
    spacings in the next render — one diff, applied in one batch — rather than five
    setters and a CSS-class toggle.

    Sorting and filtering stay in the model, as for a {!list_box}: ocgtk binds none of
    [GtkFlowBox]'s callback-taking methods ([set_sort_func], [set_filter_func],
    [bind_model]), so the child list this constructor is handed is the child list GTK
    shows, in that order. *)
val flow_box
  :  ?key:Key.t
  -> ?attrs:Attr.t list
  -> ?selection_mode:Selection_mode.t
  -> ?activate_on_single_click:bool
  -> ?min_children_per_line:int
  -> ?max_children_per_line:int
  -> ?row_spacing:int
  -> ?column_spacing:int
  -> ?homogeneous:bool
  -> ?orientation:Orientation.t
  -> selected:Key.t list
  -> t list
  -> t

(** A [GtkNotebook]: pages behind a row of tabs, one of which is showing.

    The third keyed container, and
    {b the only one in this library whose children really move}. [GtkNotebook] has
    [gtk_notebook_reorder_child], so this node is {i ordered}: a page that changes
    position in the child list is reordered in place, keeping its widgets, its GObject and
    whatever state they hold. A {!stack}, a {!list_box} and a {!flow_box} either have no
    reorder primitive at all or reach one by removing and re-inserting; this one has the
    real thing.

    Children are ordinary nodes and there is no wrapper: a notebook's pages {i are} its
    children's widgets, which is why this is the one keyed container that interposes
    nothing. What it does interpose is a tab label, and that is a widget GTK builds and
    owns from {!Attr.tab_label} -- a [string] on the page node, not a node of its own; see
    that attr for why.

    {b Every page needs a [~key]}, and a page without one is [Invalid_argument] from this
    constructor, naming the page's index. The key is the page's identity: it is what
    [~current_page] names, it is what {!Attr.on_page_changed} hands back, and it is what
    preserves a page's widgets across a re-render. GTK offers a page {i number} that moves
    whenever a page is added, removed or dragged, and every operation on a notebook is by
    that number -- which is why an application written against GTK directly keeps an array
    beside it.

    [~current_page] is {i controlled} (spec §6.5): it is compared against the page the
    widget is actually showing rather than against the previous node, so a user who
    clicked a tab the model then declined is put back. It is applied from the fixup pass
    once the whole tree exists -- a page GTK does not have yet cannot be shown, which is
    exactly the frame that adds a page and switches to it -- so a test driving the patcher
    by hand must call [Patcher.run_fixups] before reading it back. Pair it with
    {!Attr.on_page_changed} or the control is inert.

    {b Naming a page this notebook does not have is [Invalid_argument]}, raised from that
    same fixup pass and carrying the notebook's node path and the page keys it does have.

    {b The rule the three keyed containers share}:
    {i a container that shows exactly one of its children raises when told to show one
      that does not exist; a container with a plural selection ignores the keys it cannot
      find.}
    {!stack} and {!notebook} are the first half, {!list_box} and {!flow_box} the second.

    The case to watch for is a model that removes the current page without moving its
    selection: GTK picks a neighbour, the model still names the page that left, and the
    next fixup raises. That is deliberate -- the alternative is a notebook showing one
    page while the model believes another, on every frame, with no diagnostic -- and the
    fix is to render the two together, since a state that can lag the page list by a frame
    is the same mistake {!stack} documents.

    The one exception is a notebook with {b no pages at all}, which is left alone:
    [~current_page] is a required argument, so a model rendering an empty page list has no
    key it could pass that would be right, and the frame that adds the first page shows
    it.

    A page carrying [Attr.visible false] is the other way to make [~current_page] unable
    to land: {b GTK refuses to switch to a page whose child is hidden} (measured -- it
    emits [switch-page] and then leaves [get_current_page] where it was). Nothing is
    clamped here, so the comparison differs on every frame and the write is repeated on
    every frame; it is not a loop and not an error, but it is a model to bring into line
    the way a [~selected] that its {!list_box}'s mode cannot hold is.

    [~scrollable] ([false]), [~show_tabs] ([true]), [~show_border] ([true]) and [~tab_pos]
    ([Top]) are GTK's own, and unlike the other keyed containers' none of them is a value
    a reader guesses wrong. [~show_tabs:false] with a {!stack_switcher}-style header of
    your own is how a notebook is usually dressed up; a notebook whose tabs need icons or
    close buttons is a {!box} of buttons above a {!stack} instead, which is what modern
    GTK applications use.

    Tab reordering {i by the user} (drag and drop) is deliberately not exposed:
    [set_tab_reorderable] would let GTK change the page order behind the model's back, and
    the next render would put it straight back. Reordering is the model's, through the
    child list. *)
val notebook
  :  ?key:Key.t
  -> ?attrs:Attr.t list
  -> ?scrollable:bool
  -> ?show_tabs:bool
  -> ?show_border:bool
  -> ?tab_pos:Tab_position.t
  -> current_page:Key.t
  -> t list
  -> t

(** A [GtkDropDown]: a button that opens a list of strings and shows the chosen one.

    [~items] is the whole list and [~selected] is a position into it, with [-1] for
    nothing selected. Pair it with {!Attr.on_selected_changed}, or the control is inert.

    {b The items are props, not children}, and every difference between this widget and
    the three keyed containers follows from that. There is no [~key] on an item and no
    node for one: GTK holds them as strings in a list model of its own, so the only name
    an item has is its position. That is also why {!Attr.on_selected_changed} carries an
    index — the handler already holds the list it indexes into.

    It is {i not}, however, why an out-of-range [~selected] would be rejected here — and
    it is not. Only a [~selected] below [-1] raises, because no list of items could make
    that number valid. An index {i past the end} is a state a correct model passes
    through: [~items] and [~selected] come from different Bonsai state in any real view (a
    list from a query, an index from the user's picks), so deleting the last row leaves
    the index stale for one frame, and raising on that frame would end the application
    rather than report anything — see "What a constructor's [Invalid_argument] costs" at
    the top of this file.

    So an out-of-range index gets the ghost-key treatment {!list_box}'s [~selected] gets:
    it is written to the widget, GTK ignores it (silently — a position outside the model
    is a no-op there, with no notification), the divergence is reported once through the
    patcher's channel with the node's path, and the index is selected {i on the frame} the
    list grows to include it. A view that would rather clamp than wait writes
    [~selected:(Int.min selected (List.length items - 1))], which is the one-line fix the
    reported message names.

    And it is why [~selected] is controlled in the ordinary way — compared against the
    {i widget} on every frame, not against the previous node, so a choice the model
    declines is put back — rather than deferred like the other three selections. By the
    time the comparison happens the items already exist, because they are props of the
    same node.

    {b [-1] over a non-empty list is a state GTK will not hold.} A [GtkDropDown] selects
    with an internal [GtkSingleSelection] whose [autoselect] is on and is not reachable
    through any drop-down API, so [gtk_drop_down_set_selected] with the "nothing" sentinel
    over a non-empty model is a {i no-op}: the previous item stays selected and GTK emits
    nothing at all (measured). The library writes it once, sees the widget decline, and
    reports the divergence through the patcher's usual channel with the node's path — the
    same treatment {!text_view} gives text GTK refuses to store. It does not fight the
    widget: the refusal is remembered, so the frames after it cost nothing, and the model
    is left free to ask for something else. [~selected:(-1)] over [~items:[]] is honoured,
    which is the shape "nothing selected yet" usually has anyway.

    While a selection is parked like that, {b the prop is not being enforced}: the
    remembered refusal is consulted before the widget is read, so a choice the user makes
    afterwards is left standing rather than snapped back. That is the honest behaviour
    rather than an oversight — the model asked for a state no item satisfies, so there is
    nothing to snap back {i to} — and {!Attr.on_selected_changed} still reports the user's
    choice, so a model that wants to take it can. The moment the model asks for a
    selection GTK will hold, control resumes.

    Changing [~items] writes the whole list into the model GTK already holds, in one call,
    and only when the list actually differs from the previous node's — never on an idle
    frame. The model object itself is never replaced after the widget is created, which is
    what keeps a change cheap and keeps the selection: GTK carries the selected position
    across, and moves it only when the new contents force it (deleting the item that was
    selected). Where it does move, the library re-applies [~selected] in the same frame,
    so the drop-down is never left showing an item the model did not choose.

    [~enable_search] adds a search entry to the popup and defaults to GTK's [false]; it is
    worth having over a few dozen items and pointless over four. [~show_arrow] defaults to
    GTK's [true]. *)
val drop_down
  :  ?key:Key.t
  -> ?attrs:Attr.t list
  -> ?enable_search:bool
  -> ?show_arrow:bool
  -> items:string list
  -> selected:int
  -> unit
  -> t

(** A [GtkCalendar]: a month at a time, with a heading that walks between months and
    years, and one day selected.

    {b The date is a {!Core.Date.t}, and this is the only widget in the library where that
      matters as much as it does.}
    GTK has no date property. It has [year], [month] and [day] — three integers, written
    and read separately, whose [month] is {b zero-based} while whose [day] is one-based.
    There is a [gtk_calendar_get_date] and a [gtk_calendar_select_day] that trade in
    [GDateTime] and would sidestep all of it, and they are {i not bound}: they take a
    [GDateTime], this binding has no [GDateTime] anywhere, and there is no [GLib-2.0.gir]
    in the checkout to generate one from. So the conversion has to exist somewhere, and it
    exists once, in [src/widgets/w_calendar.ml]. An off-by-one there is the kind nobody
    notices until December; the live suite asserts a December date and a January one in
    the same dump, because January is the month whose zero-based index is 0 and which
    therefore looks right even when the conversion is wrong.

    [~date] is {i controlled} (spec §6.5): it is compared against the {i widget's} current
    date on every frame and written when they differ, so a day the user picks and the
    model declines snaps back. A model that wants to keep the user's choice connects
    {!Attr.on_day_selected}, which hands over a {!Core.Date.t} — GTK's [day-selected]
    carries no payload, so the handler reads the three getters back through the same
    conversion.

    That attr fires for a {i heading walk} as well as a day click, and it has to: a walk
    to another month emits no [day-selected] at all (GTK reports it as [notify::month]),
    so an attr that carried only day clicks would leave the model holding the old date and
    this prop would write the walk away on the next frame. A calendar without an
    [on_day_selected] therefore cannot be browsed either — which is correct and is what a
    controlled prop means, but is worth knowing before rendering one as a read-only
    display.

    {b A date GTK cannot hold.} GTK's year range is 1-9999 ([gtk_calendar_set_year]
    asserts it) and [Core.Date] allows year 0, so a date in year 0 is a value the widget
    will not take. It is not rejected here, for the reason {!text_view}'s unstorable text
    is not: it is a value carrying model state rather than a typo in the call, and raising
    would end the application rather than report anything (see "What a constructor's
    [Invalid_argument] costs" above). The impl refuses the write {i before} touching the
    widget — so the calendar keeps the date it had rather than being left half-written —
    remembers the refusal so the frames after it cost nothing, and reports it once through
    the patcher's channel with the node's path. A later frame offering a date GTK will
    hold writes it on {i that} frame.

    {b The three writes are not atomic, and the obvious order is wrong.} Each setter
    rebuilds the whole date and refuses the write outright if the result is not a real
    day: setting the month to February while the day is 31 fails with a critical and
    changes {i nothing} (it does not clamp), and setting the year to 2025 while the date
    is 29 February 2024 does the same. So writing year, then month, then day — which reads
    as the careful order — silently leaves the calendar on the old month for any date
    whose day does not exist in it. The library writes {b day 1 first}, then the year,
    then the month, then the real day: day 1 exists in every month of every year, so no
    intermediate state is invalid and every date in range lands. The live suite runs that
    as a matrix against the naive order, which gets four of its five transitions wrong.

    [~marked_days] is a list of days of the {i month} (1-31) to draw with a mark, applied
    as [clear_marks] plus one [mark_day] per entry whenever the list changes. It is
    {i not} controlled: nothing the user does marks a day. Marks are per day-of-month and
    survive a month change, so a day marked while February is showing is still marked in
    March; a day outside 1-31 raises here, because GTK's own answer is to ignore it in
    silence and no later date could make it a day. A calendar with no marks is a date
    picker, which is what this constructor would otherwise be only for.

    [~show_heading] and [~show_day_names] default to GTK's [true] and [~show_week_numbers]
    to GTK's [false], so the arguments a caller writes are the ones that turn something
    off. *)
val calendar
  :  ?key:Key.t
  -> ?attrs:Attr.t list
  -> ?show_day_names:bool
  -> ?show_heading:bool
  -> ?show_week_numbers:bool
  -> ?marked_days:int list
  -> date:Date.t
  -> unit
  -> t

(** A [GtkEditableLabel]: a label that turns into an entry when the user double-clicks it,
    and back into a label when the edit is committed or abandoned.

    {b Neither of this widget's two methods is the one you would look for.}
    [gtk_editable_label_set_text] does not exist: the text goes through the [GtkEditable]
    interface, exactly as an entry's does ([w_entry.ml] reaches an entry's the same way),
    and so does {!Attr.on_changed}. And [gtk_editable_label_set_editing] does not exist
    either — [editing] is {b read-only in GTK}. The class binds four methods and no
    signals at all: [new_], [start_editing], [stop_editing] and [get_editing].

    [~text] is {i controlled} (spec §6.5), on the entry's rule and with the entry's caret
    policy: compared against the widget's current text, written only when they differ, and
    the cursor position saved across the write. A model that echoes what the user typed
    writes nothing; a model that rewrites it (uppercasing, trimming) wins. Note that while
    the label is being edited, [GtkEditable] reads and writes the {i in-progress} text, so
    this prop controls the edit as it happens — which is what makes a model that rejects
    input work at all, and which is why {!Attr.on_changed} fires per keystroke rather than
    once at the end (measured: one inserted character, one [changed]).

    {b Text a [GtkEditableLabel] cannot hold.} A string containing a NUL byte is stored up
    to the NUL and no further, silently — [gtk_editable_set_text] takes a NUL-terminated
    string. That write is refused before it is made, remembered so the frames after it
    cost nothing, and reported once with the node's path, on {!text_view}'s rule. Text
    that is not valid UTF-8 is {i not} refused: unlike a [GtkTextBuffer], an editable
    label stores it and reads it back unchanged (measured), so there is nothing to report.

    [~editing] is controlled too, and controlling a read-only property means two methods
    rather than a write: [start_editing] to enter, [stop_editing ~commit:true] to leave.
    {b Leaving commits.} [stop_editing false] would {i discard} what the user typed and
    put the previous text back (measured — it emits [changed] three times doing so), and
    that is not what a model rendering [~editing:false] is saying. It is saying "stop
    editing"; the edit itself reached the model through {!Attr.on_changed} keystroke by
    keystroke, so a model that wanted to reject it has already rejected it in [~text].
    Discarding here would throw away an edit the model may have already accepted.

    The two props are written in the order {b text first, then editing}, which is the
    reverse of how they read. Entering editing mode selects the whole text, and a text
    write after [start_editing] would collapse that selection; a text write before it is
    the state the user is then handed. On the way out the same order commits the model's
    text rather than whatever the widget was showing.

    There is no value of [~editing] a [GtkEditableLabel] refuses. It enters editing mode
    while insensitive, while hidden, while unrealized and while [GtkEditable]'s [editable]
    property is [false] (all measured), so unlike [~text] there is nothing here to refuse
    or report. *)
val editable_label
  :  ?key:Key.t
  -> ?attrs:Attr.t list
  -> ?editing:bool
  -> text:string
  -> unit
  -> t

(** A [GtkStackSwitcher]: a row of buttons, one per page of the {!stack} named by
    [~stack], showing each page's {!Attr.page_title}.

    The stack is found by name rather than held as a value, because the vtree cannot name
    a live widget. The name is resolved after the whole tree has been mounted or patched,
    so the switcher may be declared {i above} the stack it drives -- which is the ordinary
    layout. A name no {!stack} in the tree registers is [Invalid_argument] at that point,
    naming both the switcher's path and the name it wanted.

    Clicking a button changes the stack's visible page, which reaches the model through
    the {i stack's} {!Attr.on_visible_child_changed} -- the switcher itself has no
    handler. *)
val stack_switcher : ?key:Key.t -> ?attrs:Attr.t list -> stack:string -> unit -> t

(** A [GtkStackSidebar]: the same thing as a {!stack_switcher} in a vertical list, which
    is the sidebar half of a two-pane window. It finds its stack the same way and on the
    same rules. *)
val stack_sidebar : ?key:Key.t -> ?attrs:Attr.t list -> stack:string -> unit -> t

(** A [GtkCenterBox]: three children addressed by role rather than position, with the
    centre one centred in the box as a whole rather than between its neighbours — which is
    what a header bar wants and what a three-child {!box} cannot do.

    Every slot is optional and independently patched: dropping [?center] empties that slot
    and leaves the other two alone. [shrink_center_last] is GTK's own [true] — when the
    three do not fit, the start and end children give up space first.

    [baseline_position] is not exposed; a centre box that needs it is a {!native} node. *)
val center_box
  :  ?key:Key.t
  -> ?attrs:Attr.t list
  -> ?shrink_center_last:bool
  -> ?start:t
  -> ?center:t
  -> ?end_:t
  -> unit
  -> t

(** A [GtkPaned]: two children with a handle the user can drag between them. Both halves
    are required — a paned with one side is a {!box}, and GTK renders the empty half as
    dead space with a handle into nothing.

    [position] is the divider's offset in pixels from the start edge. [None] leaves GTK's
    own split (the halves' natural sizes); [Some n] pins it. Unlike every other
    user-movable value in this library it is {i not} controlled (spec §6.5's deliberate
    exception): the user drags the handle continuously, and re-asserting the model's
    position on every frame would make it immovable. It is written at creation and then
    only when the {i node's} value changes, so a drag stands until the model asks for
    something else.

    That makes {!Attr.on_position_changed} informative rather than corrective: attach it
    when the position must be remembered, and expect the widget and the model to differ
    between renders when it is not attached.

    [wide_handle] draws the fat, obviously-draggable separator. [resize_start] and
    [resize_end] (both [true]) say whether a half takes part in redistributing extra
    space; [shrink_start] and [shrink_end] (both [false]) say whether a half may be
    dragged below its child's minimum size, where GTK clips the child silently. All six
    are written at creation, so the node's value stands whatever GTK's property default
    is. *)
val paned
  :  ?key:Key.t
  -> ?attrs:Attr.t list
  -> ?position:int
  -> ?wide_handle:bool
  -> ?resize_start:bool
  -> ?resize_end:bool
  -> ?shrink_start:bool
  -> ?shrink_end:bool
  -> orientation:Orientation.t
  -> start:t
  -> end_:t
  -> unit
  -> t

(** A [GtkOverlay]: a main child, plus any number of children painted on top of it.

    The main child is what the overlay is sized to. Each overlay child is positioned by
    its own {!Attr.halign}/{!Attr.valign} and margins — an overlay has no coordinates of
    its own — and by default is {i not} measured (GTK's default), so the overlay stays the
    size of its main child however large the layers over it are. That is what caps a
    picture at the size of whatever is underneath it rather than letting the image dictate
    the layout. {!Attr.measure_overlay}[ true] on an overlay child opts back in, and the
    overlay then requests at least as much room as that child needs.

    Overlay order is {i not} reconciled: GTK offers no "insert an overlay at a position",
    so overlays stack in the order they were added and a reorder in [~overlays] leaves the
    painting order alone (M1 ruling 4). Keys still preserve child identity, which is what
    a patch needs — but they are no way around this: a keyed reorder is a [Move], and a
    [Move] is exactly what the overlay swallows. A stack whose paint order really must
    change has to {i change} the keys, so the reconciler removes and re-inserts rather
    than moving, or be a {!native} node.

    [gtk_overlay_set_clip_overlay] is not exposed; see {!Attr.measure_overlay}. *)
val overlay : ?key:Key.t -> ?attrs:Attr.t list -> ?overlays:t list -> t -> t

val window
  :  ?key:Key.t
  -> ?attrs:Attr.t list
  -> ?title:string
  -> ?default_size:int * int
  -> t
  -> t

val native : ?key:Key.t -> ?attrs:Attr.t list -> Native.t -> t

(** Depth-first search for the node whose attrs carry [Test_id id].

    Raises [Invalid_argument] if more than one node carries it, naming the path of each --
    the same spelling the patcher uses in its own messages. Two nodes under one [test_id]
    is what rendering the same sub-view twice produces, and returning whichever the walk
    reached first would let a test act on an arbitrary one of them and still pass. *)
val find_by_test_id : t -> string -> t option
