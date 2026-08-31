# M2 final whole-branch review — core lens

Scope: `86224d9..f06a615`, package `final-core.diff` (`vtree/` tables and `Attr`, `src/`'s
signals, controllers, patcher, driver, embed, scheduler, widget_impl, attr_apply,
child_keys, and the public mlis). Read at HEAD, cross-checked against `final-docs.diff`,
the plan's Global Constraints + addendum, `progress.md`, and `docs/m2-backlog.md`. No
tracked file was modified; no build was run.

## Summary

The M2 core machinery holds up under a whole-branch read. The three shared tables
(`Events.for_kind`, `Events.controller_family`, `Placement.reader`) are each exhaustive
with no wildcard, each derived rather than duplicated where a second reader exists
(`is_controller_attr`, `family_attrs`, `Placement.names`), and each backed by a check that
fires when they drift from the impls — `Signals.require_slots` unconditionally at mount,
`live_events.ml` under the live gate, `test_placement.ml` for the placement pair's
inverse. The `Attr.Private` seam does what the ledger claims: every consumer coerces
explicitly, and no path reconstructs an `Attr.t` from a matched constructor.
`Controllers`' clear-once ordering is correct under all three of its callers (`update`,
`release`, and the patcher's `disarm`), and the `Payload` trampoline's `declined` discipline
is right on all three of its paths. `enqueue_fixups` is reached identically from
`note_interest` and from `reassert_only`, and `Children.iteri` spells paths the same way
`mount`/`patch` do, so a fixup's diagnostic names the node the walk would have named.
The finaliser-guard rule that `signals.mli` states is observed library-wide: `src/embed.ml`
holds the only `destroy` connection in `src/`, `vtree/` and `test_lib/` (verified by grep
over `on_destroy`/`on_unrealize`/`"destroy"`), and `Embed.stop` disconnects it in the same
call that makes the wrapper collectable.

Two code findings, both about exception paths, and both are consequences of *pairs* of
tasks rather than of any one:

- Task 3 moved stack registration out of the walk into a pass-level `apply_stack_claims`,
  and Task 12 then made `mount` exception-safe and wrote that guarantee into
  `patcher.mli`. `apply_stack_claims` runs *outside* `mount`'s try, so the one rejection it
  raises — two `Node.stack`s with one name — escapes the guarantee entirely, and under
  `Bonsai_gtk.start` it escapes it after `on_window_created` has already presented the
  window. (I1)
- `Patcher.destroy` is `mount`'s mirror and was not given the same treatment, so a raise
  from the one place teardown calls application code (`Native_gtk.destroy_payload`) strands
  the dying subtree's siblings connected and armed, and aborts `Driver.stop` before
  `abandon_fixups` and `invalidate_observers`. (I2)

Two documentation findings in public mlis are wrong rather than merely thin, and both are
the *same defect the branch already fixed once elsewhere*: `events.mli` enumerates three of
the five controller attrs (Task 5 added `Key` to the table and not to the sentence), which
is the identical "three where N ship" shape Task 15's I1 caught in `signals.mli` and spec
§6.4; and `Attr.widget_name`'s doc still explains its lossy `Unset` by a property of ocgtk
that commit `3a87d1c` on this same branch removed. (I3, I4)

Nothing found in: the `Attr.Private` seal, the `in_patch` guard, `Signals`' two
trampolines, `Controllers`' attach/detach ordering, `Scheduler`'s broken/stopped state
machine, `Embed`'s wrapper rationale and backstop lifecycle, `Reconcile`'s ordered/unordered
split, or the `ctx.report` memos, whose four implementations are the same shape and whose
one intentional difference (`W_drop_down.forget_refusal`, because a drop-down's refusal is
about an index *relative to the items* and the other three refusals are pure) is the right
one.

Verdict below: **Needs fixes** — I1 and I2 are small, local code changes; I3 and I4 are
one-sentence doc corrections in mlis an application reads.

## Critical

None.

## Important

### I1. `apply_stack_claims` raises outside `mount`'s exception-safe region, orphaning the whole tree — and under `start`, after the window has been presented

`src/patcher.ml:986-990`:

```ocaml
let mount ctx ~path ~is_root node =
  let live = mount ctx ~path ~is_root ~parent_kind:None node in
  apply_stack_claims ctx;
  live
;;
```

The inner `mount` (`src/patcher.ml:454-520`) is exception-safe: it unwinds everything it
built and re-raises. `apply_stack_claims` (`src/patcher.ml:91-99`) is *outside* that, and
its take loop calls `register_stack` (`:46-50`), which raises `Invalid_argument` —
`"%s: two Node.stacks are named %S in one tree"` — when a name is already held. When it
does, `live` is a fully built, fully connected tree that no one holds a reference to.

Failure scenario, first frame, `Bonsai_gtk.start`:

1. The view contains two `Node.stack ~name:"nav"` (an ordinary application mistake — a
   panel factory reused, a sidebar duplicated across two branches of a `match`).
2. `Bonsai_gtk_test` cannot catch it: `test_lib/bonsai_gtk_test.ml` has no stack handling
   at all (grep for `stack` returns nothing), so a fully green headless suite ships it.
3. The recursive `mount` completes. For the root `Node.window`, `note_interest`
   (`src/patcher.ml:513`, then `:310-314`) has already called `ctx.on_window_created`,
   which under `Loop.start` is `Application.add_window` + `Window.present`
   (`src/loop.ml:22-26`). **The window is on screen and owned by the `GtkApplication`.**
4. `apply_stack_claims` raises. `Driver.frame` catches, marks broken, calls
   `abandon_fixups`, re-raises (`src/driver.ml:148-154`). `t.root` was never assigned
   (`src/driver.ml:103-106` assigns only on the successful return), so `Driver.stop` has
   nothing to walk.
5. Result: `run` does not return, because the application still owns a presented window.
   The user sees a fully rendered window that will never update again — every handler still
   connected, `broken` true, nothing patching. `start` eventually returns
   `startup_failure_status`, but only when the user closes it.
6. And the tree is permanently unreclaimable, by exactly the argument `src/patcher.ml:431-438`
   makes for the case it *did* fix: every connected signal roots a GClosure that captures
   the widget wrapper and `ctx.signals`, whose `schedule`/`in_patch` close over the driver,
   which holds the Bonsai graph. Measured there at ~50k live words for a mount that had
   connected *one* handler; here it is the whole tree.

Under `Expert.embed` the same path is the leak without the window: `Embed.create`'s
`| exception exn -> Driver.stop driver; reraise` (`src/embed.ml:124-129`) walks `t.root`,
which is `None`.

The mli promises the opposite in two places. `src/patcher.mli:149-154`: *"**Exception-safe.**
Whichever of those raises, everything this call had already built is torn down first … So a
failed mount leaves nothing behind and the caller may not assume a partial `live` to clean
up; there is none"*. And `src/embed.mli:106-110`: *"Raises whatever that first frame raises …
having first torn down whatever the failed mount had built (`Patcher.mount` is
exception-safe)"*. The carve-out at `patcher.mli:162-167` is explicitly about `ctx` (fixups
and claims), not about the live tree, so it does not cover this.

This is new on the branch as a *hole in a guarantee*: before M2, `register_stack` ran inside
`note_interest` inside the walk (`git show 86224d9:src/patcher.ml:155,166,170`), so the
rejection was inside whatever unwinding existed. Task 3 moved it out; Task 12 then wrote the
guarantee. Neither task could see the interaction on its own.

Fix (small, local): give the wrapper the same shape the walk has —

```ocaml
let mount ctx ~path ~is_root node =
  let live = mount ctx ~path ~is_root ~parent_kind:None node in
  (match apply_stack_claims ctx with
   | () -> ()
   | exception exn ->
     let backtrace = Stdlib.Printexc.get_raw_backtrace () in
     destroy ctx live;
     Stdlib.Printexc.raise_with_backtrace exn backtrace);
  live
;;
```

`destroy` on a `Window` root runs `W.Window.destroy` (`src/patcher.ml:381`), which is what
takes the presented window back off screen and lets `run` return — so the same three lines
close both halves. The `patch` wrapper (`:992-996`) does **not** need this: it mutates
`live` in place and `t.root` still points at it, so `Driver.stop` can reach it.

