# Task 15 report — README, the spec's M2 amendments, and `docs/m2-backlog.md`

**Commit:** `055c70e` on `m2` (single commit; no push, no merge, no `bd`).
**Gate:** `nix develop -c ./scripts/ci.sh` → `all green`. No golden moved.

Files: `README.md`, `docs/superpowers/specs/2026-08-28-bonsai-gtk-design.md`,
`docs/m1-backlog.md` → `docs/m2-backlog.md` (`git mv`, then rewritten),
`src/widgets/w_list_box.ml`, `src/live_tree.ml`, `test_lib/bonsai_gtk_test.mli`,
`test/handle/test_gallery.ml`, plus five one-line path updates
(`w_drop_down.ml`, `w_text_view.ml`, `w_search_entry.ml`, `w_flow_box.ml`,
`live_lists.ml`, `live_text.ml`) where a comment named the old backlog filename.

---

## 1. README

### What it now says, and how each factual claim was verified

Nothing in the README was taken from the plan; every count came from the mli, and two of
them contradict the plan.

| Claim | Verified against | Result |
|---|---|---|
| **37 `Node.*` constructors** | `grep -c '^val ' vtree/node.mli` = 38, minus `find_by_test_id`, which is a query | 37. M1's 29 + M2's 8 (`text_view`, `level_bar`, `list_box`, `flow_box`, `notebook`, `drop_down`, `calendar`, `editable_label`). The plan never gave a total. |
| **19 `Bonsai_gtk_test.Action.t` constructors** | enumerated from `test_lib/bonsai_gtk_test.mli` | **The brief and the plan both say thirteen.** The real list is 19: M1's 5, nine M2 signal actions, five controller actions. Written as nineteen; see Deviation 1. |
| **18 signal event attrs, 5 controller attrs** | `Attr.Name.t`'s constructor list in `vtree/attr.mli`, cross-checked against `Events.for_kind` (18 across all kinds) and `Events.controller_family` (5, in three families) | 48 `Attr.Name.t` names in all: 20 widget-wide (19 named + the nameless `Css_class`), 6 placement, 18 signal, 5 controller. |
| **6 placement attrs, each read by one container** | `vtree/placement.ml`'s `read_by` and `reader`, which are the two halves of one table | `Grid_cell`→Grid, `Page_title`→Stack, `Measure_overlay`→Overlay, `Row_selectable`/`Row_activatable`→ListBox, `Tab_label`→Notebook. |
| **17 `Keyval` names plus `f` and `of_char`** | `grep '^val ' vtree/keyval.mli` | 19 vals: 17 plain `int`s, `f : int -> int`, `of_char : char -> int`. |
| **Four new enum modules** | `src/bonsai_gtk.mli`'s re-export block | `Selection_mode`, `Tab_position`, `Wrap_mode`, `Level_bar_mode`. These are Tasks 8/9/10's carries ("an undocumented public module the plan does not list"), all three taken here. |
| **`Expert.embed`'s signature** | `src/bonsai_gtk.mli:142` | copied verbatim. |

### Sections

- **Status line** — M2, naming the three things a reader would otherwise not find: the
  keyed containers, the controller attrs, and `embed`.
- **Widget table** — a **Lists** row (`list_box`/`flow_box`/`notebook`) and a **Pickers**
  row (`drop_down`/`calendar`); `text_view` and `editable_label` join **Text**; `level_bar`
  joins **Display** (see Deviation 2).
- **Input** (new) — the five controller attrs, why `on_key_pressed` returns a
  `Key_response.t` rather than an effect, `?phase`'s default and what `Capture` is for, the
  one-controller-one-phase rejection, and `Keyval`. It **ends with a pointer to
  Limitations**, because the brief's review focus asks that no README claim outrun a test
  and the honest statement of the click/key gap is one section down.
- **Embedding** (new) — three sentences (root must not be a window; nothing is parented for
  you; `stop` empties but does not unparent), the signature, and the reason `widget` is a
  wrapper.
- **Headless testing** — the nineteen actions as a three-row table (M1 / M2 signals / M2
  controllers), what the handle now validates and from which `vtree` table, and the two
  remaining gaps (structural, and routing) written out rather than gestured at.
