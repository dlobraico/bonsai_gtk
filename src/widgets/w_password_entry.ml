open! Core
open Bonsai_gtk_vtree
open Gtk_import

let impl : Widget_impl.t =
  { name = "PasswordEntry"
  ; create =
      (fun (kind : Kind.t) ->
        match kind with
        | Password_entry p ->
          let e = W.Password_entry.new_ () in
          let w = (e :> Widget.t) in
          Widget_impl.batch w (fun () ->
            (* The setter is nullable as of the pin this repository now tracks, the same
               as [GtkEntry]'s and [GtkSearchEntry]'s — but both paths here keep writing
               [Some _], and the update path below keeps writing [Some ""]. Taking the
               actual benefit is a separate, deliberate change, and it would have no
               visible effect on this widget in any case: GTK normalises the NULL back to
               [""] once the internal [GtkText] exists (measured on 4.22). As before, an
               absent placeholder is simply not written. *)
            Option.iter p.placeholder ~f:(fun t ->
              W.Password_entry.set_placeholder_text e (Some t));
            if not p.show_peek_icon then W.Password_entry.set_show_peek_icon e false;
            if p.activates_default then W.Password_entry.set_activates_default e true;
            ignore (W_entry.set_text_if_needed (W_entry.editable w) p.text : bool));
          w
        | k -> Widget_impl.wrong_kind "PasswordEntry" k)
  ; update =
      (fun w ~(old : Kind.t) (new_ : Kind.t) ->
        match old, new_ with
        | Password_entry old, Password_entry new_ ->
          let e : W.Password_entry.t = cast w in
          Widget_impl.batch w (fun () ->
            if not (Option.equal String.equal old.placeholder new_.placeholder)
            then
              W.Password_entry.set_placeholder_text
                e
                (Some (Option.value new_.placeholder ~default:""));
            if not (Bool.equal old.show_peek_icon new_.show_peek_icon)
            then W.Password_entry.set_show_peek_icon e new_.show_peek_icon;
            if not (Bool.equal old.activates_default new_.activates_default)
            then W.Password_entry.set_activates_default e new_.activates_default)
          (* [text] is controlled: see [reassert]. *)
        | _, k -> Widget_impl.wrong_kind "PasswordEntry" k)
  ; reassert =
      Some
        (fun w (kind : Kind.t) ->
          match kind with
          | Password_entry p ->
            let e = W_entry.editable w in
            let writes = W_entry.needs_text e p.text in
            Widget_impl.batch_if writes w (fun () ->
              if writes then ignore (W_entry.set_text_if_needed e p.text : bool))
          | k -> Widget_impl.wrong_kind "PasswordEntry" k)
  ; signals =
      [ W_entry.changed
      ; W_entry.activate ~connect:(fun w ~callback ->
          [ Signals.connected w (W.Password_entry.on_activate (cast w) ~callback) ])
      ]
  ; children = Widget_impl.No_children
  }
;;
