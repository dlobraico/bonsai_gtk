open! Core

(** A keyed list diff: turns an [old] list into a [new_] list via a sequence of ops,
    matching items by {!Key.t} where present and by positional same-kind matching
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
    followed by an [Update]; every emitted [Move] has [from > to_], since positions below
    the one currently being placed are already finalized and never revisited.

    Op order: all [Remove]s first, in descending index order (so removing earlier ones
    doesn't invalidate later indices), followed by the [Move]/[Insert]/[Update] ops for
    [new_]'s items left to right.

    [ordered] is [false] for a container GTK gives no reorder primitive for — an overlay,
    a stack, a grid. Matching is unaffected (identity is by key either way, and state
    still survives a reorder); what changes is that no [Move] is emitted, because the
    patcher would have nothing to apply it with. Emitting one and discarding it is worse
    than not emitting it: the discarded op is still counted in the patcher's index
    bookkeeping, and it shows up in a test's [op list] as though something happened.

    What that costs, and it is the whole cost: the result of applying the ops is [new_]'s
    items in {i some} order rather than in [new_]'s order, so [apply ops old = new_] no
    longer holds — only the set does. Each [Update] is therefore indexed by where its item
    already is rather than by where [new_] would put it, which is what keeps every op's
    index describing the list the caller really holds. The ops still come out in [new_]'s
    order; only their indices are the un-reordered list's.

    Raises [Invalid_argument] if [old] or [new_] contains a duplicate [Some] key
    ({!check_unique_keys}).

    The trailing [unit] is what makes [?ordered] erasable: every other argument is
    labelled, so without it OCaml cannot tell a partial application from a defaulted one
    (warning 16). *)
val diff
  :  ?ordered:bool (** default [true] *)
  -> key:('a -> Key.t option)
  -> same_kind:('a -> 'a -> bool)
  -> old:'a list
  -> new_:'a list
  -> unit
  -> 'a op list

(** [apply ops list] applies [ops] left to right to [list], per each op's documented
    semantics. Reference semantics used by tests and by the patcher's index bookkeeping.
    [apply] does not validate [Update.old] against the element actually at [index] — it
    unconditionally overwrites by position, so a caller that needs the identity guarantee
    (that the element at [index] really is [old]) must check that itself. *)
val apply : 'a op list -> 'a list -> 'a list

(** Raises [Invalid_argument] if two items share a [Some] key. {!diff} calls it on both of
    its lists; it is public so that a caller which builds a child list without diffing it
    against anything — mounting one for the first time — rejects the same tree at the same
    point rather than a frame later. The message names the key and nothing else: the
    caller is expected to prefix the container's node path (spec §11). *)
val check_unique_keys : key:('a -> Key.t option) -> 'a list -> unit
