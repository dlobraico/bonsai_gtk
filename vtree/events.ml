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
  | Spin_button _ | Scale _ -> [ On_value_changed ]
  | Expander _ -> [ On_expanded_changed ]
  | Revealer _ -> [ On_revealed ]
  | Paned _ -> [ On_position_changed ]
  | Stack _ -> [ On_visible_child_changed ]
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
   carve-out opens. Task 5 adds [Key] to {!Family.t} and its names here, and the compiler
   asks for the rest. *)
module Family = struct
  type t =
    | Click
    | Focus
  [@@deriving sexp_of, equal, compare, enumerate]
end

let controller_family : Attr.Name.t -> Family.t option = function
  | On_click -> Some Click
  | On_focus_enter | On_focus_leave -> Some Focus
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
  | On_visible_child_changed -> None
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
