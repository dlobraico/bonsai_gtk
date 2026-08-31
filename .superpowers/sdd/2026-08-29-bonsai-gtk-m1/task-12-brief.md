### Task 12: `scripts/ci.sh` end to end, from a clean tree

The gate has been run per task; this runs it once against the finished milestone, from a state that matches what a fresh clone would produce, and fixes whatever only shows up there.

**Files:**
- Modify: whatever the run turns up (expected: nothing, or `.opam` regeneration and formatting)

- [ ] **Step 1: Clean and rebuild**

```bash
cd ~/src/bonsai_gtk
git status --porcelain          # expect empty; commit or stash anything here first
dune clean
nix develop -c ./scripts/ci.sh
```
Expect `all green`. A clean build is not the same build: `dune clean` removes promoted expect output and stale `.opam` files, so this is where a test that only passed because of a leftover artifact fails.

- [ ] **Step 2: Work through whatever fails, in this order**

- **`nix build .#ocgtk`** — unrelated to M1; if it fails, the pin or nixpkgs moved. Do not "fix" it by moving the pin: report it and stop, per `docs/upstream/README.md`'s process.
- **format** — `dune fmt`, then re-check that the root `dune`/`dune-project` pass `dune format-dune-file` (the loop in `ci.sh` covers them; the `@fmt` aliases do not).
- **`git diff --exit-code -- '*.opam'`** — `dune-project` gained no new dependency in M1 except through `src/dune`, which does not regenerate `.opam`; if this fails, someone added a package dependency without recording it. Add it to `dune-project`'s `(depends ...)` (`ocgtk` already covers `ocgtk.pango`, since dune's public names all belong to the one `ocgtk` opam package — verify that rather than assuming) and commit the regenerated file.
- **`@test/runtest`** — a diff here after a clean build means a promoted expect block depended on ordering that a fresh build changes. Read the diff; do not promote it blind.
- **live tests** — the most likely genuine failure, because they depend on the GTK theme Xvfb gives them. Symptoms and causes: an extra internal child in a dump (a GTK version difference — accept and promote, noting it in the commit), a `css` list gaining a class (same), a timing-dependent value like `child-revealed` (a transition that should have been `None_` in the test — fix the test, not the expectation).
- **example smoke** — a non-124 exit means the example crashed. Run it under `xvfb-run -a dune exec` directly to see the message; a `Gtk-CRITICAL` on stderr with exit 124 is *not* a failure of this gate but is worth fixing anyway, so read the output rather than only the status.

- [ ] **Step 3: Verify the milestone against the spec, by hand**

Open `docs/superpowers/specs/2026-08-28-bonsai-gtk-design.md` §7's M1 line and check off each name against `src/widgets/`:

```bash
ls src/widgets/
grep -c '| [A-Z]' src/widgets/registry.ml   # one arm per kind, plus Native
```
Every name in the spec's M1 line must have a file and a registry arm. `Node.native` is M0's, extended in Task 6 with `Native.Picture`.

- [ ] **Step 4: Final commit (only if Step 2 changed anything)**

```bash
dune fmt 2>/dev/null; git add -A
GIT_EDITOR=true git commit -F - <<'MSG'
M1: clean-tree CI pass

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01Sg3Ci8U8kUKR8C3PL1pNSs
MSG
```

---

## Spec coverage (M1 slice)

| Spec section | Task |
|---|---|
| §5.1 constructors (`label`, `button`, `entry`, ...) | 2, 3, 4, 5, 6, 7, 8, 9 |
| §5.2 `Attr.t` (opacity, focusable, can_focus, name, cursor, event attrs) | 2, 3, 4, 5, 7, 8, 9 |
| §5.3 children shapes — `None`, `Single`, `List`, `Slots` | 1 (`List` placement), 8 (`Slots`), 9 (grid/stack list ops) |
| §5.4 keys | 1, 8, 9 (`Stack` pages keyed; `Grid`/`Overlay` identity by key) |
| §6.2 patcher algorithm | 1, 8, 9 |
| §6.4 signals, handler slots, `notify::` family | 3 (mechanism), 4, 5, 7, 9 |
| §6.5 controlled text widgets | 4 (text), 3 and 5 and 7 and 9 (the same rule for `active`, `value`, `expanded`, `reveal`, `visible_child`) |
| §6.6 `Node.native` | 6 (`Native.Picture`, the first shipped one) |
| §7 M1 catalogue | 3 (Button, ToggleButton, CheckButton, Switch), 4 (Entry, PasswordEntry, SearchEntry), 5 (SpinButton, Scale, ProgressBar, Spinner), 6 (Image, Picture, Separator, `Node.native`), 7 (ScrolledWindow, Frame, Expander, Revealer), 8 (CenterBox, Paned, Overlay), 9 (Grid, Stack, StackSwitcher, StackSidebar) |
| §7 `freeze_notify`/`thaw_notify` batches | 3 (`Widget_impl.batch`), used by every impl after |
| §7 grid children re-attached on coordinate change | 9 |
| §7 stack pages keyed by name | 9 |
| §8 effects | none — M3 |
| §9 testing (pure/headless/live) | every task; 10 sweeps |
| §11 error handling | 3 (`require_specs`), 8 (slot mismatch), 9 (missing cell, missing key, unresolvable stack name), 1 (broken driver) |
| M0 backlog "Do first in M1" | 1 (all three) |

