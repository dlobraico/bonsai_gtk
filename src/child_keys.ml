open! Core
open Bonsai_gtk_vtree
open Gtk_import

(* [Gobject.same] is pointer identity on the underlying GObject; [==] on two OCaml values
   wrapping one GObject is always false, because each extraction allocates its own custom
   block. The hash is the custom block's, which ocgtk installs as a pointer hash -- so
   [Stdlib.Hashtbl.hash] and [Gobject.same] agree, which is what a hash table needs. The
   same pair is what [w_search_entry.ml]'s [Echo] table is built on. *)
module Table = Stdlib.Ephemeron.K1.Make (struct
    type t = Widget.t

    let equal = Gobject.same
    let hash = Stdlib.Hashtbl.hash
  end)

type t = Key.t Table.t

let create () = Table.create 8
let set t widget key = Table.replace t widget key
let remove t widget = Table.remove t widget
let find t widget = Table.find_opt t widget

let find_exn t widget ~what =
  match Table.find_opt t widget with
  | Some key -> key
  | None ->
    invalid_argf
      "%s: this %s was not made by this library (its key was never recorded)"
      (type_name widget)
      what
      ()
;;

(* [clean] first, so the answer counts {i live} bindings deterministically: an ephemeron
   table's [length] includes bindings whose key has died but not yet been swept, and
   "after the next GC, eventually" is not a number a test can assert on. *)
let length t =
  Table.clean t;
  Table.length t
;;
