# Task 14 review — ocgtk fork patches (`m2-bindings`, `d98d9397..4ea70268`)

Reviewed: the five fork commits, the bonsai_gtk side `e7a1e7e..cc762d1`, and
`task-14-pin-bump.patch`. Read first: `task-14-brief.md`, `task-14-report.md` in full, the
plan's Global Constraints addendum (`docs/superpowers/plans/2026-08-29-bonsai-gtk-m2.md:49-61`),
the fork's `AGENTS.md` / `gir_gen/README.md` / `architecture/gir_gen/overrides.md`, and the
six prior fork commits.

**Gates re-run independently** (all in `nix develop ~/src/stavekeeper#girgen`):

| check | result |
|---|---|
| `xvfb-run -a dune test ocgtk/ --force` at `4ea70268` | **33 suites, 388 tests, 0 failures** — reproduces the report exactly |
| `dune test gir_gen/ --force` | **574 tests, 0 failures** — reproduces exactly |
| `git ls-remote git@github.com:dlobraico/ocgtk.git refs/heads/m2-bindings` | `4ea702684784253cf4823d0725f6ad867cb8e6be` — **matches local HEAD** (item 8 ✅) |
| `ci.sh` with the patched fork installed + `task-14-pin-bump.patch` | **`all green`, exit 0** (item 7 ✅; patch applied via `git apply --check` clean) |
| `ci.sh` with the pin restored, tree as committed | **`all green`, exit 0** on the second attempt; the first attempt hit an unrelated focus-timing flake — see M11 |

**Mutation checks** (transient in-tree edits, reverted immediately; both trees verified clean
afterwards):

| mutation | result |
|---|---|
| `ml_gobject.c:763` guard → `if (0 && …)` | `test_dispose_reentry`: counting case OK, then **`Segmentation fault (core dumped)`** at the allocating case. The report's claim reproduces exactly. |
| `ml_list_box_gen.c:235` sink removed | `test_transfer_container_lists`: **`[FAIL] element ownership 0 ListBox.get_selected_rows surv…`**. Pins the fix (see Minor M7 — it fails fast here, it does not hang). |

I also confirmed the guard is genuinely on the hot path rather than passing vacuously:
`_build/…/_tests/GObject finalizer re-entry/dispose during finalization.00{0,1,2,4}.output`
each contain **ten** `ocgtk: dropping a "destroy" emission …` warnings, and case `003` (the
hand-emitted control) contains none.

---

## Summary

The engineering is strong and the report is unusually honest — the "stale generated tree"
finding reframes the task correctly, the generator-vs-hand-patch decision for items 1–3 is the
right one and is argued from the fork's own history, and the 4c audit is real: I had the full
279-constructor removal set re-derived independently against the bundled GIRs plus the system
`GObject-2.0.gir`, walking both the C-declared type's chain and the GIR-declared return type's
chain, and **none of the 279 descends from `GInitiallyUnowned`**; the 441 → 162 arithmetic is
exact; the 151 kept sinks in compiled `gtk` code are all genuinely floating. Re-running the
generator produces **zero** `g_object_ref_sink` differences against the committed tree for
every file that actually compiles. Item 4d is accurate and correctly prioritised, including the
two claims I checked by hand.

One thing does not survive review. Commit `a913c307` reaches three Pango sites that are
**`transfer-ownership="full"`, not container**, and at one of them the generator's free loop
frees a pointer the caller still owns. `ml_glyph_item_gen.c:59` is a **new double-free /
use-after-free that this branch introduces** — before the commit those elements leaked, which
kept the caller's pointer valid. That is Critical and has to be fixed before the pin moves,
even though nothing in bonsai_gtk or Stavekeeper calls it.

Two further gaps are worth holding the branch for one revision: the 4b sweep misses
`gtk_builder_get_objects`, which is the *identical* bug at the *identical* severity as the
ListBox one that motivated the commit; and the 4a guard is installed on only one of the three
custom-block finalisers that can reach `g_object_unref`, so the segfault it fixes is still
reachable through a GValue.

`ci.sh` is green in both directions and nothing was pushed by me.

---

## Per-item judgement

| item | verdict |
|---|---|
| **1–3** nullable string bindings (`e281d8f3`, `bcd39f14`) | **Approved.** Generator+override was the right call; the override files are exactly where the maintainer's docs put them; the `class_gen_property.ml` bug is real, was genuinely unreachable before, and the fix is right. Doc gap I6. |
| **4a** finaliser re-entry guard (`7619876c`) | **Approved with fixes.** Correct under OCaml 5 for the reason given; mutation-verified. Incomplete (I2), unbounded warning (I3), undocumented semantic change (I4). |
| **4b** transfer-container list sinks (`a913c307`) | **Needs fixes.** 19 GObject sinks and the FlowBox respell are correct. The three Pango sites are misclassified, and one of them (C1) is a memory-corruption regression. Sweep incomplete (I1). |
| **4c** constructor `ref_sink` removal (`4ea70268`) | **Approved.** 279/279 audited independently and clean. Comment bug I5. |
| **5** "hand-applied regeneration" claim | **Holds.** Regeneration reproduces the committed sink counts exactly for every compiled file; the 9-file discrepancy is in files not in any `dune-generated.inc`. |
| **6** item 4d findings | **Accurate.** Both claims I spot-checked verify (see below). |
| **7** `ci.sh` against the patched fork | **Green.** |
| **8** pushed branch == local | **Yes**, `4ea70268…`. |

