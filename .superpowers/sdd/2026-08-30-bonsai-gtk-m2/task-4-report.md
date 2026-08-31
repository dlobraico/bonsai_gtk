# Task 4 report — the existential event spec, and click and focus controllers

**Commit:** `9c081e5` "Signals carry their own arguments, and widgets carry event
controllers" (46 files, +1772/-183), on `m2`, base `3ea4594`. One commit, as the plan
asks. Not pushed, not merged; no `bd` touched.

**Gate:** `nix develop -c ./scripts/ci.sh` → `all green`.

---

## The headline, first: which testing option each controller got

The plan's pre-flight correction 1 closed the open question ("can a synthetic click or key
press be delivered?") with **no**, and named the fallback. That is what landed, and it is
worth being precise about, because "click is tested" is true of three different things and
none of them is the one a reader assumes.

### Click — **option (c), plumbing only, plus two things the plan did not ask for**

There is no way to make GTK route a real button press to a gesture this library attached:
no `GdkEvent` constructor exists for any event subtype in the pinned binding,
`Gobject.Signal.emit_by_name`/`.notify` take no arguments and return unit (so neither can
carry `~n_press ~x ~y`), and no `gtk_test_*` binding exists. I re-ran the pre-flight's
checks rather than trusting them; both came back empty, as reported.

So the click evidence is in three places, and the *union* is what stands in for an
end-to-end test:

1. **Plumbing, live** — `test/live/live_controllers.ml`. Attaching `Attr.on_click`
   attaches a controller; dropping the attr removes it; re-adding gets a fresh one; the
   widget survives all of it; and teardown leaves none behind. Asserted against
   `Widget.observe_controllers` (pre-flight correction 3), i.e. **GTK's own answer**, not
   this library's bookkeeping — both numbers are printed on every line so a disagreement
   between them is the diff.
2. **The gesture's settings really reach GTK** — the same file reads `button` and
   `propagation_phase` back off the live `GtkGestureClick`. Since no click can be
   delivered, this is the *only* evidence that `~button:2` and `~phase:Capture` do
   anything at all, and it is the only thing that would catch `Controllers` configuring
   the wrong object. Not in the task text; added because without it those two arguments
   were entirely unpinned.
3. **The handler, headless** — `test/handle/test_handle.ml`, "a click action carries the
   button and the modifiers", through the new `Bonsai_gtk_test.Action.Click_at`. Middle
   click with shift, `b2 n1 shift=true` in the golden.
4. **The trampoline between them** — `test/live/live_signals.ml`, see "`Payload`'s three
   declined paths" below.

**Still not covered:** that GTK routes a real button press to the gesture. In the backlog
(`docs/m1-backlog.md`, "Tests worth adding", first two entries), with the closing
condition written down (an ocgtk fork patch exposing a `GdkEvent` constructor or
`gtk_test_widget_click`) and the compensating controls named (the gallery's Input section,
Task 16's real-display click-through, which the backlog entry now says should exercise a
node carrying `Attr.on_click`).

### Focus — **option (a), genuinely end to end**

`Widget.grab_focus` on a **presented** window really drives `GtkEventControllerFocus`.
Pre-flight correction 2 was necessary and is applied: `on_window_created` presents the
window, and the test drains the main loop (`Glib.Main.iteration false`) after each
`grab_focus`, because GTK does its focus bookkeeping from the loop and reading back in the
same breath reads back too early. With both in place the focus half asserts, for real:

- focus moving in fires `on_focus_enter`, out fires `on_focus_leave`;
- a focus change made **inside the patch guard** reaches nothing (the reentrancy guard, on
  a real controller rather than a hand-emitted signal — this is the only place in the
  suite where that guard is exercised against a controller);
- after the attrs are dropped the same `grab_focus` fires **nothing**, which is what makes
  "the controller was removed" an assertion about behaviour rather than about a counter;
- and after they come back a fresh controller works.

### `Payload`'s three declined paths — proved, with the returned value visible

The review focus asks that a reviewer be able to point at each of the three paths on which
`Payload`'s trampoline returns `declined`. No signal this binding exposes both takes
arguments and returns a value in a way a test can emit, so I exercised the trampoline
**where it is built** rather than through GTK: `Signals.connect_all` hands the callback it
wrapped to the spec's `connect`, and the test's spec keeps that callback instead of
handing it on. What is called is the real trampoline, with a `string` return type so the
answers are legible:

```
returned declined, scheduled 0      <- path 1: empty slot
returned handled:b, scheduled 1     <- the ordinary path: value now, effect scheduled
returned declined, scheduled 1      <- path 2: emission during a patch, nothing scheduled
EXN at root/0: (Failure boom)
returned declined, scheduled 1      <- path 3: [fire] raised; reported, not propagated
returned declined, scheduled 1      <- and [clear_slots] disarms a payload spec too
```

This is not a fake click: it makes no claim about GTK routing, only about the trampoline,
which is exactly what it calls.

---

## Per-step summary

**Step 1 — failing tests.** `test/test_attrs.ml` (three expect tests: round-trip and diff;
that `button`/`phase` are part of a click attr's identity, so a change in either is a `Set`
even with a physically-equal handler; and that `Click_event.t`/`Modifiers.t` sexp);
`test/handle/test_handle.ml` (four: a controller attr accepted on a kind that emits
nothing, `Click_at` carrying button and modifiers, the focus pair, and the failure when
the named node carries no handler); `test/live/live_controllers.ml` (new).

**Step 2 — verified failing.** `Unbound value "Attr.on_click"` from both test dirs.

**Step 3 — `vtree/phase.ml`, `modifiers.ml(i)`, `click_event.ml`.** As specified. `Phase`
has no `None` arm, deliberately, and the doc says why.

**Step 4 — the three attrs.** `Attr.Name.t` gains `On_click | On_focus_enter |
On_focus_leave` after every existing `On_*`, so no existing `Attrs.diff` golden reordered
(none did). `Attr.Private.t` gains the three constructors, `On_click` an inline record.
`equal` compares `button` and `phase` structurally and the handler physically.
`Events.is_controller_attr` is the new exhaustive classifier and `Events.is_supported`
short-circuits on it.

**Step 5 — `Signals.spec` becomes a variant.** `Read_back` is M1's record verbatim;
`Payload : ('p, 'r) payload -> spec` is the existential. `dispatch_payload` is the second
trampoline; `spec_attr` matches; `connect_all` builds the right callback per arm.
`update_slots`/`clear_slots` untouched — a slot is a slot. Twelve widget impls are
mechanically wrapped in `Read_back`; nothing else in them changed.

**Step 6 — GDK aliases.** `Gdk_enums`, `Gdk_constants` and `Gio` in `src/gtk_import.ml`,
with the comment about GDK's shape differing from GTK's. `modifiers_of_gdk` and
`propagation_phase` live there too, beside the other conversions, so Task 5 can use both.

**Step 7 — `src/controllers.ml(i)`,** and wired into `Patcher.live` as a field: created in
`mount` after `Signals.connect_all`, `update`d in `patch` beside `Signals.update_slots`
(unconditionally, same reason), `clear`ed in `disarm`, `release`d in `destroy`.

**Step 8 — `test_lib`.** `Click_at of string * Click_event.t`, `Focus_enter of string`,
`Focus_leave of string`. `Click_at` consults nothing on the node, and the mli says why, and
says plainly that it is the only test a click handler has.

**Step 9 — run, read, promote, gate.** `live_events.ml` gained the assertion that no impl
declares a controller attr. Two existing goldens moved and both moves are load-bearing
(below); everything else was unchanged.

**Step 10 — commit.** As above.

---

## Deviations from the task text, and why

1. **`src/gtk_import.mli` does not exist** (the file list names it). `gtk_import.ml` has no
   interface file; the additions are in the `.ml`.

2. **`is_event` stays `true` for the controller attrs, and the distinction is a second
   predicate.** The alternative — making `is_event` false, which would make
   `Events.is_supported` and `Signals.require_slots` both do the right thing for free — was
   rejected: it hides a real distinction inside a predicate whose name does not carry it,
   and it would mean the three attrs silently escape `require_specs` rather than being
   deliberately admitted by it. `Events.is_controller_attr` is exhaustive over
   `Attr.Name.t` with no wildcard, so Task 5's key attrs cannot skip the decision.

3. **`Signals.require_slots` skips controller attrs**, with the reason in a comment: their
   slots belong to `Controllers`, which builds them *from the attr itself*, so "the attr is
   present but has no slot" is not a reachable state. The mount-time assertion Task 1 added
   is otherwise unchanged and still covers every widget signal.

