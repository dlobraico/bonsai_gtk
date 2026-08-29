open! Core

(** When a scrolled window shows a scrollbar. [External_] means "never show one, but do
    not let the content dictate the size either" -- for sharing a scrollbar between views,
    and for clipping a child to whatever space it is given.

    [External_] carries a trailing underscore for the same reason
    {!Reveal_transition.None_} does: it reads as a keyword otherwise. *)
type t =
  | Always
  | Automatic
  | Never
  | External_
[@@deriving sexp_of, equal, compare]
