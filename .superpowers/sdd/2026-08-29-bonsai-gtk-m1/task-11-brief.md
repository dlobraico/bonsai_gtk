### Task 11: README's widget list, and rewriting `docs/m1-backlog.md`

**Files:**
- Modify: `README.md`, `docs/m1-backlog.md`

- [ ] **Step 1: README**

Four edits, no rewrite:

1. **Status line.** Replace "Status: pre-alpha (M0) — four widgets (`Label`, `Button`, `Box`, `Window`), the `Native` escape hatch, the runtime loop, and headless testing." with a sentence naming M1's coverage and pointing at the widget table below.
2. **A widget table**, new section after "Libraries", because "which widgets are there" is the first question anyone has:

```markdown
## Widgets

| | |
|---|---|
| **Display** | `Label` (wrap, xalign, ellipsize, max-width-chars, markup), `Image`, `Picture`, `Separator`, `ProgressBar`, `Spinner` |
| **Controls** | `Button` (label / icon / arbitrary child / frameless), `ToggleButton`, `CheckButton`, `Switch`, `SpinButton`, `Scale` |
| **Text** | `Entry`, `PasswordEntry`, `SearchEntry` — controlled: the widget is written only when the model disagrees with what it currently shows, so echoing what the user typed never moves the caret |
| **Layout** | `Box`, `Grid` (`Attr.grid_cell`), `CenterBox`, `Paned`, `Overlay` (`Attr.measure_overlay`), `Frame`, `Expander`, `Revealer`, `ScrolledWindow` |
| **Navigation** | `Stack` + `StackSwitcher` + `StackSidebar` (pages keyed by `Key.t`, switchers name their stack) |
| **Window** | `Window` (one per app until M3) |
| **Escape hatch** | `Node.native` for anything else, plus `Native.Picture` for a `GdkPaintable` source |

Shared attributes on every widget: `css_class`, `margin_*`, `halign`/`valign`,
`hexpand`/`vexpand`, `width_request`/`height_request`, `sensitive`, `visible`, `tooltip`,
`opacity`, `focusable`/`can_focus`, `widget_name`, `cursor_name`, `test_id`. Dropping an
attribute restores the value that widget was created with, not a global default.

See §7 of the design doc for what M2 (lists & text) and M3 (chrome & popups) add.
```
3. **Headless testing section**: mention the four actions (`Click`, `Toggle`, `Set_text`, `Set_value`, `Activate`) rather than just `Click`.
4. **Limitations**: drop "M0 covers four widgets"; keep single-window, no custom Cairo drawing, no `ListView`/`ColumnView`/`GridView`, and add the M1-specific ones this milestone chose deliberately, so nobody rediscovers them as bugs:
   - `Stack` and `Overlay` children are not reordered (GTK has no API for it); keys still preserve identity.
   - No radio groups (`CheckButton.set_group`): model the choice in Bonsai state.
   - No `Scale` marks, no `ProgressBar.pulse`, no `Entry` icons, no `SearchEntry.set_key_capture_widget`, no `Frame.set_label_widget` — each is a `Node.native` case and each is named in its widget's doc comment.
   - `Paned`'s position is not controlled (it would fight the drag handle).

- [ ] **Step 2: `docs/m1-backlog.md`** — rewrite as the *M2* backlog

The file's job is "what the last milestone's reviews deferred", so rewrite it rather than appending. Retitle it `# Backlog carried out of M1` (keep the filename; a rename churns links for nothing, and note the retitle in the commit message). Sections:

- **Done in M1** (a short list, so the next reader knows these are closed): child ops by predecessor widget; `Driver.frame`/`schedule_event` guarding `broken`; the reentrancy guard's live tests (`live_signals.ml` for the trampoline, `live_controls.ml` for the end-to-end programmatic-write case); per-widget unset defaults via the creation-time snapshot; `vtree/children.mli`.
- **Do first in M2**: whatever the M1 task reviews defer. Seed it now with what this plan already knows it is leaving:
  - `Attr.t` is still a public variant, so every M2 attr is a breaking change for an exhaustive match downstream — see Open Question 1; if the ruling was "defer", this is where it lives.
  - `Overlay` and `Stack` `move` ops are no-ops; if M2's `Notebook` (which *does* have `reorder_child`) shares the list machinery, revisit whether a no-op `move` should instead be an explicit `Unordered` marker on `list_ops` so the reconciler can skip emitting `Move` at all.
  - `Signals.spec.fire` reads state back off the widget; a signal with a genuinely un-readable payload (`ListBox::row-activated`'s row, key events' keyval) needs the existential-event version of `spec`. M2's `ListBox` is the forcing case.
- **API shape decisions before they become breaking**: carry forward whichever of M0's four are still open (`Expert.Driver.root_widget` vs `Node.windows`; `start ?flags`), drop the two M1 closed (per-kind unset defaults), and add: `Bonsai_gtk_test.Action.t` is a public variant with the same exhaustive-match exposure as `Attr.t`.
- **Tests worth adding**: carry forward the GC/lifetime test (remove a keyed child, `Gc.full_major`, assert finalization) and the after-display spin regression, both still unwritten; add "a `Live_tree.dump` of a tree containing every M1 widget, as one golden file" if the per-task live tests turn out to leave gaps.
- **Plumbing / hygiene**: carry forward the surviving M0 items (`scripts/setup-switch.sh`'s dirty-checkout check, the gir_gen flake shell, node paths frozen at mount, `Signals.slots`' dead `ref`, `Driver.t.last` duplicating `root.node`, exception-safety of `mount`, the hard-coded 16 ms cadence, `request_frame` not cancelling a pending `request_frame_soon`), and strike the ones M1 closed.
- **ocgtk fork**: carry the section over unchanged unless the PR status moved during M1.

- [ ] **Step 3: Commit**

```bash
git add README.md docs/m1-backlog.md
GIT_EDITOR=true git commit -F - <<'MSG'
README's widget catalogue; roll the backlog forward to M1's leftovers

docs/m1-backlog.md keeps its filename but is now "carried out of M1": M0's
three "do first" items are done, and the file lists what M1's reviews defer
instead.

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01Sg3Ci8U8kUKR8C3PL1pNSs
MSG
```

---

