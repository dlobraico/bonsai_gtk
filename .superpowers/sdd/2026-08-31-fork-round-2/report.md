# ocgtk fork round 2 — generator copy-out and ownership, then regenerate

Branch `r2-bindings` in `/home/dlobraico/src/bonsai_gtk/.ocgtk-src`, twelve commits on
`649498b4` (= `origin/main` = both apps' pin). **Nothing pushed anywhere; no merges; no
`bd`; no commits in bonsai_gtk or Stavekeeper; `ocgtk-pin.json` untouched in both.** The
branch exists only on this disk, so it is bundled:
`.superpowers/sdd/2026-08-31-fork-round-2/r2-bindings.bundle` (`git bundle verify`
passes; base `649498b4`, head `9f294eed`).

## Commits

| # | hash | what |
|---|------|------|
| 1 | `57ba8e40` | ride-along: stray `transfer_strategy = Ts_none;` deleted from the doc comment at `type_mappings.ml:256` (task-14 N5) |
| 2 | `b35f19cc` | **item 1** — record out-parameters copy out of the stack frame (generator; `value_like` in cross-references; InOut double-pointer fix) |
| 3 | `c2ba9c6d` | **item 2** — transfer-full `char*` freed once copied (`copy_string_g_free` + new `_option` twin; single-`char*` branch) |
| 4 | `d141d197` | **item 3** — `Ts_refcounted` table (`refcounted_fundamentals.ml`), the `ocgtk.refcounted` custom block, decls macros, all four generator consumers |
| 5 | `d4636e7d` | **item 6** — constructors sink iff `GInitiallyUnowned` descent (`class_hierarchy.ml`); borrowed returns `g_object_ref`, floating returns still sink (N2) |
| 6 | `aa4c29ab` | **item 5** — nullable `gpointer` returns are options (`gtk_drop_down_get_selected_item` + 8 siblings) |
| 7 | `e1992f53` | **item 7** — `Gobject.unref` exposed; `Gobject.run_dispose` bound (`Window.destroy` was already generated on this base — verified, pinned by test) |
| 8 | `bee0ea27` | fix to #4: a fundamental's ctor adopts plainly even under a lying transfer-none annotation (`gsk_fill_node_new`) |
| 9 | `9a90a712` | found at runtime: nullable `gpointer` **in-params** unwrap their option (`gtk_expression_evaluate`/`bind` segfaulted on `Some`; pre-existing on every branch) |
| 10 | `3de9848d` | **THE regeneration** — 308 `ml_*_gen.c` + 3 `*_decls.h`, C side only |
| 11 | `9fb70975` | verification suites (4 new) + `Gobject.ref_` (so unref is testable) |
| 12 | `9f294eed` | docs: `docs/dev-notes.md`, CHANGELOG, `docs/upstream/README.md` (PR withdrawal) |

## The generator rules, one line each

1. **Copy-out**: a by-value record out-param whose `Val_<CType>` ADOPTS gets
   `g_boxed_copy` (GType) or `g_memdup2` (no GType — finalizer is `g_free`) on the way
   out; records whose converter already COPIES (value-like) are untouched — a second
   copy would leak. "Does the converter copy" is a fact about the owning namespace, so
   `Crt_Record` gains `value_like` in the references format. InOut record locals are
   already pointers; converting `&inoutN` wrapped a `T**` as a `T` (2 PangoRectangle
   sites) — now converts through the pointer.
2. **char\***: a transfer-full `char*` return or out-param routes through
   `copy_string_g_free`/`copy_string_g_free_option` (copy then free inside one rooted C
   call — no cleanup-ordering surgery). Transfer-none strings unchanged; InOut excluded.
3. **Refcounted fundamentals**: `GtkExpression`, `GskRenderNode`, `GdkEvent` (audited
   from `glib:fundamental="1"` in the bundled GIRs) + `GtkParamSpecExpression` (parent
   `GObject.ParamSpec`, keyed by own c_type) resolve through ancestry to
   `Ts_refcounted {root; ref; unref}`: in-params/borrowed returns/list elements take the
   root's own ref (cast to the root type); wrappers go through
   `ml_refcounted_val_of_ext` with the root's unref as finalizer (new custom block,
   pointer-first layout, same re-entry guard as `finalize_gobject`;
   `OCGTK_KIND_REFCOUNTED` in the classifier). Constructors adopt plainly — no floating
   state exists, and the transfer-none annotations on `gsk_fill_node_new`/
   `gsk_stroke_node_new` are GIR bugs (taking their word would leak every node).
