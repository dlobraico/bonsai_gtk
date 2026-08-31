# bonsai_gtk M3 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Grow M2's lists-and-text catalogue into the spec's **M3 — chrome & popups** (§7): HeaderBar, ActionBar, Popover, MenuButton + `Node.menu` (GMenu model + GAction routing), AlertDialog/FileDialog effects, `Node.windows` multi-window, `Attr.shortcut` (GtkShortcutController) — plus the §8 effects (`after`, `on_idle`, `Clipboard.set_text`, `Alert_dialog.show`, `File_dialog.open_file/save_file/select_folder`, `Window.present`) and the display-wide CSS wiring the fork's `Style_display` stub has been waiting for. Land the "Do first in M3" items from `docs/m2-backlog.md` before any widget, because every widget added after them pays their cost twice, and split the files the backlog says M3 would otherwise grow past readability.

At the end of M3, stavekeeper's `dialog.ml` (a transient modal window with CAPTURE Escape and a Ctrl+Return default action — 15 `shell` call sites across 11 modules), `palette.ml` (a transient modal window over a list box, keyboard-driven), the viewer's ⋮ menu (`viewer_window.ml:4252-4542` — one MenuButton, five submenus, two sections, ~28 SimpleActions with display-only accels, all registered into `Command.Registry`), `shell.ml`'s multi-window pop-out (`shells` list, close-request → quit-on-last), and the delete-confirmation dialogs in `edit_dialog.ml`/`pieces_dialog.ml` (which become one `Alert_dialog.show` effect each) are all expressible. What is still missing is named in "What M3 still does not give the stavekeeper port" below, and repeated in the README's Limitations section by Task 13.

**Architecture:** Unchanged in shape from M2, extended in five places.

- `bonsai_gtk.vtree` (`vtree/`, ocgtk-free) gains the pure data the chrome needs: **`Menu`** (a declarative menu tree — items name actions, they do not carry handlers, so a menu is an equalable, sexpable *prop*), **`Action_spec`** (name + enabled + optional toggle/radio state + handler — handlers, so actions are an *attr*), **`Trigger`** (a keyval + modifiers pair for shortcuts, built from M2's `Keyval` and `Modifiers` so no GTK parse syntax enters the vtree), **`Click_response`** (the click twin of M2's `Key_response`, closing the "on_click cannot claim the sequence" backlog item), and the new kinds' enum/props modules. `Events.Family` gains a fourth family, **`Shortcut`**.
- `bonsai_gtk` (`src/`) gains **`Actions`** — the `Controllers`-shaped module that owns one `GSimpleActionGroup` per node carrying `Attr.actions`, inserts it with `Widget.insert_action_group`, keeps `enabled`/`state` controlled, and routes `SimpleAction::activate` through the trampoline discipline; **a window registry** in `Patcher.ctx` (`ctx.windows`, the `ctx.stacks` shape keyed by `Key.t`) that resolves `~transient_for` in the fixup pass and backs the `Window.present` effect; and five `src/widgets/w_<name>.ml` files (`w_header_bar`, `w_action_bar`, `w_popover`, `w_menu_button`, `w_windows`).
- `Driver` learns a root that is not one widget: `Kind.Windows` is a keyed **List** of `Node.window` children whose impl parents nothing (each window is a toplevel; `ctx.on_window_created` presents it and the application owns it), so the whole of M2's list reconciliation — keys, `Child_keys`, `move = None` — carries over to windows unchanged. `Expert.Driver.root_widget` answers `None` for a `Windows` root, which is the API break `docs/m2-backlog.md` line 220 predicted.
- `Gtk_effect` grows from one member (`quit`) to the §8 list, on the same one-process-global pattern `quit` established: `Loop.start` (and `Embed.create`, where meaningful) registers the hooks an effect needs — a frame-requester for the async ones, a window lookup for `Window.present`, the active window for dialog transience — and an effect performed outside `start` logs and resolves inert rather than raising.
- **Window close becomes a controlled prop in all but name.** The runtime connects `close-request` on every window it mounts and always answers "handled": the X button is a *request*, `Attr.on_close_request`'s effect is the model's chance to act on it, and the window actually closes when the model stops rendering its node — exactly the declined-edit discipline §6.5 applies to text. A window with no handler vetoes the close and reports once through `ctx.report`.

`bonsai_gtk_test` (`test_lib/`) stays ocgtk-free and grows the menu/action/shortcut/window validation plus six actions (`Activate_action`, `Open_popover`, `Close_popover`, `Close_request`, `Fire_shortcut`, `Focus_contains`).

**Tech Stack:** Unchanged. OxCaml `ocaml-variants.5.2.0+ox`, dune ≥ 3.17, Bonsai `v0.18~preview.130.106+341` (Cont API), `bonsai.driver`, `bonsai_test`, `virtual_dom.ui_effect`, ocgtk 0.1~preview2 (GTK 4.22, fork pin `72cc75f2` in `ocgtk-pin.json`) — dune libraries `ocgtk.gtk`, `ocgtk.gio`, `ocgtk.gdk`, `ocgtk.pango`, `ocgtk.common`. M3 adds no new dune library: `ocgtk.gio` already carries `Menu`/`Menu_item`/`Simple_action`/`Simple_action_group`/`Action_map`/`File`, `ocgtk.gdk` carries `Clipboard`/`Display`, and the display-wide CSS stub is `Ocgtk_gtk.Style_display` (top-level in `ocgtk.gtk`, *not* under `Gtk.Wrappers`). Nix flake for the dev shell, `xvfb-run` + `xdotool` for live tests.

**Spec:** `docs/superpowers/specs/2026-08-28-bonsai-gtk-design.md`
**Branch:** `m3`, from `main`.

## Pre-flight corrections (2026-08-31, override the task text below)

The scout's report is `.superpowers/sdd/2026-08-31-bonsai-gtk-m3/preflight-report.md`. Every fact-table row CONFIRMED against the pin `72cc75f2`; all eight runtime questions answered with throwaways under `xvfb-run -a`. Where a task below disagrees with this section, this section wins.

1. **Task 6 — action groups must be inserted before the widget is rooted.** `insert_action_group` on a widget already rooted in a window resolves for *activation* but never binds the `PopoverMenu`'s item tracker: the menu item renders permanently insensitive and `Simple_action.set_enabled` does nothing to it (deterministic, 3/3). Inserted any time *before* rooting, everything works — including live greying of an **open** popover, in every ordering tested. So `src/actions.ml` inserts groups at create/mount; an `Attr.actions` first *appearing* on an already-mounted node must force the menu button to re-set its menu model (or the task documents and tests the limitation — implementer states which, reviewer checks it).
2. **Task 10 + flake — `FileChooserNative` needs GSettings schemas.** Under the current dev shell it aborts the process (`GLib-GIO-ERROR: No GSettings schemas installed`). Fix once in `flake.nix`: point `GSETTINGS_SCHEMA_DIR` at gtk4's schemas. With that set, the planned live strategy works end to end: the fallback dialog is a real X window, `xdotool key Escape` reaches it, and `on_response` fires with `response_id = -4` (**DELETE_EVENT, not CANCEL/-6**) — the test asserts −4.
3. **Task 8 — never assert on a `destroy` signal**: ocgtk's `Widget.on_destroy` never delivers, even on explicit `Window.destroy`. Assert destruction via `get_visible`/`get_mapped`. Both close-request veto halves otherwise behave exactly as designed (`true` keeps the window alive; `false` really destroys — proved by GTK's "shown after destroyed" warning on re-present).
4. **Task 8 — two presents in one burst: last-present-wins focus, deterministically**; re-presenting an earlier window takes it back. `live_windows.ml` asserts that ordering.
5. **Task 2 — `Attr.autofocus`'s fixup-queue grab is sufficient**: `grab_focus` *before* `present` works and sticks after map — no post-present ordering needed. Test probes must use `Window.get_focus` + a descendant check (an entry's focus widget is its internal `GtkText`, so `has_focus` on the entry reads false).
6. **Task 10 — the `GtkDialog` loop works headlessly as assumed**: `on_response` fires synchronously on the `Dialog.response` caller's stack (`response_id = 1` delivered, destroy clean, no criticals).
7. **Fact table wording** — `Shortcut_trigger.parse_string` on garbage raises `Failure "ml_gobject_val_of_ext: NULL GObject"` (not a segfault, not a wrapped NULL; avoid-it rule unchanged). `Alert_dialog.show` (single-button) and `File_dialog.new_` do exist; neither changes the contingency rulings.
8. **Task 5 confirmed** — `Popover` `closed` is emitted synchronously inside `popdown`, so the `in_patch` guard covers the write-provoked emission; controlled `~open` as planned.
9. **Task 6 confirmed** — `remove_all` + re-append on a `GMenu` while its `PopoverMenu` is **open** is safe (no crash, popover stays mapped); no pop-down-first needed.

