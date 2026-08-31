### Task 3: Signals carry a value — Button (extended), ToggleButton, CheckButton, Switch

The first task to add widgets, and the one that generalises `Signals`. M0's `Signals.spec.fire : Attr.t -> unit Effect.t option` can only build handlers that take no argument, because ocgtk's `on_*` callbacks are mostly `unit -> unit` and the value the user just changed lives on the widget. Spec §6.4 step 4 ("converts GTK arguments to the OCaml event value") is satisfied by giving `fire` the widget and reading the value back with the class getter — which is also exactly how the `notify::<prop>` family has to work, since the generic marshaller carries no payload at all.

**Files:**
- Create: `src/widgets/w_toggle_button.ml`, `src/widgets/w_check_button.ml`, `src/widgets/w_switch.ml`, `test/live/live_controls.ml`, `test/live/expected_controls.txt`
- Modify: `src/signals.ml`, `src/signals.mli`, `src/widget_impl.ml`, `src/widget_impl.mli`, `src/patcher.ml`, `src/widgets/w_button.ml`, `src/widgets/registry.ml`, `src/live_tree.ml`, `vtree/attr.ml(i)`, `vtree/kind.ml(i)`, `vtree/node.ml(i)`, `test_lib/bonsai_gtk_test.ml(i)`, `test/test_widgets.ml`, `test/test_handle.ml`, `test/live/dune`

**Interfaces:**
- Produces:
  ```ocaml
  (* Signals *)
  type spec =
    { attr : Attr.Name.t
    ; connect : Widget.t -> callback:(unit -> unit) -> Gobject.Signal.handler_id
    ; fire : Widget.t -> Attr.t -> unit Ui_effect.t option
    }
  val notify : prop:string -> Widget.t -> callback:(unit -> unit) -> Gobject.Signal.handler_id
  val require_specs : node_path:string -> impl_name:string -> spec list -> Attrs.t -> unit

  (* Widget_impl *)
  val batch : Widget.t -> (unit -> unit) -> unit   (* freeze_notify / thaw_notify *)

  (* Attr *)
  val on_toggled : (bool -> unit Ui_effect.t) -> t

  (* Node *)
  val button
    :  ?key:Key.t -> ?attrs:Attr.t list -> ?label:string -> ?icon_name:string
    -> ?has_frame:bool -> ?child:t -> unit -> t
  val toggle_button
    :  ?key:Key.t -> ?attrs:Attr.t list -> ?label:string -> ?icon_name:string
    -> ?has_frame:bool -> ?child:t -> active:bool -> unit -> t
  val check_button
    :  ?key:Key.t -> ?attrs:Attr.t list -> ?label:string -> ?inconsistent:bool
    -> active:bool -> unit -> t
  val switch : ?key:Key.t -> ?attrs:Attr.t list -> active:bool -> unit -> t

  (* Bonsai_gtk_test.Action *)
  type t = Click of string | Toggle of string
  ```
- Consumes: `W.Button.{new_,new_with_label,new_from_icon_name,set_label,set_icon_name,set_has_frame,set_child,on_clicked}`, `W.Toggle_button.{new_,set_active,get_active,on_toggled}`, `W.Check_button.{new_,set_label,set_active,get_active,set_inconsistent,set_child,on_toggled}`, `W.Switch.{new_,set_active,get_active,set_state}`, `Gobject.Signal.connect_simple`, `Gobject.Property.{freeze_notify,thaw_notify}`.

Three shape notes before the code:

1. **Button gains a child slot.** Spec §5.1 gives `button` a `?child`. `Widget_impl.children` is fixed per kind, so `Button` becomes `Single` and `Node.button` always produces `Single child_opt` — a plain `~label:"+"` button now has `(children (Single ()))` instead of `(children No_children)` in its sexp. Update `test/test_node.ml`, `test/test_handle.ml` and the live expected files accordingly; they are the only readers.
2. **Switch has no `toggled`.** GTK4's `GtkSwitch` emits `state-set` (whose callback returns `bool`, "handled") and `notify::active`. `state-set` is the wrong hook for a controlled widget — returning `true` suppresses GTK's own state update and desynchronises `active` from `state`. Connect `notify::active` and read `get_active`. Documented on `Node.switch`.
3. **An event attr on a widget that cannot emit it is an error.** `Attr.on_toggled` on a `Node.label` is a typo the library should catch, and spec §5.1 says so. `Signals.require_specs` checks, at mount, that every `On_*` attr in the node's attrs is claimed by one of the impl's specs, and raises `Invalid_argument` with the node path otherwise. It needs to know which names are event names: add `Attr.Name.is_event : t -> bool` (a match listing the `On_*` constructors) beside it.

- [ ] **Step 1: Write the failing headless tests** (`test/test_widgets.ml`, append)

```ocaml
let%expect_test "the toggle family's constructors" =
  print_s
    [%sexp
      (Node.box
         ~orientation:Vertical
         [ Node.button ~label:"go" ()
         ; Node.button ~icon_name:"list-add-symbolic" ~has_frame:false ()
         ; Node.button ~child:(Node.label "boxed") ()
         ; Node.toggle_button ~label:"bold" ~active:true ()
         ; Node.check_button ~label:"agree" ~active:false ()
         ; Node.switch ~active:true ()
         ]
       : Node.t)];
  [%expect {| |}]
;;
```

`test/test_handle.ml` — a component whose state is driven by a `Toggle` action, which is the whole reason `Bonsai_gtk_test` grows one:

```ocaml
let toggler (graph @ local) =
  let on, set_on = Bonsai.state false graph in
  let%arr on and set_on in
  Node.window
    ~title:"Toggler"
    (Node.box
       ~orientation:Vertical
       [ Node.switch ~attrs:[ Attr.test_id "sw"; Attr.on_toggled set_on ] ~active:on ()
       ; Node.label ~attrs:[ Attr.test_id "state" ] (if on then "on" else "off")
       ])
;;

let%expect_test "Toggle fires the handler with the value the widget would take" =
  let handle = Bonsai_gtk_test.create toggler in
  Bonsai_gtk_test.Handle.show handle;
  [%expect {| |}];
  Bonsai_gtk_test.Handle.do_actions handle [ Toggle "sw" ];
  Bonsai_gtk_test.Handle.show_diff handle;
  [%expect {| |}]
;;
```

- [ ] **Step 2: Write the failing live test** (`test/live/live_controls.ml`)

This file grows through Tasks 3–5; start it with the toggle family, and with the end-to-end reentrancy case the backlog wants — a widget whose *programmatic* update emits its own signal.

