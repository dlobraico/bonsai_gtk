open! Core
open Bonsai_gtk_vtree
open Gtk_import

type ctx =
  { signals : Signals.ctx
  ; on_window_created : Widget.t -> unit
  ; (* Where a diagnostic that is not an exception goes: the model asked for something the
       widget cannot hold, the frame carries on, and somebody has to be told. Distinct
       from [Signals.ctx.on_exn], which reports an exception raised while {i dispatching}
       a signal and is not reachable from a widget impl anyway. Optional on [create_ctx]
       with an [eprintf] default, so that the runtime gets the library's usual channel and
       a test can capture the message instead of racing stderr against a golden. *)
    report : node_path:string -> string -> unit
  ; (* Live [GtkStack]s by their [Node.stack ~name]. A [stack_switcher] cannot hold a
       widget -- the vtree has no way to name one -- so it names a stack and is wired up
       after the pass that mounts them both. *)
    stacks : (string, Widget.t) Hashtbl.t
  ; (* The names this pass's stack nodes are taking, and the ones they are giving up,
       applied to [stacks] once the walk is over. See [apply_stack_claims]. *)
    stack_claims : stack_claim Queue.t
  ; (* Work deferred to the end of a mount/patch pass, so that a node may refer to another
       node regardless of which of them the walk reaches first. *)
    fixups : (unit -> unit) Queue.t
  }

and stack_claim =
  { claim_path : string
  ; give_up : string option
  ; take : string
  ; claimant : Widget.t
  }

let default_report ~node_path message = eprintf "bonsai_gtk: %s: %s\n%!" node_path message

let create_ctx ?(report = default_report) ~signals ~on_window_created () =
  { signals
  ; on_window_created
  ; report
  ; stacks = Hashtbl.create (module String)
  ; stack_claims = Queue.create ()
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

(* The stack registrations of one whole pass, in two loops: every name this pass's stacks
   are giving up, then every name they are taking.

   One loop cannot do it, because a *swap* is legal and a left-to-right walk cannot see
   one: a stack renaming ["a" -> "b"] while its sibling renames ["b" -> "a"] reaches
   [register_stack "b"] while the sibling still holds it, and the one tree is rejected as
   two. Splitting the pass is the smallest thing that distinguishes "held by a stack that
   is giving it up" from "held". A genuine collision -- two stacks that both still want
   the name when the walk is over -- still raises, from the second loop, with the same
   message and the same path.

   Deferred to the end of the walk rather than to [run_fixups]: it is still [mount] and
   [patch] that raise, which is what spec §11's "loud and early" and every existing caller
   expect. Removals are guarded by widget identity ([unregister_stack]), so a stack torn
   down mid-pass and a claim naming the same name cannot undo each other.

   The queue is emptied even when a claim raises, for the reason [run_fixups]'s is: it
   describes one pass, and carrying a failed pass's registrations into the next one would
   raise again from a frame that had nothing to do with it. *)
let apply_stack_claims ctx =
  Exn.protect
    ~f:(fun () ->
      Queue.iter ctx.stack_claims ~f:(fun c ->
        Option.iter c.give_up ~f:(fun name -> unregister_stack ctx ~name c.claimant));
      Queue.iter ctx.stack_claims ~f:(fun c ->
        register_stack ctx ~path:c.claim_path ~name:c.take c.claimant))
    ~finally:(fun () -> Queue.clear ctx.stack_claims)
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
   tree if one ever happened.

   The stack claims go with them, and for the same reason: a walk that died part-way
   collected claims for a tree that was only half built, and applying them would register
   names for widgets nothing will ever patch. (A pass that *finished* has already applied
   and emptied its own claims.) *)
let abandon_fixups ctx =
  Queue.clear ctx.fixups;
  Queue.clear ctx.stack_claims
;;

