# Task 12 report — `Expert.embed`

**Commit:** `27a8b9c` on `m2`, base `2f8eeb9`. One commit; no push, no merge, no `bd`.

**Gate:** `nix develop -c ./scripts/ci.sh` → `all green`, exit 0, run twice (once before the
final comment pass, once on the committed tree).

---

## Headline: there is no use-after-free to defend against, and that changes the API

The brief's question 6 assumes that destroying the host destroys the embedded tree, so a
frame afterwards is undefined the way any use-after-destroy is. Measured under GTK 4 with
this ocgtk pin (`d98d939`), it is not:

| what was done | what GTK did |
|---|---|
| `gtk_window_destroy` on the host window | **no `destroy` signal anywhere** — not on the window, not on the stack, not on the page |
| ...and the tree below it | **not even unparented**: the page's parent is still the `GtkStack` |
| the page afterwards | alive, unrealized, fully patchable — labels update, children append |
| dropping the last OCaml reference to the window, then two `Gc.full_major`s | `destroy` fires on **the window only**; the page is still whole |
| `gtk_box_remove` of a child something else references | no `destroy`, refcount 2 → 1, widget alive |

The reason is the shadow tree: `Patcher.live` holds an ocgtk wrapper — hence a GObject
reference — for every widget it built. A widget GTK unparents but something still
references is not disposed, and `GtkWidget::destroy` is emitted from `dispose`. So an
embedded tree **outlives its host**, and a frame after the host is gone patches widgets
that are alive and merely off screen.

Three consequences, all of which shaped what shipped:

1. The obligation in the mli is an **economy, not a safety rule**: `stop` before you drop
   the host or you keep a tick, a Bonsai graph and a whole widget tree alive for a page
   that is off screen for good. Stated that way rather than as "undefined behaviour",
   because saying "undefined" about something measured to be well-defined is worse than
   saying nothing.
2. The `destroy` backstop the ruling asked for is **kept but is quiet**: it can only fire
   for an embedder that runs `dispose` on the tree outright. It is five lines, it is
   pinned, and `embed.mli` says exactly when it can and cannot fire.
3. **`~host` is dropped** — see below.

Probes were throwaway executables under `xvfb-run` at `2f8eeb9`; every claim above is now
also a golden line in `test/live/expected_embed.txt`.

---

## The API as shipped

```ocaml
(* Bonsai_gtk.Expert *)
module Embedded = Embed   (* i.e. Embed.t and its five operations *)

val embed
  :  ?time_source:Bonsai.Time_source.t
  -> ?optimize:bool
  -> ?target_frames_per_second:float
  -> (local_ Bonsai.graph -> Node.t Bonsai.t)
  -> Embedded.t
```

`Embed` (`src/embed.mli`):

```ocaml
type t
val create : ?time_source:… -> ?optimize:bool -> ?target_frames_per_second:float -> app -> t
val widget : t -> Widget.t          (* total, stable for the t's whole life *)
val frame : t -> unit
val schedule_event : t -> unit Ui_effect.t -> unit
val broken : t -> bool
val stop : t -> unit
```

`Driver` (`src/driver.mli`):

```ocaml
type root_kind = [ `Window | `Not_window ]
val create : ?time_source:… -> ?optimize:bool -> ?root_kind:root_kind -> on_window_created:… -> app -> t
val mark_broken : t -> unit
```

### Lifetime rules, as the mli states them

- **Legal root.** `` `Window `` requires a `Node.window`; `` `Not_window `` refuses one. The
  rules are opposites, not a relaxation, and each message is written once in
  `Driver.check_root`. Below the root the rule is the patcher's and unchanged — which for
  an embedded tree means a `Node.window` is rejected **anywhere at all**, with the path.
- **Parenting.** `embed` writes to nothing. `widget` is the root and the caller parents it
  with whatever its container uses (`set_child` / `append` / `add_named` / `insert_page` /
  `insert`).