```ocaml
open! Core
open Bonsai_gtk_vtree
module Gobject = Bonsai_gtk.Private.Gtk_import.Gobject
module Live_tree = Bonsai_gtk.Private.Live_tree
module P = Bonsai_gtk.Private.Patcher
module Scheduler = Bonsai_gtk.Private.Scheduler

let nth_child (live : P.live) i : P.live =
  match live.children with
  | Single (Some box) ->
    (match box.children with
     | List children -> List.nth_exn children i
     | _ -> assert false)
  | _ -> assert false
;;

let () =
  ignore (Ocgtk_gtk.GMain.init () : string array);
  let scheduled = ref 0 in
  let scheduler = Scheduler.create ~run_frame:(fun () -> ()) in
  let ctx : P.ctx =
    { signals =
        { schedule = (fun _ -> incr scheduled)
        ; in_patch = (fun () -> Scheduler.in_patch scheduler)
        ; on_exn = (fun ~node_path exn -> printf "EXN at %s: %s\n" node_path (Exn.to_string exn))
        }
    ; on_window_created = (fun _ -> ())
    }
  in
  let view ~active =
    Node.window
      ~title:"controls"
      (Node.box
         ~orientation:Vertical
         [ Node.button ~label:"plain" ()
         ; Node.button ~icon_name:"list-add-symbolic" ~has_frame:false ()
         ; Node.button ~child:(Node.label "boxed") ()
         ; Node.toggle_button
             ~attrs:[ Attr.on_toggled (fun _ -> Ui_effect.Ignore) ]
             ~label:"bold"
             ~active
             ()
         ; Node.check_button
             ~attrs:[ Attr.on_toggled (fun _ -> Ui_effect.Ignore) ]
             ~label:"agree"
             ~active
             ()
         ; Node.switch ~attrs:[ Attr.on_toggled (fun _ -> Ui_effect.Ignore) ] ~active ()
         ])
  in
  let live = P.mount ctx ~path:"root" ~is_root:true (view ~active:false) in
  print_s (Live_tree.dump live.widget);
  (* THE reentrancy case the M0 backlog asks for: flipping [active] from the model makes
     GTK emit [toggled] / [notify::active] synchronously, inside the patch. Nothing may
     reach Bonsai from there -- the model is the single source of truth (spec §4.4). *)
  let before = !scheduled in
  let live =
    Scheduler.with_patch_guard scheduler (fun () ->
      P.patch ctx ~path:"root" ~is_root:true live (view ~active:true))
  in
  printf "scheduled during patch: %d\n" (!scheduled - before);
  print_s (Live_tree.dump live.widget);
  (* Outside the patch the same signals do reach Bonsai. *)
  Gobject.Signal.emit_by_name (nth_child live 3).widget ~name:"toggled";
  Gobject.Signal.emit_by_name (nth_child live 4).widget ~name:"toggled";
  printf "scheduled outside patch: %d\n" (!scheduled - before);
  (* An event attr the widget cannot emit is a typo, and a loud one. *)
  (match
     P.mount
       ctx
       ~path:"root"
       ~is_root:true
       (Node.window ~title:"bad" (Node.label ~attrs:[ Attr.on_toggled (fun _ -> Ui_effect.Ignore) ] "x"))
   with
   | (_ : P.live) -> print_endline "BUG: on_toggled on a label accepted"
   | exception Invalid_argument msg -> printf "rejected: %s\n" msg);
  P.destroy ctx live
;;
```

Add `live_controls` to `test/live/dune`'s `(names ...)` and a matching rule (copy the `live_signals` one).

- [ ] **Step 3: Run to verify failure** — both suites; unbound `Node.toggle_button`, `Attr.on_toggled`, `Scheduler.create` not exported.
`Scheduler` is already in `Bonsai_gtk.Private`; check `scheduler.mli` exposes `create`, `in_patch`, `with_patch_guard` and add them if not.

- [ ] **Step 4: `src/signals.ml(i)`**

```ocaml
type spec =
  { attr : Attr.Name.t
  ; connect : Widget.t -> callback:(unit -> unit) -> Gobject.Signal.handler_id
  ; fire : Widget.t -> Attr.t -> unit Ui_effect.t option
  }

let dispatch ctx w slot spec =
  if ctx.in_patch ()
  then ()
  else (
    match !slot with
    | None -> ()
    | Some attr ->
      (match spec.fire w attr with
       | None -> ()
       | Some effect -> ctx.schedule effect))
;;

(* [connect_all] is otherwise unchanged; the callback becomes
   [fun () -> match dispatch ctx w slot spec with ...]. *)

(* ocgtk generates no [on_notify_*]: detailed signal names go through the generic
   marshaller, which carries no payload, so the handler reads the property back off the
   widget with the class getter (spec §6.4). [~after:false] matches every generated
   [on_*], which defaults [?after] to false. *)
let notify ~prop w ~callback =
  Gobject.Signal.connect_simple w ~name:("notify::" ^ prop) ~callback ~after:false
;;

(* An [on_*] attr on a widget whose impl declares no spec for it is a typo that would
   otherwise be silently inert -- the slot is never written, so the handler never runs and
   nothing says why (spec §5.1, §11). *)
let require_specs ~node_path ~impl_name specs attrs =
  List.iter (Attrs.to_list attrs) ~f:(fun attr ->
    match Attr.name attr with
    | Some name when Attr.Name.is_event name ->
      if not (List.exists specs ~f:(fun s -> Attr.Name.equal s.attr name))
      then
        invalid_argf
          !"%s: %s does not emit %{sexp:Attr.Name.t}"
          node_path
          impl_name
          name
          ()
    | Some _ | None -> ())
;;
```

