# Task 4 review — the existential event spec, and click and focus controllers

**Commit reviewed:** `9c081e5` on `m2`, base `3ea4594` (46 files, +1772/-183).
Diff read in full (`review-3ea4594..9c081e5.diff`). Read-only review; nothing tracked
was modified.

**Gates re-run by the reviewer, all green:**

```
nix develop -c dune build                                        -> clean
nix develop -c dune test                                         -> clean
BONSAI_GTK_LIVE_TESTS=1 nix develop -c xvfb-run -a dune build @test/live/runtest
                                                                 -> clean
nix develop -c ./scripts/ci.sh                                   -> all green
```

(The one stderr line during the live run is `live_driver.ml`'s deliberate raise, as the
report says.)

---

## Summary

The mechanism is right. `Signals.spec` becomes `Read_back | Payload : ('p,'r) payload`,
the existential is closed correctly (`spec_attr` is the only projection, `connect_all`
holds a heterogeneous list without naming either parameter), and `Payload.connect`
assembles the payload *at connect time* — which is the load-bearing decision, since
`get_current_button` and `get_current_event_state` are only meaningful while the event is
current, and `src/controllers.ml:96-113` says exactly that in a comment. `fire`'s
`'r * unit Ui_effect.t option` split — synchronous decision, deferred consequence — is the
shape Task 5's key handler needs, and `declined` as spec data rather than a computed
default is correct for the same reason. All twelve M1 impls are mechanically rewrapped in
`Read_back` with no behavioural change (I diffed the widget hunks specifically for
non-mechanical edits: one comment re-indent, nothing else), and no `expected_*.txt` for
signals/controls/containers moved.

The controller lifecycle is right in the places the plan asked about. `Controllers.sync`'s
four cases (`src/controllers.ml:63-87`) attach on the first attr of a family, detach on the
last, and otherwise only re-slot and re-configure — so a rebuilt closure re-points the slot
and never duplicates a controller. The removal branch empties the slot **before**
`remove_controller`, and the attach branch adds and connects while the slots are still
empty, so an `enter` provoked by `add_controller` is inert. `Patcher.disarm` gained
`Controllers.clear` (slots without detaching) and `Patcher.destroy` gained
`Controllers.release`; I checked both `disarm` call sites (`src/patcher.ml:547`, `:613`)
and each is followed by `destroy`, so no controller is left attached with a dead slot.
`Controllers.update` sits unconditionally beside `Signals.update_slots` in `patch`
(`src/patcher.ml:518`) and after `connect_all` in `mount` (`src/patcher.ml:302-303`),
including for `Node.native`, which shares the one generic mount.

`in_patch` is applied uniformly: `dispatch` checks it first (`src/signals.ml:57`) and
`dispatch_payload` checks it first (`src/signals.ml:80`), returning `declined` there. The
three `declined` paths are each pinned by a line of `expected_signals.txt` via the new
`live_signals.ml` test, which is the best available evidence and is honestly framed (it
calls the callback `connect_all` actually built, and claims nothing about GTK routing).

Where it falls down is one thing, and it is in the part of the task the plan added rather
than the part it specified: the debugging name `Controllers` sets on every controller it
attaches is handed to `gtk_event_controller_set_static_name`, which does not copy. See
Critical C1 — it is memory-unsafe in the library proper, and it silently undermines the
live test that is the milestone's only evidence that controllers are attached and removed.

One further gap is worth fixing while the file is open: nothing ties
`Events.is_controller_attr` to the families `Controllers` actually handles, so Task 5 can
add a controller attr that is accepted everywhere and wired nowhere, with no diagnostic
(Important I1).

---

## Judgement of the testing-option claims

The report's headline says click got **option (c)** and focus got **option (a)**. Both
claims are accurate; I re-verified the premises rather than taking them.

**Click = (c), verified.** No `new_`/`alloc` appears in any `.ocgtk-src/ocgtk/src/gdk/
generated/*event*.mli` (all fifteen event subtypes are read-only wrappers);
`Gobject.Signal.emit_by_name : 'a obj -> name:string -> unit` (`common/gobject.mli:286`)
carries no arguments and returns unit; there is no `gtk_test_*` binding anywhere under
`gtk/generated/`. So no test can route a real press to a gesture, and the report says so
rather than dressing something else up as one. What actually stands behind "click works"
is the union the report names, and the union is honest:

- attach/detach and the gesture's `button`/`phase`, live — `test/live/live_controllers.ml`
  (but see C1: this evidence is built on a dangling read);
- the handler, headless — `test/handle/test_handle.ml`, "a click action carries the button
  and the modifiers", which really does exercise `Attr.on_click`'s handler with a button-2
  shift-held event and shows `b2 n1 shift=true` in the diff;
- the trampoline between them — `test/live/live_signals.ml`, which pins all three
  `declined` paths *and* the ordinary path, with the returned value printed.

