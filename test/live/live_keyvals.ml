open! Core
open Bonsai_gtk_vtree
module K = Ocgtk_gdk.Gdk_constants

(* [vtree/keyval.ml] hard-codes X11 keysyms because [vtree] cannot link ocgtk. This is
   what makes that safe: every constant, checked against the binding. A mismatch here is
   not a test failure to promote past -- it means an application matching on
   [Keyval.escape] would silently never match.

   Every [val] in [keyval.mli] is checked. Counting the [check] lines below against that
   file is the review instruction, and it is the only thing that makes "the table is
   pinned" true rather than "most of the table is pinned". *)
let check name ours theirs =
  if ours <> theirs then printf "MISMATCH %s: vtree=%#x gdk=%#x\n" name ours theirs
;;

let () =
  check "escape" Keyval.escape K.key_escape;
  check "return" Keyval.return K.key_return;
  check "kp_enter" Keyval.kp_enter K.key_kp_enter;
  check "tab" Keyval.tab K.key_tab;
  check "iso_left_tab" Keyval.iso_left_tab K.key_iso_left_tab;
  check "space" Keyval.space K.key_space;
  check "backspace" Keyval.backspace K.key_backspace;
  check "delete" Keyval.delete K.key_delete;
  check "up" Keyval.up K.key_up;
  check "down" Keyval.down K.key_down;
  check "left" Keyval.left K.key_left;
  check "right" Keyval.right K.key_right;
  check "home" Keyval.home K.key_home;
  check "end" Keyval.end_ K.key_end;
  check "page_up" Keyval.page_up K.key_page_up;
  check "page_down" Keyval.page_down K.key_page_down;
  check "slash" Keyval.slash K.key_slash;
  (* [f] is a function, so the ends of its range are what there is to pin; every value
     between them is [key_f1 + n - 1] by construction and GDK's own table is contiguous
     across it (65470..65481). *)
  check "f1" (Keyval.f 1) K.key_f1;
  check "f12" (Keyval.f 12) K.key_f12;
  (* [of_char] is the claim that an ASCII printable's keysym is its codepoint, which is
     what makes [Keyval.of_char 'w'] a legitimate way to spell Ctrl+W. Check both ends of
     the letter range, a digit, a punctuation mark and the [w] the claim is usually made
     about, rather than asserting it in a comment.

     There is no [K.key_A]: ocgtk's generator lowercases every constant name, so X11's
     [XK_A] (65) and [XK_a] (97) both become [key_a] and the second shadows the first --
     [gdk_constants.mli] genuinely declares [val key_a] twice. So the capitals cannot be
     checked against the binding at all, and [of_char]'s doc says so. What is checked is
     that the lowercase letters, the digits and the punctuation agree, which is the same
     claim over the range an application actually writes.

     One caveat on the letters, because a failure here is easy to misread: [K.key_a],
     [K.key_z] and [K.key_w] are the *second* of the two declarations, and which one wins
     is the order ocgtk's generator happened to emit them in. So a MISMATCH on a letter
     means the generator reordered its output, not that {!Keyval}'s arithmetic is wrong --
     [of_char 'a' = 97] would still be right. [key_0], [key_slash] and [key_space] have no
     duplicate and are unambiguous; a MISMATCH on one of those is the table. *)
  check "of_char a" (Keyval.of_char 'a') K.key_a;
  check "of_char z" (Keyval.of_char 'z') K.key_z;
  check "of_char 0" (Keyval.of_char '0') K.key_0;
  check "of_char w" (Keyval.of_char 'w') K.key_w;
  check "of_char /" (Keyval.of_char '/') K.key_slash;
  check "of_char space" (Keyval.of_char ' ') K.key_space;
  printf "keyvals agree\n"
;;

(* The range check is the other half of [of_char]'s contract: outside [0x20]-[0x7e] the
   keysym is *not* the code point, and returning one anyway would be a wrong answer that
   an application would then compare against a key GTK never delivers. *)
let () =
  List.iter [ '\n'; '\t'; '\000'; '\255' ] ~f:(fun c ->
    match Keyval.of_char c with
    | exception Invalid_argument _ -> ()
    | v -> printf "NOT REJECTED %#x -> %#x\n" (Char.to_int c) v);
  (match Keyval.f 0 with
   | exception Invalid_argument _ -> ()
   | v -> printf "NOT REJECTED f 0 -> %#x\n" v);
  (match Keyval.f 13 with
   | exception Invalid_argument _ -> ()
   | v -> printf "NOT REJECTED f 13 -> %#x\n" v);
  printf "out-of-range rejected\n"
;;
