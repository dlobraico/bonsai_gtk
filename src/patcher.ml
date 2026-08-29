open! Core
open Bonsai_gtk_vtree
open Gtk_import

type ctx =
  { signals : Signals.ctx
  ; on_window_created : Widget.t -> unit
  }

type live =
  { mutable node : Node.t
  ; widget : Widget.t
  ; impl : Widget_impl.t
  ; defaults : Attr_apply.defaults
  ; slots : Signals.slots
  ; handler_ids : Gobject.Signal.handler_id list
  ; mutable children : live Children.t
  }

let child_path path i = sprintf "%s/%d" path i

(* Spec §11: structural misuse is rejected loudly and early. A [GtkWindow] is a toplevel,
   so parenting one would make GTK log a critical and leave a silently broken tree — and
   under [Loop] the runtime would additionally present it as if it were a real window. *)
let check_placement ~path ~is_root (node : Node.t) =
  match node.kind with
  | Window _ when not is_root ->
    invalid_argf
      "%s: a Node.window may only be the root node, not a child of another node"
      path
      ()
  | _ -> ()
;;

let rec mount ctx ~path ~is_root (node : Node.t) : live =
  check_placement ~path ~is_root node;
  let impl = Registry.for_kind node.kind in
  let widget = impl.create node.kind in
  (* After [create] has applied the kind's props but before any attribute touches it:
     these are the widget's own creation-time values, which is what a later [Unset]
     restores. *)
  let defaults = Attr_apply.snapshot widget in
  Attr_apply.apply_all widget node.attrs;
  let slots, handler_ids =
    Signals.connect_all ctx.signals ~node_path:path widget impl.signals
  in
  Signals.update_slots slots node.attrs;
  let children =
    match node.children, impl.children with
    | No_children, _ -> Children.No_children
    | Single c, Single { set } ->
      let live_c =
        Option.map c ~f:(fun c -> mount ctx ~path:(child_path path 0) ~is_root:false c)
      in
      set widget (Option.map live_c ~f:(fun l -> l.widget));
      Single live_c
    | List cs, List { insert; _ } ->
      let lives =
        List.mapi cs ~f:(fun i c -> mount ctx ~path:(child_path path i) ~is_root:false c)
      in
      List.fold lives ~init:None ~f:(fun after l ->
        insert widget ~after l.widget;
        Some l.widget)
      |> (ignore : Widget.t option -> unit);
      List lives
    | (Single _ | List _), _ ->
      invalid_argf "%s: node has children but %s takes none" path impl.name ()
  in
  (match node.kind with
   | Window _ -> ctx.on_window_created widget
   | _ -> ());
  { node; widget; impl; defaults; slots; handler_ids; children }

and destroy ctx (live : live) =
  (* Slots are emptied before anything is torn down: GTK emits signals synchronously from
     [remove]/[set_child], and a handler firing here would run against a node that is
     already gone. *)
  Signals.clear_slots live.slots;
  Signals.disconnect live.widget live.handler_ids;
  (match live.children with
   | No_children -> ()
   | Single c -> Option.iter c ~f:(destroy ctx)
   | List l -> List.iter l ~f:(destroy ctx));
  match live.node.kind with
  (* A window has no parent to unparent it, so it must be destroyed explicitly. *)
  | Window _ -> W.Window.destroy (cast live.widget)
  | Native n -> Native_gtk.destroy_payload n live.widget
  | Label _ | Button _ | Box _ -> ()

(* Empties every slot in a subtree without tearing anything down.

   [destroy] clears slots too, but on the paths where GTK unparents a subtree *before* it
   is destroyed the clearing would come too late: GTK emits signals synchronously from
   [remove]/[set_child], so a handler could fire against a node Bonsai is in the middle of
   dropping. Disarming first closes that window. The obvious alternative — destroy, then
   remove — is wrong: [destroy] on a window live really destroys the window, so a window
   ever appearing as a container child would be freed before the [remove] that names it. *)
and disarm (live : live) =
  Signals.clear_slots live.slots;
  match live.children with
  | No_children -> ()
  | Single c -> Option.iter c ~f:disarm
  | List l -> List.iter l ~f:disarm