Static answers the tasks need: the `Update` kind-change arm is at `src/patcher.ml:912-944` pre-split (patch destroys the old live at 918-925; `ops.remove` of the already-destroyed widget at 940-942; the in-code comment flags the window case — after Task 1's split, find it by that comment). `root_widget` consumers: none in `examples/`; `test/live/live_driver.ml` (10 sites: 162, 167, 192, 210, 225, 257, 262, 282, 323, 350), `live_lists.ml` (598, 1069, 1739), `live_text.ml` (591, 1226, 2094, 2171, 2183).

## Global Constraints

Carried from the spec and from what M0–M2 established. These hold for every task below; read them before Task 1 and again if a review says "this does not match the codebase".

- **One widget, one file.** Each widget is `src/widgets/w_<name>.ml` exposing a single `let impl : Widget_impl.t` (spec §7). File names are prefixed `w_` because `src/dune` uses `(include_subdirs unqualified)`. `src/widgets/registry.ml` maps `Kind.t` to the impl and must stay an exhaustive match.
- **Props vs attrs.** Widget-specific properties are typed fields of that widget's `Kind.t` constructor and labelled arguments of its `Node.*` constructor, defaulted from `vtree/defaults.ml` and dropped from the sexp with `[@sexp_drop_if]`. Properties every `GtkWidget` has are `Attr.t` values passed in `~attrs`. Widget-specific *events* are attrs. A setting the *parent* holds on behalf of a child — a grid cell, a stack page's title, a list-box row's `selectable` — is an `Attr.t` on the **child**, read by the parent impl's `list_ops` and never applied by `Attr_apply` (spec §5.3). Anything that carries a handler is an attr; anything that must be equalable/sexpable frame to frame is a prop — which is why a **menu is a prop** (its items name actions) and **actions are an attr** (they carry the handlers the menu's names resolve to).
- **Named props records.** Every kind's props are a named record `Kind.<widget>_props` with `[@@deriving sexp_of, equal]`. Every defaulted field's default is a value in `vtree/defaults.ml`, read from three places (the `Node` optional argument, the `[@sexp_drop_if]`, and `kind.mli`); adding a fourth spelling is the bug `defaults.ml`'s header describes.
- **Prop batches are bracketed, conditionally.** Any `create` or `update` that may write more than one GTK property wraps the writes in `Widget_impl.batch`; `reassert` brackets with `Widget_impl.batch_if writes` (freeze/thaw measured ~80 ns — cheap, not free); never hand-roll `freeze_notify`/`thaw_notify`.
- **Keyed children.** List children are matched by `Key.t` where present and positionally otherwise. A duplicate key among siblings is `Invalid_argument`, at mount as well as at patch. `Stack` pages, `ListBox` rows, `FlowBox` children, `Notebook` pages — and now **`Node.windows` children — all *require* a key**, rejected from the constructor naming the child's index. A container with no reorder primitive has `list_ops.move = None` and `Reconcile.diff ~ordered:false` emits no `Move` for it.
- **Controlled props (spec §6.5).** A prop the user can change writes the widget only when the new value differs from the **widget's current value**, in `Widget_impl.reassert`, not `update`. A controlled prop that names a *child* (stack visible child, list/flow selection, notebook page — and now a window's `~transient_for` and a menu item's action reference) is applied from the **fixup queue** instead, after the whole tree exists, inside the same guard. The single/plural arity rule from §5.4 decides what a name that resolves to nothing does: single raises (with the empty-container carve-out), plural filters.
- **Refuse, record, report.** A controlled prop naming a value the widget cannot hold is refused *before* the widget is touched, remembered so parked frames cost a pointer comparison, and reported once through `Patcher.ctx.report` with the node path (`src/widgets/refusal.ml` is the shared machinery). The rule for raising instead: *reject only what no later frame could make valid* (`vtree/node.mli`'s opening section).
- **Signal slots.** Every signal a widget supports is connected exactly once at `create`, to a trampoline that (1) cannot let an exception cross into C, (2) returns immediately when `Scheduler.in_patch` is set, (3) reads the handler out of a mutable slot, (4) converts GTK's arguments, (5) schedules and requests a frame (spec §6.4). `Signals.spec` is `Read_back` or `Payload`: **every signal whose argument is a child widget, and every controller signal, is a `Payload`** — as is any signal whose return value GTK reads synchronously (`close-request` joins `key-pressed` here). Each `Payload` carries a `declined` value, the inert answer for the three no-handler paths. A `connect` returns `Signals.connection list` naming the object each id was issued for. Signals reachable only through the generic marshaller use `Signals.notify ~prop`. Signals ocgtk cannot bind are omitted from the API and named in the widget's doc comment, never bound to a silent no-op (spec §11).
- **Controller families.** `Attr`s that are legal on every kind (click, focus, key — and now shortcut) are declared by **no impl**: `vtree/events.ml`'s `controller_family` is the single exhaustive table, `Controllers` attaches one controller per family on demand and detaches a family the moment its last attr goes, controllers are named with `Event_controller.set_name` (never `set_static_name`), and a controller is never left attached with a dead slot. A family whose attrs disagree on `?phase` is rejected by `Events.family_phase_rejection` (generalised from `key_phase_rejection` in Task 2) — headlessly and at mount, with the same message.
- **Never connect a handler to a signal a GObject's dispose can emit** (`destroy`, `unrealize`, `notify::` on a widget being disposed), and if one is unavoidable, disconnect it before the widget can become collectable. The fork now guards the finaliser re-entry (a once-reported no-op instead of a segfault), but the rule stands: the guard is a backstop, not permission. `Embed.stop`'s backstop-disconnect comment is the worked example.
- **Every GTK call site is guarded.** Structural misuse raises `Invalid_argument` carrying the node path, at mount/patch time. Exceptions inside a trampoline are caught, logged with the node path, and do not tear down the loop. Exceptions inside a frame stop the driver for good. (spec §11)
- **Testing, three suites.** Behaviour decidable from the `Node.t` tree is a `ppx_expect` test in `test/` (package `bonsai_gtk`, depends on `bonsai_gtk.vtree` alone) or `test/handle/` (package `bonsai_gtk_test`); no test directory may straddle the two packages. Behaviour that is GTK's is a plain executable under `test/live/` printing `Live_tree.dump`, compared by a `(diff expected.txt output.txt)` rule, gated on `(enabled_if (= %{env:BONSAI_GTK_LIVE_TESTS=0} 1))`. **Every live rule whose executable presents a toplevel carries `(locks x-display)`** — M3 presents more toplevels than any milestone before it, and the M2 diagnosis (a neighbour's mapping steals the input focus) applies to every one of them. Real-input coverage uses the `test/live/live_input.ml` XTEST pattern (xdotool via `%{bin:xdotool}`, computed coordinates, `pump_until`, no sleeps); popovers, shortcuts and dialogs need it, because opening a popover and firing a chord are exactly the routing no other suite can see. No `ppx_inline_test`/`ppx_expect` in anything linking ocgtk.
- **`scripts/ci.sh` must pass** at the end of every task: `nix build .#ocgtk`, per-directory `@fmt` aliases, `dune build @all`, committed `.opam` files, `@test/runtest`, both `-p` package builds, `BONSAI_GTK_LIVE_TESTS=1 xvfb-run -a dune build @test/live/runtest`, and the example smoke runs. `dune fmt` before every commit; `.ocamlformat` is `profile=janestreet`.
- The runtime uses ocgtk **Layer 1** (`Ocgtk_gtk.Gtk.Wrappers.*`, aliased `W` in `Gtk_import`) exclusively, and never `open`s `Ocgtk_gtk.Gtk` (it shadows `unit`). Downcasts go through `Gtk_import.cast`; upcasts are plain `(x :> Widget.t)` coercions; **GIR interfaces** (`Gio.Action`, `Action_map`, `Action_group`, `Gtk.File_chooser`) are reached with their `from_gobject` checked cast, the `Editable.from_gobject` idiom. Layer 1 methods are `external` and positional — no labels. Only the generated `on_*` signal helpers are `val` and labelled.

**Commit trailer** (append to every commit body):

```
Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01Sg3Ci8U8kUKR8C3PL1pNSs
```

Use `GIT_EDITOR=true git commit -F -` with a heredoc; plain `git commit -m` hung once in this environment.

**Reference sources:**
- The pinned ocgtk checkout is `.ocgtk-src/` (branch `main` at `72cc75f2`, the post-round-2 pin). Every ocgtk signature quoted in this plan was read from `.ocgtk-src/ocgtk/src/{gtk,gio,gdk}/generated/<module>.mli` **on 2026-08-31 against that commit** — including the ones that turned out not to exist, which are called out where they bite. Note the merged-cycle module names: `Widget` lives in `event_controller_and__layout_child_and__…__widget.mli`, `Window`/`Application` in `application_and__window_and__window_group.mli`, `Clipboard`/`Display` in gdk's `app_launch_context_cycle_de440b34.mli`, `Gio.File` in `app_info_cycle_64c425a0.mli` — always go through the `Gtk.Wrappers`/`Gio.Wrappers`/`Gdk.Wrappers` aliases.
- stavekeeper, the downstream driver: `~/src/stavekeeper/lib/stavekeeper_app/{shell,viewer_window,dialog,command,palette,settings_dialog,edit_dialog,pieces_dialog}.ml`. It is a Layer-2 (`#method`) app; read it for *which* chrome a real screen needs, not for call syntax. Line numbers cited in this plan were read on 2026-08-31.
- `docs/m2-backlog.md` — Tasks 1–3 clear the "Do first in M3" list; Task 13 rewrites the file as `docs/m3-backlog.md`.
- `.superpowers/sdd/2026-08-30-bonsai-gtk-m2/` — M2's per-task reports and the final-review ledger. When a rule in this plan looks arbitrary, its reasoning is usually there.

## ocgtk facts that shape this milestone

Verified in the pinned checkout at `72cc75f2`. Each of these changed a design decision below; do not rediscover them the hard way.

| Fact | Consequence |
|---|---|
| **`Alert_dialog` has no constructor** (`gtk_alert_dialog_new` is varargs, skipped; ocgtk has no generic `g_object_new` either) and no async `choose` — only `choose_finish`. `Message_dialog` likewise has no constructor. `Dialog.new_`, `Dialog.add_button : t -> string -> int -> Widget.t`, `Dialog.get_content_area : t -> Box.t` and `Dialog.on_response` **are** bound. | Spec §8's contingency fires: `Effect.Alert_dialog.show` is built on **`GtkDialog`** (deprecated in GTK 4.10, present and functional in 4.22), and Task 10 documents which path was taken, as §8 asks. `AlertDialog.choose` is a fork-round-3 candidate. |
| **`File_dialog` cannot be launched**: `open_`/`save`/`select_folder` (async, callback-taking) are all NOT PRESENT; only the five `*_finish` halves exist. `File_chooser_dialog` is a type with zero methods. **`File_chooser_native.new_ : string option -> Window.t option -> filechooseraction -> string option -> string option -> t`** exists, `Native_dialog.{show,hide,destroy,set_modal,set_transient_for}` and **`Native_dialog.on_response : … callback:(response_id:int -> unit) …`** exist, and `File_chooser.from_gobject` + `File_chooser.get_file : t -> Gio.File.t option` + `Gio.File.get_path : t -> string option` complete the read-back. | Task 10's file effects are **FileChooserNative** end to end. Under xvfb with no portal this falls back to a plain GTK dialog window, which is what makes it live-testable at all. `Gio.File` has **no constructor** (`new_for_path` NOT PRESENT), so `set_initial_folder` cannot be fed — initial-folder is a documented omission. |
| **`Gdk.Clipboard.set_text` does not exist** (C macro), `get_text`/`read_text_async` do not exist (async). **`Clipboard.set_value : t -> Gobject.Value.t -> unit`** exists, and `Gobject.Value` can hold a string. `Widget.get_clipboard : t -> Clipboard.t` exists; `Display.get_default` does NOT (namespace function) — a display comes from `Widget.get_display`. | `Effect.Clipboard.set_text` writes through `set_value` with a string `GValue`, reached from a widget the runtime registers (Task 9). **`Clipboard.get_text` does not ship in M3** — there is no synchronous read and no bound async one; documented omission + fork-round-3 candidate. |
| **`Gdk.Rectangle` cannot be constructed** — the type exists with `union`/`intersect`/`contains_point` only, no ctor and no field accessors anywhere in the tree. | `Popover.set_pointing_to` is unusable except with `None`. **`Node.popover` has no pointing-to**; a popover points at its parent widget (GTK's default), which is all a menu button needs. Fork-round-3 candidate. |
| **`Callback_action` has no constructor** (callback-taking, skipped); `Activate_action`/`Nothing_action` have no singleton getters. What can be built: `Named_action.new_ : string -> t`, `Signal_action.new_`, `Keyval_trigger.new_ : int -> Gdk.modifiertype -> t`, `Alternative_trigger.new_`, and `Shortcut.new_ : Shortcut_trigger.t option -> Shortcut_action.t option -> t`. `Shortcut_trigger.parse_string : string -> t` returns a **non-option** where C can return NULL — a crash waiting for a typo. | **A shortcut cannot invoke an OCaml closure.** `Attr.shortcut` therefore routes through the action system: a trigger (built with `Keyval_trigger.new_` from vtree data, never `parse_string`) fires a **named action** that `Attr.actions` declared. This is also why Task 7 depends on Task 6. |
| `Simple_action.new_ : string -> Gvariant_type.t option -> t`, `new_stateful`, `set_state`, `set_enabled`, and **`on_activate : … callback:(parameter:Gvariant.t option -> unit) …`** are all bound — the activate marshaller is the one the fork's floating-GVariant fix landed in, so GVariant parameters are safe. `Gvariant.of_string/of_boolean/to_string/to_boolean` etc. exist in `ocgtk.common`; no tuple constructor (use `Gvariant.parse` if ever needed). | Full GMenu + GAction routing is expressible, stateful actions included. |
| **`Simple_action_group`'s methods are `insert`/`lookup`/`remove`**, and `lookup` returns a **non-option** `Action.t` (NULL hazard). `Action_map.from_gobject` gives `add_action`/`lookup_action` (this one correctly `option`)/`remove_action`. `Widget.insert_action_group : t -> string -> Action_group.t option -> unit` is bound; `Action_group.from_gobject` produces the argument. | `Actions` uses `Simple_action_group.new_` + `insert`, never `lookup` (the runtime keeps its own name→action table and does not read GTK back), and `insert_action_group` with the `from_gobject` casts. |
| `Menu.append : t -> string option -> string option -> unit` (label, detailed action), `append_section`/`append_submenu` (take `Menu_model.t` — a `Menu.t` upcasts structurally), `remove_all`, `Menu_item.new_` + `set_detailed_action` + **`set_attribute_value : t -> string -> Gvariant.t option -> unit`** are all bound. `set_action_and_target` (varargs) is not; `set_action_and_target_value` is. | The menu builder is straightforward; the display-only `"accel"` attribute stavekeeper renders (`viewer_window.ml:4288-4292`) is `set_attribute_value "accel" (Some (Gvariant.of_string …))`. Radio targets use `set_action_and_target_value`. |
| **`Header_bar` has no title-string setter in GTK4** — only `set_title_widget : t -> Widget.t option`, `pack_start`/`pack_end`/`remove`, `set_show_title_buttons`, `set_decoration_layout : t -> string option`. No signals. | The header bar's title is a **slot child**, not a prop; the title *string* belongs to the window (GTK shows the window title when no title widget is set). |
| `Action_bar`: `pack_start`/`pack_end`/`set_center_widget : t -> Widget.t option`/`remove`/`set_revealed`. No signals. | Three slots, one plain `revealed` prop (programmatic-only in GTK, so not controlled). |
| `Popover`: `popup`/`popdown`/`present`/`set_child`/`set_position`/`set_autohide`/`set_has_arrow`/`set_offset`/`set_cascade_popdown`, signals `on_closed`/`on_activate_default`. `Menu_button`: `set_popover : t -> Popover.t option`, `set_menu_model`, `set_label`/`set_icon_name` (**non-option** setters — no unbind), `set_primary`, `set_direction`, `set_always_show_arrow`, `popup`/`popdown`, signal `on_activate`. `Widget.set_parent : t -> t -> unit` and `unparent` exist. | `Node.popover` ships **only as `Node.menu_button`'s `~popover` slot** in M3 (see Task 5's ruling); its `~open` is a controlled prop written with `popup`/`popdown` and observed with `on_closed`. |
| `Shortcut_controller.new_`, `add_shortcut`, `remove_shortcut`, `set_scope : t -> shortcutscope` are bound; **`set_propagation_phase` lives on `Event_controller`** (coerce — the row includes `` `event_controller ``). | The `Shortcut` controller family fits the `Controllers` machinery unchanged; phase is set the same way the other three families set it. |
| `Window` is complete for M3's needs: `present`, `close`, `destroy`, `set_title : t -> string option`, `set_transient_for : t -> t option`, `set_modal`, `set_default_size`, `set_titlebar : t -> Widget.t option`, `set_hide_on_close`, `set_resizable`, `set_deletable`, `is_active`, and **`on_close_request : … callback:(unit -> bool) …`**. `Application.add_window`/`remove_window`/`get_active_window`/`get_windows` and **`set_accels_for_action : t -> string -> string array`** are bound. | Everything Task 8 needs exists. `set_title` taking an `option` means the unset path is honest (M2's nullable-binding lesson). |
| **`Style_display` is the fork's hand-written stub** at module path **`Ocgtk_gtk.Style_display`** (top-level, *not* under `Gtk.Wrappers`): `priority_application : int`, `add_provider_for_default_display : Style_provider.t -> int -> unit` (raises `Failure` before GTK init), `settings_default : unit -> Settings.t`. `Css_provider.new_`/`load_from_string` are bound, and `Widget.get_style_context` + `Style_context.add_provider : t -> Style_provider.t -> int -> unit` are bound too. | Task 11 wires both halves: display-wide CSS on `start`/`embed`, and per-widget `Attr.css_provider` via the (deprecated-but-present) style-context path. |
| `Glib.Timeout.add : ?prio:int -> ms:int -> callback:(unit -> bool) -> unit -> id` is fully labelled with a `unit` terminator; **`Glib.Idle.add : ?prio:int -> (unit -> bool) -> id` takes its callback positionally with no terminator.** | The asymmetry bites; quote both shapes in Task 9 and move on. |
| `Gesture.set_state : t -> Gtk_enums.eventsequencestate -> bool` is bound (`` `CLAIMED``/`` `DENIED``/`` `NONE``). | Per-event click claiming is one call from inside the `pressed` trampoline — `Click_response.t` is implementable (Task 2). |

## File structure

| Path | Change | What |
|---|---|---|
| `src/patcher.ml` → `src/patcher.ml` + `src/patcher_checks.ml(i)` + `src/patcher_fixups.ml(i)` | split | Task 1 (motion-only; 1071 lines today, and Tasks 6/8 both grow it) |
| `test/live/live_controllers.ml` → per-family files | split | Task 1 |
| `test/handle/test_gallery.ml` → tree + sweeps files | split | Task 1 |
| `vtree/kind.ml(i)`, `vtree/node.ml(i)` | modify | one constructor per M3 widget; `windows`; `window_props` grows (Tasks 4, 5, 6, 8) |
| `vtree/menu.ml(i)` | create | the declarative menu tree (Task 6) |
| `vtree/action_spec.ml(i)` | create | name/enabled/state/handler (Task 6) |
| `vtree/trigger.ml(i)` | create | keyval + modifiers, from M2's `Keyval`/`Modifiers` (Task 7) |
| `vtree/click_response.ml` | create | `Continue \| Claim`, the click twin of `Key_response` (Task 2) |
| `vtree/keyval.ml(i)` | modify | punctuation the chords need (Task 7) |
| `vtree/events.ml(i)` | modify | `Family.Shortcut`; `family_phase_rejection`; arms for the new kinds (Tasks 2, 4–8) |
| `vtree/attr.ml(i)` | modify | `actions`, `shortcut`, `on_close_request`, `on_contains_focus_changed`, `on_cursor_moved`, focus `?phase`, `on_click` re-typed (Tasks 2, 3, 6, 7, 8) |
| `vtree/defaults.ml` | modify | a module per M3 widget |
| `vtree/bonsai_gtk_vtree.ml` | modify | re-export every new module |
| `src/signals.ml(i)` | modify | nothing structural — `close-request` is an ordinary `Payload` (Task 8) |
| `src/controllers.ml(i)` | modify | the `Shortcut` family; focus-phase plumbing; click claiming (Tasks 2, 7) |
| `src/actions.ml(i)` | create | `GSimpleActionGroup` ownership + routing (Task 6) |
| `src/patcher.ml(i)` (post-split) | modify | `ctx.windows` registry; `Windows` interest; the `Update` kind-change latent fix; menu/action fixup checks (Tasks 6, 8) |
| `src/driver.ml(i)` | modify | `Windows` root; `root_widget` → `None` for it; `windows` accessor (Task 8) |
| `src/loop.ml` | modify | effect hooks registration; multi-window activate (Tasks 8, 9) |
| `src/embed.ml(i)` | modify | effect hooks where meaningful; `?global_css` (Tasks 9, 11) |
| `src/gtk_effect.ml(i)` | modify | `after`, `on_idle`, `Clipboard.set_text`, `Alert_dialog.show`, `File_dialog.*`, `Window.present` (Tasks 9, 10) |
| `src/widgets/w_header_bar.ml`, `w_action_bar.ml`, `w_popover.ml`, `w_menu_button.ml`, `w_windows.ml` | create | 5 new impls |
| `src/widgets/w_window.ml` | modify | close-request `Payload`; `transient_for`/`modal`/`resizable` props (Task 8) |
| `src/widgets/w_stack.ml`, `w_notebook.ml`, `w_list_box.ml`, `w_flow_box.ml`, `w_text_view.ml` | modify | report-once memos, dedup, cursor attr (Task 3) |
| `src/widgets/registry.ml` | modify | an arm per kind |
| `src/child_keys.ml(i)` | modify | `length` for tests (Task 3) |
| `src/live_tree.ml` | modify | per-type props for every M3 widget |
| `src/bonsai_gtk.ml(i)` | modify | re-exports; `start ?global_css`; `Expert` surface changes |
| `test_lib/bonsai_gtk_test.ml(i)` | modify | `Activate_action`, `Open_popover`, `Close_popover`, `Close_request`, `Fire_shortcut` actions; menu/action/shortcut/windows validation (Tasks 5–8) |
| `test/…`, `test/handle/…` | modify | per task |
| `test/live/live_chrome.ml`, `live_menus.ml`, `live_windows.ml`, `live_effects.ml`, `live_dialogs.ml`, `live_css.ml` (+ expected) | create | Tasks 4–11; every one that presents a toplevel takes `(locks x-display)` |
| `test/live/live_input.ml` | modify | popover-open, shortcut-chord and dialog-dismiss blocks (Tasks 5, 7, 10) |
| `examples/gallery.ml`, `examples/chrome.ml` | modify/create | Task 12 |
| `scripts/ci.sh` | modify | the new example in the smoke list (Task 12) |
| `README.md`, the spec, `docs/m3-backlog.md` | modify/create | Task 13 |

## What M3 gives the stavekeeper port, and what it still does not

The port is why this milestone has the shape it has. Read against `~/src/stavekeeper/lib/stavekeeper_app/`:

**Portable after M3:**

- **`dialog.ml`** — the shared modal shell (`dialog.ml:8-55`: `set_transient_for` + `set_modal` + `set_destroy_with_parent` + fixed size + a CAPTURE Escape controller, 15 call sites in 11 modules) becomes a keyed `Node.window ~transient_for ~modal` child of `Node.windows`, with M2's `Attr.on_key_pressed ~phase:Capture` for Escape and Task 8's `Attr.on_close_request` for the close button. `Dialog.on_ctrl_return` (`dialog.ml:71-87`) — a second CAPTURE controller checking `enabled ()` at press time — is a key handler whose `Key_response` the model computes, or an `Attr.shortcut` naming an action whose `enabled` the model controls; either is a rewrite of three lines, not a mechanism gap.
- **`palette.ml`** — not a popover at all: a transient modal toplevel (`palette.ml:143-149`) over an entry + list box with index-driven navigation. Portable on `Node.windows` + M2's widgets; the `close_then`-idle dance (`palette.ml:218-226`) becomes `Effect.on_idle` sequencing.
- **The viewer's ⋮ menu** — `viewer_window.ml:4252-4542`: one `Menu_button`, a five-submenu two-section `Gio.Menu`, ~28 `SimpleAction`s with `set_enabled` toggling (`ink_actions_enable_hook`, `:4490-4505`) and display-only `"accel"` attributes (`:4288-4292`). Task 6's `Node.menu_button ~menu` + `Attr.actions` covers the whole shape, including the accel *rendering* (an `accel` field on `Menu.item`) — and deliberately not accel *installation*, because stavekeeper itself never installs one (`viewer_window.ml:4230-4233`: "the key handler stays the single source of key truth"). The `register_action` bundle (`:4252-4294` — action + add_action + registry + menu item + teardown) collapses into one `Action_spec` in a list the model renders; `Command.Registry`'s `{id; label; accel; scope; enabled; run}` (`command.ml:15-22`) maps field-for-field onto `Action_spec` + `Menu.item`, so the palette and the menu can render from one list of commands, which is the composition Task 6 is designed around.
- **The menu popover's focus bug is the runtime's to fix once.** `viewer_window.ml:750-797` documents GTK4 leaving focus inside a popped-down `PopoverMenu` (every viewer key goes dead after one menu use) and works around it with a re-armable 60 ms × 8 timeout clearing `set_focus None`. Task 5's `w_menu_button` owns the equivalent repair in one place, behind the API, so no port carries that timer again.
- **`shell.ml` multi-window** — the `shells` list (`shell.ml:118`), pop-out (`:330-335`), and close-request → quit-on-last (`:653-682`) become a keyed window list in the model, `Attr.on_close_request` effects that remove a key, and `Effect.quit` when the list would empty (or just rendering `Node.windows []`, which exits — Task 8 pins that). `Effect.Window.present ~key` covers "raise the window that already has this score".
- **Delete confirmations** — `edit_dialog.ml:721-797` and `pieces_dialog.ml:668-707` are each a hand-built nested `Dialog.shell` with Cancel/Danger buttons, plus an ordering hazard (`pieces_dialog.ml:699-701`, close-before-commit under `destroy_with_parent`). Each becomes one `Effect.Alert_dialog.show ~buttons:["Cancel"; "Delete"]` bind — ~130 lines and the hazard deleted.
- **`settings_dialog.ml`'s missing folder picker** — `settings_dialog.ml:231-238` records that GtkFileDialog was unusable in the raw binding, so the design's "Choose…" button is a bare path entry. `Effect.File_dialog.select_folder` (Task 10) is the first thing in either repository that can actually open a file picker; this is the one M3 feature whose value is "unblocks a design ruling" rather than "ports existing code".
- **Idle/timeout plumbing** — `shell.ml:136-168` (guarded idles), `viewer_window.ml:582-598` (cancellable timeout), `settings_dialog.ml:683-727` and `edit_dialog.ml:561-597` (worker-poll timeouts) all have their effect-shaped halves in `Effect.after`/`Effect.on_idle`; the *cancellable* and *re-armable* variants stay app-side (a model can gate what it does when the effect resolves, which is the declarative cancel).
- **Chords** — `shell.ml:576-652`'s window-level CAPTURE key controller (8 chords, hand-defined keysyms at `:33-41` because "ocgtk generates no key constants") is portable two ways after M3: as M2 key attrs (transliteration), or as `Attr.shortcut`s naming actions (the declarative shape). The `text_input_active` gate (`:219-227`, probe the focused widget's type) has no transliteration — the model keeps that bit from focus attrs, the `contains_focus` rewrite noted in M2's plan.

**Not portable after M3, and deliberately:**

- **Imperative focus manipulation — narrowed by a controller ruling (2026-08-31).** The grab-focus-on-open cases (`entry#grab_focus` after present: `palette.ml:368`, `edit_dialog.ml:807-812`, `pieces_dialog.ml:736-740`) ARE portable via Task 2's `Attr.autofocus` — the interim fire-once primitive added precisely so "palette.ml is portable" stays true for a palette someone can type into. What remains unported, deliberately: `win#set_focus None` on every page swap (`shell.ml:252,324` — the embed host's business during the incremental port), `select_region`, and focus-follows-state generally; the full declarative focus design (who holds focus is state, not a side effect of construction order) deserves its own design and stays the largest named gap. `Node.window ~default_widget` is not attempted either. On the backlog, prominently.
- **`GtkSearchEntry.set_key_capture_widget`** (`library_window.ml:641`) and `Attr.mnemonic_widget` — the vtree still cannot name a widget; the stack-name-registry generalisation stays on the backlog.
- **A free-floating popover.** `Popover.set_pointing_to` needs a `GdkRectangle` nobody can construct (fact table), and anchoring a popover to an arbitrary node is a placement design M3 does not need (stavekeeper's only popover is the menu button's). `Node.popover` outside a `menu_button` slot is backlog + fork-round-3.
- **`Clipboard.get_text`**, a menubar (`Application.set_menubar` / `PopoverMenuBar`), file-dialog initial folders (no `Gio.File` constructor), and drag & drop — all named binding gaps, all in "Fork round 3 candidates" or out of scope.
- **The Wayland / real-display input residual** from M2's README stands, and M3's popover/shortcut/dialog input tests inherit it: everything is proven on Xvfb's X11 path.

