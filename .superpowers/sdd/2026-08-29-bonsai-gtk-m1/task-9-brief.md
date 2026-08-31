### Task 9: Placement-by-attr — Grid, Stack, StackSwitcher, StackSidebar

The last four widgets, and the two remaining pieces of container machinery: children placed by *coordinates* rather than by order (`Grid`), and widgets that refer to *another widget in the tree* (`StackSwitcher`/`StackSidebar` need the `GtkStack` they drive). Task 8's node-aware list ops carry the first; the second needs a name registry and a post-patch fixup pass.

**Files:**
- Create: `vtree/grid_cell.ml`, `vtree/stack_transition.ml`, `src/widgets/w_grid.ml`, `src/widgets/w_stack.ml`, `src/widgets/w_stack_switcher.ml`, `src/widgets/w_stack_sidebar.ml`
- Modify: `vtree/attr.ml(i)`, `vtree/kind.ml(i)`, `vtree/node.ml(i)`, `vtree/bonsai_gtk_vtree.ml`, `src/patcher.ml`, `src/patcher.mli`, `src/driver.ml`, `src/widgets/registry.ml`, `src/live_tree.ml`, `src/bonsai_gtk.ml(i)`, `test/test_widgets.ml`, `test/live/live_patcher.ml`, `test/live/live_controls.ml`, `test/live/live_containers.ml`

**Interfaces:**
- Produces:
  ```ocaml
  (* vtree *)
  module Grid_cell : sig
    type t = { column : int; row : int; width : int; height : int }
    [@@deriving sexp_of, equal, compare]
  end
  module Stack_transition : sig
    type t = None_ | Crossfade | Slide_right | Slide_left | Slide_up | Slide_down
           | Slide_left_right | Slide_up_down | Over_up | Over_down | Over_left | Over_right
           | Under_up | Under_down | Under_left | Under_right | Rotate_left | Rotate_right
  end

  (* Attr *)
  val grid_cell : column:int -> row:int -> ?width:int -> ?height:int -> unit -> t
  val page_title : string -> t
  val on_visible_child_changed : (string -> unit Ui_effect.t) -> t

  (* Node *)
  val grid
    :  ?key:Key.t -> ?attrs:Attr.t list -> ?row_spacing:int -> ?column_spacing:int
    -> ?row_homogeneous:bool -> ?column_homogeneous:bool -> t list -> t
  val stack
    :  ?key:Key.t -> ?attrs:Attr.t list -> ?transition:Stack_transition.t
    -> ?transition_duration:int -> ?hhomogeneous:bool -> ?vhomogeneous:bool
    -> name:string -> visible_child:string -> t list -> t
  val stack_switcher : ?key:Key.t -> ?attrs:Attr.t list -> stack:string -> unit -> t
  val stack_sidebar : ?key:Key.t -> ?attrs:Attr.t list -> stack:string -> unit -> t

  (* Patcher *)
  val create_ctx
    :  signals:Signals.ctx
    -> on_window_created:(Widget.t -> unit)
    -> ctx
  val run_fixups : ctx -> unit
  ```

Three design points, each with a live-test consequence:

1. **Grid children are placed by an attr.** `gtk_grid_attach(grid, child, col, row, w, h)` is a call on the *parent*, so the coordinates ride on the child node's attrs exactly as `measure_overlay` does, and are read by the grid's `insert`/`updated` ops. A grid child with no `Attr.grid_cell` is `Invalid_argument` naming the path — there is no sensible default, and silently stacking every child at (0,0) is the worst possible failure. Spec §7's note ("`Grid` children are re-`attach`ed on any coordinate change") is what `updated` implements: GTK has no "move an attached child", so a cell change is `remove` then `attach`.
2. **Grid's `move` is a no-op.** Order in the node list carries no meaning for a grid; the cell does. Reordering the children of a `Node.grid` without changing their cells must not touch GTK, and the reconciler's `Move` ops are therefore dropped. `Key.t` still governs identity, which is what preserves a cell's widget (and its focus, and its entry text) across a re-render.
3. **StackSwitcher/StackSidebar name their stack.** They need a live `GtkStack` handle, which the vtree cannot hold. `Node.stack ~name:"nav"` registers its widget under that name in the patcher's ctx, and the switcher/sidebar enqueue a *fixup* — a closure run after the whole tree has been mounted or patched — that resolves the name and calls `set_stack`. Resolving after the pass, rather than during it, makes the order of the two nodes in the tree irrelevant (a switcher above its stack is the common layout). An unresolvable name is `Invalid_argument` at fixup time, naming both the switcher's path and the name it wanted. See Open Question 3.