Also worth adding while there: `patcher.mli`'s `mount` Raises list (`:135-143`) never
mentions the duplicate-stack-name rejection at all, and `ctx.stacks`' own doc (`:30`) says
*"Two stacks with one name is `Invalid_argument`"* without saying which call raises it. See
M2 below.

Severity: Important. It is not memory-unsafe and the frame is dead either way, but a plain
application mistake produces a frozen-but-live window plus a permanent leak of the driver,
which is precisely the failure mode Task 12's work exists to prevent and which two mlis
promise cannot happen. A reviewer who weighs "a presented window that never updates" the way
spec §11 weighs silent inertness could reasonably call this Critical.

### I2. `Patcher.destroy` is not exception-safe, and it is `mount`'s mirror

`src/patcher.ml:647-660`:

```ocaml
and destroy ctx (live : live) =
  Signals.clear_slots live.slots;
  Controllers.release live.controllers;
  Signals.disconnect live.connections;
  Children.iter live.children ~f:(destroy ctx);
  release_kind ctx ~kind:live.node.kind ~widget:live.widget
```

Nothing here protects a stage from the one before it, and `release_kind`'s `Native` arm
(`:383`) calls `Native_gtk.destroy_payload`, which is *application code* — plus, by its own
contract, raises `Invalid_argument` on a payload not built by `Native.node`
(`src/native_gtk.mli:66-71`). `Native.S.destroy`'s doc (`src/native_gtk.mli:28-34`) says what
an implementation may not *do*; it never says it may not raise.

Failure scenarios:

- **Mid-frame.** `patch_list`'s `Remove` arm (`src/patcher.ml:840-845`) does
  `disarm l; ops.remove parent l.widget; destroy ctx l`. If the third child of a dying
  subtree has a `Native` node whose `destroy` raises, children four onward are never
  reached: their `Signals.connections` stay connected and their `Controllers` stay attached
  to widgets GTK has already unparented. `disarm` ran first, so their slots are empty and
  nothing can reach Bonsai — but they are now permanently rooted GClosures on detached
  widgets, the same cycle I1 describes.
- **`Driver.stop`** (`src/driver.ml:229-252`). `t.stopped <- true` and `Scheduler.stop`
  have run; `Patcher.destroy` raises part-way; `t.root <- None`, `Patcher.abandon_fixups`
  and `Bonsai_driver.Expert.invalidate_observers` are all skipped, and the exception escapes
  to the caller. `Driver.root_widget` still answers `Some` for a half-destroyed tree, and
  the deferred closures of the last pass are still holding its widgets.
- **`Embed.stop`** (`src/embed.ml:20-51`). `Driver.stop` raises, so
  `Overlay.set_child t.wrapper None` and the backstop disconnect never run. The wrapper is
  left holding the tree with a `destroy` handler still connected — the configuration the
  same function's comment calls *"actively unsafe"*. It is not actually unsafe here (a
  connected backstop is exactly what makes the wrapper un-finalisable, so the re-entry
  cannot happen), and a second `Embed.stop` heals it because `Driver.stop` is now a no-op
  and the remaining two steps run. But "call `stop` again after it threw" is not a contract
  `embed.mli` states.

`mount` was given per-stage unwinding and per-loop guards in Task 12 (`:470-476`, `:561-587`,
`:605-626`) precisely because a half-done tree strands GClosures. `destroy` does the same
four stages in the same order over the same objects and got none of it. The asymmetry only
shows on a whole-branch read, because Task 12's brief was the mount path.

Fix: make the walk complete and re-raise the first exception, rather than swallowing or
abandoning. The cheapest shape that keeps the ordering guarantees intact is to collect:

```ocaml
and destroy ctx (live : live) =
  let first = ref None in
  let step f = try f () with exn -> if Option.is_none !first then first := Some exn in
  step (fun () -> Signals.clear_slots live.slots);
  step (fun () -> Controllers.release live.controllers);
  step (fun () -> Signals.disconnect live.connections);
  Children.iter live.children ~f:(fun c -> step (fun () -> destroy ctx c));
  step (fun () -> release_kind ctx ~kind:live.node.kind ~widget:live.widget);
  Option.iter !first ~f:raise
```

