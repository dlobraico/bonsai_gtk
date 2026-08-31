# M3 pre-flight scan report

Scout run 2026-08-31, against `main` (clean apart from the uncommitted plan file) with
`.ocgtk-src` verified on the pin's commit (`git -C .ocgtk-src log --oneline -1` →
`72cc75f2`, matching `ocgtk-pin.json`). Method: every fact-table row read from the
generated `.mli`s in `.ocgtk-src/ocgtk/src/{gtk,gio,gdk}/generated/` and
`common/`; every runtime question answered by throwaway executables built in a
temporary `test/live/scout/` directory (own `dune`, libraries `ocgtk.gtk ocgtk.gdk
ocgtk.gio ocgtk.common`), run with `xvfb-run -a`, then deleted. The tree ends as it
started (`.beads/issues.jsonl` was already modified before the scan; untouched).

## The fact table, row by row

Every row was spot-checked against the pinned checkout. Verdicts:

| Row | Verdict |
|---|---|
| Alert_dialog / Message_dialog / Dialog | CONFIRMED, one addition below |
| File_dialog / File_chooser_native / Native_dialog / File_chooser / Gio.File | CONFIRMED, one nuance below |
| Gdk.Clipboard / Gobject.Value / Display | CONFIRMED (runtime-proved) |
| Gdk.Rectangle | CONFIRMED |
| Callback_action & co / triggers / Shortcut / parse_string | CONFIRMED, one softening below |
| Simple_action / Gvariant | CONFIRMED |
| Simple_action_group / Action_map / insert_action_group | CONFIRMED |
| Menu / Menu_item | CONFIRMED |
| Header_bar | CONFIRMED (plus an unlisted `set_use_native_controls`; no signals, as stated) |
| Action_bar | CONFIRMED |
| Popover / Menu_button / set_parent | CONFIRMED |
| Shortcut_controller / Event_controller.set_propagation_phase | CONFIRMED (`set_scope : t -> Gtk_enums.shortcutscope`) |
| Window / Application | CONFIRMED (`set_accels_for_action : t -> string -> string array -> unit`; `on_close_request` callback is `unit -> bool`) |
| Style_display / Css_provider / Style_context | CONFIRMED (`Ocgtk_gtk.Style_display` is top-level via `gtk/generated/ocgtk_gtk.ml` line 9; the stub is `gtk/core/style_display.mli` with exactly the three values quoted) |
| Glib.Timeout.add vs Idle.add asymmetry | CONFIRMED verbatim (`common/glib.mli:74-99`) |
| Gesture.set_state | CONFIRMED — `t -> Gtk_enums.eventsequencestate -> bool`, enum is `` `NONE | `CLAIMED | `DENIED `` (`gtk_enums.mli:1044-1051`) |

Additions/nuances (no task changes, worth knowing):

- **`Alert_dialog.show : t -> Window.t option -> unit` IS bound** (single-button
  variant), but with no constructor it is unreachable; the GtkDialog contingency
  stands unchanged.
- **`File_dialog.new_ : unit -> t` exists** along with all its setters — the row's
  claim is still right (the async `open_`/`save`/`select_folder` launchers are
  absent, only the five `*_finish` halves exist), so it still cannot be launched;
  just don't quote the row as "File_dialog has no constructor".
- `File_chooser_dialog` is indeed a type with zero methods (file ends after
  `(* Methods *)`).
- `Gio.File` has no constructor: no `new_for_path` anywhere in
  `gio/generated/app_info_cycle_64c425a0.mli`; `get_path : t -> string option` at
  line 1080.
- `Gdk.Rectangle` additionally has `equal` and `get_type` — still no constructor
  and no field accessors; `Popover.get_pointing_to : t -> bool * Rectangle.t`
  exists (read-back only), the *set* direction stays unusable.
- `Menu_button.set_label`/`set_icon_name` are non-option setters as stated, while
  the getters are `option` — the "no unbind" asymmetry is real.
- `Simple_action.on_activate`'s doc comment (fork-added) confirms `parameter` is
  genuinely `None` for parameterless actions — not a bug to work around.

## Checklist items

### 1. Fact-table signature spot-checks (the four named)

- **`Gesture.set_state` enum values**: `` `NONE ``, `` `CLAIMED ``, `` `DENIED ``
  (`gtk/generated/gtk_enums.mli:1044-1051`), return `bool`. CONFIRMED.
