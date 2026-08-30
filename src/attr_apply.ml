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

(* Everything [unset] has to be able to put back. Read once off a freshly created widget,
   before any *attribute* has been applied to it, so it is that widget's own creation-time
   value rather than a constant this module would otherwise have to guess per kind
   ([focusable] is false on a label and true on a button; [visible] is true on most
   widgets and false on a GtkWindow, which is the case the M0 review caught).

   Creation-time, not class default: the kind's props are already applied by [create], so
   a [Node.label ~selectable:true] arrives here with GTK's text cursor installed and that
   is what [Unset Cursor_name] will restore. That is the intended reading of "put back
   what this widget had".

   [widget_name] is the one field that cannot be restored exactly: ocgtk's [set_name]
   takes a [string], so there is no NULL to write back and an unnamed widget is restored
   to the class name [get_name] reported for it. *)
type defaults =
  { margin_start : int
  ; margin_end : int
  ; margin_top : int
  ; margin_bottom : int
  ; halign : Gtk_enums.align
  ; valign : Gtk_enums.align
  ; hexpand : bool
  ; vexpand : bool
  ; sensitive : bool
  ; visible : bool
  ; tooltip : string option
  ; size_request : int * int
  ; opacity : float
  ; focusable : bool
  ; can_focus : bool
  ; widget_name : string
  ; cursor : Ocgtk_gdk.Gdk.Wrappers.Cursor.t option
  }

let snapshot (w : Widget.t) =
  { margin_start = Widget.get_margin_start w
  ; margin_end = Widget.get_margin_end w
  ; margin_top = Widget.get_margin_top w
  ; margin_bottom = Widget.get_margin_bottom w
  ; halign = Widget.get_halign w
  ; valign = Widget.get_valign w
  ; hexpand = Widget.get_hexpand w
  ; vexpand = Widget.get_vexpand w
  ; sensitive = Widget.get_sensitive w
  ; visible = Widget.get_visible w
  ; tooltip = Widget.get_tooltip_text w
  ; size_request = Widget.get_size_request w
  ; opacity = Widget.get_opacity w
  ; focusable = Widget.get_focusable w
  ; can_focus = Widget.get_can_focus w
  ; widget_name = Widget.get_name w
  ; cursor = Widget.get_cursor w
  }
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
  match (attr :> Attr.Private.t) with
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
  | Opacity f -> Widget.set_opacity w f
  | Focusable b -> Widget.set_focusable w b
  | Can_focus b -> Widget.set_can_focus w b
  | Widget_name s -> Widget.set_name w s
  | Cursor_name s -> Widget.set_cursor_from_name w (Some s)
  (* [Test_id] is inert at runtime; the [On_*] attrs are handled by [Signals]. [Many] is
     flattened away by [Attrs.of_list] and never reaches here.

     The controller attrs ([On_click], [On_focus_enter], [On_focus_leave],
     [On_key_pressed], [On_key_released]) are inert here for a different reason again:
     they are not a property of the widget at all but a [GtkEventController] attached to
     it, created and removed by [Controllers] straight from the node's attrs.

     [Measure_overlay], [Grid_cell] and [Page_title] are the container-placement attrs: a
     setting the *parent* holds about this child (an overlay's measure flag, a grid cell,
     a stack page's title), which no property of the child widget corresponds to. The
     parent's impl reads it off the child node through [Widget_impl.list_ops], so it is
     inert here by construction rather than by omission -- and inert, rather than an
     error, on a widget whose parent is not the container that reads it. *)
  | Test_id _
  | Measure_overlay _
  | Grid_cell _
  | Page_title _
  | On_click _
  | On_focus_enter _
  | On_focus_leave _
  | On_key_pressed _
  | On_key_released _
  | On_clicked _
  | On_toggled _
  | On_changed _
  | On_activate _
  | On_search_changed _
  | On_value_changed _
  | On_expanded_changed _
  | On_revealed _
  | On_position_changed _
  | On_visible_child_changed _
  | Many _ -> ()
;;

(* Put back the value this widget was created with, not a constant. *)
let unset (d : defaults) (w : Widget.t) (name : Attr.Name.t) =
  match name with
  | Margin_start -> Widget.set_margin_start w d.margin_start
  | Margin_end -> Widget.set_margin_end w d.margin_end
  | Margin_top -> Widget.set_margin_top w d.margin_top
  | Margin_bottom -> Widget.set_margin_bottom w d.margin_bottom
  | Halign -> Widget.set_halign w d.halign
  | Valign -> Widget.set_valign w d.valign
  | Hexpand -> Widget.set_hexpand w d.hexpand
  | Vexpand -> Widget.set_vexpand w d.vexpand
  | Sensitive -> Widget.set_sensitive w d.sensitive
  | Visible -> Widget.set_visible w d.visible
  | Tooltip -> Widget.set_tooltip_text w d.tooltip
  | Width_request -> set_width w (fst d.size_request)
  | Height_request -> set_height w (snd d.size_request)
  | Opacity -> Widget.set_opacity w d.opacity
  | Focusable -> Widget.set_focusable w d.focusable
  | Can_focus -> Widget.set_can_focus w d.can_focus
  | Widget_name -> Widget.set_name w d.widget_name
  | Cursor_name -> Widget.set_cursor w d.cursor
  | Test_id
  | Measure_overlay
  | Grid_cell
  | Page_title
  (* The controller attrs are [Controllers]' business, not a property of the widget:
     unsetting one removes a controller, which [Controllers.update] does from the attrs
     themselves rather than from an op. *)
  | On_click
  | On_focus_enter
  | On_focus_leave
  | On_key_pressed
  | On_key_released
  | On_clicked
  | On_toggled
  | On_changed
  | On_activate
  | On_search_changed
  | On_value_changed
  | On_expanded_changed
  | On_revealed
  | On_position_changed
  | On_visible_child_changed -> ()
;;

let apply ~defaults w (op : Attrs.op) =
  match op with
  | Set a -> set w a
  | Unset n -> unset defaults w n
  | Add_css_class c -> Widget.add_css_class w c
  | Remove_css_class c -> Widget.remove_css_class w c
;;

let apply_all w attrs = List.iter (Attrs.to_list attrs) ~f:(set w)
