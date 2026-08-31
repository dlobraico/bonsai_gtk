# Task 13 review — the gallery, and a headless sweep over every M2 widget

**Reviewed:** `git diff cff9914..c5fb8a2` in full (1346 lines), plus `test/handle/test_gallery.ml`,
`examples/gallery.ml`, `examples/embed.ml`, `examples/dune`, `test_lib/bonsai_gtk_test.ml(i)`,
`test/live/live_events.ml`, `vtree/{attr,attrs,children,kind}.ml(i)`, `src/{patcher,driver,scheduler,embed}.ml`,
the plan's Global Constraints addendum, `progress.md`, `task-12-review.md`, and the implementer's
`task-13-report.md`.

**Gates re-run independently:**

- `nix develop -c ./scripts/ci.sh` → **all green** (exit 0). Live tests, both `-p` package builds,
  format, opam files, example smoke.
- Gallery alone under xvfb: `exit=124`, **stderr 0 bytes** — no `Gtk-CRITICAL`, no `Gtk-WARNING`.
  The report's number reproduces exactly.

**Mutation checks** run in a throwaway worktree at `c5fb8a2` (since removed; the main checkout
was never modified):

| Mutation | Result |
|---|---|
| `Node.picture` → `Node.label` in the tree | kind sweep goes red: `(Picture)` |
| drop `Attr.opacity`, `Attr.cursor_name`, and two **slot-nested** attrs (`Attr.measure_overlay` in the overlay's `overlays` slot, `Attr.row_selectable` in the list box's `rows` slot) | attr sweep goes red: `(Opacity Cursor_name Measure_overlay Row_selectable)` |
| drop `Attr.css_class "dim-label"` | third sweep goes red: `(dim-label)` → `()` |
| delete the `Level_bar` lifecycle row | `("kinds with no row" (missing (Level_bar)))` |
| `Kind.equal_props`'s `Text_view` arm → `true` | `props_changed=false`, `skipped (Text_view Overlay)` |

Plus two live probes of my own (throwaway executables, since deleted):

- A `Node.entry ~text:"" ()` with no `Attr.on_changed`, mounted for real, typed into, then given
  one `Patcher.reassert_only` — **the text is erased**. See Important I1.
