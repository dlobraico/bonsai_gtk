# Task 12 review — `Expert.embed`

**Commit:** `27a8b9c` on `m2`, base `2f8eeb9`. Diff read in full
(`review-2f8eeb9..27a8b9c.diff`, 882 insertions across 16 files).

**Gate re-run by the reviewer:** `nix develop -c ./scripts/ci.sh` → `all green`, exit 0.
The embed bench on that run: `0.0087 ms embedded, 0.0096 ms windowed, ratio 0.91
(bound 1.2)`. Every live golden passes; only `expected_embed.txt` and the two new
`expected_text.txt` lines moved, as the report says.

All probes below ran in a throwaway worktree at `27a8b9c` (`git worktree add
/tmp/m2-t12-verify 27a8b9c`), as a new `test/live/probe_t12.ml`, under `xvfb-run`. The
worktree has been removed; nothing tracked was modified.

---

## Summary

The entry point is the right shape, the root-kind inversion is done cleanly, and the
headline claim survives every probe I could think of: **the report is right that there is
no use-after-free, and it is right for the reason it gives.** The diagnostics are provably
identical to a windowed root, `stop` really does leave the host alone, two embeds really
are independent, and 100 frames on a tree whose host window has been destroyed produce
**zero GTK criticals**.

But the API has one hole that the Stavekeeper `Shell` will fall into on an ordinary
Bonsai pattern, and it fails silently. `Embed.t` captures the root widget at mount
(`src/embed.ml:11`) and `embed.mli:85` promises it is "the same widget for this [t]'s whole
life". The patcher does not honour that: when the root node changes *kind* between frames —
`Node.label "Loading…"` on one frame and `Node.box [...]` on the next, which is what a page
does — `Patcher.patch` mounts a replacement widget and returns it as the new root
(`src/patcher.ml:596-607`), and nothing re-parents it. The caller's container goes on
holding the old, now-disconnected widget. The page freezes on screen forever, `broken` stays
`false`, and no message is printed. That is C1, and it is the one finding I would not merge
without.

Second, `create`'s failure path does not do what both mlis say it does: a mount that raises
after connecting even one signal leaks the entire driver, its Bonsai graph and its partial
widget tree permanently — measured at ~390 KB per failure.

Verdict below: **Changes requested.**

---

## The headline claim, and the probe output

> "There is no use-after-free to defend against, and that changes the API."

**Upheld, on all four sub-claims.** Probe 1 built the exact host shape the ruling is about —
a `GtkWindow` whose child is a `GtkStack`, holding one embedded page — presented it,
destroyed the window with `gtk_window_destroy`, and then drove 100 frames, each preceded by
a real `clicked` emission and an idle drain, with `Gc.full_major ()` every 20 frames. The
embedded tree was deliberately rich, so that every GTK call a frame can make on an unrooted
widget was exercised: a `Node.stack` with a controlled `visible_child` (a fixup that writes
`set_visible_child_name`), a `stack_switcher` that has to resolve that stack, a `list_box`
with a controlled selection (a second fixup), a `notebook` with a controlled current page (a
third), a `drop_down`, an `image` and a `spinner`.

```
== probe 1: host destroyed under a live embed, 100 frames + GC
presented, realized=true, label="count 1"
after destroy: broken=false parent=GtkStack realized=false
after 100 frames: label="count 101" broken=false children=9
heap words 1048576 -> 1133349 (delta 84773), rss 80916 kB -> 82916 kB (delta 2000)
root refcount 3, host window refcount 1
stopped after the host was destroyed: broken=false
```

- **The tree survives.** After `gtk_window_destroy` the page's parent is *still* the
  `GtkStack` — GTK did not even unparent it — and it is merely unrealized.
- **Frames keep working.** 100 clicks and 100 frames took the label from `count 1` to
  `count 101` with the tree still nine children wide.
- **No criticals.** `grep -icE "critical|warning"` over the whole stderr of every probe run:
  **0**. Not from the stack fixup, not from the notebook's `set_current_page`, not from the
  list box's selection walk. (There is no `grab_focus` and no `present` anywhere in the
  runtime outside `loop.ml:26`, which `embed` replaces with a `failwith` — so the surface
  the ruling worried about is exactly what probe 1 covers.)
