### Task 15: README, the spec's M2 amendments, and `docs/m2-backlog.md`

**Files:**
- Modify: `README.md`, `docs/superpowers/specs/2026-08-28-bonsai-gtk-design.md`
- Create: `docs/m2-backlog.md`
- Delete: `docs/m1-backlog.md` (its content rolls forward; see Step 3)

- [ ] **Step 1: README**

1. **Status line** — name M2's coverage.
2. **The widget table** gains rows, and one existing row changes:

```markdown
| **Lists** | `ListBox` (keyed rows, controlled selection, per-row `Attr.row_selectable`/`row_activatable`), `FlowBox` (keyed children, controlled selection, geometry as props), `Notebook` (keyed pages, `Attr.tab_label`, controlled `current_page`, real reordering) |
| **Text** | `Entry`, `PasswordEntry`, `SearchEntry`, `TextView` (controlled buffer, caret preserved as an offset), `EditableLabel` — controlled: the widget is written only when the model disagrees with what it currently shows |
| **Pickers** | `DropDown` (string list, controlled `selected`), `Calendar` (controlled `Date.t`), `LevelBar` |
```

3. **A new "Input" section**, because event controllers are not a widget and will not be found in a widget table:

```markdown
## Input

`Attr.on_key_pressed ?phase` and `on_key_released ?phase` attach a
`GtkEventControllerKey`; the pressed handler returns a `Key_response.t`
(`Handled`/`Propagate`, each optionally carrying an effect) because GTK routes
the key on that answer synchronously, before any frame could run.
`Attr.on_click ?button ?phase` attaches a `GtkGestureClick` and delivers the
button, press count, coordinates and modifiers. `Attr.on_focus_enter` /
`on_focus_leave` attach a `GtkEventControllerFocus`. All of them may go on any
widget, and the controller exists only while the attribute does.

Keyvals are plain `int`s; `Keyval` names the ones worth naming
(`Keyval.escape`, `Keyval.of_char 'w'`) so that a view function stays free of
ocgtk and therefore headless-testable.
```

4. **A new "Embedding" section** — three sentences and the `Expert.embed` signature, aimed at exactly the reader who has an existing GTK app.
5. **Headless testing** — the action list grows to thirteen; mention that the handle now rejects an event attr a kind cannot emit, and that it still cannot see the structural mistakes or model key propagation.
6. **Limitations** — strike what M2 closed, keep single-window / no `ListView`-`ColumnView`-`GridView` / no custom Cairo drawing, and add M2's own:
   - `ListBox`/`FlowBox` sorting, filtering and header functions are unreachable from ocgtk (the generator emits no GIR-callback-taking method). Sort and filter in the model; headers are ordinary non-selectable rows.
   - A `GtkGestureClick` from `Attr.on_click` does not claim the event sequence, so a click also reaches whatever else would have handled it. There is no way to consume one in M2.
   - `Attr.on_focus_enter`/`on_focus_leave` are events, not a `contains_focus` query; an app that needs the bit keeps it in its own model.
   - `TextView` does not expose the cursor position, and its controlled write preserves the caret as a character offset (exact for an in-place rewrite, approximate for one that changes length before the caret).
   - No `Calendar` date range or "no date selected" — the date is always a real `Date.t`.
   - `EditableLabel` commits on leaving edit mode; there is no discard.
   - Keyval coverage is the curated `Keyval` list plus `of_char`; anything else is a raw int.

- [ ] **Step 2: The spec, one dated amendment per section touched**

Following M1's pattern exactly — a `**M2 amendment (2026-08-29).**` paragraph inside the section, never a rewrite of what was there:

