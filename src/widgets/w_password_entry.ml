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
            (* Unlike [GtkEntry]'s and [GtkSearchEntry]'s, this setter is not nullable —
               hence the [""] on the update path below. As there, an absent placeholder is
               simply not written. *)
            Option.iter p.placeholder ~f:(W.Password_entry.set_placeholder_text e);
            if not p.show_peek_icon then W.Password_entry.set_show_peek_icon e false;
            if p.activates_default then W.Password_entry.set_activates_default e true;
            W_entry.set_text_if_needed (W_entry.editable w) p.text);
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
                (Option.value new_.placeholder ~default:"");
            if not (Bool.equal old.show_peek_icon new_.show_peek_icon)
            then W.Password_entry.set_show_peek_icon e new_.show_peek_icon;
            if not (Bool.equal old.activates_default new_.activates_default)
            then W.Password_entry.set_activates_default e new_.activates_default;
            W_entry.set_text_if_needed (W_entry.editable w) new_.text)
        | _, k -> Widget_impl.wrong_kind "PasswordEntry" k)
  ; controlled = true
  ; signals =
      [ W_entry.changed
      ; W_entry.activate ~connect:(fun w ~callback ->
          W.Password_entry.on_activate (cast w) ~callback)
      ]
  ; children = Widget_impl.No_children
  }
;;