- **The cost is real and is what the mli says it is.** Probe 4 ran a genuine main loop with
  a 120 fps tick and a `Clock.every`, destroyed the host mid-tick, and the tick went right
  on firing (`label="ticks 23"`, `parent=GtkStack`, `broken=false`). 100 frames on the
  orphan cost ~85 k heap words and 2 MB RSS; nothing is reclaimed until `stop`.

So deviation 4 (rewriting the "host destroyed first" paragraph as an economy rather than a
safety rule) is correct, and the mli's wording is honest.

**One thing the report does not say, which I measured and which strengthens the obligation.**
An embed dropped *without* `stop` is not merely "kept alive until the process ends" — it is
permanently unreclaimable, and this is true with or without the destroy backstop:

```
== probe 2: dropped without stop -- is the tree collectable?
control (a plain GtkLabel nobody keeps): finalized: true
embed  (with destroy hook): root wrapper finalized after 2 majors + compact: false
driver (no destroy hook)  : root wrapper finalized after 2 majors + compact: false

== probe 2b: stopped, then dropped -- is the tree collectable?
embed stopped then dropped: root wrapper finalized: true
```

The cycle is not the backstop's doing (the raw `Driver` leaks identically): every signal the
patcher connects roots a closure that captures the driver (`Driver.create`'s
`~signals:{ schedule = fun effect -> schedule_event (this ()) … }`), and the driver's shadow
tree holds a GObject reference to the widget that closure is attached to. GC and refcounting
cannot break that between them. **`stop` is what breaks it, and it does so reliably** —
probe 5 confirmed the root wrapper is reclaimed after `stop` + drop for all sixteen shapes I
tried (label, button, stack, stack+switcher, list_box, flow_box, notebook, drop_down, image,
spinner, entry, search_entry, text_view, calendar, editable_label, and the whole rich tree).
That is good news for the design; it just means the obligation is load-bearing and deserves
a test in the direction that matters (see I2).