- **`Native_dialog.on_response` callback shape**:
  `?after:bool -> t -> callback:(response_id:int -> unit) -> handler_id`
  (`native_dialog.mli:78-81`). CONFIRMED, and runtime-proved (fired with `-4`, see
  item 3).
- **`Gobject.Value` string round-trip**: `Gobject.Value.create Gobject.Type.string`
  + `set_string`/`get_string` round-trips (`"hello clipboard"` came back intact),
  and `Gdk.Clipboard.set_value` accepts that value with no exception. The write
  really lands: `Clipboard.get_formats` afterwards reports
  `"gchararray text/plain;charset=utf-8 text/plain"`. CONFIRMED (runtime).
- **`Shortcut_trigger.parse_string` on garbage**: CORRECTION (softening). It does
  not segfault and does not return a wrapped NULL you can then explode on — the
  fork's wrapper raises immediately:
  `Failure("ml_gobject_val_of_ext: NULL GObject")` (observed on
  `parse_string "total garbage!!!"`; the valid input `"<Control>a"` round-trips
  through `to_string`). The design consequence is unchanged (build triggers with
  `Keyval_trigger.new_`, never `parse_string`), but the fact table's "a crash
  waiting for a typo" should read "raises `Failure` on garbage".

### 2. GtkDialog on 4.22 — CONFIRMED, plus a synchrony detail

Throwaway ran the exact loop: `Dialog.new_`, `add_button "OK" 1` (returns the
button `Widget.t`), `get_content_area` (a `GtkBox`), `(d :> W.Window.t)` upcast
(plain coercion — the phantom row is contravariant, no `cast` needed),
`set_transient_for`/`set_modal`, `present` (dialog mapped under xvfb),
`Dialog.response d 1` → **`on_response` fired with `response_id=1`,
synchronously, on the caller's stack inside the `response` call** — then
`Window.destroy` and a second drain with no criticals and no warnings on stderr.
Programmatic response works headlessly; the live-test strategy for alerts holds.
Task 10's effect completion must treat the response callback as re-entrant with
whatever calls `response` (the ordinary trampoline discipline covers it; worth a
comment in `w_`/effect code).

### 3. FileChooserNative under xvfb — CONFIRMED, with an environment CORRECTION

- First run **aborted**: `GLib-GIO-ERROR: No GSettings schemas are installed on
  the system` (core dump) the moment the FileChooserNative machinery started. The
  dev shell does not export gtk4's schemas.
- With `GSETTINGS_SCHEMA_DIR=$(pkg-config --variable=prefix gtk4)/share/gsettings-schemas/gtk4-$(pkg-config --modversion gtk4)/glib-2.0/schemas`
  exported, everything works: `new_` + `Native_dialog.show` presents the fallback
  dialog (`get_visible`=true, and `xdotool search --name <title>` finds a real X
  window bearing the dialog's title — no portal involved), `xdotool windowfocus`
  + `key Escape` reaches it, and **`on_response` fires with `response_id=-4`
  (`GTK_RESPONSE_DELETE_EVENT`)** — not `-6`/CANCEL. `Native_dialog.destroy` is
  clean.
- **Touches Task 10 and the CI wiring (Task 12/`scripts/ci.sh` or the flake)**:
  the live dialog test needs the schema dir exported (best fixed once in
  `flake.nix`'s dev shell); the Escape golden should expect `-4` (or accept
  either cancel-ish id).

### 4. Popover popdown vs `in_patch` — CONFIRMED

`closed` is emitted **synchronously, inside the `popdown` call** (handler ran
before `popdown` returned; counter 1 immediately after, no further emission when
pumping). `popup` emits nothing. So the write-provoked emission is exactly what
the `in_patch` guard covers, and Task 5's controlled `~open` design stands as
written — no record-and-decline needed.

### 5. Present-before-present focus — CONFIRMED workable, behavior pinned

Two windows presented in the same burst (no pump between): no crash, both map,
and **the last-presented window is the active one** (w1 active=false, w2
active=true), deterministically. Re-presenting the first afterwards takes the
focus back (w1 active=true, w2 active=false). So presenting a second window in
the same frame does "steal" focus, but deterministically — `live_windows.ml`'s
assertions just have to expect last-present-wins (or present in a meaningful
order). Under `(locks x-display)` this is stable.

### 6. `close-request` veto — CONFIRMED, both halves, plus a probe warning

- Handler returns `true`: window survives (`get_visible`=true after `close` +
  drain), nothing destroyed.
- Handler returns `false`: window goes away (`get_visible`=false) and it really
  is *destroyed*, not hidden — presenting it again produces GTK's "A window is
  shown after it has been destroyed. This will leave the window in an
  inconsistent state" warning.
- **Probe warning for Task 8's tests**: ocgtk's `Widget.on_destroy` handler never
  fires — not on the allowed close and not even on an explicit `Window.destroy`
  (calibrated separately; counter stayed 0 while the destroyed-window warning
  proved destruction). Presumably the fork's dispose-path guard swallows it.
  Live tests must assert destruction via `get_visible`/`get_mapped`/re-present
  behavior, never via a `destroy` signal. (Consistent with the Global Constraint
  to never connect dispose-emitted signals.)

### 7. `Menu` rebuild vs open `PopoverMenu` — CONFIRMED

With the popover open (mapped), `Menu.remove_all` + re-append (including an
`append_submenu`) on the same `GMenu`: no crash, no criticals, the popover stays
mapped and visible, and a subsequent `popdown` is clean. Task 6's patch-in-place
strategy is safe; no need to pop down first.

### 8. `insert_action_group` resolution from a popover — CONFIRMED, with one serious CORRECTION

- **Resolution from an ancestor works**: group inserted on the menu button's
  parent box; `Widget.activate_action_variant (mb) "scout.hit" None` returns
  true and the handler runs. From the *window* (above the group) it returns
  false — the lookup walks up only, scoping as promised.
- **`Simple_action.set_enabled` greys the open menu item live**: with the
  popover open, `set_enabled false` flips the `GtkModelButton` to
  insensitive and `set_enabled true` flips it back — verified by walking the
  popover's widget tree. This held in every ordering of {group on ancestor /
  group on the button} × {group attached before / after `set_menu_model`} ×
  {menu button parented / unparented at `set_menu_model` time} × {handler
  connected} × {action pre-activated}.
