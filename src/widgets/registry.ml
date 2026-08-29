open! Core
open Bonsai_gtk_vtree

let for_kind : Kind.t -> Widget_impl.t = function
  | Label _ -> W_label.impl
  | Button _ -> W_button.impl
  | Box _ -> W_box.impl
  | Window _ -> W_window.impl
  (* Task 10 replaces this with a lookup into the [Native] runtime table. *)
  | Native n -> invalid_argf "Native node %s: no runtime registered" n.name ()
;;