**The destroy backstop.** What it covers, precisely: only a `destroy` *signal emission* on
the root. Since the shadow tree always holds a reference, GTK's own teardown never emits it
(confirmed: probe 1's host destroy emitted nothing), so the hook fires only for an embedder
that disposes the tree outright — the shipped golden reaches it by
`Gobject.Signal.emit_by_name ~name:"destroy"`, which the code comment honestly labels as
standing in for disposal. `Driver.mark_broken` as the public surface is the right call given
that: `stop` would walk the very widgets being reported, and `Scheduler` is only reachable
through `Private`. Verdict on deviation 3: **accepted**; the hook is cheap, correctly
documented as quiet, and the one thing it must not do (touch widgets) it does not do.

---

## Per-deviation judgement

| # | Deviation | Verdict |
|---|---|---|
| 1 | `~host` dropped | **Accepted.** The brief authorises it explicitly and the reasoning holds: the tick is a `Glib.Timeout` on the default main context with no widget lifetime to hang on; "am I still in a tree" is `get_parent`/`root` on the root itself; and the destroy hook is genuinely better on the root than on a host whose own `destroy` is equally quiet. Carry 1 (reserving the name for M3) is the right way to leave it. |
| 2 | `?root_kind` optional, defaulting to `` `Window ``, with both real call sites naming it | **Accepted.** Keeping `Expert.Driver.create`'s published signature and the five `live_driver.ml` call sites working is worth more than the compile-time forcing, and `loop.ml:33-45` passing `~root_kind:`Window` explicitly with a comment is what the ruling was actually after. |
| 3 | `Driver.mark_broken` is new public API | **Accepted.** See above. The doc at `driver.mli:105-119` states its limits accurately, including that it is a backstop rather than the normal path. |
| 4 | The mli's "host destroyed first" paragraph rewritten as an economy | **Accepted, and correct.** My probes reproduce every measurement it rests on. Refusing to call a measured-safe thing "undefined" is the right instinct. |
| 5 | `Expert.Embedded` is a module alias, so it also exposes `create` | **Accepted.** It matches how `Expert.Driver` is exposed and keeps `Embed`'s documentation reachable. `Expert.embed` and `Expert.Embedded.create` being two names for one function is a wart, not a defect. |
| 6 | The bench is a ratio, not a wall clock | **Accepted** — house style since `task-7-review.md` N1, and the one-sided 1.2 bound is argued correctly in the comment (the embedded root is *cheaper* by exactly the window's `reassert`). |

---

## Critical

### C1. A root-kind change silently freezes the page, and `Embedded.widget` keeps pointing at the corpse

**Where:** `src/embed.ml:11` and `src/embed.ml:49-56` (the widget is captured once, at
mount) against `src/patcher.ml:596-607` (a kind change at any node mounts a *replacement*
widget and returns it) and `src/driver.ml:88` (`t.root <- Some (Patcher.patch … ~is_root:true
…)`, with nothing re-parenting the result). The promise this breaks is written at
`src/embed.mli:85-87`: *"Total, and the same widget for this [t]'s whole life."*

**Why `start` never hit it:** a windowed root's kind is always `Window`, so
`Kind.same_kind` is always true at the root and the kind-change arm is unreachable there.
`embed` makes the root an arbitrary node, so the arm becomes reachable at the root for the
first time — and the patcher's own comment on that arm ("the caller re-parents the fresh
widget") describes a caller that, for an embedded root, does not exist.

**The failure scenario, which is an ordinary page:**

```ocaml
let page graph =
  let%arr data = load graph in
  match data with
  | None   -> Node.label "Loading…"            (* Kind.Label *)
  | Some d -> Node.box ~orientation:Vertical [ … ]   (* Kind.Box  *)
```

The Shell does `stack#add_named (Embedded.widget e) (Some "viewer")` once, at mount, while
the page is still the label. When the data arrives the driver mounts a fresh `GtkBox`,
disconnects the old `GtkLabel`, and hands the box to nobody. The stack still shows the
label. No exception, no stderr line, `broken` stays `false`, and the page never updates
again.

**Measured** (probe 8; a box root that becomes a grid root on the first click):

```
== probe 8: the root node changes kind under a live embed
  before: Embedded.widget is a GtkBox, stack holds 1
  after the kind change: Embedded.widget is a GtkBox, same widget as before: true
  the stack's only child is a GtkBox, and its parent is GtkStack
  what the window actually shows: (GtkWindow … (GtkStack … (GtkBox …
     (children (GtkLabel (text "I am a box")) (GtkButton …)))))
  broken: false
  a second click on what is on screen: label is still "I am a box"
  raw driver: root_widget went GtkBox -> GtkGrid (same object: false)
```

The last line is the control: the *driver* did exactly the right thing — `root_widget` moved
from the `GtkBox` to the freshly mounted `GtkGrid`. Only `Embed`'s captured widget, and
therefore the caller's container, is stale. The line before it shows the page is not merely
frozen but inert: `destroy` disconnected the old subtree's handlers, so the button on screen
no longer even advances the model.

Two smaller consequences ride along: the destroy backstop is connected to the discarded
widget (`src/embed.ml:72-74`), so after a root-kind change it watches the wrong object; and
`stop` afterwards tears down the *new* tree while the old one stays in the caller's
container.

**Suggested fix**, cheapest first — the lead should pick, this is a design call:

1. **Own one wrapper widget.** `create` allocates a `GtkBox` (or any single-child
   container), parents the driver's root into it, and returns *that* as `widget`. Each frame,
   if `Driver.root_widget` is no longer physically the same object, unparent the old child
   and set the new one. `widget` then genuinely is stable for the `t`'s life, the mli's
   sentence becomes true, and the cost is one widget and one `phys_equal` per frame. This is
   the standard answer and I would take it.
2. **Refuse the change.** Have the driver raise `Invalid_argument` when a `` `Not_window ``
   root changes kind, naming both kinds and saying to wrap the root in a fixed container.
   Loud instead of silent, but it outlaws a legal computation and pushes the wrapper onto
   every caller.
3. **Report it.** Add `Embedded.widget` reading through to `Driver.root_widget` plus an
   `~on_root_changed` callback. Correct but hands the caller work it will forget.

Whichever is chosen, a live-test case with a root that changes kind belongs in
`live_embed.ml`; there is none today.

---

## Important

### I1. A failed `create` leaks the driver, the graph and the partial tree — both mlis say otherwise

**Where:** `src/embed.ml:43-48`; the claim is at `src/embed.mli:73-77` ("having first torn
down whatever the failed mount had built") and repeated at `src/bonsai_gtk.mli:140-141`
("Raises out of here if that first frame does, having torn down what it built").

`Driver.stop` can only tear down `t.root` (`src/driver.ml:204-218`), and a mount that raises
never assigns it — `t.root <- Some (Patcher.mount …)` at `src/driver.ml:89` is a single
assignment after the whole subtree has been built. So everything a partial mount created
survives, and any signal it had already connected roots the driver, which roots the shadow
tree, which holds GObject references back. Nothing is reclaimable.

**Measured** (probe 6; 200 failed `create`s of each shape, `Gc.stat().live_words` after two
full majors):

```
== probe 6: what a failed [create] leaves behind
  200 failed mounts, no signal in the partial tree: +112206 live words (561 each)
  200 failed mounts, one on_clicked in the partial tree: +9985483 live words (49927 each)
```

One `Attr.on_clicked` mounted before the raise is the difference between 561 words and
**49 927 words — about 390 KB — retained permanently, per failure.** (49 927 is also very
close to what an entire live embed retains, which is the point: what leaks is the whole
driver and its Bonsai graph, not just the widgets.)

Failure scenario for the Shell: a page whose computation raises on some data — a duplicate
`Key.t` among rows, a `grid_cell` on a box child, a `Node` constructor's `Invalid_argument` —
is caught by `Guard.wrap` in `request_nav`, the user goes Back and tries another piece, and
every attempt at the bad one costs 390 KB plus its widgets, forever.

**Fix:** either make `Patcher.mount` tear down what it built when it raises (it already has
`destroy`, and the recursive call sites know their partial `live`s), or have the driver
stash a partial root the `stop` path can walk. If neither is affordable in this task, the
two doc sentences must be corrected — "having stopped the scheduler and invalidated the
graph; widgets the failed mount had already built are dropped, not destroyed" — and the leak
recorded as a carry, because as written both mlis promise something the code does not do.

### I2. The obligation the mli rests on is pinned in only one direction

`expected_embed.txt` pins, thoroughly, that an un-stopped embed *survives* (`after
gtk_window_destroy: … root's parent GtkStack`, `a frame after the host was destroyed still
patches`, `after two full majors: "orphan 3", children 2`). Nothing pins the other half —
that `stop` *releases* what it promises to release. That is the claim the whole entry point
rests on: `embed` exists so a long-lived application can mount and tear down a page per
navigation, and "stop, then the widget may be dropped" (`embed.mli:107-115`) is what makes
that not a leak.

It is true today — probe 5 shows the root wrapper is reclaimed after `stop` + drop for every
widget kind in the M2 catalogue, and probe 2/2b show the two cases differ exactly on
`stop`. But nothing in the suite would notice if a future change (an added global registry,
a signal `stop` forgets to disconnect, a `Child_keys` entry keyed the wrong way) turned it
into a leak, and `live_embed.ml`'s Show/Hide-shaped churn is only in `examples/embed.ml`,
where nothing asserts.

**Fix:** one block in `live_embed.ml` in the style of `live_text.ml:2234-2255`'s
reference-count test — mount N embeds inside a function, `stop` them, drop them, two
`Gc.full_major`s, and print whether a `Stdlib.Gc.finalise` on the root wrapper ran (or print
`Gobject.get_ref_count` on a widget deliberately kept). It is ~15 lines and one golden line,
and it is the only test that would catch the regression this API is most exposed to.

---

## Minor

- **M1 — `?target_frames_per_second:0.` is load-bearing and undocumented.** The bench at
  `test/live/live_embed.ml` passes `0.` with a comment saying "installs no tick". That is
  true (`src/scheduler.ml:117-121` treats a non-positive rate as "never tick", deliberately),
  but neither `embed.mli:69-83` nor `bonsai_gtk.mli:130-142` says so, and a test depending on
  an undocumented value of a public argument is one refactor from silently starting a 1 ms
  timer. One clause in `create`'s doc fixes it.
- **M2 — `broken` is `false` after `stop`.** The report's own carry 4. `embed.mli:107-115`
  never says it, and a caller that keeps an `Embedded.t option` and asks `broken` to mean
  "is this page healthy" gets `false` for a torn-down embed. One sentence on `stop`, or on
  `broken`, closes it; the module has no `stopped` predicate and does not need one if the
  doc is explicit.
- **M3 — `examples/dune` now links `ocgtk.gtk ocgtk.gio ocgtk.common` into `counter` and
  `gallery` too.** Only `embed` needs them, and those two are precisely the examples that
  demonstrate an application never has to name ocgtk. A second `executables` stanza for
  `embed` keeps that demonstration honest. (`ci.sh`'s smoke addition is right and its
  timeout-124 convention is preserved.)
- **M4 — the destroy backstop's golden certifies the signal, not the disposal.**
  `live_embed.ml` reaches the hook with `Gobject.Signal.emit_by_name ~name:"destroy"`, which
  is a fair stand-in and is labelled as one in the comment — but it means the golden line
  `after the root's destroy fired: broken true` proves the connection exists, not that any
  real GTK path reaches it. Given the report's own measurement (no ordinary teardown emits
  it), that is probably the best available; worth a sentence in the test comment saying the
  hook has no *measured* trigger, so a future reader does not mistake the golden for
  evidence that one exists.
- **M5 — `bonsai_gtk.mli:130-142` restates `Embed`'s three rules.** Two copies of the same
  three-bullet contract will drift. Pointing at `{!Embedded}` for the rules and keeping only
  the signature summary here would be safer. Cosmetic.

## Out of scope, recorded for the backlog

- **The un-stopped-embed cycle is a `Driver` property, not an `embed` one** (probe 2: the raw
  driver leaks identically). Under `start` it never mattered because the driver outlives the
  process. If M3 wants defence in depth, the lever is disconnecting the patcher's signal
  closures from a finalizer-safe place, or holding the driver from the ctx weakly — neither
  belongs in this task.
- **`drain ()`-shaped loops (`while Glib.Main.pending ()`) can fail to terminate right after
  a `Gc.full_major` that finalizes many wrappers.** I hit this twice while probing (a
  bounded `while … && n < 200` fixed it). `live_embed.ml`'s `drain` has the unbounded shape
  and terminates fine today; if a live test ever hangs after a GC, this is where to look.
- The three `Gtk-CRITICAL: gtk_calendar_set_year: assertion 'date != NULL' failed` lines in
  the CI log come from `live_text.ml`'s year-0 refusal block (Task 11), not from anything in
  this diff.

## Checks that came back clean

- **Root rules.** `` `Not_window `` refuses a `Node.window` at the root with a message naming
  `Bonsai_gtk.start` (golden line), and the patcher refuses one anywhere below with the path
  (`nested window: root/1: …`). `check_root` runs on *every* frame
  (`src/driver.ml:82`), so a computation that starts returning a window later is caught too.
- **Diagnostics parity, tested directly** (probe 7). Identical messages, differing only by
  the one path segment the window adds:
  ```
  unsupported event attr, embedded: root/0: Label does not emit On_clicked
  unsupported event attr, windowed: root/0/0: Label does not emit On_clicked
  misplaced placement attr, embedded: root/0: Attr.grid_cell is not read by Box (…)
  misplaced placement attr, windowed: root/0/0: Attr.grid_cell is not read by Box (…)
  ```
  Plus the shipped golden's misplaced-attr-*on the root* case, which is the one an embedded
  root can reach that a windowed one cannot.
- **API fit for the Shell**, item by item: `stop` leaves the widget parented and alive and
  does not unparent (golden: `after stop: stack holds 2, the root is still a GtkBox under a
  GtkStack`), which is exactly what `shell.ml:152-159`'s `drop_viewer` (`teardown ()` then
  `stack#remove`) wants; both orders are pinned; `frame`/`schedule_event` are safe from
  `request_nav`'s idle (`schedule_event` arms a HIGH_IDLE and is a no-op once stopped or
  broken); two embeds have independent ticks, schedulers and broken-ness (golden: `after the
  breaker's frame raised: breaker true, first false, second false` and `the first embed still
  renders`); the error channel is the same scheduler, same one-line stderr report. The one
  Shell-side gap is not this task's: `app#quit` bypasses `on_close_request`
  (`shell.ml:570-575` says so), so the port will need an embed-side equivalent of
  `Viewer_window.teardown_all ()` or it will skip `stop` on the quit path.
