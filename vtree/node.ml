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

(* The keyed containers -- a stack's pages, and from M2 a list box's rows -- require a
   [~key] on every child rather than merely reconciling by it where it is present. The key
   is the child's identity in the parent's own terms: for a stack it is the GTK page name
   that [~visible_child] selects by, and for a list box it is what [~selected] names and
   what every handler receives, because GTK's own answer (a row widget, or an index that
   moves) is not something an application can act on.

   Checked here rather than at mount, which is where M1 put the stack's: the constructor
   already has the children in hand, so the mistake is caught at the line that made it and
   with no live tree involved -- a headless suite finds it, and so does a [dune build] of
   a test that never mounts anything. The impl-side check stays as a backstop for the
   nodes this function did not build (see [w_stack.ml]'s [page_name]).

   [which] is the constructor as the caller spelled it and [why] says what the key is for,
   so the two containers' messages differ only where they should. *)
let require_child_keys ~which ~why children =
  List.iteri children ~f:(fun i (c : t) ->
    match c.key with
    | Some _ -> ()
    | None -> invalid_argf "%s: child %d has no ~key (%s)" which i why ())
;;

(* The constructors below are total, with one exception: [scrolled_window] rejects a
   minimum content bound above its maximum. It is the exception because that mistake has
   no later diagnostic -- GTK calls it a programming error and checks nothing -- and
   because the two numbers are right there in the call, so the constructor is the only
   place that can name them. Every other kind of misuse a node can express is structural
   (a window below the root, a grid child with no cell, an event attr nothing emits) and
   is rejected by the patcher, which knows where in the tree the node is.

   Every default here is GTK's own, so [Node.label "x"] describes exactly the widget a
   bare [GtkLabel] already is. They are named in [Defaults] rather than written as
   literals: the matching [Kind] field's [@sexp_drop_if] has to agree with each one, and a
   literal in both places is a drift waiting to happen. *)
let label
  ?key
  ?attrs
  ?(wrap = Defaults.Label.wrap)
  ?(xalign = Defaults.Label.xalign)
  ?ellipsize
  ?(max_width_chars = Defaults.Label.max_width_chars)
  ?(width_chars = Defaults.Label.width_chars)
  ?(selectable = Defaults.Label.selectable)
  ?(use_markup = Defaults.Label.use_markup)
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

let button
  ?key
  ?attrs
  ?label
  ?icon_name
  ?(has_frame = Defaults.Button.has_frame)
  ?child
  ()
  =
  make ?key ?attrs (Button { label; icon_name; has_frame }) (Single child)
;;

let toggle_button
  ?key
  ?attrs
  ?label
  ?icon_name
  ?(has_frame = Defaults.Toggle_button.has_frame)
  ?child
  ~active
  ()
  =
  make ?key ?attrs (Toggle_button { label; icon_name; has_frame; active }) (Single child)
;;

let check_button
  ?key
  ?attrs
  ?label
  ?(inconsistent = Defaults.Check_button.inconsistent)
  ~active
  ()
  =
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
  ?(editable = Defaults.Entry.editable)
  ?(visibility = Defaults.Entry.visibility)
  ?(width_chars = Defaults.Entry.width_chars)
  ?(max_width_chars = Defaults.Entry.max_width_chars)
  ?(xalign = Defaults.Entry.xalign)
  ?(activates_default = Defaults.Entry.activates_default)
  ?(max_length = Defaults.Entry.max_length)
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
       ; max_length
       })
    No_children
;;

let password_entry
  ?key
  ?attrs
  ?placeholder
  ?(show_peek_icon = Defaults.Password_entry.show_peek_icon)
  ?(activates_default = Defaults.Password_entry.activates_default)
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
  ?(digits = Defaults.Spin_button.digits)
  ?(numeric = Defaults.Spin_button.numeric)
  ?(wrap = Defaults.Spin_button.wrap)
  ?(step = Defaults.Spin_button.step)
  ?(activates_default = Defaults.Spin_button.activates_default)
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
  ?(step = Defaults.Scale.step)
  ?(digits = Defaults.Scale.digits)
  ?(draw_value = Defaults.Scale.draw_value)
  ?(has_origin = Defaults.Scale.has_origin)
  ?(inverted = Defaults.Scale.inverted)
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
  ?(show_text = Defaults.Progress_bar.show_text)
  ?(inverted = Defaults.Progress_bar.inverted)
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
let image
  ?key
  ?attrs
  ?(pixel_size = Defaults.Image.pixel_size)
  ?(icon_size = Defaults.Image.icon_size)
  source
  =
  make ?key ?attrs (Image { source; pixel_size; icon_size }) No_children
;;