## Open questions

The controller rules on these before execution; each has a recommendation and the task that would change if the ruling goes the other way.

1. **Seal `Attr.t` (and `Bonsai_gtk_test.Action.t`) in the public surface?** M0's backlog flags this: `Attr.t` is a public variant, so each of M1's ~14 new constructors breaks any downstream exhaustive match. Sealing properly means making `Attr.t` abstract in `vtree/attr.mli` and exposing the variant as `Attr.Private.repr : t -> repr`, which `Attr_apply`, `Signals` and `Bonsai_gtk_test` (all outside the module) would go through. That is a real refactor touching four files plus every task below it. **Recommendation: seal `Attr.t` in Task 2, before the constructors land, and leave `Attr.Name.t` and `Action.t` concrete** — `Name.t` is only reachable through `Attrs.op`, which is `Private`-adjacent already, and `Action.t` is written by test authors as a literal (`do_actions handle [ Click "inc" ]`), where a constructor is the ergonomic form and a breaking change is a test-file edit, not a downstream outage. If the ruling is "defer", move the item to the M2 backlog in Task 11 and drop the sealing step from Task 2.

2. **Is `Scale`'s (and `SpinButton`'s) value controlled like text?** The spec names only the text widgets in §6.5. Applying the same rule to a slider means a drag the model declines snaps back, which is correct-but-jarring; not applying it means the widget and the model can diverge silently, which is worse and is the exact class of bug §6.5 exists to prevent. **Recommendation: yes, controlled, on the identical rule (compare against the widget's current value, not the previous node's)** — as written in Task 5, with the caveat documented on `Node.scale`. Note the deliberate exception already in the plan: `Paned`'s position is *not* controlled, because it is dragged continuously and re-asserting it every frame makes the handle immovable; that asymmetry is worth the controller's explicit blessing.

3. **How do `StackSwitcher`/`StackSidebar` refer to their `Stack`?** They need a live widget handle, which the vtree cannot hold. The options are (a) a string name registered by `Node.stack ~name` and resolved by a post-patch fixup pass — Task 9 as written; (b) making the switcher a container whose child is the stack, which is wrong (they must be siblings); (c) leaving both to `Node.native`, which drops two widgets from the M1 line. **Recommendation: (a).** It costs one hashtable and one queue on `Patcher.ctx`, it is order-independent (a switcher above its stack is the ordinary layout), and the same mechanism is what M3's `Node.windows` and `Attr.mnemonic_widget` will need. The cost is a second kind of name alongside `Key.t`; if that is judged too much, the fallback is (c) plus a backlog item.

4. **Should `Overlay`'s and `Stack`'s `move` be a silent no-op, or should `list_ops` say "unordered" out loud?** GTK offers no reorder for either. Task 8 and 9 make `move` a no-op and document it. A cleaner shape is a flag on `list_ops` that tells the patcher not to emit `Move` at all, so the reconciler's ops and GTK's reality never disagree even in principle. **Recommendation: no-op for M1, with the doc comment, and revisit in M2 when `Notebook` (which does have `reorder_child`) shares the machinery** — the flag is easy to add later and hard to design well against one example.

5. **Does `Attr.on_changed` fire on `SearchEntry` as well as `on_search_changed`?** Task 4 connects both: `changed` (immediate, via `GtkEditable`) and `search-changed` (debounced). An app that attaches both gets two events per keystroke burst. **Recommendation: expose both, as written, and document the choice on `Node.search_entry`** ("`on_changed` when the model owns the text, `on_search_changed` when a store is being queried") — the alternative, suppressing `changed` on search entries, would make `SearchEntry` the one text widget whose controlled-text story differs from the others'.

6. **`Live_tree.dump` verbosity.** GTK's internal children (a `GtkEntry`'s `GtkText`, a `GtkScrolledWindow`'s two scrollbars, a `GtkButton`'s label) appear in every dump and will make the expected files long. **Recommendation: keep them.** They are what GTK actually holds, which is the whole point of a live dump, and their presence is itself a check that a child landed inside a viewport rather than beside it. If a file becomes genuinely unreadable, add a type-keyed suppression list to `Live_tree` and document it in the mli — do not trim expected files by hand.

## Rulings on the open questions (controller, 2026-08-29)

1. Seal `Attr.t` in Task 2 via `Attr.Private.repr`; `Attr.Name.t` and `Bonsai_gtk_test.Action.t` stay concrete.
2. `Scale`/`SpinButton` values are controlled exactly like text (compare against the widget's live value, not the previous node); `Paned`'s position is the documented exception.
3. `StackSwitcher`/`StackSidebar` find their `Stack` by a string name registered with `Node.stack ~name`, resolved by an order-independent post-patch fixup pass.
4. `Overlay`/`Stack` `move` is a silent no-op with a doc comment in M1; revisit when `Notebook` (M2) shares the list machinery.
5. `SearchEntry` exposes both `Attr.on_changed` and `Attr.on_search_changed`, documented on `Node.search_entry`.
6. `Live_tree.dump` keeps GTK's internal children.
