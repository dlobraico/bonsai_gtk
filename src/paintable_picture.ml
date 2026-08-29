open! Core
open Bonsai_gtk_vtree
open Gtk_import
module Paintable = Ocgtk_gdk.Gdk.Wrappers.Paintable

module Input = struct
  type t =
    { paintable : Paintable.t option
    ; content_fit : Content_fit.t
    ; can_shrink : bool
    }

  (* [Gobject.same] rather than [phys_equal]: every C-to-OCaml crossing allocates a fresh
     wrapper block for the same pointer, so two handles to one texture are never
     physically equal (spec §2.2). *)
  let same_paintable a b =
    match a, b with
    | None, None -> true
    | Some a, Some b -> Gobject.same a b
    | None, Some _ | Some _, None -> false
  ;;

  let equal a b =
    same_paintable a.paintable b.paintable
    && Content_fit.equal a.content_fit b.content_fit
    && Bool.equal a.can_shrink b.can_shrink
  ;;
end

module M = struct
  type input = Input.t

  let name = "picture(paintable)"

  let apply (p : W.Picture.t) (i : Input.t) =
    W.Picture.set_paintable p i.paintable;
    W.Picture.set_content_fit p (W_picture.content_fit i.content_fit);
    W.Picture.set_can_shrink p i.can_shrink
  ;;

  let create (i : Input.t) =
    let p = W.Picture.new_ () in
    apply p i;
    (p :> Widget.t)
  ;;

  (* [update] runs on every re-render, not only when the input changed (see
     [Native_gtk.S]'s doc comment): the patcher compares native payloads physically and a
     fresh payload is allocated each frame. Hence the explicit [Input.equal]. *)
  let update w ~old i = if not (Input.equal old i) then apply (cast w) i

  (* The widget's reference to the paintable is GTK's business; nothing was acquired here
     that outlives it. *)
  let destroy _ = ()
end

(* Built once, at the top level, as every [Native_gtk.impl] must be: the impl carries the
   type witness the patcher matches on, so one per render would be a different widget. *)
let impl = Native_gtk.impl (module M)

let node ?key ?attrs ?(content_fit = Content_fit.Contain) ?(can_shrink = true) paintable =
  Native_gtk.node ?key ?attrs impl { Input.paintable; content_fit; can_shrink }
;;
