open! Core

(** What {!Attr.on_key_pressed}'s handler answers GTK, and what it asks Bonsai to do about
    it.

    A key press is the one event in this library that is a {i question}. Everything else
    has already happened by the time a handler sees it; a key press has not been routed
    yet, and GTK is asking "did anything handle this?" on its own stack, synchronously,
    before any frame could run. So the answer cannot be an effect -- an effect is
    scheduled and performed later -- and it cannot be only an effect either, because
    consuming Escape and closing the dialog are two different things that have to happen
    together.

    Four constructors rather than two, because all four combinations are wanted and each
    reads plainly at the call site:

    {v
                        | schedules nothing | schedules an effect
    --------------------+-------------------+---------------------
    GTK keeps routing   | Propagate         | Propagate_and eff
    GTK stops           | Handled           | Handled_and eff
    v}

    [Propagate_and] is the one a reader will ask about: it is for observing a key without
    consuming it -- a "last activity" timestamp, a type-to-search that forwards to a
    search entry, an auto-repeat suppressor watching key {i releases}. Without it, an
    observer would have to lie about handling the key, and the keystroke would stop
    reaching whatever was supposed to receive it.

    {!Attr.on_key_released} does not use this type: GTK's [key-released] callback returns
    [unit], so there is no question to answer and its handler is an ordinary {!Handler.t}. *)
type t =
  | Propagate
  | Handled
  | Propagate_and of unit Ui_effect.t
  | Handled_and of unit Ui_effect.t

(** Whether GTK should stop routing the key. This is the whole of what reaches C. *)
let handled = function
  | Propagate | Propagate_and _ -> false
  | Handled | Handled_and _ -> true
;;

(** The effect to schedule, if any. *)
let effect = function
  | Propagate | Handled -> None
  | Propagate_and e | Handled_and e -> Some e
;;

(** What {!Attr.on_key_pressed} carries: a pure function from the event to the answer.

    Named rather than written inline in [Attr] so that it can have a [sexp_of], which a
    function type has no derivable one of -- exactly why {!Handler.t} exists, and this is
    its counterpart for the one handler in the library that returns a value instead of an
    effect. *)
type handler = Key_event.t -> t

let sexp_of_handler _ = Sexp.Atom "<handler>"

(* [sexp_of_t] prints the effect as [<effect>], like every other handler in this library:
   an effect is not inspectable and a test comparing two of them is comparing closures.
   Hand-written rather than derived for exactly that reason -- there is no
   [Ui_effect.sexp_of_t] to derive from, and inventing one would be inventing an ordering
   on closures. *)
let sexp_of_t = function
  | Propagate -> Sexp.Atom "Propagate"
  | Handled -> Sexp.Atom "Handled"
  | Propagate_and _ -> Sexp.List [ Atom "Propagate_and"; Atom "<effect>" ]
  | Handled_and _ -> Sexp.List [ Atom "Handled_and"; Atom "<effect>" ]
;;
