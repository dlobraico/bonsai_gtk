open! Core
open Bonsai_gtk_vtree

(** A [GtkPicture] fed a [GdkPaintable] -- a texture the application rendered itself,
    typically a [Gdk.Memory_texture] built from pixels it owns.

    This is the library's own use of {!Bonsai_gtk.Native}: the input is an ocgtk value,
    and [bonsai_gtk.vtree] may not mention ocgtk types, so it cannot be a [Kind.t] and a
    [Node.picture] cannot take it. It is also the worked example to copy when an
    application needs a widget of its own.

    The paintable is compared with [Gobject.same], not [phys_equal]: ocgtk allocates a
    fresh wrapper for the same GObject on every crossing, so physical equality on these
    handles is always false. Keeping the {i same} texture across renders therefore costs
    nothing; building a new one each frame re-uploads it, which is the caller's decision
    to make.

    [None] shows nothing, and is how a paintable is taken back off the widget. The same
    sizing caveat as {!Bonsai_gtk_vtree.Node.picture}'s applies: a picture's natural size
    comes from its image, so capping the allocation means an unmeasured overlay over a
    sized spacer, with [~can_shrink:true ~content_fit:Contain]. *)
val node
  :  ?key:Key.t
  -> ?attrs:Attr.t list
  -> ?content_fit:Content_fit.t
  -> ?can_shrink:bool
  -> Ocgtk_gdk.Gdk.Wrappers.Paintable.t option
  -> Node.t