**4d spot-checks.** #4 (the `char*` leak) verifies: `ml_text_buffer_gen.c:246-247` is
`char* result = gtk_text_buffer_get_text(…); CAMLreturn(caml_copy_string(result));` with no
`g_free` — 56 `caml_copy_string(result)` sites in generated gtk stubs share the shape. #1 (the
in-param hazard) verifies: `gtk_string_filter_new`'s `expression` parameter is
`transfer-ownership="full"` over `<type name="Gtk.Expression"/>` (`gir/Gtk-4.0.gir:138092 ff.`),
and `GtkExpression` is `glib:fundamental="1"` with its own ref/unref — so the held-back
generator rule really would emit `g_object_ref` on a non-GObject. Holding it back is correct.

---

## Critical

### C1 — `ml_glyph_item_gen.c:59`: `Glyph_item.apply_attrs` now double-frees the caller's own record

`ocgtk/src/pango/generated/ml_glyph_item_gen.c:57-59` (added by `a913c307`):

```c
GList* c_result = pango_glyph_item_apply_attrs(PangoGlyphItem_val(self), String_val(arg1), PangoAttrList_val(arg2));
Val_GSList_with(c_result, result, item, cell, Val_PangoGlyphItem((gpointer)_tmp->data));
{ GSList* _l; for (_l = c_result; _l != NULL; _l = _l->next) g_boxed_free(pango_glyph_item_get_type(), _l->data); g_slist_free(c_result); }
```

`pango_glyph_item_apply_attrs` is **not** transfer-container. `gir/Pango-1.0.gir:9327-9348`:
the instance parameter is `transfer-ownership="full"` and the doc says, verbatim, *"This
function takes ownership of @glyph_item; it will be reused as one of the elements in the
list."* The returned list therefore **aliases the caller's own pointer**, and that pointer is
the one inside the live OCaml `self` custom block (allocated by `copy_PangoGlyphItem`,
`ml_glyph_item_gen.c:19-24`, whose finaliser is `g_boxed_free` via `finalize_gir_record`,
`ocgtk/src/common/wrappers.c:42-49`).

`Val_PangoGlyphItem` is `copy_PangoGlyphItem` (`pango_decls.h:95`), i.e. the wrappers hold
independent `g_boxed_copy` copies — so the new loop frees the **originals**, one of which
`self` still owns.

Failure scenario: `let parts = Glyph_item.apply_attrs gi text attrs in …` — `gi` is dangling
the moment `apply_attrs` returns. Any later `Glyph_item.split gi …` reads freed memory, and
when `gi` is collected `finalize_gir_record` calls `pango_glyph_item_free` on it a second time
→ heap corruption / abort.

**This is a regression introduced by the branch.** At the pin the elements simply leaked, which
left `self`'s pointer valid and freed exactly once.

Sibling sites `ml_attr_list_gen.c:149` and `ml_attr_iterator_gen.c:65` have the same free loop
but are **correct**: their instance params are `transfer none` and Pango returns freshly
allocated attributes, so the loop frees things we own and closes a real per-attribute leak.
Only the GlyphItem one aliases.

The generator rule that produced it (`c_stub_list_conv.ml`, `TransferFull` +
`is_value_type_record`) is generically right and cannot see instance-param/return aliasing.
Fix: an `(ignore)`-style exception for this one function, or drop the free loop there and
accept the (pre-existing) leak, with a comment saying why.

---

## Important

### I1 — the 4b sweep misses `gtk_builder_get_objects`, the same bug at the same severity

`ocgtk/src/gtk/generated/ml_builder_gen.c:120-122`:

```c
GList* c_result = gtk_builder_get_objects(GtkBuilder_val(self));
Val_GSList_with(c_result, result, item, cell, ml_gobject_val_of_ext((gpointer)_tmp->data));
g_slist_free(c_result);
```

`gir/Gtk-4.0.gir:17128-17140`: `<return-value transfer-ownership="container">` over a
`GLib.SList` of `GObject.Object`, doc *"Note that this function does not increment the
reference counts of the returned objects."* And `ml_gobject_val_of_ext`
(`ocgtk/src/common/wrappers.c:180-194`) explicitly does **not** ref — *"Caller is responsible
for managing refcount based on transfer-ownership"* — while `finalize_gobject` unconditionally
unrefs.

That is exactly `gtk_list_box_get_selected_rows`. Failure scenario: `Builder.get_objects b`,
drop the wrappers, `Gc.full_major` → every object the builder constructed is disposed while the
builder still holds it; the next `Builder.get_object b "id"` returns a freed pointer.

The generator skipped it because a bare `GObject.Object` element maps to
`ml_gobject_val_of_ext` rather than a `Ts_gobject` `Val_*` macro — so "regeneration produces
exactly these hunks" is true of the generator, but the generator has a hole here. The commit's
"21 of 21" framing implies the class is closed; it is not. Either fix the site and the
generator branch, or say explicitly in the message that the bare-`GObject` element case is
still open.

### I2 — the finaliser guard is on one of three finalisers that can reach `g_object_unref`

`7619876c` bumps `ocgtk_gobject_finalizer_depth` only inside `finalize_gobject`
(`wrappers.c:126-128`). Two other custom-block finalisers can drop the last reference to a
GObject and provoke exactly the same dispose → emission → `caml_callback_exn`-from-inside-the-
collector crash, with the counter at zero:

- **`finalize_gvalue`, `ocgtk/src/common/ml_gobject.c:175-181`** — `g_value_unset(&mlgv->gvalue)`
  on an object-typed GValue calls `g_object_unref`. This is reachable from OCaml:
  `ml_g_object_get_property` (`ml_gobject.c:610`) fills an OCaml-held GValue, and
  `g_object_get_property` on an object-typed property takes a strong reference. bonsai_gtk's
  `Live_tree` reads properties through a GValue for precisely this kind of workaround.
  Scenario: read a detached widget's `child`/`model` property into a GValue, drop the widget
  wrapper, drop the GValue, collect — `finalize_gvalue` disposes the widget, its `destroy`
  handler allocates, segfault. The guard never sees it.
- **`finalize_gir_record`, `wrappers.c:42-49`** — `g_boxed_free(box->type, box->ptr)`; boxed
  types that own object references release them here.

Fix is one line each: bump/decrement the same counter around those two calls. Cheap, and it
makes the guard's stated contract ("while a wrapper's finaliser is unreffing") actually true.

Related, and the report does flag it as a residual: `ml_closure_invalidate`
(`ml_gobject.c:732-735`) calls `caml_remove_global_root` from the same context, since GObject
invalidates closures during dispose. It does not allocate and the counting test exercises it,
so it is empirically fine on 5.2.0+ox — but nothing pins it, and it is the same hazard class.

*On the OCaml 5 question in the brief:* the thread-local choice is correct. In OCaml 5 a
custom-block finaliser runs on whichever domain sweeps the pool (not necessarily the allocating
one, since pools can be orphaned and adopted), but the increment, the `g_object_unref`, the
dispose and the emission are all strictly synchronous on that one OS thread, so a `__thread`
counter guards exactly the right window regardless of which domain runs it — and, unlike a
global, it cannot silence a legitimate emission on another domain. The `#else` fallback to a
plain global on non-GCC/clang is conservative in the safe direction, as the header says.