`Attr.Name.is_event`, in `vtree/attr.ml(i)`:
```ocaml
(** [true] for the handler-carrying names -- the ones a widget impl must declare a signal
    spec for. *)
let is_event = function
  | On_clicked | On_toggled -> true
  | Margin_start | Margin_end | Margin_top | Margin_bottom | Halign | Valign | Hexpand
  | Vexpand | Sensitive | Visible | Tooltip | Width_request | Height_request | Opacity
  | Focusable | Can_focus | Widget_name | Cursor_name | Test_id -> false
;;
```
Write it as an exhaustive match, never a `_ -> false`: every task below adds `On_*` names, and the compiler must force each one to be classified.

Call it from `Patcher.mount`, right before `connect_all`:
```ocaml
  Signals.require_specs ~node_path:path ~impl_name:impl.name impl.signals node.attrs;
```

- [ ] **Step 5: `src/widget_impl.ml(i)` — `batch`**

```ocaml
(* Spec §7: a prop batch is bracketed, so GTK emits one round of [notify::] at the end
   rather than one per setter -- which matters here beyond tidiness, because every
   [notify::] we emit is one the [in_patch] guard has to swallow. [protect] rather than a
   bare pair: an exception between the two would leave the object frozen forever. *)
let batch (w : Widget.t) f =
  Gobject.Property.freeze_notify w;
  Exn.protect ~f ~finally:(fun () -> Gobject.Property.thaw_notify w)
;;
```
Use it in every `update` that writes more than one property, starting with the impls below.

- [ ] **Step 6: `vtree/attr.ml(i)`** — `On_toggled of bool Handler.t`

```ocaml
(* Name.t: *) | On_toggled
(* t:      *) | On_toggled of bool Handler.t
(* name:   *) | On_toggled _ -> Some On_toggled
(* equal:  *) | On_toggled a, On_toggled b -> Handler.equal a b

(** Fires when the user flips a [toggle_button], [check_button] or [switch], carrying the
    value the widget now has. Programmatic changes -- the ones a re-render makes -- do not
    fire it: the patcher's reentrancy guard drops them, because the model is already the
    source of that value. *)
let on_toggled f = On_toggled f
```
Add `| On_toggled _ -> ()` to `Attr_apply.set` and `| On_toggled -> ()` to `unset`.

- [ ] **Step 7: `vtree/kind.ml(i)` / `node.ml(i)`**

```ocaml
type button_props =
  { label : string option
  ; icon_name : string option
  ; has_frame : bool
  }
[@@deriving sexp_of, equal]

type toggle_button_props =
  { label : string option
  ; icon_name : string option
  ; has_frame : bool
  ; active : bool
  }
[@@deriving sexp_of, equal]

type check_button_props =
  { label : string option
  ; active : bool
  ; inconsistent : bool
  }
[@@deriving sexp_of, equal]

type switch_props = { active : bool } [@@deriving sexp_of, equal]

type t =
  | Label of label_props
  | Button of button_props
  | Toggle_button of toggle_button_props
  | Check_button of check_button_props
  | Switch of switch_props
  | Box of box_props
  | Window of window_props
  | Native of Native.t
```
`name`: `"Button" | "ToggleButton" | "CheckButton" | "Switch"`. `same_kind`: one arm each. `equal_props`: `equal_button_props a b`, etc.

