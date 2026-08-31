# Task 13 — the gallery, and a headless sweep over every M2 widget

**Commit:** `c5fb8a2` on `m2` ("The gallery grows an Input page, and three sweeps count the
tree"), on top of `cff9914` (the plan addendum). One commit; no fix rounds yet.

**Gate:** `nix develop -c ./scripts/ci.sh` → `all green`.

---

## What the sweeps are, and what they found

The brief's framing was right about the hole. `test/handle/test_gallery.ml`'s golden said
"this exact tree still sexps this way"; its header said the tree was *everything*. Nothing
checked the second sentence, which is precisely how Task 10 shipped `Node.drop_down` and
`Node.level_bar` into a file that claimed to name every constructor and named neither
(Task 11 found it by hand). Three sweeps now derive their expectations from the compiler.

### 1. Every `Node` constructor appears

Walks the tree, collects `Kind.Variants.to_name`, subtracts from
`Kind.Variants.descriptions`, prints the remainder, expects `()`. The name is
`Variants.to_name`'s (the OCaml constructor) rather than `Kind.name`'s (the GTK class),
because only the former is derived from the type.

**Drift found: none.** Measured 37 distinct kinds in the tree against 37 constructors —
Task 11's fix had closed the last gap and nothing has been added since. That is a real
result rather than a vacuous one: the same count was printed under a temporary probe to
confirm the walk actually reaches every node.

### 2. Every attr name appears

The brief's test verbatim, over `Attr.Name.all`. **Drift found: 19 of 48 names appeared
nowhere in the tree** — `Margin_start`/`_end`/`_top`/`_bottom`, `Valign`, `Sensitive`,
`Visible`, `Tooltip`, `Opacity`, `Focusable`, `Can_focus`, `Widget_name`, `Cursor_name`,
`On_visible_child_changed`, and all five controller attrs (`On_click`, `On_focus_enter`,
`On_focus_leave`, `On_key_pressed`, `On_key_released`). All 19 are now placed, and **no
name is exempt**: the ones that are legal in only one place (`Grid_cell`, `Row_selectable`,
`Row_activatable`, `Tab_label`, `Page_title`, `Measure_overlay`) sit in the container that
reads them, which the tree already had one of each of.

### 3. The attr the check cannot reach

`Attr.css_class` is the one attr `Attr.name` answers `None` for — a css class is a member
of a set the patcher adds to and removes from (`Attrs.diff`'s `Add_css_class` /
`Remove_css_class`), not a keyed property — so it has no `Name.t` and sweep 2 would pass
with no css class anywhere in the tree. A third expect test closes that half explicitly
rather than leaving it to a reader to notice.

**Mutation-verified.** Removing `Attr.margin 4` and the `Attr.css_class "dim-label"` makes
sweeps 2 and 3 fail naming exactly what went missing
(`(Margin_start Margin_end Margin_top Margin_bottom)` and `()`); both were restored and the
suite re-run.

### 4. The lifecycle sweep — mount, patch, unmount, once per kind

One row per `Kind.t` constructor, the row list counted against
`Kind.Variants.descriptions` (the same idiom `test/test_events.ml` uses for its own
hand-maintained list, for the same reason). Each row builds a `before` and an `after`
differing in a property the kind really has, mounts the subject inside a scaffold through a
real `Bonsai_gtk_test` handle, patches it, and drops it.

What each row asserts:

| | |
|---|---|
| **mount / patch / unmount = ok** | each phase's tree passed the `Placement`, `Events` and key-phase checks — the same two tables the runtime consults |
| **`same_kind=true`** | a prop change makes the patcher *recurse into the widget it has*. A wrong `Kind.name` arm makes a kind answer `false` against itself and be destroyed and remounted on every frame that touches it |
| **`props_changed=true`** | a prop change is not `Kind.equal_props`, so the patcher does not *skip* the update. A missing arm here makes a kind never update at all |
| **`child_ops`** | `Reconcile.diff` over the subject's own child lists, descending through `Slots` |

The coverage table (the golden, trimmed to its shape — the full 37 rows are in the file):

```
Label           mount=ok patch=ok unmount=ok        same_kind=true  props_changed=true  child_ops=-
...
Box             mount=ok patch=ok unmount=ok        same_kind=true  props_changed=true  child_ops=1I/0M/0R/1U
Grid            mount=ok patch=ok unmount=ok        same_kind=true  props_changed=true  child_ops=1I/0M/0R/1U
Stack           mount=ok patch=ok unmount=ok        same_kind=true  props_changed=true  child_ops=1I/0M/0R/1U
List_box        mount=ok patch=ok unmount=ok        same_kind=true  props_changed=true  child_ops=rows=1I/0M/0R/1U
Flow_box        mount=ok patch=ok unmount=ok        same_kind=true  props_changed=true  child_ops=1I/0M/0R/1U
Notebook        mount=ok patch=ok unmount=ok        same_kind=true  props_changed=true  child_ops=1I/0M/0R/1U
Text_view       mount=ok patch=ok unmount=ok        same_kind=true  props_changed=true  child_ops=-
Drop_down       mount=ok patch=ok unmount=ok        same_kind=true  props_changed=true  child_ops=-
Level_bar       mount=ok patch=ok unmount=ok        same_kind=true  props_changed=true  child_ops=-
Calendar        mount=ok patch=ok unmount=ok        same_kind=true  props_changed=true  child_ops=-
Editable_label  mount=ok patch=ok unmount=ok        same_kind=true  props_changed=true  child_ops=-
Overlay         mount=ok patch=ok unmount=ok        same_kind=true  props_changed=false child_ops=overlays=1I/0M/0R/1U
Window          mount=ok patch=ok unmount=n/a(root) same_kind=true  props_changed=true  child_ops=-
Native          mount=ok patch=ok unmount=ok        same_kind=true  props_changed=true  child_ops=-
("kinds with no row" (missing ()))
("a prop change is not an update" (remounted ()) (skipped (Overlay)))
```

All eight M2 kinds have all three phases. **Two exceptions are named rather than skipped**,
on the same rule the attr sweep follows:

- **`Window`** is legal only at the root — `Patcher` raises for one anywhere else, and this
  handle is documented not to check that — so its row puts the subject *at* the root and
  has no unmount phase. Putting a window in the scaffold's child slot would have had the
  sweep certify a tree the runtime refuses, which is worse than no sweep.
- **`Overlay`**'s props are `unit` ("a `GtkOverlay` has no properties of its own: it is
  entirely its children"), so it is the one correct member of the `skipped` list. Its being
  *named there* is what stops a second kind joining it silently.

Two things the sweep's construction turned up while being written:

- **`Native`'s first draft asserted nothing.** `Kind.equal_props`'s `Native` arm compares
  payloads with `phys_equal`, and `Native.Unit` is a constant constructor — one shared
  value — so two nodes carrying it are equal and the row changed no prop at all. The row
  now uses a payload extension of the test's own carrying a string.
- **`child_ops` stopped at `List` and reported `-` for the three containers M2 added.** A
  list box's rows, a flow box's children and an overlay's layers all reach their child list
  under a `Slots` name. It descends now.

**What the sweep does not prove**, stated in the file as well: anything GTK's. There is no
widget, so "unmount" is the node leaving the tree and nothing more — no `destroy`, no
disconnected signal, no removed controller. The real create/update/destroy sweep is
`test/live/live_patcher.ml` and the per-widget live files.

### 5. A doc/behaviour drift the sweep found on the way

Writing `run_row` needed to know which handle call runs the validation.
**`Handle.recompute_view` does not.** The `Placement` / `Events` / key-phase checks live in
`Bonsai_gtk_test`'s `Result_spec.view`, which only the *printing* entry points call
(`show`, `show_into_string`, `show_diff`, `store_view`); `recompute_view` runs the
computation and never builds a view. `test_lib/bonsai_gtk_test.mli` said the opposite —
"checked on the first `Handle.show`/`Handle.recompute_view`, and on every later one".

Consequence, and it is not cosmetic: a headless test that drives a component with
`do_actions` + `recompute_view` and `show`s it only at the end has validated exactly one of
its trees, and every tree that existed only between two shows went unchecked.

Fixed: the mli now says what is true and why, and a fourth expect test pins it —

```
recompute_view: accepted
show_into_string: (Invalid_argument "root/0/0: Label does not emit On_toggled")
```

The sweep uses `show_into_string` and discards the string for exactly this reason. The
option of having `Bonsai_gtk_test` stop re-exporting `Bonsai_test.Handle` wholesale and
shadow `recompute_view` with a validating one is on the backlog rather than taken here —
it is a change to `test_lib`'s public surface, which is not this task's.

---

## The gallery, section by section

`examples/gallery.ml` gains one page; the seven that existed are unchanged.

| Page | What it shows |
|---|---|
| Controls | toggle / check / switch / entry / password entry / search entry, and the text view in a scrolled window with the caret-policy demonstration |
| Numbers | scale, spin button, progress bar, drop-down driving the level bar's range and mode, the "add a preset" button that splices the string model, spinner |
| Lists | two keyed list boxes — single-with-activation and multiple-with-selection — a non-selectable header row and a placeholder |
| Grid | keyed flow box of five cards with the grid/list geometry toggle and a selection-dependent toolbar |
| Tabs | keyed notebook with real `Move` ops and the per-page entry whose cursor survives a reorder |
| Layout | paned, scrolled window, frame, expander, revealer, image, center box, the overlay-over-a-spacer size cap |
| Dates | calendar declining weekends (the controlled-prop demonstration), heading-walk marks, editable label |
| **Input (new)** | see below |

### The Input page, and what it demonstrates

**It is load-bearing, not decorative, and the file says so in a comment.** No automated
test in this repository delivers a real click or a real key press. `live_controllers.ml`
proves the controller is attached, named, given the phase the attr asked for, and removed
again; `Bonsai_gtk_test.Action.Click_at`/`Key_press` prove the handler does the right thing
when *something* calls it. The step in between — GTK routing a real button press or a real
keystroke into that handler — is demonstrated here and nowhere else.

Four readouts, each of which must move:

1. **`last click`** — a frame whose child carries `Attr.on_click` with `~button` left at
   its default `0` ("any of them"), reporting `button N, press N, at (x, y), <modifiers>`.
   Middle and secondary buttons included, which a `GtkButton` would never report; the
   coordinates are widget-local, which is what makes a per-card gesture useful.
2. **`last key`** — `Attr.on_key_pressed ~phase:Capture` on the page's outer box, answering
   `Key_response.Propagate_and` for every key but Escape. Capture, so the box sees the key
   *before* the entry inside it; `Propagate_and`, so the entry still receives the text. The
   check is that the readout follows every keystroke **while the text still arrives** —
   that is the whole of what `Propagate_and` means.
3. **`escapes`** — Escape answers `Handled_and`, which consumes the key *and* schedules an
   effect. The counter moves and the entry never sees the key. This is stavekeeper's
   `dialog.ml` shape exactly.
4. **`focus`** — two entries carrying `Attr.on_focus_enter`/`on_focus_leave`; tabbing
   between them names which has it.

`Attr.on_key_released ~phase:Capture` rides along on the same controller (the two key attrs
share one `GtkEventControllerKey` and therefore one phase — asking for two is refused before
anything is mounted).

**Verified as far as this environment allows:** the gallery builds, comes up under `xvfb`
and stays up (`exit=124`), with **zero bytes on stderr** — no `Gtk-CRITICAL`, no
`Gtk-WARNING`. Every page's widgets, the Input page's controllers included, are mounted at
startup because a `GtkStack` builds all its pages. What is *not* verified is the four
readouts moving, which needs a person and a display; `docs/m1-backlog.md`'s real-display
click-through item now describes this page and says exactly what to check.

---

## Carries taken from Task 12

All three the ledger addressed to this task, plus the re-review Minors.

- **(a) The dispose-time-handler rule is now a section of `src/signals.mli`**, above the
  `connection` type where the lifetime rules already live. It states the rule, the measured
  reason (the finaliser re-entry segfaults when the callback allocates; three of three),
  that `src/embed.ml` holds the only `destroy` connection in `src/`, `vtree/` and
  `test_lib/`, why everything else this module connects is unreachable from the collector,
  and the one line a reader needs: a signal added to a `Widget_impl.signals` list is safe by
  construction, a connection made anywhere *else* is the one to check.
- **(b) `Embed.stop` carries the reviewer's sentence.** The wrapper cannot be finalised
  while the backstop is connected — the callback's GClosure holds the driver, the driver's
  `on_root_widget_changed` holds the wrapper — so disconnecting there is what *creates* the
  finalisable state and must happen in the same call. Probe B's numbers are cited. The
  existing "never returns" measurement is kept and extended with the segfault, pointing at
  `Signals`' new section.
- **(c) Re-review Minors:**
  - **N2** — `Patcher.destroy` and `mount`'s `unwind` now cross-reference each other
    ("keep in step with the other"), naming why the four stages are written twice
    (`destroy` has a `live`, `unwind` has only pieces of one) and that `release_kind` is
    the drift-proof half.
  - **N3** — the failed-mount tree in `live_embed.ml` now carries `Attr.on_click` **on the
    box**, not on a sibling. The reviewer's suggested placement would not have worked: the
    raise is `require_specs`', which runs *before* the raising node's own controllers are
    created, so the only way to reach `unwind` with `built_controllers = Some` is for the
    raise to come from a *child* — which means the attr has to be on the parent. The
    comment records that reasoning. Live golden unchanged, as expected.
  - **N4** — `patcher.mli`'s `mount` now says "nothing behind" is about the live tree and
    not about `ctx`: pending fixups and stack claims from completed children survive the
    raise, `abandon_fixups` clears them, `Driver.frame` always calls it, and a direct caller
    must too.
  - **N5** was the reviewer confirming round 1's minors; nothing to do.

---

## Deviations from the brief

1. **Step 3 (`live_events.ml`'s `all_kinds`) needed no change.** It already lists all 37
   kinds — every M2 one included — with the assertion
   `List.length all_kinds = List.length Kind.Variants.descriptions`. Earlier tasks landed
   their own rows. Verified by reading and by the live gate passing.
2. **The embed is not in the gallery.** The lead's message grouped "and the embed" into the
   Input section. It cannot go there: `examples/dune` deliberately links **no ocgtk** into
   `counter` and `gallery` ("an application built with bonsai_gtk never has to name it, and
   these two are where that is demonstrated"), and `Expert.embed` requires the caller to own
   a GTK container, so hosting one would mean linking `ocgtk.gtk` into the gallery and
   destroying the property that dune comment exists to protect. `examples/embed.ml` is the
   embed demonstration, is built and smoked by `ci.sh` alongside the other two, and exits
   124 clean.
3. **The lifecycle sweep covers all 37 kinds, not just the 8 M2 ones.** Same code, wider
   net, and the row list can then be counted against `Kind.Variants.descriptions` — which
   is what makes it compiler-derived rather than another hand-maintained list.
4. **`docs/m1-backlog.md` and `test_lib/bonsai_gtk_test.mli` are outside the brief's file
   list.** The mli edit is a correction of a claim this task disproved; leaving a false
   statement in a public interface after finding it seemed worse than the scope. The backlog
   edits are where the plan says out-of-scope findings go. Both are called out here so the
   reviewer can reverse either.
5. **No test file in `test/handle/` was promoted unread.** The big golden was promoted after
   reading every changed line of its diff (`grep '^[-+]|'`): the only changes are the attrs
   and the page this task added, and no pre-existing prop moved. The sweep goldens were read
   in full before promotion.

## Deliberately not done

- **A synthetic click or key press through XTEST.** The plan closed that question against
  the *binding* (no `GdkEvent` constructor, no argument-carrying emission, no `gtk_test_*`)
  and did not consider driving the X server the live tests already run on. `xdotool` or
  `xte` under the same `xvfb` would deliver a real button press and a real keystroke to a
  real window — the exact step no suite here takes — and would **close** the backlog's "not
  covered" bullet rather than compensate for it. It needs a package in the dev shell
  (`flake.nix`) and a live test mapping widget coordinates to screen coordinates, both
  outside this task's file list. **Recorded in `docs/m1-backlog.md` and flagged here as the
  most valuable single follow-up this task turned up.** `xdotool` is not currently in the
  dev shell (checked).
- **Shadowing `Handle.recompute_view` with a validating one** — see finding 5; a change to
  `test_lib`'s public surface.

---

## Test and gate tails

`nix develop -c ./scripts/ci.sh`:

```
== nix: ocgtk pin builds and passes its tests
== format
== build
== generated opam files are committed
== pure + headless tests
== per-package builds, the way opam --with-test runs them
== live tests (xvfb)
  ... (the expected annotated exceptions, Gtk-CRITICALs and benches; every bench inside
      its bound, ratios 0.36-1.20 against bounds of 1.2-5)
== example smoke
all green
```

Gallery smoke, run alone for the brief's Step 4:

```
exit=124
--- stderr bytes: 0
no criticals/warnings
```

---

## Carries to Tasks 14–16

**To Task 14 (the ocgtk fork):**
- The dispose-time rule now lives in `src/signals.mli` as well as in the plan's Global
  Constraints addendum. The binding fix it points at — the marshaller must refuse to call
  back during finalisation, or the finaliser must defer the unref to an idle — is Task 14's,
  and `signals.mli`'s section says so explicitly ("until the fork's marshaller refuses…, the
  rule is the whole of the protection"). If Task 14 lands that fix, both that paragraph and
  the `Embed.stop` comment want a sentence saying it is fixed rather than mitigated.

**To Task 15 (docs):**
- `README.md:63` says the gallery "renders one of every **M1** widget". It is M1 and M2 now,
  in eight pages, and the Input page is worth a sentence of its own since it is the
  compensating control the Limitations section will be describing.
- The README Limitations section carries Task 4's item (what `Attr.on_click`'s doc promises
  versus what is tested) — the Input page is now the thing to point at.
- `docs/m1-backlog.md` has three new/changed entries to fold into `docs/m2-backlog.md`: the
  `recompute_view` validation gap, the XTEST route, and the real-display click-through item
  now describing this page. One entry (`test_gallery.ml`'s "exactly once") is struck through
  as fixed.

**To Task 16 (final CI pass and the real-display check):**
- **Run `examples/gallery.exe` on a real display and click through the Input page.** All
  four readouts must move: click the card with each button and with modifiers, double-click
  it; type in the first entry and watch `last key` follow while the text still arrives;
  press Escape and watch `escapes` increment while the entry does not receive it; Tab
  between the entries and watch `focus`. That last-but-one is the phase check — a
  `Capture`-phase controller that had been given `Bubble` would let the entry swallow
  Escape, which is the failure mode no plumbing test can see.
- The other seven pages' click-through is unchanged from M1's carry.

---

# Fix round 1

**Commit:** `e7a1e7e` on `m2` ("Fix round 1: four gallery props that ate what the user
typed, and a Handle that checks"). **Gate:** `nix develop -c ./scripts/ci.sh` → `all green`;
gallery smoke `exit=124`, **0 bytes on stderr**.

Both Important findings are fixed. Each turned out to be larger than the review found, in
the same direction, and both extensions were measured rather than reasoned.

---

## I1 — the controlled-prop audit

The reviewer measured one node. I reproduced it and swept the four editable kinds and the
list box, with a throwaway live probe (mount the node, have "the user" type, run one
`Patcher.reassert_only`, read it back — since deleted, along with its `dune` entry):

```
entry ~text:""          typed "hi" -> after one idle frame ""
password_entry ~text:"" typed "hi" -> after one idle frame ""
search_entry ~text:""   typed "hi" -> after one idle frame ""
editable_label ~text:"" typed "hi" -> after one idle frame ""
entry ~text:"hi"        typed "hi" -> after one idle frame "hi"     <- backed: survives
search_entry ~text:"hi" typed "hi" -> after one idle frame "hi"     <- backed: survives

list_box selected at mount:      (0)
after the user selects row 1:    (1)
after one idle frame:            (0)                                <- unbacked: reverted
```

### The audit table

Every controlled prop in `examples/gallery.ml`, and what backs it. "Backed" means: a
`Bonsai.state`, written by **the attr that reports a change to that same prop**.

| # | Page | Node | Prop | Backed by | Verdict |
|---|---|---|---|---|---|
| 1 | Controls | `toggle_button` | `~active:toggled` | `on_toggled set_toggled` | ok |
| 2 | Controls | `check_button` | `~active:checked` | `on_toggled set_checked` | ok |
| 3 | Controls | `switch` | `~active:switched` | `on_toggled set_switched` | ok |
| 4 | Controls | `entry` | `~text` | `on_changed set_text` | ok |
| 5 | Controls | `password_entry` | `~text:""` | **nothing** | **fixed** — state + `on_changed` |
| 6 | Controls | `search_entry` | `~text:search` | `on_search_changed` — the *debounced* signal | **fixed** — `on_changed` writes `search`; `on_search_changed` writes a new `query` |
| 7 | Controls | `text_view` | `~text:note` | `on_changed set_note` | ok |
| 8 | Numbers | `scale` | `~value` | `on_value_changed set_value` | ok |
| 9 | Numbers | `spin_button` | `~value` | `on_value_changed set_value` | ok |
| 10 | Numbers | `progress_bar` | `~fraction` | — | ok, derived: the user cannot move it |
| 11 | Numbers | `drop_down` | `~selected:scale` | `on_selected_changed set_scale` | ok |
| 12 | Numbers | `level_bar` | `~value` | — | ok, derived |
| 13 | Lists | `list_box` (Single) | `~selected:[chosen]` | `on_row_activated` only | **fixed** — `on_selected_rows_changed` added |
| 14 | Lists | `list_box` (Multiple) | `~selected:starred` | `on_selected_rows_changed set_starred` | ok |
| 15 | Grid | `toggle_button` | `~active:as_list` | `on_toggled set_as_list` | ok |
| 16 | Grid | `flow_box` | `~selected` | `on_selected_children_changed set_selected` | ok |
| 17 | Tabs | `entry` (per page) | `~text:(Map.find_exn texts key)` | `on_changed` into the map | ok |
| 18 | Tabs | `notebook` | `~current_page:current` | `on_page_changed set_current` | ok |
| 19 | Layout | `paned` | `~position:220` | — | ok, and **deliberate**: `Node.paned` documents `position` as spec §6.5's one uncontrolled exception, because re-asserting it every frame would make the handle immovable |
| 20 | Layout | `expander` | `~expanded` | `on_expanded_changed set_expanded` | ok |
| 21 | Layout | `revealer` | `~reveal:revealed` | button | ok: `reveal` is animation state, not something the user sets directly |
| 22 | Dates | `editable_label` | `~text:title` | `on_changed` | ok |
| 23 | Dates | `editable_label` | `~editing` | `on_editing_changed set_editing` | ok |
| 24 | Dates | `check_button` | `~active:editing` | `on_toggled set_editing` | ok |
| 25 | Dates | `calendar` | `~date` | `on_day_selected` | ok — the model **declines weekends** on purpose; that is the page's demonstration |
| 26 | Dates | `calendar` | `~marked_days:marks` | buttons | ok: nothing the user does marks a day |
| 27 | Input | `entry` (first) | `~text` | `on_changed set_text` | ok |
| 28 | Input | `entry` (second) | `~text:""` | **nothing** | **fixed** — state + `on_changed` (the review's I1) |
| 29 | app | `stack` | `~visible_child:page` | `on_visible_child_changed set_page` | ok |

**Four defects, one class.** Two the review named; two the audit found. #6 is the worst of
the four and was the least visible: it is on the gallery's landing page, and the box was
unusable within ~16 ms of a keystroke rather than after some later render.

`examples/gallery.ml`'s Controls page now opens with the rule and the measurement, so the
next person adding a page reads it before writing one.

### The permanent artifact

The rule was already in `vtree/node.mli`, and its last clause was the reason four of these
got written: *"…which is the bug the required argument exists to make impossible to write
by accident."* The required `~text` makes the **prop** impossible to forget and says
nothing about the **attr**. That doc now says so, with the cadence (about sixty frames a
second under `Bonsai_gtk.start`'s 16 ms tick, since `reassert_only` runs on every node of
every frame), the measured result for all four editable kinds, and the two corollaries the
audit turned up — a `~selected` fed only by `on_row_activated`, and a `~text` fed by the
debounced `on_search_changed`. One line for the rule: **if a prop names something the user
can change, the attr that reports that change must write the state the prop reads — that
attr, not a related one.**

I did not add a live regression test. The library behaviour here is *correct* — the
erasure is the controlled-prop rule working — so a test asserting it would pin the feature,
not the bug. The defect class is an application mistake that no library test can catch,
which is why the countermeasure is the doc and the audit.

---

## I2 — the validating `Handle`, and what it found

Landed in this task, per the ruling. `Bonsai_gtk_test.Handle` is a hand-written signature
over `Bonsai_test.Handle.t`.

### Three entry points did not check, not one

| Entry point | Before | Now |
|---|---|---|
| `recompute_view` | never builds a view | checks, via `~simulate_diff_patch` |
| `recompute_view_until_stable` | ditto (it is `recompute_view` in a loop) | checks |
| `store_view` | **builds a view lazily** — a tree stored and never diffed was never seen | checks `last_result` after storing |
| `show`, `show_into_string`, `show_diff` | checked | unchanged |

`store_view` is the one nobody predicted, including my own corrected mli from the first
round, which listed it among the *checking* entry points. It is `show` without the
printing, so it looked safe; the string it stores is produced lazily. It has no
`?simulate_diff_patch` to hang a check on, so it validates `Bonsai_test.Handle.last_result`
immediately after storing — the same tree, the same frame, no second stabilization.

The golden now covers all six:

```
recompute_view:              (Invalid_argument "root/0/0: Label does not emit On_toggled")
recompute_view_until_stable: (Invalid_argument "root/0/0: Label does not emit On_toggled")
show_into_string:            (Invalid_argument "root/0/0: Label does not emit On_toggled")
show:                        (Invalid_argument "root/0/0: Label does not emit On_toggled")
show_diff:                   (Invalid_argument "root/0/0: Label does not emit On_toggled")
store_view:                  (Invalid_argument "root/0/0: Label does not emit On_toggled")
```

**Mutation-verified:** reverting `module Handle` to `Bonsai_test.Handle` turns
`recompute_view`, `recompute_view_until_stable` and `store_view` back to `accepted` and
breaks `test_handle.ml`'s toggle assertion. The test is the regression guard against the
alias coming back.

### A correction to the review's four-line sketch

**The shadow cannot be polymorphic in `'result`.** The check is `Result_spec.view`, a
function of a `Node.t`; a polymorphic `('result -> unit)` has nothing to apply it to. So
`include module type of struct include Bonsai_test.Handle end` does not typecheck against
the implementation, and the hand-written signature the ruling called for is not a style
preference — it is forced. The three shadowed values are monomorphic in `Node.t`; every
other value is re-exported with its original polymorphic type, and `t` is
`Bonsai_test.Handle.t` rather than a fresh type, so a handle passes freely between the two
modules and anything not re-exported is still reachable as `Bonsai_test.Handle.<x>`.

Not re-exported, and the mli says why: `show_model` (which carries its own
`rampantly_nondeterministic` alert whose wording is `bonsai_test`'s to change),
`result_incr`, `lifecycle_incr`, `action_input_incr` (Bonsai internals typed in `Ui_incr`).
Everything else, including the four `print_*` debug helpers, is there.

### The call sites: one was certifying a bad tree

Of the 20, **one** broke, and it broke for exactly the right reason.
`test/handle/test_handle.ml`'s *"Toggle needs a handler, and a node with toggle state to
read"* mounts `mislabelled` — a `Node.label` carrying `Attr.on_toggled`. Its own comment
says: *"`Attr.on_toggled` on a label is `Invalid_argument` the moment it is mounted, but a
headless handle never mounts anything, so this is the shape `Bonsai_gtk_test` has to refuse
on its own."* That is precisely what the test did **not** assert: `recompute_view` waved
the illegal tree through, `do_actions` was reached, and `Toggle` failed for a second,
weaker reason — `"Label (test_id lbl) has no toggle state"` — which reads like the point of
the test. The test now asserts the refusal it was written to assert:

```
(Invalid_argument "root/0: Label does not emit On_toggled")
```

A consequence worth recording: `current_active`'s `"has no toggle state"` arm now has **no
legal path to it**. The three kinds `Events.for_kind` says emit `On_toggled` are exactly
the three that carry toggle state, so any node that reaches the action has state to read.
The arm stays — it is what would fire if those two lists ever drifted, and a `match`
failure there would be a far worse diagnostic — and `bonsai_gtk_test.ml` now says so at the
arm.

The other 19 call sites pass unchanged, which is the good news: nothing else in the suite
was relying on the hole.

### The two mli paragraphs

They agree now, and in the direction the review argued for — the behaviour, not the doc.
The first says all six entry points check and gives one paragraph of history explaining why
`Handle` is a hand-written signature (naming all three shadowed functions and the one call
site that had been certifying a bad tree). The recommendation twenty lines below is now
*correct advice* and says so in a clause: the intermediate tree `recompute_view` produces is
checked like any other, and that is why `Handle`'s `recompute_view` is this library's.

`docs/m1-backlog.md`'s entry is struck through as fixed rather than left as "the fix, if it
is wanted".

---

## Minors

| | Verdict |
|---|---|
| **N1** — two of the five columns cannot fail, and the comment overclaimed `same_kind` | **Taken.** The sweep's header now has a block saying `same_kind` is a tautology *given* `Kind.name`'s totality, that it would mean something again if `same_kind` stopped being a `name` comparison (which is why it stays), and that `unmount` checks the scaffold rather than the library — with the non-vacuous part named (the third `show_into_string` re-validates the post-removal tree). The `props_changed` bullet now says outright that it is the column that can fail and cites the reviewer's own mutation. |
| **N2** — the test name reads like a lifecycle claim | **Taken.** Renamed to `every kind is diffed, and no kind is skipped`, with a comment pointing at the live gap. |
| **N3** — `Attr.visible true` pins nothing | **Taken.** `Attr.visible false`, with the reason in a comment (the tree is never displayed, so hiding a separator costs nothing). |
| **N4** — `Many` is nameless too | **Taken.** The comment now says `Css_class` is the only nameless attr *that survives flattening* and names `Many` and `Attr.flatten`. |
| **N5** — the `escapes` counter can under-count | **Argued down.** It needs two Escapes inside one 16 ms frame. A keyboard's auto-repeat is ~30/s (33 ms) and a human double-press is far slower, so the state this would fix is not reachable from the input device the page exists to be driven by. Against that: the gallery uses the same read-modify-write shape in three other places (`set_scale_names`, `set_marks`, `move`), so converting this one alone would leave the file inconsistent about a pattern it uses deliberately for legibility. Happy to take it if the lead disagrees — it is a `state_machine0` and an `Increment`. |
| **N6** — `all_kinds` is count-checked where the sweeps are name-checked | **Taken, and in both files.** The reviewer named `test/live/live_events.ml`; `test/test_events.ml` has the identical assertion, and half-closing Task 1's carry seemed worse than closing it. Both now subtract names from `Kind.Variants.descriptions`. **Mutation-verified:** replacing the `Level_bar` row with a duplicate `Label` — a change the count check waved through — now fails with `("kinds with no row in all_kinds" (missing (Level_bar)))`. Task 1's carry ("the two `all_kinds` lists are still duplicated (count-checked)") is closed. |
| **N7** — the file is 1077 lines, the sweeps sit behind a 540-line golden | **Deferred, agreed.** `gallery_tree` is already factored out, so the move is mechanical whenever M3 next touches the file. Not taken now because it would put a large pure-motion diff in front of this round's substance. |

---

## Carries to Tasks 14–16 (updated)

Unchanged from the first round except:

- **The `recompute_view` backlog entry is struck through**, not deferred. Task 15 should fold
  it into `docs/m2-backlog.md` as a closed item.
- **The XTEST / `xdotool` follow-up:** the reviewer pushed for it to become a numbered bead
  now rather than a backlog line, "because the backlog is where the same gap has already sat
  since M1". I agree and cannot act on it — this task's brief says no `bd`. **It needs the
  lead to file it**, or Task 16 to take it. It is the only change that would *close* the
  milestone's biggest test gap rather than compensate for it.
- **For Task 16's real-display click-through:** all four Input-page readouts are now safe to
  believe, and the Controls page's search box and password field and the Lists page's
  keyboard browsing are worth including in the pass — they were broken until this round and
  nothing automated covers them.
- **New, for Task 15's docs:** `vtree/node.mli`'s entry doc now carries the controlled-prop
  rule with its measurements. If the README's Limitations section says anything about
  controlled props, it should point there rather than restate it.
