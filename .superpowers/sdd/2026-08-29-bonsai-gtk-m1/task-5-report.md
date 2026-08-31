# Task 5 report — Numbers and feedback: SpinButton, Scale, ProgressBar, Spinner

**Status:** complete. **Branch:** `m1`. **Commit:** `c0ba9fd` ("SpinButton, Scale, ProgressBar, Spinner"), on top of `bff0794`. Tree clean; nothing pushed.

## What landed

| File | Change |
|---|---|
| `vtree/attr.ml(i)` | `Name.On_value_changed` (classified `is_event = true`), `On_value_changed of float Handler.t`, `name`/`equal` arms, `Attr.on_value_changed` with docs |
| `vtree/kind.ml(i)` | `spin_button_props`, `scale_props`, `progress_bar_props`, `spinner_props` + four `Kind.t` arms, `name`, `same_kind`, `equal_props` |
| `vtree/node.ml(i)` | `Node.spin_button`, `Node.scale`, `Node.progress_bar`, `Node.spinner` with per-widget docs |
| `src/widgets/w_spin_button.ml` (new) | `value-changed` spec, `set_value_if_needed`, `reassert` |
| `src/widgets/w_scale.ml` (new) | `value-changed` via `W.Range`, `set_value_if_needed`, `reassert` |
| `src/widgets/w_progress_bar.ml` (new) | diffed props only, `reassert = None`, no signals |
| `src/widgets/w_spinner.ml` (new) | one diffed prop, `reassert = None`, no signals |
| `src/widgets/registry.ml` | four arms |
| `src/live_tree.ml` | `range_props` helper + **split** `GtkScale` / `GtkSpinButton` arms, plus `GtkProgressBar` and `GtkSpinner` |
| `src/patcher.ml` | the four new kinds added to `destroy`'s exhaustive match (compiler-forced) |
| `src/attr_apply.ml` | inert `On_value_changed` arms in `set` and `unset` |
| `test_lib/bonsai_gtk_test.ml(i)` | `Action.Set_value of string * float`, dispatched to `On_value_changed` |
| `test/test_widgets.ml`, `test/test_handle.ml`, `test/live/live_controls.ml` | tests below |

## Rulings applied

