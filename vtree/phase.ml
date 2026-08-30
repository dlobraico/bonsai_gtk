open! Core

(** Where in GTK's event routing a controller runs.

    [Capture] runs top-down, from the toplevel toward the target, and is what a
    window-wide Escape handler wants: it sees the key before anything a child added later
    can swallow it (stavekeeper's [dialog.ml] says exactly this, in a comment, having
    learned it the hard way). [Bubble] -- GTK's default -- runs bottom-up from the target,
    so the innermost widget gets first refusal, which is what a per-widget shortcut wants.
    [Target] runs only when the widget {i is} the event's target.

    GTK's [`NONE] is deliberately absent: a controller in that phase never fires, which is
    what omitting the attribute already says, more clearly. *)
type t =
  | Capture
  | Bubble
  | Target
[@@deriving sexp_of, equal, compare]
