open! Core
open Bonsai_gtk_vtree
open Gtk_import

let orientation : Orientation.t -> Gtk_enums.orientation = function
  | Horizontal -> `HORIZONTAL
  | Vertical -> `VERTICAL
;;

(* [GtkPaned] has no "the user moved the handle" signal -- the drag is continuous and the
   property is the only record of it -- so this is [notify::position], read back off the
   widget (spec 6.4). It is informative, not the write-back half of a controlled prop:
   [position] is the documented exception to spec 6.5, so nothing here corrects the widget
   and a paned that carries no handler is not broken. *)
let position_changed : Signals.spec =
  { attr = Attr.Name.On_position_changed
  ; connect = Signals.notify ~prop:"position"
  ; fire =
      (fun w attr ->
        match (attr :> Attr.Private.t) with
        | On_position_changed handler -> Some (handler (W.Paned.get_position (cast w)))
        | _ -> None)
  }
;;

let impl : Widget_impl.t =
  { name = "Paned"
  ; create =
      (fun (kind : Kind.t) ->
        match kind with
        | Paned p ->
          let pane = W.Paned.new_ (orientation p.orientation) in
          let w = (pane :> Widget.t) in
          Widget_impl.batch w (fun () ->
            Option.iter p.position ~f:(W.Paned.set_position pane);
            W.Paned.set_wide_handle pane p.wide_handle;
            W.Paned.set_resize_start_child pane p.resize_start;
            W.Paned.set_resize_end_child pane p.resize_end;
            W.Paned.set_shrink_start_child pane p.shrink_start;
            W.Paned.set_shrink_end_child pane p.shrink_end);
          w
        | k -> Widget_impl.wrong_kind "Paned" k)
  ; update =
      (fun w ~(old : Kind.t) (new_ : Kind.t) ->
        match old, new_ with
        | Paned old, Paned new_ ->
          let pane : W.Paned.t = cast w in
          Widget_impl.batch w (fun () ->
            if not (Orientation.equal old.orientation new_.orientation)
            then
              W.Orientable.set_orientation
                (W.Orientable.from_gobject w)
                (orientation new_.orientation);
            (* Not controlled, and so written here rather than in [reassert]: the user
               drags the handle continuously, and re-asserting the position every frame
               would make it undraggable. Only an actual change in what the model asks for
               moves it. *)
            if not (Option.equal Int.equal old.position new_.position)
            then Option.iter new_.position ~f:(W.Paned.set_position pane);
            if not (Bool.equal old.wide_handle new_.wide_handle)
            then W.Paned.set_wide_handle pane new_.wide_handle;
            if not (Bool.equal old.resize_start new_.resize_start)
            then W.Paned.set_resize_start_child pane new_.resize_start;
            if not (Bool.equal old.resize_end new_.resize_end)
            then W.Paned.set_resize_end_child pane new_.resize_end;
            if not (Bool.equal old.shrink_start new_.shrink_start)
            then W.Paned.set_shrink_start_child pane new_.shrink_start;
            if not (Bool.equal old.shrink_end new_.shrink_end)
            then W.Paned.set_shrink_end_child pane new_.shrink_end)
        | _, k -> Widget_impl.wrong_kind "Paned" k)
  ; reassert = None
  ; signals = [ position_changed ]
  ; children =
      Widget_impl.Slots
        [ "start", Slot_single { set = (fun w c -> W.Paned.set_start_child (cast w) c) }
        ; "end", Slot_single { set = (fun w c -> W.Paned.set_end_child (cast w) c) }
        ]
  }
;;