and patch ctx ~path ~is_root (live : live) (node : Node.t) : live =
  check_placement ~path ~is_root node;
  if not (Kind.same_kind live.node.kind node.kind)
  then (
    (* Mount before destroying: the caller re-parents the fresh widget, and mounting first
       keeps the old subtree alive (and parented) until the replacement exists. *)
    let fresh = mount ctx ~path ~is_root node in
    destroy ctx live;
    fresh)
  else (
    if not (Kind.equal_props live.node.kind node.kind)
    then live.impl.update live.widget ~old:live.node.kind node.kind;
    List.iter
      (Attrs.diff ~old:live.node.attrs ~new_:node.attrs)
      ~f:(Attr_apply.apply ~defaults:live.defaults live.widget);
    Signals.update_slots live.slots node.attrs;
    live.children <- patch_children ctx ~path live node;
    live.node <- node;
    live)

and patch_children ctx ~path (live : live) (node : Node.t) : live Children.t =
  match live.children, node.children, live.impl.children with
  | No_children, No_children, _ -> No_children
  | Single old_c, Single new_c, Single { set } ->
    (match old_c, new_c with
     | None, None -> Single None
     | Some o, None ->
       disarm o;
       set live.widget None;
       destroy ctx o;
       Single None
     | None, Some n ->
       let l = mount ctx ~path:(child_path path 0) ~is_root:false n in
       set live.widget (Some l.widget);
       Single (Some l)
     | Some o, Some n ->
       let l = patch ctx ~path:(child_path path 0) ~is_root:false o n in
       (* [patch] returns a different record only when the kind changed, in which case the
          old widget is still the container's child; [set] replaces (and unparents) it. *)
       if not (phys_equal l o) then set live.widget (Some l.widget);
       Single (Some l))
  | List olds, List news, List { insert; move; remove } ->
    let ops =
      Reconcile.diff
        ~key:(fun (n : Node.t) -> n.key)
        ~same_kind:(fun a b -> Kind.same_kind a.Node.kind b.Node.kind)
        ~old:(List.map olds ~f:(fun l -> l.node))
        ~new_:news
    in
    (* [cur] mirrors, over lives, exactly what [Reconcile.apply] would do over nodes, so
       the indices the reconciler computed stay valid — and so [cur] is also what every op
       reads its placement out of. *)
    (* The widget a child at [index] must be placed after, read off the patcher's own list
       rather than GTK's: a container that interposes children of its own (list-box rows,
       stack pages) has a live child list that does not match these indices. *)
    let after_of cur index =
      if index = 0 then None else Some (List.nth_exn cur (index - 1)).widget
    in
    let cur = ref olds in
    List.iter ops ~f:(fun (op : Node.t Reconcile.op) ->
      match op with
      | Remove { index } ->
        let l = List.nth_exn !cur index in
        disarm l;
        remove live.widget l.widget;
        destroy ctx l;
        cur := List.filteri !cur ~f:(fun i _ -> i <> index)
      | Insert { index; item } ->
        let l = mount ctx ~path:(child_path path index) ~is_root:false item in
        insert live.widget ~after:(after_of !cur index) l.widget;
        cur := List.take !cur index @ (l :: List.drop !cur index)
      | Move { from; to_ } ->
        let l = List.nth_exn !cur from in
        (* [to_] indexes the list as it will be *after* the move, so the predecessor is
           computed with [l] already removed. *)
        let without = List.filteri !cur ~f:(fun i _ -> i <> from) in
        move live.widget ~child:l.widget ~after:(after_of without to_);
        cur := List.take without to_ @ (l :: List.drop without to_)
      | Update { index; item; old = _ } ->
        let l = List.nth_exn !cur index in
        let l' = patch ctx ~path:(child_path path index) ~is_root:false l item in
        if not (phys_equal l l')
        then (
          (* The kind changed, so [patch] mounted a replacement and destroyed [l]; [l]'s
             widget is still parented here. Remove it, then place the replacement where it
             was — [after] over the list with [l] taken out. ([l]'s widget was still
             parented while it was destroyed, which is what we want for the widgets M0 can
             hold here: destroying a non-window live only disconnects it. A [Window] live
             in a list would be destroyed for real before this [remove], which is fine —
             its own [destroy] unparents it — but is worth re-checking if windows ever
             become list children.) *)
          let without = List.filteri !cur ~f:(fun i _ -> i <> index) in
          remove live.widget l.widget;
          insert live.widget ~after:(after_of without index) l'.widget);
        cur := List.mapi !cur ~f:(fun i x -> if i = index then l' else x));
    List !cur
  | (No_children | Single _ | List _), _, _ ->
    invalid_argf
      "%s: %s's children changed shape under an unchanged kind"
      path
      live.impl.name
      ()
;;
