Title: Fix GC crash from a naked `GValue *` stored in the closure marshaller's argv

Branch: `dlobraico:upstream/closure-gc` (one commit on top of `main`)

## The bug

Connecting a signal handler that allocates, and then letting a major GC slice
run, crashes the runtime. The typical signature is a segfault inside the
marker (`caml_darken` / `mark_slice`) reading a very low address, or silent
heap corruption that surfaces later somewhere unrelated.

## Root cause

`ml_closure_marshal` (`ocgtk/src/common/ml_gobject.c`) builds the `argv` record
it hands to the OCaml callback and stores the marshaller's raw
`const GValue *param_values` straight into field 2:

```c
Store_field(argv_val, 2, (value)param_values);
```

Field 2 is an ordinary scanned field, and OCaml 5 forbids naked pointers
there. As soon as a handler allocates, `argv` is promoted to the major heap
with that C stack address intact, and the next major mark slice follows it: it
reads a header from the C stack and then scans the `GValue` words as OCaml
values. A `GValue`'s `g_type` word is a small even integer for the fundamental
types (`G_TYPE_UINT` is `0x1c`), so the marker takes it for a heap pointer and
dies dereferencing it — `Hd_val(0x1c)` reads `0x14`.

## The fix

Box the pointer in a one-word `Abstract_tag` block, whose payload the GC never
scans, and unbox it in the two readers (`ml_g_closure_get_arg` and
`ml_g_closure_get_arg_type`). This is the idiom `Val_GMainLoop` already uses in
`ml_glib.c`. The "valid only during this callback" contract on `argv` is
unchanged.

Two further corrections in the same GC-safety class, found while auditing the
file:

- `ml_closure_marshal`'s exception path left `result` holding the
  `(exn_ptr | 2)` exception encoding, which is neither a valid immediate nor a
  valid block. The `caml_callback_exn` that follows allocates, so the GC could
  read a misaligned header at `exn_ptr - 6`. The root is now cleared to
  `Val_unit` before anything can collect.

- `ml_raise_gerror` (`ml_glib.c`) used `caml_alloc_small` followed by direct
  `Field()` stores. `caml_alloc_small` leaves the fields uninitialized, and the
  `caml_copy_string` for field 1 allocates and can trigger a minor collection,
  which would scan field 1 as a garbage value. It now uses `caml_alloc` (which
  fills scannable blocks with `Val_unit`) and `Store_field`.

## Verification

`tests/test_closure_with_gc.ml` gains `argv survives Gc.full_major inside the
handler`: it allocates inside the handler, forces `Gc.full_major`, and reads
`argv` again afterwards. `Gc.full_major` is mandatory and `Gc.minor` cannot
substitute — the minor collector never follows a pointer outside the minor
heap, so the three tests already in that file are structurally blind to this
bug.

Applying only the new test file onto `main` and running it: the three existing
cases pass and the new one **segfaults** (SIGSEGV, core dumped). On this branch
all four pass.

Full suite on the branch: 28 suites, 367 tests, 0 failures
(`dune build && xvfb-run -a dune runtest --force`).

## Relation to the other PRs

Independent — it applies to `main` on its own and touches no file that the
other branches change in the same place. It is the first of six ownership and
lifetime fixes; the others are GObject refcounting in the generated stubs, the
same fixes in `gir_gen`, a floating-`GVariant` use-after-free in
`SimpleAction`, `GBytes` memory accounting, and a new `Style_display` module.
