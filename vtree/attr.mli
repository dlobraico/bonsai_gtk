open! Core

(** Which attribute an {!t} is, without its value: the key {!Attrs} stores attrs under,
    and the thing an [Unset] names.

    Unlike {!t}, this variant stays {b concrete} in the documented surface, deliberately.
    It is only reachable through [Attrs.op], which is [Private]-adjacent already, and
    [Attr_apply.unset]'s exhaustive match over it is the mechanism that makes "unset
    restores the creation-time default" impossible to forget for a new attribute. Sealing
    it would trade a compile error inside this library for a silent omission. The cost is
    that a milestone which adds an attribute is a breaking change for an application that
    matches on {!Name.t} exhaustively -- which no application has any reason to do. *)
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
    | Measure_overlay
    | Grid_cell
    | Page_title
    | Row_selectable
    | Row_activatable
    | On_clicked
    | On_toggled
    | On_changed
    | On_activate
    | On_search_changed
    | On_value_changed
    | On_expanded_changed
    | On_revealed
    | On_position_changed
    | On_visible_child_changed
    | On_row_activated
    | On_selected_rows_changed
    | On_child_activated
    | On_selected_children_changed
    | On_click
    | On_focus_enter
    | On_focus_leave
    | On_key_pressed
    | On_key_released
  [@@deriving sexp_of, compare, equal, enumerate]

  (** [true] for the handler-carrying names.

      Two kinds of them, and {!Bonsai_gtk_vtree.Events} tells them apart. Most are a
      {i signal} of some widget class: a widget impl must declare a spec for one, the
      patcher rejects it at mount on a widget that declares none, and [Events.for_kind] is
      the table of which kind emits which. The rest -- the ones
      [Events.is_controller_attr] answers [true] for -- are event controllers the runtime
      attaches to whatever widget carries the attr, so they are legal on every kind and no
      impl declares them. *)
  val is_event : t -> bool

  (** Every attribute name, for tests that must not be able to forget one. The M1 review
      found [is_event] pinned on 2 of 32 names, which is the same as unpinned. *)
  val all : t list

  (** The name as it appears in error messages — [Sexp.to_string (sexp_of_t t)], so
      [On_toggled] prints as ["On_toggled"]. *)
  val to_string : t -> string

  include Comparable.S_plain with type t := t
end

module Private : sig
  (** {b No stability promise.} The constructors of {!t}, for the library's own runtime
      ([Attr_apply], [Signals], the widget impls) and its test harness.

      They live here rather than in the documented surface because every milestone adds
      constructors, and an application matching on them exhaustively would break on each
      one. Build attrs with the smart constructors below; if you find yourself needing to
      take one apart, that is a missing accessor and worth an issue.

      This is the underlying type of {!t}, which is a {i private} abbreviation of it, so
      nothing converts and nothing allocates: [(Attr.css_class "x" :> Attr.Private.t)] is
      [Css_class "x"], the same value, and the coercion is erased.

      What [private] buys, and it is compiler-enforced rather than promised:

      - [Test_id "x"] does not typecheck as an {!t} — the only way to build one is the
        smart constructors below, so [Attr.t] values are always well-formed.
      - [match (a : Attr.t) with Test_id _ -> …] does not typecheck either, whether the
        constructor is spelled bare or qualified. Taking an attr apart requires writing
        [(a :> Attr.Private.t)] — which is legal for anyone, deliberately: the library
        does it in 20-odd places, and an application that does it has named [Private] at
        the site and cannot claim to have stumbled in. What it {i cannot} do is match by
        accident, which is what a bare alias allowed.

      So a milestone that adds a constructor breaks only code that spelled the coercion. *)
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
    | Measure_overlay of bool
    | Grid_cell of Grid_cell.t
    | Page_title of string
    | Row_selectable of bool
    | Row_activatable of bool
    | On_clicked of unit Handler.t
    | On_toggled of bool Handler.t
    | On_changed of string Handler.t
    | On_activate of unit Handler.t
    | On_search_changed of string Handler.t
    | On_value_changed of float Handler.t
    | On_expanded_changed of bool Handler.t
    | On_revealed of bool Handler.t
    | On_position_changed of int Handler.t
    | On_visible_child_changed of string Handler.t
    | On_row_activated of Key.t Handler.t
    | On_selected_rows_changed of Key.t list Handler.t
    | On_child_activated of Key.t Handler.t
    | On_selected_children_changed of Key.t list Handler.t
    | On_click of
        { button : int
        ; phase : Phase.t
        ; handler : Click_event.t Handler.t
        }
    | On_focus_enter of unit Handler.t
    | On_focus_leave of unit Handler.t
    | On_key_pressed of
        { phase : Phase.t
        ; handler : Key_response.handler
        }
    | On_key_released of
        { phase : Phase.t
        ; handler : Key_event.t Handler.t
        }
    | Many of t list

  val sexp_of_t : t -> Sexp.t
