open! Core

(** A declarative menu tree — the [GMenu] model a {!Node.menu_button}'s [~menu] renders.

    {b Pure data, and that is the design}: items {i name} actions (["scope.name"]), they
    never carry handlers, so a menu is an equalable, sexpable {b prop} diffed like any
    other — while the handlers live in {!Attr.actions} on the menu button or an ancestor,
    which is where GTK's own action resolution looks. A name that resolves to no action in
    scope is [Invalid_argument] at mount, at patch, and headlessly — the single-referent
    rule; see [Action_resolution].

    There is no [Kind.Menu] widget because a [GMenu] is not a widget: this module plus
    {!Node.menu_button}'s [~menu] argument {i is} spec §7's [Node.menu]. *)

module Item : sig
  type t = private
    { label : string
    ; action : string
    (** ["scope.name"], or ["scope.name::target"] to activate a {!Action_spec.Radio} with
        [target]. *)
    ; accel : string option
    (** {b Display-only}, GTK accel syntax (["<Control>k"]): rendered beside the label by
        the [PopoverMenu] via the ["accel"] attribute, never installed as an accelerator.
        stavekeeper's rule ([viewer_window.ml:4230-4233] — "the key handler stays the
        single source of key truth"), adopted as ours: key {i routing} is
        {!Attr.on_key_pressed}'s or (Task 7) {!Attr.shortcut}'s. *)
    }
  [@@deriving sexp_of, equal]

  val create : ?accel:string -> label:string -> action:string -> unit -> t

  (** The ["scope.name"] half, a radio's ["::target"] stripped. *)
  val action_reference : t -> string
end

type entry =
  | Item of Item.t
  | Section of
      { label : string option
      ; entries : entry list
      }
  | Submenu of
      { label : string
      ; entries : entry list
      }
[@@deriving sexp_of, equal]

type t = entry list [@@deriving sexp_of, equal]

val item : ?accel:string -> label:string -> action:string -> unit -> entry
val section : ?label:string -> entry list -> entry
val submenu : label:string -> entry list -> entry

(** Every ["scope.name"] any item references, depth-first, duplicates kept. *)
val action_references : t -> string list