*On the "does GTK expect a return value" question:* the early `return` leaves `return_value`
at whatever `g_value_init` left it (the type's default), which is what a
`G_SIGNAL_RUN_LAST`-with-accumulator signal would see. In practice the only signals that reach
this branch are dispose-emitted ones — `destroy`, `unrealize`, `unmap`, `notify::` — none of
which returns a value, so GTK is left consistent. Worth one sentence in the comment, since a
future GTK could emit a value-returning signal from dispose.

### I3 — the guard's `g_warning` is unbounded, and turns a working case into an abort under `fatal-warnings`

`ml_gobject.c:763-780` emits one ~300-byte `g_warning` **per dropped emission**, with no
rate limiting. Measured: 10 warnings per test case in `test_dispose_reentry`. A long-running
Bonsai app collects discarded widgets continuously, and `notify::` handlers are ubiquitous in
a two-way-bound UI, so this is a real stderr flood, not a theoretical one.

Worse: `G_DEBUG=fatal-warnings` (standard in GTK's own CI and common in downstream test
harnesses) and `g_log_set_always_fatal(G_LOG_LEVEL_WARNING)` turn each of these into an abort.
Before the fix, a *non-allocating* dispose-time handler ran fine — the commit message's own
"counting destroy handler survived, 10 emissions". After it, that same program aborts under
fatal-warnings. Recommend a one-shot `static gboolean warned` (or `g_warning` once and
`g_debug` thereafter), which keeps the diagnostic and removes both problems.

### I4 — the semantic change is not stated where a consumer will find it

The fix does not only prevent a crash; it **stops running handlers that previously ran**. The
commit's own measurement says the counting handler survived and fired ten times at the pin; it
now fires zero times. Any consumer using a `destroy` or `notify::` handler for cleanup —
removing itself from a registry, decrementing a live-object count, flushing state — silently
stops doing it, with only a warning on stderr.

bonsai_gtk is safe: the plan's Global Constraints addendum
(`docs/superpowers/plans/2026-08-29-bonsai-gtk-m2.md:51-61`) already forbids the pattern and
Task 13 put the rule in `signals.mli`. But this is a fork-wide behaviour change for every other
consumer and belongs in `CHANGELOG.md` and in the commit's summary line, not only in a C
comment. Nothing in the branch touches `CHANGELOG.md`.

### I5 — `test_constructor_ownership.ml:28-30` documents `GtkAdjustment` as the opposite of what it is

```
(* GtkStringList, GtkTextBuffer, GtkSizeGroup and GtkAdjustment all descend
   from GObject rather than GInitiallyUnowned, so none of them is ever
   floating. *)
```

`GtkAdjustment` descends from `GObject.InitiallyUnowned` — `gir/Gtk-4.0.gir:6771-6774`,
`<class name="Adjustment" … parent="GObject.InitiallyUnowned">`. Its constructor correctly
**kept** its sink (`ml_adjustment_gen.c:26`), and the assertion passes — but for the opposite
reason the comment gives: the sink consumed the floating reference, it was not "never
floating".

Failure scenario: a maintainer takes this comment at face value, concludes `GtkAdjustment` is a
plain GObject that the 4c sweep missed, and deletes `ml_adjustment_gen.c:26`. Then
`Scrollbar.new_ (Some adj)` sinks the float instead of adding a reference, the OCaml finaliser
unrefs, and the scrollbar reads a freed adjustment. That is precisely the use-after-free class
this whole commit was audited to avoid — planted in the documentation rather than the code.
Move `GtkAdjustment` into `test_widgets_are_still_sunk`, or fix the comment.

### I6 — the new `(nullable …)` override action is not in the maintainer's override reference

`gir_gen/README.md`'s "Override System" section is one line: *"See
[architecture/gir_gen/overrides.md](../architecture/gir_gen/overrides.md) for the full override
format reference, architecture, and workflow."* That file was not touched by the branch, and
`architecture/gir_gen/overrides.md:44` still reads `type override_action = Ignore | Set_version
of string`, with the grammar section (lines 83-87) listing only `(ignore)` and `(version …)`.

The `sexp` comments in `ocgtk/overrides/gtk.sexp` are good, but the fork's own documented
contract is that the reference file is the place to look. A maintainer taking this upstream
will find a grammar the docs do not describe. One paragraph in `overrides.md` plus the updated
`override_action` type would close it.

---

## Minor

- **M1 — `override_apply.ml:155-156` describes validation that does not exist.** The comment says
  naming a target on a property "is rejected by the caller below rather than silently ignored".
  There is no such rejection: `property_set_nullable _targets` (line 157) discards its argument
  and `apply_components_by_name` (line 72-74) applies it unconditionally, so
  `(property placeholder-text (nullable bogus))` is silently accepted. Either add the check or
  delete the claim.
- **M2 — `(nullable …)` is a silent no-op on constructors, signals, enum members and fields.**
  `apply_class_components` passes `~set_nullable` only for methods and properties
  (`override_apply.ml:169-182`); constructors (line 163-167) and signals (line 183-188) fall
  through to the identity default, while the parser accepts the qualifier anywhere. The
  entity-level case correctly warns (line 305-314); the component-level ones should too.
- **M3 — `4ea70268`'s message miscounts and mislabels.** "190 files" — the actual figure is 206
  generated `.c` files (208 changed, including the test and its `dune`). The subject lists
  `gtk gio gdk gsk pango` but 19 of the 279 removals are in `gdkpixbuf`.
- **M4 — `a913c307`'s message misclassifies 7 of the 24 sites it touches.** Four
  (`gtk_cell_area_get_focus_siblings` `ml_cell_area_gen.c`, `gtk_size_group_get_widgets`,
  `gtk_application_get_windows`, `g_emblemed_icon_get_emblems`) are `transfer-ownership="none"`,
  not container — the *code* is right (they correctly do not free the list), only the rationale
  is wrong. The three Pango sites are `transfer-ownership="full"`; contrary to the message they
  did **not** get a `g_boxed_copy` added — the copy was already inside `Val_PangoAttribute` /
  `Val_PangoGlyphItem`. And the count is 24 call sites, not 21, once the Pango three are folded
  in as the message folds them. This matters beyond pedantry: the stated container rationale is
  what makes C1 look correct.
- **M5 — one of the report's two switch-state proofs is vacuous.** The checkpoint says the
  switch was "verified two ways, not just by the stamp", the second being that the guard's
  `g_warning` string is *"absent from `_opam/lib/ocgtk/*.a`"*. That glob matches only
  `_opam/lib/ocgtk/ocgtk.a`, which never contains C-stub strings; the string actually lives in
  `_opam/lib/ocgtk/common/libocgtk_common_stubs.a`. I checked with the **patched** fork
  installed: `strings _opam/lib/ocgtk/ocgtk.a | grep -c 'ocgtk: dropping'` → `0`, while
  `strings _opam/lib/ocgtk/common/libocgtk_common_stubs.a | grep -c dropping` → `1`. The check
  returns "absent" either way. The `bonsai-gtk-ocgtk-rev` stamp is the real evidence and it was
  correct.
- **M6 — the pin-bump patch leaves a comment that becomes false.** `src/widgets/w_password_entry.ml`
  keeps *"Unlike [GtkEntry]'s and [GtkSearchEntry]'s, this setter is not nullable — hence the
  [""] on the update path below"* directly above the call the patch changes to pass `Some t`.
  After the pin moves that sentence is wrong. The report flags the behavioural follow-up but not
  this comment; it is a one-line addition to the patch.
- **M7 — the ListBox mutation does not reproduce as described.** The report says removing the sink
  from `ml_list_box_gen.c` leaves the suite "still running when killed at 60 s and again at
  90 s". In my run it produced a clean `[FAIL] element ownership 0 …` within seconds. The test
  pins the fix either way; the characterisation just is not reproducible, and a reader trying to
  re-derive it will be confused.
- **M8 — `test_dispose_reentry.ml`'s three finalisation cases assert nothing.** They end in
  `check bool "…" true true`; `fired` is incremented in the handler and never read. The real
  assertion is "the process did not segfault", which is legitimate for this bug, but the cases
  cannot distinguish "emission dropped" from "handler ran". Adding
  `check int "no handler ran during finalisation" 0 !fired` would pin the actual contract, and
  would catch a future "fix" that runs the handler unsafely without crashing on this machine.
- **M9 — `test_transfer_container_lists.ml` pins 2 of the 24 sites.** Only `GtkListBox` and
  `GtkFlowBox` are exercised; `text_iter`, `tree_view`, `cell_layout`, `size_group`,
  `window_group`, `accessible_list`, `application`, `gesture`, `emblemed_icon`, the four GDK
  sites and all three Pango sites are unpinned — which is why C1 got through. The refcount-
  invariance case (the technique that generalises) is applied only to ListBox; lifting it into a
  table-driven helper is the cheap way to cover the class. Note also that all cases sit behind
  `require_gtk`, which `Alcotest.skip ()`s without a display, so on a display-less runner the
  file pins nothing at all.
- **M10 — informational, pre-existing, deserves its own issue.** 31 of the 279 constructors in
  the removal list build non-GObject fundamentals: 28 `GskRenderNode` subclasses and 3
  `GtkExpression` subclasses (`ml_constant_expression_gen.c:25`, `ml_object_expression_gen.c:25`,
  `ml_property_expression_gen.c:25`). Their wrappers still go through `ml_gobject_val_of_ext`,
  whose finaliser is `g_object_unref(G_OBJECT(ptr))` — an *invalid cast* critical plus a leak on
  every collection. **Not caused by this commit** (the removed `ref_sink` short-circuited on
  `G_IS_OBJECT` the same way, so the refcount is 1 before and after); the commit removes one
  bogus critical per construction and leaves the leak. The report's 4d #3 sees part of this;
  it is the same root cause as 4d #1's `GtkExpression` hazard and should be fixed with it.
  Relatedly, the report's 4d #3 count of "11 constructors keep a sink on a
  non-`GInitiallyUnowned` type" is 9 by my count once the names are enumerated, and 9 of the 11
  sink lines sit in files that are in **no** `dune-generated.inc` (`ml_gl_renderer_gen.c`,
  `ml_vulkan_renderer_gen.c`, and five Gio-Unix files whose types have moved to
  `GioUnix-2.0.gir`) — i.e. they are dead code, which the report does not say.

- **M11 — not Task 14's, but found while re-running its gates: `test/live/expected_controllers.txt`
  is flaky.** On my first `ci.sh` run against the *restored pin* (i.e. the tree exactly as
  committed, nothing of this task installed) the live tests failed with

  ```
  -|n1 focus from presenting the window: focus-enter
  -|n1 focus parked off the target: focus-leave
  +|n1 focus from presenting the window: focus-enter,focus-leave
  +|n1 focus parked off the target:
  ```

  i.e. the `focus-leave` arrived one frame earlier than the golden expects. Three subsequent
  `dune build @test/live/runtest --force` runs and a second full `ci.sh` were all green, so it
  is a timing flake in the controllers focus test under Xvfb, not a regression — but it will
  bite whoever runs this gate next, and it is exactly the sort of thing that gets misattributed
  to a pin bump. Worth a bead of its own.

---

## State left

Exactly as found, and verified:

- `.ocgtk-src` on **`m2-bindings`** at `4ea70268`, `git status --porcelain` **empty**.
- `bonsai_gtk` on `m2` at `cc762d1`, working tree clean apart from the pre-existing untracked
  `.beads/issues.jsonl`.
- The opam switch was returned to the **pin** with the report's exact restore commands
  (`_opam/.opam-switch/bonsai-gtk-ocgtk-rev` = `d98d939711d315cfb595d472594407044ff4f147`,
  matching `ocgtk-pin.json`), and `ci.sh` re-run on the restored state: **`all green`, exit 0**.
- Nothing was pushed. No tracked file was left modified in either repository. The two mutation
  edits and the `task-14-pin-bump.patch` application were reverted with `git checkout --`.

---

## Verdict

**Needs fixes** — one Critical and, in my judgement, I1 and I2 with it.

C1 is a memory-corruption regression the branch introduces; it must not go onto the pin. I1 is
the same defect class the branch exists to close, left open one file away from the one it
closed, and it is cheaper to fix now than to explain later. I2 leaves the segfault 4a fixes
reachable by a second route with a two-line change available.

Everything else here is text: I3–I6 and the Minors are comments, counts, a `CHANGELOG` entry
and a docs paragraph. None of them blocks the pin.

To be clear about what is *not* in doubt: the 4c audit is sound and I re-derived it
independently; both regression tests genuinely fail without their fixes; the test counts and
the pushed SHA reproduce exactly; `ci.sh` is green against the patched fork with the supplied
patch; and the report's account of what it did and did not do is accurate everywhere I checked
it except M5's second switch-state proof.

Suggested order: fix C1 (an override or a comment plus dropping the loop at that one site) and
I1 (the builder site, plus the generator's bare-`GObject` element branch) as a sixth and
seventh commit or as fixups into `a913c307`; add the two counter bumps for I2 into `7619876c`;
then sweep I3–I6 and the Minors. Re-push, re-prefetch, and the pin bump goes ahead unchanged —
`task-14-pin-bump.patch` is independent of all of it.

---

# Re-review — fix round 1 (`4ea70268..cd071aa1`, six commits)

Scoped to the range. I re-derived every counting claim rather than reading it, mutation-tested
the three fixes whose value depends on a test actually failing without them, and settled the
floating-reference question with a standalone GTK probe rather than by reasoning.

**Gates re-run independently:**

| check | result |
|---|---|
| `xvfb-run -a dune test ocgtk/ --force` at `cd071aa1` | **35 runs, 403 tests, 0 failures** — reproduces the report exactly (35/403 because `test_dispose_reentry` runs twice; 34 suites / 397 distinct) |
| `dune test gir_gen/ --force` | **593 tests, 0 failures** — reproduces exactly |
| `ci.sh`, fix-round fork installed + refreshed `task-14-pin-bump.patch` | **`all green`, exit 0**; `git apply --check` clean |
| `ci.sh`, pin restored, tree as committed | **`all green`, exit 0** |

**Mutation checks** (transient in-tree edits, reverted immediately; `git status --porcelain`
empty afterwards both times):

| mutation | result | claim |
|---|---|---|
| restore the per-element `g_boxed_free` loop in `ml_glyph_item_gen.c` | `test_glyph_item_alias`: **`Segmentation fault (core dumped)`** | confirmed |
| drop the two guard lines around `g_value_unset` | `test_dispose_reentry`: **`FAIL no handler ran during GValue finalization … Received: '10'`** | confirmed, and exactly the "runs, ten of ten" the report describes |
| restore a per-occurrence `g_warning` in `ocgtk_report_dropped_emission` | same binary under `G_DEBUG=fatal-warnings`: **exit 134** (SIGABRT) | confirmed |

---

## C1 — the fix direction is right, and the residual is honestly scoped

`ocgtk/src/pango/generated/ml_glyph_item_gen.c:57-61` now ends in `g_slist_free(c_result);`
alone, under a comment naming the override. The caller's record is no longer freed. The new
`test_glyph_item_alias` suite is not decorative: with the loop restored it segfaults.

The pre-existing leak is **accepted and commented**, not silently absorbed — in
`ocgtk/overrides/pango.sexp` and again in `architecture/gir_gen/overrides.md`. I agree with the
scoping. The "better" fix the lead asks about (copy the record before handing it to a callee
that takes ownership) is the transfer-full **instance-parameter** class, which is the same
family as held-back 4d #1 and is genuinely a different change; doing it here would have meant
shipping an unaudited ownership rule to close a leak that predates the branch. Fixing the
double free and leaving the leak, loudly, is the right trade.

Doing it as a generator override rather than a hand patch is also right, and the round found
the reason it had to be: `gir_gen overrides`, the regenerator that `overrides.md` itself tells
you to run on a GTK upgrade, rebuilt record entries from `fields` only and **silently dropped a
record's methods** — which would have deleted `(record GlyphItem (method apply_attrs …))` and
put the double free straight back. Fixed in `cd071aa1` with a mutation test. That is a good
find; nothing in the branch would have exposed it except this override.

## The aliasing audit — conclusion sound, headline number wrong

Independently re-parsed all nine bundled GIRs. The load-bearing answers all hold:

| | claimed | mine |
|---|---|---|
| instance-parameter `transfer-ownership="full"` | 1 (`pango_glyph_item_apply_attrs`) | **1**, same function (`gir/Pango-1.0.gir:9327`, instance-param at `:9362`) |
| ordinary parameter `transfer-ownership="full"` | 0 | **0** |
| instance transfer other than none/absent/full | 0 | **0** |
| bare `GObject.Object` list elements | 1 (`gtk_builder_get_objects`) | **1**, same function (`gir/Gtk-4.0.gir:17144`) |

and they hold across *every* candidate population, so **there is no second aliasing site** — the
conclusion the fix rests on is correct. Per-element free loops in the generated tree: two remain
(`ml_attr_list_gen.c:149`, `ml_attr_iterator_gen.c:65`), both correct, as claimed.

See N1 for the one number that does not reproduce.

## I1 — the deviation is justified, and the blast radius is exactly as stated

Going to the type mapping instead of the list branch is a deviation from my ruling and it is the
right call. The argument is not merely asserted, it is *demonstrated*: with only the list branch
fixed, the regression test the ruling itself demands cannot be written, because reading an
object back goes through `gtk_builder_get_object` — the return half of the same hole — and the
suite melts into a GtkBox drain loop. A fix that makes its own regression test unwritable is the
wrong fix.

I verified the blast radius the hard way rather than taking the diff on trust: a second
generator built from `HEAD` with only the two `Ts_gobject` words reverted, both trees fully
regenerated, and the regenerations diffed. **Exactly 13 lines in 11 files, all `.c`, zero `.ml`,
zero `.mli`**, and the twelve function names match the report one-for-one. All 13 GIR returns
are `transfer-ownership="none"` (the list one is `container`), so the "generator emits no ref
for an owned return" gap is not triggered. `ml_builder_gen.c` and `ml_glyph_item_gen.c` are
**byte-identical** to regeneration.

**The floating-reference question, settled empirically.** I compiled a standalone GTK4 probe
(no ocgtk involved) and read `g_object_is_floating` at the reachable sites:

```
builder_get_object GtkBox              floating=0 refs=1
builder_get_object GtkLabel (child)    floating=0 refs=2
builder_get_objects elem (×3)          floating=0
single_selection_get_selected_item     floating=0   (GtkStringObject)
drop_down_get_selected_item            floating=0   (GtkStringObject)
object_expression_get_object           floating=0
task_get_source_object                 floating=0
```

GtkBuilder sinks what it constructs, model items are plain GObjects, and the expression/task
cases return caller-supplied objects. So `g_object_ref_sink ≡ g_object_ref` at all 13 sites and
no floating reference is claimed. See N2 for why I would still change the primitive.

## I2 — all three finalisers, and thread-local is the right scope

`wrappers.c:57-59` (`g_boxed_free`), `wrappers.c:137-139` (`g_object_unref`) and the pair around
`g_value_unset` in `ml_gobject.c` all bump the counter; the `g_free` branch is deliberately left
alone and says why. `wrappers.h`'s header now describes a contract all three keep, where before
it described one only `finalize_gobject` kept.

**On the lead's domains question: thread-local is correct, and I think it is the only correct
choice.** In OCaml 5 a custom-block finaliser runs on whichever domain reclaims the block — for
a minor-heap block the allocating domain, for a major-heap one the domain that sweeps the pool,
which can differ after pool orphaning and adoption. That does not matter here, because the
guard never has to be read by a domain other than the one that set it: the increment, the
`g_object_unref` / `g_value_unset` / `g_boxed_free`, the GTK dispose, the emission and the
`ml_closure_marshal` call are a single synchronous C call chain on one OS thread, and the
finaliser holds the domain lock throughout, so no systhread of that domain can interleave.
`__thread` is per-OS-thread and OCaml 5 domains are OS threads, so the marshaller always reads
the counter the finaliser just bumped, on any domain. A process-wide flag would be *safe* but
over-suppressing — a collection on one domain would silence a legitimate emission on another —
so the header's stated reasoning is right. (Unchanged and out of scope, but worth knowing: GTK
is not thread-safe, so a widget finaliser running on a non-main domain performs an unsafe
dispose regardless of the guard. The guard is not what would make multi-domain GTK work.)

The regression reaches the crash through `finalize_gvalue` specifically — the widget wrappers
are collected first so that the GValue's unref is deterministically the last one, rather than
`finalize_gobject`'s, which was already guarded and would have masked it. That is the right
construction. `finalize_gir_record`'s guard has no test and the commit says so; I would not have
invented one either — no bound boxed type owns a GObject whose dispose reaches an OCaml handler
today.

One consequence worth recording rather than fixing: the guard now covers every `g_boxed_free`,
which runs for every boxed record collected (`GtkTextIter`, `GdkRGBA`, `PangoAttribute`, …), so
the window in which an emission can be dropped is wider than it was. The exposure is tiny, the
reasoning is the same one that justifies the GObject case, and it is strictly safer than
crashing — but it does slightly widen the I4 behaviour change.

## I3 — better than what I asked for

`G_LOG_LEVEL_MESSAGE` once behind `g_once_init_enter`, then `G_LOG_LEVEL_DEBUG`
(`ml_gobject.c:768-787`). My suggestion was a one-shot `g_warning`, which would have fixed the
flood and left the abort — `G_DEBUG=fatal-warnings` and the usual
`g_log_set_always_fatal(G_LOG_LEVEL_WARNING)` both cover `WARNING`, neither covers `MESSAGE`.
Choosing `MESSAGE` satisfies both halves of the finding at once, the diagnostic still prints
under the default handler, the per-signal detail survives at `G_MESSAGES_DEBUG=all`, and the
first message says so, so nobody concludes it happened once. And it is **pinned**, not measured
once: `ocgtk/tests/gtk/dune:152-158` runs the same binary again under
`G_DEBUG=fatal-warnings`, which exits 134 the moment the per-occurrence `g_warning` comes back.

## I4, I5, I6, and the Minors

**I4** — `CHANGELOG.md`'s `[Unreleased]` leads with the behaviour change, in the second person,
saying what stops working, that it is not a no-op ("ten times out of ten" before), what to do
instead, why running it is not an option and why `g_idle_add` is not either, and that all three
finaliser paths hold the guard. The marshaller header carries the same statement plus the
`return_value` answer I asked for. bonsai_gtk's `docs/upstream/README.md` carries it for readers
of that repository. All three places, as ruled.

**I5** — better than the fix I proposed. Rather than moving `GtkAdjustment` into the widget
case, it gets its own, asserting **parentage** (`is_a "GInitiallyUnowned"` true, `is_a
"GtkWidget"` false) rather than only the refcount. The refcount is what made the wrong comment
look right; the parentage is what a maintainer needs to see before deleting a sink.

**I6** — `architecture/gir_gen/overrides.md` now carries a corrected `override_action` type, an
applicability table, a `(nullable …)` section with the three forms, and `(return-aliases-instance)`.

**M1** — genuinely fixed, not just re-worded: `override_parser.ml` hard-errors when
`comp_kind = "property"` and the qualifier carries targets. The `override_apply.ml:155-156`
comment I flagged as false is now true. **M2** — fixed as a hard error via
`qualifier_applies_to` / `check_qualifier`, covering `(nullable …)` and
`(return-aliases-instance)`; I agree a hard error beats the warning I suggested, since the
component kind is decidable from the sexp the parser already holds. **M5** — the new check reads
`common/libocgtk_common_stubs.a`; I saw it report 2 with the fix-round fork installed and the
rev stamp agree, so the switch-state evidence is now real. **M6** — the patch rewrites the
comment, and the replacement explains why the code still writes `Some`. **M8** — fixed, and it
immediately earned its keep: the deterministic `= 0` assertion is what caught I2's mutation when
the crash did not come. **M3/M4/M7/M9/M10/M11** — accepted or partly fixed with reasons I agree
with; M3 and M4 are unfixable without rewriting pushed history, and M4's substantive half (the
misleading rationale) is repaired in the code and the docs where a reader will actually land.

