open! Core

(* The values are written in hex because that is how X11's [keysymdef.h] writes them and
   how a reader checks one against it; [test/live/live_keyvals.ml] is what checks them
   against the binding this library actually runs on. *)

let escape = 0xff1b
let return = 0xff0d
let kp_enter = 0xff8d
let tab = 0xff09
let iso_left_tab = 0xfe20
let space = 0x020
let backspace = 0xff08
let delete = 0xffff
let up = 0xff52
let down = 0xff54
let left = 0xff51
let right = 0xff53
let home = 0xff50
let end_ = 0xff57
let page_up = 0xff55
let page_down = 0xff56
let slash = 0x02f

(* The punctuation the downstream chords need (Task 7): all printable ASCII, so each is
   its own codepoint ([of_char]'s contract) -- named anyway, because a chord table that
   reads [Keyval.comma] is checkable against keysymdef.h at a glance where [0x2c] is not.
   Pinned against the binding in [test/live/live_keyvals.ml] like the rest. *)
let comma = 0x02c
let question = 0x03f
let grave = 0x060
let bracketleft = 0x05b
let bracketright = 0x05d
let minus = 0x02d
let equal = 0x03d
let f1 = 0xffbe

(* F1..F12 are contiguous from [f1], which is what makes this a function rather than
   twelve values. It stops at 12 rather than continuing: X11 has keysyms up to F35, but
   they are not all contiguous with this run and a keyboard that reports them is rare
   enough that a guess would be a wrong answer nobody would test. *)
let f n =
  if n < 1 || n > 12 then invalid_argf "Keyval.f: %d is not in 1..12" n ();
  f1 + n - 1
;;

(* X11's keysyms for printable ASCII *are* the code points -- [XK_space] is 0x020,
   [XK_asciitilde] is 0x07e, and every letter, digit and punctuation mark in between is
   its own byte. Outside that range they are not: [XK_Return] is 0xff0d, not 0x00d, and
   [XK_BackSpace] is 0xff08, not 0x008. Returning [Char.to_int c] for those anyway would
   hand back a keyval GTK never delivers, which an application would then compare against
   forever without matching -- silently, since a keyval is just an int. So it raises. *)
let of_char c =
  let code = Char.to_int c in
  if code < 0x20 || code > 0x7e
  then
    invalid_argf
      "Keyval.of_char: %#x is not printable ASCII (0x20..0x7e), and its keysym is not \
       its code point"
      code
      ();
  code
;;
