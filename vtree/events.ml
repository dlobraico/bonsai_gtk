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

let is_supported kind name =
  (not (Attr.Name.is_event name)) || List.mem (for_kind kind) name ~equal:Attr.Name.equal
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
