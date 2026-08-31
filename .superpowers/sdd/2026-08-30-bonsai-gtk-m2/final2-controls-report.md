# M2 final review — controls lens

Whole-branch, `86224d9..f06a615`, HEAD `f06a6155b0970e81bc3b30f056fa47bdccc62823`.
Package `final-controls.diff`; every finding re-verified against the working tree at HEAD.
Read-only: nothing was modified, nothing was built or run.

Scope: the controlled-prop rule and GTK's editing model across `w_text_view.ml`,
`w_drop_down.ml`, `w_level_bar.ml`, `w_calendar.ml`, `w_editable_label.ml`, and the M1
widgets this branch touched — `w_entry.ml`, `w_search_entry.ml`, `w_password_entry.ml`,
`w_switch.ml` — plus `vtree/node.ml`, `vtree/node.mli`, and the parts of `src/patcher.ml`
and `src/signals.ml` that carry the discipline. Items already listed in
`docs/m2-backlog.md` are not re-reported; where I have new information about one it is in
the recommendation section rather than as a finding.

## Summary

The controlled-prop rule is genuinely one rule across all nine widgets, and it survives
the cross-widget comparison better than I expected it to. Every `reassert` in the
directory compares against the **widget** and never against the previous node; every one
of them hoists that comparison out of `Widget_impl.batch_if` so a no-write frame pays no
freeze/thaw (all 15 `reassert`s in `src/widgets/` do this, without exception); every
refusal is decided **before** anything is compared or bracketed, which was Task 9's R1
ruling and has been applied uniformly to all four widgets that can refuse. The
`in_patch` audit came back clean: the DropDown's splice, the Calendar's `day-selected` +
`notify::month` + `notify::year` trio, and the EditableLabel's `start_editing` /
`stop_editing` are all synchronous emissions inside `Scheduler.with_patch_guard`
(`src/driver.ml:80-108` wraps `reassert_only` and `run_fixups` too, so idle frames are
covered), and `search-changed` remains the only asynchronous echo — correctly handled by
`w_search_entry.ml`'s ephemeron. The per-idle-frame sweep found exactly one O(len)
straggler, the `GtkEditable` `get_text` in the entry family, and it is already on the
backlog (`docs/m2-backlog.md:305-308`). Teardown is sound: `Signals.connected` carries the
object with the id, so the Calendar's three-connection list and the TextView's
buffer-side connection are both disconnected from the objects they were issued for. The
ephemeron keys are safe — ocgtk installs a real pointer hash and a pointer compare
(`ocgtk/src/common/wrappers.c:117-146`), so `Ephemeron.K1.Make (Gobject.same)` is a hash
table and not a list.

What I did find is one behavioural gap that is documentation-shaped but user-visible
(`~editing` is the only controlled prop in the library that does not tell the application
it must pair the prop with its attr, and it is the one where omitting the attr is most
invisible), one structural observation that bears directly on the entry-NUL decision (the
refuse-record-report discipline is one rule and four hand-copied implementations), and
four Minors — a stale comment in `node.ml` that contradicts both `node.mli` and the impl,
a remaining hole in `capped` at GTK's 65536-character clamp, an asymmetry in what the
docs say about a *parked* refusal, and a NUL sentence missing from `node.mli` that the
README already carries.

No Critical.

## Critical

None.

## Important

### I1 — `editable_label`'s `~editing` is the only controlled prop with no "pair it with the attr" warning, and it is the one that most needs it

`vtree/node.mli:1184-1232` (the `editable_label` doc block), `vtree/attr.mli:585-602`
(`on_editing_changed`), `vtree/node.ml:710`.

Every other controlled prop in `node.mli` tells the application, in as many words, that
the prop is inert without the attr that reports its changes:

- `toggle_button` :80, `check_button` :99, `switch` :119 — "Pair it with `Attr.on_toggled`
  or the control is inert" / "wants an `Attr.on_toggled` for the same reason"
- `entry` :143 — "There is no uncontrolled mode"; `text_view` :274 the same
- `spin_button` :356, `scale` :395 — "Pair it with `Attr.on_value_changed` or the control
  is inert"
