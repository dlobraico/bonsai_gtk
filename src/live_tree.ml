open! Core
open Gtk_import

(* Only non-default values are printed, so a dump stays about the widget under test rather
   than about GTK's defaults — and so adding a property here does not churn every expected
   file. The defaults are GTK4's own: zero margins, [`FILL] alignment, no expansion, no
   tooltip, and [-1] (meaning "no request") for both halves of the size request. *)
let align_name : Gtk_enums.align -> string = function
  | `FILL -> "fill"
  | `START -> "start"
  | `END -> "end"
  | `CENTER -> "center"
  | `BASELINE_FILL -> "baseline-fill"
  | `BASELINE -> "baseline"
  | `BASELINE_CENTER -> "baseline-center"
;;

let ellipsize_name : Ocgtk_pango.Pango.ellipsizemode -> string = function
  | `NONE -> "none"
  | `START -> "start"
  | `MIDDLE -> "middle"
  | `END -> "end"
;;

let policy_name : Gtk_enums.policytype -> string = function
  | `ALWAYS -> "always"
  | `AUTOMATIC -> "automatic"
  | `NEVER -> "never"
  | `EXTERNAL -> "external"
;;

let content_fit_name : Gtk_enums.contentfit -> string = function
  | `FILL -> "fill"
  | `CONTAIN -> "contain"
  | `COVER -> "cover"
  | `SCALE_DOWN -> "scale-down"
;;

let int_prop name value ~default =
  if value = default then [] else [ Sexp.List [ Atom name; Atom (Int.to_string value) ] ]
;;

let float_prop name value ~default =
  if Float.equal value default
  then []
  else [ Sexp.List [ Atom name; Atom (sprintf "%g" value) ] ]
;;

let string_prop name value ~default =
  if String.equal value default then [] else [ Sexp.List [ Atom name; Atom value ] ]
;;

let flag_prop name value = if value then [ Sexp.Atom name ] else []

(* A string property read through a GValue rather than through its class getter, for the
   getters ocgtk binds as [string] where the C function may return NULL --
   [gtk_password_entry_get_placeholder_text] is the one M1 hits, and calling it on a
   password entry that never had a placeholder is a segfault rather than an exception.
   [ml_g_value_get_string] maps NULL to [""], which is what the callers below already
   treat as "no placeholder". *)
let string_property (w : Widget.t) ~name =
  let v = Gobject.Value.create Gobject.Type.string in
  Gobject.Property.get_value w ~name v;
  Gobject.Value.get_string v
;;

let policy_prop name (p : Gtk_enums.policytype) =
  match p with
  | `AUTOMATIC -> []
  | p -> [ Sexp.List [ Atom name; Atom (policy_name p) ] ]
;;

let align_prop name (a : Gtk_enums.align) =
  match a with
  | `FILL -> []
  | a -> [ Sexp.List [ Atom name; Atom (align_name a) ] ]
;;

let layout_props (w : Widget.t) =
  let width, height = Widget.get_size_request w in
  List.concat
    [ int_prop "margin-start" (Widget.get_margin_start w) ~default:0
    ; int_prop "margin-end" (Widget.get_margin_end w) ~default:0
    ; int_prop "margin-top" (Widget.get_margin_top w) ~default:0
    ; int_prop "margin-bottom" (Widget.get_margin_bottom w) ~default:0
    ; align_prop "halign" (Widget.get_halign w)
    ; align_prop "valign" (Widget.get_valign w)
    ; flag_prop "hexpand" (Widget.get_hexpand w)
    ; flag_prop "vexpand" (Widget.get_vexpand w)
    ; (match Widget.get_tooltip_text w with
       | None -> []
       | Some s -> [ Sexp.List [ Atom "tooltip"; Atom s ] ])
    ; int_prop "width-request" width ~default:(-1)
    ; int_prop "height-request" height ~default:(-1)
    ; float_prop "opacity" (Widget.get_opacity w) ~default:1.
      (* GTK's [get_name] falls back to the widget's class name when no name was set, so
         that — not the empty string — is the "unnamed" value to suppress. *)
    ; string_prop "name" (Widget.get_name w) ~default:(type_name w)
    ; (match Widget.get_cursor w with
       | None -> []
       | Some c ->
         [ Sexp.List
             [ Atom "cursor"
             ; Atom (Option.value (Ocgtk_gdk.Gdk.Wrappers.Cursor.get_name c) ~default:"?")
             ]
         ])
    ]
;;

(* Both range widgets' value and bounds, printed unconditionally: they are what the node
   asked for rather than GTK defaults, and a dump that omitted them could not show a
   controlled write landing (or failing to). *)
let range_props ~value ~lower ~upper =
  [ Sexp.List [ Atom "value"; Atom (sprintf "%g" value) ]
  ; Sexp.List [ Atom "range"; Atom (sprintf "%g" lower); Atom (sprintf "%g" upper) ]
  ]
;;

(* Shared by [GtkButton] and [GtkToggleButton], which sets the same three properties
   through the same [GtkButton] setters. *)
let button_props (b : W.Button.t) =
  [ [%sexp `label (W.Button.get_label b : string option)] ]
  @ (match W.Button.get_icon_name b with
     | None -> []
     | Some i -> [ Sexp.List [ Atom "icon"; Atom i ] ])
  @ if W.Button.get_has_frame b then [] else [ Sexp.Atom "frameless" ]
