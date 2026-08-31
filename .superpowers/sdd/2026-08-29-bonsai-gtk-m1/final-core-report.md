# Final review — M1 core runtime (`m1` @ `886b1d5`, base `9f80cd4`)

Scope: `vtree/` (Node/Attr/Attrs/Kind/Children/Reconcile/Defaults), `src/patcher.ml(i)`,
`src/driver.ml(i)`, `src/signals.ml(i)`, `src/scheduler.ml(i)`, `src/widget_impl.ml(i)`,
`src/attr_apply.ml(i)`, `src/widgets/registry.ml`, `src/live_tree.ml`,
`src/native_gtk.ml(i)`, `src/bonsai_gtk.ml(i)`. Read-only; no build was run.

Everything in `docs/m1-backlog.md` was read first and is not re-reported, except where a
backlog item's *severity or reachability* is materially understated — that is called out
explicitly as a re-rating rather than as a new finding.

## Summary

The core is in good shape. I checked `Reconcile.diff` by hand against the cases that
usually break a keyed differ — pure reorder, remove-plus-move, mixed keyed/unkeyed,
unkeyed-with-a-kind-change, more-new-than-old — and the op stream and the patcher's `cur`
bookkeeping agree with `Reconcile.apply` in every one; the `after_of` index invariants
hold (`after_of` is never called with an index past the list it reads). The teardown
ordering is right: `disarm` really does close the window §6.2 describes, `destroy` clears
slots and disconnects before any GTK call that could emit, and ocgtk's wrapper holds a
strong `g_object_ref` (`wrappers.c:107`, `finalize_gobject`), so the unparent-then-
disconnect order in `patch_list`/`patch_single` is not a use-after-free. The stack name
registry's `Gobject.same` guard in `destroy` (`patcher.ml:287`) is correct, and I could
not construct a silent-clobber path through the rename arm — every swap or reuse raises
rather than corrupting. `reassert` is wired the way spec §6.5's amendment says, and
patching every frame really is what makes a declined edit snap back.

Four things are worth fixing. Two are one-line-ish gaps in promises the code already
makes (`Driver.broken` is not set on the path `Driver.mli` says it covers; duplicate
sibling keys are not checked at mount and their message carries no node path). One is a
re-rating: the backlogged `register_stack` collision fires on an ordinary structural
refactor, not just the exotic case the backlog describes. The fourth is an M2 landmine in
the `Signals.spec` contract.

No Critical findings.

## Critical

None.

## Important

### 1. A hand-driven `Driver.frame` that raises does not set `broken`, so the next frame diffs against a half-patched shadow tree

`src/driver.ml:33-91`, `src/scheduler.ml:55-64`, `src/driver.mli:40-42`, `src/loop.ml:44`

`Scheduler.broken` is set in exactly one place — `guarded_frame` (`scheduler.ml:58-63`) —
which only runs when the scheduler drives the frame. `Driver.frame` called directly sets
nothing. But `driver.mli:40-42` says:

> Once a frame has raised (`broken` is `true`) this is a no-op: the promise that nothing
> updates the tree again holds for hand-driven frames as well as for the scheduler's.

That is false for the case it names. The promise holds for a hand-driven frame *after*
the scheduler broke the driver (which is what `test/live/live_driver.ml:174` tests), but
not for a hand-driven frame that raises. And `driver.mli:5-9` plus spec §4.1 advertise
hand-driven frames as the supported embedder/test path.

Failure scenario: an embedder owns its own main loop and calls `Driver.frame` per
iteration. Frame 5's computation returns a `Node.box` whose second child gained a
conditional `Attr.on_toggled`. `Patcher.patch` walks the box's list, patches child 0
(GTK mutated, `live.node <- node` written for it), then raises `Invalid_argument` from
`Signals.require_specs` on child 1 (`patcher.ml:350-356`). The exception escapes
`with_patch_guard`, so `live.children` for the box is never assigned and `live.node` for
the box is still frame 4's. The embedder logs it and calls `frame` again. `t.stopped` is
false, `Scheduler.broken` is false, so frame 6 proceeds and diffs frame 6's nodes against
a shadow tree that is part frame 4 and part frame 5 — exactly the state `broken` exists
to prevent.