4. **Sink rule**: constructor sinks require `GInitiallyUnowned` **ancestry**, not the
   GIR transfer annotation; borrowed method returns take `g_object_ref` (ref_sink on a
   borrowed floating pointer *claims* the float); explicitly transfer-floating returns
   still sink.
5. **gpointer is a pointer** on both nullable paths (c→ml returns AND ml→c in-params).

## Regeneration (commit `3de9848d`) — stats

C side only, wholesale from `scripts/generate-bindings.sh`. The `.ml`/`.mli` are
deliberately not taken: **regenerated ML is byte-identical before vs. after every
generator change on this branch** (measured with `diff -q` across all 9 namespaces
against a baseline regeneration at `649498b4`), while wholesale ML would revert fork
commit `2ed607d2`'s hand-maintained `Gvariant.t option` signatures and rewrap ~936
files under a mismatched ocamlformat. `docs/dev-notes.md` now records that contract.

| class | sites |
|---|---|
| record out-param copy-out | **202** = 172 `g_boxed_copy` (153 graphene — the backlog's exact count — + 19 GdkRectangle the backlog's sweep missed) + 30 `g_memdup2` (PangoRectangle, incl. 2 InOut double-pointer sites) |
| transfer-full `char*` freed | **85** (47 plain + 38 option) |
| borrowed returns ref_sink→ref | **440 removed** = 411 `g_object_ref` + 29 fundamental own-refs |
| transfer-full in-params (held-back class) | **31** `g_object_ref` + **6** `gtk_expression_ref` (the sites that forced the hold-back) |
| decls macro pairs → refcounted | **53** (GdkEvent+14, GskRenderNode+31, GtkExpression+5, GtkParamSpecExpression) |
| GBytes borrowed returns | **6** `g_boxed_copy` (item 4, as predicted) |
| gpointer getters → option | **9** returns; + `evaluate`/`bind` in-params |
| stray ctor sinks removed | 2 live (fill/stroke node); the other 7 sit in dead files no `dune-generated.inc` compiles (ignored classes; stale stubs, never built) |

Failure-shape sweeps over the regenerated tree: the only `Val_x(&out)` left are copying
converters (TextIter, TreeIter, Border, Requisition, GdkRGBA, GskPathPoint) and
`Val_GValue_copy` — all safe; zero `g_object_ref/sink/unref` on any fundamental; the one
remaining borrowed-return ref_sink is in a dead file.

## Proofs, with numbers

- **Graphene copy-out** (`tests/test_record_out_copy.ml`, display-free): a
  `Rect.union` out-param keeps x/y/**width=320**/height after 150 more binding calls
  and a `Gc.full_major`; the tuple-returning `intersection` path likewise; 100
  out-params hold 100 distinct widths. *Mutation:* restoring
  `Val_graphene_rect_t(&out2)` in the union stub fails the first case.
- **`char*` free** (`tests/gtk/test_text_buffer_leak.ml`): 200 whole-buffer reads of a
  1 MB `GtkTextBuffer` — fixed stub: RSS **−856 KB** (noise); *mutation* (plain
  `caml_copy_string` restored): RSS **+198,100 KB**, test fails. Threshold 100 MB
  separates the two by half an order of magnitude each way.
- **Expression ownership** (`tests/gtk/test_refcounted_fundamentals.ml`): 400
  expressions constructed and collected under a GLib-GObject/Gtk critical-counting
  handler — **0 criticals/warnings** (the broken finalizer criticized per collection);
  the wrapper classifies `OCGTK_KIND_REFCOUNTED`; and this is where commit 9's
  segfault was caught — `evaluate` on `Some obj` crashed until the in-param option fix.
- **`get_expression` answers Some** (same file): a set property-expression reads back
  `Some`, **evaluates** against a `GtkStringObject` to the property's value ("alpha"),
  survives a major GC, and clears to `None`. Verified on this machine's GTK (the nix
  shell's GTK 4; the m2-backlog's complaint measured on 4.22 — retest there when a
  4.22 runner exists).