- Focus enter/leave ordering across two widgets on a presented window:
  `TAB: first -> second: leave first,enter second`. **Leave precedes enter**, so the gallery's
  focus readout is correct. (I went looking for a bug here and there isn't one.)

---

## Summary

The three sweeps are real. I attacked each one and each one bit, including through `Slots` — the
place a naive walk would have quietly stopped, and the place the report says a first cut of
`child_ops` *did* stop. Both counts are compiler-derived for real: `Attr.Name.all` is
`[@@deriving enumerate]` (`vtree/attr.mli:60`) and `Kind.Variants.descriptions` is
`[@@deriving variants]` (`vtree/kind.ml:480`), so neither can be satisfied by editing a list. The
19 unexercised attr names were a genuine find, and closing them with **no exemptions** — placing
`Grid_cell`, `Row_selectable`, `Tab_label`, `Measure_overlay` and the rest in the one container
that reads each — is the right call and is what makes the check hold its value.

The lifecycle sweep is the weaker of the two ideas, and the file is mostly honest about why. Its
load-bearing column is `props_changed` (mutation-verified above) and its `child_ops` golden is a
real `Reconcile.diff` fixture. Two of its five columns assert nothing a library bug could move:
`same_kind` is tautological under the current `Kind.same_kind`, and `unmount` tests the sweep's own
scaffold. That is Minor N1, not a defect — but the comment claims more for `same_kind` than the code
can deliver.

Two things I would not ship as they stand.

**I1** — the Input page's second entry is a controlled `~text:""` with no `on_changed`, and the
page's own capture-phase key handler guarantees a frame on every keystroke, so typing into it
erases the text. Measured. The Input page is the *one* artifact whose purpose is to be a truth
signal for a human, and it contains an element that looks broken; Task 16's click-through is where
that will land.

**I2** — the `recompute_view` finding is excellent and the mli correction is right, but the same
file, twenty lines further down, still **instructs the reader to call `recompute_view` between
actions** (`test_lib/bonsai_gtk_test.mli:274-282`), and the repo's own headless suite takes that
advice 15 times in `test/handle/test_handle.ml`. So this is not a hazard the Stavekeeper port might
one day hit; it is the harness's documented idiom, already in use, and the doc now contradicts
itself. Fixing the behaviour is four lines (measured — see I2), and I argue below that behaviour,
not documentation, is the right end state.

Everything in `src/` in this diff is comment-only. No out-of-scope creep.

---

## Per-deviation judgement

**1. Step 3 (`live_events.ml`'s `all_kinds`) needed no change — agree.** Verified: the list already
has 37 rows and `test/live/live_events.ml:73` asserts
`List.length all_kinds = List.length Kind.Variants.descriptions`. Nothing to add. (Note in N6 below
that this assertion is by *count* where the new sweep is by *name*.)

**2. The embed is not in the gallery — agree, and strongly.** `examples/dune:1-5` states the
property in as many words: `counter` and `gallery` link no ocgtk, and that is what they exist to
demonstrate. `Expert.embed` requires the caller to own a GTK container, so a gallery page hosting
one would have to link `ocgtk.gtk` and destroy the property the dune comment protects. More to the
point, **the demonstration the lead asked for already exists**: `examples/embed.ml` adds the
embedded page to a real `GtkStack` with `add_named`, drives it in and out with Show/Hide buttons
(`examples/embed.ml:80-129`), calls `Expert.Embedded.stop`, and is smoked by `ci.sh` alongside the
other two (`exit=124`, verified). Asking for it a second time inside `gallery.exe` would buy nothing
and cost the one architectural claim the examples directory makes.

**3. The lifecycle sweep covers all 37 kinds, not just the 8 — agree.** Strictly better, and it is
what lets the row list be counted against `Kind.Variants.descriptions` instead of being a third
hand-maintained list.

**4. `docs/m1-backlog.md` and `test_lib/bonsai_gtk_test.mli` outside the brief's file list —
agree.** The backlog is where the plan says out-of-scope findings go, and leaving a statement in a
public mli that this task disproved would have been worse than the scope. Called out clearly enough
to reverse. See I2 for the half of the mli edit that is incomplete.

**5. No expected file promoted unread — accept.** I read the full golden diff myself: the only
changes are the attrs this task added, the new Input page, and the header rewrite. No pre-existing
prop moved.

**"Deliberately not done" — agree with both, with one push.**

- *XTEST / `xdotool` under the same xvfb.* Correctly scoped out (it needs `flake.nix`, which is not
  in this task's file list) and correctly identified as the most valuable follow-up: it would
  **close** the milestone's biggest test gap rather than compensate for it, and the compensating
  control it would replace is a one-time human click-through that no CI run ever repeats. My push:
  this should become a numbered bead now, not a backlog line, because the backlog is where the same
  gap has already sat since M1. Task 16 or a dedicated task.
- *Shadowing `Handle.recompute_view`.* Correct that it touches `test_lib`'s public surface. See I2
  for why I think it should still land inside M2.

---

## Critical

None.

---

## Important

### I1. The Input page's second entry erases anything typed into it — on the one page whose job is to be believed by a human

`examples/gallery.ml:722-730`:

```ocaml
; Node.entry
    ~attrs:
      [ Attr.hexpand true
      ; Attr.on_focus_enter (fun () -> set_focus "second entry")
      ; Attr.on_focus_leave (fun () -> set_focus "(neither)")
      ]
    ~placeholder:"Tab to me"
    ~text:""          (* controlled, and pinned to "" forever *)
    ()
```

`text` is a controlled prop: `W_entry.reassert` compares against the **widget's** text and writes
when it differs (`src/widgets/w_entry.ml:14-33`), and `Patcher.reassert_only`
(`src/patcher.ml:1017`) runs it on every node on every frame, including a no-change frame
(`src/driver.ml:88`). Under `Bonsai_gtk.start` the scheduler holds a 16 ms `Glib.Timeout`
(`src/scheduler.ml`, `start_tick`), so a frame happens ~60 times a second regardless of input — and
this page additionally guarantees one per keystroke, because its capture-phase handler at
`examples/gallery.ml:681` schedules `set_key` for **every** key, including keys typed into this
entry.

Measured, mounting the exact node and running one `reassert_only`:

```
after the user typed: "hi"
after one idle tick:  ""
```

**Failure scenario.** Task 16's real-display click-through is the compensating control for the
untestable click and key paths, and this page's own comment tells the person running it: *"If any of
those readouts does not move, the controller machinery is broken however green the suite is."* A
person following that instruction tabs to the second entry, types, and watches the characters
vanish. The page has just told them how to interpret that. At best they lose an hour proving the
controllers are fine; at worst they file a controller bug against a working library, or — worse in
the other direction — they conclude the page is unreliable and stop trusting the three readouts that
*are* the evidence.

**Fix (one line plus a state).** Give it its own state and `Attr.on_changed`, exactly as the first
entry has:

```ocaml
let text2, set_text2 = Bonsai.state "" graph in
...
; Attr.on_changed set_text2
; ~text:text2
```

Alternatively make the second focus target something with no editable text (a `Node.button`), which
also removes the temptation to type in it. Either is fine; the current node is not.

**Pre-existing twin, not this task's:** `examples/gallery.ml:92-96` — the Controls page's
`Node.password_entry ~text:"" ()` with no `on_changed` — has the identical defect and has since M1.
That one belongs on the backlog (it is a second reason the "real-display click-through" item has
never been actioned), not in this task's fix round. But it should be fixed in the same edit if the
implementer is in the file anyway, since Task 16's click-through will hit it too.

### I2. The `recompute_view` correction is half-landed: the same mli still tells the reader to use it, and the repo's own suite does so 15 times

The finding itself is first-rate — `Handle.recompute_view` runs the computation without building
the view, so the `Placement`/`Events`/key-phase checks in `Result_spec.view`
(`test_lib/bonsai_gtk_test.ml:76-98`) never run, and the mli claimed the opposite. Pinned by a real
test (`test/handle/test_gallery.ml:1060`) whose golden shows `recompute_view: accepted` against
`show_into_string`'s `Invalid_argument`. Correct, and worth the detour.

But the correction stops at one paragraph. Twenty lines below it, unchanged:

> `test_lib/bonsai_gtk_test.mli:274-282` — "*…if the second click is meant to see whatever the first
> click's effect changed …, call `[Handle.recompute_view handle]` between the two actions to force a
> fresh snapshot first. See `test/test_handle.ml` for the pattern: two single-click `do_actions`
> calls separated by `recompute_view`.*"

So one paragraph of this mli says `recompute_view` does not check the tree, and the next recommends
it as the way to advance a test between actions. `test/handle/test_handle.ml` follows the
recommendation **15 times**. Every tree those 15 calls produced is unvalidated today, and the file
the mli points at as "the pattern" is the one demonstrating the hole.

**Which end should have been fixed — the doc or the behaviour?** The behaviour, and I do not think
it is close.

- Task 1's principle is stated in this library's own words at `test_lib/bonsai_gtk_test.ml:62`:
  "*so that a headless suite cannot certify a tree the runtime refuses*". Right now it can, through
  the entry point the mli recommends. A guarantee that holds only if you avoid the documented idiom
  is not a guarantee; it is a convention with a footnote.
- The Stavekeeper port is precisely this workload. A port drives a screen through a sequence of
  model actions and prints once at the end — that is what a port diff wants to read. Under the
  current behaviour such a test validates its final tree and none of the intermediate ones, which is
  exactly the class of bug (a placement attr in the wrong container, an event attr on a kind that
  does not emit it) that only shows up on a transient tree — a row that exists for one frame, a stack
  page shown only mid-flow.
- The report's stated reason for deferring — "it is a change to `test_lib`'s public surface" — is
  true of the *signature* and not of the *implementation*. `Bonsai_test.Handle.recompute_view` takes
  `?simulate_diff_patch:('result -> unit)` and hands it the computed result. I verified this:

  ```
  simulate_diff_patch saw a Window
  recompute_view returned
  ```

  So the validating version is four lines:

  ```ocaml
  let recompute_view ?simulate_diff_patch handle =
    Bonsai_test.Handle.recompute_view handle ~simulate_diff_patch:(fun node ->
      ignore (Result_spec.view node : string);
      Option.iter simulate_diff_patch ~f:(fun f -> f node))
  ```

  The real cost is that `module Handle = Bonsai_test.Handle` in the mli has to stop being a plain
  alias, and OCaml will not let you `include module type of` and then shadow a value in the same
  signature — so it needs a hand-written `Handle : sig … end` or a separately named
  `Bonsai_gtk_test.recompute_view`. That is a decision worth ten minutes, not a milestone.

**What I am asking for in this task**, in descending order of what I would insist on:

1. **At minimum, and non-negotiably: fix the contradiction.** `mli:274-282` must say that the
   `recompute_view` it recommends leaves the intermediate tree unchecked, and point at
   `show_into_string`-and-discard as the checked alternative — the same thing `run_row` does
   (`test/handle/test_gallery.ml:830-836`) and for the same reason. Leaving one paragraph
   recommending what the paragraph above warns against is worse than the original wrong sentence,
   because the original was at least self-consistent.
2. **Name the sibling.** `Handle.recompute_view_until_stable` (`_opam/lib/bonsai_test/proc.mli`) is a
   second non-checking entry point — it is `recompute_view` in a loop. The corrected mli lists four
   checking entry points and singles out one non-checking one, so a reader doing the subtraction gets
   the right answer, but only by inference. Four words fixes it, and the backlog entry
   (`docs/m1-backlog.md`) and the new expect test should name it too.
3. **My recommendation: land the shadow inside M2** — Task 15 or 16, not the backlog. The 15 existing
   call sites are the argument: this is not a latent gap waiting for the port, it is already the
   suite's habit, and every task after this one adds more of them. If the lead prefers to defer, the
   backlog entry should say the port is expected to hit it, rather than "the fix, if it is wanted".

---

## Minor

**N1. Two of the lifecycle sweep's five columns cannot fail, and the comment claims otherwise for
one of them.**

`test/handle/test_gallery.ml:854` prints `same_kind=%-5b`, and the comment above `sweep_rows` says a
wrong answer there is "*one `Kind.name` arm … apart from being wrong*". It is not. `Kind.same_kind`
is `String.equal (name a) (name b)` (`vtree/kind.ml:549`) and `Kind.name` is a total function of the
*constructor* (`vtree/kind.ml:482-519`) — so two nodes built from the same constructor always
produce the same string, and `same_kind` is **true by construction** for every row. No single-arm
edit to `name` can make a kind differ from itself; you would have to make `name` read a prop, which
is not a plausible bug. The column would have been meaningful against the 32-arm matrix with the
`_ -> false` wildcard that `vtree/kind.ml:521-548` describes as *removed* — the comment appears to
have been written against that older shape.

`unmount=%-9s` is weaker still: `STILL THERE` can only be printed if `subject_of`
(`test/handle/test_gallery.ml:763`) disagrees with `lifecycle_app`'s own `if step = 0 … else None`
(`:761`). It asserts the sweep's scaffold, not the library. (It is not *zero* — the third
`show_into_string` re-validates the post-removal tree — but nothing about unmounting is checked.)

Neither is harmful; both cost a reader's trust in the other three columns. The cheap fix is one
sentence: say that `same_kind` is a tautology *given* `Kind.name`'s exhaustiveness and is printed as
the record of that invariant, and that `unmount` is a scaffold check. The expensive fix — dropping
them — I would not do, since a future `same_kind` that stops being a `name` comparison would want
this column back.

**N2. What the sweep proves about `update` is narrower than "mount, patch, unmount" suggests, and
the one place it could be misread is the row header.** `props_changed=true` proves the patcher will
*not skip* the impl's `update`; it says nothing about whether `update` writes anything, because
`test/handle/dune` links no ocgtk and there is no widget. The file's closing paragraph
(`test/handle/test_gallery.ml:717-722`) says this correctly and I have no complaint about the
substance — but "every kind mounts, patches and unmounts" as the test's *name* reads like a
lifecycle claim, and a per-kind live `update` sweep is still the gap `docs/m1-backlog.md` records
("*there is still no single live `Live_tree.dump` golden over the whole catalogue*"). Consider
naming the test for what it checks (`every kind is diffed, and no kind is skipped`), or leave it and
accept that the paragraph carries the caveat.

**N3. `Attr.visible true` is the one of the 19 placements that pins nothing.**
`test/handle/test_gallery.ml:150` puts `Attr.visible true` on a separator. `true` is the GTK default,
so the write is a no-op and no wrong value of this attr could change the golden — which is the shape
of the M1 backlog's "*three expect tests pass props the sexp then drops*", even though here the sexp
does keep it (attrs are not `[@sexp_drop_if]`'d, and the golden shows `(attrs ((Visible true)))`).
It satisfies the sweep, which is all the sweep asks. If you want it to mean more, `Attr.visible
false` on a node the tree can afford to hide costs nothing; otherwise add the half-sentence that this
placement is name coverage only. Everything else among the 19 is placed somewhere it does something:
`Sensitive`/`Opacity` on a button with a child (`:62`), `Tooltip`/`Valign` on the spinner (`:144`),
`Cursor_name` beside the click gesture (`:302`), `Focusable`/`Can_focus` on the box that carries the
key controller (`:293`), `On_visible_child_changed` on the one kind that emits it (`:40`).

**N4. "`Attr.css_class` is the one attr `Attr.name` answers `None` for" is very slightly wrong.**
`vtree/attr.ml:273` is `| Css_class _ | Many _ -> None`. `Many` also has no name; it just cannot
reach `Attrs.to_list` because `Attr.flatten` walks it first (`vtree/attrs.ml:26-36`). The claim's
*conclusion* is right — `Css_class` is the only nameless attr the sweep can encounter — but the
report and the comment at `test/handle/test_gallery.ml:674-680` should say "the only nameless attr
that survives flattening", so a future reader adding a second combinator does not conclude the
invariant is about `Css_class` specifically.

**N5. The `escapes` counter can under-count.** `examples/gallery.ml:676-678` does
`set_escapes (escapes + 1)` over a `Bonsai.state`, reading `escapes` from the arr — so two Escapes
landing in the same frame count as one. At 16 ms per frame that needs a faster double-press than a
human manages, so this will never be seen; but the page is a truth signal and a
`Bonsai.state_machine0` with an `Increment` action costs the same to write. Take it or leave it.

**N6. `live_events.ml`'s `all_kinds` is still count-checked where the new sweeps are name-checked.**
`test/live/live_events.ml:73` asserts only `List.length all_kinds = List.length
Kind.Variants.descriptions`, so a duplicated row plus an omitted one passes — the failure Task 1
recorded as a carry and this task's `("kinds with no row" (missing …))` idiom fixes properly.
Aligning the live file with the new idiom is a five-line change and would close the carry. Not this
task's file list; worth a backlog line if not taken.

**N7. `test/handle/test_gallery.ml` is 1077 lines, of which ~540 are one golden, and the three
sweeps sit behind it.** The golden is still reviewable — I read this task's delta to it and it is
~60 lines, every one an attr or the Input page — but the sweeps are now the more valuable half of the
file and any future diff to them arrives underneath half a thousand lines of sexp churn. A later
task could move them to `test/handle/test_coverage.ml` (they need only `gallery_tree`, which is
already factored out at `:20`). Not now; noting it before the file grows again in M3.

---

## Checks that came back clean

Recording these because I went looking for bugs in each and did not find one.

- **Focus enter/leave ordering.** The Input page's readout has both entries' `on_focus_leave` write
  `"(neither)"`, so if GTK emitted the new widget's `enter` before the old widget's `leave`, every
  Tab would end at `(neither)` and the demo would look broken. Measured on a presented window with
  the same handlers: `TAB: first -> second: leave first,enter second`. Leave precedes enter; the
  readout is correct. The existing live golden could not have answered this — `live_controllers.ml`
  instruments only one widget, so lines 12-14 and 36-39 of `expected_controllers.txt` never show two
  widgets' events interleaved.
- **The sweeps walk `Slots`.** `Children.iter` descends through slots (`vtree/children.ml:9-16`), and
  `list_box`'s placeholder is a slot rather than a side field (`vtree/node.ml:512-516`), so nothing in
  the tree is out of the walk's reach. Confirmed by mutation, above.
- **Both counts are compiler-derived.** `Attr.Name.all` is `[@@deriving enumerate]`;
  `Kind.Variants.descriptions` is `[@@deriving variants]`. Neither can be satisfied by editing a
  list, which is the whole point.
- **`Window`'s Root placement is the right call, not a dodge.** `Bonsai_gtk_test` deliberately does
  not check "a window may only be the root" (it needs the widget impls), so a `Window` row in the
  scaffold's child slot would have made the sweep certify a tree the runtime refuses. Putting the
  subject at the root instead is exactly the rule the attr sweep follows, and the ci.sh live log
  shows the runtime's refusal message that would otherwise have been hidden.
- **`Overlay` in the `skipped` list is the one correct member**, its props really are `unit`, and
  printing the list rather than asserting emptiness is what stops a second kind joining it silently.
- **The Task 12 carries are all landed and faithful.** The `signals.mli` section
  (`src/signals.mli:18-49`) states the rule, the measured reason and the threshold in the same words
  as the plan's addendum (plan lines 49-61), names `src/embed.ml` as the only `destroy` connection in
  `src/`, `vtree/` and `test_lib/`, and closes with the maintainable half — a signal in a
  `Widget_impl.signals` list is safe by construction, a connection anywhere else is the one to check.
  `Embed.stop` (`src/embed.ml:36-46`) carries the reviewer's sentence essentially verbatim with probe
  B's numbers. N2 (the `unwind`/`destroy` cross-references), N3 (the `Attr.on_click` moved to the
  box, with the reasoning for why the reviewer's suggested placement could not work — which is
  correct: `require_specs` runs before the raising node's own controllers exist) and N4
  (`mount`'s "nothing behind" is about the live tree, not `ctx`) are all done. Live golden unchanged,
  live suite green.
- **No out-of-scope creep.** Every `src/` hunk in this diff is inside a comment. The only
  non-comment, non-test change outside `examples/` is the `Attr.on_click` added to `live_embed.ml`'s
  failing-mount tree, which is carry N3.

---

## Verdict

**Approved with two Important findings to answer.**

The sweeps do what the task asked and survive being attacked; the 19-name find justifies the whole
exercise, and the `recompute_view` discovery is worth more than the sweep that turned it up. The
gallery's Input page demonstrates on_click with button/press-count/coordinates/modifiers,
`Propagate_and` and `Handled_and` as separately observable readouts, and focus enter/leave — all four
paths the lead asked for, all four visible to a person, with the phase choice (`Capture`) that makes
the Escape case a real test rather than a coincidence. The embed's absence from the gallery is
correctly argued and the demonstration exists in `examples/embed.ml`.

**I1** should be fixed before Task 16 runs the click-through — it is a one-line change and it is the
difference between that check producing a signal and producing a false alarm on the page built to
carry it.

**I2**'s first bullet (the mli contradicting itself twenty lines apart) I would not sign off without;
the second (naming `recompute_view_until_stable`) is four words; the third (landing the shadow
inside M2) is the lead's call, but the 15 existing call sites make it a poor thing to defer past the
port that will add more of them.

The Minors are all cheap and none blocks. N1 is the one I would take, because a column that cannot
fail is worse than an absent one — it spends the reader's trust on the columns that do.

---

# Re-review — fix round 1 (`e7a1e7e`)

Scope: `git diff c5fb8a2..e7a1e7e` against I1 and I2 and the seven Minors. I did not re-read
the rest of the task.

**Gates re-run independently:** `nix develop -c ./scripts/ci.sh` → **all green** (exit 0). All
three examples under xvfb: `gallery exit=124 stderr=0`, `embed exit=124 stderr=0`,
`counter exit=124 stderr=0`.

Both Important findings are closed, and both were larger than I found them — in the same
direction, and each extension is measured rather than asserted. Verdict at the bottom.

## I1 — closed, and the audit is complete

**The audit table accounts for every controlled prop in the repository.** I enumerated the
impls with a non-`None` `Widget_impl.reassert` (14: calendar, search_entry, toggle_button,
revealer, check_button, spin_button, password_entry, scale, drop_down, entry, editable_label,
expander, switch, text_view) plus the four applied from the fixup queue (stack
`~visible_child`, list_box / flow_box `~selected`, notebook `~current_page`), then counted every
constructor of those kinds in `examples/gallery.ml`: 27 node instances, of which `editable_label`
and `calendar` each carry two controlled props — **29, which is exactly the table's row count, row
for row.** `examples/counter.ml` and `examples/embed.ml` contain no controlled prop at all, so the
gallery is the whole surface. Nothing is missing and nothing is padding.

The four fixes are correctly wired — the prop reads the state the *reporting* attr writes:

- `password_entry` — `~text:password` / `Attr.on_changed set_password`.
- `search_entry` — `~text:search` / `Attr.on_changed set_search`, with the debounced
  `on_search_changed` moved to a second `query` state. `Events.for_kind`'s `Search_entry` arm
  (`vtree/events.ml:29`) lists `On_changed`, so both are legal on the kind. This one is a better
  find than #5 or #28: it is the landing page, and the failure window was the 150 ms debounce
  rather than "no signal at all", which is why nobody caught it.
- `list_box` (Single) — `~selected:[chosen]` now also fed by `on_selected_rows_changed`.
- Input entry 2 — `~text:second` / `Attr.on_changed set_second` (my I1).

**The list-box fix rests on a claim I checked rather than took.** It only works if
`selected-rows-changed` fires for a selection that is *not* an activation. Live probe, mounting the
fixed node and calling `select_row` on row 1 (what the arrow keys do):

```
-- mounted (selection fixups applied)
  selected-rows-changed [a]
-- select row 1 without activating it (the arrow-key case)
  selected-rows-changed [b]        <- and no row-activated
```

So the new attr genuinely closes the loop the keyboard opens; the old wiring could not have.

**On the decision not to add a regression test:** agreed, and for the reason given — the erasure
*is* the controlled-prop rule working, so a test asserting it would pin the feature. The
countermeasure that can work is the one taken: `vtree/node.mli`'s entry doc now states the rule
with its cadence ("about sixty times a second"), the measured result for all four editable kinds,
and the two corollaries the audit found. That is the right place for it — it is the doc the next
person writing a page reads, and the previous wording ("the bug the required argument exists to
make impossible to write by accident") was actively misleading, since the required argument
constrains the prop and says nothing about the attr. Correcting a doc that caused four instances of
a bug is a better artifact than a test that cannot exist.

## I2 — closed, and it found more than I did

**The signature re-exports everything, and nothing is silently dropped.** I compared the two
signatures mechanically. `Bonsai_test.Handle` exposes 21 values; `Bonsai_gtk_test.Handle` re-exports
17 (three of them shadowed) and omits exactly four — `show_model`, `result_incr`, `lifecycle_incr`,
`action_input_incr` — which are the four the mli names and justifies in a trailing doc comment. Spot-
checking types against `_opam/lib/bonsai_test/proc.mli`: `show`, `show_into_string`, `show_diff`,
`last_result`, `do_actions`, `time_source`, `advance_clock`, `advance_clock_by`, `create`,
`has_after_display_events` and the four `print_*` are identical, including optional arguments. The
only narrowings are the three shadowed functions, monomorphised to `Node.t`.

**And the monomorphisation is forced, as the report says — my four-line sketch was wrong.** The
check is `Result_spec.view : Node.t -> string`; a polymorphic `'result -> unit` has nothing to apply
it to, so `include module type of struct include Bonsai_test.Handle end` cannot describe the
implementation and the hand-written signature is not a style choice. Correction accepted. `t` is
kept as `Bonsai_test.Handle.t` rather than a fresh type, which is the right call — it keeps the
escape hatch the omitted four need.

**Validation runs on every path, including `_until_stable`'s loop — verified from source, not
inferred.** `_opam/lib/bonsai_test/proc.ml:258-266`:

```ocaml
let recompute_view_until_stable ?(max_computes = 100) ?simulate_diff_patch handle =
  recompute_view ?simulate_diff_patch handle;
  ...
  while Driver.has_after_display_events handle do
    recompute_view ?simulate_diff_patch handle;
```

`?simulate_diff_patch` is forwarded to **every** inner call, so every intermediate tree of the loop
is checked, not just the last. The mli's "Every intermediate tree is checked, not just the last" is
accurate.

**`store_view` was a real third hole, and my own first-round mli correction had it wrong.** I listed
`store_view` among the *checking* entry points, following the sentence I was correcting. Source:
`proc.ml:299` is `let store_view handle = ignore (recompute_store_and_show handle : string Lazy.t)`
and `driver.ml:30` initialises `last_view = lazy ""` — the view is a `string Lazy.t` stored
unforced, so `Result_spec.view` was never called for a tree stored and never diffed. Confirmed by
probe:

```
bonsai_test store_view: accepted
bonsai_gtk store_view: (Invalid_argument "root/0/0: Label does not emit On_toggled")
```

Good catch, correctly diagnosed, and the fix (validate `last_result` immediately after storing,
since there is no `?simulate_diff_patch` to hang it on) is right: no stabilization happens between
`store_view`'s internal `Driver.result` read and the shadow's, so it is the same tree in the same
frame, exactly as the comment claims.

**The pin flipped, and it is a real regression guard.** Mutation: I reverted `module Handle` to
`Bonsai_test.Handle` in both `.ml` and `.mli` in a throwaway worktree:

```
-|    recompute_view: (Invalid_argument "root/0/0: Label does not emit On_toggled")
-|    recompute_view_until_stable: (Invalid_argument ...)
-|    store_view: (Invalid_argument ...)
+|    recompute_view: accepted
+|    recompute_view_until_stable: accepted
+|    store_view: accepted
```

plus `test_handle.ml:149` going red with `"did not raise"`. All three shadows and the call-site fix
are guarded. The golden covers all six entry points, and each uses a fresh handle — correct, since a
handle that has raised out of a frame is not a fair subject for the next one.

**The bad call site's fix is a real fix, not a loosened test.** `test/handle/test_handle.ml:130-151`
now asserts `(Invalid_argument "root/0: Label does not emit On_toggled")` at `recompute_view`, in
place of the weaker `(Failure "Label (test_id lbl) has no toggle state")` at `do_actions`. That is
strictly stronger, and it is the assertion `mislabelled`'s own comment always claimed to be making —
"*`Attr.on_toggled` on a label is `Invalid_argument` the moment it is mounted … this is the shape
`Bonsai_gtk_test` has to refuse on its own*" — which the test was not making. The first half of the
test (`Toggle "state"`, no handler) is untouched. The consequence is stated honestly: `current_active`'s
`"has no toggle state"` arm now has no legal path through this module, is kept as defensive, and
says so where it lives (`test_lib/bonsai_gtk_test.ml:59-64`). Keeping it is right — a `match` failure
there would be a far worse diagnostic than the `failwithf`, and the arm is still reachable through
`Bonsai_test.Handle` directly.

**The mli paragraphs agree.** The header now lists all six entry points as checking, carries one
paragraph of history explaining why `Handle` is hand-written, and the recommendation at
`test_lib/bonsai_gtk_test.mli:386-391` gains the clause that makes it correct advice rather than a
trap. `docs/m1-backlog.md`'s entry is struck through as fixed. Nothing else in `test/`, `src/` or
`examples/` calls `Bonsai_test.Handle` directly, so the 19 other call sites really are unaffected.

## The Minors

N1, N2, N3, N4 and N6 taken; all five land where I asked. N1's new block is better than what I
suggested — it names what is *not* vacuous about the unmount phase (the third `show_into_string`
re-validates the post-removal tree) rather than only conceding the column. N6 was taken in both
files rather than the one I named, and mutation-verified against exactly the drift a count check
waves through (a duplicated row plus an omitted one); Task 1's carry is closed.

**N5 argued down — accepted.** The reasoning is sound: two Escapes inside one 16 ms frame is below a
keyboard's ~33 ms auto-repeat, so the state the fix would correct is not reachable from the input
device the page exists to be driven by; and converting one of the file's four read-modify-write
sites would leave it inconsistent about a pattern it uses deliberately. I would not spend the change.

**N7 deferred — agreed**, and for the right reason: a large pure-motion diff in front of this round's
substance would have made the round harder to review, which is the cost the move exists to avoid.

## New Minors (neither blocking)

**N8. The mli's guarantee is stated absolutely and is true only of this module.**
`test_lib/bonsai_gtk_test.mli:346-349`: "*So there is no way to advance a handle past a tree without
checking it, and no idiom a test has to avoid.*" Since `Handle.t = Bonsai_test.Handle.t` — correctly,
and by design — `Bonsai_test.Handle.recompute_view handle` still typechecks and still skips the
check, and the same file points readers at `Bonsai_test.Handle` for the four omitted values two
paragraphs above. Scope the sentence ("no way to advance a handle *through this module*…"). Do not
make `t` abstract to close it: that would cost the interop the omissions depend on, and the hole is
unexercised today (nothing in `test/`, `src/` or `examples/` calls that module).

**N9. The N4 comment now contradicts itself in consecutive sentences.**
`test/handle/test_gallery.ml:682-691` opens "*`[Attr.name]` answers `[None]` for two constructors,
`[Css_class]` and `[Many]`…*" and the next paragraph begins "*`[Attr.css_class]` is the attr
`[Attr.name]` answers `[None]` for*" — the old sentence with "the one" edited down to "the", which
now reads as denying the paragraph above it. Start the second "It has no `[Name.t]` because…" and
the two agree.

## Verdict

**Approved.** I1 and I2 are closed, both were correctly found to be wider than I reported, and every
extension is backed by a measurement I could reproduce: the audit table is complete against the
impls (29 rows, 29 controlled props, no others in the repo), the list-box fix's load-bearing signal
fires without activation, the `Handle` signature drops nothing silently, `_until_stable` checks
every iteration of its loop, `store_view` really was lazy and really is checked now, and the pin
flips under mutation. The `store_view` find corrects an error in my own first-round review, which is
the best kind of fix-round result. `ci.sh` is green and all three examples come up clean.

N8 and N9 are one sentence each and can ride along with any later commit in this milestone; neither
needs a round of its own. The XTEST follow-up still needs the lead to file it — the implementer is
right that this task's brief forbids `bd`, and it remains the only change that would close the
milestone's biggest test gap rather than compensate for it.
