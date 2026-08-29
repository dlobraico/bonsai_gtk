open! Core
open Bonsai_gtk_vtree
open Gtk_import

let policy : Policy.t -> Gtk_enums.policytype = function
  | Always -> `ALWAYS
  | Automatic -> `AUTOMATIC
  | Never -> `NEVER
  | External_ -> `EXTERNAL
;;

(* Nothing here is controlled: a scrolled window's only user-driven state is its scroll
   position, which is deliberately not a prop (see the mli). *)
let impl : Widget_impl.t =
  { name = "ScrolledWindow"
  ; create =
      (fun (kind : Kind.t) ->
        match kind with
        | Scrolled_window p ->
          let s = W.Scrolled_window.new_ () in
          let w = (s :> Widget.t) in
          Widget_impl.batch w (fun () ->
            W.Scrolled_window.set_policy s (policy p.hpolicy) (policy p.vpolicy);
            W.Scrolled_window.set_min_content_width s p.min_content_width;
            W.Scrolled_window.set_min_content_height s p.min_content_height;
            W.Scrolled_window.set_max_content_width s p.max_content_width;
            W.Scrolled_window.set_max_content_height s p.max_content_height;
            W.Scrolled_window.set_propagate_natural_width s p.propagate_natural_width;
            W.Scrolled_window.set_propagate_natural_height s p.propagate_natural_height;
            W.Scrolled_window.set_has_frame s p.has_frame;
            W.Scrolled_window.set_kinetic_scrolling s p.kinetic_scrolling;
            W.Scrolled_window.set_overlay_scrolling s p.overlay_scrolling);
          w
        | k -> Widget_impl.wrong_kind "ScrolledWindow" k)
  ; update =
      (fun w ~(old : Kind.t) (new_ : Kind.t) ->
        match old, new_ with
        | Scrolled_window old, Scrolled_window new_ ->
          let s : W.Scrolled_window.t = cast w in
          Widget_impl.batch w (fun () ->
            (* GTK sets both policies in one call, so either one changing rewrites both. *)
            if not
                 (Policy.equal old.hpolicy new_.hpolicy
                  && Policy.equal old.vpolicy new_.vpolicy)
            then
              W.Scrolled_window.set_policy s (policy new_.hpolicy) (policy new_.vpolicy);
            if old.min_content_width <> new_.min_content_width
            then W.Scrolled_window.set_min_content_width s new_.min_content_width;
            if old.min_content_height <> new_.min_content_height
            then W.Scrolled_window.set_min_content_height s new_.min_content_height;
            if old.max_content_width <> new_.max_content_width
            then W.Scrolled_window.set_max_content_width s new_.max_content_width;
            if old.max_content_height <> new_.max_content_height
            then W.Scrolled_window.set_max_content_height s new_.max_content_height;
            if not (Bool.equal old.propagate_natural_width new_.propagate_natural_width)
            then
              W.Scrolled_window.set_propagate_natural_width s new_.propagate_natural_width;
            if not (Bool.equal old.propagate_natural_height new_.propagate_natural_height)
            then
              W.Scrolled_window.set_propagate_natural_height
                s
                new_.propagate_natural_height;
            if not (Bool.equal old.has_frame new_.has_frame)
            then W.Scrolled_window.set_has_frame s new_.has_frame;
            if not (Bool.equal old.kinetic_scrolling new_.kinetic_scrolling)
            then W.Scrolled_window.set_kinetic_scrolling s new_.kinetic_scrolling;
            if not (Bool.equal old.overlay_scrolling new_.overlay_scrolling)
            then W.Scrolled_window.set_overlay_scrolling s new_.overlay_scrolling)
        | _, k -> Widget_impl.wrong_kind "ScrolledWindow" k)
  ; reassert = None
  ; signals = []
  ; children =
      Widget_impl.Single
        { set = (fun w child -> W.Scrolled_window.set_child (cast w) child) }
  }
;;