`Stack`'s own list ops need one more accommodation: GTK offers no way to insert a page at a position or reorder pages, so `insert` ignores `after` (pages land in add order) and `move` is a no-op, like `Overlay`'s. Page *order* only affects the button order in a `StackSwitcher`; page *identity* and *selection* are by name, which is the node's `Key.t` and is fully reconciled. Document it on `Node.stack`.

- [ ] **Step 1: Failing headless test** (`test/test_widgets.ml`)

```ocaml
let%expect_test "grid children carry their cells; stack pages carry their keys" =
  print_s
    [%sexp
      (Node.grid
         ~row_spacing:6
         ~column_spacing:12
         [ Node.label ~attrs:[ Attr.grid_cell ~column:0 ~row:0 () ] "Name"
         ; Node.entry ~attrs:[ Attr.grid_cell ~column:1 ~row:0 () ] ~text:"" ()
         ; Node.label
             ~attrs:[ Attr.grid_cell ~column:0 ~row:1 ~width:2 () ]
             "spans both columns"
         ]
       : Node.t)];
  [%expect {| |}];
  print_s
    [%sexp
      (Node.box
         ~orientation:Vertical
         [ Node.stack_switcher ~stack:"nav" ()
         ; Node.stack
             ~name:"nav"
             ~visible_child:"library"
             [ Node.label ~key:"library" ~attrs:[ Attr.page_title "Library" ] "L"
             ; Node.label ~key:"practice" ~attrs:[ Attr.page_title "Practice" ] "P"
             ]
         ]
       : Node.t)];
  [%expect {| |}]
;;
```

- [ ] **Step 2: Failing live test** — append to `test/live/live_containers.ml`

Two claims only a live test can make: a re-celled child is re-attached rather than duplicated, and a switcher finds a stack declared *after* it.

```ocaml
  (* Grid: the third child moves cell without changing key, so it must be detached and
     re-attached at the new coordinates -- and be the same GObject afterwards. *)
  let grid_view ~span =
    Node.window
      ~title:"grid"
      (Node.grid
         ~row_spacing:6
         ~column_spacing:12
         [ Node.label ~key:"k" ~attrs:[ Attr.grid_cell ~column:0 ~row:0 () ] "Name"
         ; Node.label ~key:"v" ~attrs:[ Attr.grid_cell ~column:1 ~row:0 () ] "Bach"
         ; Node.label
             ~key:"note"
             ~attrs:
               [ (if span
                  then Attr.grid_cell ~column:0 ~row:1 ~width:2 ()
                  else Attr.grid_cell ~column:0 ~row:2 ())
               ]
             "note"
         ])
  in
  let live = P.mount ctx ~path:"root" ~is_root:true (grid_view ~span:false) in
  print_s (Live_tree.dump live.widget);
  let note_before =
    match live.children with
    | Single (Some g) ->
      (match g.children with
       | List cs -> (List.nth_exn cs 2).widget
       | _ -> assert false)
    | _ -> assert false
  in
  let live = P.patch ctx ~path:"root" ~is_root:true live (grid_view ~span:true) in
  print_s (Live_tree.dump live.widget);
  (match live.children with
   | Single (Some g) ->
     (match g.children with
      | List cs ->
        printf
          "same widget after re-attach: %b\n"
          (Gobject.same note_before (List.nth_exn cs 2).widget)
      | _ -> assert false)
   | _ -> assert false);
  (* A grid child with no cell is a bug worth failing on. *)
  (match
     P.mount
       ctx
       ~path:"root"
       ~is_root:true
       (Node.window ~title:"g" (Node.grid [ Node.label "cell-less" ]))
   with
   | (_ : P.live) -> print_endline "BUG: grid child without a cell accepted"
   | exception Invalid_argument msg -> printf "rejected: %s\n" msg);
  P.destroy ctx live;
  (* Stack: the switcher is declared *above* the stack it drives, so it can only be wired
     up after the whole tree exists -- which is what [run_fixups] is for. *)
  let stack_view ~visible ~pages =
    Node.window
      ~title:"stack"
      (Node.box
         ~orientation:Vertical
         [ Node.stack_switcher ~stack:"nav" ()
         ; Node.stack_sidebar ~stack:"nav" ()
         ; Node.stack
             ~name:"nav"
             ~transition:None_
             ~visible_child:visible
             ~attrs:[ Attr.on_visible_child_changed (fun _ -> Ui_effect.Ignore) ]
             (List.map pages ~f:(fun (key, title) ->
                Node.label ~key ~attrs:[ Attr.page_title title ] key))
         ])
  in
  let live =
    P.mount
      ctx
      ~path:"root"
      ~is_root:true
      (stack_view ~visible:"library" ~pages:[ "library", "Library"; "practice", "Practice" ])
  in
  P.run_fixups ctx;
  print_s (Live_tree.dump live.widget);
  let live =
    P.patch
      ctx
      ~path:"root"
      ~is_root:true
      live
      (stack_view
         ~visible:"practice"
         ~pages:[ "library", "Library!"; "practice", "Practice"; "setlists", "Setlists" ])
  in
  P.run_fixups ctx;
  print_s (Live_tree.dump live.widget);
  (* An unresolvable stack name names both ends of the mistake. *)
  (match
     let live =
       P.mount
         ctx
         ~path:"root"
         ~is_root:true
         (Node.window ~title:"s" (Node.stack_switcher ~stack:"nope" ()))
     in
     P.run_fixups ctx;
     live
   with
   | (_ : P.live) -> print_endline "BUG: unresolvable stack name accepted"
   | exception Invalid_argument msg -> printf "rejected: %s\n" msg);
  P.destroy ctx live
```

