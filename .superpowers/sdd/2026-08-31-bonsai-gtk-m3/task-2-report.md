# Task 2 report — the click that can claim, and the focus family grows up

Branch `m3`, commits `b7484cc..919f77d` (five). `nix develop -c ./scripts/ci.sh`:
**all green** at `919f77d` (tail below).

## What changed

**`199c48e` — Click_response and the on_click re-type (steps 1, 2, and step 6's
live half).**
`vtree/click_response.ml` is Key_response's click twin (`Continue | Claim |
Continue_and | Claim_and`, plus `claim`, `effect`, `handler`, the `<effect>`-hiding
sexps). `Attr.on_click`'s handler is re-typed to `Click_event.t -> Click_response.t`
— source-breaking by design, taken cleanly: every caller in the repository updated
(tests, live suites, examples), no compat shim; `Bonsai_gtk` re-exports the module.
The trampoline (`Controllers.click_spec`'s `fire`) calls
`Gesture.set_state (gc :> W.Gesture.t) `CLAIMED` synchronously on the C stack when
the response claims, ignoring the `bool` by type; the three no-handler paths claim
nothing (`declined` is `Continue`-shaped), preserving M2's card-inside-listbox
behaviour. `Bonsai_gtk_test.Click_at` prints the response and performs its effect on
`Key_press`'s precedent; `test_attrs` pins `claim`/`effect` over all four
constructors. `live_input.ml` gains the end-to-end block: a nested pair of
bubble-phase gestures driven by real XTEST presses — under `Claim` the outer handler
is silent, under `Continue` both fire, inner first. The pair sits *beside* the button
target because the Xvfb screen is 640×480 and a fourth row would fall below it.
The whole live suite (with the new block) ran 10/10 consecutively.

**`111c799` — focus `?phase`, `on_contains_focus_changed`, `family_phase_rejection`
(step 3).**
`Attr.on_focus_enter`/`on_focus_leave` gain `?phase` (default `Bubble`), carried in
the constructor because it is a controller property. `Attr.on_contains_focus_changed`
is the `contains_focus` query as an event: a `Read_back` on
`notify::contains-focus` of the *controller* — `Signals.notify_connection` names the
controller object, which is what `Signals.connection` exists for — with
`Event_controller_focus.contains_focus` read back at fire time. It carries no phase
(a notify fires in no propagation phase) and does not vote in the family's phase.
`Events.key_phase_rejection` generalises to
`family_phase_rejection : path:string -> Family.t -> Attrs.t -> string option`,
walking the family's *phased* attrs in `Attr.Name` order and naming the first two
that disagree plus the family's controller class. The Key family's message text is
byte-identical, so its goldens hold. `Controllers.configure_phase` (shared by Focus
and Key) and `Bonsai_gtk_test`'s per-family loop both render it.
Headless: a `Focus_contains` action driving both directions; the Focus-family phase
disagreement rejected with mount's string; a phaseless contains-focus attr beside a
phased one accepted. Live (`live_controllers_focus`, plus a
`focus_controller_props` probe in the util): the phase reaches the
`GtkEventControllerFocus` (`CAPTURE` read back, re-phased to `BUBBLE` on patch) and
contains-focus fires with real focus motion — the golden pins the emission order
(`contains=true,enter`). The `live_controllers_click` sweep gains the new attr's row.

**`561c559` — `require_slots` on the patch path (step 4).**
The M2-review one-liner: `patch` calls `Signals.require_slots` beside
`require_specs`, under the same non-empty-diff guard.

**`270cfad` + `919f77d` — `Attr.autofocus` (step 5).**
Fire-once, from the fixup queue, exactly per the controller's ruling and pre-flight
correction 5. The patcher enqueues a claim at mount for a node carrying `true` and
at patch on the false→true edge (read against the *old* node's attrs, before
`live.node <- node`); a kind-change remount is a fresh mount and re-fires.
`Patcher_fixups.run_fixups` drains the generic queue and then applies the pass's
autofocus claims together: grouped by `Widget.get_root` (rootless claims — an
embed's pre-parented tree — group together), two grabs in one toplevel raise
`Events.autofocus_rejection` naming both paths, otherwise each fires one
`Widget.grab_focus` whose `bool` is deliberately dropped. Reassert-only frames
enqueue nothing, so a parked frame costs nothing and never fights the user.
`Bonsai_gtk_test` tracks the same edges per frame — by node path, reset per
`create` — and renders the same string; the what-is-checked table gains row 17 with
the path-identity caveat spelled out.
Headless: the mount-frame duplicate rejected; the staged shape (one widget keeps
rendering `true`, a second flips later) accepted across frames. Live
(`live_controllers_focus`, 5/5 runs): the mount grab sticks across the map (probed
with `Window.get_focus` + `Widget.is_ancestor`, never `has_focus` on the entry, per
pre-flight correction 5); the flip moves focus; a re-render with no edge leaves the
user's focus where the user put it; the duplicate raises from `run_fixups` with the
headless string. The gallery entry now carries the attr so the attr sweep pins it.

## What the tests prove

- The claim *routing* — a claimed sequence withheld from another live gesture — is
  proven by real X input, the one thing no other suite can see; the decision and the
  effect are pinned headlessly; the `set_state` constant and plumbing live in the
  trampoline the goldens exercise.
- The focus phase is proven *delivered* (read back off the live controller, and
  re-read on patch), not just carried; contains-focus is proven end to end
  (connect on the controller, read-back, dispatch, real focus motion).
- Autofocus's four contract facts (grab sticks, flip moves, no-edge writes nothing,
  duplicate raises) are all live-pinned, and the headless/runtime rejection strings
  are one function.