4. **`sync` is polymorphic in the controller's concrete type** rather than storing an
   upcast `Event_controller.t`. The task's sketch would have needed an unsafe downcast to
   re-apply the gesture's button on the "already attached" path; a `(type a)` parameter with
   an `~upcast` argument removes it. Same four cases, same ordering.

5. **`release` is split from a new `clear`,** as the task anticipated: `Patcher.disarm`
   needs the slot-emptying without the detaching, because on the paths where a subtree is
   unparented before it is destroyed the detaching has not happened yet. `patcher.mli`'s
   promise now says "the widgets' own and their controllers'".

6. **`Controllers` names every controller it attaches** (`bonsai_gtk.click`,
   `bonsai_gtk.focus`, via `gtk_event_controller_set_static_name`), and exposes
   `is_ours`. Not in the task text, and it turned out to be necessary: a `GtkButton`
   ships with a `GtkGestureClick`, a `GtkEventControllerKey` and a `GtkShortcutController`
   of its own, so the pre-flight's "item count N → N+1 → N" is measured against a baseline
   of 3, "the widget has a GtkGestureClick" is true before this library does anything, and
   a test counting the total would break the day a GTK release changes how many a button
   has. Counting by name makes the golden say `gtk=(bonsai_gtk.focus bonsai_gtk.click)`
   rather than `gtk=5`. The name is also GTK Inspector's label, which is what the GTK API
   is for.

7. **The live test also reads the gesture's `button` and `phase` back off GTK.** See the
   headline section; without it those two constructor arguments had no test at all.

8. **`test/live/live_signals.ml` gained the `Payload` trampoline test.** Not in the task's
   file list. The review focus asks for the three declined paths to be pointable-at, and
   nothing else in the suite could reach them.

9. **`test/test_events.ml`'s "the table and `is_event` cover the same names" was rewritten,
   not re-promoted.** Its `event_names_no_kind_emits` assertion would have gone from `()`
   to listing the three controller attrs, which is exactly the kind of golden-widening the
   plan's reviewer brief warns about. Instead the filter now excludes controller attrs (so
   a real signal name falling out of every `for_kind` row would still fail), a new
   assertion says no controller attr appears in any `for_kind` row, and a second new test
   asserts every controller attr is supported on **every** kind — including `Node.native`,
   where every signal attr is rejected.

10. **`test/test_placement.ml`'s count moved 29 → 32.** Mechanical: three names added, none
    of them a placement attr. The list of placement attrs beside it is unchanged, which is
    the assertion that matters.

11. **Warning 30.** `read_back` and `payload` share `attr`, `connect` and `fire`
    deliberately — they are two spellings of one concept. Suppressed over the declaration
    only, in both `.ml` and `.mli`, with the reason written down, rather than adding `-30`
    to the library's flags.

12. **`examples/gallery.ml` was not touched.** The task's file list does not include it and
    the plan gives the gallery's Input section to Task 15/16. Carried below.

---

## What the tests prove, and one negative check

I broke `Controllers`' `remove_controller` deliberately and re-ran the live test before
promoting the golden. It goes red loudly and in the right way:

```
click attr dropped: gtk=(bonsai_gtk.focus bonsai_gtk.click) bonsai=1
focus attrs dropped, click back: gtk=(bonsai_gtk.click bonsai_gtk.focus bonsai_gtk.click) bonsai=1
after destroy: gtk=2
```

— GTK and this library disagree, and duplicates accumulate. Worth noting what that
experiment *also* showed: the line `focus after its attrs were dropped:` stayed empty even
with the leak, because `clear_slots` still ran. So the two halves pin different things —
that line pins the slot-emptying, the `gtk=` lines pin the removal — and neither would
catch the other's bug. Both are needed and both are there.

---

## Test and CI tails

```
$ nix develop -c dune test
(exit 0, no output)

$ BONSAI_GTK_LIVE_TESTS=1 nix develop -c xvfb-run -a dune build @test/live/runtest
(clean; the "exception in frame, stopping the driver" line is live_driver.ml's
 deliberate raise, unchanged from before this task)

$ nix develop -c ./scripts/ci.sh
== nix: ocgtk pin builds and passes its tests
== format
== build
== generated opam files are committed
== pure + headless tests
== per-package builds, the way opam --with-test runs them
== live tests (xvfb)
== example smoke
all green
```

`test/live/expected_controllers.txt` in full:

```
(GtkWindow (title (controllers)) (css (background))
 (children
  (GtkBox (spacing 0) (css (vertical))
   (children
    (GtkButton (label (target)) (css (text-button))
     (children (GtkLabel (text target))))
    (GtkButton (label (other)) (css (text-button))
     (children (GtkLabel (text other))))))))
mounted target: gtk=(bonsai_gtk.focus bonsai_gtk.click) bonsai=2
mounted other: gtk=() bonsai=0
mounted gesture: button=2 phase=CAPTURE
focus into target: focus-enter
focus to other: focus-leave
focus during a patch: 
focus away again: focus-leave
click attr dropped: gtk=(bonsai_gtk.focus) bonsai=1
focus attrs dropped, click back: gtk=(bonsai_gtk.click) bonsai=1
focus after its attrs were dropped: 
both attrs back: gtk=(bonsai_gtk.focus bonsai_gtk.click) bonsai=2
re-added gesture: button=2 phase=CAPTURE
focus after the attrs came back: focus-enter
(GtkWindow ...unchanged tree...)
after destroy: gtk=0
destroyed cleanly
```

---

## Carries and things deliberately left undone

- **The end-to-end click gap** is in `docs/m1-backlog.md` under "Tests worth adding",
  written out in full (what is covered where, what is not, and what would close it). It
  covers Task 5's key controllers too.
- **`Attr.on_click`'s mli says the gesture cannot claim the event sequence and that this is
  "named in the README's Limitations".** It is not there yet — Task 15 owns the README. The
  sentence is a promise Task 15 has to keep.
- **The gallery has no Input section yet** (Task 15/16). It is now also a compensating
  control for the missing synthetic click, so it should exercise a node carrying
  `Attr.on_click` and not only the M1 widgets.
- **A focus controller has no `~phase`.** M2's `Attr.on_focus_*` take no phase argument, so
  the controller stays in GTK's default (bubble). If Task 5's key attrs make phase feel
  like a controller-wide idea, this is where the asymmetry is.
- **`Controllers.attached_count` and `is_ours` exist for the live test.** Both are in
  `Private`, both are documented as such. If Task 5 adds a third family, `attached_count`'s
  hand-written list of options grows and there is no compiler check on it — a small,
  known, contained hazard.
- **Task 5 hooks left in place:** `Controllers.t` has a commented slot for
  `mutable key : W.Event_controller_key.t attached option`, `Attr.Name.t` has a comment
  saying where `On_key_pressed`/`On_key_released` go, `Phase` and `Modifiers` are already
  shared, and `modifiers_of_gdk` lives in `gtk_import` rather than in `controllers.ml` so
  the key spec can use it.

---

# Fix round 1

**Commit:** `328ca80` "Fix round 1, C1 and I1: a name GTK could keep, and a family the
compiler counts" (8 files, +400/-101), on `m2`, on top of `9c081e5`. No history rewrite,
not pushed, not merged.

**Gate:** `nix develop -c ./scripts/ci.sh` → `all green`.

One commit rather than two, following this milestone's convention (`3ea4594` did the same
for two findings). The body separates C1 from I1 and names each minor.

---

## C1 (Critical) — `set_static_name` with a computed string

