open! Core
open Bonsai_gtk_vtree

(** Runs [app] as a [GtkApplication] and returns the application's exit status.

    Blocks until the last window is closed or an {!Effect.quit} is performed. The Bonsai
    computation is built on the application's [activate] signal, not before, because GTK
    forbids creating widgets earlier.

    [application_id] is the D-Bus name GTK identifies the app by; it should be a reverse
    DNS name and defaults to a placeholder. [target_frames_per_second] sets how often a
    frame runs on its own, which is what drives [Bonsai.Clock] and after-display handlers
    — frames caused by user interaction do not wait for it. [time_source] and [optimize]
    are {!Driver.create}'s. *)
val start
  :  ?application_id:string
  -> ?time_source:Bonsai.Time_source.t
  -> ?optimize:bool
  -> ?target_frames_per_second:float
  -> (local_ Bonsai.graph -> Node.t Bonsai.t)
  -> int
