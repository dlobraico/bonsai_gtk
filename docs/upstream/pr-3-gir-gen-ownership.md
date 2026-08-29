Title: gir_gen: gate ref_sink on transfer, ref transfer-full in-params, fix GList element ownership, map GBytes as boxed

Branch: `dlobraico:upstream/gir-gen-ownership` (one commit on top of `main`)

## The bug

The generator emits stubs with four systematic reference-ownership errors. The
resulting crashes and leaks, and the hand-patched stubs, are the subject of the
companion PR; this one fixes the generator so regeneration converges on the
corrected output.

There is also a hard portability bug: **`gir_gen` does not compile at all** on a
toolchain where the legacy `result` compatibility package is in scope. It
shadows `Stdlib.Result` with a module that has no `bind`, and nine `let* ` 
definitions across seven files say bare `Result.bind`. Verified against `main`:
`dune build @gir_gen/all` fails with `Error: Unbound value Result.bind`.

## Root cause and fix, per class

Every ocgtk wrapper's finalizer releases exactly one reference, so the
generator must emit a matching acquire at every site that wraps a borrowed
pointer, and hand out a fresh reference at every site that gives a pointer to a
callee that takes ownership.

**Constructors (`c_stub_constructor.ml`).** `g_object_ref_sink` was emitted for
every `Ts_gobject` constructor return "regardless of transfer annotation". That
is correct only for the floating return of a `GInitiallyUnowned`-derived class;
for a transfer-full return (plain `GObject` classes such as `GdkTexture`,
`GtkGesture*`, `GtkEventController*`, `GMenu`, `GMenuItem`, `GSimpleAction`) it
adds a second reference nothing ever drops. The sink is now gated on the return
transfer, mirroring the method path's `generate_ref_sink_stmt`. That needs the
annotation to survive parsing, so `gir_constructor` gains `ctor_return_transfer`
and `gir_parser` stops discarding the constructor's `<return-value>`. A missing
annotation still defaults to `TransferNone`, i.e. it fails toward an extra
`ref_sink` (a bounded leak) rather than toward a use-after-free.

**Transfer-full GObject in-parameters (`c_stub_helpers.ml`).** When the callee
takes ownership of an object argument (`gtk_widget_add_controller` is the
canonical case) the stub passed the wrapper's only reference while the
wrapper's finalizer went on dropping it too. The stub now emits `g_object_ref`
around the argument, with a nullable form that re-reads the pure `Option_val`
expression rather than introducing a statement expression.

**GList/GSList element ownership (`c_stub_list_conv.ml`).** Element conversion
ignored the return's transfer mode entirely. For transfer-none and
transfer-container returns the elements are borrowed, so an adopting converter
must acquire first: `g_object_ref_sink` for GObjects, `g_boxed_copy` for opaque
boxed records, `g_variant_ref` for GVariants. Copying converters (strings,
value-like records) and value-encoded elements (enums, bitfields, primitives)
are ownership-agnostic and are left alone. A borrowed pointer to a GType-less
opaque record has no way to take a reference at all, so it now falls through to
the existing loud TODO placeholder instead of producing a finalizer that frees
callee-owned memory. The mirror-image bug is fixed in `generate_list_cleanup`:
for transfer-full returns, elements whose converter COPIES leave the owned
original behind, which was leaked — those now get `g_list_free_full` /
`g_boxed_free`, while elements whose wrapper adopts the pointer still free only
the nodes.

**GBytes (`type_mappings.ml`).** GBytes was mapped `Ts_none`, so borrowed
GBytes returns were wrapped without acquiring anything even though `Val_GBytes`
adopts and its finalizer unrefs. GBytes is a refcounted boxed type whose
`g_boxed_copy` is `g_bytes_ref`, so `Ts_boxed "g_bytes_get_type"` gives exactly
the right transfer-none handling on both returns and borrowed list elements.

**Portability.** The nine `( let* )` definitions are now `Stdlib.Result.bind`
— `c_stub_bitfield.ml`, `c_stub_class.ml`, `c_stub_enum.ml`, `c_stub_record.ml`,
`signal_gen.ml`, `override_parser.ml` (one each) and `version_guard.ml` (three).
No unqualified `Result.bind` remains under `gir_gen/`.

## Verification

Eleven new generator tests in `gir_gen/test/c_stubs/generation_tests.ml` assert
on the emitted C: the constructor transfer gate (none / floating / full), the
transfer-full in-param ref and its transfer-none counterpart, the GBytes
transfer-none and transfer-full returns, and four borrowed/owned GList element
cases.

`dune build @gir_gen/all && dune runtest gir_gen --force`: 561 tests, 0
failures, including all 33 `C Stubs` cases. On `main` this command does not get
as far as running — see the `Result.bind` note above.

## Relation to the other PRs

- **GObject ownership in the generated stubs** — the companion PR, which
  hand-patches the stubs this change would now emit. Either order works; if you
  prefer to take this one first and regenerate, we will drop that PR's diff in
  favour of the regenerator's output.
- Independent of the other four branches; applies to `main` on its own and
  touches only `gir_gen/`.