- **The reassert-only walk for an embedded root** is the driver's existing path, and the
  bench compares like with like: both computations return a physically fixed node, so both
  take `Patcher.reassert_only`. Reproduced at ratio 0.91 (bound 1.2).
- **`Live_tree.dump` of an embedded root** works and is dumped both from the host window
  (which is what proves the tree is inside the stack rather than a sibling toplevel) and from
  the root itself.
- **The headless handle is untouched** — `test_lib/` does not appear in the diff and
  `@test/runtest` is green.
- **Task 11 carries.** The reviewer's note is taken properly: the re-pick block in
  `live_text.ml:2128-2158` is the test that names `st.last_fired <- None`, with the mutation
  result written down. The other six carries are correctly left as M2 backlog.
- **Out-of-scope creep:** none of substance. `examples/embed.ml`, the `ci.sh` smoke entry and
  the `patcher.mli` doc paragraph are all in the task's remit; `Driver.mark_broken` is
  argued for.

---

## Verdict

**Changes requested.**

- **C1** must be resolved before this lands — it is a silent, permanent freeze on an
  ordinary page shape, in the exact container idiom (`stack#add_named` once, at mount) the
  entry point was built for.
- **I1** must be fixed or its two doc sentences corrected and the leak carried; a doc that
  promises teardown where there is none is worse than no sentence.
