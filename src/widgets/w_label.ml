open! Core
open Bonsai_gtk_vtree
open Gtk_import

let impl : Widget_impl.t =
  { name = "Label"
  ; create =
      (fun (kind : Kind.t) ->
        match kind with
        | Label { text } -> (W.Label.new_ (Some text) :> Widget.t)
        | k -> Widget_impl.wrong_kind "Label" k)
  ; update =
      (fun w ~(old : Kind.t) (new_ : Kind.t) ->
        match old, new_ with
        | Label { text = old_text }, Label { text = new_text } ->
          if not (String.equal old_text new_text) then W.Label.set_text (cast w) new_text
        | _, k -> Widget_impl.wrong_kind "Label" k)
  ; signals = []
  ; children = Widget_impl.No_children
  }
;;
