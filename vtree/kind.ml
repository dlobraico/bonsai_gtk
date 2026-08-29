open! Core

type t =
  | Label of { text : string }
  | Button of { label : string option }
  | Box of
      { orientation : Orientation.t
      ; spacing : int
      ; homogeneous : bool
      }
  | Window of
      { title : string option
      ; default_size : (int * int) option
      }
  | Native of Native.t
[@@deriving sexp_of]

let name = function
  | Label _ -> "Label"
  | Button _ -> "Button"
  | Box _ -> "Box"
  | Window _ -> "Window"
  | Native n -> "Native:" ^ n.name
;;

let same_kind a b =
  match a, b with
  | Label _, Label _ | Button _, Button _ | Box _, Box _ | Window _, Window _ -> true
  | Native a, Native b -> String.equal a.name b.name
  | _ -> false
;;

let equal_props a b =
  match a, b with
  | Label { text = a }, Label { text = b } -> String.equal a b
  | Button { label = a }, Button { label = b } -> Option.equal String.equal a b
  | Box a, Box b ->
    Orientation.equal a.orientation b.orientation
    && a.spacing = b.spacing
    && Bool.equal a.homogeneous b.homogeneous
  | Window a, Window b ->
    Option.equal String.equal a.title b.title
    && Option.equal
         (fun (w, h) (w', h') -> w = w' && h = h')
         a.default_size
         b.default_size
  | Native a, Native b -> String.equal a.name b.name && phys_equal a.payload b.payload
  | _ -> false
;;
