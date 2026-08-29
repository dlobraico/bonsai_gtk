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
  ; slots : Signals.slots
  ; handler_ids : Gobject.Signal.handler_id list
  ; mutable children : live Children.t
  }

let child_path path i = sprintf "%s/%d" path i

let rec mount ctx ~path (node : Node.t) : live =
  let impl = Registry.for_kind node.kind in
  let widget = impl.create node.kind in
  Attr_apply.apply_all widget node.attrs;
  let slots, handler_ids =
    Signals.connect_all ctx.signals ~node_path:path widget impl.signals
  in
  Signals.update_slots slots node.attrs;
  let children =
    match node.children, impl.children with
    | No_children, _ -> Children.No_children
    | Single c, Single { set } ->
      let live_c = Option.map c ~f:(fun c -> mount ctx ~path:(child_path path 0) c) in
      set widget (Option.map live_c ~f:(fun l -> l.widget));
      Single live_c
    | List cs, List { insert; _ } ->
      let lives = List.mapi cs ~f:(fun i c -> mount ctx ~path:(child_path path i) c) in
      List.iteri lives ~f:(fun i l -> insert widget ~index:i l.widget);
      List lives
    | (Single _ | List _), _ ->
      invalid_argf "%s: node has children but %s takes none" path impl.name ()
  in
  (match node.kind with
   | Window _ -> ctx.on_window_created widget
   | _ -> ());
  { node; widget; impl; slots; handler_ids; children }

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

and patch ctx ~path (live : live) (node : Node.t) : live =
  if not (Kind.same_kind live.node.kind node.kind)
  then (
    (* Mount before destroying: the caller re-parents the fresh widget, and mounting first
       keeps the old subtree alive (and parented) until the replacement exists. *)
    let fresh = mount ctx ~path node in
    destroy ctx live;
    fresh)
  else (
    if not (Kind.equal_props live.node.kind node.kind)
    then live.impl.update live.widget ~old:live.node.kind node.kind;
    List.iter
      (Attrs.diff ~old:live.node.attrs ~new_:node.attrs)
      ~f:(Attr_apply.apply live.widget);
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
       set live.widget None;
       destroy ctx o;
       Single None
     | None, Some n ->
       let l = mount ctx ~path:(child_path path 0) n in
       set live.widget (Some l.widget);
       Single (Some l)
     | Some o, Some n ->
       let l = patch ctx ~path:(child_path path 0) o n in
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
       the indices the reconciler computed stay valid — and so does GTK's own child order,
       which the [insert]/[move] ops read back to find their sibling. *)
    let cur = ref olds in
    List.iter ops ~f:(fun (op : Node.t Reconcile.op) ->
      match op with
      | Remove { index } ->
        let l = List.nth_exn !cur index in
        remove live.widget l.widget;
        destroy ctx l;
        cur := List.filteri !cur ~f:(fun i _ -> i <> index)
      | Insert { index; item } ->
        let l = mount ctx ~path:(child_path path index) item in
        insert live.widget ~index l.widget;
        cur := List.take !cur index @ (l :: List.drop !cur index)
      | Move { from; to_ } ->
        let l = List.nth_exn !cur from in
        move live.widget ~child:l.widget ~to_;
        let without = List.filteri !cur ~f:(fun i _ -> i <> from) in
        cur := List.take without to_ @ (l :: List.drop without to_)
      | Update { index; item; old = _ } ->
        let l = List.nth_exn !cur index in
        let l' = patch ctx ~path:(child_path path index) l item in
        if not (phys_equal l l')
        then (
          (* The kind changed, so [patch] mounted a replacement and destroyed [l]. [l]'s
             widget was still parented while it was destroyed, which is what we want for
             the widgets M0 can hold here: destroying a non-window live only disconnects
             it. A [Window] live in a list would be destroyed for real before this
             [remove], which is fine (its own [destroy] unparents it) but is worth
             re-checking if windows ever become list children. *)
          remove live.widget l.widget;
          insert live.widget ~index l'.widget);
        cur := List.mapi !cur ~f:(fun i x -> if i = index then l' else x));
    List !cur
  | (No_children | Single _ | List _), _, _ ->
    invalid_argf
      "%s: %s's children changed shape under an unchanged kind"
      path
      live.impl.name
      ()
;;