- **Frames.** `create` mounts with one frame of its own, then installs a tick
  (`Driver.start_tick ~fps:target_frames_per_second`, default 60) on whatever main context
  the embedder runs. No `GtkApplication`, no main loop. With no main loop the tick never
  fires and `frame` is the only path — which is how `live_embed.ml` works.
- **Two embeds.** Each `create` builds its own `Driver`, hence its own `Scheduler`, tick and
  broken-ness. One dying stops only itself. They share exactly what any two GLib users
  share: the main context. Pinned — a third embed's frame raises through the tick's guarded
  path and the other two go on rendering.
- **Teardown.** `stop` = `Driver.stop` (tick off, tree torn down, observers invalidated) and
  **does not unparent**. Either order is safe; after `stop` the widget is an ordinary GTK
  widget the embedder may keep or drop. Idempotent; `frame` afterwards raises.
- **A failed `create`** tears down what it built before re-raising, since the caller gets an
  exception instead of a `t` and would have no handle to `stop`.
- **Errors** go through the same channel as `start`: the scheduler logs once on stderr and
  stops the driver; `broken` reports it.
- **`require_specs` / `Placement` / diagnostics** are untouched — same points, same
  messages. Pinned by mounting a misplaced `Attr.grid_cell` on an *embedded* root and
  showing it produces the identical "on the root node, which has no container to read it"
  rejection a windowed root gets.

---

## Per-step summary

**Step 1–2 (failing test).** `test/live/live_embed.ml` written first against the brief's
sketch; failed with `Unbound value "Expert.embed"`.