let picture
  ?key
  ?attrs
  ?(content_fit = Defaults.Picture.content_fit)
  ?(can_shrink = Defaults.Picture.can_shrink)
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
  ?(hpolicy = Defaults.Scrolled_window.hpolicy)
  ?(vpolicy = Defaults.Scrolled_window.vpolicy)
  ?(min_content_width = Defaults.Scrolled_window.min_content_width)
  ?(min_content_height = Defaults.Scrolled_window.min_content_height)
  ?(max_content_width = Defaults.Scrolled_window.max_content_width)
  ?(max_content_height = Defaults.Scrolled_window.max_content_height)
  ?(propagate_natural_width = Defaults.Scrolled_window.propagate_natural_width)
  ?(propagate_natural_height = Defaults.Scrolled_window.propagate_natural_height)
  ?(has_frame = Defaults.Scrolled_window.has_frame)
  ?(kinetic_scrolling = Defaults.Scrolled_window.kinetic_scrolling)
  ?(overlay_scrolling = Defaults.Scrolled_window.overlay_scrolling)
  child
  =
  (* The one constructor in this file that rejects its arguments (see the note at the
     top). GTK calls a min above a max a programming error and checks nothing at runtime:
     the scrolled window then sizes itself to whichever bound the layout reaches first,
     which reads as a layout bug a long way from its cause. [-1] is "no bound" on either
     side and never conflicts; equal bounds are a fixed size rather than a conflict. *)
  let check_bounds what ~min ~max =
    if min <> -1 && max <> -1 && min > max
    then
      invalid_argf
        "Node.scrolled_window: min_content_%s (%d) is above max_content_%s (%d)"
        what
        min
        what
        max
        ()
  in
  check_bounds "width" ~min:min_content_width ~max:max_content_width;
  check_bounds "height" ~min:min_content_height ~max:max_content_height;
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

let frame ?key ?attrs ?label ?(label_align = Defaults.Frame.label_align) child =
  make ?key ?attrs (Frame { label; label_align }) (Single (Some child))
;;

let expander
  ?key
  ?attrs
  ?label
  ?(use_markup = Defaults.Expander.use_markup)
  ~expanded
  child
  =
  make ?key ?attrs (Expander { label; expanded; use_markup }) (Single (Some child))
;;

let revealer
  ?key
  ?attrs
  ?(transition = Defaults.Revealer.transition)
  ?(transition_duration = Defaults.Revealer.transition_duration)
  ~reveal
  child
  =
  make
    ?key
    ?attrs
    (Revealer { reveal; transition; transition_duration })
    (Single (Some child))
;;

let box
  ?key
  ?attrs
  ?(spacing = Defaults.Box.spacing)
  ?(homogeneous = Defaults.Box.homogeneous)
  ~orientation
  children
  =
  make ?key ?attrs (Box { orientation; spacing; homogeneous }) (List children)
;;

let grid
  ?key
  ?attrs
  ?(row_spacing = Defaults.Grid.row_spacing)
  ?(column_spacing = Defaults.Grid.column_spacing)
  ?(row_homogeneous = Defaults.Grid.row_homogeneous)
  ?(column_homogeneous = Defaults.Grid.column_homogeneous)
  children
  =
  make
    ?key
    ?attrs
    (Grid { row_spacing; column_spacing; row_homogeneous; column_homogeneous })
    (List children)
;;

let stack
  ?key
  ?attrs
  ?(transition = Defaults.Stack.transition)
  ?(transition_duration = Defaults.Stack.transition_duration)
  ?(hhomogeneous = Defaults.Stack.hhomogeneous)
  ?(vhomogeneous = Defaults.Stack.vhomogeneous)
  ~name
  ~visible_child
  children
  =
  require_child_keys
    ~which:"Node.stack"
    ~why:"a stack page's key is its GTK page name"
    children;
  make
    ?key
    ?attrs
    (Stack
       { name
       ; visible_child
       ; transition
       ; transition_duration
       ; hhomogeneous
       ; vhomogeneous
       })
    (List children)
;;

let list_box
  ?key
  ?attrs
  ?(selection_mode = Defaults.List_box.selection_mode)
  ?(activate_on_single_click = Defaults.List_box.activate_on_single_click)
  ?(show_separators = Defaults.List_box.show_separators)
  ?placeholder
  ~selected
  children
  =
  require_child_keys
    ~which:"Node.list_box"
    ~why:"a row's key is the identity every handler receives"
    children;
  make
    ?key
    ?attrs
    (List_box { selection_mode; activate_on_single_click; show_separators; selected })
    (* Two slots rather than a bare list: the placeholder is a child of the [GtkListBox]
       and is patched like any other node, but it is not a row -- it has no key, it is
       never selected or activated, and it must not take part in the rows' reconciliation.
       Naming the two apart is what keeps those facts structural. *)
    (Slots [ "placeholder", Single placeholder; "rows", List children ])
;;

(* The two geometry mistakes GTK does not diagnose usefully.

   [gtk_flow_box_set_max_children_per_line] is [g_return_if_fail (n_children > 0)]: a zero
   logs a critical and leaves the old value, so a caller who meant "no maximum" gets GTK's
   own 7 and no exception. And every one of these four numbers is an unsigned integer in
   C, so a negative is not rejected at all -- it arrives as a very large positive number
   and the layout silently stops making sense.

   Rejected here for the reason {!scrolled_window}'s min/max bound is: the mistake has no
   later diagnostic worth the name, and the two numbers are right there in the call, so
   the constructor is the only place that can name them. *)
