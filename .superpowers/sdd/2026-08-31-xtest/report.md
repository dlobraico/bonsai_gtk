# The XTEST bead — a re-runnable test for the input path

Branch `xtest-input`, from `main` at `b4cac1d`. Bead `bonsai_gtk-5qv`. No push, no merge,
no `bd`.

## Commits

| sha | what |
|---|---|
| `334b674` | `xdotool` joins `xvfb-run` in the default devShell; the two by-hand click-through scripts lose their hardcoded `/nix/store` PATH line and gain an up-front `command -v` check for the three programs they need. |
| `d0a761e` | `test/live/live_input.ml`, `test/live/expected_input.txt`, and its rule in `test/live/dune`. |
| `5150c7e` | `docs/m2-backlog.md` (item closed, framing corrected, one new fork item), `README.md` Limitations, and the two stale rule counts in `test/live/dune` / `scripts/ci.sh`. |

The by-hand scripts live under `.superpowers/sdd/2026-08-30-bonsai-gtk-m2/task-16-clickthrough/`,
which `.superpowers/.gitignore` excludes, so their fix is on disk and not in a commit. That
is the only part of the brief that could not be committed.

## What the test is

`test/live/live_input.ml` is the twelfth live executable and is both the application and
the driver. It mounts a small tree through the patcher (`Node.window` → box → a click
target label, a box carrying a `Capture`-phase `Attr.on_key_pressed` over two entries, and
a `GtkButton` click target), presents it, pumps until mapped, computes each target's
geometry from the binding, spawns `xdotool` with `Unix.create_process`, and pumps its own
main loop until the handler's counter moves.

No sleeps, no screenshots, no hardcoded pixels:

- **the wait** is `pump_until`, which does *blocking* `Glib.Main.iteration true` and stops
  the instant the counter moves. Its bound is a `Glib.Timeout` source, which exists only so
  that a *failure* terminates — on the passing path it is removed without having fired.
  Nothing in the file waits on wall-clock time. A second bound (100 000 iterations) sits
  under it for a source that is always ready;
- **the coordinates** come from `translate_coordinates` + `get_width`/`get_height` per
  target, and every click is aimed at a computed point and then checked against the
  widget-local coordinates the handler reports (`hit-aim`);
- **the readouts** are values diffed against a golden.

Three counters (`clicks`, `keys`, `focuses`) rather than one, because each block waits for
its own event: `xdotool keydown ctrl` is a real key press, so a single "something fired"
counter would have woken the ctrl-click block on `Control_L` before the click arrived.

## What each golden line proves

```
mapped: true                                   the toplevel is mapped, so it has an
                                               allocation and a window xdotool can find
label geometry: compute_bounds=true origin=true box-positive=true bounds-is-box=true
                                               GTK answered both geometry calls, and for a
                                               plain widget they agree exactly
compute_bounds rect survives a later ocgtk call: false
                                               the ocgtk hazard below, pinned
window active: true                            `xdotool search … windowfocus` gave this
                                               process the X input focus (XTEST, not
                                               XSendEvent — see below)
entry 1 has focus on activation: true          the baseline the focus assertions differ from
on activation: (focus-enter e1)                GTK focuses the first focusable widget when
                                               the toplevel activates, and `on_focus_enter`
                                               fires for it
button 1: (label button=1 n_press=1 hit-aim=true in-bounds=true mods=none)
button 2: (label button=2 …)                   buttons 1, 2 and 3 each reported as
button 3: (label button=3 …)                   themselves, through one `~button:0` gesture
                                               — a `GtkButton` would never see 2 or 3.
                                               `hit-aim` is the widget-local coordinates
                                               matching the aimed point to within 1 px;
                                               `in-bounds` is them lying inside the target
double click: (… n_press=1 … n_press=2 …)      GTK emits the gesture once per press and the
                                               second carries n_press 2
ctrl click: (capture Control_L mods=none entry1 Control_L label button=1 … mods=control)
                                               the ctrl modifier is carried on the click;
                                               the Control_L press itself reaches both key
                                               controllers on the way, which is honest and
                                               is why the line names it
10 px below the target, then a sentinel on it: (label button=1 …)
                                               THE NEGATIVE. A click 10 px past the
                                               target's bottom edge moved nothing: the line
                                               carries only the sentinel that followed it.
                                               This is what makes the coordinates real
                                               rather than lucky, and it is what would fail
                                               if the toplevel were not at (0,0)
button geometry: … bounds-is-box=false         a themed GtkButton's compute_bounds is NOT
                                               its widget box (below)
primary click on a GtkButton: (focus-leave e1 button button=1 n_press=1 hit-aim=true …)
                                               an `Attr.on_click` on a GtkButton does see
                                               the press despite the button's own gesture
                                               claiming the sequence; the button also takes
                                               the focus, hence the `focus-leave e1`
click into entry 2: (focus-enter e2)           focus on a click, gaining half
focus: e1=false e2=true
click back into entry 1: (focus-leave e2 focus-enter e1)
                                               focus on a click, the leave/enter pair
focus: e1=true e2=false
key x: (capture x mods=none)                   a printable key reaches the capture handler
entry 1 text after x: "x"                      …and, propagated, reaches the entry
key F1 (capture propagates): (capture F1 mods=none entry1 F1)
                                               THE CONTROL. A key the GtkText does not
                                               consume propagates out of the capture
                                               handler and reaches the entry's own
                                               bubble-phase controller
key Escape (capture handles): (capture Escape mods=none)
                                               Escape is `Handled` in the capture phase and
                                               entry 1's controller never runs — the one
                                               line that differs from the F1 line, and the
                                               only direct evidence anywhere that
                                               `Key_response.Handled` stops GTK's routing
entry 1 text after Escape: "x"                 …and the entry's text is untouched
Tab: (capture Tab mods=none entry1 Tab focus-leave e1 focus-enter e2)
                                               focus enter/leave on Tab, and Tab propagating
                                               through both controllers on the way
focus after Tab: e1=false e2=true
```