- **Plan ruling 2 (controlled values).** `Scale` and `SpinButton` write their value only through `Widget_impl.reassert`, comparing against the **widget's** live value, never the previous node's — the Task 4 mechanism, not the brief's/spec's "controlled flag". `update` for both deliberately omits `value` (commented in place). `ProgressBar` and `Spinner` have `reassert = None`.
- **Pre-flight correction (Live_tree).** The brief's `| "GtkScale" | "GtkSpinButton"` arm reading one `W.Range.get_value` is wrong — `GtkSpinButton` is not a `GtkRange`. Implemented as two arms: the scale reads `W.Range.get_value` / `W.Range.get_adjustment` (sound because `Scale.t`'s phantom row contains `` `range ``), the spin button reads `W.Spin_button.get_value` / `get_range`.
- **`value-changed` on both.** For the scale it is `W.Range.on_value_changed`, for the spin button `W.Spin_button.on_value_changed`. Both `fire`s read the value back off the widget (GTK's signal carries no payload, and the widget's number is the clamped/rounded one the user sees).
- **Float comparison: exact `Float.( <> )`, no epsilon.** Documented in `w_spin_button.ml`. Rationale: GTK clamps a written value into `[min, max]` and rounds it to `digits`, so a model value the widget cannot represent never compares equal and is re-written on every patch — but `gtk_adjustment_set_value` is itself a no-op when the clamped result is unchanged, so the cost is one C call and no emission. An epsilon would instead let a *real* divergence smaller than the epsilon stand, which is the failure §6.5 exists to prevent.
- **Bounds/step/digits are ordinary uncontrolled props**, diffed in `update`. The page increment is `step *. 10.` (documented on both `Node.spin_button` and `Node.scale`); a local `page` helper in each impl rather than a cross-module reference.
- **Constructor defaults** as the brief specifies: `step = 1.`; `digits = 0` (spin) / `1` (scale, GTK's own); `numeric = true` (deliberately *not* GTK's `false`); `wrap`, `activates_default`, `inverted`, `show_text` false; `draw_value`, `has_origin` true. `min`/`max`/`value` (and `fraction`, `spinning`, `orientation`) are required labelled arguments and so carry no `[@sexp_drop_if]`.
- **Deliberately not exposed**, each with an mli note: scale marks (`add_mark`/`clear_marks` — list-valued with no per-item removal), `gtk_progress_bar_pulse` (stateful timer-driven animation; use `Node.spinner`, or `Node.native` for a pulsing bar), and the spin button's `climb_rate`/`snap_to_ticks`/`update_policy`/adjustment.

## Tests (verbatim RED → GREEN)

**RED** (`dune build @all`, before any implementation): `Unbound value "Node.spin_button"` (test_widgets.ml:108), `Unbound value "Node.scale"` (test_handle.ml:263), `Unbound value "Attr.on_value_changed"` (live_controls.ml:260).

**Headless** (`test/test_widgets.ml`): "the numeric family's constructors" — confirms every `[@sexp_drop_if]` default drops, e.g. `(Spin_button ((value 120) (min 40) (max 280)))` for a `~step:1.` spin button, and `(Scale ((orientation Horizontal) (value 7) (min 1) (max 32) (draw_value false)))`.

**Headless** (`test/test_handle.ml`): "Set_value goes through the model, which may refuse it" — a scale whose model clamps at 8; `Set_value ("s", 9.5)` renders `(value 8)`, i.e. the action goes through the handler and the *model* decides. Also extended the existing missing-handler test to `Set_value ("echo", 1.)` → `node echo has no on_value_changed handler`.

**Live** (`test/live/live_controls.ml`, appended): mounts scale + spin button + progress bar + spinner, then

```
value-changed reaching Bonsai outside a patch: 2
model wins: scale 3, spin 3
value-changed reaching Bonsai from patches: 0
```

The first line proves both specs are connected (each class's own `value-changed`, emitted by hand outside a patch). The middle line is the claim: the scale was dragged to 7 and the spin button spun to 42 behind the model's back, then patched with the tree unchanged at 3 — `reassert` pulled both back. The third line is the reentrancy guard: none of those writes reached Bonsai. A final patch to 6 dumps the whole family, showing `(GtkScale (value 6) (range 0 10))`, `(GtkSpinButton (value 6) (range 0 100) numeric)`, `(GtkProgressBar (fraction 0.6) (text p) show-text)`, `(GtkSpinner spinning)`.

**Gate:** `nix develop -c ./scripts/ci.sh` → `all green` (ocgtk pin, format, build, opam files, headless tests, xvfb live tests, example smoke). The `exception in frame ... a Node.window may only be the root node` line on stderr during the live phase is `live_driver.ml`'s pre-existing intentional negative test, not a regression.

## Concerns / notes for later tasks

1. `Live_tree` prints `numeric` on every `GtkSpinButton` this library builds, because the node default (`true`) differs from GTK's own (`false`) and `flag_prop` prints what is true. Deliberate — it reflects the library's chosen default — but it is a constant line in every future spin-button dump.
2. The scale dump reads its bounds through `W.Range.get_adjustment` + `W.Adjustment.get_lower/get_upper` because `W.Range` binds no `get_range`; the spin button uses its own `get_range`. Cosmetic asymmetry only.
3. `Attr.t` remains a public unsealed variant, so this task's new constructor is another breaking change for any downstream exhaustive match. That is the deferred Open Question 1; Task 11 records it in the M2 backlog.
4. Nothing in `README.md`'s widget catalogue was touched — that is Task 11's job.
