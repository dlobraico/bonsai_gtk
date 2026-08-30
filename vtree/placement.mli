open! Core

(** Which container-placement attributes each kind reads off its children.

    A placement attr is a setting the {i parent} holds on behalf of a child — a grid cell,
    a stack page's title, an overlay child's measure flag (spec §5.3's M1 amendment). It
    rides on the child node's [attrs] and is read by the parent's implementation;
    [Attr_apply] never applies one to the child. So a placement attr on a child whose
    parent does not read it is not merely wrong, it is {b unobservable}: nothing writes
    it, nothing reads it, and no other check in the library has any reason to look at it.

    Pure data, in [vtree] rather than in the runtime, for the reason {!Events} is: two
    things need it and only one of them may link ocgtk. [Patcher.check_placement] rejects
    a misplaced attr at mount and at patch, and [Bonsai_gtk_test] rejects the same tree at
    handle time — otherwise a suite that is entirely headless certifies an application
    that raises the moment it is shown.

    Unlike {!Events}, whose two consumers build the same message from the same two
    ingredients and agree by convention, both consumers here call {!rejection} and get the
    identical string. The message is longer and has two shapes, which is more than a
    convention can hold. *)

(** The placement attrs this kind reads off its children. The empty list — every kind but
    [Grid], [Stack] and [Overlay] — is deliberate and is what makes this a diagnostic: a
    container that reads none of them rejects all of them. *)
val read_by : Kind.t -> Attr.Name.t list

(** The container that reads [name], as [Kind.name] spells it; [None] for every attr that
    is not parent-held. Exhaustive over {!Attr.Name.t} with no wildcard, so a new
    attribute cannot skip the question. *)
val reader : Attr.Name.t -> string option

(** Every parent-held attr name, in [Attr.Name] order. Derived from {!reader}. *)
val names : Attr.Name.t list

(** [is_read_by ~parent name] is [true] if [name] is not a placement attr, or is one
    [parent] reads. [parent] is [None] for the tree's root, which has no container above
    it and therefore reads nothing. *)
val is_read_by : parent:Kind.t option -> Attr.Name.t -> bool

(** The first placement attr in [attrs] that [parent] does not read, in [Attr.Name] order.
    [None] when every placement attr present is one [parent] reads. *)
val misplaced : parent:Kind.t option -> Attrs.t -> Attr.Name.t option

(** {!misplaced}, rendered as the [Invalid_argument] message both the patcher and
    [Bonsai_gtk_test] raise — node path first, then the attr as the caller spelled it, the
    container that has it, and the container that would read it (spec §11). [None] when
    nothing is misplaced. *)
val rejection : path:string -> parent:Kind.t option -> Attrs.t -> string option
