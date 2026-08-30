open! Core

module Name = struct
  module T = struct
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
      (* The controller attrs, after every signal name so that no existing [Attrs.diff]
         output reorders. *)
      | On_click
      | On_focus_enter
      | On_focus_leave
      | On_key_pressed
      | On_key_released
    [@@deriving sexp_of, compare, equal, enumerate]

    (* Exhaustive on purpose, never [_ -> false]: every widget task adds [On_*] names, and
       the compiler is what forces each new one to be classified here. A name that says
       [true] is one [Signals.require_specs] insists some widget impl claims. *)
    let is_event = function
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
      (* The controller attrs are events too -- they carry a handler and a widget that
         cannot deliver one is a mistake worth a diagnostic. What they are not is any
         impl's *signal*: no [Widget_impl.signals] declares one and no slot for one lives
         on the widget, so the two mount-time checks treat them apart --
         [Events.is_supported] short-circuits (they are legal on every kind) and
         [Signals.require_slots] skips them (their slots belong to [Controllers], which
         creates them from the attr itself). [Events.is_controller_attr] is that
         distinction, and it is the one place it is written down. *)
      | On_click
      | On_focus_enter
      | On_focus_leave
      | On_key_pressed
      | On_key_released -> true
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
      | Page_title -> false
    ;;
  end

  include T
  include Comparable.Make_plain (T)

  let to_string t = Sexp.to_string (sexp_of_t t)
end

(* The variant lives in [Private] and reaches the rest of this file through [include],
   which is what lets [attr.mli] publish [type t = Private.t] -- the constructors
   documented in one place that carries no stability promise, and the type itself
   documented without them.

   [include] rather than a second spelling of the constructor list: [Attr.t] and
   [Attr.Private.t] are the same type, so nothing converts and nothing allocates, and
   there is no duplicated list to drift.

   [private] lives in the mli only ([type t = private Private.t]); in here [t] is the
   plain variant, so this file constructs and matches freely. Outside, neither is possible
   without spelling the coercion [(a :> Attr.Private.t)] -- which is what makes the seal
   compiler-enforced rather than merely documented. The coercion runs one way, which is
   why [flatten] below exists. *)
module Private = struct
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
    (* [button] and [phase] ride in the constructor rather than being captured by the
       handler because they are properties of the *controller*: [Controllers.update] has
       to see a change in either without the handler having to change, and a view that
       rebuilds its closures every frame changes the handler on every frame regardless. *)
    | On_click of
        { button : int
        ; phase : Phase.t
        ; handler : Click_event.t Handler.t
        }
    | On_focus_enter of unit Handler.t
    | On_focus_leave of unit Handler.t
    (* [phase] rides in the constructor for the same reason [On_click]'s does: it is a
       property of the *controller*, and [Controllers.update] has to see it change without
       the handler having to. The two key attrs share one [GtkEventControllerKey], so
       there is exactly one phase to write and carrying it on both is what lets either
       attr appear alone -- at the price of a rejection when both appear and disagree
       ([Events.key_phase_rejection]). *)
    | On_key_pressed of
        { phase : Phase.t
        ; handler : Key_response.handler
        }
    | On_key_released of
        { phase : Phase.t
        ; handler : Key_event.t Handler.t
        }
    | Many of t list
  [@@deriving sexp_of]
end

include Private

(* [Many] flattened away, so that [Attrs.of_list] -- the one caller that has to
   look *inside* a [Many] -- never needs to turn a [Private.t] back into a [t], which the
   private abbreviation forbids. Depth-first and left to right, so "last one wins" in
   [Attrs.of_list] still means what it says. *)
let flatten ts =
  let rec go acc = function
    | Many l -> List.fold l ~init:acc ~f:go
    | attr -> attr :: acc
  in
  List.rev (List.fold ts ~init:[] ~f:go)
;;

let name = function
  | Css_class _ | Many _ -> None
  | Margin_start _ -> Some Name.Margin_start
  | Margin_end _ -> Some Margin_end
  | Margin_top _ -> Some Margin_top
  | Margin_bottom _ -> Some Margin_bottom
  | Halign _ -> Some Halign
  | Valign _ -> Some Valign
  | Hexpand _ -> Some Hexpand
  | Vexpand _ -> Some Vexpand
  | Sensitive _ -> Some Sensitive
  | Visible _ -> Some Visible
  | Tooltip _ -> Some Tooltip
  | Width_request _ -> Some Width_request
  | Height_request _ -> Some Height_request
  | Opacity _ -> Some Opacity
  | Focusable _ -> Some Focusable
  | Can_focus _ -> Some Can_focus
  | Widget_name _ -> Some Widget_name
  | Cursor_name _ -> Some Cursor_name
  | Test_id _ -> Some Test_id
  | Measure_overlay _ -> Some Measure_overlay
  | Grid_cell _ -> Some Grid_cell
  | Page_title _ -> Some Page_title
  | On_clicked _ -> Some On_clicked
  | On_toggled _ -> Some On_toggled
  | On_changed _ -> Some On_changed
  | On_activate _ -> Some On_activate
  | On_search_changed _ -> Some On_search_changed
  | On_value_changed _ -> Some On_value_changed
  | On_expanded_changed _ -> Some On_expanded_changed
  | On_revealed _ -> Some On_revealed
  | On_position_changed _ -> Some On_position_changed
  | On_visible_child_changed _ -> Some On_visible_child_changed
  | On_click _ -> Some On_click
  | On_focus_enter _ -> Some On_focus_enter
  | On_focus_leave _ -> Some On_focus_leave
  | On_key_pressed _ -> Some On_key_pressed
  | On_key_released _ -> Some On_key_released
