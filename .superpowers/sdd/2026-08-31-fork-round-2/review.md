# Review: ocgtk fork round 2 (`r2-bindings`, 649498b4..9f294eed)

Reviewer: independent verification of every commit, the regenerated tree, the four new
runtime suites (run under `xvfb-run -a`), the gir_gen suite, a hand mutation of the
copy-out stub, a full scratch-worktree regeneration at head AND base, the three patch
files, the pin hash, and the opam switch state.

## Verdict: **Request changes** — narrowly

The generator work is correct, complete for everything in scope, and verified end to
end; every quantitative claim in the report that I could test reproduced exactly (616
gir_gen tests, the regen site counts of 153/19/30/411/29, RSS −856 KB, the mutation
failure, byte-identical fresh ML, the pin hash). The request-changes is about one thing:
the report's failure-shape sweep claim is **false**, and the same blind spot is baked
into `docs/dev-notes.md`'s permanent sweep instructions — seven live, compiled,
memory-unsafe array-out-param stubs (in six files) remain in the tree while the round's record says
"all safe". They are pre-existing (present at the base, untouched by this branch), so
the fix I'm asking for is documentation + a filed follow-up, not a rework of the branch.
Everything else is approve-quality.

---

## C — critical

### C1. The "only copying converters remain" sweep claim is false; seven array-out-param stubs are still memory-unsafe, and dev-notes' documented sweep cannot see them

The report states: *"the only `Val_x(&out)` left are copying converters (TextIter,
TreeIter, Border, Requisition, GdkRGBA, GskPathPoint) and `Val_GValue_copy` — all
safe."* Sweeping the regenerated tree myself with a pattern that also matches array
elements (`Val_[A-Za-z0-9_]+\(&out[0-9]`) finds seven additional live stub functions across six **compiled**
files (all verified present in their namespace's `dune-generated.inc`):

Stack arrays — the exact read-after-return UB of item 1, in the fixed-size-array
out-param path the scalar fix does not cover:
- `ocgtk/src/graphene/generated/ml_box_gen.c:143` — `graphene_box_get_vertices`,
  `graphene_vec3_t out1[8];` … `Val_graphene_vec3_t(&out1[i])`
- `ocgtk/src/graphene/generated/ml_frustum_gen.c:104` — `graphene_frustum_get_planes`,
  `graphene_plane_t out1[6];`
- `ocgtk/src/graphene/generated/ml_rect_gen.c:297` — `graphene_rect_get_vertices`,
  `graphene_vec2_t out1[4];`

`Val_graphene_vec3_t` is `ml_gir_record_val_ptr_with_type(...)` — an ADOPTING boxed
wrap (`ml_vec3_gen.c:23-26`), so each element is a pointer into a destroyed stack frame
plus a finalizer that will `g_boxed_free` stack memory. Exposed in the public MLIs
(`rect.mli:156 external get_vertices`, `frustum.mli:48 get_planes`).

Heap arrays — arguably worse (use-after-free plus heap corruption, not just stack UB):
- `ocgtk/src/gdk/generated/ml_display_gen.c:124,148` — `gdk_display_map_keyval` /
  `map_keycode`: each element adopts `&out2[i]`, an *interior* pointer of the
  transfer-full array, then the stub `g_free(out2)`s the whole array
  (`ml_display_gen.c:126`). Every element read is UAF; every element finalizer later
  `g_free`s an interior pointer of an already-freed block (`Val_GdkKeymapKey` →
  `ml_gir_record_val_ptr`, g_free-adopting — `ml_keymap_key_gen.c:23`).
- `ocgtk/src/gtk/generated/ml_gesture_stylus_gen.c:91` — `gtk_gesture_stylus_get_backlog`
  (`gesture_stylus.mli:35`, public), same shape.
- `ocgtk/src/pango/generated/ml_layout_gen.c:557` — `pango_layout_get_log_attrs`, same.

All seven exist byte-identically at the base `649498b4` (verified with `git show`) — **not
a regression of this branch**, and not inside the backlog's counted 153 (its sweep
counted scalar `<type> outN;` locals only). But:

1. `docs/dev-notes.md`'s "sweep the regenerated C before trusting it" section commits
   the regex `Val_[A-Za-z_0-9]+\(&(out|inout)[0-9]+\)` — the trailing `\)` cannot match
   `&out1[i]`, so the next round's mandated sweep is guaranteed to miss the same seven
   sites, and the doc's promise "all should come back clean apart from the dead files"
   is wrong today.
