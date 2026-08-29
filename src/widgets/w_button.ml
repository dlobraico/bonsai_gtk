open! Core
open Bonsai_gtk_vtree
open Gtk_import

let clicked : Signals.spec =
  { attr = Attr.Name.On_clicked
  ; connect = (fun w ~callback -> W.Button.on_clicked (cast w) ~callback)
  ; fire =
      (fun (attr : Attr.t) ->
        match attr with
        | On_clicked handler -> Some (handler ())
        | _ -> None)
  }
;;

let impl : Widget_impl.t =
  { name = "Button"
  ; create =
      (fun (kind : Kind.t) ->
        match kind with
        | Button { label = Some label } -> (W.Button.new_with_label label :> Widget.t)
        | Button { label = None } -> (W.Button.new_ () :> Widget.t)
        | k -> Widget_impl.wrong_kind "Button" k)
  ; update =
      (fun w ~(old : Kind.t) (new_ : Kind.t) ->
        match old, new_ with
        | Button { label = old_label }, Button { label = new_label } ->
          if not (Option.equal String.equal old_label new_label)
          then
            (* GTK has no "unset label"; [set_label ""] is the closest thing, and it is
               what a [None] label renders as anyway. *)
            W.Button.set_label (cast w) (Option.value new_label ~default:"")
        | _, k -> Widget_impl.wrong_kind "Button" k)
  ; signals = [ clicked ]
  ; children = Widget_impl.No_children
  }
;;
