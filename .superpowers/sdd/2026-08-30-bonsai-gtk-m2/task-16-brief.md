### Task 16: `scripts/ci.sh` end to end, from a clean tree

The gate has run per task; this runs it once against the finished milestone from a state that matches a fresh clone, and fixes whatever only shows up there. Last because it is a gate, not content — Task 15 is the last task that writes anything a reader sees, which is what R6 asks for.

**Files:** whatever the run turns up (expected: nothing, or `.opam` regeneration and formatting).

- [ ] **Step 1: Clean and rebuild**

```bash
cd ~/src/bonsai_gtk
git status --porcelain          # expect empty; commit or stash anything here first
dune clean
nix develop -c ./scripts/ci.sh
```

Expect `all green`. `dune clean` removes promoted expect output and stale `.opam` files, so this is where a test that only passed because of a leftover artifact fails.

- [ ] **Step 2: Work through failures, in this order**

- **`nix build .#ocgtk`** — unrelated to M2 unless Task 14 moved something. If Task 14 left `.ocgtk-src` dirty, this builds the *pin*, not the checkout, so it should still pass; if it does not, report and stop rather than moving the pin.
- **format** — `dune fmt`, then the root `dune`/`dune-project` loop.
- **`git diff --exit-code -- '*.opam'`** — M2 adds no dune library, so this should not move. If it does, someone added a dependency without recording it in `dune-project`. (And apply the backlog's one-word fix while here: the check should be `git diff --exit-code HEAD -- '*.opam'` so *staged* drift is caught too.)
- **`@test/runtest`** — a diff after a clean build means a promoted block depended on ordering a fresh build changes. Read it; do not promote blind.
- **the two `-p` package builds** — the failure mode is a test directory that grew a dependency across the package line. `test/` may depend on `bonsai_gtk.vtree` only; `test/handle/` on `bonsai_gtk_test`. M2 added `test/test_events.ml` to the first — confirm `Events` is in `bonsai_gtk.vtree` and not in `bonsai_gtk`.
- **live tests** — the most likely genuine failure, because they depend on the GTK theme Xvfb gives them. An extra internal child in a dump or a new css class is a GTK version difference: accept, promote, and note it in the commit. A timing-dependent value is a test bug: fix the test.
- **example smoke** — a non-124 exit means the example crashed. Run it under `xvfb-run -a dune exec` directly to read the message.

- [ ] **Step 3: Verify the milestone against the spec, by hand**

```bash
ls src/widgets/
grep -c '| [A-Z]' src/widgets/registry.ml
grep -c 'MISMATCH' test/live/expected_events.txt   # expect 0
```

Every name in spec §7's M2 line must have a file and a registry arm: ListBox, FlowBox, Notebook, TextView, DropDown, LevelBar, Calendar, EditableLabel. Then check the controller attrs and `Expert.embed` are real, since neither is a widget and neither shows up in that count.

- [ ] **Step 4: Run the gallery under a real display**, not Xvfb, and click through the Input section. This is the only check on the controller attrs' end-to-end behaviour if Task 4's live tests landed on option (c), and it takes two minutes. If no real display is available, say so in the report and leave the item in `docs/m2-backlog.md` rather than quietly skipping it.

- [ ] **Step 5: Final commit (only if Step 2 changed anything)**

```bash
dune fmt 2>/dev/null; git add -A
GIT_EDITOR=true git commit -F - <<'MSG'
M2: clean-tree CI pass

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01Sg3Ci8U8kUKR8C3PL1pNSs
MSG
```

---

## Spec coverage (M2 slice)

| Spec section | Task |
|---|---|
| §5.1 constructors (`list_box`, `flow_box`, `notebook`, `text_view`, `drop_down`, `level_bar`, `calendar`, `editable_label`) | 6, 7, 8, 9, 10, 11 |
| §5.2 `Attr.t` — sealed; controller attrs brought forward from M3 | 1 (seal), 4 (click, focus), 5 (key) |
| §5.3 children shapes — keyed lists, the unordered marker | 2 (marker), 6, 7, 8 |
| §5.4 keys — required by three more containers; the show-one/select-many rule | 6, 7, 8 |
| §6.2 patcher algorithm — the reassert-only walk, `enqueue_fixups` | 2 |
| §6.3 `Reconcile.diff` — `?ordered` | 2 |
| §6.4 signals — the `Payload` spec, controllers, a signal on a non-widget object | 4, 5, 9 (the buffer) |
| §6.5 controlled props — buffer text, selections, current page, date, editing | 6, 7, 8, 9, 10, 11; 2 (`batch_if`) |
| §6.6 `Node.native` | unchanged; `Events` gives it `[]`, which is §6.6's rule (Task 1) |
| §7 M2 catalogue | 6–11; 15 marks it done |
| §8 effects | none — M3 |
| §9 testing — the headless handle rejects what the runtime rejects | 1, and every task after |
| §11 error handling — six new structural messages | 3, 5, 6, 8, 12 |
| M1 backlog "Do first in M2" (12 items) | 1 (3), 2 (4), 3 (5) |
| Downstream: `Expert.embed` | 12 |

## Rulings carried into this plan

The controller ruled these before writing; they are recorded so a task that finds one inconvenient argues with the ruling rather than quietly going the other way.

1. **`Attr.t` is sealed by a type re-export inside `Attr.Private`**, not by an abstract type plus a `repr` conversion. Same type, no allocation, one line per internal matcher. `Attr.Name.t` stays concrete, because `Attr_apply.unset`'s exhaustive match over it is what makes a new attr's restore-to-default impossible to forget.
2. **`Signals.spec` becomes a variant with an existential `Payload`** carrying both a payload built by `connect` and a return value handed back to GTK, plus a `declined` value for the emissions that reach no handler. `Read_back` stays for everything whose value is on the widget.
3. **Event controllers are attached on demand by a `Controllers` module** that reuses `Signals`' trampolines and slots, not by giving every widget three controllers at `create`.
4. **`on_key_pressed`'s handler returns a `Key_response.t`**, not an effect: the decision is synchronous because GTK's routing is, and the effect rides along.
5. **`vtree/keyval.ml` hard-codes X11 keysyms**, pinned against `Gdk_constants` by a live test, so that view functions stay ocgtk-free.
6. **`list_ops.move` is an option**, and `None` is the unordered marker that stops `Reconcile` emitting `Move`. Not a separate `bool`.
7. **List box / flow box / notebook children are auto-wrapped and require keys**; per-child settings ride as attrs on the child, read by the parent, as `Attr.grid_cell` and `Attr.page_title` already do.
8. **A container that shows exactly one child raises on a name that does not resolve; a container with a plural selection ignores keys it cannot find.** Documented identically on `Node.stack`, `Node.notebook`, `Node.list_box` and `Node.flow_box`.
9. **Selections and the current page are applied from the fixup queue**, like a stack's visible child, because `reassert` runs before children are patched. A dropdown's selection is the exception and lives in `reassert`, because its items are props.
10. **`Expert.embed` parents nothing and refuses a `Node.window` root.** `Bonsai_gtk.start` is unchanged.
11. **ocgtk fork changes are prepared locally in one task at the end and never pushed.** Nothing before Task 14 may depend on them.

## Plan author's notes

Written for the controller. Five places where this plan disagrees with, or goes beyond, the brief — flagged rather than silently changed, per instructions.

1. **R5's premise is half wrong, in a way that does not change the task but does change what it will find.** The brief lists "nullable `Widget.set_name`, nullable `Stack_page.set_title`, nullable `Password_entry.get_placeholder_text`" as fork changes to collect. They are the right three, but **no fork patch for any of them exists** — the fork's six commits are five memory/ownership fixes and one new `Style_display` module, and the nullability comes straight from GIR annotations the generator honours. So Task 14 is not "collect the changes M2 made", it is "write three patches from scratch", and the first question it has to answer is whether the fix belongs in the generator (which would cover all four at once and matches what the maintainer preferred last time) or in a hand-patched stub. I have written the task that way. It is still one task and still not pushed.

2. **I put the clean-tree CI pass after the docs task, which reads against R6's "docs task last".** The docs have to describe the finished milestone, and the CI pass can only change formatting, `.opam` files and promoted goldens — never anything a reader sees. Putting CI last means the last *authored* task is docs, which I believe is what R6 is protecting; putting docs last literally would mean writing the README before the final gate had run. M1 made the same choice (its Task 11 was docs, Task 12 the CI pass) and I have followed it. If the controller wants the literal ordering, swap 15 and 16 — nothing else changes.

3. **The live tests may not be able to deliver a synthetic click or key press, and I have not pretended otherwise.** `Gobject.Signal.emit_by_name` takes no arguments and returns unit, so it cannot deliver `~n_press ~x ~y` or `~keyval ~keycode ~state`; there is no `GdkEvent` constructor in the binding; and I could not confirm from the signature survey whether a `gtk_test_*` helper is bound. Task 4 Step 1 makes the implementer *check*, choose among three options, and **write down which they got** — and if it is the weakest one (assert attach/detach, prove the handler headlessly, put the gap in the backlog), the plan says so in three places rather than one, because a milestone that ships two new event families with no end-to-end test of either is a thing the controller should know about before it ships, not after. The gallery's Input section and Task 16's real-display click-through are the compensating controls. **This is the single largest risk in the milestone** and I would rather it were visible than covered.

4. **I added two things the brief did not name, and both earn their place.** The first is `Attr.Name.all` (Task 1), because the M1 final review found `is_event` pinned on 2 names of 32 and the fix is one deriving plus one test — and because Task 13's "the gallery names every attr" check is impossible without it. The second is the constructor-time key check on `Node.list_box`/`Node.flow_box`/`Node.notebook`, and retrofitting it to `Node.stack` (Task 6, Step 1): M1 put the stack's check in the impl, which means a missing key is found at mount rather than at construction, and now that four containers need the same rule it is worth having in one place and earlier. Both are small; say if either should go.

5. **Two rulings in the brief I think are right but that a reviewer will push on, so I have written the reasoning into the code comments rather than only into the plan.** (a) Bringing the controller attrs forward from M3 makes M2 noticeably bigger — two tasks and five attrs — but the alternative is building `Payload`'s existential for `row-activated` alone, which does not need the `'r` return value, and then widening it again in M3 when the key controller arrives. Building it once against its hardest consumer is cheaper and the resulting type is better. (b) Auto-wrapping list-box rows rather than exposing a `Node.list_box_row` is the choice I am least certain of: it makes per-row settings into attrs-on-the-child, which is a pattern the codebase already has but which reads oddly the first time (`Attr.row_selectable false` on a `Node.label`). The alternative costs an extra node kind, an extra child-shape rule, and a new way to get it wrong. I have gone with wrapping and said so on the constructor; if the controller prefers the explicit row, Tasks 6 and 7 change shape but nothing else does.

One thing I could not check: the plan cites stavekeeper line numbers throughout, verified on 2026-08-29 against the working tree at `~/src/stavekeeper`. That tree had uncommitted changes when I read it. The citations are a reading aid, not a contract — the pre-flight scan says so.
