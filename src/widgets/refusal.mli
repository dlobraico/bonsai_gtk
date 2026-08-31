open! Core
open Gtk_import

(** Refuse, record, report: the one mechanism behind every controlled prop whose value the
    widget cannot hold.

    Five widgets have the same problem. A model renders a value that GTK will not store —
    a text with a NUL in it, a date outside GTK's 1–9999, a drop-down index past the end —
    and a controlled prop compares against the {i widget}, so the comparison says
    "differs" on that frame and on every frame after it. Writing anyway is worse than
    useless: the write does not land (or lands truncated), nothing changes, and the next
    idle frame tries again, forever, silently. What M2 settled on instead, in
    [w_text_view.ml] first, is:

    - {b refuse} the write {i before} anything is compared or bracketed, leaving the
      widget exactly as it was, so the library's belief about the widget stays true;
    - {b record} the value it was refused for, so the decision is made once rather than
      per frame and a parked frame costs a pointer comparison;
    - {b report} the reason once, through [Patcher.ctx.report], which is the one place
      holding both the widget and the path of the node it came from.

    This module is that mechanism, once. It was four hand-copied implementations —
    byte-identical modulo the value type, and diverging in exactly one place that mattered
    ([take_report] minting an ephemeron entry to find [None] in it) — until the fifth
    widget was about to be a fifth copy.

    {b Ordering.} [already_refused] is safe to consult {i before} the widget is read
    (task-9-review.md R1) precisely because the refusal predicates are pure functions of
    the value: a value refused once is refused always, and [landed] clears the memo on
    every write that succeeds. A widget whose refusal depends on something else — a
    drop-down index is refused {i relative to the item list} — must call
    {!Make.forget_refusal} from whatever changes that answer.

    {b Weakly keyed on the widget}, so a view that is destroyed takes its entry with it
    rather than pinning the GObject alive. The key must be the [Widget.t] the patcher
    retains — the same value [create] returned and [reassert] is handed — which is
    [Child_keys]' invariant in a smaller place. *)

module type Value = sig
  (** What a refusal is remembered against: the text, the date, the index. *)
  type t

  val equal : t -> t -> bool
end

(** Per-widget state a particular widget wants {i beside} the refusal, carried in the same
    ephemeron entry so that a frame costs one lookup rather than two: the text view's
    written-text cache, the calendar's last-fired memo. *)
module type Extra = sig
  type t

  val create : unit -> t
end

(** For the widgets that want none. *)
module No_extra : Extra with type t = unit

module Make (V : Value) (E : Extra) : sig
  type t = private
    { mutable refused : V.t option
    ; mutable unreported : string option
    ; extra : E.t
    }

  (** This widget's entry, created empty if it has none. *)
  val state : Widget.t -> t

  val extra : Widget.t -> E.t

  (** The message for a refused write, if one has not been reported yet; cleared by the
      read, so a refusal is reported once however many frames it survives. Called by the
      patcher once per widget of the kind per frame, and it allocates nothing and creates
      no entry when there is nothing to say. *)
  val take_report : Widget.t -> string option

  (** Whether this exact value has already been decided against — and so whether the frame
      can stop here, without reading the widget, comparing anything or bracketing
      anything. *)
  val already_refused : t -> V.t -> bool

  (** Record a refusal and the message that explains it. The caller has already left the
      widget untouched; this is the bookkeeping half. *)
  val refuse : t -> V.t -> reason:string -> unit

  (** A write landed, so nothing is refused any more. *)
  val landed : t -> unit

  (** Drop the memo because something other than the value may have changed the answer.
      Only the drop-down needs this (its refusal is about an index relative to the items),
      and it is a no-op for a widget with no entry. *)
  val forget_refusal : Widget.t -> unit
end
