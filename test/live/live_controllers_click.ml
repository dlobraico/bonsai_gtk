open! Core
open Bonsai_gtk_vtree
open Live_controllers_util

(* The click family's plumbing, and the sweep over every controller attr. See
   [live_controllers_util.ml]'s header for what these blocks can and cannot prove: no
   click is deliverable through the pinned binding, so the evidence here is the
   controller's presence, name, button, phase and armed slots. Neither block presents a
   toplevel, which is why this executable's rule carries no [(locks x-display)]. *)

(* Once, before anything below: every block here needs GTK initialised, and the regression
   case has to run before the assertions that depend on the thing it pins. *)
let () = ignore (Ocgtk_gtk.GMain.init () : string array)

(* Regression for the [set_static_name] bug (review C1).

   [gtk_event_controller_set_static_name] stores the pointer it is handed
   {i without copying}, so naming a controller with a runtime-computed OCaml string left
   GTK pointing into the heap: after a collection [get_name] read garbage, and after a
   compaction that returned the chunk to the OS it was a read of unmapped memory --
   reachable from GTK Inspector on any application built with this library.

   It also hollowed out the whole controllers suite. Every [gtk=] line above is
   [observe_controllers] filtered by [Controllers.is_ours], which is that same read: under
   allocation pressure the filter starts rejecting our own controllers, so the lines with
   a [bonsai=] beside them go flaky-red with no bug behind them, and [after destroy]
   passes {i vacuously} -- it cannot tell "removed" from "unnameable". So this runs before
   the assertions that depend on it.

   The churn is deliberate: short-lived allocations force minor collections, and
   [Gc.compact] moves and can release what survives, which is what turns a stale pointer
   from "wrong bytes" into "freed memory". *)
let () =
  let scheduler = Scheduler.create ~run_frame:(fun () -> ()) in
  let ctx =
    P.create_ctx
      ~signals:
        { schedule = (fun e -> Ui_effect.Expert.eval e ~f:Fn.id ~on_exn:raise)
        ; in_patch = (fun () -> Scheduler.in_patch scheduler)
        ; on_exn =
            (fun ~node_path exn -> printf "EXN at %s: %s\n" node_path (Exn.to_string exn))
        }
      ~on_window_created:(fun _ -> ())
      ()
  in
  (* A label, not a button: a label emits no signal at all, so a controller on one can
     only have come from the attr. *)
  let live =
    P.mount
      ctx
      ~path:"gc"
      ~is_root:true
      (Node.label
         ~attrs:
           [ Attr.on_click ~button:2 (fun _ -> Ui_effect.Ignore)
           ; Attr.on_focus_enter (fun () -> Ui_effect.Ignore)
           ]
         "x")
  in
  P.run_fixups ctx;
  controllers "before gc" live live.widget;
  for _ = 1 to 20 do
    for _ = 1 to 100_000 do
      ignore (Sys.opaque_identity (Bytes.create 8) : Bytes.t)
    done;
    Gc.compact ()
  done;
  (* The names must read back exactly as they did, and the gesture's own properties with
     them -- a stale [priv->name] and a stale anything else fail the same way. *)
  controllers "after gc" live live.widget;
  click_gesture_props "after gc" live.widget;
  P.destroy ctx live;
  printf "gc regression done\n"
;;

(* Every controller attr [Events] admits is one [Controllers] actually attaches (review
   I1).

   [Events.controller_family] is what makes these attrs legal on every kind, skipped by
   [Signals.require_slots] and connected by no widget impl. The exhaustive match in
   [Controllers.update] is what stops a family being named there and attached by nothing;
   this is the other half, and it is what catches a family that is dispatched but wired
   {i wrongly} -- a [sync] whose [wanted] reads the empty attr set, say, which the
   compiler cannot see.

   The row list is hand-written because there is no way to derive a *value* per
   constructor of [Attr.Name.t]; the assertion below is what stops it going stale, exactly
   as [live_events.ml]'s [all_kinds] count does for [Kind.t]. *)
let each_controller_attr : (Attr.Name.t * Attr.t) list =
  [ On_click, Attr.on_click (fun _ -> Ui_effect.Ignore)
  ; On_focus_enter, Attr.on_focus_enter (fun () -> Ui_effect.Ignore)
  ; On_focus_leave, Attr.on_focus_leave (fun () -> Ui_effect.Ignore)
  ; On_key_pressed, Attr.on_key_pressed (fun _ -> Key_response.Propagate)
  ; On_key_released, Attr.on_key_released (fun _ -> Ui_effect.Ignore)
  ]
;;

let () =
  assert (
    List.equal
      Attr.Name.equal
      (List.map each_controller_attr ~f:fst)
      (List.filter Attr.Name.all ~f:Events.is_controller_attr))
;;

let () =
  let scheduler = Scheduler.create ~run_frame:(fun () -> ()) in
  let ctx =
    P.create_ctx
      ~signals:
        { schedule = (fun e -> Ui_effect.Expert.eval e ~f:Fn.id ~on_exn:raise)
        ; in_patch = (fun () -> Scheduler.in_patch scheduler)
        ; on_exn =
            (fun ~node_path exn -> printf "EXN at %s: %s\n" node_path (Exn.to_string exn))
        }
      ~on_window_created:(fun _ -> ())
      ()
  in
  List.iter each_controller_attr ~f:(fun (name, attr) ->
    (* A label again: it emits nothing, so anything attached came from the attr, and the
       node is accepted at all only because controller attrs are legal on every kind. *)
    let live = P.mount ctx ~path:"sweep" ~is_root:true (Node.label ~attrs:[ attr ] "x") in
    P.run_fixups ctx;
    printf
      !"%{sexp: Attr.Name.t} -> family=%{sexp: Events.Family.t option} attached=%{sexp: \
        string list}\n"
      name
      (Events.controller_family name)
      (names live.widget);
    P.destroy ctx live);
  printf "every controller attr attaches a controller\n"
;;