;;

let rec equal a b =
  match a, b with
  | Css_class a, Css_class b
  | Tooltip a, Tooltip b
  | Test_id a, Test_id b
  | Widget_name a, Widget_name b
  | Cursor_name a, Cursor_name b
  | Page_title a, Page_title b -> String.equal a b
  | Margin_start a, Margin_start b
  | Margin_end a, Margin_end b
  | Margin_top a, Margin_top b
  | Margin_bottom a, Margin_bottom b
  | Width_request a, Width_request b
  | Height_request a, Height_request b -> Int.equal a b
  | Halign a, Halign b | Valign a, Valign b -> Align.equal a b
  | Hexpand a, Hexpand b
  | Vexpand a, Vexpand b
  | Sensitive a, Sensitive b
  | Visible a, Visible b
  | Focusable a, Focusable b
  | Can_focus a, Can_focus b
  | Measure_overlay a, Measure_overlay b -> Bool.equal a b
  | Opacity a, Opacity b -> Float.equal a b
  | Grid_cell a, Grid_cell b -> Grid_cell.equal a b
  | On_clicked a, On_clicked b -> Handler.equal a b
  | On_toggled a, On_toggled b -> Handler.equal a b
  | On_changed a, On_changed b -> Handler.equal a b
  | On_activate a, On_activate b -> Handler.equal a b
  | On_search_changed a, On_search_changed b -> Handler.equal a b
  | On_value_changed a, On_value_changed b -> Handler.equal a b
  | On_expanded_changed a, On_expanded_changed b -> Handler.equal a b
  | On_revealed a, On_revealed b -> Handler.equal a b
  | On_position_changed a, On_position_changed b -> Handler.equal a b
  | On_visible_child_changed a, On_visible_child_changed b -> Handler.equal a b
  (* The two controller properties compare structurally and the handler physically: a
     frame that moves the gesture to another button, or into the capture phase, is a
     change [Controllers.update] must see even though the closure is rebuilt (and so
     unequal) on every frame anyway. *)
  | On_click a, On_click b ->
    Int.equal a.button b.button
    && Phase.equal a.phase b.phase
    && Handler.equal a.handler b.handler
  | On_focus_enter a, On_focus_enter b -> Handler.equal a b
  | On_focus_leave a, On_focus_leave b -> Handler.equal a b
  (* Same rule as [On_click]: the controller property structurally, the handler
     physically. [On_key_pressed]'s handler is not a [Handler.t] -- it returns a
     [Key_response.t] rather than an effect -- but it is still a closure the view rebuilds
     every frame, so [phys_equal] is the only honest comparison and [Handler.equal] is
     spelled out here rather than reached for. *)
  | On_key_pressed a, On_key_pressed b ->
    Phase.equal a.phase b.phase && phys_equal a.handler b.handler
  | On_key_released a, On_key_released b ->
    Phase.equal a.phase b.phase && Handler.equal a.handler b.handler
  | Many a, Many b -> List.equal equal a b
  | _ -> false
;;

let css_class s = Css_class s
let margin_start n = Margin_start n
let margin_end n = Margin_end n
let margin_top n = Margin_top n
let margin_bottom n = Margin_bottom n
let margin n = Many [ Margin_start n; Margin_end n; Margin_top n; Margin_bottom n ]
let halign a = Halign a
let valign a = Valign a
let hexpand b = Hexpand b
let vexpand b = Vexpand b
let sensitive b = Sensitive b
let visible b = Visible b
let tooltip s = Tooltip s
let width_request n = Width_request n
let height_request n = Height_request n
let opacity f = Opacity f
let focusable b = Focusable b
let can_focus b = Can_focus b
let widget_name s = Widget_name s
let cursor_name s = Cursor_name s
let test_id s = Test_id s

(* A setting the *overlay* holds about this child, not a property of the child, so it is
   read by [w_overlay] from the child node's attrs rather than written by [Attr_apply];
   see the mli. *)
let measure_overlay b = Measure_overlay b

(* [gtk_grid_attach] is a call on the *grid*, so a child's coordinates are something the
   grid holds about it rather than a property of the child; they ride on the child node's
   attrs and are read by [w_grid]. See the mli. *)
let grid_cell ~column ~row ?(width = 1) ?(height = 1) () =
  Grid_cell { Grid_cell.column; row; width; height }
;;

let page_title s = Page_title s
let on_clicked eff = On_clicked (fun () -> eff)
let on_toggled f = On_toggled f
let on_changed f = On_changed f
let on_activate eff = On_activate (fun () -> eff)
let on_search_changed f = On_search_changed f
let on_value_changed f = On_value_changed f
let on_expanded_changed f = On_expanded_changed f
let on_revealed f = On_revealed f
let on_position_changed f = On_position_changed f
let on_visible_child_changed f = On_visible_child_changed f

let on_click ?(button = 0) ?(phase = Phase.Bubble) handler =
  On_click { button; phase; handler }
;;

let on_focus_enter f = On_focus_enter f
let on_focus_leave f = On_focus_leave f
let on_key_pressed ?(phase = Phase.Bubble) handler = On_key_pressed { phase; handler }
let on_key_released ?(phase = Phase.Bubble) handler = On_key_released { phase; handler }
let many l = Many l
let empty = Many []