---

## New minors (none blocking)

- **N1 — the aliasing audit's headline count does not reproduce.** `ocgtk/overrides/pango.sexp`
  and `overrides.md` say "of 93 list-returning callables across all nine". Restricted to
  `<method>` / `<function>` / `<constructor>` as the sentence states, the figure is **75** (54
  method, 21 function, 0 constructor; 69 unique `c:identifier`s). 93 is 75 plus the 18
  `<virtual-method>` nodes — but there are also 18 `<callback>` nodes describing the *same* vtable
  slots, so 93 both double-counts one representation and omits the other. The safety conclusion
  is unaffected (I re-ran the three predicates over all four candidate populations and got
  1/0/0 every time), but a maintainer re-deriving the number will not get 93. Change it to 75
  and say "methods, functions and constructors".
- **N2 — `g_object_ref_sink` is still the wrong primitive on the borrowed-return path.** For a
  borrowed reference you want `g_object_ref`; `ref_sink` differs only on a floating object, and
  then it *claims the float* instead of adding a reference, so the wrapper's finaliser would
  destroy an object the container still points at. Nothing reachable is floating today — I
  measured all of it — and this is the same choice `a913c307` already made for list elements, so
  it is consistent rather than newly wrong. But `generate_ref_sink_stmt`'s borrowed-return branch
  would be correct by construction with `g_object_ref`, leaving `ref_sink` to constructors where
  the float is the point.
