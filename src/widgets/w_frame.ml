open! Core
open Bonsai_gtk_vtree
open Gtk_import

let impl : Widget_impl.t =
  { name = "Frame"
  ; create =
      (fun (kind : Kind.t) ->
        match kind with
        | Frame p ->
          (* [new_] takes the label, so only the alignment is left to set -- and only when
             it is not GTK's own, which keeps a plain frame free of writes. *)
          let f = W.Frame.new_ p.label in
          if Float.( <> ) p.label_align 0. then W.Frame.set_label_align f p.label_align;
          (f :> Widget.t)
        | k -> Widget_impl.wrong_kind "Frame" k)
  ; update =
      (fun w ~(old : Kind.t) (new_ : Kind.t) ->
        match old, new_ with
        | Frame old, Frame new_ ->
          let f : W.Frame.t = cast w in
          Widget_impl.batch w (fun () ->
            if not (Option.equal String.equal old.label new_.label)
            then W.Frame.set_label f new_.label;
            if Float.( <> ) old.label_align new_.label_align
            then W.Frame.set_label_align f new_.label_align)
        | _, k -> Widget_impl.wrong_kind "Frame" k)
  ; reassert = None
  ; signals = []
  ; children =
      Widget_impl.Single { set = (fun w child -> W.Frame.set_child (cast w) child) }
  }
;;