**Step 3 (`driver.ml(i)`).** `root_kind` as a variant per the ruling. Shipped **optional,
defaulting to `` `Window ``**, and `loop.ml` passes `~root_kind:`Window` *explicitly*: a
required argument would have broken the published `Expert.Driver.create` signature and five
call sites in `live_driver.ml` for no behavioural gain, while the explicit pass at both call
sites is what the ruling actually wanted ("neither entry point can pass the wrong one
silently"). `Driver.mark_broken` added for the destroy backstop — deliberately not `stop`,
which would walk the very subtree whose disposal is being reported.

**Step 4 (`embed.ml(i)`).** Thin, as specified: `Driver.create` + one `frame` + the destroy
connection + `start_tick`, wrapped in a two-field record. `on_window_created` is a
`failwith`, not a no-op: reaching it would mean the root-kind check *and* the patcher both
had a hole, and a silently unpresented window is the §11 failure mode.

**Step 5 (`bonsai_gtk.ml(i)`).** `Expert` gains `module Embedded = Embed` and `val embed`.
`Expert.Driver` stays exposed. `Bonsai_gtk.start` is untouched.

**Step 6 (run, promote, gate, commit).** Only `expected_embed.txt` and the two new
`expected_text.txt` lines moved; **every other live golden is byte-identical**, which is the
review focus item about `start`'s behaviour.

**`patcher.mli`.** Doc-only. `~is_root` now says what it means for an embedded root: it
records *where* the node is, not what it may be; the kind rule is the driver's `root_kind`
and runs first, so an embedded root is passed `~is_root:true` like any other and the window
it may not be has already been rejected with a better message.

**Example.** `examples/embed.ml` — a hand-built `GtkApplicationWindow` + `GtkStack` +
Show/Hide buttons, mounting and tearing down a Bonsai page repeatedly (so a leak or a
use-after-teardown has somewhere to show up), with `on_close_request` doing the `stop` the
mli asks for. The page runs a `Bonsai.Clock.every` so the tick is visibly working, not just
servicing clicks. It mounts at startup so `scripts/ci.sh`'s smoke exercises the embed;
`ci.sh` now builds and smokes it alongside `counter` and `gallery`.

**Headless handle:** unaffected and untouched — `Bonsai_gtk_test` does not link the driver.
`dune build @test/runtest` and the per-package `bonsai_gtk_test` run are green.

---

## Deviations, with reasons

1. **`~host` dropped** (the brief authorizes this explicitly and asks for the reasoning).
   Neither claimed use is real: the tick is a `Glib.Timeout` on the default main context
   with no widget lifetime to hang on, and "am I still in a tree" is
   `Widget.get_parent`/`root` on the root itself. The third possible use — the destroy hook
   — is *better* on the root (the host may be a plain container whose `destroy` is as quiet
   as the root's, and a window host's fires only at an arbitrary GC because ocgtk's wrapper
   holds a reference). And the hazard it insured against does not exist, per the headline.
   An unused argument in a new public entry point is worse than adding it in M3, so it is
   not there. **The brief's Step-1 test code and any Stavekeeper call site written against
   it lose one labelled argument.**
2. **`?root_kind` is optional, defaulting to `` `Window ``**, rather than required — with
   both real call sites naming it. Reason above.
3. **`Driver.mark_broken` is new public API**, not in the brief's changed-interfaces list.
   The destroy backstop needs a way to stop a driver without touching widgets, and
   `Scheduler` is only reachable through `Private`. Documented as a backstop, not a normal
   path.
4. **The mli's "host destroyed first" paragraph is rewritten** against the measurement: not
   "undefined behaviour turned into a no-op", but "the tree survives; the cost is a tick and
   a graph kept alive". The backstop is described as covering the one path that is not
   measured to be safe.
5. **`Expert.Embedded` is a module alias**, so it also exposes `create` — which `embed` is.
   The brief's sketch showed a five-value signature. Aliasing keeps `Embed`'s documentation
   reachable from `Expert.Embedded` and matches how `Expert.Driver` is exposed; `embed` is
   documented as "`Embedded.create`, under the name the call site reads best".
6. **The bench is a ratio, not a wall-clock bound** — `task-7-review.md` N1's second form,
   already the house style.

---

## Carries taken from Task 11

- **The reviewer's note** (the declined-day re-pick guard defended by a comment, not by a
  test): taken. `test/live/live_text.ml`'s driver-calendar block gains a re-pick — the user
  picks the same refused Saturday a second time — and two golden lines.
  **Mutation-verified**: deleting `st.last_fired <- None` from `w_calendar.ml`'s `set_date`
  turns both new lines into `handler saw 0 more` and leaves `2026-08-29` standing on the
  calendar with no frame coming (a handler that never fires schedules no effect, so no idle
  is armed), and it poisons the four C1 walk lines after it too.
- **Carries 1, 3, 4, 5, 6, 7** (editable-label props, O(len) entry compare, the gallery's
  unenforced completeness claim, the calendar's four unexposed signals,
  `read_back.connect`'s single multi-emission user, the unconnected `notify::day`): **not
  taken** — none is in this task's files and all are M2 backlog rather than blockers.

---

## Test / CI tails

```
== live tests (xvfb)
bonsai_gtk: exception in frame, stopping the driver: (Invalid_argument
  "root/0/1: a Node.window may only be the root node, not a child of another node")
live_embed: the bonsai_gtk frame exception that follows is expected
bonsai_gtk: exception in frame, stopping the driver: (Invalid_argument
  "root/1: a Node.window may only be the root node, not a child of another node")
bench: 0.0089 ms embedded, 0.0107 ms windowed, ratio 0.83 (bound 1.2)
...
== example smoke
all green
```

`test/live/expected_embed.txt` in full:

```
before the caller parents it: stack holds 0, root's parent is nothing
(GtkWindow (title ()) (css (background)) hidden
 (children
  (GtkStack (visible (page))
   (children
    (GtkBox (spacing 0) (css (vertical))
     (children (GtkLabel (text "count 0"))
      (GtkButton (label (+)) (css (text-button))
       (children (GtkLabel (text +))))))))))
(GtkBox (spacing 0) (css (vertical))
 (children (GtkLabel (text "count 1"))
  (GtkButton (label (+)) (css (text-button)) (children (GtkLabel (text +))))))
broken: false
window root: Bonsai_gtk.embed: the root node is a Node.window, but an embedded tree is parented into a container the caller owns and a GtkWindow is a toplevel that cannot be parented. Use Bonsai_gtk.start for a tree that owns its window, or make the root a container.
nested window: root/1: a Node.window may only be the root node, not a child of another node
misplaced attr on the root: root: Attr.grid_cell is on the root node, which has no container to read it (a placement attribute is read by the container, and this one holds children for Grid)
a second embed alongside the first: stack holds 2
after two clicks on the second: "count 1" and "second 2"
after the breaker's frame raised: breaker true, first false, second false
the first embed still renders: "count 2"
after stop: stack holds 2, the root is still a GtkBox under a GtkStack
stop then remove: stack holds 1, the root's parent is nothing
remove then stop: stack holds 0 before the stop
remove then stop: the root is a GtkBox under nothing, still usable: "second 2"
frame after stop: Bonsai_gtk: Driver.frame on a stopped driver (stop invalidates the Bonsai graph and tears the widget tree down; build a new driver instead)
the host is presented and the page renders: "orphan 1"
after gtk_window_destroy: broken false, root's parent GtkStack, realized false
a frame after the host was destroyed still patches: "orphan 2"
after two full majors: "orphan 3", children 2, type GtkBox
stop after the host was destroyed: broken false
before the destroy: broken false
after the root's destroy fired: broken true
a frame on it was a no-op, still broken: true
stopped a broken embed
bench: 2000 idle frames, embedded/windowed cost ratio under 1.2: true
```

The load-bearing lines: `after stop: stack holds 2` (if `stop` ever unparented, this drops
to 1 and the next line's parent becomes `nothing`); `after gtk_window_destroy: … root's
parent GtkStack` (the measurement the whole lifetime section rests on); `after the
breaker's frame raised: breaker true, first false, second false` (independent schedulers).

New in `test/live/expected_text.txt`:

```
driver, the user picks the same Saturday again: 2026-08-29 (handler saw 1 more)
driver, refused a second time: 2026-08-31 (handler saw 1 more)
```

The bench, three consecutive runs under `xvfb`: 0.0085 / 0.0086 / 0.0086 ms embedded
against 0.0096 / 0.0098 / 0.0096 ms windowed — ratio 0.89 every time, and 0.83 on the CI
run. The embedded root is *cheaper*, by exactly the one `Node.window` whose `reassert` the
windowed tree runs every frame; the bound is one-sided at 1.2 because the claim is "no
worse" and 1.2 still catches a doubling.

---

## Carries to Task 13

1. **The `~host`-shaped hole is still open for M3.** An `Attr` that names an ancestor (a
   search entry's key-capture widget, a mnemonic target) is the one use that would make a
   host argument real. When it arrives, it belongs on `embed` as `~host` — the name is
   reserved by this report, not by the code.
2. **`Expert.embed` is not in the README.** Task 15 owns docs; the README's entry-point
   section names only `start`, and `examples/embed.ml` is not listed anywhere a reader
   finds it.
3. **Nothing stops an embedded tree being ticked while it is off screen**, which is exactly
   what the mli's obligation asks the caller to prevent by hand. If M3 wants it automatic,
   `notify::root` is the deterministic signal (it goes NULL the moment the tree leaves a
   toplevel, unlike `destroy`, which was measured never to fire) — but it also fires on a
   legitimate re-parent between windows, so it can only drive a *query* (`Embedded.rooted`)
   or an opt-in pause, never an automatic break. Deliberately not built here.
4. **`Embedded.broken` is `false` after `stop`**, inheriting `Driver`'s split between
   "stopped" and "broken". Correct but easy to misread as "still healthy"; if a caller ever
   wants one predicate, the honest one is `stopped || broken` and it does not exist.
5. **`examples/embed.ml`'s Show/Hide cycle is only smoke-tested for three seconds.** The
   mount/teardown loop it exists to exercise is proven in `live_embed.ml`, not by the
   example; an example that drove itself under an env var would close that, at the cost of
   `ci.sh`'s exit-code check growing a special case.
6. **Two `Bonsai_gtk.start`s still cannot coexist, but `start` + N embeds now can.**
   `Gtk_effect.quit` targets the `start` application only; performing it from inside an
   embedded tree that has no `start` above it logs and does nothing, which is the existing
   documented behaviour and is now reachable a second way.

---

# Fix round 1

**Commit:** `629185c` on `m2`, base `27a8b9c`. One commit; no push, no merge, no `bd`.

**Gate:** `nix develop -c ./scripts/ci.sh` → `all green`, exit 0, run twice (once before the
example's comment pass, once on the committed tree). Only `expected_embed.txt` moved; every
other live golden is byte-identical, which is the check that the exception-safe `mount`
did not change `start`'s behaviour.

---

## C1 — `Embedded.widget` now names a wrapper the runtime owns

**Accepted without argument.** The reviewer is right, the failure is silent, and the shape
it fails on is a page: `Node.label "Loading…"` on one frame and `Node.box […]` on the next.
`Patcher.patch`'s kind-change arm mounts a replacement and destroys the original, and the
caller's `add_named` had run once, at mount. Under `start` the arm is unreachable — a
windowed root is always a `Window` — so `embed` is what made it reachable.

**Ruling taken: option 1.** `Embed.create` allocates one container, parents the driver's
root into it, and returns it as `widget`. The per-frame `phys_equal` the ruling describes
lives in the driver rather than in `Embed`, because `Embed.frame` is not the only path to a
frame: the tick and the idle a `schedule_event` arms both call `Driver.frame` directly, so a
check in `Embed` would miss every frame the embed did not drive by hand. `Driver.create`
gains `?on_root_widget_changed`, called with the root widget whenever that widget becomes a
different object — once at the first mount, and on any frame where the patched root is not
physically the old one. `start` passes nothing and is unaffected.

### Which container, and why it was measured

The wrapper has to be invisible to layout, or `embed` silently re-flows every page. Measured
under GTK 4 (`xvfb`, throwaway probe at `27a8b9c`): a non-expanding child with
`halign`/`valign` `` `CENTER `` inside a 400×300 `GtkStack` page, position relative to the
stack —

| wrapper | child position | what is lost |
|---|---|---|
| none (parented directly) | **(196,142)** | — |
| `GtkBox` `` `VERTICAL `` | (196,**0**) | `valign` |
| `GtkBox` `` `HORIZONTAL `` | (**0**,142) | `halign` |
| `GtkGrid` cell | (**0**,**0**) | both |
| **`GtkOverlay`** | **(196,142)** | **nothing** |

A box packs along its orientation and a grid packs into a cell, so both hand the child its
natural size and drop the alignment on that axis. `GtkOverlay` gives its main child the
whole allocation — it is `GtkBinLayout` under a public name — which is what `set_child` on a
window or a stack page does. All four forward `hexpand`/`vexpand` correctly (checked with an
expanding child: 400×284 in every case); only the overlay also forwards alignment. It draws
nothing and adds no CSS, but it is a real widget and shows up in a `Live_tree` dump, which
the mli says.

`stop` unparents the rendered tree from the wrapper and leaves the wrapper — an ordinary
empty container — parented wherever the caller put it. The mli says what the caller must
then do: remove it (either order) and drop it, and that dropping it is what releases the
tree.

### Test evidence

`test/live/live_embed.ml`, golden lines:

```
kind change, before: the stack holds a GtkOverlay holding a GtkButton
kind change, after: the stack still holds the same GtkOverlay (same object: true), now holding a GtkBox
the widget the patcher replaced is a GtkButton whose parent is now nothing
(GtkWindow … (GtkStack … (GtkOverlay (children (GtkBox … (GtkLabel (text "loaded 1")) …)))))
a click on the new content reached the model: "loaded 2", broken false
```

The last line is the reviewer's requirement and the one that would have failed before: the
old page was not merely frozen but inert, because `destroy` had disconnected its handlers.
The `Live_tree` dump is taken from the host window, so it shows the wrapper in position
between the caller's stack and the rendered root. The wrapper also appears in the two
existing dumps and in the `after stop` line, which now reads `the wrapper is still a
GtkOverlay under a GtkStack, holding 0`.

The reviewer's two riders are closed with it: the destroy backstop is connected to the
wrapper, which never changes; and `stop` tears down the tree that is current.

---

## I1 — `Patcher.mount` is exception-safe

**Fixed at the root cause, per the ruling.** `mount` now records what it has built as it
builds it and, on any raise after the widget exists, undoes exactly those stages before
re-raising with the original backtrace: slots emptied, controllers released, connections
disconnected, completed children destroyed, and the kind's own registrations released.

The kind-specific tail of `destroy` is extracted as `release_kind ctx ~kind ~widget` and
both paths call it, so the two cannot drift — a kind that acquires something at mount is a
compile error in one exhaustive match rather than a silent leak on one of two paths.

The child helpers each protect what *they* built, which is what makes a raise on the third
child not strand the first two: `mount_list` accumulates its lives and destroys them,
`mount_slots` does the same over already-built slots, and `mount_single` covers the `set`
call that can raise after its child exists. Each recursive `mount` cleans up after itself,
so only the siblings a helper built are its business.

`Driver.create`'s and `Embed.create`'s "torn down what it built" sentences are now true for
`start` as well. The M1 backlog item is struck through and annotated.

### Test evidence, and the instrument that was thrown away

Two deterministic checks in the golden:

```
a mount that raises: root/3: Label does not emit On_clicked
the siblings it had already built were torn down: 2 native destroys of 2
a mount that registers then raises: root/1: Label does not emit On_clicked
the same ctx then mounts a tree naming the same stack, and a switcher finds it
```

The first uses `Native.S.destroy` as the counter (the ruling's own suggestion) — it runs
from `release_kind`, so it cannot pass while the shared match is wrong. **Mutation-verified:**
deleting `List.iter !built ~f:(destroy ctx)` from `mount_list`'s unwind turns it into `0
native destroys of 2`.

The second is the `ctx.stacks`/claims half the ruling asked for. It drives the patcher
directly, because there is no other way to see it: an embed whose frame raised is broken for
good, so no driver ever mounts twice on one `ctx`. **Mutation-verified in both directions:**
with the `abandon_fixups` call removed, the second mount raises `root/0: two Node.stacks are
named "shared" in one tree`. The first half of the corresponding backlog item turns out not
to be a defect at all — registrations are deferred to `apply_stack_claims`, which a raising
mount never reaches — and the backlog now says so; the `drop_stack_names` mirror image is
still open.

**I wrote a live-words leak test and deleted it, which is worth recording.** The reviewer's
390 KB is real and I reproduced it (50 664 live words per failed create, against 11 136
after the fix). But as a *test* it does not work, and I found that by mutating it: the two
shapes it compares are both dominated by a retention that is not the mount's, so with the
fix removed the ratio moved the *wrong way* (1.30 mutated against 2.18 fixed). The reason is
the finding below. A number that inverts under the mutation it is meant to catch is worse
than no number, so the deterministic instruments above are what shipped and the measurement
lives in the report and the backlog.

### A finding out of scope, now on the backlog

**A `Driver` is never reclaimed, stopped or not.** A `Driver.create` that is stopped without
ever being framed retains ~39 000 live words on a heap settled through two full majors; a
failed `embed`, ~10 000. It is the Bonsai graph rather than anything GTK — Incremental's
state is global and outlives the observer invalidation `stop` performs — so an application
building a driver per dialog grows without bound. Recorded in `docs/m1-backlog.md` with the
measurement; the lever is Bonsai's, not this library's. It is also why the words test could
not work.

---

## I2 — and the two things it turned up

**Taken.** One block, both directions, in the golden:

```
5 embeds stopped and dropped: 5 wrappers finalized
5 embeds dropped without stop: 0 wrappers finalized
```

The `without stop` row is what proves the finaliser is a real instrument rather than one
that never fires; the `stopped` row is the claim the entry point rests on. Writing it turned
up two defects, neither of which existed before this round and both of which are now fixed:

1. **`Driver.stop` did not drop `on_root_widget_changed`.** The callback closes over the
   wrapper, and the driver is never reclaimed (above) — so the field kept the caller's
   widget alive for the life of the process, turning "after `stop` you may drop it" into a
   promise the runtime quietly broke. Measured: without the drop, `0 of 5`. `stop` now
   clears it, and `driver.mli` says why.

2. **The destroy backstop hangs the process when the wrapper is finalized.** Making the
   wrapper collectable made GTK dispose it from inside OCaml's finalisation: ocgtk's
   finaliser unrefs the GObject, dispose emits `destroy`, and the marshaller calls back into
   OCaml from the collector. Measured: with the handler left connected, the second `embed`
   created after a stopped embed had been dropped never returns — bisected by removing the
   connection, which made the suite pass. `Embed.stop` now disconnects it, which is also the
   right rule on its own terms: the backstop's job is to notice a disposal *while this embed
   is rendering*, and after `stop` there is nothing to protect. The disconnect is guarded by
   an `option` because `stop` is idempotent and `g_signal_handler_disconnect` on a stale id
   is a GLib critical, not a no-op (caught by the suite before commit).

   Recorded on the backlog as a general hazard: nothing stops an application connecting its
   own `destroy` handler and hitting the same thing, and nothing warns.

---

## Minors

| # | Taken | What |
|---|---|---|
| M1 | yes | `target_frames_per_second ≤ 0` documented on `Embedded.create` and on `Expert.embed`, pointing at `Driver.start_tick` for what it leaves running. |
| M2 | yes | `broken` now says it is "did rendering fail", not "is this page healthy" — a stopped embed answers `false` — and tells a caller holding an `Embedded.t option` to read `None` as "torn down". |
| M3 | yes | `examples/dune` split in two, with `(modules …)` on each (two stanzas in one directory otherwise both claim the `.pp.ml` rules). `counter` and `gallery` link no ocgtk again, and a comment says that is the point. |
| M4 | yes | The backstop's test comment now says what the block does and does not prove: the connection exists, and there is no *measured* trigger. It also names the block that would change first if a GTK upgrade ever produced one. |
| M5 | yes | `bonsai_gtk.mli`'s `embed` doc no longer restates `Embed`'s three rules; it points at `{!Embedded}` and says that is the copy to keep up to date. |

Also taken, from the reviewer's out-of-scope list: `live_embed.ml`'s `drain` is bounded. Not
a precaution — this file hit the hang, after a click on a page whose embed still had a 60 fps
tick, and the bound is what let me localise the real problem behind it (defect 2 above). The
other live tests' `drain`s are untouched and recorded on the backlog.

---

## Carries to Task 13 (updated)

Carries 1, 2, 5 and 6 from the first round stand. Carry 3 is **withdrawn** in its original
form — `notify::root` as a possible automatic pause — because this round found that a GTK
signal reaching OCaml during finalisation can hang the process; anything of that shape now
needs the disposal question answered first. Carry 4 is **closed**: `Embedded.broken` is
documented as not meaning "healthy".

New:

7. **`Bonsai_gtk.start`'s `on_window_created` has the same retention shape** as
   `on_root_widget_changed` did and is *not* dropped by `Driver.stop`: it closes over the
   `GtkApplication`. Harmless today, since the only `start` in a process outlives its driver
   anyway, and one line the day it is not. On the backlog.
8. **The wrapper is visible.** `Live_tree` dumps show a `GtkOverlay`, GTK Inspector shows
   one, and a CSS selector written against the caller's container (`stack > box`) no longer
   matches. Nothing in M2 does that; a theme-heavy application might. The alternative is a
   `GtkWidget` subclass with `GtkBinLayout`, which ocgtk cannot express.
9. **`Patcher.patch` is still not exception-safe**, only `mount` is. A patch that raises
   part-way leaves the shadow tree describing a GTK tree it does not match, which is exactly
   why a raising frame breaks the driver for good — so this is bounded in a way the mount
   leak was not. But `patch`'s kind-change arm now calls an exception-safe `mount`, which is
   the half that was reachable from an embedded root.