- **N3 — `docs/dev-notes.md` does not exist.** Ten generated files point at it as the
  authoritative "re-apply on any vendor re-sync" list, including files this round touches
  (`ml_widget_gen.c`, `ml_flow_box_gen.c`, `ml_simple_action_gen.c`, …). `docs/` holds only
  `code_guidelines/` and `plans/`. Pre-existing, but this round adds more hand-applied hunks whose
  survival depends on exactly that discipline, so the missing inventory is now load-bearing.
- **N4 — `GList*` declared for 13 GSList-returning stubs**, including `ml_glyph_item_gen.c:57`,
  which this round edits: `GList* c_result = pango_glyph_item_apply_attrs(…)` then
  `g_slist_free(c_result)`. It works because both structs lead with `data`/`next`, but the types
  are incompatible and `-Wincompatible-pointer-types` is an error by default in GCC 14+ and
  Clang 16+. Builds clean on this toolchain. Pre-existing and systemic (also `ml_file_list_gen.c:95`,
  `ml_display_manager_gen.c:41`, `ml_builder_gen.c:120`, `ml_size_group_gen.c:49`,
  `ml_text_iter_gen.c:217,236,272`, `ml_layout_gen.c:575,596`, and the two attr sites).
- **N5 — stray text inside a doc comment**, `gir_gen/lib/type_mappings.ml:256`: the literal
  `transfer_strategy = Ts_none;` sits mid-sentence inside the `GObject.Value` comment. Harmless
  (it is inside `(* … *)`), pre-existing, and *not* from `95c1d6e8` — but it sits two lines from
  the words that commit changes, so it reads like collateral. Worth deleting while nearby.
