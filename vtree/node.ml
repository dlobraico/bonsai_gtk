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

(* [min], [max] and [value] are required on both range widgets for the reason [text] is
   required on the entries: a widget whose value nothing feeds back is uncontrolled, and
   an implicit 0-100 range is a bug generator. *)
let spin_button
  ?key
  ?attrs
  ?(digits = 0)
  ?(numeric = true)
  ?(wrap = false)
  ?(step = 1.)
  ?(activates_default = false)
  ~min
  ~max
  ~value
  ()
  =
  make
    ?key
    ?attrs
    (Spin_button { value; min; max; step; digits; numeric; wrap; activates_default })
    No_children
;;

let scale
  ?key
  ?attrs
  ?(step = 1.)
  ?(digits = 1)
  ?(draw_value = true)
  ?(has_origin = true)
  ?(inverted = false)
  ~orientation
  ~min
  ~max
  ~value
  ()
  =
  make
    ?key
    ?attrs
    (Scale
       { orientation; value; min; max; step; digits; draw_value; has_origin; inverted })
    No_children
;;

let progress_bar
  ?key
  ?attrs
  ?text
  ?(show_text = false)
  ?(inverted = false)
  ?ellipsize
  ~fraction
  ()
  =
  make
    ?key
    ?attrs
    (Progress_bar { fraction; text; show_text; inverted; ellipsize })
    No_children
;;

let spinner ?key ?attrs ~spinning () = make ?key ?attrs (Spinner { spinning }) No_children

(* [source] comes last and unlabelled on both of these: it is the one thing an image or a
   picture cannot do without, and putting it in final position is what lets the optional
   arguments before it be erased. *)
let image ?key ?attrs ?(pixel_size = -1) ?(icon_size = Icon_size.Inherit) source =
  make ?key ?attrs (Image { source; pixel_size; icon_size }) No_children
;;

let picture
  ?key
  ?attrs
  ?(content_fit = Content_fit.Contain)
  ?(can_shrink = true)
  ?alternative_text
  source
  =
  make
    ?key
    ?attrs
    (Picture { source; content_fit; can_shrink; alternative_text })
    No_children
;;

(* The trailing [unit] is what makes [?key] and [?attrs] erasable: [~orientation] is
   labelled, so without it the optional arguments in front of it never get their defaults.
   Same shape as [spinner] and the rest. *)
let separator ?key ?attrs ~orientation () =
  make ?key ?attrs (Separator { orientation }) No_children
;;

(* All four take their child positionally, like [window]: a scrolled window with nothing
   in it, a frame around nothing, an expander that expands onto nothing are all
   meaningless, so the slot is required rather than [?child]. That also means none of
   these can express [Single None] -- the child is replaced, never removed. *)
let scrolled_window
  ?key
  ?attrs
  ?(hpolicy = Policy.Automatic)
  ?(vpolicy = Policy.Automatic)
  ?(min_content_width = -1)
  ?(min_content_height = -1)
  ?(max_content_width = -1)
  ?(max_content_height = -1)
  ?(propagate_natural_width = false)
  ?(propagate_natural_height = false)
  ?(has_frame = false)
  ?(kinetic_scrolling = true)
  ?(overlay_scrolling = true)
  child
  =
  make
    ?key
    ?attrs
    (Scrolled_window
       { hpolicy
       ; vpolicy
       ; min_content_width
       ; min_content_height
       ; max_content_width
       ; max_content_height
       ; propagate_natural_width
       ; propagate_natural_height
       ; has_frame
       ; kinetic_scrolling
       ; overlay_scrolling
       })
    (Single (Some child))
;;

let frame ?key ?attrs ?label ?(label_align = 0.) child =
  make ?key ?attrs (Frame { label; label_align }) (Single (Some child))
;;

let expander ?key ?attrs ?label ?(use_markup = false) ~expanded child =
  make ?key ?attrs (Expander { label; expanded; use_markup }) (Single (Some child))
;;

let revealer
  ?key
  ?attrs
  ?(transition = Reveal_transition.None_)
  ?(transition_duration = 250)
  ~reveal
  child
  =
  make
    ?key
    ?attrs
    (Revealer { reveal; transition; transition_duration })
    (Single (Some child))
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
