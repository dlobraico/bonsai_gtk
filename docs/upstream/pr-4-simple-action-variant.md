Title: Fix floating-GVariant use-after-free and NULL activate parameter in SimpleAction

Branch: `dlobraico:upstream/simple-action-variant` (one commit on top of `main`)

> **Breaking API change.** `Simple_action.on_activate` and
> `GSimple_action.on_activate` change their callback parameter from
> `~parameter:Gvariant.t` to `~parameter:Gvariant.t option`. This is
> unavoidable — see the second defect below — but it is a signature change and
> it should land in a release that says so. The old type was uninhabited in
> practice for parameterless actions: the callback could never be reached at
> all, so no working call site can break, only ones that were already dead.

## The bugs

Two separate defects make GAction menu items unusable. Both are on the GVariant
ownership path.

### 1. Floating references handed to `Val_GVariant`

`Val_GVariant`'s contract, stated in its own doc comment, is that the pointer
must be a genuine transfer-full (owned, non-floating) reference: the custom
block adopts it and its finalizer unrefs. Every `g_variant_new_*()` constructor
instead returns a **floating** reference.

Passing one straight through looks transfer-full — the pointer is "ours" — but
is not. The first API that takes ownership of it
(`g_menu_item_set_attribute_value`, for instance) calls `g_variant_ref_sink()`
itself, and on an unsunk floating reference that only clears the floating bit
without bumping the count. The refcount stays 1, now owned by that API, while
the OCaml custom block still believes it owns the same reference; its finalizer
then drops the count to 0 and frees memory the other owner still points at. The
observable failure is a menu item whose attribute value is garbage after the
next collection.

This is the same hazard class as the `g_object_ref_sink()` fixes on the GObject
side, for GVariant's own floating-ref convention instead of
`GInitiallyUnowned`.

**Fix:** sink at each `g_variant_new_*()` wrapper before calling
`Val_GVariant`. Sinking an already-floating refcount-1 reference leaves the
count at 1 — still ours, no longer floating — so a later `ref_sink` by a
GTK/GIO API genuinely increments to 2 and our finalizer's single unref
correctly drops it back to 1 instead of 0.

### 2. NULL parameter GValue on the "activate" signal

GAction's "activate" signal carries a NULL parameter GVariant whenever the
action was created with no parameter type (`g_simple_action_new` with a NULL
second argument), which is every plain menu item. `Simple_action.on_activate`'s
marshaller called `Gobject.Value.get_variant`, which raises on NULL. Activating
any plain menu item therefore always raised — and the exception was silently
eaten by the signal marshaller's error path, leaving the menu item inert with
no diagnostic at all.

**Fix:** add `Gobject.Value.get_variant_opt` (`ml_g_value_get_variant_opt`),
the same accessor with NULL mapped to `None` instead of raising, and change
`on_activate`'s callback type to `~parameter:Gvariant.t option`. The
existing `get_variant` is untouched, for callers that legitimately treat a
variant as mandatory.

## Verification

New `tests/test_gio_simple_action.ml`:

- `parameter-less activation does not raise` — creates a `Simple_action` with
  no parameter type, connects `on_activate`, activates it, and asserts the
  callback ran and saw `None`.
- `accel attribute survives Gc.compact` — sets a GVariant attribute on a
  `GMenuItem`, forces `Gc.compact`, and reads the attribute back. This is the
  use-after-free. Reduced to a standalone test file and run against `main`, it
  **segfaults** (SIGSEGV, core dumped) before printing a result; it passes on
  this branch.

Full suite on the branch: 29 suites, 368 tests, 0 failures
(`dune build && xvfb-run -a dune runtest --force`).

## Relation to the other PRs

- **GObject ownership in the generated stubs** — the GObject-side sibling of
  the same floating-reference class. The two branches both touch
  `ml_gobject.c`, in different functions, and merge cleanly in either order.
- Applies to `main` on its own; no dependency on any other branch.