- **N6 — the tree is 34 files behind its own generator**, not the one the C1 commit's
  pango-scoped sentence implies: 28 files / 31 sites of the transfer-full GObject in-parameter
  class and 6 borrowed-`GBytes` returns. Both are the report's own held-back 4d #1 and #2, so
  this is disclosed rather than hidden, and six of the 28 are files this branch never touches.
  Combined with N3 there is no in-repo record of it. When 4d #1 is taken up, that inventory is
  the place to start.

---

## State left

- Fork on **`m2-bindings`** at `cd071aa1f695643ce42429fb06c70a8cddf794d7`, `git status
  --porcelain` **empty**.
- bonsai_gtk on `m2` at `ffd827c`, clean apart from the pre-existing untracked `.beads/issues.jsonl`.
- Opam switch returned to the **pin** (`bonsai-gtk-ocgtk-rev` = `d98d9397…`, matching
  `ocgtk-pin.json`), and `ci.sh` re-run green on the restored state.
- Nothing pushed. All three mutation edits and the patch application reverted with
  `git checkout --`. No tracked file left modified in either repository.

## Verdict

**Approved to push+pin.**

Every finding I raised is addressed, and three of them are addressed better than I proposed:
I3's `MESSAGE`-not-`WARNING` choice defeats `fatal-warnings` where my one-shot `g_warning` would
not have; I5 asserts parentage where I would have moved a case; and M2 hard-errors where I
suggested a warning. C1's fix is at the generator with the residual leak stated in two places
and correctly deferred to the in-parameter class. I1's deviation from my ruling is the right
call and the only one that leaves the finding testable — and its blast radius is exactly the 13
lines claimed, which I verified by building a second generator and diffing full regenerations
rather than reading the diff. The floating-reference hazard I would have raised against I1's
`ref_sink` does not materialise anywhere reachable, measured rather than argued.

N1–N6 are a wrong count in a comment, a primitive I would spell differently, a missing docs
file, a pre-existing pointer-type sloppiness, a stray line, and a held-back backlog that is
already written down in the report. None of them touches behaviour and none should hold the pin.

Push `m2-bindings`, `nix-prefetch-github dlobraico ocgtk --rev cd071aa1f695643ce42429fb06c70a8cddf794d7`,
bump `rev` + `hash` in both `ocgtk-pin.json` files, apply `task-14-pin-bump.patch` in bonsai_gtk,
and re-run the gates. I have run the last of those against this exact fork and it is green.