- **`get_selected_item`**: `None` on an empty model; `Some` GtkStringObject on a
  populated one; one wrapper adds exactly one reference and a collection gives exactly
  it back (absolute counts are the drop-down machinery's business — measured 6 with one
  wrapper alive).
- **`run_dispose`/`unref`/`Window.destroy`** (`tests/gtk/test_dispose_controls.ml`):
  dispose releases a GtkBox's child reference while the wrapper survives; `ref_`/`unref`
  round-trip the count; `Window.destroy` is bound and callable.
- **live_input canary**: with the patched fork installed, the golden diff flipped
  exactly one line — `compute_bounds rect survives a later ocgtk call: false → true` —
  and with `r2-canary.patch` applied, the whole live suite is green.

## Suite tallies

| | before (branch base `649498b4`) | after (branch head `9f294eed`) |
|---|---|---|
| gir_gen | 593 tests, 0 failures | **616 tests, 0 failures** (+23) |
| ocgtk (xvfb) | 34 runs / 398 tests, 0 failures | **38 runs / 408 tests, 0 failures** (+4 suites) |
| bonsai_gtk `ci.sh` | green on the pin (repo history) | **all green, exit 0** against the patched fork + `r2-canary.patch`; the first run *without* the canary patch failed on exactly the flipped canary line, as designed |
| bonsai_gtk vs restored pin | — | `dune build @all` green after the switch was restored |

`ci.sh`'s first step (`nix build .#ocgtk`) builds the **pin** from GitHub and cannot see
`.ocgtk-src`; every other step read the opam path pin = the patched fork. The live suite
ran inside ci.sh with `BONSAI_GTK_LIVE_TESTS=1` under xvfb (dynamic display via
`xvfb-run -a`; `:99` never touched).

## Patch files (none committed, per the brief)

All under `.superpowers/sdd/2026-08-31-fork-round-2/`:

- `r2-canary.patch` — bonsai_gtk `test/live/live_input.ml` (both comments rewritten:
  copy-out is now the rule, the canary line is a regression tripwire) +
  `test/live/expected_input.txt` (`survives: false → true`). ocamlformat-clean
  (`@test/live/fmt` passes with it applied). `git apply --check` clean.