- [ ] **Step 3: Run to verify failure.**

- [ ] **Step 4: The two vtree modules**

```ocaml
(* vtree/grid_cell.ml *)
open! Core

(** Where a child sits in a [Node.grid], and how many cells it covers. Columns and rows are
    zero-based and may be sparse -- a grid is not a table, and nothing has to fill row 1
    for something to sit in row 2. *)
type t =
  { column : int
  ; row : int
  ; width : int
  ; height : int
  }
[@@deriving sexp_of, equal, compare]

(* vtree/stack_transition.ml *)
open! Core

type t =
  | None_
  | Crossfade
  | Slide_right
  | Slide_left
  | Slide_up
  | Slide_down
  | Slide_left_right
  | Slide_up_down
  | Over_up
  | Over_down
  | Over_left
  | Over_right
  | Under_up
  | Under_down
  | Under_left
  | Under_right
  | Rotate_left
  | Rotate_right
[@@deriving sexp_of, equal, compare]
```
GTK also has `OVER_UP_DOWN`, `OVER_DOWN_UP`, `OVER_LEFT_RIGHT`, `OVER_RIGHT_LEFT` and `ROTATE_LEFT_RIGHT`; leave them out and say so in the mli — they are the "pick a direction from the child order" variants, and the child order of a `Node.stack` is explicitly not meaningful (point 3 above), so offering them would promise something the widget does not deliver.

- [ ] **Step 5: `vtree/attr.ml(i)` — three attrs**

```ocaml
(* Name.t: *) | Grid_cell | Page_title | On_visible_child_changed
(* t: *)
  | Grid_cell of Grid_cell.t
  | Page_title of string
  | On_visible_child_changed of string Handler.t
```
`equal`: `Grid_cell.equal`, `String.equal`, `Handler.equal`. `is_event`: only the last is `true`. `Attr_apply.set`/`unset`: all three inert (they are read by the parent impl, in the "container-placement attrs" group).

```ocaml
(** Where this child sits in its parent [Node.grid]. Required on every grid child --
    there is no default, and defaulting to (0,0) would stack the whole grid in one cell
    and look like a layout bug rather than a missing attribute.

    [width]/[height] (default 1) are the number of columns and rows spanned. Inert on any
    widget whose parent is not a grid. *)
let grid_cell ~column ~row ?(width = 1) ?(height = 1) () =
  Grid_cell { Grid_cell.column; row; width; height }
;;

(** The label a [Node.stack]'s switcher or sidebar shows for this page. The page's *name*
    -- what [~visible_child] selects it by -- is the node's [Key.t], not this. Inert
    outside a stack. *)
let page_title s = Page_title s

(** Fires when a [Node.stack]'s visible page changes, carrying the new page's name (the
    child's [Key.t]). Programmatic changes -- what [~visible_child] does -- are dropped by
    the reentrancy guard, as always; this is the user clicking a switcher button. *)
let on_visible_child_changed f = On_visible_child_changed f
```

