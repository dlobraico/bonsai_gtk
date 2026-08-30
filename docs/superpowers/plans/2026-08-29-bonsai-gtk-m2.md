# bonsai_gtk M2 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Grow M1's core-and-layout catalogue into the spec's **M2 — lists & text**: ListBox (keyed rows, selection), FlowBox, Notebook, TextView (controlled buffer), DropDown (string list), LevelBar, Calendar, EditableLabel. Bring M3's **event controllers** forward — `Attr.on_key_pressed`/`on_key_released`/`on_click`/`on_focus_enter`/`on_focus_leave` — because the mechanism M2 has to build for `ListBox::row-activated` (a signal whose payload cannot be read back off the widget) is the same mechanism they need, and because stavekeeper's dialogs cannot be ported without them. Add `Bonsai_gtk.Expert.embed`, so stavekeeper's imperative `Shell` can host a bonsai-rendered page inside a `GtkStack` it already owns and the port can proceed a screen at a time rather than all at once. Land the twelve items `docs/m1-backlog.md` marks "Do first in M2" before any widget, because every widget added after them pays their cost twice.

At the end of M2, stavekeeper's `library_window.ml` (FlowBox of cards, search entry, click gestures on cards), `sidebar.ml` (ListBox with keyed rows and selection), `layer_panel.ml` (ListBox rows with check buttons) and `dialog.ml` (Escape in CAPTURE phase) are all expressible. What is still missing is named in "What M2 still does not give the stavekeeper port" below, and repeated in the README's Limitations section by Task 15.

**Architecture:** Unchanged in shape from M1, extended in four places.

