# Final review — M1 container & layout widgets

Branch `m1`, HEAD `886b1d5`, base `9f80cd4`. Read-only; no build was run.
Scope: `src/widgets/w_{box,window,label,scrolled_window,frame,expander,revealer,center_box,paned,overlay,grid,stack,stack_switcher,stack_sidebar}.ml`
against `src/patcher.ml`, `src/widget_impl.ml(i)`, `vtree/{children,reconcile,node,attr,kind,defaults}.ml(i)`,
`test/`, `test/live/`, `examples/gallery.ml`.
Items already in `docs/m1-backlog.md` are not re-reported.

## Summary

The container area is in good shape. The `~after:(Widget.t option)` placement ruling is
implemented consistently: I hand-traced `Reconcile.diff` + `Patcher.patch_list` over four
permutations (pure rotate, rotate-with-remove, insert-between-moves, move-to-head) and the
`cur`/`without`/`after_of` bookkeeping produces the correct GTK sibling in every case,
including the kind-change-in-place arm. `Slots` is genuinely the same code as a top-level
shape — `mount_single`/`mount_list` are shared verbatim — so a `center_box` slot going
`Some -> None -> Some` and a slot whose child changes kind are handled by the paths the
single-child containers already prove, and both are covered by `live_containers.ml`.
The stack name registry, the fixup pass, and the switcher/sidebar resolution are correct
for the hard cases the brief names: a switcher declared above its stack, a rename that
drops the old registration, a collision that raises, and `run_fixups` running *inside*
`Scheduler.with_patch_guard` (`src/driver.ml:70-79`) so the corrective `select` write does
not feed itself back to Bonsai. `set_bounds` in `w_scrolled_window.ml:25-35` is correct:
I checked it against nine old/new bound pairs including both `-1` sentinels and both
directions of the overlap, and no write is lost. Label prop precedence
(`use_markup` forcing a text rewrite because `set_text`/`set_markup` each flip it) is
right, and Label correctly has no `reassert` — a `GtkLabel` has no user-driven text edit,
only a selection.

Two findings rise above nits. Neither corrupts the tree; both are diagnosis/behaviour
gaps that a real app will hit.

No Critical findings.

## Critical

None.

## Important

### I1. Duplicate child keys are accepted at mount and only rejected on the first patch — with no node path

`vtree/reconcile.ml:20-29` (`check_unique_keys`), called only from `Reconcile.diff`
(`vtree/reconcile.ml:55-56`), which is called only from `Patcher.patch_list`
(`src/patcher.ml:408-414`). `Patcher.mount_list` (`src/patcher.ml:216-227`) never checks.
The `diff` call is also the one child-list call *not* wrapped in `child_op ~path`
(contrast `src/patcher.ml:430`, `435`, `443`, `455`, `467`), so its message carries no path.

Failure scenario, acute for `Stack` because a page's key *is* its GTK page name
(`src/widgets/w_stack.ml:29-34`):

```ocaml
Node.stack ~name:"nav" ~visible_child:"detail"
  [ Node.label ~key:"detail" "a"; Node.label ~key:"detail" "b" ]
```

- Frame 1 (mount): both pages are added. `gtk_stack_page_set_name` emits
  `Gtk-WARNING **: Duplicate child name in GtkStack: detail` on stderr and proceeds.
  `W.Stack.get_child_by_name` returns the first, so `select` picks page "a" and the second
  page is unreachable — the switcher shows two identical buttons, one of which does
  nothing. Nothing in the library says anything.
- Frame 2 (any patch, and the driver now patches every frame): `Reconcile.diff` raises
  `Invalid_argument "Reconcile.diff: duplicate key detail"`. That message names neither the
  stack, nor the child path, nor the fact that the two keys are page names. In a tree with
  several keyed lists the reader has nothing to search on. `Driver.frame` then marks itself
  broken, so the app dies on its second frame.