## Pre-flight scan

Before Task 1, one scout verifies each of these **against the code**, and reports discrepancies to the controller (into "Pre-flight corrections" above) rather than fixing them. M1 needed three corrections at this stage, M2 needed four; every item below is something this plan asserts and could be wrong about.

- [ ] **The fact table's signatures.** Spot-check every row of "ocgtk facts that shape this milestone" against `.ocgtk-src` at the commit `ocgtk-pin.json` names **today** — the pin moved to `72cc75f2` after the fork's round 2, and if round 2's regeneration changed any surface this plan quotes (the array-element copy-out touched gdk/gtk/graphene stubs), the affected task must hear it. In particular: `Gesture.set_state`'s exact enum values, `Native_dialog.on_response`'s callback shape, `Gobject.Value` string round-trip (`create`/`set_string`/what `Clipboard.set_value` needs), and whether `Shortcut_trigger.parse_string` on garbage returns a wrapped NULL (write a 5-line throwaway under `test/live/`, run, delete).
- [ ] **`GtkDialog` on 4.22.** Build one by hand in a throwaway live executable: `Dialog.new_`, `add_button "OK" 1`, `set_transient_for`/`set_modal` via the `` `window `` coercion, `present`, `Dialog.response d 1` programmatically, confirm `on_response` fires with `response_id:1` and `Window.destroy` cleans up without criticals. Task 10's alert effect assumes exactly this loop, including that **programmatic `response` works headlessly under xvfb** — it is the whole live-test strategy for alerts.
- [ ] **`FileChooserNative` under xvfb.** Confirm `new_` + `show` under `xvfb-run` presents the fallback dialog (no portal), that `xdotool key Escape` reaches it (the live_input pattern), and that the response callback then fires with `CANCEL`/`DELETE_EVENT`. If Escape does not reach it, Task 10's live test downgrades to show-then-`destroy` and says so.
- [ ] **Popover popdown vs `in_patch`.** Confirm `Popover.popup`/`popdown` emit `closed` synchronously or asynchronously (measure: call `popdown` inside a patch-guarded block, see when the handler runs). Task 5's controlled `~open` assumes the `in_patch` guard covers the write-provoked emission; if `closed` arrives from an idle (the `search-changed` shape), the popover needs the record-and-decline treatment instead — say which.
- [ ] **`GtkWindow` present-before-child or after?** Task 8 mounts a window's subtree, then `on_window_created` presents. Confirm with a throwaway that presenting a second window from inside the same frame as the first does not steal focus in a way that breaks `live_windows.ml`'s assertions under `(locks x-display)`.
- [ ] **`close-request` veto.** Connect `on_close_request` returning `true`, call `Window.close`, confirm the window survives and no destroy is emitted. Then return `false` and confirm GTK destroys it — the two halves of Task 8's always-veto design.
- [ ] **`Menu` rebuild vs `PopoverMenu`.** Task 6 patches a changed menu by `remove_all` + re-append on the *same* `GMenu`. Confirm an **open** `PopoverMenu` tracks that without crashing (GTK's items-changed machinery), or note that the popover must be popped down first.
- [ ] **`insert_action_group` resolution from a popover.** A `PopoverMenu`'s action lookup walks from the menu button's tree position. Confirm an action group inserted on an *ancestor* of the menu button resolves (this is the scoping Task 6 promises), and that `Widget.action_set_enabled` vs `Simple_action.set_enabled` — the plan uses the latter — greys the menu item live.
- [ ] **`Patcher`'s `Update` kind-change arm** (`docs/m2-backlog.md:725-726`): read the current code, confirm the remove-after-destroy order is still there, and note which lines Task 8's fix must touch — it is latent until a `Window` sits in a list, which `w_windows` makes real.
- [ ] **`Driver.root_widget` consumers.** `grep -rn root_widget test/ examples/` — Task 8 changes its answer for a `Windows` root; list every call site so the task's file list is complete.
- [ ] **`grab_focus` timing for `Attr.autofocus`** (controller addition). On the frame a window mounts, the fixup queue runs before `on_window_created` presents — confirm with a throwaway whether `Widget.grab_focus` before `present` sticks (M2's pre-flight already knows it needs a realized, mapped widget), or whether the autofocus grab must run after present (an `on_window_created`-ordered fixup, or a map-signal one-shot). Task 2's implementer needs the answer, not the question.
- [ ] **stavekeeper still builds** (`cd ~/src/stavekeeper && dune build @all 2>&1 | tail -5`), so this plan's line-number citations are not stale.

## How to execute

Tasks are ordered by dependency and are not interchangeable. Tasks 1–3 are the splits and the backlog and must land first; 4–5 are the chrome widgets; 6 is the riskiest design (menus/actions) and needs 5; 7 needs 6 (shortcuts fire actions); 8 (windows) depends only on 1–3; 9–10 are the effects (9 needs 8's registry for `Window.present`; 10 needs 9's async pattern and benefits from 8 for transience); 11 is independent after 1; 12–14 are integration and docs.

**Per task:** one implementer, then one reviewer, then fix rounds, then a scoped re-review of just the fixes — exactly M2's protocol:

1. **Implementer.** Works the steps in order. Every task starts with a failing test and ends with `./scripts/ci.sh` green and one commit. If a step turns out to be wrong — a signature that does not exist, a behaviour GTK does not have — **stop and report it** rather than inventing a workaround; the plan is wrong and the controller needs to know, because the same wrong assumption is probably in three other tasks. Write a `task-N-report.md` in `.superpowers/sdd/2026-08-31-bonsai-gtk-m3/` naming: what changed, what the tests prove, every deviation from the plan and why, and everything deliberately left undone.
2. **Reviewer.** Reads the diff with the task text and this plan's Global Constraints in hand. Reviews for: does it do what the task said; does it follow the constraints (batch, controlled-prop discipline, keyed children, connection-names-its-object, no ocgtk in vtree or test_lib, `(locks x-display)` on toplevel-presenting rules); are the tests real (does a golden actually pin the claim); is a behaviour claimed in a doc comment actually exercised. Findings are graded Important / Minor / Out-of-scope. **Out-of-scope findings go to the backlog, not into the task.**
3. **Fix rounds.** The implementer answers every Important finding — by fixing it, or by arguing it down in writing. A finding neither fixed nor argued is a review failure, not an accepted risk.
4. **Scoped re-review.** The reviewer reads *only the fix commits* against *only the findings*, and says done or names what is still open.

**At the end of the milestone**, a final whole-branch review split by area, each reviewer reading the full diff of the branch through one lens:

- **core** — the patcher split, `src/driver.ml`, `src/loop.ml`, `src/actions.ml`, `src/gtk_effect.ml`, `src/widgets/w_windows.ml`, `w_window.ml`. Lens: lifetimes, reentrancy, exception paths, what happens on the frame that raises — and specifically: what holds a native dialog alive mid-effect, what happens when the driver stops with an effect in flight, and whether any handler can run against a destroyed window.
- **chrome** — `w_header_bar`, `w_action_bar`, `w_popover`, `w_menu_button`, the slots plumbing, the popover focus repair. Lens: the controlled-prop rule for `~open`, slot patch order, what a declined popover-close does.
- **menus & input** — `vtree/menu.ml`, `action_spec.ml`, `trigger.ml`, `src/actions.ml` (again, deliberately — two lenses on the riskiest file), `src/controllers.ml`, the shortcut family, the click claim. Lens: name resolution (menu → action, shortcut → action, `transient_for` → window) at mount, at patch, and across a frame where the referent does not exist yet; slot/handler lifetime for actions.
- **tests** — `test/`, `test/handle/`, `test/live/`, `test_lib/`, `examples/`. Lens: does the suite certify anything it should not; which claims in the mlis have no test; which goldens would not change if the code were wrong; is every toplevel-presenting rule locked.

Then one fix wave over the union of the four reports, and a re-review of the fix wave.

---

### Task 1: File splits, and two golden debts

Pure-motion first, so every later diff in this milestone reads as substance. `docs/m2-backlog.md:431-435` names the files ("both want splitting before M3 grows them again"), and `src/patcher.ml` at 1071 lines is about to take the window registry, the `Windows` interest and two new fixup checks.

**Files:**
- Split: `src/patcher.ml` → `src/patcher.ml` (mount/patch/destroy walk) + `src/patcher_checks.ml(i)` (`check_placement`, the key checks, the path-prefix helper) + `src/patcher_fixups.ml(i)` (`enqueue_fixups`, `note_interest`, `run_fixups`, `abandon_fixups`, the stack registry). `patcher.mli` stays the single public interface; the new modules are internal and `patcher.ml` re-exports nothing new.
- Split: `test/live/live_controllers.ml` (800+ lines, seven blocks) → one file per controller family (`live_controllers_click.ml`, `_key.ml`, `_focus.ml`) plus a shared `live_controllers_util.ml`; the dune rules and goldens split with them, each keeping `(locks x-display)` where its executable presents a toplevel.
- Split: `test/handle/test_gallery.ml` (1077 lines, ~540 of them one golden) → `test_gallery_tree.ml` (the tree, exported) + `test_gallery.ml` (the golden) + `test_gallery_sweeps.ml` (the four sweeps).
- Modify: `vtree/kind.ml(i)` — remove `[@sexp_drop_if Option.is_none]` from `paned_props.position` (the "erased at its default" finding, `docs/m2-backlog.md:280-286`); refresh every paned golden this moves.

**Steps:**

- [ ] **Step 1:** Split the three files. The split commits contain **no behaviour change**: `git diff --stat` shows only moves plus `open`/module-path adjustments, and every golden except the paned ones is byte-identical.
- [ ] **Step 2:** Remove the `sexp_drop_if`, run `dune runtest`, promote the moved goldens deliberately (read each diff — the only change is `(position ())` appearing).
- [ ] **Step 3:** `./scripts/ci.sh`; one commit per split plus one for the goldens, so a bisect never lands inside a move.

**Verification:** ci.sh green; `wc -l` on the three split sources all under ~500; the paned sexp now distinguishes "no position computed" from "no such field".

### Task 2: The click that can claim, and the focus family grows up

Three "Do first in M3" items that all live in `Controllers` and its attrs, plus the one-line `require_slots` fix the M2 review called "the one I would take before the controller attrs land" (`docs/m2-backlog.md:175-182`).

**Files:**
- Create: `vtree/click_response.ml`
- Modify: `vtree/attr.ml(i)`, `vtree/events.ml(i)`, `src/controllers.ml(i)`, `src/patcher.ml`, `test_lib/bonsai_gtk_test.ml(i)`, `test/test_events.ml`, `test/handle/test_handle.ml`, `test/live/live_controllers_click.ml`, `_focus.ml` (+ goldens), `test/live/live_input.ml` (+ golden)

**Interfaces:**

```ocaml
(* vtree/click_response.ml — the click twin of Key_response. [Claim] makes the gesture
   claim the event sequence (GTK_EVENT_SEQUENCE_CLAIMED), so nothing else sees the click;
   [Continue] is M2's behaviour and the default a missing handler produces. The decision
   is synchronous (Gesture.set_state runs on the C stack); the effect is scheduled. *)