- **CORRECTION — the one ordering that breaks, deterministically (3/3 runs)**:
  if `insert_action_group` runs **after the subtree is already rooted in a
  window** (`Window.set_child` first, insert after), the PopoverMenu's item
  never binds: it renders **permanently insensitive**, and `set_enabled` in
  either direction does nothing — while `activate_action_variant` from the menu
  button still resolves and fires. GTK's action-muxer chain is wired when a
  widget is rooted; a group inserted on an already-rooted ancestor is seen by
  the widget-layer lookup but not by the menu tracker's binding.
  **Touches Task 6** (and the menus & input review lens): `Actions` must insert
  its `GSimpleActionGroup` at node *create* (before the patcher parents the
  subtree into a rooted tree) — which is the natural create-time order — and the
  hazard case is *`Attr.actions` first appearing on an already-mounted node in a
  later frame*. That frame must either re-set the menu button's model (rebuild
  the popover so the tracker rebinds) or the mli must document that a menu's
  action group has to be present from the menu button's mount. Also worth a
  handle/live test pinning whichever rule Task 6 picks.
- Bonus observation: `activate_action_variant` on a *disabled* action returns
  `true` (found) and does not run the handler — don't use its return value as
  "did it fire".

### 9. `Patcher`'s `Update` kind-change arm — CONFIRMED present, lines noted

`src/patcher.ml:912-944` (pre-split numbering). The arm reads `l.node` before
`patch` (912-917), calls `patch` at 918-925 — which, on a kind change, mounts the
replacement and **destroys the old live** — and only then, in the else-branch at
930-943, does `ops.remove parent l.widget` (941) + `ops.insert` (942). The
comment at 931-939 itself says a `Window` live in a list "would be destroyed for
real before this `remove` … worth re-checking if windows ever become list
children". Task 8's fix touches exactly that else-branch (the
remove-then-insert at 940-942, and/or ordering relative to the `patch` call at
918); note Task 1 moves this file, so find it post-split by the comment text.

### 10. `Driver.root_widget` consumers — listed

`grep -rn root_widget test/ examples/`: **no hits in `examples/`**. All call
sites (every one `Option.value_exn (… root_widget …)`):

- `test/live/live_driver.ml`: lines 162, 167, 192, 210, 225, 257, 262, 282, 323, 350
- `test/live/live_lists.ml`: lines 598, 1069, 1739
- `test/live/live_text.ml`: lines 591, 1226, 2094, 2171, 2183

(Plus the definition/`on_root_widget_changed` uses in `src/driver.ml(i)`,
`src/embed.ml:53,105`, `src/signals.mli:35-37`.) Task 8's file list should
include the three live test files if the `Windows`-root `None` answer changes any
of their setups; none of them uses a `Windows` root today, so the existing
`value_exn`s stay valid.

