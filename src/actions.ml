open! Core
open Bonsai_gtk_vtree
open Gtk_import

(* The GTK side of {!Attr.actions}: one [GSimpleActionGroup] per node carrying the attr,
   inserted with [Widget.insert_action_group] under the attr's scope, its [GSimpleAction]s
   kept {b controlled} -- [Controllers]' shape over the action system.

   {b Insertion order is load-bearing} (pre-flight correction 1): a group inserted before
   the widget is rooted binds a [PopoverMenu]'s item tracker in every ordering tested; a
   group inserted on an already-rooted widget resolves for {i activation} but never binds
   the tracker, so menu items render permanently insensitive. [Patcher.mount] calls
   {!create}+{!update} while the widget is still unparented -- the parent's insert runs
   after the whole mount returns -- so the normal shape is always the good ordering. The
   attr {i first appearing} on an already-mounted node is the documented limitation; see
   {!Attr.actions}.

   {b The controlled discipline, per spec §6.5 through an action}: [enabled] and [state]
   are written only when they differ from the [GAction] read-back -- cheap, and honest,
   because GTK itself never changes either: we connect no [change-state], and an
   {i activation} never touches state here -- the handler's effect is scheduled, the model
   decides, and the next frame's write moves GTK. A declined toggle never moves the menu's
   checkmark.

   [Simple_action_group.lookup] is banned (non-option, NULL crash -- fact table): this
   module keeps its own name table and never reads GTK back for an action object. *)

