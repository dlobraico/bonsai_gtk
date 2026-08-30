open! Core

(** A click a [GtkGestureClick] reported.

    [button] is the mouse button that was pressed -- 1 for the primary, 2 for the middle,
    3 for the secondary -- and is the button that actually fired, not the one
    {!Attr.on_click} was constructed with (with [~button:0], the default, any of them
    fires). [n_press] is 1 for a single click, 2 for the second click of a double, and so
    on; GTK emits the gesture once per press, so a double click arrives as two events, the
    second with [n_press = 2].

    [x] and [y] are in the {i widget's own} coordinates -- a gesture attached to a card
    reports where in that card the click landed, whatever the card's position on screen.
    That is what makes a per-card gesture useful rather than a window-wide one that has to
    hit-test for itself (stavekeeper's [library_window.ml:155-159] explains exactly this,
    which is why it attaches per card rather than to the FlowBox).

    [modifiers] is read off the controller while the event is still current; see
    {!Modifiers}. *)
type t =
  { button : int
  ; n_press : int
  ; x : float
  ; y : float
  ; modifiers : Modifiers.t
  }
[@@deriving sexp_of, equal]