- `expander` :638, `stack` :737, `list_box` :812, `flow_box` :894, `notebook` :982,
  `drop_down` :1038 — the same sentence
- `calendar` :1136 — "A calendar without an `on_day_selected` therefore cannot be browsed
  either — which is correct and is what a controlled prop means, but is worth knowing
  before rendering one as a read-only display."

`editable_label`'s `~editing` has no such sentence, in `node.mli` or in `attr.mli`. The
`attr.mli` block for `on_editing_changed` (:596-601) explains that `~editing` is controlled
and why leaving commits, and stops there.

It is the worst place to omit it, for two reasons. First, `?editing` is **optional and
defaults to `false`** (`vtree/node.ml:710`, `vtree/defaults.ml:245-247`), so
`Node.editable_label ~text:"Rehearsal" ()` compiles, reads as a drop-in `Node.label`, and
is the shape a first user will write. Second, the resulting widget is not merely
"uncontrolled", it is *broken in the direction the widget exists for*: the user
double-clicks, GTK enters editing mode and emits `notify::editing` (which no attr is
listening for), and on the next frame — at most 16 ms later under the tick —
`w_editable_label.ml:192-199` calls `stop_editing l true` and puts it back. The label
flashes into an entry and out again, forever, with nothing on stderr and nothing in
`require_specs` to complain (the attr is optional, so its absence is legal on every node).

The nearby doc actually makes this *harder* to spot: `node.mli:1225-1228` says "There is
no value of `~editing` a `GtkEditableLabel` refuses… so unlike `~text` there is nothing
here to refuse or report", which reads as reassurance exactly where the warning belongs.

The gallery gets it right (`examples/gallery.ml:589, 603-615`: `Bonsai.state` behind
`~editing` plus `Attr.on_editing_changed set_editing`), so the shape is understood — it
was simply never written down.

Fix: one sentence in `node.mli`'s `editable_label` block, in the calendar's words, and a
clause in `attr.mli:596-601`. No code change.

### I2 — the refuse-record-report discipline is one rule and four hand-copied implementations

`src/widgets/w_text_view.ml:77-123, 204-213`; `src/widgets/w_drop_down.ml:84-132, 213-217`;
`src/widgets/w_calendar.ml:109-155, 166-170`; `src/widgets/w_editable_label.ml:72-126`;
`src/patcher.ml:162-176, 239-256`.

Not a defect — every copy is correct, and I checked the reset rules against each other
rather than against one source (see below). It is the structural answer to this lens's
central question, and it is the fact the entry-NUL decision turns on, so it belongs in the
report.

Four widgets each carry their own private copy of the same 40-line mechanism:

| | `Cache` (`Ephemeron.K1.Make`) | `cached` record | `state` | `take_report` | `already_refused` |
|---|---|---|---|---|---|
| `w_text_view.ml` | :77-82 | :84-94 | :101-108 | :116-123 | :204-213 (string, adopting) |
| `w_drop_down.ml` | :84-89 | :91-101 | :105-112 | :120-127 | :213-217 (int) |
| `w_calendar.ml` | :109-114 | :116-129 | :133-140 | :148-155 | :166-170 (`Date.t`) |
| `w_editable_label.ml` | :72-77 | :79-87 | :91-98 | :103-110 | :117-126 (string, adopting) |

The four `Cache` modules are byte-identical. `state` and `take_report` are byte-identical
in all four modulo the record's field list. `already_refused` is byte-identical between
`w_text_view.ml` and `w_editable_label.ml`. On top of that the patcher carries four
`interest` constructors that exist only to name these widgets (`src/patcher.ml:162-176`)
and four one-line `Option.iter (W_X.take_report widget) ~f:(ctx.report ~node_path:path)`
arms (`:239-256`).

