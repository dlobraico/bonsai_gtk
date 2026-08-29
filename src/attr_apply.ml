open! Core
open Bonsai_gtk_vtree
open Gtk_import

let align : Align.t -> Gtk_enums.align = function
  | Fill -> `FILL
  | Start -> `START
  | End -> `END
  | Center -> `CENTER
  | Baseline -> `BASELINE_FILL
;;

(* GTK exposes width and height as a single [set_size_request] call, so setting one
   requires reading the current pair back to preserve the other. *)
let set_width (w : Widget.t) width =
  let _, height = Widget.get_size_request w in
  Widget.set_size_request w width height
;;

let set_height (w : Widget.t) height =
  let width, _ = Widget.get_size_request w in
  Widget.set_size_request w width height
;;

let set (w : Widget.t) (attr : Attr.t) =
  match attr with
  | Css_class c -> Widget.add_css_class w c
  | Margin_start n -> Widget.set_margin_start w n
  | Margin_end n -> Widget.set_margin_end w n
  | Margin_top n -> Widget.set_margin_top w n
  | Margin_bottom n -> Widget.set_margin_bottom w n
  | Halign a -> Widget.set_halign w (align a)
  | Valign a -> Widget.set_valign w (align a)
  | Hexpand b -> Widget.set_hexpand w b
  | Vexpand b -> Widget.set_vexpand w b
  | Sensitive b -> Widget.set_sensitive w b
  | Visible b -> Widget.set_visible w b
  | Tooltip s -> Widget.set_tooltip_text w (Some s)
  | Width_request n -> set_width w n
  | Height_request n -> set_height w n
  (* [Test_id] is inert at runtime; [On_clicked] is handled by [Signals]. [Many] is
     flattened away by [Attrs.of_list] and never reaches here. *)
  | Test_id _ | On_clicked _ | Many _ -> ()
;;

(* Reset to the GTK default for [name]. *)
let unset (w : Widget.t) (name : Attr.Name.t) =
  match name with
  | Margin_start -> Widget.set_margin_start w 0
  | Margin_end -> Widget.set_margin_end w 0
  | Margin_top -> Widget.set_margin_top w 0
  | Margin_bottom -> Widget.set_margin_bottom w 0
  | Halign -> Widget.set_halign w `FILL
  | Valign -> Widget.set_valign w `FILL
  | Hexpand -> Widget.set_hexpand w false
  | Vexpand -> Widget.set_vexpand w false
  | Sensitive -> Widget.set_sensitive w true
  | Visible -> Widget.set_visible w true
  | Tooltip -> Widget.set_tooltip_text w None
  | Width_request -> set_width w (-1)
  | Height_request -> set_height w (-1)
  | Test_id | On_clicked -> ()
;;

let apply w (op : Attrs.op) =
  match op with
  | Set a -> set w a
  | Unset n -> unset w n
  | Add_css_class c -> Widget.add_css_class w c
  | Remove_css_class c -> Widget.remove_css_class w c
;;

let apply_all w attrs = List.iter (Attrs.to_list attrs) ~f:(set w)
