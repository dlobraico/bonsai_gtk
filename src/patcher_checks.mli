open! Core
open Bonsai_gtk_vtree

(** The patcher's structural checks and its path-prefix helpers, split out of
    [patcher.ml]'s walk. Internal to the library: {!Patcher} is the public interface, and
    everything here is documented on the entry point that reaches it
    ({!Patcher.mount}/{!Patcher.patch}). *)

(** [child_path path i] is the path of the [i]'th child of the node at [path], spelled the
    one way every error message in the walk spells it. *)
val child_path : string -> int -> string

(** Runs [f], prefixing [path] onto any [Invalid_argument] it raises. For container child
    ops, which know nothing about where in the tree they are (spec §11); only the op call
    is wrapped, never the recursive [mount]/[patch] beside it, so a nested container's
    message is prefixed once. *)
val child_op : path:string -> (unit -> 'a) -> 'a

(** Rejects a {!Bonsai_gtk_vtree.Kind.Window} anywhere but the root, and a
    container-placement attr on a child whose parent does not read it -- see
    {!Bonsai_gtk_vtree.Placement}, which holds the table and the message. Runs on every
    node of every mount and patch pass. *)
val check_placement
  :  path:string
  -> is_root:bool
  -> parent_kind:Kind.t option
  -> Node.t
  -> unit

(** Rejects a duplicate key among [cs], with [path] prefixed. The mount-time half of the
    keyed-children rule: [Reconcile.diff] makes the same check on the patch path, but a
    first frame never reaches it. *)
val check_unique_keys : path:string -> Node.t list -> unit
