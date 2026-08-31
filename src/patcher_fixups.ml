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
  ; (* The [Attr.autofocus] grabs this pass decided to fire -- a mount carrying [true], or
       a patch flipping false-to-true -- applied by [run_fixups] after the generic queue.
       A queue of its own rather than closures in [fixups], because the
       once-per-frame-per-toplevel check has to see all of them together. *)
    autofocus_claims : autofocus_claim Queue.t
  }

and autofocus_claim =
  { autofocus_path : string
  ; autofocus_widget : Widget.t
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
  ; autofocus_claims = Queue.create ()
  }
;;

let claim_autofocus ctx ~path widget =
  Queue.enqueue ctx.autofocus_claims { autofocus_path = path; autofocus_widget = widget }
;;

(* The grabs of one pass, checked together and then fired. Two grabs aimed at one toplevel
   is the single-referent rule broken -- neither could win except by walk order, which is
   not a thing a model should be able to depend on -- so it raises, naming both paths,
   with the string [Bonsai_gtk_test] renders for the same tree. Grabs aimed at
   {i different} toplevels are independent and all fire ([Node.windows] is Task 8, and
   this is written for it); the toplevel is read with [get_root] now that the tree exists,
   and claims whose widget has no root yet -- an [Embed.create] pass, whose tree is
   parented by the caller after the frame -- are grouped together, as the one tree they
   are.

   The [bool] answer of [grab_focus] is dropped: a widget that refuses the grab (not
   focusable, or its focus vfunc declined) is GTK's answer at grab time, and there is
   nothing to do about it on this frame. Fire-once means exactly that.

   Emptied even when the duplicate check raises, on [run_fixups]'s reasoning: the queue
   describes one pass. *)
let apply_autofocus ctx =
  Exn.protect
    ~f:(fun () ->
      let claims = Queue.to_list ctx.autofocus_claims in
      let root_of c = Widget.get_root c.autofocus_widget in
      let same_toplevel a b =
        match root_of a, root_of b with
        | Some ra, Some rb -> Gobject.same ra rb
        | None, None -> true
        | Some _, None | None, Some _ -> false
      in
      List.iteri claims ~f:(fun i c ->
        match
          List.find (List.take claims i) ~f:(fun earlier -> same_toplevel earlier c)
        with
        | Some earlier ->
          invalid_arg
            (Events.autofocus_rejection
               ~first:earlier.autofocus_path
               ~second:c.autofocus_path)
        | None -> ());
      List.iter claims ~f:(fun c -> ignore (Widget.grab_focus c.autofocus_widget : bool)))
    ~finally:(fun () -> Queue.clear ctx.autofocus_claims)
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
    ~finally:(fun () -> Queue.clear ctx.fixups);
  (* After the generic queue, so a selection the same frame set has settled before focus
     moves; a raise in the queue above abandons these (the [finally] runs, [apply] does
     not), which matches the all-or-nothing a raising frame already has. *)
  apply_autofocus ctx
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
  Queue.clear ctx.stack_claims;
  Queue.clear ctx.autofocus_claims
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
     outside GTK's 1-9999 and any [GtkEditable]'s [~text] with a NUL in it are both writes
     the widget will not take; the impls refuse them and this is where the path comes
     from. *)
  | Calendar
  (* The popover's controlled [~open_], applied from the fixups because [popup] needs the
     popover parented -- its [create] runs before the menu button's slot [set] -- and
     because [enqueue_fixups] runs on the mount, patch {i and} reassert-only passes, which
     is exactly the coverage a controlled prop needs (the reassert frame is the one that
     re-opens a declined dismissal). *)
  | Popover of Kind.popover_props
  (* One arm for four kinds, because they are one widget as far as the text is concerned:
     entry, password entry, search entry and editable label all write their [~text]
     through [W_entry.set_text_if_needed], which refuses a NUL and records the refusal in
     one table, so there is one [take_report] to ask. *)
  | Editable

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
  | Popover p -> Popover p
  | Entry _ | Password_entry _ | Search_entry _ | Editable_label _ -> Editable
  | Label _
  | Button _
  | Toggle_button _
  | Check_button _
  | Switch _
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
  | Header_bar _
  | Action_bar _
  | Menu_button _
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
  (* The fifth caller, over four kinds at once: a [~text] with a NUL in it is refused by
     [W_entry.set_text_if_needed] whichever [GtkEditable] widget it was written through,
     and the refusals of all four live in one table. *)
  | Editable -> Option.iter (W_entry.take_report widget) ~f:(ctx.report ~node_path:path)
  | Popover { open_; _ } ->
    (* Deferred for the reason the selections are: during the mount walk the popover is
       not yet parented into its menu button when its own node is reached, and [popup] on
       an unparented popover is a GTK critical. By fixup time the whole tree exists. *)
    Queue.enqueue ctx.fixups (fun () -> W_popover.apply_open widget ~open_)
  | Stack { visible_child; _ } ->
    (* Enqueued rather than applied: the pages are attached after this on a mount, and
       patched after this on a patch, and a page GTK does not have yet cannot be selected.
       It is also the only place that can tell a page which is not there {i yet} from one
       that is never coming, which is why [W_stack.select] rejects an unknown name and why
       the path is prefixed here -- [select] knows no more about where it is than any
       other container op does (spec §11). *)
    Queue.enqueue ctx.fixups (fun () ->
      Patcher_checks.child_op ~path (fun () -> W_stack.select widget ~visible_child);
      (* After the attempt, because the report the attempt may have minted -- a
         [~visible_child] naming a hidden page, which GTK declines silently and which
         [select] therefore says once -- is this pass's news. Same shape as the
         [take_report] arms above, sequenced inside the fixup because the refusal is
         decided there rather than in [reassert]. *)
      Option.iter (W_stack.take_report widget) ~f:(ctx.report ~node_path:path))
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
    Queue.enqueue ctx.fixups (fun () ->
      W_list_box.apply_selection widget ~selected;
      (* The dedup report, on the select-fixup arms' pattern: a [~selected] that lists a
         key twice is deduped and said once, and the fixup is where that is decided. *)
      Option.iter (W_list_box.take_report widget) ~f:(ctx.report ~node_path:path))
  | Flow_box { selected; _ } ->
    (* The list box's arm, over the other container: the children are attached after this
       on a mount and patched after this on a patch, and a key naming no child is ignored
       rather than rejected, so there is no path to prefix here either. *)
    Queue.enqueue ctx.fixups (fun () ->
      W_flow_box.apply_selection widget ~selected;
      (* The list box's polling, over the other copy of the same container. *)
      Option.iter (W_flow_box.take_report widget) ~f:(ctx.report ~node_path:path))
  | Notebook { current_page; _ } ->
    (* A stack's arm over the other container that shows exactly one child, and it rejects
       an unknown key for the same reason: the pages are attached after this on a mount
       and patched after this on a patch, so this is the only place that can tell a page
       that is not there {i yet} from one that is never coming. The path is prefixed here
       -- [select] knows no more about where it is than any other container op does (spec
       §11). *)
    Queue.enqueue ctx.fixups (fun () ->
      Patcher_checks.child_op ~path (fun () -> W_notebook.select widget ~current_page);
      (* The stack arm's polling, over the twin divergence: a hidden [~current_page]. *)
      Option.iter (W_notebook.take_report widget) ~f:(ctx.report ~node_path:path))
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
   | Popover _
   | Editable -> ());
  enqueue_fixups ctx ~path ~widget ~interest
;;
