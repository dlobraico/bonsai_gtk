open! Core

(** [Ui_effect] — the effect type Bonsai schedules — plus the one effect that only makes
    sense in a GTK app. *)
include module type of struct
  include Ui_effect
end

(** Quits the application started by {!Bonsai_gtk.start}: the main loop returns and
    {!Bonsai_gtk.start} yields its exit status.

    This targets whichever application {!Bonsai_gtk.start} is currently running — the
    library supports one per process. Outside {!Bonsai_gtk.start} — under
    {!Bonsai_gtk.Expert.Driver}, in a headless test, or after [start] has returned — there
    is nothing to quit, so performing this logs and does nothing. *)
val quit : unit t

(** Not part of the public API: {!Bonsai_gtk.start} uses this to point {!quit} at the
    application it created, and to unpoint it once the main loop has returned. *)
module For_start : sig
  (** Warns on stderr if an application is already registered, which means two [start]s
      are live at once and {!quit} is about to change meaning. *)
  val set_app : Gtk_import.W.Application.t -> unit

  val clear_app : unit -> unit
end