The gap ("GTK routes a real press here") is written into `docs/m1-backlog.md` with its
closing condition and its compensating controls. That is what the pre-flight correction
asked for.

**Focus = (a), verified, and genuinely end to end.** Pre-flight correction 2 is applied:
`~on_window_created:(fun w -> W.Window.present (cast w))`
(`test/live/live_controllers.ml:120`), plus a `pump ()` that drains up to 50 loop
iterations after each `grab_focus`. I ran the executable directly and the handler
observations are real, not defaults: `focus into target: focus-enter`, `focus to other:
focus-leave`, and — the two that matter — `focus during a patch:` (empty, the reentrancy
guard on a real controller, which nothing else in the suite exercises) and `focus after
its attrs were dropped:` (empty, i.e. the removed controller stops firing rather than
merely being unreferenced). That last line is a behavioural assertion and it is the
strongest thing in the file; note that it survives C1 (it does not go through `is_ours`).

**Pre-flight correction 3 is applied** — `Widget.observe_controllers` is what
`live_controllers.ml:40` counts, i.e. GTK's own answer rather than this library's
bookkeeping, printed beside `Controllers.attached_count` on every line so a disagreement is
the diff. The counting is by controller *name* rather than by total, and the report's
justification is correct and checkable: a `GtkButton` really does ship with three
controllers of its own, so `N -> N+1 -> N` against a total would have had a baseline of 3
and would move with GTK releases. The assertion the plan asked for is present in a stronger
form (`gtk=(bonsai_gtk.focus bonsai_gtk.click)` -> `gtk=(bonsai_gtk.focus)` ->
`gtk=(bonsai_gtk.click)` -> both -> `after destroy: gtk=0`). The mechanism that makes the
naming possible is the defect in C1.

---

## Per-deviation judgement

| # | Deviation | Judgement |
|---|---|---|
| 1 | `src/gtk_import.mli` does not exist; additions went in the `.ml` | **Sound** — factual; the plan's file list was wrong. |
| 2 | `is_event` stays `true` for controller attrs; `Events.is_controller_attr` is a second exhaustive predicate | **Sound.** The rejected alternative (making `is_event` false) would have hidden a real distinction behind a predicate whose name does not carry it, and would have let the three attrs escape `require_specs` by accident rather than by decision. The predicate is exhaustive with no wildcard, so Task 5 cannot skip the choice. |
| 3 | `Signals.require_slots` skips controller attrs | **Sound as far as it goes.** The reason given is correct — `Controllers` builds those slots from the attr itself, so "attr present, no slot" is not reachable *for the two families that exist*. But it removes the only mount-time net over controller attrs, and nothing replaces it; see I1. |
| 4 | `sync` is polymorphic in the controller type (`(type a)` + `~upcast`) rather than storing an upcast `Event_controller.t` | **Sound**, and better than the plan's sketch: re-applying `set_button` on the already-attached path would otherwise have needed an unchecked downcast. Same four cases, same ordering. |
| 5 | `release` split into `clear` + `release` | **Sound and required.** `patcher.mli` promises pre-unparent slot-emptying for the whole subtree; `disarm` needs emptying without detaching. The mli text was updated to say "the widgets' own and their controllers'". |
| 6 | `Controllers` names every controller it attaches, and exposes `is_ours` | **Goal sound, mechanism unsound.** Counting by name instead of by total or by class is the right call and the report's reasoning is correct. `gtk_event_controller_set_static_name` is the wrong API for a runtime-computed string. See C1. |
| 7 | The live test reads the gesture's `button` and `phase` back off GTK | **Sound**, and the most valuable unasked-for addition: with no click deliverable, this is the only evidence that `~button:2` and `~phase:Capture` reach the object at all, and the only thing that would catch `Controllers` configuring the wrong object. |
| 8 | `live_signals.ml` gained the `Payload` trampoline test | **Sound.** It is the only way to reach the three `declined` paths in this binding, it exercises the real trampoline `connect_all` built (not a hand-rolled copy), and the golden prints the returned value so a wrong answer is visible rather than inferred. |
| 9 | `test_events.ml`'s coverage test rewritten rather than re-promoted | **Sound, and the right instinct.** Widening `event_names_no_kind_emits` from `()` to a three-name list is exactly the golden-widening the reviewer brief warns about. The replacement is stronger: the filter now excludes controller attrs (so a *signal* name falling out of every row still fails), a new assertion says no controller attr appears in any `for_kind` row, and a second new test asserts every controller attr is supported on every kind including `Node.native`. |
| 10 | `test_placement.ml`'s count 29 -> 32 | **Sound** — mechanical; the placement-attr list beside it, which is the load-bearing half, is unchanged. |
| 11 | Warning 30 suppressed over the declaration only, in both `.ml` and `.mli` | **Sound.** Narrow, reasoned in a comment, not added to the library flags. |
| 12 | `examples/gallery.ml` untouched | **Sound.** Not in the task's file list; the plan gives the gallery's Input section to Task 15/16, and the carry is recorded. |

