open! Core
open Bonsai_gtk_vtree
open Gtk_import

(* Not private to this module: [Paintable_picture], the native paintable-backed picture,
   maps the same enum. *)
let content_fit : Content_fit.t -> Gtk_enums.contentfit = function
  | Fill -> `FILL
  | Contain -> `CONTAIN
  | Cover -> `COVER
  | Scale_down -> `SCALE_DOWN
;;

(* Same rule as [W_image.set_source]: [Empty] goes through a setter that actually clears,
   which for GtkPicture is [set_paintable None] (there is no [clear]). *)
let set_source (p : W.Picture.t) (source : Picture_source.t) =
  match source with
  | Empty -> W.Picture.set_paintable p None
  | Filename path -> W.Picture.set_filename p (Some path)
  | Resource path -> W.Picture.set_resource p (Some path)
;;

let apply_props (p : W.Picture.t) ~content_fit:cf ~can_shrink ~alternative_text =
  W.Picture.set_content_fit p (content_fit cf);
  W.Picture.set_can_shrink p can_shrink;
  W.Picture.set_alternative_text p alternative_text
;;

let impl : Widget_impl.t =
  { name = "Picture"
  ; create =
      (fun (kind : Kind.t) ->
        match kind with
        | Picture props ->
          let p = W.Picture.new_ () in
          let w = (p :> Widget.t) in
          Widget_impl.batch w (fun () ->
            set_source p props.source;
            apply_props
              p
              ~content_fit:props.content_fit
              ~can_shrink:props.can_shrink
              ~alternative_text:props.alternative_text);
          w
        | k -> Widget_impl.wrong_kind "Picture" k)
  ; update =
      (fun w ~(old : Kind.t) (new_ : Kind.t) ->
        match old, new_ with
        | Picture old, Picture new_ ->
          let p : W.Picture.t = cast w in
          Widget_impl.batch w (fun () ->
            if not (Picture_source.equal old.source new_.source)
            then set_source p new_.source;
            if not (Content_fit.equal old.content_fit new_.content_fit)
            then W.Picture.set_content_fit p (content_fit new_.content_fit);
            if not (Bool.equal old.can_shrink new_.can_shrink)
            then W.Picture.set_can_shrink p new_.can_shrink;
            if not (Option.equal String.equal old.alternative_text new_.alternative_text)
            then W.Picture.set_alternative_text p new_.alternative_text)
        | _, k -> Widget_impl.wrong_kind "Picture" k)
  ; reassert = None
  ; signals = []
  ; children = Widget_impl.No_children
  }
;;