- [ ] **Step 6: `vtree/kind.ml(i)` / `node.ml(i)`**

```ocaml
type grid_props =
  { row_spacing : int
  ; column_spacing : int
  ; row_homogeneous : bool
  ; column_homogeneous : bool
  }
[@@deriving sexp_of, equal]

type stack_props =
  { name : string
  ; visible_child : string
  ; transition : Stack_transition.t
  ; transition_duration : int
  ; hhomogeneous : bool
  ; vhomogeneous : bool
  }
[@@deriving sexp_of, equal]

type stack_ref_props = { stack : string } [@@deriving sexp_of, equal]

(* ... in Kind.t: *)
  | Grid of grid_props
  | Stack of stack_props
  | Stack_switcher of stack_ref_props
  | Stack_sidebar of stack_ref_props
```
`Kind.name`: `"Grid" | "Stack" | "StackSwitcher" | "StackSidebar"`. GTK defaults: spacings `0`, homogeneous flags `false`, `transition = None_`, `transition_duration = 200`, `hhomogeneous = true`, `vhomogeneous = true`.

```ocaml
let grid
  ?key ?attrs ?(row_spacing = 0) ?(column_spacing = 0) ?(row_homogeneous = false)
  ?(column_homogeneous = false) children
  =
  make
    ?key
    ?attrs
    (Grid { row_spacing; column_spacing; row_homogeneous; column_homogeneous })
    (List children)
;;

let stack
  ?key ?attrs ?(transition = Stack_transition.None_) ?(transition_duration = 200)
  ?(hhomogeneous = true) ?(vhomogeneous = true) ~name ~visible_child children
  =
  make
    ?key
    ?attrs
    (Stack
       { name; visible_child; transition; transition_duration; hhomogeneous; vhomogeneous })
    (List children)
;;

let stack_switcher ?key ?attrs ~stack () = make ?key ?attrs (Stack_switcher { stack }) No_children
let stack_sidebar ?key ?attrs ~stack () = make ?key ?attrs (Stack_sidebar { stack }) No_children
```

`Node.stack`'s doc comment carries the three rules a caller must know:
```
    Every child needs a [~key]: it is the GTK page name, it is what [~visible_child]
    selects by, and it is what preserves a page's widgets across a re-render. A child
    without one is [Invalid_argument] at mount.

    Child *order* is not reconciled: GTK offers no way to insert a page at a position or
    to reorder pages, so pages land in the order they are first added and reordering the
    list does nothing. Order only affects the button order in a [stack_switcher]; identity
    and selection are entirely by key.

    [~name] is how a [stack_switcher] or [stack_sidebar] elsewhere in the tree finds this
    stack. Two stacks with the same name in one tree is [Invalid_argument].
```

- [ ] **Step 7: `src/patcher.ml(i)` — the name registry and fixups**

`ctx` gains two mutable fields, and a constructor so callers stop writing the record literal (there are four such literals in `test/live/` and one in `driver.ml`; a constructor means the next field costs nothing):

```ocaml
type ctx =
  { signals : Signals.ctx
  ; on_window_created : Widget.t -> unit
  ; (* Live [GtkStack]s by their [Node.stack ~name]. A [stack_switcher] cannot hold a
       widget -- the vtree has no way to name one -- so it names a stack and is wired up
       after the pass that mounts them both. *)
    stacks : (string, Widget.t) Hashtbl.t
  ; (* Work deferred to the end of a mount/patch pass, so that a node may refer to another
       node regardless of which of them the walk reaches first. *)
    fixups : (unit -> unit) Queue.t
  }

let create_ctx ~signals ~on_window_created =
  { signals
  ; on_window_created
  ; stacks = Hashtbl.create (module String)
  ; fixups = Queue.create ()
  }
;;

let register_stack ctx ~path ~name widget =
  match Hashtbl.add ctx.stacks ~key:name ~data:widget with
  | `Ok -> ()
  | `Duplicate ->
    invalid_argf "%s: two Node.stacks are named %S in one tree" path name ()
;;

let resolve_stack ctx ~path ~name : Widget.t =
  match Hashtbl.find ctx.stacks name with
  | Some w -> w
  | None ->
    invalid_argf
      "%s: no Node.stack is named %S (a stack_switcher/stack_sidebar must name a stack \
       that exists somewhere in the same tree)"
      path
      name
      ()
;;

(* Runs everything deferred by the pass just finished, then empties the queue. Called by
   [Driver.frame] inside the patch guard; live tests call it by hand. Fixups may not
   enqueue further fixups -- nothing needs to, and a queue that feeds itself is a hang. *)
let run_fixups ctx =
  Queue.iter ctx.fixups ~f:(fun f -> f ());
  Queue.clear ctx.fixups
;;
```