### The goldens are instruments, not transcripts

Three mutations, all run:

| mutation | result |
|---|---|
| capture handler returns `Propagate` for Escape instead of `Handled` | **caught** — `key Escape … (capture Escape mods=none entry1 Escape)` |
| the "miss" click aimed 10 px *inside* the target instead of 10 px past it | **caught** — the line gains a `hit-aim=false` event in front of the sentinel |
| aiming from `compute_bounds` rather than from the widget box (this was not a deliberate mutation — it was the first version of the file) | **caught** — `hit-aim=false` on the GtkButton, which is how the finding below was made |

## Two findings, both pinned by golden lines

**1. `compute_bounds` is the wrong call for aiming a click.** The design sketch and the
backlog both name it, and it is bound, and for a plain widget it is exactly right (the
label reports `bounds-is-box=true`). It is *not* the rectangle a gesture reports
coordinates in. Measured: a themed `GtkButton` allocated 320x120 has a widget box of
286x110 inset by (17,5), and `compute_bounds` answers with the whole 320x120 — the region
the widget draws in, which is what its own documentation says and which CSS puts outside
the box. Aiming at the centre of the bounds lands 17 px left and 5 px above the centre of
the button. That is the same shape of miss that made a working handler look broken in the
by-hand run. The right pair is `translate_coordinates` of (0,0) plus
`get_width`/`get_height`, which is what the file uses; `bounds-is-box` is reported per
target so the difference is on the record rather than in a comment.

**2. The `graphene_rect_t` `compute_bounds` answers with points into a destroyed stack
frame.** Read its width immediately: 320. Make one more call into the binding, read again:
0. Measured directly (`before=(0.00,0.00,320.00,120.00) after=(-0.00,0.00,0.00,0.00)`).

*Sharpened in fix round 1, per the review's Important 1, which is right on every point.*
This is not a lifetime convention and not a stale-but-defined buffer. The stub declares the
out-parameter as a C stack local and hands its address to `Val_graphene_rect_t`, which is
`ml_gir_record_val_ptr_with_type(...)` — a val_ptr wrapper that does not copy. So the OCaml
value points into a frame `CAMLreturn` destroys and every read through it is a
read-after-return: undefined behaviour. Two consequences the original wording hid, both now
written into `box_of`'s comment and the backlog:

- **`box_of`'s workaround is luck, not safety.** Reading all four fields "immediately"
  still dereferences the dead frame, and each accessor is itself a C call pushing a frame
  that may or may not land on the same bytes. It is a workaround for a generator bug, not a
  pattern to copy.
- **Two golden lines are therefore canaries rather than assertions about this library** —
  `bounds-is-box=…` and the `survives` line. An ocgtk rebuild could move them with no
  change here. Nothing the test *asserts* depends on them: the aim comes from
  `translate_coordinates` and `get_width`/`get_height`, so every click, every `hit-aim` and
  the negative are unaffected. Across the review's 20 runs and this branch's own, neither
  moved.