;;

(* [focusable] and [can_focus] are deliberately absent: their defaults are per widget
   class, so there is no constant to compare against and an unconditional print would
   churn every expected file. The live attr test covers them instead, by asserting that a
   widget which had them set and then unset dumps identically to one that never did. *)
let rec dump (w : Widget.t) : Sexp.t =
  let ty = type_name w in
  let props =
    (match ty with
     | "GtkLabel" ->
       let l = cast w in
       [ [%sexp `text (W.Label.get_text l : string)] ]
       @ flag_prop "wrap" (W.Label.get_wrap l)
       @ float_prop "xalign" (W.Label.get_xalign l) ~default:0.5
       @ (match W.Label.get_ellipsize l with
          | `NONE -> []
          | e -> [ Sexp.List [ Atom "ellipsize"; Atom (ellipsize_name e) ] ])
       @ int_prop "max-width-chars" (W.Label.get_max_width_chars l) ~default:(-1)
       @ int_prop "width-chars" (W.Label.get_width_chars l) ~default:(-1)
       @ flag_prop "selectable" (W.Label.get_selectable l)
       @ flag_prop "markup" (W.Label.get_use_markup l)
     | "GtkButton" -> button_props (cast w)
     | "GtkToggleButton" ->
       button_props (cast w) @ flag_prop "active" (W.Toggle_button.get_active (cast w))
     | "GtkCheckButton" ->
       let c = cast w in
       [ [%sexp `label (W.Check_button.get_label c : string option)] ]
       @ flag_prop "active" (W.Check_button.get_active c)
       @ flag_prop "inconsistent" (W.Check_button.get_inconsistent c)
     | "GtkSwitch" ->
       let s = cast w in
       (* [state] as well as [active]: the two are kept equal deliberately (see
          [w_switch.ml]), and only printing one would not show that. *)
       flag_prop "active" (W.Switch.get_active s)
       @ flag_prop "state" (W.Switch.get_state s)
     (* One arm for the three entry kinds: everything but the placeholder and each class's
        own extra reads through [GtkEditable], which all three implement. GTK's internal
        children (the [GtkText] the entry delegates to, the search and peek icons) print
        like any other child — that is what GTK actually holds. *)
     | "GtkEntry" | "GtkPasswordEntry" | "GtkSearchEntry" ->
       let e = W.Editable.from_gobject w in
       let placeholder =
         match ty with
         | "GtkEntry" -> W.Entry.get_placeholder_text (cast w)
         | "GtkSearchEntry" -> W.Search_entry.get_placeholder_text (cast w)
         | _ -> Some (string_property w ~name:"placeholder-text")
       in
       (* [""] is "no placeholder": [GtkPasswordEntry]'s getter is not nullable, and
          clearing either of the other two writes an empty string GTK reports back. *)
       let placeholder =
         match placeholder with
         | Some "" -> None
         | p -> p
       in
       [ [%sexp `text (W.Editable.get_text e : string)] ]
       @ (match placeholder with
          | None -> []
          | Some p -> [ Sexp.List [ Atom "placeholder"; Atom p ] ])
       @ int_prop "width-chars" (W.Editable.get_width_chars e) ~default:(-1)
       @ int_prop "max-width-chars" (W.Editable.get_max_width_chars e) ~default:(-1)
       @ float_prop "xalign" (W.Editable.get_alignment e) ~default:0.
       @ (if W.Editable.get_editable e then [] else [ Sexp.Atom "read-only" ])
       @
         (match ty with
         | "GtkEntry" ->
           if W.Entry.get_visibility (cast w) then [] else [ Sexp.Atom "masked" ]
         | "GtkPasswordEntry" ->
           if W.Password_entry.get_show_peek_icon (cast w)
           then []
           else [ Sexp.Atom "no-peek-icon" ]
         | _ ->
           int_prop "search-delay" (W.Search_entry.get_search_delay (cast w)) ~default:150)
     (* [GtkSpinButton] is *not* a [GtkRange] -- it owns its own adjustment and its own
        getters -- so these two arms share their shape and none of their calls. *)
     | "GtkScale" ->
       let s : W.Scale.t = cast w in
       let r : W.Range.t = cast w in
       let a = W.Range.get_adjustment r in
       range_props
         ~value:(W.Range.get_value r)
         ~lower:(W.Adjustment.get_lower a)
         ~upper:(W.Adjustment.get_upper a)
       @ int_prop "digits" (W.Scale.get_digits s) ~default:1
       @ (if W.Scale.get_draw_value s then [] else [ Sexp.Atom "no-value" ])
       @ (if W.Scale.get_has_origin s then [] else [ Sexp.Atom "no-origin" ])
       @ flag_prop "inverted" (W.Range.get_inverted r)
     | "GtkSpinButton" ->
       let s : W.Spin_button.t = cast w in
       let lower, upper = W.Spin_button.get_range s in
       range_props ~value:(W.Spin_button.get_value s) ~lower ~upper
       @ int_prop "digits" (W.Spin_button.get_digits s) ~default:0
       @ flag_prop "numeric" (W.Spin_button.get_numeric s)
       @ flag_prop "wrap" (W.Spin_button.get_wrap s)
     | "GtkProgressBar" ->
       let b : W.Progress_bar.t = cast w in
       [ Sexp.List
           [ Atom "fraction"; Atom (sprintf "%g" (W.Progress_bar.get_fraction b)) ]
       ]
       @ (match W.Progress_bar.get_text b with
          | None -> []
          | Some t -> [ Sexp.List [ Atom "text"; Atom t ] ])
       @ flag_prop "show-text" (W.Progress_bar.get_show_text b)
       @ flag_prop "inverted" (W.Progress_bar.get_inverted b)
       @
         (match W.Progress_bar.get_ellipsize b with
         | `NONE -> []
         | e -> [ Sexp.List [ Atom "ellipsize"; Atom (ellipsize_name e) ] ])
     | "GtkSpinner" -> flag_prop "spinning" (W.Spinner.get_spinning (cast w))
     (* Only the icon name is printed for an image, and only [has-paintable] for a
        picture: a file-backed source becomes a texture whose identity is not stable
        across runs, and its pixels are not what these tests are claiming. *)
     | "GtkImage" ->
       (match W.Image.get_icon_name (cast w) with
        | None -> []
        | Some n -> [ Sexp.List [ Atom "icon"; Atom n ] ])
       @ int_prop "pixel-size" (W.Image.get_pixel_size (cast w)) ~default:(-1)
     | "GtkPicture" ->
       let p : W.Picture.t = cast w in
       flag_prop "has-paintable" (Option.is_some (W.Picture.get_paintable p))
       @ (match W.Picture.get_content_fit p with
          | `CONTAIN -> []
          | f -> [ Sexp.List [ Atom "content-fit"; Atom (content_fit_name f) ] ])
       @ (if W.Picture.get_can_shrink p then [] else [ Sexp.Atom "no-shrink" ])
       @
         (match W.Picture.get_alternative_text p with
         | None -> []
         | Some t -> [ Sexp.List [ Atom "alt"; Atom t ] ])
     | "GtkSeparator" ->
       [ Sexp.List
           [ Atom "orientation"
           ; Atom
               (match W.Orientable.get_orientation (W.Orientable.from_gobject w) with
                | `HORIZONTAL -> "horizontal"
                | `VERTICAL -> "vertical")
           ]
       ]
     (* A [GtkScrolledWindow] prints its two internal [GtkScrollbar] children like any
        other child, and a non-scrollable child arrives wrapped in a [GtkViewport] GTK
        added itself. Both are left in: they are the honest tree, and the viewport's
        presence is what shows the child landed *inside* the scroller rather than beside
        it. Only the two content minima are printed -- the policies are visible in the
        scrollbars, and the rest are size hints no test has claimed. *)
     | "GtkScrolledWindow" ->
       let s : W.Scrolled_window.t = cast w in
       let hpolicy, vpolicy = W.Scrolled_window.get_policy s in
       (* The policies are printed because nothing else in the dump shows them: the two
          scrollbars are children whatever the policy says, and a [`NEVER] one differs
          only in child visibility, which this dump does not descend into. *)
       policy_prop "hpolicy" hpolicy
       @ policy_prop "vpolicy" vpolicy
       @ int_prop
           "min-content-height"
           (W.Scrolled_window.get_min_content_height s)
           ~default:(-1)
       @ int_prop
           "min-content-width"
           (W.Scrolled_window.get_min_content_width s)
           ~default:(-1)
       @ int_prop
           "max-content-height"
           (W.Scrolled_window.get_max_content_height s)
           ~default:(-1)
       @ int_prop
           "max-content-width"
           (W.Scrolled_window.get_max_content_width s)
           ~default:(-1)
       @ flag_prop
           "propagate-natural-height"
           (W.Scrolled_window.get_propagate_natural_height s)
       @ flag_prop
           "propagate-natural-width"
           (W.Scrolled_window.get_propagate_natural_width s)
       @ (if W.Scrolled_window.get_kinetic_scrolling s
          then []
          else [ Sexp.Atom "no-kinetic" ])
       @ (if W.Scrolled_window.get_overlay_scrolling s
          then []
          else [ Sexp.Atom "no-overlay" ])
       @ flag_prop "framed" (W.Scrolled_window.get_has_frame s)
     | "GtkFrame" -> [ [%sexp `label (W.Frame.get_label (cast w) : string option)] ]
     | "GtkExpander" ->
       [ [%sexp `label (W.Expander.get_label (cast w) : string option)] ]
       @ flag_prop "expanded" (W.Expander.get_expanded (cast w))
     (* Both halves: [reveal] is the input the model controls and [revealed] the outcome
        the animation settles, and a dump that showed only one could not tell a reveal
        that landed from one still in flight. *)
     | "GtkRevealer" ->
       flag_prop "reveal" (W.Revealer.get_reveal_child (cast w))
       @ flag_prop "revealed" (W.Revealer.get_child_revealed (cast w))
     | "GtkCenterBox" ->
       (* Only the non-GTK value: which of the three slots are filled is visible in the
          children, and an empty slot parents nothing at all. *)
       if W.Center_box.get_shrink_center_last (cast w)
       then []
       else [ Sexp.Atom "no-shrink-center-last" ]
     (* [position] and [position-set] together: [position] alone cannot distinguish a
        divider the node pinned from one GTK computed, and pinning it is what
        [Node.paned ~position] does (GTK sets [position-set] as a side effect of
        [set_position]). This is also the read-back for the one prop in this library that
        is deliberately not controlled. *)
     | "GtkPaned" ->
       let p : W.Paned.t = cast w in
       [ Sexp.List [ Atom "position"; Atom (Int.to_string (W.Paned.get_position p)) ] ]
       @ flag_prop "position-set" (W.Paned.get_position_set p)
       @ flag_prop "wide-handle" (W.Paned.get_wide_handle p)
       @ (if W.Paned.get_resize_start_child p then [] else [ Sexp.Atom "no-resize-start" ])
       @ (if W.Paned.get_resize_end_child p then [] else [ Sexp.Atom "no-resize-end" ])
       @ flag_prop "shrink-start" (W.Paned.get_shrink_start_child p)
       @ flag_prop "shrink-end" (W.Paned.get_shrink_end_child p)
     (* [measure-overlay] is a setting the *overlay* holds about each child, so a child's
        own dump cannot show it; print it from this side, as the indices of the children
        the overlay does not measure -- indices into the *whole* child list, main child
        included at 0, so the first overlay child is 1. The main child is never listed: it
        is not an overlay, and GTK's getter reports [false] for it whatever the overlay is
        doing, so including it would print every overlay as having an unmeasured 0. *)
     | "GtkOverlay" ->
       let o : W.Overlay.t = cast w in
       let main = W.Overlay.get_child o in
       (match
          List.filter_mapi (widget_children w) ~f:(fun i c ->
            if Option.exists main ~f:(fun m -> Gobject.same m c)
               || W.Overlay.get_measure_overlay o c
            then None
            else Some i)
        with
        | [] -> []
        | idxs -> [ [%sexp `unmeasured (idxs : int list)] ])
     (* A grid child's cell is held by the *grid*, so a child's own dump cannot show it;
        print it from this side, in [widget_children] order so the list lines up with the
        children printed underneath.

        That order is GTK's, not the node list's: [gtk_grid_attach] appends, so a child
        whose cell changed -- detached and re-attached by the grid's [updated] hook --
        moves to the end of both this list and the children below it, however early it
        sits in the node list. Nothing about a grid's layout depends on that order. *)
     | "GtkGrid" ->
       let g : W.Grid.t = cast w in
       int_prop "row-spacing" (W.Grid.get_row_spacing g) ~default:0
       @ int_prop "column-spacing" (W.Grid.get_column_spacing g) ~default:0
       @ flag_prop "row-homogeneous" (W.Grid.get_row_homogeneous g)
       @ flag_prop "column-homogeneous" (W.Grid.get_column_homogeneous g)
       @
         (match
            List.map (widget_children w) ~f:(fun c ->
              let column, row, width, height = W.Grid.query_child g c in
              [%sexp (column : int), (row : int), (width : int), (height : int)])
          with
         | [] -> []
         | cells -> [ Sexp.List (Atom "cells" :: cells) ])
     (* A [GtkStack]'s pages are not children in the [get_first_child] sense -- the page
        widgets themselves are what the recursion below walks -- so the only thing to add
        is which of them is showing. *)
     | "GtkStack" ->
       [ [%sexp `visible (W.Stack.get_visible_child_name (cast w) : string option)] ]
     (* Whether the fixup pass wired these up at all: the buttons or rows they build are
        children, but a switcher pointing at nothing has none and so would dump the same
        as one whose stack is simply empty. *)
     | "GtkStackSwitcher" ->
       flag_prop "has-stack" (Option.is_some (W.Stack_switcher.get_stack (cast w)))
     | "GtkStackSidebar" ->
       flag_prop "has-stack" (Option.is_some (W.Stack_sidebar.get_stack (cast w)))
     | "GtkWindow" -> [ [%sexp `title (W.Window.get_title (cast w) : string option)] ]
     | "GtkBox" -> [ [%sexp `spacing (W.Box.get_spacing (cast w) : int)] ]
     | _ -> [])
    @ (match Array.to_list (Widget.get_css_classes w) with
       | [] -> []
       | l -> [ [%sexp `css (l : string list)] ])
    @ layout_props w
    @ (if Widget.get_visible w then [] else [ Sexp.Atom "hidden" ])
    @ if Widget.get_sensitive w then [] else [ Sexp.Atom "insensitive" ]
  in
  let kids =
    match widget_children w with
    | [] -> []
    | kids -> [ Sexp.List (Sexp.Atom "children" :: List.map kids ~f:dump) ]
  in
  Sexp.List (Sexp.Atom ty :: (props @ kids))
;;
