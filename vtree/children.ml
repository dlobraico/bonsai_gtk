open! Core

type 'a t =
  | No_children
  | Single of 'a option
  | List of 'a list
  | Slots of (string * 'a t) list
[@@deriving sexp_of]

let rec iter t ~f =
  match t with
  | No_children -> ()
  | Single c -> Option.iter c ~f
  | List l -> List.iter l ~f
  | Slots slots -> List.iter slots ~f:(fun (_, s) -> iter s ~f)
;;

let rec find_map t ~f =
  match t with
  | No_children -> None
  | Single c -> Option.bind c ~f
  | List l -> List.find_map l ~f
  | Slots slots -> List.find_map slots ~f:(fun (_, s) -> find_map s ~f)
;;