**Accepted without argument. The reviewer is right and my comment beside the call was
wrong in exactly the way that matters:** it stated the requirement correctly ("the string
must outlive the controller") and then asserted the value satisfied it ("these are
literals, which do"). `name_prefix ^ suffix` is a runtime concatenation, unreachable the
moment `set_name` returns. I verified the two halves of the mechanism myself rather than
taking them on trust: `ml_gtk_event_controller_set_static_name` passes
`String_option_val(arg1)` straight through
(`.ocgtk-src/ocgtk/src/gtk/generated/ml_event_controller_gen.c:26`), and
`ml_gtk_event_controller_set_name` (`:62`) is the same call shape into the `g_strdup`-ing
GTK function.

**Change** (`src/controllers.ml:30-45`): `W.Event_controller.set_name`, one identifier.
The comment is rewritten to say what is actually true, including *why the hoisted-literal
"fix" the reviewer warned against is not a fix* — OCaml does not promise a literal is
static data, and under bytecode literals live in the heap and move under compaction.

**Regression test**, as ruled — `test/live/live_controllers.ml`, and it runs **first** in
the file, before every assertion that depends on the name being readable (the file now
opens with a standalone `GMain.init` so that ordering is possible). It mounts a
`Node.label` carrying `Attr.on_click ~button:2` and `Attr.on_focus_enter` through
`Patcher.mount`, churns the heap (20 rounds × 100k short `Bytes`, `Gc.compact` between
rounds), then re-reads the names, the count, and the gesture's properties. A label rather
than a button, deliberately: a label emits no signal at all, so anything attached can only
have come from the attr.

**It reproduces the reviewer's finding exactly.** With `set_static_name` put back:

```
before gc: gtk=(bonsai_gtk.focus bonsai_gtk.click) bonsai=2 total=3
after gc:  gtk=()                                  bonsai=2 total=3
after gc:  no gesture of ours
```

and with `set_name`:

```
before gc: gtk=(bonsai_gtk.focus bonsai_gtk.click) bonsai=2 total=3
after gc:  gtk=(bonsai_gtk.focus bonsai_gtk.click) bonsai=2 total=3
after gc:  button=2 phase=BUBBLE
```

The `total=3` on both lines of the failing run is the part worth pointing at: it says the
controllers were still attached and only their *names* went bad, which is the diagnosis
rather than the symptom.

**`after destroy` is no longer vacuous.** I took the second of the two options in the
ruling and then also the first, because they cost one line each. `controllers` now prints
a third number, `total=`, which is `observe_controllers` with no filtering and so does not
go through `get_name` at all; and the destroy is now bracketed by a positive read on the
same widget:

```
before destroy: gtk=(bonsai_gtk.focus bonsai_gtk.click) bonsai=2 total=5
after destroy:  gtk=()                                  total=3
```

`5 → 3` is the assertion, and it holds whatever happens to the names. The baseline is now
in the golden rather than in a comment (`mounted other: gtk=() bonsai=0 total=3` is a
`GtkButton`'s own three controllers), which also makes the case for counting by name
legible to a reader of the file.

---

## I1 (Important) — a controller attr accepted everywhere and wired nowhere

**Accepted.** The reviewer's walk-through of how Task 5 trips on this is correct, and the
report's own carry ("`attached_count`'s option list is hand-maintained") was the small
version of the same defect.

**Change:** one exhaustive table in `vtree/`, as ruled.

- `Events.Family.t = Click | Focus` (`[@@deriving ... enumerate]`).
- `Events.controller_family : Attr.Name.t -> Family.t option`, exhaustive with no
  wildcard.
- `Events.is_controller_attr` is now `Option.is_some (controller_family name)` — derived,
  so the two cannot disagree.
- `Events.family_attrs : Family.t -> Attr.Name.t list`, derived from `Attr.Name.all`, is
  what `Controllers` asks whether a family's controller should exist.

`Controllers` then dispatches on `Family.t` with an exhaustive match in **four** places,
not one: `update`, `clear`, `release` and `attached_count` are all
`List.iter/count Events.Family.all ~f:(fun family -> match family with …)`. Adding `Key`
to the variant is four compile errors, and `attached_count`'s hand-maintained option list
— the report's carry — is gone with the same change. `wanted` is computed from
`family_attrs` rather than from names spelled in `controllers.ml`, so Task 5's second key
attr joins its family in `vtree/events.ml` and nothing in `src/controllers.ml` changes.

**The positive test the ruling asked for** is a sweep in `live_controllers.ml`: one
`(name, attr)` row per controller attr, asserted complete against
`List.filter Attr.Name.all ~f:Events.is_controller_attr` (an `assert`, so a missing row
aborts the executable — the same device `live_events.ml` uses for `Kind.t`), then for each
row a mount of a `Node.label` carrying it, a check that a controller of ours appeared, and
a destroy:

```
On_click       -> family=(Click) attached=(bonsai_gtk.click)
On_focus_enter -> family=(Focus) attached=(bonsai_gtk.focus)
On_focus_leave -> family=(Focus) attached=(bonsai_gtk.focus)
every controller attr attaches a controller
```

So the three doors are now all shut: a family named and not attached is a **compile
error**; a name admitted and not in the sweep is an **abort**; a name in the sweep whose
family attaches nothing is a **golden diff**. What the golden additionally pins, for free,
is the name→family mapping itself — sending `On_focus_leave` to `Click` would show up as
`attached=(bonsai_gtk.click)`.

I did not put the check in `require_slots`'s place (the ruling's "or, better"). Reason:
`require_slots` runs per mount and would have to consult a per-widget structure to answer
"did this family attach", which means either exporting more of `Controllers` into a
hot path or duplicating the family table in `src/`. The live sweep answers the same
question once, against the real GTK object, and the compile error is what carries the
weight for the case the reviewer actually worried about (a missed `sync` call). If a
reviewer disagrees I will move it.

---

## Minors

| # | Verdict | What changed |
|---|---|---|
| M1 | **Fixed.** | The shared doc comment sat between the two `val`s and so attached to `on_focus_leave` only. Both now have their own, and `on_focus_enter`'s carries the "or any of its children" sense that was the point of the comment. `vtree/attr.mli`. |
| M2 | **Fixed.** | `sync`'s detach path now calls `clear t` (every family) before `remove_controller`, not just the removed family's slots. The reviewer is right that the two removal paths must not disagree about an invariant one of them states in a comment. `release` is now `clear t` followed by a `Family.t`-driven detach loop, so the two really are the same three steps in the same order; `controllers.mli`'s claim that they are "the same code" is softened to what is true. |
| M3 | **Fixed.** | `Gtk_import.Gio` removed — dead, and not in Step 6's list. `Gdk_constants` stays: unused today, named by Step 6, and Task 5's keyval test is its caller. |
| M4 | **Argued, no change.** | Correct and I have nothing to add: `x`/`y` in widget coordinates, `n_press` counting up, `~button:0` meaning "any", and "the gesture does not claim the sequence" are all unexercised and *cannot* be exercised without a deliverable press. That is the option-(c) gap, not a separate omission. I have widened the backlog entry's framing accordingly — it already says "GTK routes a real press here", and the reviewer's point is that the documented *semantics* ride on the same missing capability. Noting it here so the next reader of the backlog understands its scope; I did not re-edit `docs/m1-backlog.md`, since the entry as written already covers the capability rather than a single assertion. |
| M5 | **Fixed.** | The live test now drops `on_focus_enter` alone and keeps `on_focus_leave`: `on_focus_enter alone dropped: gtk=(bonsai_gtk.focus) bonsai=1 total=4` (the controller stays), and `focus in and out with only on_focus_leave: focus-leave` (focusing in fires nothing, focusing out fires once). That is `sync`'s `Some _, true` branch with an attr genuinely disappearing, which nothing else reached. |
| M6 | **Argued, no change.** | Agreed on the facts and on the scope call. `connect_all` passes the widget to every trampoline and both controller specs ignore it, so each controller's GClosure holds a root on the widget's wrapper. It is broken correctly by `disconnect` on both removal paths, so nothing leaks today; narrowing it means changing `connect_all`'s signature, which every M1 spec shares. It strengthens the case for the backlog's unwritten "remove a keyed child, `Gc.full_major`, assert finalization" test, which is where I would rather spend it. |

---

## Gates after the fix round

```
$ nix develop -c dune build @all            -> clean
$ nix develop -c dune test                  -> clean (exit 0, no output)
$ BONSAI_GTK_LIVE_TESTS=1 nix develop -c xvfb-run -a dune build @test/live/runtest
                                            -> clean
$ nix develop -c ./scripts/ci.sh
== nix: ocgtk pin builds and passes its tests
== format
== build
== generated opam files are committed
== pure + headless tests
== per-package builds, the way opam --with-test runs them
== live tests (xvfb)
== example smoke
all green
```

`test/live/expected_controllers.txt` after the round (the four new sections are the GC
regression, the family sweep, the `total=` column, and the partial-focus-family case):

```
before gc: gtk=(bonsai_gtk.focus bonsai_gtk.click) bonsai=2 total=3
after gc: gtk=(bonsai_gtk.focus bonsai_gtk.click) bonsai=2 total=3
after gc: button=2 phase=BUBBLE
gc regression done
On_click -> family=(Click) attached=(bonsai_gtk.click)
On_focus_enter -> family=(Focus) attached=(bonsai_gtk.focus)
On_focus_leave -> family=(Focus) attached=(bonsai_gtk.focus)
every controller attr attaches a controller
(GtkWindow ...)
mounted target: gtk=(bonsai_gtk.focus bonsai_gtk.click) bonsai=2 total=5
mounted other: gtk=() bonsai=0 total=3
mounted gesture: button=2 phase=CAPTURE
focus into target: focus-enter
focus to other: focus-leave
focus during a patch: 
focus away again: focus-leave
click attr dropped: gtk=(bonsai_gtk.focus) bonsai=1 total=4
on_focus_enter alone dropped: gtk=(bonsai_gtk.focus) bonsai=1 total=4
focus in and out with only on_focus_leave: focus-leave
focus attrs dropped, click back: gtk=(bonsai_gtk.click) bonsai=1 total=4
focus after its attrs were dropped: 
both attrs back: gtk=(bonsai_gtk.focus bonsai_gtk.click) bonsai=2 total=5
re-added gesture: button=2 phase=CAPTURE
focus after the attrs came back: focus-enter
(GtkWindow ...)
before destroy: gtk=(bonsai_gtk.focus bonsai_gtk.click) bonsai=2 total=5
after destroy: gtk=() total=3
destroyed cleanly
```

## Carries after the fix round

Unchanged from the first report — the README Limitations sentence (Task 15), the gallery
Input section exercising `Attr.on_click` (Task 15/16), the absence of a `~phase` on
`Attr.on_focus_*`, and the end-to-end click/key gap in `docs/m1-backlog.md`. **Closed by
this round:** "`Controllers.attached_count`'s option list is hand-maintained" — it is now
derived from `Events.Family.all` like everything else in the module. **Added:** M6's
GClosure-holds-the-widget observation belongs with the backlog's unwritten finalization
test, which now has two reasons to be written.

---

# Fix round 2

**Commit:** `93c819c` "Fix round 2, N1: emptying the slots once, before any family is
touched" (6 files, +217/-24), on `m2`, on top of `328ca80`. No history rewrite, not
pushed, not merged.

**Gate:** `nix develop -c ./scripts/ci.sh` → `all green`.

---

## N1 — accepted; it was mine, and it bit in the shipped order too

The reviewer's analysis is exactly right, and the shared blame in their write-up is more
generous than the facts warrant: they proposed the one-line change, I applied it into a
per-family loop without checking the interaction, and I did not add an assertion that
could see it.

One correction to the review's framing, in the direction of "worse than described". The
review says "with `Click | Focus`, the frame that triggers it is one that drops the *focus*
attrs while keeping `on_click` — and the victim is the click slot, which no test in this
repo can observe". That was true of the tests as they stood, but the frame in question is
**already in the golden**: `focus attrs dropped, click back`. Adding `Controllers.armed`
and re-running round 1's code prints it directly, with no ordering change and no probe:

```
focus attrs dropped, click back: gtk=(bonsai_gtk.click) bonsai=1 total=4 armed=()
```

So the defect was live on the shipped ordering, on a line the suite already walked
through, and the only thing missing was a way to look at it.

## The fix, and where it differs from the ruling

The ruling was: the removal branch clears only its own family; `release` keeps the
all-families clear. I did that — `sync`'s `Some a, false` branch is
`Signals.clear_slots a.slots` again — **and additionally** hoisted a single `clear t` to
the top of `Controllers.update`, which is the reviewer's own suggested shape.

The reason for doing both rather than the branch alone: the branch-only version fixes N1
but silently drops the invariant round 1 added *on the reviewer's Minor 2* — that no slot
is armed while `gtk_widget_remove_controller` runs, since removal can itself provoke a
leave or a cancel. Reverting to the pre-round-1 behaviour to fix a round-1 regression would
have put Minor 2 back on the table. The up-front clear keeps both properties at once, and
the two together are what make the ordering irrelevant:

- nothing is armed when any `remove_controller` runs, because the emptying happens before
  any family is touched;
- every surviving family ends the frame armed, because the emptying no longer happens
  *between* two families' `sync` calls — each one's own `update_slots` re-arms it.

Unconditional rather than the review's guarded version, for the reason the review itself
offers: the condition is one more thing to get wrong, and the cost is a walk of at most
three short assoc lists per patched node per frame. Both `controllers.ml` and
`controllers.mli` state the two-invariant argument at the call site.

If the lead prefers the literal ruling — branch-only, no hoist — it is a one-line deletion
and I will make it, but it reopens Minor 2.

## How it is asserted: `Signals.armed` / `Controllers.armed`

The ruling asked for the click direction to be asserted "via the library's own slot
introspection (or `is_ours` + a `Payload` trampoline call)". I took the first, because the
second would have meant reaching into `connect_all`'s callback from a second file and would
still only have proved the trampoline, not the slot.

- `Signals.armed : slots -> Attr.Name.t list` — the names whose slot currently holds an
  attr, sorted, so a golden pins the set rather than the order a spec list was written in.
- `Controllers.armed : t -> Attr.Name.t list` — the same across every attached family,
  through the existing `Events.Family.t` match.

Both are documented as test introspection, and as the *only* way to see the distinction
they expose: an emptied slot is invisible from GTK's side, and for a signal that cannot be
synthesised it is invisible from the handler's side too, so "attached" and "will call
something" are two facts and only this says the second. Every controller line in
`live_controllers.ml` now carries `armed=`, which strengthens the file well beyond this
finding — the existing attach/detach lines now say what the controllers will *do*, not just
that they exist.

## The regression test, and that it is ordering-independent

A dedicated `n1` block (its own tree, its own presented window), asserting both directions:

```
n1 baseline: gtk=(bonsai_gtk.focus bonsai_gtk.click) bonsai=2 total=5 armed=(On_click On_focus_enter On_focus_leave)
n1 focus from presenting the window: focus-enter
n1 focus parked off the target: focus-leave
n1 baseline focus: focus-enter,focus-leave
n1 click family dropped: gtk=(bonsai_gtk.focus) bonsai=1 total=4 armed=(On_focus_enter On_focus_leave)
n1 focus in the same frame that dropped on_click: focus-enter,focus-leave
n1 both back: gtk=(bonsai_gtk.click bonsai_gtk.focus) bonsai=2 total=5 armed=(On_click On_focus_enter On_focus_leave)
n1 focus family dropped: gtk=(bonsai_gtk.click) bonsai=1 total=4 armed=(On_click)
n1 focus after its own family was dropped:
n1 regression done
```

- **Direction 1**, as ruled: the click family is dropped and the focus handlers are driven
  **in the same frame as the patch** — `focus_round` runs immediately after `P.patch` /
  `run_fixups`, with no intervening render. The focus attrs are byte-identical across that
  frame, so anything that stopped them firing came from the click removal.
- The baseline and post-patch rounds print *identically* (`focus-enter,focus-leave`). That
  cost two extra lines — the window presentation focuses the target, and each round is
  parked on the other button first — and it is what makes the two comparable at a glance
  rather than each needing its own reading. Both are labelled rather than silently drained.
- **Direction 2**: the focus family is dropped and `armed=(On_click)` says the gesture is
  still live. `armed=()` there is precisely the round-1 bug.

**Ordering-independence, verified by experiment rather than by argument.** I flipped
`Events.Family.t` to `Focus | Click` (a pure ordering change) and re-ran:

| | shipped `Click; Focus` | flipped `Focus; Click` |
|---|---|---|
| **with this fix** | `n1 click family dropped: armed=(On_focus_enter On_focus_leave)` · `n1 focus in the same frame…: focus-enter,focus-leave` · `n1 focus family dropped: armed=(On_click)` | **identical** on all three (only `gtk=`'s order moves, which is `observe_controllers`' order, GTK's not ours) |
| **with round 1's code** | `n1 focus family dropped: armed=()` | `n1 click family dropped: armed=()` · `n1 focus in the same frame…:` *(empty)* |

So the victim moves with the order and the test catches it either way — which is the
property that matters, because Task 5 appends `Key` and moves it again. The bottom-right
cell also reproduces the reviewer's own probe exactly.

## Gates after the round

```
$ nix develop -c dune build @all   -> clean
$ nix develop -c dune test         -> clean
$ BONSAI_GTK_LIVE_TESTS=1 nix develop -c xvfb-run -a dune build @test/live/runtest -> clean
$ nix develop -c ./scripts/ci.sh   -> all green
```

The `n1` focus lines were run three times before promotion and again after the flip
experiment; identical every time. (Determinism here is not free — it is why the
presentation transient is drained and every round starts parked on the same widget.)

## Carries after round 2

Unchanged: the README Limitations sentence (Task 15), the gallery Input section exercising
`Attr.on_click` (Task 15/16), no `~phase` on `Attr.on_focus_*`, and the end-to-end
click/key gap in `docs/m1-backlog.md`. **Note for Task 5:** `Events.Family.all` gains
`Key`, which moves which family is downstream of which in `update`'s loop — the `n1` block
is the test that says that does not matter, and it should gain a third direction (drop the
key family, assert click and focus survive) when `Key` lands.
