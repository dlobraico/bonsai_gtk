open! Core

type 'a op =
  | Insert of
      { index : int
      ; item : 'a
      }
  | Move of
      { from : int
      ; to_ : int
      }
  | Remove of { index : int }
  | Update of
      { index : int
      ; old : 'a
      ; item : 'a
      }
[@@deriving sexp_of]

(* The message carries no path: every caller is a container's child list, and the patcher
   prefixes the container's own path onto it the same way it does for a grid child with no
   cell (spec §11). *)
let check_unique_keys ~key items =
  ignore
    (List.fold items ~init:Key.Set.empty ~f:(fun seen item ->
       match key item with
       | None -> seen
       | Some k ->
         if Set.mem seen k
         then
           invalid_argf
             "duplicate key %s among one container's children (a key identifies a child \
              among its siblings, so no two of them may share one)"
             k
             ();
         Set.add seen k)
     : Key.Set.t)
;;

(* Match every new item to at most one old index. Keyed: by key. Unkeyed: the k-th unkeyed
   new item pairs with the k-th unkeyed old item iff same_kind. *)
let matches ~key ~same_kind ~old ~new_ =
  let old_by_key =
    List.filter_mapi old ~f:(fun i o -> Option.map (key o) ~f:(fun k -> k, i))
    |> Key.Map.of_alist_exn
  in
  let old_unkeyed =
    List.filter_mapi old ~f:(fun i o -> if Option.is_none (key o) then Some i else None)
    |> Array.of_list
  in
  let unkeyed_seen = ref 0 in
  List.map new_ ~f:(fun n ->
    match key n with
    | Some k -> Map.find old_by_key k
    | None ->
      let j = !unkeyed_seen in
      incr unkeyed_seen;
      if j < Array.length old_unkeyed && same_kind (List.nth_exn old old_unkeyed.(j)) n
      then Some old_unkeyed.(j)
      else None)
;;

let diff ?(ordered = true) ~key ~same_kind ~old ~new_ () =
  check_unique_keys ~key old;
  check_unique_keys ~key new_;
  let matched = matches ~key ~same_kind ~old ~new_ in
  let old_arr = Array.of_list old in
  let kept = Int.Set.of_list (List.filter_opt matched) in
  (* 1. removes, descending, so earlier indices stay valid *)
  let removes =
    List.init (Array.length old_arr) ~f:Fn.id
    |> List.filter ~f:(fun i -> not (Set.mem kept i))
    |> List.rev
    |> List.map ~f:(fun index -> Remove { index })
  in
  (* current.(j) is the identity token of the element at live position j, tracked in
     lockstep with what [apply] would do to [old]: a surviving old index, or [-1] for an
     item this loop has already inserted fresh. [-1] can never match the [findi] below,
     which only ever looks for a real (non-negative) old index. *)
  let current =
    ref (List.init (Array.length old_arr) ~f:Fn.id |> List.filter ~f:(Set.mem kept))
  in
  let ops =
    List.concat_mapi (List.zip_exn new_ matched) ~f:(fun i (item, m) ->
      match m with
      | None ->
        current := List.take !current i @ [ -1 ] @ List.drop !current i;
        [ Insert { index = i; item } ]
      | Some old_idx ->
        let from = List.findi_exn !current ~f:(fun _ x -> x = old_idx) |> fst in
        (* The [Update]'s index is where this item lives once whatever this branch does to
           [current] is done. In the ordered case a [Move] puts it at [i]; in the
           unordered case nothing moves it, so it stays at [from] -- and the [Update] must
           say so, or it would patch whichever child happens to sit at [i] instead. Note
           that [from = i] takes the same branch for the same reason, which is why the
           ordered path's ops are byte-identical to what they were before [ordered]
           existed. *)
        if from = i || not ordered
        then [ Update { index = from; old = old_arr.(old_idx); item } ]
        else (
          let without = List.filteri !current ~f:(fun j _ -> j <> from) in
          current := List.take without i @ [ old_idx ] @ List.drop without i;
          [ Move { from; to_ = i }; Update { index = i; old = old_arr.(old_idx); item } ]))
  in
  removes @ ops
;;

let apply ops list =
  List.fold ops ~init:list ~f:(fun l op ->
    match op with
    | Remove { index } -> List.filteri l ~f:(fun i _ -> i <> index)
    | Insert { index; item } -> List.take l index @ [ item ] @ List.drop l index
    | Move { from; to_ } ->
      let item = List.nth_exn l from in
      let l = List.filteri l ~f:(fun i _ -> i <> from) in
      List.take l to_ @ [ item ] @ List.drop l to_
    | Update { index; item; _ } ->
      List.mapi l ~f:(fun i x -> if i = index then item else x))
;;
