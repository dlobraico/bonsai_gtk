open! Core

(** A keyed list diff: turns an [old] list into a [new_] list via a minimal sequence of
    ops, matching items by {!Key.t} where present and by positional same-kind matching
    otherwise (see {!diff}). *)

type 'a op =
  | Insert of
      { index : int
      ; item : 'a
      } (** Insert [item] so it ends up at [index]. *)
  | Move of
      { from : int
      ; to_ : int
      } (** Remove the element currently at [from] and re-insert it at [to_]. *)
  | Remove of { index : int } (** Delete the element at [index]. *)
  | Update of
      { index : int
      ; old : 'a
      ; item : 'a
      }
  (** Replace the element at [index] with [item]; [old] is what it used to be. Same
      identity as [old] (e.g. same key) — the patcher recurses into the existing native
      widget rather than recreating it. *)
[@@deriving sexp_of]

(** [diff ~key ~same_kind ~old ~new_] computes the ops that turn [old] into [new_] when
    applied in order (see {!apply}).

    Matching: an item with [key item = Some k] matches the old item with the same key, if
    any. An item with [key item = None] matches positionally against the old list's
    unkeyed items in order — the k-th unkeyed item in [new_] pairs with the k-th unkeyed
    item in [old] iff [same_kind] holds between them; otherwise it is unmatched.

    Every unmatched old item produces a [Remove]. Every unmatched new item produces an
    [Insert]. Every matched pair produces an optional [Move] (when its position changed)
    followed by an [Update].

    Op order: all [Remove]s first, in descending index order (so removing earlier ones
    doesn't invalidate later indices), followed by the [Move]/[Insert]/[Update] ops for
    [new_]'s items left to right.

    Raises [Invalid_argument] if [old] or [new_] contains a duplicate [Some] key. *)
val diff
  :  key:('a -> Key.t option)
  -> same_kind:('a -> 'a -> bool)
  -> old:'a list
  -> new_:'a list
  -> 'a op list

(** [apply ops list] applies [ops] left to right to [list], per each op's documented
    semantics. Reference semantics used by tests and by the patcher's index bookkeeping. *)
val apply : 'a op list -> 'a list -> 'a list
