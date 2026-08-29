Title: Add Glib_bytes.of_bigstring, and declare GBytes payload size to the GC

Branch: `dlobraico:upstream/glib-bytes` (one commit on top of `main`)

## The bugs

Two related gaps on the `GBytes` path.

### 1. No way to build a GBytes from a Bigarray

The only constructor was `Glib_bytes.create`, which takes an OCaml string.
A caller holding a `Bigarray` — a decoded image buffer, say — had to
materialise the whole buffer as an OCaml string first, and `ml_g_bytes_new`
then copied *that* into the GBytes. Two copies, plus a large short-lived
major-heap allocation, on every call.

### 2. GBytes declared zero external memory

Both GBytes-wrapping stubs used `caml_alloc_custom(..., 0, 1)` — declaring
**zero** external memory for a payload that can be tens of megabytes. The GC
therefore had no reason to run often enough to reach the GBytes and texture
finalizers, so a workload that allocates a GBytes per frame accumulated
C-heap memory that was freed in principle and never in practice.

## The fixes

### `of_bigstring`

```ocaml
external of_bigstring :
  (char, Bigarray.int8_unsigned_elt, Bigarray.c_layout) Bigarray.Array1.t -> t
  = "ml_g_bytes_new_from_bigarray"
```

Copies once, straight into the GBytes. The stub reads the data pointer and byte
size and calls `g_bytes_new` immediately, with no OCaml allocation in between,
so nothing can move the bigarray out from under `Caml_ba_data_val` before the
copy completes. The result shares no memory with the bigarray and has no
lifetime coupling to it — the bigarray may be freed as soon as the call
returns.

### External memory accounting

Declare the real payload size at every allocation site, via a small
`alloc_gbytes_custom` helper, and have the finalizer balance it. The freed byte
count must equal the declared one; both are the GBytes payload size, which is
immutable, so `g_bytes_get_size` in the finalizer always matches the size
declared at allocation.

Which runtime call to use **cannot be decided from `OCAML_VERSION`**, which is
why this carries a configurator probe rather than a version test:

- On stock OCaml 5.x, `caml_alloc_custom_mem` paces via `custom_major_ratio`
  and `caml_alloc_custom_dep` does not exist.
- On OxCaml — which reports a stock version number —
  `caml_alloc_custom_mem` only picks minor-vs-major placement
  (`caml_adjust_gc_speed` is a compat no-op there) and is inert for pacing,
  while `caml_alloc_custom_dep` tracks dependent bytes instead and requires a
  matching two-argument `caml_free_dependent_memory` in the finalizer.

So `src/configurator/probe_custom_dep.ml` compiles a program that re-declares
both functions with the dependent-memory signatures; a toolchain whose headers
declare `caml_free_dependent_memory` with one argument fails on the conflicting
prototype. The probe defines `OCGTK_HAS_CAML_ALLOC_CUSTOM_DEP` when supported
and nothing otherwise. It only re-declares the functions and never references
them, so it compiles and links without the OCaml runtime library.

## Verification

`tests/test_glib_bytes.ml` gains an `of_bigstring` group: content equality,
empty and embedded-NUL payloads, and a copy proof that mutates the source
bigarray and forces two `Gc.compact` calls before re-reading the GBytes.

Full suite on the branch: 28 suites, 370 tests, 0 failures
(`dune build && xvfb-run -a dune runtest --force`).

The accounting change has no direct assertion — it is a GC-pacing hint, not an
observable API — so it is covered only by the existing GBytes tests continuing
to pass. Happy to add a `Gc.stat`-based test if you would like one, though it
would be inherently timing-sensitive.

## Relation to the other PRs

- **`gir_gen` ownership fixes** — that PR remaps `GBytes` from `Ts_none` to
  `Ts_boxed "g_bytes_get_type"`, which is about *reference acquisition* on
  borrowed GBytes returns. This PR is about *payload size accounting* on the
  wrapper. They touch different concerns and different files; independent in
  either order.
- Applies to `main` on its own.