end

(** One attribute: a widget-wide property, a container-placement setting the parent reads,
    or an event handler. Build them with the smart constructors below; taking one apart
    means coercing to {!Private}, which carries no stability promise. *)
type t = private Private.t

val sexp_of_t : t -> Sexp.t

(** Every leaf attr of [ts], with {!many} flattened away, depth-first and left to right.

    Exposed for [Attrs.of_list], which is the one caller that has to walk {i into} a
    [Many] and get {!t}s back out: {!t} is a private abbreviation, so the coercion to
    {!Private.t} only runs one way and a [Many]'s payload cannot be injected back.
    Applications have no reason to call this. *)
val flatten : t list -> t list

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

(** For a child of {!Node.overlay}'s [~overlays]: whether the overlay's own size request
    takes this child into account. [false] — GTK's own default
    ([GtkOverlayLayoutChild:measure]), and this library's — lets an overlay be laid out at
    the size of its {i main} child and merely painted over, which is how an image is kept
    from dictating the size of what contains it. [true] is the opt-in: the overlay then
    requests at least as much room as this child needs.

    This is the one attr in this module that no widget applies to itself: it is a setting
    the {i overlay} holds about this child ([gtk_overlay_set_measure_overlay]), so it
    rides on the child node's attrs and is read by the overlay's impl — on insert, and
    again through [Widget_impl.list_ops.updated] when it changes.

    Inert on any other widget, and on an overlay's main child: no other container reads
    it. [gtk_overlay_set_clip_overlay] is the same mechanism and is not exposed; it is
    three lines beside this one if it is wanted. *)
val measure_overlay : bool -> t

