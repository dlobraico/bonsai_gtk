# Task 4 report — HeaderBar and ActionBar, the first Slots widgets since M1

Branch `m3`, commits `9d8f7f4..6749003`: the Task-3 minors commit (`9d8f7f4`, ordered
by the controller as this stretch's first), the task itself (`bd6ee6d`), and a
two-line lock-count bookkeeping commit (`6749003`).
`nix develop -c ./scripts/ci.sh`: **all green** at `6749003`.

## What changed (`bd6ee6d`)

**vtree.** `Kind.Header_bar of header_bar_props`
(`show_title_buttons` default `true`, dropped at default; `decoration_layout :
string option`, `None` = GTK's default, honest because the setter is nullable) and
`Kind.Action_bar of action_bar_props` (`revealed` default `true`, a **plain prop,
not controlled** — the user cannot move it, so there is nothing to reassert; GTK's
revealing-is-not-visibility caveat is on the constructor). `Node.header_bar
?title ?show_title_buttons ?decoration_layout ?start ?end_` and `Node.action_bar
?revealed ?center ?start ?end_`, exactly the plan's interfaces. Both pack areas
require keys, rejected at the constructor naming the child's index
(`require_child_keys`, the list_box precedent, with a pack-area-specific `why`).
`Defaults.Header_bar`/`Defaults.Action_bar` carry the two bool defaults.

**Design rulings carried into the code, per the plan's notes:**
- the title is a **slot child, not a string** (GTK4 has no title setter; an empty
  slot shows the window's title — the live dump exhibits the fallback);
- `Window.set_titlebar` wiring is deliberately absent — Task 8's; until then a
  header bar is an ordinary first child, and the constructor doc says stavekeeper's
  hand-rolled header row (`viewer_window.ml:678-817`) ports either way;
- the pack areas take `move = None` (no reorder primitive, no insert-at-position:
  `after` is unusable and children keep insertion order — the mli says so; keys
  preserve *identity*, `w_overlay`'s bargain);
- one slot-agnostic GTK `remove` serves both areas of each bar;
- `set_use_native_controls` (macOS stoplight chrome) deliberately not exposed,
  stated in `w_header_bar.ml`'s header.

**Impls.** `src/widgets/w_header_bar.ml` and `w_action_bar.ml`: no signals,
`Slots` children (`title`/`center` Singles + two `Slot_list`s), `create`/`update`
over the props (header bar's pair bracketed with `Widget_impl.batch`; the action
bar's single write is not, per the may-write-more-than-one rule), `reassert =
None`. Registry, `interest_of_kind` (`Nothing`), `release_kind` and `Events.
for_kind` (both `[]`) arms added — each a compiler-forced exhaustive-match edit.
`Live_tree` gains `GtkHeaderBar` (`no-title-buttons`, `decoration_layout`) and
`GtkActionBar` (`concealed`) arms; slot membership is visible in the children.

**Tests, nets first.** The M2 coverage mechanism did its job on cue (the plan's
verification): after the kinds existed, the constructor sweep, the lifecycle sweep
and `test_events`' name-checked `all_kinds` all went red until both kinds appeared
in the gallery tree, the sweep row list, and the two hand lists — those failures
are the "failing pure tests" of step 1, and their goldens now carry the rows
(`(HeaderBar ())`/`(ActionBar ())` in the for_kind golden; two lifecycle rows with
`child_ops=start=1I/0M/0R/1U end=0I/0M/0R/0U`). `test_widgets.ml` pins the
defaults-erased sexps (`(Header_bar ())` bare), the valued sexps, the slot shapes,
and all four pack-area key rejections with their exact messages.

**Live.** `test/live/live_chrome.ml` (new executable + rule, `(locks x-display)`):
mounts both bars with keyed slot children under one window, then in one patch
inserts and removes per pack area, empties the title slot and conceals the action
bar. The two `Live_tree.dump`s are the assertion: every child in the slot GTK put
it in (start/title/end inside the header's `GtkCenterBox`, the revealer inside the
action bar), keyed children (`back`, `del`) surviving the edit with their widgets,
the window-title fallback label (`(text chrome) (css (title))`) appearing when the
title slot empties, and `concealed` on the patched bar.

## Deviations from the plan

1. **Step order.** The plan's step 1 asks for failing pure tests first; the
   failing tests here were largely the *derived* sweeps (which cannot be written
   before the kinds exist — they fail by construction the moment the variant
   grows), plus hand-written sexp/rejection tests landed in the same commit. Same
   net effect — red before green is visible in the sweep goldens — but the strict
   file-by-file TDD sequencing is squashed into the one commit.
2. **`live_chrome.ml` does not present its window** (dump-only, `on_window_created`
   ignores), but its rule still takes `(locks x-display)` as the plan's file table
   instructs — the conservative choice `live_containers` already makes.
3. The dune header's and ci.sh's executable/lock counts updated (15/12) in the
   trailing bookkeeping commit, as in Tasks 1 and 2.

## Deliberately left undone

- `Node.window ~titlebar` (Task 8, per the plan's design note).
- Gallery *example* (`examples/gallery.ml`) demonstration — Task 12 owns the
  examples; the handle gallery tree carries both kinds for the sweeps.
- Any popover/menu machinery — Tasks 5–6; the header bar's end area holding a
  menu button is exactly where Task 5's widget will sit.

## Also in this stretch

`9d8f7f4` took the Task-3 review's three Minors: the non-existent
`note_duplicates` reference in both list containers, live_text's caret-after-mount
comment now crediting create-before-connect_all ordering rather than the patch
guard, and the task-3 report's parked/settled ratio amended to
"machine-dependent; sub-microsecond absolute cost" per the reviewer's
non-reproduction.

## ci.sh tail

```
== example smoke
(counter, gallery, embed each held for their 3 s timeout)
all green
```

Full gate at `6749003`.
