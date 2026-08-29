open! Core

(** How a [stack] animates between pages. The direction names GTK's own: a [Slide_right]
    transition slides the new page in {i from the left}.

    GTK's [OVER_UP_DOWN], [OVER_DOWN_UP], [OVER_LEFT_RIGHT], [OVER_RIGHT_LEFT] and
    [ROTATE_LEFT_RIGHT] are deliberately absent: each picks its direction from the
    {i child order}, and a stack's child order is explicitly not meaningful (see
    {!Node.stack}), so offering them would promise something the widget does not deliver.

    [None_] rather than [None] for the reason {!Reveal_transition} has one: "no
    transition" is a real GTK value here rather than the absence of a property, and the
    trailing underscore keeps it from shadowing [Option.None] in every match. *)
type t =
  | None_
  | Crossfade
  | Slide_right
  | Slide_left
  | Slide_up
  | Slide_down
  | Slide_left_right
  | Slide_up_down
  | Over_up
  | Over_down
  | Over_left
  | Over_right
  | Under_up
  | Under_down
  | Under_left
  | Under_right
  | Rotate_left
  | Rotate_right
[@@deriving sexp_of, equal, compare]
