# Task 6 report — ListBox: keyed rows, a key in every handler, and `Child_keys`

**Commit:** `cd2f446` on `m2`, base `7ba161a`. 39 files, +1925/−60.
**Gate:** `nix develop -c ./scripts/ci.sh` → `all green` (the one stderr line is
`live_driver.ml`'s deliberate raise, as in Tasks 4 and 5).

---

## The hazard the brief singled out, resolved

**The patcher tracks the inner widget, not the wrapper.** `Patcher.patch_list`
(`src/patcher.ml:600-655`) keeps `l.widget` — the child's own widget — in `cur`, and
`after_of` reads `(List.nth_exn cur (index - 1)).widget` off that same list. So `insert`,
`move`, `remove`, `updated` and `~after` are *all* handed the application's child, never
the `GtkListBoxRow`.

The fix is the brief's preferred one, `Widget.get_parent`, wrapped in
`W_list_box.row_of ~what` with a `Gobject.Type.name` check rather than a bare `cast` (a
wrong downcast is undefined behaviour, not an exception). Every one of the five sites goes
through it.

I checked the alternative — letting GTK unwrap — empirically and it does not work:
`gtk_list_box_remove` handed an inner child logs `Tried to remove non-child` and does
nothing, and there is no insert-an-inner-child at all. That is recorded in `row_of`'s
comment so the next reader does not retry it.

## Per-step summary

**Step 1–2 (failing tests first).** `test/test_widgets.ml` (constructors, defaults, the
two constructor-time key rejections), `test/handle/test_handle.ml` (the sidebar in
miniature, plus the `Events` and `Placement` negatives), `test/live/live_lists.ml` +
`expected_lists.txt`. Verified failing (`Unbound value "Node.list_box"`).

**Step 3.** `vtree/selection_mode.ml` — `None_ | Single | Browse | Multiple`.

**Step 4.** Four attrs. `Row_selectable`/`Row_activatable` sit beside `Page_title`;
`On_row_activated`/`On_selected_rows_changed` sit after `On_visible_child_changed` and
before the controller block, so no existing `Attrs.diff` ordering moves. `Attr_apply` gets
inert arms in `set` and `unset`; `Events.for_kind` gains
`| List_box _ -> [ On_row_activated; On_selected_rows_changed ]`;
`Placement.read_by` gains `| List_box _ -> [ Row_selectable; Row_activatable ]` and
`Placement.reader` maps both to `"ListBox"`.

**Step 5.** `src/child_keys.ml(i)` — the ephemeron table, `Gobject.same` + the custom
block's pointer hash, exactly `w_search_entry.ml`'s `Echo` pattern.

**Step 6.** `src/widgets/w_list_box.ml`. Rows auto-wrapped; per-row flags read off the
child node; `selected_keys` / `row_by_key` / `apply_selection`; the two specs.

**Step 7.** `Patcher.interest` gains `List_box of Kind.list_box_props`; `enqueue_fixups`
gains the arm; the three exhaustive matches (`note_interest`, `drop_stack_names`,
`destroy`) each got theirs from the compiler.

**Step 8.** `Live_tree` gains `GtkListBox` (selection-mode when not `SINGLE`,
`activate-on-double-click` when single-click is off, `show-separators`, the count of
selected rows) and `GtkListBoxRow` (`selected`, `not-selectable`, `not-activatable`). **No
keys are printed**, per the brief.

**Step 9.** `Bonsai_gtk_test.Action.{Activate_row, Set_selection}`, neither consulting the
node's own props.

**Step 10.** `dune fmt` per directory, `./scripts/ci.sh` → `all green`, one commit.

## Deviations, with reasons

1. **`Child_keys.find_exn` is called from the spec's `fire`, not from its `connect`.** The
   brief put the lookup in `connect`'s closure. That closure is called straight from C and
   is *outside* `Signals.dispatch_payload`, so a raise there would cross into GTK's stack
   frame — the one thing every trampoline in `Signals` exists to prevent. Nothing is lost
   by deferring: the row is an ordinary callback argument that stays valid (unlike a
   click's modifier state, which is why `connect` assembles *that* payload), and the
   lookup is not even reached when the slot is empty. The payload's `'p` is therefore
   `Widget.t`; the application's handler still receives a `Key.t`, which is the actual
   ruling. Written down in `row_activated`'s comment and in `child_keys.mli`'s
   `find_exn` doc.

2. **The row flags are plain `bool`s defaulting to GTK's `true`, not `Option.iter`.** The
   brief's sketch was `Option.iter (row_flag node Row_selectable) ~f:set_selectable`. That
   is wrong in `updated`: a row that *drops* `Attr.row_selectable false` would write
   nothing and stay non-selectable forever. Answering with GTK's own default makes the
   removal case correct, and it is what `w_overlay.measure` already does. Pinned live —
   see the `after the flags swapped` case, which is one of the four caught mutations.

3. **The placeholder is a `Slots` container, not a bare list.** `?placeholder:t` is a
   `Node.t` and so has to be mounted and patched. `Node.list_box` builds
   `Slots [ "placeholder", Single placeholder; "rows", List children ]` — the
   `Node.overlay` pattern. This keeps three facts structural: the placeholder has no key,
   it is never selected or activated, and it takes no part in the rows' reconciliation.
   `get_row_at_index` and `get_index` both ignore it (verified), so the wrapper index
   arithmetic is unaffected.

4. **The required-key check, not a constructor-time *duplicate*-key check.** The task
   message says "constructor-time duplicate-key check"; the brief, and plan author's note
   4, both specify a *missing*-key check, which is what landed
   (`Node.require_child_keys`, retrofitted to `Node.stack`). I deliberately did **not**
   move the duplicate-key check to the constructor: `Reconcile.check_unique_keys` already
   rejects duplicates at mount *and* at patch with the container's node path, which is
   strictly more informative than a constructor message, and moving it would relocate
   three already-tested rejections (`live_containers.ml`'s `dupkey`, `duppage`,
   `patchdup`) onto a message with no path. Say if the other reading was meant.

5. **`w_stack`'s `keyless` live case now reports the constructor's message.** Retrofitting
   the check to `Node.stack` makes `w_stack.page_name`'s raise unreachable through the
   constructor; `expected_containers.txt` moved from
   `rejected: keyless/0/0: Stack child has no ~key …` to the constructor's message. The
   impl-side raise is kept as belt-and-braces with a comment saying why (a `Node.native`
   payload assembling children, a future constructor).

6. **`move`'s "read the index after the removal" is an assumption not made, not a bug
   fixed.** I claimed in a first draft that reading the predecessor's index before the
   removal would be wrong, then mutation-tested it and found no diff. `Reconcile.diff`
   emits every `Move` with `from > to_` (`reconcile.mli:38`), so the predecessor is always
   *before* the moved row and its index is untouched by the removal. Reading after the
   removal is what `~after`'s contract says and stays right if that invariant ever widens;
   the comment now says exactly that rather than overstating it.

7. **The driver-level declined-selection test lives in `live_lists.ml`, not
   `live_driver.ml`.** It is the same claim `live_driver.ml` makes for a toggle
   (`reassert`) and a stack page (a fixup), for the second fixup. Putting it beside the
   rest of the list-box evidence keeps `expected_driver.txt` untouched.

8. **Gallery entry landed now rather than in Task 13** (the task message asked for it; the
   brief's ten steps did not). `examples/gallery.ml` gains a "Lists" page — a `Single`
   list activated by row and a `Multiple` list selected by row, both keyed, with a header
   row and a placeholder; `test/handle/test_gallery.ml`'s sweep gains a `Node.list_box`
   exercising every optional argument and both row attrs. Task 13 should treat this as
   already done for `ListBox`.

## Carries taken from `task-5-review.md`

Four of the six Minors, all cheap:

- **M1** — `vtree/key_event.ml`'s `modifiers` doc said it is "read off the controller while
  the event is still current", which is `Click_event`'s path. It now says the modifiers
  arrive as the callback's `~state` and that a `Key_event.t` can therefore be stored past
  the handler.
- **M2** — the four stale "Task 5 will…" forward references (`vtree/events.mli:23`,
  `src/controllers.ml:53`, `:169`, `:323`) rewritten in the present tense. The `events.mli`
  one was the one that mattered: public API doc calling a landed feature future work.
- **M3** — `vtree/attr.mli`'s `on_key_pressed` said the phase conflict is caught "at
  mount"; it is caught at mount, at patch, and at handle time, all three from
  `Events.key_phase_rejection`. Now says so.
- **M4** — `live_keyvals.ml` gains the caveat that `key_a`/`key_z`/`key_w` are the *second*
  of two declarations, so a MISMATCH on a letter means ocgtk's generator reordered its
  output, not that `Keyval`'s arithmetic is wrong. `key_0`/`key_slash`/`key_space` have no
  duplicate and are called out as the unambiguous ones.

**Not taken:** M5 (`Events.key_phase` is public and answers for a node
`key_phase_rejection` rejects) is explicitly "noting, not a finding" and the fix is a type
change; M6 belongs in Task 12's brief (whatever `Expert.embed` does on a raising frame has
to be "stop", not "skip this frame") rather than in a widget task.

## GTK facts established empirically (throwaway probe, deleted)

Several of these contradict a plausible guess and drove the defaults:

| Fact | Consequence |
|---|---|
| `GtkListBox` `selection-mode` defaults to **`SINGLE`**, not `NONE` | `Defaults.List_box.selection_mode = Single`; `Live_tree` prints the mode when it is *not* `SINGLE` |
| `activate-on-single-click` defaults to **`true`** | printed as `activate-on-double-click` when false |
| `show-separators` defaults to `false`; row `selectable`/`activatable` both default to `true` | the row readers answer `true` on absence |
| `gtk_list_box_remove` handed an **inner child** warns and does nothing | `row_of` is mandatory, not a tidiness choice |
| `get_index` on an unparented row is `-1`; a placeholder is not counted | the index arithmetic is safe with a placeholder present |
| remove + re-insert preserves the row **and its child** | keyed identity across a reorder holds |
| switching `MULTIPLE` → `SINGLE` **clears the whole selection** | noted in `update`; harmless only because the fixup runs after |
| a `selectable false` row cannot be selected however hard you ask | `asking for the header row: (none)` |

## What the tests prove, and the mutations that confirm they bite

`test/live/expected_lists.txt` pins, in order: the mount golden (rows, wrapper props,
placeholder); a keyed reorder moving *the same GObjects* (`Gobject.same` as a set) *and*
where they moved to; a rightward move with a row behind it; a middle insert; the declined
selection; add-and-select in one frame; the selected row removed; a ghost key ignored; a
multi-selection surviving a frame that lists it the other way round **with a write count of
0**; a non-selectable row refusing selection; three keys in `Single` mode; a kind change
replacing the wrapper and keeping the selection; the row flags swapping; teardown firing no
handler; and the whole declined-selection cycle through a real `Driver.frame`
(`after the user clicked: b` → `after the frame the click armed: a (Bonsai saw 1)` →
`after one more frame: a (Bonsai saw 1)`).

Five mutations run against the committed tree, all caught:

| Mutation | Caught by |
|---|---|
| `apply_selection` compares unsorted | `writes for a re-ordered but equal selection: 0` → `3` |
| `updated` does not re-read the row flags | `after the flags swapped: hdr` → `(none)`, plus the dump |
| the `List_box` arm of `enqueue_fixups` removed | `after mount: b` → `(none)`, and every selection line |
| every row registered under `""` | same |
| `Child_keys` keyed on `phys_equal` instead of `Gobject.same` | same — which is the exact failure `child_keys.mli` warns about |

One mutation *not* caught, and deliberately so: reading the predecessor's index before the
removal in `move` (see deviation 6 — it is behaviourally identical under the reconciler's
`from > to_` invariant).

**Not pinned:** `Child_keys.remove` in the `remove` op. Omitting it changes no golden — it
is a bounded leak into a process-wide table, not a behaviour — and the only way to observe
it would be to expose the table's size. Flagged rather than tested.

## Test/CI tails

```
$ nix develop -c ./scripts/ci.sh
== nix: ocgtk pin builds and passes its tests
== format
== build
== generated opam files are committed
== pure + headless tests
== per-package builds, the way opam --with-test runs them
== live tests (xvfb)
bonsai_gtk: exception in frame, stopping the driver: (Invalid_argument
  "root/0/1: a Node.window may only be the root node, not a child of another node")
== example smoke
all green
```

Counts updated: `test_placement.ml` 34 → 36 non-placement names and a `List_box` row in the
`containers` list (without it the new "read by exactly one container" assertion would have
printed `0` and quietly stopped meaning anything); `test_events.ml` and `live_events.ml`
`all_kinds` 29 → 30, checked against `Kind.Variants.descriptions`.

## Carries for Tasks 7 and 8

- **`Child_keys` is ready as specified and needs no change.** `src/child_keys.ml(i)`. One
  table *per container module* — `W_flow_box` and `W_notebook` each declare their own
  `let child_keys = Child_keys.create ()`, never share this one. `find_exn ~what` takes the
  noun (`"flow box child"`, `"notebook page"`).
- **Call `find_exn` from the spec's `fire`, not from `connect`** (deviation 1). This is the
  one thing to copy verbatim; the brief's sketch has the raise crossing into C.
- **Check where the patcher's ops point before writing anything.** For `FlowBox` it is the
  same wrapper problem (`GtkFlowBoxChild`) and the same `Widget.get_parent` answer. For
  `Notebook` it is *not*: `gtk_notebook_remove_page` takes a page index and the page's
  child is a direct child of the notebook, so `Widget.get_parent` gives the notebook, not a
  wrapper — Task 8 needs `page_num`, and its `Child_keys` is keyed on the page's *content*
  widget rather than on a wrapper. Confirm this against the binding before writing.
- **`Node.require_child_keys ~which ~why`** (`vtree/node.ml:30`) is the shared
  constructor-time check; `Node.flow_box` and `Node.notebook` each add one call.
- **The selection fixup is a template, not a shared function.** `Patcher.interest` gains a
  constructor per container and `enqueue_fixups` an arm; the compiler asks for the arms in
  `note_interest`, `drop_stack_names` and `destroy`. `apply_selection`'s sort-before-compare
  is the part a reviewer should check for, and the write-count line is how to pin it.
- **`Placement.read_by`'s comment now names `Notebook -> [ Tab_label ]` as the next arm.**
- **`Live_tree` prints no keys**, here or in Tasks 7–8; the live test prints
  `W_<container>.selected_keys` instead, which is a read *through* the table.
- **Task 8 needs the `Unordered` marker decision made explicitly**: `GtkNotebook` has
  `reorder_child`, so it is `move = Some …` and `~ordered:true` — unlike `ListBox`, which
  also has `move = Some` but implements it as remove-and-re-insert.
- **`Selection_mode.t` is shared** with `FlowBox` (`gtk_flow_box_set_selection_mode` takes
  the same enum); `W_list_box.selection_mode`'s converter is four lines and should be
  lifted to `Gtk_import` when the second consumer arrives, not duplicated.

---

# Fix round 1 — review `task-6-review.md`

**Commit:** `f573799` on `m2`, base `cd2f446`. 8 files, +361/−40.
**Gate:** `nix develop -c ./scripts/ci.sh` → `all green`.

Both findings accepted without argument. Writing C1's regression test turned up a
**second, independent bug of the same family**, which is reported below as C1b — it was
entangled with C1 in the shipped code and neither the review nor I had separated them.

---

## C1 — `selected_keys` destroyed the rows it read

**Accepted; the reviewer's diagnosis is exactly right and I verified every link.**

- `gtk_list_box_get_selected_rows` is `transfer-ownership="container"` —
  `.ocgtk-src/gir/Gtk-4.0.gir:89573` is literally that line.
- `ml_list_box_gen.c:229-238` wraps each row with `Val_GtkListBoxRow((gpointer)_tmp->data)`
  and no `g_object_ref_sink`.
- `ml_gobject.c:373-378` states the contract in the fork's own words: the caller must sink
  a transfer-none pointer first, "since the wrapper's finalizer unconditionally
  `g_object_unref`s on GC".
- `ml_flow_box_gen.c:222-233` is the same call on `GtkFlowBoxChild` **with** the sink and a
  comment describing this exact bug. The `GtkListBox` twin was simply never reached.

**Fix (a).** `W_list_box.selected_keys` now walks a new `rows` helper — `get_row_at_index`
(which sinks, `ml_list_box_gen.c:258-265`) plus `is_selected` — and filters. `row_by_key`
was rewritten on the same helper. Answers in widget order, which is what
`Attr.on_selected_rows_changed`'s doc already promised.

**Fix (b).** `src/live_tree.ml`'s `selected-rows` count now uses a local
`selected_row_count` walk with a comment pointing at `W_list_box.rows`. Counting rather than
calling `W_list_box` keeps `Live_tree` a dump of GTK rather than a read through this
library's tables.

**Fix (c) — the sweep the ruling asked for.** `grep` over the whole tree: the only two uses
of `get_selected_rows` were the two above, both mine, both replaced. Nothing else in this
library enumerates GObjects except `Widget.observe_controllers` in
`test/live/live_controllers.ml`, and I checked its ownership: `gtk_widget_observe_controllers`
is transfer-full and wrapped by an owning `Val_GListModel`, and `g_list_model_get_object` is
transfer-full and wrapped by `ml_gobject_val_of_ext` — both balanced. Nothing to change.

Widening the grep to the *binding*: `Val_GList_with|Val_GSList_with` appears at **47 sites
in the generated stubs and exactly one of them sinks** (the hand-patched FlowBox). The
other 46 are the same latent bug; `Gesture.get_sequences`, `Widget.list_mnemonic_labels`
and `TreeView.get_columns` are among them. None is used here today.

**Fix (d) — the regression test**, first block of `test/live/live_lists.ml`, before
everything else in the file for the reason `live_controllers.ml`'s heap-churn test runs
first: every selection line below it is a read of the selection, so if that read is what
destroys the rows then the whole golden was measuring a tree quietly falling apart. It
mounts a `Multiple` list box with two of three rows selected, then runs 250 frames of
`reassert_only` + `run_fixups` inside `Scheduler.with_patch_guard` — which is exactly what
`Driver.frame` runs on a physically-same-node frame, i.e. what an idle app does 60 times a
second — with `Gc.full_major ()` every 50, printing the selection each time, and dumps the
tree at the end.

**Evidence on the old code.** Running the new test against the pre-fix `selected_keys`:

```
gc: mounted, selected a,b
gc: after 50 frames + full_major, selected (none)
gc: after 100 frames + full_major, selected (none)
gc: after 150 frames + full_major, selected (none)
gc: after 200 frames + full_major, selected (none)
gc: after 250 frames + full_major, selected (none)
```

with, on stderr, `Did you call g_object_unref() instead of gtk_widget_unparent()?`, then
runs of `g_object_unref: assertion 'G_IS_OBJECT (object)' failed` and
`g_object_ref_sink: assertion 'G_IS_OBJECT (object)' failed` — unrefs landing on freed
memory — and finally **SIGSEGV, exit 139**, in `Live_tree.dump`. The reviewer's
reproduction, independently.

**A correction to my own first attempt at that evidence.** My first run of the test
segfaulted immediately with no output at all, and I nearly wrote that up as C1. It was my
bug: the new `let () = …` block ran *before* the file's `GMain.init`, which was inside the
main block. Hoisting init to a top-level statement (as `live_controllers.ml` already does)
produced the honest numbers above. Recording it because "the regression test crashed" is
the kind of evidence that is worth exactly nothing if the cause is the test.

**Post-fix**, the same test prints `selected a,b` at all five checkpoints and the dump shows
three rows with two selected. Mutation: putting `get_selected_rows` back **fails the live
rule outright** (`dune build @test/live/runtest` exits 1 — the process dies part-way through
the golden). Note the failure mode: with the C1b fix in place the corruption is mostly
*stderr*, and dune's `diff` rule compares stdout only, so what makes it bite is that the
process does not survive to finish its output. The test flushes per batch precisely so that
a future regression says how many frames it survived rather than only "got signal SEGV".

**Fix (e).** `docs/m1-backlog.md`'s ocgtk-fork section gains the entry, with the GIR line,
both stub line ranges, the fork's own contract comment, the FlowBox precedent, the 47/1
count, and the ruling that the real fix belongs in the generator rather than in a fourth
hand patch. `w_list_box.ml`'s `rows` comment says outright that nothing in this library may
call `get_selected_rows` until that lands. A general rule of thumb was added beside it:
read the *stub*, not the GIR, and the shape of test that catches this class is N frames + a
`Gc.full_major` + an assertion that the widgets are still there.

---

## C1b — the ephemeron was keyed on a value nothing retained (found while testing C1, not in the review)

With C1 fixed the regression test *still* printed `(none)` from frame 50, while the dump
showed both rows correctly `selected`. So the rows were fine and the **lookups** had
stopped answering.

`Child_keys` is `Ephemeron.K1`, which is weak in the **OCaml value**, not in the GObject.
The key was `(row :> Widget.t)` — the wrapper `wrap` creates — and nothing anywhere
retains that value: it is unreachable the moment `wrap` returns. Every entry was therefore
dropped at the first major collection, however alive GTK kept the row. `w_search_entry.ml`'s
`Echo` table has always worked precisely because *its* key is the widget the live tree
holds.

This is why the shipped `selected_keys` returned `(none)` in the reviewer's reproduction as
well: two independent causes, one symptom.

**Fix.** The table is keyed on the row's **child** — the OCaml value the patcher stores in
`live.widget`, so reachable for exactly as long as the node is, which is the lifetime the
table wants. A row is looked up through `List_box_row.get_child` (`key_of_row`,
`key_of_row_exn`). Uniqueness is unaffected: two list boxes rendering the same child *node*
still mount two distinct child widgets, so the brief's reason for keying on the wrapper
(node sharing) does not apply to widgets.

`child_keys.mli` now states the invariant as a requirement on callers, because **Tasks 7
and 8 inherit it** and it is invisible in the types.

**Mutation:** keying on the row wrapper again turns all five checkpoints from `a,b` to
`(none)`.

---

## I1 — a ghost key rewrote the whole selection every frame

**Accepted.** `apply_selection` now computes
`wanted = List.filter selected ~f:(fun k -> Option.is_some (row_by_key w k))` and compares
`current` against `wanted`; the **write still iterates `selected`**, so ruling 5 is
untouched — what the model asked for reaches GTK and what GTK kept is what the next frame
reads back.

**What a ghost key means, decided and documented.** The reviewer's preferred option, and
the one that landed: *inert until the row arrives, then selected on the frame it arrives.*
That is the same-frame rule `~visible_child` has, and it is the reason the selection is a
fixup rather than a `reassert` — a returning row makes `wanted` grow, the comparison goes
false once, and the row is selected in that pass. `Node.list_box`'s doc now says "inert,
not an error — and inert in the strong sense", spells out the same-frame behaviour, and
keeps the asymmetry with `~visible_child` beside it.

The residual the reviewer excluded is excluded: three keys in `Single`, or a key on a
`row_selectable false` row, still rewrite every frame. `apply_selection`'s comment now
distinguishes the two cases explicitly — a model to bring into line with its mode, versus a
key that is simply not here yet — so the next reader does not "fix" the first by narrowing
the write.

**Tests.** Two new lines, both on the reviewer's suggested instrument:

```
writes on an identical frame with a ghost key held: 0
the ghost row arrived: a,ghost
```

**Mutation:** dropping the narrowing turns the first from `0` to `2`, exactly as predicted.

---

## Minors

**M1 (taken).** `Child_keys` entries are now dropped for a container torn down *whole*, not
only for a child removed from one that stays: `W_list_box.forget_rows` walks the rows and
drops each entry, called from `Patcher.destroy`'s `List_box` arm, where the `GtkListBox`
still holds its rows (the children's own teardown detaches them from Bonsai without
unparenting). `child_keys.mli`'s `remove` doc now names both paths and why they are
different code.

*A mistake this caused, caught before commit.* I first inserted the arm at the bottom of
`destroy`'s kind match, immediately after a long or-pattern chain — so
`| Label _ | Button _ | … | Grid _ | List_box _ -> forget_rows` bound **every** listed kind
to it, and `forget_rows` ran on labels, boxes and buttons. It was silent in the goldens
(`get_row_at_index` on a non-list-box logs and returns `None`) and showed up only as
`gtk_list_box_get_row_at_index: assertion 'GTK_IS_LIST_BOX (box)' failed` on stderr — in
`live_patcher` and `live_controls`, which contain no list box at all, which is what gave it
away. Moved above the chain. I then swept the whole live suite for GTK
criticals and warnings: **0 in all nine executables**, which is also the first time that
has been checked here rather than assumed.

**M2 (taken).** The ordering in `remove` — `Child_keys.remove` *before* `W.List_box.remove`
— now says why it is load-bearing: GTK emits `selected-rows-changed` synchronously from the
remove and `selected_keys` drops rows it cannot find, so forgetting the key first is what
stops a handler being handed the key of a row that has just left the tree. The obvious
tidy-up reintroduces it.

**M3 (taken).** One extra frame in `live_lists.ml` with `~selection_mode:Browse` and
`~activate_on_single_click:false`, whose dump pins the two `Live_tree` spellings nothing
else reached: `(selection-mode browse) activate-on-double-click`. These are the two
properties the report's own table calls out as the ones a reader guesses backwards, so
having them in a golden is worth the frame.

**M4 (noting, no change).** Agreed, and it is worth saying the review is right that nothing
is lost: `rejected: root/0/0: Grid child has no Attr.grid_cell …` on the same golden still
pins that the patcher prefixes a child path. The trade — a message at the point of the
mistake, in exchange for that message having no node path because no tree exists yet — is
plan note 4's, and it is the right one.

**M5 (argued, no change).** `Activate_row` firing on a `row_activatable false` row is the
one place the headless handle certifies something the runtime will not do, and the review is
right that this diff takes considerable trouble elsewhere to make that impossible. I still
think it should stay, and the distinction is between two different kinds of "the runtime
refuses this":

- `Events` and `Placement` reject a **tree**. The mistake is static, it is in the view, and
  a handle that accepted it would certify a program that raises on sight. Refusing is the
  whole point.
- `row_activatable false` refuses an **event**, dynamically, on data. `Bonsai_gtk_test`
  models no event routing at all — it delivers to one node by `test_id`, which
  `bonsai_gtk_test.mli` says at length for clicks and keys — so filtering this one case
  would be the *only* piece of routing it implements, and would read as a promise the rest
  of the harness does not keep.

That said, the review's real point is that the choice is about to be made twice more.
**Carry for Tasks 7 and 8, stated as a ruling to be confirmed rather than a preference:**
`Activate_child` and `Set_page` should follow `Activate_row` — deliver what the test asked
for, consult nothing on the node — and if the controller prefers the opposite, all three
should change together and `bonsai_gtk_test.mli` should gain a sentence saying the harness
models per-widget activability but not routing.

**M6 (agreed, not for this task).** `apply_selection` is O(|selected| × rows), and I1's fix
makes it worse on the frame it does run (`row_by_key` per key for the narrowing, then again
for the write). Both are still bounded by "frames that actually change the selection", which
after I1 is the frames that should write. For `FlowBox` over a few hundred cards this is the
thing to revisit, and a per-container reverse map (key → child) is the answer. Carried.

**M7 (noting, no change).** Correct, and identical to `Attr.measure_overlay` on an
overlay's main child. `placement.ml`'s header already explains why the granularity is the
parent's kind rather than the parent's slot, and says what tightening it would cost. Not
worth threading a slot name for one inert attr.

---

## Files touched

`src/widgets/w_list_box.ml`, `src/live_tree.ml`, `src/patcher.ml`, `src/child_keys.mli`,
`vtree/node.mli`, `test/live/live_lists.ml`, `test/live/expected_lists.txt`,
`docs/m1-backlog.md`.

## Mutation summary for this round

| Mutation | Caught by |
|---|---|
| `get_selected_rows` restored in `selected_keys` | the live rule fails outright (`dune` exit 1; process dies mid-golden) |
| `Child_keys` keyed on the row wrapper again | `gc: … selected a,b` → `(none)` at all five checkpoints |
| ghost-key narrowing dropped from `apply_selection` | `writes on an identical frame with a ghost key held: 0` → `2` |

## Carries updated for Tasks 7 and 8

- **`Child_keys` has a lifetime rule now**: key on the widget the patcher stores in
  `live.widget`, never on a wrapper the impl makes and drops. `W_flow_box` keys on the
  `GtkFlowBoxChild`'s *child* and looks up through `FlowBoxChild.get_child`; `W_notebook`
  keys on the page's content widget, which is already the patcher's child. Stated in
  `child_keys.mli`.
- **Drop entries on both teardown paths**: the per-child `list_ops.remove`, *and* a
  `forget_rows`-shaped sweep from `Patcher.destroy`'s arm for the container. Put that arm
  **above** the big or-pattern chain, not after it.
- **`gtk_flow_box_get_selected_children` is safe** (the fork sinks it) — but read the stub,
  not the GIR, for any other object-returning getter: 46 of the binding's 47
  `Val_GList_with` sites are unsinked.
