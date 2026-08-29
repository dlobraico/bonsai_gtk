open! Core
open Bonsai_gtk_vtree
open Gtk_import

let policy : Policy.t -> Gtk_enums.policytype = function
  | Always -> `ALWAYS
  | Automatic -> `AUTOMATIC
  | Never -> `NEVER
  | External_ -> `EXTERNAL
;;

(* [min_content_*] and [max_content_*] are one constraint spread over two properties:
   GTK's [set_min_content_width] asserts the new minimum is not above the maximum
   currently set, [set_max_content_width] asserts the mirror of that, and a failed
   assertion *drops the write* -- the widget keeps its old bound and only a Gtk-CRITICAL
   on stderr says so. So a fixed write order silently loses one of the two whenever the
   new pair sits entirely above or below the old one: bumping a window's bounds from
   80..300 up to 400..600 writes min=400 against a max still at 300, and the minimum never
   lands.

   Move whichever bound is in the way first: the maximum, when the new minimum is above
   the maximum currently set; the minimum otherwise. [-1] is GTK's "unset" and asserts
   against nothing, which is why the sentinel is checked rather than compared. Creation
   needs none of this -- a fresh [GtkScrolledWindow] has both bounds unset. *)
let set_bounds ~set_min ~set_max ~old_min ~old_max ~new_min ~new_max =
  let write_min () = if old_min <> new_min then set_min new_min in
  let write_max () = if old_max <> new_max then set_max new_max in
  if new_min >= 0 && old_max >= 0 && new_min > old_max
  then (
    write_max ();
    write_min ())
  else (
    write_min ();
    write_max ())
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
            set_bounds
              ~set_min:(W.Scrolled_window.set_min_content_width s)
              ~set_max:(W.Scrolled_window.set_max_content_width s)
              ~old_min:old.min_content_width
              ~old_max:old.max_content_width
              ~new_min:new_.min_content_width
              ~new_max:new_.max_content_width;
            set_bounds
              ~set_min:(W.Scrolled_window.set_min_content_height s)
              ~set_max:(W.Scrolled_window.set_max_content_height s)
              ~old_min:old.min_content_height
              ~old_max:old.max_content_height
              ~new_min:new_.min_content_height
              ~new_max:new_.max_content_height;
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
