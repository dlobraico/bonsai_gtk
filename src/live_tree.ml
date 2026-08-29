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
         | _ -> Some (W.Password_entry.get_placeholder_text (cast w))
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
