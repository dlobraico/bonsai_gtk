# Task 4 review — HeaderBar + ActionBar (9d8f7f4, bd6ee6d, 6749003)

**Verdict: APPROVE**, with four Minors (two are one-line doc fixes; none blocks Task 5).
`nix develop -c ./scripts/ci.sh` re-run by this reviewer at `6749003`: exit 0, **all
green** (tail below). Tree left as found.

## The Task-3 minors commit (`9d8f7f4`)

Matches task-3-review.md's Minors exactly and contains nothing else: Minor 2 (the
`note_duplicates` phantom) fixed identically in `src/widgets/w_list_box.ml` and
`w_flow_box.ml`; Minor 3 (the caret-after-mount comment) rewritten in
`test/live/live_text.ml` to credit create-before-`connect_all` ordering and to note this
test's `P.mount` is not under the patch guard — which is what my non-reproduction
established. Minor 1's amendment landed in the (untracked) task-3-report.md:25, which now
reads "machine-dependent and not a property of the code". All three settled.

## What I verified, per the scrutiny list

**1. Slots vs list children — the shadow-tree shape is right.** `Node.header_bar` builds
`Slots [title Single; start List; end List]` (vtree/node.ml), `Node.action_bar`
`Slots [center Single; start List; end List]`, and both impls declare the same names in
the same order — `mount_slots`/`patch_slots` zip node slots against impl slots and raise
on any name or order mismatch (src/patcher.ml:276-313, 652-688), so a drift between
constructor and impl is loud, not silent. A title-slot child that changes *kind* in one
frame goes through `patch_single`'s Some/Some arm (src/patcher.ml:522-535): the
replacement is mounted, the old live destroyed in place, and `set` (=
`set_title_widget`) swaps the widget — the M0 worked example, correctly inherited. A
keyed child that moves **between** `~start` and `~end_` in one frame is a remove in one
slot's diff and a fresh mount in the other's (the two slot lists are reconciled
independently), i.e. remove+insert with identity loss — correct and unavoidable, but the
mli does not say so; see Minor 3.

**2. Keyed-required + `move = None` on a reorder.** Verified in vtree/reconcile.ml:63-107:
with `~ordered:false` (derived from `Option.is_some ops.move`, src/patcher.ml:552-556)
matching is still by key, **no `Move` is emitted**, and each survivor gets an `Update`
indexed at the position it already occupies (the `from = i || not ordered` branch). So a
within-area permutation is neither rejected nor remove+insert: it patches every child in
place and leaves the on-screen (insertion) order alone — exactly what the mli's
insertion-order sentence claims, and what the header comment in `w_header_bar.ml` says.
The impl's `Move` arm is unreachable and stated as a raise, keeping the two in step.
There is no per-bar reorder golden; the behaviour is pinned generically in
test/test_reconcile.ml ("keyed reorder produces moves, not remove+insert" and the
`~ordered:false` twin at :53-99, :182-216) and against real GTK in
test/live/live_containers.ml:396-403. Acceptable — but the mli's *precedent citation* for
this is wrong, and it is the one substantive error I found: node.mli:1451 says the slot
lists are "unordered on {!list_box}'s terms ([Widget_impl.list_ops.move] is [None])",
while `w_list_box.ml:436` has `move = Some …` (list_box is an **ordered** container that
implements moves by remove+re-insert-at-position). The correct precedent is
{!overlay}/`w_overlay.ml:47` — which the impl header and the report both cite correctly.
See Minor 1.

**3. The window-title fallback.** Exhibited: `test/live/expected_chrome.txt:51-52` shows
`(GtkLabel (text chrome) … (css (title)))` inside the header's `GtkCenterBox` after the
patch empties the title slot — GTK's internal fallback label carrying the *window's*
title ("chrome"), where dump 1 line 15 had the user's `(GtkLabel (text "the title"))`.
Re-adding a title child is not exercised live (the test only goes Some→None), but the
lifecycle sweep's header_bar row patches title **None→Some** headlessly
(test/handle/test_gallery_sweeps.ml:474-476: old row has no `~title`, new row does), so
both directions of the slot are covered across the two suites.

