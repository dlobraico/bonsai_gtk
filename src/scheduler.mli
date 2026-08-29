open! Core

(** Owns the library's relationship with the GLib main loop: when Bonsai frames run, and
    what must never happen inside one.

    Two things drive frames. {!request_frame} is the reactive path — a signal handler
    fired an effect, so the tree has to be recomputed — and it coalesces: any number of
    requests between two frames arm a single [HIGH_IDLE] source. {!start_tick} is the
    periodic path, for the wall clock and Bonsai's own time-based components.

    Frames never run synchronously from a signal handler. GTK emits signals from inside
    calls the patcher itself makes ([set_child], [remove], ...), so a synchronous frame
    could re-enter the patcher mid-patch; deferring to an idle means the stack is always
    back in GLib before Bonsai runs. {!in_patch} covers the remaining window, where GTK
    emits a signal while the patcher is running. *)
type t

(** [run_frame] is the thunk this scheduler drives. It is called from GLib callbacks and
    its exceptions are caught and logged rather than escaping into the C frame. *)
val create : run_frame:(unit -> unit) -> t

(** Arms a coalesced high-priority idle that runs one frame. A no-op if a frame is already
    armed or the scheduler has been {!stop}ped. *)
val request_frame : t -> unit

(** [true] while {!with_patch_guard}'s [f] is running. *)
val in_patch : t -> bool

(** Runs [f] with {!in_patch} set, restoring it even if [f] raises. *)
val with_patch_guard : t -> (unit -> 'a) -> 'a

(** Starts a repeating timeout that runs a frame [fps] times a second. Calling it twice
    replaces the previous tick; a non-positive [fps] means no tick at all. *)
val start_tick : t -> fps:float -> unit

(** [true] between {!start_tick} and {!stop}, i.e. a frame is guaranteed to run soon
    without anyone asking for one. *)
val ticking : t -> bool

(** Cancels the tick and makes every later {!request_frame} a no-op; an idle already armed
    still fires but does nothing. Idempotent. *)
val stop : t -> unit