- ci.sh green: fmt, `@all`, opam files, headless, both `-p` builds, full live suite
  under xvfb, example smoke.

## Deviations from the plan, and choices the plan left open

1. **`key_phase`/`key_phase_rejection` are deleted**, not kept as thin wrappers —
   the implementer's choice step 3 offers. No caller outside this repository exists
   (the vtree is unreleased), both in-repo consumers now call the general function,
   and the Key message text is unchanged so goldens hold.
2. **Step 4 has no test.** Reaching the `require_slots` patch-path check requires a
   table/impl drift that `live_events.ml` already fails CI on; no tree buildable
   from the public surface can trigger it. The call is a backstop, and the commit
   says so.
3. **live_input's claim pair is horizontal**, beside the button target, because the
   Xvfb screen is 640×480 and the planned "two overlapping click targets" as a new
   row would sit below the screen. The nesting (outer box gesture around an inner
   label gesture, both bubble) is the overlap that matters for routing.
4. **The headless autofocus check is path-keyed**, which over-fires in exactly one
   case: a keyed child that *moves* while rendering `autofocus true` changes path
   and would be counted as firing again, where the live widget (same widget, no
   edge) would not. Documented in the mli (row 17); no tree in the repository moves
   an autofocused node.
5. **Click_at now prints a line** (`on_click <id> -> <response>`), so any future
   handle test using it gets a golden line the M2 version did not print — one
   existing test's golden moved (deliberately, to show `Claim_and`).
6. **The claim's own `bool` from `Gesture.set_state` and `grab_focus`'s are both
   ignored by type** — stated in comments; neither has a caller that could act on a
   refusal within the frame.

## Deliberately left undone

- README's Limitations rewrite ("cannot consume the click" is now false) — Task 13
  owns the docs; the attr's own mli doc is already correct.
- The full focus-is-state design (focus following the model, `select_region`,
  default widgets) — on the backlog by the controller's own ruling; `autofocus`'s
  mli says so.
- `Bonsai_gtk_test` modelling of claim routing — impossible headlessly and
  documented as such on `Click_at`.
- The two `Attrs.find`-based helpers stay in `Events` (`autofocus_requested`,
  `autofocus_rejection`) rather than a new module; they are two small functions on
  the module both consumers already import.

## ci.sh tail

```
== example smoke
(counter, gallery, embed each held for their 3 s timeout)
all green
```

Full gate at `919f77d`: nix ocgtk build, per-directory fmt, `dune build @all`,
committed .opam check, headless tests, both `-p` package builds, live suite under
xvfb, example smoke — all green. Additional stability runs: live_input 10/10,
live_controllers_focus 5/5 (each with its output deleted to force re-runs).

## Fix round 1

One commit, `6869497`, answering the review's Important 1 and Minors 2–4;
`nix develop -c ./scripts/ci.sh` all green at that commit.

- **Important 1 (doc-only, per the controller's ruling — no retry implemented):**
  `Attr.autofocus`'s mli now carries the honest paragraph: under
  `Bonsai_gtk.Expert.embed` the mount-frame grab does nothing — the tree has no
  `GtkRoot` at fixup time, and `gtk_widget_grab_focus` on a rootless widget returns
  FALSE outright, which fire-once never retries — while a later false→true flip
  after the host roots the wrapper works. The deferred-to-root-change fix is cited
  as bead `bonsai_gtk-vdy`.
- **Minor 2:** row 17 of the what-is-checked table and the `autofocus_fired`
  comment now document both divergence directions of the path-keyed approximation:
  the moving keyed child (headless over-fires) and the same-path kind-change
  remount (re-fires live, no edge headlessly, so a frame pairing it with a second
  widget's flip raises live and is certified headlessly).
- **Minor 3:** the three stale `key_phase_rejection` references
  (`vtree/attr.mli`, `test_lib/bonsai_gtk_test.mli`,
  `test/handle/test_gallery_tree.ml`) now name `family_phase_rejection`, with the
  surrounding prose updated where the old sentence was key-specific.
- **Minor 4:** `Events.attr_phase` is exhaustive with no wildcard, with a comment
  stating why (Task 7's shortcut family must be classified or nothing compiles).
  No behaviour change; build, headless and the full gate stay green.
- **Minor 5** (examples/gallery vs handle-gallery drift by one attr) deliberately
  not taken — deferred to Task 12 by the controller, recorded in the ledger.
