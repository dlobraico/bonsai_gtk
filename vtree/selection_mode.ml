open! Core

(** How many rows or children may be selected at once.

    [None_] rather than [None]: a constructor called [None] would shadow [Option.None] in
    every match in the file that handles it, which is the same reason
    {!Bonsai_gtk_vtree.Reveal_transition} and {!Bonsai_gtk_vtree.Stack_transition} spell
    theirs [None_].

    [Single] is GTK's own default -- at most one row selected, and clicking the selected
    one deselects it. [Browse] is [Single] with "exactly one" instead of "at most one":
    GTK keeps a row selected at all times and will not let the user deselect. A model that
    renders [~selected:[]] to a [Browse] list box is asking for something GTK does not do;
    see {!Bonsai_gtk_vtree.Node.list_box}, which documents what happens then.

    [None_] is a list nothing can be selected in, which is the right mode for a menu of
    rows that are only ever activated. *)
type t =
  | None_
  | Single
  | Browse
  | Multiple
[@@deriving sexp_of, equal, compare]
