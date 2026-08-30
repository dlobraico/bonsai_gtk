open! Core

(** How a {!Node.level_bar} draws the space between its minimum and its value.

    GTK's own [GtkLevelBarMode], which only the level bar reads.

    [Continuous] is GTK's own default and draws one filled block that grows smoothly: a
    disk-usage bar, a signal strength, a battery. [Discrete] draws the bar as a row of
    equal segments and fills whole segments only, which is what a rating out of five or a
    count of retries wants — and it is the mode that makes the level bar something a
    {!Node.progress_bar} is not, since a progress bar has no notion of a step at all.

    In [Discrete] the number of segments is [max -. min] rounded, so the two are chosen
    together: [~min:0. ~max:5.] draws five blocks and [~min:0. ~max:1.] draws one, which
    is a discrete bar that looks broken. There is no separate segment count to set. *)
type t =
  | Continuous
  | Discrete
[@@deriving sexp_of, equal, compare]