and, independently, have `Driver.stop` reach `abandon_fixups` /`invalidate_observers` and
`Embed.stop` reach its two trailing steps whatever `destroy` did (an `Exn.protect
~finally`). Whichever is taken, `native_gtk.mli`'s `destroy` doc should say what happens if
it raises.

Severity: Important. Reachability is narrow — it needs a `Native` impl whose `destroy`
raises, which is application code in the documented escape hatch — but the consequence is
the leak class Task 12 spent a task closing, and `Driver.stop` silently not invalidating its
observers is exactly the "a driver per dialog grows without bound" item already on the
backlog under *Plumbing / hygiene*.

### I3. `vtree/events.mli` names three of the five controller attrs — the defect Task 15's I1 fixed in `signals.mli` and not here

`vtree/events.mli:57-60`:

```
(** [true] for the event attrs {!controller_family} gives a family, derived from it so the
    two cannot disagree: {!Attr.on_click}, {!Attr.on_focus_enter}, {!Attr.on_focus_leave}.
```

`Events.controller_family` (`vtree/events.ml:109-112`) gives a family to **five** names:
`On_click`, `On_focus_enter`, `On_focus_leave`, `On_key_pressed`, `On_key_released`.

The sentence was written in `9c081e5` (Task 4, before the `Key` family existed). `7ba161a`
(Task 5) added `Key` to `Family.t` and to `controller_family` — and touched
`vtree/events.mli` in the same commit, without updating this list. The doc's own phrase
*"derived from it so the two cannot disagree"* is true of the code and false of the sentence
sitting beside it, which is the worst version of this: a reader checking whether keys are
controller attrs is told, in the file that decides it, that they are not.

