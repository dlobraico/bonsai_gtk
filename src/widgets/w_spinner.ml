open! Core
open Bonsai_gtk_vtree
open Gtk_import

(* [spinning] is the whole of a spinner, and it is not controlled: the animation is GTK's
   own and the user cannot change it, so an ordinary diffed write is all it needs. *)
let impl : Widget_impl.t =
  { name = "Spinner"
  ; create =
      (fun (kind : Kind.t) ->
        match kind with
        | Spinner { spinning } ->
          let s = W.Spinner.new_ () in
          W.Spinner.set_spinning s spinning;
          (s :> Widget.t)
        | k -> Widget_impl.wrong_kind "Spinner" k)
  ; update =
      (fun w ~(old : Kind.t) (new_ : Kind.t) ->
        match old, new_ with
        | Spinner old, Spinner new_ ->
          if not (Bool.equal old.spinning new_.spinning)
          then W.Spinner.set_spinning (cast w) new_.spinning
        | _, k -> Widget_impl.wrong_kind "Spinner" k)
  ; reassert = None
  ; signals = []
  ; children = Widget_impl.No_children
  }
;;
