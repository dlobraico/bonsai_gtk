open! Core

(** What {!Attr.on_click}'s handler tells the gesture to do with the event sequence, and
    what it asks Bonsai to do about the click.

    The click twin of {!Key_response}, for the same reason in a different tense: a key
    press is a question GTK asks before routing, while a click has already been routed
    when the handler runs — but the {i sequence} it belongs to is still live, and
    [Gesture.set_state] can claim it so that no other gesture sees the rest of it. [Claim]
    does exactly that ([GTK_EVENT_SEQUENCE_CLAIMED]): the click is consumed, and a handler
    on a card can take a press without its list box's click-to-select firing — the M2
    limitation this type closes. The decision is synchronous ([Gesture.set_state] runs on
    the C stack, inside the [pressed] trampoline); the effect is scheduled like any other.

    [Continue] is M2's behaviour and what a missing handler produces: the gesture claims
    nothing, so the click also reaches whatever else would have handled it — a button's
    own gesture, a list box's selection. The four constructors are {!Key_response}'s table
    with the verbs renamed:

    {v
                        | schedules nothing | schedules an effect
    --------------------+-------------------+---------------------
    others still see it | Continue          | Continue_and eff
    sequence claimed    | Claim             | Claim_and eff
    v} *)
type t =
  | Continue
  | Claim
  | Continue_and of unit Ui_effect.t
  | Claim_and of unit Ui_effect.t

(** Whether the gesture should claim the event sequence. This is the whole of what reaches
    GTK. *)
let claim = function
  | Continue | Continue_and _ -> false
  | Claim | Claim_and _ -> true
;;

(** The effect to schedule, if any. *)
let effect = function
  | Continue | Claim -> None
  | Continue_and e | Claim_and e -> Some e
;;

(** What {!Attr.on_click} carries: a pure function from the event to the answer. Named for
    the reason {!Key_response.handler} is — a function type has no derivable [sexp_of]. *)
type handler = Click_event.t -> t

let sexp_of_handler _ = Sexp.Atom "<handler>"

(* Hand-written for the reason [Key_response]'s is: an effect is not inspectable, so it
   prints as [<effect>] like every handler in this library. *)
let sexp_of_t = function
  | Continue -> Sexp.Atom "Continue"
  | Claim -> Sexp.Atom "Claim"
  | Continue_and _ -> Sexp.List [ Atom "Continue_and"; Atom "<effect>" ]
  | Claim_and _ -> Sexp.List [ Atom "Claim_and"; Atom "<effect>" ]
;;