**And it is 153 stubs, not one.** I reproduced the review's sweep independently — a local
`<type> outN;` handed to `Val_<type>(&outN)` — and got the same numbers to the stub:
**153 across 22 files**, `graphene_vec3_t` 28 · `graphene_rect_t` 22 · `graphene_point3d_t`
18 · `graphene_vec4_t` 17 · `graphene_vec2_t` 16 · `graphene_point_t` 13 ·
`graphene_matrix_t` 10 · `graphene_box_t` 8 · `graphene_quaternion_t` 8 · `graphene_plane_t`
4 · `graphene_sphere_t` 3 · `graphene_quad_t` 2 · `graphene_size_t` 2 · `graphene_euler_t` 1
· `graphene_ray_t` 1. (Counted at the fork's `4ae6698c`; the pinned `649498b4` is not in the
local ocgtk checkout, but this is generator output.) That count is what turns the backlog
item from "worth checking every stub that returns a boxed struct" into scoped work: one
generator change — allocate and copy, the way the record converters already do for
transfer-full returns — plus a regeneration closes all 153. Filed that way under "Still open
on the fork" in `docs/m2-backlog.md`.

## What xdotool could not deliver, and other empirical limits

Nothing xdotool was asked for failed. Four things were learned by trying, and all four are
written into the test's comments:

- **XTEST, not XSendEvent.** `xdotool key --window $WID` is XSendEvent and GTK drops events
  with the `send_event` record set, so it delivers nothing; `xdotool search … windowfocus`
  followed by a plain `key` is XTEST and works. There is no window manager under Xvfb, so
  `windowactivate` fails and is not needed. (Task 16's finding, re-stated in the file
  because it is the first thing a "simplification" would break.)
- **A `GtkEntry`'s bubble-phase key controller never sees a printable key.** The `GtkText`
  inside a `GtkEntry` consumes it in the target phase to insert it, so the bubble phase
  never reaches the `GtkEntry` the attr is on. This is GTK, not this library. It is why the
  propagation proof uses the entry's *text* as the evidence that the printable arrived, and
  F1 (which `GtkText` does not consume) as the control for the Escape assertion.
- **An `Attr.on_click` on a `GtkButton` does see the press**, despite the button's own
  `GtkGestureClick` claiming the sequence. Recorded rather than assumed; the assertions that
  have to be exact are on the label.
- **Single clicks must be spread apart.** GTK resets a gesture's press count only when two
  presses are more than `gtk-double-click-distance` (5 px) apart, and it does not appear to
  require the same button. A one-line label is ~20 px tall, so its quarter-points are inside
  that distance and the second single click would arrive as `n_press = 2`. The target
  therefore requests 320x120 and the click points are ≥30 px apart.

## Determinism

| batch | command | result |
|---|---|---|
| clean, 10 runs | `BONSAI_GTK_LIVE_TESTS=1 nix develop -c xvfb-run -a dune build @test/live/runtest`, with `rm -f _build/default/test/live/output_*.txt` before each (otherwise dune caches the targets and the run is a no-op — `ci.sh` does the same `rm` for the same reason) | **10 / 10 pass, 0 fail** |
| 2x oversubscription, 5 runs | same, with 48 spinning shell loops on a 24-core host; load average went from 5.03 at the start to 49.99 at the end | **5 / 5 pass, 0 fail** |
| full gate, twice consecutively | `nix develop -c ./scripts/ci.sh` | **both `all green`**, 60 s and 59 s |

~~The `live_embed` bound-ratio flake the final review measured at 2x oversubscription
(`bound_ratio = 1.2`, review C2) did not fire in either loaded batch. It is unrelated to
this work and remains open.~~ **Corrected in fix round 1:** C2 was *closed* before this
branch began, by the M2 fix wave in `ad21cc3` (an ancestor of `main`), which interleaved
the two measurement phases into one loop with two accumulators and raised `frames` from
2 000 to 20 000. The `ratio 1.00` with two equal sides that both ci tails below show is the
signature of the interleaved bench, not a flake declining to fire — the pre-fix sequential
version reported ~0.87 with the two sides visibly different. The fixed code was in this
branch's own tree, at `b4cac1d:test/live/live_embed.ml:581-612`, naming "final review, live
C2" in its comment, while the original sentence was being written. That was a
record-keeping error, not a measurement one.

The live rule really runs inside `ci.sh`: `_build/default/test/live/output_input.txt` was
rewritten 32 s before the shell prompt returned from the second gate run.

### Both ci.sh tails