- `bonsai_gtk.vtree` (`vtree/`, ocgtk-free) gains the pure enum and record modules the new attrs need (`Phase`, `Modifiers`, `Keyval`, `Key_event`, `Key_response`, `Click_event`, `Selection_mode`, `Wrap_mode`, `Level_bar_mode`), a `Selection` helper, and **`Events`** — the `Kind.t -> Attr.Name.t list` table that says which event attrs each kind can carry. `Events` is the one piece of knowledge `Bonsai_gtk_test` was missing: it can now reject at handle-creation time exactly what `Signals.require_specs` rejects at mount, instead of certifying an application the runtime will refuse. `Attr.t` and `Attr.Name.t` are **sealed**: the variants move behind `Attr.Private`, which carries no stability promise, so M3's attrs are not a breaking change for a downstream exhaustive match.
- `bonsai_gtk` (`src/`) gains: a **`Signals.spec` variant** — M1's read-the-value-back-off-the-widget shape becomes `Read_back`, and a new existential `Payload` carries a typed payload built from the signal's own arguments *and* a return value handed back to GTK (which is what `key-pressed` needs and nothing in M1 did); **`Controllers`**, which attaches `GtkEventControllerKey` / `GtkGestureClick` / `GtkEventControllerFocus` to a widget on demand as the controller attrs appear and removes them as they go, reusing the whole trampoline/slot/guard machinery underneath; **`Child_keys`**, one ephemeron table per container module mapping a live wrapper widget (`GtkListBoxRow`, `GtkFlowBoxChild`, a notebook page's content) back to the `Key.t` its node carried, which is what lets `row-activated` deliver a key rather than an index; and eight `src/widgets/w_<name>.ml` files.
- `list_ops` gains an **ordered/unordered marker**: `move` becomes an option, and `None` means "this container has no reorder primitive", which stops `Reconcile.diff` emitting `Move` ops nobody can apply. `Overlay`, `Stack` and `Grid` take `None`; `Notebook` — the first container with a real `reorder_child` — takes `Some`.
- `Driver.frame` gains a **reassert-and-fixup-only walk** for the frames on which Bonsai hands back the physically same node, which M1 deliberately paid a full tree walk for.

`bonsai_gtk_test` (`test_lib/`) stays ocgtk-free and grows five actions plus the `Events`-backed validation.

**Tech Stack:** Unchanged. OxCaml `ocaml-variants.5.2.0+ox`, dune ≥ 3.17, Bonsai `v0.18~preview.130.106+341` (Cont API), `bonsai.driver`, `bonsai_test`, `virtual_dom.ui_effect`, ocgtk 0.1~preview2 (GTK 4.22, fork pin in `ocgtk-pin.json`) — dune libraries `ocgtk.gtk`, `ocgtk.gio`, `ocgtk.gdk`, `ocgtk.pango`, `ocgtk.common`. M2 adds no new dune library: `ocgtk.gio` (already present, for `Gio.Wrappers.List_model`) and `ocgtk.gdk` (already present, for `Gdk_enums.modifiertype` and `Gdk_constants.key_*`) cover everything. Nix flake for the dev shell, `xvfb-run` for live tests.

**Spec:** `docs/superpowers/specs/2026-08-28-bonsai-gtk-design.md`

## Pre-flight corrections (2026-08-30, override the task text below)

The scout's report is `.superpowers/sdd/2026-08-30-bonsai-gtk-m2/preflight-report.md`.
Every checklist item verified as stated except these four; where a task below disagrees
with this section, this section wins.

1. **Task 5 — no synthetic key press exists.** `Event_controller_key.forward` only re-routes
   an event the controller is already processing; there is no `GdkEvent` constructor in the
   pinned binding. The task's open question is closed: **no**. Land the plumbing-only
   fallback for both click (Task 4) and key (Task 5) up front — attach/detach asserted live,
   handler logic proved headlessly through `Bonsai_gtk_test` — and put the end-to-end gap on
   the backlog with the gallery Input section and Task 16's real-display click-through as
   the compensating controls.
2. **Task 4 — the `live_controllers.ml` sample must present its window** before exercising
   focus (`Widget.grab_focus` only drives the focus chain on a realized, mapped widget); as
   written `on_window_created` is a no-op and the focus assertions would read `false`.
3. **Task 4 — use `Widget.observe_controllers : t -> Gio.List_model.t`** (exists in the
   binding, missing from the ocgtk-facts table) to make the attach/detach assertion
   concrete: item count N → N+1 on attach → N on unmount / attr removal.
4. **Task 2 — `batch_if` stays.** Measured: `Widget_impl.batch` on a `GtkLabel` is
   ~79.5 ns/call (100k calls = 7.95 ms) — cheap, not free; the "skip if free" escape hatch
   does not trigger. Record the numbers in the task report.

Minor, no action: `gdk_constants.mli` declares `val key_a` twice (harmless);
`w_password_entry.ml` has no `Attr.t` references, so Task 1 Step 4's file list is one
short.

## Global Constraints

Carried from the spec and from what M0 and M1 established. These hold for every task below; read them before Task 1 and again if a review says "this does not match the codebase".

- **One widget, one file.** Each widget is `src/widgets/w_<name>.ml` exposing a single `let impl : Widget_impl.t` (spec §7). File names are prefixed `w_` because `src/dune` uses `(include_subdirs unqualified)`, so `w_list_box.ml` becomes module `W_list_box` and cannot collide with ocgtk's own `List_box`. `src/widgets/registry.ml` maps `Kind.t` to the impl and must stay an exhaustive match.
- **Props vs attrs.** Widget-specific properties are typed fields of that widget's `Kind.t` constructor and labelled arguments of its `Node.*` constructor, defaulted from `vtree/defaults.ml` and dropped from the sexp with `[@sexp_drop_if]`. Properties every `GtkWidget` has are `Attr.t` values passed in `~attrs`. Widget-specific *events* are attrs. A setting the *parent* holds on behalf of a child — a grid cell, a stack page's title, and now a list-box row's `selectable`, a notebook page's tab label — is an `Attr.t` on the **child**, read by the parent impl's `list_ops` and never applied by `Attr_apply` (spec §5.3's M1 amendment).
- **Named props records.** Every kind's props are a named record `Kind.<widget>_props` with `[@@deriving sexp_of, equal]`, so `Kind.equal_props` is one call per kind and impls can name the record in a signature. Every defaulted field's default is a value in `vtree/defaults.ml`, read from three places (the `Node` optional argument, the `[@sexp_drop_if]`, and `kind.mli`); adding a fourth spelling is the bug `defaults.ml`'s header describes.
- **Prop batches are bracketed.** Any `create`, `update` or `reassert` that may write more than one GTK property wraps the writes in `Widget_impl.batch`; never hand-roll `freeze_notify`/`thaw_notify` (an exception between them leaves the object frozen).
- **Keyed children.** List children are matched by `Key.t` where present and positionally otherwise. A duplicate key among siblings is `Invalid_argument`, at mount as well as at patch. **`Stack` pages, `ListBox` rows, `FlowBox` children and `Notebook` pages all *require* a key**: for a stack the key is the GTK page name, and for the other three it is the identity handed to `on_row_activated` / `on_child_activated` / `on_page_changed`, which have nothing else to say.
- **Controlled props (spec §6.5).** A prop the user can change writes the widget only when the new value differs from the **widget's current value**, never from the previous node's, and it lives in `Widget_impl.reassert` rather than `update`, because the patcher skips `update` when the two nodes' props are equal — which is exactly what a *declined* edit produces. The exception is a controlled prop that names a child: a `Stack`'s visible child, and now a `ListBox`/`FlowBox` selection and a `Notebook`'s current page. `reassert` runs *before* the children are patched, so on the frame that both adds a row and selects it there would be nothing to select; those four are applied from the **fixup queue** instead, on the identical rule and inside the same guard.
- **Signal slots.** Every signal a widget supports is connected exactly once at `create`, to a trampoline that (1) cannot let an exception cross into C, (2) returns immediately when `Scheduler.in_patch` is set, (3) reads the handler out of a mutable slot, (4) converts GTK's arguments into the OCaml event value, (5) schedules and requests a frame (spec §6.4). Re-rendering rewrites slots; nothing is disconnected before `destroy`. A `connect` returns a `Signals.connection` naming the object it connected *to* — which for M2 is frequently not the widget (a `GtkTextBuffer`, an event controller, a `GtkStringList`). Signals ocgtk exposes only through the generic marshaller — the `notify::<prop>` family — are connected with `Signals.notify ~prop` and read back with the class getter. Signals ocgtk cannot bind at all are omitted from the API and named in the widget's doc comment; never bound to a silent no-op (spec §11).
- **Event controllers follow the signal lifetime rules.** A controller `Controllers` attached is removed with `Widget.remove_controller` and its handlers disconnected when the attr goes away or the widget is destroyed, and its slot is emptied before teardown, exactly as `Signals.clear_slots` does for the widget's own signals. A controller is never left attached with a dead slot.
- **Every GTK call site is guarded.** Structural misuse raises `Invalid_argument` carrying the node path, at mount/patch time. Exceptions inside a trampoline are caught, logged with the node path, and do not tear down the loop. Exceptions inside a frame stop the driver for good. (spec §11)
- **Testing, three suites.** Behaviour decidable from the `Node.t` tree — constructor defaults, sexp shape, attr diffing, reconciliation, what an action does to the model — is a `ppx_expect` test in `test/` (package `bonsai_gtk`, depends on `bonsai_gtk.vtree` alone) or `test/handle/` (package `bonsai_gtk_test`). **No test directory may straddle the two packages** (spec §9's M1 amendment). Behaviour that is GTK's — that a write really moves the widget, that a keyed row is the same GObject after a reorder, that a programmatic write's signal is swallowed — is a plain executable under `test/live/` printing `Live_tree.dump`, compared by a `(diff expected.txt output.txt)` rule and gated on `(enabled_if (= %{env:BONSAI_GTK_LIVE_TESTS=0} 1))`. No `ppx_inline_test`/`ppx_expect` in anything linking ocgtk.
- **`scripts/ci.sh` must pass** at the end of every task: `nix build .#ocgtk`, per-directory `@fmt` aliases, `dune build @all`, committed `.opam` files, `@test/runtest`, both `-p` package builds, `BONSAI_GTK_LIVE_TESTS=1 xvfb-run -a dune build @test/live/runtest`, and the counter and gallery smoke runs. `dune fmt` before every commit; `.ocamlformat` is `profile=janestreet`.
- The runtime uses ocgtk **Layer 1** (`Ocgtk_gtk.Gtk.Wrappers.*`, aliased `W` in `Gtk_import`) exclusively, and never `open`s `Ocgtk_gtk.Gtk` (it shadows `unit`). Downcasts go through `Gtk_import.cast`; upcasts are plain `(x :> Widget.t)` coercions. **Layer 1 methods are `external` and positional — no labels.** Only the generated `on_*` signal helpers are `val` and labelled.

**Commit trailer** (append to every commit body):

```
Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01Sg3Ci8U8kUKR8C3PL1pNSs
```

Use `GIT_EDITOR=true git commit -F -` with a heredoc; plain `git commit -m` hung once in this environment.

**Reference sources:**
- The pinned ocgtk checkout is `.ocgtk-src/` (created by `scripts/setup-switch.sh`, gitignored). Every ocgtk signature quoted in this plan was read from `.ocgtk-src/ocgtk/src/{gtk,gdk,gio}/generated/<module>.mli`; check there first when a call does not typecheck. **The signatures in this plan were verified against that checkout on 2026-08-29** — including the ones that turned out not to exist, which are called out where they bite.
- stavekeeper, the downstream driver: `~/src/stavekeeper/lib/stavekeeper_app/{library_window,sidebar,layer_panel,dialog,setlist_ui,shell,cards}.ml`. It is a Layer-2 (`#method`) app, so read it for *which* widgets and properties a real screen needs, not for call syntax.
- `docs/m1-backlog.md` — Tasks 1–3 clear the "Do first in M2" list; Task 15 rewrites the file as `docs/m2-backlog.md`.
- `.superpowers/sdd/2026-08-29-bonsai-gtk-m1/` — M1's per-task reports, the four final-review area reports and the fix-wave ledger. When a rule in this plan looks arbitrary, its reasoning is usually there.

## ocgtk facts that shape this milestone

Verified in the pinned checkout. Each of these changed a design decision below; do not rediscover them the hard way.

| Fact | Consequence |
|---|---|
| `List_box.set_header_func` / `set_sort_func` / `set_filter_func` / `bind_model` are **NOT PRESENT** (the generator skips every GIR callback-taking method). Same for `Flow_box`. | Headers are ordinary non-selectable, non-activatable rows — which is what stavekeeper's `sidebar.ml:19-34` already builds by hand. Sorting and filtering stay in the Bonsai model, as spec §7 already says. `List_box.set_placeholder` **does** exist and is exposed. |
| `Calendar.get_date` and `select_day` are **NOT PRESENT** (they take/return `GLib.DateTime`), and **GDateTime is not bound anywhere** — there is no `GLib-2.0.gir` in the checkout. | The controlled date goes through `set_year`/`set_month`/`set_day` + `get_year`/`get_month`/`get_day`, which are all present. **GTK's `month` property is 0-based**; `Node.calendar` takes a `Core.Date.t` and the impl does the conversion, so the trap never reaches an application. |
| `Editable_label.set_text` / `get_text` are **NOT PRESENT**; `set_editing` is **NOT PRESENT** (`editing` is read-only in GTK). `start_editing : t -> unit` and `stop_editing : t -> bool -> unit` are. | Text goes through `W.Editable.from_gobject`, exactly as `w_entry.ml:8` already does for the three entry kinds. The controlled `editing` prop is written with `start_editing`/`stop_editing ~commit:true` and observed with `notify::editing` + `get_editing`. |
| `Drop_down` has exactly one signal, `on_activate`. There is no `on_selected`. | Selection is observed with `Signals.notify ~prop:"selected"` + `get_selected` — the `w_switch.ml`/`w_stack.ml` pattern. |
| `Text_buffer.on_insert_text`, `on_delete_range` and `on_mark_set` are **NOT PRESENT**. `on_changed` is, and carries no payload. | TextView's `on_changed` reads the text back with `get_bounds` + `get_text`. Cursor position is observable only through `notify::cursor-position` (the property getter `get_cursor_position` exists); M2 does not expose it, and says so on `Node.text_view`. |
| `Text_buffer.new_` takes a `Text_tag_table.t option` (pass `None`); `set_text` takes a trailing byte length (pass `-1`); `get_text` takes two iters and an `include_hidden` bool. `Text_iter` has **no** `new_`/`alloc`/`copy` — every getter returns a fresh GC-managed copy. | Reading the buffer is `let a, b = get_bounds buf in get_text buf a b true`. Iters are cheap to allocate and are invalidated by edits; re-fetch after every mutation. |
| `Event_controller_key.on_key_pressed`'s callback is `~keyval:int -> ~keycode:int -> ~state:Gdk_enums.modifiertype -> bool`. | The existing `Signals.spec.connect : Widget.t -> callback:(unit -> unit) -> connection` cannot express it, in *both* directions: arguments in and a `bool` out. This is the forcing case for Task 4's existential spec. |
| `Gdk_enums.modifiertype = modifiertype_flag list` — a **list of polymorphic variants**, not an int and not a set. `` `ALT_MASK ``, not `MOD1_MASK`. | The vtree cannot mention it, so `Modifiers.t` is a plain record of bools and `w`-side code converts. Do not assume `[]` means "no modifiers" without checking what `modifiertype_of_int 0` produces — the pre-flight scan asks for this. |
| `gdk_keyval_name` / `gdk_keyval_from_name` are **NOT PRESENT**, but `Ocgtk_gdk.Gdk_constants` has 2450 `key_*` int constants, plus `event_stop : bool` and `event_propagate : bool`. | `vtree/keyval.ml` hard-codes the handful an application needs (they are X11 keysyms and have been stable for thirty years); a live test pins every one of them against `Gdk_constants`, so the table cannot drift. |
| `Gesture.get_current_event_state` is **NOT PRESENT on `Gesture`** — the method is on `GtkEventController`. | Coerce: `W.Event_controller.get_current_event_state (g :> W.Event_controller.t)`. `Gesture_single.get_current_button` *is* on `Gesture_single`. |
| `Notebook.insert_page : t -> Widget.t -> Widget.t option -> int -> int` — the tab label is an **option**, the position is the **fourth** argument, and the result is the new page index. | Easy to get wrong; the `ignore (… : int)` is required. |
| `String_list.t`'s row is `[ \`string_list \| \`object_ ]` and `List_model.t`'s is `[ \`list_model ]`, so `:>` will not typecheck. | Use `Ocgtk_gio.Gio.Wrappers.List_model.from_gobject`, the same checked-interface-cast idiom as `Editable.from_gobject`. |
| `Gtk_constants.invalid_list_position : int` is `G_MAXUINT` — on 64-bit OCaml that is `4294967295`, **not** `-1`. | `Node.drop_down`'s "nothing selected" is `-1` in the vtree and is translated at the boundary. |
| `Widget.set_name : t -> string -> unit` (not nullable); `Stack_page.set_title : t -> string -> unit` (not nullable, though `get_title` returns an option); `Password_entry.get_placeholder_text : t -> string` (not nullable, and returns NULL from C — a crash, worked around in `Live_tree`). | These are the three nullable-binding items in `docs/m1-backlog.md`'s ocgtk-fork section. **No fork patch for them exists yet**; Task 14 prepares them locally and nothing before Task 14 may depend on them. |
| `Gobject.same` is pointer identity, and the custom block installs a pointer hash, so `Stdlib.Ephemeron.K1.Make` over `{ equal = Gobject.same; hash = Stdlib.Hashtbl.hash }` is a working weak map keyed on a GObject. | This is exactly what `src/widgets/w_search_entry.ml`'s `Echo` table already does, and it is what `Child_keys` is built on. Plain `==` on two `Gobject.obj` values wrapping one GObject is **false**; never use it. |

## File structure

| Path | Change | What |
|---|---|---|
| `vtree/attr.ml(i)` | modify | Seal behind `Attr.Private`; `Name.all`; M2's attrs (Task 1, 4, 5, 6, 7, 8, 9, 10, 11) |
| `vtree/events.ml(i)` | create | `Events.for_kind : Kind.t -> Attr.Name.t list` — the table `Signals.require_specs` and `Bonsai_gtk_test` share (Task 1) |
| `vtree/phase.ml` | create | `Capture \| Bubble \| Target` (Task 4) |
| `vtree/modifiers.ml(i)` | create | a record of bools; `none`, `equal`, `sexp_of_t` (Task 4) |
| `vtree/click_event.ml` | create | `{ button; n_press; x; y; modifiers }` (Task 4) |
| `vtree/keyval.ml(i)` | create | the curated keysym table (Task 5) |
| `vtree/key_event.ml` | create | `{ keyval; keycode; modifiers }` (Task 5) |
| `vtree/key_response.ml` | create | `Propagate \| Handled \| Propagate_and of … \| Handled_and of …` (Task 5) |
| `vtree/selection_mode.ml` | create | `None_ \| Single \| Browse \| Multiple` (Task 6) |
| `vtree/wrap_mode.ml` | create | `None_ \| Char \| Word \| Word_char` (Task 9) |
| `vtree/level_bar_mode.ml` | create | `Continuous \| Discrete` (Task 10) |
| `vtree/reconcile.ml(i)` | modify | `diff ?ordered` — no `Move` ops for an unordered container (Task 2) |
| `vtree/kind.ml(i)`, `vtree/node.ml(i)` | modify | one constructor per M2 widget; `entry_props.max_length` (Tasks 3, 6–11) |
| `vtree/defaults.ml` | modify | a module per M2 widget |
| `vtree/bonsai_gtk_vtree.ml` | modify | re-export every new module |
| `src/signals.ml(i)` | modify | `spec` becomes `Read_back \| Payload`; `spec_attr`; `require_specs` reads `Events` (Tasks 1, 4) |
| `src/controllers.ml(i)` | create | on-demand key / click / focus controllers (Tasks 4, 5) |
| `src/child_keys.ml(i)` | create | ephemeron map from a live wrapper widget to its node's `Key.t` (Task 6) |
| `src/widget_impl.ml(i)` | modify | `list_ops.move` becomes an option; `batch_if` (Task 2) |
| `src/patcher.ml(i)` | modify | `live.controllers`; `enqueue_fixups` factored out; `reassert_only`; the new containers' selection fixups; the diagnostics (Tasks 2, 3, 4, 6, 7, 8) |
| `src/driver.ml(i)` | modify | phys-equal roots take the reassert-and-fixup-only walk (Task 2) |
| `src/attr_apply.ml(i)` | modify | the new attrs' `set`/`unset` arms, and the parent-held ones' inert arms |
| `src/live_tree.ml` | modify | per-type props for every M2 widget |
| `src/gtk_import.ml(i)` | modify | `Gdk_enums`, `Gdk_constants` aliases (Task 4) |
| `src/widgets/w_list_box.ml` … `w_editable_label.ml` | create | 8 new widget impls |
| `src/widgets/w_stack.ml`, `w_grid.ml`, `w_overlay.ml`, `w_switch.ml`, `w_scrolled_window.ml` | modify | `move = None`; `w_switch` creates via `reassert`; the diagnostics (Tasks 2, 3) |
| `src/widgets/registry.ml` | modify | an arm per kind |
| `src/bonsai_gtk.ml(i)` | modify | re-export the new vtree modules; `Expert.embed` (Task 12) |
| `src/embed.ml(i)` | create | the non-window root (Task 12) |
| `test_lib/bonsai_gtk_test.ml(i)` | modify | `Search_changed`, `Set_expanded`, `Activate_row`, `Select`, `Set_page`, `Key_press`, `Click`(gesture) actions; `Events`-backed rejection (Tasks 1, 4, 5, 6, 7, 8) |
| `test/test_attrs.ml`, `test_node.ml`, `test_widgets.ml`, `test_reconcile.ml` | modify | new attrs/constructors/ops |
| `test/test_events.ml` | create | the `Events` table over `Kind` (Task 1) |
| `test/handle/*.ml` | modify | the new actions |
| `test/live/live_events.ml` (+ expected) | create | `Events` agrees with every impl's `signals` (Task 1) |
| `test/live/live_controllers.ml` (+ expected) | create | Tasks 4–5 |
| `test/live/live_lists.ml` (+ expected) | create | Tasks 6–8 |
| `test/live/live_text.ml` (+ expected) | create | Tasks 9–11 |
| `test/live/live_embed.ml` (+ expected) | create | Task 12 |
| `test/live/live_keyvals.ml` (+ expected) | create | the `Keyval` table against `Gdk_constants` (Task 5) |
| `test/live/dune` | modify | rules for the new executables |
| `test/handle/test_gallery.ml`, `examples/gallery.ml` | modify | every M2 constructor (Task 13) |
| `README.md`, the spec, `docs/m2-backlog.md` | modify/create | Task 15 |
| `scripts/ci.sh` | modify | if Task 16 finds anything |

## What M2 gives the stavekeeper port, and what it still does not

The port is why this milestone has the shape it has, so be explicit about both halves. Read against `~/src/stavekeeper/lib/stavekeeper_app/`:

**Portable after M2:**

- **`dialog.ml`** — the shared modal shell is `set_transient_for` + `set_modal` + a CAPTURE-phase Escape controller (`dialog.ml:37-51`). Task 5 gives the controller; the transient modal window itself is M3 (`Node.windows`), so a dialog ported now is a page, not a window. Say that rather than implying otherwise.
- **`sidebar.ml`** — a `GtkListBox` in `SINGLE` mode with `activate_on_single_click`, explicit rows, header rows that set `selectable false`/`activatable false` (`sidebar.ml:19-34`), a placeholder row, `on_row_activated`, and a programmatic `select_row` to restore selection after a rebuild. Task 6 covers all of it, and *removes the reason the file exists*: the parallel `rows`/`row_widgets` arrays (`sidebar.ml:150,205`) and the `get_index`-into-an-array bridge (`sidebar.ml:216-223`) exist only because `row-activated` hands back an index. `Attr.on_row_activated` hands back the node's key.
- **`layer_panel.ml`** — the same shape (`layer_panel.ml:62-96,177`), plus the `suppress_next_toggle` guard at `:117-142` that exists because `check#set_active` re-fires `toggled`. The `in_patch` guard makes that guard unnecessary; the port deletes it.
- **`library_window.ml`** — the FlowBox grid (`:211-222`), its runtime reconfiguration for list-vs-grid view (`:226-239`), `on_child_activated` and `on_selected_children_changed` (`:678,706`), the per-card `GtkGestureClick` with `set_button 0`, `get_current_button` and a shift-modifier read (`:166-185`), and the search entry with its built-in `set_search_delay 150` (`:203`). Tasks 4, 7 and M1's `search_entry` cover these. The card→model bridge via `card_entries` and `get_index` (`:479-481, 686-713`) goes the same way the sidebar's does.
- **`cards.ml`** — already portable on M1 (`Overlay` with `measure_overlay false`, `Picture` with `content_fit`, a clipping `ScrolledWindow`).

**Not portable after M2, and deliberately:**

- **Menus and popovers.** `viewer_window.ml`'s `GtkMenuButton` + `Gio.Menu` + `Gio.Simple_action` tree (`:727-731, 4074-4262`) is M3's `Node.menu`.
- **Transient modal windows.** Every dialog in the app is a second `GtkWindow` (`dialog.ml:6-53`, ten call sites). `Node.windows` is M3.
- **`GtkSearchEntry.set_key_capture_widget`.** `library_window.ml:641` arms and disarms it on every page swap; the vtree cannot name a widget, so this is an M3 item alongside `Attr.mnemonic_widget` — the same problem `stack_switcher ~stack:"name"` solves with a name registry.
- **`Event_controller_focus.contains_focus` as a *query*.** `library_window.ml:653-666` attaches a focus controller and never connects a signal: it polls `contains_focus` from inside the search entry's `changed` handler, because `has_focus` on a `GtkSearchEntry` is always false (its inner `GtkText` holds focus). M2 gives `on_focus_enter`/`on_focus_leave`, from which an application can maintain the same bit in its own model — which is the declarative answer — but it is a rewrite of that code, not a transliteration. Flagged in the README.
- **Imperative focus manipulation.** `root#set_focus (Some …)` (`library_window.ml:663`) and `win#set_focus None` on every page swap (`shell.ml:108,150`). No `Attr.grab_focus` in M2; M3 or an effect.
- **Application-wide CSS.** `theme.ml:277-300` installs one provider for the display. The fork already carries `Style_display.add_provider_for_default_display` (fork commit `d98d9397`); wiring it up is M3 per spec §7.

**The bridge M2 does build:** `Bonsai_gtk.Expert.embed` (Task 12). `shell.ml` owns an `Application_window` holding a `GtkStack` and installs pages with `stack#add_named page_widget (Some "library")` (`shell.ml:250`). `embed` returns a plain `Widget.t` that `add_named` accepts, plus a teardown. That is what makes the port incremental: the sidebar can become a bonsai subtree inside the imperative `library_window.ml` before `library_window.ml` itself is a computation.

## Pre-flight scan

Before Task 1, one scout verifies each of these **against the code**, and reports discrepancies to the controller rather than fixing them. M1's plan needed three corrections at this stage and each would have cost a task's worth of rework. Every item below is something this plan asserts and could be wrong about.

- [ ] **`Attr.t`'s consumers.** `grep -rn 'Attr\.' src/ test_lib/ | grep -v 'Attr\.Name' | wc -l`, and list every file that *matches on* `Attr.t` constructors (`| On_changed`, `| Css_class`, …) rather than only calling its constructors. Task 1 assumes the seal is a mechanical `open Attr.Private` per file. If any file destructures an `Attr.t` inside a signature or a functor argument, say so.
- [ ] **`Attr.Name.t` has no `all`.** Confirm, and confirm `[@@deriving compare, equal]` plus `Comparable.S_plain` are what `Attrs` relies on — Task 1 adds `[@@deriving enumerate]`, which needs `ppx_enumerate` (part of `ppx_jane`, already in every preprocess stanza; check `vtree/dune`).
- [ ] **The `Kind.t`↔impl event correspondence.** For each kind, list `(Registry.for_kind kind).signals |> List.map ~f:spec_attr` and compare against what `Node.<kind>`'s doc comment claims. Task 1's `Events.for_kind` must reproduce the first list exactly. Report any kind where they already disagree — that is a live bug, not an M2 item.
- [ ] **`modifiertype_of_int 0`.** Write a five-line executable under `test/live/` (throwaway; delete it after) that prints `Ocgtk_gdk.Gdk_enums.modifiertype_of_int 0` and `modifiertype_of_int 4`. Task 4 assumes the empty list means "no modifiers" and that `` `NO_MODIFIER_MASK `` does not appear in the decoding of `0`. If it does, `Modifiers.of_gdk` must filter it.
- [ ] **`Gdk_constants.key_escape` and friends.** Confirm the module path is `Ocgtk_gdk.Gdk_constants` (not `Ocgtk_gdk.Gdk.Gdk_constants`) from inside `src/`, and print `key_escape`, `key_return`, `key_tab`, `key_space`, `key_a` to confirm the values Task 5's `vtree/keyval.ml` hard-codes.
- [ ] **`Patcher`'s kind-keyed fixup dispatch.** Read `src/patcher.ml` around lines 130–185. Task 2 factors that into an `enqueue_fixups` helper called from three places; confirm it is currently one site in `mount` and one in `patch`, and that the comment at line 95 really does describe an exhaustive match that the compiler enforces.
- [ ] **`Driver.frame_body`'s root comparison.** M1 removed `Driver.t.last`. Confirm the root node of the previous frame is reachable as `t.root`'s `live.node` (i.e. `Patcher.live.node`, which is `mutable` and written back by `patch`), because Task 2's phys-equal check compares against it. If `patch` writes `live.node <- node` *before* the walk completes, the comparison is still sound but say so explicitly.
- [ ] **`Widget_impl.batch` cost.** Time it: a hundred thousand `Widget_impl.batch w (fun () -> ())` calls on a `GtkLabel`. Task 2 replaces the unconditional bracket in `reassert` with a conditional one; if `freeze_notify`/`thaw_notify` on an unchanged object is already free, say so and the step becomes a comment instead of a change.
- [ ] **`Reconcile.diff`'s `Move` emission.** Confirm `Move` is emitted only for matched pairs whose position changed and always with `from > to_` (the mli says so). Task 2's `?ordered:false` must drop exactly those and change nothing else — in particular it must not change which items are matched.
- [ ] **`Live_tree.dump`'s extension points.** Confirm the per-type match in `src/live_tree.ml` is keyed on `Gobject.Type.name` (or however it gets `"GtkLabel"`), and that adding an arm is local. Report the helper names (`int_prop`, `flag_prop`, `float_prop`, `string_prop`) so the widget tasks quote real ones.
- [ ] **`test/live/dune`'s shape.** Confirm the `(executables …)` stanza globs or lists names, and what the redundant `(deps …)` noted in the backlog looks like, so the five new executables are added the way the existing ones are.
- [ ] **stavekeeper still builds** (`cd ~/src/stavekeeper && dune build @all 2>&1 | tail -5`). The plan cites line numbers in it; if the file has moved under someone else's edits, the citations in this plan are stale and the reviewer should not treat them as authoritative.

## How to execute

Tasks are ordered by dependency and are not interchangeable. Tasks 1–3 are the backlog and must land first; 4–5 build the controller mechanism; 6–11 are the widgets, each of which depends on 1–5 and on nothing else in 6–11 **except** that 7 and 8 reuse `Child_keys` from 6 and 8 uses the `Unordered` marker from 2. 12 depends on nothing after 3. 13–16 are integration and docs.

**Per task:** one implementer, then one reviewer, then fix rounds, then a scoped re-review of just the fixes.

1. **Implementer.** Works the steps in order. Every task starts with a failing test and ends with `./scripts/ci.sh` green and one commit. If a step turns out to be wrong — a signature that does not exist, a behaviour GTK does not have — **stop and report it** rather than inventing a workaround; the plan is wrong and the controller needs to know, because the same wrong assumption is probably in three other tasks. Write a `task-N-report.md` in `.superpowers/sdd/2026-08-29-bonsai-gtk-m2/` naming: what changed, what the tests prove, every deviation from the plan and why, and everything deliberately left undone.
2. **Reviewer.** Reads the diff (`git diff <base>..<head>`, saved as `review-<base>..<head>.diff` beside the report) with the task text and this plan's Global Constraints in hand. Reviews for: does it do what the task said; does it follow the constraints (batch, controlled-prop discipline, keyed children, connection-names-its-object, no ocgtk in vtree or test_lib); are the tests real (does a golden actually pin the claim, or does it pin a default that would print the same either way — the M1 backlog's "three expect tests pass props the sexp then drops" is the failure mode); is a behaviour claimed in a doc comment actually exercised. Findings are graded Important / Minor / Out-of-scope. **Out-of-scope findings go to the backlog, not into the task.**
3. **Fix rounds.** The implementer answers every Important finding — by fixing it, or by arguing it down in writing. A finding neither fixed nor argued is a review failure, not an accepted risk.
4. **Scoped re-review.** The reviewer reads *only the fix commits* against *only the findings*, and says done or names what is still open. Do not re-review the whole task.

**At the end of the milestone**, a final whole-branch review split by area, each reviewer reading the full diff of the branch through one lens, as M1's was:

- **core** — `vtree/` (except the widget-facing constructors), `src/signals.ml`, `src/controllers.ml`, `src/patcher.ml`, `src/driver.ml`, `src/widget_impl.ml`, `src/embed.ml`. Lens: lifetimes, reentrancy, exception paths, what happens on the frame that raises.
- **controls** — `src/widgets/w_{text_view,drop_down,level_bar,calendar,editable_label}.ml` and their nodes/props/live tests. Lens: the controlled-prop rule, GTK's editing model, what a declined edit does.
- **containers** — `src/widgets/w_{list_box,flow_box,notebook}.ml`, `src/child_keys.ml`, the list-ops changes, the selection fixups. Lens: identity across reorders, what happens when a keyed child is removed while selected, ownership of the wrapper widgets.
- **tests** — `test/`, `test/handle/`, `test/live/`, `test_lib/`, `examples/`. Lens: does the suite certify anything it should not; which claims in the mlis have no test; which goldens would not change if the code were wrong.

Then one fix wave over the union of the four reports, and a re-review of the fix wave.

---

### Task 1: Seal the attr surface, and the vtree event table

Three backlog items that all live in `vtree/attr.mli` and `test_lib/`, and that every task after this one depends on. They go first because each M2 attr added before the seal is another line of a downstream exhaustive match that will break later, and because the event table is what stops the headless suite certifying an app the runtime refuses.

**Files:**
- Modify: `vtree/attr.ml`, `vtree/attr.mli`, `vtree/bonsai_gtk_vtree.ml`, `src/attr_apply.ml`, `src/signals.ml`, `src/signals.mli`, every `src/widgets/w_*.ml` that matches on `Attr.t`, `test_lib/bonsai_gtk_test.ml`, `test_lib/bonsai_gtk_test.mli`, `test/test_attrs.ml`, `test/handle/test_handle.ml`, `test/live/dune`
- Create: `vtree/events.ml`, `vtree/events.mli`, `test/test_events.ml`, `test/live/live_events.ml`, `test/live/expected_events.txt`

**Interfaces:**
- Produces:
  ```ocaml
  (* vtree/attr.mli — the whole variant moves behind [Private]. *)
  type t

  val sexp_of_t : t -> Sexp.t
  (* every existing smart constructor stays exactly where it is *)

  module Name : sig
    type t = ... (* still concrete: see the ruling below *)
    val all : t list
    val is_event : t -> bool
    val to_string : t -> string
    include Comparable.S_plain with type t := t
  end

  module Private : sig
    (** No stability promise. The library's own runtime and test harness match on this;
        an application that does is choosing to break on the next milestone. *)
    type nonrec t = t =
      | Css_class of string
      | ...
      | Many of t list
  end

  (* vtree/events.mli *)
  val for_kind : Kind.t -> Attr.Name.t list
  val is_supported : Kind.t -> Attr.Name.t -> bool
  val unsupported : Kind.t -> Attrs.t -> Attr.Name.t option

  (* test_lib/bonsai_gtk_test.mli — Action.t gains *)
  | Search_changed of string * string
  | Set_expanded of string * bool
  ```
- Consumes: nothing new from ocgtk.

**The seal, and why it is cheap.** `type nonrec t = t = | Css_class of string | …` inside `module Private` re-exports the *same* type with its constructors visible there and nowhere else. `Attr.t` and `Attr.Private.t` are the same type, so nothing needs converting; a file that matches on the variant adds one line — `open Attr.Private` at the top, or `match (attr : Attr.Private.t) with` at the site — and its existing match compiles unchanged. This is the same idiom `Bonsai_gtk.Private` already uses, and it is what makes the "real refactor touching four files plus every task below it" the M1 ruling feared into a mechanical edit. **Do not** invent a separate `repr` type and a conversion function: that would be a real refactor, it would allocate, and it buys nothing the type re-export does not.

`Attr.Name.t` stays concrete in the documented surface, per M1's ruling: it is only reachable through `Attrs.op`, which is `Private`-adjacent already, and `Attr_apply.unset` matching on it exhaustively is the mechanism that makes "unset restores the creation-time default" impossible to forget for a new attr. Sealing it would trade a compile error for a silent omission. Say this in the mli.

**The event table, and the two sources of truth.** `Events.for_kind` is pure data in `vtree`; `(Registry.for_kind kind).signals` is the real thing in `src`. They must agree, and nothing but a test can make them. That test cannot be a `ppx_expect` test — it links ocgtk — so it is `test/live/live_events.ml`, which needs no display but lives under the live gate for the ocgtk-free rule. It is the *only* thing standing between the two lists, so write it first and make its failure message say which kind and which direction.

- [ ] **Step 1: Write the failing tests**

`test/test_events.ml` — new file:

```ocaml
open! Core
open Bonsai_gtk_vtree

(* One row per kind, so that adding a kind without an [Events] arm is a compile error and
   adding one with the wrong arm is a diff here. The kinds are built with their cheapest
   constructor; only the constructor, not the props, decides the answer. *)
let%expect_test "every kind's event attrs" =
  let kinds =
    [ (Node.label "x").kind
    ; (Node.button ()).kind
    ; (Node.toggle_button ~active:false ()).kind
    ; (Node.switch ~active:false ()).kind
    ; (Node.entry ()).kind
    ; (Node.search_entry ()).kind
    ; (Node.scale ~min:0. ~max:1. ~value:0. ()).kind
    ; (Node.expander ~expanded:false ~label:"e" (Node.label "x")).kind
    ; (Node.stack ~name:"s" ~visible_child:"a" []).kind
    ; (Node.box ~orientation:Vertical []).kind
    ]
  in
  List.iter kinds ~f:(fun kind ->
    print_s [%sexp (Kind.name kind : string), (Events.for_kind kind : Attr.Name.t list)]);
  [%expect {| |}]
;;

let%expect_test "unsupported finds the offending name, and only event names" =
  let attrs =
    Attrs.of_list
      [ Attr.css_class "c"; Attr.test_id "t"; Attr.on_toggled (fun _ -> Ui_effect.Ignore) ]
  in
  print_s [%sexp (Events.unsupported (Node.label "x").kind attrs : Attr.Name.t option)];
  [%expect {| |}];
  print_s
    [%sexp
      (Events.unsupported (Node.switch ~active:false ()).kind attrs : Attr.Name.t option)];
  [%expect {| |}]
;;

(* [Attr.Name.all] exists so that [is_event]'s classification is pinned rather than
   assumed -- the M1 final review found it tested on 2 names of 32, and adding an [On_foo]
   to the wrong branch compiles. *)
let%expect_test "is_event over every name" =
  let events, plain = List.partition_tf Attr.Name.all ~f:Attr.Name.is_event in
  print_s [%sexp `events (events : Attr.Name.t list)];
  [%expect {| |}];
  print_s [%sexp `plain (plain : Attr.Name.t list)];
  [%expect {| |}]
;;
```

`test/handle/test_handle.ml` — append the two new actions and the rejection:

```ocaml
let searcher (graph @ local) =
  let query, set_query = Bonsai.state "" graph in
  let%arr query and set_query in
  Node.window
    ~title:"Search"
    (Node.box
       ~orientation:Vertical
       [ Node.search_entry
           ~attrs:[ Attr.test_id "q"; Attr.on_search_changed set_query ]
           ~text:query
           ()
       ; Node.expander
           ~attrs:[ Attr.test_id "adv"; Attr.on_expanded_changed (fun _ -> Ui_effect.Ignore) ]
           ~expanded:false
           ~label:"advanced"
           (Node.label ~attrs:[ Attr.test_id "hits" ] query)
       ])
;;

let%expect_test "Search_changed and Set_expanded reach their handlers" =
  let handle = Bonsai_gtk_test.create searcher in
  Bonsai_gtk_test.Handle.show handle;
  [%expect {| |}];
  Bonsai_gtk_test.Handle.do_actions handle [ Search_changed ("q", "bach") ];
  Bonsai_gtk_test.Handle.show_diff handle;
  [%expect {| |}];
  Bonsai_gtk_test.Handle.do_actions handle [ Set_expanded ("adv", true) ];
  Bonsai_gtk_test.Handle.show_diff handle;
  [%expect {| |}]
;;

(* The whole point of [Events]: a handle that would have gone green on a tree the runtime
   refuses at mount now refuses it here, with the same message shape. *)
let%expect_test "an event attr the kind cannot emit is rejected by the handle" =
  let bad (_graph @ local) =
    Bonsai.return
      (Node.window
         ~title:"bad"
         (Node.label ~attrs:[ Attr.on_toggled (fun _ -> Ui_effect.Ignore) ] "not a switch"))
  in
  Expect_test_helpers_core.require_does_raise (fun () ->
    let handle = Bonsai_gtk_test.create bad in
    Bonsai_gtk_test.Handle.show handle);
  [%expect {| |}]
;;
```

`test/live/live_events.ml` — the agreement test:

```ocaml
open! Core
open Bonsai_gtk_vtree
module Registry = Bonsai_gtk.Private.Registry
module Signals = Bonsai_gtk.Private.Signals

(* Every kind, built with its cheapest constructor. This list is the one place that has to
   grow with [Kind.t]; there is no exhaustive-match trick that produces a *value* per
   constructor, so a new kind missing from here is caught by the count assertion below
   rather than by the compiler. *)
let all_kinds : Kind.t list = [ (* ... every Node constructor, one call each ... *) ]

let () =
  (* No display is needed: [Registry.for_kind] only reads a record. The file lives under
     the live gate because it links ocgtk, which ppx_expect cannot. *)
  List.iter all_kinds ~f:(fun kind ->
    let from_impl =
      (Registry.for_kind kind).signals
      |> List.map ~f:Signals.spec_attr
      |> List.sort ~compare:Attr.Name.compare
    in
    let from_table = List.sort (Events.for_kind kind) ~compare:Attr.Name.compare in
    if not (List.equal Attr.Name.equal from_impl from_table)
    then
      print_s
        [%message
          "MISMATCH"
            ~kind:(Kind.name kind)
            ~impl:(from_impl : Attr.Name.t list)
            ~table:(from_table : Attr.Name.t list)]);
  printf "kinds checked: %d\n" (List.length all_kinds);
  printf "agreed\n"
;;
```

The expected file is two lines. A mismatch prints a third and the diff fails. `kinds checked` is what catches a kind nobody added to `all_kinds`: bump it deliberately, and Task 13's gallery sweep is the second net under it.

- [ ] **Step 2: Run to verify failure** — `dune build @test/runtest` → unbound `Events`, unbound `Attr.Name.all`, unknown constructor `Search_changed`.

- [ ] **Step 3: `vtree/attr.ml(i)` — the seal and `Name.all`**

In `attr.mli`, replace the bare `type t = | Css_class of string | …` with `type t` plus `val sexp_of_t : t -> Sexp.t`, keep every smart constructor and `val name`/`val equal` where they are, and add at the bottom:

```ocaml
module Private : sig
  (** {b No stability promise.} The variant, for the library's own runtime
      ([Attr_apply], [Signals], the widget impls) and its test harness. It is the same
      type as {!t} — [Attr.Private.Css_class "x"] and [Attr.css_class "x"] are the same
      value — so nothing converts and nothing allocates.

      It is here rather than in the documented surface because every milestone adds
      constructors, and an application matching on them exhaustively would break on each
      one. Build attrs with the constructors above; if you find yourself needing to take
      one apart, that is a missing accessor and worth an issue. *)
  type nonrec t = t =
    | Css_class of string
    | Margin_start of int
    (* ... every constructor, unchanged and in the same order ... *)
    | Many of t list
end
```

`attr.ml` needs `module Private = struct type nonrec t = t = Css_class of string | … end`, spelled out. That duplication is the price of the idiom; a comment in `attr.ml` says so and points at the compiler error a divergence produces (it is a type error, not a silent drift — the two definitions must be structurally identical or `type nonrec t = t = …` does not typecheck, which is exactly the safety we want).

`Name.t` gains `[@@deriving enumerate]` alongside its existing derivings, and:

```ocaml
val all : t list
(** Every attribute name, for tests that must not be able to forget one. The M1 review
    found [is_event] pinned on 2 of 32 names, which is the same as unpinned. *)

val to_string : t -> string
(** The name as it appears in error messages — [Sexp.to_string (sexp_of_t t)]. *)
```

Add a paragraph to `Name.t`'s doc saying why *it* is not sealed: `Attr_apply.unset`'s exhaustive match over it is what makes an attr's restore-to-default impossible to forget, and it is only reachable through `Attrs.op`.

- [ ] **Step 4: Every matcher gets one line**

`grep -ln 'Attr\.' src/*.ml src/widgets/*.ml test_lib/*.ml` and, for each file that *matches on* the variant, add `open Attr.Private` after the existing `open Bonsai_gtk_vtree` — or, where the file already writes `(attr : Attr.t)` in a match scrutinee annotation, change it to `(attr : Attr.Private.t)`. Prefer the annotation form in `Signals.spec` bodies (it is one word and keeps the constructor namespace out of the file); prefer the `open` in `src/attr_apply.ml`, which is nothing but matches.

Files expected to need it: `src/attr_apply.ml`, `src/signals.ml`, `src/widgets/w_{button,entry,search_entry,password_entry,toggle_button,check_button,switch,spin_button,scale,expander,revealer,paned,stack,grid,overlay}.ml`, `test_lib/bonsai_gtk_test.ml`. The pre-flight scan produces the real list; if it is longer than this, that is fine — each is one line.

- [ ] **Step 5: `vtree/events.ml(i)`**

```ocaml
open! Core

(** Which event attributes each kind can carry.

    Pure data, in [vtree] rather than in the runtime, because two things need it and only
    one of them may link ocgtk: [Signals.require_specs] rejects an unsupported event attr
    at mount, and [Bonsai_gtk_test] must reject the same tree at handle time — otherwise a
    suite that is entirely headless certifies an application that raises the moment it is
    shown, which is exactly what M1 shipped (see [bonsai_gtk_test.mli]'s warning, which
    Task 1 rewrites).

    This table and each widget impl's [Widget_impl.signals] are two statements of one
    fact. [test/live/live_events.ml] compares them for every kind and fails the build if
    they disagree; that test is the only thing keeping them honest, so do not weaken it. *)
val for_kind : Kind.t -> Attr.Name.t list

(** [is_supported kind name] is [true] if [name] is not an event name, or is one this kind
    emits. A non-event name is always supported: this answers "may this attr be here",
    and layout attrs may be anywhere. *)
val is_supported : Kind.t -> Attr.Name.t -> bool

(** The first event attr in [attrs] that [kind] cannot emit, in [Attr.Name] order. [None]
    when every event attr present is one this kind emits. *)
val unsupported : Kind.t -> Attrs.t -> Attr.Name.t option
```

The implementation is one `match` over `Kind.t` with no wildcard arm:

```ocaml
let for_kind : Kind.t -> Attr.Name.t list = function
  | Label _ | Image _ | Picture _ | Separator _ | Spinner _ | Progress_bar _
  | Level_bar _ | Stack_switcher _ | Stack_sidebar _ | Native _ -> []
  | Button _ -> [ On_clicked ]
  | Toggle_button _ | Check_button _ | Switch _ -> [ On_toggled ]
  | Entry _ | Password_entry _ -> [ On_changed; On_activate ]
  | Search_entry _ -> [ On_changed; On_activate; On_search_changed ]
  | Spin_button _ | Scale _ -> [ On_value_changed ]
  | Expander _ -> [ On_expanded_changed ]
  | Revealer _ -> [ On_revealed ]
  | Paned _ -> [ On_position_changed ]
  | Stack _ -> [ On_visible_child_changed ]
  | Window _ | Box _ | Grid _ | Center_box _ | Overlay _ | Frame _
  | Scrolled_window _ -> []
  (* M2's kinds are added by their own tasks. *)
;;
```

`Native _ -> []` is load-bearing and matches spec §6.6: a native node declares no specs, so any event attr on one is rejected.

The **controller attrs are not in this table** and must not be: `On_key_pressed`, `On_click` and the rest are handled by `Controllers`, not by any impl's `signals`, and they are legal on *every* kind. `is_supported` therefore returns `true` for them unconditionally. Task 4 adds that arm and a comment saying why, and extends `live_events.ml` to assert that no impl declares a controller name in its `signals`.

- [ ] **Step 6: `src/signals.ml(i)` — `require_specs` reads the table**

`require_specs` currently walks the impl's specs. Change it to take the kind and consult `Events.unsupported`, so that the mount-time rejection and the headless rejection are the *same* function of the *same* data:

```ocaml
val require_specs
  :  node_path:string
  -> impl_name:string
  -> Kind.t
  -> Attrs.t
  -> unit
```

and its body is `match Events.unsupported kind attrs with None -> () | Some name -> invalid_argf "%s: %s cannot emit %s" node_path impl_name (Attr.Name.to_string name) ()`. Keep the message shape M1 used so the existing expected files do not churn; if it does churn, read the diff and promote deliberately.

The `spec list` argument goes away, which means `Patcher` passes `live.node.kind` instead of `impl.signals`. That is one call site each in `mount` and `patch`.

`spec_attr : spec -> Attr.Name.t` is added now (trivially `fun s -> s.attr`) because Task 4 turns `spec` into a variant and `live_events.ml` should not have to change then.

- [ ] **Step 7: `test_lib/bonsai_gtk_test.ml(i)` — two actions, and the validation**

```ocaml
| Search_changed of string * string
(** test_id of a [search_entry] carrying [Attr.on_search_changed], and the text the
    user typed. Fires that handler with exactly that string.

    Distinct from [Set_text] on the same node, which fires [Attr.on_changed]: the two
    are different signals on the real widget — [changed] is immediate, [search-changed]
    arrives [search_delay] ms after typing stops — and an app that attaches both wants
    to test them apart. Neither consults the node's own [text] prop, for the reason
    [Set_text] documents. *)

| Set_expanded of string * bool
(** test_id of an [expander] carrying [Attr.on_expanded_changed], and the state the user
    dragged it to. Fires that handler with exactly that bool; the node's own [expanded]
    prop is not consulted, so a test can show a model that declines to open. *)
```

And in `create`, before returning the handle, install validation: the result spec's `view` (or a wrapper around it) walks the node tree and raises `Invalid_argument` on the first node whose `Events.unsupported node.kind node.attrs` is `Some name`, with the same `path: kind cannot emit name` shape the patcher uses. Walk with `Children.iteri` so the path spelling matches the patcher's exactly.

Then **rewrite the "Structural validation happens at mount, not here" paragraph** in `bonsai_gtk_test.mli`. It is now half wrong, which is worse than wholly wrong. The new text says: event attrs a kind cannot emit *are* rejected here, by the same table the runtime uses; what is still only checked at mount is the structural half — a `Node.grid` child with no `Attr.grid_cell`, a `Node.stack` page with no `~key`, two stacks under one `~name`, duplicate sibling keys, a `Node.window` off-root — and the escape from that is still a live test or running the app.

- [ ] **Step 8: `test/live/dune`** — add `live_events` to the `(names …)` list and a rule in the shape of the existing ones.

- [ ] **Step 9: Run, read, promote**

```
dune build @test/runtest && dune promote
BONSAI_GTK_LIVE_TESTS=1 xvfb-run -a dune build @test/live/runtest && dune promote
./scripts/ci.sh
```

Read `expected_events.txt` before promoting: it must say `agreed`, and `kinds checked` must equal the number of arms in `Registry.for_kind`. Every other expected file must be **unchanged** — this task changes no runtime behaviour. A diff anywhere else means the `require_specs` message shape moved; decide deliberately.

- [ ] **Step 10: Commit**

```bash
dune fmt 2>/dev/null; git add vtree src test test_lib
GIT_EDITOR=true git commit -F - <<'MSG'
Seal Attr.t behind Attr.Private; one event table for the runtime and the harness

Attr.t's variant moves into Attr.Private, which carries no stability promise,
so M2's and M3's attrs stop being breaking changes for a downstream exhaustive
match. It is a type re-export, not a conversion: Attr.t and Attr.Private.t are
the same type, and every internal matcher needed one line.

Events.for_kind is the Kind.t -> Attr.Name.t list table that Signals.require_specs
and Bonsai_gtk_test now share, so the headless suite refuses exactly the trees
the runtime refuses instead of certifying an app that raises at mount.
test/live/live_events.ml is the only thing keeping the table and the widget
impls' own signal lists in agreement.

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01Sg3Ci8U8kUKR8C3PL1pNSs
MSG
```

**Review focus:** that the seal really is the same type (no conversion, no allocation, no `Obj`); that `Events.for_kind` has no wildcard arm; that `live_events.ml` would actually fail if a table entry were wrong — try breaking one deliberately and confirm the diff goes red before promoting; that the rewritten `bonsai_gtk_test.mli` paragraph does not now overclaim in the other direction.

---

### Task 2: What a patch does — the phys-equal walk, the unordered marker, the batch cost, `w_switch`

Four backlog items, all about the patch path, and all cheaper to do before eight widgets are built on top of them.

**Files:**
- Modify: `vtree/reconcile.ml`, `vtree/reconcile.mli`, `src/widget_impl.ml`, `src/widget_impl.mli`, `src/patcher.ml`, `src/patcher.mli`, `src/driver.ml`, `src/driver.mli`, `src/widgets/w_stack.ml`, `src/widgets/w_grid.ml`, `src/widgets/w_overlay.ml`, `src/widgets/w_box.ml`, `src/widgets/w_switch.ml`, `test/test_reconcile.ml`, `test/live/live_containers.ml`, `test/live/live_driver.ml`
- Create: nothing

**Interfaces:**
- Changed:
  ```ocaml
  (* Reconcile *)
  val diff
    :  ?ordered:bool  (** default [true] *)
    -> key:('a -> Key.t option)
    -> same_kind:('a -> 'a -> bool)
    -> old:'a list
    -> new_:'a list
    -> 'a op list

  (* Widget_impl *)
  type list_ops =
    { insert : Widget.t -> after:Widget.t option -> node:Node.t -> Widget.t -> unit
    ; move : (Widget.t -> child:Widget.t -> after:Widget.t option -> unit) option
    ; remove : Widget.t -> Widget.t -> unit
    ; updated : Widget.t -> old:Node.t -> node:Node.t -> Widget.t -> unit
    }

  val batch_if : bool -> Widget.t -> (unit -> unit) -> unit

  (* Patcher *)
  val reassert_only : ctx -> live -> unit
  ```
- Unchanged: everything else. `Reconcile.apply` keeps its meaning; the op type does not change.

**Why `move` becomes an option rather than a `bool` beside it.** M1's ruling 4 deferred this pending a container with a real reorder; Notebook (Task 8) is that container. Two facts have to stay in step — "this container can reorder" and "here is how" — and a `bool` field next to a `move` function lets them disagree. An `option` makes the illegal states unrepresentable: `None` *is* the marker, and the patcher cannot call a `move` that a container does not have. `Overlay`, `Stack` and `Grid` take `None`; `Box` and (in Task 8) `Notebook` take `Some`.

The patcher then passes `~ordered:(Option.is_some move)` to `Reconcile.diff`, and `diff` emits no `Move` ops at all for an unordered list. That is strictly better than M1's no-op `move`: the ops the reconciler produces and the ops the patcher can apply are the same set, so the `cur` bookkeeping never records a move that did not happen, and a reader of a `Reconcile.diff` sexp in a test is not looking at ops that are silently discarded.

**What `?ordered:false` must and must not change.** It drops the `Move` ops. It must not change which items are *matched* — matching is by key, and an unordered container's children still have keys and still preserve identity across a reorder. Concretely: for `old = [a; b; c]`, `new_ = [c; a; b]`, ordered gives `Move` ops plus three `Update`s; unordered gives three `Update`s and nothing else, in `new_`'s order. The children stay where GTK put them; only the paint or tab order goes unreconciled, which is what spec §5.3 already documents for those three.

- [ ] **Step 1: Write the failing tests**

`test/test_reconcile.ml` — append:

```ocaml
let%expect_test "an unordered diff matches by key but emits no Move" =
  let item k = k in
  let diff ?ordered old new_ =
    Reconcile.diff
      ?ordered
      ~key:(fun k -> Some k)
      ~same_kind:(fun _ _ -> true)
      ~old:(List.map old ~f:item)
      ~new_:(List.map new_ ~f:item)
  in
  print_s [%sexp (diff [ "a"; "b"; "c" ] [ "c"; "a"; "b" ] : string Reconcile.op list)];
  [%expect {| |}];
  print_s
    [%sexp
      (diff ~ordered:false [ "a"; "b"; "c" ] [ "c"; "a"; "b" ] : string Reconcile.op list)];
  [%expect {| |}];
  (* Removals and insertions are unaffected: an unordered container still adds and drops
     children, it just cannot say where. *)
  print_s
    [%sexp
      (diff ~ordered:false [ "a"; "b" ] [ "b"; "c" ] : string Reconcile.op list)];
  [%expect {| |}]
;;
```

`test/live/live_driver.ml` — the phys-equal walk. This is the test that says the optimisation did not break the thing M1's comment refused to break:

```ocaml
  (* Bonsai handing back the *physically same* node must still put a declined edit back.
     M1 paid a full tree walk for this; the walk is now reassert-and-fixups only, and this
     is what says the two are equivalent where it matters.

     The node is built once and returned by reference, which is what a Bonsai computation
     whose state did not change does. Then the widget is changed behind the driver's back,
     the way a user does, and one frame must undo it. *)
  let view = Node.window ~title:"phys" (Node.switch ~attrs:[ ... ] ~active:false ()) in
  let d = Driver.create ~on_window_created:(fun _ -> ()) (fun (_ : local_ Bonsai.graph) ->
    Bonsai.return view)
  in
  Driver.frame d;
  printf "after mount: %b\n" (switch_active d);
  set_switch_active d true;              (* the user flips it *)
  printf "after the user flipped it: %b\n" (switch_active d);
  Driver.frame d;                        (* same node, reassert-only walk *)
  printf "after the declining frame: %b\n" (switch_active d);
```

Expected: `false`, `true`, `false`. And the same shape for a stack whose `~visible_child` the user navigated away from with a switcher click, which exercises the *fixup* half rather than the `reassert` half — that one is the reason the walk cannot be "call `reassert` and stop".

- [ ] **Step 2: Run to verify failure** — `dune build @test/runtest` → unknown labelled argument `?ordered`.

- [ ] **Step 3: `vtree/reconcile.ml(i)`**

Add `?(ordered = true)` and, at the single point where a matched pair's position change emits a `Move`, guard it. The mli gains:

```ocaml
    [ordered] is [false] for a container GTK gives no reorder primitive for — an
    overlay, a stack, a grid. Matching is unaffected (identity is by key either way, and
    state still survives a reorder); what changes is that no [Move] is emitted, because
    the patcher would have nothing to apply it with. Emitting one and discarding it is
    worse than not emitting it: the discarded op is still counted in the patcher's index
    bookkeeping, and it shows up in a test's [op list] as though something happened.
```

- [ ] **Step 4: `src/widget_impl.ml(i)` — `move` becomes an option, and `batch_if`**

The doc on `move` is rewritten:

```ocaml
  ; move : (Widget.t -> child:Widget.t -> after:Widget.t option -> unit) option
  (** Move a child already in the container to sit directly after [after] ([None] =
      first). [after] is computed over the sibling list with [child] already taken out of
      it, which is the order GTK's [reorder_child_after] expects.

      [None] means this container has no reorder primitive — [GtkOverlay], [GtkStack] and
      [GtkGrid] have none — and is not a no-op but a *marker*: the patcher passes
      [~ordered:false] to [Reconcile.diff], which then emits no [Move] at all. Keys still
      preserve identity; children stay in the order they were first added, and for a stack
      or a grid that order is invisible anyway (a grid's placement is its
      {!Bonsai_gtk_vtree.Attr.grid_cell}). *)
```

and `batch_if`:

```ocaml
val batch_if : bool -> Widget.t -> (unit -> unit) -> unit
(** [batch_if writes w f] is {!batch} when [writes], and [f ()] otherwise.

    For [reassert], which runs on every patch of every node of its kind — including the
    overwhelming majority that write nothing — and which was paying a
    [freeze_notify]/[thaw_notify] pair each time. The caller decides [writes] by the same
    comparison it was about to make anyway: [reassert] for a single-prop kind computes
    "does the widget already hold this" first, and brackets only when the answer is no.

    A [reassert] that writes two or more props still has to bracket before the first
    write, so its [writes] is the disjunction of its per-prop comparisons. Getting that
    wrong is a correctness bug (an unbracketed multi-prop write emits a [notify::] per
    setter), so a kind with several controlled props should prefer plain {!batch} unless
    the saving was measured. *)
```

- [ ] **Step 5: `src/widgets/*.ml` — the four containers, and `w_switch`**

`w_box.ml`: `move = Some (fun parent ~child ~after -> W.Box.reorder_child_after (cast parent) child after)`.
`w_stack.ml`, `w_grid.ml`, `w_overlay.ml`: `move = None`, and each one's existing "this is a documented no-op" comment becomes "this container is unordered; see `Widget_impl.list_ops.move`".

`w_switch.ml`'s `create` currently hand-writes `active`. Route it through `reassert` instead, so the controlled prop has exactly one implementation:

```ocaml
let reassert w (kind : Kind.t) =
  match kind with
  | Switch p ->
    let s : W.Switch.t = cast w in
    let writes = not (Bool.equal (W.Switch.get_active s) p.active) in
    Widget_impl.batch_if writes w (fun () -> if writes then W.Switch.set_active s p.active)
  | k -> Widget_impl.wrong_kind "Switch" k
;;
```
and `create` ends with `reassert w kind` rather than its own `set_active`. Two consequences worth stating in a comment: the widget is created inactive and then written, which is one extra property write on the create path for an initially-active switch, and it is the same write the patcher would have made on the next frame; and `create` runs *outside* the patch guard on the very first mount, so the `notify::active` it emits is real — harmless, because the slots are empty until `Signals.update_slots` runs, which is after `create`. Confirm that ordering in `Patcher.mount` before writing the comment.

Do the same audit for every other kind with a `reassert` — `w_entry`, `w_password_entry`, `w_search_entry`, `w_toggle_button`, `w_check_button`, `w_spin_button`, `w_scale`, `w_expander`, `w_revealer` — and convert each unconditional `Widget_impl.batch` in `reassert` to `batch_if`. Where the kind has one controlled prop this is mechanical. `w_entry` is the interesting one: `set_text_if_needed` already returns whether it wrote, but the bracket has to be *outside* the decision, so restructure to compare first (`String.equal (W.Editable.get_text e) text`), then `batch_if`, then write.

If the pre-flight scan's timing says `freeze_notify`/`thaw_notify` on an unchanged object is free, skip this step entirely, delete `batch_if`, and record the measurement in the task report. Do not add an abstraction to avoid a cost that is not there.

- [ ] **Step 6: `src/patcher.ml` — `enqueue_fixups`, and `reassert_only`**

Factor the kind-keyed fixup dispatch (currently inline in `mount` and again in `patch`) into one function, because a third caller is about to need it:

```ocaml
(* What a node of this kind wants done once the whole pass is over: a stack selecting a
   page that does not exist while the stack is being built, a switcher resolving the stack
   it names. Called from [mount], from [patch], and from [reassert_only] -- the last is
   why it is a function rather than two copies: a frame that skips the walk must still
   re-apply the selections, since a selection is a controlled prop and the frame that
   declines a navigation is exactly the frame where nothing else moved. *)
let enqueue_fixups ctx ~path (live : live) = ...
```

and add the walk:

```ocaml
(** Re-applies every controlled prop in the tree and re-runs the pass's fixups, without
    diffing anything.

    For the frames on which Bonsai hands back the physically same node it handed back last
    frame. Nothing in the tree can have changed — it is the same value — so there is no
    [update] to run, no [Attrs.diff] to compute and no child list to reconcile. What there
    still is, and what M1's full walk was really paying for, is the two halves of the
    controlled-prop rule: [Widget_impl.reassert] and the selection fixups. A model that
    *declines* a user's edit renders the same value it rendered last frame, so this is
    precisely the frame on which the widget has to be put back. Skipping it entirely — the
    obvious optimisation, and the one [Driver.frame_body]'s comment refused — leaves the
    declined edit standing on screen.

    Does not touch [live.node] (it is already the node), does not run [require_specs] (the
    attrs are the same values), and does not run lifecycles. Raises what a [reassert]
    raises. *)
let rec reassert_only ctx (live : live) =
  Option.iter live.impl.reassert ~f:(fun f -> f live.widget live.node.kind);
  enqueue_fixups ctx ~path:live_path live;
  Children.iter live.children ~f:(reassert_only ctx)
;;
```

Note the path: `enqueue_fixups` wants one for its error messages. `live` does not carry its path today (the backlog's "node paths are frozen at mount" item is about this). Either thread `~path` through the recursion the way `mount`/`patch` do — cheap, and what this plan assumes — or add a `path` field to `live`. Prefer threading; adding the field is a bigger change than this task should make and the backlog item that would justify it is about staleness after a move, which threading also fixes for this walk.

- [ ] **Step 7: `src/driver.ml(i)`**

In `frame_body`, replace the "every frame patches" comment's *conclusion* while keeping its reasoning, and branch:

```ocaml
  check_root node;
  Scheduler.with_patch_guard t.scheduler (fun () ->
    match t.root with
    | Some live when phys_equal node live.node ->
      (* Bonsai handed back the same value. Nothing to diff -- but the controlled props
         still have to be re-asserted, because the frame on which the model declines a
         user's edit is exactly the frame on which its view did not change. See
         [Patcher.reassert_only]. *)
      Patcher.reassert_only t.patcher_ctx live;
      Patcher.run_fixups t.patcher_ctx
    | _ ->
      t.root <- Some (... the existing mount-or-patch ...);
      Patcher.run_fixups t.patcher_ctx)
```

The comparison is against `live.node`, which `patch` writes back. Confirm from the pre-flight scan that `patch` assigns `live.node <- node` and that a frame which raised does not leave a stale one (it does not: the driver is broken and never runs another frame).

`driver.mli` on `frame` gains: "A frame on which the computation returns the physically same node as the previous frame does not diff: it re-asserts the tree's controlled props and re-runs its fixups, which is the whole of what a no-change frame ever did. This is what makes an idle tick nearly free."

- [ ] **Step 8: Run, read, promote**

Every existing `expected_*.txt` must be **unchanged**. This task is a refactor plus an optimisation; a diff in `expected_containers.txt` means the unordered marker changed a placement, which it must not. If `live_containers.ml`'s overlay or stack section diffs, re-read Step 3 — the likeliest bug is dropping `Move` *and* the matching that produced it.

Add to `live_containers.ml` the case the marker exists for: an overlay whose three keyed children are rendered in a new order, twice, asserting the dump is identical both times *and* that each child is the same GObject (compare `Gobject.same` against handles taken before the patch). That is the claim "keys still preserve identity" and it had no test.

- [ ] **Step 9: Full gate + commit**

```bash
./scripts/ci.sh
dune fmt 2>/dev/null; git add vtree src test
GIT_EDITOR=true git commit -F - <<'MSG'
Unordered containers, cheaper reasserts, and a no-diff frame that still reasserts

[list_ops.move] is an option: [None] is the marker for a container GTK gives no
reorder primitive for, and [Reconcile.diff ~ordered:false] then emits no [Move]
at all rather than emitting one for the patcher to discard. Overlay, Stack and
Grid take it; Notebook (M2) will not.

A frame on which Bonsai returns the physically same node takes a
reassert-and-fixups-only walk instead of a full diff. M1 paid the full walk
deliberately, because that frame is exactly the one on which a declined edit has
to be put back -- so the new walk does both halves of that (reassert and the
selection fixups) and nothing else.

[Widget_impl.batch_if] stops every controlled kind from bracketing a
freeze/thaw around the patches that write nothing, and [w_switch] now creates
through its own [reassert] like every other controlled kind.

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01Sg3Ci8U8kUKR8C3PL1pNSs
MSG
```

**Review focus:** that `?ordered:false` changed matching in no way (read the diff of `Reconcile.diff` line by line); that `reassert_only` really does run the fixups and not only the reasserts — the stack case in `live_driver.ml` is the test that says so, and it should fail if the `enqueue_fixups` call is deleted; that `batch_if`'s `writes` argument is the disjunction of the comparisons in every multi-prop `reassert` that uses it; that `w_switch.create` calling `reassert` cannot fire a handler (slots are empty until after `create`).

---

### Task 3: The diagnostics backlog — silent inertness becomes `Invalid_argument`

Five items, all of the same shape: something an application can write that today does nothing and says nothing. Each is a typo with no feedback, and each gets more expensive to add once more containers read parent-held attrs (Tasks 6, 7 and 8 all add one).

**Files:**
- Modify: `vtree/attr.mli`, `vtree/kind.ml`, `vtree/kind.mli`, `vtree/node.ml`, `vtree/node.mli`, `vtree/defaults.ml`, `src/patcher.ml`, `src/widgets/w_stack.ml`, `src/widgets/w_entry.ml`, `src/live_tree.ml`, `test/test_widgets.ml`, `test/live/live_containers.ml`, `test/live/live_controls.ml`
- Create: nothing

**The five:**

1. **`Attr.grid_cell` and `Attr.page_title` outside their container are silently inert.** A `Node.grid_cell` on a box child, a `Node.page_title` on a button in a header bar — nothing reads them, nothing complains.
2. **`Node.stack ~visible_child` naming a page that never exists is silently inert forever.** Right for a page that arrives on a later frame, wrong for a typo, and indistinguishable today.
3. **`min > max` content bounds on `Node.scrolled_window`** are not rejected. GTK calls it a programming error and has no runtime check of its own.
4. **`Kind.entry_props` has no `max_length`.** Absent from spec §7's signature too, so never-scoped rather than dropped — but `GtkEntry:max-length` is the usual companion to a controlled `text`, and stavekeeper's `dialog.ml` fields would use it.
5. **The same-frame stack name *swap* raises the wrong error.** Two stacks exchanging names in one frame gives `two Node.stacks are named "b" in one tree`, because `note_interest`'s rename arm does `Hashtbl.remove old; register new` per child left to right and the second stack still holds the new name.

**Interfaces:**
- Produces:
  ```ocaml
  (* Node *)
  val entry : ... -> ?max_length:int -> ... -> unit -> t   (* -1 = unlimited, GTK's own *)
  ```
- Changed: nothing's type. Four behaviours become loud.

**Ruling on (1): a container-placement attr is rejected by the *parent*, at the point the parent reads its children.** Not by `Attr_apply` (which sees a child without knowing its parent), and not by the constructor (which cannot know either). `Patcher`'s list and single child helpers already prefix the child's node path onto container rejections; add one check there, driven by a small table:

```ocaml
(* Which parent-held attrs each container reads off its children. A child carrying one the
   container does not read is a typo -- [Attr.grid_cell] on a box child, [Attr.page_title]
   on a notebook page (it is [Attr.tab_label] there) -- and there is no other diagnostic
   for it: nothing applies these to the child, so a wrong one is simply never read.

   The empty list is the common case and is deliberate: a container that reads none of
   them rejects all of them. *)
let placement_attrs_read_by : Kind.t -> Attr.Name.t list = function
  | Grid _ -> [ Grid_cell ]
  | Stack _ -> [ Page_title ]
  | Overlay _ -> [ Measure_overlay ]
  | _ -> []
;;
```
and the check runs per child at mount and at patch: if the child carries a placement name not in the parent's list, `Invalid_argument` naming the child's path, the attr, and the parent's impl name. `Measure_overlay` joins the table because it is the same family; the M1 backlog only named two.

Tasks 6–8 extend this table (`List_box -> [Row_selectable; Row_activatable]`, `Notebook -> [Tab_label]`), which is why it lands now with a comment saying so.

**Ruling on (2): a `~visible_child` that names no page is `Invalid_argument` from the fixup pass, not from `w_stack.select`.** `select` is called per frame and correctly leaves an absent name alone — the frame that adds the page runs it again. What is missing is a way to tell "not yet" from "never". The fixup already runs after the whole tree exists, so at that point *every* page this frame renders is present: a name absent then is absent in the rendered tree, which is a typo, not a race. Change `select` to raise when the name is absent, and confirm against `live_containers.ml`'s add-and-select-in-one-pass case that the fixup ordering really does make that true. **If it does not** — if there is any legitimate frame where a stack's chosen page is not yet added — stop and report: the item is then not a diagnostic but a design question, and the fallback is to leave it inert and move it to the M2 backlog with the counter-example written down.

- [ ] **Step 1: Write the failing tests**

`test/test_widgets.ml` — the constructor-level ones:

```ocaml
let%expect_test "a scrolled window with min above max is rejected at the constructor" =
  Expect_test_helpers_core.require_does_raise (fun () ->
    Node.scrolled_window ~min_content_width:400 ~max_content_width:200 (Node.label "x"));
  [%expect {| |}];
  (* -1 is "no bound" on either side and never conflicts. *)
  print_s
    [%sexp
      (Node.scrolled_window ~min_content_width:400 (Node.label "x") : Node.t)];
  [%expect {| |}]
;;

let%expect_test "entry max_length reaches the kind and defaults away" =
  print_s [%sexp (Node.entry ~text:"a" () : Node.t)];
  [%expect {| |}];
  print_s [%sexp (Node.entry ~text:"a" ~max_length:8 () : Node.t)];
  [%expect {| |}]
;;
```

`test/live/live_containers.ml` — the three runtime ones, each as a `require_raises`-style print (these are plain executables, so catch and print rather than using expect helpers):

```ocaml
let raises name f =
  match f () with
  | () -> printf "%s: NO RAISE\n" name
  | exception Invalid_argument m -> printf "%s: %s\n" name m
;;

raises "grid_cell on a box child" (fun () ->
  ignore
    (P.mount ctx ~path:"root" ~is_root:true
       (Node.window ~title:"w"
          (Node.box ~orientation:Vertical
             [ Node.label ~attrs:[ Attr.grid_cell ~column:0 ~row:0 () ] "misplaced" ]))
     : P.live));
raises "page_title outside a stack" (fun () -> ...);
raises "visible_child names no page" (fun () ->
  let live = P.mount ctx ~path:"root" ~is_root:true
    (Node.window ~title:"w"
       (Node.stack ~name:"nav" ~visible_child:"typo"
          [ Node.label ~key:"home" "home" ]))
  in
  P.run_fixups ctx;
  P.destroy ctx live);
```

Note the third one's shape: the raise comes from `run_fixups`, not from `mount`, and the test has to call it — which is exactly what `patcher.mli` already tells a hand-driven test to do.

- [ ] **Step 2: Run to verify failure** — `dune build @test/runtest` → unknown labelled argument `~max_length`; and the live test prints three `NO RAISE` lines.

- [ ] **Step 3: `Node.scrolled_window`'s bounds check**

In `vtree/node.ml`, before `make`:

```ocaml
  (* GTK calls a min above a max a programming error and checks nothing at runtime: the
     scrolled window silently sizes itself to whichever the layout reaches first, which
     looks like a layout bug a long way from its cause. [-1] is "no bound" on either side
     and never conflicts with anything. *)
  let check_bounds what ~min ~max =
    if min <> -1 && max <> -1 && min > max
    then
      invalid_argf
        "Node.scrolled_window: min_content_%s (%d) is above max_content_%s (%d)"
        what min what max ()
  in
  check_bounds "width" ~min:min_content_width ~max:max_content_width;
  check_bounds "height" ~min:min_content_height ~max:max_content_height;
```

This is the first constructor in `Node` that raises. Say so in `node.mli`'s doc for `scrolled_window` and in a note at the top of the file: constructors are otherwise total, and this one is the exception because the mistake is unrecoverable later.

- [ ] **Step 4: `entry_props.max_length`**

`vtree/defaults.ml`: `module Entry = struct … let max_length = 0 end`. **GTK's own default is `0`, meaning unlimited** — not `-1`. Check `.ocgtk-src/…/entry.mli` for `set_max_length`/`get_max_length` and confirm before writing the default; the plan asserts `0` from GTK's documented `GtkEntry:max-length`, and the defaults file's whole purpose is that this number is written once.

`Kind.entry_props` gains `max_length : int [@sexp_drop_if Int.equal Defaults.Entry.max_length]`; `Node.entry` gains `?max_length`; `w_entry.ml`'s `create` writes it when it differs from the default and `update` when it differs from `old`. It is **not** controlled: it is a constraint on the widget, not a value the user changes. `Live_tree.dump`'s `GtkEntry` arm gains `int_prop "max-length" … ~default:0`.

`Node.password_entry` and `Node.search_entry` do **not** get it: `GtkPasswordEntry` and `GtkSearchEntry` have no `max-length` property of their own (they are not `GtkEntry` subclasses in GTK4), and `GtkEditable` has no `set_max_length`. Verify in the checkout; if `Editable` does have it, add it to all three and say so in the report.

- [ ] **Step 5: The placement-attr table, in `src/patcher.ml`**

Add `placement_attrs_read_by` as above, and call the check from wherever the patcher already validates a child against its parent (the same helper that raises for a grid child with no `Attr.grid_cell`). Message shape, matching the existing ones:

```
root/0/1: Attr.grid_cell is not read by Box (a placement attribute is read by the
container, and this one holds children for Grid)
```

The parenthetical naming *which* container does read it is the useful half — a misplaced `grid_cell` is nearly always a child that ended up in the wrong parent.

- [ ] **Step 6: `w_stack.select` raises on an absent name**

```ocaml
let select (w : Widget.t) ~visible_child =
  let s : W.Stack.t = cast w in
  match W.Stack.get_child_by_name s visible_child with
  | None ->
    (* Not a race. This runs from the fixup pass, after the whole tree is built, so every
       page this frame renders is already added; a name absent here is absent from the
       rendered tree. The patcher prefixes the stack's node path. *)
    invalid_argf
      "Node.stack ~visible_child:%S names no page (pages are keyed by ~key; this stack \
       has %s)"
      visible_child
      (String.concat ~sep:", " (page_names s))
      ()
  | Some _ ->
    if not (Option.equal String.equal (W.Stack.get_visible_child_name s) (Some visible_child))
    then W.Stack.set_visible_child_name s visible_child
;;
```

`page_names` enumerates the stack's children via `Widget.get_first_child`/`get_next_sibling` and `W.Stack.get_page` → `Stack_page.get_name`. Listing them is what turns the message from an accusation into a fix.

**Before writing this, run the existing `live_containers.ml` add-and-select-in-one-pass case with the raise in place.** If it raises, the premise is wrong; stop and report per the ruling above.

- [ ] **Step 7: The same-frame name swap**

`note_interest`'s rename arm processes children left to right, so a swap hits `register_stack "b"` while the other stack still holds `"b"`. Fix by splitting the pass: first remove every registration this frame's stack nodes are giving up, then add every one they are taking. Two loops over the same child list rather than one:

```ocaml
(* Two passes, because a *swap* is legal and a one-pass walk cannot see it: renaming
   [a -> b] while [b -> a] renames in the same frame hits [register "b"] while the other
   stack still holds it. Removals first, additions second; a genuine collision then still
   raises on the addition, from the second pass, with the same message. *)
```

Add the test to `live_containers.ml` beside the existing rename cases: two keyed stacks whose `~name`s trade, asserting no raise and that a switcher naming each still resolves to the right one after `run_fixups`.

- [ ] **Step 8: Run, read, promote, gate**

```
dune build @test/runtest && dune promote
BONSAI_GTK_LIVE_TESTS=1 xvfb-run -a dune build @test/live/runtest && dune promote
./scripts/ci.sh
```

`expected_controls.txt` will diff by one line (the entry's `max-length`) only if a test sets it; if it diffs otherwise, the default is wrong.

- [ ] **Step 9: Commit**

```bash
dune fmt 2>/dev/null; git add vtree src test
GIT_EDITOR=true git commit -F - <<'MSG'
Four silently-inert mistakes become Invalid_argument, and Entry gets max_length

A placement attribute on a child whose container does not read it
(Attr.grid_cell on a box child, Attr.page_title outside a stack) is now
rejected by the container at mount and at patch, naming the container that
*does* read it. A Node.stack ~visible_child naming no page raises from the
fixup pass, which runs after the whole tree exists -- so "not yet" and "never"
are distinguishable there and nowhere earlier. Node.scrolled_window rejects a
min content bound above its max, which GTK calls a programming error and does
not check.

Two stacks swapping names in one frame no longer collide: the rename pass drops
every registration before it takes any.

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01Sg3Ci8U8kUKR8C3PL1pNSs
MSG
```

**Review focus:** that the `visible_child` raise really cannot fire on a legitimate frame — the add-and-select case is the proof and it must be in the suite, not just run once; that the placement table's `_ -> []` arm is a wildcard on purpose (it is: every container that reads none rejects all) and is commented as such; that `max_length`'s default matches GTK's, read from the binding rather than from this plan; that the two-pass rename still raises on a real collision.

---

### Task 4: The existential event spec, and click and focus controllers

The mechanism the rest of M2 is built on, plus the two controller families whose callbacks return `unit` — so the mechanism lands with consumers but without the extra complication of a return value, which Task 5 adds.

M1's `Signals.spec.fire` takes the widget and reads the value back off it with a class getter, because GTK's callbacks mostly carry no payload. Three M2 signals break that: `GtkListBox::row-activated` hands over a row that is gone by the time anything could read it back, `GtkGestureClick::pressed` carries coordinates the widget does not store, and `GtkEventControllerKey::key-pressed` carries a keyval *and wants a `bool` back*. All three need the arguments GTK passed, so `spec` grows a variant that keeps them.

**Files:**
- Modify: `src/signals.ml`, `src/signals.mli`, `src/patcher.ml`, `src/patcher.mli`, `src/gtk_import.ml`, `src/gtk_import.mli`, `src/attr_apply.ml`, `vtree/attr.ml`, `vtree/attr.mli`, `vtree/events.ml`, `vtree/bonsai_gtk_vtree.ml`, `src/bonsai_gtk.ml`, `src/bonsai_gtk.mli`, `test_lib/bonsai_gtk_test.ml`, `test_lib/bonsai_gtk_test.mli`, `test/test_attrs.ml`, `test/handle/test_handle.ml`, `test/live/dune`, `test/live/live_events.ml`
- Create: `vtree/phase.ml`, `vtree/modifiers.ml`, `vtree/modifiers.mli`, `vtree/click_event.ml`, `src/controllers.ml`, `src/controllers.mli`, `test/live/live_controllers.ml`, `test/live/expected_controllers.txt`

**Interfaces:**
- Produces:
  ```ocaml
  (* Signals *)
  type spec =
    | Read_back of read_back
    | Payload : ('p, 'r) payload -> spec

  and read_back =
    { attr : Attr.Name.t
    ; connect : Widget.t -> callback:(unit -> unit) -> connection
    ; fire : Widget.t -> Attr.t -> unit Ui_effect.t option
    }

  and ('p, 'r) payload =
    { attr : Attr.Name.t
    ; connect : Widget.t -> callback:('p -> 'r) -> connection
    ; fire : Widget.t -> Attr.t -> 'p -> 'r * unit Ui_effect.t option
    ; declined : 'r
    }

  val spec_attr : spec -> Attr.Name.t

  (* Controllers *)
  type t
  val create : Signals.ctx -> node_path:string -> Widget.t -> t
  val update : t -> Attrs.t -> unit
  val release : t -> unit

  (* vtree/phase.ml *)
  type t = Capture | Bubble | Target [@@deriving sexp_of, equal, compare]

  (* vtree/modifiers.mli *)
  type t = { shift : bool; control : bool; alt : bool; super : bool; hyper : bool; meta : bool }
  val none : t
  val equal : t -> t -> bool

  (* vtree/click_event.ml *)
  type t =
    { button : int; n_press : int; x : float; y : float; modifiers : Modifiers.t }
  [@@deriving sexp_of]

  (* Attr *)
  val on_click : ?button:int -> ?phase:Phase.t -> Click_event.t Handler.t -> t
  val on_focus_enter : unit Handler.t -> t
  val on_focus_leave : unit Handler.t -> t
  ```
- Consumes: `W.Gesture_click.{new_,on_pressed}`, `W.Gesture_single.{set_button,get_current_button}`, `W.Event_controller_focus.{new_,on_enter,on_leave}`, `W.Event_controller.{set_propagation_phase,get_current_event_state}`, `W.Widget.{add_controller,remove_controller}`, `Ocgtk_gdk.Gdk_enums.modifiertype`.

**Three shape decisions, each of which a reviewer should push on:**

1. **`declined` is a field, not a `default` computed from `'r`.** When the slot is empty, when `in_patch` is set, or when `fire` raises, the trampoline still owes GTK a return value. For a `unit` payload that is `()`; for `key-pressed` it is `false` (propagate), and getting it wrong the other way would make a widget with no handler swallow every key it sees. It is data on the spec because the *safe* answer differs per signal and nothing else knows it.

2. **`fire` returns `'r * unit Ui_effect.t option`, not `'r Ui_effect.t`.** The return value has to reach GTK *synchronously*, on the C stack, and a Bonsai effect is scheduled and performed later. So the decision ("do I consume this key") is made from the event, purely, in the trampoline; the consequence (a state update) is an effect like any other. This is exactly the shape stavekeeper's `dialog.ml:44-47` already has by hand — `if keyval = key_escape then (win#close (); true) else false` — and Task 5's `Key_response.t` is that shape given a name.

3. **Controllers are attached on demand, not per widget.** The alternative is attaching three controllers to every widget at `create` so that `Signals.connect_all` can own them uniformly. That is three GObjects per widget for a feature most widgets never use, on a library whose whole selling point over immediate-mode GTK is that a frame is cheap. `Controllers` instead creates a controller the first time its attr appears and removes it when the last of its attrs goes away — and then hands the connecting to `Signals.connect_all` anyway, so the trampoline, the slots, the `in_patch` guard, the exception guard and the disconnect-from-the-right-object rule are all the existing code.

- [ ] **Step 1: Write the failing tests**

`test/test_attrs.ml` — the attrs are values before they are behaviour:

```ocaml
let%expect_test "controller attrs round-trip and diff" =
  let click = Attr.on_click ~button:2 (fun _ -> Ui_effect.Ignore) in
  let attrs = Attrs.of_list [ click; Attr.on_focus_enter (fun () -> Ui_effect.Ignore) ] in
  print_s [%sexp (attrs : Attrs.t)];
  [%expect {| |}];
  (* A handler that changed is a Set; a handler that is physically the same is not.
     Handlers compare physically (spec §5.2), so a view that rebuilds its closures every
     frame writes the slot every frame -- which is a slot write, not a GTK call. *)
  print_s [%sexp (Attrs.diff ~old:attrs ~new_:(Attrs.of_list [ click ]) : Attrs.op list)];
  [%expect {| |}]
;;
```

`test/live/live_controllers.ml` — the real thing. This file grows in Task 5; start it with click and focus:

```ocaml
open! Core
open Bonsai_gtk_vtree
module Gobject = Bonsai_gtk.Private.Gtk_import.Gobject
module Live_tree = Bonsai_gtk.Private.Live_tree
module P = Bonsai_gtk.Private.Patcher
module Scheduler = Bonsai_gtk.Private.Scheduler
module W = Bonsai_gtk.Private.Gtk_import.W

let () =
  ignore (Ocgtk_gtk.GMain.init () : string array);
  let events = ref [] in
  let record s = events := s :: !events in
  let scheduler = Scheduler.create ~run_frame:(fun () -> ()) in
  let ctx =
    P.create_ctx
      ~signals:
        { schedule = (fun e -> Ui_effect.Expert.eval e ~f:Fn.id)
        ; in_patch = (fun () -> Scheduler.in_patch scheduler)
        ; on_exn = (fun ~node_path exn -> printf "EXN at %s: %s\n" node_path (Exn.to_string exn))
        }
      ~on_window_created:(fun _ -> ())
  in
  (* A button with a click gesture and a focus controller. The gesture is on the button,
     not on the window, so the dump shows where the controller went -- [Live_tree] cannot
     see controllers, so what this test asserts is *behaviour*, by emitting. *)
  let view ~with_click =
    Node.window
      ~title:"controllers"
      (Node.button
         ~attrs:
           (List.filter_opt
              [ Some (Attr.on_focus_enter (fun () -> record "focus-enter"; Ui_effect.Ignore))
              ; Some (Attr.on_focus_leave (fun () -> record "focus-leave"; Ui_effect.Ignore))
              ; (if with_click
                 then
                   Some
                     (Attr.on_click (fun (e : Click_event.t) ->
                        record (sprintf "click b%d n%d ctrl=%b" e.button e.n_press e.modifiers.control);
                        Ui_effect.Ignore))
                 else None)
              ])
         ~label:"target"
         ())
  in
  let live = P.mount ctx ~path:"root" ~is_root:true (view ~with_click:true) in
  P.run_fixups ctx;
  print_s (Live_tree.dump live.widget);
  ...
```

Emitting a real click is the hard part and the plan must say how, because "call `emit_by_name`" does not work: `Gobject.Signal.emit_by_name` takes no arguments and returns unit, so it cannot deliver `~n_press ~x ~y`. Three options, in preference order:

- **(a) Drive it through `Widget.activate`** for the *focus* controller (`grab_focus` really does emit `enter`), and for the click gesture accept that a synthetic press needs an event. Test what can be tested honestly.
- **(b) `Gtk.Test`** — check `.ocgtk-src` for a `gtk_test_widget_click` binding. If it exists, use it; if not, say so.
- **(c) Assert the *plumbing* rather than the emission**: that attaching the attr adds a controller (count `Widget`'s controllers — check whether `Widget.observe_controllers` or a list accessor is bound; if not, this is unobservable), that removing the attr removes it, and that the widget survives both.

**Run the pre-flight-style check first**: `grep -rn 'controller' .ocgtk-src/ocgtk/src/gtk/generated/event_controller_and__*.mli | grep -i 'list\|observe\|n_controllers'` and `ls .ocgtk-src/ocgtk/src/gtk/generated/ | grep -i test`. Then pick, and **write down in the task report which of the three you got**. If only (c) is available, the honest live test asserts attach/detach and lifetime, and the *handler* behaviour is proved headlessly by Task 4's `Bonsai_gtk_test` action instead — which is a real test of the handler and a real gap on the GTK half, and the gap goes in the backlog. Do not fake a click by calling the handler directly and then claim the controller works.

What is certainly testable, and must be:

```ocaml
  (* Dropping the attr must remove the controller and disconnect its handler. Nothing
     observes a removed controller directly, so this asserts the consequence that matters:
     the widget is still alive, still patchable, and a later frame can add the attr back
     and get a working controller again. A leaked controller would keep a slot -- and the
     closure it captured -- alive as a GC root for the widget's lifetime. *)
  let live = Scheduler.with_patch_guard scheduler (fun () ->
    P.patch ctx ~path:"root" ~is_root:true live (view ~with_click:false))
  in
  let live = Scheduler.with_patch_guard scheduler (fun () ->
    P.patch ctx ~path:"root" ~is_root:true live (view ~with_click:true))
  in
  print_s (Live_tree.dump live.widget);
  P.destroy ctx live;
  printf "destroyed cleanly\n"
```

`test/handle/test_handle.ml` — the headless half, which is where an application's key and click logic is actually tested:

```ocaml
let%expect_test "a click action carries the button and the modifiers" =
  let app (graph @ local) =
    let log, set_log = Bonsai.state [] graph in
    let%arr log and set_log in
    Node.window ~title:"clicks"
      (Node.box ~orientation:Vertical
         [ Node.label ~attrs:[ Attr.test_id "card"
                             ; Attr.on_click (fun (e : Click_event.t) ->
                                 set_log (sprintf "b%d shift=%b" e.button e.modifiers.shift :: log))
                             ] "card"
         ; Node.label ~attrs:[ Attr.test_id "log" ] (String.concat ~sep:"," log)
         ])
  in
  let handle = Bonsai_gtk_test.create app in
  Bonsai_gtk_test.Handle.show handle;
  [%expect {| |}];
  Bonsai_gtk_test.Handle.do_actions handle
    [ Click_at ("card", { button = 2; n_press = 1; x = 0.; y = 0.; modifiers = Modifiers.none }) ];
  Bonsai_gtk_test.Handle.show_diff handle;
  [%expect {| |}]
;;
```

This is stavekeeper's `library_window.ml:166-185` in miniature — middle click, or button 1 with shift, pops the piece out — and it is the whole reason the payload carries `button` and `modifiers`.

- [ ] **Step 2: Run to verify failure** — unbound `Attr.on_click`, unbound `Click_event`.

- [ ] **Step 3: `vtree/phase.ml`, `modifiers.ml(i)`, `click_event.ml`**

```ocaml
(* vtree/phase.ml *)
open! Core

(** Where in GTK's event routing a controller runs.

    [Capture] runs top-down, from the toplevel toward the target, and is what a window-wide
    Escape handler wants: it sees the key before anything a child added later can swallow
    it (stavekeeper's [dialog.ml] says exactly this, in a comment, having learned it the
    hard way). [Bubble] — GTK's default — runs bottom-up from the target, so the innermost
    widget gets first refusal, which is what a per-widget shortcut wants. [Target] runs
    only when the widget *is* the event's target.

    GTK's [`NONE] is deliberately absent: a controller in that phase never fires, which is
    what omitting the attribute already says, more clearly. *)
type t =
  | Capture
  | Bubble
  | Target
[@@deriving sexp_of, equal, compare]
```

```ocaml
(* vtree/modifiers.mli *)
open! Core

(** Which modifier keys were down.

    A record of bools rather than a set or a mask, because [vtree] cannot name GDK's
    [modifiertype] (which is a list of polymorphic variants) and because the question an
    application asks is always "was control down", never "give me the mask". The runtime
    converts at the boundary.

    Lock (caps lock) and the five button masks GDK also reports are deliberately absent:
    they are pointer and keyboard *state*, not modifiers a shortcut is keyed on, and
    including them would put a bit in every comparison that nothing wants to compare. If
    one is ever needed it goes here with a note, not into an escape hatch. *)
type t =
  { shift : bool
  ; control : bool
  ; alt : bool
  ; super : bool
  ; hyper : bool
  ; meta : bool
  }
[@@deriving sexp_of, equal, compare]

(** No modifier down. What a synthetic event in a headless test usually wants. *)
val none : t
```

`click_event.ml` is the record above with `[@@deriving sexp_of, equal]`. `x` and `y` are in the widget's own coordinates, and the doc says so — a gesture attached to a card reports coordinates within that card, which is what makes a per-card gesture useful (stavekeeper's `library_window.ml:155-159` comment explains why it attaches per card rather than to the FlowBox).

- [ ] **Step 4: `vtree/attr.ml(i)` — three attrs, and where their names go in the order**

`Attr.Name.t` gains, adjacent to each other and *after* the existing `On_*` names (so no existing `Attrs.diff` output reorders):

```ocaml
  | On_click
  | On_focus_enter
  | On_focus_leave
  (* Task 5 adds On_key_pressed, On_key_released here *)
```

and `Attr.t`:

```ocaml
  | On_click of
      { button : int
      ; phase : Phase.t
      ; handler : Click_event.t Handler.t
      }
  | On_focus_enter of unit Handler.t
  | On_focus_leave of unit Handler.t
```

`On_click` carries its `button` and `phase` in the constructor because they are properties of the *controller*, not of the handler, and `Controllers.update` needs to see a change in either without the handler having to change. `equal` compares `button`, `phase` and the handler physically.

Constructors:
```ocaml
val on_click : ?button:int -> ?phase:Phase.t -> Click_event.t Handler.t -> t
(** A [GtkGestureClick] on this widget.

    [button] is which mouse button to listen for; [0] (the default) means all of them, and
    the one that was pressed arrives in {!Click_event.button}. [phase] defaults to
    {!Phase.Bubble}, GTK's own — a gesture on a card in a selection container wants bubble,
    so that the container's own selection gesture still runs.

    The gesture does {i not} claim the event sequence, so a click also reaches whatever
    else would have handled it. That is deliberate and is what lets a card carry a
    middle-click handler without breaking its list box's click-to-select; an application
    that wants to consume the click has no way to say so in M2, which is named in the
    README's Limitations. *)

val on_focus_enter : unit Handler.t -> t
val on_focus_leave : unit Handler.t -> t
(** A [GtkEventControllerFocus] on this widget. [on_focus_enter] fires when focus moves
    into the widget {i or any of its children} — which is the useful sense for a composite
    widget like a [GtkSearchEntry], whose own [has_focus] is always false because its
    inner [GtkText] holds the focus.

    Both are attached to one controller, so a widget carrying either pays for one. *)
```

`Events`: add the arm from Task 1's Step 5 —

```ocaml
(* The controller attrs are legal on every kind: they are not any impl's signal, they are
   a [GtkEventController] the runtime attaches to whatever widget carries the attr. So
   [is_supported] short-circuits on them rather than consulting [for_kind], and no impl
   may declare one in its [Widget_impl.signals] -- [test/live/live_events.ml] asserts
   that, because an impl that did would connect a second handler nobody removes. *)
let is_controller_attr : Attr.Name.t -> bool = function
  | On_click | On_focus_enter | On_focus_leave -> true
  | _ -> false
;;
```

- [ ] **Step 5: `src/signals.ml(i)` — the variant**

The `Read_back` arm's trampoline is M1's, unchanged. The `Payload` arm's:

```ocaml
let dispatch_payload ctx ~node_path ~declined ~fire w slot p =
  (* Same five obligations as the read-back trampoline (spec §6.4), plus a sixth: whatever
     happens, GTK gets a value back. An exception here must not cross into C, and the
     value it returns instead has to be the *safe* one -- for a key controller that is
     "propagate", because a handler that raised has certainly not handled the key. *)
  match
    if ctx.in_patch ()
    then declined
    else (
      match !slot with
      | None -> declined
      | Some attr ->
        let r, effect = fire w attr p in
        Option.iter effect ~f:ctx.schedule;
        r)
  with
  | r -> r
  | exception exn ->
    ctx.on_exn ~node_path exn;
    declined
;;
```

`connect_all` matches on the variant and builds the right callback; `update_slots` and `clear_slots` are unchanged (a slot is a slot). `spec_attr` becomes `function Read_back r -> r.attr | Payload p -> p.attr`.

The mli's `spec` doc gains:

```ocaml
(** [Read_back] is the ordinary shape: GTK's callback carries nothing and the value the
    user just changed lives on the widget, so [fire] reads it back with the class getter.
    Every M1 signal is one of these, and so is every [notify::] one, whose generic
    marshaller carries nothing at all.

    [Payload] is for the signals whose arguments cannot be recovered afterwards. Three
    exist in M2: [GtkListBox::row-activated] (the row is gone by the time anything could
    look for it), [GtkGestureClick::pressed] (the coordinates are not stored anywhere), and
    [GtkEventControllerKey::key-pressed] (the keyval, and a [bool] GTK wants back). ['p] is
    the payload the [connect] closure assembles — it may combine the callback's arguments
    with things read off the object, which is how a click's [button] and [modifiers] get
    in — and ['r] is what the callback returns to GTK.

    [declined] is that return value for the emissions that reach no handler: an empty
    slot, an emission during a patch, or a [fire] that raised. It must be the *inert*
    answer for the signal — [false] ("not handled") for a key controller — because those
    three cases are precisely the ones where the application has said nothing. *)
```

- [ ] **Step 6: `src/gtk_import.ml(i)` — the GDK aliases**

```ocaml
module Gdk_enums = Ocgtk_gdk.Gdk_enums
module Gdk_constants = Ocgtk_gdk.Gdk_constants
```

with a comment: the class modules come from `Ocgtk_gdk.Gdk.Wrappers` but the enums and constants are top-level in `Ocgtk_gdk`, which is not the shape `Gtk` has, and forgetting that costs ten minutes each time.

- [ ] **Step 7: `src/controllers.ml(i)`**

```ocaml
(** The [GtkEventController]s attached to one widget on account of its attributes.

    Unlike a widget's own signals — connected once at [create] for every spec its impl
    declares — a controller exists only while an attribute asks for one. Three reasons it
    is not simply "attach all of them to every widget": three GObjects per widget is a real
    cost on a library whose claim is that a frame is cheap; a controller's propagation
    phase is part of the attribute, so there is no phase to pick before the attribute
    exists; and a widget with no key handler should not appear in GTK's capture chain at
    all.

    What it is {i not} is a second signal mechanism. The connecting, the slots, the
    [in_patch] guard, the exception guard and the disconnect-from-the-object-that-issued-
    the-id rule are all [Signals]; this module decides only which controllers should exist
    and owns their attach/detach. *)
type t

(** Attaches nothing. Call once per widget, at mount, right after [Signals.connect_all];
    the first {!update} creates whatever the attrs ask for. *)
val create : Signals.ctx -> node_path:string -> Widget.t -> t

(** Brings the attached controllers into line with [attrs]: creates one whose attrs have
    appeared, removes one whose attrs have all gone, re-points the handler slots, and
    re-applies the propagation phase and the gesture's button.

    A phase or button change re-applies the setter rather than rebuilding the controller —
    both are plain properties and GTK re-reads them per event. Cheap enough to do
    unconditionally, which is what this does: comparing first would mean storing the old
    attr, and the setter on an unchanged value is free.

    Called at mount after {!create}, and on every patch whose attrs differ. *)
val update : t -> Attrs.t -> unit

(** Empties every slot, disconnects, and removes every controller from the widget.

    The slot-emptying is first and is the load-bearing half: [gtk_widget_remove_controller]
    can itself provoke a leave or a cancel, and a slot still armed then would reach Bonsai
    from inside teardown. Same rule, same reason, as [Signals.clear_slots]. *)
val release : t -> unit
```

Implementation shape:

```ocaml
type attached =
  { controller : W.Event_controller.t
  ; slots : Signals.slots
  ; connections : Signals.connection list
  }

type t =
  { ctx : Signals.ctx
  ; node_path : string
  ; widget : Widget.t
  ; mutable click : attached option
  ; mutable focus : attached option
  (* Task 5 adds [mutable key : attached option] *)
  }
```

and one helper per family:

```ocaml
(* [wanted] is whether any of this family's attrs is present. Attach on the first, detach
   on the last, and in between only re-slot. *)
let sync t ~wanted ~get ~set ~make ~specs attrs =
  match get t, wanted with
  | None, false -> ()
  | Some a, false ->
    Signals.clear_slots a.slots;
    Signals.disconnect a.connections;
    W.Widget.remove_controller t.widget a.controller;
    set t None
  | Some a, true -> Signals.update_slots a.slots attrs
  | None, true ->
    let controller = make () in
    W.Widget.add_controller t.widget controller;
    let slots, connections =
      Signals.connect_all t.ctx ~node_path:t.node_path t.widget (specs controller)
    in
    Signals.update_slots slots attrs;
    set t (Some { controller; slots; connections })
;;
```

Note what `specs controller` does: it builds `Signals.spec`s whose `connect` **ignores the widget it is handed** and connects to the captured controller instead, returning `Signals.connected controller id`. That is exactly what `Signals.connection` was widened for in M1's fix wave, and it is why `Controllers` needs no new disconnect machinery.

The click spec:

```ocaml
let click_spec (gc : W.Gesture_click.t) : Signals.spec =
  Payload
    { attr = Attr.Name.On_click
    ; connect =
        (fun _w ~callback ->
          Signals.connected
            gc
            (W.Gesture_click.on_pressed gc ~callback:(fun ~n_press ~x ~y ->
               (* The button and the modifier state are not callback arguments: they are
                  read off the gesture and its controller while the event is still
                  current. This is the whole reason [Payload]'s [connect] assembles the
                  payload rather than [fire] doing it -- after the callback returns, both
                  are gone. *)
               let button = W.Gesture_single.get_current_button (gc :> W.Gesture_single.t) in
               let modifiers =
                 Modifiers.of_gdk
                   (W.Event_controller.get_current_event_state (gc :> W.Event_controller.t))
               in
               callback ({ button; n_press; x; y; modifiers } : Click_event.t))))
    ; fire =
        (fun _w attr (e : Click_event.t) ->
          match (attr : Attr.Private.t) with
          | On_click { handler; _ } -> (), Some (handler e)
          | _ -> (), None)
    ; declined = ()
    }
;;
```

`Modifiers.of_gdk` lives in `src/` (it names `Gdk_enums.modifiertype`), not in `vtree`. Put it in `src/controllers.ml` or, better, in `src/gtk_import.ml` beside the other conversions, so Task 5 can use it too.

Wire `Controllers` into `Patcher.live` as a field, created in `mount` after `Signals.connect_all`, `update`d in `patch` on the same condition that re-runs `Signals.update_slots`, and `release`d in `destroy` alongside `clear_slots`/`disconnect`. **Check the ordering in `destroy` carefully**: `patcher.mli` promises that on the paths where a subtree is unparented before being destroyed, the slots of the whole subtree are emptied *before* the unparenting. Controllers must obey the same promise, so whatever helper does the pre-emptying (`disarm`) gains a `Controllers.clear` — a slot-emptying without the detaching, since the detaching happens in `destroy`. If `release` is the only entry point, split it.

- [ ] **Step 8: `test_lib` — the `Click_at` and focus actions**

```ocaml
| Click_at of string * Click_event.t
(** test_id of a node carrying [Attr.on_click], and the click to deliver. Fires that
    handler with exactly that event; nothing is derived from the node, and in particular
    the [button] the attr was constructed with is {i not} consulted — a headless test that
    delivers button 3 to a [~button:1] gesture is testing its own handler, not GTK's
    filtering, and pretending otherwise would make the action's behaviour depend on a
    detail no headless model has. Build the event with {!Bonsai_gtk_vtree.Click_event}'s
    record and {!Modifiers.none}. *)

| Focus_enter of string
| Focus_leave of string
(** test_id of a node carrying the matching attr. *)
```

- [ ] **Step 9: Run, read, promote, gate**

`live_events.ml` gains the assertion that no impl declares a controller attr. Every other expected file unchanged.

- [ ] **Step 10: Commit**

```bash
dune fmt 2>/dev/null; git add vtree src test test_lib
GIT_EDITOR=true git commit -F - <<'MSG'
Signals carry their own arguments, and widgets carry event controllers

[Signals.spec] becomes a variant. [Read_back] is M1's shape -- GTK's callback
carries nothing and [fire] reads the value off the widget -- and the new
existential [Payload] keeps the arguments GTK passed and hands a value back to
GTK. Three M2 signals need it: a list box's activated row, a click's
coordinates, and (next task) a key press, which also wants a bool returned
synchronously while its effect is scheduled as usual.

[Controllers] attaches a GtkGestureClick or a GtkEventControllerFocus to a
widget when [Attr.on_click] / [Attr.on_focus_enter] / [on_focus_leave] appears
and removes it when the last of them goes, reusing [Signals]' trampolines,
slots, guards and disconnect rules underneath rather than growing a second
mechanism.

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01Sg3Ci8U8kUKR8C3PL1pNSs
MSG
```

**Review focus:** that a removed controller's slot is emptied *before* `remove_controller`, and that `destroy`'s pre-unparent emptying covers controllers too; that `Payload`'s trampoline returns `declined` on all three of the paths it is supposed to (empty slot, in_patch, exception) — the reviewer should be able to point at each; that `connect` assembling the payload (rather than `fire`) is what makes `button` and `modifiers` readable at all, and that the comment says so; that no controller attr appears in any impl's `signals`; that the live test's method of provoking a click is honestly described, and that if it is option (c) the gap is in the backlog rather than papered over.

---

### Task 5: Key controllers — the `bool` return, phases, and a keyval table `vtree` can name

The second controller family, and the one that forced `Payload`'s `'r`. Stavekeeper cannot port a single dialog without it (`dialog.ml:37-51`), and the shell's Ctrl+W / Ctrl+Return routing (`shell.ml:264-296`) is the same shape.

**Files:**
- Modify: `vtree/attr.ml`, `vtree/attr.mli`, `vtree/events.ml`, `vtree/bonsai_gtk_vtree.ml`, `src/controllers.ml`, `src/gtk_import.ml`, `src/bonsai_gtk.ml(i)`, `test_lib/bonsai_gtk_test.ml(i)`, `test/test_attrs.ml`, `test/handle/test_handle.ml`, `test/live/live_controllers.ml`, `test/live/dune`
- Create: `vtree/keyval.ml`, `vtree/keyval.mli`, `vtree/key_event.ml`, `vtree/key_response.ml`, `test/live/live_keyvals.ml`, `test/live/expected_keyvals.txt`

**Interfaces:**
- Produces:
  ```ocaml
  (* vtree/key_response.ml *)
  type t =
    | Propagate
    | Handled
    | Propagate_and of unit Ui_effect.t
    | Handled_and of unit Ui_effect.t

  (* vtree/key_event.ml *)
  type t = { keyval : int; keycode : int; modifiers : Modifiers.t } [@@deriving sexp_of]

  (* vtree/keyval.mli — X11 keysyms, as ints *)
  val escape : int
  val return : int
  val kp_enter : int
  val tab : int
  val iso_left_tab : int
  val space : int
  val backspace : int
  val delete : int
  val up : int
  val down : int
  val left : int
  val right : int
  val home : int
  val end_ : int
  val page_up : int
  val page_down : int
  val slash : int
  val f : int -> int          (* f 1 .. f 12 *)
  val of_char : char -> int

  (* Attr *)
  val on_key_pressed : ?phase:Phase.t -> (Key_event.t -> Key_response.t) -> t
  val on_key_released : ?phase:Phase.t -> Key_event.t Handler.t -> t
  ```
- Consumes: `W.Event_controller_key.{new_,on_key_pressed,on_key_released}`, `W.Event_controller.set_propagation_phase`, `Gdk_constants.{key_*,event_stop,event_propagate}`.

**Why `on_key_pressed`'s handler is not a `Handler.t`.** Every other event attr's handler is `'a -> unit Ui_effect.t`, because every other event is something that already happened. A key press is a *question* — GTK asks "did anything handle this?" and routes accordingly, on the C stack, before the frame that would answer it. So the handler is `Key_event.t -> Key_response.t`: the decision is a pure function of the event, and the effect (if any) rides along. This is what stavekeeper writes by hand today and it is the only shape that can be both synchronous and declarative.

Four constructors rather than two, because all four combinations are wanted and each reads plainly at the call site:

| | schedules nothing | schedules an effect |
|---|---|---|
| **GTK keeps routing** | `Propagate` | `Propagate_and eff` |
| **GTK stops** | `Handled` | `Handled_and eff` |

`Propagate_and` is the one a reader will ask about: it is for observing a key without consuming it — a "last activity" timestamp, a type-to-search that forwards to a search entry, `viewer_window.ml`'s auto-repeat suppression on key *release*. Without it, an observer would have to lie about handling the key.

**`vtree/keyval.ml` hard-codes X11 keysyms, and a live test pins them.** `vtree` may not link ocgtk, so it cannot read `Gdk_constants`; and an application that keeps its view functions ocgtk-free (which is the whole point of the vtree/runtime split, and what stavekeeper already does) needs to name Escape. The values are X11 keysyms, unchanged since 1987, and stavekeeper already hard-codes `0xff1b` for Escape in `dialog.ml:4`. What makes this safe rather than merely likely-safe is `test/live/live_keyvals.ml`, which asserts every entry against `Ocgtk_gdk.Gdk_constants.key_*`. Write that test **first**; if a single value disagrees, the whole approach is suspect and the fallback (expose the raw int and make applications depend on `bonsai_gtk` for the constants, losing the ocgtk-free view library) needs the controller's ruling.

- [ ] **Step 1: Write the failing tests**

`test/live/live_keyvals.ml`:

```ocaml
open! Core
open Bonsai_gtk_vtree
module K = Ocgtk_gdk.Gdk_constants

(* [vtree/keyval.ml] hard-codes X11 keysyms because [vtree] cannot link ocgtk. This is
   what makes that safe: every constant, checked against the binding. A mismatch here is
   not a test failure to promote past -- it means an application matching on
   [Keyval.escape] would silently never match. *)
let check name ours theirs =
  if ours <> theirs then printf "MISMATCH %s: vtree=%#x gdk=%#x\n" name ours theirs
;;

let () =
  check "escape" Keyval.escape K.key_escape;
  check "return" Keyval.return K.key_return;
  check "kp_enter" Keyval.kp_enter K.key_kp_enter;
  check "tab" Keyval.tab K.key_tab;
  check "iso_left_tab" Keyval.iso_left_tab K.key_iso_left_tab;
  check "space" Keyval.space K.key_space;
  check "backspace" Keyval.backspace K.key_backspace;
  check "delete" Keyval.delete K.key_delete;
  check "up" Keyval.up K.key_up;
  check "down" Keyval.down K.key_down;
  check "left" Keyval.left K.key_left;
  check "right" Keyval.right K.key_right;
  check "home" Keyval.home K.key_home;
  check "end" Keyval.end_ K.key_end;
  check "page_up" Keyval.page_up K.key_page_up;
  check "page_down" Keyval.page_down K.key_page_down;
  check "slash" Keyval.slash K.key_slash;
  check "f1" (Keyval.f 1) K.key_f1;
  check "f12" (Keyval.f 12) K.key_f12;
  (* [of_char] is the claim that an ASCII printable's keysym is its codepoint, which is
     what makes [Keyval.of_char 'w'] a legitimate way to spell Ctrl+W. Check both ends of
     the range and a couple in the middle rather than asserting it in a comment. *)
  check "of_char a" (Keyval.of_char 'a') K.key_a;
  check "of_char z" (Keyval.of_char 'z') K.key_z;
  check "of_char A" (Keyval.of_char 'A') K.key_A;
  check "of_char 0" (Keyval.of_char '0') K.key_0;
  check "of_char w" (Keyval.of_char 'w') K.key_w;
  printf "keyvals agree\n"
;;
```

The expected file is one line. Check the exact spellings of `K.key_A` and `K.key_0` in `gdk_constants.mli` first — the generator may lowercase or prefix differently for capitals and digits; if `key_A` does not exist, drop that line and say so in `of_char`'s doc.

`test/handle/test_handle.ml` — the shape stavekeeper's dialog has:

```ocaml
let%expect_test "Escape is handled, other keys propagate" =
  let app (graph @ local) =
    let open_, set_open = Bonsai.state true graph in
    let%arr open_ and set_open in
    Node.window ~title:"dialog"
      (Node.box ~orientation:Vertical
         ~attrs:
           [ Attr.test_id "sheet"
           ; Attr.on_key_pressed ~phase:Capture (fun (e : Key_event.t) ->
               if e.keyval = Keyval.escape
               then Key_response.Handled_and (set_open false)
               else Propagate)
           ]
         [ Node.label ~attrs:[ Attr.test_id "state" ] (if open_ then "open" else "closed") ])
  in
  let handle = Bonsai_gtk_test.create app in
  Bonsai_gtk_test.Handle.show handle;
  [%expect {| |}];
  (* The action prints what the handler answered, which is the half a headless test can
     see and the half an application's logic actually lives in. *)
  Bonsai_gtk_test.Handle.do_actions handle
    [ Key_press ("sheet", { keyval = Keyval.of_char 'x'; keycode = 0; modifiers = Modifiers.none }) ];
  Bonsai_gtk_test.Handle.show_diff handle;
  [%expect {| |}];
  Bonsai_gtk_test.Handle.do_actions handle
    [ Key_press ("sheet", { keyval = Keyval.escape; keycode = 0; modifiers = Modifiers.none }) ];
  Bonsai_gtk_test.Handle.show_diff handle;
  [%expect {| |}]
;;
```

`test/live/live_controllers.ml` — append the live half. Unlike a click, a key press **is** deliverable: `W.Event_controller_key.forward : t -> Widget.t -> bool` exists, and so does the ordinary route of `Gobject.Signal.emit_by_name` (which cannot carry the arguments, so it is useless here). Check whether a `GdkEvent` can be synthesised from the binding; if not, the honest live assertions are the same three as the click gesture's — attach, detach, survive — plus one that *is* directly observable and worth having:

```ocaml
  (* The phase really is written onto the controller. Nothing else in this file can see a
     controller's properties, but the propagation phase is readable, and a wrong phase is
     the failure mode stavekeeper's dialog.ml comment is entirely about: in BUBBLE a key
     controller a caller adds later runs first and swallows Escape. *)
  printf "phase: %s\n" (phase_of_only_key_controller live);
```

which needs a way to reach the controller — `Controllers` is `Private`, so expose `Bonsai_gtk.Private.Controllers` and a `Controllers.Private.key_controller : t -> W.Event_controller.t option` for the test. A test-only accessor is better than an untested phase.

- [ ] **Step 2: Run to verify failure.**

- [ ] **Step 3: `vtree/keyval.ml(i)`, `key_event.ml`, `key_response.ml`**

`keyval.mli`'s header carries the reasoning:

```ocaml
(** X11 keysyms, as the plain [int]s GTK delivers.

    Hard-coded rather than re-exported from GDK because this library's whole vtree/runtime
    split exists so that an application's view functions can be written against
    [bonsai_gtk.vtree] alone, with no ocgtk dependency and therefore headless-testable —
    and a view that handles Escape has to be able to name Escape. The values are X11
    keysyms and have not changed since 1987; [test/live/live_keyvals.ml] checks every one
    of them against [Ocgtk_gdk.Gdk_constants] on every CI run, which is what turns "has not
    changed" into "is checked".

    Only the keys an application actually branches on are here. A keyval this module does
    not name is still an ordinary [int] and can be compared to one — {!of_char} covers the
    printable ASCII range, and the rest are in GDK's headers. *)

val of_char : char -> int
(** The keysym of a printable ASCII character, which for [0x20]–[0x7e] is its own code
    point — so [of_char 'w'] is Ctrl+W's keyval and [of_char '/'] is the "start a search"
    key. Raises [Invalid_argument] outside that range: a keysym for [\n] or [\255] is not
    the codepoint and quietly returning one would be a wrong answer rather than an
    error. *)
```

`key_response.ml` is the four-constructor variant with the table above as its doc, plus:

```ocaml
(** [sexp_of_t] prints the effect as [<effect>], like every other handler in this
    library: an effect is not inspectable and a test comparing two of them is comparing
    closures. *)
```

- [ ] **Step 4: `vtree/attr.ml(i)`**

```ocaml
  | On_key_pressed of
      { phase : Phase.t
      ; handler : Key_event.t -> Key_response.t
      }
  | On_key_released of
      { phase : Phase.t
      ; handler : Key_event.t Handler.t
      }
```

with, on `on_key_pressed`:

```ocaml
val on_key_pressed : ?phase:Phase.t -> (Key_event.t -> Key_response.t) -> t
(** A [GtkEventControllerKey] on this widget.

    The handler is not a {!Handler.t}: it returns a {!Key_response.t} rather than an
    effect, because GTK asks a key press a {i question} — "did anything handle this?" — and
    routes the event on the answer, synchronously, on its own stack, long before the frame
    that an effect would run in. So the decision is a pure function of the event and the
    consequence rides along: [Handled_and eff] stops the routing {i and} schedules [eff].

    [phase] defaults to {!Phase.Bubble}, GTK's own. Use {!Phase.Capture} for a
    window-or-dialog-wide key: in bubble phase GTK runs the {i last} controller added
    first, so any controller a child adds afterwards sees the key first and can swallow
    it, and "afterwards" is not something a declarative tree controls. A [GtkPopover] has
    its own surface and so is not below the window in the capture chain — an open popover
    still takes its own Escape.

    Both this and {!on_key_released} share one controller, so a widget carrying both pays
    for one; giving them different phases is [Invalid_argument] at mount, because there is
    only one phase to write.

    The keyval is a plain [int]; {!Bonsai_gtk_vtree.Keyval} names the ones worth naming. *)
```

`on_key_released`'s handler *is* an ordinary `Handler.t`: GTK's `key-released` callback returns `unit`, so there is no question to answer.

- [ ] **Step 5: `src/controllers.ml` — the key family**

One `GtkEventControllerKey` serves both attrs. `wanted` is "either attr present". The phase comes from whichever attr carries it, and **differing phases raise**:

```ocaml
(* One controller, one phase. Two attrs asking for different ones is a mistake with no
   good resolution -- picking either silently gives one of them behaviour its author did
   not ask for -- so it is [Invalid_argument] with the node path, like every other
   structural rejection (spec §11). *)
let key_phase attrs =
  match Attrs.find attrs On_key_pressed, Attrs.find attrs On_key_released with
  | Some (On_key_pressed p), Some (On_key_released r) when not (Phase.equal p.phase r.phase) ->
    invalid_argf
      "on_key_pressed is %s and on_key_released is %s, but they share one \
       GtkEventControllerKey and so one phase"
      (Phase.to_string p.phase) (Phase.to_string r.phase) ()
  | Some (On_key_pressed p), _ -> Some p.phase
  | _, Some (On_key_released r) -> Some r.phase
  | _ -> None
;;
```

The pressed spec is the `Payload` with `'r = bool`:

```ocaml
let key_pressed_spec (kc : W.Event_controller_key.t) : Signals.spec =
  Payload
    { attr = Attr.Name.On_key_pressed
    ; connect =
        (fun _w ~callback ->
          Signals.connected
            kc
            (W.Event_controller_key.on_key_pressed kc ~callback:(fun ~keyval ~keycode ~state ->
               callback ({ keyval; keycode; modifiers = Gtk_import.modifiers state } : Key_event.t))))
    ; fire =
        (fun _w attr e ->
          match (attr : Attr.Private.t) with
          | On_key_pressed { handler; _ } ->
            (match handler e with
             | Propagate -> false, None
             | Handled -> true, None
             | Propagate_and eff -> false, Some eff
             | Handled_and eff -> true, Some eff)
          | _ -> false, None)
    ; declined = false
      (* [Gdk_constants.event_propagate]. A widget whose slot is empty, or whose handler
         raised, has certainly not handled the key; returning [true] there would make a
         window with a broken handler swallow every keystroke in the application. *)
    }
;;
```

Use the literal `false` with that comment rather than `Gdk_constants.event_propagate`, or use the constant and drop the comment's first sentence — either, but say which and be consistent with `key_released_spec`.

- [ ] **Step 6: `test_lib` — the `Key_press` action, and what it can honestly claim**

```ocaml
| Key_press of string * Key_event.t
(** test_id of a node carrying [Attr.on_key_pressed], and the key to deliver. Fires that
    handler with exactly that event and performs the effect of whatever
    {!Bonsai_gtk_vtree.Key_response.t} it returns.

    What this {i cannot} model is propagation. A real key press walks GTK's capture and
    bubble chains and stops where a handler says [Handled]; here it is delivered to one
    node, by [test_id], and the [Handled]/[Propagate] half of the answer is not acted on —
    there is no chain to act on it in. So a test can show that a handler decided to
    consume Escape and what that decision did to the model; it cannot show that the
    keystroke then failed to reach a sibling. That half is a live test, or the
    application. *)

| Key_release of string * Key_event.t
```

Say the same thing, shorter, in the mli's opening paragraph about what the handle validates — this is the second known gap after the structural one, and both belong in the same place.

- [ ] **Step 7: `Events`** — add `On_key_pressed`/`On_key_released` to `is_controller_attr`.

- [ ] **Step 8: Run, read, promote, gate.** `expected_keyvals.txt` is `keyvals agree`. Any `MISMATCH` line is a stop-and-report.

- [ ] **Step 9: Commit**

```bash
dune fmt 2>/dev/null; git add vtree src test test_lib
GIT_EDITOR=true git commit -F - <<'MSG'
Key controllers: a synchronous answer to GTK, an effect for Bonsai

[Attr.on_key_pressed]'s handler returns a [Key_response.t] rather than an
effect, because GTK asks a key press a question and routes on the answer, on
its own stack, before any frame could run. [Handled]/[Propagate] is that
answer; [Handled_and]/[Propagate_and] carry an effect alongside it, which is
what lets a handler consume Escape *and* update the model.

Both key attrs share one GtkEventControllerKey, so differing ~phase arguments
are Invalid_argument rather than one of them silently losing.

vtree/keyval.ml hard-codes the X11 keysyms an application branches on, so a
view function stays ocgtk-free and headless-testable; test/live/live_keyvals.ml
checks every one of them against Gdk_constants on every run.

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01Sg3Ci8U8kUKR8C3PL1pNSs
MSG
```

**Review focus:** that `declined = false` is right and commented; that the differing-phase rejection has a test; that `Keyval`'s table is checked in full — count the `check` lines against the `val`s in `keyval.mli`, they must match; that `Key_press`'s inability to model propagation is stated in the mli and not only in the plan; that `of_char`'s range check raises rather than returning a wrong keysym.

---

### Task 6: ListBox — keyed rows, a key in every handler, and `Child_keys`

The forcing case for everything Tasks 4 and 5 built, and the widget stavekeeper's `sidebar.ml` and `layer_panel.ml` are made of.

**Files:**
- Modify: `vtree/attr.ml(i)`, `vtree/kind.ml(i)`, `vtree/node.ml(i)`, `vtree/defaults.ml`, `vtree/events.ml`, `vtree/selection_mode.ml` (create), `vtree/bonsai_gtk_vtree.ml`, `src/patcher.ml`, `src/widgets/registry.ml`, `src/live_tree.ml`, `src/bonsai_gtk.ml(i)`, `test_lib/bonsai_gtk_test.ml(i)`, `test/test_widgets.ml`, `test/handle/test_handle.ml`, `test/live/dune`
- Create: `vtree/selection_mode.ml`, `src/child_keys.ml`, `src/child_keys.mli`, `src/widgets/w_list_box.ml`, `test/live/live_lists.ml`, `test/live/expected_lists.txt`

**Interfaces:**
- Produces:
  ```ocaml
  (* vtree/selection_mode.ml *)
  type t = None_ | Single | Browse | Multiple [@@deriving sexp_of, equal, compare]

  (* Node *)
  val list_box
    :  ?key:Key.t -> ?attrs:Attr.t list
    -> ?selection_mode:Selection_mode.t
    -> ?activate_on_single_click:bool
    -> ?show_separators:bool
    -> ?placeholder:t
    -> selected:Key.t list
    -> t list
    -> t

  (* Attr — on the list box *)
  val on_row_activated : Key.t Handler.t -> t
  val on_selected_rows_changed : Key.t list Handler.t -> t
  (* Attr — on a child of a list box *)
  val row_selectable : bool -> t
  val row_activatable : bool -> t

  (* Child_keys *)
  type t
  val create : unit -> t
  val set : t -> Widget.t -> Key.t -> unit
  val remove : t -> Widget.t -> unit
  val find : t -> Widget.t -> Key.t option
  val find_exn : t -> Widget.t -> what:string -> Key.t

  (* Bonsai_gtk_test.Action *)
  | Activate_row of string * Key.t
  | Set_selection of string * Key.t list
  ```
- Consumes: `W.List_box.{new_,insert,remove,select_row,unselect_row,unselect_all,get_selected_rows,set_selection_mode,set_activate_on_single_click,set_show_separators,set_placeholder,on_row_activated,on_selected_rows_changed}`, `W.List_box_row.{new_,set_child,set_selectable,set_activatable,get_index}`, `Gtk_enums.selectionmode`.

**Five design rulings, all of which a reviewer should be able to argue with:**

1. **Rows are auto-wrapped, and children require a key.** `Node.list_box` takes ordinary child nodes; the impl creates a `GtkListBoxRow` per child, sets the child into it, and keeps the wrapper. The alternative — a `Node.list_box_row` the application builds — puts a widget in the tree whose only job is to exist, and makes "did you remember to wrap it" a new class of mistake. Per-row settings ride as attrs on the child (`Attr.row_selectable`, `Attr.row_activatable`), read by `list_ops.insert` and `updated`, exactly as `Attr.page_title` and `Attr.grid_cell` already are. And **every child must carry `~key`**, on the same rule and with the same message shape as a stack page: the key is the row's identity, it is what every handler receives, and there is nothing else to hand back. Stavekeeper's header rows get a synthetic key (`"header-instruments"`), which is better than the index they use today.

2. **Handlers receive keys, never rows or indices.** `on_row_activated` is a `Payload` spec: GTK hands the callback a `GtkListBoxRow`, the `connect` closure maps it to a key through `Child_keys`, and `fire` hands the key to the application. This is the *entire* reason `Payload` exists, and it is what deletes the parallel arrays in `sidebar.ml:150,205` and `layer_panel.ml:90`.

3. **Selection is controlled, and applied from the fixup queue.** `~selected:Key.t list` is the model's selection; the widget is written only when it differs from what the widget currently holds. It cannot live in `reassert` for the same reason a stack's visible child cannot: `reassert` runs before the children are patched, so the frame that adds a row and selects it would have nothing to select. `Patcher.enqueue_fixups` (Task 2) gains an arm.

4. **A key in `~selected` that no row carries is ignored, not an error.** Unlike a stack's `~visible_child` (Task 3), a selection is plural and a model that keeps a selected id through a filter change is doing something reasonable — the row comes back when the filter does. Selecting nothing is a legitimate state; selecting a row that is not there is not expressible. So: select the ones present, ignore the rest, and say so in `Node.list_box`'s doc. **This asymmetry with `~visible_child` is deliberate and must be documented on both**, or the next reader will "fix" one of them.

5. **`selection_mode` and `~selected` can disagree, and GTK arbitrates.** Handing three keys to a `Single` list box means GTK keeps the last one selected. Do not pre-clamp in the impl: the model then diverges from the widget on the very next frame's comparison, and the reassert loop writes forever. Write what was asked, read back what GTK kept, compare on the read-back value. Note it on `Node.list_box`.

**`Child_keys`** is one ephemeron table per container module, keyed on the *wrapper* widget:

```ocaml
(** Which node key a container's live wrapper widget came from.

    [GtkListBox], [GtkFlowBox] and [GtkNotebook] all hand a signal callback a {i widget} —
    a row, a child, a page's content — and every one of the questions an application asks
    about it ("which item was activated", "which are selected") is a question about the
    node it came from. The node is gone by then, so the answer is recorded when the
    wrapper is created and looked up when the signal fires.

    Weakly keyed, so a destroyed row takes its entry with it rather than pinning the
    GObject alive. [Gobject.same] is the equality: two OCaml values wrapping one GObject
    are never [==], and using [==] here would silently never find anything. The pattern
    (and the reason) is [src/widgets/w_search_entry.ml]'s [Echo] table.

    One table per container module rather than one per container instance: the keys are
    unique per container but the {i widgets} are unique globally, so a shared table is
    correct and saves a lookup. *)
```

built on `Stdlib.Ephemeron.K1.Make (struct type t = Widget.t let equal = Gobject.same let hash = Stdlib.Hashtbl.hash end)`.

`find_exn ~what` raises `Invalid_argument` naming `what` (`"list box row"`) — reachable only if a container hands back a widget it never registered, which is a library bug, and a silent `None` there would show up as a handler that mysteriously never fires.

- [ ] **Step 1: Write the failing tests**

`test/test_widgets.ml`:

```ocaml
let%expect_test "list box constructors and defaults" =
  print_s
    [%sexp
      (Node.list_box
         ~selected:[]
         [ Node.label ~key:"a" "Alpha"; Node.label ~key:"b" "Beta" ]
       : Node.t)];
  [%expect {| |}];
  print_s
    [%sexp
      (Node.list_box
         ~selection_mode:Browse
         ~activate_on_single_click:true
         ~show_separators:true
         ~placeholder:(Node.label "nothing here")
         ~selected:[ "b" ]
         [ Node.label ~key:"a" ~attrs:[ Attr.row_selectable false ] "Header"
         ; Node.label ~key:"b" "Beta"
         ]
       : Node.t)];
  [%expect {| |}]
;;

let%expect_test "a list box child without a key is rejected at the constructor" =
  Expect_test_helpers_core.require_does_raise (fun () ->
    Node.list_box ~selected:[] [ Node.label "unkeyed" ]);
  [%expect {| |}]
;;
```

Note this last one: unlike a stack page (whose missing key is caught by the impl at mount, because M1 put the check there), a list box's key requirement is checkable in the constructor and should be — the earlier the better, and `Node.list_box` already has the children in hand. **Do the same for `Node.stack` while here**, so the two behave alike; that is a one-line change to `Node.stack` and a message improvement, and it makes `w_stack.page_name`'s raise unreachable-but-kept as a belt-and-braces (say so in its comment).

`test/handle/test_handle.ml` — the sidebar, in miniature:

```ocaml
let filter_list (graph @ local) =
  let chosen, set_chosen = Bonsai.state "all" graph in
  let%arr chosen and set_chosen in
  Node.window ~title:"Sidebar"
    (Node.box ~orientation:Vertical
       [ Node.list_box
           ~attrs:[ Attr.test_id "rail"; Attr.on_row_activated set_chosen ]
           ~selection_mode:Single
           ~selected:[ chosen ]
           [ Node.label ~key:"hdr" ~attrs:[ Attr.row_selectable false; Attr.row_activatable false ] "FILTERS"
           ; Node.label ~key:"all" "All pieces"
           ; Node.label ~key:"recent" "Recent"
           ]
       ; Node.label ~attrs:[ Attr.test_id "chosen" ] chosen
       ])
;;

let%expect_test "activating a row hands the model the row's key" =
  let handle = Bonsai_gtk_test.create filter_list in
  Bonsai_gtk_test.Handle.show handle;
  [%expect {| |}];
  Bonsai_gtk_test.Handle.do_actions handle [ Activate_row ("rail", "recent") ];
  Bonsai_gtk_test.Handle.show_diff handle;
  [%expect {| |}]
;;
```

`test/live/live_lists.ml` — the GTK half. This file grows through Tasks 6–8. The claims it must pin for the list box:

```ocaml
  (* 1. The rows GTK holds, in order, with the wrapper's own props. *)
  let live = P.mount ctx ~path:"root" ~is_root:true (view ~selected:[ "b" ] ~rows:[ "a"; "b"; "c" ]) in
  P.run_fixups ctx;
  print_s (Live_tree.dump live.widget);

  (* 2. A keyed reorder moves the same GObjects. Take handles first, patch, compare with
        [Gobject.same] -- the dump alone cannot say this, because two rows holding the same
        label print identically. *)
  let rows_before = row_widgets live in
  let live = patch (view ~selected:[ "b" ] ~rows:[ "c"; "a"; "b" ]) in
  printf "same GObjects after reorder: %b\n" (rows_match rows_before (row_widgets live));
  print_s (Live_tree.dump live.widget);

  (* 3. The declined selection. The user clicks row "c"; the model keeps "b"; the frame
        that renders the *same* selection must put the widget back. This is spec §6.5 for
        a container, and the reason selection is a fixup rather than an [update]. *)
  select_row_by_hand live "c";
  printf "after the user clicked: %s\n" (selected_keys live);
  let live = patch (view ~selected:[ "b" ] ~rows:[ "c"; "a"; "b" ]) in
  printf "after the declining frame: %s\n" (selected_keys live);

  (* 4. Add a row and select it in one frame. The row does not exist when [reassert] would
        have run, which is why this is a fixup; without the fixup this prints nothing
        selected. *)
  let live = patch (view ~selected:[ "d" ] ~rows:[ "c"; "a"; "b"; "d" ]) in
  printf "add-and-select: %s\n" (selected_keys live);

  (* 5. Removing the selected row. GTK drops the selection; the model still says "d", and
        the next frame must not resurrect a row that is gone. Nothing selected, no raise. *)
  let live = patch (view ~selected:[ "d" ] ~rows:[ "c"; "a"; "b" ]) in
  printf "selected row removed: %s\n" (selected_keys live);

  (* 6. A key in ~selected that no row carries is ignored (ruling 4), not an error. *)
  let live = patch (view ~selected:[ "a"; "ghost" ] ~rows:[ "c"; "a"; "b" ]) in
  printf "selection with a ghost key: %s\n" (selected_keys live);

  (* 7. Teardown does not fire a handler. GTK emits [selected-rows-changed] as rows go
        away; [scheduled] must not move across the destroy. *)
  let before = !scheduled in
  P.destroy ctx live;
  printf "handlers fired during teardown: %d\n" (!scheduled - before);
```

Cases 3, 4, 5 and 7 are the ones that would pass with a wrong implementation if they were left out. Write them first.

- [ ] **Step 2: Run to verify failure.**

- [ ] **Step 3: `vtree/selection_mode.ml`**

```ocaml
(** How many rows or children may be selected at once.

    [None_] rather than [None]: a constructor called [None] would shadow [Option.None] in
    every match in the file that handles it, which is the same reason
    {!Bonsai_gtk_vtree.Reveal_transition} and {!Stack_transition} spell theirs [None_].

    [Browse] is [Single] with "exactly one" instead of "at most one": GTK keeps a row
    selected at all times and will not let the user deselect. A model that renders
    [~selected:[]] to a [Browse] list box is asking for something GTK does not do; see
    {!Bonsai_gtk_vtree.Node.list_box}. *)
type t = None_ | Single | Browse | Multiple [@@deriving sexp_of, equal, compare]
```

- [ ] **Step 4: `vtree/attr.ml(i)` and the placement table**

Four names, adjacent: `On_row_activated`, `On_selected_rows_changed`, `Row_selectable`, `Row_activatable`. The last two are placement attrs, so `Attr_apply.set`/`unset` get inert arms (with the comment the existing placement attrs have), `Events.for_kind` never mentions them (they are not events), and **`Patcher.placement_attrs_read_by` (Task 3) gains `| List_box _ -> [ Row_selectable; Row_activatable ]`** — which is what makes `Attr.row_selectable` on a box child an error rather than a mystery.

- [ ] **Step 5: `src/child_keys.ml(i)`** — as specified above. Forty lines, half of them the doc comment.

- [ ] **Step 6: `src/widgets/w_list_box.ml`**

The three parts worth writing out here, because each has a trap:

```ocaml
(* One table for every list box in the process. Keyed on the [GtkListBoxRow] wrapper this
   impl creates, never on the application's child widget: two list boxes may render the
   same child node, and the wrapper is what GTK hands back. *)
let row_keys = Child_keys.create ()

let row_key (node : Node.t) =
  match node.key with
  | Some key -> key
  | None ->
    (* Unreachable: [Node.list_box] rejects an unkeyed child. Kept because the patcher can
       reach [insert] from a path the constructor did not build (a [Node.native] payload
       assembling children, a future constructor), and a silent [""] key would make every
       row answer to the same name. *)
    invalid_arg "list box child has no ~key (a row's key is the identity handlers receive)"
;;

let wrap ~(node : Node.t) (child : Widget.t) =
  let row = W.List_box_row.new_ () in
  W.List_box_row.set_child row (Some child);
  (* Per-row settings are the *parent's*, read off the child node's attrs. A header row is
     [~attrs:[ Attr.row_selectable false; Attr.row_activatable false ]] -- which is exactly
     what stavekeeper's sidebar.ml:21-22 does by hand. *)
  Option.iter (row_flag node Row_selectable) ~f:(W.List_box_row.set_selectable row);
  Option.iter (row_flag node Row_activatable) ~f:(W.List_box_row.set_activatable row);
  Child_keys.set row_keys (row :> Widget.t) (row_key node);
  row
;;
```

`list_ops`:

```ocaml
  ; children =
      Widget_impl.List
        { insert =
            (fun parent ~after ~node child ->
              let row = wrap ~node child in
              (* [GtkListBox] has no insert-after; it has insert-at-index. The patcher's
                 [after] is a *widget*, so turn it back into an index with the wrapper's
                 own [get_index] -- which is GTK's answer, not the patcher's, and is
                 correct here precisely because the list box interposes nothing else: its
                 children are exactly the wrappers this impl made. [None] is index 0. *)
              let index =
                match after with
                | None -> 0
                | Some w -> W.List_box_row.get_index (cast w) + 1
              in
              W.List_box.insert (cast parent) (row :> Widget.t) index)
        ; move =
            Some
              (fun parent ~child ~after ->
                (* No [reorder_child_after]: remove and re-insert. The row survives (this
                   holds a reference through [child]), so keyed identity is preserved --
                   which is the whole claim, and [live_lists.ml] case 2 is what checks it.
                   [remove] can drop the selection; the selection fixup runs after every
                   pass and puts it back. *)
                ...)
        ; remove =
            (fun parent child ->
              Child_keys.remove row_keys child;
              W.List_box.remove (cast parent) child)
        ; updated =
            (fun _parent ~old ~node row ->
              (* The key cannot change -- a changed key is a different child to the
                 reconciler -- so only the two row flags are re-read. *)
              ...)
        }
```

**Careful:** the patcher's `remove`/`move` are handed the widget *it* recorded as the child, which for this container is the wrapper, not the application's child widget. Confirm that `list_ops.insert` returning nothing means the patcher keeps `l.widget` (the child's own widget) in `cur`, not the wrapper — if so, `after`, `move` and `remove` will all be handed the *inner* widget and every line above is wrong. **This is the single most likely way this task goes sideways.** Read `Patcher.patch_children`'s `List` arm before writing a line of `w_list_box.ml`, and if the patcher tracks inner widgets, the fix is to map inner → wrapper through a second `Child_keys`-shaped table (or through `Widget.get_parent`, which for a wrapped child *is* the row). Prefer `get_parent`: it is one call, it cannot go stale, and it is exactly what GTK guarantees. Write down which it turned out to be.

The two specs:

```ocaml
let row_activated : Signals.spec =
  Payload
    { attr = Attr.Name.On_row_activated
    ; connect =
        (fun w ~callback ->
          Signals.connected
            w
            (W.List_box.on_row_activated (cast w) ~callback:(fun ~row ->
               callback (Child_keys.find_exn row_keys (row :> Widget.t) ~what:"list box row"))))
    ; fire =
        (fun _w attr key ->
          match (attr : Attr.Private.t) with
          | On_row_activated handler -> (), Some (handler key)
          | _ -> (), None)
    ; declined = ()
    }
;;

(* [selected-rows-changed] carries nothing, so this one is a [Read_back] -- the selection
   *is* readable off the widget. It still goes through [Child_keys], to answer in the
   application's terms rather than GTK's. *)
let selected_rows_changed : Signals.spec =
  Read_back
    { attr = Attr.Name.On_selected_rows_changed
    ; connect = (fun w ~callback -> Signals.connected w (W.List_box.on_selected_rows_changed (cast w) ~callback))
    ; fire =
        (fun w attr ->
          match (attr : Attr.Private.t) with
          | On_selected_rows_changed handler -> Some (handler (selected_keys w))
          | _ -> None)
    }
;;
```

`selected_keys` maps `get_selected_rows` through `Child_keys.find` and drops the `None`s — a row GTK reports that this impl did not register cannot happen, but dropping is the right response if it ever does, because raising from inside a signal is worse than under-reporting.

The selection application, called from the fixup:

```ocaml
(* Controlled, on spec §6.5's rule and compared against the widget rather than the
   previous node -- so the frame on which the model *declines* a click puts the selection
   back. From the fixup pass rather than [reassert] because the rows do not exist when
   [reassert] runs; see [Widget_impl.reassert]'s own note about [Stack].

   Keys naming no row are ignored rather than rejected: a model that holds a selected id
   across a filter change is doing something reasonable, and the row comes back when the
   filter does. This is deliberately *unlike* [Node.stack ~visible_child], which raises --
   a stack shows exactly one page and a name that never resolves is a typo with no other
   symptom. Both are documented on their constructors. *)
let apply_selection (w : Widget.t) ~selected =
  let current = selected_keys w in
  if not (List.equal String.equal (List.sort ~compare:String.compare current)
            (List.sort ~compare:String.compare selected))
  then (
    let lb : W.List_box.t = cast w in
    W.List_box.unselect_all lb;
    List.iter selected ~f:(fun key ->
      Option.iter (row_by_key w key) ~f:(fun row -> W.List_box.select_row lb (Some row))))
;;
```

Sorting both sides before comparing is deliberate: GTK reports selected rows in *widget* order and the model lists them in whatever order it built. Two orderings of one selection must not look like a change, or the fixup writes every frame and the user can never keep a multi-selection.

- [ ] **Step 7: `src/patcher.ml`** — `enqueue_fixups` gains `| List_box p -> Queue.enqueue ctx.fixups (fun () -> W_list_box.apply_selection widget ~selected:p.selected)`.

- [ ] **Step 8: `src/live_tree.ml`** — a `"GtkListBox"` arm printing `selection-mode` (when not `NONE`), `activate-on-single-click` (when true — GTK's own default is true, so print it when *false*; check), `show-separators`, and the count of selected rows; and a `"GtkListBoxRow"` arm printing `selected`, and `selectable`/`activatable` when false. **Do not print the row's key**: `Live_tree` dumps GTK, and the key is the vtree's. A golden that showed keys would go green on an implementation that put them in the wrong rows.

Instead, `live_lists.ml` prints `selected_keys` itself, which is a read through `Child_keys` and therefore does exercise the mapping.

- [ ] **Step 9: `test_lib`** — `Activate_row of string * Key.t` and `Set_selection of string * Key.t list`, both firing the named node's handler with exactly the key(s) given; neither consults the node's own `~selected`, for the reason `Set_text` documents.

- [ ] **Step 10: Run, read, promote, gate, commit**

```bash
./scripts/ci.sh
dune fmt 2>/dev/null; git add vtree src test test_lib
GIT_EDITOR=true git commit -F - <<'MSG'
ListBox: rows keyed by the node's key, and every handler speaks in keys

Children are auto-wrapped in GtkListBoxRows the impl owns, and every child must
carry ~key: the key is the row's identity and it is what on_row_activated and
on_selected_rows_changed hand back. Child_keys is the weak map from a live
wrapper to its key that makes that possible; it is what Signals' new Payload
spec exists for, and it is what deletes the parallel row arrays a GTK app needs
because row-activated only offers an index.

Selection is controlled and applied from the fixup pass, so the frame on which
a model declines a click puts the selection back, and a frame that adds a row
can select it. A key naming no row is ignored -- unlike a stack's
~visible_child, which raises; both asymmetries are documented on both
constructors.

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01Sg3Ci8U8kUKR8C3PL1pNSs
MSG
```

**Review focus:** whether the patcher tracks the wrapper or the inner widget, and that whichever it is, `insert`/`move`/`remove`/`updated`/`after` all agree — this is the task's main hazard; that `apply_selection` sorts before comparing; that removing a selected row does not raise and does not resurrect it; that teardown fires no handler (case 7); that `Live_tree` prints no keys; that the ignored-ghost-key asymmetry with `~visible_child` is documented on *both* constructors, not one.

---

### Task 7: FlowBox — the same machinery, a grid of cards

Deliberately the task after ListBox and deliberately smaller: it reuses `Child_keys`, the auto-wrapping, the keyed-children rule and the selection fixup wholesale. What is new is the geometry props and the fact that stavekeeper reconfigures them at runtime (`library_window.ml:226-239` switches one FlowBox between a grid and a list view), which is exactly what a declarative prop diff is for.

**Files:**
- Modify: `vtree/attr.ml(i)`, `vtree/kind.ml(i)`, `vtree/node.ml(i)`, `vtree/defaults.ml`, `vtree/events.ml`, `src/patcher.ml`, `src/widgets/registry.ml`, `src/live_tree.ml`, `test_lib/bonsai_gtk_test.ml(i)`, `test/test_widgets.ml`, `test/handle/test_handle.ml`, `test/live/live_lists.ml`
- Create: `src/widgets/w_flow_box.ml`

**Interfaces:**
- Produces:
  ```ocaml
  val flow_box
    :  ?key:Key.t -> ?attrs:Attr.t list
    -> ?selection_mode:Selection_mode.t
    -> ?activate_on_single_click:bool
    -> ?min_children_per_line:int
    -> ?max_children_per_line:int
    -> ?row_spacing:int
    -> ?column_spacing:int
    -> ?homogeneous:bool
    -> selected:Key.t list
    -> t list
    -> t

  val on_child_activated : Key.t Handler.t -> Attr.t
  val on_selected_children_changed : Key.t list Handler.t -> Attr.t
  ```
- Consumes: `W.Flow_box.{new_,insert,remove,select_child,unselect_all,get_selected_children,get_child_at_index,set_selection_mode,set_activate_on_single_click,set_min_children_per_line,set_max_children_per_line,set_row_spacing,set_column_spacing,set_homogeneous,on_child_activated,on_selected_children_changed}`, `W.Flow_box_child.{new_,set_child,get_index}`.

**Defaults** (`vtree/defaults.ml`, read from the GTK docs and confirmed against a live widget in Step 5, not from this table alone):

```ocaml
module Flow_box = struct
  let selection_mode = Selection_mode.Single
  let activate_on_single_click = true
  let min_children_per_line = 0
  let max_children_per_line = 7
  let row_spacing = 0
  let column_spacing = 0
  let homogeneous = false
end
```

`max_children_per_line`'s GTK default of 7 is the one worth checking: it is a real value, not "unlimited", and an application that never sets it gets seven per line whatever its width. Confirm by dumping a fresh `GtkFlowBox` in the live test and printing `get_max_children_per_line` before promoting.

**One deliberate difference from ListBox:** `activate_on_single_click` is defaulted to GTK's `true`, and `Node.flow_box`'s doc calls out that stavekeeper sets it to `false` on purpose (`library_window.ml:216`) so that a single click selects and a double click opens. That is the interaction a grid of cards wants and it is not the default.

- [ ] **Step 1: Write the failing tests**

`test/test_widgets.ml` — constructor and defaults, plus the unkeyed-child rejection (same rule as ListBox).

`test/handle/test_handle.ml` — the library grid in miniature: a flow box of keyed cards, `on_child_activated` opening one and `on_selected_children_changed` driving a "1 selected" label and a button's `sensitive` attr. That last part is the thing stavekeeper does with mutation (`library_window.ml:272-273,612-615`) and is worth showing declaratively in a test, because it is the argument for the port.

`test/live/live_lists.ml` — append. The claims:

```ocaml
  (* 1. Geometry, and the runtime reconfiguration stavekeeper does by hand: the same flow
        box rendered as a grid and then as a list. Every one of the five props changes in
        one patch, which is what [Widget_impl.batch] is for. *)
  (* 2. Keyed reorder preserves GObjects, as for the list box. *)
  (* 3. The declined selection, and add-and-select in one frame. *)
  (* 4. Removing the selected child. GTK's [remove] does *not* emit
        [selected-children-changed] -- a documented quirk that cost stavekeeper a real
        dangling-widget crash (library_window.ml:76-97) -- so the model's selection and the
        widget's can silently diverge. Assert what this library does: the next frame's
        selection fixup compares against the widget and puts the model's answer back, so
        the divergence lasts less than a frame and nothing reads it in between. *)
```

Case 4 is the one to write first and the one to describe in the impl's comments: it is a real GTK sharp edge, the reason the imperative app has a crash comment, and the strongest single argument for the declarative version.

- [ ] **Step 2–5: implement** — `w_flow_box.ml` is `w_list_box.ml` with a different set of props and `Flow_box_child` for `List_box_row`. Its own `Child_keys.create ()` table (one per module, per `Child_keys`'s doc). `insert` uses `W.Flow_box.insert` with an index derived from `after` the same way, with the same caveat about which widget the patcher tracks — resolved in Task 6, so quote the answer rather than re-deriving it. `move` is `Some` (remove-and-reinsert, as for the list box). `apply_selection` is the same function with `select_child`/`unselect_all`/`get_selected_children`.

**Do not** factor `w_list_box.ml` and `w_flow_box.ml` into a shared functor. They differ in five prop names, two class names and three method names, and the shared part is thirty lines that read better twice than once behind an abstraction that would have to be parameterised on the wrapper type. Say this in a comment at the top of `w_flow_box.ml` so a reviewer does not file it as duplication — and if the reviewer disagrees, that is a legitimate argument and the third container (Task 8) is the point at which to have it.

- [ ] **Step 6: `Events`, `Registry`, `Live_tree`, the placement table** — `Flow_box` reads no placement attrs, so its arm in `placement_attrs_read_by` is `[]` (i.e. it falls into the wildcard, and that is correct: a `row_selectable` on a flow box child is a mistake). `Live_tree`'s `"GtkFlowBox"` arm prints the five geometry props against their defaults and the selection count.

- [ ] **Step 7: `test_lib`** — reuse `Activate_row` and `Set_selection`? **No.** Add `Activate_child of string * Key.t`, because the action names a *kind* of node and a test reading `Activate_row ("grid", …)` against a flow box is confusing; and because the handle looks the node up by `test_id` and can therefore check the kind and fail loudly on a mismatch, which it should. `Set_selection` *is* shared — it is the same question for both kinds — and its doc says which kinds it accepts.

- [ ] **Step 8: Run, read, promote, gate, commit**

```bash
./scripts/ci.sh
dune fmt 2>/dev/null; git add vtree src test test_lib
GIT_EDITOR=true git commit -F - <<'MSG'
FlowBox: keyed children, controlled selection, geometry as a prop diff

The same auto-wrapping, keyed-children and selection-fixup machinery ListBox
uses, over GtkFlowBoxChild. The geometry props (min/max per line, spacings,
homogeneous) are ordinary props, which is what makes switching one flow box
between a grid view and a list view a diff rather than five setters and a
css-class toggle.

GtkFlowBox.remove does not emit selected-children-changed, so a removed
selected child silently diverges the widget from the model; the selection fixup
runs on the next frame and puts the model's answer back, which is asserted
rather than assumed.

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01Sg3Ci8U8kUKR8C3PL1pNSs
MSG
```

**Review focus:** that `max_children_per_line`'s default was read off a live widget, not copied from this plan; that the remove-a-selected-child case asserts the recovery rather than the divergence; that the no-functor decision is argued in a comment and that the reviewer either agrees or says so now rather than at the final review.

---

### Task 8: Notebook — the first container with a real reorder

Third and last of the keyed containers, and the one Task 2's `Unordered` marker was designed against: `GtkNotebook` has `reorder_child`, so it takes `move = Some` and its children genuinely move.

**Files:**
- Modify: `vtree/attr.ml(i)`, `vtree/kind.ml(i)`, `vtree/node.ml(i)`, `vtree/defaults.ml`, `vtree/events.ml`, `src/patcher.ml`, `src/widgets/registry.ml`, `src/live_tree.ml`, `test_lib/bonsai_gtk_test.ml(i)`, `test/test_widgets.ml`, `test/handle/test_handle.ml`, `test/live/live_lists.ml`
- Create: `src/widgets/w_notebook.ml`

**Interfaces:**
- Produces:
  ```ocaml
  val notebook
    :  ?key:Key.t -> ?attrs:Attr.t list
    -> ?scrollable:bool
    -> ?show_tabs:bool
    -> ?show_border:bool
    -> current_page:Key.t
    -> t list
    -> t

  val tab_label : string -> Attr.t     (* on a notebook child *)
  val on_page_changed : Key.t Handler.t -> Attr.t
  ```
- Consumes: `W.Notebook.{new_,insert_page,remove_page,page_num,get_n_pages,get_nth_page,set_current_page,get_current_page,set_tab_label_text,reorder_child,set_scrollable,set_show_tabs,set_show_border,on_switch_page}`.

**Four things this widget does differently from the other two, each because GTK does:**

1. **Pages are addressed by *index*, not by widget.** `remove_page` takes an int; `insert_page` takes an int and returns one; `reorder_child` takes a widget and an int. So every operation begins with `page_num nb child`, which is GTK's own answer and is the right one here — a notebook interposes nothing, its children *are* the pages' content widgets. `Child_keys` is keyed on the content widget rather than on a wrapper, which is the one place the three containers differ.

2. **`insert_page` returns the new index and takes the tab label as an option, fourth-argument-last.** `ignore (W.Notebook.insert_page nb child (Some label) index : int)`. Getting the argument order wrong typechecks in exactly one wrong way (`Widget.t option` and `int` are distinct, so it does not — good) and the `int` result is easy to forget.

3. **The tab label is a *widget* GTK owns**, and `set_tab_label_text` builds a `GtkLabel` for it. `Attr.tab_label` is therefore a `string`, not a node: a node would mean a second child list, a second patch path and a second lifetime for something that is always a label. An application that wants a tab with an icon has `Node.native`; say so on the attr.

4. **`current_page` is controlled and, like the others, applied from the fixup queue.** `on_switch_page`'s callback carries `~page:Widget.t ~page_num:int` — the *content widget*, not a `Notebook_page.t` — so `Child_keys` maps it and the handler gets a key. Note that GTK emits `switch-page` during `insert_page` of the first page, which happens inside the patch: the `in_patch` guard swallows it, and the live test asserts that (`scheduled` unchanged across a mount).

**And one it does the same:** a page whose `~key` is missing is rejected by the constructor, and `~current_page` naming no page **raises**, unlike a list box's selection and like a stack's `~visible_child`. The rule is now statable in one sentence, and `Node.notebook`, `Node.stack` and `Node.list_box` should each carry it: *a container that shows exactly one of its children raises when told to show one that does not exist; a container with a plural selection ignores the keys it cannot find.* Put that sentence in all three docs, identically.

- [ ] **Step 1: Write the failing tests**

`test/test_widgets.ml` — constructors, the `~tab_label` attr on children, defaults.

`test/handle/test_handle.ml` — a two-page notebook whose `current_page` is model state, with `Set_page` driving it.

`test/live/live_lists.ml` — append:

```ocaml
  (* 1. Pages, tab labels, and which is current. *)
  (* 2. A real reorder. This is the first container in the library where [Move] does
        something: the same three pages in a new order, asserting both that the tab order
        changed in the dump *and* that the page widgets are the same GObjects. The overlay
        case in live_containers.ml is the mirror image -- same GObjects, order unchanged --
        and between them they say what [list_ops.move = None] means. *)
  (* 3. The declined page change: the user clicks tab 3, the model re-renders page 1. *)
  (* 4. Add a page and make it current in one frame. *)
  (* 5. Remove the current page. GTK picks a neighbour; the model still says the old key;
        the fixup then raises, because ~current_page names no page -- which is the
        documented behaviour and is the *application's* bug (it removed a page without
        moving its selection). Assert the raise and its message. *)
  (* 6. Mounting a notebook fires no handler, though GTK emits switch-page while pages are
        being inserted. *)
```

Case 5 deserves a moment's thought before it is written: is raising right? A model that removes the current page without choosing a new one has an inconsistent view, and every frame after it renders the same inconsistency, so a silent ignore would leave the notebook showing whatever GTK picked while the model believed something else — the divergence spec §6.5 exists to prevent. Raising is loud and points at the render. **If the implementer disagrees after writing it, say so in the report**; it is a genuine judgement call and the alternative (clamp to GTK's choice and let the model see it through `on_page_changed`) is defensible.

- [ ] **Step 2–6: implement.** `w_notebook.ml`, following `w_list_box.ml`'s shape with the four differences above. `list_ops.move = Some (fun parent ~child ~after -> W.Notebook.reorder_child (cast parent) child (index_after parent after))` where `index_after` is `0` for `None` and `page_num parent w + 1` otherwise — note that `reorder_child`'s index is the *destination* index in the list with the child still in it, so check GTK's semantics against the live test rather than trusting this line.

- [ ] **Step 7: `placement_attrs_read_by`** gains `| Notebook _ -> [ Tab_label ]`.

- [ ] **Step 8: `Live_tree`** — a `"GtkNotebook"` arm printing `pages`, `current-page`, and `show-tabs`/`show-border`/`scrollable` when not default. The tab labels appear in the dump anyway, as the `GtkLabel` children GTK made.

- [ ] **Step 9: Run, read, promote, gate, commit**

```bash
./scripts/ci.sh
dune fmt 2>/dev/null; git add vtree src test test_lib
GIT_EDITOR=true git commit -F - <<'MSG'
Notebook: keyed pages, and the first container whose children really move

GtkNotebook has reorder_child, so it takes [list_ops.move = Some] and
Reconcile emits Move ops for it -- the case Task 2's unordered marker was
designed against. Its pages are addressed by index rather than by widget, which
is why every operation starts at page_num, and its Child_keys table is keyed on
the page's content widget rather than on a wrapper this impl made.

~current_page is controlled and applied from the fixup pass, and names a page
that must exist: a container showing exactly one of its children raises when
told to show one that is not there, where a container with a plural selection
ignores keys it cannot find. Stack, Notebook and ListBox now each say that in
their own docs.

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01Sg3Ci8U8kUKR8C3PL1pNSs
MSG
```

**Review focus:** that `reorder_child`'s index semantics were checked against GTK rather than assumed; that the reorder test asserts *both* the new order and the same GObjects; that the `in_patch` guard really does swallow the `switch-page` GTK emits during a mount (case 6 is the proof); that the one-sentence show-exactly-one/plural-selection rule appears verbatim in all three constructors' docs.

---

### Task 9: TextView — a controlled buffer, and a cursor policy stated out loud

The one M2 widget whose signal lives on a different GObject than the widget, which is what M1's object-carrying `connect` was widened for (spec §6.4's amendment names `GtkTextBuffer` explicitly as the case it was anticipating).

**Files:**
- Modify: `vtree/kind.ml(i)`, `vtree/node.ml(i)`, `vtree/defaults.ml`, `vtree/events.ml`, `vtree/bonsai_gtk_vtree.ml`, `src/widgets/registry.ml`, `src/live_tree.ml`, `src/bonsai_gtk.ml(i)`, `test/test_widgets.ml`, `test/handle/test_handle.ml`, `test/live/dune`
- Create: `vtree/wrap_mode.ml`, `src/widgets/w_text_view.ml`, `test/live/live_text.ml`, `test/live/expected_text.txt`

**Interfaces:**
- Produces:
  ```ocaml
  (* vtree/wrap_mode.ml *)
  type t = None_ | Char | Word | Word_char [@@deriving sexp_of, equal, compare]

  val text_view
    :  ?key:Key.t -> ?attrs:Attr.t list
    -> ?wrap:Wrap_mode.t
    -> ?editable:bool
    -> ?monospace:bool
    -> ?cursor_visible:bool
    -> ?accepts_tab:bool
    -> ?left_margin:int -> ?right_margin:int -> ?top_margin:int -> ?bottom_margin:int
    -> text:string
    -> unit
    -> t
  ```
- Consumes: `W.Text_view.{new_,get_buffer,set_wrap_mode,set_editable,set_monospace,set_cursor_visible,set_accepts_tab,set_left_margin,set_right_margin,set_top_margin,set_bottom_margin}`, `W.Text_buffer.{get_bounds,get_text,set_text,get_cursor_position,get_iter_at_offset,place_cursor,get_char_count,on_changed}`.

**The three ocgtk facts that shape the implementation**, each verified and each easy to get wrong:

- `Text_buffer.set_text : t -> string -> int -> unit` — the trailing `int` is a **byte length**; `-1` means NUL-terminated, which is what to pass. `String.length s` also works and is equivalent for OCaml's byte strings; pass `-1` and say why in a comment, so nobody "fixes" it to a character count.
- `Text_buffer.get_text : t -> Text_iter.t -> Text_iter.t -> bool -> string` — there is no whole-buffer variant. Reading is `let a, b = W.Text_buffer.get_bounds buf in W.Text_buffer.get_text buf a b true`. The trailing `true` is `include_hidden_chars`; with no tags in play it makes no difference, and `true` is the answer that keeps making no difference if tags ever arrive.
- **`Text_iter` has no constructor.** Every iter comes from a buffer getter and is a GC-managed copy; mutating one (`set_offset`, `forward_char`) touches your copy and not the buffer. Iters are invalidated by edits, so re-fetch after every mutation — which the code below does by never holding one across a write.

**The cursor policy, stated rather than implied.** `GtkEntry`'s `reassert` saves `get_position` and restores it, because `set_text` moves the caret to the end and GTK clamps a restored position to the new length. A `GtkTextBuffer` is the same problem with a worse failure: a multi-line note whose caret jumps to the end on every keystroke the model echoes is unusable. So:

```ocaml
(* Controlled, on spec §6.5's rule: written only when the buffer's current text differs
   from the model's, never when the previous node's did.

   The cursor is saved as a *character offset* and restored after the write, which is the
   same policy [w_entry.ml] uses and has the same two properties. It is right when the
   model echoed what was typed (nothing is written, so nothing moves) and right when the
   model rewrote it in place (uppercasing, trimming trailing space: the offset still
   means what it meant). It is *approximate* when the model changed the text's length
   before the cursor -- an autocompleter inserting six characters at the start leaves the
   caret six characters early -- and GTK clamps an offset past the end.

   That is a policy, not an accident, and the honest alternative is worse: preserving the
   cursor by diffing old against new text would be a general text-diff in a widget impl,
   and preserving nothing would put the caret at the end of the document on every write.
   Applications that need better own the cursor themselves, which M2 does not expose --
   [notify::cursor-position] is the hook, and it is on the backlog.

   The selection is *not* preserved: [set_text] collapses it, and restoring it would mean
   restoring an anchor the model may have invalidated. An application that programmatically
   rewrites text under a selection is doing something the user will notice however this
   behaves. *)
```

Write that comment. It is the kind of thing that gets re-litigated in three months.

- [ ] **Step 1: Write the failing tests**

`test/test_widgets.ml` — constructor and defaults, including that `~text` is required (positional-ish, a labelled non-optional) so a text view always has a controlled text, like the entries.

`test/handle/test_handle.ml` — the declined edit, headlessly:

```ocaml
let notes (graph @ local) =
  let text, set_text = Bonsai.state "" graph in
  let%arr text and set_text in
  (* A model that refuses anything over ten characters: the state does not change, so the
     view does not change, so the *only* thing that puts the widget back is [reassert] --
     which is what makes this the interesting test and not a formality. *)
  Node.window ~title:"Notes"
    (Node.text_view
       ~attrs:[ Attr.test_id "body"; Attr.on_changed (fun s -> if String.length s <= 10 then set_text s else Effect.Ignore) ]
       ~text
       ())
;;
```

with two `Set_text` actions, one accepted and one refused, and `show_diff` after each. The refused one must show **no diff**, which is the headless shadow of the live claim below.

`test/live/live_text.ml` — the GTK half. This file grows through Tasks 9–11:

```ocaml
  (* 1. Props: wrap mode, editable, monospace, the four margins. *)
  (* 2. The controlled write. Type into the buffer by hand (insert at the cursor, the way a
        user does), then render the *same* model text: the buffer must go back. *)
  (* 3. The caret. Put the cursor in the middle, have the model rewrite the text to
        something of the same length, and assert the offset survived. Then have it rewrite
        to something shorter and assert the offset clamped rather than raised. *)
  (* 4. The echo. Render text the buffer already holds: [get_text] is called, [set_text] is
        not, and the caret does not move. Observable as the cursor offset being unchanged
        after a patch that "wrote" the same string. *)
  (* 5. The reentrancy case. A programmatic write emits [changed] on the buffer,
        synchronously, from inside the patch; [scheduled] must not move. This is the
        buffer-object version of the case live_controls.ml pins for entries, and it is the
        first time a signal connected to a non-widget GObject goes through the guard. *)
  (* 6. Teardown disconnects from the *buffer*. Destroy the view, then emit [changed] on
        the buffer handle the test still holds: nothing fires. A connection that named the
        widget instead of the buffer would fail to disconnect here -- which is exactly the
        bug M1's fix wave widened [Signals.connection] to prevent, and this is the first
        test that can actually catch it. *)
```

Case 6 is the most valuable test in this task and did not exist before, because M1 had no signal on a long-lived non-widget object. Write it.

- [ ] **Step 2: Run to verify failure.**

- [ ] **Step 3: `vtree/wrap_mode.ml`** — four constructors, `None_` for the shadowing reason, mapping to `Gtk_enums.wrapmode`'s `` `NONE | `CHAR | `WORD | `WORD_CHAR ``. GTK's default is `` `NONE ``, so `Defaults.Text_view.wrap = Wrap_mode.None_`; note in `Node.text_view`'s doc that `Word_char` is what a notes field usually wants (wrap at word boundaries, break a word that does not fit) and `None_` is what a code field wants.

- [ ] **Step 4: `src/widgets/w_text_view.ml`**

```ocaml
let buffer (w : Widget.t) : W.Text_buffer.t = W.Text_view.get_buffer (cast w)

(* [get_buffer] is not a constructor: [GtkTextView] makes its own buffer at construction
   and [get_buffer] returns that same one every time, so this is a cheap accessor and the
   object identity is stable for the widget's lifetime -- which is what makes it safe to
   connect a signal to it at [create] and disconnect at [destroy]. Do not call
   [set_buffer]: swapping the buffer would strand the connection on the old one. *)

let read w =
  let b = buffer w in
  let start_, end_ = W.Text_buffer.get_bounds b in
  W.Text_buffer.get_text b start_ end_ true
;;

let set_text_if_needed w text =
  let b = buffer w in
  if String.equal (read w) text
  then false
  else (
    let offset = W.Text_buffer.get_cursor_position b in
    (* [-1] is GTK's "the string is NUL-terminated". Not a character count: passing one
       would truncate any text containing a multi-byte character. *)
    W.Text_buffer.set_text b text (-1);
    (* Re-fetch: the iter above (if any) is invalid after the write, and [get_iter_at_offset]
       clamps an offset past the end, which is the right answer when the model shortened
       the text. *)
    W.Text_buffer.place_cursor b (W.Text_buffer.get_iter_at_offset b offset);
    true)
;;

let changed : Signals.spec =
  Read_back
    { attr = Attr.Name.On_changed
    ; connect =
        (fun w ~callback ->
          (* The buffer is where [changed] is emitted, so the buffer is what the connection
             must name -- a handler id is unique per object, and disconnecting a buffer's
             id from the widget would at best log a GLib critical and at worst disconnect
             something unrelated (spec §6.4's M1 amendment). *)
          let b = buffer w in
          Signals.connected b (W.Text_buffer.on_changed b ~callback))
    ; fire =
        (fun w attr ->
          match (attr : Attr.Private.t) with
          | On_changed handler -> Some (handler (read w))
          | _ -> None)
    }
;;
```

`reassert` is `set_text_if_needed` under `batch_if`. `create` writes the props and then the text last, matching `w_entry.ml`'s ordering and for the same reason (a margin or wrap change re-lays-out the view, and doing that after the write would re-run the caret placement).

- [ ] **Step 5: `Live_tree`** — a `"GtkTextView"` arm printing the text (through `get_bounds`+`get_text`), `wrap-mode` when not `NONE`, `read-only` when not editable, `monospace`, and the margins when non-zero. **Truncate the text** at, say, 60 characters with an ellipsis: a golden with a paragraph in it is unreadable and would churn on every wording change. Say so in a comment beside the arm, and note that the truncation means the golden cannot pin a long text — which is fine, because case 2 above prints the text itself.

- [ ] **Step 6: Run, read, promote, gate, commit**

```bash
./scripts/ci.sh
dune fmt 2>/dev/null; git add vtree src test
GIT_EDITOR=true git commit -F - <<'MSG'
TextView: a controlled buffer, and a cursor policy written down

The text is controlled on spec §6.5's rule, and the caret is saved as a
character offset across the write -- exact when the model echoed or rewrote in
place, approximate when it changed the length before the cursor, and clamped by
GTK when it shortened the text. That is a policy rather than an accident and
the impl says so at length, because the alternatives (a text diff in a widget
impl, or the caret at the end after every write) are both worse.

[changed] is connected to the GtkTextBuffer, not the view: the first signal in
this library on a long-lived object that is not the widget, and the first test
that can catch a connection naming the wrong object -- destroying the view and
then emitting on the buffer must fire nothing.

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01Sg3Ci8U8kUKR8C3PL1pNSs
MSG
```

**Review focus:** that `set_text`'s trailing argument is `-1` and commented; that no `Text_iter` is held across a write; that the disconnect-from-the-buffer test would fail if `connect` named the widget (try it); that `Live_tree`'s truncation is documented and that some test still pins the full text.

---

### Task 10: DropDown and LevelBar — a rebuilt model, and a trivial one

Paired deliberately: `GtkDropDown` is the most awkward widget in M2 (its model is a separate GObject that has to be rebuilt, and its only selection signal is a `notify::`), and `GtkLevelBar` is four properties and no signals.

**Files:**
- Modify: `vtree/attr.ml(i)`, `vtree/kind.ml(i)`, `vtree/node.ml(i)`, `vtree/defaults.ml`, `vtree/events.ml`, `vtree/bonsai_gtk_vtree.ml`, `src/widgets/registry.ml`, `src/live_tree.ml`, `src/bonsai_gtk.ml(i)`, `test_lib/bonsai_gtk_test.ml(i)`, `test/test_widgets.ml`, `test/handle/test_handle.ml`, `test/live/live_text.ml`
- Create: `vtree/level_bar_mode.ml`, `src/widgets/w_drop_down.ml`, `src/widgets/w_level_bar.ml`

**Interfaces:**
- Produces:
  ```ocaml
  val drop_down
    :  ?key:Key.t -> ?attrs:Attr.t list
    -> ?enable_search:bool
    -> ?show_arrow:bool
    -> items:string list
    -> selected:int          (** [-1] for none *)
    -> unit
    -> t

  val level_bar
    :  ?key:Key.t -> ?attrs:Attr.t list
    -> ?min:float -> ?max:float
    -> ?mode:Level_bar_mode.t
    -> ?inverted:bool
    -> value:float
    -> unit
    -> t

  val on_selected_changed : int Handler.t -> Attr.t

  (* Bonsai_gtk_test.Action *)
  | Set_selected of string * int
  ```
- Consumes: `W.Drop_down.{new_from_strings,set_model,get_model,set_selected,get_selected,set_enable_search,set_show_arrow}`, `W.String_list.{new_,get_n_items,get_string}`, `Ocgtk_gio.Gio.Wrappers.List_model.from_gobject`, `Ocgtk_gtk.Gtk_constants.invalid_list_position`, `W.Level_bar.{new_,set_value,get_value,set_min_value,set_max_value,set_mode,set_inverted}`.

**Four rulings for DropDown:**

1. **`-1` is "nothing selected" in the vtree; `invalid_list_position` is at the boundary.** GTK's sentinel is `G_MAXUINT`, which OCaml sees as `4294967295` — not `-1`, and a number no application would write on purpose. `Node.drop_down ~selected:(-1)` translates to it on the way in and back from it on the way out, in `w_drop_down.ml` and nowhere else. Say so on the constructor: `-1` is the value, and any other out-of-range index is `Invalid_argument` at the constructor (it is checkable there — `items` is in hand).

2. **The model is rebuilt only when the items differ, and the identity short-circuit is on the *list*, not on the widget.** Rebuilding a `GtkStringList` resets the selection, closes an open popup and re-lays-out the button, so doing it on every frame would make the widget unusable. `update` compares the new `items` against the old node's — an ordinary prop comparison, which the patcher has already done via `Kind.equal_props`, so in practice `update` is only reached when *something* differs and the items comparison inside it is what decides whether the expensive half runs:

```ocaml
(* Rebuilt, not mutated: [GtkStringList] has [append]/[remove]/[splice], and computing a
   minimal splice from two string lists is a diff nobody has asked for. A whole-model
   replacement is one call and is correct; what makes it affordable is that it happens
   only when the items actually changed, which for the dropdowns a real app has (a fixed
   list of modes, a list of setlists that changes when the database does) is rare.

   Rebuilding resets [selected] to [invalid_list_position], so the selection is re-applied
   immediately after -- by [reassert], which the patcher runs right after [update] and
   which compares against the widget. Nothing else re-selects, and the ordering is the
   whole reason this is safe. *)
```

3. **`selected` is controlled and lives in `reassert`**, unlike the three containers' selections — because a dropdown's items are *props*, not children, so they exist by the time `reassert` runs. This is the one M2 selection that is not a fixup and the doc says why, in one sentence, so the asymmetry does not read as an oversight.

4. **`on_selected_changed` is a `notify::selected`.** `GtkDropDown`'s only signal is `activate`. Use `Signals.notify ~prop:"selected"` and `get_selected`; report `-1` for `invalid_list_position`. This is the pattern `w_switch.ml` and `w_stack.ml` established and it needs no new machinery — note in the impl that stavekeeper reaches for the identical raw connection today (`setlist_ui.ml:145-152`, with a comment saying ocgtk binds no such signal), and that this is the library's answer to it.

**LevelBar** has no signals and no controlled prop (`value` is set by the program, never by the user — there is no interaction). It is `create` + `update` + `Live_tree` arm + a gallery entry, and it is in this task to keep Task 10 the same size as its neighbours. Its one trap: `set_min_value`/`set_max_value`/`set_value` must be written in an order that never leaves min above max, so write `min` and `max` before `value`, and when both bounds change write whichever moves *outward* first. Bracket in `batch`.

- [ ] **Step 1: Write the failing tests**

`test/test_widgets.ml`:

```ocaml
let%expect_test "drop down rejects an out-of-range selection at the constructor" =
  Expect_test_helpers_core.require_does_raise (fun () ->
    Node.drop_down ~items:[ "a"; "b" ] ~selected:2 ());
  [%expect {| |}];
  (* [-1] is the one out-of-range value that means something. *)
  print_s [%sexp (Node.drop_down ~items:[ "a"; "b" ] ~selected:(-1) () : Node.t)];
  [%expect {| |}]
;;
```

`test/live/live_text.ml` — append:

```ocaml
  (* 1. A dropdown, its items, and which is selected. *)
  (* 2. Changing the *selection* alone must not rebuild the model: take the model's GObject
        before and after and assert [Gobject.same]. Without this, "rebuilt only when the
        items differ" is a comment rather than a claim. *)
  (* 3. Changing the items rebuilds the model *and* re-applies the selection in the same
        frame, so the widget is never left showing [invalid_list_position]. Assert
        [get_selected] after the patch, not just the item list.
  (* 4. The declined selection: the user picks item 2, the model re-renders 0. *)
  (* 5. The reentrancy case: [set_selected] emits [notify::selected] synchronously inside
        the patch, and a model rebuild emits it too. [scheduled] unchanged across both. *)
  (* 6. A level bar's three-value write leaves min <= max at every intermediate step --
        assert by writing a value/min/max triple that would be invalid in the wrong order
        and checking GTK logged nothing (the dump is the check: a clamped value shows). *)
```

Case 2 is the one that would silently pass with a wrong implementation, so it goes first.

- [ ] **Step 2–5: implement.** The model rebuild:

```ocaml
let set_items (d : W.Drop_down.t) items =
  let sl = W.String_list.new_ (Some (Array.of_list items)) in
  (* [String_list.t]'s row is [`string_list | `object_] and [List_model.t]'s is
     [`list_model], so a [:>] coercion does not typecheck. [from_gobject] is the checked
     interface cast -- the same idiom as [Editable.from_gobject] in w_entry.ml -- and it
     raises [Failure] rather than corrupting anything if handed the wrong type. *)
  W.Drop_down.set_model d (Some (Ocgtk_gio.Gio.Wrappers.List_model.from_gobject sl))
;;
```

and the sentinel translation:

```ocaml
(* GTK's "nothing selected" is G_MAXUINT, which OCaml sees as 4294967295. The vtree says
   [-1], because that is the number an application writes and because a positive sentinel
   larger than any real index would compare wrongly against a bounds check somewhere. The
   translation is here and only here. *)
let to_gtk = function
  | -1 -> Ocgtk_gtk.Gtk_constants.invalid_list_position
  | n -> n
;;

let of_gtk n = if n = Ocgtk_gtk.Gtk_constants.invalid_list_position then -1 else n
```

- [ ] **Step 6: `Live_tree`** — `"GtkDropDown"` printing the item list (read back through `get_model` → `List_model.get_object` → `String_object.get_string`, or through the `GtkStringList` if the cast is cheaper — check which the binding makes easier) and `selected`; `"GtkLevelBar"` printing `value`, `min`/`max` when not `0.`/`1.`, `mode` when `DISCRETE`, `inverted`.

Reading the items back is worth the trouble: without it the golden shows a dropdown button and nothing about what is in it, and case 3 above has nothing to assert against.

- [ ] **Step 7: Run, read, promote, gate, commit**

```bash
./scripts/ci.sh
dune fmt 2>/dev/null; git add vtree src test test_lib
GIT_EDITOR=true git commit -F - <<'MSG'
DropDown over a rebuilt string model, and LevelBar

A GtkDropDown's items live in a separate GObject, so changing them means
replacing the model -- which resets the selection, so the selection is
re-applied by [reassert] on the same frame and the widget is never left showing
nothing. The model is rebuilt only when the items differ, which a live test
asserts by GObject identity rather than by comment.

"Nothing selected" is -1 in the vtree and G_MAXUINT at the boundary, translated
in one place. Selection changes arrive as notify::selected, GtkDropDown having
no signal of its own -- the same raw connection stavekeeper makes by hand today.

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01Sg3Ci8U8kUKR8C3PL1pNSs
MSG
```

**Review focus:** that the model-identity test exists and would fail on an unconditional rebuild; that the selection is re-applied on the same frame as a rebuild, not the next; that `-1`↔`invalid_list_position` appears in exactly two functions; that the level bar's writes cannot transiently invert its bounds.

---

### Task 11: Calendar and EditableLabel — two widgets whose GTK API is not the one you expect

Both are small; both have an API shape that will send an implementer down a wrong path if the plan does not say so first.

**Files:**
- Modify: `vtree/attr.ml(i)`, `vtree/kind.ml(i)`, `vtree/node.ml(i)`, `vtree/defaults.ml`, `vtree/events.ml`, `src/widgets/registry.ml`, `src/live_tree.ml`, `test_lib/bonsai_gtk_test.ml(i)`, `test/test_widgets.ml`, `test/handle/test_handle.ml`, `test/live/live_text.ml`
- Create: `src/widgets/w_calendar.ml`, `src/widgets/w_editable_label.ml`

**Interfaces:**
- Produces:
  ```ocaml
  val calendar
    :  ?key:Key.t -> ?attrs:Attr.t list
    -> ?show_day_names:bool -> ?show_heading:bool -> ?show_week_numbers:bool
    -> ?marked_days:int list
    -> date:Date.t
    -> unit
    -> t

  val editable_label
    :  ?key:Key.t -> ?attrs:Attr.t list
    -> ?editing:bool
    -> text:string
    -> unit
    -> t

  val on_day_selected : Date.t Handler.t -> Attr.t
  val on_editing_changed : bool Handler.t -> Attr.t

  (* Bonsai_gtk_test.Action *)
  | Select_day of string * Date.t
  | Set_editing of string * bool
  ```
- Consumes: `W.Calendar.{new_,set_day,get_day,set_month,get_month,set_year,get_year,set_show_day_names,set_show_heading,set_show_week_numbers,mark_day,unmark_day,clear_marks,on_day_selected}`, `W.Editable_label.{new_,start_editing,stop_editing,get_editing}`, `W.Editable.{from_gobject,set_text,get_text,get_position,set_position,on_changed}`.

**Calendar: `get_date` and `select_day` do not exist, and neither does GDateTime.** Both take or return `GLib.DateTime` in C and the generator dropped them; there is no `GLib-2.0.gir` in the checkout at all, so there is no way to build one. What *does* exist is the three integer properties, and they are enough:

```ocaml
(* [gtk_calendar_get_date] and [select_day] are not bound -- they trade in GDateTime, which
   this binding does not have at all -- so the date is read and written as three integer
   properties. Two things about them:

   GTK's [month] property is ZERO-BASED (0 = January) while [day] is one-based. That
   asymmetry is GTK's, it is the kind of thing that produces an off-by-one nobody notices
   until December, and it stops here: [Node.calendar] takes a [Date.t] and this is the only
   code that ever sees the raw month.

   The three writes are not atomic. Writing day=31 and then month=1 addresses February 31st
   in between, which GTK normalises somewhere the caller cannot see. Write year, then
   month, then day -- month before day means the day is validated against the right month's
   length -- and bracket all three in [Widget_impl.batch] so the [day-selected] each one
   emits is a single notification at the end rather than three. The [in_patch] guard drops
   them either way; the bracket is about not doing three round trips through GTK's
   notify machinery. *)
let write_date (c : W.Calendar.t) date =
  W.Calendar.set_year c (Date.year date);
  W.Calendar.set_month c (Month.to_int (Date.month date) - 1);
  W.Calendar.set_day c (Date.day date)
;;

let read_date (c : W.Calendar.t) =
  Date.create_exn
    ~y:(W.Calendar.get_year c)
    ~m:(Month.of_int_exn (W.Calendar.get_month c + 1))
    ~d:(W.Calendar.get_day c)
;;
```

`~date` is controlled, compared through `Date.equal read_date`, in `reassert` (a calendar has no children, so no fixup). `on_day_selected` is a `Read_back` spec whose `fire` calls `read_date` — GTK's `day-selected` carries no payload and fires on all three property changes, which is exactly what a read-back spec is for.

`~marked_days` is a plain `int list` of days-of-month, applied by `clear_marks` then `mark_day` per entry when the list differs. It is not controlled (the user cannot mark a day) and it is in M2 because a calendar with no marks is a date picker, and a date picker is what `Node.calendar` would otherwise be for.

**EditableLabel: `set_text` does not exist on it, and `set_editing` does not exist at all.**

```ocaml
(* [GtkEditableLabel] binds four methods and no signals: [new_], [start_editing],
   [stop_editing] and [get_editing]. Text goes through the [GtkEditable] interface, exactly
   as [w_entry.ml] reaches an entry's -- [W.Editable.from_gobject] is a checked cast, and
   [GtkEditableLabel] implements [GtkEditable], so [set_text]/[get_text]/[on_changed] all
   work through it and the [changed] connection names the [GtkEditable] as [w_entry.ml]'s
   does.

   [editing] is READ-ONLY in GTK: there is no [set_editing]. Making it a controlled prop
   therefore means [start_editing ()] to enter and [stop_editing ~commit:true] to leave,
   which are not symmetric with each other and are certainly not a property write. In
   particular [stop_editing false] would *discard* what the user typed, so committing is
   the only defensible choice for a declarative library: the model that set [~editing:false]
   is saying "stop editing", not "throw away the edit", and the edit reaches it through
   [Attr.on_changed] either way.

   Observed with [notify::editing] + [get_editing], there being no signal. *)
```

`~text` is controlled through `Editable` with the same save-and-restore-position dance as `w_entry.ml` — reuse `W_entry.set_text_if_needed` directly rather than copying it (it takes a `W.Editable.t` and is already exported from the module; if it is not exported, export it, and note in `w_entry.ml` that it now has a second caller).

`~editing` is controlled too, and its `reassert` compares `get_editing` against the prop. Note the ordering hazard: entering edit mode selects the text, and a `reassert` that writes the text *after* calling `start_editing` would collapse that selection. Write text first, then editing — the reverse of what reads naturally.

- [ ] **Step 1: Write the failing tests**

`test/test_widgets.ml` — constructors, plus:

```ocaml
let%expect_test "calendar takes a Date.t, not GTK's zero-based month" =
  print_s [%sexp (Node.calendar ~date:(Date.of_string "2026-01-15") () : Node.t)];
  [%expect {| |}]
;;
```

`test/handle/test_handle.ml` — a date picker whose model rejects weekends, which is the declined-edit shape for a calendar and which no other test in the suite has.

`test/live/live_text.ml` — append:

```ocaml
  (* 1. A calendar showing a date, and January in particular -- the month whose zero-based
        index is 0 and which therefore looks right even when the conversion is wrong.
        Assert December too, in the same dump. *)
  (* 2. The declined date: click a day by hand ([set_day]), render the same model date, and
        assert it went back. *)
  (* 3. Marked days added and removed. *)
  (* 4. An editable label's text, and its editing state entered and left. Assert that
        leaving edit mode with ~editing:false keeps the text the user typed rather than
        reverting it -- which is [stop_editing true] and is the ruling above. *)
  (* 5. The reentrancy case for both: a programmatic write emits [day-selected] /
        [notify::editing] inside the patch, [scheduled] unchanged. *)
```

Case 1's December assertion is the whole defence against the off-by-one, and case 4 is the whole defence against `stop_editing false`.

- [ ] **Step 2–6: implement, run, promote, gate.**

`Live_tree`: `"GtkCalendar"` printing `date` as `YYYY-MM-DD` **through `read_date`, not through the raw properties** — a dump that printed the raw zero-based month would make a wrong conversion look right. `"GtkEditableLabel"` printing the text (via `Editable.get_text`) and `editing` when true.

- [ ] **Step 7: Commit**

```bash
./scripts/ci.sh
dune fmt 2>/dev/null; git add vtree src test test_lib
GIT_EDITOR=true git commit -F - <<'MSG'
Calendar over three int properties, and EditableLabel through GtkEditable

Neither widget has the API you would look for. gtk_calendar_get_date and
select_day trade in GDateTime, which this binding does not have anywhere, so
the date is the year/month/day properties -- and GTK's month is zero-based
while its day is not, an asymmetry that now stops inside w_calendar.ml because
Node.calendar takes a Date.t.

GtkEditableLabel binds four methods and no signals: text goes through the
GtkEditable interface (as an entry's does), and [editing] is read-only, so the
controlled prop is start_editing / stop_editing ~commit:true. Committing rather
than discarding is the only defensible reading of a model that renders
~editing:false.

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01Sg3Ci8U8kUKR8C3PL1pNSs
MSG
```

**Review focus:** that a December date round-trips (the zero-based month); that `Live_tree` prints the date through the same conversion the impl uses and that some test would still catch a conversion that is wrong in both places (case 1's December assertion, compared against the `Date.t` the node carried); that leaving edit mode commits; that `reassert` writes text before editing.

---

### Task 12: `Expert.embed` — a bonsai tree inside a container someone else owns

The entry point that makes the stavekeeper port incremental. `Bonsai_gtk.start` is unchanged and stays the answer for an application that is bonsai_gtk all the way down.

**Files:**
- Modify: `src/bonsai_gtk.ml`, `src/bonsai_gtk.mli`, `src/driver.ml`, `src/driver.mli`, `src/patcher.ml`, `test/live/dune`
- Create: `src/embed.ml`, `src/embed.mli`, `test/live/live_embed.ml`, `test/live/expected_embed.txt`

**Interfaces:**
- Produces:
  ```ocaml
  (* Bonsai_gtk.Expert *)
  module Embedded : sig
    type t
    val widget : t -> Widget.t
    val frame : t -> unit
    val schedule_event : t -> unit Ui_effect.t -> unit
    val broken : t -> bool
    val stop : t -> unit
  end

  val embed
    :  ?time_source:Bonsai.Time_source.t
    -> ?optimize:bool
    -> ?target_frames_per_second:float
    -> host:Widget.t
    -> (local_ Bonsai.graph -> Node.t Bonsai.t)
    -> Embedded.t
  ```
- Changed: `Driver.create` gains `?root_may_be_window:bool` (or equivalent — see the ruling), and `Patcher.mount`'s `~is_root` grows a meaning.

**Six questions the entry point has to answer, and the answers this plan rules on:**

1. **What is a legal root?** For `start`, exactly a `Node.window` (spec §11). For `embed`, exactly **not** a `Node.window`: a `GtkWindow` is a toplevel and cannot be parented, so embedding one would produce the GTK critical §11 exists to prevent. So the root check inverts rather than relaxes, and the message says which entry point the caller wanted:

```
Bonsai_gtk.embed: the root node is a Node.window, but an embedded tree is
parented into ~host and a GtkWindow is a toplevel that cannot be parented. Use
Bonsai_gtk.start for a tree that owns its window, or make the root a container.
```

The below-the-root rule is unchanged: a `Node.window` anywhere but the root is still `Invalid_argument`, and for an embedded tree that means anywhere at all. Implement it as a `root_kind : [ \`Window | \`Not_window ]` argument to `Driver.create` rather than a bool, so the two messages are written once each and neither entry point can pass the wrong one silently.

2. **Who parents the widget?** The caller. `embed` mounts the tree and hands back the root widget through `Embedded.widget`; the host is *not* written to. This is deliberate and is what makes `embed` composable with a `GtkStack` (`add_named` returns a page), a `GtkBox` (`append`), a `GtkNotebook` (`insert_page`) and a `GtkListBox` (`insert`) alike, none of which is `set_child`. **Then why does `embed` take `~host` at all?** Because the driver needs a widget to hang the frame tick's lifetime on and to answer "am I still in a tree" — and because a future `Attr` that names an ancestor (a search entry's key-capture widget, a mnemonic target) will need it. If Step 3 finds neither use is real yet, **drop `~host` and say so in the report**: an unused argument in a new public entry point is worse than adding it in M3.

3. **What drives frames?** Not `Bonsai_gtk.start`'s `GtkApplication`, which the embedder owns. `embed` installs its own tick with `Driver.start_tick ~fps:target_frames_per_second` (default 60) on the GLib main loop the embedder is already running, and `Embedded.frame` lets a test drive by hand. If there is no main loop running, the tick simply never fires and `Embedded.frame` is the only path — which is exactly what `test/live/live_embed.ml` does, and it is worth stating because it is how a headless-ish live test of an embedded tree works.

4. **When does `require_specs` run?** Unchanged — at mount and at each patch, from the patcher, for every node including the root. Nothing about embedding changes what a node may carry.

5. **What does teardown do?** `Embedded.stop` tears the widget tree down and invalidates the Bonsai observers, exactly as `Driver.stop` does — **but it does not unparent the root widget**, because it did not parent it. The embedder removes it from its container, before or after `stop`, and the mli says so with the order that is safe (either; the widget survives `stop` as a plain unparented `GtkWidget` and the embedder may drop it on the floor, since nothing holds a reference). Stavekeeper's `shell.ml:87` already does `t.stack#remove viewer.widget` after `viewer.teardown ()`, which is the shape.

6. **What happens if the embedder destroys the host first?** GTK destroys the subtree with it, and the shadow tree then describes widgets that are gone. There is no way to detect this cheaply and no good behaviour to fall back on, so: `Embedded.stop` must be called before the host goes away, and calling a frame afterwards is undefined in the way any use-after-destroy is. Say that in the mli, plainly, as the one obligation embedding puts on the caller that `start` does not. If `Widget.on_destroy` is bound (check — the M2 signature survey says `on_destroy` exists on `Widget`), connect to the *root* widget's `destroy` and mark the embedded driver broken from it; that turns undefined behaviour into a no-op and is worth the one connection. Do that if it is a handful of lines, and say in the report which you did.

- [ ] **Step 1: Write the failing test** (`test/live/live_embed.ml`)

```ocaml
(* An embedded tree inside a container the test owns, which is what stavekeeper's Shell
   is: a GtkStack that holds pages, none of which is a window. *)
let () =
  ignore (Ocgtk_gtk.GMain.init () : string array);
  let window = W.Window.new_ () in
  let stack = W.Stack.new_ () in
  W.Window.set_child window (Some (stack :> Widget.t));
  let clicks = ref 0 in
  let app (graph @ local) =
    let n, set_n = Bonsai.state 0 graph in
    let%arr n and set_n in
    (* No Node.window: the root is a box, which is what an embedded tree must be. *)
    Node.box ~orientation:Vertical
      [ Node.label (sprintf "count %d" n)
      ; Node.button ~attrs:[ Attr.on_clicked (set_n (n + 1)) ] ~label:"+" ()
      ]
  in
  let embedded = Bonsai_gtk.Expert.embed ~host:(stack :> Widget.t) app in
  ignore (W.Stack.add_named stack (Bonsai_gtk.Expert.Embedded.widget embedded) (Some "page")
          : W.Stack_page.t);
  print_s (Live_tree.dump (window :> Widget.t));
  (* A frame driven by hand, because this test runs no main loop. *)
  Bonsai_gtk.Expert.Embedded.frame embedded;
  print_s (Live_tree.dump (window :> Widget.t));
  (* The root really is inside the stack, not a sibling toplevel: the dump above says so
     structurally, which is the point of dumping from the *window* rather than from the
     embedded root. *)
  ...
  (* A window root is refused, with a message naming [start]. *)
  (match Bonsai_gtk.Expert.embed ~host:(stack :> Widget.t)
           (fun (_ : local_ Bonsai.graph) -> Bonsai.return (Node.window ~title:"no" (Node.label "x")))
   with
   | _ -> printf "window root: NO RAISE\n"
   | exception Invalid_argument m -> printf "window root: %s\n" m);
  (* Teardown leaves the host alone. *)
  Bonsai_gtk.Expert.Embedded.stop embedded;
  printf "after stop, stack still has %d children\n" (n_children stack);
  W.Stack.remove stack (...);
  printf "removed cleanly\n"
```

The `after stop` line is the interesting one: it must be `1`, because `stop` does not unparent. If the implementation unparents, this catches it.

- [ ] **Step 2: Run to verify failure** — unbound `Bonsai_gtk.Expert.embed`.

- [ ] **Step 3: `src/driver.ml(i)`** — the root-kind argument, and nothing else. `check_root` gains the two messages. Confirm that `Driver.create`'s existing callers (there is one, in `bonsai_gtk.ml`) pass `` `Window ``.

- [ ] **Step 4: `src/embed.ml(i)`** — thin. It is `Driver.create` + `Driver.frame` (once, to mount) + `Driver.start_tick`, wrapped in a record that exposes four of the driver's operations and hides `root_widget` (whose `option` is meaningless once the first frame has run) behind a total `widget`.

```ocaml
(** A Bonsai computation rendering into a widget the caller parents.

    The counterpart to {!Bonsai_gtk.start}, for an application that already has a GTK main
    loop and a window and wants a Bonsai-rendered subtree inside it — porting a screen at
    a time rather than all at once, or embedding a declarative panel in an imperative app.

    Three things differ from {!Bonsai_gtk.start}, and all three follow from "the caller owns
    the window":

    - The root node must {i not} be a [Node.window]: the result is parented into an
      existing container, and a [GtkWindow] is a toplevel that cannot be parented. (A
      [Node.window] below the root is rejected as it always is, which for an embedded tree
      means anywhere.)
    - Nothing is parented for you. {!widget} is the root, and the caller puts it wherever
      its container puts children — [set_child], [append], [add_named], [insert_page]. That
      is why there is no "attach" here: there is no one call that covers them.
    - {!stop} tears the tree down but does not unparent it. Remove it from your container
      yourself, before or after; the widget survives {!stop} as an ordinary unparented
      widget and may then be dropped.

    The one obligation embedding adds: {!stop} before the host is destroyed. GTK destroys a
    subtree with its parent, and a frame after that would diff against widgets that are
    gone. [embed] connects to the root's [destroy] and marks itself broken if it happens
    anyway, so the failure is a no-op rather than a crash — but the frames between the
    destroy and the next tick are wasted and the effects they queue are dropped. *)
```

- [ ] **Step 5: `src/bonsai_gtk.ml(i)`** — `Expert` gains `module Embedded` and `val embed`, with the mli doc pointing at `Embed`'s. Keep `Expert.Driver` exposed: `embed` is a convenience over it, not a replacement, and the existing live tests use `Driver` directly.

- [ ] **Step 6: Run, read, promote, gate, commit**

```bash
./scripts/ci.sh
dune fmt 2>/dev/null; git add src test
GIT_EDITOR=true git commit -F - <<'MSG'
Expert.embed: a Bonsai subtree inside a container the caller owns

The entry point that makes an incremental port possible -- an existing GTK app
with its own main loop and window can render one page with Bonsai and keep the
rest imperative. The root must not be a Node.window (an embedded tree is
parented, and a GtkWindow cannot be), nothing is parented for the caller
(add_named, append and set_child are not one call), and stop tears the tree
down without unparenting it.

Bonsai_gtk.start is unchanged.

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01Sg3Ci8U8kUKR8C3PL1pNSs
MSG
```

**Review focus:** that the window-root rejection names `start` in its message; that `stop` does not unparent and there is a test that would notice; that `~host` is used for something or was dropped; that the destroy-the-host-first obligation is in the mli and not only here; that `Driver`'s existing behaviour is unchanged for `start` (its live tests must not diff).

---

### Task 13: The gallery, and a headless sweep over every M2 widget

M1's Task 10, repeated for M2's eight widgets and five attrs. Two nets under the per-task tests: a headless sweep that names every constructor once, and a runnable window that shows them.

**Files:**
- Modify: `examples/gallery.ml`, `test/handle/test_gallery.ml`, `test/live/live_events.ml`
- Create: nothing

- [ ] **Step 1: `test/handle/test_gallery.ml`** — extend the single tree with every M2 constructor and every M2 attr, and print its sexp. What this catches that the per-task tests do not: a constructor whose defaults changed under it, a `[@sexp_drop_if]` that drops a value the caller asked for (the M1 backlog's "three expect tests pass props the sexp then drops"), and a kind nobody added to `Events` or `Registry`.

Add the assertion M1's file could not make, now that `Attr.Name.all` exists:

```ocaml
(* Every attr constructor appears somewhere in this tree. Not "every attr is exercised" --
   the sexp cannot say that -- but "no attr was added and then forgotten", which is the
   failure this file is a net under. The list is derived from [Attr.Name.all], so a new
   name fails here until someone puts it in the gallery. *)
let%expect_test "the gallery names every attr" =
  let used = names_in_tree gallery_tree in
  let missing =
    List.filter Attr.Name.all ~f:(fun n -> not (List.mem used n ~equal:Attr.Name.equal))
  in
  print_s [%sexp (missing : Attr.Name.t list)];
  [%expect {| () |}]
;;
```

Some names legitimately cannot appear (`Grid_cell` only inside a grid, `Row_selectable` only inside a list box) — but they *can* appear, in the right container, and the gallery has one of each. If a name genuinely cannot be placed, exempt it explicitly by name with a comment rather than weakening the check.

- [ ] **Step 2: `examples/gallery.ml`** — a section per M2 widget. Keep the existing structure (one `Node.frame`-labelled block per family) and add: **Lists** (a list box with header/normal/placeholder rows and a live selection count; a flow box of eight coloured cards with the grid/list toggle stavekeeper has), **Text** (a text view with a word-wrap toggle; an editable label), **Pickers** (a dropdown driving the text view's wrap mode, a calendar, a level bar fed by a scale), **Notebook** (three pages with a reorder button), and **Input** (a box with `Attr.on_key_pressed` that shows the last key, and a card with `Attr.on_click` that shows the last button and modifiers).

That last section is the only *runnable* demonstration that the controllers work end to end, given the live tests may only be able to assert attach/detach (Task 4, Step 1). It is therefore load-bearing rather than decorative — say so in a comment, and check it by hand under a real display before the milestone closes (`docs/m2-backlog.md` carries "real-display click-through of the gallery" forward from M1 either way).

- [ ] **Step 3: `live_events.ml`'s `all_kinds`** — add the eight new kinds and bump the count.

- [ ] **Step 4: `./scripts/ci.sh`** — the gallery smoke run already covers `examples/gallery.exe`; confirm it still exits 124 (came up and stayed up) rather than crashing, and read stderr for `Gtk-CRITICAL` even though the gate does not fail on one.

- [ ] **Step 5: Commit.**

**Review focus:** that the attr-coverage check has no blanket exemption; that the gallery's input section actually reacts (run it); that no expected file in `test/handle/` was promoted without being read.

---

### Task 14: ocgtk fork changes, prepared locally and not pushed

Everything M2 wanted from the binding and did not have, collected into one commit series on the fork, listed, and **left for the user to decide about**. An agent does not push the fork.

**Files:** none in this repository, except `docs/upstream/README.md` if it has a list to extend.

**Context.** `ocgtk-pin.json` pins `dlobraico/ocgtk` at `d98d9397`. The fork's six commits are all memory/ownership fixes plus `Style_display`; **there is no nullable-setter patch**, so every item below is new work. `.ocgtk-src/` is the checkout (gitignored, created by `scripts/setup-switch.sh`). `docs/upstream/README.md` describes the upstreaming process and says six PRs are open as drafts.

**The list, in the order they should be committed:**

1. **`Widget.set_name : t -> string option -> unit`.** From `docs/m1-backlog.md`: upstream binds only `string`, so `Unset Widget_name` cannot write NULL and restores `""` instead. `""` and NULL differ to GTK's CSS matcher.
2. **`Stack_page.set_title : t -> string option -> unit`.** A page that loses its `Attr.page_title` currently gets `""`, which is a blank *clickable* switcher button rather than no button (M1 containers M1).
3. **`Password_entry.get_placeholder_text : t -> string option`** and **`set_placeholder_text : t -> string option -> unit`.** The getter is a **crash**, not a wrong value: the C function returns NULL when unset and the stub copies it. `Live_tree` works around it by reading the property through a GValue; the three entry kinds could share one rule if the setter were nullable too.
4. **Whatever M2 discovered.** Fill this in from the task reports rather than from this plan — the candidates the signature survey suggests are `List_box.set_header_func` / `set_sort_func` / `set_filter_func` (the generator skips every GIR callback-taking method, so this is a generator change, not a binding one, and is a much larger piece of work than 1–3), a `GLib.DateTime` binding (there is no `GLib-2.0.gir` in the checkout at all, so this is "add a namespace"), and `gdk_keyval_name`/`from_name` (namespace-level functions, which the generator emits none of). **None of these is a small patch**, and none is needed by M2 — the plan routed around all three. List them as *findings*, with the workaround M2 used, and let the user decide whether any is worth a milestone of its own.

- [ ] **Step 1: Confirm the checkout is clean and at the pin**

```bash
cd ~/src/bonsai_gtk/.ocgtk-src
git status --porcelain     # expect empty
git log --oneline -1       # expect d98d9397
```

A dirty checkout means someone (or a previous run of this task) already started; read it before adding to it. Do **not** `rm -rf` and re-clone — `scripts/setup-switch.sh`'s reinstall stamp keys on the rev, and the backlog already notes it does not notice a dirty tree.

- [ ] **Step 2: Find how nullability is expressed**

The generator reads GIR `nullable=` annotations; these four are cases where the C API takes or returns NULL and the annotation is missing or ignored. Before writing anything, determine which:

```bash
cd ~/src/bonsai_gtk/.ocgtk-src
grep -n 'set_name' gir/Gtk-4.0.gir | head -20
grep -rn 'nullable' gir_gen/ | head -20
```

If the GIR *does* say nullable and the generator ignored it, the fix is in the generator and covers all four at once — much better, and worth saying so. If the GIR does not say it, the fix is either a GIR override table (check whether `gir_gen` has one) or a hand-patched stub. **Report which before writing code**: a generator fix and a hand patch are different sizes and different upstreaming stories, and ocgtk's own history (fork commit `2ed607d2` hand-patches stubs that commit `3322e3b6`'s generator later emits) says the maintainer prefers regeneration.

- [ ] **Step 3: One commit per item, on a topic branch**

```bash
git switch -c bonsai-gtk-m2-nullable
# ... item 1 ...
git commit -F - <<'MSG'
gtk: Widget.set_name accepts NULL

gtk_widget_set_name(w, NULL) resets the widget to its class default name, which
is distinguishable from "" by the CSS matcher. The generated binding takes a
plain string, so a caller that wants to *unset* the name cannot.

MSG
```

Follow ocgtk's own commit style (read `git log` in the checkout), not this repository's — and **do not add the bonsai_gtk `Co-Authored-By`/`Claude-Session` trailer to fork commits** unless the fork's existing commits carry one. Check.

- [ ] **Step 4: Verify locally, without moving the pin**

```bash
cd ~/src/bonsai_gtk/.ocgtk-src && dune build @all && dune runtest
cd ~/src/bonsai_gtk && opam reinstall ocgtk       # spec §2.1's missing step
./scripts/ci.sh                                    # must still pass, unchanged
```

`scripts/ci.sh` must pass **without any bonsai_gtk change**: these are additive binding changes and nothing in M2 depends on them (that is R5, and it is why this task is last among the code tasks). If something in bonsai_gtk breaks, a signature changed rather than being added, and that is a compatibility problem to report rather than to absorb.

- [ ] **Step 5: Do not push. Do not move the pin.** Report:

- the branch name and `git log --oneline` of the new commits, in the checkout;
- for each item: whether it was a generator fix or a hand patch, and why;
- the M2 findings from item 4 with their workarounds;
- the exact commands the user would run to push and re-pin (`git push`, then `nix-prefetch-github` or whatever `ocgtk-pin.json`'s hash comes from — read `flake.nix` and `scripts/setup-switch.sh` for the real procedure and quote it), so that accepting the work is one paste.

**Review focus:** that `scripts/ci.sh` passes with the fork changes *and* would pass without them; that nothing was pushed; that the report is specific enough for the user to act on without re-deriving anything.

---

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