This is a §11 conformance gap in two ways: the malformed tree is accepted at mount, and the
eventual rejection is the only child-list `Invalid_argument` without a path prefix.
The fix is two lines: call `check_unique_keys` from `mount_list` as well, and wrap the
`Reconcile.diff` call in `child_op ~path`. (Partly `vtree/reconcile.ml` territory, so it may
also land in the core reviewer's report.)

### I2. A grid cell change drops keyboard focus, and the comment claims the opposite

`src/widgets/w_grid.ml:63-71`:

```ocaml
; updated =
    (fun parent ~old ~node child ->
      (* ... The widget survives, so its focus and its entry text do too. *)
      if not (Grid_cell.equal (cell old) (cell node))
      then (
        W.Grid.remove (cast parent) child;
        attach parent node child))
```

`gtk_grid_remove` is `gtk_widget_unparent`, which unroots the child's whole subtree; GTK
clears the toplevel's focus when the focused widget is unrooted, and `gtk_grid_attach`
re-roots it with no focus. The entry text survives (it is widget state); the focus does not,
and neither does anything else keyed on root/map — an in-progress IM preedit is the other
casualty.

Failure scenario: a form laid out in a `Node.grid` — the shape `stavekeeper` will use — where
a row's `Attr.grid_cell` span widens when a validation message appears beside it. The user is
typing in the `Node.entry` in that row; the model re-renders with
`~width:2` instead of `~width:1`; the entry is detached and re-attached, and the next
keystroke goes nowhere because focus is now on the window. The user sees typing stop
mid-word for no visible reason.

The backlog already accepts that a re-attach moves the child to GTK's end (dump order);
focus loss is a separate consequence and is not listed. Two things are wanted:
(a) correct the comment, which currently asserts focus survives and is the only place a
future reader would look; (b) either save/restore focus around the re-attach
(`gtk_root_get_focus` / `gtk_widget_grab_focus`) or state the limitation in
`Attr.grid_cell`'s doc so callers know not to move cells under a focused subtree.

Note: I verified the OCaml side (the detach/re-attach is unconditional on any cell change)
by reading the code; the GTK-side focus behaviour is from GTK4's `gtk_widget_unparent`
semantics and is *not* exercised by any test in `test/live/` — worth a live assertion
either way, since the current comment is a claim no test backs.

## Minor

### M1. Dropping `Attr.page_title` leaves a blank, clickable switcher button

`src/widgets/w_stack.ml:133-141`. The `updated` hook writes
`Option.value (page_title node) ~default:""`, with the comment `[""] is GTK's "no title":
[set_title] is not nullable`. `""` is not GTK's "no title" for the two widgets that consume
it: `gtk_stack_switcher`'s `update_button` and `gtk_stack_sidebar`'s row update both set the
button/row visible on `title != NULL`, not on emptiness.

Scenario: a page rendered with `~attrs:[ Attr.page_title "Setlists" ]` and later re-rendered
without the attr. `insert` for a titleless page uses `add_named` (NULL title, hidden button);
`updated` for a page that *loses* its title writes `""` (visible, empty button). So the same
model state reaches two different UIs depending on how it got there — a page that never had a
title has no button, a page whose title was cleared has an empty one you can still click.
The fix is a nullable `set_title` in the ocgtk fork (alongside the `Widget.set_name` item
already on the M2 list), or `g_object_set (page, "title", NULL, NULL)`.

Related doc gap, same mechanism: `Node.stack_switcher`'s doc (`vtree/node.mli:539-550`) says
the switcher shows "each page's `Attr.page_title`" but not that a page *without* one gets no
button at all. A stack whose pages carry no `page_title` renders a switcher that is present,
sized, and completely empty, with no diagnostic. Worth one sentence.

### M2. One failing fixup silently drops the rest of the pass's fixups

`src/patcher.ml:51-55`. `run_fixups` iterates the queue under `Exn.protect`, so the first
fixup that raises aborts the iteration and the `finally` clears everything behind it.

Scenario: a tree with two stacks, `"nav"` and `"detail"`, and a `stack_switcher ~stack:"nav"`.
A frame removes the `"nav"` stack (a legitimate conditional render) but leaves the switcher.
The switcher's fixup raises from `resolve_stack` (`src/patcher.ml:31-41`) — correct and
documented — but `"detail"`'s enqueued `W_stack.select` never runs, so the reported failure
comes with a tree whose *other* stack silently did not get its selection applied. Bounded in
practice because `Driver.frame` marks itself broken on the raise, so there is no next frame;
it matters for the error the developer reads and for tests that drive the patcher by hand and
catch the exception.

### M3. `ctx.stacks` keeps registrations from a subtree whose mount raised

`src/patcher.ml:25-29` + `184-204`. `register_stack` happens in `note_interest` at the end of
`mount`, and a `mount` that raises later in the walk never runs `destroy`, so the name stays
bound to an orphaned widget.

Scenario (this is what the existing test at `test/live/live_containers.ml:571-586` actually
leaves behind): mounting a box of two stacks both named `"nav"` raises on the second, but the
first is still in `ctx.stacks`. A caller that catches the `Invalid_argument` and re-renders now
gets a spurious "two Node.stacks are named" for the *corrected* tree, or wires a switcher to a
widget that is no longer in any tree. The backlog's "mount is not exception-safe (bounded)"
item is phrased as "leaves its already-created widget undestroyed", which does not cover the
registry; worth extending that item rather than filing a new one.

### M4. Two grid children in one cell have no diagnostic

`src/widgets/w_grid.ml:12-22`. A missing `Attr.grid_cell` raises with a path, but two children
claiming `~column:0 ~row:0` — or overlapping spans — are attached silently and painted on top
of each other. That is the same class of "looks like a layout bug rather than the mistake it
is" the missing-cell check exists to prevent, and the information to detect it is right there
in the ops (the impl would need a per-patch occupancy set, which is why I rate it Minor rather
than proposing it outright).

### M5. An overlay child whose *kind* changes jumps to the top of the z-order

`src/patcher.ml:462-469` + `src/widgets/w_overlay.ml:34-47`. The kind-change arm is
`ops.remove` then `ops.insert`, and `add_overlay` always appends, so an overlay at list
position 0 that changes kind ends up painted above every other overlay. This is adjacent to
the known "`Overlay` `move` is a no-op" item but distinct: that one is about a *reorder in the
node list*, this one fires with the list order unchanged. Same one-line mitigation is
unavailable (GTK has no overlay reorder), so it belongs in the same backlog entry as an extra
sentence rather than as separate work.

### M6. `w_frame.create` and `w_center_box.update` write outside `Widget_impl.batch`

`src/widgets/w_frame.ml:13-14`, `src/widgets/w_center_box.ml:22-23`. Both write at most one
property, so this is consistency rather than cost — noted only because every other impl in
the area brackets its writes and a reader will wonder why these two do not.

## Out-of-scope observations

- **Verified fixed, as the brief asked.** `set_bounds` (`src/widgets/w_scrolled_window.ml:25-35`)
  is correct. Traced: `80..300 -> 400..600` (max first, both land), `400..600 -> 80..300`
  (min first, both land), `-1..-1 -> 400..600`, `100..-1 -> 5000..6000`, `100..200 -> -1..50`,
  `100..200 -> 250..-1`. The only pair that loses a write is `min > max` input, which is the
  already-filed "not rejected at the constructor" item. `create` (`:47-57`) writes min before
  max, which is safe only because a fresh `GtkScrolledWindow` has both unset — the comment says
  so, and it is right.
- **`clip_overlay`** is deliberately unexposed and documented as such (`vtree/attr.mli:153`,
  `vtree/node.mli:632`). Not a gap.
- **Window close-request** is absent from the spec, the M1 plan, and `Attr.t` — it is not an M1
  omission. Worth noting for M3 (`Node.windows`): with no `close-request` handler a model
  cannot veto or observe a window close, which is exactly the frame in which multi-window
  state has to be reconciled.
- **`Node.t`'s children shape vs the impl's.** `mount_children`'s first arm
  (`src/patcher.ml:264`) is `| No_children, _ -> Children.No_children`, so a node declaring
  `No_children` against an impl that expects `Single`/`List` is silently accepted rather than
  raising like every other mismatch. Unreachable through the `Node` constructors (each fixes its
  own shape), so this is only a note in case `Node.t` ever becomes directly constructible.
- **`w_paned`'s uncontrolled `position`** is implemented exactly as ruled: written only when the
  model's value moves, never re-asserted, `notify::position` informative only. A paned with no
  `on_position_changed` is not broken. Confirmed against `vtree/kind.ml:214-226` and the test at
  `test/live/live_containers.ml:368-378`.
- **`Attr.measure_overlay` is better covered than the backlog implies.**
  `test/live/live_containers.ml:325-365` flips it `false -> true -> false` and reads it back as
  a live property through `Live_tree`'s `unmeasured` list, so the `updated` hook is exercised in
  both directions. It does not belong on the "untested update branches" list.
- **Coverage genuinely absent in this area:** no test moves a grid child's cell while a
  descendant holds focus (I2); no test drops an `Attr.page_title` (M1); no test mounts a keyed
  list with duplicate keys (I1); no test removes a stack while a switcher still names it (the
  `stray` test at `:543` covers the never-existed case, which takes the same code path but not
  the same lifecycle).

## Verdict

**Approved with fixes.** Nothing here blocks the branch: no finding corrupts the widget tree,
loses a child, or misplaces one. I1 and I2 should be fixed or filed before M2 — I1 because it
is a two-line §11 fix and stack page names are exactly where a user meets it, I2 because the
comment currently tells a future reader the opposite of what the code does. M1 and M3–M6 are
backlog material.