```
ci3 exit=0 elapsed=60s
bench: calendar 0.00017 ms settled, 0.00013 ms parked on a refused date, ratio 0.77
bench: editable label 0.00020 ms at 16 chars, 0.00013 ms parked on a refused write, 1.23073 ms at 100 000 chars (the compare is O(len), as every entry's already is)
bench: entry 0.00029 ms settled at 16 chars, 0.00019 ms parked on a refused 100 000-char write, ratio 0.65
live_embed: the bonsai_gtk frame exception that follows is expected
bonsai_gtk: exception in frame, stopping the driver: (Invalid_argument
  "root/1: a Node.window may only be the root node, not a child of another node")
bench: 0.0103 ms embedded, 0.0103 ms windowed, ratio 1.00 (bound 1.2)
== example smoke
all green
```

```
ci4 exit=0 elapsed=59s
bench: calendar 0.00017 ms settled, 0.00013 ms parked on a refused date, ratio 0.76
bench: editable label 0.00020 ms at 16 chars, 0.00014 ms parked on a refused write, 1.23307 ms at 100 000 chars (the compare is O(len), as every entry's already is)
bench: entry 0.00022 ms settled at 16 chars, 0.00016 ms parked on a refused 100 000-char write, ratio 0.70
live_embed: the bonsai_gtk frame exception that follows is expected
bonsai_gtk: exception in frame, stopping the driver: (Invalid_argument
  "root/1: a Node.window may only be the root node, not a child of another node")
bench: 0.0083 ms embedded, 0.0083 ms windowed, ratio 1.00 (bound 1.2)
== example smoke
all green
```

## Deviations from the design sketch, with reasons

1. **The primary click target is a `Node.label`, not a `Node.button`.** The sketch said "a
   button with `Attr.on_click`". A `GtkButton` carries a `GtkGestureClick` of its own, and
   the exact assertions (three button numbers, `n_press` 2, an aimed coordinate) should not
   depend on how two gestures on one widget share a claimed sequence. The button is still in
   the tree as a *second* target with the same assertions, so the golden records what a
   `GtkButton` does — it sees the press, with the right button, count and coordinates — and
   the label carries the load. Nothing was lost; a fact was gained.

2. **Aim comes from `translate_coordinates` + `get_width`/`get_height`, not from
   `compute_bounds`.** The sketch named `compute_bounds`. It is wrong for this purpose, for
   the measured reason above. `compute_bounds` is still called for every target and its
   agreement with the box is a golden line, so the sketch's call is reported rather than
   dropped.

3. **The rule is red, not skipped, where `xdotool` is absent.** The sketch asked for "a
   second `enabled_if` clause or a `(deps %{bin:xdotool})` so it is skipped rather than red".
   Dune's `enabled_if` has no "does this binary exist" predicate, and the only way to get
   *skipped* would be a second environment variable nobody sets. `%{bin:xdotool}` was chosen:
   it declares the dependency **and** hands the executable an absolute path, so the test does
   not depend on `PATH` at all, and a dev shell without xdotool fails at the rule with
   "Program xdotool not found" — which names the actual problem, unlike the "no window" the
   by-hand script produced. Since xdotool is now in the devShell, its absence means a
   misconfigured shell, which is a thing worth failing on rather than silently skipping the
   one test that covers the input path.

4. **The propagation proof needed a control the sketch did not anticipate.** "A printable key
   reaching both the capture handler AND the entry" cannot be shown through the entry's own
   controller, because `GtkText` consumes printables before the bubble phase (see above). The
   printable half is proved through the entry's text, and the "reaches the entry's own
   controller" half through F1, which nothing consumes. Escape's `Handled` is then a
   one-symbol difference from the F1 line rather than an unsupported negative.

5. **The three keys the sketch's tree did not have.** `xdotool keydown ctrl` is a real key
   press and reaches the key controllers before the click does, so the ctrl-click golden line
   names `Control_L`; and the file uses three separate counters rather than one so that each
   block waits for its own event rather than for that key press.

6. **A golden line about ocgtk rather than about this library.**
   `compute_bounds rect survives a later ocgtk call: false` asserts a binding bug. It is in
   the golden because the bug would break this file first and silently, and because a fork
   round that fixes it should have to notice. Precedent: `live_keyvals.ml` checks `Keyval`
   against `Gdk_constants` on every run for the same kind of reason.

## Still open

- **A real display.** This is X11 under Xvfb with no window manager and no compositor. GTK
  takes a different input path on Wayland (`gdk_wayland`). Named in the backlog and in the
  README as the residual.
- ~~**`live_embed.ml`'s `bound_ratio = 1.2`** (final review C2) is untouched and still
  open.~~ **Wrong; struck in fix round 1.** C2 was closed by `ad21cc3` before this branch
  began. Nothing about it is open.
- The ocgtk `graphene_rect_t` bug wants an upstream issue on the fork.

