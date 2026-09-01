open! Core
open Bonsai_gtk_vtree
open Gtk_import

(** The GTK side of {!Bonsai_gtk_vtree.Attr.actions}: one [GSimpleActionGroup] per node
    carrying the attr, inserted under its scope with [Widget.insert_action_group],
    [Controllers]-shaped — created with the live record, re-synced from the attrs on every
    patch, cleared before an unparent, released at destroy.

    {b Insertion order is load-bearing} (pre-flight correction 1): the group must be
    inserted before the widget is rooted or a [PopoverMenu]'s item tracker never binds.
    [Patcher.mount] runs {!create}/{!update} while the widget is still unparented, so the
    normal shape always gets the good ordering; the attr first {i appearing} on an
    already-mounted node is the documented limitation on {!Attr.actions}.

    [enabled] and [state] are controlled (spec §6.5): written only when the [GAction]
    read-back differs, and an activation never moves state — the handler's effect is
    scheduled and the model's next frame decides. The activate trampoline follows the five
    signal rules; [Simple_action_group.lookup] is never called (its non-option return
    crashes on NULL — the module keeps its own name table). *)
type t

val create : Signals.ctx -> node_path:string -> Widget.t -> t

(** Syncs the group to the node's attrs: builds it on the frame {!Attr.actions} appears,
    removes it on the frame the attr goes, rebuilds under a renamed scope, and diffs the
    spec list by name in between — a shape change (Simple/Toggle/Radio) rebuilds that
    action, since parameter type and statefulness are construction-time. *)
val update : t -> Attrs.t -> unit

(** Empties every handler slot without detaching anything — the pre-unparent disarming,
    [Controllers.clear]'s twin. *)
val clear : t -> unit

(** Disconnects the activate handlers, removes the group from the widget
    ([insert_action_group scope None]) and drops it. *)
val release : t -> unit