- **I2** should be taken here — it is ~15 lines and it defends the claim the whole entry
  point rests on.
- The Minors are the implementer's call.

Everything else is approved as shipped, including all six deviations. The headline claim is
correct and was worth making; it is the reason the API is as simple as it is, and it held up
under every probe I put to it.

---

# Re-review — fix round 1 (`629185c`)

Scope: `git diff 27a8b9c..629185c` only, against C1, I1, I2 and the two defects the
implementer found while closing I2. Probes ran in a throwaway worktree at `629185c`
(`test/live/probe_rr.ml`, under `xvfb-run`), including one run against a deliberately
mutated `src/embed.ml`; the worktree has been removed and nothing tracked was modified.

**Gate re-run:** `nix develop -c ./scripts/ci.sh` → `all green`, exit 0. Embed bench ratio
0.92 (bound 1.2). Only `expected_embed.txt` moved among the goldens, which is the check
that the exception-safe `mount` did not change `start`'s behaviour.

**Verdict: Approved.** All three findings are closed, and I verified each independently
rather than reading the goldens. One finding below is new, and it is about the *backlog
entry* rather than the code: the finaliser hazard is worse than "hangs", and the library is
clean of it only because the one place that could reach it now disconnects.

---

## The finaliser hazard (the main focus)

