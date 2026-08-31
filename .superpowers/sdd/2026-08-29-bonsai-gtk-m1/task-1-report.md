# Task 1 report — backlog first: `~after` child ops, the broken-driver guard, the reentrancy test

Branch `m1`, commit `14f9312` on top of `ce22d83`. `scripts/ci.sh` green.

## What changed

### 1. Child placement by predecessor widget (`~after`), not GTK's live child list

- `src/widget_impl.ml:5-12` — `child_ops.List` is now
  `insert : Widget.t -> after:Widget.t option -> Widget.t -> unit`,
  `move : Widget.t -> child:Widget.t -> after:Widget.t option -> unit`.
- `src/widget_impl.ml` — `sibling_before` **deleted** (was `widget_impl.ml:22-37`), along
  with its `widget_impl.mli:39-46` doc comment. Nothing else referenced it (grepped
  `src test test_lib examples vtree`).
- `src/widget_impl.mli:6-22` — the new contract is documented on `insert`/`move`: `after`
  is the live widget *the patcher's own bookkeeping* says precedes this position, never a
  widget read back out of GTK; `move`'s `after` is computed over the sibling list with
  `child` already taken out, which is the order `reorder_child_after` expects.
- `src/widgets/w_box.ml:36-45` — both ops are now one-liners straight onto
  `W.Box.insert_child_after` / `W.Box.reorder_child_after`, whose ocgtk signatures already
  take a `Widget.t option` sibling (`.ocgtk-src/ocgtk/src/gtk/generated/box.mli:32,68`).
  No ocgtk name adaptation was needed; the brief's calls exist as written.
- `src/patcher.ml:52-59` (`mount`) — the `List` arm folds the previous live widget through
  instead of indexing, so mounting a list of *n* children costs *n* inserts and zero GTK
  child-list walks.
- `src/patcher.ml:150-195` (`patch_children`, `List` arm) — new local
  `after_of cur index` (`patcher.ml:155-157`) reads the predecessor off `cur`. Used by
  `Insert` (`:169`, over `!cur`), `Move` (`:176`, over `without` = `!cur` minus the moved
  child, because `to_` indexes the list as it will be after the move) and the kind-change
  half of `Update` (`:193`, over `!cur` minus the replaced child).

Behaviour is unchanged for `GtkBox`: `expected_patcher.txt` and `expected_driver.txt` both
diffed clean against the rewrite before any test was touched (see GREEN #1 below — the
only later `expected_driver.txt` change is the deliberate new assertion in §2).

### 2. The broken-driver guard

- `src/driver.ml:15-22` — `schedule_event` is a no-op once `Scheduler.broken`. A broken
  driver renders nothing again, so queueing into it only grows a queue nobody drains.