2. The report presents the sweep result as a safety conclusion the controller will rely
   on when closing the backlog item.

**Required:** (a) fix the sweep pattern in `docs/dev-notes.md` and record the seven open
sites there (or fix them — the array-element c→ml conversion can route through the same
`record_out_param_copy` rule: `Val_x(g_boxed_copy(t(), &out1[i]))` closes all seven, and
for the heap arrays the existing free-after-copy already sequences correctly);
(b) correct the report's sweep paragraph; (c) file the follow-up bead for the array
out-param class. The CHANGELOG headline ("By-value record out-parameters no longer point
into a destroyed stack frame") deserves a scoping clause too since `Rect.get_vertices`
still does exactly that.

## I — important

*(none beyond C1 — its heap-array half is the worst content, kept under C1.)*

## M — minor

### M1. Cross-namespace `record_out_param_copy` cannot see `disguised`

`gir_gen/lib/generate/c_stub_helpers.ml` (`record_out_param_copy`): the same-namespace
arm mirrors `val_ptr_call_for_record` (boxed iff `glib_get_type` **and not disguised**),
but the cross-namespace arm matches on `Crt_Record { opaque = false; get_type_func;
value_like = false }` — `Crt_Record` carries no `disguised` field, so a disguised record
with a get_type would be classified `Record_copy_boxed` here while its owning
namespace's converter adopts with `g_free` — mismatched alloc/free. Unreachable today (a
disguised record has no complete type, so it cannot be a by-value out-param), so this is
a latent-consistency note: either mirror `disguised` into `Crt_Record` or leave a
comment stating the unreachability argument.

### M2. `Val_option` double-evaluates its pointer argument; the new copy expressions must never reach it

`wrappers.h:182`: `#define Val_option(ptr, wrapper) ((ptr) ? Val_some(wrapper(ptr)) :
Val_none)`. If a nullable by-value record out-param were ever emitted, the generated
`Val_option(g_boxed_copy(...), Val_x)` would run the copy twice and leak one. I swept
the regenerated tree: zero occurrences today (the char* path dodged the macro with the
`copy_string_g_free_option` *function* — the right pattern). Worth a one-line guard
comment at the macro or a gir_gen test pinning that nullable record out-params (if ever
legal) take a function twin.

### M3. Report tally nit

I measure the ocgtk suite at head as 38 runs / **409** tests, 0 failures (report: 408).
Immaterial — possibly a version-gated test differing between my nixpkgs GTK and the
implementer's shell — but noting it since the report promises recorded numbers.

## N — notes (verifications performed, all positive)

- **N1. Suites, run by me** (pure `nix-shell` on the flake-locked nixpkgs, xvfb via
  `xvfb-run -a`, display :99 never used): gir_gen **616 tests, 0 failures** (486+130);
  ocgtk **38 runs / 409 tests, 0 failures**. The four new suites run for real (verbose
  mode shows the assertions), not skipped: the leak test printed *"RSS grew −856 KB …
  threshold 100000 KB"* — the report's exact number.
- **N2. Copy-out mutation reproduced**: reverted `ml_graphene_rect_union`'s conversion
  to `Val_graphene_rect_t(&out2)` by hand, rebuilt — `test_record_out_copy` FAILS on
  the first case and the run aborts (the finalizer `g_boxed_free`s stack memory), which
  is the strongest possible confirmation the test pins the bug. Tree and `_build`
  restored and re-verified green.
- **N3. Regeneration commit is honest**: in a scratch worktree at `9f294eed`, running
  `./scripts/generate-bindings.sh` produces **zero** diffs in any `.c`/`.h` — the
  committed C is byte-for-byte the head generator's output.
- **N4. Deviation 1's byte-identical claim verified independently**: fresh ML generated
  at base `649498b4` vs at head differs in **zero** files across all 9 namespaces
  (`diff -rq` on both scratch regenerations). Keeping the committed ML was sound, and
  dev-notes records the contract with the correct rationale (the `2ed607d2` SimpleAction
  signatures + the ocamlformat mismatch).
- **N5. Commit 8's "the GIR lies" claim verified**: `gir/Gsk-4.0.gir` annotates
  `gsk_fill_node_new`/`gsk_stroke_node_new` `transfer-ownership="none"` while their own
  return doc says "A new `GskRenderNode`" — the known upstream GSK annotation bug
  (corrected in later GTK). All other render-node ctors are transfer-full. Trusting the
  annotation would have leaked every fill/stroke node; adopting is right, and the
  override is scoped to the `Ts_refcounted` constructor arm only.