let require_non_negative ~which ~arg n =
  if n < 0
  then
    invalid_argf
      "%s: ~%s is %d, but GTK reads it as an unsigned number (a negative one arrives as \
       a very large positive one, with no error)"
      which
      arg
      n
      ()
;;

let flow_box
  ?key
  ?attrs
  ?(selection_mode = Defaults.Flow_box.selection_mode)
  ?(activate_on_single_click = Defaults.Flow_box.activate_on_single_click)
  ?(min_children_per_line = Defaults.Flow_box.min_children_per_line)
  ?(max_children_per_line = Defaults.Flow_box.max_children_per_line)
  ?(row_spacing = Defaults.Flow_box.row_spacing)
  ?(column_spacing = Defaults.Flow_box.column_spacing)
  ?(homogeneous = Defaults.Flow_box.homogeneous)
  ?(orientation = Defaults.Flow_box.orientation)
  ~selected
  children
  =
  require_child_keys
    ~which:"Node.flow_box"
    ~why:"a child's key is the identity every handler receives"
    children;
  let which = "Node.flow_box" in
  require_non_negative ~which ~arg:"min_children_per_line" min_children_per_line;
  require_non_negative ~which ~arg:"row_spacing" row_spacing;
  require_non_negative ~which ~arg:"column_spacing" column_spacing;
  if max_children_per_line < 1
  then
    invalid_argf
      "%s: ~max_children_per_line is %d, but GTK requires at least 1 (a flow box has no \
       \"unlimited\"; its own default is 7)"
      which
      max_children_per_line
      ();
  make
    ?key
    ?attrs
    (Flow_box
       { selection_mode
       ; activate_on_single_click
       ; min_children_per_line
       ; max_children_per_line
       ; row_spacing
       ; column_spacing
       ; homogeneous
       ; orientation
       ; selected
       })
    (* A plain [List], unlike {!list_box}'s two slots: a flow box has no placeholder, so
       every child of the node is a child of the grid and there is nothing to name apart. *)
    (List children)
;;

let stack_switcher ?key ?attrs ~stack () =
  make ?key ?attrs (Stack_switcher { stack }) No_children
;;

let stack_sidebar ?key ?attrs ~stack () =
  make ?key ?attrs (Stack_sidebar { stack }) No_children
;;

(* The slot containers. Each names its children by role, so the shape is [Slots] and each
   slot carries the shape it wants: three optional singles for a centre box, two required
   singles for a paned, and a single plus a list for an overlay. *)
let center_box
  ?key
  ?attrs
  ?(shrink_center_last = Defaults.Center_box.shrink_center_last)
  ?start
  ?center
  ?end_
  ()
  =
  make
    ?key
    ?attrs
    (Center_box { shrink_center_last })
    (Slots [ "start", Single start; "center", Single center; "end", Single end_ ])
;;

(* Both halves are required: a paned with one side is a box, and GTK renders an empty half
   as dead space with a draggable handle into nothing. *)
let paned
  ?key
  ?attrs
  ?position
  ?(wide_handle = Defaults.Paned.wide_handle)
  ?(resize_start = Defaults.Paned.resize_start)
  ?(resize_end = Defaults.Paned.resize_end)
  ?(shrink_start = Defaults.Paned.shrink_start)
  ?(shrink_end = Defaults.Paned.shrink_end)
  ~orientation
  ~start
  ~end_
  ()
  =
  make
    ?key
    ?attrs
    (Paned
       { orientation
       ; position
       ; wide_handle
       ; resize_start
       ; resize_end
       ; shrink_start
       ; shrink_end
       })
    (Slots [ "start", Single (Some start); "end", Single (Some end_) ])
;;

let overlay ?key ?attrs ?(overlays = []) child =
  make
    ?key
    ?attrs
    (Overlay ())
    (Slots [ "child", Single (Some child); "overlays", List overlays ])
;;

let window ?key ?attrs ?title ?default_size child =
  make ?key ?attrs (Window { title; default_size }) (Single (Some child))
;;

let native ?key ?attrs n = make ?key ?attrs (Native n) No_children

(* The whole tree is walked even once a match is found, because two nodes carrying one
   [Attr.test_id] is a mistake worth reporting rather than resolving by walk order: it is
   what rendering the same sub-view twice produces (two rows, both with a "delete"
   button), and a test that acted on whichever the search reached first would pass while
   asserting nothing about which. *)
let find_by_test_id t id =
  let found = ref [] in
  let rec go path t =
    if Option.equal String.equal (Attrs.test_id t.attrs) (Some id)
    then found := (path, t) :: !found;
    Children.iteri t.children ~path ~f:go
  in
  go "root" t;
  match List.rev !found with
  | [] -> None
  | [ (_, t) ] -> Some t
  | duplicates ->
    invalid_argf
      "Node.find_by_test_id: %d nodes carry the test_id %s (%s); a test_id has to \
       identify one node"
      (List.length duplicates)
      id
      (String.concat ~sep:", " (List.map duplicates ~f:fst))
      ()
;;
