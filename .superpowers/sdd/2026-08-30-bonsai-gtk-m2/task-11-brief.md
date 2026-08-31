### Task 11: Calendar and EditableLabel — two widgets whose GTK API is not the one you expect

Both are small; both have an API shape that will send an implementer down a wrong path if the plan does not say so first.

**Files:**
- Modify: `vtree/attr.ml(i)`, `vtree/kind.ml(i)`, `vtree/node.ml(i)`, `vtree/defaults.ml`, `vtree/events.ml`, `src/widgets/registry.ml`, `src/live_tree.ml`, `test_lib/bonsai_gtk_test.ml(i)`, `test/test_widgets.ml`, `test/handle/test_handle.ml`, `test/live/live_text.ml`
- Create: `src/widgets/w_calendar.ml`, `src/widgets/w_editable_label.ml`

**Interfaces:**
- Produces:
  ```ocaml
  val calendar
    :  ?key:Key.t -> ?attrs:Attr.t list
    -> ?show_day_names:bool -> ?show_heading:bool -> ?show_week_numbers:bool
    -> ?marked_days:int list
    -> date:Date.t
    -> unit
    -> t

  val editable_label
    :  ?key:Key.t -> ?attrs:Attr.t list
    -> ?editing:bool
    -> text:string
    -> unit
    -> t

  val on_day_selected : Date.t Handler.t -> Attr.t
  val on_editing_changed : bool Handler.t -> Attr.t

  (* Bonsai_gtk_test.Action *)
  | Select_day of string * Date.t
  | Set_editing of string * bool
  ```
- Consumes: `W.Calendar.{new_,set_day,get_day,set_month,get_month,set_year,get_year,set_show_day_names,set_show_heading,set_show_week_numbers,mark_day,unmark_day,clear_marks,on_day_selected}`, `W.Editable_label.{new_,start_editing,stop_editing,get_editing}`, `W.Editable.{from_gobject,set_text,get_text,get_position,set_position,on_changed}`.

**Calendar: `get_date` and `select_day` do not exist, and neither does GDateTime.** Both take or return `GLib.DateTime` in C and the generator dropped them; there is no `GLib-2.0.gir` in the checkout at all, so there is no way to build one. What *does* exist is the three integer properties, and they are enough:

```ocaml
(* [gtk_calendar_get_date] and [select_day] are not bound -- they trade in GDateTime, which
   this binding does not have at all -- so the date is read and written as three integer
   properties. Two things about them:

   GTK's [month] property is ZERO-BASED (0 = January) while [day] is one-based. That
   asymmetry is GTK's, it is the kind of thing that produces an off-by-one nobody notices
   until December, and it stops here: [Node.calendar] takes a [Date.t] and this is the only
   code that ever sees the raw month.

   The three writes are not atomic. Writing day=31 and then month=1 addresses February 31st
   in between, which GTK normalises somewhere the caller cannot see. Write year, then
   month, then day -- month before day means the day is validated against the right month's
   length -- and bracket all three in [Widget_impl.batch] so the [day-selected] each one
   emits is a single notification at the end rather than three. The [in_patch] guard drops
   them either way; the bracket is about not doing three round trips through GTK's
   notify machinery. *)
let write_date (c : W.Calendar.t) date =
  W.Calendar.set_year c (Date.year date);
  W.Calendar.set_month c (Month.to_int (Date.month date) - 1);
  W.Calendar.set_day c (Date.day date)
;;

let read_date (c : W.Calendar.t) =
  Date.create_exn
    ~y:(W.Calendar.get_year c)
    ~m:(Month.of_int_exn (W.Calendar.get_month c + 1))
    ~d:(W.Calendar.get_day c)
;;
```

`~date` is controlled, compared through `Date.equal read_date`, in `reassert` (a calendar has no children, so no fixup). `on_day_selected` is a `Read_back` spec whose `fire` calls `read_date` — GTK's `day-selected` carries no payload and fires on all three property changes, which is exactly what a read-back spec is for.

`~marked_days` is a plain `int list` of days-of-month, applied by `clear_marks` then `mark_day` per entry when the list differs. It is not controlled (the user cannot mark a day) and it is in M2 because a calendar with no marks is a date picker, and a date picker is what `Node.calendar` would otherwise be for.

**EditableLabel: `set_text` does not exist on it, and `set_editing` does not exist at all.**

