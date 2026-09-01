open! Core

(* Every action reference in the tree resolves, checked from pure vtree data so that the
   patcher (at mount and at patch, from the pass wrappers -- the whole tree is in hand as
   data before anything is built) and [Bonsai_gtk_test] (per frame) run the {i same}
   function and raise the {i same} string. That is the M2 sharing rule, and it is what
   closes the certify-then-grey-out gap: GTK resolves a popover's action names against the
   groups inserted on the menu button and its ancestors, so a check any looser would
   certify menus GTK will render insensitive.

   The environment is threaded down the walk: each node's [Attr.actions] extends it for
   the node itself and its subtree -- self-or-ancestor, exactly GTK's path. A sibling's
   scope is deliberately out of reach. The env is a {i union}, same-scope entries
   included, and that matches GTK (measured, [test/live/live_menus.ml]'s shadowing block):
   a nearer group registered under the same scope does {i not} shadow an ancestor's -- the
   muxer falls through, so a name the nearer "app" lacks still resolves against the
   ancestor's "app", exactly as this walk says.

   The carve-out ruling (§5.4's singular arity, the stack-switcher precedent): a menu is a
   claim about actions the caller can see, so a dangling name is a typo and raises --
   never a state to pass through. If a real model ever needs a menu naming actions that do
   not exist yet, that is a controller question, not a wider default. *)

let scope_of reference =
  match String.index reference '.' with
  | None -> None
  | Some i -> Some (String.prefix reference i, String.drop_prefix reference (i + 1))
;;

let node_actions (node : Node.t) =
  match (Attrs.find node.attrs Actions :> Attr.Private.t option) with
  | Some (Actions { scope; specs }) ->
    Some
      ( scope
      , List.map specs ~f:(fun (s : Action_spec.t) ->
          ( s.name
          , match s.kind with
            | Radio _ -> `Radio
            | Simple _ | Toggle _ -> `Plain )) )
  | Some _ | None -> None
;;

(* The references this node's own props and attrs make: a menu button's menu items, and
   the node's shortcuts -- one function, so the walk (and its message) covers both. A
   shortcut reference carries no "::" (the constructor rejects it), so nothing needs
   stripping on that side. *)
let node_references (node : Node.t) =
  let from_menu =
    match node.kind with
    | Menu_button { menu = Some menu; _ } ->
      List.map (Menu.action_references menu) ~f:(fun r -> r, `Menu)
    | _ -> []
  in
  let from_shortcuts =
    match (Attrs.find node.attrs Shortcut :> Attr.Private.t option) with
    | Some (Shortcut shortcuts) ->
      List.map shortcuts ~f:(fun (s : Attr.shortcut) -> s.action, `Shortcut)
    | Some _ | None -> []
  in
  from_menu @ from_shortcuts
;;

let check ~path (root : Node.t) =
  let rec go
    ~path
    ~(env : (string * (string * [ `Plain | `Radio ]) list) list)
    (node : Node.t)
    =
    let env =
      match node_actions node with
      | Some (scope, names) -> (scope, names) :: env
      | None -> env
    in
    List.iter (node_references node) ~f:(fun (reference, source) ->
      let resolved =
        match scope_of reference with
        | None -> None
        | Some (scope, name) ->
          (* Every entry of the scope, nearest first, union semantics -- the muxer falls
             through on a same-scope miss (measured; see the header). The nearest holder
             of the {i name} decides its kind. *)
          List.find_map env ~f:(fun (s, names) ->
            if String.equal s scope
            then List.Assoc.find names name ~equal:String.equal
            else None)
      in
      match resolved, source with
      | None, (`Menu | `Shortcut) ->
        let in_reach =
          match List.map env ~f:fst with
          | [] -> "none"
          | scopes ->
            String.concat ~sep:", " (List.dedup_and_sort ~compare:String.compare scopes)
        in
        (* One noun and one string for both callers and both sources: a menu item and a
           shortcut make the same kind of claim. *)
        invalid_argf
          "%s: action reference %S resolves to no Attr.actions here or on an ancestor \
           (scopes in reach: %s)"
          path
          reference
          in_reach
          ()
      | Some `Radio, `Shortcut ->
        (* Feasible but unshipped: [Shortcut.set_arguments] is bound, so a targeted
           shortcut could carry the radio's parameter -- M3 scopes it out (see
           docs/m3-backlog.md, "Do first in M4"). Until then a shortcut activates through
           a parameterless [GtkNamedAction], which GTK refuses against a parameterised
           action -- silently, which is why this raises instead. *)
        invalid_argf
          "%s: shortcut action %S names a radio action; targeted shortcuts are not \
           shipped in M3 (wrap the choice in a Simple action, or see the backlog entry \
           on Shortcut.set_arguments)"
          path
          reference
          ()
      | Some (`Radio | `Plain), `Menu | Some `Plain, `Shortcut -> ());
    Children.iteri node.children ~path ~f:(fun path child -> go ~path ~env child)
  in
  go ~path ~env:[] root
;;
