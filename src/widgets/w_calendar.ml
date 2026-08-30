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
   place. *)
module Cache = Stdlib.Ephemeron.K1.Make (struct
    type t = Widget.t

    let equal = Gobject.same
    let hash = Stdlib.Hashtbl.hash
  end)

type cached =
  { (* The exact date a write was last refused for, so the decision is made once rather
       than on every frame. A [Date.t option] rather than the text view's [string option]:
       [Date.t] is an immediate, so there is no string to adopt and the comparison is
       already a machine word -- the drop-down's [int option] in a different type. *)
    mutable refused : Date.t option
  ; (* A refusal the patcher has not yet reported. Taken (and cleared) by
       [Patcher.enqueue_fixups], which is the one place holding both this widget and the
       path of the node it came from. *)
    mutable unreported : string option
  }

let cache : cached Cache.t = Cache.create 8

let state w =
  match Cache.find_opt cache w with
  | Some st -> st
  | None ->
    let st = { refused = None; unreported = None } in
    Cache.replace cache w st;
    st
;;

(* The message for a refused date, if there is one that has not been reported yet.

   Called by the patcher once per calendar per frame, because a [Widget_impl] is handed a
   widget and a kind and knows neither where it is in the tree nor how the runtime
   reports. Cleared by the read, so one refusal is reported once however many frames it
   survives. *)
let take_report w =
  let st = state w in
  match st.unreported with
  | None -> None
  | Some message ->
    st.unreported <- None;
    Some message
;;

(* Whether this exact date has already been decided against.

   Safe to consult {i before} the widget is read, on [w_text_view.ml]'s [already_refused]
   reasoning (task-9-review.md R1): [unholdable] is pure and [st.refused] is cleared by
   every write that lands, so a matching memo means the write can only fail again and the
   frame has nothing to do. Without it a calendar parked on a year-0 date would run
   [unholdable] and take a [freeze_notify]/[thaw_notify] pair on every idle frame forever.
   Both questions are O(1) here, so this ordering is about not writing rather than about
   not comparing -- the same shape as the drop-down's. *)
let already_refused st date =
  match st.refused with
  | Some d -> Date.equal d date
  | None -> false
;;

(* Write the date, or refuse it and record why. Returns nothing: the caller has already
   decided that a write is wanted. *)
let set_date c st date =
  match unholdable date with
  | Some reason ->
    (* Refused. The calendar is untouched, so it goes on showing a date that is at least a
       real one, and a later frame offering a date GTK will hold writes it on {i that}
       frame -- Tasks 6-8's same-frame rule, over a different kind of ghost. *)
    st.refused <- Some date;
    st.unreported <- Some reason
  | None ->
    write_date c date;
    st.refused <- None
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

(* [day-selected] carries no payload -- it is GTK saying "the date moved", not saying to
   what -- so this is a read-back spec, which is exactly what a read-back spec is for. The
   payload the handler wants is assembled by [read_date] from the same three getters the
   write used, so the zero-based month is converted in one place for both directions.

   It is the only one of [GtkCalendar]'s five signals this library exposes, and
   [vtree/events.ml] says why: [next-month], [prev-month], [next-year] and [prev-year]
   report that the heading was clicked rather than what the calendar now shows, and
   walking to another month moves the day, so [day-selected] fires for all four anyway.

   The guard matters here as much as anywhere in the library: [write_date] emits
   [day-selected] once or twice on every date change the model makes, and every one of
   those is a write the library made on the user's behalf inside a patch. *)
let day_selected : Signals.spec =
  Read_back
    { attr = Attr.Name.On_day_selected
    ; connect =
        (fun w ~callback ->
          let c : W.Calendar.t = cast w in
          Signals.connected c (W.Calendar.on_day_selected c ~callback))
    ; fire =
        (fun w attr ->
          match (attr :> Attr.Private.t) with
          | On_day_selected handler -> Some (handler (read_date (cast w)))
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
      (not (already_refused st p.date)) && not (Date.equal (read_date c) p.date)
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
