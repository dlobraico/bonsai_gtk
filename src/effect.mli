open! Core

(** [Ui_effect] — the effect type Bonsai schedules — plus the one effect that only makes
    sense in a GTK app. *)
include module type of struct
  include Ui_effect
end

(** Quits the application started by {!Bonsai_gtk.start}: the main loop returns and
    {!Bonsai_gtk.start} yields its exit status.

    Outside {!Bonsai_gtk.start} — under {!Bonsai_gtk.Expert.Driver}, or in a headless test
    — there is no application to quit, so performing this logs and does nothing. *)
val quit : unit t

(** Not part of the public API: {!Bonsai_gtk.start} uses this to point {!quit} at the
    application it created. *)
module For_start : sig
  val set_app : Gtk_import.W.Application.t -> unit
end