type t =
  | Continue
  | Claim
  | Continue_and of unit Ui_effect.t
  | Claim_and of unit Ui_effect.t

(* vtree/attr.mli — the handler is re-typed; this is a source-breaking change and M3 is
   the milestone to take it, before any downstream exists. *)
val on_click
  :  ?phase:Phase.t
  -> ?button:int
  -> (Click_event.t -> Click_response.t)
  -> t

val on_focus_enter : ?phase:Phase.t -> unit Ui_effect.t -> t
val on_focus_leave : ?phase:Phase.t -> unit Ui_effect.t -> t

val on_contains_focus_changed : (bool -> unit Ui_effect.t) -> t
(** The [contains_focus] *query* stavekeeper polls, as an event: fires with the focus
    controller's [contains-focus] property each time it flips ([Signals.notify]-shaped,
    on the shared Focus-family controller). "Is the focus anywhere inside this subtree"
    is now a bit the model can own without deriving it from enter/leave pairs. *)

val autofocus : bool -> t
(** Controller ruling (2026-08-31), overriding the planner's defer: grab focus once,
    from the fixup queue, on the frame this widget mounts carrying [autofocus true]
    or on the frame the attr flips false→true. Fire-once, NOT a controlled prop: it
    never fights the user moving focus afterwards, and re-rendering [true] on an
    already-mounted widget writes nothing. At most one autofocus may fire per frame
    per toplevel; two in one frame is [Invalid_argument] naming both paths (the
    single-referent rule). This is the narrow interim primitive that makes the
    ported palette/dialogs typeable-into on open ([palette.ml:368],
    [edit_dialog.ml:807-812], [pieces_dialog.ml:736-740]); the full
    focus-is-state design stays on the backlog, and the mli says so. *)

