open! Core
open Bonsai_gtk_vtree
open Gtk_import

let impl : Widget_impl.t =
  { name = "Window"
  ; create =
      (fun (kind : Kind.t) ->
        match kind with
        | Window { title; default_size } ->
          let window = W.Window.new_ () in
          Widget_impl.batch
            (window :> Widget.t)
            (fun () ->
              W.Window.set_title window title;
              Option.iter default_size ~f:(fun (width, height) ->
                W.Window.set_default_size window width height));
          (window :> Widget.t)
        | k -> Widget_impl.wrong_kind "Window" k)
  ; update =
      (fun w ~(old : Kind.t) (new_ : Kind.t) ->
        match old, new_ with
        | Window old, Window new_ ->
          Widget_impl.batch w (fun () ->
            if not (Option.equal String.equal old.title new_.title)
            then W.Window.set_title (cast w) new_.title;
            (* GTK has no way to clear a default size, so [None] leaves the current one
               alone rather than fighting the window manager. *)
            match new_.default_size with
            | Some (width, height)
              when not
                     (Option.equal [%equal: int * int] old.default_size new_.default_size)
              -> W.Window.set_default_size (cast w) width height
            | _ -> ())
        | _, k -> Widget_impl.wrong_kind "Window" k)
  ; controlled = false
  ; signals = []
  ; children =
      Widget_impl.Single { set = (fun w child -> W.Window.set_child (cast w) child) }
  }
;;