```ocaml
let button ?key ?attrs ?label ?icon_name ?(has_frame = true) ?child () =
  make ?key ?attrs (Button { label; icon_name; has_frame }) (Single child)
;;

let toggle_button ?key ?attrs ?label ?icon_name ?(has_frame = true) ?child ~active () =
  make ?key ?attrs (Toggle_button { label; icon_name; has_frame; active }) (Single child)
;;

let check_button ?key ?attrs ?label ?(inconsistent = false) ~active () =
  make ?key ?attrs (Check_button { label; active; inconsistent }) (Single None)
;;

let switch ?key ?attrs ~active () = make ?key ?attrs (Switch { active }) No_children
```
`check_button` takes no `?child`: GTK allows one, but a check button with both a label and a child is a GTK warning, and `?label` covers every real use. Note it in the mli.

mli doc comments to write:
- `button`: "`label`, `icon_name` and `child` are alternatives; giving more than one is a GTK warning, and the last one GTK applies wins. `has_frame:false` is the flat/ghost button stavekeeper spells `stk-btn-ghost`."
- `toggle_button` / `check_button` / `switch`: "`active` is *controlled*: the widget is written only when the model's value differs from what the widget currently shows, so a model that ignores `Attr.on_toggled` pins the widget rather than fighting the user. Pair it with `Attr.on_toggled` or the control is inert."
- `switch`: "GTK's `state-set` signal is deliberately not exposed: returning `true` from it suppresses GTK's own state update and desynchronises `state` from `active`. `Attr.on_toggled` is `notify::active`."

- [ ] **Step 8: `src/widgets/w_button.ml`**

```ocaml
open! Core
open Bonsai_gtk_vtree
open Gtk_import

let clicked : Signals.spec =
  { attr = Attr.Name.On_clicked
  ; connect = (fun w ~callback -> W.Button.on_clicked (cast w) ~callback)
  ; fire =
      (fun _w (attr : Attr.t) ->
        match attr with
        | On_clicked handler -> Some (handler ())
        | _ -> None)
  }
;;

(* Shared with [w_toggle_button.ml]: a GtkToggleButton *is* a GtkButton, so the label /
   icon-name / has-frame props are set through the same calls. *)
let apply_button_props
  (b : W.Button.t)
  ~(old : (string option * string option * bool) option)
  ~label
  ~icon_name
  ~has_frame
  =
  let changed get = match old with
    | None -> true
    | Some o -> not (Poly.equal (get o) (get (label, icon_name, has_frame)))
  in
  if changed (fun (l, _, _) -> l)
  then
    (* GTK has no "unset label"; [set_label ""] is the closest thing, and it is what a
       [None] label renders as anyway. *)
    W.Button.set_label b (Option.value label ~default:"");
  if changed (fun (_, i, _) -> i)
  then Option.iter icon_name ~f:(W.Button.set_icon_name b);
  if changed (fun (_, _, f) -> f) then W.Button.set_has_frame b has_frame
;;

let impl : Widget_impl.t =
  { name = "Button"
  ; create =
      (fun (kind : Kind.t) ->
        match kind with
        | Button p ->
          let b =
            match p.icon_name, p.label with
            | Some icon, _ -> W.Button.new_from_icon_name icon
            | None, Some label -> W.Button.new_with_label label
            | None, None -> W.Button.new_ ()
          in
          if not p.has_frame then W.Button.set_has_frame b false;
          (b :> Widget.t)
        | k -> Widget_impl.wrong_kind "Button" k)
  ; update =
      (fun w ~(old : Kind.t) (new_ : Kind.t) ->
        match old, new_ with
        | Button old, Button new_ ->
          Widget_impl.batch w (fun () ->
            apply_button_props
              (cast w)
              ~old:(Some (old.label, old.icon_name, old.has_frame))
              ~label:new_.label
              ~icon_name:new_.icon_name
              ~has_frame:new_.has_frame)
        | _, k -> Widget_impl.wrong_kind "Button" k)
  ; signals = [ clicked ]
  ; children = Widget_impl.Single { set = (fun w child -> W.Button.set_child (cast w) child) }
  }
;;
```

