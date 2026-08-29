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
      | Test_id
      | On_clicked
    [@@deriving sexp_of, compare, equal]
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
  | Test_id of string
  | On_clicked of unit Handler.t
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
  | Test_id _ -> Some Test_id
  | On_clicked _ -> Some On_clicked
;;

let rec equal a b =
  match a, b with
  | Css_class a, Css_class b | Tooltip a, Tooltip b | Test_id a, Test_id b ->
    String.equal a b
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
  | Visible a, Visible b -> Bool.equal a b
  | On_clicked a, On_clicked b -> Handler.equal a b
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
let test_id s = Test_id s
let on_clicked eff = On_clicked (fun () -> eff)
let many l = Many l
let empty = Many []