This is the same shape as Task 15's I1 — spec §6.4 and `signals.mli:76` claimed three
`Payload` signals where six ship — which Task 16 fixed by *deriving* the claim ("child-widget
arguments + controller signals") rather than re-listing. That fix did not sweep for the twin
one file over.

Second instance, same cause, in `src/patcher.mli:109-111`:

```
  ; controllers : Controllers.t
  (** The event controllers this node's attributes ask for — a [GtkGestureClick] for
      {!Bonsai_gtk_vtree.Attr.on_click], a [GtkEventControllerFocus] for the focus pair.
```

No `GtkEventControllerKey`, though `Controllers.t` has had a `key` field since Task 5
(`src/controllers.ml:21`). (The `{!…on_click]` there is also a malformed odoc reference —
opened with `{!`, closed with `]` — so it renders as literal text; see M7.)

Fix: state the rule rather than the list, as Task 16 did for `Payload` — "the attrs
`controller_family` gives a family: today the click gesture, the focus pair and the key
pair" — or, better, drop the enumeration and point at `controller_family`, which is the
table and is exhaustive.

Severity: Important. It is documentation only, but it is a public `vtree` mli, it is
*wrong* rather than incomplete, and the branch already ruled that this exact defect class
gets fixed by derivation.

### I4. `Attr.widget_name`'s documented reason was removed by this branch's own pin bump

`vtree/attr.mli:236-245`:

```
    Dropping this attribute is the one [Unset] that is not exact: ocgtk's [set_name] takes
    a [string], not a [string option], so there is no way to pass NULL and restore "this
    widget has no name". … a NULL-accepting [set_name] in the ocgtk fork would remove the
    caveat.
```

and the same claim in `src/attr_apply.ml:24-26`.

The fork has had a NULL-accepting `set_name` since `3a87d1c` on this branch, and the
library already passes an option through it — `src/attr_apply.ml:99`
(`Widget.set_name w (Some s)`), `:168` (`Widget.set_name w (Some d.widget_name)`), and
`src/controllers.ml:48` (`Event_controller.set_name c (Some (name_prefix ^ suffix))`). The
backlog itself lists this under *Closed during M2*: *"ocgtk fork: `Widget.set_name : t ->
string option -> unit` — landed … and pinned"*.

The **behaviour** is unchanged deliberately (backlog, *Do first in M3*: the behavioural half
is not taken, `Unset Widget_name` still writes `Some d.widget_name`), and that decision is
fine. What is wrong is the stated *reason*: the mli tells an application that the caveat
exists because the binding cannot express NULL, when the binding can and the library chooses
not to. A reader who wants the caveat gone is sent to fix a thing that is already fixed.

The backlog compounds this by framing the doc work as conditional — *"`Attr.widget_name`'s
doc needs rewriting when the first one is taken"* — which reads as "the doc is accurate
until then". It is not.

Fix: two sentences. `attr.mli` should say the caveat is now a deliberate choice (the write
is still `Some`, so an unnamed widget is restored to the class name `get_name` reported)
rather than a binding limitation, and `attr_apply.ml:24-26` should say the same. The
backlog's *Do first in M3* entry should lose the "when the first one is taken" conditional.

Severity: Important. Public mli, factually false about the pinned dependency, and false
*because of a commit on this branch* — so it is a whole-branch regression rather than an
inherited inaccuracy.

## Minor

**M1. `patcher.mli`'s `report` doc says it has one caller; four ship.**
`src/patcher.mli:18-20`: *"Today's only caller is a `Node.text_view` whose `~text` GTK will
not store"*. `enqueue_fixups` has four report arms — `Text_view` (`src/patcher.ml:239-240`),
`Drop_down` (`:246-247`), `Calendar` (`:253-254`), `Editable_label` (`:255-256`) — added by
Tasks 10 and 11 in direct response to Task 9's carry ("Task 8's hidden-page divergence and a
list-box `~selected` the mode cannot hold are the same shape and should get the hook"). The
implementations are consistent with each other (all four: `Cache = Ephemeron.K1.Make`,
`{ refused; unreported }`, `take_report` clearing `unreported`, `already_refused` consulted
before any widget read), so this is the doc lagging the code, not a semantic split.

**M2. `patcher.mli`'s Raises lists are incomplete in two places.** `run_fixups` (`:70-80`)
enumerates the `stack_switcher`/`stack_sidebar` rejection and the `Node.stack
~visible_child` one, but not `W_notebook.select`'s (`src/widgets/w_notebook.ml:199-204`,
reached from `src/patcher.ml:294-295` through `child_op`), which Task 8 added on exactly the
stack's reasoning. `mount` (`:135-143`) omits the duplicate-stack-name rejection entirely —
see I1.

**M3. `driver.mli` says the backstop is on the root widget; it is on the wrapper.**
`src/driver.mli:134`: *"`Bonsai_gtk.Expert.embed` connects this to its **root widget's**
`destroy`"*. `src/embed.ml:148-152` connects it to the wrapper, and `src/embed.ml:130-133`
and `src/embed.mli:87` both say why that is the only correct choice (the wrapper is what the
caller parents; the root widget's identity changes on a root-kind change). Two public mlis
disagree about a design decision the branch took deliberately.

**M4. `Events.family_attrs` rebuilds a 48-element filter on every call, three times per
patched node per frame.** `vtree/events.ml:214-219` is a function; `Controllers.wanted`
(`src/controllers.ml:55-58`) calls it once per family, and `Controllers.update`
(`:341`) runs for every node of every patch — unconditionally, including for the
overwhelming majority of nodes that carry no controller attr at all. That is ~144
`controller_family` matches plus three list allocations per node per frame that can never
answer anything but `false`. The identical derive-from-the-table idiom one file over,
`Placement.names` (`vtree/placement.ml:93`), is a top-level `let` computed once. Unmeasured,
so no claim about whether it shows up — but the backlog's own lesson from Task 7
(`apply_selection` at 24 ms/frame) is that per-frame per-node walks are where the numbers
have actually been. One-line fix: memoise `family_attrs` over `Family.all`, or have `wanted`
walk the node's attrs (0–5 of them) and ask `controller_family`, rather than walking all 48
names and asking `Attrs.find`.

**M5. The placement seam has no drift check equivalent to the events seam's.** Two gaps,
both narrower than they look but worth recording together:

- `Placement.read_by` has a wildcard (`vtree/placement.ml:29`), deliberately — but that
  means a *new kind* with a `read_by` arm is not a compile error, and
  `test/test_placement.ml`'s inverse check runs over a hand-written six-element `containers`
  list (`:33-45`). A new container kind copy-pasting `| Foo _ -> [ Grid_cell ]` would be
  accepted by `is_read_by`, contradicted by `reader` (which still says "Grid"), missed by
  the test, and its children's `Attr.grid_cell` would be silently inert — the exact failure
  the table exists to prevent. A *new attr* is caught, because `reader` is exhaustive.
- Nothing checks that a container which *declares* a placement attr actually *applies* it.
  On the events side there are two independent statements (`Events.for_kind` and the impl's
  `signals`) held together by `live_events.ml` and, unconditionally, by
  `Signals.require_slots`. On the placement side there is one table and an unchecked
  convention; if `w_notebook.ml` stopped reading `Attr.tab_label`, `Placement` would go on
  accepting it. Goldens would probably catch it, which is why this is Minor rather than
  more.

**M6. All four `take_report`s mint an ephemeron entry to find `None` in it.**
`src/widgets/w_text_view.ml:116-118`, `w_drop_down.ml:120-122`, `w_calendar.ml:148-150`,
`w_editable_label.ml:103-105` all open with `let st = state w in`, and `state` (`replace`s
on miss) creates the entry. The backlog records this as task-9 re-review R3 but names only
`w_text_view.ml`, where it is the one with a consequence (a minted entry is
`{ stale = true }`, i.e. it would provoke a buffer read). Tasks 10 and 11 copied the shape
without copying the note. `Cache.find_opt` is the fix in all four.

**M7. Malformed odoc reference.** `src/patcher.mli:110`:
`{!Bonsai_gtk_vtree.Attr.on_click]` — opened with `{!`, closed with `]`. The only one in
`src/*.mli`, `vtree/*.mli` and `test_lib/*.mli` (grepped).

**M8. `Signals.spec`'s two arms differ in connection arity with no stated reason.**
`Read_back.connect` returns a `connection list` and the mli spends a paragraph
(`src/signals.mli:119-129`) justifying it — the calendar needs `day-selected` plus two
`notify::` for one attr. `Payload.connect` (`:145`) returns a single `connection` and the
mli never mentions the asymmetry. Nothing needs it today; it is the shape M3 would have to
change if a `Payload` signal ever needed two emissions for one attr, and it belongs beside
the *API shape decisions before they become breaking* list rather than being rediscovered.

**M9. `Controllers.update`'s `configure` raising leaves different states on the two paths,
undocumented.** `sync`'s attach branch runs `configure` before `add_controller`
(`src/controllers.ml:122-126`), so a rejected node leaves nothing attached — stated in the
comment at `:292`. Its update branch runs `configure` before `update_slots` (`:119-121`),
so a `configure_key` rejection on a *patch* (two key attrs whose phases diverge on frame
two) leaves the key controller attached, connected, and with empty slots — silently
disarmed rather than detached. Harmless, because `Controllers.update` runs inside
`Driver.frame_body`'s guard and the frame is about to break the driver for good; recorded
because the comment at `:292` reads as if it covered both paths.

**M10. `W_editable_label` is absent from `Bonsai_gtk.Private`** (`src/bonsai_gtk.mli:151-169`)
while its three `ctx.report` siblings — `W_text_view`, `W_drop_down`, `W_calendar` — are all
exported. No test needs it today; the asymmetry is the kind that reads as an omission to
whoever next writes a test for the refusal path.

## Out-of-scope observations

These are outside the core lens but are the merge-time questions `progress.md` parked for
this round, and I have a view on two of them:

- **`(locks x-display)` vs `-j 1`.** The reviewer's own reproduction (task-16 fix round I3)
  settles it: `(locks x-display)` binds the constraint to the eleven rules rather than to
  one flag on one call site, so the alias is safe however it is invoked, and it does not
  serialise anything else in the build. Eleven mechanical edits, verified on this toolchain.
  I would take it in the fix wave and keep `-j 1` out.
- **Whether `entry`/`search_entry`/`password_entry` should refuse a NUL** (backlog, *Do
  first in M3*, task-16 I1). Yes, and it is a core-consistency question rather than a widget
  one: `Patcher.ctx.report`'s four arms are now the library's stated answer to "the model
  asked for something the widget cannot hold", and these three are the only text widgets
  that instead rewrite the widget on *every* idle frame, forever, with nothing on stderr.
  The `unwritable`/`already_refused`/`take_report` machinery is identical in all four
  existing implementations (M6 above), so this is a fifth copy of a settled shape, not a new
  design. The counter-argument in the backlog — three more per-widget caches — is a real
  cost, and it is the argument for doing all three at once behind `W_entry` rather than for
  not doing them.
- **The XTEST bead (`bonsai_gtk-5qv`)** and **whether `.superpowers/` should survive the
  checkout** are decisions for the controller and the user respectively; nothing in the core
  lens bears on either.

Also noted, not filed: `Loop.start`'s `on_window_created` closes over the `GtkApplication`
and is not dropped by `Driver.stop`, unlike `on_root_widget_changed` — already on the
backlog under *Plumbing / hygiene* ("`Bonsai_gtk.start`'s `on_window_created` has the same
shape"), and I1 does not change the analysis.

## Verdict

**Needs fixes.**

Blocking-ish, in the sense that they are small and the branch's own mlis promise otherwise:

- **I1** — three lines in `src/patcher.ml`'s `mount` wrapper, plus the two mli sentences.
  This is the one I would not merge without.
- **I2** — an `Exn.protect`-shaped change in `Patcher.destroy`, `Driver.stop` and
  `Embed.stop`. Narrower reachability; defensible to defer to M3 *if* it goes on the backlog
  with I1's reasoning attached, since it is the same class.
- **I3, I4** — one sentence each, in `vtree/events.mli` (+ `src/patcher.mli:109-111`) and
  `vtree/attr.mli` (+ `src/attr_apply.ml:24-26`). Both are wrong rather than thin, and both
  are false *because of commits on this branch*, so they should not roll forward as backlog
  items.

The Minors are backlog material, except M1/M2/M7 which are cheap enough to take in the same
pass as I3.

## Re-review (fix wave)

Re-checked at `36aa26c` against `git diff f06a615..36aa26c`, read-only, no builds. Only my
own findings; the other lenses' items are theirs.

**I1 — fixed, `8bd5df9`.** `src/patcher.ml`'s `mount` wrapper now wraps
`apply_stack_claims` and calls `destroy ctx live` before re-raising with the original
backtrace — the shape I proposed, with the comment stating both halves (the leak, and that
`destroy` on a `Window` root is what takes the presented window back off screen). `patch`'s
wrapper is correctly left alone, with the reason written down. `patcher.mli`'s `mount`
Raises list now carries the duplicate-`~name` rejection (`:143-145`) and the
exception-safety paragraph says it is inside the guarantee though decided after the walk
(`:156-159`). Two live cases in `live_patcher.ml` pin it — the window is off screen after
the rejection, and a `clicked` on the button that was in it schedules nothing — plus one in
`live_embed.ml` for the `Embed.create` path where the caller has no handle at all; the
commit records all three as mutation-verified. My reachability argument survives and is now
documented rather than implicit: `test_lib/bonsai_gtk_test.ml` still does not check stack
names, and the new table in `bonsai_gtk_test.mli:455` says so in as many words ("two
Node.stacks under one ~name — decidable without GTK: yes; handle checks it: no").

**I2 — fixed, `8bd5df9`, and in one place better than I asked.** `Patcher.destroy` is
collect-and-reraise with the `step` guard per stage *and per child* (`src/patcher.ml:647+`),
so a raise on the third sibling no longer strands the fourth. `Driver.stop` reaches its
trailing steps through `Exn.protect`, and the `finally` also does `t.root <- None` — which
closes the residual I noted in passing but did not file, that `root_widget` went on
answering `Some` for a half-destroyed tree. `Embed.stop` likewise runs the unparent and the
backstop disconnect from a `finally`, so the state its own comment calls unsafe is now
unreachable rather than merely unlikely. `native_gtk.mli:33-41` states the contract a
raising `destroy` gets (the rest of the teardown runs, the exception is re-raised, nothing
retries, so the implementation has leaked what `create` acquired), `patcher.mli:222-231`
states the completes-then-reraises rule, and `driver.mli`/`embed.mli` say what `stop`
raises. The mid-list raising-`Native` case is pinned in `live_patcher.ml`.

**I3 — fixed, `7504f8e`, by derivation rather than by re-listing.** `vtree/events.mli`'s
`is_controller_attr` no longer enumerates; it points at `controller_family` and explains
why a list would be a second statement of the table — and records the actual failure ("this
sentence named three attrs for the whole of M2, while five had a family"), which is the
version a later maintainer benefits from. `patcher.mli`'s `controllers` field is rewritten
the same way ("one per `Events.Family.t` whose attrs the node carries"), taking M7's
malformed odoc reference with it. `signals.mli` and spec §6.4 dropped the `Payload` count
on the same rule, so the two "N of them exist" claims in `src/` are both gone rather than
one being fixed twice.

**I4 — fixed, `7504f8e`.** `vtree/attr.mli:234-246` now says the lossy `Unset` is a choice
rather than a limit, names what the library still writes (`Some d.widget_name`), and points
at the backlog item for the behavioural half; `src/attr_apply.ml:24-28` says the same. The
backlog's *Do first in M3* entry lost the "when the first one is taken" conditional that
made the stale text read as accurate.

**Minors.** M1, M2 and M7 taken in `7504f8e` — and M1 is now more than a correction: the
`report` field's doc describes the shared mechanism (`Refusal`) rather than a caller list,
so it cannot go stale the way it did. M2's two halves both landed (the notebook
`~current_page` rejection in `run_fixups`' Raises list; the duplicate name in `mount`'s).
M3 taken in `8bd5df9` — `driver.mli:134-139` now says the backstop is on the wrapper and
adds *why* it is not the rendered root. M6 is closed by the `Refusal` functor in `2d72884`
rather than patched four times: `take_report` opens with `Cache.find_opt` and creates no
entry (`refusal.ml:55-57`), and `refusal.mli:23-25` records that the four hand-copies
"diverg[ed] in exactly one place that mattered" — which was the finding. M4, M5, M8, M9 and
M10 are on the backlog under *Left by the final review's fix wave* with my reasoning
carried over intact; M4's deferral ("unmeasured, and the fix has two shapes worth choosing
between with a number in hand") and M10's ("less of an asymmetry after the wave — the
label's refusal now lives in `W_entry`, which is not exported either") are both better
calls than filing them as work.

**One thing I re-checked because the wave moved it.** `interest` grew an `Editable` arm
collapsing `Entry`/`Password_entry`/`Search_entry`/`Editable_label` (`2d72884`, which also
took my out-of-scope recommendation on the entry-NUL question). All three exhaustive
matches over `interest` moved with it — `enqueue_fixups:259`, `note_interest:346`,
`drop_stack_names:741` — and `interest_of_kind:193` maps the four kinds. No drift.
`src/controllers.ml` and `vtree/events.ml` are untouched by the wave, so the table/seam
analysis in the report above still stands as written.

**Residual, recorded not filed.** `destroy` now re-raises deliberately, so a raising native
`destroy` inside `mount`'s `unwind ()` — or inside the new wrapper's `destroy ctx live` —
will propagate in place of the exception that started the unwind, masking the original
diagnostic. It needs a mount-or-claim failure *and* a misbehaving native node in the same
tree, both exceptions are `Invalid_argument`-class, and the frame is dead either way. The
shape is unchanged from before the wave (the old `destroy` raised out of `unwind` too), so
this is not a regression and I would not spend a commit on it; it is worth knowing if
anyone ever debugs a duplicate-stack-name rejection that reports something else.

### Verdict

**Approved.** Both code findings are fixed as recommended, with live regressions the commit
records as mutation-verified; both documentation findings are fixed by removing the
duplicated claim rather than by correcting it, which is the durable version; every Minor is
either taken or on the backlog with its reasoning. Nothing in the wave's core changes
introduced a new problem in this lens.