- `r2-pin-bump.patch` (bonsai_gtk) and `r2-pin-bump-stavekeeper.patch` — identical
  one-file changes to each repo's `ocgtk-pin.json`:
  `rev = 9f294eede2e27b75d5f22d2be18319e10ca1aeed`,
  `hash = sha256-WlZsl0k5Bbren6rzSp39P1VkNW2fUqvTKttu+eBwIbE=`. Both `git apply --check`
  clean in their repos. Only the pin file is needed — both flake.nix files and both
  setup scripts read it (re-verified this round). Stavekeeper needs **no** source
  change (grep-verified: zero uses of any changed call; not build-verified).
  **Hash caveat:** computed as `nix hash path` over a `git archive` of the tip (no
  `.gitattributes` in the repo, so it should equal `fetchFromGitHub`'s NAR hash) — but
  it could not be checked against GitHub because the branch is unpushed. After pushing,
  confirm with `nix-prefetch-github dlobraico ocgtk --rev 9f294eed…` before trusting it.

## Deviations, with reasons

1. **The regeneration commit covers generated C only.** The brief says "ONE
   regeneration commit"; it is one, but `.ml`/`.mli` were restored to the committed
   tree. Justification measured, not assumed: fresh ML output is byte-identical across
   all of this round's generator changes, and taking it wholesale would revert
   `2ed607d2`'s semantic fix (breaking `test_gio_simple_action`) and bury review under
   ~936 files of ocamlformat rewrap. Recorded permanently in `docs/dev-notes.md`.
2. **`docs/upstream/README.md` was created in the fork** (it did not exist there; the
   historical per-PR tracking doc lives in bonsai_gtk, where I may not commit). It
   records the closure of #173–#178 on 2026-08-31 and the six surviving topic branches.
3. **Commit 8 exists** because commit 4 briefly trusted a transfer-none annotation on
   fundamental constructors; the GIR lies (`gsk_fill_node_new`). Kept as its own commit
   rather than rewriting history mid-branch.
4. **Commit 9 (nullable gpointer in-params) is beyond the brief's list** — found when
   the verification suite segfaulted calling `Expression.evaluate (Some …)`. It is the
   exact ml→c mirror of item 5 and pre-existing on every branch; leaving a known
   segfault ungated was not an option.
5. **`Gobject.ref_` exposed alongside `unref`** (commit 11): `ml_g_object_ref` also
   existed valueless, and unref is untestable without a reference one is entitled to
   drop.
6. **The copy-out closed 202 sites, not 153**: the backlog's sweep counted only
   graphene; GdkRectangle (19, boxed adopt) and PangoRectangle (30, g_free adopt — the
   finalizer freed stack memory) are the same bug and fell to the same rule.
7. **No runtime GskRenderNode construction test**: `Gdk.Rgb_a` has no OCaml-reachable
   allocator, so a ColorNode cannot be built from the test suite. The node class is
   covered structurally (decls + ctor + ancestry gir_gen tests) and shares the exact
   finalizer/ref machinery the expression tests prove live.
8. **The transfer-container list-element path still uses `g_object_ref_sink`**
   (round 1's deliberate choice, pinned by its tests). N2's argument applies there too,
   but the brief scoped item 6 to constructors and borrowed returns; flagged as a
   candidate follow-up, not changed.

## Also found, not asked for

- The InOut record conversion wrapped `&inout1` — a `PangoRectangle**` — as a
  rectangle (2 sites). Fixed inside item 1.
- `gtk_expression_evaluate`/`bind` segfault on `Some` (commit 9, above).
- The 18 hand-written breadcrumb comment lines in generated files ("T5 fix…",
  `score-library-*`, "re-apply on vendor re-sync") were dropped by the regeneration —
  correct, since every rule they described now lives in the generator with tests; the
  scrub-grep concern about score-library comments in diff context is thereby mooted
  for the tree going forward (noted in the fork's new upstream README).

## Carries / follow-ups

- Dead stub files for overridden-away classes (7 with stray sinks, 1 with a
  borrowed-return ref_sink) linger uncompiled; deleting them would silence sweeps.
  Listed in `docs/dev-notes.md`.
- The fork's ocamlformat pin (out of scope per brief) is now the only thing standing
  between the tree and full ML regeneration; dev-notes says so.
- GSList-typed stubs still declared `GList*` (N4, out of scope).
- `test_transfer_container_lists.ml` still pins 3 of 24 sites (task, not fix-round).
- Verify `get_expression → Some` on GTK 4.22 specifically when such a runner exists.
- After pushing: re-run `nix build .#ocgtk` against the real pin (the hermetic
  nix-sandbox build was not run here, for task-14's disk-space reason; the suite DID
  run under `xvfb-run` in the nix dev shell).

# Checkpoint (reboot)

Written 2026-08-31. The round is **finished**; nothing half-applied.

- `.ocgtk-src` on **`r2-bindings`** at `9f294eed`, 12 commits on `649498b4`,
  `git status --porcelain` empty. **Not pushed** — the bundle in this directory is the
  only other copy.
- **bonsai_gtk** on `main` at `801e670`, tree clean except `.beads/issues.jsonl`
  (Beads' own export, present before this round; not mine — no `bd` was run).
- **Stavekeeper** untouched, clean.
- **Opam switch: restored to the PIN** (`649498b4`). Verified by the honest check —
  `nm _opam/lib/ocgtk/common/libocgtk_common_stubs.a | grep -c ml_refcounted_val_of_ext`
  → **0** (the symbol exists only on r2-bindings); the
  `bonsai-gtk-ocgtk-rev` stamp also reads `649498b4…` (it was never changed —
  remember `opam reinstall` does not update it; the symbol is the evidence).
  `dune build @all` in bonsai_gtk is green against the restored pin.
- To install the patched fork again:
  `git -C .ocgtk-src checkout r2-bindings` (already there) then
  `nix develop . -c sh -c 'eval "$(opam env --switch=. --set-switch)" && opam reinstall -y --assume-depexts ocgtk'`,
  and apply `r2-canary.patch` before running the live suite.
- Precise next steps for the controller: push `r2-bindings`; `nix-prefetch-github`
  to confirm the hash; apply the two pin-bump patches + `r2-canary.patch`;
  `./scripts/setup-switch.sh && nix develop . -c ./scripts/ci.sh` in bonsai_gtk;
  `./scripts/setup-ocgtk.sh && nix build .#ocgtk` in Stavekeeper.

---

# Fix round 1

Five commits on `r2-bindings`, on top of `9f294eed` — new head **`72cc75f2`**. History
untouched, same trailers, nothing pushed, no `bd`, no app-repo commits, pins untouched.

```
48c9bd57 gir_gen common: array elements of by-value records copy before the adopting wrap
ead0bb1b gir_gen: bounded-integer array elements convert by value, not by address
0473b317 gdk gsk gtk graphene pango: regenerate the C stubs for the array element copy-out
2d2c551c tests: the array out-param classes proven at runtime, both mutations fatal
72cc75f2 docs: the sweep that could not see array elements, corrected and re-run
```

## C1 — fixed in the generator, not documented around

The full fix, as the lead directed; the reviewer's one-arm judgment held. The array
element c→ml conversion (`generate_array_c_to_ml`) now consults the same
copy-before-adopt rule as the scalar path: `Val_x(g_boxed_copy(t(), &var[i]))` for boxed
records, `(T*)g_memdup2(&var[i], sizeof(T))` for GType-less ones, value-like (copying)
converters and primitives untouched. `record_out_param_copy` moved to
`c_stub_type_analysis.ml` so both callers share it without a dependency cycle
(`c_stub_helpers` re-exports it; no call-site changes).

**The regeneration closed 14 record sites in 12 files, not just the review's 7** — the
same arm serves array RETURNS, where borrowed and transfer-full heap arrays had the
identical interior-pointer hazard the review did not enumerate:

| kind | sites |
|---|---|
| review's stack arrays (fixed-size out-params) | `graphene_box_get_vertices`, `frustum_get_planes`, `rect_get_vertices` — `g_boxed_copy` per element |
| review's heap arrays (out-params) | `gdk_display_map_keyval` + `map_keycode`, `gtk_gesture_stylus_get_backlog`, `pango_layout_get_log_attrs` — `g_memdup2` per element; the transfer-full container `g_free` unchanged and now correctly sequenced (copy in the conversion, free in cleanup) |
| sibling array returns (same hazard, found by the fix) | `gdk_event_get_history`, `gsk_{conic,linear,radial}_gradient_node` `get_color_stops`, `gsk_text_node_get_glyphs`, `gtk_print_settings_get_page_ranges`, `pango_layout_get_log_attrs`'s return variant |

**Ride-along surfaced by the corrected sweep** (`ead0bb1b`): `Val_gsize` and the
bounded-int macros were missing from the primitive-converter list, so
`gdk_texture_downloader_download_bytes_with_planes`'s two `gsize[4]` arrays converted
each element as `Val_gsize(&out1[i])` — the slot's ADDRESS cast to gsize. Wrong values
(not memory-unsafe), live and compiled, pre-existing; fixed and pinned.

### gir_gen tests (+7, → 622 total)

Stack-array boxed copy; value-like array elements untouched (double copy would leak);
heap-array memdup with the container free intact; array-return copy; the M2 Val_option
tripwire; the gsize by-value case; plus the no-raw-slot negations inside each.

### Runtime proofs, both mutation-fatal

- **Stack arrays** (`tests/test_record_out_copy.ml`, display-free):
  `Rect.get_vertices` on a (0,0,320,60) rect reads back exactly xs {0,0,320,320} /
  ys {0,0,60,60}, again after 150 more binding calls and a `Gc.full_major`. *Mutation*
  (restore `Val_graphene_vec2_t(&out1[i])`): FAIL on garbage vertex values, exit 1.
- **Heap arrays** (`tests/gtk/test_heap_array_out.ml`, display-gated): GdkKeymapKey has
  no accessors, so the observable fact IS the crash's absence — `Display.map_keyval`'s
  array taken, dropped, collected hard, taken again; stable, process lives. *Mutation*
  (restore `Val_GdkKeymapKey(&out2[i])`): segfault, exit 139.

## The corrected sweep, re-run (review item a)

`docs/dev-notes.md` now carries the fixed patterns — the first regex without the
trailing `\)` (which is what hid `&out1[i]`), widened to `result` variables, plus a
second explicit grep for `&<var>[i]` — with the miss recorded beside them. Result at
`72cc75f2`: the adopting-shape sweep lists **only** copying converters (GtkTextIter,
GtkTreeIter, GtkBorder, GtkRequisition, GdkRGBA, GskPathPoint, Val_GValue_copy); the
array grep's single hit is `ml_border_node_gen.c`'s `Val_GdkRGBA(&result[i])`, safe
because `Val_GdkRGBA` = `copy_GdkRGBA`. The round-2 sweep paragraph earlier in this
report should be read with this correction: at `9f294eed` it was true only for the
scalar shape its regex could see; **at `72cc75f2` the claim holds for the array shape
too, because the sites were fixed, not because the regex says so.**

## CHANGELOG (review item, headline honesty)

The copy-out entry is now scoped to "202 **scalar** stubs" and a sibling entry states
the array class (14 sites, stack + heap, plus the gsize by-address conversion) — the
headline claims exactly what is true.

## Minors

- **M1**: the cross-namespace arm of `record_out_param_copy` carries the
  unreachability comment (a disguised record has no complete C type, so it can never be
  a by-value out-param or array element; mirror `disguised` into `Crt_Record` before
  ever adding a pointer-typed caller). Comment chosen over the field, per the lead.
- **M2**: `wrappers.h`'s `Val_option` documents the double-evaluation hazard and the
  function-twin rule; a gir_gen test pins that a nullable-annotated record out-param
  keeps the plain copy conversion and never reaches the macro.
- **M3**: re-run recorded. Command: `xvfb-run -a dune test ocgtk/ --force` in the
  fork root under `nix develop ~/src/stavekeeper#girgen`, tallied by summing the
  per-suite "N tests run" lines. Before this fix round I measure **38 runs / 408
  tests / 0 failures** (twice); at `72cc75f2`, with the new heap-array suite,
  **39 runs / 409 tests / 0 failures**. The reviewer's 409-at-38-runs reading remains
  unreproduced here — consistent with one version-gated case differing between GTK
  builds, and immaterial either way (0 failures in all readings).

## Verification

- gir_gen: **622 tests, 0 failures** (was 616).
- ocgtk under `xvfb-run -a`: **39 runs / 409 tests / 0 failures** (was 38/408 here).
- Regeneration commit re-checked: after `0473b317`, `generate-bindings.sh` produces
  zero further `.c`/`.h` diffs; `.ml`/`.mli` byte-identical across both new generator
  commits (restored per the standing contract).
- App-level verification not redone, per the lead: the changes are generated-C only;
  neither app compiles against any changed surface (`get_vertices`/`map_keyval` and
  siblings are unused in both apps — the round-2 grep covered `compute_bounds`-family
  and the new sites are in the same generated-only tier; re-grepped `get_vertices|
  map_keyval|get_backlog|get_log_attrs|get_color_stops|get_page_ranges` — zero uses).

## Deliverables refreshed

- **Bundle**: `r2-bindings.bundle` rebuilt — base `649498b4`, head `72cc75f2`,
  `git bundle verify` passes.
- **Pin-bump patches**: both rewritten to
  `rev = 72cc75f2a591c0ace7e25720c25031f53b2856bd`,
  `hash = sha256-+d4B9viBvnE7q43ge4hy/HrC8vh3+jP/ssXSdB/FKsQ=` (same method:
  `nix hash path` over a clean `git archive`; same caveat: confirm with
  `nix-prefetch-github` after pushing). Both `git apply --check` clean in their repos.
- **`r2-canary.patch`**: unchanged — it touches only bonsai_gtk test files and embeds
  no rev; still applies clean.

## State left

- `.ocgtk-src` on `r2-bindings` at `72cc75f2` (17 commits on the pin), clean, unpushed.
- Opam switch **still on the PIN** — this round never ran opam (fork suites built via
  the dune workspace); re-verified: `ml_refcounted_val_of_ext` absent from
  `_opam/lib/ocgtk/common/libocgtk_common_stubs.a`.
- bonsai_gtk clean except Beads' own `.beads/issues.jsonl`; Stavekeeper clean.
- The reviewer's "file the follow-up bead" became moot: the class is fixed, not filed
  (and `bd` remains forbidden to this task).
