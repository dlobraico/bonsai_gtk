# M2 final review — headless tests & the test library

Lens: `test/` (non-live), `test/handle/`, `test_lib/`, dune/opam. Read-only; nothing built or run.
Everything below verified against HEAD `f06a615`. Backlog items in `docs/m2-backlog.md` are not
re-reported; where a finding is adjacent to one, the entry is cited.

## Summary

The suite is unusually honest for its size. The three sweeps in `test/handle/test_gallery.ml`
derive their expectations from the compiler (`Kind.Variants.descriptions`, `Attr.Name.all`)
rather than from hand-maintained lists; the lifecycle sweep names its own two vacuous columns
out loud; the six-entry-point test at `test_gallery.ml:1099` is a real regression pin, and the
`recompute_view` shadow it protects is a genuine closure of a real hole. `test/test_events.ml`
and `test/test_placement.ml` pin the two shared tables from both directions. I found no test
that is silently wrong about what it computes.

What I did find is a systematic overstatement of what the headless handle *is*, in the three
places a reader goes to find out: `test_lib/bonsai_gtk_test.mli`, `README.md` §Headless testing,
and `README.md` §Limitations. All three explain the remaining gap with a reason that is false —
"needs the widget implementations or a live tree" — for every item on their own list; two of them
list items that *are* already caught headlessly (contradicted by `test/test_widgets.ml`); and the
single most likely structural mistake an application can make, a root node that is not a
`Node.window`, appears in none of the mli's list. Separately, three event attrs
(`On_revealed`, `On_position_changed`, `On_visible_child_changed`) have no `Action` at all, and
nothing in the suite notices — the attrs sweep is satisfied by the attr *appearing* in the
gallery tree, which all three do.

Two expect tests accept an output that is byte-identical to the output their action never
running would produce. One erasure (`paned_props.position`) hides a controlled prop from every
golden. The `-p` split puts every completeness sweep in the package that `opam install bonsai_gtk
--with-test` does not run.

Verdict below: **approve with fixes** — nothing here is a code defect; the Critical is a
documentation defect about the value of the tests, which for a review of the tests is the thing
that matters most.

---

## Critical

### C1. The three places that say what the headless handle is worth are wrong, in three independent ways, and disagree with each other

