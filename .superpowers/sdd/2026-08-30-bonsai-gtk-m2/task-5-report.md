# Task 5 report — key controllers: the `bool` return, phases, and a keyval table `vtree` can name

**Commit:** `7ba161a` on `m2`, base `93c819c`. 27 files, +1472/-63.
**Gate:** `nix develop -c ./scripts/ci.sh` → `all green`.

---

## Per-step summary

### Step 1–2: the failing tests

`test/live/live_keyvals.ml` was written first, with its dune rule and
`expected_keyvals.txt` (`keyvals agree` / `out-of-range rejected`), and run to confirm
`Error: Unbound module "Keyval"`. It checks **every `val` in `keyval.mli`** against
`Ocgtk_gdk.Gdk_constants` — 17 named keysyms, both ends of `f`'s range, and six `of_char`
points — plus the two range rejections.

The other three test sites (`test/handle/test_handle.ml`, `test/test_attrs.ml`,
`test/live/live_controllers.ml`) were written after the modules they name existed, because
they need `Attr.on_key_pressed` to typecheck at all; they are listed with their evidence
below.

### Step 3: `vtree/keyval.ml(i)`, `key_event.ml`, `key_response.ml`

- `keyval.ml(i)` — the 17 keysyms as hex, `f : int -> int` (1..12, `Invalid_argument`
  outside), `of_char : char -> int` (0x20..0x7e, `Invalid_argument` outside). The mli
  carries the reasoning the brief specified.
- `key_event.ml` — `{ keyval; keycode; modifiers }` with `sexp_of, equal`.
- `key_response.ml` — the four constructors, plus `handled : t -> bool`,
  `effect : t -> unit Ui_effect.t option`, a hand-written `sexp_of_t` printing `<effect>`,
  and `type handler = Key_event.t -> t` with `sexp_of_handler` printing `<handler>`.

### Step 4: `vtree/attr.ml(i)`

`On_key_pressed of { phase; handler }` / `On_key_released of { phase; handler }` added to
`Name.t` (after `On_focus_leave`, so no existing `Attrs.diff` golden reorders), to
`Private.t`, to `name`, to `equal` (phase structurally, handler physically) and as smart
constructors defaulting `?phase` to `Bubble`. `attr.mli` carries the doc the brief wrote,
plus the `on_key_released` paragraph. The exhaustive matches in `src/attr_apply.ml`
(`set`, `unset`) and `vtree/placement.ml` (`reader`) gained their arms.

### Step 5: `src/controllers.ml` — the key family

`mutable key : W.Event_controller_key.t attached option`; `key_pressed_spec` /
`key_released_spec`, both `Payload`; the `Key` arm in `attached`, `update` and `release`.
`declined = Gdk_constants.event_propagate` (the constant, not a literal `false` — see
deviation 2).

### Step 6: `test_lib`

`Key_press of string * Key_event.t` and `Key_release of string * Key_event.t`. `Key_press`
**prints** the `Key_response.t` the handler answered and then performs the effect that
response carries; `Key_release` prints nothing (`key-released` returns `unit`). Both the
action doc and the `create` doc say what the handle cannot model — see "Testing option"
below.

### Step 7: `Events`

`Family.Key`, `controller_family`'s two arms — and, because the family table is exhaustive
and derived from, that was the whole of it: `is_controller_attr`, `family_attrs`,
`Signals.require_slots`'s skip and `Controllers.update`'s dispatch all followed with no
further edits. Adding `Key` produced exactly the four compile errors Task 4's fix round
promised.

### Step 8: run, read, promote, gate

`keyvals agree` on the first run — no `MISMATCH` line, so the hard-coded table is
confirmed against the pinned binding and the fallback the brief describes was not needed.

### Step 9: commit

`7ba161a`, message as specified plus two paragraphs on the two deviations.

---

## Testing option obtained, with evidence

