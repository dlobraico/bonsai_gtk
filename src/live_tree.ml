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

let int_prop name value ~default =
  if value = default then [] else [ Sexp.List [ Atom name; Atom (Int.to_string value) ] ]
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
    ]
;;

let rec dump (w : Widget.t) : Sexp.t =
  let ty = type_name w in
  let props =
    (match ty with
     | "GtkLabel" -> [ [%sexp `text (W.Label.get_text (cast w) : string)] ]
     | "GtkButton" -> [ [%sexp `label (W.Button.get_label (cast w) : string option)] ]
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
