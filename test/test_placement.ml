open! Core
open Bonsai_gtk_vtree

(* [Placement.names] is derived from [Placement.reader], which is exhaustive over
   [Attr.Name.t] with no wildcard -- so an attribute added to [Attr.Name] cannot reach
   this list without someone having answered "is this held by the parent?". Printing the
   list is what turns that answer into a reviewable diff. *)
let%expect_test "which attrs are container-placement attrs, and who reads each" =
  print_s
    [%sexp
      (List.map Placement.names ~f:(fun name -> name, Placement.reader name)
       : (Attr.Name.t * string option) list)];
  [%expect
    {|
    ((Measure_overlay (Overlay)) (Grid_cell (Grid)) (Page_title (Stack))
     (Row_selectable (ListBox)) (Row_activatable (ListBox)))
    |}];
  (* Everything else is either an ordinary widget property or an event, and is legal
     anywhere. *)
  print_s
    [%sexp
      (List.count Attr.Name.all ~f:(fun name -> Option.is_none (Placement.reader name))
       : int)];
  [%expect {| 38 |}]
;;

(* The two tables are inverses, and nothing else checks that: [read_by] is what the
   patcher and the handle consult, [reader] is what the message names, and a pair that
   disagreed would reject an attr while telling the author to put it exactly where it
   already is. *)
let%expect_test "read_by and reader agree" =
  let containers =
    [ (Node.grid []).kind
    ; (Node.stack ~name:"s" ~visible_child:"a" []).kind
    ; (Node.overlay (Node.label "x")).kind
    ; (Node.list_box ~selected:[] []).kind
      (* In the list although it reads nothing, which is the point: a flow box is the
         container a reader most expects to have a [Flow_child_selectable] to go with the
         list box's, and it has none because [GtkFlowBoxChild] has no such property.
         Pinning the empty list here is what keeps that a decision rather than an
         oversight. *)
    ; (Node.flow_box ~selected:[] []).kind
    ]
  in
  print_s
    [%sexp
      (List.map containers ~f:(fun kind -> Kind.name kind, Placement.read_by kind)
       : (string * Attr.Name.t list) list)];
  [%expect
    {|
    ((Grid (Grid_cell)) (Stack (Page_title)) (Overlay (Measure_overlay))
     (ListBox (Row_selectable Row_activatable)) (FlowBox ()))
    |}];
  (* Every name a container reads names that container back... *)
  print_s
    [%sexp
      (List.concat_map containers ~f:(fun kind ->
         List.map (Placement.read_by kind) ~f:(fun name ->
           Option.equal String.equal (Placement.reader name) (Some (Kind.name kind))))
       : bool list)];
  [%expect {| (true true true true true) |}];
  (* ...and every name with a reader is read by exactly one of them, so no placement attr
     is left with nowhere legal to go. *)
  print_s
    [%sexp
      (List.map Placement.names ~f:(fun name ->
         ( name
         , List.count containers ~f:(fun kind ->
             List.mem (Placement.read_by kind) name ~equal:Attr.Name.equal) ))
       : (Attr.Name.t * int) list)];
  [%expect
    {|
    ((Measure_overlay 1) (Grid_cell 1) (Page_title 1) (Row_selectable 1)
     (Row_activatable 1))
    |}]
;;

(* A kind that reads none of them rejects all of them -- the wildcard arm, which is the
   whole diagnostic. *)
let%expect_test "a container that reads no placement attr rejects every one" =
  let box = (Node.box ~orientation:Vertical []).kind in
  print_s [%sexp (Placement.read_by box : Attr.Name.t list)];
  [%expect {| () |}];
  let attrs = Attrs.of_list [ Attr.page_title "Library" ] in
  print_s [%sexp (Placement.misplaced ~parent:(Some box) attrs : Attr.Name.t option)];
  [%expect {| (Page_title) |}];
  print_s
    [%sexp
      (Placement.misplaced
         ~parent:(Some (Node.stack ~name:"s" ~visible_child:"a" []).kind)
         attrs
       : Attr.Name.t option)];
  [%expect {| () |}];
  (* The root has no container above it. *)
  print_s [%sexp (Placement.misplaced ~parent:None attrs : Attr.Name.t option)];
  [%expect {| (Page_title) |}];
  (* A non-placement attr is legal anywhere, including on the root. *)
  print_s
    [%sexp
      (Placement.misplaced ~parent:None (Attrs.of_list [ Attr.margin 4 ])
       : Attr.Name.t option)];
  [%expect {| () |}]
;;
