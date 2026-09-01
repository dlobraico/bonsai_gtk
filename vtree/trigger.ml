open! Core

(** What fires a {!Attr.shortcut}: a keyval plus a modifier set, as plain vtree data.

    {b No GTK parse syntax enters the vtree}, deliberately: the runtime builds the GTK
    trigger with [Keyval_trigger.new_] from these two fields, and
    [Shortcut_trigger.parse_string] — whose non-option return wraps NULL on garbage and
    raises [Failure] from the binding's guard (pre-flight correction 7) — is never called.
    A trigger is data a golden can read, built from the same {!Keyval} and {!Modifiers}
    the key attrs already use. *)
type t =
  { key : int (* a {!Keyval} *)
  ; modifiers : Modifiers.t
  }
[@@deriving sexp_of, equal, compare]

let create ?(modifiers = Modifiers.none) key = { key; modifiers }

(* A few names for the label; everything else printable is its own character and the rest
   render as hex, which a display string can afford -- this is presentation, not routing. *)
let key_label key =
  if key = Keyval.escape
  then "Escape"
  else if key = Keyval.return
  then "Return"
  else if key = Keyval.tab
  then "Tab"
  else if key = Keyval.space
  then "space"
  else if key = Keyval.backspace
  then "BackSpace"
  else if key = Keyval.delete
  then "Delete"
  else if key = Keyval.up
  then "Up"
  else if key = Keyval.down
  then "Down"
  else if key = Keyval.left
  then "Left"
  else if key = Keyval.right
  then "Right"
  else if key >= 0x20 && key <= 0x7e
  then String.of_char (Char.of_int_exn key)
  else (
    match List.find (List.range 1 13) ~f:(fun n -> Keyval.f n = key) with
    | Some n -> sprintf "F%d" n
    | None -> sprintf "0x%x" key)
;;

(** ["<Control><Shift>k"]-style, GTK's accelerator spelling in GTK's own modifier order
    (Shift, Control, Alt, Super, Hyper, Meta) — {b for display only}: it is what a
    {!Menu.Item.accel} wants to say beside a label, and nothing ever parses it. *)
let to_label { key; modifiers = m } =
  let mods =
    [ "<Shift>", m.shift
    ; "<Control>", m.control
    ; "<Alt>", m.alt
    ; "<Super>", m.super
    ; "<Hyper>", m.hyper
    ; "<Meta>", m.meta
    ]
    |> List.filter_map ~f:(fun (s, b) -> if b then Some s else None)
    |> String.concat
  in
  mods ^ key_label key
;;
