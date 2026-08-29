Title: Fix four GObject reference-ownership classes in the generated stubs

Branch: `dlobraico:upstream/gobject-ownership` (one commit on top of `main`)

## The bug

Three distinct symptoms, one underlying accounting error:

- `GtkFlowBoxChild ... has a parent GtkFlowBox ... during dispose. ... Did you
  call g_object_unref() instead of gtk_widget_unparent()?` — reproducible under
  Xvfb, a still-parented widget disposed out from under its container.
- `GTK_IS_EVENT_CONTROLLER` criticals, then segfaults, on widget teardown.
- Unbounded RSS growth from constructors on a per-frame path
  (`gdk_memory_texture_new` is the measurable one).

## Root cause

ocgtk's object wrapper (`ml_gobject_val_of_ext`, `common/wrappers.h`) claims a
reference that its finalizer unconditionally drops with a single
`g_object_unref`. The arithmetic therefore only balances if every call site
that wraps a transfer-none or floating pointer acquires a reference first, and
every call site that hands a wrapper's pointer to an API that consumes it hands
over a reference of its own. Four ownership classes got this wrong.

**Missing sink on a borrowed return.** `ml_g_value_get_object`:
`g_value_get_object` returns a borrowed pointer, but every generated signal
marshaller for an object-typed parameter and every object-typed property read
goes through this function. Each wrapper it produced carried an extra,
unbalanced unref — harmless while something else keeps the refcount
comfortably above zero, and fatal the moment the wrapper is collected while the
object is still parented. This is the `FlowBoxChild ... during dispose`
critical.

**Borrowed elements of a transfer-container GList.**
`gtk_flow_box_get_selected_children` is transfer-container: the list nodes are
ours to free, but each `GtkFlowBoxChild *` element is transfer-none — exactly
like `get_child_at_index` and `get_child_at_pos` in the same file. Unlike
those, this one wrapped the element without sinking it.

**Transfer-full in-parameter.** `gtk_widget_add_controller` consumes the
caller's reference on the controller, while the OCaml wrapper's finalizer still
drops its own. The wrapper's only reference was double-dropped at widget
teardown plus wrapper collection.

**Over-sinking a transfer-full constructor return.** `gdk_memory_texture_new`,
`gtk_gesture_click_new`, `gtk_gesture_drag_new`, `gtk_gesture_stylus_new`,
`gtk_event_controller_key_new`, `g_menu_new`, `g_menu_item_new` and
`g_simple_action_new` all return a single owned, non-floating reference for
types that are **not** `GInitiallyUnowned`. The generator emitted its
floating-constructor boilerplate `g_object_ref_sink()` for them anyway, adding
a second reference nothing ever dropped.

## The fix

`g_object_ref_sink` on the borrowed `g_value_get_object` return and on the
borrowed GList elements; `g_object_ref` around the consumed
`add_controller` argument; and removal of the spurious `g_object_ref_sink` from
the eight transfer-full constructors.

## A note on the generated files

Most of the files touched here live under `generated/`. This commit patches the
already-checked-in stubs by hand so the fix is reviewable and bisectable on its
own; the companion PR fixes `gir_gen` itself so regeneration converges on
exactly this output. If you would rather take the generator change first and
regenerate, that is fine by us — say so and we will reorder the two PRs and
replace this diff with the regenerator's output. The hand-patched comments
already point at the generator change.

## Verification

Full suite on the branch: 28 suites, 366 tests, 0 failures
(`dune build && xvfb-run -a dune runtest --force`). The suite is unchanged in
size; the ownership behaviour itself is covered by the generator tests in the
companion PR, which assert on the emitted C for each of these four cases.

## Relation to the other PRs

- **`gir_gen` ownership fixes** — the generator-side counterpart. It is the one
  that makes this permanent; see the note above about the ordering.
- **Floating-GVariant UAF in SimpleAction** — same hazard class, GVariant's
  floating-ref convention instead of `GInitiallyUnowned`'s. Independent
  branches; both touch `ml_gobject.c` but in different functions and they merge
  cleanly.
- Applies to `main` on its own; no dependency on the closure-marshal PR.