The reset rules, compared side by side, *are* coherent, and the coherence is a real
invariant rather than a coincidence: the memo may be consulted before the widget is read
exactly when the refusal predicate is a pure function of the value being written, and
where it is not, the memo is explicitly invalidated by whatever changes GTK's answer.
`unwritable` (text view, editable label) and `unholdable` (calendar) are pure, so a
landing write is the only clearing event; a drop-down's answer depends on the model
contents, so `forget_refusal` is called from `update`'s items branch
(`w_drop_down.ml:329-338`) and the same-frame recovery falls out of it. I traced the
drop-down's memo through items shrink / items grow / prop-only change / selection landing
and could not construct a state where the memo outlives its truth.

But that invariant is stated in four comments and enforced nowhere. Adding a fifth widget
to the discipline — which is precisely the entry-NUL question — means a fifth `Cache`, a
fifth `state`, a fifth `take_report`, a fifth `interest` constructor and a fifth patcher
arm, and the backlog's counter-argument against doing it is, verbatim, "three more
per-widget caches are a cost" (`docs/m2-backlog.md:162-163`). That cost is an artefact of
the copying, not of the rule.

The factoring is not hypothetical: `W_entry.set_text_if_needed` / `needs_text` /
`changed` are already the shared implementation for **all four** `GtkEditable` widgets
(`w_entry.ml:5-12` says so explicitly, and `w_editable_label.ml:175, 190, 247` uses them),
so a refusal living in `W_entry` covers entry, password entry, search entry and editable
label at once — which would take the number of caches from four to three, not to seven.
See the recommendation.

## Minor

### M1 — `node.ml`'s level-bar comment says GTK clamps `~value` into the range; it does not, and two other places in the branch say so correctly

`vtree/node.ml:278-280`:

> `[value]` outside the range is *not* rejected: GTK clamps it into `[min, max]`, which is
> what a caller rendering a ratio that occasionally exceeds 1 wants, and clamping is
> visible in the widget rather than silent.