```ocaml
(* [GtkEditableLabel] binds four methods and no signals: [new_], [start_editing],
   [stop_editing] and [get_editing]. Text goes through the [GtkEditable] interface, exactly
   as [w_entry.ml] reaches an entry's -- [W.Editable.from_gobject] is a checked cast, and
   [GtkEditableLabel] implements [GtkEditable], so [set_text]/[get_text]/[on_changed] all
   work through it and the [changed] connection names the [GtkEditable] as [w_entry.ml]'s
   does.

   [editing] is READ-ONLY in GTK: there is no [set_editing]. Making it a controlled prop
   therefore means [start_editing ()] to enter and [stop_editing ~commit:true] to leave,
   which are not symmetric with each other and are certainly not a property write. In
   particular [stop_editing false] would *discard* what the user typed, so committing is
   the only defensible choice for a declarative library: the model that set [~editing:false]
   is saying "stop editing", not "throw away the edit", and the edit reaches it through
   [Attr.on_changed] either way.

   Observed with [notify::editing] + [get_editing], there being no signal. *)
```

`~text` is controlled through `Editable` with the same save-and-restore-position dance as `w_entry.ml` — reuse `W_entry.set_text_if_needed` directly rather than copying it (it takes a `W.Editable.t` and is already exported from the module; if it is not exported, export it, and note in `w_entry.ml` that it now has a second caller).

`~editing` is controlled too, and its `reassert` compares `get_editing` against the prop. Note the ordering hazard: entering edit mode selects the text, and a `reassert` that writes the text *after* calling `start_editing` would collapse that selection. Write text first, then editing — the reverse of what reads naturally.

- [ ] **Step 1: Write the failing tests**

`test/test_widgets.ml` — constructors, plus:

```ocaml
let%expect_test "calendar takes a Date.t, not GTK's zero-based month" =
  print_s [%sexp (Node.calendar ~date:(Date.of_string "2026-01-15") () : Node.t)];
  [%expect {| |}]
;;
```

`test/handle/test_handle.ml` — a date picker whose model rejects weekends, which is the declined-edit shape for a calendar and which no other test in the suite has.

`test/live/live_text.ml` — append:

```ocaml
  (* 1. A calendar showing a date, and January in particular -- the month whose zero-based
        index is 0 and which therefore looks right even when the conversion is wrong.
        Assert December too, in the same dump. *)
  (* 2. The declined date: click a day by hand ([set_day]), render the same model date, and
        assert it went back. *)
  (* 3. Marked days added and removed. *)
  (* 4. An editable label's text, and its editing state entered and left. Assert that
        leaving edit mode with ~editing:false keeps the text the user typed rather than
        reverting it -- which is [stop_editing true] and is the ruling above. *)
  (* 5. The reentrancy case for both: a programmatic write emits [day-selected] /
        [notify::editing] inside the patch, [scheduled] unchanged. *)
```

Case 1's December assertion is the whole defence against the off-by-one, and case 4 is the whole defence against `stop_editing false`.

- [ ] **Step 2–6: implement, run, promote, gate.**

`Live_tree`: `"GtkCalendar"` printing `date` as `YYYY-MM-DD` **through `read_date`, not through the raw properties** — a dump that printed the raw zero-based month would make a wrong conversion look right. `"GtkEditableLabel"` printing the text (via `Editable.get_text`) and `editing` when true.

- [ ] **Step 7: Commit**

```bash
./scripts/ci.sh
dune fmt 2>/dev/null; git add vtree src test test_lib
GIT_EDITOR=true git commit -F - <<'MSG'
Calendar over three int properties, and EditableLabel through GtkEditable

Neither widget has the API you would look for. gtk_calendar_get_date and
select_day trade in GDateTime, which this binding does not have anywhere, so
the date is the year/month/day properties -- and GTK's month is zero-based
while its day is not, an asymmetry that now stops inside w_calendar.ml because
Node.calendar takes a Date.t.

GtkEditableLabel binds four methods and no signals: text goes through the
GtkEditable interface (as an entry's does), and [editing] is read-only, so the
controlled prop is start_editing / stop_editing ~commit:true. Committing rather
than discarding is the only defensible reading of a model that renders
~editing:false.

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01Sg3Ci8U8kUKR8C3PL1pNSs
MSG
```

**Review focus:** that a December date round-trips (the zero-based month); that `Live_tree` prints the date through the same conversion the impl uses and that some test would still catch a conversion that is wrong in both places (case 1's December assertion, compared against the `Date.t` the node carried); that leaving edit mode commits; that `reassert` writes text before editing.

---

