open! Core

(** One named action: what a menu item or (Task 7) a shortcut resolves to, and the one
    place in the menu system that carries handlers — which is why actions are an {i attr}
    ({!Attr.actions}: equalable frame to frame only physically) while a menu is a prop
    (pure data, {!Menu}). The GTK object behind a spec is a [GSimpleAction] in a
    [GSimpleActionGroup] the runtime owns and keeps controlled.

    stavekeeper's [Command.Registry] rows (
    {[
      { id; label; accel; scope; enabled; run }
    ]}
    , [command.ml:15-22]) map field-for-field onto a spec plus a {!Menu.Item}: [id] is
    [name]; [scope] is {!Attr.actions}' [~scope]; [enabled] is [enabled]; [run] is the
    effect; and [label]/[accel] are the {!Menu.Item}'s [label]/[accel] (the accel
    display-only, stavekeeper's own rule) — so one list of commands renders the ⋮ menu,
    the palette, and (Task 7) the chords. *)

(** [Toggle] and [Radio] are {b controlled} (spec §6.5), told through an action: [state]
    is written to GTK only when it differs from the read-back, and an {i activation} never
    moves it — the handler's effect is scheduled, the model decides, and the next frame's
    write moves GTK. A declined toggle never moves the menu's checkmark. GTK never changes
    the state on its own either: the runtime connects no [change-state], so the model is
    the single writer.

    A [Radio]'s parameter type is string ([Gvariant "s"]); the handler receives the
    activated target — the part after ["::"] in the menu item's action reference. *)
type kind =
  | Simple of unit Ui_effect.t
  | Toggle of
      { state : bool
      ; on_activate : unit Ui_effect.t
      }
  | Radio of
      { state : string
      ; on_activate : string -> unit Ui_effect.t
      }

type t =
  { name : string
  ; enabled : bool
  ; kind : kind
  }

val sexp_of_t : t -> Sexp.t

(** States compare structurally, handlers physically — the event-attr rule. *)
val equal : t -> t -> bool

val simple : ?enabled:bool -> name:string -> unit Ui_effect.t -> t
val toggle : ?enabled:bool -> name:string -> state:bool -> unit Ui_effect.t -> t

val radio
  :  ?enabled:bool
  -> name:string
  -> state:string
  -> (string -> unit Ui_effect.t)
  -> t