`icon_name` is set only when present, never cleared: `Button.set_icon_name` takes a plain `string`, so there is no "no icon" value, and switching a button from an icon back to a label is expressed by setting the label (which replaces the icon child). Say so in the mli.

- [ ] **Step 9: `src/widgets/w_toggle_button.ml`**

```ocaml
open! Core
open Bonsai_gtk_vtree
open Gtk_import

let toggled : Signals.spec =
  { attr = Attr.Name.On_toggled
  ; connect = (fun w ~callback -> W.Toggle_button.on_toggled (cast w) ~callback)
  ; fire =
      (fun w (attr : Attr.t) ->
        match attr with
        | On_toggled handler -> Some (handler (W.Toggle_button.get_active (cast w)))
        | _ -> None)
  }
;;

let impl : Widget_impl.t =
  { name = "ToggleButton"
  ; create =
      (fun (kind : Kind.t) ->
        match kind with
        | Toggle_button p ->
          let b =
            match p.icon_name, p.label with
            | Some _, _ | None, _ -> W.Toggle_button.new_ ()
          in
          let as_button : W.Button.t = cast b in
          W_button.apply_button_props
            as_button
            ~old:None
            ~label:p.label
            ~icon_name:p.icon_name
            ~has_frame:p.has_frame;
          if p.active then W.Toggle_button.set_active b true;
          (b :> Widget.t)
        | k -> Widget_impl.wrong_kind "ToggleButton" k)
  ; update =
      (fun w ~(old : Kind.t) (new_ : Kind.t) ->
        match old, new_ with
        | Toggle_button old, Toggle_button new_ ->
          Widget_impl.batch w (fun () ->
            W_button.apply_button_props
              (cast w)
              ~old:(Some (old.label, old.icon_name, old.has_frame))
              ~label:new_.label
              ~icon_name:new_.icon_name
              ~has_frame:new_.has_frame;
            (* Controlled, per the global constraints: compare against what the widget
               currently shows, not against [old.active]. The user may have flipped it
               since the last render, and a model that chose not to follow must pin the
               widget back rather than skip the write. *)
            let b : W.Toggle_button.t = cast w in
            if not (Bool.equal (W.Toggle_button.get_active b) new_.active)
            then W.Toggle_button.set_active b new_.active)
        | _, k -> Widget_impl.wrong_kind "ToggleButton" k)
  ; signals = [ toggled ]
  ; children = Widget_impl.Single { set = (fun w child -> W.Button.set_child (cast w) child) }
  }
;;
```
The `match p.icon_name, p.label with Some _, _ | None, _ -> W.Toggle_button.new_ ()` is deliberate and should be written as plain `W.Toggle_button.new_ ()`: `GtkToggleButton` has `new_with_label` but no `new_from_icon_name`, so both props go through the shared setter path. Simplify it when writing the file.

- [ ] **Step 10: `src/widgets/w_check_button.ml`**

