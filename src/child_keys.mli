open! Core
open Bonsai_gtk_vtree
open Gtk_import

(** Which node key a container's live wrapper widget came from.

    [GtkListBox], [GtkFlowBox] and [GtkNotebook] all hand a signal callback a {i widget} —
    a row, a child, a page's content — and every one of the questions an application asks
    about it ("which item was activated", "which are selected") is a question about the
    node it came from. The node is gone by then, so the answer is recorded when the
    wrapper is created and looked up when the signal fires.

    Weakly keyed, so a destroyed widget takes its entry with it rather than pinning the
    GObject alive. [Gobject.same] is the equality: two OCaml values wrapping one GObject
    are never [==], and using [==] here would silently never find anything. The pattern
    (and the reason) is [src/widgets/w_search_entry.ml]'s [Echo] table.

    {b The key must be an OCaml value that something else keeps reachable for as long as
      the entry should live},
    and that is a real constraint rather than a formality. The ephemeron is weak in the
    {i OCaml value}, not in the GObject: an entry is dropped at the first collection after
    that particular wrapper becomes garbage, however alive GTK keeps the underlying
    object. So key on the widget the patcher stores in [live.widget] -- which is exactly
    as long-lived as the node -- and never on a wrapper a container impl creates and
    drops, which is unreachable the moment the function that made it returns. [W_list_box]
    keys on the row's {i child} for this reason and looks a row up through
    [List_box_row.get_child]; keying on the row itself lost every entry at the first major
    collection, with no error anywhere -- the rows stayed selected and the lookups simply
    stopped answering.

    One table per container module rather than one per container instance: the keys are
    unique per container but the {i widgets} are unique globally, so a shared table is
    correct and saves a lookup. *)
type t

val create : unit -> t

(** Records [key] for [widget], replacing any earlier entry. Called where the wrapper is
    made, which is the only place both halves are in hand. *)
val set : t -> Widget.t -> Key.t -> unit

(** Drops [widget]'s entry, so that a table shared by every container of a kind does not
    accumulate entries for the lifetime of the process. A destroyed widget would
    eventually take its entry with it, but "the next GC" is not a bound worth relying on
    for a list the user filters.

    Both ways a wrapper can leave have to call it, and they are not the same code path: a
    child removed from a container that stays ([Widget_impl.list_ops.remove]), and every
    child of a container that is itself torn down — the patcher walks a dying subtree
    rather than removing each child from its parent, so the per-child hook never runs
    there. See [W_list_box]'s [remove] and [forget_rows]. *)
val remove : t -> Widget.t -> unit

val find : t -> Widget.t -> Key.t option

(** {!find}, raising [Invalid_argument] naming [what] (["list box row"]) when there is no
    entry.

    Reachable only if a container hands back a widget it never registered, which is a bug
    in this library rather than anything an application did. It raises rather than
    answering [None] because a silent [None] there is a handler that mysteriously never
    fires — the failure every check in [Signals] exists to prevent. Call it from a spec's
    [fire] rather than from its [connect]: [Signals.dispatch]'s trampolines are what stand
    between a raise and GTK's C frame, and [connect]'s closure runs outside them. *)
val find_exn : t -> Widget.t -> what:string -> Key.t
