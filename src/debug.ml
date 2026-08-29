open! Core
open Gtk_import

let rec dump_live_tree (w : Widget.t) : Sexp.t =
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
    @ (if Widget.get_visible w then [] else [ Sexp.Atom "hidden" ])
    @ if Widget.get_sensitive w then [] else [ Sexp.Atom "insensitive" ]
  in
  let kids =
    match widget_children w with
    | [] -> []
    | kids -> [ Sexp.List (Sexp.Atom "children" :: List.map kids ~f:dump_live_tree) ]
  in
  Sexp.List (Sexp.Atom ty :: (props @ kids))
;;
