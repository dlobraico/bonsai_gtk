open! Core
open Bonsai_gtk_vtree
open Gtk_import

(* The windows root: a virtual node holding the keyed toplevels, whose widget is an
   {b anchor} -- a bare [GtkBox] that is never parented, never presented and never
   realized. It exists because [Patcher.live] requires a widget: with one, the shadow tree
   keeps its shape and the list machinery (keyed reconciliation, [Child_keys], the unwind
   paths) runs unmodified. The alternative -- making [Patcher.live.widget] optional --
   touches every line of the patcher for one kind's benefit, which is why the anchor was
   chosen (Task 8's design ruling).

   The [list_ops] parent nothing, and each no-op is load-bearing:
   - [insert] has nothing to do because the child window was created by its own mount and
     [ctx.on_window_created] is what presents it (under [Bonsai_gtk.start], the
     application adds and presents it; the anchor could not parent a toplevel anyway).
   - [remove] has nothing to do because a window has no parent to be removed from; the
     child's own teardown runs [release_kind]'s [W.Window.destroy], unchanged from M2.
   - [move = None] is the marker it is everywhere: toplevels have no z-order the
     application controls, so keys preserve identity and no [Move] is ever emitted. *)
let impl : Widget_impl.t =
  { name = "Windows"
  ; create =
      (fun (kind : Kind.t) ->
        match kind with
        | Windows -> (W.Box.new_ `VERTICAL 0 :> Widget.t)
        | k -> Widget_impl.wrong_kind "Windows" k)
  ; update =
      (fun _w ~old:_ (new_ : Kind.t) ->
        match new_ with
        | Windows -> ()
        | k -> Widget_impl.wrong_kind "Windows" k)
  ; reassert = None
  ; signals = []
  ; children =
      Widget_impl.List
        { insert = (fun _parent ~after:_ ~node:_ _child -> ())
        ; move = None
        ; remove = (fun _parent _child -> ())
        ; updated = (fun _parent ~old:_ ~node:_ _child -> ())
        }
  }
;;
