open! Core

(* One [match] over [Kind.t] with no wildcard arm: a kind added without a decision here is
   a compile error, which is the only reason this table can be trusted to be complete.
   [test/live/live_events.ml] is what keeps each arm honest against the widget impl that
   actually connects the signals. *)
let for_kind : Kind.t -> Attr.Name.t list = function
  | Label _
  | Image _
  | Picture _
  | Separator _
  | Spinner _
  | Progress_bar _
  (* A [GtkLevelBar] emits nothing this library exposes. It has no interaction at all --
     no drag, no scroll, no keyboard -- so its value only ever changes because the model
     wrote it. GTK does have [offset-changed], for the named markers that colour a bar's
     zones; this library exposes no offsets, so binding a handler for them would be
     binding one nothing can provoke. *)
  | Level_bar _
  | Stack_switcher _
  | Stack_sidebar _
  (* Spec §6.6: a native node declares no specs of its own -- a native widget that needs
     to reach Bonsai connects its own GTK handler in [create] -- so any event attr on one
     is rejected rather than silently inert. *)
  | Native _ -> []
  | Button _ -> [ On_clicked ]
  | Toggle_button _ | Check_button _ | Switch _ -> [ On_toggled ]
  | Entry _ | Password_entry _ -> [ On_changed; On_activate ]
  | Search_entry _ -> [ On_changed; On_activate; On_search_changed ]
  (* No [On_activate]: Enter inserts a newline in a text view rather than submitting, and
     GTK emits nothing for it. The line a reader copies across from an entry is therefore
     rejected here rather than accepted and never firing. [On_changed] is the buffer's
     signal rather than the view's, which is invisible from this table and is
     [w_text_view.ml]'s business. *)
  | Text_view _ -> [ On_changed; On_cursor_moved ]
  | Spin_button _ | Scale _ -> [ On_value_changed ]
  | Expander _ -> [ On_expanded_changed ]
  | Revealer _ -> [ On_revealed ]
  | Paned _ -> [ On_position_changed ]
  | Stack _ -> [ On_visible_child_changed ]
  | List_box _ -> [ On_row_activated; On_selected_rows_changed ]
  (* Its own pair, not the list box's: the two containers emit different GTK signals, so a
     line copied from a list box to a flow box is rejected here rather than being accepted
     and never firing. *)
  | Flow_box _ -> [ On_child_activated; On_selected_children_changed ]
  (* One signal, and again its own: [switch-page] is the notebook's, and a line copied
     from a stack ([On_visible_child_changed]) is rejected here rather than accepted and
     never firing. *)
  | Notebook _ -> [ On_page_changed ]
  (* [GtkDropDown]'s only signal is [activate], which fires when the user re-picks the
     item already showing and carries nothing; a selection change is a [notify::selected]
     and nothing else. Its own name rather than [On_visible_child_changed] or
     [On_selected_rows_changed], on this table's usual rule: a line copied from a stack or
     a list box is rejected here instead of being accepted and never firing. *)
  | Drop_down _ -> [ On_selected_changed ]
  (* One attr, and behind it three GTK emissions: [day-selected] plus [notify::month] and
     [notify::year]. That is not an implementation detail leaking into this table -- it is
     what makes the {i attr} mean what its name says. A heading walk moves the month or
     the year and leaves the day-of-month alone, so it emits {b no} [day-selected] at all
     (measured, by clicking the calendar's own heading buttons -- and true even for Jan 31
     -> Feb, where the day does move). The first round exposed [day-selected] alone on the
     opposite premise, and the result was a controlled date the user could not browse: the
     walk was never reported, so no model could follow it, and the next [reassert] wrote
     the old date back. [w_calendar.ml] has the measurements.

     [next-month], [prev-month], [next-year] and [prev-year] are still not exposed: they
     say the heading was clicked rather than what the calendar now shows, and the two
     [notify::] connections already carry what they change. *)
  | Calendar _ -> [ On_day_selected ]
  (* Two, and the first is the {i entry's} name rather than one of its own: a
     [GtkEditableLabel] reaches its text through [GtkEditable], so [changed] is literally
     the same interface signal an entry emits and a line copied from an entry works here.
     [On_editing_changed] is the other half, and it is a [notify::editing] -- the class
     binds no signals at all. *)
  | Editable_label _ -> [ On_changed; On_editing_changed ]
  (* The popover's one exposed signal; [activate-default] waits for a consumer. *)
  | Popover _ -> [ On_closed ]
  (* [close-request] is the window's one exposed signal, and it is a veto: the runtime
     always answers GTK "handled" and this attr is how the model hears about the request.
     See [Attr.on_close_request]. *)
  | Window _ -> [ On_close_request ]
  (* A [GtkMenuButton]'s [activate] (the button was popped open programmatically or by
     mnemonic) is deliberately unexposed in M3: nothing reports a {i user} open either
     (see [Node.popover]), and half an opening story is worse than none. *)
  | Menu_button _
  (* [GtkHeaderBar] and [GtkActionBar] declare no signals at all -- pure structure. And
     the windows root is a virtual node whose anchor widget is never realized, so nothing
     could ever emit from it. *)
  | Windows
  | Box _
  | Grid _
  | Center_box _
  | Overlay _
  | Header_bar _
  | Action_bar _
  | Frame _
  | Scrolled_window _ -> []
;;

(* The controller families, and which attr names belong to each.

   One table, exhaustive over [Attr.Name.t] with no wildcard, and it is the single point
   of truth for three separate things that would otherwise drift:

   - [is_controller_attr] is derived from it, so [Events.is_supported] admits exactly the
     names that have a family;
   - [Signals.require_slots] skips exactly the same names, because their slots belong to
     [Controllers] rather than to the widget;
   - [Controllers.update] dispatches on {!Family.t} with an exhaustive match, so a family
     added here without a controller to attach it is a compile error rather than an attr
     that is accepted on every node and wired to nothing.

   That last one is the reason this is a table rather than a predicate. Without it, a task
   adding a key controller could add the names to a predicate (which it must, or nothing
   compiles), have [require_specs] accept them, [require_slots] skip them,
   [live_events.ml] pass (no impl declares them) -- and the handler would never run, on
   any widget, with no diagnostic anywhere. That is exactly the silent inertness
   [require_specs] exists to prevent, reintroduced through the door the controller
   carve-out opens. Adding [Key] here was four compile errors and no thought, which is
   what the table was for. *)
module Family = struct
  type t =
    | Click
    | Focus
    | Key
    | Shortcut (** [GtkShortcutController] *)
  [@@deriving sexp_of, equal, compare, enumerate]
end

let controller_family : Attr.Name.t -> Family.t option = function
  | On_click -> Some Click
  | On_focus_enter | On_focus_leave | On_contains_focus_changed -> Some Focus
  | On_key_pressed | On_key_released -> Some Key
  | Shortcut -> Some Shortcut
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
  | Css_provider
  | Test_id
  | Autofocus
  | Measure_overlay
  | Grid_cell
  | Page_title
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
  | On_page_changed
  | On_selected_changed
  | On_day_selected
  | On_editing_changed
  | On_cursor_moved
  | On_closed
  | On_close_request
  | Actions
  | Row_selectable
  | Row_activatable
  | Tab_label -> None
;;

(* The second carve-out beside the controller one, and one constructor wide: an
   [Attr.actions] carries handlers (so [is_event] says yes and the diagnostics apply) but
   is no impl's signal -- [src/actions.ml] attaches a [GSimpleActionGroup] to whatever
   widget carries it, exactly as [Controllers] attaches an event controller -- so
   [is_supported] admits it on every kind and [Signals.require_slots] skips it. *)
let is_actions_attr : Attr.Name.t -> bool = function
  | Actions -> true
  | _ -> false
;;

(* The controller attrs are legal on every kind: they are not any impl's signal, they are
   a [GtkEventController] the runtime attaches to whatever widget carries the attr. So
   [is_supported] short-circuits on them rather than consulting [for_kind], and no impl
   may declare one in its [Widget_impl.signals] -- [test/live/live_events.ml] asserts
   that, because an impl that did would connect a second handler nobody removes. *)
let is_controller_attr name = Option.is_some (controller_family name)

(* In [Attr.Name] order, and derived rather than written again: [Controllers] asks this
   which attrs decide whether a family's controller should exist at all. *)
let family_attrs family =
  List.filter Attr.Name.all ~f:(fun name ->
    match controller_family name with
    | Some f -> Family.equal f family
    | None -> false)
;;

(* One controller per family serves every attr of that family, so there is exactly one
   propagation phase to write and up to two places that can ask for one. Two attrs asking
   for different phases is a mistake with no good resolution -- picking either silently
   gives one of them behaviour its author did not ask for -- so it is a rejection, like
   every other structural mistake (spec §11). Not every family attr carries a phase
   ([On_contains_focus_changed] is a [notify::], which fires in no phase at all), which is
   why this walks the attrs that do rather than the family's whole list.

   It lives here rather than in [Controllers] for the reason [for_kind] and
   [Placement.reader] do: the runtime is not the only thing that has to refuse this tree.
   [Bonsai_gtk_test] refuses it too, from this same function, so a headless suite cannot
   certify a view that raises the moment it is shown -- which is the whole point of
   putting these tables in [vtree]. Both callers render {!family_phase_rejection}'s
   string, so the two messages are identical outright rather than by convention. *)
(* Exhaustive with no wildcard, on the neighbouring tables' rule: a phase-carrying
   controller attr must be classified here or nothing compiles -- a wildcard would
   silently drop its phase from the family's vote instead (which is what one would have
   done to [Shortcut], the attr this returns a {i list} for -- a repeatable attr carries
   one phase per entry). *)
let attr_phases (attr : Attr.t) =
  match (attr :> Attr.Private.t) with
  | On_click { phase; _ }
  | On_focus_enter { phase; _ }
  | On_focus_leave { phase; _ }
  | On_key_pressed { phase; _ }
  | On_key_released { phase; _ } -> [ phase ]
  | Shortcut shortcuts -> List.map shortcuts ~f:(fun (s : Attr.shortcut) -> s.phase)
  | Css_class _
  | Margin_start _
  | Margin_end _
  | Margin_top _
  | Margin_bottom _
  | Halign _
  | Valign _
  | Hexpand _
  | Vexpand _
  | Sensitive _
  | Visible _
  | Tooltip _
  | Width_request _
  | Height_request _
  | Opacity _
  | Focusable _
  | Can_focus _
  | Autofocus _
  | Widget_name _
  | Cursor_name _
  | Css_provider _
  | Test_id _
  | Measure_overlay _
  | Grid_cell _
  | Page_title _
  | Row_selectable _
  | Row_activatable _
  | Tab_label _
  | On_clicked _
  | On_toggled _
  | On_changed _
  | On_activate _
  | On_search_changed _
  | On_value_changed _
  | On_expanded_changed _
  | On_revealed _
  | On_position_changed _
  | On_visible_child_changed _
  | On_row_activated _
  | On_selected_rows_changed _
  | On_child_activated _
  | On_selected_children_changed _
  | On_page_changed _
  | On_selected_changed _
  | On_day_selected _
  | On_editing_changed _
  | On_cursor_moved _
  | On_closed _
  | On_close_request _
  | On_contains_focus_changed _
  | Actions _
  | Many _ -> []
;;

(* The phased attrs of [family] that are present, in [Attr.Name] order -- which is what
   makes "the first two that disagree" a stable answer. *)
let family_phases family attrs =
  List.concat_map (family_attrs family) ~f:(fun name ->
    match Attrs.find attrs name with
    | None -> []
    | Some attr -> List.map (attr_phases attr) ~f:(fun phase -> name, phase))
;;

let family_phase family attrs =
  match family_phases family attrs with
  | [] -> None
  | (_, phase) :: _ -> Some phase
;;

(* Plain [sprintf] over pre-rendered names rather than
   [!"...%{sexp: Phase.t}..."]: ocamlformat rewrites a [\]-continued ppx_custom_printf
   literal by joining the lines and keeping their indentation, so the message comes out
   with a run of spaces down the middle of it. [Placement.rejection] is plain [sprintf]
   for the same reason. *)
let phase_name phase = Sexp.to_string (Phase.sexp_of_t phase)

(* The smart constructor's spelling, [Placement.rejection]'s rule: the message points at
   the line the caller wrote, which says [Attr.on_key_pressed]. *)
let attr_spelling name = String.lowercase (Attr.Name.to_string name)

let controller_class : Family.t -> string = function
  | Click -> "GtkGestureClick"
  | Focus -> "GtkEventControllerFocus"
  | Key -> "GtkEventControllerKey"
  | Shortcut -> "GtkShortcutController"
;;

(* The trigger's twin of the phase doctrine, and it lives here for the same reason: two
   shortcuts on one node sharing a trigger but naming different actions would make "which
   action runs" a fact about install order rather than about the tree, and both the
   runtime and [Bonsai_gtk_test] must refuse it with one string. Same trigger, same action
   is legal (and collapses to one installed shortcut). *)
let shortcut_conflict_rejection ~path attrs =
  match (Attrs.find attrs Attr.Name.Shortcut :> Attr.Private.t option) with
  | Some (Shortcut shortcuts) ->
    let sorted =
      List.sort shortcuts ~compare:(fun (a : Attr.shortcut) b ->
        [%compare: Trigger.t * string] (a.trigger, a.action) (b.trigger, b.action))
    in
    let rec find_conflict = function
      | (a : Attr.shortcut) :: (b :: _ as rest) ->
        if Trigger.equal a.trigger b.trigger && not (String.equal a.action b.action)
        then Some (a, b)
        else find_conflict rest
      | [ _ ] | [] -> None
    in
    Option.map (find_conflict sorted) ~f:(fun (a, b) ->
      sprintf
        "%s: two Attr.shortcuts share the trigger %s but name different actions (%S and \
         %S); which one ran would be an accident of order, so the node is rejected"
        path
        (Trigger.to_label a.trigger)
        a.action
        b.action)
  | Some _ | None -> None
;;

let family_phase_rejection ~path (family : Family.t) attrs =
  match family_phases family attrs with
  | [] | [ _ ] -> None
  | (first_name, first_phase) :: rest ->
    List.find rest ~f:(fun (_, phase) -> not (Phase.equal first_phase phase))
    |> Option.map ~f:(fun (other_name, other_phase) ->
      sprintf
        "%s: Attr.%s asks for %s and Attr.%s for %s, but they share one %s and so one \
         propagation phase"
        path
        (attr_spelling first_name)
        (phase_name first_phase)
        (attr_spelling other_name)
        (phase_name other_phase)
        (controller_class family))
;;

let is_supported kind name =
  (not (Attr.Name.is_event name))
  || is_controller_attr name
  || is_actions_attr name
  || List.mem (for_kind kind) name ~equal:Attr.Name.equal
;;

(* [Attrs.to_list] yields the css classes (which carry no name) and then the keyed attrs
   in [Attr.Name] order, so "the first one" is a stable answer rather than whichever the
   caller happened to write first. *)
let unsupported kind attrs =
  List.find_map (Attrs.to_list attrs) ~f:(fun attr ->
    match Attr.name attr with
    | Some name when not (is_supported kind name) -> Some name
    | Some _ | None -> None)
;;

(* The [Attr.autofocus] helpers, in [vtree] for the reason the phase rejection is: the
   patcher decides which grabs fire (mount, or a false-to-true flip) and raises on two in
   one frame, and [Bonsai_gtk_test] makes the same decision over the same attrs headlessly
   -- both render [autofocus_rejection], so the two messages are identical outright. *)
let autofocus_requested attrs =
  match (Attrs.find attrs Attr.Name.Autofocus :> Attr.Private.t option) with
  | Some (Autofocus b) -> b
  | Some _ | None -> false
;;

let autofocus_rejection ~first ~second =
  sprintf
    "%s and %s both ask Attr.autofocus to grab focus in this frame, but at most one \
     autofocus may fire per frame per toplevel"
    first
    second
;;

(* The [~transient_for] rejections, in [vtree] on the autofocus strings' reasoning: the
   patcher resolves the key at fixup time against the windows its walk registered, and
   [Bonsai_gtk_test] resolves the same key against the same tree headlessly -- both render
   these, so the two messages are identical by construction. *)
let transient_for_rejection ~path ~key ~existing =
  sprintf
    "%s: ~transient_for names no window: no Node.windows child is keyed %S (keys that \
     exist: %s; a window may only be transient for another window in the same \
     Node.windows list)"
    path
    (key : Key.t)
    (match existing with
     | [] -> "none"
     | keys ->
       String.concat ~sep:", " (List.map keys ~f:(fun k -> sprintf "%S" (k : Key.t))))
;;

let transient_for_self_rejection ~path ~key =
  sprintf
    "%s: ~transient_for is this window's own ~key %S (a window cannot be transient for \
     itself)"
    path
    (key : Key.t)
;;
