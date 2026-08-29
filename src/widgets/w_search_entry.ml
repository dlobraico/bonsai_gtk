open! Core
open Bonsai_gtk_vtree
open Gtk_import

(* GTK's debounced signal, emitted [search_delay] ms after typing stops. It is the search
   entry's own; [changed] (immediate) reaches it through [GtkEditable] like the other two
   entries, and both are connected — see [Node.search_entry]'s doc for which to use. *)
let search_changed : Signals.spec =
  { attr = Attr.Name.On_search_changed
  ; connect = (fun w ~callback -> W.Search_entry.on_search_changed (cast w) ~callback)
  ; fire =
      (fun w (attr : Attr.t) ->
        match attr with
        | On_search_changed handler ->
          Some (handler (W.Editable.get_text (W_entry.editable w)))
        | _ -> None)
  }
;;

let impl : Widget_impl.t =
  { name = "SearchEntry"
  ; create =
      (fun (kind : Kind.t) ->
        match kind with
        | Search_entry p ->
          let e = W.Search_entry.new_ () in
          let w = (e :> Widget.t) in
          Widget_impl.batch w (fun () ->
            (* As in [w_entry.ml]: writing [None] builds an empty placeholder label. *)
            Option.iter p.placeholder ~f:(fun t ->
              W.Search_entry.set_placeholder_text e (Some t));
            Option.iter p.search_delay ~f:(W.Search_entry.set_search_delay e);
            W_entry.set_text_if_needed (W_entry.editable w) p.text);
          w
        | k -> Widget_impl.wrong_kind "SearchEntry" k)
  ; update =
      (fun w ~(old : Kind.t) (new_ : Kind.t) ->
        match old, new_ with
        | Search_entry old, Search_entry new_ ->
          let e : W.Search_entry.t = cast w in
          Widget_impl.batch w (fun () ->
            if not (Option.equal String.equal old.placeholder new_.placeholder)
            then W.Search_entry.set_placeholder_text e new_.placeholder;
            (* [None] means "leave GTK's own 150 ms alone", so going from [Some] back to
               [None] writes nothing rather than guessing a value to restore. *)
            if not (Option.equal Int.equal old.search_delay new_.search_delay)
            then Option.iter new_.search_delay ~f:(W.Search_entry.set_search_delay e))
          (* [text] is controlled: see [reassert]. *)
        | _, k -> Widget_impl.wrong_kind "SearchEntry" k)
  ; reassert =
      Some
        (fun w (kind : Kind.t) ->
          match kind with
          | Search_entry p ->
            Widget_impl.batch w (fun () ->
              W_entry.set_text_if_needed (W_entry.editable w) p.text)
          | k -> Widget_impl.wrong_kind "SearchEntry" k)
  ; signals =
      [ W_entry.changed
      ; search_changed
      ; W_entry.activate ~connect:(fun w ~callback ->
          W.Search_entry.on_activate (cast w) ~callback)
      ]
  ; children = Widget_impl.No_children
  }
;;
