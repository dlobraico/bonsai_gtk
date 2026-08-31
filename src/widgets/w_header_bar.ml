open! Core
open Bonsai_gtk_vtree
open Gtk_import

(* Pure structure: [GtkHeaderBar] declares no signals, and its one non-slot surface is the
   two props below. The title is a {i slot} ([set_title_widget]), not a prop -- GTK4's
   header bar has no title-string setter, and with no title widget it shows the window's
   title; see [Node.header_bar].

   The two pack areas have no reorder primitive and no insert-at-position: children stack
   in the order packed, so [after] is unusable, [move] is [None]
   ([Reconcile.diff ~ordered:false] emits no [Move]), and keys preserve identity rather
   than order -- [w_overlay.ml]'s bargain, stated on the constructor. [remove] is
   slot-agnostic in GTK, which is why one [remove] serves both areas.

   [set_use_native_controls] (the macOS "stoplight" buttons; a no-op on Linux) is
   deliberately not exposed: it is platform chrome no model should hold. *)
let impl : Widget_impl.t =
  { name = "HeaderBar"
  ; create =
      (fun (kind : Kind.t) ->
        match kind with
        | Header_bar p ->
          let hb = W.Header_bar.new_ () in
          let w = (hb :> Widget.t) in
          Widget_impl.batch w (fun () ->
            if not p.show_title_buttons then W.Header_bar.set_show_title_buttons hb false;
            if Option.is_some p.decoration_layout
            then W.Header_bar.set_decoration_layout hb p.decoration_layout);
          w
        | k -> Widget_impl.wrong_kind "HeaderBar" k)
  ; update =
      (fun w ~(old : Kind.t) (new_ : Kind.t) ->
        match old, new_ with
        | Header_bar old, Header_bar new_ ->
          let hb : W.Header_bar.t = cast w in
          Widget_impl.batch w (fun () ->
            if not (Bool.equal old.show_title_buttons new_.show_title_buttons)
            then W.Header_bar.set_show_title_buttons hb new_.show_title_buttons;
            if not
                 (Option.equal String.equal old.decoration_layout new_.decoration_layout)
            then
              (* The setter is nullable, so dropping the argument really unsets: back to
                 the desktop's own layout rather than a remembered string. *)
              W.Header_bar.set_decoration_layout hb new_.decoration_layout)
        | _, k -> Widget_impl.wrong_kind "HeaderBar" k)
  ; reassert = None
  ; signals = []
  ; children =
      Widget_impl.Slots
        [ ( "title"
          , Slot_single { set = (fun w c -> W.Header_bar.set_title_widget (cast w) c) } )
        ; ( "start"
          , Slot_list
              { insert =
                  (fun parent ~after:_ ~node:_ child ->
                    W.Header_bar.pack_start (cast parent) child)
              ; move = None
              ; remove = (fun parent child -> W.Header_bar.remove (cast parent) child)
              ; updated = (fun _parent ~old:_ ~node:_ _child -> ())
              } )
        ; ( "end"
          , Slot_list
              { insert =
                  (fun parent ~after:_ ~node:_ child ->
                    W.Header_bar.pack_end (cast parent) child)
              ; move = None
              ; remove = (fun parent child -> W.Header_bar.remove (cast parent) child)
              ; updated = (fun _parent ~old:_ ~node:_ _child -> ())
              } )
        ]
  }
;;
