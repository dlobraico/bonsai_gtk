open! Core

(** A key press or release a [GtkEventControllerKey] reported.

    [keyval] is the X11 keysym -- the {i logical} key, after the keyboard layout and the
    shift state have been applied, so the A key with shift held arrives as [0x41] and
    without it as [0x61]. It is what an application branches on; {!Keyval} names the ones
    worth naming and {!Keyval.of_char} covers printable ASCII.

    [keycode] is the hardware scan code of the physical key, before any layout. It is here
    because GTK carries it and because a game or a keyboard remapper needs it; a shortcut
    does not, and an application that reaches for it on a keyboard-layout question is
    almost certainly asking the wrong one.

    [modifiers] arrives as the [~state] argument of the controller's own callback -- it is
    not fetched off anything, so unlike {!Click_event}'s it does not depend on the event
    still being current and a [Key_event.t] can be stored past the handler; see
    {!Modifiers}. Note that it is the state {i before} this key was pressed, which is
    GDK's convention and is what makes [Ctrl] held plus [w] pressed arrive as
    [{ control = true }] with [keyval = Keyval.of_char 'w'] rather than as two events
    neither of which is the shortcut. *)
type t =
  { keyval : int
  ; keycode : int
  ; modifiers : Modifiers.t
  }
[@@deriving sexp_of, equal]
