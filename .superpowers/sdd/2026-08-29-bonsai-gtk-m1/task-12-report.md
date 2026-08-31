# Task 12 report: `scripts/ci.sh` end to end from a clean tree, and the M1 catalogue check

Branch `m1`, HEAD `886b1d5` (unchanged — no code changes, no commits). No subagents used.

## 1. Clean rebuild

```bash
cd ~/src/bonsai_gtk
git status --short          # empty before starting
nix develop -c bash -c 'dune clean && echo DUNE_CLEAN_OK'
```
→ `DUNE_CLEAN_OK`.

```bash
nix develop -c bash -c './scripts/ci.sh'
```

Elapsed: **30s**. Exit code: **0**.

Verbatim stdout/stderr (full output — the whole log, not a tail, since it's short):

```
== nix: ocgtk pin builds and passes its tests
== format
== build
== generated opam files are committed
== pure + headless tests
== live tests (xvfb)
bonsai_gtk: exception in frame, stopping the driver: (Invalid_argument
  "root/0/1: a Node.window may only be the root node, not a child of another node")
== example smoke
all green
```

The `Invalid_argument` line is a log message from a §11 error-handling live test
(a `Node.window` nested under another node — driver is expected to catch and report
this, not crash), printed to stderr mid-run; the script does not treat it as a
failure and `all green` follows. Every stage — `nix build .#ocgtk`, format, `@all`
build, the `.opam` diff gate, `@test/runtest`, `@test/live/runtest` under `xvfb-run`,
and both example smokes (`counter`, `gallery`, expected exit 124 under `timeout`) —
passed on the first attempt. Nothing in Step 2's fix-it list was needed.

## 2. Post-run drift check

```bash
git status --short
```
→ empty. No `.opam` regeneration, no formatting diffs, no other drift. Step 4
(final commit) does not apply — nothing changed.

## 3. M1 catalogue vs. `src/widgets/`, by hand

Spec §7's M1 line (`docs/superpowers/specs/2026-08-28-bonsai-gtk-design.md:544-548`):

> Button, ToggleButton, CheckButton, Switch, Entry, PasswordEntry, SearchEntry,
> SpinButton, Scale, ProgressBar, Spinner, Image, Picture, Separator,
> ScrolledWindow, Frame, Expander, Grid, CenterBox, Paned, Overlay, Revealer,
> Stack + StackSwitcher + StackSidebar, `Node.native` — 29 `Node.*` constructors
> in all.

`ls src/widgets/`:

| Spec name | File | Present |
| --- | --- | --- |
| Button | `w_button.ml` | yes |
| ToggleButton | `w_toggle_button.ml` | yes |
| CheckButton | `w_check_button.ml` | yes |
| Switch | `w_switch.ml` | yes |
| Entry | `w_entry.ml` | yes |
| PasswordEntry | `w_password_entry.ml` | yes |
| SearchEntry | `w_search_entry.ml` | yes |
| SpinButton | `w_spin_button.ml` | yes |
| Scale | `w_scale.ml` | yes |
| ProgressBar | `w_progress_bar.ml` | yes |
| Spinner | `w_spinner.ml` | yes |
| Image | `w_image.ml` | yes |
| Picture | `w_picture.ml` | yes |
| Separator | `w_separator.ml` | yes |
| ScrolledWindow | `w_scrolled_window.ml` | yes |
| Frame | `w_frame.ml` | yes |
| Expander | `w_expander.ml` | yes |
| Grid | `w_grid.ml` | yes |
| CenterBox | `w_center_box.ml` | yes |
| Paned | `w_paned.ml` | yes |
| Overlay | `w_overlay.ml` | yes |
| Revealer | `w_revealer.ml` | yes |
| Stack | `w_stack.ml` | yes |
| StackSwitcher | `w_stack_switcher.ml` | yes |
| StackSidebar | `w_stack_sidebar.ml` | yes |
| `Node.native` | (mechanism in `vtree/node.mli`, dispatched via `Native _` in `registry.ml`; not a `src/widgets/*.ml` file of its own) | yes |

All 25 named M1 widgets have a file; `Node.native` is confirmed as a registry
arm (`Native n -> Native_gtk.impl_of_payload n`), extended with `Native.Picture`
in Task 6 per the brief.

**Extra files in `src/widgets/`** (expected, not M1's — M0's and infra):
`registry.ml` (the dispatch table itself, not a widget), `w_box.ml` (Box, M0),
`w_label.ml` (Label, M0), `w_window.ml` (Window, M0).

```bash
grep -c '| [A-Z]' src/widgets/registry.ml
```
→ **29** — one arm per `Node.*` kind (`Label`, `Button`, `Toggle_button`,
`Check_button`, `Switch`, `Entry`, `Password_entry`, `Search_entry`,
`Spin_button`, `Scale`, `Progress_bar`, `Spinner`, `Image`, `Picture`,
`Separator`, `Scrolled_window`, `Frame`, `Expander`, `Revealer`, `Box`, `Grid`,
`Stack`, `Stack_switcher`, `Stack_sidebar`, `Center_box`, `Paned`, `Overlay`,
`Window`) plus `Native _`. Matches "one arm per kind, plus Native" exactly.

## 4. Constructor count vs. `test/test_gallery.ml`

```bash
grep -c '^val ' vtree/node.mli
```
→ **30** = 29 `Node.*` constructors (`label`, `button`, `toggle_button`,
`check_button`, `switch`, `entry`, `password_entry`, `search_entry`,
`spin_button`, `scale`, `progress_bar`, `spinner`, `image`, `picture`,
`separator`, `scrolled_window`, `frame`, `expander`, `revealer`, `box`, `grid`,
`stack`, `stack_switcher`, `stack_sidebar`, `center_box`, `paned`, `overlay`,
`window`, `native`) + `find_by_test_id`. Matches "29 constructors +
`find_by_test_id`" exactly.

Cross-checked every one of the 29 constructor names against `Node\.<name>\b` in
`test/test_gallery.ml` — all 29 appear at least once (counts ranged 1–13, e.g.
`label` ×13, `box` ×6, `button` ×3, `separator` ×2, the rest ×1). None missing.

## Summary

Clean-tree CI passes end to end with zero fixes needed; the tree is unchanged
and free of drift; every M1-line widget has a file and a registry arm; the
29-constructor count in `vtree/node.mli` is exact and every constructor is
exercised in `test/test_gallery.ml`. M1's catalogue checks out against the spec.
