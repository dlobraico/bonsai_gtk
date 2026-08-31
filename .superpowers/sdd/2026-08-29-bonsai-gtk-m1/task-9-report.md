# Task 9 report — Placement-by-attr: Grid, Stack, StackSwitcher, StackSidebar

**Status:** complete. Branch `m1`, commit `28b1d6b` ("Grid, Stack, StackSwitcher, StackSidebar"), 26 files, +1267/-41. `scripts/ci.sh` green end to end (nix ocgtk pin, format, build, opam files, headless, live under xvfb, example smoke). No push.

## What landed

### vtree
- `vtree/grid_cell.ml` — `{ column; row; width; height }`, `sexp_of/equal/compare`.
- `vtree/stack_transition.ml` — 18 constructors. GTK's `OVER_UP_DOWN`, `OVER_DOWN_UP`, `OVER_LEFT_RIGHT`, `OVER_RIGHT_LEFT`, `ROTATE_LEFT_RIGHT` are deliberately absent, documented in the module doc: each picks its direction from the child order, and a stack's child order is explicitly not meaningful.
- `vtree/attr.ml(i)` — `Grid_cell of Grid_cell.t`, `Page_title of string`, `On_visible_child_changed of string Handler.t`; the first two classified `is_event = false`, the third `true`. `Attr.grid_cell ~column ~row ?width ?height ()`, `Attr.page_title`, `Attr.on_visible_child_changed`.
- `vtree/kind.ml(i)` — `grid_props`, `stack_props`, `stack_ref_props` (shared by switcher and sidebar); four `Kind.t` arms with `name`/`same_kind`/`equal_props`. GTK defaults with `[@sexp_drop_if]`: spacings 0, homogeneous flags false, `transition = None_`, `transition_duration = 200`, `h/vhomogeneous = true`. `stack_props.name` and `visible_child` carry no drop-if — both are required labelled arguments.
- `vtree/node.ml(i)` — `grid`, `stack`, `stack_switcher`, `stack_sidebar`, each with the doc comment the brief specified (grid's required cell and dropped `Move`; the stack's three rules about keys, unreconciled order, and `~name`).
- `vtree/bonsai_gtk_vtree.ml` and `src/bonsai_gtk.ml(i)` re-export `Stack_transition` and `Grid_cell`.