---

## Critical

### C1 — every controller's debugging name is a dangling pointer into the OCaml heap, and the live test's attach/detach assertion is built on reading it

`src/controllers.ml:34-38`:

```ocaml
let name_prefix = "bonsai_gtk."

let set_name (c : W.Event_controller.t) suffix =
  W.Event_controller.set_static_name c (Some (name_prefix ^ suffix))
;;
```

with the comment "Static in GTK's sense means 'not copied', so the string must outlive the
controller; these are literals, which do."

The comment states the requirement correctly and then misidentifies the value. `name_prefix
^ suffix` is not a literal: it is a fresh, heap-allocated OCaml string, computed at
runtime, and it is unreachable the moment `set_name` returns. `bonsai_gtk.click` does not
appear in the linked binary (`strings` finds only the `bonsai_gtk.` prefix), so flambda2
does not fold it into static data.

The binding hands GTK the raw pointer — `String_option_val(v)` is
`((v) == Val_none ? NULL : String_val(Some_val(v)))`
(`.ocgtk-src/ocgtk/src/common/wrappers.h:99`) — and GTK stores it without copying:
`gtk_event_controller_set_static_name`'s GIR parameter doc is literally *"a name for
@controller, must be a static string"* (`.ocgtk-src/gir/Gtk-4.0.gir:53706`), and the
implementation assigns `priv->name = (char *)name; priv->name_is_static = TRUE;`. So from
the first minor collection onward, GTK holds a pointer to memory OCaml has reclaimed, and
`gtk_event_controller_get_name` — called by GTK Inspector, and by this library's own
`is_ours` — reads it.

**Reproduced twice, the second time through the library's own code path.** A probe that
mounts `Node.button ~attrs:[Attr.on_click ~button:2 ...]` through `Patcher.mount`, then
churns the heap (20 rounds of 100k short strings, each round followed by `Gc.compact`),
then re-reads:

```
before gc: (bonsai_gtk.click) count=1
after  gc: ()                 count=0
```

A minimal probe against the raw binding shows the corrupted bytes directly, and shows the
fix working:

```
immediately: bonsai_gtk.click
after gc:    <garbage bytes>
literal:     bonsai_gtk.literal     (* set_static_name with a true literal: survives *)
set_name:    bonsai_gtk.copied      (* set_name with a computed string: survives *)
```

**Failure scenario, concretely.** Two distinct consequences, and the second is the one that
matters for this task:

1. *In the library.* Any long-running application allocates continuously. Every controller
   this library attaches ends up with `priv->name` pointing into reclaimed OCaml heap.
   Reading it is undefined behaviour: today it yields garbage bytes, and after a compaction
   that releases a heap chunk back to the OS it is a read of unmapped memory — a segfault
   inside `gtk_event_controller_get_name`, reachable from GTK Inspector on any app built
   with this library.

2. *In the test that is supposed to catch controller leaks.* Every `gtk=` line in
   `expected_controllers.txt` is `observe_controllers` filtered by `Controllers.is_ours`,
   i.e. by that same read. Under allocation pressure the filter starts rejecting our own
   controllers. On the lines that print `bonsai=N` beside it the golden goes **red** — a
   flaky live test with no bug behind it. On the last line, `after destroy: gtk=0`, there
   is no `bonsai=` counterpart, so a garbage read makes it **pass vacuously**: the line
   cannot distinguish "the controllers were removed" from "their names became
   unreadable". That is the failure direction the assertion exists to detect. It also
   means the report's negative check (breaking `remove_controller` and watching duplicates
   accumulate) was only valid because the names happened to still be readable in that
   particular run.

**Fix.** `W.Event_controller.set_name` is bound in the same module
(`event_controller_and__...mli:28`) and `g_strdup`s its argument — one identifier, verified
safe in the probe above. Do not "fix" this by hoisting `"bonsai_gtk.click"` and
`"bonsai_gtk.focus"` to top-level literals: that happens to work for native code, where
string literals are static data, but it is not a guarantee OCaml gives, and it is false
under bytecode, where literals live in the heap and are moved by compaction.

---

## Important

### I1 — a controller attr can be accepted everywhere and wired nowhere, silently

`vtree/events.ml:39-46` (`is_controller_attr`), `src/signals.ml:182-186`
(`require_slots` skips them), `src/controllers.ml:168-193` (`update`'s two hand-written
`sync` calls).

M1's fix wave built a three-layer net so that an event attr can never be silently inert:
`require_specs` asks the table, `require_slots` asks the slots that were actually built,
and `live_events.ml` cross-checks the table against the impls. Controller attrs are
deliberately outside all three — `is_supported` short-circuits on them, `require_slots`
skips them, and `live_events.ml`'s new assertion checks only the *negative* (that no impl
declares one). Nothing checks the positive: that a name `Events.is_controller_attr` returns
`true` for is a name `Controllers.update` actually handles.

