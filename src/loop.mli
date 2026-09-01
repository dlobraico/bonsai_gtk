open! Core
open Bonsai_gtk_vtree

(** Runs [app] as a [GtkApplication] and returns the application's exit status.

    Blocks until the last window is closed or a {!Gtk_effect.quit} is performed. The
    Bonsai computation is built on the application's [activate] signal, not before,
    because GTK forbids creating widgets earlier.

    One application per process: the library keeps a single reference to the running
    application for {!Gtk_effect.quit} to find, so two overlapping [start]s would fight
    over it (the second warns on stderr). The reference is dropped once the loop returns.

    [application_id] is the D-Bus name GTK identifies the app by; it should be a reverse
    DNS name and defaults to a placeholder. [target_frames_per_second] sets how often a
    frame runs on its own, which is what drives [Bonsai.Clock] and after-display handlers
    — frames caused by user interaction do not wait for it. A non-positive value installs
    no tick; see {!Driver.start_tick} for what that leaves running. [time_source] and
    [optimize] are {!Driver.create}'s.

    If building the computation or rendering its first frame raises, the exception is
    logged and the status is non-zero even though GTK itself exited cleanly: an
    application that never opened a window must not look like a successful run.

    If a *later* frame raises, the exception is logged and the driver stops permanently
    (see {!Driver.broken}): the main loop keeps running and the window stays on screen at
    its last good state, but nothing updates it again, and this call returns a non-zero
    status when the loop finally exits. Frames are not atomic, so retrying one that raised
    would patch a GTK tree the shadow tree no longer describes. *)
val start
  :  ?application_id:string
  -> ?time_source:Bonsai.Time_source.t
  -> ?optimize:bool
  -> ?target_frames_per_second:float
  -> ?global_css:string
  -> (local_ Bonsai.graph -> Node.t Bonsai.t)
  -> int