### Widget impls
- `src/widgets/w_grid.ml` — props in a `batch`; `insert` attaches at the cell; `move` is a documented no-op (M1 ruling 4); `updated` compares `Grid_cell.equal` and does `remove` + `attach` on any of column/row/width/height changing, keeping the same GObject. `cell` raises `Invalid_argument` with no path (the patcher supplies it).
- `src/widgets/w_stack.ml` — transition mapping, `page_name` (the child's `Key.t`, `Invalid_argument` when absent), `page_title`, the `notify::visible-child-name` signal spec via `Signals.notify`, `add_titled`/`add_named` on insert, `W.Stack.remove` on remove, `GtkStackPage.set_title` on `updated`, and `select` — the controlled write, compared against the widget's live value.
- `src/widgets/w_stack_switcher.ml` / `w_stack_sidebar.ml` — `attach` helpers called from the fixup pass so the patcher stays widget-agnostic (the sidebar's `set_stack` is non-nullable, unlike the switcher's).

### Patcher
- `ctx` is now `private` with `stacks : (string, Widget.t) Hashtbl.t` and `fixups : (unit -> unit) Queue.t`; built by `create_ctx ~signals ~on_window_created`. `register_stack`, `resolve_stack`, `run_fixups`.
- A single `interest` variant (`Nothing | Window | Stack of Kind.stack_props | Stack_ref of [`Switcher|`Sidebar] * string`) computed by an *exhaustive* `interest_of_kind`, and one `note_interest ~pass:[`Mount | `Patch of Kind.t]` shared by mount and patch. This replaces the brief's two near-identical inline matches and makes the compiler ask about every future kind that needs a registration or a fixup.
- `destroy` drops the stack's registration alongside the existing `Window`/`Native` arms.
- `Driver.frame` drains the queue inside the patch guard, immediately after mount/patch; `Driver.create` uses `create_ctx`.
- New `child_op ~path` wrapper in `mount_list`/`patch_list` prefixes the child's path onto any `Invalid_argument` a container's child op raises. It wraps only the op call, never the recursive `mount`/`patch` beside it, so a nested container's message is prefixed exactly once. This improves every container's errors, not just the grid's.

### Live_tree
`GtkGrid` (spacings, homogeneous flags, and a `cells` list in `widget_children` order), `GtkStack` (`visible`), and — beyond the brief — `GtkStackSwitcher`/`GtkStackSidebar` `has-stack` flags, so a switcher wired to nothing is distinguishable from one whose stack is merely empty.

## Deviations and judgement calls

1. **Where the stack's controlled `visible_child` is written.** The task context cited "use `Widget_impl.reassert`, not a flag". `reassert` runs *before* `patch_children`, so on the frame that both adds a page and selects it there is nothing to select — the exact ordering problem the brief's Step 9 identifies. The selection is therefore applied by the fixup (`W_stack.select`), enqueued unconditionally on every mount and patch, and `Stack`'s `reassert` is `None` with a comment saying why. The *discipline* of ruling 2 is preserved intact: `select` compares against `W.Stack.get_visible_child_name`, not against the previous node, so a page the model declined is put back. The live test proves it ("declined visible child: setlists; reached Bonsai: 0").
2. **`run_fixups` clears under `Exn.protect`** rather than after a bare `Queue.iter`. A failed pass's queue would otherwise raise again from an unrelated later frame. Documented in the mli.
3. **A renamed stack drops its old registration** on patch (the brief only `Hashtbl.set`s the new name), so a switcher still naming the old one fails loudly instead of driving a stack the tree no longer calls that.
4. **`Window`'s `on_window_created` stays mount-only.** Folding it into the shared `note_interest` made this explicit rather than accidental; a `Patch` pass does not re-present the window.
5. **`ctx` is `private`** in the mli, since `create_ctx` is now the constructor. This is what forced (and caught) the three live-test migrations.
6. **`live_signals.ml` was not changed**: its `ctx` is a `Signals.ctx`, not a `Patcher.ctx`, and remains a record literal. The three files that built `P.ctx` — `live_controls.ml`, `live_containers.ml`, `live_patcher.ml` — now call `P.create_ctx`.
7. **Two tests beyond the brief's list**, both cheap and both covering documented §11 behaviour: a grid reorder that keeps the cells (proving `move` is dropped — nothing in GTK shifts), and two `Node.stack`s sharing a name (`rejected: dup/0/1: two Node.stacks are named "nav" in one tree`).

## Tests

Headless (`test/test_widgets.ml`): one new expect test, promoted — grid children carrying `Grid_cell` in their attrs with defaults dropped from the kind sexp, and a switcher/stack pair with page keys and titles.

Live (`test/live/live_containers.ml`, appended, expected file promoted):
- Grid: mount, cell move (0,2)→(0,1,w2), `same widget after re-attach: true`, `cells` going `((0 0 1 1) (1 0 1 1) (0 2 1 1))` → `(... (0 1 2 1))`; a reorder with unchanged cells leaving GTK untouched; `rejected: root/0/0: Grid child has no Attr.grid_cell (every child of a Node.grid needs one)`.
- Stack: switcher and sidebar declared *above* the stack, both resolving (`has-stack`) after `run_fixups`; the selection following `~visible_child` on the very first frame (which is what the fixup exists for); a page added (switcher gains a button, sidebar a row) with a title edited in place (`Library` → `Library!`); a page removed; the controlled decline under the patch guard, with zero signals reaching Bonsai; the same `notify::visible-child-name` reaching Bonsai outside a patch; `rejected: stray/0: no Node.stack is named "nope" (...)`; `rejected: dup/0/1: two Node.stacks are named "nav" in one tree`.

## Concerns / follow-ups

- **Same-frame stack name reuse.** If one frame removes a stack named `"nav"` and adds a different one with the same name, and the reconciler happens to emit the `Insert` before the `Remove`, `register_stack`'s `Hashtbl.add` raises rather than silently swapping. That is loud, not corrupting, but it is a rename pattern an app could hit; if it ever matters the fix is to defer registration to the fixup pass as well.
- **Stack page order** is unreconciled by design (M1 ruling 4). A model that must reorder switcher buttons has to change the keys, exactly as for `Overlay`. Worth revisiting when `Notebook` (M2) shares the list machinery, which is where ruling 4 already points.
- `Attr.grid_cell` and `Attr.page_title` are inert outside their container, silently — consistent with `measure_overlay`, and documented on each, but there is no diagnostic for a typo'd placement.

---

# Fix round 1

**Commit:** `545c67d` on `m1` — "driver: patch every frame so declined edits reassert; stack rename collisions raise" (9 files, +195/-50). `dune build @check` clean, headless green, live suite green, `scripts/ci.sh` green. No push.

## 1. Stack rename clobbers (Important)

`note_interest`'s `Patch` branch now splits three ways instead of unconditionally `Hashtbl.set`ting:

- name unchanged → `Hashtbl.set` (the entry already points here; `set` rather than nothing so a registration lost to an earlier teardown heals itself);
- name changed → `Hashtbl.remove` the old name, then `register_stack` — which is `Hashtbl.add`, so renaming *onto* a name another stack holds raises the identical `Invalid_argument` as declaring the collision at mount;
- old kind not a `Stack` → `register_stack`. Unreachable (`patch` only reaches here when the kinds match) but registering rather than assuming keeps it harmless if that changes.

`destroy` now removes the entry only while it still maps to the widget being torn down (`Gobject.same`), so a stack that renamed itself onto this name during the same pass is not unregistered by the teardown of the one it displaced.

Live case added: two stacks named `first`/`second`, patched so the second takes `first`. Output: `rejected: ren/0/1: two Node.stacks are named "first" in one tree` — byte-for-byte the mount-time message.

## 2. Driver skips the patch for a physically identical root (promoted observation)

The `phys_equal`-against-`t.last` short-circuit is gone from `Driver.frame`, and the `last` field with it. The reasoning is recorded in a comment at the call site: a model that declines an edit renders the same value, so the node is physically the same, so the patch a phys-equal guard throws away is exactly the patch that would put the widget back — and both halves of the cure (`Widget_impl.reassert` and the stack-selection fixup) live inside it. The comment also states the cost honestly: an unchanged frame still walks the shadow tree, but `Kind.equal_props` skips every impl `update` and `Attrs.diff` writes nothing, so no GTK call is made.

New driver-level live test (`declining_app` in `test/live/live_driver.ml`): a `Bonsai.state` whose setter is never called, so every frame after the first renders the identical node. It holds a toggle button pinned `~active:false` and a stack pinned `~visible_child:"a"`, each carrying a handler that only bumps a ref through `Effect.of_sync_fun`. The test flips the toggle and moves the stack page as a user would, drains the GLib loop, and reads back:

```
declined toggle: active false, Bonsai saw 1
declined page: visible a, Bonsai saw 1
```

Both halves are load-bearing: `active false` / `visible a` is the reassert-and-fixup that only runs because the frame no longer short-circuits (under the old code these read `true` and `b`), and `Bonsai saw 1` proves the handler was armed rather than the event never having happened. The stack half also covers the fixup path specifically, which `reassert` does not reach. Every pre-existing expectation in `expected_driver.txt` is unchanged, so dropping the short-circuit caused no regressions.

## Minors folded in

- `widget_impl.mli` `reassert`: `None` now documented as also covering the kind whose controlled prop is applied by `Patcher.run_fixups` — a `Stack`'s visible child names a page, and `reassert` runs before the children are patched, so on the frame that both adds a page and selects it there would be nothing to select.
- `patcher.mli` `run_fixups`: notes that a raise abandons the rest of the queue — fixups behind the failing one do not run and are dropped with it — matching the all-or-nothing a raising frame already has.
- `live_tree.ml` `GtkGrid` arm: notes that the printed order is GTK's, not the node list's, because `gtk_grid_attach` appends — so a re-attached child moves to the end of both the `cells` list and the children below it, however early it sits in the node list.
- Live case for a stack page without `~key`: `rejected: keyless/0/0: Stack child has no ~key (a stack page's key is its GTK page name)`.

## `scripts/ci.sh` tail, verbatim

```
== nix: ocgtk pin builds and passes its tests
warning: Git tree '/home/dlobraico/src/bonsai_gtk' is dirty
== format
== build
== generated opam files are committed
== pure + headless tests
== live tests (xvfb)
bonsai_gtk: exception in frame, stopping the driver: (Invalid_argument
  "root/0/1: a Node.window may only be the root node, not a child of another node")
== example smoke
all green
```

(The `Invalid_argument` line is `live_driver.ml`'s pre-existing broken-driver test writing to stderr, not a failure. The "dirty" warning is nix seeing the uncommitted tree during the run.)

## New concern raised by fix 2

**The spec now contradicts the code.** `docs/superpowers/specs/2026-08-28-bonsai-gtk-design.md` §4.2 step 4 says "If the new root is not `phys_equal` to the last rendered root: `Patcher.patch`", and §4.3 says "When nothing changed, flush is a no-op and the patch is skipped by the `phys_equal` check, so an idle tick costs one stabilization." Both are now false. I did not edit the spec — it is outside this task's file list and Task 11 owns the doc sweep — but it should not ship saying the opposite of `driver.ml`. Suggested replacement for the §4.3 sentence: an idle tick costs one stabilization plus one shadow-tree walk, which makes no GTK calls.

Related, and worth a Task 11 backlog line rather than a change here: at 60 fps the tick now runs `Attrs.diff` per node per frame, which allocates on an otherwise idle app. The spec's own "suspending the tick while idle is a noted future optimization" is the right place for it, and it matters more now than it did.
