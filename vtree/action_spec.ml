open! Core

(** One named action: what a menu item or a shortcut resolves to, and the one place in the
    menu system that carries handlers — which is why actions are an {i attr}
    ({!Attr.actions}) while a menu is a prop. The GTK object behind a spec is a
    [GSimpleAction] in a [GSimpleActionGroup] the runtime owns; see [src/actions.ml].

    [Toggle] and [Radio] are {b controlled} in spec §6.5's sense, told through an action:
    the [state] here is written to GTK (only when it differs from the read-back), and an
    activation never moves it — the handler's effect is scheduled, the model decides, and
    the next frame's write moves GTK. A declined toggle therefore never moves the menu's
    checkmark. GTK itself never changes the state either: the runtime connects no
    [change-state], so there is no second writer. *)
type kind =
  | Simple of unit Ui_effect.t
  | Toggle of
      { state : bool
      ; on_activate : unit Ui_effect.t
      }
  | Radio of
      { state : string
      ; on_activate : string -> unit Ui_effect.t
      }

type t =
  { name : string
  ; enabled : bool
  ; kind : kind
  }

(* Effects and handlers print as every handler in this library does; the states and the
   wiring stay visible, which is what a golden needs to say a toggle's checkmark did not
   move. *)
let sexp_of_kind = function
  | Simple _ -> Sexp.List [ Atom "Simple"; Atom "<effect>" ]
  | Toggle { state; on_activate = _ } ->
    Sexp.List [ Atom "Toggle"; [%sexp { state : bool }] ]
  | Radio { state; on_activate = _ } ->
    Sexp.List [ Atom "Radio"; [%sexp { state : string }] ]
;;

let sexp_of_t { name; enabled; kind } =
  Sexp.List
    ([ [%sexp `name (name : string)] ]
     @ (if enabled then [] else [ Sexp.List [ Atom "enabled"; Atom "false" ] ])
     @ [ sexp_of_kind kind ])
;;

(* States compare structurally and handlers physically, the event-attr rule: a view that
   rebuilds its closures every frame changes the handler every frame regardless, while a
   toggle whose [state] moved is a change [Actions.update] must see. *)
let equal_kind a b =
  match a, b with
  | Simple a, Simple b -> phys_equal a b
  | Toggle a, Toggle b ->
    Bool.equal a.state b.state && phys_equal a.on_activate b.on_activate
  | Radio a, Radio b ->
    String.equal a.state b.state && phys_equal a.on_activate b.on_activate
  | (Simple _ | Toggle _ | Radio _), _ -> false
;;

let equal a b =
  String.equal a.name b.name && Bool.equal a.enabled b.enabled && equal_kind a.kind b.kind
;;

(* GLib's [g_action_name_is_valid] class: non-empty, ASCII alphanumerics plus '.' and '-'.
   Anything outside it is rejected here because the resolution walk compares declared and
   referenced strings for equality -- a malformed pair *resolves* -- and the first GTK
   call to see the reference, [g_menu_item_set_detailed_action], responds to a parse
   failure with [g_error]: a process abort (probed under xvfb; a space in the name dies
   with "Detailed action name 'app.my act' has invalid format", SIGABRT). A name with
   valid GVariant text in parentheses would instead parse as a *targeted* activation of a
   different action, and an empty name builds an item no group can ever serve. None of the
   three becomes valid in a later frame, so by node.mli's rejection rule all three belong
   here. *)
let validate_name name =
  let valid_char c = Char.is_alphanum c || Char.equal c '.' || Char.equal c '-' in
  if String.is_empty name || not (String.for_all name ~f:valid_char)
  then
    invalid_argf
      "Action_spec: name %S must be non-empty and contain only [A-Za-z0-9.-] (GTK's \
       action-name charset -- anything else aborts in GLib's detailed-action parser)"
      name
      ()
;;

let simple ?(enabled = true) ~name eff =
  validate_name name;
  { name; enabled; kind = Simple eff }
;;

let toggle ?(enabled = true) ~name ~state on_activate =
  validate_name name;
  { name; enabled; kind = Toggle { state; on_activate } }
;;

let radio ?(enabled = true) ~name ~state on_activate =
  validate_name name;
  { name; enabled; kind = Radio { state; on_activate } }
;;
