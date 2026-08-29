open! Core

type t =
  { kind : Kind.t
  ; key : Key.t option [@sexp.option]
  ; attrs : Attrs.t
  ; children : t Children.t
  }
[@@deriving sexp_of]

let make ?key ?(attrs = []) kind children =
  { kind; key; attrs = Attrs.of_list attrs; children }
;;

(* Every default here is GTK's own, so [Node.label "x"] describes exactly the widget a
   bare [GtkLabel] already is. *)
let label
  ?key
  ?attrs
  ?(wrap = false)
  ?(xalign = 0.5)
  ?ellipsize
  ?(max_width_chars = -1)
  ?(width_chars = -1)
  ?(selectable = false)
  ?(use_markup = false)
  text
  =
  make
    ?key
    ?attrs
    (Label
       { text
       ; wrap
       ; xalign
       ; ellipsize
       ; max_width_chars
       ; width_chars
       ; selectable
       ; use_markup
       })
    No_children
;;

let button ?key ?attrs ?label ?icon_name ?(has_frame = true) ?child () =
  make ?key ?attrs (Button { label; icon_name; has_frame }) (Single child)
;;

let toggle_button ?key ?attrs ?label ?icon_name ?(has_frame = true) ?child ~active () =
  make ?key ?attrs (Toggle_button { label; icon_name; has_frame; active }) (Single child)
;;

let check_button ?key ?attrs ?label ?(inconsistent = false) ~active () =
  (* [No_children], not [Single None]: a check button has no child slot in this library
     (see the mli), and the patcher rejects a children shape its impl does not hold. *)
  make ?key ?attrs (Check_button { label; active; inconsistent }) No_children
;;

let switch ?key ?attrs ~active () = make ?key ?attrs (Switch { active }) No_children

(* All three take [~text] as a required labelled argument: a text widget with no text prop
   is uncontrolled, and an uncontrolled text widget in a declarative tree is a bug that
   shows up as "my entry resets when something unrelated re-renders". *)
let entry
  ?key
  ?attrs
  ?placeholder
  ?(editable = true)
  ?(visibility = true)
  ?(width_chars = -1)
  ?(max_width_chars = -1)
  ?(xalign = 0.)
  ?(activates_default = false)
  ~text
  ()
  =
  make
    ?key
    ?attrs
    (Entry
       { text
       ; placeholder
       ; editable
       ; visibility
       ; width_chars
       ; max_width_chars
       ; xalign
       ; activates_default
       })
    No_children
;;

let password_entry
  ?key
  ?attrs
  ?placeholder
  ?(show_peek_icon = true)
  ?(activates_default = false)
  ~text
  ()
  =
  make
    ?key
    ?attrs
    (Password_entry { text; placeholder; show_peek_icon; activates_default })
    No_children
;;

let search_entry ?key ?attrs ?placeholder ?search_delay ~text () =
  make ?key ?attrs (Search_entry { text; placeholder; search_delay }) No_children
;;

let box ?key ?attrs ?(spacing = 0) ?(homogeneous = false) ~orientation children =
  make ?key ?attrs (Box { orientation; spacing; homogeneous }) (List children)
;;

let window ?key ?attrs ?title ?default_size child =
  make ?key ?attrs (Window { title; default_size }) (Single (Some child))
;;

let native ?key ?attrs n = make ?key ?attrs (Native n) No_children

let rec find_by_test_id t id =
  if Option.equal String.equal (Attrs.test_id t.attrs) (Some id)
  then Some t
  else (
    let kids =
      match t.children with
      | No_children -> []
      | Single c -> Option.to_list c
      | List l -> l
    in
    List.find_map kids ~f:(fun c -> find_by_test_id c id))
;;