- **N6. Refcounted machinery**: the fundamentals table matches an independent GIR audit
  (`glib:fundamental="1"` roots = Gtk.Expression, Gsk.RenderNode, Gdk.Event; 13 Event +
  31 RenderNode + 5 Expression subclasses; ParamSpecExpression's parent is outside the
  bundled GIRs and is correctly keyed by its own c_type → `g_param_spec_ref/unref`).
  The `ocgtk.refcounted` block has full parity with the gobject block (pointer-first
  layout, same `ocgtk_gobject_finalizer_depth` guard, identity compare/hash,
  `custom_fixed_length_default`). 53 decls macro pairs (7 gtk + 32 gsk + 14 gdk).
  Zero `g_object_*` calls on any fundamental in the regenerated tree.
- **N7. Sink rule**: every remaining live ctor sink is on a `GInitiallyUnowned`
  descendant (widgets, Adjustment, CellRenderer/CellArea/TreeViewColumn families); the
  only live ctor sinks removed were fill/stroke node (fundamentals; debug/shadow-node
  removals were stale-tree artifacts, transfer-full in GIR). The 7 remaining ctor sinks
  and 1 borrowed-return sink on non-floating classes sit in files absent from every
  `dune-generated.inc` (verified file by file — dead, as claimed). No borrowed-floating
  case exists where the old `ref_sink` was load-bearing: floating refs exist only for
  `GInitiallyUnowned` by GObject's definition, and explicitly transfer-floating returns
  still sink. List elements keep `ref_sink` — round 1's pinned choice, correctly
  declared out of scope (report deviation 8).
- **N8. char\* rule**: 85 sites (47 plain + 38 option) — counts confirmed.
  `copy_string_g_free` copies before freeing inside one rooted C call under the runtime
  lock; the OCaml GC cannot move or observe the C string; the option twin is a function
  (no double-eval). Transfer-none strings verified untouched (`gtk_widget_get_name`,
  `gtk_editable_get_text` unchanged); property getters verified NOT routed through the
  free (their strings stay owned by the `GValue` that `g_value_unset` releases).
- **N9. Nullable gpointer commits are exact mirrors**: c→ml `Val_option(result,
  ml_gobject_val_of_ext)` after `g_object_ref` (9 getters); ml→c `Option_val(v, conv,
  NULL)` scoped to `gir_type.nullable` only — non-option in-params untouched.
  `expression.mli` already promised `'a obj option` for `evaluate`, so commit 9 makes
  the C match the ML, and `Expression.evaluate (Some …)` is exercised live by the new
  suite. The regen's other new `Option_val` sites are the held-back transfer-full
  in-param class landing (e.g. `gtk_grid_view_new` refs before handing over) — correct.
- **N10. Regen counts audited from the diff**: +153 graphene `g_boxed_copy(&out)`,
  +19 `gdk_rectangle`, +30 `g_memdup2` (incl. the 2 `PangoRectangle` InOut sites, which
  now convert through the pointer — the old code wrapped a `PangoRectangle**`),
  −440 `ref_sink` on borrowed returns (+411 `g_object_ref`, +29 fundamental own-refs),
  +6 `g_boxed_copy(g_bytes_get_type(), …)`. 311 generated files (308 `.c` + 3
  `_decls.h`), zero `.ml`/`.mli`. All exactly as reported.
- **N11. Patch files**: `r2-canary.patch` applies clean in bonsai_gtk and flips exactly
  the one golden line + rewrites the two comments (content reviewed — accurate);
  both pin-bump patches apply clean in their respective repos; both repos' `flake.nix`
  and setup scripts read `ocgtk-pin.json` (no embedded rev anywhere). Stavekeeper source
  spot-check agrees with "no changed call used" (`#get_text` there is
  `gtk_editable_get_text`, transfer-none, untouched; the other `get_text` hits are
  PDFium FFI).
- **N12. Pin hash**: reproduced independently — `nix hash path` over a clean
  `git archive` of `9f294eed` = `sha256-WlZsl0k5Bbren6rzSp39P1VkNW2fUqvTKttu+eBwIbE=`,
  no `.gitattributes` in the repo. **Still a merge-time item**: confirm against GitHub
  with `nix-prefetch-github dlobraico ocgtk --rev 9f294eed…` after pushing, before
  trusting the bumped pins (the report says the same).