### Is disconnecting on `stop` sufficient? Yes — and for a stronger reason than the report gives

The report justifies the disconnect as "after [stop] there is nothing left to protect",
which reads as a policy choice. It is actually a safety requirement, and the proof is a
cycle nobody has written down:

- the backstop's GClosure lives on the wrapper and **captures the driver**;
- `Driver.on_root_widget_changed` is a closure that **captures the wrapper**
  (`src/embed.ml:88-96`).

So while the backstop is connected, wrapper → GClosure → driver → callback → wrapper: a
cycle spanning the OCaml heap and GObject refcounting that neither side can break. The
wrapper is therefore **not finalisable while the handler is attached**, and the only code
that clears `on_root_widget_changed` is `Driver.stop` (`src/driver.ml:226-241`, the assignment at 240), reached
from exactly two places — `Embed.stop`, which disconnects the backstop three lines later,
and `Embed.create`'s failure path, where the backstop was never connected. "The wrapper is
finalisable" and "the backstop is connected" are mutually exclusive states by construction,
not merely sequenced.

**Measured** (probe B — the reviewer's question put directly: a `t` dropped *without*
`stop`, whose backstop is still connected, including a signal-free tree where the usual
widget→closure→driver→tree cycle does not exist):

```
== B: dropped WITHOUT stop, backstop still connected -- can the wrapper be finalised?
  signal-free, unparented, no stop: wrappers finalized 0 of 1
  signal-free, parented, no stop:   wrappers finalized 0 of 1
  with a handler, no stop:          wrappers finalized 0 of 1
  a fresh embed still frames afterwards: broken false, content GtkBox
```