**4. `revealed` as a plain prop — right, and for the stated reason.** The controlled-prop
rule exists for props the *user* can move out from under the model; GTK gives the user no
gesture that changes an action bar's `revealed`, so there is nothing to reassert and no
event to hear. Mechanically there is also nothing to fight: `update` compares old model
value to new model value and never reads the widget back (`w_action_bar.ml`), and GTK
sets the `revealed` property synchronously — the *animation* runs on the internal
revealer's `child-revealed`, which this code never touches or reads (the `Live_tree` arm
even documents that ActionBar has no child-revealed read-back). A patch mid-animation
therefore writes iff the model changed, which is the correct semantics. Reasoning is
stated in all four places (kind.ml, kind.mli, node.mli, the impl header), plus the
revealing-is-not-visibility caveat on the constructor.

**5. The M2 coverage mechanism — verified against the diffs, and it is real.** The nets
are `Kind.Variants.descriptions` (compiler-derived) checked against hand lists, so
growing the variant makes `missing` non-empty in each until a row is added. All gained
both kinds in `bd6ee6d`: the gallery tree (test_gallery_tree.ml, full nodes with keyed
pack children), the constructor-sweep golden (test_gallery.ml), the lifecycle sweep row
list (test_gallery_sweeps.ml, rows exercising title-add, pack insert, and props change —
golden `start=1I/0M/0R/1U end=0I/0M/0R/0U`, whose 1U is what proves keyed match-don't-
recreate at the handle level), `test_events.ml`'s name-checked `all_kinds` (golden rows
`(HeaderBar ())`/`(ActionBar ())`), and `live_events.ml`'s twin (37→39). "Went red until
the rows appeared" is structural, not just claimed. `examples/gallery.ml` did **not**
gain them — the Task-12 drift again — and the report names it under "Deliberately left
undone" with the Task-12 attribution, consistent with the ledger's Task-2 carry.

**6. The rejections.** The four pinned (test_widgets.ml) are the four unkeyed-pack-child
cases — header `~start`, header `~end_`, action `~start`, action `~end_` — with exact
messages naming the constructor as spelled and the child's index
(`"Node.header_bar ~start: child 0 has no ~key (a pack area has no reorder primitive,
…)"`). No tree path, correctly: these raise at the constructor, before any tree exists —
the same shared `require_child_keys` (vtree/node.ml:30-35) the list_box precedent uses.
Of the other candidates: a title slot given a keyed *list* is statically impossible
(`?title:t`); bar-in-bar nesting is legal to GTK and rightly unrejected; a **duplicate
key across the two areas of one bar is accepted** — uniqueness is checked per slot list
(`check_unique_keys` per diff, vtree/reconcile.ml:64-65). I judge per-area to be the
right scope (a key "identifies a child among its siblings", and each slot is its own
sibling list) — but no test or doc pins that choice; see Minor 3.

**7. The two deferrals are recorded where an implementer will look.**
`Window.set_titlebar` → Task 8: stated in `Node.header_bar`'s doc (node.mli, "Where the
bar goes is the application's choice in M3" paragraph), with the stavekeeper
`viewer_window.ml:678-817` port note. `set_use_native_controls`: named and reasoned in
`w_header_bar.ml`'s header — the widget's doc comment being spec §11's designated home
for omissions. Both also in the commit message. (The plan's aside that spec §5.3's table
"gains its HeaderBar/ActionBar rows" is Task 13's to land — there is no spec file in this
repo — though the report's left-undone list doesn't mention it; nitpick only.)