In `mount`, after the widget exists and its children are attached, beside the existing `on_window_created` dispatch:

```ocaml
  (match node.kind with
   | Window _ -> ctx.on_window_created widget
   | Stack { name; _ } -> register_stack ctx ~path ~name widget
   | Stack_switcher { stack } ->
     Queue.enqueue ctx.fixups (fun () ->
       W.Stack_switcher.set_stack (cast widget) (Some (cast (resolve_stack ctx ~path ~name:stack))))
   | Stack_sidebar { stack } ->
     Queue.enqueue ctx.fixups (fun () ->
       W.Stack_sidebar.set_stack (cast widget) (cast (resolve_stack ctx ~path ~name:stack)))
   | _ -> ());
```
`Patcher` may not call `W.*` for a specific widget directly if that muddles the layering — if it does, put the two setter closures behind `W_stack_switcher.attach : Widget.t -> Widget.t -> unit` and `W_stack_sidebar.attach` and call those. Prefer that; the patcher should stay widget-agnostic.

In `patch`, the same three cases, because a stack may have been re-created (kind change) or renamed, and a switcher may now name a different stack:
```ocaml
    (match node.kind with
     | Stack { name; _ } ->
       (* Re-register under the (possibly new) name; the old entry is dropped by
          [destroy], which runs before this only in the kind-changed path. *)
       Hashtbl.set ctx.stacks ~key:name ~data:live.widget
     | Stack_switcher { stack } | Stack_sidebar { stack } ->
       Queue.enqueue ctx.fixups (fun () -> ... same as mount ...)
     | _ -> ());
```
Re-enqueueing on every patch, rather than only when the name changed, is deliberate: it is one hashtable lookup and one setter per switcher per frame, and it is the only thing that keeps a switcher pointing at a stack that was itself replaced.

In `destroy`, drop the registration:
```ocaml
  | Stack { name; _ } -> Hashtbl.remove ctx.stacks name
```
placed with the existing `Window`/`Native` arms.

`Driver.frame` drains the queue inside the guard, immediately after the mount/patch:
```ocaml
    Scheduler.with_patch_guard t.scheduler (fun () ->
      t.root <- Some (match t.root with ... );
      Patcher.run_fixups t.ctx);
```
and `Driver.create` builds its ctx with `Patcher.create_ctx`.

- [ ] **Step 8: `src/widgets/w_grid.ml`**