type live =
  { mutable node : Node.t
  ; widget : Widget.t
  ; impl : Widget_impl.t
  ; defaults : Attr_apply.defaults
  ; slots : Signals.slots
  ; connections : Signals.connection list
  ; controllers : Controllers.t
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
  | List_box of Kind.list_box_props
  | Flow_box of Kind.flow_box_props
  | Notebook of Kind.notebook_props
  (* Carries nothing: what the patcher does for a text view is not to write anything but
     to say where a refused write happened, and only the widget is needed to ask. *)
  | Text_view
  (* Carries nothing, for the same reason and about a different refusal: a drop-down whose
     [~selected] is [-1] over a non-empty list is asking for a selection GTK will not
     hold, and this is where that gets said. *)
  | Drop_down
  (* Carries nothing, twice more and for the same reason. A calendar's [~date] in a year
     outside GTK's 1-9999 and an editable label's [~text] with a NUL in it are both writes
     the widget will not take; the impls refuse them and this is where the path comes
     from. *)
  | Calendar
  | Editable_label

let interest_of_kind (kind : Kind.t) =
  match kind with
  | Window _ -> Window
  | Stack p -> Stack p
  | Stack_switcher { stack } -> Stack_ref (`Switcher, stack)
  | Stack_sidebar { stack } -> Stack_ref (`Sidebar, stack)
  | List_box p -> List_box p
  | Flow_box p -> Flow_box p
  | Notebook p -> Notebook p
  | Text_view _ -> Text_view
  | Drop_down _ -> Drop_down
  | Calendar _ -> Calendar
  | Editable_label _ -> Editable_label
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
  | Level_bar _
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

(* What a node of this kind wants done once the whole pass is over: a stack selecting a
   page that does not exist while the stack is being built, a switcher resolving the stack
   it names.

   Called from [note_interest] -- so from [mount] and from [patch] -- and from
   [reassert_only]. The last is why this is a function of its own rather than two lines
   inside [note_interest]: a frame that skips the walk must still re-apply the selections,
   since a selection is a controlled prop and the frame that declines a navigation is
   exactly the frame on which nothing else moved. *)
let enqueue_fixups ctx ~path ~widget ~(interest : interest) =
  match interest with
  | Nothing | Window -> ()
  (* Not a fixup at all: nothing is deferred and nothing is written. This is the one place
     that holds both a text view and the path of the node it came from, which is what a
     refused write needs in order to say anything useful. Reported here rather than from
     the impl because a [Widget_impl] is handed a widget and a kind and knows neither
     where it is in the tree nor how the runtime reports.

     One ephemeron lookup per text view per frame, and no allocation unless there is
     something to say. Runs after [create] on a mount and after [reassert] on a patch and
     on an idle frame, which are the three places a write can be refused. *)
  | Text_view ->
    Option.iter (W_text_view.take_report widget) ~f:(ctx.report ~node_path:path)
  (* The second caller of [ctx.report], and the same shape as the first: not a fixup,
     nothing deferred and nothing written -- [W_drop_down.reassert] has already decided
     the write cannot land, and this is the one place holding both the widget and the path
     of the node it came from. One ephemeron lookup per drop-down per frame, allocating
     nothing unless there is something to say. *)
  | Drop_down ->
    Option.iter (W_drop_down.take_report widget) ~f:(ctx.report ~node_path:path)
  (* The third and fourth callers of [ctx.report], the same shape as the first two: not a
     fixup, nothing deferred and nothing written -- the impl's [reassert] has already
     decided the write cannot land, and this is the one place holding both the widget and
     the path of the node it came from. One ephemeron lookup per widget per frame,
     allocating nothing unless there is something to say. *)
  | Calendar ->
    Option.iter (W_calendar.take_report widget) ~f:(ctx.report ~node_path:path)
  | Editable_label ->
    Option.iter (W_editable_label.take_report widget) ~f:(ctx.report ~node_path:path)
  | Stack { visible_child; _ } ->
    (* Enqueued rather than applied: the pages are attached after this on a mount, and
       patched after this on a patch, and a page GTK does not have yet cannot be selected.
       It is also the only place that can tell a page which is not there {i yet} from one
       that is never coming, which is why [W_stack.select] rejects an unknown name and why
       the path is prefixed here -- [select] knows no more about where it is than any
       other container op does (spec §11). *)
    Queue.enqueue ctx.fixups (fun () ->
      child_op ~path (fun () -> W_stack.select widget ~visible_child))
  | Stack_ref (which, name) ->
    (* Re-enqueued on every pass rather than only when the name changed: it is one
       hashtable lookup and one setter per switcher per frame, and it is the only thing
       that keeps a switcher pointing at a stack that was itself replaced. *)
    Queue.enqueue ctx.fixups (fun () ->
      let stack = resolve_stack ctx ~path ~name in
      match which with
      | `Switcher -> W_stack_switcher.attach widget stack
      | `Sidebar -> W_stack_sidebar.attach widget stack)
  | List_box { selected; _ } ->
    (* The same reason a stack's page is deferred, one step further: the rows are attached
       after this on a mount and patched after this on a patch, so the frame that adds a
       row and selects it has nothing to select until the pass is over. Unlike
       [W_stack.select] this one rejects nothing -- a key naming no row is ignored, and
       [Node.list_box] says why -- so there is no path to prefix. *)
    Queue.enqueue ctx.fixups (fun () -> W_list_box.apply_selection widget ~selected)
  | Flow_box { selected; _ } ->
    (* The list box's arm, over the other container: the children are attached after this
       on a mount and patched after this on a patch, and a key naming no child is ignored
       rather than rejected, so there is no path to prefix here either. *)
    Queue.enqueue ctx.fixups (fun () -> W_flow_box.apply_selection widget ~selected)
  | Notebook { current_page; _ } ->
    (* A stack's arm over the other container that shows exactly one child, and it rejects
       an unknown key for the same reason: the pages are attached after this on a mount
       and patched after this on a patch, so this is the only place that can tell a page
       that is not there {i yet} from one that is never coming. The path is prefixed here
       -- [select] knows no more about where it is than any other container op does (spec
       §11). *)
    Queue.enqueue ctx.fixups (fun () ->
      child_op ~path (fun () -> W_notebook.select widget ~current_page))
;;

(* The immediate half of realizing a node -- a window is presented, a stack registers its
   name -- followed by {!enqueue_fixups} for the deferred half. Shared by [mount] and
   [patch], which differ only in [pass]. *)
let note_interest
  ctx
  ~path
  ~widget
  ~(interest : interest)
  ~(pass : [ `Mount | `Patch of Kind.t ])
  =
  (match interest with
   | Nothing -> ()
   | Window ->
     (* Once per window, at mount: the runtime presents it and holds onto it. *)
     (match pass with
      | `Mount -> ctx.on_window_created widget
      | `Patch _ -> ())
   | Stack { name; _ } ->
     (* Recorded rather than applied, and applied by [apply_stack_claims] once the walk is
        over. A patched stack gives up the name it held whether or not that is the name it
        is taking again: the give-up-then-take pair is what lets two stacks exchange names
        in one frame, and re-taking a name this same widget just released is also what
        heals a registration some earlier teardown lost.

        A renamed stack giving its old name up is what makes a switcher still naming it
        fail loudly rather than drive a stack the tree no longer calls that. *)
     let give_up =
       match pass with
       | `Mount -> None
       | `Patch (Kind.Stack { name = old_name; _ }) -> Some old_name
       | `Patch _ ->
         (* Unreachable: [patch] only gets here when the kinds match. Claiming without
            giving anything up is what keeps it harmless if that ever changes. *)
         None
     in
     Queue.enqueue
       ctx.stack_claims
       { claim_path = path; give_up; take = name; claimant = widget }
   | Stack_ref _
   | List_box _
   | Flow_box _
   | Notebook _
   | Text_view
   | Drop_down
   | Calendar
   | Editable_label -> ());
  enqueue_fixups ctx ~path ~widget ~interest
;;

(* Spec §11: structural misuse is rejected loudly and early. A [GtkWindow] is a toplevel,
   so parenting one would make GTK log a critical and leave a silently broken tree — and
   under [Loop] the runtime would additionally present it as if it were a real window.

   [parent_kind] is [None] for the root only. A placement attr there is rejected on the
   same rule as anywhere else: there is no container above it to read one -- see
   [Bonsai_gtk_vtree.Placement], which holds the table and the message. *)
let check_placement ~path ~is_root ~(parent_kind : Kind.t option) (node : Node.t) =
  (match node.kind with
   | Window _ when not is_root ->
     invalid_argf
       "%s: a Node.window may only be the root node, not a child of another node"
       path
       ()
   | _ -> ());
  (* [Placement] rather than a table here: it is pure [Kind.t]/[Attr.Name.t] data, and
     [Bonsai_gtk_test] -- which cannot link ocgtk, so cannot see this file -- runs the
     same check over the same table at handle time. Both raise the string [rejection]
     builds, so the two messages are identical by construction rather than by inspection. *)
  Option.iter (Placement.rejection ~path ~parent:parent_kind node.attrs) ~f:invalid_arg
;;

(* The kind-specific half of tearing a node down: the registrations and payloads the
   patcher holds on a node's behalf, which nothing in [Signals] or [Controllers] knows
   about.

   Shared by {!destroy}, which runs it on a node that was fully built, and by {!mount}'s
   unwind path, which runs it on one that raised part-way. Those are the only two callers
   and they must not drift: a kind that acquires something at mount has to release it on
   both paths, and a single exhaustive match is what makes adding one a compile error in
   the one place rather than a silent leak in the other. *)
let release_kind ctx ~(kind : Kind.t) ~(widget : Widget.t) =
  match kind with
  (* A window has no parent to unparent it, so it must be destroyed explicitly. *)
  | Window _ -> W.Window.destroy (cast widget)
  | Stack { name; _ } -> unregister_stack ctx ~name widget
  | Native n -> Native_gtk.destroy_payload n widget
  (* The rows never pass through [list_ops.remove] on this path -- the patcher tears a
     subtree down by walking it, not by removing each child from its parent -- so their
     [Child_keys] entries are dropped here instead; see [W_list_box.forget_rows]. *)
  | List_box _ -> W_list_box.forget_rows widget
  (* Same reason, same placement requirement: {i above} the or-pattern chain below, or
     every kind listed in it binds to this arm as well and [forget_children] runs on
     labels and boxes. *)
  | Flow_box _ -> W_flow_box.forget_children widget
  (* Same reason, same placement requirement: {i above} the or-pattern chain below. *)
  | Notebook _ -> W_notebook.forget_pages widget
  | Label _
  | Button _
  | Toggle_button _
  | Check_button _
  | Switch _
  | Entry _
  | Password_entry _
  | Search_entry _
  | Text_view _
  | Drop_down _
  | Calendar _
  | Editable_label _
  | Level_bar _
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
;;

(* Mounting is exception-safe: if any step after the widget exists raises, everything this
   call had already built is torn down before the exception goes on up.

   Without that, a mount that raises part-way leaks permanently rather than merely
   failing. [Driver.stop] can only walk [t.root], and [t.root] is assigned once, after the
   whole subtree is built -- so nothing the failed pass created is reachable from the
   driver, while every signal it had already connected roots a GClosure that captures the
   driver, which holds the shadow tree, which holds GObject references back. GC and
   refcounting cannot break that cycle between them. Measured (task-12-review.md, probe 6)
   at ~50k live words -- about 390 KB -- per failed mount that had connected one handler,
   against ~560 words for one that had not: the whole driver and its Bonsai graph, not
   just the widgets.

   It is also what makes {!Bonsai_gtk.start}'s and {!Bonsai_gtk.Expert.embed}'s "the
   failed frame tore down what it built" promises true rather than aspirational, and it
   closes the M1 backlog item of the same name.

   The unwind mirrors {!destroy} step for step, over whatever exists so far: slots emptied
   first (so a signal GTK emits while the partial tree comes apart reaches nothing), then
   the controllers, then the connections, then the children, then the kind's own
   registrations through the {!release_kind} both paths share. The widget itself is not
   destroyed or unparented -- it was never parented, nothing references it once this
   returns, and destroying it is {!destroy}'s rule for windows only.

   The child helpers below each protect what {i they} built, for the same reason: a raise
   on the third child must not strand the first two, and only the loop that built them
   knows they exist. *)
let rec mount ctx ~path ~is_root ~parent_kind (node : Node.t) : live =
  check_placement ~path ~is_root ~parent_kind node;
  let impl = Registry.for_kind node.kind in
  let widget = impl.create node.kind in
  (* Filled in as each stage succeeds, and read by [unwind] to undo exactly the stages
     that did. *)
  let built_slots = ref None in
  let built_connections = ref [] in
  let built_controllers = ref None in
  let built_children = ref None in
  (* Keep in step with {!destroy}: the four stages below are that function's, in its
     order, over whatever exists so far. Only the tail is genuinely shared
     ({!release_kind} is the kind-specific half, factored out so it cannot drift); the
     four stages are written out twice because [destroy] has a [live] and this has only
     pieces of one, and a change to what [Signals] or [Controllers] needs at teardown has
     to land in both. *)
  let unwind () =
    Option.iter !built_slots ~f:Signals.clear_slots;
    Option.iter !built_controllers ~f:Controllers.release;
    Signals.disconnect !built_connections;
    Option.iter !built_children ~f:(Children.iter ~f:(destroy ctx));
    release_kind ctx ~kind:node.kind ~widget
  in
  match
    (* After [create] has applied the kind's props but before any attribute touches it:
       these are the widget's own creation-time values, which is what a later [Unset]
       restores. *)
    let defaults = Attr_apply.snapshot widget in
    Attr_apply.apply_all widget node.attrs;
    (* Before anything is connected: an event attr no spec claims would create no slot, so
       the handler would never run and nothing would say why (spec §11). *)
    Signals.require_specs ~node_path:path node.kind node.attrs;
    let slots, connections =
      Signals.connect_all ctx.signals ~node_path:path widget impl.signals
    in
    built_slots := Some slots;
    built_connections := connections;
    (* [require_specs] above asked [Events]; this asks the slots that were actually built.
       The two can only disagree if the table and this impl's [signals] have drifted, and
       that drift would otherwise be a handler that silently never fires. *)
    Signals.require_slots ~node_path:path ~impl_name:impl.name slots node.attrs;
    Signals.update_slots slots node.attrs;
    (* The controller attrs are nobody's signal, so neither check above sees them: they
       are legal on every kind and no impl declares a spec for one. What creates their
       slots is this, from the attrs themselves. *)
    let controllers = Controllers.create ctx.signals ~node_path:path widget in
    built_controllers := Some controllers;
    Controllers.update controllers node.attrs;
    let children =
      mount_children
        ctx
        ~path
        ~impl_name:impl.name
        ~parent_kind:node.kind
        widget
        node.children
        impl.children
    in
    built_children := Some children;
    note_interest ctx ~path ~widget ~interest:(interest_of_kind node.kind) ~pass:`Mount;
    { node; widget; impl; defaults; slots; connections; controllers; children }
  with
  | live -> live
  | exception exn ->
    let backtrace = Stdlib.Printexc.get_raw_backtrace () in
    unwind ();
    Stdlib.Printexc.raise_with_backtrace exn backtrace

(* One shape, mounted. The three helpers below are what a top-level shape and a slot of
   that shape share: a slot is not a special case, it is the same code under a longer
   path. *)
and mount_single ctx ~path ~parent_kind parent ~set (c : Node.t option) : live option =
  let live_c =
    Option.map c ~f:(fun c ->
      mount ctx ~path:(child_path path 0) ~is_root:false ~parent_kind:(Some parent_kind) c)
  in
  (* [set] is the only thing here that can raise after the child exists, and the child is
     not reachable from anywhere else yet. *)
  (match set parent (Option.map live_c ~f:(fun l -> l.widget)) with
   | () -> ()
   | exception exn ->
     let backtrace = Stdlib.Printexc.get_raw_backtrace () in
     Option.iter live_c ~f:(destroy ctx);
     Stdlib.Printexc.raise_with_backtrace exn backtrace);
  live_c

and mount_list
  ctx
  ~path
  ~parent_kind
  parent
  ~(ops : Widget_impl.list_ops)
  (cs : Node.t list)
  : live list
  =
  (* Spec §11 says mount *and* patch time. [Reconcile.diff] checks this on the patch path,
     but a first frame never reaches it -- so without this a duplicate key is accepted
     once and rejected on the second frame, which for a [Node.stack] means GTK has already
     been handed two pages with one name and [get_child_by_name] is already ambiguous. *)
  child_op ~path (fun () ->
    Reconcile.check_unique_keys ~key:(fun (n : Node.t) -> n.key) cs);
  (* Newest first, and only ever appended to, so that a raise on the third child can tear
     down the first two: each recursive [mount] cleans up after itself, but the siblings
     it never touched are known only here. The [insert] loop is inside the same guard for
     the same reason -- a container that rejects the child it is handed (a grid cell with
     no [Attr.grid_cell], a stack page with no key) raises after every child has been
     built. *)
  let built = ref [] in
  match
    let lives =
      List.mapi cs ~f:(fun i c ->
        let l =
          mount
            ctx
            ~path:(child_path path i)
            ~is_root:false
            ~parent_kind:(Some parent_kind)
            c
        in
        built := l :: !built;
        l)
    in
    List.foldi lives ~init:None ~f:(fun i after l ->
      child_op ~path:(child_path path i) (fun () ->
        ops.insert parent ~after ~node:l.node l.widget);
      Some l.widget)
    |> (ignore : Widget.t option -> unit);
    lives
  with
  | lives -> lives
  | exception exn ->
    let backtrace = Stdlib.Printexc.get_raw_backtrace () in
    List.iter !built ~f:(destroy ctx);
    Stdlib.Printexc.raise_with_backtrace exn backtrace

and mount_slots ctx ~path ~impl_name ~parent_kind parent node_slots op_slots =
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
    (* Same guard as [mount_list]'s, over slots rather than list items: an overlay whose
       [~overlays] slot raises must not strand the main child it already built. *)
    let built = ref [] in
    (match
       List.map pairs ~f:(fun ((name, cs), (op_name, op)) ->
         if not (String.equal name op_name)
         then invalid_argf "%s: slot %s does not exist on %s" path name impl_name ();
         let path = sprintf "%s/%s" path name in
         let slot =
           match cs, (op : Widget_impl.slot_ops) with
           | Children.Single c, Slot_single { set } ->
             Children.Single (mount_single ctx ~path ~parent_kind parent ~set c)
           | List cs, Slot_list ops ->
             Children.List (mount_list ctx ~path ~parent_kind parent ~ops cs)
           | (No_children | Single _ | List _ | Slots _), _ ->
             invalid_argf "%s: slot %s has the wrong shape for %s" path name impl_name ()
         in
         built := slot :: !built;
         name, slot)
     with
     | slots -> slots
     | exception exn ->
       let backtrace = Stdlib.Printexc.get_raw_backtrace () in
       List.iter !built ~f:(Children.iter ~f:(destroy ctx));
       Stdlib.Printexc.raise_with_backtrace exn backtrace)

and mount_children
  ctx
  ~path
  ~impl_name
  ~parent_kind
  parent
  (children : Node.t Children.t)
  (ops : Widget_impl.child_ops)
  : live Children.t
  =
  match children, ops with
  | No_children, _ -> Children.No_children
  | Single c, Single { set } -> Single (mount_single ctx ~path ~parent_kind parent ~set c)
  | List cs, List ops -> List (mount_list ctx ~path ~parent_kind parent ~ops cs)
  | Slots node_slots, Slots op_slots ->
    Slots (mount_slots ctx ~path ~impl_name ~parent_kind parent node_slots op_slots)
  | (Single _ | List _ | Slots _), _ ->
    invalid_argf "%s: node's children do not match %s's shape" path impl_name ()

and destroy ctx (live : live) =
  (* Keep in step with [mount]'s [unwind], which does these same four stages in this same
     order over a subtree that only half exists. *)
  (* Slots are emptied before anything is torn down: GTK emits signals synchronously from
     [remove]/[set_child], and a handler firing here would run against a node that is
     already gone. *)
  Signals.clear_slots live.slots;
  (* [release] empties its own slots before it removes anything, so by the time
     [gtk_widget_remove_controller] runs -- which can itself provoke a leave or a cancel
     -- every slot on this widget, its own and its controllers', is already empty. *)
  Controllers.release live.controllers;
  Signals.disconnect live.connections;
  Children.iter live.children ~f:(destroy ctx);
  release_kind ctx ~kind:live.node.kind ~widget:live.widget

(* Empties every slot in a subtree without tearing anything down.

   [destroy] clears slots too, but on the paths where GTK unparents a subtree *before* it
   is destroyed the clearing would come too late: GTK emits signals synchronously from
   [remove]/[set_child], so a handler could fire against a node Bonsai is in the middle of
   dropping. Disarming first closes that window. The obvious alternative — destroy, then
   remove — is wrong: [destroy] on a window live really destroys the window, so a window
   ever appearing as a container child would be freed before the [remove] that names it. *)
and disarm (live : live) =
  Signals.clear_slots live.slots;
  (* The controllers' slots too, and not the controllers themselves: this is the
     pre-unparent disarming, and the detaching belongs to [destroy], which runs after. A
     click gesture or a focus controller is exactly the kind of thing GTK will emit from
     during an unparent. *)
  Controllers.clear live.controllers;
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
   definition not in the subtree being thrown away.

   Since registrations became claims applied at the end of the walk, [destroy]'s own
   [unregister_stack] would also run before any of them, so this is belt-and-braces rather
   than the repair it was. It is kept because it states the ordering requirement at the
   place that depends on it: the kind-change arm mounts before it destroys, and that is
   what makes the requirement exist at all. *)
and drop_stack_names ctx (live : live) =
  (match interest_of_kind live.node.kind with
   | Stack { name; _ } -> unregister_stack ctx ~name live.widget
   | Nothing
   | Window
   | Stack_ref _
   | List_box _
   | Flow_box _
   | Notebook _
   | Text_view
   | Drop_down
   | Calendar
   | Editable_label -> ());
  Children.iter live.children ~f:(drop_stack_names ctx)

and patch ctx ~path ~is_root ~parent_kind (live : live) (node : Node.t) : live =
  check_placement ~path ~is_root ~parent_kind node;
  if not (Kind.same_kind live.node.kind node.kind)
  then (
    (* Mount before destroying: the caller re-parents the fresh widget, and mounting first
       keeps the old subtree alive (and parented) until the replacement exists. The stack
       names the old subtree holds are given up first, so that a stack the replacement
       re-declares does not collide with the copy of itself that is on its way out. *)
    drop_stack_names ctx live;
    let fresh = mount ctx ~path ~is_root ~parent_kind node in
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
    then Signals.require_specs ~node_path:path node.kind node.attrs;
    if not (Kind.equal_props live.node.kind node.kind)
    then live.impl.update live.widget ~old:live.node.kind node.kind;
    (* Unconditionally, and after [update]: a controlled prop is compared against the
       widget, not against the previous node, so it has to be re-applied even on the patch
       where nothing in the tree changed — which is exactly the patch a model that
       declined the user's edit produces. See [Widget_impl.reassert]. *)
    Option.iter live.impl.reassert ~f:(fun f -> f live.widget node.kind);
    List.iter attr_ops ~f:(Attr_apply.apply ~defaults:live.defaults live.widget);
    Signals.update_slots live.slots node.attrs;
    (* Beside [update_slots] and on the same terms: unconditional, because every frame
       rebuilds its closures. This is also where a controller is created for an attr the
       frame *added* and removed for one it dropped. *)
    Controllers.update live.controllers node.attrs;
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

and patch_single
  ctx
  ~path
  ~parent_kind
  parent
  ~set
  (old_c : live option)
  (new_c : Node.t option)
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
    let l =
      mount ctx ~path:(child_path path 0) ~is_root:false ~parent_kind:(Some parent_kind) n
    in
    set parent (Some l.widget);
    Some l
  | Some o, Some n ->
    let l =
      patch
        ctx
        ~path:(child_path path 0)
        ~is_root:false
        ~parent_kind:(Some parent_kind)
        o
        n
    in
    (* [patch] returns a different record only when the kind changed, in which case the
       old widget is still the container's child; [set] replaces (and unparents) it. *)
    if not (phys_equal l o) then set parent (Some l.widget);
    Some l

and patch_list
  ctx
  ~path
  ~parent_kind
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
      (* [~ordered] is [false] exactly when this container has no reorder primitive, so
         the ops the reconciler produces and the ops this function can apply are the same
         set: no [Move] is emitted for such a container, rather than emitted here and
         discarded there. See [Widget_impl.list_ops.move]. *)
      Reconcile.diff
        ~ordered:(Option.is_some ops.move)
        ~key:(fun (n : Node.t) -> n.key)
        ~same_kind:(fun a b -> Kind.same_kind a.Node.kind b.Node.kind)
        ~old:(List.map olds ~f:(fun l -> l.node))
        ~new_:news
        ())
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
      let l =
        mount
          ctx
          ~path:(child_path path index)
          ~is_root:false
          ~parent_kind:(Some parent_kind)
          item
      in
      child_op ~path:(child_path path index) (fun () ->
        ops.insert parent ~after:(after_of !cur index) ~node:item l.widget);
      cur := List.take !cur index @ (l :: List.drop !cur index)
    | Move { from; to_ } ->
      (* Unreachable for an unordered container: [~ordered] above is
         [Option.is_some ops.move], and [Reconcile.diff] emits no [Move] when it is false.
         Stated as a raise rather than an ignored op because the two have to be kept in
         step, and a silently dropped [Move] is exactly the bookkeeping bug the option
         exists to prevent. *)
      let move =
        match ops.move with
        | Some move -> move
        | None ->
          invalid_argf
            "%s: a Move op reached a container that has no reorder primitive"
            path
            ()
      in
      let l = List.nth_exn !cur from in
      (* [to_] indexes the list as it will be *after* the move, so the predecessor is
         computed with [l] already removed. *)
      let without = List.filteri !cur ~f:(fun i _ -> i <> from) in
      child_op ~path:(child_path path to_) (fun () ->
        move parent ~child:l.widget ~after:(after_of without to_));
      cur := List.take without to_ @ (l :: List.drop without to_)
    | Update { index; item; old = _ } ->
      let l = List.nth_exn !cur index in
      (* Read *before* [patch], which writes [live.node <- node] at the end: reading it
         afterwards would hand the hook two identical nodes, and every parent-held setting
         would silently stop updating. *)
      let old_node = l.node in
      let l' =
        patch
          ctx
          ~path:(child_path path index)
          ~is_root:false
          ~parent_kind:(Some parent_kind)
          l
          item
      in
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

and patch_slots ctx ~path ~impl_name ~parent_kind parent old_slots new_slots op_slots =
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
           name, Children.Single (patch_single ctx ~path ~parent_kind parent ~set o n)
         | List o, List n, Slot_list ops ->
           name, Children.List (patch_list ctx ~path ~parent_kind parent ~ops o n)
         | (No_children | Single _ | List _ | Slots _), _, _ ->
           invalid_argf "%s: slot %s has the wrong shape for %s" path name impl_name ()))

and patch_children ctx ~path (live : live) (node : Node.t) : live Children.t =
  let impl_name = live.impl.name in
  let parent_kind = node.kind in
  match live.children, node.children, live.impl.children with
  | No_children, No_children, _ -> No_children
  | Single old_c, Single new_c, Single { set } ->
    Single (patch_single ctx ~path ~parent_kind live.widget ~set old_c new_c)
  | List olds, List news, List ops ->
    List (patch_list ctx ~path ~parent_kind live.widget ~ops olds news)
  | Slots old_slots, Slots new_slots, Slots op_slots ->
    Slots
      (patch_slots
         ctx
         ~path
         ~impl_name
         ~parent_kind
         live.widget
         old_slots
         new_slots
         op_slots)
  | (No_children | Single _ | List _ | Slots _), _, _ ->
    invalid_argf
      "%s: %s's children changed shape under an unchanged kind"
      path
      impl_name
      ()
;;

(* The two entry points, each wrapping the walk in the pass-level bookkeeping the walk
   itself cannot do: the root has no parent to read a placement attr off it, and the stack
   names the walk collected are applied once it is over (see [apply_stack_claims]). A walk
   that raised leaves its claims for [abandon_fixups], which the runtime calls on its way
   out of a frame that died. *)
let mount ctx ~path ~is_root node =
  let live = mount ctx ~path ~is_root ~parent_kind:None node in
  apply_stack_claims ctx;
  live
;;

let patch ctx ~path ~is_root live node =
  let live = patch ctx ~path ~is_root ~parent_kind:None live node in
  apply_stack_claims ctx;
  live
;;

(* Re-applies every controlled prop in the tree and re-runs the pass's fixups, without
   diffing anything.

   For the frames on which Bonsai hands back the physically same node it handed back last
   frame. Nothing in the tree can have changed -- it is the same value -- so there is no
   [update] to run, no [Attrs.diff] to compute and no child list to reconcile. What there
   still is, and what a full walk was really paying for, is the two halves of the
   controlled-prop rule: [Widget_impl.reassert] and the selection fixups. A model
   that *declines* a user's edit renders the same value it rendered last frame, so this is
   precisely the frame on which the widget has to be put back. Skipping it entirely -- the
   obvious optimisation, and the one [Driver.frame_body]'s comment used to refuse --
   leaves the declined edit standing on screen.

   Does not touch [live.node] (it is already the node), does not run [require_specs] (the
   attrs are the same values), does not re-register stack names (nothing moved, so the
   registrations are the ones this same tree made) and does not run lifecycles. The path
   is threaded rather than stored on [live], because [enqueue_fixups] wants one for its
   error messages and [Children.iteri] already spells it the way [mount] and [patch] do.
   Raises whatever a [reassert] raises. *)
let rec reassert_only ctx ~path (live : live) =
  Option.iter live.impl.reassert ~f:(fun f -> f live.widget live.node.kind);
  enqueue_fixups ctx ~path ~widget:live.widget ~interest:(interest_of_kind live.node.kind);
  Children.iteri live.children ~path ~f:(fun path child -> reassert_only ctx ~path child)
;;
