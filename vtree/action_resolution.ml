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
    Some (scope, List.map specs ~f:(fun (s : Action_spec.t) -> s.name))
  | Some _ | None -> None
;;

(* The references this node's own props make. Today that is a menu button's menu; Task 7's
   [Attr.shortcut] joins here, which is why the walk asks a function rather than matching
   inline. *)
let node_references (node : Node.t) =
  match node.kind with
  | Menu_button { menu = Some menu; _ } -> Menu.action_references menu
  | _ -> []
;;

let check ~path (root : Node.t) =
  let rec go ~path ~(env : (string * string list) list) (node : Node.t) =
    let env =
      match node_actions node with
      | Some (scope, names) -> (scope, names) :: env
      | None -> env
    in
    List.iter (node_references node) ~f:(fun reference ->
      let resolved =
        match scope_of reference with
        | None -> false
        | Some (scope, name) ->
          List.exists env ~f:(fun (s, names) ->
            String.equal s scope && List.mem names name ~equal:String.equal)
      in
      if not resolved
      then (
        let in_reach =
          match List.map env ~f:fst with
          | [] -> "none"
          | scopes ->
            String.concat ~sep:", " (List.dedup_and_sort ~compare:String.compare scopes)
        in
        invalid_argf
          "%s: menu item action %S resolves to no Attr.actions here or on an ancestor \
           (scopes in reach: %s)"
          path
          reference
          in_reach
          ()));
    Children.iteri node.children ~path ~f:(fun path child -> go ~path ~env child)
  in
  go ~path ~env:[] root
;;