- **Limitations** — regrouped under five headings, because the flat list had grown past the
  point where a reader could find anything: *Not covered by any test*, *Input*, *Widgets*,
  *Not bound yet*, *Structure and lifecycle*.
- **ocgtk fork** — names M2's fork round (transfer-container sinks, constructor over-ref,
  three nullable strings, the finaliser re-entry) and points at `docs/m2-backlog.md` for
  what the fork still owes. Verified against `3a87d1c`'s message and diff.

### Two stale README claims corrected rather than carried

1. **"a walk restricted to the re-assert and fixup passes is on the backlog"** — it is not.
   `Patcher.reassert_only` landed in Task 2 (`ee64cc6`) and `Driver.frame` takes it on the
   phys-equal path (`src/driver.ml:85-87`). The bullet now says what actually happens. The
   spec's §4.2 and §4.3 carried the same stale sentence and got the same correction.
2. **"Container-specific attributes are inert elsewhere"** — since Task 3 they raise. The
   paragraph now says so, *and* names the one case that is still inert
   (`Attr.measure_overlay` on an overlay's main child), because `Placement`'s granularity is
   the parent's kind rather than its slot.

### Limitations claims spot-checked against source

The brief asks for three; I checked all of them. The eight that matter:

| Limitation | Source |
|---|---|
| ListBox/FlowBox sort, filter, header unreachable | `vtree/node.mli:846-847`, `:934-935`; confirmed by `task-14-report.md`'s "confirmed unchanged and still out of reach" |
| `on_click` does not claim the sequence | `vtree/attr.mli:617-620` (which promises this is "named in the README's Limitations" — that promise is now kept) |
| focus attrs are events, not `contains_focus`; and take no `?phase` | `vtree/attr.mli:622-634` — `on_focus_enter`/`on_focus_leave` have no `?phase` in their signatures |
| TextView caret as a character offset, exact/approximate/clamped | `vtree/node.mli:277-293` |
| Calendar has no range and no "no date"; year 0 refused | `vtree/node.mli` calendar doc; `Node.calendar`'s only constructor-time raise is `~marked_days` outside 1–31 (`vtree/node.ml:688-698`) |
| EditableLabel commits on leaving edit mode | `vtree/node.mli` editable_label doc ("`stop_editing false` would *discard*…") |
| DropDown stale index inert, `< -1` raises | `vtree/node.ml:648-657` |
| Keyval curated | `vtree/keyval.mli` |

---

## 2. The spec — twelve dated M2 amendments

All additive; nothing that was there was rewritten, per M1's pattern. Dated
`2026-08-30`, matching the existing §5.3 amendment.

| Section | What the amendment says |
|---|---|
| §4.1 | The second entry point: `Expert.embed`'s signature, the three inversions of `start`'s rules (root must not be a window; `widget` is a wrapper, with the root-kind-change argument for why; `stop` does not unparent), and the obligation embedding adds. |
| §4.2 | `Patcher.reassert_only` landed. Explains why narrowing the walk is not a re-introduction of the guard M1 removed. |
| §4.3 | One-clause note that the second of the two "future optimizations" is done; suspending the tick while idle is not. |
| §5.2 | Two changes: the seal is `type t = private Private.t` (the plan's spelling does not typecheck), and `Attr.Name.t` stays concrete deliberately; the controller attrs ship in M2 with `?phase`/`?button` and a `Key_response.t`, `on_map`/`on_unmap` and `css_provider` do not. |
| §5.3 | Extends the existing M2 amendment: the `List` row now includes ListBox/FlowBox/Notebook, their children **require keys** (raised by the constructor, so no node path), rows are auto-wrapped, per-row settings are placement attrs, a notebook interposes nothing. |
| §5.4 | The one-sentence key rule, quoted as a block: exactly-one-child containers raise, plural selections filter. With the reason the asymmetry is not arbitrary, the ghost-key same-frame rule, and the `Child_keys` keying invariant. |
| §6.4 | `spec` is a variant. `Read_back` (now returning a connection *list*, with the calendar as the forcing case) and `Payload : ('p,'r) payload -> spec` for the three signals whose payload cannot be recovered. Why `fire` returns `'r * effect option`. `declined`. Event controllers attached by `Controllers` on demand, one per `Events.Family.t`, declared by no impl, and named with `set_name` not `set_static_name`. |
| §6.5 | The grown controlled-prop list with the three details that each cost a round (the text view's cache, the calendar's day-1-first order, the label's text-then-editing order); the new fixup-pass cases including the notebook's read-back; refuse–record–report; `batch_if`. |
| §7 | M2 marked ***done* (2026-08-30)** with the eight widgets, the five controller attrs, `embed`, the enum and event-value modules, **37 constructors** and **nineteen** test actions — plus the two details the section did not anticipate (the controller attrs came forward from M3 because `row-activated` needed the same `Payload` mechanism; `Calendar` takes a `Core.Date.t` because there is no `GDateTime` and no `GLib-2.0.gir`). The implementation-notes paragraph gains an inline amendment extending "sorting and filtering in the model" to headers. |
| §9 | The three tables the handle validates against and that both sides call the same function for each message; why `Handle` is hand-written; the nineteen actions; and **what layer 2 still cannot see** — the structural half and routing — with the live suite's inability to close the second. |
| §11 | Six new families of structural message (misplaced placement attr; `~visible_child`/`~current_page` naming no child, with the empty-container carve-out; a keyed container's child with no `~key`, and why it carries no node path; the constructor-time arithmetic rejections including `min > max`; differing key phases; window-root-under-`embed` and non-window-root-under-`start`). Plus a second amendment for the finaliser rule, and a third for the reject-only-what-no-later-frame-could-make-valid rule and the `ctx.report` channel. |

---

## 3. `docs/m2-backlog.md`

`git mv docs/m1-backlog.md docs/m2-backlog.md`, then rewritten. Sections: header; *Closed
during M2 (was "do first in M2")*; *Closed during M2 from the M1 final-review carries*; *Do
first in M3*; *API shape decisions before they become breaking*; *Carried out of M2's task
reviews (Minor, unfixed)*; *Tests worth adding*; *Known-and-accepted dump quirks*;
*Plumbing / hygiene*; *ocgtk fork*.

### All thirteen "do first in M2" items, verified closed with their commit

Each was checked in the source, not taken from the ledger.

| Item | Landed | Verified by |
|---|---|---|
| Seal `Attr.t` | Task 1 `09ee6f7` + `1daa1b5` | `vtree/attr.mli`: `type t = private Private.t` |
| vtree-level event table | Task 1 `09ee6f7` | `git log --diff-filter=A -- vtree/events.ml` |
| Headless `Search_changed` (+ expander) | Task 1 `09ee6f7` | `Action.Search_changed`, `Action.Set_expanded` in the mli |
| Unordered marker replacing the no-op `move` | Task 2 `ee64cc6` | `list_ops.move : … option` |
| Reassert-and-fixup-only walk | Task 2 `ee64cc6` | `git log -S reassert_only -- src/patcher.ml` |
| Per-`reassert` batch cost | Task 2 `ee64cc6` | `git log -S batch_if -- src/widget_impl.mli` |
| `w_switch`'s hand-rolled active write | Task 2 `ee64cc6` | `git log -S "reassert w kind" -- src/widgets/w_switch.ml` |
| Existential-event `spec` | **Task 4** `9c081e5` | `git log -S "\| Payload" -- src/signals.mli`. Not Tasks 1–3, as the brief assumed — `ListBox::row-activated` is the forcing case and arrives with the container. |
| `min > max` scrolled-window bounds | Task 3 `b458449` | `vtree/node.ml:375-385` |
| `grid_cell`/`page_title` silently inert | Task 3 `b458449` + `a9b7b34` | `vtree/placement.ml` |
| Same-frame stack name swap | Task 3 `b458449` | `git log -S give -- src/patcher.ml` |
| `Kind.entry_props` has no `max_length` | Task 3 `b458449` | `vtree/kind.ml:64` |
| ocgtk `Widget.set_name` nullable | Task 14, pinned in `3a87d1c` | `src/attr_apply.ml` now writes `Some s` |

Four M1 final-review carries M2 also closed are recorded as closed, each verified:
`~visible_child` naming no page (now raises, `w_stack.ml:92`), `is_event` pinned over
`Attr.Name.all` (`test/test_events.ml:176`), `Patcher.mount` exception-safety (Task 12,
with the M1 entry's "bounded" claim corrected — it was a permanent ~50k-word retention per
failure), and the validating `recompute_view` (Task 13).

### Backlog reconciliation — every review-flagged item, and where it landed

Mined by two delegated agents reading all fourteen reviews in full, then reconciled against
the file. `docs/m1-backlog.md` had been updated during M2 by Tasks 2, 3, 6, 9, 10, 12 and
13 only; **nothing from Tasks 1, 4, 5, 7, 8, 11, 13's re-review or 14 had ever been written
into it.** That is what this rewrite closes.

| Review finding | Was in the old file? | Where it is now |
|---|---|---|
| task-1 M8 `require_slots` off the patch path | no | *Do first in M3* |
| task-1 M9 `deriving variants` widens `kind.mli` | no | *API shape decisions* |
| task-1 M10 nested `Attr.many` unpinned | no | *Tests worth adding* |
| task-1 M3 residual: two duplicated `all_kinds` lists | no | *Carried out of M2's reviews → Consistency* |
| task-1 M7 validation in `Result_spec.view` | n/a | not filed — the review says "no action, as intended" |
| task-2 M1 phys-equal fast path unpinned | yes | *Tests worth adding*, **updated**: Task 2 made the fast path narrower rather than merely equal, so the flip is now a performance change, not a no-op |
| task-2 M2 `batch_if` contract | no | not filed — ruled "leave it" by the controller |
| task-2 M3 spec §5.3 drift | n/a | closed in Task 3 |
| task-3 M6 `Placement` granularity | yes | *Tests worth adding*, **merged** with task-6 M7 so it names both instances |
| task-3 re-review `Placement.is_read_by` over-broad | no | *API shape decisions* |
| task-3 deviation-2 residuals | no | not filed — declined, and the review agrees |
| task-4 M4 untestable `Click_event` doc claims | no (general gap was) | *Carried out of M2's reviews → Diagnostics*, as the scope-widening of the click/key gap the report argued for |
| task-4 M6 controller GClosure roots the widget | no | *Carried → Diagnostics*, cross-linked to the GC/lifetime test |
| task-4 rr2 `clear t`/`update_slots` coupling | no | *Carried → Diagnostics* |
| task-4 rr2 `expected_controllers.txt` order dependence | no | *Known-and-accepted dump quirks* |
| task-4/5 focus `~phase` asymmetry | no | *Do first in M3* — and a Limitations bullet in the README |
| task-5 M5 `Events.key_phase` public trap | no | *API shape decisions* |
| task-5 M6 disarmed slots / embed exception policy | no | closed by Task 12 (`Driver.mark_broken`); not re-filed |
| task-5 `key_pressed_answer`/`declined` exports | no | *API shape decisions* |
| task-5 / task-13 N7 file lengths | no | *Carried → Consistency* |
| task-6 M4 `keyless` case loses the path claim | no | *Carried → Diagnostics* |
| task-6 M5 `Activate_row` vs `row_activatable false` | no | *Do first in M3* (with the `Activate_child`/`Set_page` consistency carry) |
| task-6 M7 row attr on the placeholder | no | *Carried → Diagnostics*, and folded into the `Placement` granularity item |
| task-6 M6 `apply_selection` O(n·m) | n/a | closed in Task 7; recorded in *Do first in M3* as the measurement that displaced M1's `after_of` prediction |
| task-7 M4 `forget_children`/`forget_rows` unpinned | no | *Do first in M3* (`Child_keys`) and *Tests worth adding* |
| task-7 M2 `min > max` children accepted | no | *API shape decisions* |
| task-7 no-functor decision + its standing trigger | no | *Do first in M3* |
| task-7 rr N2 (two words; second stderr producer) | no | *Carried → Consistency* and *dump quirks* |
| task-8 N9 forward-move reason | n/a | taken in Task 9 |
| task-8 N10 stale deviation 6 | no | *Carried → Consistency* |
| task-8 carry 3 `Tab_position` undocumented | no | **README and spec §7** (this task), plus *Plumbing* for §5.1's stale sketch |
| task-8 carry 4 the two `Reconcile` theorems | no | *Tests worth adding* |
| task-8 carry 6 hidden `~current_page` diverges | no | *Do first in M3* |
| task-8 carries 1/2/5 (`still_remembered`, `tabs_in_dump`, page order) | no | *Tests worth adding* |
| task-9 R2 `enqueue_fixups` name | no | *Carried → Consistency* |
| task-9 R3 `take_report` uses `state` | no | *Carried → Consistency* |
| task-9 rr2 RR1 rebuilt-equal-string report | no | *Tests worth adding* |
| task-9 rr2 RR2 report depends on the intervening write | no | *Carried → Behaviour* |
| task-9 carry 2 `Wrap_mode` undocumented | no | **README and spec §7** |
| task-9 carry 3 `char*` leak | yes | *ocgtk fork → Still open*, **rewritten** as item 4d #4 and named the highest-value remaining item |
| task-9 carry 4 cache invariant untestable | no | *Tests worth adding* |
| task-9 carry 5 `notify::cursor-position` | no | *Do first in M3* |
| task-10 I1 `GtkStringList` leak | yes | **struck** — fixed on the fork and in the pin; moved to *ocgtk fork → Fixed in M2's fork round* |
| task-10 I4 README sentence | yes (as "Documentation M2 owes M3") | **discharged**: the README's *Structure and lifecycle* opens with it. The old section is gone. |
| task-10 carry 2 `Level_bar_mode` undocumented | no | **README and spec §7** |
| task-11 M6 `same_marks` order-sensitive | no | *Carried → Behaviour* |
| task-11 rr M1 Dec→Jan walk absent | no | *Tests worth adding* |
| task-11 rr M2 midnight flake | no | *Tests worth adding* |
| task-11 rr M3 three-connection teardown | no | *Tests worth adding* |
| task-11 rr M5 / carry 3 editable-label 1.22 ms | no | *Carried → Consistency*, with the number |
| task-11 carry 1 no `~editable`/`~width_chars`/`~xalign` | no | *API shape decisions* |
| task-11 carries 5, 6, 7 (heading signals, connection list, `notify::day`) | no | *Carried → Consistency* |
| task-11 carry 2 | n/a | **withdrawn by the implementer; deliberately not carried** |
| task-12 rr N1 finaliser entry understates the defect | yes, wrongly | **rewritten**: it is a memory-safety bug, measured as a segfault when the callback allocates, and it is fixed on the fork — now under *Fixed in M2's fork round* |
| task-12 out-of-scope #1 driver never reclaimed | yes | *Plumbing*, carried with the M3 lever |
| task-12 out-of-scope #2 unbounded `drain` | yes | *Plumbing* |
| task-12 shell-side `app#quit` gap | no | *Plumbing*, marked as the port's |
| task-13 N5 `escapes` counter | no | not filed — argued down and accepted |
| task-13 N7 file length | no | *Carried → Consistency* |
| task-13 N2 no live per-kind `update` sweep | yes | *Tests worth adding* |
| task-13 XTEST push | yes | *Tests worth adding*, promoted to the second bullet with the reviewer's "it would close rather than compensate" framing; the bead is the controller's |
| task-13 rr N8, N9 | no | **taken in this task** (see §4) |
| task-14 M3, M4 commit-message miscounts | no | *ocgtk fork → Still open*, marked unfixable (history is pushed) |
| task-14 M7 4b reproduction overstated | no | *ocgtk fork → Still open* |
| task-14 M9 3 of 24 sites pinned, all behind `require_gtk` | no | *ocgtk fork → Still open* |
| task-14 M10 31 non-GObject-fundamental constructors | no | *ocgtk fork → Still open*, merged with 4d #1 as the review asks, and carrying the 9-not-11 correction |
| task-14 M11 controllers golden flake under Xvfb | no | *Known-and-accepted dump quirks*, so a future pin bump is not blamed for it |
| task-14 rr N1 93 → 75 | no | *ocgtk fork → Still open* |
| task-14 rr N2 `ref_sink` vs `ref` on the borrowed path | no | *ocgtk fork → Still open* |
| task-14 rr N3 missing `docs/dev-notes.md` | no | *ocgtk fork → Still open* |
| task-14 rr N4 `GList*` for GSList stubs | no | *ocgtk fork → Still open* |
| task-14 rr N5 stray text in a doc comment | no | *ocgtk fork → Still open* |
| task-14 rr N6 tree 34 files behind its generator | no | *ocgtk fork → Still open* |
| task-14 item 4d #1–#7 | **none of it** | *ocgtk fork → Still open*, all seven, with 4d #5's fixed half separated from its unfixed half |
| task-14 behavioural half of items 1–3 not taken | no | *Do first in M3*, naming the blank-switcher-button consequence |
| task-14 `caml_remove_global_root` residual | no | *ocgtk fork → Still open* |
| task-14 no `gir_gen` dev shell | yes | *Plumbing* |
| task-14 `opam reinstall` does not clear the stamp | no | *Plumbing*, merged with the existing `setup-switch.sh` bullet |
| task-14 no working `dune build @fmt` on the fork | no | *ocgtk fork → Still open* |
| task-14 `test_glyph_item_alias` needs a display | no | *ocgtk fork → Still open* |
| task-14 Stavekeeper pin bump outstanding | no | *Plumbing*, with the hash |
| task-14 six draft PRs + twelve unrouted commits | yes (PRs only) | *ocgtk fork → Still open*, extended with the twelve and the scrub-grep warning |
| Unreachable: `set_header_func`/`sort_func`/`filter_func`, `GLib.DateTime`, `gdk_keyval_name` | no | *ocgtk fork → Confirmed out of reach*, each with the M2 workaround that stands |

### The ocgtk section, re-cut against the current pin

The brief's Task 14 note said the section "should be re-cut when the pin moves, not now".
The pin has moved (`ocgtk-pin.json` = `649498b4`, committed in `3a87d1c`), so it is re-cut.
Five entries moved from *open* to *Fixed in M2's fork round* — `get_selected_rows`'s missing
sink and its 23 twins, the constructor `ref_sink`, the three nullable strings,
`get_selected_item`'s missing sink (its `.mli`-`option` half is separated out and stays
open), and the finaliser re-entry — and the finaliser entry's wording is corrected from
"hangs" to what was measured.

---

## 4. Carries taken

1. **`task-13-review` re-review N8** — `test_lib/bonsai_gtk_test.mli`. The absolute
   "no way to advance a handle past a tree without checking it" is scoped to this module,
   with the reason (`Handle.t = Bonsai_test.Handle.t` by design, which is what lets the four
   omitted values be used unchanged) and the reviewer's explicit instruction not to make `t`
   abstract.
2. **`task-13-review` re-review N9** — `test/handle/test_gallery.ml:688`. The second
   paragraph now opens "It has no `[Name.t]` because…" instead of restating the first
   paragraph's claim in a form that denied it. Its tail was reflowed to remove the "so it has
   no `[Name.t]`" that then became redundant.
3. **The README Limitations carries from Tasks 4–5** — the plumbing-only click/key gap with
   its compensating controls is the **first** bullet of Limitations, under its own heading,
   and says what is covered on each side and what is not; `Attr.on_click`'s mli promise that
   "an application that wants to consume the click has no way to say so in M2, which is named
   in the README's Limitations" is now a promise kept. The **focus `~phase` asymmetry** is a
   bullet of its own.
4. **The README Limitations carry from task-10-review I4** — a constructor's
   `Invalid_argument` costs the whole application, with the rule the checks follow. It opens
   *Structure and lifecycle*.
5. **`w_list_box.ml`'s `get_selected_rows` prohibition** — dropped. I checked the comment's
   own reasoning first, and the brief's suggested replacement ("the binding now sinks and the
   walk is kept for widget-order reasons") is only three-quarters right: `row_by_key`,
   `forget_rows` and `apply_selection` want **every** row, not the selected ones, so the
   shorter call would not do for them at all; `selected_keys` is the one caller that could
   take it today and shares this walk so that "in widget order" and the `Child_keys` lookup
   are stated once. The comment now says that, and keeps one paragraph of the history because
   it is what the backlog's "read the stub, not the GIR" rule rests on.
6. **The same staleness in `src/live_tree.ml`** — three comments claimed
   `get_selected_rows` "does not [sink]" and one claimed `get_selected_item`'s stub "fails to
   ref". Not in the brief's list; found by grep while doing carry 5, and left uncorrected they
   would contradict the file next door. Each now says which half is fixed in the pin and which
   is not.
7. **The three undocumented public enum modules** (`Tab_position`, `Wrap_mode`,
   `Level_bar_mode`) that Tasks 8, 9 and 10 each routed to "Task 15's docs and Task 16's spec
   sweep" — all three are in the README and in spec §7. Spec §5.1's constructor sketch is
   still M0's and does not show `?tab_pos`/`?wrap`/`?mode`; that half is Task 16's and is
   recorded in the backlog's *Plumbing*.

---

## 5. Deviations

1. **"the action list grows to thirteen" → nineteen.** The brief and the plan both say
   thirteen. `test_lib/bonsai_gtk_test.mli` has nineteen constructors: `Click`, `Toggle`,
   `Set_text`, `Activate`, `Set_value`, `Search_changed`, `Set_expanded`, `Click_at`,
   `Focus_enter`, `Focus_leave`, `Key_press`, `Key_release`, `Activate_row`,
   `Activate_child`, `Set_selection`, `Set_page`, `Set_selected`, `Select_day`,
   `Set_editing`. M1's Task 11 set the bar at "verified against code", so the code wins.
   Written as nineteen in the README, spec §9 and the backlog's *API shape decisions*.
2. **`LevelBar` is under Display, not Pickers.** The brief's drafted table row puts it in
   Pickers with `DropDown` and `Calendar`. A `GtkLevelBar` picks nothing — it has no
   interaction at all, which is exactly why `Events.for_kind` gives it an empty list — and
   filing it beside two controlled inputs would mislead a reader scanning for something to
   put a handler on. It sits with `progress_bar`, which is what it is a sibling of.
3. **Limitations is regrouped under five headings** rather than kept as one flat list. M1's
   list was eight bullets; M2's is twenty, and the click/key gap in particular needs to be
   the first thing a reader meets rather than the eleventh. Nothing was dropped in the
   regrouping except what M2 closed.
4. **Two README claims were corrected rather than carried forward** (the reassert-only walk;
   placement attrs no longer inert, with the one case that still is). Both are factual
   corrections, not new scope, and both are mirrored in the spec.
5. **`src/live_tree.ml` is outside the brief's file list.** Three comments there made the
   same stale claim the prohibition comment did. Correcting one and not the other three
   would leave the file next door contradicting it.
6. **The plan and the M1 plan were left pointing at `docs/m1-backlog.md`.** The brief says to
   update "the two references"; there were nine outside the plans, and all nine are updated.
   The two plan documents are dated historical records of what was decided, and the M2 plan's
   own Task 15 entry *is* the instruction to do this rename — rewriting it would erase the
   instruction being followed.
7. **`Patcher.require_slots` off the patch path (task-1 M8) is filed under *Do first in M3*,
   not fixed.** It is a one-line fix in `src/patcher.ml` and the reviewer called it "the one
   I would take", but this is the docs task and its file list is docs plus the named carries;
   changing patcher behaviour in it would be a code change with no review round behind it.

---

## 6. CI tail

```
bonsai_gtk: exception in frame, stopping the driver: (Invalid_argument
  "root/1: a Node.window may only be the root node, not a child of another node")
bench: 0.0087 ms embedded, 0.0098 ms windowed, ratio 0.89 (bound 1.2)
bench: 0.00036 ms at 16 chars, 0.00013 ms at 1 MB, ratio 0.36 (bound 5)
bench: 0.00015 ms parked on a refused 1 MB write, ratio 1.14 (bound 5)
bench: 0.00014 ms at 4 items, 0.00014 ms at 1000 items, ratio 0.94 (bound 5)
bench: 0.00012 ms parked on a refused selection, ratio 0.87 (bound 5)
bench: calendar 0.00017 ms settled, 0.00012 ms parked on a refused date, ratio 0.73
bench: editable label 0.00020 ms at 16 chars, 0.00016 ms parked on a refused write,
       1.23135 ms at 100 000 chars (the compare is O(len), as every entry's already is)
== example smoke
all green
```

No golden moved, as expected for a docs change: the only non-doc edits are comments and one
mli doc comment. `git status` after the commit is clean apart from an untracked
`.beads/issues.jsonl`, which is not this task's.

**One note for whoever runs the gate next:** `dune build @fmt` (the whole-tree alias) fails
in this checkout with `EROFS` on `result/lib/…/Cairo.mli`, because a `nix build` result
symlink is in the working directory and the root `@fmt` alias walks into it. `scripts/ci.sh`
is already written around this (line 17 lists the per-directory aliases); use
`dune build @vtree/fmt @src/fmt @test/fmt @test_lib/fmt @test/live/fmt @examples/fmt`
to auto-promote, not `@fmt`.
