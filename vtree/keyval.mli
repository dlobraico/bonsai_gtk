open! Core

(** X11 keysyms, as the plain [int]s GTK delivers.

    Hard-coded rather than re-exported from GDK because this library's whole vtree/runtime
    split exists so that an application's view functions can be written against
    [bonsai_gtk.vtree] alone, with no ocgtk dependency and therefore headless-testable —
    and a view that handles Escape has to be able to name Escape. The values are X11
    keysyms and have not changed since 1987; [test/live/live_keyvals.ml] checks every one
    of them against [Ocgtk_gdk.Gdk_constants] on every CI run, which is what turns "has
    not changed" into "is checked".

    Only the keys an application actually branches on are here. A keyval this module does
    not name is still an ordinary [int] and can be compared to one — {!of_char} covers the
    printable ASCII range, and the rest are in GDK's headers. *)

val escape : int
val return : int

(** The numeric keypad's Enter, which is a {i different} keysym from {!return} — a dialog
    that accepts on Enter has to match both. *)
val kp_enter : int

val tab : int

(** Shift+Tab, which GTK delivers as its own keysym rather than as {!tab} with a shift
    modifier. A backwards-navigation handler that matches only [tab] never fires. *)
val iso_left_tab : int

val space : int
val backspace : int
val delete : int
val up : int
val down : int
val left : int
val right : int
val home : int

(** Trailing underscore because [end] is an OCaml keyword. *)
val end_ : int

val page_up : int
val page_down : int
val slash : int

(** The punctuation the downstream chord tables need — all printable ASCII, each its own
    codepoint, named so a chord table reads as prose. The table stays curated: anything
    else printable is {!of_char}, and the rest of X11 is a raw [int]
    ([docs/m2-backlog.md:114-115]'s rule, kept). *)
val comma : int

val question : int
val grave : int
val bracketleft : int
val bracketright : int
val minus : int
val equal : int

(** [f n] is the keysym of function key [n], for [n] in [1] .. [12]. Raises
    [Invalid_argument] outside that range: F13 and beyond exist in X11 but are not
    contiguous with the rest on every keyboard, and returning a guess would be worse than
    saying no. *)
val f : int -> int

(** The keysym of a printable ASCII character, which for [0x20]–[0x7e] is its own code
    point — so [of_char 'w'] is Ctrl+W's keyval and [of_char '/'] is the "start a search"
    key. Raises [Invalid_argument] outside that range: a keysym for [\n] or [\255] is not
    the codepoint and quietly returning one would be a wrong answer rather than an error.

    A capital is its own keysym ([of_char 'A'] is 65, [of_char 'a'] is 97), which is what
    GTK delivers for Shift+A — so a handler that wants "the A key" whatever the shift
    state has to match both, or ask {!Key_event.modifiers}. The capitals are the one part
    of this module [test/live/live_keyvals.ml] cannot check against the binding: ocgtk's
    generator lowercases constant names, so X11's [XK_A] and [XK_a] both arrive as
    [Gdk_constants.key_a] and only the second survives. The lowercase letters, the digits
    and the punctuation are checked, and they are the same claim over the same range. *)
val of_char : char -> int