**Key = plumbing only (the brief's option (c)), as pre-flight correction 1 predicted.**
Re-verified against `.ocgtk-src`: `Event_controller_key.forward : t -> Widget.t -> bool`
is documented "can only be used in handlers for the `key-pressed`, `key-released` or
`modifiers` signals" — it re-routes an event the controller is already processing, which
is a state no test can put it in; there is no `GdkEvent` constructor; `emit_by_name`
carries no arguments. So no synthetic key press.

What was landed instead, and what each piece actually pins:

| Fact | Where | Evidence in the golden |
|---|---|---|
| the keysym table is right | `live_keyvals.ml` | `keyvals agree`, checked against `Gdk_constants` |
| `of_char`/`f` reject rather than guess | `live_keyvals.ml`, `test_attrs.ml` | `out-of-range rejected`; two `Invalid_argument` goldens |
| both attrs attach **one** controller, named | `live_controllers.ml` | `keys both attrs: gtk=(bonsai_gtk.key) bonsai=1 total=4` — a `GtkButton` has three of its own, one of which is a `GtkEventControllerKey`, so the name filter is doing real work; `key_controller_props` fails loudly on a second one |
| the `~phase` reaches GTK | `live_controllers.ml` | `phase=CAPTURE` / `BUBBLE` / `TARGET`, read back off the live controller |
| a phase change re-configures rather than rebuilds | `live_controllers.ml` | `keys moved to target: … bonsai=1 total=4` with `phase=TARGET` |
| one attr going is not the family going | `live_controllers.ml` | `keys released dropped: … armed=(On_key_pressed)` — controller still there, one slot emptied |
| both attrs going removes the controller | `live_controllers.ml` | `keys both dropped: gtk=() bonsai=0 total=3`, `no key controller of ours` |
| every controller attr `Events` admits attaches one | `live_controllers.ml` sweep | `On_key_pressed -> family=(Key) attached=(bonsai_gtk.key)`, list asserted against `Attr.Name.all` |
| dropping a family does not disarm its siblings, **in all three directions** | `live_controllers.ml` n1 block | see below |
| differing phases are rejected, at mount **and** at patch | `live_controllers.ml` | `mount rejected: phases/0/0: …`, `patch rejected: …` |
| the handler's answer reaches GTK's `bool` | `live_controllers.ml` | `Propagate -> handled=false performed=false` … `(Handled_and <effect>) -> handled=true performed=true`, `declined=false event_propagate=false event_stop=true` |
| the handler logic itself | `test/handle/test_handle.ml` | `key_pressed sheet -> Propagate` then `key_pressed sheet -> (Handled_and <effect>)` with the model diff |
| the `Payload` trampoline's three `declined` paths | `live_signals.ml` (Task 4) | unchanged |

**The n1 regression block gained its third direction**, as Task 4's carry asked. It now
mounts all three families and drops each in turn:

```
n1 baseline:               armed=(On_click On_focus_enter On_focus_leave On_key_pressed On_key_released)
n1 click family dropped:   armed=(On_focus_enter On_focus_leave On_key_pressed On_key_released)
n1 focus in the same frame that dropped on_click: focus-enter,focus-leave
n1 focus family dropped:   armed=(On_click On_key_pressed On_key_released)
n1 key family dropped:     armed=(On_click On_focus_enter On_focus_leave)
n1 focus in the same frame that dropped the key attrs: focus-enter,focus-leave
```

Click is now first of three in `Family.all`, so the click-dropped direction is the widest
it has ever been: under round 1's bug it would have wiped both the focus and key slots.
The focus half is driven for real (`grab_focus` on a presented window) in the same frame
as the patch; the click and key halves are `Controllers.armed`, which is the only
observable there is.

**Not covered, and now written into `docs/m1-backlog.md`:** that GTK routes a real
keystroke to the controller, and — the part specific to keys — **that propagation works**.
No suite here can show that a `Handled` Escape failed to reach a sibling, or that a
`Capture`-phase controller saw the key before a child's `Bubble`-phase one. Every *input*
to GTK's routing is asserted (the phase on the object, the `bool` the handler answers, the
controller's presence on the right widget); the routing itself is GTK's and is unchecked.
The backlog entry now names that explicitly, names `gtk_test_widget_send_key` alongside
`gtk_test_widget_click` as what would close it, and the real-display click-through item now
asks for a `Capture`-phase key handler with a focusable child below it, since a wrong phase
is exactly the failure a plumbing test cannot see.

---

## Deviations from the task text, and why

1. **The differing-phase rule lives in `vtree/events.ml`, not only in
   `src/controllers.ml`.** The brief's Step 5 writes `key_phase` inside `Controllers`.
   Written there, the rejection would be a *fourth* structural mistake that
   `Bonsai_gtk_test` accepts and the runtime refuses — which is the failure mode
   `Events` and `Placement` were both created to remove, and which
   `bonsai_gtk_test.mli` warns about by name. So `Events.key_phase` and
   `Events.key_phase_rejection ~path` are in vtree, exactly on `Placement.rejection`'s
   pattern (one function renders the string, both consumers `invalid_arg` it), and
   `Controllers.configure_key` and `Bonsai_gtk_test.require_supported` call it. The two
   messages are identical outright — `test/handle/test_handle.ml` and
   `expected_controllers.txt` both contain
   `Attr.on_key_pressed asks for Capture and Attr.on_key_released for Bubble, but they
   share one GtkEventControllerKey and so one propagation phase`, differing only in the
   node path. The runtime check is ordered *after* placement and `require_specs`, matching
   mount order, so a node with two mistakes reports the same one in both places.

2. **`declined` is `Gdk_constants.event_propagate`, not a literal `false`**, and it is
   bound once as `Controllers.key_pressed_declined` so that the spec's `declined` and
   `key_pressed_answer`'s fallback cannot drift. The brief offered either spelling and
   asked which; this one, because `live_controllers.ml` can then pin it —
   `declined=false event_propagate=false event_stop=true` — against GDK rather than
   against a literal that would agree with itself. `key_released_spec`'s `declined` is
   `()`, which has no constant, so "consistent with `key_released_spec`" does not bind.

3. **No `Controllers.Private.key_controller` accessor.** The brief suggested one so the
   live test could read the phase. It is not needed: `Widget.observe_controllers` filtered
   by `Controllers.is_ours` and by GObject type name is exactly how `click_gesture_props`
   already reads the gesture's `button`/`phase`, and `key_controller_props` is the same
   five lines. It also asserts there is exactly **one** key controller of ours, which a
   direct accessor could not.

4. **A different test-only accessor was added instead:
   `Controllers.key_pressed_answer` (and `key_pressed_declined`).** The brief flags
   "a `Handled` that does not stop propagation would be a Critical". Auditing the chain,
   every link but one was already covered: `Key_response.handled` headlessly,
   `dispatch_payload`'s three `declined` paths in `live_signals.ml`, and
   trampoline-result → `key-pressed`'s return by the type system (the callback is
   `... -> bool` and `'r` is fixed to `bool` by `declined`). The uncovered link was the
   spec's own `fire` — reachable only through a real key press, and through the
   existential `Signals.spec` not reachable from a test at all. So `fire`'s body *is*
   `key_pressed_answer`, exposed and documented as test-facing (as `armed` and `is_ours`
   already are), and pinned over all four constructors. No duplication: the spec calls it.