**8. The lock and the bookkeeping.** live_chrome's rule carries `(locks x-display)`
(test/live/dune:121) though the executable never presents (`on_window_created` ignores;
no `present` call) — the plan's file table instructs it and live_containers is the same
shape, so the *choice* is fine. The counts in `6749003` are consistent: 15 executables,
12 locked rules (14 grep hits minus 2 comment mentions), 3 unlocked exceptions named in
the header, and ci.sh's "twelve of the fifteen" matches. But the header's covering
sentence — "The twelve rules whose executable **presents a toplevel** carry `(locks
x-display)`" — is now false for two of the twelve (live_containers, live_chrome, both
dump-only), and the lock-despite-not-presenting reasoning lives only in the task report,
not in the dune file or either .ml header. `6749003`'s entire job was this bookkeeping;
it updated the number and perpetuated the mischaracterization. See Minor 2.

**9. ci.sh at `6749003`** — run once by me, exit 0. Tail:

```
== example smoke
libEGL warning: DRI3 error: Could not get DRI3 device
libEGL warning: Ensure your X server supports DRI3 to get accelerated rendering
all green
```

## Findings

**Important:** none.

**Minor:**

1. **node.mli:1451 cites the wrong precedent, and the citation inverts the fact.** "the
   slot lists are unordered on {!list_box}'s terms ([Widget_impl.list_ops.move] is
   [None])" — `w_list_box.ml:436` has `move = Some` (ListBox has insert-at-position, so
   it honours reorders). A reader sent to {!list_box} to understand the no-reorder
   bargain finds a container that reorders. The correct precedent is {!overlay}
   (`w_overlay.ml:47`), which `w_header_bar.ml`'s own header and the report cite
   correctly. One-word fix.
2. **test/live/dune's header sentence mischaracterizes the twelve locked rules.** "The
   twelve rules whose executable presents a toplevel carry `(locks x-display)`" — two of
   the twelve (live_containers, live_chrome) present nothing; they lock conservatively.
   The counts are all consistent; the *reason* a dump-only rule locks is stated nowhere
   in-tree (only in the task report). Suggest the header say something true: "Twelve of
   the fifteen rules carry the lock — the ten whose executables present a toplevel, plus
   live_containers and live_chrome, which are dump-only but lock conservatively as cheap
   insurance on the shared display" — next to the three already-documented exceptions.
   (Exact presenting-vs-dump-only split per executable is the implementer's to state;
   the point is the current sentence claims a property two of the twelve lack.)
3. **Cross-area behaviour is unpinned and undocumented.** Two facts a user of these bars
   will eventually hit: (a) a duplicate key in `~start` and `~end_` of the same bar is
   accepted (uniqueness is per pack area — defensible, but currently an accident of
   per-list checking rather than a stated choice); (b) a keyed child moved from `~start`
   to `~end_` in one frame is destroyed and re-mounted (the two slot lists diff
   independently), so identity is *not* preserved across areas even though the mli's
   headline is "keys preserve identity". One sentence in the header_bar doc covers both;
   a two-line addition to the rejection/sexp tests would pin (a).
4. **The live_chrome comment (and the report) overclaim what the dump proves.** "The
   header's [back] and the bar's [del] keep their widgets across the edit … which the
   dump shows as the surviving buttons" — the dump shows presence and slot, not widget
   identity; a destroy+recreate would print byte-identically. Identity-on-key-match is
   actually pinned by test_reconcile.ml and by the lifecycle sweep's `1U` (an Update,
   not a Remove+Insert, for the kept key). The comment should lean on those, not on the
   dump.

**Out-of-scope / for the ledger:**

- The plan's Task 4 file list names `test/test_node.ml` as modified; the pure tests
  landed in `test/test_widgets.ml` beside the other widget sexp/rejection tests instead.
  Better home; no action.
- The report's step-order deviation (TDD squashed into one commit, red-before-green
  visible only via the sweep mechanism) is accurately disclosed and matches how Tasks
  1–3 actually ran; the sweeps make the red structural for *derived* coverage, though
  the hand-written rejection tests' redness is unverifiable after the fact.
- Task 5's popover will be the first *signal-bearing* Slots widget; nothing in this
  task's slot machinery needed touching for it, which is the cleanliness this task was
  scheduled to prove.

## Verification transcript

- `git diff 629ae6a..6749003 --stat` — 26 files, matches the report's inventory; no
  files outside the task's footprint (the two list-container files and live_text.ml are
  `9d8f7f4`'s).
- Read in full: both impls, the vtree diff, patcher slot machinery
  (mount_slots/patch_slots/patch_single/patch_list), reconcile.ml + mli contract,
  live_chrome.ml + golden, all test diffs, both bookkeeping hunks.
- ci.sh: exit 0 at `6749003`, tail above; working tree clean of source changes after
  (only the pre-existing `.beads/issues.jsonl` modification and untracked sdd reports).