There is a second half to this. `ctx.fixups` is only emptied by `run_fixups`'
`Exn.protect ~finally` (`patcher.ml:51-55`). If the raise happens inside `mount`/`patch`,
`run_fixups` is never entered, so the queue keeps that pass's entries and the *next*
hand-driven frame drains them along with its own. `patcher.ml:43-50`'s comment
("carrying a failed pass's work into the next one would raise again from a frame that had
nothing to do with it") describes precisely the bug that is left open on this path — a
stale `resolve_stack` closure raising "no `Node.stack` is named X" from an unrelated
frame.

`src/loop.ml:44` uses this path for the library's own first frame: if that frame raises
after the window was presented (a `stack_switcher` naming a stack that does not exist
raises in `run_fixups`, *after* `t.root` was assigned), `start_tick` is skipped and
`failure` is recorded, but `broken` stays false — so the window comes up looking alive and
the driver dies on the first user interaction instead of at startup.

Fix: have `Driver.frame` mark the scheduler broken (and clear `ctx.fixups`) when the
frame body raises, then re-raise — i.e. move the state transition out of `guarded_frame`
and leave `guarded_frame` responsible only for logging and not re-raising into C.

### 2. Duplicate sibling keys are not detected at mount, and the message carries no node path

`vtree/reconcile.ml:20-29`, `src/patcher.ml:216-228` (`mount_list`), `src/patcher.ml:409-414`

Spec §11 lists "duplicate sibling keys" among the structural misuses that raise
`Invalid_argument` **"with the node path at mount/patch time"**. Neither half holds.

*Not at mount.* `check_unique_keys` is called only from `Reconcile.diff`
(`reconcile.ml:55-56`), and `Reconcile.diff` is only reached from `patch_list`.
`mount_list` (`patcher.ml:216-228`) maps `mount` over the children and inserts them with
no key check at all. So a first frame with `Node.box [ label ~key:"a" …; label ~key:"a" … ]`
mounts cleanly; the duplicate is caught on the *second* frame.

Under `Bonsai_gtk.start` that means: window comes up, first tick (~16 ms later) raises,
`guarded_frame` logs and breaks the driver, exit status 2 — a frozen window rather than a
startup error. Under `Bonsai_gtk_test` (which renders through `Bonsai_test.Handle` and
never touches the patcher) it is not caught at all. For a `Node.stack` it is worse than a
late error: `W_stack.insert` calls `add_named` with the duplicate page name
(`w_stack.ml:118-130`), so the first frame silently builds a stack whose
`get_child_by_name` is ambiguous, and *then* frame 2 raises.

*No node path.* The message is
`Reconcile.diff: duplicate key a` (`reconcile.ml:26`), and the call at `patcher.ml:409` is
deliberately outside `child_op`'s path-prefixing wrapper (`patcher.ml:74-77`). Every other
structural message in the M1 amendment to §11 is path-prefixed; this one names neither the
container nor the tree position, so in an app with a dozen list containers it says nothing
about where to look. Contrast `w_grid.ml:11-16` and `w_stack.ml:29-34`, which raise
path-less on purpose *because* `child_op` prefixes them.

Fix: call `check_unique_keys` from `mount_list` too, and route both call sites through
`child_op` (or pass `~path` into `Reconcile.diff`).

### 3. Re-rating: the backlogged `register_stack` collision fires on an ordinary refactor, not only on remove-plus-insert

`src/patcher.ml:25-29`, `src/patcher.ml:139-156`, `src/patcher.ml:329-337`

The backlog records this as *"Same-frame stack name reuse or swap raises … a frame that
removes the stack named `"nav"` and inserts a **different** one with that name hits
`Hashtbl.add`. Loud, not corrupting."* That framing makes it sound like an exotic case. It
is not: the kind-change path reaches it with a single unchanged stack.

`patch` mounts the replacement subtree *before* destroying the old one
(`patcher.ml:333-336`, deliberately, so the old subtree stays parented until the
replacement exists). `mount` registers stack names as it walks (`patcher.ml:141` →
`register_stack` → `Hashtbl.add`). The old subtree's registration is not dropped until
`destroy ctx live` runs, which is after `mount` returns.

Scenario: the app renders

```ocaml
Node.box ~orientation:Vertical [ Node.stack ~name:"nav" ~visible_child:page pages ]
```

and the next frame wraps that same stack in a frame — `Node.frame ~label:"Nav" (Node.stack ~name:"nav" …)`.
The node at that position changes kind Box → Frame, so `patch` mounts the Frame subtree,
which registers `"nav"` while the Box's stack still holds it → `Hashtbl.add` returns
`` `Duplicate`` → `"root/0: two Node.stacks are named "nav" in one tree"`. There is exactly
one stack named `"nav"` in the app; the message is actively misleading, and under
`start` it permanently breaks the driver.

The same window opens for any container swap around a named stack (Box → ScrolledWindow,
Frame → Expander, …), which is ordinary UI work rather than a same-frame name swap.

The backlog's proposed fix (defer registration to the fixup pass, as the visible-child
write already is) also fixes this, so no new work is implied — but this should be
"do first in M2" rather than a curiosity, and the backlog entry should carry this
scenario.

### 4. `Signals.spec.connect` may connect to any GObject, but `Signals.disconnect` always disconnects from the widget — M2's `TextView`/`ListBox` are exactly the cases that break it

`src/signals.mli:20-32`, `src/signals.ml:31-48`, `src/signals.ml:86-88`,
`src/patcher.ml:277`

`spec.connect : Widget.t -> callback:(unit -> unit) -> Gobject.Signal.handler_id` gets the
widget and returns a handler id, and `connect_all` collects those ids into
`live.handler_ids`. Teardown does `Signals.disconnect live.widget live.handler_ids`
(`patcher.ml:277`, `signals.ml:86-88`) — every id is disconnected **from the widget**.

Nothing in the type or the doc says `connect` must connect to `w` itself. Every M1 spec
happens to (I checked all ten: `Signals.notify` connects to `w`; `w_entry.ml:30`'s
`W.Editable.from_gobject w` is a checked cast to the same instance, not
`gtk_editable_get_delegate`; `w_scale.ml:16`'s `W.Range` and `w_spin_button.ml:9`'s
`W.Spin_button` are the widget). So this is latent, not broken today.

It stops being latent in M2. `GtkTextView`'s interesting signals (`changed`,
`notify::cursor-position`) live on the `GtkTextBuffer`, not the view. `GtkDropDown`'s
`notify::selected-item` is on the widget but its model's `items-changed` is not. Key and
pointer events come from `GtkEventControllerKey`/`GtkGestureClick` objects attached to the
widget (spec §6.4 names all three). A spec that connects to any of those returns a handler
id belonging to a different GObject, and `g_signal_handler_disconnect(widget, id)` at
teardown is at best a GLib critical and at worst disconnects an unrelated handler that
happens to share the id — while the real handler stays connected, keeping the slot and its
closure alive as a GC root (the leak spec §6.1 calls out).

Fix before M2 starts adding widgets: make `spec` carry the object it connected to
(`connect : Widget.t -> callback:… -> (Gobject.obj * handler_id)`, or a
`disconnect : Widget.t -> handler_id -> unit` member alongside `connect`), and say in
`signals.mli` that `connect` must return an id valid on the object `disconnect` will be
given.

## Minor

1. **`Scheduler.with_patch_guard` hard-codes `false` rather than restoring the previous
   value** (`src/scheduler.ml:41-44`). The `.mli:42-43` says "restoring it even if `f`
   raises", which reads as save/restore. Nesting is not reachable in M1 — `Driver.frame`
   is the only caller and nothing in the patch path spins the main loop
   (`gtk_window_present` and `gtk_application_add_window` do not) — but a nested
   `with_patch_guard` would clear the guard on the *inner* exit and leave the rest of the
   outer patch dispatching signals into Bonsai mid-patch, silently. M2's dialogs and
   anything that iterates the loop are what would make it reachable. One-line fix; worth
   taking now.

2. **A `Node.stack ~visible_child` naming a page that never exists is silently inert
   forever** (`src/widgets/w_stack.ml:50-59`). `select` requires
   `Option.is_some (get_child_by_name …)` before writing, and the comment chooses silence
   deliberately ("the frame that adds the page runs this again"). That is the right call
   for a page that arrives later, but it also means a typo'd `~visible_child` shows page 0
   forever with no diagnostic — while the neighbouring mistakes (a switcher naming a
   missing stack, a stack page with no key, a grid child with no cell) are all loud. Every
   page's key is available at patch time, so a "named a page this stack has never had"
   warning is cheap. Same family as the backlog's "`Attr.grid_cell`/`Attr.page_title` are
   silently inert outside their container"; consider folding it into that entry.

3. **`Driver.schedule_event` guards `broken` but not `stopped`** (`src/driver.ml:14-21`).
   After `Driver.stop`, `Bonsai_driver.Expert.invalidate_observers` has run
   (`driver.ml:159`), but `schedule_event` still calls `Bonsai_driver.schedule_event` into
   that graph; only `request_frame` is a no-op. Not reachable through the patcher's own
   handlers (all disconnected by `stop`), but reachable for an embedder holding the driver
   value, and for a `Native` widget whose `create`-installed handler outlives `destroy`.
   `frame` guards both; `schedule_event` should too.

4. **`Driver.stop` leaves `ctx.fixups` populated** (`src/driver.ml:149-159`). If the last
   frame raised inside `mount`/`patch`, the queue still holds closures over widgets from
   that pass, and `stop` never drains or clears it, so the ctx pins them for as long as the
   driver value lives. `ctx.stacks` self-empties through `destroy`'s `Gobject.same` arm, so
   that half is fine.

5. **Spec §6.2 step 1 still says destroy-then-mount** (`docs/…-design.md`, §6.2:
   "Different `kind` … → `destroy live`, then `mount new_node`"). The implementation does
   the opposite on purpose (`patcher.ml:333-336`: mount first so the old subtree stays
   alive and parented until the replacement exists), which is better, and §6.2 got no M1
   amendment for it. Same paragraph's step 2 lists attrs before props; the implementation
   is props → `reassert` → attrs → slots → children (`patcher.ml:357-366`). Both are drift
   in the spec's favour of the older design; worth an amendment line so the next reader
   does not "fix" the code to match.

6. **`Native_gtk.S.destroy`'s contract does not mention that a replacement's `create` runs
   first** (`src/native_gtk.mli:27-34`). Because of the mount-before-destroy order above, a
   native node whose parent's kind changes has its replacement `create`d while the old
   instance's `destroy` has not yet run. A native impl that acquires an exclusive resource
   (a port, a file lock, a singleton subscription) will collide. One sentence in the
   `destroy` doc.

7. **`patch_children`'s catch-all message conflates two different bugs**
   (`src/patcher.ml:521-526`). The arm `(No_children | Single _ | List _ | Slots _), _, _`
   catches both "the node's children shape changed under an unchanged kind" (the message it
   prints) and "the impl's `child_ops` disagrees with both" — which would be a registry bug,
   not an app bug. The second is unreachable today (mount validates it), so this is
   cosmetic, but the message will mislead whoever hits it first in M2.

## Out-of-scope observations

- `Kind.equal_props` compares `Native` payloads with `phys_equal` (`kind.ml:395`), so a
  native node's `update` runs on every frame. That is documented in `native_gtk.mli:20-25`
  and is the right call given the payload is freshly allocated per render — noting it only
  because it means M2's native widgets pay a per-frame `update` no `equal_props` can skip.
- `Registry.for_kind (Native n)` allocates a fresh `Widget_impl.t` (and a fresh
  `input_of_kind` closure) per call (`native_gtk.ml:35-62`). Only `mount` consults the
  registry, so it is per-widget-creation, not per-frame. Negligible.
- `Patcher.interest` (`patcher.ml:82-119`) is a closed variant matched exhaustively at
  three sites, which is a good design for M1's one cross-reference (stack names). M2 adds
  cross-references of a different shape — a `GtkPopover` parents itself onto a widget
  rather than being a child, a `HeaderBar` is a window's titlebar rather than its child —
  and neither fits `Widget_impl.child_ops`. Worth deciding early whether `interest` grows
  a general "named widget" registry or whether those get their own mechanism; the
  exhaustive match will make the question unavoidable, which is the point of it.
- `Live_tree.dump` prints a `GtkStack`'s pages through `widget_children`, which in GTK4 is
  the page widgets themselves — correct, and worth keeping in mind when M2's `Notebook`
  (whose tab labels *are* widget children) lands, since its dump will not look like this.

## Verdict

**Approved with fixes recommended.** Nothing here blocks the branch: no Critical, no data
corruption, and the two behavioural gaps (#1, #2) are reachable only through a raising
frame or a duplicate key — both application bugs, both already loud under
`Bonsai_gtk.start`, just later and less legibly than spec §11 promises. #1 and #2 are
small and I would take them before M2 starts; #3 is a backlog re-rating (no new work, just
priority); #4 is a contract change that is much cheaper now than after six M2 widgets have
been written against the current `spec`.