So no: the still-connected backstop can never be re-entered from the GC, because the state
that would allow it cannot arise. **Worth putting in the code**, because the invariant is
load-bearing and currently rests on a reader noticing two closures in different files. One
sentence on `Embed.stop`'s comment ("the wrapper cannot be finalised while this is
connected — the callback holds the driver and the driver's `on_root_widget_changed` holds
the wrapper — so disconnecting here is what *creates* the finalisable state, and it must
happen in the same call") would make it maintainable.

The fix itself is confirmed necessary. Probe C against the shipped tree:

```
== C: stopped and dropped, then more embeds (the hang the fix removed)
  stopped and dropped: wrappers finalized 10 of 10
  the next embed after the collection returned: broken false
```

and against a mutated `src/embed.ml` with only the disconnect removed, the same probe
**hangs** — killed at 120 s, having printed A and B and stalled inside C1. The defect and
its fix are both real.

### Does anything else in the library connect a dispose-time handler? No

`src/embed.ml:139` is the only `destroy` connection in `src/`, `vtree/` and `test_lib/`
(grep for `on_destroy` and `"destroy"`). Everything else the patcher connects — the
`notify::` read-backs on switch, expander, revealer, drop_down, stack, editable_label and
paned; the controllers; the connections that name a `GtkTextBuffer`, a `GtkStringList` or
an event controller — is disconnected by `Patcher.destroy` before its widget can become
collectable, and structurally could not be reached from the collector anyway: a connected
closure roots the driver, which roots the widget. The library is clean.

### N1 (Important, but not a blocker for this task). The backlog entry understates the defect: it is a memory-safety bug, not a hang

`docs/m1-backlog.md`'s new entry says a `destroy` handler reached during finalisation
"re-enters OCaml from the collector, and hangs". Measured with **no bonsai_gtk involved at
all** — plain ocgtk widgets, a handler that does nothing but count (probe A2):

```
== A2: narrowing the finalisation hazard, with no bonsai_gtk involved
  1 plain label + destroy handler             survived, handler fired 1 time(s)
  10 plain labels + destroy handlers          survived, handler fired 10 time(s)
  10 overlays + destroy handlers              survived, handler fired 10 time(s)
  10 overlays with a child + destroy handlers survived, handler fired 10 time(s)
  control: emitted by hand                    survived, handler fired 1 time(s)
  1 overlay, handler allocating 200 strings   *** Segmentation fault (core dumped) ***
```

Three runs, three segfaults, at the same case; on one run the "allocating 1 word" case
crashed too, so the threshold is not stable. The control is the same handler emitted by
hand on a widget nobody is collecting, and it is fine — so the trigger is unambiguously
the collector, and the discriminator is **whether the callback allocates**, which no
application author can be expected to reason about.

That changes what the entry is. As written it reads as a liveness bug in one library's
teardown; it is a memory-safety bug in the binding, reachable by any downstream
application that connects `destroy` and lets the widget be collected. Two consequences:

1. It belongs in **Task 14's fork work**, not only on the backlog: the marshaller should
   refuse to call back into OCaml during finalisation, or ocgtk's finaliser should defer
   the unref to an idle. Either fixes it for every consumer.
2. Until then it deserves a **library-wide rule**, in the plan's Global Constraints and in
   `signals.mli` beside the signal-lifetime rules: *never connect a handler to a signal a
   GObject's dispose can emit; if one is unavoidable, disconnect it before the widget can
   become collectable.* bonsai_gtk already obeys it — the rule is for the next widget and
   for downstream.

Not a blocker for Task 12: nothing in the library hits it, and stavekeeper connects no
`destroy` handlers today (0 hits for `on_destroy` under `lib/`), so the port is not
exposed. Recording the severity correctly is what matters.

---

## C1 — closed

The wrapper design is right and the two riders are genuinely closed (the backstop now lives
on a widget that never changes; `stop` tears down the tree that is current). Beyond the
shipped golden I checked three things it does not cover:

- **Layout transparency, reproduced independently** (probe E), in both regimes — the
  report's table only measured the alignment one:

  ```
  parented directly    halign/valign CENTER: position (196,142) size 8x16
  GtkOverlay           halign/valign CENTER: position (196,142) size 8x16
  GtkBox vertical      halign/valign CENTER: position (196,0)   size 8x16
  GtkBox horizontal    halign/valign CENTER: position (0,142)   size 8x16
  parented directly    hexpand+vexpand FILL: position (0,0) size 400x300
  GtkOverlay           hexpand+vexpand FILL: position (0,0) size 400x300
  GtkBox vertical      hexpand+vexpand FILL: position (0,0) size 400x300
  ```

  `GtkOverlay` is byte-identical to direct parenting in both; the box loses alignment on
  its orientation axis and is identical under expansion. The choice and its reasoning hold.

- **Fixups still run for the replacement tree** (probe G). A kind change into a tree
  containing a `Node.stack` with a controlled `visible_child` *and* a `stack_switcher`
  naming it: `broken false`, the stack shows page `b`, and the switcher resolved its stack
  and built its two toggle buttons. Calling `on_root_widget_changed` inside the patch guard
  and before `run_fixups` (`src/driver.ml:90-104`) is the right placement and does not
  strand the deferred work.

- **A kind change whose replacement mount raises** (probe F): driver `broken true`, the
  wrapper still holds the pre-change `GtkButton`, and `stop` afterwards returns normally.
  Sane degradation, and — a bonus from I1 — the failed replacement mount no longer strands
  anything.

## I1 — closed, with the residue correctly placed

`Patcher.mount`'s unwind mirrors `destroy` stage for stage, `release_kind` is a genuinely
shared exhaustive match, and each child helper protects only what it built (so no
double-destroy: a helper's own unwind runs before the exception reaches the caller, and the
caller's `built_*` ref is set only on success). `unregister_stack` is guarded by
`Gobject.same` and is a no-op for a kind that never registered, so `release_kind` is safe
on a partial mount. Re-measured:

```
== D: failed [create]
  200 failed creates: +1524386 live words (7621 each)
  a working embed afterwards: broken false
```

Down from 49 927 words per failure to 7 621 — a 6.5× improvement, matching the
implementer's own 50 664 → 11 136. The residue is the Bonsai/Incremental graph, not the
patcher, and the new backlog entry ("A `Driver` is never reclaimed, stopped or not") is the
right home for it with the right lever named.

## I2 — closed, and the two defects it turned up were the right ones

Both directions in one golden, with the `without stop` row proving the finaliser is a live
instrument. Reproduced independently (probe C, 10 of 10). Dropping
`on_root_widget_changed` in `Driver.stop` is correct and the mli explains why in terms of
the driver's own non-collectability, which is the honest reason.

## Minor

- **N2. `unwind` and `destroy` share only their kind tail.** `release_kind` makes the
  kind-specific half drift-proof, and the comment says so — but the four stages before it
  (slots, controllers, connections, children) are still written out twice, and those are
  the ones a future `Signals`/`Controllers` change would touch. `destroy` takes a `live`
  and `unwind` has only partial pieces, so sharing is awkward; a cross-reference comment on
  each ("keep in step with the other") is the cheap version.
- **N3. The `Controllers.release` arm of the unwind is exercised but never loaded.** The
  test raises in `require_specs`, which runs before any controller attr is applied, so the
  released `Controllers.t` is always empty. A sibling carrying `Attr.on_click` in front of
  the raising node would make the arm mean something.
- **N4. `Patcher.mount`'s "leaves nothing behind" is true of the live tree, not of the ctx
  queues.** Pending fixups and stack claims from completed children survive the raise and
  are cleared only by `abandon_fixups` — which is why the new patcher-level test has to
  call it by hand. `Driver.frame` always does, so no caller is exposed; one clause in the
  mli ("a direct patcher caller must still `abandon_fixups`") would match the code.
- **N5.** Minors M1–M5 from the first round are all taken and read correctly; the
  `examples/dune` split builds and smokes green in ci.

## Verdict

**Approved.** C1, I1 and I2 are closed and independently verified; the wrapper choice is
the right one and its layout claim reproduces; the two defects found while closing I2 were
found for the right reasons and fixed correctly. The one thing I would not leave as it
stands is **N1** — the finaliser hazard is a segfault, not a hang, it is ocgtk's rather
than this library's, and it should reach Task 14 and the Global Constraints rather than
sitting in a backlog line that describes it as a teardown inconvenience. That is a
milestone-level action, not a change to this task.
