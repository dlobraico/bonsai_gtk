open! Core
open Bonsai_gtk_vtree
open Gtk_import

let ellipsize : Ellipsize.t option -> Ocgtk_pango.Pango.ellipsizemode = function
  | None -> `NONE
  | Some Start -> `START
  | Some Middle -> `MIDDLE
  | Some End -> `END
;;

(* Only the props that differ are written: [set_text] and [set_markup] both reset the
   label's attribute list, and [set_ellipsize] forces a re-layout. [old = None] is the
   create path, where "differs" is true of everything. *)
let apply_props (l : W.Label.t) (p : Kind.label_props) ~(old : Kind.label_props option) =
  let changed field equal =
    match old with
    | None -> true
    | Some o -> not (equal (field o) (field p))
  in
  (* [use_markup] is not set directly: [set_markup] turns it on and [set_text] turns it
     off, so the text has to be rewritten whenever either half changes. *)
  if changed (fun p -> p.Kind.text) String.equal
     || changed (fun p -> p.Kind.use_markup) Bool.equal
  then if p.use_markup then W.Label.set_markup l p.text else W.Label.set_text l p.text;
  if changed (fun p -> p.Kind.wrap) Bool.equal then W.Label.set_wrap l p.wrap;
  if changed (fun p -> p.Kind.xalign) Float.equal then W.Label.set_xalign l p.xalign;
  if changed (fun p -> p.Kind.ellipsize) (Option.equal Ellipsize.equal)
  then W.Label.set_ellipsize l (ellipsize p.ellipsize);
  if changed (fun p -> p.Kind.max_width_chars) Int.equal
  then W.Label.set_max_width_chars l p.max_width_chars;
  if changed (fun p -> p.Kind.width_chars) Int.equal
  then W.Label.set_width_chars l p.width_chars;
  if changed (fun p -> p.Kind.selectable) Bool.equal
  then W.Label.set_selectable l p.selectable
;;

let impl : Widget_impl.t =
  { name = "Label"
  ; create =
      (fun (kind : Kind.t) ->
        match kind with
        | Label p ->
          let l = W.Label.new_ None in
          apply_props l p ~old:None;
          (l :> Widget.t)
        | k -> Widget_impl.wrong_kind "Label" k)
  ; update =
      (fun w ~(old : Kind.t) (new_ : Kind.t) ->
        match old, new_ with
        | Label old, Label new_ -> apply_props (cast w) new_ ~old:(Some old)
        | _, k -> Widget_impl.wrong_kind "Label" k)
  ; signals = []
  ; children = Widget_impl.No_children
  }
;;