```ocaml
open! Core
open Bonsai_gtk_vtree
open Gtk_import

(* A grid child's coordinates are an argument to a call on the *grid*, not a property of
   the child, so they ride on the child node's attrs and are read here (spec §7). There is
   no default: a grid child with no cell would stack at (0,0) with every other, which
   looks like a layout bug rather than the missing attribute it is. *)
let cell (node : Node.t) =
  match Attrs.find node.attrs Grid_cell with
  | Some (Grid_cell c) -> c
  | _ ->
    invalid_argf
      "Grid child has no Attr.grid_cell (every child of a Node.grid needs one)"
      ()
;;

let attach parent (node : Node.t) child =
  let c = cell node in
  W.Grid.attach (cast parent) child c.column c.row c.width c.height
;;

let impl : Widget_impl.t =
  { name = "Grid"
  ; create =
      (fun (kind : Kind.t) ->
        match kind with
        | Grid p ->
          let g = W.Grid.new_ () in
          let w = (g :> Widget.t) in
          Widget_impl.batch w (fun () ->
            W.Grid.set_row_spacing g p.row_spacing;
            W.Grid.set_column_spacing g p.column_spacing;
            W.Grid.set_row_homogeneous g p.row_homogeneous;
            W.Grid.set_column_homogeneous g p.column_homogeneous);
          w
        | k -> Widget_impl.wrong_kind "Grid" k)
  ; update =
      (fun w ~(old : Kind.t) (new_ : Kind.t) ->
        match old, new_ with
        | Grid old, Grid new_ ->
          let g : W.Grid.t = cast w in
          Widget_impl.batch w (fun () ->
            if old.row_spacing <> new_.row_spacing
            then W.Grid.set_row_spacing g new_.row_spacing;
            if old.column_spacing <> new_.column_spacing
            then W.Grid.set_column_spacing g new_.column_spacing;
            if not (Bool.equal old.row_homogeneous new_.row_homogeneous)
            then W.Grid.set_row_homogeneous g new_.row_homogeneous;
            if not (Bool.equal old.column_homogeneous new_.column_homogeneous)
            then W.Grid.set_column_homogeneous g new_.column_homogeneous)
        | _, k -> Widget_impl.wrong_kind "Grid" k)
  ; signals = []
  ; children =
      Widget_impl.List
        { insert = (fun parent ~after:_ ~node child -> attach parent node child)
        ; (* Order in the node list means nothing to a grid; the cell is the placement, so
             a reorder that keeps the cells must not touch GTK. *)
          move = (fun _parent ~child:_ ~after:_ -> ())
        ; remove = (fun parent child -> W.Grid.remove (cast parent) child)
        ; updated =
            (fun parent ~old ~node child ->
              (* GTK has no "move an attached child": a coordinate change is a detach and
                 a re-attach of the same widget (spec §7). *)
              if not (Grid_cell.equal (cell old) (cell node))
              then (
                W.Grid.remove (cast parent) child;
                attach parent node child))
        }
  }
;;
```
The `cell` error message has no path in it; `Patcher` is what knows the path. Either thread it (make `cell` take `~path`, and have the ops take it from... they cannot) or catch and re-raise in the patcher. Simplest correct answer: have `insert`/`updated` raise as above, and let `Patcher.mount_list`/`patch_list` wrap each op call in a `try ... with Invalid_argument msg -> invalid_argf "%s: %s" path msg ()`. Add that wrapper once in the patcher's list helpers; it improves every container's errors, not just the grid's.

- [ ] **Step 9: `src/widgets/w_stack.ml`**

