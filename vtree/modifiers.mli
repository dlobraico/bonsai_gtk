open! Core

(** Which modifier keys were down.

    A record of bools rather than a set or a mask, because [vtree] cannot name GDK's
    [modifiertype] (which is a list of polymorphic variants) and because the question an
    application asks is always "was control down", never "give me the mask". The runtime
    converts at the boundary ([Gtk_import.modifiers_of_gdk]).

    Lock (caps lock) and the five button masks GDK also reports are deliberately absent:
    they are pointer and keyboard {i state}, not modifiers a shortcut is keyed on, and
    including them would put a bit in every comparison that nothing wants to compare. If
    one is ever needed it goes here with a note, not into an escape hatch. *)
type t =
  { shift : bool
  ; control : bool
  ; alt : bool
  ; super : bool
  ; hyper : bool
  ; meta : bool
  }
[@@deriving sexp_of, equal, compare]

(** No modifier down. What a synthetic event in a headless test usually wants, and what a
    real click with nothing held down produces. *)
val none : t
