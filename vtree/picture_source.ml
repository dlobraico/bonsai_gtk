open! Core

(** Where a [Node.picture] gets its image. A [GdkPaintable] source -- a texture the
    application rendered -- is not here: the vtree may not mention ocgtk types. Use
    [Bonsai_gtk.Native.Picture] for that. *)
type t =
  | Empty
  | Filename of string
  | Resource of string
[@@deriving sexp_of, equal, compare]
