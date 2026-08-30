open! Core
open Bonsai_gtk_vtree
open Gtk_import

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
  | `Duplicate -> invalid_argf "%s: two Node.stacks are named %S in one tree" path name ()
;;

(* Only while the entry is still this widget's: a stack that claimed the name during the
   same pass owns it now, and dropping the one it displaced must not unregister it. *)
let unregister_stack ctx ~name widget =
  match Hashtbl.find ctx.stacks name with
  | Some w when Gobject.same w widget -> Hashtbl.remove ctx.stacks name
  | Some _ | None -> ()
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

(* Runs everything the pass just finished deferred, then empties the queue. Called by
   [Driver.frame] inside the patch guard; a test driving the patcher by hand calls it
   itself. Fixups may not enqueue further fixups -- nothing needs to, and a queue that
   feeds itself is a hang.

   Emptied even when a fixup raises: the queue describes one pass, and carrying a failed
   pass's work into the next one would raise again from a frame that had nothing to do
   with it. *)
let run_fixups ctx =
  Exn.protect
    ~f:(fun () -> Queue.iter ctx.fixups ~f:(fun f -> f ()))
    ~finally:(fun () -> Queue.clear ctx.fixups)
;;

(* The same emptying, for a pass that never reached [run_fixups] because [mount] or
   [patch] raised part-way through it. Without this the queue keeps that pass's closures
   -- which pin the widgets they captured, and which would run against the *next* pass's
   tree if one ever happened. *)
let abandon_fixups ctx = Queue.clear ctx.fixups

type live =
  { mutable node : Node.t
  ; widget : Widget.t
  ; impl : Widget_impl.t
  ; defaults : Attr_apply.defaults
  ; slots : Signals.slots
  ; connections : Signals.connection list
  ; mutable children : live Children.t
  }

let child_path path i = sprintf "%s/%d" path i

(* A container's child op may reject the node it is handed -- a grid child with no
   [Attr.grid_cell], a stack page with no [~key]. The op knows nothing about where in the
   tree it is, so the path is added here rather than threaded into every impl (spec §11).
   Only the op call is wrapped, never the recursive [mount]/[patch] beside it, so a nested
   container's message is prefixed once. *)
let child_op ~path f =
  try f () with
  | Invalid_argument msg -> invalid_argf "%s: %s" path msg ()
;;

(* Every kind whose mount, patch or teardown the patcher itself has something to do about,
   beyond what the impl does. Matched exhaustively at each of the three sites so that a
   new kind with a registration or a fixup cannot be added without the compiler asking. *)
type interest =
  | Nothing
  | Window
  | Stack of Kind.stack_props
  | Stack_ref of [ `Switcher | `Sidebar ] * string

let interest_of_kind (kind : Kind.t) =
  match kind with
  | Window _ -> Window
  | Stack p -> Stack p
  | Stack_switcher { stack } -> Stack_ref (`Switcher, stack)
  | Stack_sidebar { stack } -> Stack_ref (`Sidebar, stack)
  | Label _
  | Button _
  | Toggle_button _
  | Check_button _
  | Switch _
  | Entry _
  | Password_entry _
  | Search_entry _
  | Spin_button _
  | Scale _
  | Progress_bar _
  | Spinner _
  | Image _
  | Picture _
  | Separator _
  | Scrolled_window _
  | Frame _
  | Expander _
  | Revealer _
  | Center_box _
  | Paned _
  | Overlay _
  | Grid _
  | Box _
  | Native _ -> Nothing
;;

(* The deferred half of realizing a node: a window is presented, a stack registers its
   name and asks for its selection to be applied once its pages exist, and a switcher or
   sidebar asks for the stack it names to be looked up once the whole tree does. Shared by
   [mount] and [patch], which differ only in [pass]. *)
let note_interest
  ctx
  ~path
  ~widget
  ~(interest : interest)
  ~(pass : [ `Mount | `Patch of Kind.t ])
  =
  match interest with
  | Nothing -> ()
  | Window ->
    (* Once per window, at mount: the runtime presents it and holds onto it. *)
    (match pass with
     | `Mount -> ctx.on_window_created widget
     | `Patch _ -> ())
  | Stack { name; visible_child; _ } ->
    (match pass with
     | `Mount -> register_stack ctx ~path ~name widget
     | `Patch (Kind.Stack { name = old_name; _ }) when String.equal old_name name ->
       (* The name did not move, so the entry already points here. [set] rather than
          nothing so a registration lost to some earlier teardown heals itself. *)
       Hashtbl.set ctx.stacks ~key:name ~data:widget
     | `Patch (Kind.Stack { name = old_name; _ }) ->
       (* A renamed stack drops its old entry, so a switcher still naming it fails loudly
          rather than driving a stack the tree no longer calls that -- and claims the new
          name through [register_stack], so renaming *onto* a name another stack already
          holds raises exactly as declaring the collision outright would. *)
       Hashtbl.remove ctx.stacks old_name;
       register_stack ctx ~path ~name widget
     | `Patch _ ->
       (* Unreachable: [patch] only gets here when the kinds match. Registering rather
          than assuming is what keeps it harmless if that ever changes. *)
       register_stack ctx ~path ~name widget);
    (* Enqueued rather than applied: the pages are attached after this on a mount, and
       patched after this on a patch, and a page GTK does not have yet cannot be selected. *)
    Queue.enqueue ctx.fixups (fun () -> W_stack.select widget ~visible_child)
  | Stack_ref (which, name) ->
    (* Re-enqueued on every patch rather than only when the name changed: it is one
       hashtable lookup and one setter per switcher per frame, and it is the only thing
       that keeps a switcher pointing at a stack that was itself replaced. *)
    Queue.enqueue ctx.fixups (fun () ->
      let stack = resolve_stack ctx ~path ~name in
      match which with
      | `Switcher -> W_stack_switcher.attach widget stack
      | `Sidebar -> W_stack_sidebar.attach widget stack)
;;

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
  (* Before anything is connected: an event attr no spec claims would create no slot, so
     the handler would never run and nothing would say why (spec §11). *)
  Signals.require_specs ~node_path:path ~impl_name:impl.name node.kind node.attrs;
  let slots, connections =
    Signals.connect_all ctx.signals ~node_path:path widget impl.signals
  in
  Signals.update_slots slots node.attrs;
  let children =
    mount_children ctx ~path ~impl_name:impl.name widget node.children impl.children
  in
  note_interest ctx ~path ~widget ~interest:(interest_of_kind node.kind) ~pass:`Mount;
  { node; widget; impl; defaults; slots; connections; children }

(* One shape, mounted. The three helpers below are what a top-level shape and a slot of
   that shape share: a slot is not a special case, it is the same code under a longer
   path. *)
and mount_single ctx ~path parent ~set (c : Node.t option) : live option =
  let live_c =
    Option.map c ~f:(fun c -> mount ctx ~path:(child_path path 0) ~is_root:false c)
  in
  set parent (Option.map live_c ~f:(fun l -> l.widget));
  live_c

and mount_list ctx ~path parent ~(ops : Widget_impl.list_ops) (cs : Node.t list)
  : live list
  =
  (* Spec §11 says mount *and* patch time. [Reconcile.diff] checks this on the patch path,
     but a first frame never reaches it -- so without this a duplicate key is accepted
     once and rejected on the second frame, which for a [Node.stack] means GTK has already
     been handed two pages with one name and [get_child_by_name] is already ambiguous. *)
  child_op ~path (fun () ->
    Reconcile.check_unique_keys ~key:(fun (n : Node.t) -> n.key) cs);
  let lives =
    List.mapi cs ~f:(fun i c -> mount ctx ~path:(child_path path i) ~is_root:false c)
  in
  List.foldi lives ~init:None ~f:(fun i after l ->
    child_op ~path:(child_path path i) (fun () ->
      ops.insert parent ~after ~node:l.node l.widget);
    Some l.widget)
  |> (ignore : Widget.t option -> unit);
  lives

and mount_slots ctx ~path ~impl_name parent node_slots op_slots =
  (* Slot lists are written by this repository on both sides, and are short and fixed, so
     equal length and equal order is a fair requirement -- and a loud one when broken. *)
  match List.zip node_slots op_slots with
  | Unequal_lengths ->
    invalid_argf
      "%s: %s has %d slots, node has %d"
      path
      impl_name
      (List.length op_slots)
      (List.length node_slots)
      ()
  | Ok pairs ->
    List.map pairs ~f:(fun ((name, cs), (op_name, op)) ->
      if not (String.equal name op_name)
      then invalid_argf "%s: slot %s does not exist on %s" path name impl_name ();
      let path = sprintf "%s/%s" path name in
      match cs, (op : Widget_impl.slot_ops) with
      | Children.Single c, Slot_single { set } ->
        name, Children.Single (mount_single ctx ~path parent ~set c)
      | List cs, Slot_list ops ->
        name, Children.List (mount_list ctx ~path parent ~ops cs)
      | (No_children | Single _ | List _ | Slots _), _ ->
        invalid_argf "%s: slot %s has the wrong shape for %s" path name impl_name ())

and mount_children
  ctx
  ~path
  ~impl_name
  parent
  (children : Node.t Children.t)
  (ops : Widget_impl.child_ops)
  : live Children.t
  =
  match children, ops with
  | No_children, _ -> Children.No_children
  | Single c, Single { set } -> Single (mount_single ctx ~path parent ~set c)
  | List cs, List ops -> List (mount_list ctx ~path parent ~ops cs)
  | Slots node_slots, Slots op_slots ->
    Slots (mount_slots ctx ~path ~impl_name parent node_slots op_slots)
  | (Single _ | List _ | Slots _), _ ->
    invalid_argf "%s: node's children do not match %s's shape" path impl_name ()

and destroy ctx (live : live) =
  (* Slots are emptied before anything is torn down: GTK emits signals synchronously from
     [remove]/[set_child], and a handler firing here would run against a node that is
     already gone. *)
  Signals.clear_slots live.slots;
  Signals.disconnect live.connections;
  Children.iter live.children ~f:(destroy ctx);
  match live.node.kind with
  (* A window has no parent to unparent it, so it must be destroyed explicitly. *)
  | Window _ -> W.Window.destroy (cast live.widget)
  | Stack { name; _ } -> unregister_stack ctx ~name live.widget
  | Native n -> Native_gtk.destroy_payload n live.widget
  | Label _
  | Button _
  | Toggle_button _
  | Check_button _
  | Switch _
  | Entry _
  | Password_entry _
  | Search_entry _
  | Spin_button _
  | Scale _
  | Progress_bar _
  | Spinner _
  | Image _
  | Picture _
  | Separator _
  | Scrolled_window _
  | Frame _
  | Expander _
  | Revealer _
  | Center_box _
  | Paned _
  | Overlay _
  | Grid _
  | Stack_switcher _
  | Stack_sidebar _
  | Box _ -> ()

(* Empties every slot in a subtree without tearing anything down.

   [destroy] clears slots too, but on the paths where GTK unparents a subtree *before* it
   is destroyed the clearing would come too late: GTK emits signals synchronously from
   [remove]/[set_child], so a handler could fire against a node Bonsai is in the middle of
   dropping. Disarming first closes that window. The obvious alternative — destroy, then
   remove — is wrong: [destroy] on a window live really destroys the window, so a window
   ever appearing as a container child would be freed before the [remove] that names it. *)
and disarm (live : live) =
  Signals.clear_slots live.slots;
  Children.iter live.children ~f:disarm

(* Every stack name a subtree holds, given up before the subtree is replaced.

   The kind-change arm below mounts the replacement *before* destroying what it replaces,
   so that the old widgets stay alive and parented until the new ones exist. That ordering
   is right, and it is also why an ordinary refactor collided with itself: wrapping a
   [Node.stack ~name:"nav"] in a [Node.frame] changes the parent's kind, so the
   replacement subtree registers "nav" while the subtree being replaced still holds it,
   and [register_stack] rejects the one stack in the tree as two.

   Dropping the registrations first is enough, and it does not weaken the check: a genuine
   collision is two stacks that are *both* still in the tree, and the other one is by
   definition not in the subtree being thrown away. *)
and drop_stack_names ctx (live : live) =
  (match interest_of_kind live.node.kind with
   | Stack { name; _ } -> unregister_stack ctx ~name live.widget
   | Nothing | Window | Stack_ref _ -> ());
  Children.iter live.children ~f:(drop_stack_names ctx)

and patch ctx ~path ~is_root (live : live) (node : Node.t) : live =
  check_placement ~path ~is_root node;
  if not (Kind.same_kind live.node.kind node.kind)
  then (
    (* Mount before destroying: the caller re-parents the fresh widget, and mounting first
       keeps the old subtree alive (and parented) until the replacement exists. The stack
       names the old subtree holds are given up first, so that a stack the replacement
       re-declares does not collide with the copy of itself that is on its way out. *)
    drop_stack_names ctx live;
    let fresh = mount ctx ~path ~is_root node in
    destroy ctx live;
    fresh)
  else (
    let attr_ops = Attrs.diff ~old:live.node.attrs ~new_:node.attrs in
    (* Spec §11 says mount *and* patch time. A conditionally-added event attr
       ([if editing then Attr.on_toggled ...]) lands on a widget that was mounted without
       it, so only this call is in a position to reject it — [connect_all] ran once, at
       mount, and no slot exists for a name no spec claims.

       Computing the diff first is about *ordering*: the check runs before anything is
       written, so the raise leaves the widget untouched. The guard itself saves little —
       handlers are rebuilt every frame and [Attr.equal] compares them physically, so any
       node carrying an [on_*] attr at all has a non-empty diff on every frame, and it is
       the attr-free subtrees rather than the interesting ones that get skipped. *)
    if not (List.is_empty attr_ops)
    then
      Signals.require_specs ~node_path:path ~impl_name:live.impl.name node.kind node.attrs;
    if not (Kind.equal_props live.node.kind node.kind)
    then live.impl.update live.widget ~old:live.node.kind node.kind;
    (* Unconditionally, and after [update]: a controlled prop is compared against the
       widget, not against the previous node, so it has to be re-applied even on the patch
       where nothing in the tree changed — which is exactly the patch a model that
       declined the user's edit produces. See [Widget_impl.reassert]. *)
    Option.iter live.impl.reassert ~f:(fun f -> f live.widget node.kind);
    List.iter attr_ops ~f:(Attr_apply.apply ~defaults:live.defaults live.widget);
    Signals.update_slots live.slots node.attrs;
    live.children <- patch_children ctx ~path live node;
    (* Before [live.node <- node]: a renamed stack has to drop the name it was registered
       under, and that name is only on the *old* node. *)
    note_interest
      ctx
      ~path
      ~widget:live.widget
      ~interest:(interest_of_kind node.kind)
      ~pass:(`Patch live.node.kind);
    live.node <- node;
    live)

and patch_single ctx ~path parent ~set (old_c : live option) (new_c : Node.t option)
  : live option
  =
  match old_c, new_c with
  | None, None -> None
  | Some o, None ->
    disarm o;
    set parent None;
    destroy ctx o;
    None
  | None, Some n ->
    let l = mount ctx ~path:(child_path path 0) ~is_root:false n in
    set parent (Some l.widget);
    Some l
  | Some o, Some n ->
    let l = patch ctx ~path:(child_path path 0) ~is_root:false o n in
    (* [patch] returns a different record only when the kind changed, in which case the
       old widget is still the container's child; [set] replaces (and unparents) it. *)
    if not (phys_equal l o) then set parent (Some l.widget);
    Some l

and patch_list
  ctx
  ~path
  parent
  ~(ops : Widget_impl.list_ops)
  (olds : live list)
  (news : Node.t list)
  : live list
  =
  (* Wrapped like every other child-list op: the reconciler knows nothing about where in
     the tree it is, and its duplicate-key rejection is the one structural message that
     used to reach the caller with no path on it at all. *)
  let edits =
    child_op ~path (fun () ->
      Reconcile.diff
        ~key:(fun (n : Node.t) -> n.key)
        ~same_kind:(fun a b -> Kind.same_kind a.Node.kind b.Node.kind)
        ~old:(List.map olds ~f:(fun l -> l.node))
        ~new_:news)
  in
  (* [cur] mirrors, over lives, exactly what [Reconcile.apply] would do over nodes, so the
     indices the reconciler computed stay valid — and so [cur] is also what every op reads
     its placement out of. *)
  (* The widget a child at [index] must be placed after, read off the patcher's own list
     rather than GTK's: a container that interposes children of its own (list-box rows,
     stack pages) has a live child list that does not match these indices. *)
  let after_of cur index =
    if index = 0 then None else Some (List.nth_exn cur (index - 1)).widget
  in
  let cur = ref olds in
  List.iter edits ~f:(fun (op : Node.t Reconcile.op) ->
    match op with
    | Remove { index } ->
      let l = List.nth_exn !cur index in
      disarm l;
      child_op ~path:(child_path path index) (fun () -> ops.remove parent l.widget);
      destroy ctx l;
      cur := List.filteri !cur ~f:(fun i _ -> i <> index)
    | Insert { index; item } ->
      let l = mount ctx ~path:(child_path path index) ~is_root:false item in
      child_op ~path:(child_path path index) (fun () ->
        ops.insert parent ~after:(after_of !cur index) ~node:item l.widget);
      cur := List.take !cur index @ (l :: List.drop !cur index)
    | Move { from; to_ } ->
      let l = List.nth_exn !cur from in
      (* [to_] indexes the list as it will be *after* the move, so the predecessor is
         computed with [l] already removed. *)
      let without = List.filteri !cur ~f:(fun i _ -> i <> from) in
      child_op ~path:(child_path path to_) (fun () ->
        ops.move parent ~child:l.widget ~after:(after_of without to_));
      cur := List.take without to_ @ (l :: List.drop without to_)
    | Update { index; item; old = _ } ->
      let l = List.nth_exn !cur index in
      (* Read *before* [patch], which writes [live.node <- node] at the end: reading it
         afterwards would hand the hook two identical nodes, and every parent-held setting
         would silently stop updating. *)
      let old_node = l.node in
      let l' = patch ctx ~path:(child_path path index) ~is_root:false l item in
      if phys_equal l l'
      then
        child_op ~path:(child_path path index) (fun () ->
          ops.updated parent ~old:old_node ~node:item l'.widget)
      else (
        (* The kind changed, so [patch] mounted a replacement and destroyed [l]; [l]'s
           widget is still parented here. Remove it, then place the replacement where it
           was — [after] over the list with [l] taken out. ([l]'s widget was still
           parented while it was destroyed, which is what we want for the widgets M0 can
           hold here: destroying a non-window live only disconnects it. A [Window] live in
           a list would be destroyed for real before this [remove], which is fine — its
           own [destroy] unparents it — but is worth re-checking if windows ever become
           list children.) *)
        let without = List.filteri !cur ~f:(fun i _ -> i <> index) in
        child_op ~path:(child_path path index) (fun () ->
          ops.remove parent l.widget;
          ops.insert parent ~after:(after_of without index) ~node:item l'.widget));
      cur := List.mapi !cur ~f:(fun i x -> if i = index then l' else x));
  !cur

and patch_slots ctx ~path ~impl_name parent old_slots new_slots op_slots =
  (* Every slot list here comes from the same fixed constructor and the same impl, so a
     length or name mismatch is a bug in one of them rather than anything a caller did. *)
  match List.zip old_slots new_slots with
  | Unequal_lengths ->
    invalid_argf "%s: %s's slots changed shape under an unchanged kind" path impl_name ()
  | Ok pairs ->
    (match List.zip pairs op_slots with
     | Unequal_lengths ->
       invalid_argf
         "%s: %s has %d slots, node has %d"
         path
         impl_name
         (List.length op_slots)
         (List.length new_slots)
         ()
     | Ok triples ->
       List.mapi triples ~f:(fun i (((name, old_c), (new_name, new_c)), (op_name, op)) ->
         if not (String.equal name new_name && String.equal name op_name)
         then
           invalid_argf
             "%s: slot %d is %s in the live tree, %s in the node, %s on %s"
             path
             i
             name
             new_name
             op_name
             impl_name
             ();
         let path = sprintf "%s/%s" path name in
         match old_c, new_c, (op : Widget_impl.slot_ops) with
         | Children.Single o, Children.Single n, Slot_single { set } ->
           name, Children.Single (patch_single ctx ~path parent ~set o n)
         | List o, List n, Slot_list ops ->
           name, Children.List (patch_list ctx ~path parent ~ops o n)
         | (No_children | Single _ | List _ | Slots _), _, _ ->
           invalid_argf "%s: slot %s has the wrong shape for %s" path name impl_name ()))

and patch_children ctx ~path (live : live) (node : Node.t) : live Children.t =
  let impl_name = live.impl.name in
  match live.children, node.children, live.impl.children with
  | No_children, No_children, _ -> No_children
  | Single old_c, Single new_c, Single { set } ->
    Single (patch_single ctx ~path live.widget ~set old_c new_c)
  | List olds, List news, List ops ->
    List (patch_list ctx ~path live.widget ~ops olds news)
  | Slots old_slots, Slots new_slots, Slots op_slots ->
    Slots (patch_slots ctx ~path ~impl_name live.widget old_slots new_slots op_slots)
  | (No_children | Single _ | List _ | Slots _), _, _ ->
    invalid_argf
      "%s: %s's children changed shape under an unchanged kind"
      path
      impl_name
      ()
;;
