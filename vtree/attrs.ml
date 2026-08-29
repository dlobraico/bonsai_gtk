open! Core

type t =
  { by_name : Attr.t Attr.Name.Map.t
  ; css_classes : string list (* insertion order, unique *)
  }

type op =
  | Set of Attr.t
  | Unset of Attr.Name.t
  | Add_css_class of string
  | Remove_css_class of string
[@@deriving sexp_of]

let empty = { by_name = Attr.Name.Map.empty; css_classes = [] }

let sexp_of_t t =
  let css =
    if List.is_empty t.css_classes
    then []
    else [ [%sexp `css_classes (t.css_classes : string list)] ]
  in
  Sexp.List (css @ List.map (Map.data t.by_name) ~f:Attr.sexp_of_t)
;;

let of_list attrs =
  let rec add t = function
    | Attr.Many l -> List.fold l ~init:t ~f:add
    | Css_class c ->
      if List.mem t.css_classes c ~equal:String.equal
      then t
      else { t with css_classes = t.css_classes @ [ c ] }
    | attr ->
      (match Attr.name attr with
       | None -> t
       | Some name -> { t with by_name = Map.set t.by_name ~key:name ~data:attr })
  in
  List.fold attrs ~init:empty ~f:add
;;

let find t name = Map.find t.by_name name
let css_classes t = t.css_classes

let test_id t =
  match find t Test_id with
  | Some (Test_id s) -> Some s
  | _ -> None
;;

let to_list t = List.map t.css_classes ~f:Attr.css_class @ Map.data t.by_name

let diff ~old ~new_ =
  let removed =
    List.filter old.css_classes ~f:(fun c ->
      not (List.mem new_.css_classes c ~equal:String.equal))
  in
  let added =
    List.filter new_.css_classes ~f:(fun c ->
      not (List.mem old.css_classes c ~equal:String.equal))
  in
  let keyed =
    Map.fold_symmetric_diff
      old.by_name
      new_.by_name
      ~data_equal:Attr.equal
      ~init:[]
      ~f:(fun acc (name, change) ->
        match change with
        | `Left _ -> Unset name :: acc
        | `Right a | `Unequal (_, a) -> Set a :: acc)
    |> List.rev
  in
  List.map removed ~f:(fun c -> Remove_css_class c)
  @ List.map added ~f:(fun c -> Add_css_class c)
  @ keyed
;;
