open! Core

(** The shape of a node's children, fixed by its {!Kind.t} (spec §5.3).

    [Slots] is for containers whose children are addressed by role rather than by
    position: a [center_box]'s [start]/[center]/[end], a [paned]'s two halves, an
    [overlay]'s main child and its overlays. Each slot carries its own shape, so a slot is
    itself a [Single] or a [List] and is patched by the same code.

    The patcher requires a node's shape and its impl's [child_ops] to agree, including the
    slot {i names} and their order; a mismatch is [Invalid_argument] rather than a
    silently dropped child, because both sides are written in this repository and a
    mismatch is always a bug in one of them. *)
type 'a t =
  | No_children
  | Single of 'a option
  | List of 'a list
  | Slots of (string * 'a t) list
[@@deriving sexp_of]

(** Every child, in order, descending through slots. *)
val iter : 'a t -> f:('a -> unit) -> unit

(** First child for which [f] returns [Some], in the same order as {!iter}. *)
val find_map : 'a t -> f:('a -> 'b option) -> 'b option