### 11. `grab_focus` timing for `Attr.autofocus` — ANSWERED: before present works

Probed via `Window.get_focus` (NOT `Widget.has_focus` — on a `GtkEntry` the real
focus widget is its internal `GtkText` child, so `has_focus` on the entry itself
is always false; Task 2's live assertions must use `Window.get_focus` +
descendant check, or probe the `GtkText`):

- **Grab before present, on an unrealized, unmapped widget**: `grab_focus`
  returns `true`, `Window.get_focus` is already the entry's `GtkText` before
  present, **and it sticks after the window maps** (focus still inside the
  entry, not the first-in-tree widget; window active).
- Grab after present+map (control): also works, moves focus as expected.

So the fixup-queue grab before `on_window_created` presents is sufficient —
no map-signal one-shot needed. M2's "needs a realized, mapped widget" worry does
not apply to this path on GTK 4.22/xvfb. Task 2 can implement `Attr.autofocus`
exactly as the plan's interface sketch describes.

### 12. stavekeeper still builds — CONFIRMED

`dune build @all` in `~/src/stavekeeper`: exit 0. The plan's line-number
citations are current.

## Corrections summary (paste into "Pre-flight corrections")

1. **(Task 6, important)** `insert_action_group` on a widget that is *already
   rooted in a window* resolves for activation but never binds the PopoverMenu
   item tracker: the menu item is permanently insensitive and
   `Simple_action.set_enabled` has no effect on it (deterministic, 3/3). Groups
   inserted any time *before* rooting work fully, including live greying of an
   open popover. `Actions` must insert groups at create/mount (pre-rooting); an
   `Attr.actions` that first appears on an already-mounted node must force the
   menu button to re-set its menu model (rebind), or the limitation must be
   documented and tested.
2. **(Task 10 + Task 12/CI, important)** FileChooserNative aborts the process
   (`GLib-GIO-ERROR: No GSettings schemas are installed`) under the current dev
   shell; export gtk4's schema dir (fix once in `flake.nix`) before any live
   dialog test. With schemas present the planned live strategy works end to end;
   xdotool Escape yields `response_id=-4` (DELETE_EVENT), not CANCEL — pin `-4`
   or accept both.
3. **(Task 8, minor)** ocgtk's `Widget.on_destroy` never delivers (even on
   explicit `Window.destroy`); assert window destruction in tests via
   `get_visible`/`get_mapped`, never a destroy signal. Both close-request veto
   halves otherwise behave exactly as designed (veto keeps the window alive;
   `false` really destroys).
4. **(Task 8/live_windows, minor)** Presenting two windows in one burst is safe
   but the *last* present takes focus, deterministically; re-presenting an
   earlier window takes it back. Write `live_windows.ml` assertions to
   last-present-wins.
5. **(Task 2, minor)** `Attr.autofocus`'s grab works from the fixup queue
   *before* present and sticks after map — no post-present ordering needed. Test
   assertions must probe `Window.get_focus` (the focus widget for an entry is
   its internal `GtkText`, so `has_focus` on the entry reads false).
6. **(Task 10, note)** `Dialog.on_response` fires synchronously on the stack of
   the `Dialog.response` caller (response_id delivered correctly, destroy clean)
   — fine for the planned design, just keep the trampoline discipline in mind
   when the effect itself calls `response`.
7. **(Fact table, wording)** `Shortcut_trigger.parse_string` on garbage raises
   `Failure("ml_gobject_val_of_ext: NULL GObject")` rather than crashing or
   returning a wrapped NULL — the "never parse_string" rule stands, the "crash
   waiting for a typo" phrasing overstates it. Also: `Alert_dialog.show`
   (single-button) and `File_dialog.new_` do exist — neither changes the
   contingency rulings, but don't quote the table as "no constructor" for
   File_dialog.
8. **(Task 5, confirmation with teeth)** Popover `closed` is emitted
   synchronously inside `popdown` — the `in_patch` guard covers the
   write-provoked emission; controlled `~open` as planned, no record-and-decline.
9. **(Task 6, confirmation)** Rebuilding a `GMenu` (`remove_all` + re-append)
   while its PopoverMenu is open is safe; no pop-down-first needed.

Everything else in the fact table and the plan's ocgtk quotations is CONFIRMED
against `72cc75f2` as written.