```ocaml
open! Core
open Bonsai_gtk_vtree
open Gtk_import

let toggled : Signals.spec =
  { attr = Attr.Name.On_toggled
  ; connect = (fun w ~callback -> W.Check_button.on_toggled (cast w) ~callback)
  ; fire =
      (fun w (attr : Attr.t) ->
        match attr with
        | On_toggled handler -> Some (handler (W.Check_button.get_active (cast w)))
        | _ -> None)
  }
;;

let impl : Widget_impl.t =
  { name = "CheckButton"
  ; create =
      (fun (kind : Kind.t) ->
        match kind with
        | Check_button p ->
          let c = W.Check_button.new_ () in
          W.Check_button.set_label c p.label;
          if p.active then W.Check_button.set_active c true;
          if p.inconsistent then W.Check_button.set_inconsistent c true;
          (c :> Widget.t)
        | k -> Widget_impl.wrong_kind "CheckButton" k)
  ; update =
      (fun w ~(old : Kind.t) (new_ : Kind.t) ->
        match old, new_ with
        | Check_button old, Check_button new_ ->
          let c : W.Check_button.t = cast w in
          Widget_impl.batch w (fun () ->
            if not (Option.equal String.equal old.label new_.label)
            then W.Check_button.set_label c new_.label;
            if not (Bool.equal old.inconsistent new_.inconsistent)
            then W.Check_button.set_inconsistent c new_.inconsistent;
            if not (Bool.equal (W.Check_button.get_active c) new_.active)
            then W.Check_button.set_active c new_.active)
        | _, k -> Widget_impl.wrong_kind "CheckButton" k)
  ; signals = [ toggled ]
  ; children = Widget_impl.No_children
  }
;;
```
Radio groups (`Check_button.set_group`) are out of scope: a group is a reference to a *sibling widget*, which the vtree cannot name, and modelling "which of these is chosen" in Bonsai state and rendering N check buttons is both simpler and what a Bonsai app wants. Say that in `Node.check_button`'s doc comment.

- [ ] **Step 11: `src/widgets/w_switch.ml`**

```ocaml
open! Core
open Bonsai_gtk_vtree
open Gtk_import

(* [state-set] is the signal that looks right and is not: its callback's [bool] return
   suppresses GTK's own state update, which desynchronises [state] from [active] the first
   time a handler returns [true]. ocgtk exposes no [on_notify_active], so this goes through
   the generic marshaller by detailed name (spec §6.4). *)
let toggled : Signals.spec =
  { attr = Attr.Name.On_toggled
  ; connect = Signals.notify ~prop:"active"
  ; fire =
      (fun w (attr : Attr.t) ->
        match attr with
        | On_toggled handler -> Some (handler (W.Switch.get_active (cast w)))
        | _ -> None)
  }
;;

let impl : Widget_impl.t =
  { name = "Switch"
  ; create =
      (fun (kind : Kind.t) ->
        match kind with
        | Switch { active } ->
          let s = W.Switch.new_ () in
          if active
          then (
            W.Switch.set_active s true;
            (* [active] is what the user asked for, [state] what the app has actually
               done about it. bonsai_gtk has no asynchronous confirmation step, so they
               are always equal; setting both keeps the switch from rendering its
               "pending" look. *)
            W.Switch.set_state s true);
          (s :> Widget.t)
        | k -> Widget_impl.wrong_kind "Switch" k)
  ; update =
      (fun w ~(old : Kind.t) (new_ : Kind.t) ->
        match old, new_ with
        | Switch _, Switch { active } ->
          let s : W.Switch.t = cast w in
          if not (Bool.equal (W.Switch.get_active s) active)
          then
            Widget_impl.batch w (fun () ->
              W.Switch.set_active s active;
              W.Switch.set_state s active)
        | _, k -> Widget_impl.wrong_kind "Switch" k)
  ; signals = [ toggled ]
  ; children = Widget_impl.No_children
  }
;;
```

- [ ] **Step 12: `src/widgets/registry.ml`** — three arms

```ocaml
  | Toggle_button _ -> W_toggle_button.impl
  | Check_button _ -> W_check_button.impl
  | Switch _ -> W_switch.impl
```

- [ ] **Step 13: `src/live_tree.ml`** — per-type props

