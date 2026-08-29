open! Core
open Bonsai_gtk_vtree
open Gtk_import

(* Called from the patcher's fixup pass, once the named stack is known to exist. It lives
   here rather than in the patcher so the patcher stays widget-agnostic. *)
let attach (switcher : Widget.t) (stack : Widget.t) =
  W.Stack_switcher.set_stack (cast switcher) (Some (cast stack))
;;

let impl : Widget_impl.t =
  { name = "StackSwitcher"
  ; create =
      (fun (kind : Kind.t) ->
        match kind with
        (* The stack is wired up by a fixup after the pass, not here: the stack may be
           mounted after this switcher, and often is -- a switcher above the stack it
           drives is the ordinary layout. *)
        | Stack_switcher _ -> (W.Stack_switcher.new_ () :> Widget.t)
        | k -> Widget_impl.wrong_kind "StackSwitcher" k)
  ; update =
      (fun _w ~(old : Kind.t) (new_ : Kind.t) ->
        match old, new_ with
        (* Re-pointing at a different stack is also a fixup; nothing to do inline. *)
        | Stack_switcher _, Stack_switcher _ -> ()
        | _, k -> Widget_impl.wrong_kind "StackSwitcher" k)
  ; reassert = None
  ; signals = []
  ; children = Widget_impl.No_children
  }
;;