(* vtree/events.mli *)
val family_phase_rejection : path:string -> Family.t -> Attrs.t -> string option
(** Generalises M2's [key_phase_rejection]: any family whose present attrs ask for two
    different phases is rejected with one message shape naming the family, the attrs and
    the phases. [key_phase_rejection] becomes [family_phase_rejection ~family:Key] and
    its message text is unchanged (goldens hold). *)
```

**Steps:**

- [ ] **Step 1: failing tests.** `test/handle/test_handle.ml`: a `Click_at` on a handler returning `Claim_and eff` shows the effect scheduled and prints the response (the `Key_press` precedent); `on_contains_focus_changed` fires from a new `Focus_contains` handle action; two focus attrs with different `?phase` raise via `family_phase_rejection` with the family named. `test/test_events.ml`: the `is_event`/family tables over the changed names.
- [ ] **Step 2: `Click_response` + attr re-type.** The click `Payload` spec's `'r` becomes the claim decision; the trampoline calls `Gesture.set_state g `CLAIMED` (coerced per the fact table) when the response says so, `ignore`-ing the `bool` result with a type annotation. `declined` stays `Continue`-shaped: no handler claims nothing, which preserves M2's card-inside-listbox behaviour and the `live_input.ml` measurement that a button's own gesture still sees the press.
- [ ] **Step 3: focus `?phase` + `on_contains_focus_changed`.** The Focus family's controller takes its phase from the attrs like Key does; `family_phase_rejection` replaces `key_phase_rejection` (which becomes a thin call into it, kept for message stability, or deleted if no external caller — implementer's choice, stated in the report). `contains-focus` is observed with `Signals.notify ~prop:"contains-focus"` **on the controller object** — the connection names the controller, not the widget, which is exactly what `Signals.connection` exists for.
- [ ] **Step 4: `require_slots` on the patch path** — the one-liner: `Patcher.patch` calls it where mount already does.
- [ ] **Step 5: `Attr.autofocus`.** The fixup-queue grab (focus needs the child tree realized, the same reason selection lives there), the once-per-frame-per-toplevel check, headless validation of the duplicate rejection, and a live case: a window mounting an entry with `autofocus true` has focus in the entry with no click (`(locks x-display)`); flipping a second widget's attr false→true moves it; re-rendering `true` on the first writes nothing (parked-frame golden).
- [ ] **Step 6: live coverage.** `live_controllers_click.ml` asserts the claim plumbing (`armed=`); `live_input.ml` gains the end-to-end pair: two overlapping click targets where the inner handler answers `Claim` and the golden shows the outer handler silent, then `Continue` and the golden shows both — the routing only a real click can prove.

**Verification:** ci.sh green; the M2 backlog items at lines 97-99, 100-106 and 175-182 are quotable as closed; `live_input.ml`'s new block runs 10/10 under load like its existing ones.

### Task 3: Report-once memos, `Child_keys.length`, and the text view's caret

The remaining "Do first in M3" items — all container/text-widget side, none structural.

**Files:**
- Modify: `src/widgets/w_stack.ml`, `w_notebook.ml`, `w_list_box.ml`, `w_flow_box.ml`, `w_text_view.ml`, `src/child_keys.ml(i)`, `vtree/attr.ml(i)`, `vtree/events.ml(i)`, `test/live/live_lists.ml`, `live_text.ml` (+ goldens), `test/handle/test_handle.ml`

**Steps:**

- [ ] **Step 1: the select-fixup memos** (`docs/m2-backlog.md:136-149`). A `~visible_child`/`~current_page` naming a page carrying `Attr.visible false` writes on every frame forever; both get one memo shape (the `Refusal` record-and-report machinery, keyed on the offending key): the fixup still *tries* each frame (the page may become visible), but reports once — "`~current_page` names a hidden page; GTK will not switch to it" — and the live test pins that a parked frame costs no GTK write beyond the one attempt. Measure the parked-frame cost in the task report, as the backlog asks.
- [ ] **Step 2: the `~selected` dedup** (`:150-158`). Ruling, taking the backlog's "decide together" instruction: **dedupe *and* report once.** `apply_selection` dedupes `wanted` before comparing (which stops the every-frame `unselect_all` churn — the behaviour fix), and a list that *needed* deduping is reported once per distinct value (which keeps the model typo visible — the consistency-with-M2 half). Same change in both `w_list_box.ml` and `w_flow_box.ml`; this is the second fix made twice in these files, and per the standing trigger (`:159-163`) the task report must say whether a third copy is now on the table.
- [ ] **Step 3: `Child_keys.length : _ t -> int`** exposed for tests, plus one live case per container (list box, flow box, notebook): N keyed children mounted, `length = N`; remove k, `Gc.full_major`, pump, `length` settles to N−k. This is the pin that makes the task-7-M4 mutation (`| Flow_box _ -> ()` in destroy) fail a golden.
- [ ] **Step 4: `Attr.on_cursor_moved : (int -> unit Ui_effect.t) -> t`** on `text_view` (`:107-110`): `Signals.notify ~prop:"cursor-position"` on the **buffer** (connection names the buffer), payload read back with `get_cursor_position`. The constructor doc's "approximate caret" paragraph now ends with the attr that closes it.
- [ ] **Step 5:** headless actions/goldens for the new attr; `Events.for_kind` arm updated; `live_events.ml`'s agreement sweep stays green.