- `src/driver.ml:39-46` — `frame` returns rather than raising once `Scheduler.broken`.
  The `stopped` check still raises above it: being stopped is caller error, being broken
  is not (the scheduler's own guarded path reaches `frame` too). The rest of the body is
  the unchanged old body, re-indented into the `else` branch.
- `src/driver.mli:36-46` — `frame` gains "Once a frame has raised (`broken` is `true`)
  this is a no-op: the promise that nothing updates the tree again holds for hand-driven
  frames as well as for the scheduler's."; `schedule_event` gains "A no-op once the driver
  is broken."

### 3. Tests

- **New** `test/live/live_signals.ml` — the `in_patch` reentrancy-guard test: a real
  `GtkButton`, M0's real `W_button.clicked` spec, a real trampoline, and a `ctx` whose
  `in_patch` the test flips. Pins six counts across empty slot / armed slot / during patch
  / after patch / raising handler / cleared slot.
- **New** `test/live/expected_signals.txt`.
- `test/live/dune` — `live_signals` added to `(names ...)`, plus its own
  `runtest` rule behind the same `BONSAI_GTK_LIVE_TESTS` gate.
- `test/live/live_driver.ml:97-103` — **added** an assertion for §2 that nothing pinned
  before: after the breaking app has broken the driver, a *hand-driven*
  `Expert.Driver.frame broken` must return instead of re-raising, and the tree must still
  show its last good state. New expected line `expected_driver.txt:17`.
- `src/bonsai_gtk.ml:37`, `src/bonsai_gtk.mli:106` — `module W_button = W_button` added to
  the `Private` block so the live test can name M0's `clicked` spec.

`docs/m1-backlog.md` deliberately left untouched (Task 11 updates it).

## TDD evidence

All commands run from the repo root as
`nix develop -c bash -c 'eval "$(opam env --switch=. --set-switch)"; …'`.

### RED #1 — the reentrancy live test, before `Private.W_button` existed

```
$ BONSAI_GTK_LIVE_TESTS=1 xvfb-run -a dune build @test/live/runtest
File "test/live/live_signals.ml", line 24, characters 8-43:
24 |       [ Bonsai_gtk.Private.W_button.clicked ]
             ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
Error: Unbound module "Bonsai_gtk.Private.W_button"
bonsai_gtk: exception in frame, stopping the driver: (Invalid_argument
  "root/0/1: a Node.window may only be the root node, not a child of another node")
```

(The trailing `bonsai_gtk:` line is `live_driver`'s own expected stderr, not a failure.)

### GREEN #1 — after the `~after` rewrite, the driver guard and the `Private` export

```
$ BONSAI_GTK_LIVE_TESTS=1 xvfb-run -a dune build @test/live/runtest
File "test/live/expected_signals.txt", line 1, characters 0-0:
------ test/live/expected_signals.txt
++++++ test/live/output_signals.txt
File "test/live/expected_signals.txt", line 1, characters 0-1:
+|empty slot: 0
+|armed slot: 1
+|during patch: 1
+|after patch: 2
+|after raising handler: 3
+|after clear: 3
bonsai_gtk: exception in frame, stopping the driver: (Invalid_argument
  "root/0/1: a Node.window may only be the root node, not a child of another node")
```

The only diff is the new (empty) expectation file filling in, and the six numbers are
exactly the ones the brief predicted. The two that carry the claim:

- `during patch: 1` — unchanged from `armed slot: 1`, so the signal GTK emitted while
  `in_patch` was true never reached Bonsai; and `after patch: 2` proves the slot was still
  armed the whole time, i.e. the drop was the guard and not an empty slot.
- `after clear: 3` — unchanged from `after raising handler: 3`, so `clear_slots` really
  disarms a still-connected handler, which is what `Patcher.disarm` relies on.

Crucially, `expected_patcher.txt` and `expected_driver.txt` produced **no diff at all** in
this run: the `~after` rewrite is behaviour-preserving for `GtkBox`, as a refactor must
be. `dune promote` then wrote `expected_signals.txt`.

### RED #2 — the driver's `broken` guard (a separate assertion, added deliberately)

With the new `live_driver.ml` assertion in place and `src/driver.ml` reverted to HEAD
(`git checkout src/driver.ml`):

```
$ BONSAI_GTK_LIVE_TESTS=1 xvfb-run -a dune build @test/live/runtest
File "test/live/dune", lines 30-40, characters 0-243:
...
bonsai_gtk: exception in frame, stopping the driver: (Invalid_argument
  "root/0/1: a Node.window may only be the root node, not a child of another node")
Uncaught exception:

  (Invalid_argument
   "root/0/1: a Node.window may only be the root node, not a child of another node")

Raised at Stdlib.invalid_arg in file "stdlib.ml" (inlined), line 40, characters 20-45
Called from Base__Printf.invalid_argf.(fun) in file "src/printf.ml", line 11, characters 24-37
Called from Bonsai_gtk__Patcher.mount in file "src/patcher.ml", line 35, characters 2-37
Called from Bonsai_gtk__Patcher.patch_children.(fun) in file "src/patcher.ml", line 168, characters 16-75
...
Called from Bonsai_gtk__Driver.frame in file "src/driver.ml", lines 52-57, characters 4-270
Called from Dune__exe__Live_driver in file "test/live/live_driver.ml", line 100, characters 2-28
```

That is exactly the backlog's complaint: `frame` guarded `stopped` but not `broken`, so a
hand-driven frame on a broken driver re-entered the patcher against a stale shadow tree
and re-raised.

### GREEN #2 — with `src/driver.ml` restored

```
$ BONSAI_GTK_LIVE_TESTS=1 xvfb-run -a dune build @test/live/runtest
bonsai_gtk: exception in frame, stopping the driver: (Invalid_argument
  "root/0/1: a Node.window may only be the root node, not a child of another node")
File "test/live/expected_driver.txt", line 1, characters 0-0:
------ test/live/expected_driver.txt
++++++ test/live/output_driver.txt
File "test/live/expected_driver.txt", line 17, characters 0-1:
 |stopped
 |broken before: false
 |broken after: true
+|frame on broken driver returned, still broken: true
 |(GtkWindow (title (break)) (css (background)) hidden
 | (children
 |  (GtkBox (spacing 0) (css (vertical))
 |   (children
 |    (GtkButton (label (+)) (css (text-button))
 |     (children (GtkLabel (text +))))))))
 |broken driver stopped
```

The frame returned, the driver stayed broken, and the dump *after* the no-op frame is
byte-identical to the one before it — the window still shows its last good state.
`dune promote` accepted the single new line.

### Flakiness check

Not required (nothing flaked), but run anyway since these are xvfb tests:

```
$ for i in 1 2 3; do BONSAI_GTK_LIVE_TESTS=1 xvfb-run -a dune build @test/live/runtest --force ... ; done
run 1: pass
run 2: pass
run 3: pass
```

## `scripts/ci.sh` (verbatim)

```
$ nix develop -c bash -c './scripts/ci.sh'
warning: Git tree '/home/dlobraico/src/bonsai_gtk' is dirty
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

(The `dirty` warnings and the `exception in frame` line are pre-existing: the former is
Nix reading an uncommitted tree, the latter is `live_driver`'s breaking-app fixture
logging on the path it is built to exercise. The run above was made before the commit.)

## Self-review against "Do first in M1"

- **Child ops `~index` + `sibling_before` → `~after:(Widget.t option)` fed from `cur`** —
  done, `sibling_before` deleted outright so there is no second placement path left to
  drift. The placement now costs no GTK round-trip per insert, and it is correct for a
  container that interposes children of its own, which is the reason M1 needed it first.
- **`Driver.frame` guards `broken`; `schedule_event` no-op once broken** — done, and the
  `frame` half is now pinned by a live assertion that fails loudly without the fix
  (RED #2). `driver.mli` says both.
- **Reentrancy-guard (`in_patch`) test** — done at the level M0's widget set can express:
  real button, real spec, real trampoline, test-controlled `in_patch`. The backlog's
  end-to-end phrasing ("a `Native` impl whose `update` emits a signal on itself") needs a
  widget whose programmatic update emits — `ToggleButton`/`Switch` — and lands in Task 3,
  per the brief.
- `docs/m1-backlog.md` untouched, as instructed (Task 11 owns it).
- Tests assert real behaviour, not tautologies: every printed number in
  `expected_signals.txt` moves or fails to move for a reason named in a comment, and the
  driver assertion was demonstrated failing before the fix.
- `scripts/ci.sh` green; live suite green three times over.

## Concerns

1. **`schedule_event`'s broken guard is not directly pinned by a test.** Nothing public
   observes the Bonsai action queue's length, and `Scheduler.guarded_frame` already calls
   `stop`, which makes `request_frame` a no-op anyway — so the guard's only observable
   effect is the queue not growing. `live_driver` does click a broken driver's button
   twice (exercising the path), but the assertion is "nothing re-raises", which held
   before the change too. If this matters, a `Private` counter on queued actions would
   pin it; I did not add one rather than widen `Private` for a single assertion.
2. **`after_of` is O(index) per op** (`List.nth_exn`), and the surrounding `cur`
   bookkeeping is already O(n) per op via `List.take`/`drop`/`filteri`, so a list patch is
   O(n·ops). That is unchanged in order from M0 (which additionally walked GTK's child
   list per op, so this is strictly cheaper), but it is a list-shaped data structure doing
   index arithmetic, and a container with many children — the `GtkListBox` M1 adds — will
   feel it. Worth an array or a zipper if a list widget ever gets long; not worth it now.
3. **The `Update` kind-change arm still removes after `patch` destroyed the old live.**
   I preserved M0's comment about a `Window` in a list being destroyed for real before the
   `remove` that names it. The `~after` change does not affect this; it stays a latent
   issue for whenever windows become list children (M3's `Node.windows`).
4. **`Widget_impl.child_ops` is a breaking change** for any out-of-tree impl. Nothing
   outside `src/widgets/` implements it today and `Widget_impl` lives under `Private`, so
   this is free now and would not have been later — which is the backlog's point.