```ocaml
     | "GtkToggleButton" ->
       [ [%sexp `label (W.Button.get_label (cast w) : string option)] ]
       @ flag_prop "active" (W.Toggle_button.get_active (cast w))
     | "GtkCheckButton" ->
       [ [%sexp `label (W.Check_button.get_label (cast w) : string option)] ]
       @ flag_prop "active" (W.Check_button.get_active (cast w))
       @ flag_prop "inconsistent" (W.Check_button.get_inconsistent (cast w))
     | "GtkSwitch" -> flag_prop "active" (W.Switch.get_active (cast w))
```
and extend the existing `"GtkButton"` arm with `@ (match W.Button.get_icon_name (cast w) with None -> [] | Some i -> [ Sexp.List [ Atom "icon"; Atom i ] ])` and `@ (if W.Button.get_has_frame (cast w) then [] else [ Sexp.Atom "frameless" ])`.

- [ ] **Step 14: `test_lib/bonsai_gtk_test.ml(i)` — the `Toggle` action**

```ocaml
module Action = struct
  type t =
    | Click of string
    | Toggle of string
  [@@deriving sexp_of]
end

let node_exn node id =
  match Node.find_by_test_id node id with
  | Some n -> n
  | None -> failwithf "Bonsai_gtk_test: no node with test_id %s" id ()
;;

(* The value a real toggle would take: whatever the node is *not* showing now. Reading it
   off the node rather than taking it as an argument is what makes the action mean "the
   user clicked this", which is the only thing a test can actually claim. *)
let current_active (node : Node.t) id =
  match node.kind with
  | Toggle_button { active; _ } | Check_button { active; _ } | Switch { active } -> active
  | k -> failwithf "Bonsai_gtk_test: %s (test_id %s) has no toggle state" (Kind.name k) id ()
;;

module Result_spec = struct
  type t = Node.t
  type incoming = Action.t

  let view node = Sexp.to_string_hum (Node.sexp_of_t node)

  let incoming node (action : Action.t) =
    match action with
    | Click id ->
      let n = node_exn node id in
      (match Attrs.find n.attrs On_clicked with
       | Some (On_clicked h) -> h ()
       | _ -> failwithf "Bonsai_gtk_test: node %s has no on_clicked handler" id ())
    | Toggle id ->
      let n = node_exn node id in
      (match Attrs.find n.attrs On_toggled with
       | Some (On_toggled h) -> h (not (current_active n id))
       | _ -> failwithf "Bonsai_gtk_test: node %s has no on_toggled handler" id ())
  ;;
end
```
The mli documents `Toggle`: "Fires the node's `on_toggled` with the negation of the `active` prop it currently renders — what clicking the real widget would produce. Fails if the node is not a toggle, or carries no handler."

- [ ] **Step 15: Run, read, promote, gate**

```
dune build @test/runtest && dune promote
BONSAI_GTK_LIVE_TESTS=1 xvfb-run -a dune build @test/live/runtest && dune promote
```
In `output_controls.txt`, read before promoting: `scheduled during patch: 0` (the claim), then `scheduled outside patch: 2`, and the second dump showing `active` on all three toggles. `output_patcher.txt` and `output_driver.txt` change here — the button's `(children (Single ()))` and the new `frameless`/`icon` props — so re-read those diffs too rather than promoting blind.
Then `./scripts/ci.sh`.

- [ ] **Step 16: Commit**

```bash
dune fmt 2>/dev/null; git add vtree src test test_lib
GIT_EDITOR=true git commit -F - <<'MSG'
ToggleButton, CheckButton, Switch; Button gains icon/child/frame

Signal specs now receive the widget, so a handler can carry the value GTK
just changed -- which is the only way to build one for the notify:: family,
whose generic marshaller carries no payload at all. An on_* attr on a widget
that declares no matching spec is now Invalid_argument at mount rather than
silently inert.

The toggles' [active] is controlled: written only when it differs from what
the widget shows, and the signals that write provokes are dropped by the
in_patch guard -- pinned by a live test, which is the end-to-end version of
the reentrancy case M0's backlog asked for.

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01Sg3Ci8U8kUKR8C3PL1pNSs
MSG
```

---