---

# Fix round 1

Against `.superpowers/sdd/2026-08-31-xtest/review.md` ("Approve", with a pre-merge list).
One commit, `1b3c98c`. Gate run once after: `all green`.

## Taken

**Minor 1 — the merge-blocker. The file's header recommended the call the file disproves.**
Correct, and the worst kind of stale comment: a maintainer who reads the header and not the
body reaches for exactly the call that produces a silent 17 px miss, which is the failure
this branch exists to prevent. Three places, not two — the review found the header bullet
(`:38`) and the `aim` comment (`:211`); the paragraph about the (0,0) toplevel also said
"a point computed from the widget's bounds". All three now say the widget *box*, and the
header bullet names `compute_bounds` explicitly as the wrong call with the measured reason
and a pointer to `box_of`, so the trap is disarmed for a reader who stops there.

**Important 1 — read-after-return, not "does not own its storage", and 153 of them.**
Accepted in full; the review is right on every point and the original characterisation was
the kind that reads as a convention one could rely on. Rewritten in three places:
`box_of`'s comment (which now says its own workaround is stack-layout luck rather than a
rule, so nobody adopts the pattern), the canary comment above the `survives` line (which
now says both diagnostic lines are reading UB and that nothing the test asserts depends on
them), and `docs/m2-backlog.md`, where the fork item is rewritten around the stub source,
the val_ptr wrapper, the 153/22 count with its type breakdown, and the one-generator-change
fix. I re-ran the sweep myself rather than transcribing it and got the same numbers to the
stub. No code changed; this is entirely characterisation, which is the point — the previous
wording would have had the next person patch a call site.

**A1 / Minor 2 — the `live_embed` bound-ratio claim.** Struck in both places. C2 was closed
by `ad21cc3` before this branch existed, the fixed code was in my own tree while I wrote
the sentence, and the `ratio 1.00` with two equal sides in my own pasted ci tails is the
interleaved bench's signature rather than a flake declining to fire. I read "did not fire
under load" as evidence the defect was dormant when it was evidence the fix was working —
the failure was not checking `git log` for the thing I was about to call open.

**Minor 3 — the README's "nor its text" half of the Escape claim.** Right that it proves
nothing: Escape is not printable, so a `GtkText` leaves the text alone either way. Replaced
with the evidence that is load-bearing — F1 propagating *to* the entry's own bubble-phase
controller against Escape not doing so, as a matched pair.

**Minor 4 — the README section under the wrong heading.** Renamed to "The input path, and
the one part of it still untested" and led with the real-display residual, so the section
under "What is deliberately still out" opens with the thing that is out.

**Minor 6 — `(Sys.get_argv ()).(1)`.** Now a `failwith` naming the expected argument and
how the dune rule supplies it. Verified by running the executable by hand under `xvfb`
without the path.

## Argued rather than taken

**Minor 5 — `in-bounds` never adds information.** True as stated: given `hit-aim=true` and
aim fractions strictly inside the box, `in-bounds` is implied, and the only aim with a
fraction of `1.0` is the miss, which never records. Kept, with a comment at the computation
saying exactly that — it is the guard for an aim point that is *not* strictly inside, which
is a plausible future addition (an edge or corner hit), and a golden field costs nothing to
keep and a mutation to reintroduce. The review flagged it to make it a choice; it is one,
and it is now recorded at the code rather than only here.

**Minor 7 — the by-hand scripts advertise a devShell that does not provide ImageMagick.**
Taken, but not by the route suggested. Adding `pkgs.imagemagick` beside `xdotool` would
make the message true and would put ImageMagick in every developer's shell — for two
git-ignored screenshot scripts that the committed test replaces, and whose whole point is
that the test reads values instead of pixels. `xdotool` earns its place in the shell
because a committed rule depends on it; ImageMagick does not. So the *message* is fixed
instead: the `xdotool` check says "run under `nix develop`", and the ImageMagick check says
it is deliberately not in the devShell and names adding it as the caller's option. Nothing
ships either way — `.superpowers/sdd/.gitignore` is `*` — but the next person now reads
something true.

## Gate

`nix develop -c ./scripts/ci.sh` once after the fix round: `all green`, exit 0.
The live alias was also re-run on its own beforehand to confirm the golden is byte-identical
— the round changed comments, one error message and two docs, and no observable behaviour.

## Merged
xtest-input merged --ff-only into main and pushed 2026-08-31; bead bonsai_gtk-5qv closed. The graphene read-after-return item (153 stubs, generator-wide) is the headline of the next fork round, recorded in docs/m2-backlog.md.