```ocaml
open! Core
open Bonsai_gtk_vtree
open Gtk_import

let transition : Stack_transition.t -> Gtk_enums.stacktransitiontype = function
  | None_ -> `NONE
  | Crossfade -> `CROSSFADE
  | Slide_right -> `SLIDE_RIGHT
  | Slide_left -> `SLIDE_LEFT
  | Slide_up -> `SLIDE_UP
  | Slide_down -> `SLIDE_DOWN
  | Slide_left_right -> `SLIDE_LEFT_RIGHT
  | Slide_up_down -> `SLIDE_UP_DOWN
  | Over_up -> `OVER_UP
  | Over_down -> `OVER_DOWN
  | Over_left -> `OVER_LEFT
  | Over_right -> `OVER_RIGHT
  | Under_up -> `UNDER_UP
  | Under_down -> `UNDER_DOWN
  | Under_left -> `UNDER_LEFT
  | Under_right -> `UNDER_RIGHT
  | Rotate_left -> `ROTATE_LEFT
  | Rotate_right -> `ROTATE_RIGHT
;;

(* A page's name is the child's key: it is what [~visible_child] selects by and what the
   reconciler matches on, so making them the same value is what keeps the two agreeing. *)
let page_name (node : Node.t) =
  match node.key with
  | Some key -> key
  | None ->
    invalid_arg "Stack child has no ~key (a stack page's key is its GTK page name)"
;;

let page_title (node : Node.t) =
  match Attrs.find node.attrs Page_title with
  | Some (Page_title t) -> Some t
  | _ -> None
;;

(* ocgtk exposes no [on_notify_visible_child_name]; the detailed name goes through the
   generic marshaller (spec §6.4). *)
let visible_child_changed : Signals.spec =
  { attr = Attr.Name.On_visible_child_changed
  ; connect = Signals.notify ~prop:"visible-child-name"
  ; fire =
      (fun w (attr : Attr.t) ->
        match attr with
        | On_visible_child_changed handler ->
          (* [None] only while the stack is empty, which the user cannot click their way
             into; nothing to report then. *)
          Option.map (W.Stack.get_visible_child_name (cast w)) ~f:handler
        | _ -> None)
  }
;;

let impl : Widget_impl.t =
  { name = "Stack"
  ; create =
      (fun (kind : Kind.t) ->
        match kind with
        | Stack p ->
          let s = W.Stack.new_ () in
          let w = (s :> Widget.t) in
          Widget_impl.batch w (fun () ->
            W.Stack.set_transition_type s (transition p.transition);
            W.Stack.set_transition_duration s p.transition_duration;
            W.Stack.set_hhomogeneous s p.hhomogeneous;
            W.Stack.set_vhomogeneous s p.vhomogeneous);
          (* [visible_child] is deliberately not set here: the pages do not exist yet
             (the patcher attaches children after [create]), and naming a page that is not
             there is a GTK warning. The first [update] after mount cannot run either, so
             the selection is applied by the child ops -- see [insert] below. *)
          w
        | k -> Widget_impl.wrong_kind "Stack" k)
  ; update =
      (fun w ~(old : Kind.t) (new_ : Kind.t) ->
        match old, new_ with
        | Stack old, Stack new_ ->
          let s : W.Stack.t = cast w in
          Widget_impl.batch w (fun () ->
            if not (Stack_transition.equal old.transition new_.transition)
            then W.Stack.set_transition_type s (transition new_.transition);
            if old.transition_duration <> new_.transition_duration
            then W.Stack.set_transition_duration s new_.transition_duration;
            if not (Bool.equal old.hhomogeneous new_.hhomogeneous)
            then W.Stack.set_hhomogeneous s new_.hhomogeneous;
            if not (Bool.equal old.vhomogeneous new_.vhomogeneous)
            then W.Stack.set_vhomogeneous s new_.vhomogeneous;
            (* Controlled, against the widget: the user may have clicked a switcher
               button since the last render, and a model that did not follow must put the
               selection back. Skipped when the named page does not exist yet -- children
               are patched after this, and the [insert] below re-asserts it. *)
            if (not
                  (Option.equal
                     String.equal
                     (W.Stack.get_visible_child_name s)
                     (Some new_.visible_child)))
               && Option.is_some (W.Stack.get_child_by_name s new_.visible_child)
            then W.Stack.set_visible_child_name s new_.visible_child)
        | _, k -> Widget_impl.wrong_kind "Stack" k)
  ; signals = [ visible_child_changed ]
  ; children =
      Widget_impl.List
        { insert =
            (fun parent ~after:_ ~node child ->
              (* GTK has no positional insert for pages; they land in add order, which only
                 affects switcher button order. *)
              let name = page_name node in
              (match page_title node with
               | Some title ->
                 ignore (W.Stack.add_titled (cast parent) child (Some name) title : W.Stack_page.t)
               | None ->
                 ignore (W.Stack.add_named (cast parent) child (Some name) : W.Stack_page.t));
              (* The first page GTK receives becomes visible whether or not it is the one
                 the model asked for, and [update] could not assert the selection before
                 the pages existed. Re-assert it here, now that this page does. *)
              ())
        ; move = (fun _parent ~child:_ ~after:_ -> ())
        ; remove = (fun parent child -> W.Stack.remove (cast parent) child)
        ; updated =
            (fun parent ~old ~node child ->
              if not (Option.equal String.equal (page_title old) (page_title node))
              then (
                let page = W.Stack.get_page (cast parent) child in
                W.Stack_page.set_title page (Option.value (page_title node) ~default:"")))
        }
  }
;;
```

The empty `()` and its comment in `insert` mark a real ordering problem that has to be solved rather than commented: `create` cannot select a page (none exist), and `update` runs *before* children are patched, so on the very first frame the stack shows whichever page was added first. Fix it in the patcher rather than in the impl, with the mechanism Step 7 already added — have the `Stack` arm of `mount`/`patch` enqueue a fixup that asserts the selection after the pass:

```ocaml
   | Stack { name; visible_child; _ } ->
     register_stack ctx ~path ~name widget;
     Queue.enqueue ctx.fixups (fun () -> W_stack.select ctx_widget ~visible_child)
```
with, in `w_stack.ml`:
```ocaml
(* Applied as a post-pass fixup: the pages exist only after the children have been
   patched, and naming a page GTK does not have yet is a warning and a no-op. *)
let select (w : Widget.t) ~visible_child =
  let s : W.Stack.t = cast w in
  if (not (Option.equal String.equal (W.Stack.get_visible_child_name s) (Some visible_child)))
     && Option.is_some (W.Stack.get_child_by_name s visible_child)
  then W.Stack.set_visible_child_name s visible_child
;;
```
and the same enqueue in `patch`'s `Stack` arm. Then drop the selection block from `impl.update` entirely — one place decides it, after the tree is complete. Do it that way; the version inside `update` above is left in the plan only to show why it does not work.

