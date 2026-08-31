### Task 8: Named slots — CenterBox, Paned, Overlay

The first task to need a children shape M0 does not have. Spec §5.3's fourth row: `Slots` (named), for containers whose children are addressed by role rather than position. It also needs list ops that can see the child *node*, because an overlay's children carry a per-child layout flag (`measure-overlay`) that lives on the parent, not on the child widget — which is the same mechanism Task 9's `Grid` cells and `Stack` page titles need.

stavekeeper uses both: `cards.ml` and `library_window.ml` put an unmeasured overlay over a spacer to cap a `GtkPicture`'s allocated size (`overlay#set_measure_overlay picture_widget false`), which is the single trick that makes their thumbnail grid work.

**Files:**
- Create: `vtree/children.mli`, `src/widgets/w_center_box.ml`, `src/widgets/w_paned.ml`, `src/widgets/w_overlay.ml`
- Modify: `vtree/children.ml`, `vtree/node.ml(i)`, `vtree/kind.ml(i)`, `vtree/attr.ml(i)`, `src/widget_impl.ml(i)`, `src/patcher.ml`, `src/widgets/w_box.ml`, `src/widgets/registry.ml`, `src/live_tree.ml`, `test/test_widgets.ml`, `test/test_reconcile.ml` (nothing — check), `test/live/live_containers.ml`

**Interfaces:**
- Produces:
  ```ocaml
  (* vtree/children.ml *)
  type 'a t =
    | No_children
    | Single of 'a option
    | List of 'a list
    | Slots of (string * 'a t) list       (* slot name -> that slot's own shape *)
  [@@deriving sexp_of]

  (* Widget_impl *)
  type list_ops =
    { insert : Widget.t -> after:Widget.t option -> node:Node.t -> Widget.t -> unit
    ; move : Widget.t -> child:Widget.t -> after:Widget.t option -> unit
    ; remove : Widget.t -> Widget.t -> unit
    ; updated : Widget.t -> old:Node.t -> node:Node.t -> Widget.t -> unit
    }
  type single_ops = { set : Widget.t -> Widget.t option -> unit }
  type slot_ops =
    | Slot_single of single_ops
    | Slot_list of list_ops
  type child_ops =
    | No_children
    | Single of single_ops
    | List of list_ops
    | Slots of (string * slot_ops) list
  val no_list_update : Widget.t -> old:Node.t -> node:Node.t -> Widget.t -> unit

  (* Attr *)
  val measure_overlay : bool -> t

  (* Node *)
  val center_box
    :  ?key:Key.t -> ?attrs:Attr.t list -> ?shrink_center_last:bool
    -> ?start:t -> ?center:t -> ?end_:t -> unit -> t
  val paned
    :  ?key:Key.t -> ?attrs:Attr.t list -> ?position:int -> ?wide_handle:bool
    -> ?resize_start:bool -> ?resize_end:bool -> ?shrink_start:bool -> ?shrink_end:bool
    -> orientation:Orientation.t -> start:t -> end_:t -> t
  val overlay : ?key:Key.t -> ?attrs:Attr.t list -> ?overlays:t list -> t -> t
  ```

**Why the list ops gain `node`.** A list container's per-child settings sometimes live on the *parent*: `gtk_overlay_set_measure_overlay(overlay, child, bool)`, `gtk_grid_attach(grid, child, col, row, w, h)`, `gtk_stack_page_set_title(page, title)`. None of them is a property of the child widget, so `Attr_apply` cannot apply them and the child impl cannot know them. They are attrs on the child *node* that the parent impl reads. Hence: `insert` receives the node it is inserting, and a new `updated` hook fires after a child is patched in place so the parent can react to those attrs changing. `move` does not need the node (nothing positional depends on it).

