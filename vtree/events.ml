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
  | Text_view _ -> [ On_changed ]
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
  | Window _ | Box _ | Grid _ | Center_box _ | Overlay _ | Frame _ | Scrolled_window _ ->
    []
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
  [@@deriving sexp_of, equal, compare, enumerate]
end

let controller_family : Attr.Name.t -> Family.t option = function
  | On_click -> Some Click
  | On_focus_enter | On_focus_leave -> Some Focus
  | On_key_pressed | On_key_released -> Some Key
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
  | Row_selectable
  | Row_activatable
  | Tab_label -> None
;;

(* One [GtkEventControllerKey] serves both key attrs, so there is exactly one propagation
   phase to write and two places that can ask for one. Two attrs asking for different
   phases is a mistake with no good resolution -- picking either silently gives one of
   them behaviour its author did not ask for -- so it is a rejection, like every other
   structural mistake (spec §11).

   It lives here rather than in [Controllers] for the reason [for_kind] and
   [Placement.reader] do: the runtime is not the only thing that has to refuse this tree.
   [Bonsai_gtk_test] refuses it too, from this same function, so a headless suite cannot
   certify a view that raises the moment it is shown -- which is the whole point of
   putting these tables in [vtree]. Both callers render {!key_phase_rejection}'s string,
   so the two messages are identical outright rather than by convention. *)
let key_phases attrs =
  ( (match (Attrs.find attrs On_key_pressed :> Attr.Private.t option) with
     | Some (On_key_pressed { phase; _ }) -> Some phase
     | Some _ | None -> None)
  , match (Attrs.find attrs On_key_released :> Attr.Private.t option) with
    | Some (On_key_released { phase; _ }) -> Some phase
    | Some _ | None -> None )
;;

let key_phase attrs =
  match key_phases attrs with
  | Some p, _ -> Some p
  | None, r -> r
;;

(* Plain [sprintf] over a pre-rendered name rather than
   [!"...%{sexp: Phase.t}..."]: ocamlformat rewrites a [\]-continued ppx_custom_printf
   literal by joining the lines and keeping their indentation, so the message comes out
   with a run of spaces down the middle of it. [Placement.rejection] is plain [sprintf]
   for the same reason. *)
let phase_name phase = Sexp.to_string (Phase.sexp_of_t phase)

let key_phase_rejection ~path attrs =
  match key_phases attrs with
  | Some pressed, Some released when not (Phase.equal pressed released) ->
    Some
      (sprintf
         "%s: Attr.on_key_pressed asks for %s and Attr.on_key_released for %s, but they \
          share one GtkEventControllerKey and so one propagation phase"
         path
         (phase_name pressed)
         (phase_name released))
  | (Some _ | None), (Some _ | None) -> None
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

let is_supported kind name =
  (not (Attr.Name.is_event name))
  || is_controller_attr name
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