type action_state =
  { action : Gio.Simple_action.t
  ; shape : [ `Simple | `Toggle | `Radio ]
      (* A spec whose kind changed shape is a different GTK object (parameter type and
         statefulness are construction-time), so the survivor diff rebuilds it. *)
  ; slot : Action_spec.kind option ref
  ; connection : Signals.connection
  }

type group =
  { scope : string
  ; group_obj : Gio.Simple_action_group.t
  ; actions : (string, action_state) Hashtbl.t
  }

type t =
  { ctx : Signals.ctx
  ; node_path : string
  ; widget : Widget.t
  ; mutable group : group option
  }

let create ctx ~node_path widget = { ctx; node_path; widget; group = None }

(* The activate trampoline, [Signals.dispatch]'s five obligations spelled here because the
   slot is this module's rather than a widget signal's: no exception crosses into C, an
   emission during a patch is dropped (belt: we never write anything that emits
   [activate], but the constraint holds anyway), the handler is read out of the mutable
   slot, the [GVariant] parameter is converted at the boundary, and the effect is
   scheduled. [activate] returns nothing to GTK, so there is no [declined] value. *)
let connect_activate t (action : Gio.Simple_action.t) slot =
  let id =
    Gio.Simple_action.on_activate action ~callback:(fun ~parameter ->
      match
        if t.ctx.in_patch ()
        then ()
        else (
          match !slot with
          | None -> ()
          | Some (Action_spec.Simple eff) -> t.ctx.schedule eff
          | Some (Toggle { on_activate; _ }) -> t.ctx.schedule on_activate
          | Some (Radio { on_activate; _ }) ->
            (match parameter with
             | Some target -> t.ctx.schedule (on_activate (Gvariant.to_string target))
             | None ->
               (* GTK refuses an activation whose parameter does not match the action's
                  declared type, so a radio with no target is unreachable; inert rather
                  than raising, per the trampoline rule. *)
               ()))
      with
      | () -> ()
      | exception exn ->
        (try t.ctx.on_exn ~node_path:t.node_path exn with
         | _ -> ()))
  in
  Signals.connected action id
;;

let shape_of : Action_spec.kind -> _ = function
  | Simple _ -> `Simple
  | Toggle _ -> `Toggle
  | Radio _ -> `Radio
;;

let make_action t (spec : Action_spec.t) =
  let action =
    match spec.kind with
    | Simple _ -> Gio.Simple_action.new_ spec.name None
    | Toggle { state; _ } ->
      Gio.Simple_action.new_stateful spec.name None (Gvariant.of_boolean state)
    | Radio { state; _ } ->
      Gio.Simple_action.new_stateful
        spec.name
        (Some Gvariant_type.string)
        (Gvariant.of_string state)
  in
  if not spec.enabled then Gio.Simple_action.set_enabled action false;
  let slot = ref (Some spec.kind) in
  let connection = connect_activate t action slot in
  { action; shape = shape_of spec.kind; slot; connection }
;;

(* The controlled writes, against the [GAction]-interface read-backs. [get_state] answers
   an option (correctly: a stateless action has none); a stateful action of ours always
   has one, and a [None] read-back is treated as "differs" so the write repairs it. *)
let sync_surviving (st : action_state) (spec : Action_spec.t) =
  st.slot := Some spec.kind;
  let as_action = Gio.Action.from_gobject st.action in
  if not (Bool.equal (Gio.Action.get_enabled as_action) spec.enabled)
  then Gio.Simple_action.set_enabled st.action spec.enabled;
  match spec.kind with
  | Simple _ -> ()
  | Toggle { state; _ } ->
    let current =
      match Gio.Action.get_state as_action with
      | Some v -> Some (Gvariant.to_boolean v)
      | None -> None
    in
    if not (Option.equal Bool.equal current (Some state))
    then Gio.Simple_action.set_state st.action (Gvariant.of_boolean state)
  | Radio { state; _ } ->
    let current =
      match Gio.Action.get_state as_action with
      | Some v -> Some (Gvariant.to_string v)
      | None -> None
    in
    if not (Option.equal String.equal current (Some state))
    then Gio.Simple_action.set_state st.action (Gvariant.of_string state)
;;

let remove_action group name (st : action_state) =
  st.slot := None;
  Signals.disconnect [ st.connection ];
  Gio.Simple_action_group.remove group.group_obj name
;;

let build_group t ~scope ~(specs : Action_spec.t list) =
  let group_obj = Gio.Simple_action_group.new_ () in
  let actions = Hashtbl.create (module String) in
  List.iter specs ~f:(fun spec ->
    let st = make_action t spec in
    Gio.Simple_action_group.insert group_obj (Gio.Action.from_gobject st.action);
    Hashtbl.set actions ~key:spec.name ~data:st);
  Widget.insert_action_group
    t.widget
    scope
    (Some (Gio.Action_group.from_gobject group_obj));
  { scope; group_obj; actions }
;;

let release_group t (g : group) =
  (* Slots emptied and handlers disconnected before the group leaves the widget, the
     teardown ordering every controller follows. *)
  Hashtbl.iteri g.actions ~f:(fun ~key:_ ~data:st ->
    st.slot := None;
    Signals.disconnect [ st.connection ]);
  Widget.insert_action_group t.widget g.scope None
;;

let update t attrs =
  let wanted =
    match (Attrs.find attrs Attr.Name.Actions :> Attr.Private.t option) with
    | Some (Actions { scope; specs }) -> Some (scope, specs)
    | Some _ | None -> None
  in
  match t.group, wanted with
  | None, None -> ()
  | Some g, None ->
    release_group t g;
    t.group <- None
  | None, Some (scope, specs) -> t.group <- Some (build_group t ~scope ~specs)
  | Some g, Some (scope, specs) when not (String.equal g.scope scope) ->
    (* A renamed scope is a different name GTK resolves under: the old group leaves in
       full and a fresh one arrives, exactly as a kind change remounts a widget. *)
    release_group t g;
    t.group <- Some (build_group t ~scope ~specs)
  | Some g, Some (_, specs) ->
    let wanted_names = List.map specs ~f:(fun (s : Action_spec.t) -> s.name) in
    (* Departures first, so a name that changes shape in place (removed under one kind,
       arriving under another) never has two GTK actions alive at once. *)
    Hashtbl.filteri_inplace g.actions ~f:(fun ~key:name ~data:st ->
      if List.mem wanted_names name ~equal:String.equal
      then true
      else (
        remove_action g name st;
        false));
    List.iter specs ~f:(fun spec ->
      match Hashtbl.find g.actions spec.name with
      | Some st when Poly.equal st.shape (shape_of spec.kind) -> sync_surviving st spec
      | Some st ->
        remove_action g spec.name st;
        let st = make_action t spec in
        Gio.Simple_action_group.insert g.group_obj (Gio.Action.from_gobject st.action);
        Hashtbl.set g.actions ~key:spec.name ~data:st
      | None ->
        let st = make_action t spec in
        Gio.Simple_action_group.insert g.group_obj (Gio.Action.from_gobject st.action);
        Hashtbl.set g.actions ~key:spec.name ~data:st)
;;

(* The pre-unparent disarming, [Controllers.clear]'s half: slots only, so an [activate]
   GTK emits while the subtree comes apart reaches nothing, and the detaching stays
   [release]'s. *)
let clear t =
  Option.iter t.group ~f:(fun g -> Hashtbl.iter g.actions ~f:(fun st -> st.slot := None))
;;

let release t =
  Option.iter t.group ~f:(fun g -> release_group t g);
  t.group <- None
;;

(* The GTK-side read-back, for tests: what [GAction] answers for each name, which is the
   only honest source for a controlled-prop golden -- the runtime's own bookkeeping cannot
   certify itself. Sorted by name so the golden is stable. *)
let dump t =
  match t.group with
  | None -> Sexp.Atom "no-group"
  | Some g ->
    let rows =
      Hashtbl.to_alist g.actions
      |> List.sort ~compare:(fun (a, _) (b, _) -> String.compare a b)
      |> List.map ~f:(fun (name, st) ->
        let a = Gio.Action.from_gobject st.action in
        let state =
          match Gio.Action.get_state a with
          | None -> Sexp.Atom "-"
          | Some v ->
            (match st.shape with
             | `Toggle -> Bool.sexp_of_t (Gvariant.to_boolean v)
             | `Radio -> String.sexp_of_t (Gvariant.to_string v)
             | `Simple -> Sexp.Atom "?")
        in
        Sexp.List
          [ Atom name
          ; List [ Atom "enabled"; Bool.sexp_of_t (Gio.Action.get_enabled a) ]
          ; List [ Atom "state"; state ]
          ])
    in
    Sexp.List (Sexp.List [ Atom "scope"; Atom g.scope ] :: rows)
;;