(** Where this child sits in its parent {!Node.grid}. Required on every grid child --
    there is no default, and defaulting to (0,0) would stack the whole grid in one cell
    and look like a layout bug rather than the missing attribute it is. A grid child
    without one is [Invalid_argument], naming the child's path.

    [column] and [row] are zero-based and may be sparse: nothing has to fill row 1 for
    something to sit in row 2. [width] and [height] (both [1]) are the number of columns
    and rows the child spans.

    Like {!measure_overlay} this is a container-placement attr: [gtk_grid_attach] is a
    call on the {i grid}, so the coordinates are a setting the grid holds about this child
    rather than a property of the child widget. The grid's impl reads it off the child
    node -- on insert, and again through [Widget_impl.list_ops.updated], where a changed
    cell is a detach and a re-attach of the same widget because GTK has no "move an
    attached child". Inert on any widget whose parent is not a grid. *)
val grid_cell : column:int -> row:int -> ?width:int -> ?height:int -> unit -> t

(** The label a {!Node.stack}'s switcher or sidebar shows for this page. The page's
    {i name} -- what [~visible_child] selects it by -- is the node's {!Key.t}, not this.

    A container-placement attr like {!grid_cell}: it is held by the [GtkStackPage] the
    stack wraps around this child, not by the child. Inert outside a stack. *)
val page_title : string -> t

(** Whether this row of a {!Node.list_box} may be selected. [true] is GTK's own default.

    A container-placement attr like {!page_title}: {!Node.list_box} wraps every child in a
    [GtkListBoxRow] of its own, and this is a property of that wrapper rather than of the
    child, so it rides on the child node's attrs and is read by the list box's impl -- on
    insert, and again through [Widget_impl.list_ops.updated] when it changes.

    [false] is what a header row is. ocgtk binds none of [GtkListBox]'s callback-taking
    methods, [set_header_func] included, so a header in this library is an ordinary row
    that refuses selection and activation -- which is what an application written against
    GTK directly generally builds by hand anyway.

    Inert outside a list box, and rejected there: a row attr on a box child is applied by
    nobody and read by nobody, so it is [Invalid_argument] at mount and at handle time
    like every other misplaced placement attr. *)
val row_selectable : bool -> t

(** Whether this row of a {!Node.list_box} may be activated -- whether clicking it (or
    pressing Enter on it) emits [row-activated] and so reaches {!on_row_activated}. [true]
    is GTK's own default. A container-placement attr on the same terms as
    {!row_selectable}, and [false] on the same kind of row. *)
val row_activatable : bool -> t

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

(** Fires while the user drags a {!Node.paned}'s handle, carrying the divider position the
    widget now holds. This is [notify::position], so it also fires for the library's own
    writes — which the patcher's reentrancy guard drops, as it does for the rest of the
    [notify::] family.

    Purely informative: unlike the toggles' [active], a paned's [~position] is {i not}
    controlled (see {!Node.paned}), so a model that ignores this attr is not broken — it
    simply does not learn where the user left the handle. Attach it when the position must
    survive a restart, or be mirrored somewhere else in the UI. *)
val on_position_changed : (int -> unit Ui_effect.t) -> t

(** Fires when a {!Node.stack}'s visible page changes, carrying the new page's name -- the
    child's {!Key.t}.

    This is [notify::visible-child-name], so it also fires for the library's own writes;
    the patcher's reentrancy guard drops those, which leaves the user clicking a
    {!Node.stack_switcher} button or a {!Node.stack_sidebar} row.

    [~visible_child] is {i controlled} (spec §6.5), so a stack that carries no
    [on_visible_child_changed] -- or whose model ignores it -- snaps back to the model's
    page. Attaching it to a widget that emits no such signal raises [Invalid_argument]
    when the node is mounted or patched. *)
val on_visible_child_changed : (string -> unit Ui_effect.t) -> t

(** Fires when the user activates a row of a {!Node.list_box} -- a click if the list box
    has [~activate_on_single_click] (GTK's default), a double click otherwise, or Enter on
    the focused row. Carries the {i key} of the node that row was built from.

    The key, and never the row or its index, is the point. GTK's [row-activated] hands its
    callback a [GtkListBoxRow] the library made and the application has never seen, and
    [GtkListBoxRow.get_index] answers in positions that move whenever the list is filtered
    or sorted -- so an application written against GTK directly keeps an array beside the
    list box and looks the row up in it. The runtime keeps that map instead
    ([src/child_keys.ml]), and hands back the name the node already had.

    A row with {!row_activatable} [false] never emits this, which is what makes a header
    row inert rather than a click that reports a key nothing acts on.

    Attaching it to a widget that emits no such signal raises [Invalid_argument] when the
    node is mounted or patched. *)
val on_row_activated : (Key.t -> unit Ui_effect.t) -> t

(** Fires when a {!Node.list_box}'s selection changes, carrying the keys of {i every}
    selected row, in the widget's order -- so a list box in [Multiple] mode reports the
    whole selection rather than the row that just moved, and an emptied selection reports
    [[]].

    GTK's [selected-rows-changed] carries nothing; the selection is read back off the
    widget and mapped through the same table {!on_row_activated} uses. It also fires for
    the library's own writes, which the patcher's reentrancy guard drops -- so what
    reaches the model is the user's doing.

    [~selected] is {i controlled} (spec §6.5), so a list box that carries no
    [on_selected_rows_changed] -- or whose model ignores it -- snaps back to the model's
    selection on the next frame. Attaching it to a widget that emits no such signal raises
    [Invalid_argument] when the node is mounted or patched. *)
val on_selected_rows_changed : (Key.t list -> unit Ui_effect.t) -> t

(** Fires when the user activates a child of a {!Node.flow_box} -- a click if the flow box
    has [~activate_on_single_click] (GTK's default), a double click otherwise, or Enter on
    the focused child. Carries the {i key} of the node that child was built from, for the
    reason {!on_row_activated} carries one: GTK's [child-activated] hands back a
    [GtkFlowBoxChild] the library made, and its index moves whenever the grid is filtered
    or re-sorted.

    A grid of cards usually pairs this with [~activate_on_single_click:false], so that a
    single click selects a card (reaching {!on_selected_children_changed}) and a double
    click opens it (reaching this).

    Attaching it to a widget that emits no such signal raises [Invalid_argument] when the
    node is mounted or patched -- including on a {!Node.list_box}, which emits
    {!on_row_activated} instead. The two are different GTK signals on different widgets
    and the attrs are named after them. *)
val on_child_activated : (Key.t -> unit Ui_effect.t) -> t

(** Fires when a {!Node.flow_box}'s selection changes, carrying the keys of {i every}
    selected child, in the widget's order -- the same shape and the same rules as
    {!on_selected_rows_changed}, over [selected-children-changed].

    It fires when a selected child is {i removed}, too, with the reduced selection; the
    key of the departing child is gone from the table before GTK is told to remove it, so
    a handler is never handed the name of a child that has just left the tree.

    Attaching it to a widget that emits no such signal raises [Invalid_argument] when the
    node is mounted or patched. *)
val on_selected_children_changed : (Key.t list -> unit Ui_effect.t) -> t

(** A [GtkGestureClick] on this widget.

    [button] is which mouse button to listen for; [0] (the default) means all of them, and
    the one that was pressed arrives in {!Click_event.button}. [phase] defaults to
    {!Phase.Bubble}, GTK's own -- a gesture on a card in a selection container wants
    bubble, so that the container's own selection gesture still runs.

    Unlike every other event attr, this one is legal on {i any} node: it is not a signal
    of some widget class but a controller the runtime attaches to whatever carries it. The
    controller exists only while the attr does -- a frame that drops it removes the
    controller, and a later frame that adds it back gets a fresh one.

    The gesture does {i not} claim the event sequence, so a click also reaches whatever
    else would have handled it. That is deliberate and is what lets a card carry a
    middle-click handler without breaking its list box's click-to-select; an application
    that wants to consume the click has no way to say so in M2, which is named in the
    README's Limitations. *)
val on_click : ?button:int -> ?phase:Phase.t -> Click_event.t Handler.t -> t

(** Fires when focus moves {i into} this widget or any of its children -- which is the
    useful sense for a composite widget like a [GtkSearchEntry], whose own [has_focus] is
    always false because its inner [GtkText] holds the focus.

    A [GtkEventControllerFocus], which this attr shares with {!on_focus_leave}: a widget
    carrying either pays for one controller, and it lives exactly as long as the last of
    the two attrs does. Like {!on_click}, legal on any node. *)
val on_focus_enter : unit Handler.t -> t

(** Fires when focus leaves this widget and all of its children. The other half of
    {!on_focus_enter}, on the same controller and the same terms. *)
val on_focus_leave : unit Handler.t -> t

(** A [GtkEventControllerKey] on this widget.

    The handler is not a {!Handler.t}: it returns a {!Key_response.t} rather than an
    effect, because GTK asks a key press a {i question} — "did anything handle this?" —
    and routes the event on the answer, synchronously, on its own stack, long before the
    frame that an effect would run in. So the decision is a pure function of the event and
    the consequence rides along: [Handled_and eff] stops the routing {i and} schedules
    [eff].

    [phase] defaults to {!Phase.Bubble}, GTK's own. Use {!Phase.Capture} for a
    window-or-dialog-wide key: in bubble phase GTK runs the {i last} controller added
    first, so any controller a child adds afterwards sees the key first and can swallow
    it, and "afterwards" is not something a declarative tree controls. A [GtkPopover] has
    its own surface and so is not below the window in the capture chain — an open popover
    still takes its own Escape.

    Both this and {!on_key_released} share one controller, so a widget carrying both pays
    for one; giving them different phases is [Invalid_argument], because there is only one
    phase to write. Raised at mount, at patch (a conditionally-added [~phase] reaching a
    widget mounted without one), and by [Bonsai_gtk_test]'s handle -- all three from
    [Events.key_phase_rejection], so a headless suite cannot certify a view the runtime
    refuses.

    Like {!on_click}, legal on {i any} node: it is not a signal of some widget class but a
    controller the runtime attaches to whatever carries it, and it exists exactly as long
    as the attr does.

    The keyval is a plain [int]; {!Bonsai_gtk_vtree.Keyval} names the ones worth naming. *)
val on_key_pressed : ?phase:Phase.t -> (Key_event.t -> Key_response.t) -> t

(** Fires when a key is released over this widget. The other half of {!on_key_pressed}, on
    the same [GtkEventControllerKey] and therefore the same phase.

    This handler {i is} an ordinary {!Handler.t}: GTK's [key-released] callback returns
    [unit], so there is nothing to answer and no [Key_response.t] to return. A release
    cannot be consumed — by the time it happens the press has already been routed. *)
val on_key_released : ?phase:Phase.t -> Key_event.t Handler.t -> t

val many : t list -> t
val empty : t
