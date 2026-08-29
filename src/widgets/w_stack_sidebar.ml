open! Core
open Bonsai_gtk_vtree
open Gtk_import

(* As [W_stack_switcher.attach], but [gtk_stack_sidebar_set_stack] is not nullable: a
   sidebar cannot be pointed at nothing, only at another stack. *)
let attach (sidebar : Widget.t) (stack : Widget.t) =
  W.Stack_sidebar.set_stack (cast sidebar) (cast stack)
;;

let impl : Widget_impl.t =
  { name = "StackSidebar"
  ; create =
      (fun (kind : Kind.t) ->
        match kind with
        | Stack_sidebar _ -> (W.Stack_sidebar.new_ () :> Widget.t)
        | k -> Widget_impl.wrong_kind "StackSidebar" k)
  ; update =
      (fun _w ~(old : Kind.t) (new_ : Kind.t) ->
        match old, new_ with
        | Stack_sidebar _, Stack_sidebar _ -> ()
        | _, k -> Widget_impl.wrong_kind "StackSidebar" k)
  ; reassert = None
  ; signals = []
  ; children = Widget_impl.No_children
  }
;;
