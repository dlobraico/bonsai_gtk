open! Core

(** How a {!Node.text_view} breaks lines that are wider than it is.

    GTK's own [GtkWrapMode], which only the text view reads. [None_] rather than [None]: a
    constructor called [None] would shadow [Option.None] in every match in the file that
    handles it, which is the same reason {!Bonsai_gtk_vtree.Selection_mode},
    {!Bonsai_gtk_vtree.Reveal_transition} and {!Bonsai_gtk_vtree.Stack_transition} spell
    theirs that way.

    [None_] is GTK's own default and is what a {i code} field wants: no wrapping at all,
    so a long line runs off to the right and the view scrolls horizontally to follow it.
    [Word_char] is what a {i notes} field usually wants -- break at word boundaries, and
    break inside a word that does not fit on a line by itself. [Word] is the same without
    that second half, so a single word longer than the view is clipped rather than split;
    [Char] breaks anywhere and reads badly in prose. *)
type t =
  | None_
  | Char
  | Word
  | Word_char
[@@deriving sexp_of, equal, compare]
