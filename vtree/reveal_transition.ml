open! Core

(** How a [revealer] animates its child in and out. The direction names GTK's own: a
    [Slide_right] transition slides the child in {i from the left}.

    Unlike {!Ellipsize}, this has a [None_] constructor: "no transition" is a real,
    selectable GTK value here rather than the absence of a property, and the trailing
    underscore keeps it from shadowing [Option.None] in every match. *)
type t =
  | None_
  | Crossfade
  | Slide_right
  | Slide_left
  | Slide_up
  | Slide_down
  | Swing_right
  | Swing_left
  | Swing_up
  | Swing_down
[@@deriving sexp_of, equal, compare]