`Widget_impl.no_list_update` is the do-nothing `updated` for the containers with no such attrs (`Box`, and Task 9's nothing-else); write it once rather than a lambda per impl.

- [ ] **Step 1: Failing headless test** (`test/test_widgets.ml`)

The sexp of a slotted node is the thing to pin, because it is a new `Children.t` constructor and every expect file that ever prints one depends on its shape:

```ocaml
let%expect_test "slot containers print their slots by name" =
  print_s
    [%sexp
      (Node.center_box
         ~start:(Node.label "l")
         ~center:(Node.label "c")
         ~end_:(Node.button ~label:"r" ())
         ()
       : Node.t)];
  [%expect {| |}];
  print_s
    [%sexp
      (Node.paned
         ~orientation:Horizontal
         ~position:240
         ~start:(Node.label "sidebar")
         ~end_:(Node.label "content")
       : Node.t)];
  [%expect {| |}];
  print_s
    [%sexp
      (Node.overlay
         ~overlays:
           [ Node.picture ~attrs:[ Attr.measure_overlay false ] (Filename "/tmp/t.png") ]
         (Node.box ~orientation:Vertical ~attrs:[ Attr.width_request 150 ] [])
       : Node.t)];
  [%expect {| |}]
;;

let%expect_test "find_by_test_id descends into slots" =
  let view =
    Node.overlay
      ~overlays:[ Node.label ~attrs:[ Attr.test_id "badge" ] "9" ]
      (Node.label "under")
  in
  print_s [%sexp (Option.is_some (Node.find_by_test_id view "badge") : bool)];
  [%expect {| |}]
;;
```

- [ ] **Step 2: Failing live test** — append to `test/live/live_containers.ml`

```ocaml
  (* Slots: each is patched independently, and clearing one must not disturb the others.
     The overlay case is stavekeeper's thumbnail trick -- an unmeasured overlay over a
     sized spacer -- so [measure-overlay] is checked as a live property, not just a node. *)
  let slots ~center ~badge =
    Node.window
      ~title:"slots"
      (Node.paned
         ~orientation:Horizontal
         ~position:120
         ~start:
           (Node.center_box
              ~start:(Node.label "L")
              ?center:(if center then Some (Node.label "C") else None)
              ~end_:(Node.button ~label:"R" ())
              ())
         ~end_:
           (Node.overlay
              ~overlays:
                (Node.label ~key:"badge" ~attrs:[ Attr.measure_overlay badge ] "9"
                 :: (if badge then [ Node.label ~key:"extra" "+" ] else []))
              (Node.box
                 ~orientation:Vertical
                 ~attrs:[ Attr.width_request 150; Attr.height_request 60 ]
                 [])))
  in
  let live = P.mount ctx ~path:"root" ~is_root:true (slots ~center:true ~badge:false) in
  print_s (Live_tree.dump live.widget);
  let live = P.patch ctx ~path:"root" ~is_root:true live (slots ~center:false ~badge:true) in
  print_s (Live_tree.dump live.widget);
  (* A slot the impl does not have is structural misuse, like a nested window. *)
  P.destroy ctx live
```

- [ ] **Step 3: Run to verify failure.**

- [ ] **Step 4: `vtree/children.ml(i)`**

```ocaml
(* children.ml *)
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
```
The mli M0 never wrote (a backlog hygiene item), documenting the invariant that makes the patcher's matching sound:

```ocaml
(* children.mli *)
open! Core

(** The shape of a node's children, fixed by its {!Kind.t} (spec §5.3).

    [Slots] is for containers whose children are addressed by role rather than by
    position: a [center_box]'s [start]/[center]/[end], a [paned]'s two halves, an
    [overlay]'s main child and its overlays. Each slot carries its own shape, so a slot is
    itself a [Single] or a [List] and is patched by the same code.

    The patcher requires a node's shape and its impl's [child_ops] to agree, including the
    slot *names* and their order; a mismatch is [Invalid_argument] rather than a silently
    dropped child, because both sides are written in this repository and a mismatch is
    always a bug in one of them. *)
type 'a t =
  | No_children
  | Single of 'a option
  | List of 'a list
  | Slots of (string * 'a t) list
[@@deriving sexp_of]

val iter : 'a t -> f:('a -> unit) -> unit
val find_map : 'a t -> f:('a -> 'b option) -> 'b option
```

Rewrite `Node.find_by_test_id`'s recursion with `Children.find_map`, which is what it should have been:
```ocaml
let rec find_by_test_id t id =
  if Option.equal String.equal (Attrs.test_id t.attrs) (Some id)
  then Some t
  else Children.find_map t.children ~f:(fun c -> find_by_test_id c id)
;;
```

- [ ] **Step 5: `src/widget_impl.ml(i)`**

```ocaml
type single_ops = { set : Widget.t -> Widget.t option -> unit }

type list_ops =
  { insert : Widget.t -> after:Widget.t option -> node:Node.t -> Widget.t -> unit
  ; move : Widget.t -> child:Widget.t -> after:Widget.t option -> unit
  ; remove : Widget.t -> Widget.t -> unit
  ; updated : Widget.t -> old:Node.t -> node:Node.t -> Widget.t -> unit
  }

type slot_ops =
  | Slot_single of single_ops
  | Slot_list of list_ops

type child_ops =
  | No_children
  | Single of single_ops
  | List of list_ops
  | Slots of (string * slot_ops) list

(* For containers with no per-child settings of their own -- the common case. *)
let no_list_update _parent ~old:_ ~node:_ _child = ()
```
mli, on `list_ops`:
```ocaml
  { insert : Widget.t -> after:Widget.t option -> node:Node.t -> Widget.t -> unit
  (** Add a child not yet in the container, directly after [after] ([None] = first).
      [node] is the child's description: some containers keep per-child settings of their
      own -- an overlay's measure flag, a grid cell, a stack page's title -- which are not
      properties of the child widget and so are read from the child node's attrs here
      rather than applied by [Attr_apply]. *)
  ; ...
  ; updated : Widget.t -> old:Node.t -> node:Node.t -> Widget.t -> unit
  (** Called after a child that stayed in place was patched, with its previous and new
      descriptions. This is where those same parent-held settings are re-applied when they
      change. [no_list_update] for containers that have none. *)
  }
```

- [ ] **Step 6: `src/patcher.ml` — factor the shapes, then add `Slots`**

`mount`'s and `patch_children`'s bodies become dispatch over three helpers, so a slot reuses exactly the code a top-level shape uses. Sketch (write it out properly in the file):

```ocaml
and mount_children ctx ~path (widget : Widget.t) impl_name
  (children : Node.t Children.t) (ops : Widget_impl.child_ops) : live Children.t =
  match children, ops with
  | No_children, _ -> Children.No_children
  | Single c, Single { set } -> Single (mount_single ctx ~path widget ~set c)
  | List cs, List ops -> List (mount_list ctx ~path widget ~ops cs)
  | Slots node_slots, Slots op_slots ->
    Slots
      (List.map2_exn_or_invalid ~path node_slots op_slots ~f:(fun (name, cs) (op_name, op) ->
         if not (String.equal name op_name)
         then invalid_argf "%s: slot %s does not exist on %s" path name impl_name ();
         let path = sprintf "%s/%s" path name in
         match cs, op with
         | Single c, Slot_single { set } -> name, Children.Single (mount_single ctx ~path widget ~set c)
         | List cs, Slot_list ops -> name, Children.List (mount_list ctx ~path widget ~ops cs)
         | _ -> invalid_argf "%s: slot %s has the wrong shape for %s" path name impl_name ()))
  | (Single _ | List _ | Slots _), _ ->
    invalid_argf "%s: node's children do not match %s's shape" path impl_name ()
```
`List.map2_exn_or_invalid` is not a real function: use `match List.zip node_slots op_slots with Ok pairs -> ... | Unequal_lengths -> invalid_argf "%s: %s has %d slots, node has %d" ...`. Slot lists are written by this repository on both sides and are short and fixed, so equal length and equal order is a fair requirement — and a loud one when broken.

`patch_children` gets the same three-way split (`patch_single`, `patch_list`, and the `Slots` arm zipping live slots, node slots and op slots), and `patch_list` is Task 1's op loop verbatim plus one line: after a same-kind `Update`, call the container's hook.

```ocaml
      | Update { index; item; old = _ } ->
        let l = List.nth_exn !cur index in
        let old_node = l.node in
        let l' = patch ctx ~path:(child_path path index) ~is_root:false l item in
        if phys_equal l l'
        then ops.updated parent ~old:old_node ~node:item l'.widget
        else (
          let without = List.filteri !cur ~f:(fun i _ -> i <> index) in
          ops.remove parent l.widget;
          ops.insert parent ~after:(after_of without index) ~node:item l'.widget);
        cur := List.mapi !cur ~f:(fun i x -> if i = index then l' else x)
```
Note `old_node` is captured *before* `patch` writes `live.node <- node`, which it does at the end — reading it afterwards would hand the hook two identical nodes and every parent-held setting would silently stop updating. That is the single most likely bug in this task; the live test's `measure_overlay` flip is what catches it.

`destroy` and `disarm` recurse with `Children.iter`, which handles `Slots` for free.

- [ ] **Step 7: `src/widgets/w_box.ml`** — adapt to the new record: `insert = (fun parent ~after ~node:_ child -> ...)`, `updated = Widget_impl.no_list_update`.

- [ ] **Step 8: `vtree/attr.ml(i)` — `measure_overlay`**

```ocaml
(* Name.t: *) | Measure_overlay
(* t:      *) | Measure_overlay of bool

(** For a child of [Node.overlay]'s [~overlays]: whether the overlay's own size request
    takes this child into account. [false] -- the useful case -- lets an overlay be laid
    out at the size of its *main* child and merely painted over, which is how an image is
    kept from dictating the size of what contains it.

    Inert on any other widget: it is a setting the *overlay* holds about this child, not a
    property of the child, so no other container reads it. *)
let measure_overlay b = Measure_overlay b
```
`is_event` → `false`. `Attr_apply.set`/`unset` → inert arms, with the comment already drafted in Task 2 covering the whole "container-placement attrs" group.

- [ ] **Step 9: `vtree/kind.ml(i)` / `node.ml(i)`**

```ocaml
type center_box_props = { shrink_center_last : bool } [@@deriving sexp_of, equal]

type paned_props =
  { orientation : Orientation.t
  ; position : int option
  ; wide_handle : bool
  ; resize_start : bool
  ; resize_end : bool
  ; shrink_start : bool
  ; shrink_end : bool
  }
[@@deriving sexp_of, equal]

type overlay_props = unit [@@deriving sexp_of, equal]
```
```ocaml
let center_box ?key ?attrs ?(shrink_center_last = true) ?start ?center ?end_ () =
  make
    ?key
    ?attrs
    (Center_box { shrink_center_last })
    (Slots [ "start", Single start; "center", Single center; "end", Single end_ ])
;;

let paned
  ?key ?attrs ?position ?(wide_handle = false) ?(resize_start = true) ?(resize_end = true)
  ?(shrink_start = false) ?(shrink_end = false) ~orientation ~start ~end_
  =
  make
    ?key
    ?attrs
    (Paned
       { orientation; position; wide_handle; resize_start; resize_end; shrink_start; shrink_end })
    (Slots [ "start", Single (Some start); "end", Single (Some end_) ])
;;

let overlay ?key ?attrs ?(overlays = []) child =
  make ?key ?attrs (Overlay ()) (Slots [ "child", Single (Some child); "overlays", List overlays ])
;;
```
`Paned` takes both halves as required arguments: a paned with one side is a box, and GTK renders an empty half as dead space with a draggable handle into nothing. `position = None` leaves GTK's own (the halves' natural split); `Some n` pins it, and — unlike the toggles — it is *not* controlled, because the user drags the handle continuously and pinning it every frame makes it undraggable. Document that on the constructor, and expose `Attr.on_position_changed` so an app that wants to own the position can store what the user chose. (Deferred: `on_position_changed` is not in M1's attr list; if it is wanted, it is three lines beside `on_expanded_changed`. Note it in the mli as available on request rather than shipping an untested attr.)

- [ ] **Step 10: `src/widgets/w_center_box.ml`**

```ocaml
open! Core
open Bonsai_gtk_vtree
open Gtk_import

let impl : Widget_impl.t =
  { name = "CenterBox"
  ; create =
      (fun (kind : Kind.t) ->
        match kind with
        | Center_box p ->
          let b = W.Center_box.new_ () in
          if not p.shrink_center_last then W.Center_box.set_shrink_center_last b false;
          (b :> Widget.t)
        | k -> Widget_impl.wrong_kind "CenterBox" k)
  ; update =
      (fun w ~(old : Kind.t) (new_ : Kind.t) ->
        match old, new_ with
        | Center_box old, Center_box new_ ->
          if not (Bool.equal old.shrink_center_last new_.shrink_center_last)
          then W.Center_box.set_shrink_center_last (cast w) new_.shrink_center_last
        | _, k -> Widget_impl.wrong_kind "CenterBox" k)
  ; signals = []
  ; children =
      Widget_impl.Slots
        [ "start", Slot_single { set = (fun w c -> W.Center_box.set_start_widget (cast w) c) }
        ; "center", Slot_single { set = (fun w c -> W.Center_box.set_center_widget (cast w) c) }
        ; "end", Slot_single { set = (fun w c -> W.Center_box.set_end_widget (cast w) c) }
        ]
  }
;;
```

- [ ] **Step 11: `src/widgets/w_paned.ml`**

```ocaml
open! Core
open Bonsai_gtk_vtree
open Gtk_import

let orientation : Orientation.t -> Gtk_enums.orientation = function
  | Horizontal -> `HORIZONTAL
  | Vertical -> `VERTICAL
;;

let impl : Widget_impl.t =
  { name = "Paned"
  ; create =
      (fun (kind : Kind.t) ->
        match kind with
        | Paned p ->
          let pane = W.Paned.new_ (orientation p.orientation) in
          let w = (pane :> Widget.t) in
          Widget_impl.batch w (fun () ->
            Option.iter p.position ~f:(W.Paned.set_position pane);
            W.Paned.set_wide_handle pane p.wide_handle;
            W.Paned.set_resize_start_child pane p.resize_start;
            W.Paned.set_resize_end_child pane p.resize_end;
            W.Paned.set_shrink_start_child pane p.shrink_start;
            W.Paned.set_shrink_end_child pane p.shrink_end);
          w
        | k -> Widget_impl.wrong_kind "Paned" k)
  ; update =
      (fun w ~(old : Kind.t) (new_ : Kind.t) ->
        match old, new_ with
        | Paned old, Paned new_ ->
          let pane : W.Paned.t = cast w in
          Widget_impl.batch w (fun () ->
            if not (Orientation.equal old.orientation new_.orientation)
            then
              W.Orientable.set_orientation
                (W.Orientable.from_gobject w)
                (orientation new_.orientation);
            (* Not controlled: the user drags the handle continuously, and re-asserting the
               position every frame would make it undraggable. Only an actual change in
               what the model asks for moves it. *)
            if not (Option.equal Int.equal old.position new_.position)
            then Option.iter new_.position ~f:(W.Paned.set_position pane);
            if not (Bool.equal old.wide_handle new_.wide_handle)
            then W.Paned.set_wide_handle pane new_.wide_handle;
            if not (Bool.equal old.resize_start new_.resize_start)
            then W.Paned.set_resize_start_child pane new_.resize_start;
            if not (Bool.equal old.resize_end new_.resize_end)
            then W.Paned.set_resize_end_child pane new_.resize_end;
            if not (Bool.equal old.shrink_start new_.shrink_start)
            then W.Paned.set_shrink_start_child pane new_.shrink_start;
            if not (Bool.equal old.shrink_end new_.shrink_end)
            then W.Paned.set_shrink_end_child pane new_.shrink_end)
        | _, k -> Widget_impl.wrong_kind "Paned" k)
  ; signals = []
  ; children =
      Widget_impl.Slots
        [ "start", Slot_single { set = (fun w c -> W.Paned.set_start_child (cast w) c) }
        ; "end", Slot_single { set = (fun w c -> W.Paned.set_end_child (cast w) c) }
        ]
  }
;;
```

- [ ] **Step 12: `src/widgets/w_overlay.ml`**

```ocaml
open! Core
open Bonsai_gtk_vtree
open Gtk_import

(* The overlay holds this about each of its overlay children; it is not a property of the
   child, so it rides on the child node's attrs and is read here (see [Attr.measure_overlay]).
   Default [true] is GTK's. *)
let measure (node : Node.t) =
  match Attrs.find node.attrs Measure_overlay with
  | Some (Measure_overlay b) -> b
  | _ -> true
;;

let impl : Widget_impl.t =
  { name = "Overlay"
  ; create =
      (fun (kind : Kind.t) ->
        match kind with
        | Overlay () -> (W.Overlay.new_ () :> Widget.t)
        | k -> Widget_impl.wrong_kind "Overlay" k)
  ; update =
      (fun _w ~(old : Kind.t) (new_ : Kind.t) ->
        match old, new_ with
        | Overlay (), Overlay () -> ()
        | _, k -> Widget_impl.wrong_kind "Overlay" k)
  ; signals = []
  ; children =
      Widget_impl.Slots
        [ "child", Slot_single { set = (fun w c -> W.Overlay.set_child (cast w) c) }
        ; ( "overlays"
          , Slot_list
              { insert =
                  (fun parent ~after:_ ~node child ->
                    (* GTK has no "insert an overlay at a position": overlays stack in the
                       order added, and [after] is unusable. Order among overlays is
                       therefore *not* reconciled -- a reorder in the node list leaves the
                       painting order alone. Keys still preserve identity, which is what
                       matters; a stack whose paint order must change is a case for
                       separate keys per layer. *)
                    W.Overlay.add_overlay (cast parent) child;
                    W.Overlay.set_measure_overlay (cast parent) child (measure node))
              ; move = (fun _parent ~child:_ ~after:_ -> ())
              ; remove = (fun parent child -> W.Overlay.remove_overlay (cast parent) child)
              ; updated =
                  (fun parent ~old ~node child ->
                    if not (Bool.equal (measure old) (measure node))
                    then W.Overlay.set_measure_overlay (cast parent) child (measure node))
              } )
        ]
  }
;;
```

- [ ] **Step 13: Registry, `Live_tree`**

`Live_tree` cannot read `measure-overlay` off a child without the parent, so print it from the parent's side: in `dump`, when `ty` is `"GtkOverlay"`, print `(unmeasured (<index> ...))` listing the indices of children the overlay does not measure. Concretely:
```ocaml
     | "GtkOverlay" ->
       let o = cast w in
       (match
          List.filter_mapi (widget_children w) ~f:(fun i c ->
            if W.Overlay.get_measure_overlay o c then None else Some i)
        with
        | [] -> []
        | idxs -> [ [%sexp `unmeasured (idxs : int list)] ])
```

- [ ] **Step 14: Run, read, promote, `./scripts/ci.sh`.**
Read for: the center box's middle slot disappearing without disturbing start/end; the overlay's second dump listing the badge as unmeasured *and* holding the new `extra` overlay; the paned printing both halves. Then commit.

- [ ] **Step 15: Commit**

```bash
dune fmt 2>/dev/null; git add vtree src test
GIT_EDITOR=true git commit -F - <<'MSG'
Named child slots; CenterBox, Paned, Overlay

Children.t gains [Slots], the spec's fourth shape: children addressed by role,
each slot carrying its own Single/List shape and patched by the same code.

List child ops now see the child node, and gain an [updated] hook, because
some per-child settings live on the parent -- an overlay's measure flag, and
Task 9's grid cells and stack page titles. They ride on the child node's attrs
and the parent impl reads them.

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01Sg3Ci8U8kUKR8C3PL1pNSs
MSG
```

---