5. **`src/gtk_import.ml` unchanged.** The brief lists it as a file to modify.
   `modifiers_of_gdk`, `propagation_phase` and the `Gdk_constants` alias all landed in
   Task 4 and needed nothing added.

6. **`Keyval.of_char 'A'` is not checked against the binding.** `gdk_constants.mli`
   genuinely declares `val key_a` twice — ocgtk's generator lowercases constant names, so
   X11's `XK_A` (65) and `XK_a` (97) collide and the second wins. The brief anticipated
   this ("if `key_A` does not exist, drop that line and say so in `of_char`'s doc"); that
   line is dropped and `keyval.mli`'s `of_char` doc says why, notes that a capital *is* its
   own keysym (`of_char 'A' = 65`, which is what GTK delivers for Shift+A), and points out
   that a handler wanting "the A key regardless of shift" has to match both or ask
   `modifiers`. `of_char 'W'` is still pinned in `test/test_attrs.ml` against the literal
   `0x57`, so the capitals are not unchecked, only uncheckable *against GDK*. The
   lowercase letters, a digit, and two punctuation marks are checked against the binding,
   which is the same claim over the same arithmetic.

7. **`Events.key_phase_rejection` uses plain `sprintf`, not `!"...%{sexp: Phase.t}..."`.**
   ocamlformat rewrites a `\`-continued `ppx_custom_printf` literal by joining the lines
   and *keeping* their indentation, which shipped a message with a 12-space run down the
   middle of it. Caught by the golden; `Placement.rejection` avoids it the same way.

8. **`Key_response.handler` is a named type.** `Attr.Private.t` derives `sexp_of`, and a
   bare `Key_event.t -> Key_response.t` field has no derivable `sexp_of` — the same reason
   `Handler.t` exists. `Attr.on_key_pressed`'s published signature is still
   `?phase:Phase.t -> (Key_event.t -> Key_response.t) -> t`; the alias is the same type.

9. **Extra tests beyond the brief's list.** `test/test_attrs.ml` gained the keysym table as
   a headless golden (so a value changing is a diff even without a display, and a reader
   can check it against `keysymdef.h`), the four-constructor `Key_response` table, the two
   `Invalid_argument` messages, and key-attr diffing including that `~phase` is part of the
   attr's identity. `test/handle/test_handle.ml` gained `Propagate_and` + `Key_release`
   (the observe-without-consuming case, which is the constructor a reader asks about), the
   phase-conflict rejection *and* its agreeing counterpart, and the two no-handler
   failures.

---

## Review-focus items, answered

- **`declined = event_propagate` is right and commented** — deviation 2, and pinned in the
  golden against GDK.
- **The differing-phase rejection has a test** — three: mount and patch in
  `live_controllers.ml`, and the handle in `test_handle.ml`, all sharing one message.
- **`Keyval`'s table is checked in full** — `keyval.mli` declares 17 values plus `f` and
  `of_char`; `live_keyvals.ml` has 17 `check` lines for the values, 2 for `f`'s ends, and 6
  for `of_char`. The one entry that cannot be checked against GDK is `of_char`'s capitals,
  for the reason in deviation 6.
- **`Key_press`'s inability to model propagation is in the mli** — in the action's own doc
  *and* in `create`'s opening summary, as a named second gap beside the structural one,
  which is where the brief asked for it.
- **`of_char`'s range check raises** — and the message names the range and says why the
  code point is not the keysym outside it.

---

## Gate output (tails)

```
$ nix develop -c dune test              -> exit 0, no output
$ BONSAI_GTK_LIVE_TESTS=1 nix develop -c xvfb-run -a dune build @test/live/runtest
                                        -> exit 0
   (one stderr line: live_driver.ml's deliberate raise,
    "root/0/1: a Node.window may only be the root node")
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

