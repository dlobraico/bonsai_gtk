open! Core
open Bonsai_gtk_vtree
open Gtk_import

(* {1 The date, which is three integers and not a date}

   [gtk_calendar_get_date] and [gtk_calendar_select_day] are not bound. Both trade in
   [GLib.DateTime], the generator skips every method whose signature mentions a type it
   has not generated, and there is no [GLib-2.0.gir] in the checkout at all -- so there is
   no [GDateTime] anywhere in this binding and no way to add one from here. What does
   exist is the three integer properties, and they are enough.

   Two things about them.

   {b GTK's [month] is ZERO-BASED and its [day] is not.} That asymmetry is GTK's. It is
   the kind of thing that produces an off-by-one nobody notices until December -- January
   is index 0 and reads correctly however wrong the conversion is -- and it stops here:
   [Node.calendar] takes a [Date.t], these two functions are the only code in the library
   that ever sees the raw month, and [Live_tree] prints a calendar's date {i through}
   [read_date] rather than through the getters, so a golden cannot make a wrong conversion
   look right.

   {b The three writes are not atomic, and the order that reads as careful is wrong.} Each
   setter rebuilds the whole date and refuses outright if the result is not a real day:
   [gtk_calendar_set_month] builds [g_date_time_new_local (year, month, day, ...)], and a
   NULL from that trips [g_return_if_fail (date != NULL)] -- a critical on stderr and
   {i no write at all}. It does not clamp. So the "obvious" order, year then month then
   day, silently leaves the calendar on the old month whenever the day-of-month does not
   exist in the new one:

   {v
     from 2026-12-31 to 2026-02-15, written year, month, day:
       set_year 2026   ok (no change)
       set_month 1     REFUSED -- 31 February is not a day
       set_day 15      ok
       -> 2026-12-15, which is neither date
   v}

   [test/live/live_text.ml] runs that as a matrix and the naive order gets four of the
   five transitions wrong, including both leap-day ones; the fifth is there because it is
   the one the naive order gets right (nothing moves at all), and a matrix of failures
   alone would prove nothing about the order that works. The order below is
   {b day 1 first}, then year, then month, then the real day: day 1 exists in every month
   of every year, so no intermediate state is invalid, and every date GTK's year range
   admits lands.

   The cost is one extra write and, when the target day is not 1, one extra [day-selected]
   -- GTK emits that signal exactly when the day-of-month changes, so the sequence emits
   two (day to 1, day to [d]) where a single [set_day] would emit one. Every one of them
   is inside a patch and is dropped by the reentrancy guard; what [Widget_impl.batch] is
   for here is the [notify::year] / [notify::month] / [notify::day] round trips, which the
   guard does not save and which the bracket collapses to one thaw. (Measured:
   [freeze_notify] does {i not} suppress [day-selected] -- it is a signal, not a property
   notification -- so the bracket is about notify traffic and nothing else.) *)
let write_date (c : W.Calendar.t) date =
  W.Calendar.set_day c 1;
  W.Calendar.set_year c (Date.year date);
  W.Calendar.set_month c (Month.to_int (Date.month date) - 1);
  W.Calendar.set_day c (Date.day date)
;;

(* The inverse, and the only reader. [Date.create_exn] cannot raise on what GTK holds: a
   [GtkCalendar]'s date is always a real day, because every setter refuses anything else.
   [Date.t] is an immediate, so this allocates nothing -- which is what makes it cheap
   enough for [reassert] to call on every idle frame without a cache of the kind
   [w_text_view.ml] needs. *)
let read_date (c : W.Calendar.t) =
  Date.create_exn
    ~y:(W.Calendar.get_year c)
    ~m:(Month.of_int_exn (W.Calendar.get_month c + 1))
    ~d:(W.Calendar.get_day c)
;;

(* {1 A date GTK will not hold}

   Exactly one shape, and it is the year. [gtk_calendar_set_year] asserts
   [year >= 1 && year <= 9999]; [Core.Date] admits year 0 and rejects 10000 and above, so
   the values a [Date.t] can carry and the values GTK will take differ in precisely one
   place. Everything else a [Date.t] can express -- every month, every leap day -- lands,
   which the live matrix asserts rather than assumes.

   Checked {i before} the write and not after it, which matters here more than it did for
   the drop-down: the write is four calls, and letting a year-0 date reach them would land
   [set_day 1] and then fail the other three, leaving the calendar on a date {i neither}
   the model nor the user asked for. Refusing first leaves the widget exactly as it was,
   which is [w_text_view.ml]'s rule for text a [GtkTextBuffer] will not store, in the one
   shape it takes here. *)
let unholdable date =
  let y = Date.year date in
  if y < 1 || y > 9999
  then
    Some
      (sprintf
         "~date:%s is in year %d, and GTK's calendar holds years 1 to 9999 \
          (gtk_calendar_set_year asserts it and writes nothing); the write was refused \
          and the calendar was left showing the date it had"
         (Date.to_string date)
         y)
  else None
;;

(* What this calendar has already asked GTK for and been refused, per widget.

   Weakly keyed on the widget, as [w_text_view.ml]'s cache and [w_drop_down.ml]'s are: a
   calendar that is destroyed takes its entry with it rather than pinning the GObject
   alive. The key must be the [Widget.t] the patcher retains -- the same value [create]
   returned and [reassert] is handed -- which is [Child_keys]' invariant in a smaller
   place.

   The refusing half is {!Refusal}'s, written once for the five widgets that have one;
   what rides beside it here is the dedup memo below, in the same ephemeron entry so that
   a frame costs one lookup rather than two. *)
module Fired = struct
  (* The date the handler was last told about, so that one user action reaching this
     widget through more than one GTK emission is delivered once. See {!fire_date}. *)
  type t = { mutable last_fired : Date.t option }

  let create () = { last_fired = None }
end

module Refused = Refusal.Make (Date) (Fired)

let state = Refused.state
let take_report = Refused.take_report

(* [Refused.already_refused] answers "has this exact date already been decided against",
   and is safe to consult {i before} the widget is read for the reason {!Refusal} states
   (task-9-review.md R1): [unholdable] is pure and the memo is cleared by every write that
   lands. Without it a calendar parked on a year-0 date would run [unholdable] and take a
   [freeze_notify]/[thaw_notify] pair on every idle frame forever. Both questions are O(1)
   here, so this ordering is about not writing rather than about not comparing -- the same
   shape as the drop-down's. *)

(* Write the date, or refuse it and record why. Returns nothing: the caller has already
   decided that a write is wanted. *)
let set_date c (st : Refused.t) date =
  match unholdable date with
  | Some reason ->
    (* Refused. The calendar is untouched, so it goes on showing a date that is at least a
       real one, and a later frame offering a date GTK will hold writes it on {i that}
       frame -- Tasks 6-8's same-frame rule, over a different kind of ghost. *)
    Refused.refuse st date ~reason
  | None ->
    write_date c date;
    Refused.landed st;
    (* The dedup memo is about what the {i user} was last told, and this write moves the
       widget out from under it. Without this line a date the model {i declined} could be
       chosen only once: the handler fired for it, [reassert] put the model's date back,
       and a second attempt at the same day would be coalesced away against a memo that no
       longer describes anything the user can see. *)
    st.extra.last_fired <- None
;;

(* Marks, applied whole rather than diffed.

   [clear_marks] plus one [mark_day] per entry is 32 calls at the very worst and is run
   only when the list actually differs, so a diff would buy nothing and would have to
   reason about duplicates. Order and duplicates make no difference to the result, which
   is why {!Kind.calendar_props} keeps a plain [int list].

   The range is [Node.calendar]'s to enforce and it does: [gtk_calendar_mark_day] tests
   [day >= 1 && day <= 31] itself and returns silently, with no critical, so a day outside
   it would never appear and nothing would say why. A day that is out of range for the
   month {i showing} is a different thing and is legal -- marks are per day-of-month and
   survive a month change (measured: day 31 marked while February is showing is still
   marked in March). *)
let set_marks (c : W.Calendar.t) days =
  W.Calendar.clear_marks c;
  List.iter days ~f:(fun day -> W.Calendar.mark_day c day)
;;

let same_marks a b = phys_equal a b || List.equal Int.equal a b

(* {1 Every way the displayed date can change}

   The date is a controlled prop, so the attr beside it has to fire whenever the date the
   calendar {i shows} changes -- not merely when GTK emits the signal named after days.
   The first round got this wrong, and got it wrong from a premise its own golden already
   disproved: it exposed [day-selected] alone, on the ground that "walking to another
   month moves the day too, so [day-selected] fires for all four anyway".

   {b It does not.} Measured on GTK 4.22 by emitting [clicked] on the calendar's own
   heading buttons, which is the exact path a user click takes:

   {v
     next/prev-month : month moves, day survives -> notify::month only, day-selected +0
     next/prev-year  : year moves,  day survives -> notify::year only,  day-selected +0
     Jan 31 -> Feb   : month AND day move        -> notify::day + notify::month,
                                                    day-selected STILL +0
   v}

   The heading path never emits [day-selected] at all, even when it moves the day. So a
   user who walked to September was never reported, the model went on holding August, and
   the next [reassert] -- any frame, any event, the idle tick -- wrote August back and the
   calendar snapped. The widget could not be browsed, and no application could have been
   written that kept up, because there was no attr through which to learn.

   {b Three connections, one attr name, one slot.} [day-selected] is GTK's own event for
   the user picking a day and is what the grid path emits; [notify::month] and
   [notify::year] are the two components a heading walk moves. Together they cover the
   date completely, because the date {i is} those three properties and every write goes
   through [calendar_set_date], which notifies each component that changed. (A fourth,
   [notify::day], would make that argument structural rather than measured -- it fires on
   every day change including the heading ones. It is not connected because no reachable
   path changes the day alone without [day-selected]: the heading buttons cannot, and the
   grid emits it. If one is ever found, adding it here is one line and the dedup below
   already absorbs the extra emission.)

   They share one [Attr.Name.t] and therefore one slot, so [Signals.update_slots],
   [Signals.armed] and [Signals.require_slots] are untouched and [live_events.ml]'s
   comparison against [Events.for_kind] still sees exactly one name. What
   [Signals.read_back.connect] returning a list buys is only that all three are torn down.

   {b Coalescing.} One user action can reach more than one of the three -- a grid click on
   a day drawn from the adjacent month moves the month as well as the day -- so the
   handler is deduped against the date it was last told about. That is exact rather than
   approximate, and it is safe, because every emission in a burst reads the
   {i same final date}: [calendar_set_date] updates its date before notifying anything
   (measured -- each of the logged callbacks above reports the post-walk date, never the
   pre-walk one). So a burst delivers the new date exactly once, never zero times and
   never twice.

   The memo is cleared by every library write ({!set_date}), which is what keeps a date
   the model {i declined} choosable again. It is not cleared anywhere else, and does not
   need to be: any other way the widget's date changes is itself an emission that updates
   it. *)
let fire_date w =
  let fired = Refused.extra w in
  let date = read_date (cast w) in
  match fired.last_fired with
  | Some d when Date.equal d date -> None
  | Some _ | None ->
    fired.last_fired <- Some date;
    Some date
;;

(* [day-selected] carries no payload -- it is GTK saying "the date moved", not saying to
   what -- and a [notify::] carries none either, so this is a read-back spec, which is
   exactly what a read-back spec is for. The payload the handler wants is assembled by
   [read_date] from the same three getters the write uses, so the zero-based month is
   converted in one place for both directions.

   [next-month], [prev-month], [next-year] and [prev-year] are still not exposed, and now
   for a reason that holds: they say the heading was clicked rather than what the calendar
   shows, and the two [notify::] connections above already carry what they change. An
   application that genuinely wants "the user is browsing" as distinct from "the date
   changed" would need them; nothing in M2 does.

   The guard matters here as much as anywhere in the library: [write_date] emits
   [day-selected] and up to two [notify::] per date change the model makes, and every one
   of those is a write the library made on the user's behalf inside a patch. *)
let day_selected : Signals.spec =
  Read_back
    { attr = Attr.Name.On_day_selected
    ; connect =
        (fun w ~callback ->
          let c : W.Calendar.t = cast w in
          [ Signals.connected c (W.Calendar.on_day_selected c ~callback)
          ; Signals.notify_connection ~prop:"month" c ~callback
          ; Signals.notify_connection ~prop:"year" c ~callback
          ])
    ; fire =
        (fun w attr ->
          match (attr :> Attr.Private.t) with
          | On_day_selected handler ->
            (* [None] when this emission is one the application has already been told
               about, which [Signals.dispatch] reads as "nothing to schedule" -- the same
               answer it gives for an attr this spec does not handle. *)
            Option.map (fire_date w) ~f:handler
          | _ -> None)
    }
;;

(* Controlled (spec §6.5): compared against the {i widget's} date on every frame and never
   against the previous node's. A calendar has no children, so this is [reassert]'s rather
   than the fixup queue's -- there is nothing to wait for, exactly as for a drop-down's
   selection.

   The comparison comes first so that the bracket is outside the decision: a calendar
   patched with the date it already shows -- which is every idle frame -- must pay neither
   the write nor the freeze/thaw. See [Widget_impl.batch_if]. *)
let reassert w (kind : Kind.t) =
  match kind with
  | Calendar p ->
    let c : W.Calendar.t = cast w in
    let st = state w in
    let writes =
      (not (Refused.already_refused st p.date)) && not (Date.equal (read_date c) p.date)
    in
    Widget_impl.batch_if writes w (fun () -> if writes then set_date c st p.date)
  | k -> Widget_impl.wrong_kind "Calendar" k
;;

let impl : Widget_impl.t =
  { name = "Calendar"
  ; create =
      (fun (kind : Kind.t) ->
        match kind with
        | Calendar p ->
          let c = W.Calendar.new_ () in
          let w = (c :> Widget.t) in
          Widget_impl.batch w (fun () ->
            (* GTK's own are [true], [true] and [false], so each is written only when the
               node asks for the other -- a no-op write would still emit a [notify::] for
               the guard to swallow. [Defaults] is not re-exported from [Bonsai_gtk_vtree]
               (it is [Kind]'s and [Node]'s), so the three values are spelled out here, as
               every other impl in this directory spells its own out. *)
            if not p.show_day_names then W.Calendar.set_show_day_names c false;
            if not p.show_heading then W.Calendar.set_show_heading c false;
            if p.show_week_numbers then W.Calendar.set_show_week_numbers c true;
            if not (List.is_empty p.marked_days) then set_marks c p.marked_days;
            (* The date last, and through [reassert] rather than a second [write_date] of
               its own, so the one controlled prop this kind has has exactly one
               implementation -- including the refusal that notices a year GTK will not
               take. A fresh [GtkCalendar] comes up showing today, so a node asking for
               anything else pays one write here, which is the write the next patch would
               have made anyway. *)
            reassert w kind);
          w
        | k -> Widget_impl.wrong_kind "Calendar" k)
  ; update =
      (fun w ~(old : Kind.t) (new_ : Kind.t) ->
        match old, new_ with
        | Calendar old, Calendar new_ ->
          let c : W.Calendar.t = cast w in
          Widget_impl.batch w (fun () ->
            if not (Bool.equal old.show_day_names new_.show_day_names)
            then W.Calendar.set_show_day_names c new_.show_day_names;
            if not (Bool.equal old.show_heading new_.show_heading)
            then W.Calendar.set_show_heading c new_.show_heading;
            if not (Bool.equal old.show_week_numbers new_.show_week_numbers)
            then W.Calendar.set_show_week_numbers c new_.show_week_numbers;
            (* Compared before it is applied, for [w_drop_down.ml]'s reason: a view that
               rebuilds an equal list every render must not make GTK redraw the month
               every frame. [phys_equal] first, so a view that computes its marks once
               answers in a pointer comparison. This is reached only on a frame where
               something about the node already differed -- the patcher compares
               [Kind.equal_props] first and skips [update] entirely otherwise -- so an
               idle frame never gets here.

               Unlike the drop-down's items, a marks change does not disturb anything the
               refusal memo is about: marks and the date are independent in GTK, so
               nothing is forgotten here. *)
            if not (same_marks old.marked_days new_.marked_days)
            then set_marks c new_.marked_days)
          (* [date] is deliberately absent: it is controlled, which makes it [reassert]'s,
             and the patcher runs that immediately after this and on every other patch
             too. *)
        | _, k -> Widget_impl.wrong_kind "Calendar" k)
  ; reassert = Some reassert
  ; signals = [ day_selected ]
  ; children = Widget_impl.No_children
  }
;;
