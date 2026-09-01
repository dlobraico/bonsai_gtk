open! Core
open Bonsai_gtk_vtree
open Gtk_import

(** The pass-level bookkeeping of the patcher's walk, split out of [patcher.ml]: the
    context a pass runs in, the stack-name registry and its end-of-pass claims, the fixup
    queue, and the per-kind interests that feed both. Internal to the library: {!Patcher}
    is the public interface — it re-exports {!ctx}, {!create_ctx}, {!run_fixups} and
    {!abandon_fixups}, and everything here is documented there. *)

(** Concrete here (unlike {!Patcher.ctx}, which is [private]) so that [patcher.ml] can
    re-export it by equation; nothing outside the library can see this module. *)
type ctx =
  { signals : Signals.ctx
  ; mutable on_window_created : Widget.t -> unit
  ; report : node_path:string -> string -> unit
  ; stacks : (string, Widget.t) Hashtbl.t
  ; stack_claims : stack_claim Queue.t
  ; fixups : (unit -> unit) Queue.t
  ; autofocus_claims : autofocus_claim Queue.t
  ; windows : (Key.t, Widget.t) Hashtbl.t
  }

and autofocus_claim =
  { autofocus_path : string
  ; autofocus_widget : Widget.t
  }

and stack_claim =
  { claim_path : string
  ; give_up : string option
  ; take : string
  ; claimant : Widget.t
  }

(** Replaces [ctx.on_window_created] with a no-op. [Driver.stop]'s: the callback closes
    over the [GtkApplication] under [Bonsai_gtk.start], and a stopped driver is never
    collectable, so leaving it would keep the application alive for the process's life. *)
val drop_on_window_created : ctx -> unit

val create_ctx
  :  ?report:(node_path:string -> string -> unit)
  -> signals:Signals.ctx
  -> on_window_created:(Widget.t -> unit)
  -> unit
  -> ctx

(** Removes [name] only while the registry entry is still [widget]'s: a stack that claimed
    the name during the same pass owns it now, and dropping the one it displaced must not
    unregister it. *)
val unregister_stack : ctx -> name:string -> Widget.t -> unit

(** Records a [Node.windows] child in [ctx.windows] as it mounts, so a sibling's
    [~transient_for] can resolve it from the fixup queue whichever of them the walk
    reached first. Unlike the stack names these need no claims pass: a child's key never
    changes while it lives (the reconciler matches by key, so a renamed child is a
    remove-plus-insert), and duplicate keys were already rejected by
    [Reconcile.check_unique_keys]. The [`Duplicate] arm is the same defensive raise the
    stack registry keeps. *)
val register_window : ctx -> path:string -> key:Key.t -> Widget.t -> unit

(** {!unregister_stack}'s guard, over the window registry: removes [key] only while the
    entry is still [widget]'s. Safe to call for any keyed window, registered or not. *)
val unregister_window : ctx -> key:Key.t -> Widget.t -> unit

(** Applies the pass's collected {!stack_claim}s to [ctx.stacks] — every give-up first,
    then every take, so that two stacks may exchange names in one frame — and empties the
    queue, raising [Invalid_argument] on a genuine collision. Called by
    {!Patcher.mount}/{!Patcher.patch} once their walk is over. *)
val apply_stack_claims : ctx -> unit

(** Records one [Attr.autofocus] grab the pass decided to fire -- the patcher calls it at
    mount for a node carrying [true] and at patch for a false-to-true flip. Fired by
    {!run_fixups} after the generic queue: all of a pass's grabs are checked together (at
    most one per toplevel per frame; two is [Invalid_argument] naming both paths, via
    [Events.autofocus_rejection]) and then applied with [Widget.grab_focus]. *)
val claim_autofocus : ctx -> path:string -> Widget.t -> unit

(** See {!Patcher.run_fixups}. *)
val run_fixups : ctx -> unit

(** See {!Patcher.abandon_fixups}. *)
val abandon_fixups : ctx -> unit

(** Every kind whose mount, patch or teardown the patcher itself has something to do
    about, beyond what the impl does. Matched exhaustively at each site so that a new kind
    with a registration or a fixup cannot be added without the compiler asking. *)
type interest =
  | Nothing
  | Window of Kind.window_props
  | Stack of Kind.stack_props
  | Stack_ref of [ `Switcher | `Sidebar ] * string
  | List_box of Kind.list_box_props
  | Flow_box of Kind.flow_box_props
  | Notebook of Kind.notebook_props
  | Text_view
  | Drop_down
  | Calendar
  | Popover of Kind.popover_props
  | Editable

val interest_of_kind : Kind.t -> interest

(** The deferred half of a node's interest: enqueues the end-of-pass selections and
    resolutions, and reports any refusal the widget recorded since the last pass. Also
    called by {!Patcher.reassert_only}, because a selection is a controlled prop and the
    frame that declines a navigation is exactly the frame on which nothing else moved. *)
val enqueue_fixups : ctx -> path:string -> widget:Widget.t -> interest:interest -> unit

(** The immediate half — a window is presented at mount, a stack claims its name —
    followed by {!enqueue_fixups} for the deferred half. Shared by {!Patcher.mount} and
    {!Patcher.patch}, which differ only in [pass]. *)
val note_interest
  :  ctx
  -> path:string
  -> widget:Widget.t
  -> interest:interest
  -> pass:[ `Mount | `Patch of Kind.t ]
  -> unit
