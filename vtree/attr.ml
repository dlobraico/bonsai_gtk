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
      | On_clicked
      | On_toggled
      | On_changed
      | On_activate
      | On_search_changed
    [@@deriving sexp_of, compare, equal]

    (* Exhaustive on purpose, never [_ -> false]: every widget task adds [On_*] names, and
       the compiler is what forces each new one to be classified here. A name that says
       [true] is one [Signals.require_specs] insists some widget impl claims. *)
    let is_event = function
      | On_clicked | On_toggled | On_changed | On_activate | On_search_changed -> true
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
      | Test_id -> false
    ;;
  end

  include T
  include Comparable.Make_plain (T)
end

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
  | On_clicked of unit Handler.t
  | On_toggled of bool Handler.t
  | On_changed of string Handler.t
  | On_activate of unit Handler.t
  | On_search_changed of string Handler.t
  | Many of t list
[@@deriving sexp_of]

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
  | On_clicked _ -> Some On_clicked
  | On_toggled _ -> Some On_toggled
  | On_changed _ -> Some On_changed
  | On_activate _ -> Some On_activate
  | On_search_changed _ -> Some On_search_changed
;;

let rec equal a b =
  match a, b with
  | Css_class a, Css_class b
  | Tooltip a, Tooltip b
  | Test_id a, Test_id b
  | Widget_name a, Widget_name b
  | Cursor_name a, Cursor_name b -> String.equal a b
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
  | Can_focus a, Can_focus b -> Bool.equal a b
  | Opacity a, Opacity b -> Float.equal a b
  | On_clicked a, On_clicked b -> Handler.equal a b
  | On_toggled a, On_toggled b -> Handler.equal a b
  | On_changed a, On_changed b -> Handler.equal a b
  | On_activate a, On_activate b -> Handler.equal a b
  | On_search_changed a, On_search_changed b -> Handler.equal a b
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
let on_clicked eff = On_clicked (fun () -> eff)
let on_toggled f = On_toggled f
let on_changed f = On_changed f
let on_activate eff = On_activate (fun () -> eff)
let on_search_changed f = On_search_changed f
let many l = Many l
let empty = Many []
