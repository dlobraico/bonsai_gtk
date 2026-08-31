# Task 15 review — README, the spec's M2 amendments, and `docs/m2-backlog.md` (`3a87d1c..055c70e`)

Reviewer pass over `git diff 3a87d1c..055c70e` (14 files, +1362/−673), read in full, against
`task-15-brief.md`, `progress.md` in full, `task-15-report.md`, and the fourteen
`task-N-review.md` files. Fact-checking review on M1 Task 11's bar: every count derived from
the code rather than read off the report, every error string grepped out of `src/`, every
commit hash resolved, every binding claim checked against `.ocgtk-src` at the pinned
`649498b4`.

**Gates run.** `nix develop -c dune build` → exit 0. `nix develop -c dune test` → exit 0. No
golden moved, as expected for a docs change.

## Summary

The docs are accurate on nearly everything that was checkable, and the two counts the
implementer refused to take from the plan (37 constructors, nineteen actions) are both right
where the brief and the plan were both wrong. The README's structure — Input and Embedding as
their own sections, Limitations regrouped under five headings with the untested-input gap
first — is a real improvement over a flat list that had grown to twenty bullets, and the
click/key gap is stated more honestly here than the brief asked for.

Three factual errors survive, all one-or-two-line fixes, none of them blocking:

1. **spec §6.4 says three `Payload` signals exist; six do.** The amendment copies a stale
   sentence out of `signals.mli` that Tasks 6, 7 and 8 invalidated.
2. **README says `CheckButton.set_group` is unbound.** It is bound in the pinned ocgtk, and
   was bound at M1's pin too. This one is carried from M1's README rather than introduced
   here, but Task 15 rewrote the bullet's section and re-verified "all of them".
3. **Limitations omits the TextView/EditableLabel refuse-record-report rule**, while
   documenting both of the analogous refusals (calendar year 0, drop-down stale index) — and
   the Text row's controlled-write sentence implies the write always happens.

Six Minors, mostly precision. The `w_list_box.ml` prohibition rewrite (carry 5) is correct
against `.ocgtk-src@649498b4` on every clause I checked, including the "three of its four
callers" claim, and the `live_tree.ml` sweep the implementer added off its own bat (deviation
5) is right to have been added.

## Per-deviation judgement

**1. "thirteen" → nineteen actions. Accept, and it is the right call.**
`test_lib/bonsai_gtk_test.mli:6-204` has exactly nineteen constructors; I enumerated them and
the README's three-row split (M1 five / M2 signals nine / M2 controllers five) partitions them
exactly. The brief and the plan are both wrong and the code wins, which is the M1 Task 11
rule. The number is carried consistently into spec §9 and the backlog's *API shape decisions*.

**2. `LevelBar` under Display, not Pickers. Accept.** `vtree/events.ml:19` puts `Level_bar`
in the emits-nothing arm with an explicit comment that it has no interaction at all. Filing
it beside two controlled inputs would mislead exactly the reader scanning for something to
attach a handler to. Correct, and correctly argued.

**3. Limitations regrouped under five headings. Accept.** Nothing was dropped that M2 did not
close — I diffed the old bullet list against the new headings item by item. Putting the
untested-input gap first is the right editorial call given the brief's own review focus.

