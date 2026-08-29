open! Core

type t =
  { kind : Kind.t
  ; key : Key.t option [@sexp.option]
  ; attrs : Attrs.t
  ; children : t Children.t
  }
[@@deriving sexp_of]

(** A [GtkLabel]. Every optional property defaults to GTK's own default, so a label built
    from text alone is a plain [GtkLabel].

    [xalign] is horizontal alignment of the text {i within} the label's allocation ([0.]
    left, [0.5] centred, [1.] right) — distinct from [Attr.halign], which places the label
    within its parent. [ellipsize] absent means "do not ellipsize". [max_width_chars] and
    [width_chars] are [-1] for "no request". [use_markup] parses the text as Pango markup;
    malformed markup is GTK's problem — it logs and shows the raw string. *)
val label
  :  ?key:Key.t
  -> ?attrs:Attr.t list
  -> ?wrap:bool
  -> ?xalign:float
  -> ?ellipsize:Ellipsize.t
  -> ?max_width_chars:int
  -> ?width_chars:int
  -> ?selectable:bool
  -> ?use_markup:bool
  -> string
  -> t

val button : ?key:Key.t -> ?attrs:Attr.t list -> ?label:string -> unit -> t

val box
  :  ?key:Key.t
  -> ?attrs:Attr.t list
  -> ?spacing:int
  -> ?homogeneous:bool
  -> orientation:Orientation.t
  -> t list
  -> t

val window
  :  ?key:Key.t
  -> ?attrs:Attr.t list
  -> ?title:string
  -> ?default_size:int * int
  -> t
  -> t

val native : ?key:Key.t -> ?attrs:Attr.t list -> Native.t -> t

(** Depth-first search for a node whose attrs carry [Test_id id]. *)
val find_by_test_id : t -> string -> t option