That is safe for the two families that exist, because they were added together. It stops
being safe at exactly the next task. Concretely: Task 5 must add `On_key_pressed` and
`On_key_released` to `Attr.Name.t` and to `is_controller_attr` (otherwise
`Events.is_supported` rejects them on every kind and nothing compiles past the first
test). If the third `sync` call in `Controllers.update` is then missed — a plausible miss,
since `update` is a flat sequence of two calls with no exhaustive match forcing the third —
the result is: `Attr.on_key_pressed` is accepted on every node by both the runtime and the
headless handle, `require_specs` passes, `require_slots` passes (it skips it),
`live_events.ml` passes (no impl declares it), `test_events.ml`'s "every controller attr is
supported on every kind" passes — and the handler never runs, on any widget, in any
application, with no diagnostic anywhere. That is precisely the failure mode
`require_specs` was written to eliminate, reintroduced through the door the controller
carve-out opened.

The report already notes the small version of this ("`Controllers.attached_count`'s option
list is hand-maintained"). The list of *families* has the same shape and worse
consequences.

**Fix,** cheapest first: have `Controllers.update` dispatch from an exhaustive match on
`Attr.Name.t` (a `handled : Attr.Name.t -> bool`, or a `families : (Attr.Name.t list * ...)
list` built from one), and assert in `test/test_events.ml` — or, better, at mount in
`require_slots`'s place — that `List.filter Attr.Name.all ~f:Events.is_controller_attr` is
exactly the set `Controllers` handles. Deriving `attached_count` from the same structure
closes the report's carry at the same time.

---

## Minor

- **M1. `Attr.on_focus_enter` has no documentation.** `vtree/attr.mli:381-391`: the shared
  doc comment for the focus pair is placed *before* `val on_focus_leave`, so odoc attaches
  it to `on_focus_leave` and `on_focus_enter` is documented by nothing. The task text put
  it after both vals (a trailing comment attaches to the preceding item). Move it, or
  duplicate a one-liner onto `on_focus_enter`.

- **M2. `sync`'s detach path does not honour the invariant `release` states.**
  `src/controllers.ml:65-69` empties only the removed family's slots before
  `remove_controller`, while a sibling controller on the same widget stays armed —
  whereas `release` (`:204-214`) deliberately clears *every* family first and its comment
  explains why ("one still-armed slot on a *different* controller of the same widget would
  reach Bonsai from inside teardown"). Unreachable today, because `Controllers.update` only
  runs from `Patcher.mount`/`patch`, and `Driver` wraps both in `Scheduler.with_patch_guard`
  (`src/driver.ml:61`) — but `clear_slots` exists precisely as belt-and-braces against that
  guard not being the whole story, and the two paths should not disagree. One line: `clear
  t;` at the top of the `Some a, false` branch. Relatedly, `controllers.mli:54-56` claims
  `release` and "the attr-removal path in `update`" are "the same code"; they are two
  separate hand-written sequences, and `release` unrolls the two families by hand.

- **M3. `Gtk_import.Gio` is dead.** `src/gtk_import.ml:17` adds `module Gio =
  Ocgtk_gio.Gio`, which nothing references — `live_controllers.ml` reaches for
  `Ocgtk_gio.Gio.Wrappers.List_model` directly. Not in the task's Step 6 (which named
  `Gdk_enums` and `Gdk_constants` only). `Gdk_constants` is also currently unused but is
  planned for Task 5, so it earns its place; `Gio` does not.

- **M4. Several `Click_event` doc claims have no test, and cannot have one in M2.** That
  `x`/`y` are in the widget's own coordinates, that `n_press` counts up within a
  multi-click, that `~button:0` means "any", and `on_click`'s "the gesture does not claim
  the event sequence" are all unexercised — the last is verifiable only by the absence of a
  `set_state`/claim call, which I confirmed. This is the acknowledged option-(c) gap rather
  than a new omission; noting it so the backlog entry's scope is understood to cover the
  documented semantics, not just "a press arrives".

- **M5. Partial removal within the focus family is untested.** The live test only ever adds
  or drops both focus attrs together, so the `Some a, true` path with one of the two slots
  going empty (drop `on_focus_enter`, keep `on_focus_leave`) is never exercised. It is a
  plain `update_slots` and almost certainly right; a third line in the existing sequence
  would pin it.

- **M6. The controller callback captures a widget it never uses.** `Signals.connect_all`
  passes `w` into both trampolines, and both controller specs ignore it (`fun _w ...`), so
  each controller's GClosure holds an OCaml root on the widget's wrapper — a second
  GObject/OCaml reference cycle per controller, on top of the one M1's own signal handlers
  already create. It is broken correctly by `release`/`sync`'s `disconnect`, so nothing
  leaks today; it is another reason the backlog's still-unwritten
  "remove a keyed child, `Gc.full_major`, assert the widget was finalized" test matters.
  Changing `connect_all`'s signature is out of scope here.

---

## Out of scope (already carried, no action in this task)

The report's four carries are all correctly placed: the README Limitations sentence
`Attr.on_click`'s doc promises (Task 15), the gallery Input section exercising
`Attr.on_click` (Task 15/16), the absence of a `~phase` on `Attr.on_focus_*`, and the
end-to-end click/key gap in `docs/m1-backlog.md`. The backlog entry is written out properly
— what is covered where, what is not, what would close it — rather than as a one-line
placeholder.

---

## Verdict

**Needs fixes.**

One Critical (C1 — `set_static_name` with a computed string: undefined behaviour in the
library, and it hollows out the live test that is this task's headline evidence; the fix is
`set_name`) and one Important (I1 — nothing ties `Events.is_controller_attr` to the
families `Controllers` handles, and Task 5 is the task that will trip on it).

Everything else in the task is in good shape: the existential spec is correctly closed and
correctly documented, the M1 read-back path is unchanged for all twelve existing widgets,
the `in_patch` guard and the exception guard are applied on both arms with all three
`declined` paths pinned by a real test, the controller attach/detach/re-point/release
ordering is right and reaches every mount and teardown path, and the two testing-option
claims in the report are accurate — I re-verified the binding facts behind both rather
than taking them on trust.

---

# Re-review — fix round 1 (`328ca80`)

Scoped to `git diff 9c081e5..328ca80` (8 files, +400/-101) against the findings above.
Read-only; the one mutation experiment was done in a throwaway worktree at `328ca80`,
which has been removed (`git worktree remove` + `prune`; the tree is clean).

**Gate re-run by the reviewer:** `nix develop -c ./scripts/ci.sh` -> `all green`.

## C1 — closed

**No `set_static_name` call remains.** `grep -rn set_static_name src/ vtree/ test/ test_lib/
examples/ docs/` returns three hits and all three are prose: the explanatory comment at
`src/controllers.ml:32` and two in `test/live/live_controllers.ml` (`:60`, `:118-120`)
naming the bug the regression pins. The call site is now
`W.Event_controller.set_name c (Some (name_prefix ^ suffix))` (`src/controllers.ml:46`),
which is the `g_strdup`-ing GTK function. The rewritten comment is correct, including the
part that matters most for the next reader: it says explicitly that hoisting the names to
top-level literals is *not* the alternative fix, and gives the bytecode reason.

**The churn test really is a gate — verified by mutation, not by reasoning.** In the
worktree I restored `set_static_name` (one `sed`, nothing else) and ran
`live_controllers.exe`:

```
before gc: gtk=(bonsai_gtk.focus bonsai_gtk.click) bonsai=2 total=3
after gc:  gtk=()                                  bonsai=2 total=3
after gc:  no gesture of ours
```

against a golden that requires the names to be unchanged and `button=2 phase=BUBBLE`.
Three diff lines, so the `(diff expected_controllers.txt output_controllers.txt)` rule
fails. The design of the case is right on two counts I checked specifically: it runs
**first** in the file (a separate `let () = GMain.init ...` was hoisted to make that
possible), before every assertion that reads a name — so the file can no longer be
hollowed out from underneath by the very bug it is meant to catch; and it mounts a
`Node.label`, which emits no signal and ships with no controllers of its own, so
`total=3` is unambiguous. That `total=3` is unchanged across the failing run is the
diagnosis rather than the symptom: it says the controllers are still attached and only
their names went bad.

**`after destroy` is no longer vacuous.** `controllers` gained an unfiltered `total=`
column that does not go through `get_name`, and the destroy is bracketed:
`before destroy: ... total=5` -> `after destroy: gtk=() total=3`. The `5 -> 3` holds
whatever happens to the names, and the `GtkButton`'s own three controllers are now in the
golden rather than in a comment, which is what makes the case for name-filtering legible.
Both options from the ruling were taken; that was the right call, they cost a line each.

## I1 — closed

`Events.Family.t = Click | Focus` with `controller_family : Attr.Name.t -> Family.t
option` exhaustive over `Attr.Name.t` with no wildcard (`vtree/events.ml:60-95`).
`is_controller_attr` is now `Option.is_some (controller_family name)` and `family_attrs`
is filtered out of `Attr.Name.all`, so **the table is the only place a controller attr is
classified** — I checked for a second classifier and there is none: no `On_click` /
`On_focus_*` name is spelled anywhere in `src/controllers.ml` any more (`wanted` asks
`Events.family_attrs`), `Signals.require_slots` still calls `Events.is_controller_attr`,
and `Events.is_supported` short-circuits through the same predicate.

**The compile-error link is real — verified by mutation.** Adding `| Key` to `Family.t` in
the worktree produces exactly three hard errors, and nothing else has to be touched to get
them:

```
File "src/controllers.ml", lines 62-64:   Error (warning 8 [partial-match])   (* attached *)
File "src/controllers.ml", lines 215-241: Error (warning 8 [partial-match])   (* update   *)
File "src/controllers.ml", lines 260-266: Error (warning 8 [partial-match])   (* release  *)
```

The report says "four places"; it is three, because `clear` and `attached_count` are both
derived from `attached` rather than matching themselves. That is better than the claim,
not worse — and `attached_count`'s hand-maintained option list, the report's own carry
from round one, is gone with it.

The positive half is the sweep in `live_controllers.ml:193-230`: one `(name, attr)` row
per controller attr, `assert`ed complete against
`List.filter Attr.Name.all ~f:Events.is_controller_attr` (an abort, so a missing row kills
the executable), then a mount-per-row on a `Node.label` printing family and attached
names. So the three doors named in the report really are all shut, and the golden pins the
name->family mapping for free (`On_focus_leave` misrouted to `Click` would print
`attached=(bonsai_gtk.click)`).

I accept the argument for not putting the check in `require_slots`' place: answering "did
this family attach" per mount means either exporting more of `Controllers` onto a hot path
or duplicating the family table in `src/`, and the compile error is what carries the weight
for the case the finding was actually about.

## Minors

M1, M3, M5 fixed as described and verified in the diff: both focus attrs now carry their
own doc comment (and `on_focus_enter`'s keeps the "or any of its children" sense);
`Gtk_import.Gio` is gone and `Gdk_constants` correctly kept; the live test now drops
`on_focus_enter` alone and shows the controller staying attached with one slot emptied
(`on_focus_enter alone dropped: gtk=(bonsai_gtk.focus) bonsai=1 total=4`, then `focus in
and out with only on_focus_leave: focus-leave` — focusing in fires nothing, out fires
once). M4 and M6 are argued rather than changed; both arguments are correct and I have
nothing to add to either.

M2 was fixed as I suggested, and my suggestion was wrong. See N1.

## New — Important

### N1 — removing one controller family disarms every family that sorts before it, for the rest of the frame

`src/controllers.ml:95-106` (the `Some a, false` branch of `sync`) and `:212-241`
(`update`).

The M2 fix replaced `Signals.clear_slots a.slots` with `clear t`, which empties **every**
family's slots. That is right in `release`, where nothing is re-armed afterwards. It is
wrong inside `update`'s per-family loop, because `update` iterates
`List.iter Events.Family.all` and each family's `sync` is the only thing that re-arms that
family. So a family removed at iteration *i* wipes the slots of every family already
processed at iterations `< i`, and nothing re-arms them until the next patch of that node.

I proposed exactly this one-line change without noticing the interaction with the loop, so
this one is on me.

**Failure scenario, and I reproduced it.** In a worktree I flipped `Family.t` to
`Focus | Click` — a pure ordering change, no logic touched — so that the victim becomes the
family whose handlers a test can actually observe, and ran a probe that mounts a button
carrying `on_click` + `on_focus_enter` + `on_focus_leave`, then patches **dropping only
`on_click`** (the focus attrs are byte-identical across the frame):

```
Family.all = (Focus Click)
baseline (click+focus present):                              [enter,leave]
after dropping on_click only  <-- focus attrs never changed: []
one more no-op frame later:                                  [enter,leave]
```

Control, same probe, same commit, shipped order restored:

```
Family.all = (Click Focus)
baseline (click+focus present):                              [enter,leave]
after dropping on_click only  <-- focus attrs never changed: [enter,leave]
one more no-op frame later:                                  [enter,leave]
```

So the defect is in the shipped code; only the ordering decides who it lands on.

**Who it lands on today, and why no test sees it.** With `Click | Focus`, the frame that
triggers it is one that drops the *focus* attrs while keeping `on_click` — and the victim
is the click slot, which no test in this repo can observe, because there is no synthetic
click. The live test walks straight through the case:
`focus attrs dropped, click back` patches from (click absent, focus present) to (click
present, focus absent), so `Click`'s `sync` attaches and arms the gesture and then
`Focus`'s `sync` calls `clear t` and empties it again. The golden's next line is a focus
assertion, so nothing notices. A user middle-clicking that widget between that frame and
the next render gets nothing.

**Why it gets worse in Task 5.** `Key` will be appended to `Family.t`, so
`Family.all = [Click; Focus; Key]`. A frame that drops `Attr.on_key_pressed` while keeping
a click or focus handler then disarms both of them — and focus *is* observable, so this
stops being a silent bug and starts being a live-test failure whose cause is three files
away from the change that provoked it.

**Fix.** Hoist the emptying out of the per-family branch so it happens once, before any
`sync` runs — then every surviving family is re-armed by its own `update_slots` regardless
of order:

```ocaml
let update t attrs =
  (* Before any family is touched, and for the reason [release] gives: [remove_controller]
     can provoke a leave or a cancel, and a still-armed slot on a sibling controller would
     reach Bonsai from inside it. Once, up front, rather than inside a branch -- each
     family's [sync] re-arms its own slots below, and a [clear] in the middle of the loop
     would undo the ones already done. *)
  if List.exists Events.Family.all ~f:(fun f ->
       Option.is_some (attached t f) && not (wanted attrs f))
  then clear t;
  List.iter Events.Family.all ~f:(fun family -> ... (* sync, no [clear t] in its branches *))
;;
```

(An unconditional `clear t` at the top of `update` works too and is simpler to state; it
costs one extra walk of at most three short assoc lists per patched node per frame, and it
makes the invariant hold without a condition to get wrong. Either is fine — the load-bearing
part is that the emptying stops happening *between* two families' `sync` calls.) `sync`'s
`Some a, false` branch then goes back to `Signals.clear_slots a.slots`, or to nothing at
all, since `update` has already emptied everything; `release` keeps its own `clear t`
unchanged.

Worth adding a line to the live test that would have caught it: after the
`focus attrs dropped, click back` frame the golden already prints a focus drain
(`focus after its attrs were dropped:`); the symmetric case for the family that *stayed*
needs the click slot, which is unobservable — so the honest test is the one I ran, i.e. an
ordering-independent assertion. The cheapest is to make the `on_focus_enter alone dropped`
sequence also drop a *whole other family* in the same frame and then check the focus
handlers still fire.

## Verdict

**Needs fixes** — one new Important (N1), introduced by the M2 fix and not caught by the
suite.

C1 and I1 are both properly closed, and closed with real gates rather than assertions about
gates: I mutated the code back in both cases and watched the golden fail (C1) and the
compiler refuse (I1). Every Minor is either fixed or argued down correctly. Nothing else in
the round regressed — `ci.sh` is green, the widget impls, `Signals`, `Patcher`, `test_lib`
and the headless suite are untouched by this diff, and the goldens that moved
(`expected_controllers.txt`) moved only where the report says.

N1 is a small, contained change to one function, and re-review of it should be a matter of
reading `update` and re-running the live suite.

---

# Re-review 2 — fix round 2 (`93c819c`)

Scoped to `git diff 328ca80..93c819c` (6 files, +217/-24) against N1 alone. Read-only;
the mutation experiments were run in a throwaway worktree at `93c819c`, since removed
(`git worktree remove` + `prune`, `git worktree list` shows only the main checkout, tree
clean).

**Gates re-run by the reviewer:** `./scripts/ci.sh` -> `all green`; the live suite run
three times with `--force` -> exit 0 each time (the new `n1 focus from presenting the
window: focus-enter` line depends on GTK focusing the first focusable child on `present`,
so I checked it for flakiness specifically; it is stable).

## N1 — closed

The new order of operations in `update` (`src/controllers.ml:221-245`) is:

```
clear t                                  (* every attached family's slots -> None *)
for family in Events.Family.all:
  None,false -> ()
  Some,false -> clear_slots a.slots      (* already empty; idempotent *)
                disconnect; remove_controller; set None
  Some,true  -> configure; update_slots  (* re-arms *)
  None,true  -> make; set_name; configure; add_controller;
                connect_all; update_slots (* armed *)
```

and `sync`'s removal branch is back to `Signals.clear_slots a.slots`
(`src/controllers.ml:104-121`). That is the shape I sketched, in its unconditional
variant, which my own finding named as acceptable — so the report's offer to fall back to
the "literal ruling" (branch-only, no hoist) should be declined. Its reasoning is right and
better than mine: branch-only fixes N1 but hands Minor M2 back, because nothing would then
guarantee that no sibling slot is armed while `gtk_widget_remove_controller` runs. The
hoist holds both properties at once, and it is the hoist rather than the branch that makes
the result ordering-independent.

**Verified by mutation, all four corners.** I reverted `controllers.ml` to the round-1
shape (hoist deleted, `clear t` back in the removal branch) and independently flipped
`Events.Family.t` to `Focus | Click`, and ran `live_controllers.exe`:

| code | `Family.all` | direction 1 (drop click, keep focus) | direction 2 (drop focus, keep click) |
|---|---|---|---|
| round 1 | `Click; Focus` (shipped) | passes | **fails** — `armed=()` |
| round 1 | `Focus; Click` | **fails** — `armed=()`, focus silent | passes |
| round 2 | `Click; Focus` | passes | passes |
| round 2 | `Focus; Click` | passes | passes |

Concretely, round-1 code on the shipped ordering prints

```
n1 focus family dropped: gtk=(bonsai_gtk.click) bonsai=1 total=4 armed=()
```

against a golden requiring `armed=(On_click)` — a diff, so the `(diff expected_controllers
.txt output_controllers.txt)` rule fails. And round-1 code on the flipped ordering prints

```
n1 click family dropped: ... armed=()
n1 focus in the same frame that dropped on_click:
```

i.e. the other direction catches it there. So the test genuinely fails on the round-1 code
under either ordering, via one direction or the other, and both directions pass on the
round-2 code under either ordering. That is the ordering-independence the fix claims, and
it is the property that matters when Task 5 appends `Key`.

**The report's correction to my framing is right and I accept it.** I wrote that the
shipped-order victim was "the click slot, which no test in this repo can observe". Accurate
about the tests as they stood, but the *frame* was already in the golden — `focus attrs
dropped, click back` is exactly the drop-focus-keep-click transition — so the defect was
live on the shipped ordering on a line the suite already walked through, and only the means
of looking at it was missing. My own mutation run reproduces that same transition as
`armed=()`. "Worse than described" is the correct characterisation.

**`Signals.armed` / `Controllers.armed` are the right instrument.** `Signals.armed`
(`src/signals.ml:128-134`) filters the slots that hold an attr and sorts by
`Attr.Name.compare`, so the golden pins the set rather than `connect_all`'s prepend order;
`Controllers.armed` folds it across the attached families through the existing
`Events.Family.t` match, so it grows with the variant rather than beside it. Both are
documented as test introspection and both sit under `Private`, alongside `attached_count`
and `is_ours`. This was the better of the two options in the ruling: it observes the slot
itself rather than the trampoline, which is the thing N1 was about.

It also pays for itself immediately elsewhere in the golden. `before gc: ... armed=(On_click
On_focus_enter)` on a node carrying only those two attrs pins something nothing else did —
that the focus controller connects both of its specs but leaves `On_focus_leave`'s slot
empty when the attr is absent — and `mounted other: ... armed=()` pins the negative.

## The two questions asked

**Can a family that is present but unchanged lose its slot between the clear and its sync?**
Transiently yes, and that is the point rather than a defect: between `clear t` and its own
`sync`, a surviving family's slots are empty, and that window spans every earlier family's
`add_controller` / `remove_controller` / `configure`. Anything GTK emits into it is inert,
which is precisely the M2 invariant. It cannot leak past the end of `update`, because every
surviving family's own branch (`Some,true` and `None,true` alike) ends in `update_slots`.

The one way it becomes permanent is an exception thrown by an earlier family's `sync` —
`Gesture_click.new_`, `add_controller`, or `configure` raising — which would leave later
families disarmed. That is not reachable as a live-but-inert state: the exception propagates
out of `Patcher.patch`, and a frame that raises stops the driver for good (spec §11,
`Driver.broken`), so nothing renders into that tree again. No action; noting it because it
is the only path I could find and it is closed by something outside this file.

**Is the "unchanged closure" fast path still re-arming?** Yes, at both levels, and I checked
both rather than assuming: `Patcher.patch` still calls `Controllers.update` unconditionally
in the same-kind branch (`src/patcher.ml:521` — `patcher.ml` is untouched by this diff), and
`sync`'s `Some a, true` branch calls `Signals.update_slots` unconditionally, with no
attr-equality guard. So a node whose closures are physically unchanged is cleared and
re-armed on every frame, which is correct. `reassert_only` correctly does not touch
controllers at all — a `clear` there without a following `update` would leave slots empty.

## Minor — no action needed, noted for the file

- **The coupling is now load-bearing and only half-documented.** `update`'s unconditional
  `clear t` is safe *only* because `sync`'s `Some a, true` branch re-arms unconditionally.
  A future "skip `update_slots` when the attrs are physically equal" optimisation in either
  place would reintroduce N1 in a worse form — every controller slot on every node empty on
  every frame. `update`'s comment says "each surviving family's own [update_slots], below,
  re-arms it", which states the dependency from one side; the `Some a, true` branch has
  nothing saying it must not become conditional. A one-line comment there would close it.

- **`expected_controllers.txt` has a cosmetic dependence on `Family.all` order** — the
  `gtk=` name lists follow attach order, so flipping the variant reorders them even though
  every `armed=` assertion holds. Appending `Key` will not disturb `Click`/`Focus`, so
  nothing to do; worth knowing before anyone reorders the variant for tidiness.

## Verdict

**Approved.**

N1 is closed by the right mechanism, with both invariants held simultaneously rather than
traded off, and it is closed with a test I confirmed fails on the previous code — under
either family ordering, which is what makes it a guard for Task 5 rather than for this
frame's arrangement. The instrument the fix adds (`Signals.armed` / `Controllers.armed`) is
the smallest thing that could have seen the bug and immediately pins two other facts the
suite was asserting only by implication.

Nothing else regressed: `patcher.ml`, `vtree/`, the widget impls, `test_lib/` and the
headless suite are untouched by this diff, the goldens moved only where a column was added
or an N1 line inserted, `ci.sh` is green, and three consecutive live runs are stable.

Task 4 is done from my side: C1, I1, N1 and every Minor are resolved or argued down, and
the carries (README Limitations, the gallery Input section, the end-to-end click/key gap
with its closing condition, the focus `~phase` asymmetry) are recorded where the later
tasks will find them.
