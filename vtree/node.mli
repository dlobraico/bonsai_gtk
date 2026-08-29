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
    was. A write-back is not free when it does happen: GTK replaces the whole text, so the
    caret lands at the end whenever the model shortened it past the old position, the
    selection is dropped, and an input method's in-flight preedit (a half-composed CJK or
    accented character) is disturbed. That is the price of a model that rewrites as you
    type, and the reason the widget is left alone whenever it already agrees. There is no
    uncontrolled mode: an entry whose text no [Attr.on_changed] feeds back into the model
    resets to the model's value the next time anything re-renders, which is the bug the
    required argument exists to make impossible to write by accident.

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
    [placement], are not exposed; a scroller that needs them is a {!native} node. *)
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
    without one is [Invalid_argument] at mount.

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
    Naming a page that does not exist leaves the selection alone rather than raising: the
    frame that adds the page will select it.

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

(** Depth-first search for a node whose attrs carry [Test_id id]. *)
val find_by_test_id : t -> string -> t option
