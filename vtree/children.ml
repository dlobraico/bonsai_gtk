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

let rec iteri t ~path ~f =
  match t with
  | No_children -> ()
  | Single c -> Option.iter c ~f:(f (sprintf "%s/0" path))
  | List l -> List.iteri l ~f:(fun i c -> f (sprintf "%s/%d" path i) c)
  | Slots slots ->
    List.iter slots ~f:(fun (name, s) -> iteri s ~path:(sprintf "%s/%s" path name) ~f)
;;