Note for anyone re-running the gate: plain `dune fmt` fails in this checkout — it walks
into the read-only `result/` nix symlink. Use the per-directory aliases `scripts/ci.sh`
uses: `dune build @vtree/fmt @src/fmt @test/fmt @test_lib/fmt @test/live/fmt @examples/fmt`.

---

## Carries

- **README Limitations** (Task 15) — now two sentences, not one. `Attr.on_click`'s doc
  promises a gesture that does not claim the sequence; `Attr.on_key_pressed`'s promises
  the opposite (a `Handled` that does), and neither claim has an end-to-end test. The
  Limitations section should say that key propagation and phase ordering are GTK's and are
  unverified here, and point at the backlog entry.
- **Gallery Input section** (Task 15/16) — should now exercise `Attr.on_key_pressed` in
  `Capture` phase over a focusable child, as well as `Attr.on_click`. It is the only
  compensating control for the phase, which is the half a plumbing test cannot see.
- **The focus `~phase` asymmetry** (carried from Task 4, still open) — `on_click`,
  `on_key_pressed` and `on_key_released` all take `?phase`; `on_focus_enter`/`on_focus_leave`
  do not, and `Controllers`' focus arm has a comment saying so. With two of three families
  now taking one, the asymmetry is more visible; adding `?phase` to the focus pair would
  make `Events.key_phase_rejection` generalise to a `family_phase_rejection` and remove the
  one-off. Not in this task's scope.
- **`Controllers.key_pressed_answer` / `key_pressed_declined` are test-facing exports.**
  They are `fire`'s body and `declined`'s value, so they cannot drift from the spec, but
  they do widen `controllers.mli`. If a future milestone finds a way to deliver a real key
  press, they become redundant and should go.
- **`test/live/live_controllers.ml` is getting long** (seven blocks, 827 lines). Nothing is
  wrong with it, but a Task 16 reader will want it split by family, or the click/key
  plumbing blocks merged — they assert the same four facts about different controllers.