**4. Two stale README claims corrected rather than carried. Accept, both verified.**
`Patcher.reassert_only` is real and `Driver.frame` takes it on the phys-equal path
(`src/driver.ml:86-88`); the placement attrs do raise since Task 3, and the one case that is
still inert (`Attr.measure_overlay` on an overlay's *main* child) is named — which matches
`vtree/placement.ml:13-17` exactly. Mirroring both into the spec (§4.2, §4.3, §5.2 area) is
right.

**5. `src/live_tree.ml` outside the brief's file list. Accept.** Three comments there made
the same stale claim the prohibition comment did; correcting one and not the others would
leave adjacent files contradicting each other. Both new claims check out: `get_selected_rows`
now sinks (`.ocgtk-src/ocgtk/src/gtk/generated/ml_list_box_gen.c:235`,
`Val_GList_with(..., g_object_ref_sink(_tmp->data))`), and `get_selected_item`'s two halves
really are split — `ml_drop_down_gen.c:185` now has the `g_object_ref_sink`, while `:186`
still returns `ml_gobject_val_of_ext(result)` where `drop_down.mli:63` promises an `option`
and `wrappers.c:213` has the `_option` variant two functions away. The comment says precisely
that.

**6. Nine references updated, the two plan documents left alone. Accept.**
`grep -rn 'm1-backlog'` outside `_build`/`.git`/`.ocgtk-src` now returns only the two
deliberate mentions in `docs/m2-backlog.md:8-9` and the M1/M2 plan documents. The argument
(a plan is a dated record, and the M2 plan's Task 15 entry *is* the instruction being
followed) is correct.

**7. `Patcher.require_slots` off the patch path filed, not fixed. Accept.** A patcher
behaviour change with no review round behind it does not belong in the docs commit. It is
filed under *Do first in M3* with the review's own "the one I would take" framing intact.

**Report nit (not a finding against the deliverable):** §"Files" says "five one-line path
updates" and then names six files; the diff has eight hunks across those six. And §1's table
says "48 `Attr.Name.t` names in all: 20 widget-wide (19 named + the nameless `Css_class`), 6
placement, 18 signal, 5 controller" — those add to 49 unless the reader notices that
`Css_class` is not one of the 48. Both are report-only.

## Backlog reconciliation (§3 of the report)

I grepped all fourteen `task-*-review.md` files for "backlog" (48 hits) and read every hit
with context. **Every explicit "worth a backlog line" / "record this" instruction a review
gave is in the file**, at the section the report's table says:

- task-2 M1 (phys-equal fast path unpinned) → *Tests worth adding*, and correctly **updated**:
  Task 2 made the fast path narrower, so the flip is a performance change now, not a no-op.
- task-3 M6 (placement granularity) → *Tests worth adding*, merged with task-6 M7 so it names
  both instances (overlay main child, list-box placeholder). Matches
  `vtree/placement.ml:13-17`.
- task-4 M4 (untestable `Click_event` doc claims) and M6 (controller GClosure roots the
  widget) → *Carried → Diagnostics*, the latter cross-linked to the GC/lifetime test as the
  review asked.
- task-6 M5 (`Activate_row` on a `row_activatable false` row) → *Do first in M3*.
- task-7 M4, M2, and the no-functor decision with its standing trigger → all three present.
- task-9 carry 3 (`char*` leak) → rewritten as the *ocgtk fork → Still open* headline item
  with the per-keystroke number the re-review asked for.
- task-10 I1 (`GtkStringList` leak) → correctly **struck** and moved to *Fixed in M2's fork
  round*; task-10 I4 → discharged into the README's *Structure and lifecycle* opener.
- task-12 rr N1 → rewritten from "hangs" to the measured memory-safety framing, and moved to
  *Fixed in M2's fork round*, which is right now that the fork guard is pinned.
- task-13 rr N8/N9 → taken in this commit (see below). The XTEST item is promoted to the
  second bullet of *Tests worth adding* with the reviewer's "it would close rather than
  compensate" framing.
- task-14: all of M3/M4/M7/M9/M10/M11, rr N1–N6, and item 4d #1–#7 are present, with 4d #5's
  fixed half separated from its unfixed half and M10's 9-not-11 correction carried.

**Hashes.** Every commit named in *Closed during M2* resolves on `m2` and its message matches
the claim: `09ee6f7`, `1daa1b5`, `ee64cc6`, `b458449`, `a9b7b34` ("the placement table moves
to vtree, and the handle reads it" — exactly what the entry attributes to it), `9c081e5`,
`629185c`, `c5fb8a2`, `e7a1e7e`, `3a87d1c`, `e9e7793`. The fork's `a913c307` and `649498b4`
resolve in `.ocgtk-src`, and `git rev-list --count d98d9397..649498b4` = **12**, matching
"Twelve commits sit on it beyond M1's pin".

**Do-first-in-M3 is sensible.** The seven seeded items are all real and all closable, and the
`after_of` entry is the best thing in the file: it records that M1's prediction was *wrong*,
names what bit instead (`apply_selection`, 24 ms → 0.39 ms), and says why that matters for
where M3 spends its next optimisation. That is a backlog earning its keep.

**`docs/m1-backlog.md`'s disposition:** deleted, content rolled forward, header explains the
rename. See Minor 4 for the one thing the header claims that is not true.

## Critical

None.

## Important

### I1. spec §6.4's amendment says three `Payload` signals exist; six do

`docs/superpowers/specs/2026-08-28-bonsai-gtk-design.md`, §6.4 M2 amendment:

> `Payload : ('p, 'r) payload -> spec` is for the signals whose arguments cannot be recovered
> afterwards. Three exist: `GtkListBox::row-activated` …, `GtkGestureClick::pressed` …, and
> `GtkEventControllerKey::key-pressed`.

Six `Payload` specs ship:

| site | signal |
|---|---|
| `src/widgets/w_list_box.ml:274` | `GtkListBox::row-activated` |
| `src/widgets/w_flow_box.ml:252` | `GtkFlowBox::child-activated` |
| `src/widgets/w_notebook.ml:228` | `GtkNotebook::switch-page` |
| `src/controllers.ml:139` | `GtkGestureClick::pressed` |
| `src/controllers.ml:242` | `GtkEventControllerKey::key-pressed` |
| `src/controllers.ml:263` | `GtkEventControllerKey::key-released` |

The last one is not an oversight in the code — `src/controllers.ml:260-262` says so outright:
"It is still a `Payload` rather than a `Read_back`: the keyval is a callback argument and
nothing on the controller remembers it afterwards." The two container signals are the same
shape as the list box's for the same reason (the child is gone by the time anything could
look for it, `w_flow_box.ml:245-250`, `w_notebook.ml:221-226`).

The sentence is copied near-verbatim out of `src/signals.mli:76-78` ("Three exist in M2"),
which was written at Task 4/5 and which Tasks 6, 7 and 8 then invalidated without updating.
Task 15 propagated a stale claim into the spec instead of deriving the count, which is the
one thing the brief said not to do.

**Failure scenario.** A reader planning M3's containers reads §6.4, concludes that
`Payload` is the exceptional arm used three times and that a container's activation signal is
normally a `Read_back`, and writes a `Read_back` spec for the next `child-activated`-shaped
signal — the exact mistake `w_flow_box.ml`'s comment exists to prevent. The correct
generalisation ("every signal whose argument is a child widget, plus every controller
signal") is invisible from the amendment as written.

**Fix:** say six, list them, and fix `signals.mli:76` in the same breath (it is one word plus
two clauses, and the mli is the source the spec was copied from).

### I2. README says `CheckButton.set_group` is unbound; it is bound

`README.md:389-390`:

> - **No radio groups** (`CheckButton.set_group` is unbound): model the exclusive choice in
>   Bonsai state and render the `active` flags from it.

At the pinned fork (`ocgtk-pin.json` = `649498b4`):

```
.ocgtk-src/ocgtk/src/gtk/generated/check_button.mli:42:
external set_group : t -> t option -> unit = "ml_gtk_check_button_set_group"
.ocgtk-src/ocgtk/src/gtk/generated/toggle_button.mli:23:
external set_group : t -> t option -> unit = "ml_gtk_toggle_button_set_group"
```

Both are also present at M1's pin (`git show d98d9397:…/check_button.mli` has the same line),
so this is a claim that was wrong when M1's README first made it (`886b1d5`) and is still
wrong. It is not in the report's eight-item spot-check table, so it was not among the
Limitations claims that were actually verified — despite §1 saying "The brief asks for three;
I checked all of them."

**Failure scenario.** Two readers make different wrong decisions. An application author
looking for radio buttons is told the *binding* cannot do it, so they do not go looking for
`Node.check_button ~group`; and whoever plans M3 rules a `~group` prop out as blocked on fork
work that does not exist. The advice that follows the parenthetical (model the exclusive
choice in Bonsai state) is sound and should stay — a controlled `active` flag really is the
right shape for a declarative tree — but the *reason* is false and is doing the arguing.

**Fix:** replace the parenthetical with what is actually true — `Node.check_button` exposes
no `~group`, GTK's grouping is a mutable pointer between widgets rather than a prop, and
modelling it in Bonsai state is the declarative answer. Nothing about ocgtk.

### I3. Limitations omits the TextView / EditableLabel refuse-record-report rule

The README's Limitations documents the two other refusals in the milestone — the calendar's
year-0 date (`README.md:371-373`) and the drop-down's stale index (`:378-382`) — and states
the general rule at `:410-417`. It says nothing about the third, which is the one an
application is most likely to hit:

- `src/widgets/w_text_view.ml:159-179` — text that is not valid UTF-8, or that contains an
  embedded NUL, is **refused before the write**, the buffer and the cache are left untouched,
  and it is reported once through `Patcher.ctx.report`. The message is
  `"text contains a NUL byte, which GTK would silently truncate at; the write was refused and
  the buffer was left as it was"`.
- `src/widgets/w_editable_label.ml:55` — the same for a NUL in an editable label's `~text`.

This is not covered by the general rule bullet, which is about *states a correct model passes
through* (a stale index, a key whose child has not arrived) and names only those two. A
refused UTF-8 write is the opposite case: a value no later frame makes valid, which is not
rejected either.

Worse, the Widgets table's Text row (`README.md:95`) makes the affirmative claim that
contradicts it: "controlled: the widget is written only when the model disagrees with what it
currently shows" — which says the write happens whenever they disagree.

**Failure scenario.** An application renders a `Node.text_view` from a file it loaded, or
from a network payload, or from a field that can carry a NUL. The buffer silently keeps the
previous document, the model and the widget diverge permanently, and the only evidence is one
stderr line at the moment of the first refusal. The developer reads the README's controlled
guarantee, concludes the divergence must be a bonsai_gtk bug, and goes looking in the patcher.
`vtree/node.mli` has the rule; the README — the document that lists the other two refusals —
does not.

**Fix:** one bullet under *Widgets*, beside the `TextView` caret one.

## Minor

**M1. "Five new event-value modules", followed by six names.** Spec §7's M2 catalogue: "five
new event-value modules (`Phase`, `Modifiers`, `Click_event`, `Keyval`, `Key_event`,
`Key_response`)". Six are listed and six ship — all six are re-exported at
`src/bonsai_gtk.mli:45-51` and all six were added in M2 (`9c081e5` for the first three,
`7ba161a` for the last three). The same "plus the five event-value modules" appears in
`docs/m2-backlog.md`'s *Plumbing* section. The enumerated list is right, so nobody is misled
about *which*; only the numeral is wrong — but in a section whose whole point is auditable
counts, and next to a correct "four new enum modules", it is the one number a reader would
quote.

**M2. §11's "Each message names the other entry point" is true of one of the two.**
The amendment's last bullet: "**A window root under `embed`, and a non-window root under
`start`** (§4.1). Each message names the other entry point". `src/driver.ml:54-58` (the embed
side) does: "Use Bonsai_gtk.start for a tree that owns its window…". `src/driver.ml:49-52`
(the start side) does not: `"Bonsai_gtk: the root node must be a Node.window, got %s"`. That
is the only other root message in `src/`. A reader of the spec would believe the diagnostic
is symmetric and would not add the missing pointer — which is the pointer that matters most,
since a caller with an existing GTK app is the one who needs to be told `embed` exists.
Either fix the message (one clause) or scope the sentence.

**M3. "The one container whose children move in place" — a box does too.**
`README.md:94` ("real reordering — the one container whose children move in place, since it
has `gtk_notebook_reorder_child`") and spec §7 ("the one container in the library whose
children really move"). `src/widgets/w_box.ml:39-45` is `move = Some (… W.Box.reorder_child_after …)`,
and its own comment says "A box is one of the two containers that can really reorder (the
other is M2's notebook)". `w_notebook.ml:349-351`'s "the one real reorder" is scoped to its
two keyed siblings (list box and flow box do remove-and-re-insert), and the scope was lost in
the copy. A reader with a reorderable list would conclude a `box` cannot preserve widget state
across a reorder, and reach for the wrong container. The Limitations bullet at `:427-433` is
fine — `Stack`/`Grid`/`Overlay` really are the three `move = None` containers, which I checked.

**M4. "`git mv` carried the history" is not true in practice.** `docs/m2-backlog.md:10`.
The rename similarity is 9% (`git diff -M05% --summary` reports
`rename docs/{m1-backlog.md => m2-backlog.md} (9%)`), so `git log --follow docs/m2-backlog.md`
returns exactly one commit and default rename detection never fires. The very next clause —
"The M1 history is under the old path" — is true and is the useful half; the `git mv` claim
should go, or say plainly that the rewrite is total and `--follow` will not find it.

**M5. The search-entry echo claim overstates, and this commit's own backlog says so.**
`README.md:386-388`: "the record is consumed either way and can never suppress more than the
one signal the write armed." `src/widgets/w_search_entry.ml:41-46` documents the exception —
a write that *empties* the box makes GTK emit `search-changed` synchronously inside the patch,
`Signals.dispatch` drops it on `in_patch` before `fire` can consume the record, and a `""`
record survives to be matched against a later `""` emission. `docs/m2-backlog.md` carries this
as an open Behaviour item ("A search-entry write that empties the box leaves its echo record
unconsumed"). "Can never" should be "cannot, except when a write empties the box — see the
backlog", or just drop the absolute.

**M6. README's headless-testing guarantee is unscoped where the mli and spec §9 are not.**
`README.md:261-264`: "Every entry point that advances a handle checks — `show`, … and
`recompute_view_until_stable`". The N8 carry taken in this very commit
(`test_lib/bonsai_gtk_test.mli:349-355`) exists precisely because the absolute form is true
only of this module: `Handle.t = Bonsai_test.Handle.t`, so `Bonsai_test.Handle.recompute_view`
still typechecks and still skips the check. Spec §9's amendment carries the caveat in
parentheses; the README does not. A reader following the README who reaches for
`Bonsai_test.Handle` directly for one of the four values this module does not re-export gets
an unchecked handle without being told. Half a sentence.

## Verdict

**Approved with fixes.** No Critical, and nothing here justifies a round of its own — I1, I2
and I3 are one or two lines each and can ride with Task 16, which is the CI pass and is the
natural place for them (I1 also wants the one-word correction in `src/signals.mli:76`, which
is a code file and is why it should not wait for M3).

What the deliverable gets right is the part that is hardest to get right: the counts are
derived, not copied — 37 constructors (38 `val`s in `vtree/node.mli` minus `find_by_test_id`,
and the widget table's nine rows enumerate exactly those 37), nineteen actions, eighteen
signal attrs and five controller attrs matching `Events.for_kind` and `Events.controller_family`
exactly, six placement attrs matching `Placement.reader`, seventeen `Keyval` names plus `f` and
`of_char`. Every §11 message I grepped matches `src/` (placement rejection, the two
container-name-not-found raises with their empty-container carve-outs, `require_child_keys`
across all four constructors, all six constructor-time arithmetic rejections, the key-phase
rejection). `Expert.embed`'s signature is verbatim from `src/bonsai_gtk.mli:142-148` and the
Embedding section agrees with `src/embed.mli` clause for clause. The click/key honesty is
better than the brief required: the README does not merely say the gap exists, it says what is
covered on each side, names the compensating controls, and points the Input section at
Limitations before a reader can rely on it.

The three errors share one cause worth naming for M3's docs task: each is a sentence that was
*carried* rather than *derived* — §6.4's "three" out of `signals.mli`, the radio-group
parenthetical out of M1's README, and the omitted refusal rule out of a Limitations list that
was regrouped rather than re-enumerated against `vtree/node.mli`. The counts, which the
implementer explicitly refused to take from the plan, are all correct. The prose claims, which
were inherited, are where the misses are.