`test_lib/bonsai_gtk_test.mli:368-374` (in `create`'s doc):

> What is still only checked at mount is the structural half **that needs the widget
> implementations or the live tree**: a `Node.grid` child with no `Attr.grid_cell`, a
> `Node.stack` page with no `~key` or a `~visible_child` naming no page, two stacks under one
> `~name`, a `stack_switcher` naming no stack, duplicate keys among siblings, a `Node.window`
> anywhere but the root.

`README.md:272-278` repeats the same sentence and the same list.

Three separate errors:

**(a) The stated reason is false for every item on the list.** Not one of the six needs a widget
implementation or a live tree; every one is decidable from `bonsai_gtk.vtree`, which this library
already depends on:

- *duplicate keys among siblings* — `vtree/reconcile.ml:24` `check_unique_keys` is pure vtree,
  is already exported, is already pinned by `test/test_reconcile.ml:109`, and is called by the
  patcher at `src/patcher.ml:553` (mount) and `:818` (patch). The handle could call the same
  function in `require_supported`'s `Children.iteri` for a `List`.
- *`Node.window` anywhere but the root* — `src/patcher.ml:357`. `require_supported` already
  carries `~parent`; `Some _, Window _ -> reject` is two lines.
- *two stacks under one `~name`*, *a `stack_switcher` naming no stack* (`src/patcher.ml:49`,
  `:64`) — both are a walk over `Kind.Stack`/`Kind.Stack_switcher`/`Kind.Stack_sidebar` names in
  the node tree.
- *a `~visible_child` naming no page* (`src/widgets/w_stack.ml:92`) — the pages' `~key`s are on
  the node; the empty-stack carve-out the runtime documents at `w_stack.ml:83-90` transfers
  unchanged.
- *a `Node.grid` child with no `Attr.grid_cell`* (`src/widgets/w_grid.ml:16`) — parent kind plus
  child attrs, which is exactly the data `Placement` already reads. The handle today enforces
  only the *negative* half of the grid rule (a non-grid child must not carry `Grid_cell`) and
  not the positive half (a grid child must).

The real reason none of them is checked is that nobody wrote the check. Saying instead that they
*cannot* be checked from vtree tells a reader the gap is structural and closed, when it is a
backlog item nobody has filed.

**(b) One listed item is already checked headlessly, and the branch's own tests prove it.**
"a `Node.stack` page with no `~key`" is rejected by the *constructor*
(`vtree/node.ml:476` calling `require_child_keys` at `:30`), which runs inside the Bonsai
computation and therefore headlessly. `test/test_widgets.ml:553` is the test. `README.md:450-455`
makes the same claim about four containers at once — "a `list_box`/`flow_box`/`notebook` child
with no key, a `stack` page with no key … none of them stops a headless test" — and
`test/test_widgets.ml:530`, `:674`, `:826`, `:553` are four expect tests demonstrating that all
four *do*.

**(c) The mli omits the root-kind rule entirely.** `src/driver.ml:44-61` `check_root` requires
the root node of a `Bonsai_gtk.start` tree to be a `Node.window`, and requires an
`Expert.embed` root *not* to be one. `root_kind` appears nowhere in `test_lib/`, nowhere in
`test/handle/`, and nowhere in `docs/m2-backlog.md`. `README.md:450` mentions it; the mli and
README §Headless testing do not.

**Wrong conclusion this produces.** An author writes a view function that returns
`Node.box ~orientation:Vertical [...]` — the window forgotten, or lost in a refactor that hoisted
the root into a component. Every `Bonsai_gtk_test` test is green, the golden is a complete and
correct-looking tree, and `test/handle/test_gallery.ml`'s sweeps say nothing (a `Root` placement
exists in the lifecycle sweep, but only for the `Window` row). `Bonsai_gtk.start` then raises
`Invalid_argument "Bonsai_gtk: the root node must be a Node.window, got Box…"` out of
`Driver.frame`, which marks the driver broken — per `vtree/node.mli:19-24`, *every frame after it
is a no-op and the window never repaints again*. This is the single cheapest structural check in
the file (one `match` on `node.kind` against a `?root_kind` argument mirroring `Driver.create`'s)
and the one most likely to fire in practice, and it is the one the mli does not mention.

A reader of the current text concludes "the headless suite catches everything decidable without
GTK; what is left needs a display." The true statement is "the headless suite catches three of
the twelve things the runtime refuses that are decidable without GTK, and one of the nine it does
not catch will silently permanently break the driver on frame 1."

Fix: correct the reason to what it is (not yet implemented, and here is why it was not worth it
in M2 / here is the bead), drop the constructor-checked items from all three lists, add the
root-kind rule to the mli and README §Headless testing, and reconcile README §Limitations with
`test/test_widgets.ml`. The gap table in this report is the material.

---

## Important

### I1. Three event attrs have no `Action`, and no sweep can see it

`Bonsai_gtk_test.Action.t` (`test_lib/bonsai_gtk_test.ml:5-25`) has nineteen constructors covering
twenty of the twenty-three names `Attr.Name.is_event` admits. The three with no action are
`On_revealed`, `On_position_changed` and `On_visible_child_changed` — verified against
`test/test_events.ml:182-187`'s `is_event` golden and by grepping `test_lib/` and `test/handle/`.
So a handler attached with `Attr.on_revealed`, `Attr.on_position_changed` or
`Attr.on_visible_child_changed` cannot be fired by any headless test. Not on the backlog
(`docs/m2-backlog.md` mentions none of the three).

The mli's `Action` doc is 190 lines of scrupulous per-action reasoning about *why each action
behaves as it does*; it nowhere says which handlers have no action. The `create` doc's list of
"known gaps" is routing and structure, not this.

**All three sweeps are blind to it**, which is the more interesting half:

- The kinds sweep (`test_gallery.ml:650`) counts `Kind.Variants.to_name`; `Revealer`, `Paned`
  and `Stack` are all in the tree.
- The attrs sweep (`test_gallery.ml:671`) counts *presence* of each `Attr.Name.t` in
  `names_in_tree sweep_tree`. All three attrs are there —
  `test_gallery.ml:40` (`on_visible_child_changed`), `:176` (`on_revealed`), `:252`
  (`on_position_changed`) — each attached to `fun _ -> Ui_effect.Ignore`. The sweep is green.
- The lifecycle sweep (`test_gallery.ml:1006`) mounts/patches/unmounts each kind and prints
  `props_changed`/`child_ops`; it never dispatches an action.

And no golden can compensate, because `Attr.t`'s sexp prints every handler as `<handler>`
(visible throughout `test_gallery.ml:332`'s golden). So for these three attrs there is *no*
headless evidence at all that the right closure is behind the right name: not the sweeps, not the
goldens, not the actions.

**Wrong conclusion.** An app wires `Attr.on_position_changed` on a `Node.paned` to the wrong
setter (a copy-paste from a sibling splitter). `dune runtest` is green — the sweeps pass, the
golden shows `(On_position_changed <handler>)`, and no test can invoke it. Only
`test/live/live_containers.ml` (opt-in, `BONSAI_GTK_LIVE_TESTS=1`) or the running app finds it.

Fix, cheapest first: (i) add a sweep in `test/handle/test_gallery.ml` asserting that every name
in `List.filter Attr.Name.all ~f:Attr.Name.is_event` is reachable by some `Action` — a
hand-maintained mapping is fine, since the point is to make the *next* omission a failure;
(ii) add the three actions (`Set_revealed`, `Set_position`, `Set_visible_child`), which is the
same shape as `Set_expanded` and `Set_page`; or at minimum (iii) state the three by name in the
mli's `Action` doc.

### I2. `test/handle/test_handle.ml:1818` and `:2151` accept an output their action never running would produce

Both "declined" tests have the same shape:

```
let declining (graph @ local) =
  let page, _set_page = Bonsai.state "score" graph in       (* the setter is discarded *)
  ...  ~attrs:[ Attr.test_id "tabs"; Attr.on_page_changed (fun _ -> Ui_effect.Ignore) ]
...
Bonsai_gtk_test.Handle.do_actions handle [ Set_page ("tabs", "parts") ];
Bonsai_gtk_test.Handle.show_diff handle;
[%expect {| |}]
```

(`:1787-1819` for the notebook; `:2124-2152` for the drop-down, identically.) The handler is a
constant `Ui_effect.Ignore` and the model has no setter, so the *only* thing the empty golden
records is that the tree did not move. Replace `| Set_page (id, key) -> … h key` in
`test_lib/bonsai_gtk_test.ml:262-269` with a no-op returning `Ui_effect.Ignore`, and both tests
stay green. Their comments claim more than that — "A model that *declines* the change renders the
page it was already rendering, so the node is unchanged — which headless is the whole of the
claim" — but "the model declined" and "the action did nothing" are indistinguishable in the
accepted output.

Both are the *only* declining test for their action, so the property "a declining model is
declining rather than unreached" is pinned nowhere for `Set_page` and `Set_selected`. (The
positive tests at `:1746` and `:2086` prove the actions fire, in separate handles, so the suite as
a whole is not blind — but a reader taking either declining test at its word is.)

The branch already contains the right pattern twice, in the same file:
`test_handle.ml:2311` ("a date picker that declines weekends") drives accept → decline → accept
through *one* handle with a `chosen` label, so the empty diff at `:2378` is bracketed by two
non-empty ones; `test_handle.ml:1996` ("a text view's model accepts one edit and refuses the
next") does the same at `:2024`, and its comment explicitly adds "the model is still live
afterwards: a decline is not a wedge." Fix: make the two weak tests follow their neighbours —
give the declining model a real setter it refuses, or add a label recording the attempt, so the
golden shows the handler ran.

### I3. `Set_text` can deliver text the runtime refuses to write, and nothing says so

`src/widgets/w_text_view.ml:174-186` refuses a `~text` containing a NUL byte or invalid UTF-8:
the write is declined, the buffer is left as it was, the cache is untouched, and the refusal is
reported once per distinct text through `Patcher.ctx.report`. `w_editable_label` does the same for
NUL. This is refuse-record-report, not a raise — but it is unambiguously the runtime declining a
state, and the handle's contract is that a green headless suite means the runtime will hold the
tree.

`Action.Set_text` (`test_lib/bonsai_gtk_test.ml:131-135`) hands the handler *exactly* the string
given, and `Result_spec.view` validates only `Placement`/`Events`/key-phase, so the resulting node
is printed and accepted. The mli's `Set_text` doc (`:12` onward) explains at length why the node's own
`text` is not consulted; it does not mention NUL or UTF-8, and neither does the `create` doc's gap
list.

**Wrong conclusion.** A model loads note text from disk or from a network payload and the test
drives it through `Set_text ("body", contents)` where `contents` carries a NUL (a truncated file, a
length-prefixed blob). The golden shows `(Text_view ((text "line1\000line2")))`, the test asserts
the note round-trips, and it passes. Live, the write is refused every frame, the buffer keeps the
previous text, and the only signal is one line on stderr from `default_report`.

The NUL half is decidable in pure OCaml (`String.mem text '\000'`), and so is UTF-8 validity
(`Core`'s `String.Utf8`); the runtime uses `Glib.Utf8.validate` only because it is already linked.
So this is a fourth item for the gap table rather than a genuine impossibility. Adjacent backlog
entry — "Should `entry`/`search_entry`/`password_entry` refuse a NUL the way `text_view` does?"
(`docs/m2-backlog.md`, "Do first in M3") — is about the *runtime*'s asymmetry across five widgets;
this finding is about the *handle* certifying what the runtime already refuses on the two that do
check, and stands whichever way that question is answered. (If the three entries are made to
refuse too, the handle gap grows to five widgets.)

### I4. Three comments claim "the one place" where the headless suite over-certifies; there are at least five

`test/handle/test_handle.ml:2158-2160`:

> That asymmetry is worth pinning: **it is the one place in M2** where a headless suite going
> green does not mean the runtime will hold the state, and the runtime says so out loud rather
> than silently.

`docs/m2-backlog.md` (Do first in M3, the `row_activatable` entry) says the same of a different
case: "It is **the one place** the headless handle certifies something the runtime will not do,
everywhere else in M2 considerable trouble was taken so that it cannot". Two mutually exclusive
"one place" claims, and neither is right. The set, from the ledger's own record:

1. `drop_down ~selected:-1` over a non-empty list, and an index past the end
   (`test_handle.ml:2161`, Task 10).
2. `Activate_row` on a row carrying `Attr.row_activatable false`, and its two followers
   (backlog, Task 6 M5).
3. `text_view`/`editable_label` text the runtime refuses to write (I3 above, Task 9).
4. `notebook ~current_page` naming a page whose child is hidden — Task 8's recorded GTK fact:
   `set_current_page` emits `switch-page` and leaves the current page unchanged. Headless the node
   simply renders the new page.
5. `list_box`/`flow_box` `~selected` naming keys with no rows — the ghost-key rule (Tasks 6–8):
   deliberate, inert until the row arrives, and correct — but headless the golden shows the key
   selected on a frame the widget does not.

Each individually is documented where it lives. What is wrong is the *aggregate* claim, repeated
in two places, that there is exactly one. A reader who has read either sentence will not go
looking for the other four. Fix: replace both with a single list (the gap table below is it), or
drop the superlative.

### I5. The completeness sweeps do not run in the package whose types they check

`test/dune` is package `bonsai_gtk` and depends on `bonsai_gtk.vtree` only; `test/handle/dune` is
package `bonsai_gtk_test`. Both files carry a clear comment explaining why, and the split is
correct as a build constraint. The consequence is not stated anywhere:

`dune build -p bonsai_gtk @runtest` — which is literally what `bonsai_gtk.opam`'s `build:`
stanza runs under `--with-test` — masks `test/handle/`. So the three sweeps that guarantee
"a kind added to `Kind.t` fails until someone puts a node of it in the gallery" and "an attr added
to `Attr.Name.t` fails until someone places it" (`test_gallery.ml:650`, `:671`, `:1006`) do **not**
run when `bonsai_gtk` is installed with tests, even though `Kind.t` and `Attr.Name.t` are
`bonsai_gtk`'s own types. They run only under a bare `dune runtest` or `scripts/ci.sh`.

The mirror is true too: `dune build -p bonsai_gtk_test @runtest` masks `test/`, so the two shared
tables the handle depends on (`test/test_events.ml`, `test/test_placement.ml`) are not checked when
the handle package is tested.

Neither is a defect in the split — the split is forced. But `README.md:296-300` says only that
"`dune runtest` alone only runs the pure and headless suites"; it does not say that *neither
per-package `@runtest` runs both*, which is the fact a downstream packager needs. Fix: one sentence
in README §Development, and — if it is worth more than that — a `(package bonsai_gtk)` alias
depending on both, or moving the kinds/attrs sweeps (which need only `bonsai_gtk.vtree` +
`Attr.Name.all`, not `Bonsai_gtk_test`) into `test/`, where they would run under both.

---

## Minor

- **M1. `Set_selection` ignores `selection_mode`.** `test_lib/bonsai_gtk_test.ml:244-255` picks the
  attr by kind and hands the handler the key list verbatim. `Selection_mode.t`
  (`vtree/selection_mode.ml`) has `None_`, `Single`, `Browse`, `Multiple`. A test may deliver two
  keys to a `~selection_mode:Single` list box, or any key at all to a `None_` one, and certify a
  model handling a selection GTK can never report. The mli's `Set_selection` doc says only that the
  node's `~selected` is not consulted; `selection_mode` is a *kind prop*, not `~selected`, and is
  not mentioned. Same shape as the documented `Click_at`/`~button` decision, so the fix is a
  sentence, not a check. (`test_handle.ml:1441`'s card grid is `Single` and correctly only ever
  delivers zero or one key, so the suite does not currently violate this.)
- **M2. `Set_value` ignores `~digits`; `Set_text` ignores `~max_length`.** The mli's `Set_value`
  doc carefully covers `min`/`max` ("there is no GTK adjustment headless"), but not the spin
  button's `~digits`, which GTK rounds to. `Set_text` covers nothing of the kind, though
  `w_entry`'s reassert compares against the `max_length`-truncated text (ledger, Task 3), so a
  headless golden can show an entry holding more characters than the widget will ever hold. Two
  sentences, in the doc that already sets the precedent.
- **M3. `paned_props.position` is erased from every golden and has no action.** `vtree/kind.mli:244`
  — `position : int option [@sexp_drop_if Option.is_none]`. `None` is "GTK decides", and it is what
  a model renders when it has not computed a position — indistinguishable in the sexp from a model
  that never had the field. Combined with I1 (no `Set_position` action) and the `<handler>` sexp,
  the paned's controlled position is invisible to the headless suite in both directions. Every
  other controlled prop deliberately carries no `sexp_drop_if` and the mli says so at `:203`,
  `:282`, `:298`, `:325`; this is the one that does, and no comment marks it as the exception.
- **M4. `with_check` renders the whole tree's sexp and throws it away.**
  `test_lib/bonsai_gtk_test.ml:360-366` calls `Result_spec.view`, whose second line is
  `Sexp.to_string_hum (Node.sexp_of_t node)`. Only `require_supported` is wanted;
  `require_supported ~path:"root" ~parent:None node` is in scope at that point. As written,
  `recompute_view_until_stable` renders the full sexp of the tree up to `max_computes` (default
  100) times per call, and any `sexp_of` that raised would surface as a check failure. One-line
  change, no behaviour difference.
- **M5. "props take part in `equal_props`" varies one field.** `test/test_widgets.ml:29`, `:499`,
  `:643`, `:797`, `:918`, `:1032`, `:1120`, `:1279`, `:1336`. Every `equal_*_props` is
  `[@@deriving equal]` (`vtree/kind.ml:27` onward), so per-field participation is the compiler's
  guarantee and these tests pin only that `equal_props`'s arm dispatches to the right derived
  function. That is worth having; the titles claim the broader property. Note this is also **what
  all three sweeps would miss together**: the kinds sweep compares names, the attrs sweep compares
  names, the lifecycle sweep varies one prop per kind (`test_gallery.ml:910`), and these vary one
  or two — so a hand-written `equal_props` arm ignoring a field is caught by nothing. The `Native`
  arm (`kind.ml`, `phys_equal a.payload b.payload`) is exactly such a hand-written arm, and
  `test_gallery.ml:904-909` documents that the sweep skips it.
- **M6. `bonsai_gtk_test` the *package* is not ocgtk-free, though the library is.** The mli
  (`:321-324`) says "This library depends on `bonsai_gtk.vtree` alone -- that is what keeps it, and
  the view functions written against it, free of ocgtk". True of `test_lib/dune`'s `libraries`
  field. But `bonsai_gtk_test.opam` depends on `bonsai_gtk {= version}`, and `bonsai_gtk.opam`
  depends unconditionally on `ocgtk {>= "0.1~preview2"}` — because `vtree/` is a sub-library of the
  `bonsai_gtk` package, not a package of its own. So a CI machine that wants only the headless
  handle must still install GTK4 and the pinned ocgtk fork. Closing it means a third package
  (`bonsai_gtk_vtree`); not worth doing in M2, but the mli sentence should say "the library" rather
  than leaving a reader to infer the install is light.
- **M7. `bonsai_gtk_test.opam` over-declares `ppx_expect`** as a hard (non-`with-test`) dependency
  while `test_lib/dune` preprocesses with `ppx_jane` only. Defensible — consumers of a test handle
  write expect tests — but it is the one dependency in either opam file that no stanza in the
  package needs. From `dune-project`'s `(package bonsai_gtk_test)` stanza.
- **M8. `Handle.do_actions` reads a tree that may never have been checked.** The mli promises "there
  is no way to advance a handle *through this module* past a tree without checking it". `do_actions`
  does not advance, but it does dispatch against `Driver.result`'s current tree, so
  `create app |> fun h -> Handle.do_actions h [ Click "x" ]` with no intervening entry point acts on
  an unvalidated tree. No test in the branch does this (every `do_actions` follows a `show` or a
  `recompute_view`), and the failure mode is benign (the next entry point raises). Worth a clause
  in the mli's guarantee, not a check.
- **M9. The six-entry-point test exercises one of the three checks.** `test_gallery.ml:1099` proves
  all six entry points reach `Result_spec.view` using an `Events` violation only. Placement and
  key-phase share the same call site (`bonsai_gtk_test.ml:112`), so this is sound by construction —
  but the test's own header calls itself "the regression" for the whole guarantee, and a future
  refactor that moved one of the three checks out of `view` (into, say, `show` alone) would not
  move this golden. A three-row table instead of six lines would close it for the cost of the
  rows.

---

## Handle-vs-runtime gap table

What `Patcher.mount`/`patch`, `Driver`, and the controlled-prop writers reject or refuse, against
what `Bonsai_gtk_test` checks. "vtree-decidable" = computable from `bonsai_gtk.vtree` alone, which
is what `test_lib` already links.

| # | What the runtime rejects | Where | vtree-decidable | Handle checks | Documented as a gap |
|---|---|---|---|---|---|
| 1 | Event attr the kind cannot emit | `signals.ml:163-177` ← `patcher.ml:485` | yes (`Events`) | **yes** | n/a |
| 2 | Placement attr the parent does not read | `patcher.ml:366` | yes (`Placement`) | **yes** | n/a |
| 3 | Two key attrs, different `~phase` | `controllers.ml:294` | yes (`Events`) | **yes** | n/a |
| 4 | Root is not a `Node.window` under `start`; *is* one under `embed` | `driver.ml:49`, `:56` | yes (one match) | **no** | **no** — absent from mli and README §Headless (C1c) |
| 5 | `Node.window` below the root | `patcher.ml:357` | yes (2 lines) | **no** | listed, wrong reason (C1a) |
| 6 | Duplicate keys among siblings | `reconcile.ml:24` ← `patcher.ml:553`, `:818` | yes (already exported + tested) | **no** | listed, wrong reason (C1a) |
| 7 | `Node.grid` child with no `Attr.grid_cell` | `w_grid.ml:16` | yes (parent kind + child attrs) | **no** (only the negative half) | listed, wrong reason (C1a) |
| 8 | `~visible_child` naming no page | `w_stack.ml:92` (fixup) | yes (+ empty-stack carve-out) | **no** | listed, wrong reason (C1a) |
| 9 | `~current_page` naming no page | `w_notebook` fixup | yes | **no** | README §Limitations only |
| 10 | Two stacks under one `~name` | `patcher.ml:49` | yes (tree walk) | **no** | listed, wrong reason (C1a) |
| 11 | `stack_switcher`/`_sidebar` naming no stack | `patcher.ml:64` | yes (tree walk) | **no** | listed, wrong reason (C1a) |
| 12 | `stack`/`list_box`/`flow_box`/`notebook` child with no `~key` | `node.ml:30` **constructor** (+ `w_stack.ml:39` backstop) | — | **yes, already** | listed *as a gap*, which is wrong (C1b) |
| 13 | Slot/children shape mismatch | `patcher.ml:645`, `:920` | no (needs impls) | no | not listed; unreachable via `Node.*` |
| 14 | `Move` to a container with no `move` | patch path | yes (`~ordered`) | n/a — the handle never diffs | n/a |
| 15 | `text_view`/`editable_label` text with NUL or invalid UTF-8 (refuse-record-report) | `w_text_view.ml:174` | yes (NUL certainly; UTF-8 with `Core`) | **no** | **no** (I3) |
| 16 | `entry`/`search_entry`/`password_entry` NUL — silently truncated, rewritten every frame | `w_entry` (no check) | yes | **no** | backlog (M3 "Do first"), as a runtime question |
| 17 | `entry ~max_length` truncation | `w_entry` reassert | yes | **no** | **no** (M2) |
| 18 | `drop_down ~selected` = −1 over a non-empty list, or past the end | GTK, at mount; reported | no (GTK decides) | no — by design | **yes**, `test_handle.ml:2154` + mli |
| 19 | `Activate_row` on `row_activatable false` (and its two followers) | GTK never emits | yes | no — by design | **yes**, backlog |
| 20 | `list_box`/`flow_box` `~selected` naming no child | ghost-key rule | yes | no — by design, correct | yes, `node.mli:28-33` |
| 21 | `notebook ~current_page` on a hidden child | GTK (Task 8) | no | no | task-8 record only |
| 22 | `Set_selection` beyond `selection_mode` | GTK never emits | yes | no | **no** (M1) |

Rows 4–12 and 15–17 are the ones C1 is about: fourteen runtime rejections, thirteen of them
vtree-decidable, one already closed and mis-listed as open.

### Action fidelity

Twenty of twenty-three event names have an action. The three that do not — `On_revealed`,
`On_position_changed`, `On_visible_child_changed` — are I1. Of the twenty that do, the divergences
from the runtime's handler path are:

| Action | Diverges from the runtime by | Documented |
|---|---|---|
| `Toggle` | reads the *node's* `active`; the runtime reads the widget's `get_active`. Agree only because the `in_patch` guard suppresses programmatic writes | yes (mli + `bonsai_gtk_test.ml:53`) |
| `Set_value` | no adjustment: unclamped by `min`/`max`, **unrounded by `~digits`** | min/max yes; digits **no** (M2) |
| `Set_text` | any string, including NUL / invalid UTF-8 / beyond `~max_length` | **no** (I3, M2) |
| `Click_at` | `~button` not consulted | yes |
| `Key_press` | `~phase` inert; `Handled` not acted on; no chain | yes, twice |
| `Activate_row` / `Activate_child` / `Set_page` | key need not name a child; `row_activatable false` fires | yes (mli + backlog) |
| `Set_selection` | key list need not respect `selection_mode` | **no** (M1) |
| `Set_selected` | index not range-checked | yes, at length |
| `Select_day` / `Set_editing` / `Focus_*` / `Activate` / `Search_changed` / `Set_expanded` / `Click` | faithful | — |

### What all three sweeps miss together

1. An event attr with no action (I1) — the attrs sweep is satisfied by presence in `sweep_tree`,
   and all three offenders are there.
2. Which closure is behind an attr — every handler sexps as `<handler>`, so no golden distinguishes
   a correctly-wired attr from a mis-wired one; only an action firing it can. Combined with (1),
   three attrs have neither.
3. A per-field regression in a hand-written `equal_props` arm (M5) — names, names, and one prop
   per kind.
4. A controlled prop erased at its default (M3, `paned position`).
5. Anything about the *root*: the sweeps' `Root` placement exists only for the `Window` row
   (`test_gallery.ml:746-752`), so no sweep would notice the root-kind rule going unchecked (C1c).

---

## Verdict

**Approve with fixes.** No code defect found in `test_lib/` or in any headless test; the library
does what its implementation says, the shadowed entry points genuinely close the hole Task 13
found, and the three sweeps are real nets rather than decorative ones. The Critical is a
documentation defect, but it is the defect that matters most for a review of the tests: three
places tell a reader that the headless suite catches everything catchable without GTK, and the
true figure is three of sixteen. Fixing C1 is prose plus the gap table above; I1 and I2 are each
a few lines of test; I3–I5 are sentences. None blocks the merge.

If any of it is to become code rather than prose, the order by value is: the root-kind check
(C1c — cheapest, and the failure it prevents is unrecoverable), the duplicate-key check
(row 6 — the function is already written and already tested), `Node.window` below the root
(row 5 — two lines), then an action-coverage sweep (I1).

---

# Re-review (fix wave)

Re-checked at `36aa26c` against `f06a615`, read-only, nothing built. Only my own findings.

## Verdict

**All five Important findings and all three halves of the Critical are closed.** Six of my
nine Minors were taken and three backlogged with reasons. The three new handle checks are
faithful to the runtime — I compared the message strings byte for byte after normalising
OCaml's `\`-continuations, and all three are identical; the duplicate-key path prefixing
matches the patcher's for both the plain-list and the slot-list case; the empty-stack
carve-out is untouched (no `~visible_child` check was added, and `w_stack.ml`'s carve-out
comment is intact and now carries a new measured caveat of its own). The three new actions
each reach the runtime's own handler payload type and the new test moves all three models
with three distinct values. The two declined tests now bracket their empty diff with a
non-empty one on each side, so a no-op action would fail them.

The gap table on `create` is accurate: I re-derived every row at HEAD and found one omission
(N1 below) and no wrong row. **Nothing found in this pass rises above Minor.** Approve.

## What I verified, item by item

**C1(a) — the false reason.** Gone from both copies. `test_lib/bonsai_gtk_test.mli:431-497` (`:437`)
now says outright: "Most of what is still unchecked is decidable from `bonsai_gtk.vtree`
alone, which this library already links; the honest reason is that nobody has written those
checks yet." `README.md:273-282` no longer restates the list and points at the table
instead. Closed.

**C1(b) — the constructor-checked items.** Row 7 of the new table reads
"stack/list_box/flow_box/notebook child with no `~key` — yes, at the constructor", and
`README.md:483-495` now says "A `list_box`/`flow_box`/`notebook`/`stack` child with no key
is rejected earlier still, by the constructor, so it stops a headless test too." Matches
`vtree/node.ml:30` and the four tests at `test/test_widgets.ml:530`, `:553`, `:674`, `:826`.
Closed.

**C1(c) — the root-kind rule.** `create` gained `?root_kind:[ \`Window | \`Not_window ]`
(default `` `Window ``), `Result_spec.check` runs `check_root` before `require_supported`,
and the runtime runs `Driver.check_root` at `src/driver.ml:86` inside `frame_body` before
the patcher walks — so the two orders agree, which is what the new comment claims. Both
messages are byte-identical to `driver.ml:45-61`'s, verified mechanically. The golden at
`test/handle/test_handle.ml:2661-2710` covers all four cells of the matrix plus
`recompute_view` (the entry point that builds no view). Closed.

Three things I checked that could have broken and did not:

- The mutable `current_root_kind` global is argued honestly, and the argument holds: every
  root kind is accepted by exactly one of the two rules, so a stale rule always yields a
  loud rejection of a legal tree, never a silent acceptance. The alternative they tried and
  rejected (wrapping the computation) is correctly described — raising inside a `Bonsai.map`
  does poison Incremental for the rest of the process.
- `create` sets the ref *before* `Handle.create`, so the first frame is checked against it.
- The existing ~45 handle tests all have `Node.window` roots, so the `` `Window `` default
  does not turn any of them red. The one that could have — `test_gallery.ml`'s lifecycle
  sweep, whose `Root` placement makes the row's own node the root — uses `Root` on exactly
  one row (`test_gallery.ml:1076`), and that row is `Node.window`.

**C1 residual, and the reason it is not a finding:** the two copied messages are copies, not
shared code, because `test_lib` cannot link `bonsai_gtk`. The commit says so and points at
the goldens as the thing that keeps them in step. That is the right structure available; a
shared `vtree` module holding the three strings would be better and is not worth a round.

**I1 — three actionless event attrs.** `Set_revealed`, `Set_position` and
`Set_visible_child` added (`test_lib/bonsai_gtk_test.ml:13-15`, `:275-294`). Payload fidelity
checked against the runtime:

| Action | handle passes | runtime passes | verdict |
|---|---|---|---|
| `Set_revealed` | `bool` → `On_revealed of bool Handler.t` | `W.Revealer.get_child_revealed` on `notify::child-revealed` (`w_revealer.ml:27`) | ✓ and the mli's "the state GTK reports at the end of its transition" is exactly right — `child-revealed`, not `reveal-child` |
| `Set_position` | `int` → `On_position_changed of int Handler.t` | `W.Paned.get_position` on `notify::position` (`w_paned.ml:17`) | ✓ |
| `Set_visible_child` | `Key.t` (= `string`, `vtree/key.mli:3`) → `On_visible_child_changed of string Handler.t` | `W.Stack.get_visible_child_name` (`w_stack.ml:119`), which is the child's `~key` | ✓ |

The new sweep at `test_gallery.ml:699-758` is exhaustive over `Attr.Name.t` with no wildcard,
so a name added to the type is a compile error there. The test at `test_handle.ml:2765-2884`
fires all three in one `do_actions` with three distinct values and shows three distinct
diffs, so a mis-wiring would move the wrong one. Closed.

**I2 — the two declined tests.** Both rewritten to accept → decline → accept through one
handle with a real setter that refuses exactly one value (`test_handle.ml:1788-1877` for the
notebook, adding a third "settings" page; `:2184-2257` for the drop-down, refusing index 3).
Replacing `Set_page`'s or `Set_selected`'s arm with a no-op now fails the first and third
`show_diff` of each. Closed, and both now match the shape the date-picker and text-view tests
already had.

**I3 — text the runtime refuses.** Documented on `Action.Set_text` (mli `:19-25`) and as rows
14 and 15 of the table. Separately, `2d72884` widened the *runtime*: `W_entry.set_text_if_needed`
(`w_entry.ml:144`, `unwritable` at `:105`) now refuses a NUL for every `GtkEditable` —
`entry`, `password_entry`, `search_entry` and `editable_label` all route through it — so row
14's "a NUL in **any** text, or invalid UTF-8 in a text_view" is precisely true at HEAD, not
an approximation. That also closes the backlog's open question about the three entries in the
direction that makes the row simpler. Closed.

**I4 — "the one place".** Both superlatives gone. `test_handle.ml:2251-2257` now says "one of
the six places … The list lives on `Bonsai_gtk_test.create`, once", and the backlog's
`row_activatable` entry no longer claims to be the only one. The canonical list is the
`{3 Where a green headless suite does not mean the runtime will hold the state}` section of
`create`'s doc. Six bullets, four marked deliberate, and both counts check out. Closed except
for N1 below.

**I5 — the `-p` split.** `README.md:310-322` now states the consequence in both directions,
names the three sweeps that do not run under `-p bonsai_gtk @runtest` and the two table tests
that do not run under `-p bonsai_gtk_test @runtest`, and records why the move was not made:
the kinds and attrs sweeps read `gallery_tree`, which the handle-based lifecycle sweep in the
same file also reads, so relocating them to `test/` is a rewrite rather than a file move. I
confirmed that: `sweep_tree` at `test_gallery.ml:631` is `gallery_tree ~n:0`, and
`lifecycle_app`/`sweep_rows` in the same file need `Bonsai_gtk_test`. **The sweeps were not
moved**, so the answer to "does the relocated sweep still run under both per-package
`@runtest`s" is that there was no relocation — the finding was closed as documentation plus a
recorded reason, which I think is the right call for a fix wave. Closed as scoped.

**Minors.** M1 (`selection_mode` not consulted), M2 (`~digits` and `~max_length`), M3 (paned
`position` erased at its default — now stated on `Set_position` itself, which is the right
place), M4 (`with_check` calls `Result_spec.check`, not `view`, so the sexp render is gone
from both shadowed entry points and from `store_view`), M6 (mli distinguishes the *library*
from the *package*), M8 (`do_actions` clause) all taken. M5, M7, M9 backlogged with the
reasons and cross-references intact (`docs/m2-backlog.md`, the "headless M5/M7/M9" entries).

## New, all Minor

- **N1. The canonical six-place list omits the *prop* form of the `selection_mode`
  disagreement.** Bullet four covers `Action.Set_selection` delivering more keys than the
  mode allows. The same divergence exists without any action: `Node.list_box
  ~selection_mode:Single ~selected:[ "a"; "b" ]` is a legal node, prints
  `(selected (a b))` in a golden, and live `W_list_box.apply_selection`
  (`w_list_box.ml`, "Nothing is clamped: what the model asked for is written, and what GTK
  kept is what the next frame's comparison reads back") writes both, GTK keeps one, and the
  comparison differs on **every frame for the life of the tree**. `vtree/node.mli`'s
  `list_box` doc states this exactly and at length — so it is documented on its constructor
  like the ghost keys — but it is not on the list that now claims to be the one copy. The
  fix keeps the count at six: widen bullet four to say the same is true of `~selected` as a
  prop, and point at `Node.list_box`. Worth doing precisely because a canonical numbered list
  that is off by one on the day it lands is how the last superlative rotted.
- **N2. `require_unique_keys` checks every slot before recursing into any slot.**
  `test_lib/bonsai_gtk_test.ml:98-106` (called at `:141`) walks all slots for duplicates, then
  `Children.iteri` recurses into all children. The patcher interleaves: `mount_slots`
  mounts each slot completely (`check_unique_keys`, then each child) before starting the
  next. So an `overlay` or `list_box` whose *first* slot's subtree carries a bad event attr
  and whose *second* slot has duplicate keys reports the event attr at mount and the
  duplicate key in the handle. Both messages are correct and both are `Invalid_argument`;
  only which one you see differs, and only when a tree has two distinct mistakes in two
  different slots. Narrow enough that I would take the note over the code — and the
  runtime's own cross-slot order rests on `List.map`'s evaluation order, which is a reason
  to soften the "reports the same one here and there" claim rather than to chase it. The
  plain-`List` case, which is the common one, matches exactly.
- **N3. The coverage sweep's `action_for` maps to strings that nothing checks against
  `Action.t`.** `test_gallery.ml:700-712` returns `Some "Set_position"` and friends; deleting
  `Set_position` from `Action.t` (and from `incoming`'s match) leaves the sweep green. The
  sweep is therefore a net in the *addition* direction only — a new event attr fails it,
  a deleted action does not. That is the direction that matters and the comment says so
  ("[Action.t] itself is not walked -- it has no [enumerate]"), so this is a residual rather
  than a defect. If it is ever worth closing, `[@@deriving enumerate]` on a payload-free
  mirror enum would do it.
- **N4. The re-exported `Handle.create` does not set `current_root_kind`.** A handle built
  with `Bonsai_gtk_test.Handle.create result_spec app` inherits whatever the last
  `Bonsai_gtk_test.create` left in the ref. Same loud-not-silent argument applies, and the
  mli already tells callers to prefer `Bonsai_gtk_test.create`; half a sentence on
  `Handle.create`'s doc ("and does not set the root-kind rule") would finish it.
- **N5. The number "six" is now in two places again** — `create`'s doc and
  `test_handle.ml:2251`. The pointer in the latter ("the list lives on
  `Bonsai_gtk_test.create`, once") is the durable half; the count beside it is the part that
  rotted last time. Dropping the number from the test comment costs nothing.

## Gap table, re-derived at HEAD

Row for row against `create`'s table, all verified: rows 1-3 unchanged and correct; **rows 4,
5 and 6 are newly closed** and each verified against the runtime's own raise site and message;
row 7 correctly reclassified as constructor-checked; rows 8-12 correctly still open (nothing
in the wave touched `w_grid.ml:16`, `w_stack.ml`'s `select`, `w_notebook`'s fixup,
`patcher.ml:49` or `:64`); row 13 unreachable via `Node.*`, correct; row 14 now true of all
five text widgets after `2d72884`; row 15 open, and `Node.entry` separately gained a
constructor check for a *negative* `~max_length` (`vtree/node.ml:145-151`), which is adjacent
but does not close it; row 16 correctly `n/a`.

**Count after the wave: three of sixteen checked → six of sixteen, plus one that was always
checked at the constructor.** Of the five that remain and are vtree-decidable (rows 8-12), all
five are tree walks over data `test_lib` already links, and the mli now says so in those words
instead of claiming they need a widget. That is the change I asked for.
