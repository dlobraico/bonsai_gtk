open! Core
open Bonsai_gtk_vtree

(* items are (key option, kind) *)
type item = string option * string [@@deriving sexp_of, equal, compare, quickcheck]

let key (k, _) = k
let same_kind (_, a) (_, b) = String.equal a b
let diff ~old ~new_ = Reconcile.diff ~key ~same_kind ~old ~new_
let show ~old ~new_ = print_s [%sexp (diff ~old ~new_ : item Reconcile.op list)]
let k s kind = Some s, kind
let u kind = None, kind

let%expect_test "identical lists -> updates only" =
  show ~old:[ k "a" "L"; u "B" ] ~new_:[ k "a" "L"; u "B" ];
  [%expect
    {|
    ((Update (index 0) (old ((a) L)) (item ((a) L)))
     (Update (index 1) (old (() B)) (item (() B))))
    |}]
;;

let%expect_test "append and remove" =
  show ~old:[ k "a" "L" ] ~new_:[ k "a" "L"; k "b" "L" ];
  [%expect
    {|
    ((Update (index 0) (old ((a) L)) (item ((a) L)))
     (Insert (index 1) (item ((b) L))))
    |}];
  show ~old:[ k "a" "L"; k "b" "L" ] ~new_:[ k "b" "L" ];
  [%expect {| ((Remove (index 0)) (Update (index 0) (old ((b) L)) (item ((b) L)))) |}]
;;

let%expect_test "keyed reorder produces moves, not remove+insert" =
  show ~old:[ k "a" "L"; k "b" "L"; k "c" "L" ] ~new_:[ k "c" "L"; k "a" "L"; k "b" "L" ];
  [%expect
    {|
    ((Move (from 2) (to_ 0)) (Update (index 0) (old ((c) L)) (item ((c) L)))
     (Update (index 1) (old ((a) L)) (item ((a) L)))
     (Update (index 2) (old ((b) L)) (item ((b) L))))
    |}]
;;

let%expect_test "unkeyed items match positionally only when kinds agree" =
  show ~old:[ u "L"; u "B" ] ~new_:[ u "B"; u "L" ];
  [%expect
    {|
    ((Remove (index 1)) (Remove (index 0)) (Insert (index 0) (item (() B)))
     (Insert (index 1) (item (() L))))
    |}]
;;

let%expect_test "duplicate keys raise" =
  Expect_test_helpers_core.require_does_raise (fun () ->
    diff ~old:[] ~new_:[ k "a" "L"; k "a" "L" ]);
  [%expect {| (Invalid_argument "Reconcile.diff: duplicate key a") |}]
;;

(* A stricter interpreter than [Reconcile.apply]: it never blindly overwrites by index. At
   each [Update], it asserts the element currently at [index] is exactly [old] (the item
   [diff] claims is there) before replacing it — this is the identity guarantee the GTK
   patcher depends on ("patch the widget that used to be [old] into [item]"), which
   [Reconcile.apply]'s plain index-overwrite can't check. It also asserts every op's
   indices are in bounds. Test-local only; [Reconcile.apply] itself is intentionally left
   unchanged. *)
let checked_apply ops list =
  List.fold ops ~init:list ~f:(fun l (op : item Reconcile.op) ->
    let n = List.length l in
    match op with
    | Reconcile.Remove { index } ->
      assert (index >= 0 && index < n);
      List.filteri l ~f:(fun i _ -> i <> index)
    | Reconcile.Insert { index; item } ->
      assert (index >= 0 && index <= n);
      List.take l index @ [ item ] @ List.drop l index
    | Reconcile.Move { from; to_ } ->
      assert (from >= 0 && from < n);
      assert (to_ >= 0 && to_ < n);
      let item = List.nth_exn l from in
      let l = List.filteri l ~f:(fun i _ -> i <> from) in
      List.take l to_ @ [ item ] @ List.drop l to_
    | Reconcile.Update { index; old; item } ->
      assert (index >= 0 && index < n);
      [%test_eq: item] (List.nth_exn l index) old ~message:"Update: stale index/identity";
      List.mapi l ~f:(fun i x -> if i = index then item else x))
;;

let%test_unit "apply (diff old new) old = new" =
  let gen =
    let open Quickcheck.Generator.Let_syntax in
    let%bind n = Int.gen_incl 0 6 in
    List.gen_with_length
      n
      (let%map key =
         Option.quickcheck_generator
           (String.gen_with_length 1 (Char.gen_uniform_inclusive 'a' 'e'))
       and kind = Quickcheck.Generator.of_list [ "L"; "B" ] in
       key, kind)
  in
  let dedup l =
    List.fold l ~init:([], String.Set.empty) ~f:(fun (acc, seen) ((key, _) as it) ->
      match key with
      | Some kk when Set.mem seen kk -> acc, seen
      | Some kk -> it :: acc, Set.add seen kk
      | None -> it :: acc, seen)
    |> fst
    |> List.rev
  in
  Quickcheck.test
    (Quickcheck.Generator.both gen gen)
    ~sexp_of:[%sexp_of: item list * item list]
    ~f:(fun (old, new_) ->
      let old = dedup old
      and new_ = dedup new_ in
      let ops = diff ~old ~new_ in
      [%test_result: item list] (Reconcile.apply ops old) ~expect:new_;
      [%test_result: item list] (checked_apply ops old) ~expect:new_)
;;
