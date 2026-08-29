open! Core
open Bonsai_gtk_vtree
open Gtk_import

let icon_size : Icon_size.t -> Gtk_enums.iconsize = function
  | Inherit -> `INHERIT
  | Normal -> `NORMAL
  | Large -> `LARGE
;;

(* One call per source, and [clear] for [Empty]: GTK keeps whichever source was set last,
   so switching kinds has to go through the new kind's setter, and switching *to* nothing
   has to go through [clear] -- [set_from_icon_name w None] leaves a previously set file
   in place. *)
let set_source (i : W.Image.t) (source : Image_source.t) =
  match source with
  | Empty -> W.Image.clear i
  | Icon_name name -> W.Image.set_from_icon_name i (Some name)
  | File path -> W.Image.set_from_file i (Some path)
  | Resource path -> W.Image.set_from_resource i (Some path)
;;

(* Nothing here is controlled and nothing emits: an image has no user input to decline. *)
let impl : Widget_impl.t =
  { name = "Image"
  ; create =
      (fun (kind : Kind.t) ->
        match kind with
        | Image p ->
          let i = W.Image.new_ () in
          let w = (i :> Widget.t) in
          Widget_impl.batch w (fun () ->
            set_source i p.source;
            if p.pixel_size <> -1 then W.Image.set_pixel_size i p.pixel_size;
            W.Image.set_icon_size i (icon_size p.icon_size));
          w
        | k -> Widget_impl.wrong_kind "Image" k)
  ; update =
      (fun w ~(old : Kind.t) (new_ : Kind.t) ->
        match old, new_ with
        | Image old, Image new_ ->
          let i : W.Image.t = cast w in
          Widget_impl.batch w (fun () ->
            if not (Image_source.equal old.source new_.source)
            then set_source i new_.source;
            if old.pixel_size <> new_.pixel_size
            then W.Image.set_pixel_size i new_.pixel_size;
            if not (Icon_size.equal old.icon_size new_.icon_size)
            then W.Image.set_icon_size i (icon_size new_.icon_size))
        | _, k -> Widget_impl.wrong_kind "Image" k)
  ; reassert = None
  ; signals = []
  ; children = Widget_impl.No_children
  }
;;
