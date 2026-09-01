open! Core
open Bonsai_gtk_vtree

(** [Ui_effect] — the effect type Bonsai schedules — plus the effects that only make sense
    in a GTK app: {!quit}, the two timing effects, the clipboard write and
    {!Window.present}. *)
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

(** Resolves after [span] on the GLib main loop ([g_timeout_add]-backed, one-shot per
    perform; a negative span behaves as zero). Resolution runs the effect's continuation
    and then asks the runtime for a frame, so state the continuation set is on screen on
    the very next frame.

    Performing it needs a running runtime only at {i resolution}: if {!Driver.stop} ran
    while it was in flight, the timeout still fires, the continuation still runs, and a
    stderr line says no frame is coming — log-and-resolve, never a raise. The
    {i cancellable} timer stays app-side: a model can gate what it does when this
    resolves, which is the declarative cancel. *)
val after : Time_ns.Span.t -> unit t

(** Resolves on the next GLib idle ([g_idle_add]-backed, one-shot per perform) — "after
    GTK has finished what it is doing", which is what a focus move or a size-dependent
    read wants to sequence behind. Same resolution and same teardown contract as {!after}. *)
val on_idle : unit t

module Clipboard : sig
  (** Writes [text] to the display's clipboard, through a widget the runtime registered (a
      clipboard belongs to a display, and a display is reached from a widget). Performed
      with no running app it logs and resolves.

      [get_text] does {b not} ship: the binding has no synchronous read and no bound async
      one (fact table; fork-round-3 candidate). This mli line is the documented omission. *)
  val set_text : string -> unit t
end

(** Spec §8's alert, on the path the binding actually has: {b a real [GtkDialog]} --
    deprecated in GTK 4.10, present and functional in 4.22 -- because [AlertDialog] cannot
    be constructed in the pin ([gtk_alert_dialog_new] is varargs and there is no generic
    [g_object_new]); the §8 contingency, exercised and documented here so Task 13's spec
    amendment can quote it. *)
module Alert_dialog : sig
  (** Shows a modal alert -- transient for [start]'s active window when there is one --
      with [message] (a plain-text heading; never markup, the strings are not this
      dialog's to interpret), an optional [detail] line, and one button per label.
      Resolves with the {b index} of the button pressed.

      [cancel] (default 0) is the index answered on dismissal -- Escape, Alt+F4, the
      window close button, all of which deliver a reserved negative response id
      (DELETE_EVENT, measured) -- the addition that makes the effect {i total} where §8's
      signature said nothing about dismissal (deviation recorded in Task 13). The dialog
      is held by the runtime from show until its response, so the effect value may be
      dropped freely; two alerts at once are two dialogs. *)
  val show : ?detail:string -> ?cancel:int -> buttons:string list -> string -> int t
end

(** Spec §8's file dialogs, on the path the binding actually has:
    {b [GtkFileChooserNative]} -- because [GtkFileDialog] cannot be {i launched} in the
    pin (its async [open]/[save]/[select_folder] are all unbound; only the [*_finish]
    halves exist). Under a portal-less display the native chooser falls back to a plain
    GTK dialog window, which is what makes it live-testable. Also the quotable half of the
    §8 contingency, with {!Alert_dialog}'s. *)
module File_dialog : sig
  (** Each resolves with [Some path] on accept and [None] on any dismissal (Escape
      delivers DELETE_EVENT, not CANCEL -- measured). Modal, transient for [start]'s
      active window when there is one; held by the runtime from show until response.

      No initial-folder argument on any of them: [Gio.File] has no constructor in the pin
      ([new_for_path] is unbound), so there is nothing to feed [set_initial_folder] -- a
      documented omission. *)
  val open_file : ?title:string -> ?accept_label:string -> unit -> string option t

  (** [initial_name] pre-fills the name entry ([set_current_name]) -- the "Untitled
      document" affordance. *)
  val save_file
    :  ?title:string
    -> ?accept_label:string
    -> ?initial_name:string
    -> unit
    -> string option t

  val select_folder : ?title:string -> ?accept_label:string -> unit -> string option t
end

module Window : sig
  (** Presents (raises, focuses) the window keyed [key] in the root [Node.windows] list —
      "raise the window that already has this score". A key naming no window, a perform
      under {!Bonsai_gtk.Expert.embed} (which has no windows), and a perform with no
      running app each log and resolve; an effect is a value a test may perform, so none
      of them raises.

      [close] and [set_title] from spec §8 do {b not} ship: the node's existence and
      [~title] {i are} close and set_title in a declarative tree, and an effect that
      duplicates a prop is a second writer fighting the patcher — the Paned lesson.
      [present] is the one with no prop equivalent. The §8 deviation is recorded in the
      spec amendment (Task 13). *)
  val present : Key.t -> unit t
end

(** Not part of the public API: {!Bonsai_gtk.start} uses this to point {!quit} at the
    application it created, and to unpoint it once the main loop has returned. *)
module For_start : sig
  (** Warns on stderr if an application is already registered, which means two [start]s
      are live at once and {!quit} is about to change meaning. *)
  val set_app : Gtk_import.W.Application.t -> unit

  val clear_app : unit -> unit
end

(** Not part of the public API either: the process-global hooks a {i performed} effect
    reaches the runtime through — {!For_start}'s shape, generalised. Registered by
    [Loop.start]'s activate (all three hooks) and by [Embed.create] (no [lookup_window]:
    an embed has no windows, and {!Window.present} then logs and resolves, matching
    {!quit}'s outside-[start] behaviour).

    Every hook closes over a driver, so [Driver.stop] drops them — through the thunk the
    registrar hands [Driver.set_effect_hooks_drop] — or a stopped driver's whole graph
    stays reachable for the process's life, the [on_root_widget_changed] leak shape
    (docs/m2-backlog.md). Registration is last-wins; {!unregister} is identity-guarded
    (the stack registry's discipline), so the first of two embeds stopping cannot take the
    second one's hooks down.

    The slot is single, and the converse of that guard is real: the most recent registrant
    owns effect resolution for the whole process, and its stop leaves any {i earlier}
    still-live driver hookless -- that driver's async resolutions then log as outside a
    running app while its app still runs. Observable only under [fps <= 0] (the default 60
    fps tick flushes injects regardless); a real multi-driver hook story is on the backlog
    (docs/m2-backlog.md, "Recorded during M3"). *)
module For_runtime : sig
  type registration

  val register
    :  ?lookup_window:(Key.t -> Gtk_import.Widget.t option)
    -> request_frame:(unit -> unit)
    -> context_widget:(unit -> Gtk_import.Widget.t option)
    -> unit
    -> registration

  (** A no-op if a later {!register} has already displaced this registration. *)
  val unregister : registration -> unit
end

(** Test-only probes into the dialog keep-alive tables (see the impl's §2.2 note):
    reachable through [Bonsai_gtk.Private], read by [test/live/live_dialogs.ml] to drive
    an alert programmatically and to prove the mid-show [Gc.full_major] cannot take one
    down. *)
module For_live_tests : sig
  (** The live alerts, oldest first. *)
  val live_alert_dialogs : unit -> Gtk_import.W.Dialog.t list

  (** Alerts plus file choosers still awaiting a response. *)
  val live_dialog_count : unit -> int
end
