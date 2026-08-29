open! Core
open Bonsai_gtk_vtree
open Gtk_import

let ellipsize : Ellipsize.t option -> Ocgtk_pango.Pango.ellipsizemode = function
  | None -> `NONE
  | Some Start -> `START
  | Some Middle -> `MIDDLE
  | Some End -> `END
;;

(* Nothing here is controlled and nothing emits: a progress bar has no user input to
   decline, so [reassert] is [None] and [fraction] is an ordinary diffed prop. *)
let impl : Widget_impl.t =
  { name = "ProgressBar"
  ; create =
      (fun (kind : Kind.t) ->
        match kind with
        | Progress_bar p ->
          let b = W.Progress_bar.new_ () in
          let w = (b :> Widget.t) in
          Widget_impl.batch w (fun () ->
            W.Progress_bar.set_fraction b p.fraction;
            (* [None] is GTK's own "show the percentage instead", and is what the setter
               takes, so unlike the entries' placeholder this needs no [Option.iter]. *)
            W.Progress_bar.set_text b p.text;
            W.Progress_bar.set_show_text b p.show_text;
            if p.inverted then W.Progress_bar.set_inverted b true;
            W.Progress_bar.set_ellipsize b (ellipsize p.ellipsize));
          w
        | k -> Widget_impl.wrong_kind "ProgressBar" k)
  ; update =
      (fun w ~(old : Kind.t) (new_ : Kind.t) ->
        match old, new_ with
        | Progress_bar old, Progress_bar new_ ->
          let b : W.Progress_bar.t = cast w in
          Widget_impl.batch w (fun () ->
            if Float.( <> ) old.fraction new_.fraction
            then W.Progress_bar.set_fraction b new_.fraction;
            if not (Option.equal String.equal old.text new_.text)
            then W.Progress_bar.set_text b new_.text;
            if not (Bool.equal old.show_text new_.show_text)
            then W.Progress_bar.set_show_text b new_.show_text;
            if not (Bool.equal old.inverted new_.inverted)
            then W.Progress_bar.set_inverted b new_.inverted;
            if not (Option.equal Ellipsize.equal old.ellipsize new_.ellipsize)
            then W.Progress_bar.set_ellipsize b (ellipsize new_.ellipsize))
        | _, k -> Widget_impl.wrong_kind "ProgressBar" k)
  ; reassert = None
  ; signals = []
  ; children = Widget_impl.No_children
  }
;;