- **N13. Switch state**: verified on the PIN as the checkpoint claims —
  `nm _opam/lib/ocgtk/common/libocgtk_common_stubs.a | grep -c ml_refcounted_val_of_ext`
  → 0, stamp reads `649498b4…`. My review never ran opam; both app checkouts left
  clean (`git status` empty everywhere; scratch worktrees removed;
  the copy-out mutation was reverted and the clean build re-run green).
- **N14. Bundle**: `git bundle verify` passes; base `649498b4`, head `9f294eed`,
  matching the branch tip.

## Scope check against the brief

Items 1–8 all delivered where the brief's counts applied; deviations 1–8 in the report
are each justified and, where checkable, checked (deviation 1 proven, deviation 6's
extra 49 sites are real and the same bug class, deviation 4's commit 9 is scoped and
mirror-exact). Out-of-scope items (GSList typing, ocamlformat pin, list-element
`ref_sink`, table-driving the container-list test) correctly left alone.

## What "request changes" concretely asks for

1. `docs/dev-notes.md`: replace the first sweep regex with one that catches array
   elements (e.g. `Val_[A-Za-z0-9_]+\(&(out|inout)[0-9]+` without the closing paren, or
   add a second grep for `&out[0-9]+\[`), and add the seven open array-out-param stub
   functions to the known-open list (or close them in the generator — one arm, see C1).
2. Correct the report's sweep paragraph (and ideally add a scoping clause to the
   CHANGELOG's copy-out headline).
3. File the follow-up bead for the array out-param class (3 stack-UB + 4 heap-UAF
   stub functions across 6 files, all pre-existing).

None of this requires touching the 12 commits' generator logic, which I am satisfied is
correct.

# Re-review (fix round 1): 9f294eed..72cc75f2

## Verdict: **Approve**

All four findings closed the right way — C1 in the generator, not documented around —
and the five commits introduce nothing new. Every claim in the fix-round report that I
could test reproduced, including both mutation claims (one of which I re-ran myself and
got the exact predicted `exit 139`).

## Findings closed

- **C1 — closed.** `generate_array_c_to_ml`'s element expression now consults the same
  `record_out_param_copy` rule as the scalar path (the rule moved to
  `c_stub_type_analysis.ml` with `c_stub_helpers` re-exporting it — no call-site or
  behavior change on the scalar path, verified by the unchanged 622-green scalar tests
  and zero scalar diffs in the regen). The discrimination is intact end-to-end:
  - *Adopting records copied*: `Val_GdkKeymapKey((GdkKeymapKey*)g_memdup2(&out2[i],
    sizeof(GdkKeymapKey)))` in `ml_display_gen.c:123`, `g_boxed_copy` for the three
    graphene stack arrays.
  - *Value-like untouched* (double copy would leak): `ml_border_node_gen.c:70` keeps
    plain `Val_GdkRGBA(&result[i])`, and `Val_GdkRGBA` is `copy_GdkRGBA`
    (`gdk_decls.h:274`) — no second copy anywhere in the regen diff.
  - *Heap-array sequencing*: read the regenerated `map_keyval`, `map_keycode`, and
    `get_backlog` stubs — elements `g_memdup2`'d inside the loop, container `g_free`'d
    after it. Correct.
  - *Container ownership on array returns respected*: `gsk_text_node_get_glyphs` and
    the three `get_color_stops` (GIR transfer-none) copy elements and free nothing;
    `gdk_event_get_history` (transfer-container) and
    `gtk_print_settings_get_page_ranges` (transfer-full) free the container after
    copying. Checked against the GIR annotations directly.
- **M1 — closed** (comment chosen over the field, per the lead): the cross-namespace
  arm carries an accurate unreachability comment naming the exact precondition for ever
  needing to mirror `disguised` into `Crt_Record`.
- **M2 — closed**: `wrappers.h`'s `Val_option` documents the double-evaluation hazard
  and the function-twin rule, and
  `test_nullable_record_out_param_never_reaches_val_option` is precisely the tripwire I
  asked for.
- **M3 — recorded** with command and environment. The tally delta persists and remains
  immaterial (see N3).

## Verification performed