`gtk_level_bar_set_value` does not clamp. Only the *bound* setters do — which is the whole
premise of `src/widgets/w_level_bar.ml:78-92`, whose comment ("the clamping is asymmetric:
`set_min_value` and `set_max_value` drag the live value into the new range, while
`set_value` does not clamp at all") is what forces the unconditional value rewrite when
only the bounds moved, and which says `test/live/live_text.ml` pins the line. `node.mli`
:472-475 is also correct and precise: "GTK clamps a value the *bounds* move over … and
stores a value written directly whatever it is (a bar below its minimum draws empty)."

So the mli and the impl agree with each other and with a live test, and the implementation
comment in `node.ml` contradicts both. Observable difference: `Node.level_bar ~min:0.
~max:1. ~value:5. ()` leaves `get_value` reading `5.`, not `1.`. Comment-only fix; the
mli's sentence is the one to copy.

### M2 — `capped` does not know about GTK's 65536-character clamp, and `Node.entry` validates `~max_length` not at all

`src/widgets/w_entry.ml:35-64` (`capped`), `vtree/node.ml:120-148` (`let entry`).

`capped` exists so that a `~text` longer than `~max_length` costs one write instead of one
per idle frame, by comparing against what the widget can actually hold. GTK's own
documentation for `gtk_entry_buffer_set_max_length`, in the pinned 4.22 GIR
(`share/gir-1.0/Gtk-4.0.gir`, `gtk/gtkentrybuffer.c:551`), says: "the maximum length of the
entry buffer, or 0 for no maximum… **The value passed in will be clamped to the range
0-65536.**" `gtk_entry_set_max_length` delegates straight to it.

`capped` uses the node's `max_length` unclamped. So with `~max_length` above 65536 and a
`~text` longer than 65536 characters:

- `create` / `update` write `set_max_length 100_000`; GTK stores 65536.
- `capped ~max_length:100_000 text` returns `text` unchanged (70 000 ≤ 100 000).
- `set_text` stores the first 65536 characters.
- `needs_text` is therefore true on **every** frame, so `reassert` takes the freeze/thaw,
  rewrites the whole text and re-places the caret 60 times a second, forever — which is
  exactly the failure `capped` was introduced to prevent, and the same shape the backlog
  records for a NUL.

Reachability is the mitigating factor: it needs a `~max_length` above 65536 (an odd but
not absurd way to spell "effectively no limit") *and* a text past 65536 characters. That
is why this is Minor rather than Important; the consequence when it is hit is severe.

Related, and the reason to fix it at the constructor: `Node.entry` validates nothing about
`~max_length`, while the same file rejects a `~selected` below `-1`
(`vtree/node.ml:641-651`), a `~marked_days` outside 1–31 (:690-699) and a level bar's
negative or inverted bounds (:291-311). A `~max_length` above 65536 or below 0 is a
configuration constant no later frame can make valid — the exact class `node.ml` raises
for. One line at the constructor, or `Int.min max_length 65536` inside `capped`; the
constructor is the more consistent of the two.

### M3 — "while a refusal is parked, the prop is not enforced" is documented for the drop-down only, and three other widgets behave identically

`vtree/node.mli:1080-1088` says, for the drop-down and with admirable directness:

> While a selection is parked like that, **the prop is not being enforced**: the remembered
> refusal is consulted before the widget is read, so a choice the user makes afterwards is
> left standing rather than snapped back.

That is a consequence of the Task 9 R1 ordering, and it is therefore equally true of the
other three refusing widgets, whose `reassert`s consult the memo before reading the widget
in exactly the same way:

- `w_text_view.ml:416` — a text view parked on invalid UTF-8 lets the user type freely and
  never snaps back. `node.mli:309-323` says the view "keeps what it was showing" and "the
  model is not wedged", which is about the *library's* write; it does not say control of
  the widget is suspended meanwhile.
- `w_editable_label.ml:178` — same for `~text`, and with a twist worth a clause of its own:
  `writes_editing` (:179) is computed independently of the memo, so while the label's
  `~text` is parked its `~editing` is *still* enforced. That is defensible but is the only
  half-enforced controlled node in the library, and it is written down nowhere.
- `w_calendar.ml:327` — a calendar parked on a year-0 date leaves the user's browsing
  standing. `node.mli:1127-1135` says the calendar "keeps the date it had", again about
  the library's write.

Doc-only; the drop-down's paragraph is the model, and the other three want a sentence each
(or one shared sentence in the README's refusal section, which already groups them).

### M4 — `node.mli` says nothing about a NUL in an entry's `~text`, though the README and the backlog both do

`vtree/node.mli:132-201` (`entry`), `:195-208` (`password_entry`), `:210-247`
(`search_entry`).

Task 16's fix round put the per-widget rule in `README.md:379-395`, correctly and in
detail — including the sentence "the widget is therefore rewritten on every idle frame,
silently". `node.mli` is the reference an application actually reads, and it documents
`text_view`'s refusal (:309-323) and `editable_label`'s (:1203-1210) at length, and
`entry`'s `max_length` divergence at length (:177-195, eleven lines for a case that costs
one write) — but says nothing at all about the one text divergence that costs a write per
frame for the life of the tree.

Whichever way the entry-NUL question is decided, the three entry constructors want the
sentence: today's behaviour if it stands, the refusal rule if it does not.

### M5 — the idle-frame cost note for the `GtkEditable` read is understated

`src/widgets/w_editable_label.ml:66-71`:

> `gtk_editable_get_text` is transfer-none and copies one short string into OCaml, which is
> precisely the cost `w_entry.ml` already pays on every idle frame for every entry in the
> tree.

The string copy is not the whole cost. Reaching the interface goes through
`W_entry.editable` = `W.Editable.from_gobject` (`w_entry.ml:13`), whose stub
(`.ocgtk-src/ocgtk/src/gtk/generated/ml_editable_gen.c:251-263`) does a `g_type_is_a`
check, a `g_object_ref`, and `caml_alloc_custom` of a finalised wrapper — so each of the
four editable widgets allocates a finalised custom block, takes a GObject reference and
schedules an unref on **every idle frame**, on top of the `caml_copy_string`.

In absolute terms this is negligible (tens of nanoseconds per widget per frame), and I am
not proposing a change. But this comment, together with `docs/m2-backlog.md:305-308`, is
the milestone's record of what an idle frame costs per entry, and that record should be
accurate if the backlog item is ever picked up — the fix it names (generalising
`w_text_view.ml`'s cache) removes the ref and the wrapper allocation as well as the
comparison, which makes it a better trade than the note currently implies.

## The entry-NUL question — recommendation

The question parked by Task 16 (`docs/m2-backlog.md:157-163`): should
`entry` / `search_entry` / `password_entry` refuse an embedded NUL the way `text_view` and
`editable_label` do?

**Recommendation: yes — refuse, and put the refusal in `W_entry.set_text_if_needed` so all
four `GtkEditable` widgets get it from one place. Not a merge blocker; the first item of
the post-merge fix wave or of M3.**

Confirmed at HEAD, so the decision rests on facts rather than on the backlog's summary:
`Editable.set_text` is `String_val(arg1)` into `gtk_editable_set_text`
(`ml_editable_gen.c:28-33`), so the C string terminates at the first NUL; `needs_text`
(`w_entry.ml:33`) compares the read-back against the model's full string, so it is true on
every frame; and `Patcher.reassert_only` runs under the 60 fps tick that `Loop`
(`src/loop.ml:55`) and `Embed` (`src/embed.ml:153`) both start by default. The per-frame
rewrite is real and is not rate-limited by anything.

Three things I would add to what the backlog records:

1. **It is worse on a search entry than the backlog says.** Every frame's write calls
   `W_search_entry.set_text` (:33-35), which re-arms GTK's `search_delay` timeout and
   replaces the echo record. At 60 fps the 150 ms debounce is reset every 16 ms and never
   elapses, so `Attr.on_search_changed` **never fires at all** on that widget — not "fires
   spuriously", never fires. A filter-as-you-type box with a NUL anywhere in its model text
   is silently dead, and the one signal that would have told the application it was dead is
   the one that is suppressed.

2. **It is the milestone's only silent, permanent, unbounded divergence.** Everything else
   is refused and reported (text view, editable label, calendar, drop-down), clamped by the
   library at a cost of one write (`capped`), or rejected at the constructor (level bar
   bounds, calendar marks, `~selected < -1`). The entries are not a documented tolerance
   like `max_length`; they are the one case where the library keeps writing forever and
   says nothing.

3. **The asymmetry is arbitrary from the application's side.** `Node.editable_label ~text:s`
   refuses and reports; `Node.entry ~text:s` melts. Both write through the *same function*.

The backlog's counter-arguments answered:

- *"A NUL is a caller bug."* So is a `~date` in year 0 and a `~selected` past the end, and
  both are refused-recorded-reported rather than tolerated, on the stated ground that the
  library should say what happened instead of diverging in silence. The `max_length`
  precedent does not transfer: truncating at `max_length` is the widget's own rule applied
  to the model's text — GTK would truncate a *typed* string identically, so tolerating it
  is honest — whereas a NUL truncation is a C-string artefact of a value the widget cannot
  represent, which is the text view's case exactly.
- *"Three more per-widget caches are a cost."* Only under the copying described in I2. Put
  `unwritable` (NUL only — invalid UTF-8 stays written, since `w_editable_label.ml:42-49`
  measured that a `GtkEditable` round-trips the bytes) and the memo inside `W_entry`,
  beside `set_text_if_needed` and `needs_text`, and one cache serves entry, password entry,
  search entry **and** editable label — whose private copy (`w_editable_label.ml:72-126`)
  then deletes. Net: four caches become three, and the patcher's four `interest` arms stay
  four (`Editable`, `Text_view`, `Drop_down`, `Calendar`) rather than becoming seven.

Sizing, for the fix wave: `unwritable` + memo + `take_report` moved into `w_entry.ml`
(~50 lines, most of it lifted from `w_editable_label.ml`), `w_editable_label.ml` loses its
cache and calls the shared one, one `interest` constructor replacing `Editable_label` with
`Editable` and covering four kinds, one live block, and the README's three-bullet section
(:379-395) collapses to two rules: *every `GtkEditable` widget refuses a NUL and nothing
else; the text view additionally refuses invalid UTF-8.*

If the fix wave has no room for that, the cheap fallback closes the worst half without any
new machinery: compare against `String.prefix text (String.index text '\000' |> …)` in the
entries' `reassert`, on `capped`'s own precedent, so the divergence costs one write instead
of one per frame. It stays silent, which is why I would not choose it — but the per-frame
rewrite is the part that is a defect rather than a policy, and it should not survive the
milestone in either form without at least M4's sentence in `node.mli`.

## Verdict

**Approve, with fixes.** No Critical, and nothing in the controls code needs to change to
merge. The discipline holds across all nine widgets and the four refusal mechanisms agree
with each other on every rule I could compare them on.

For the fix wave, in order:

1. **I1** — one sentence in `node.mli`'s `editable_label` block and a clause in
   `attr.mli:596-601`. Doc-only, and the only finding here with a user-visible
   consequence that today's docs do not warn about.
2. **M1** — correct or delete `vtree/node.ml:278-280`; the mli's sentence at :472-475 is
   the one to copy.
3. **M3, M4** — a sentence each; M4's wording depends on the entry-NUL decision, so take
   them together.
4. **M2** — one line at `Node.entry`, on the file's own established rule.
5. **M5** — two clauses in one comment.

**I2 and the entry-NUL question are one decision, and I would take it now rather than
carry it**: refuse, in `W_entry`, as the first item after the merge. Deciding it against
the refusal is defensible only if `node.mli` gains M4's sentence in the same breath, since
the current state is that the library's primary reference does not mention its own worst
silent failure.

---

# Re-review (fix wave)

Re-checked at `36aa26c00be7d53b960a6475d2746b4bd2eac4d4`, against `f06a615..36aa26c`.
Scope limited to my own findings and to whether the factoring introduced divergence.
Read-only; nothing built or run.

## Disposition

| | finding | status |
|---|---|---|
| I1 | `~editing` has no "pair it with the attr" warning | **taken**, `node.mli:1311-1322` and `attr.mli:617-623` |
| I2 | four hand-copied refuse-record-report implementations | **taken**, `src/widgets/refusal.ml` + `.mli` |
| — | entry-NUL recommendation | **taken**, in the recommended form |
| M1 | `node.ml` says GTK clamps a level bar's `~value` | **taken**, `node.ml:293-303` |
| M2 | `capped` blind to GTK's 65536 clamp; `~max_length` unvalidated | **taken**, `w_entry.ml:49-57` + `node.ml:145-149` |
| M3 | parked-refusal behaviour documented for the drop-down only | **taken**, four places in `node.mli` |
| M4 | no NUL sentence in `node.mli` for the three entries | **taken**, `node.mli:204-220, 251-253, 285-290` |
| M5 | idle-frame cost note understates the interface cast | **taken**, folded into `docs/m2-backlog.md:408-419` |

## The shared module preserves every reset rule I traced

`Refusal.Make (V : Value) (E : Extra)` (`refusal.ml:22-90`) is the mechanism once, and the
four call sites are `Make (String) (No_extra)` in `w_entry.ml:119`, `Make (String) (Written)`
in `w_text_view.ml:93`, `Make (Int) (No_extra)` in `w_drop_down.ml:92` and
`Make (Date) (Fired)` in `w_calendar.ml:117`. Checked line by line:

- **`already_refused` is unchanged in behaviour, including the adoption.** `refusal.ml:66-78`
  is `phys_equal` then `V.equal` then adopt — the text view's and editable label's version
  verbatim. For the two immediate value types the `phys_equal` arm always wins, so the
  adoption never allocates a `Some` for an `int` or a `Date.t`; the drop-down's and
  calendar's "no string to adopt" property is preserved by the ordering rather than lost to
  generalisation.
- **The parked-frame O(1) idle frame holds for all four.** Entry family:
  `W_entry.needs_write` (`w_entry.ml:132-134`) asks the memo *before* `needs_text`, so a
  parked entry does no `from_gobject`, no `get_text` and no compare. Text view
  (`w_text_view.ml:371-374`): memo before `holds`, so `refresh` and the whole-buffer read
  are still skipped — the comment's 518× measurement still describes the code. Drop-down
  (`w_drop_down.ml:236-239`): memo before `get_selected`. Calendar
  (`w_calendar.ml:287-289`): memo before `read_date`. All four still hoist the whole
  decision outside `Widget_impl.batch_if`, so a parked frame pays no freeze/thaw.
- **The drop-down's `forget_refusal` survives intact**, which was the rule I was most
  concerned about: it is `Refused.forget_refusal` (`w_drop_down.ml:95`), still called from
  the items branch of `update` (`w_drop_down.ml:293`), and `refusal.ml:87-89` implements it
  over `find_opt` so it is a no-op on a widget with no entry — observably identical to the
  old mint-then-clear. The invariant is now *stated* rather than only practised:
  `refusal.mli:27-32` says the memo may be consulted before the widget is read precisely
  because the predicates are pure, and that a widget whose refusal is relative to something
  else must call `forget_refusal` from whatever changes that answer. That is the thing my
  I2 said was enforced nowhere.
- **The private record is doing real work.** `type t = private { mutable refused; mutable
  unreported; extra }` (`refusal.mli:59-63`) means no call site can assign `refused` or
  `unreported` directly — every one of them goes through `refuse` / `landed` / `take_report`.
  The per-widget mutable state that legitimately differs rides in `extra` (the text view's
  `{ text; stale }`, the calendar's `{ last_fired }`), which is an ordinary record, so
  `w_text_view.ml:229-230` and `w_calendar.ml:233` still mutate what they own. The
  compiler now enforces the discipline the four copies kept by convention.
- **One improvement I did not ask for, and it is the right one.** `take_report`
  (`refusal.ml:55-64`) uses `find_opt` instead of `state`, so asking a widget that has never
  refused anything no longer mints an ephemeron entry — and in the text view's case no
  longer mints one with `stale = true`, which had the next frame paying a whole-buffer read
  for a question nobody asked. Uniform across all four now.
- **Report plumbing and memo semantics unchanged.** `refuse` sets both fields, `take_report`
  clears only `unreported`, `landed` clears only `refused` — so a refusal is still reported
  once per contiguous run of the value and the memo outlives the report. The patcher's arms
  are still exhaustive at all three sites (`patcher.ml:179, 193, 346`), with
  `Editable_label` replaced by `Editable` covering `Entry | Password_entry | Search_entry |
  Editable_label` (`patcher.ml:193`) and asking the one table
  (`W_entry.take_report`, `patcher.ml:259`). I checked that `reassert` precedes
  `enqueue_fixups` on all three paths that can refuse — mount (`create` → `note_interest`),
  patch (`reassert` → `note_interest`), and `reassert_only` — so nothing is recorded a frame
  before it can be read.

## The NUL refusal itself

`W_entry.set_text_if_needed` (`w_entry.ml:144-165`) now takes the `Widget.t` rather than the
`W.Editable.t` — necessary and correctly reasoned at :136-138, since `from_gobject` mints a
fresh wrapper and the memo must key on the value the patcher retains. All four kinds route
through it (`w_entry.ml:231, 274`; `w_password_entry.ml:25, 55`; `w_search_entry.ml:33`;
`w_editable_label.ml:109`), and `needs_text` now has no caller outside `needs_write`, so
there is no longer a way to reach the write while bypassing the memo.

Two consequences I specifically checked:

- **The search entry's echo is not armed by a refused write.** `set_text`
  (`w_search_entry.ml:33`) records an echo only when `set_text_if_needed` returns `true`, and
  a refusal returns `false` — so a refused write arms no debounce and leaves no record to
  suppress a later genuine search. Correct, and the reason is written down at
  `w_entry.ml:140-143`.
- **The editable label's half-enforcement is now deliberate and documented.** `writes_text`
  is `W_entry.needs_write w p.text` while `writes_editing` is computed independently
  (`w_editable_label.ml:104-106`), so a parked text leaves `~editing` under control. That was
  the loose end in my M3, and `node.mli:1289-1292` and `w_editable_label.ml:99-102` now both
  say so in as many words.

`capped` (`w_entry.ml:48-73`) clamps to 65536 before comparing, which closes M2's per-frame
rewrite; the constructor rejects a negative `~max_length` and deliberately admits a large one
(`node.ml:120-149`). Both the clamp and the choice not to reject above 65536 are argued
rather than asserted, and the argument is right — GTK's own answer to a large value is to
clamp, so tolerating it is honest as long as the comparison knows.

## Divergence the side-by-side table would now flag

Two, both cosmetic; neither is a behaviour difference.

### N1 — the counts left over from the merge are wrong in five places

`refusal.mli:7` ("Five widgets have the same problem"), `w_text_view.ml:79`,
`w_drop_down.ml:85` and `w_calendar.ml:110` (all "the five widgets"). The mechanism now
serves **seven kinds** — entry, password entry, search entry, editable label, text view,
drop-down, calendar — through **four** tables and **four** patcher arms. Five is neither
number, on any reading I could construct; it looks like the pre-merge count of files that
would each have had a copy.

The same merge left the arm numbering inconsistent inside one function:
`patcher.ml:249` still reads "The third and fourth callers of `ctx.report`" over the
`Calendar` arm *alone* — the old fourth was `Editable_label`, which became `Editable` — while
`patcher.ml:256` calls `Editable` "the fifth caller". Four arms, numbered 1, 2, "3 and 4", 5.

Exactly the class of stale count this milestone has already corrected twice (37 → 36
`w_*.ml`, three → six `Payload` signals), so worth the same treatment.

### N2 — `Refusal.Make` is applicative, so two applications with the same arguments would share a type but not a table

`refusal.mli:58`. OCaml functors are applicative by default, so
`Refusal.Make (String) (Refusal.No_extra).t` denotes the same type wherever that path is
written, while the `Cache.create 8` in the body (`refusal.ml:36`) runs once per application
and gives each its own table. A future widget that writes
`module Refused = Refusal.Make (String) (Refusal.No_extra)` in its own file would therefore
get a `t` equal to `W_entry.Refused.t`, and
`W_entry.Refused.refuse (W_foo.Refused.state w) v ~reason` would typecheck — recording a
refusal in one table while the patcher's arm reads the other. A refusal recorded and never
reported: the silent-inertness class this milestone has been rigorous about everywhere else.

**Nothing reaches it today** — the four applications have pairwise distinct argument pairs
(`String`/`No_extra`, `String`/`Written`, `Int`/`No_extra`, `Date`/`Fired`), so there are
zero collisions at HEAD. It is a hardening note for the fifth application, and the fix is one
character: make `Make` generative (`module Make (V : Value) (E : Extra) () : sig … end`), so
each application gets its own type and mixing two is a compile error rather than a silent
write into the wrong record. `src/widgets/` has no `.mli` except `refusal.mli`, so every
widget module's `Refused` is reachable from every other widget file, which is what makes the
mistake spellable at all.

## Verdict

**Approve.** All eight findings taken, and taken in the form I would have chosen — the
refusal module is the factoring I argued for rather than a mechanical extraction, and the
private record plus the `forget_refusal` contract in `refusal.mli:27-32` make the discipline
compiler-enforced where it was previously enforced by four comments agreeing with each other.
The entry-NUL change landed in exactly the recommended shape: the refusal lives in the one
function all four `GtkEditable` widgets already wrote their text through, the cache count went
from four to four rather than to seven, and `w_editable_label.ml`'s private copy is gone.

I re-traced every reset rule from my original table against the shared implementation and
found no divergence: the parked frame is still O(1) in all four, the drop-down's items-change
invalidation is intact and now stated as the module's one documented exception, and the report
channel keeps its once-per-distinct-value semantics.

N1 (stale counts, five places) and N2 (make `Make` generative) are both cosmetic/hardening and
should ride with whatever the next docs pass is. Neither blocks the merge, and I would not hold
the branch for either.