- [ ] **Step 10: `src/widgets/w_stack_switcher.ml` and `w_stack_sidebar.ml`**

```ocaml
(* w_stack_switcher.ml *)
open! Core
open Bonsai_gtk_vtree
open Gtk_import

(* Called from the patcher's fixup pass, once the named stack is known to exist. *)
let attach (switcher : Widget.t) (stack : Widget.t) =
  W.Stack_switcher.set_stack (cast switcher) (Some (cast stack))
;;

let impl : Widget_impl.t =
  { name = "StackSwitcher"
  ; create =
      (fun (kind : Kind.t) ->
        match kind with
        (* The stack is wired up by a fixup after the pass, not here: the stack may be
           mounted after this switcher, and often is (a switcher above the stack it
           drives is the ordinary layout). *)
        | Stack_switcher _ -> (W.Stack_switcher.new_ () :> Widget.t)
        | k -> Widget_impl.wrong_kind "StackSwitcher" k)
  ; update =
      (fun _w ~(old : Kind.t) (new_ : Kind.t) ->
        match old, new_ with
        (* Re-pointing at a different stack is also a fixup; nothing to do inline. *)
        | Stack_switcher _, Stack_switcher _ -> ()
        | _, k -> Widget_impl.wrong_kind "StackSwitcher" k)
  ; signals = []
  ; children = Widget_impl.No_children
  }
;;
```
`w_stack_sidebar.ml` is the same file with `Stack_sidebar`, `W.Stack_sidebar.new_`, and `attach` calling `W.Stack_sidebar.set_stack (cast sidebar) (cast stack)` — note the non-optional argument, unlike the switcher's.

- [ ] **Step 11: Registry, `Live_tree`, ctx literals**

Registry: four arms. `Live_tree`:
```ocaml
     | "GtkGrid" ->
       int_prop "row-spacing" (W.Grid.get_row_spacing (cast w)) ~default:0
       @ int_prop "column-spacing" (W.Grid.get_column_spacing (cast w)) ~default:0
       @ (* A grid child's cell is held by the grid, so print it from here. *)
       (match
          List.map (widget_children w) ~f:(fun c ->
            let col, row, width, height = W.Grid.query_child (cast w) c in
            [%sexp (col : int), (row : int), (width : int), (height : int)])
        with
        | [] -> []
        | cells -> [ Sexp.List (Atom "cells" :: cells) ])
     | "GtkStack" ->
       [ [%sexp `visible (W.Stack.get_visible_child_name (cast w) : string option)] ]
```
Print the grid's cells in `widget_children` order so the list lines up with the children printed underneath it. A `GtkStack`'s pages are not `widget_children` in the page sense — the child widgets themselves are what `get_first_child` walks — so the existing recursion is right as it stands.

Replace the four `P.ctx` record literals in `test/live/*.ml` with `P.create_ctx ~signals:{...} ~on_window_created:(...)`.

- [ ] **Step 12: Run, read, promote, `./scripts/ci.sh`.**
Read for: `same widget after re-attach: true` (the claim that a cell change moves rather than rebuilds), the grid's `cells` list changing from `((0 0 1 1) (1 0 1 1) (0 2 1 1))` to `(... (0 1 2 1))`, both rejection messages naming their path, the stack's `visible` following `~visible_child` on both frames — including the first, which is what the fixup exists for — and the switcher gaining a button when the third page appears.

- [ ] **Step 13: Commit**

```bash
dune fmt 2>/dev/null; git add vtree src test
GIT_EDITOR=true git commit -F - <<'MSG'
Grid, Stack, StackSwitcher, StackSidebar

Grid children are placed by Attr.grid_cell -- a call on the parent, so it
rides on the child node and is read by the grid's child ops -- and a cell
change is a detach and re-attach of the same widget, since GTK has no move.
A grid child without a cell is Invalid_argument rather than a silent pile at
(0,0).

StackSwitcher and StackSidebar name their stack, and are wired up by a fixup
pass that runs after the whole tree exists, so a switcher may be declared
above the stack it drives. The stack's own page selection is applied there
too: at [create] time it has no pages to select.

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01Sg3Ci8U8kUKR8C3PL1pNSs
MSG
```

---

