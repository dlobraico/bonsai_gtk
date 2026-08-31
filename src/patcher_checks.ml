open! Core
open Bonsai_gtk_vtree

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
   (* The one place a popover is legal in M3, and [Bonsai_gtk_test] refuses the same trees
      with the same strings -- copied there, goldens hold them together, the window rule's
      arrangement. A [Menu_button] parent implies the ~popover slot: the button has no
      other child position. *)
   | Popover _ ->
     (match parent_kind with
      | Some (Menu_button _) -> ()
      | Some k ->
        invalid_argf
          "%s: a Node.popover may only be a Node.menu_button's ~popover slot, not a \
           child of %s"
          path
          (Kind.name k)
          ()
      | None ->
        invalid_argf
          "%s: a Node.popover may only be a Node.menu_button's ~popover slot, not the \
           root"
          path
          ())
   | _ -> ());
  (* [Placement] rather than a table here: it is pure [Kind.t]/[Attr.Name.t] data, and
     [Bonsai_gtk_test] -- which cannot link ocgtk, so cannot see this file -- runs the
     same check over the same table at handle time. Both raise the string [rejection]
     builds, so the two messages are identical by construction rather than by inspection. *)
  Option.iter (Placement.rejection ~path ~parent:parent_kind node.attrs) ~f:invalid_arg
;;

(* Spec §11 says mount *and* patch time. [Reconcile.diff] checks this on the patch path,
   but a first frame never reaches it -- so without this a duplicate key is accepted once
   and rejected on the second frame, which for a [Node.stack] means GTK has already been
   handed two pages with one name and [get_child_by_name] is already ambiguous. *)
let check_unique_keys ~path (cs : Node.t list) =
  child_op ~path (fun () ->
    Reconcile.check_unique_keys ~key:(fun (n : Node.t) -> n.key) cs)
;;