- **Sibling array-return claim (item 2) confirmed both ways**: at `9f294eed` all seven
  sites wrap `&result[i]`/`&out1[i]` through adopting converters (`git show` at that
  rev: `Val_GskColorStop(&result[i])` ×3, `Val_PangoGlyphInfo`, `Val_GdkTimeCoord`,
  `Val_GtkPageRange`, `Val_PangoLogAttr` ×2); at `72cc75f2` every one memdups. My own
  sweep of the whole tree at head (pattern matching any `&var[i]` and any
  `&out/inout/result` prefix) finds **only** the seven copying converters plus the one
  safe `Val_GdkRGBA(&result[i])` — nothing array-shaped remains.
- **gsize ride-along (item 3)**: the six additions are exact-string matches on
  bounded-integer *value macros* (`wrappers.h:217-226`, all `Val_long` casts); no record
  converter can collide with those names, and the regen diff shows exactly the two
  `texture_downloader` lines flipping to `Val_gsize(out1[i])`/`(out2[i])`. Confirmed the
  old shape returned slot addresses as values (wrong data, not unsafe), as claimed.
- **Regeneration honesty (item 4)**: scratch worktree at `72cc75f2`,
  `generate-bindings.sh` → **zero** `.c`/`.h` diffs; the fix-round regen commit touches
  13 generated `.c` files, 16 lines, and **zero** `.ml`/`.mli` (contract intact).
- **Suites (item 5)**: gir_gen **622 tests / 0 failures** (492+130) — matches. ocgtk
  under `xvfb-run -a`: **39 runs / 411 tests / 0 failures** here (see N3 on the count).
  The two new runtime proofs run for real (verbose asserts shown), including the
  vertices case and the heap-array case.
- **Mutation reproduced**: restored `Val_GdkKeymapKey(&out2[i])` in `ml_display_gen.c`
  by hand, rebuilt — `test_heap_array_out` **segfaults, exit 139**, exactly the report's
  claim. Reverted, rebuilt, re-verified green, tree clean. (The stack-array mutation I
  assessed by reading; it is the same shape I reproduced fatally in round 2.)
- **Dev-notes sweeps (item 6)**: ran both corrected patterns at `72cc75f2` verbatim —
  first lists exactly {GdkRGBA, GskPathPoint, GtkBorder, GtkRequisition, GtkTextIter,
  GtkTreeIter, GValue_copy}; second's single hit is `ml_border_node_gen.c:70`, safe.
  The recorded result is accurate, and the regex-blind-spot history is memorialized
  beside the patterns.
- **Deliverables (item 7)**: bundle verifies (contains `72cc75f2` = branch tip,
  requires `649498b4`); both pin-bump patches carry
  `rev = 72cc75f2…` / `hash = sha256-+d4B9viBvnE7q43ge4hy/HrC8vh3+jP/ssXSdB/FKsQ=` and
  `git apply --check` clean **in their own repos** (Stavekeeper checked in Stavekeeper);
  the hash **reproduces** from `nix hash path` over a clean `git archive` of
  `72cc75f2` (post-push `nix-prefetch-github` confirmation still owed, as both reports
  say); canary patch applies clean.
- **CHANGELOG honesty**: the copy-out entry now reads "202 **scalar** stubs" with a
  sibling entry for the 14 array sites and the gsize fix. Scoped correctly.
- **State**: fork clean at `72cc75f2`; switch still on the PIN
  (`ml_refcounted_val_of_ext` absent from the installed archive — re-ran the nm check);
  bonsai_gtk clean except the pre-existing `.beads/issues.jsonl`; Stavekeeper clean;
  scratch worktree removed; `_build` rebuilt clean after the mutation.

## N — notes

- **N1**: The array-conv refactor that unifies the gptr/plain element branches into one
  `element_conv_expr` is behavior-preserving for every non-record path (gptr cast arm
  byte-identical; nullable and non-nullable variants share the same expression as
  before) — confirmed by the zero-diff regeneration outside the 16 intended lines.
- **N2**: The heap-array test leans on "absence of abort" as its observable
  (GdkKeymapKey has no accessors) — legitimate, and the mutation run demonstrates the
  counterfactual crashes ten-out-of-ten as documented.
- **N3**: Tally arithmetic nit, immaterial: the fix round adds **2** runtime tests (the
  heap suite's 1 + `test_record_out_copy`'s new vertices case), so the report's own
  38/408 → 39/409 (+1) is internally short by one; my measurements went 38/409 →
  39/411 (+2, consistent). Same persistent one-test environment delta as round 2,
  0 failures in every reading — nothing to act on beyond this note.

Merge-time items unchanged from round 2: push, `nix-prefetch-github` hash
confirmation, then the two pin bumps + canary patch and each app's CI.