| Section | Amendment |
|---|---|
| §5.2 `Attr.t` | The variant is sealed behind `Attr.Private`. The controller attrs listed here in the original (`on_key_pressed`, `on_key_released`, `on_focus_enter`, `on_focus_leave`) ship in M2 rather than M3, with `?phase` and a `Key_response.t`; `on_map`/`on_unmap` do not. |
| §5.3 Children shapes | `ListBox`, `FlowBox` and `Notebook` are `List` and their children **require keys**. `list_ops.move` is an option and `None` is the unordered marker, replacing M1's no-op `move`; `Overlay`/`Stack`/`Grid` take it, `Notebook` does not. |
| §5.4 Keys | The one-sentence rule: a container that shows exactly one of its children raises when told to show one that does not exist; a container with a plural selection ignores keys it cannot find. |
| §6.4 Signals | `spec` is a variant. `Read_back` is the M1 shape; `Payload` carries the signal's own arguments and a return value handed back to GTK, for the three signals whose payload cannot be recovered. Event controllers are attached on demand by `Controllers`, not declared by any impl. |
| §6.5 Controlled props | The list grows: a text view's buffer, a dropdown's selection, a calendar's date, an editable label's text and editing state, and — from the fixup queue, alongside a stack's visible child — a list box's and flow box's selection and a notebook's current page. And the note that a `reassert` now brackets conditionally (`batch_if`). |
| §7 catalogue | M2 marked *done* with the eight widgets, the five controller attrs, `Expert.embed`, and the count of `Node.*` constructors. Two details this section did not anticipate: the controller attrs came forward from M3, and `Calendar` takes a `Core.Date.t` because GDateTime is not bound at all. |
| §9 Testing | The headless handle rejects unsupported event attrs, via a table in `vtree` shared with `Signals.require_specs`; what it still cannot see is the structural half and key propagation. |
| §11 Error handling | The new structural messages: a placement attr on a container that does not read it; a `~visible_child`/`~current_page` naming no child; a list box or notebook child with no key; a `min > max` scrolled-window bound; two key attrs asking for different phases; a window root under `embed` and a non-window root under `start`. |

- [ ] **Step 3: `docs/m2-backlog.md`**

Roll `docs/m1-backlog.md` forward. **This is a new file, and `m1-backlog.md` is deleted** — M1 kept the old filename deliberately ("a rename churns links for nothing"), but two milestones in, a file called `m1-backlog.md` describing M2's leftovers is a trap. `git mv` it so the history follows, then rewrite. Sections:

- **Closed during M2** — Tasks 1–3's twelve items, each with its task and commit.
- **Do first in M3** — whatever M2's reviews defer. Seeded now with what this plan already knows it is leaving:
  - `Attr.on_click` cannot claim the event sequence.
  - `Attr.on_focus_enter`/`on_focus_leave` are events, not the `contains_focus` query stavekeeper polls.
  - `TextView` exposes no cursor position (`notify::cursor-position` is the hook).
  - `Bonsai_gtk_test.Key_press` cannot model propagation.
  - The `Keyval` table is curated, not complete.
  - Whatever the live tests could not provoke — if Task 4 landed on option (c), "no live test delivers a synthetic click" goes here in bold, because it is the biggest untested surface in the milestone.
  - `Child_keys` is one table per module and is never compacted: an entry is removed on `remove` and otherwise waits for the GC. Correct, but nothing measures it.
  - `after_of` is still `O(index)` and the `cur` bookkeeping `O(n)` per op, so a list patch is `O(n·ops)` — M1 predicted "M2's `ListBox` is what will feel it". Record whether it did, with a number.
- **API shape decisions before they become breaking** — `Bonsai_gtk_test.Action.t` is now thirteen constructors and still concrete; `Expert.Driver.root_widget` still cannot survive `Node.windows`; `start ?flags`; no `close-request` on `Node.window`; and new: `Key_response.t` and `Selection_mode.t` are public variants.
- **Carried out of the final review (Minor, unfixed)** — from M2's four area reports.
- **Tests worth adding** — carry forward the GC/lifetime test (still unwritten since M0; M2's `Child_keys` makes it more interesting, not less), the after-display spin regression, the real-display click-through, and whatever M2 adds.
- **Plumbing / hygiene** — carry forward the surviving items, strike what M2 closed.
- **ocgtk fork** — Task 14's list and its findings, verbatim, plus the six draft PRs' status.

Update the two references to `docs/m1-backlog.md` (`CLAUDE.md`? `README.md`? `grep -rn 'm1-backlog' --exclude-dir=_build .`) to the new name.

- [ ] **Step 4: Commit**

```bash
git add README.md docs/
GIT_EDITOR=true git commit -F - <<'MSG'
README's M2 catalogue, the spec's M2 amendments, and the backlog rolled forward

docs/m1-backlog.md becomes docs/m2-backlog.md (git mv, so the history follows):
M1 kept the old name on purpose, but two milestones in, a file named for the
milestone before last is a trap.

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01Sg3Ci8U8kUKR8C3PL1pNSs
MSG
```

**Review focus:** that every spec amendment is dated and additive; that the Limitations list matches what the code actually does (check three of them against the source at random); that no README claim outruns a test — in particular the Input section, if the live tests could not deliver a synthetic click.

---