**Verification:** ci.sh green; every "Do first in M3" bullet in `docs/m2-backlog.md:95-191` is now either closed by Tasks 1–3, deliberately carried (the two the plan carries: `after_of` cost — the backlog itself says spend where measurements are; `Activate_row`-on-non-activatable — revisit-once-deliberately, Task 13 re-records it), or absorbed into a later task (Keyval completeness → Task 7; propagation modelling → Task 7's live_input block; nullable behavioural half → Task 13 decides). Task 13's backlog rewrite must account for all of them by name.

### Task 4: HeaderBar and ActionBar — the first Slots widgets since M1

Two low-risk widgets that exercise the Slots children shape before the popover needs it. Neither has signals; both are pure structure.

**Files:**
- Create: `src/widgets/w_header_bar.ml`, `src/widgets/w_action_bar.ml`
- Modify: `vtree/kind.ml(i)`, `vtree/node.ml(i)`, `vtree/defaults.ml`, `vtree/events.ml`, `src/widgets/registry.ml`, `src/live_tree.ml`, `test/test_node.ml`, `test/test_widgets.ml`, `test/handle/test_gallery_tree.ml`, `test/live/live_chrome.ml` (create, + golden), `test/live/dune`

**Interfaces:**

```ocaml
val header_bar
  :  ?key:Key.t
  -> ?attrs:Attr.t list
  -> ?title:t                  (* the title SLOT — a widget, not a string; GTK4's
                                  HeaderBar has no title string, the window's title
                                  shows when this is absent. Say so in the doc. *)
  -> ?show_title_buttons:bool  (* default true, GTK's default *)
  -> ?decoration_layout:string
  -> ?start:t list             (* keyed *)
  -> ?end_:t list              (* keyed *)
  -> unit
  -> t

val action_bar
  :  ?key:Key.t
  -> ?attrs:Attr.t list
  -> ?revealed:bool            (* default true; plain prop — the user cannot change it,
                                  so no reassert *)
  -> ?center:t
  -> ?start:t list
  -> ?end_:t list
  -> unit
  -> t
```

**Design notes.** Both are `Slots` (spec §5.3's table finally gains its HeaderBar/ActionBar rows): `start` and `end_` are keyed lists patched with the Paned/Overlay slot machinery, `title`/`center` are Singles. GTK offers no reorder inside `pack_start`'s area — removal + re-`pack` is the move, so the slot lists take `move = None` and the mli says children keep insertion order. `remove` serves both slots (GTK's `remove` is slot-agnostic). Where the header bar goes is the *application's* choice: M3 does not add `Node.window ~titlebar` wiring in this task — `Window.set_titlebar` lands with the window props in Task 8, and until then a header bar is an ordinary first child (which is exactly what stavekeeper's hand-rolled header row is; `viewer_window.ml:678-817` ports to `header_bar` or stays a `box` — both true after M3, say so in the constructor doc).

**Steps:**

- [ ] **Step 1:** failing pure tests — constructor defaults, sexp shape, `Events.for_kind` rows (both `[]`).
- [ ] **Step 2:** the two impls; `Live_tree` arms (`show-title-buttons`, `revealed`, slot order).
- [ ] **Step 3:** `live_chrome.ml`: mount both with keyed slot children, patch an insertion and a removal per slot, dump; `(locks x-display)`.
- [ ] **Step 4:** gallery tree + sweeps rows; ci.sh.

**Verification:** the four gallery sweeps in `test/handle/` go green only after both kinds appear in the tree — the M2 mechanism doing its job.

### Task 5: MenuButton and Popover — controlled open, and the focus GTK leaves behind

**Files:**
- Create: `src/widgets/w_menu_button.ml`, `src/widgets/w_popover.ml`
- Modify: `vtree/kind.ml(i)`, `vtree/node.ml(i)`, `vtree/defaults.ml`, `vtree/events.ml(i)`, `vtree/attr.ml(i)` (`on_popover_closed` if ruled an attr — see below), `src/widgets/registry.ml`, `src/patcher.ml` (popover placement check), `src/live_tree.ml`, `test_lib/bonsai_gtk_test.ml(i)` (`Open_popover`/`Close_popover` actions), tests, `test/live/live_chrome.ml`, `test/live/live_input.ml` (+ goldens)

**Interfaces:**

```ocaml
val popover
  :  ?key:Key.t
  -> ?attrs:Attr.t list        (* Attr.on_closed is the popover's event attr *)
  -> ?open_:bool               (* CONTROLLED, default false *)
  -> ?position:Position.t      (* `Top | `Bottom | `Left | `Right, new enum module *)
  -> ?autohide:bool            (* default true *)
  -> ?has_arrow:bool           (* default true *)
  -> t                         (* the single child *)
  -> t

val menu_button
  :  ?key:Key.t
  -> ?attrs:Attr.t list
  -> ?label:string
  -> ?icon_name:string
  -> ?primary:bool
  -> ?always_show_arrow:bool
  -> ?menu:Menu.t              (* Task 6 adds this argument; this task ships without it *)
  -> ?popover:t                (* a Node.popover — the ONE place a popover may appear *)
  -> unit
  -> t
```

**Design rulings, stated because a reviewer will ask:**

- **A popover is legal in exactly one position in M3: `menu_button`'s `~popover` slot.** GTK4 popovers are parented with `Widget.set_parent` rather than a container's add, and pointing-to needs the unconstructible `GdkRectangle` (fact table), so a free-floating popover is a placement design with no consumer — stavekeeper's only popover is the menu button's, and its palette is a *window*. `Patcher` rejects a `Popover` kind anywhere else with the placement-attr message shape, naming the slot that does accept it. Free anchoring goes to the backlog.
- **`~open_` is a controlled prop applied from `reassert`,** written with `popup`/`popdown` only when it differs from `Widget.get_visible` on the popover (the readable open bit), inside the `in_patch` guard. A user dismissal (click-away, Escape — GTK's `autohide`) emits `closed`; the spec is a `Read_back` firing `Attr.on_closed`'s effect, and the model that ignores it gets the popover re-opened on the next frame — the declined-edit rule, stated in the doc. The pre-flight scan's popdown-synchronicity item decides whether the guard suffices or the `search-changed` record-and-decline treatment is needed; the task text assumes the guard and the correction section overrides.
- **`label`/`icon_name` have non-option setters** (fact table): the impl treats "unset" as "write the other one" (GTK makes them mutually exclusive) and the constructor requires at most one of `~label`/`~icon_name`, `Invalid_argument` otherwise — a constructor-arithmetic rejection in M2's family.
- **The popdown focus repair lives here.** `viewer_window.ml:750-797` documents GTK4 leaving window focus on the unmapped popover child after popdown, killing every window key until someone clears it. `w_menu_button` connects the popover's `closed` (its own connection, named) and, in the trampoline, checks whether the window's focus widget is inside the popped-down popover and clears it with `Window.set_focus None` via `Widget.get_root` — once, synchronously, no timer. The live_input block below is the proof it works; if the synchronous clear is too early (GTK may move focus after `closed`), fall back to a one-shot idle and record the measurement. This is a *widget-impl workaround for a GTK behaviour*, documented in `w_menu_button.ml`'s header with the stavekeeper citation.

**Steps:**

- [ ] **Step 1:** failing tests: constructors, defaults, sexp; handle actions `Open_popover`/`Close_popover` fire `on_closed`'s handler and diff the `open_` prop; the placement rejection (a `popover` inside a `box`) raises headlessly with the same message as mount.
- [ ] **Step 2:** `w_popover.ml` — create parents nothing (the menu button's impl calls `set_popover`); controlled `open_` in `reassert`; `closed` spec.
- [ ] **Step 3:** `w_menu_button.ml` — props, the `~popover` Single slot patched through `set_popover (Some …)`/`None`, the focus repair.
- [ ] **Step 4:** `live_chrome.ml`: mount a menu button + popover, drive `~open_` both ways from the model, dump visibility; assert the declined-dismissal reopen (model pins `open_:true`, call `popdown` programmatically, next frame shows it visible again).
- [ ] **Step 5:** `live_input.ml` gains the real-input block: click the menu button (XTEST), pump until the popover maps, golden the `on_closed`-armed line; press Escape, confirm `closed` fired and — the regression the repair exists for — a subsequent window-level key chord still reaches its handler. `(locks x-display)` throughout.

**Verification:** ci.sh green; the focus-repair assertion in live_input is the port-blocking bug proven fixed at the library layer.

### Task 6: Actions and `Node.menu` — GAction routing as data

The riskiest design area of the milestone. Read this section twice before writing code.

**Files:**
- Create: `vtree/menu.ml(i)`, `vtree/action_spec.ml(i)`, `src/actions.ml(i)`
- Modify: `vtree/attr.ml(i)`, `vtree/kind.ml(i)` (`menu_button_props.menu`), `vtree/node.ml(i)`, `vtree/events.ml(i)`, `src/patcher.ml` + `src/patcher_fixups.ml` (menu-reference fixup check), `src/widgets/w_menu_button.ml`, `src/attr_apply.ml` (inert arm — `Actions` owns application), `src/live_tree.ml`, `test_lib/bonsai_gtk_test.ml(i)` (`Activate_action`), `test/test_menu.ml` (create), `test/handle/test_handle.ml`, `test/live/live_menus.ml` (create, + golden), `test/live/live_input.ml`, `test/live/dune`

**The model.** Three layers, each a separate concern:

1. **The menu tree is pure data** (`vtree/menu.ml`):

```ocaml
module Item : sig
  type t = private
    { label : string
    ; action : string          (* "scope.name", or "scope.name::target" for radios *)
    ; accel : string option    (* DISPLAY-ONLY, GTK accel syntax; rendered by
                                  PopoverMenu via the "accel" attribute, never
                                  installed as an accelerator. stavekeeper's rule
                                  (viewer_window.ml:4230-4233), adopted as ours. *)
    }
  val create : ?accel:string -> label:string -> action:string -> t
end

type entry =
  | Item of Item.t
  | Section of { label : string option; entries : entry list }
  | Submenu of { label : string; entries : entry list }

type t = entry list [@@deriving sexp_of, equal]
```

  No handlers anywhere, so `Menu.t` is a **prop** — a field of `menu_button_props`, diffed with `equal`, printed in the sexp. `Node.menu` per spec §7 is this module plus the `~menu` argument; there is no `Kind.Menu` widget, because a GMenu is not a widget.

2. **Actions carry the handlers** (`vtree/action_spec.ml`):

```ocaml
type kind =
  | Simple of unit Ui_effect.t
  | Toggle of { state : bool; on_activate : unit Ui_effect.t }
      (* the model flips its own bool; the runtime writes [state] to GTK (controlled),
         and does NOT let GTK toggle it — an activate is a request *)
  | Radio of { state : string; on_activate : string -> unit Ui_effect.t }
      (* parameter type "s"; the handler receives the activated target *)

type t = { name : string; enabled : bool; kind : kind }
val simple : ?enabled:bool -> name:string -> unit Ui_effect.t -> t
val toggle : ?enabled:bool -> name:string -> state:bool -> unit Ui_effect.t -> t
val radio : ?enabled:bool -> name:string -> state:string -> (string -> unit Ui_effect.t) -> t
```

```ocaml
(* vtree/attr.mli *)
val actions : scope:string -> Action_spec.t list -> t
(** One [GSimpleActionGroup], inserted on this widget under [scope]
    ([Widget.insert_action_group]). GTK resolves "scope.name" from any menu or
    shortcut at or below this node. Legal on every kind (a controller-family-shaped
    attr, though it attaches an action group rather than an event controller).
    Duplicate names within one attr: [Invalid_argument] from the constructor. *)
```

3. **`src/actions.ml` owns the GTK side**, `Controllers`-shaped: created with the live record, `update` diffs the spec list by name — a new name builds a `Simple_action` (`new_` with `None`/`Some Gvariant_type.string` parameter type per kind, `new_stateful` for toggle/radio) and `insert`s it; a departed name is `Action_map.remove_action` (through `from_gobject` — the group's own `remove` works too, implementer's choice, but `lookup` is banned: it returns a non-option that crashes on NULL, fact table); a surviving name gets `enabled` and `state` written **only when they differ from `Action.get_enabled`/`get_state` read back** — the controlled-prop rule, because GTK itself never changes them (we never let it), making this cheap. Handlers live in slots keyed by name; `on_activate`'s trampoline follows the five signal rules (the `in_patch` guard matters: writing `state` fires nothing back because we never connect `change-state`, but the guard is kept anyway per the constraint). **A `Toggle`'s activation does not call `set_state`** — the effect is scheduled, the model decides, next frame's controlled write moves GTK; a declined toggle therefore never moves the menu's checkmark, which is the §6.5 story told through a menu. `clear`/`release` mirror `Controllers`: `insert_action_group scope None` then drop, before the widget can be destroyed.

**Name resolution and what validates it.** A menu item's `action` names `scope.name`. The rule, following the stack-switcher precedent (single-referent name resolution raises): **at the fixup pass, every action name referenced by any mounted menu must resolve to an `Attr.actions` scope+name on the menu button itself or one of its ancestors** — that is GTK's own resolution path for a popover, so checking anything looser would certify menus GTK will grey out. `Invalid_argument` with the node path, the missing name, and the scopes that *are* in reach. `Bonsai_gtk_test` runs the same check per frame from the vtree (it has the tree and the attrs; the walk is identical code in `vtree`, shared as a function per the M2 rule). The carve-out follows §5.4's plural rule debate resolved the single way: a menu is a claim about actions the caller can see, so a dangling name is a typo, not a state to pass through — flag this ruling to the controller if a real model contradicts it.

**Rebuild strategy.** `menu_button`'s `update` compares `Menu.equal`; on change it does `Menu.remove_all` + full re-append on the *same* `GMenu` (GTK's items-changed propagates to an open popover — pre-flight confirms; if that crashes, popdown first and reopen per the controlled `open_`). Accels render via `Menu_item.new_` + `set_detailed_action`/`set_action_and_target_value` + `set_attribute_value "accel" (Some (Gvariant.of_string a))`. Sections and submenus recurse with `append_section`/`append_submenu` (a `Menu.t` upcasts to `Menu_model.t` structurally).

**What this composes with downstream.** stavekeeper's `Command.Registry` rows `{id; label; accel; scope; enabled; run}` map onto `Action_spec.simple ~name:id ~enabled` + `Menu.Item.create ~label ~accel ~action` — one list of commands renders the ⋮ menu, the palette and (Task 7) the chords, which is the single-source-of-truth shape `viewer_window.ml:4278-4287` builds by hand today.

**Steps:**

- [ ] **Step 1: failing pure tests** (`test/test_menu.ml`): menu sexp/equal; duplicate action names rejected; the resolution walk over a small tree (present, absent, ancestor-scoped, sibling-scoped-therefore-absent).
- [ ] **Step 2: failing handle tests**: `Activate_action ("test-id-of-node-with-actions", "scope.name")` fires the right handler (and the radio variant carries its target); a menu referencing a missing action raises with the mount message; a toggle activation shows no state change until the model moves it.
- [ ] **Step 3:** `vtree/menu.ml`, `action_spec.ml`, the attr, the shared resolution function.
- [ ] **Step 4:** `src/actions.ml`; wire into `Patcher.live` beside `controllers` (create/update/clear/release at the same four points).
- [ ] **Step 5:** `w_menu_button.ml` gains `~menu` (building the GMenu, owning the `PopoverMenu` via `set_menu_model`); the fixup check.
- [ ] **Step 6:** `live_menus.ml`: mount a button with a two-submenu menu and a toggle; `Activate` the action programmatically via `Action_group.activate_action` on the inserted group (read back through `from_gobject`) and golden the round trip — activation scheduled, state written next frame; flip `enabled` and dump the read-back. `(locks x-display)`.
- [ ] **Step 7:** `live_input.ml`: open the menu with a real click, arrow-down + Return (XTEST) to activate an item, golden the handler's evidence — the only test in the repository that proves a human can operate a menu.

**Verification:** ci.sh green; the handle rejects a dangling action name with the same message as mount (quote both in the report); the toggle's declined-edit golden shows the checkmark not moving.

### Task 7: `Attr.shortcut` — a fourth controller family

Depends on Task 6: a shortcut **fires a named action**, because the binding cannot build a `CallbackAction` (fact table) — the design consequence is that shortcuts and menus share one handler table, which is the composition stavekeeper wants anyway.

**Files:**
- Create: `vtree/trigger.ml(i)`
- Modify: `vtree/keyval.ml(i)`, `vtree/attr.ml(i)`, `vtree/events.ml(i)` (`Family.Shortcut`), `src/controllers.ml(i)`, `test/test_events.ml`, `test/handle/test_handle.ml`, `test_lib/bonsai_gtk_test.ml(i)` (`Fire_shortcut`), `test/live/live_controllers_shortcut.ml` (create), `test/live/live_input.ml`, `test/live/live_keyvals.ml` (+ goldens), `test/live/dune`

**Interfaces:**

```ocaml
(* vtree/trigger.ml — no GTK parse syntax in the vtree. Shortcut_trigger.parse_string
   returns a non-option that can wrap NULL (fact table), so the runtime builds triggers
   with Keyval_trigger.new_ from this data instead, and parsing never happens. *)
type t =
  { key : Keyval.t
  ; modifiers : Modifiers.t
  }
[@@deriving sexp_of, equal, compare]

val to_label : t -> string   (* "<Control>k"-style, for display; pure string building *)

(* vtree/attr.mli *)
val shortcut : ?phase:Phase.t -> trigger:Trigger.t -> action:string -> t
(** Repeatable (accumulates, like [css_class]). All shortcuts on one node share one
    [GtkShortcutController] (the Shortcut family) and therefore one phase;
    [Events.family_phase_rejection] applies. [action] is "scope.name", resolved
    exactly as a menu item's is — same fixup check, same message. Scope is LOCAL:
    the shortcut fires while focus is inside this widget's subtree, so a
    window-level chord is a shortcut attr on the window node. *)
```

**Design notes.** `Controllers` grows the `Shortcut` family: attach builds `Shortcut_controller.new_`, sets phase via the `Event_controller` coercion, and adds one `Shortcut.new_ (Some (Keyval_trigger.new_ keyval gdk_mods)) (Some (Named_action.new_ action))` per attr. Diffing shortcuts is remove-and-re-add of the changed ones (the controller is a `GListModel`; `remove_shortcut` needs the `Shortcut.t`, so the family keeps a `(Trigger.t * string) -> Shortcut.t` assoc in its live state). There is **no slot and no trampoline** for this family — the firing path is GTK → NamedAction → the `Actions` group's `activate` trampoline, which already obeys the five rules; the family's job is only attach/detach, and `armed` reports it for the live dumps. `Keyval` gains the punctuation the chords in this repo's downstream need (`comma`, `slash`, `question`, `grave`, `bracketleft`, `bracketright`, `minus`, `equal` — pinned against `Gdk_constants` by `live_keyvals.ml` like the originals; the table stays curated, and the raw-`int` escape stays the documented answer for the rest, per `docs/m2-backlog.md:114-115`).

`Fire_shortcut (test_id, trigger)` in the handle resolves the trigger against the node's shortcut attrs and fires the named action's handler — pure table lookups, no routing model, and the mli repeats M2's honesty paragraph: the handle does not model *who sees the chord first*; `live_input.ml` is where phase is real.

**Steps:**

- [ ] **Step 1:** failing tests — trigger sexp/label; two shortcut attrs with different phases rejected; `Fire_shortcut` reaches a `Simple` action's effect; a shortcut naming a missing action raises via the Task 6 check.
- [ ] **Step 2:** `Trigger`, `Keyval` additions, the attr, the family table row (`controller_family`'s exhaustive match forces every arm — the M2 design paying off).
- [ ] **Step 3:** the `Controllers` family implementation.
- [ ] **Step 4:** `live_controllers_shortcut.ml`: attach/detach plumbing, `observe_controllers` count, `armed` lines; `live_keyvals.ml` pins the new constants.
- [ ] **Step 5:** `live_input.ml`: a window-level `<Control>k` chord (XTEST `keydown ctrl`, `key k`, `keyup ctrl`) fires the action's handler with an entry focused — the case stavekeeper's `arm_keys` ordering dance exists for, proven end to end.

**Verification:** ci.sh green; `Events.Family.all` (enumerate) shows four families and `live_events.ml`'s no-impl-declares-a-controller-attr sweep still holds.

### Task 8: `Node.windows` — many toplevels, one tree

The other deep design task. Depends only on Tasks 1–3. Everything here was checked against the current runtime on 2026-08-31: `Driver.t.root` is a single `Patcher.live option` (`driver.ml:18`), `check_root` matches one node's kind (`driver.ml:45-62`), `check_placement` rejects `Window` anywhere below the root (`patcher.ml:357-364` pre-split), `on_window_created` is already called once per window node and `Loop`'s implementation (`loop.ml:22-27`, `add_window` + `present`) is already N-window-capable — the single-window limit is structural in the driver and the placement check, nowhere else.

**Files:**
- Create: `src/widgets/w_windows.ml`
- Modify: `vtree/kind.ml(i)` (`Windows`; `window_props` grows `transient_for`, `modal`, `resizable`), `vtree/node.ml(i)` (`windows`; `window` gains the new args + `Attr.on_close_request` support), `vtree/attr.ml(i)` (`on_close_request`), `vtree/events.ml` (`Window` gains `On_close_request`), `src/widgets/w_window.ml`, `src/patcher.ml` + `patcher_checks.ml` + `patcher_fixups.ml` (`ctx.windows` registry; placement relaxation; the `Update` kind-change latent fix), `src/driver.ml(i)`, `src/loop.ml`, `src/embed.ml` (unchanged rule, new message text), `src/live_tree.ml`, `test_lib/bonsai_gtk_test.ml(i)` (`Close_request`; windows-root validation), tests, `test/live/live_windows.ml` (create, + golden), `test/live/dune`, `examples/counter.ml` (gains `Attr.on_close_request Effect.quit` — see the close ruling)

**Interfaces:**

```ocaml
val windows : t list -> t
(** A virtual root holding keyed [Node.window]s (spec §4.1/§5.1). Legal only as the
    root, only under [Bonsai_gtk.start]. Every child must be a [Node.window] with a
    [~key] — both rejected from this constructor (the children's kinds are known
    here), naming the index. Rendering [windows []] lets the application exit: with
    no windows left, [GtkApplication] releases and [start] returns — which is the
    declarative [Effect.quit]. *)

val window
  :  ?key:Key.t
  -> ?attrs:Attr.t list        (* Attr.on_close_request lives here *)
  -> ?title:string
  -> ?default_size:int * int
  -> ?transient_for:Key.t      (* another window in the same [windows] list *)
  -> ?modal:bool               (* default false *)
  -> ?resizable:bool           (* default true *)
  -> t
  -> t

(* vtree/attr.mli *)
val on_close_request : unit Ui_effect.t -> t
(** The user asked this window to close (X button, Alt+F4, [Window.close]). The
    runtime ALWAYS answers GTK "handled" — the window closes when, and only when,
    the model stops rendering its node. This effect is the model's chance to do
    that. A window with no handler swallows the request and reports once: a window
    whose lifetime nobody owns is a model bug, not a UI courtesy. *)

(* Expert surface *)
val Driver.root_widget : t -> Widget.t option   (* None for a Windows root — breaking *)
val Driver.windows : t -> (Key.t * Widget.t) list  (* the live windows, for tests/effects *)
```

**Design rulings:**

- **`Windows` is a real Kind with a real (never-shown) anchor widget.** `Patcher.live` requires a widget; `w_windows.ml` creates a bare `W.Box.new_` that is never parented, never presented and never realized — it exists so the shadow tree keeps its shape and the list machinery runs unmodified. Its `list_ops` parent nothing: `insert` is a no-op (the window was created by its own mount, and `ctx.on_window_created` presents it), `remove` is a no-op (the child's `destroy` path runs `release_kind`'s `W.Window.destroy`, unchanged from M2), `move = None`. The children are keyed and `Child_keys` applies as to any list. Document on the impl why an anchor and not a `live` refactor: making `widget` optional touches every line of the patcher for one kind's benefit.
- **Placement.** `check_root` accepts `Window` *or* `Windows` for `` `Window`` root kind (embed still rejects both, message updated to name them); `check_placement` allows `Window` when the parent kind is `Windows` **and** the parent is the root, and rejects `Windows` anywhere below the root. The messages name the legal positions.
- **The close ruling** (the architecture bullet, restated where it is implemented): `w_window.ml` gains a `Payload` spec for `close-request` with `declined = true` — connected at create like every signal, answering "handled" on all paths. With a handler: schedule its effect. Without: `true` still (the veto), plus a once-per-window report through the signals ctx (the trampoline has no node path today — pre-flight confirms what `Signals.ctx` can reach; if nothing, a once-latched stderr line, stated in the mli). **This changes M2 behaviour for the single window too**: an M2 app's X button destroyed the window under the shadow tree (a desync nobody hit only because nothing patched fast enough to care); after this task the X button is inert without a handler. `examples/counter.ml` and the gallery gain `Attr.on_close_request Effect.quit`, and the README's migration note is written in Task 13. This is the plan's most user-visible ruling — flag it to the controller if the review wants a softer default, but the alternatives (allow-and-desync, allow-and-hope-the-app-quits) were both rejected for corrupting the shadow tree.
- **`transient_for` resolves in the fixup pass** through `ctx.windows : (Key.t, Widget.t) Hashtbl.t` — registered by `w_windows`'s child mounts (mirroring `register_stack`/`unregister_stack`, same duplicate/rename semantics), resolved after the whole list exists because a dialog may precede its parent in the list. A key naming no window: `Invalid_argument` listing the keys that exist — the single-referent rule (§5.4), same as the stack switcher. Applied only when it differs from what was last written (a `set_transient_for` cache in the impl; GTK has a getter, `get_transient_for`, use it and skip the cache — implementer reads the fact table's Window row).
- **The `Update` kind-change latent fix** (`docs/m2-backlog.md:725-726`): the arm that removes a child after `patch` destroyed the old live widget runs in the wrong order the moment a `Window` sits in a list — a destroyed window cannot be removed. Reorder to M2's disarm→remove→destroy discipline for the kind-change-inside-`Update` path, with a live regression: patch a `windows` list swapping a window child's kind... which cannot happen (children must be windows) — the *actual* regression is any list container whose child changes kind, so pin it in `live_lists.ml` with a box: the fix is general, the window was just the finder.
- **`Loop.start`**: `activate` unchanged in shape — the first frame mounts N windows and `on_window_created` presents each. `Driver.stop` destroys them all through the normal walk. `root_widget` answers `None` for a `Windows` root (the mli documents the break; the M2 backlog line 220 is quotable); `Driver.windows` is the replacement for anything that needed the widget, and what Task 9's `Window.present` reads. The `on_window_created`-closes-over-the-app one-liner (`docs/m2-backlog.md:715-717`) is fixed here: `Driver.stop` drops it alongside `on_root_widget_changed`.
- **Headless**: the handle validates the windows-root shape (children all windows, all keyed, `windows` only at root, only under the window root kind) from the vtree — shared functions, same messages. `Close_request key` fires the window's handler.

**Steps:**

- [ ] **Step 1:** failing pure/handle tests: constructor rejections (non-window child, missing key, nested `windows`); `Close_request`; `transient_for` naming a missing key raises at fixup (live) and headlessly via the shared walk.
- [ ] **Step 2:** vtree: `Windows`, the new window props, the attr, `Events` row.
- [ ] **Step 3:** `w_windows.ml` + placement changes + registry + fixup.
- [ ] **Step 4:** `w_window.ml`: the close-request spec, the new props (`modal`/`resizable` plain; `transient_for` via fixup), `set_titlebar` wiring for a `header_bar` first-child? — **no**: `~titlebar` stays unshipped (Task 4's note), reconfirm and move on.
- [ ] **Step 5:** driver/loop: root acceptance, `root_widget`/`windows`, stop, the closed-over-app fix.
- [ ] **Step 6:** the `Update`-arm fix + its live regression.
- [ ] **Step 7:** `live_windows.ml` (`(locks x-display)`): mount two keyed windows + a modal transient third; dump titles/modal/transient reality (`get_transient_for` names the right window); drop the dialog's node, confirm destroy; `Close_request` veto proven — `Window.close` on a handler-less window leaves it alive and the report fires once; reorder keys and confirm identity survives (same GObject).
- [ ] **Step 8:** examples updated; ci.sh.

**Verification:** ci.sh green; `examples/counter.ml` closes from the X button again (via its new handler); the review checks the desync argument in the close ruling rather than re-litigating it.

### Task 9: Timing, clipboard, and `Window.present` effects

The §8 effects that need no dialog. Establishes the async-effect pattern Task 10 reuses.

**Files:**
- Modify: `src/gtk_effect.ml(i)`, `src/loop.ml`, `src/embed.ml`, `src/driver.ml` (hook registration), `test/live/live_effects.ml` (create, + golden), `test/live/dune`, `test/handle/test_handle.ml` (effects are opaque values headlessly — pin only that they exist and sexp as `<effect>`)

**Interfaces:**

```ocaml
val after : Time_ns.Span.t -> unit t     (* Glib.Timeout-backed *)
val on_idle : unit t                     (* resolves on the next Glib.Idle *)
module Clipboard : sig
  val set_text : string -> unit t
  (* get_text does NOT ship: no sync read, no bound async one. Fact table; fork
     round 3. The mli says so where a caller will look. *)
end
module Window : sig
  val present : Key.t -> unit t
  (* close and set_title from §8 do NOT ship: the node's existence and ~title ARE
     close and set_title in a declarative tree, and an effect that duplicates a
     prop is a second writer fighting the patcher — the Paned lesson. present is
     the one with no prop equivalent (raise/focus an existing window). Deviation
     from §8 recorded in the spec amendment, Task 13. *)
end
```

**The async pattern**, written once here and reused in Task 10: effects are built with `Ui_effect.Private.make`; the GLib callback resolves the effect's callback and then calls the registered frame-requester. `Gtk_effect.For_runtime` (the `For_start` shape, generalised) holds three registered hooks — `request_frame : unit -> unit`, `lookup_window : Key.t -> Widget.t option` (reads `Driver.windows`), and `context_widget : unit -> Widget.t option` (any live widget; the clipboard and Task 10's dialogs reach GTK through it — `Widget.get_clipboard`, `Widget.get_display`) — set by `Loop.start`'s activate and by `Embed.create` (which registers `request_frame` and `context_widget` but not `lookup_window`; a `Window.present` under embed logs and resolves, matching `quit`'s outside-`start` behaviour). Every hook is cleared where `For_start.clear_app` is called and dropped by `Driver.stop`, because a hook closing over a stopped driver is the leak shape `docs/m2-backlog.md:708-717` documents. `Glib.Timeout.add ?prio ~ms ~callback ()` vs `Glib.Idle.add ?prio fn` — the label/terminator asymmetry is real (fact table); both callbacks return `false` (one-shot).

`Clipboard.set_text` builds a string `Gobject.Value` and calls `Clipboard.set_value` on `Widget.get_clipboard (context_widget ())`; performed with no context it logs and resolves (never raises — an effect is a value a test may perform).

**Steps:**

- [ ] **Step 1:** `live_effects.ml` written first, failing: a model schedules `after (16ms)` then `on_idle` from a button's effect; the executable pumps its own loop (`live_input.ml`'s `pump_until`, no sleeps) until the model's counter shows both resolved *in order*; `Window.present ~key` on the second of two windows flips `Window.is_active` (this half `(locks x-display)`); `Clipboard.set_text` then read back — **there is no bound read**, so assert only that the call returns and the golden line is "set_text: ok" (say in a comment why the assertion is thin; the honest test arrives with a fork-round-3 read).
- [ ] **Step 2:** the hooks + the four effects.
- [ ] **Step 3:** teardown: `Driver.stop` with an `after` in flight — the timeout fires after stop; the callback must tolerate a cleared frame-requester (log-and-resolve). Pin it in `live_effects.ml`.

**Verification:** ci.sh green; the in-flight-after-stop line in the golden is the review's first stop.

### Task 10: Alert and file dialogs as effects

Spec §8, on the paths the binding actually has (fact table): **GtkDialog** for alerts (the §8 contingency, exercised and documented), **FileChooserNative** for files.

**Files:**
- Modify: `src/gtk_effect.ml(i)`, `test/live/live_dialogs.ml` (create, + golden), `test/live/live_input.ml` (dialog-dismiss block), `test/live/dune`

**Interfaces:**

```ocaml
module Alert_dialog : sig
  val show
    :  ?detail:string
    -> ?cancel:int          (* the index answered on Escape / window close; default 0.
                               §8's signature returns the chosen index and says nothing
                               about dismissal; this is the addition that makes the
                               effect total. Deviation recorded in Task 13. *)
    -> buttons:string list
    -> string
    -> int t
end

module File_dialog : sig
  val open_file     : ?title:string -> ?accept_label:string -> unit -> string option t
  val save_file     : ?title:string -> ?accept_label:string -> ?initial_name:string -> unit -> string option t
  val select_folder : ?title:string -> ?accept_label:string -> unit -> string option t
  (* No initial folder: Gio.File has no constructor in the pin (fact table). *)
end
```

**Design notes.** `Alert_dialog.show`: build `Dialog.new_`, coerce to `Window` for `set_transient_for` (the active window via `Application.get_active_window` when under `start`, else none) and `set_modal true`, fill `get_content_area` with two labels (message bold via `Attr`-less direct `Label.set_markup`? — no: plain `set_text` plus a css class; no markup injection from user strings), `add_button label i` per button, `set_default_response` to the last, `on_response` resolves the effect with the id (mapping `DELETE_EVENT`/Escape to `?cancel`), then `Window.destroy`. **The dialog and its handler id are held in a table until resolved** — an ocgtk wrapper dropped early is unref'd by the finaliser and the dialog vanishes mid-show (§2.2's ownership rule; this is the same obligation the shadow tree discharges for widgets, discharged here by hand). File effects: `File_chooser_native.new_ (Some title) parent action (Some accept) None`, `Native_dialog.set_modal`, `on_response` → on `` `ACCEPT``'s int (`Gtk_enums.responsetype_to_int`) read `File_chooser.from_gobject` → `get_file` → `Gio.File.get_path`, resolve `string option`; `Native_dialog.destroy`; same keep-alive table. Both effect families are serially reentrant (two alerts at once = two dialogs; the table is a table, not a slot).

These are effects, not nodes, so the headless story is honest and thin: a handle test performs nothing GTK; apps that want to test flows inject their own effects (the M2 pattern for `quit`). The live story is real: `Dialog.response d i` works programmatically (pre-flight confirms), so `live_dialogs.ml` drives an alert to each button and to dismissal without input; the FileChooserNative fallback dialog under xvfb is dismissed with the `live_input.ml` XTEST Escape (pre-flight confirms reachability; the downgrade path is show-then-destroy with the gap stated in the golden).

**Steps:**

- [ ] **Step 1:** `live_dialogs.ml` failing: alert → programmatic response per button, cancel mapping, destroy confirmed (no criticals on a `Gc.full_major` after); the keep-alive proven by a `Gc.full_major` **between** show and response.
- [ ] **Step 2:** the alert effect; then the three file effects (shared plumbing, one `filechooseraction` each).
- [ ] **Step 3:** the `live_input.ml` block: `select_folder` presented, XTEST Escape, effect resolves `None`. `(locks x-display)`.
- [ ] **Step 4:** doc the §8 contingency in `gtk_effect.mli` ("GtkDialog because AlertDialog cannot be constructed in the pin; FileChooserNative because GtkFileDialog cannot be launched") so Task 13's spec amendment quotes it.

**Verification:** ci.sh green; the mid-show `full_major` line is in the golden.

### Task 11: Display-wide CSS, and `Attr.css_provider`

The fork's `Style_display` stub (carried since M1, spec §7's out-of-scope note) finally wired, plus the per-widget provider §5.2 deferred.

**Files:**
- Modify: `src/bonsai_gtk.ml(i)` (`start ?global_css`), `src/loop.ml`, `src/embed.ml(i)` (`?global_css`), `vtree/attr.ml(i)` (`css_provider`), `src/attr_apply.ml`, `src/gtk_import.ml` (the `Style_display` alias — it is top-level `Ocgtk_gtk.Style_display`, not under `Wrappers`; fact table), `test/live/live_css.ml` (create, + golden), `test/live/dune`

**Interfaces:**

```ocaml
val start : ?global_css:string -> … (* installed once at activate:
    Css_provider.new_ + load_from_string + Style_display.add_provider_for_default_display
    at priority_application. Raises before GTK init, so activate is the only place. *)
val Expert.embed : ?global_css:string -> …  (* same provider, caller's display *)

val Attr.css_provider : string -> t
(** A per-widget stylesheet: one CssProvider on this widget's own style context
    (Widget.get_style_context + Style_context.add_provider — deprecated in GTK 4.10,
    functional in 4.22, and the only per-widget path the binding has; say so).
    Set = load+add; changed string = load_from_string on the SAME provider (GTK
    restyles); unset = remove_provider. The provider is owned by the live state
    (the wrapper must stay alive: §2.2). *)
```

`global_css` on a *second* `start` in one process re-adds a provider (GTK accumulates) — the single-app warning in `For_start.set_app` covers the situation; note it in the mli rather than engineering removal.

**Steps:**

- [ ] **Step 1:** `live_css.ml` failing: a label with a `css_provider` colouring it + a `global_css` class; assert via… `Live_tree` cannot read computed style, so the honest assertions are structural — provider attached (style context read-back where bound), attr unset removes it, `load_from_string` on invalid CSS does not crash the frame (GTK logs; we don't) — and one visual-truth line if `Snapshot`/render read-back exists in the pin (pre-flight: it does not — keep structural and say so in the golden header).
- [ ] **Step 2:** implement; `Attr_apply` owns the attr with a `defaults`-shaped unset.
- [ ] **Step 3:** the gallery's window gains a `global_css` line so the smoke exercises the activate path.

**Verification:** ci.sh green; `Attr.css_provider`'s unset restores the un-styled state (the `Attr.Name` exhaustive-unset discipline doing its job).

### Task 12: Gallery, examples, and the sweeps

**Files:**
- Modify: `test/handle/test_gallery_tree.ml`, `test_gallery_sweeps.ml`, `examples/gallery.ml`, `examples/counter.ml` (already touched by Task 8), `scripts/ci.sh`, `test/handle/test_handle.ml`
- Create: `examples/chrome.ml`

**Steps:**

- [ ] **Step 1:** every M3 kind and attr into both gallery trees; the four sweeps (`Kind.Variants.descriptions` × tree, `Attr.Name.all` × tree, event-attr action coverage, lifecycle rows) go green — they went red the moment Task 4 added a kind, and have been carried red-locally/green-at-commit per task; this task is where the *example* twin catches up, because nothing sweeps it (`docs/m2-backlog.md:304-310` — still true; re-record in Task 13, do not fix here).
- [ ] **Step 2:** `examples/chrome.ml`: a `Node.windows` app — main window with `header_bar` (menu button + menu + actions + shortcut), an about-style alert from a menu item, a second window opened by effect/model, close-request handled. This is the M3 counter: the smallest program that exercises every headline feature, and the smoke run that would have caught a menus-crash-on-open.
- [ ] **Step 3:** `scripts/ci.sh`: add `chrome` to the example smoke list (`for ex in counter gallery embed chrome`); no other change.
- [ ] **Step 4:** ci.sh.

**Verification:** the sweeps enumerate 42 constructors (37 + Windows, Header_bar, Action_bar, Popover, Menu_button) without a hand count; `chrome` survives its 3-second smoke.

### Task 13: README, spec M3 amendments, `docs/m3-backlog.md`

**Files:** `README.md`, `docs/superpowers/specs/2026-08-28-bonsai-gtk-design.md` (M3 amendment blocks), `docs/m3-backlog.md` (create), `docs/m2-backlog.md` (strike-through closures only)

**Steps:**

- [ ] **Step 1: spec amendments**, in the established voice (dated blocks, measured claims): §4.1 (`Windows` root; `root_widget` break), §5.2 (the M3 attrs; focus `?phase` closing the M2 asymmetry note), §5.3 (HeaderBar/ActionBar slots rows made real; the popover's one legal position), §6.4 (the `Shortcut` family; `close-request` as a `Payload` with a synchronous answer), §6.5 (popover `~open`; action `enabled`/`state`; the close ruling as the controlled-prop story), §7 (M3 marked done with the shipped list and the two details it did not anticipate — the GtkDialog/FileChooserNative substitutions, the actions-not-closures shortcut design), §8 (what shipped vs the list: `Clipboard.get_text` and `Window.close`/`set_title` deviations with reasons).
- [ ] **Step 2: README** — Widgets/Input/Effects sections extended; **Limitations rewritten**: the close-request migration note (M2 apps must add a handler to quit from the X button); no focus effects (the largest named gap); no free popover / pointing-to; no clipboard read; no menubar; no initial folder; accel display vs installation; the Wayland residual paragraph updated to cover menus/dialogs.
- [ ] **Step 3: `docs/m3-backlog.md`** in the m2-backlog format: closed-in-M3 (every "Do first in M3" bullet accounted for by name — Task 3's verification list is the checklist), do-first-in-M4 (focus model; free popover; named-widget registry for `set_key_capture_widget`/`mnemonic_widget`; the gallery-twin sweep; `Activate_row`-class handle honesty revisit; the nullable behavioural half if still untaken), the carried test debts, and the fork section below copied in as the round-3 ledger.
- [ ] **Step 4:** ci.sh; the docs build is `dune build @all` (no doc toolchain) — proofread by the reviewer instead.

### Task 14: `scripts/ci.sh` end to end from a clean tree

M2's Task 16, repeated because M3 added executables, locks, an example and xdotool blocks.

- [ ] `git clean -dfx`-level check in a scratch clone (not the working tree): `scripts/setup-switch.sh` at the pin, then `./scripts/ci.sh` twice back to back — the second run catches golden-caching asymmetry (`ci.sh` already deletes `output_*.txt`; confirm the new suites' outputs are in that glob).
- [ ] Loaded-run determinism: the M2 bar — live suite green under parallel load (the spinner trick from the input work), 5/5.
- [ ] Fix whatever this finds; that is the task.

**Verification:** two consecutive green `nix develop -c ./scripts/ci.sh` from cold, stated with run times in the report.

## Fork round 3 candidates

Binding gaps found while planning M3, aggregated here so the next fork round is scoped the way round 2 was (themed commits, upstreamable, regenerate-don't-hand-patch). **No M3 task blocks on any of these** — every one has a chosen workaround or a documented omission above.

**New, from M3's survey (each names the M3 consequence it would improve):**
1. **`GtkAlertDialog` constructor + async `choose`** (hand stubs — `new` is varargs, `choose` is callback-async). Would replace Task 10's deprecated-GtkDialog alert path with the modern one §8 named first.
2. **`GtkFileDialog` async launchers** (`open`, `save`, `select_folder` — hand stubs pairing the already-generated `*_finish` halves). Would replace FileChooserNative and un-deprecate Task 10's file path.
3. **`GdkClipboard.set_text` + `read_text_async`** (hand stubs; set_text is a C convenience macro, read is callback-async). Unblocks `Effect.Clipboard.get_text`, and makes Task 9's thin set_text assertion a round trip.
4. **`GdkRectangle` constructor/accessors** (boxed-record ctor). Unblocks `Popover.set_pointing_to` and the free-floating popover design.
5. **`GtkCallbackAction`** (callback-taking ctor, hand stub). Would let `Attr.shortcut` hold a closure without routing through a named action — evaluate *after* M3 ships, because the action-routing design may prove the better shape anyway.
6. **`Shortcut_trigger.parse_string` / `Simple_action_group.lookup` NULL returns** — two non-option signatures over nullable C returns (the M1 nullable class, new instances). M3 avoids both calls; fix so nobody else trips.
7. **`Gio.File.new_for_path`** (namespace-level ctor, same class as `gdk_keyval_name`). Unblocks file-dialog initial folders.
8. **`Display.get_default` / `Display_manager.get`** (namespace-level). Would free the effects from the `context_widget` hook for display access.

**Known carries (from the round-2 close-out — do not re-derive):**
9. List-element borrowed-return `ref_sink` → `ref` (`generate_ref_sink_stmt`'s borrowed branch, correct-by-construction argument; m2-backlog "still open" §9).
10. `GList*` declared for GSList-returning stubs (13 sites; `-Wincompatible-pointer-types` is an error on GCC 14+/Clang 16+).
11. Dead stub files: sink-on-non-`GInitiallyUnowned` constructors in files no `dune-generated.inc` references (9 sites; tighten to "sink iff `GInitiallyUnowned`").
12. The fork's `gir_gen/.ocamlformat` 0.29.0 pin vs the `#girgen` shell's build — no working `dune build @fmt` on the fork; a bead of its own.

