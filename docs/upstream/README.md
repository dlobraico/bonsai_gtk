# ocgtk upstreaming status

Fork: https://github.com/dlobraico/ocgtk, branch `bonsai-gtk` (based on upstream `40ab0b6`).
bonsai_gtk pins the head of this branch via `ocgtk-pin.json`.

Branch head: `d98d939711d315cfb595d472594407044ff4f147`.

| # | Commit | Theme | Topic branch (fork) | Scrubbed head | Draft | Upstream PR |
|---|--------|-------|---------------------|---------------|-------|-------------|
| 1 | `60f34b07` | closure-marshal GC safety | `upstream/closure-gc` | `aecc35e6` | [pr-1](pr-1-closure-gc.md) | pending user approval |
| 2 | `81917a4e` | GObject ownership in generated stubs | `upstream/gobject-ownership` | `4ae6698c` | [pr-2](pr-2-gobject-ownership.md) | pending user approval |
| 3 | `3322e3b6` | gir_gen ownership fixes | `upstream/gir-gen-ownership` | `c63a3a42` | [pr-3](pr-3-gir-gen-ownership.md) | pending user approval |
| 4 | `2ed607d2` | floating-GVariant UAF in SimpleAction | `upstream/simple-action-variant` | `c1d91606` | [pr-4](pr-4-simple-action-variant.md) | pending user approval |
| 5 | `7d9d2ef7` | Glib_bytes.of_bigstring + GBytes memory accounting | `upstream/glib-bytes` | `79aa24e1` | [pr-5](pr-5-glib-bytes.md) | pending user approval |
| 6 | `d98d9397` | Style_display.add_provider_for_default_display | `upstream/style-display` | `a80c3dda` | [pr-6](pr-6-style-display.md) | pending user approval |

## Topic branches

All six are pushed to the fork (`origin`, https://github.com/dlobraico/ocgtk)
and each is a **single scrubbed commit cherry-picked directly onto
`upstream/main`**. As of this writing `upstream/main` is still `40ab0b6b`, the
base of `bonsai-gtk`, so all six cherry-picks applied without conflict and none
of them needs to be based on another. If upstream moves, re-check before
opening PRs.

Each topic branch differs from its `bonsai-gtk` counterpart **only in code
comments and one Alcotest suite display string** — the `run "..."` banner in
`ocgtk/tests/test_gio_simple_action.ml`, which embedded a ticket id and so had
to be scrubbed too. That string is the only non-comment line changed across all
six branches (verified with `git diff <picked-sha> <amended-sha>` per branch).
`bonsai-gtk` itself is unscrubbed and unchanged at `d98d9397` — it is what
`ocgtk-pin.json` pins, and must stay byte-exact.

No pull requests have been opened. Opening them is gated on user approval.

Each draft starts with two header lines — `Title:` and `Branch:` — that are
**for us, not for the PR body**. `--body-file` sends the file verbatim, so
those two lines (and the blank line after them) must be stripped, and the title
passed separately with `--title`. After approval, per PR:

```bash
cd ~/src/bonsai_gtk
open_pr() {  # open_pr <slug> <N> "<title>"
  sed '1,3d' "docs/upstream/pr-$2-$1.md" > /tmp/pr-body.md
  gh pr create --repo chris-armstrong/ocgtk \
    --head "dlobraico:upstream/$1" --title "$3" --body-file /tmp/pr-body.md
}
```

with the six titles taken verbatim from each draft's `Title:` line:

| N | slug | `--title` |
|---|---|---|
| 1 | `closure-gc` | Fix GC crash from a naked `GValue *` stored in the closure marshaller's argv |
| 2 | `gobject-ownership` | Fix four GObject reference-ownership classes in the generated stubs |
| 3 | `gir-gen-ownership` | gir_gen: gate ref_sink on transfer, ref transfer-full in-params, fix GList element ownership, map GBytes as boxed |
| 4 | `simple-action-variant` | Fix floating-GVariant use-after-free and NULL activate parameter in SimpleAction |
| 5 | `glib-bytes` | Add Glib_bytes.of_bigstring, and declare GBytes payload size to the GC |
| 6 | `style-display` | Add Style_display: application-wide CSS providers and gtk_settings_get_default |

`sed '1,3d'` drops the `Title:` line, the blank line, and the `Branch:` line —
check each file still begins where you expect before piping it to `gh`. Then
fill the resulting URLs into the table above.

### Verification per branch

Scrub grep (the pattern set below, restricted to that branch's changed files)
returns **zero hits on all six**, and zero on all six commit messages.

| Branch | Build + test | Result |
|---|---|---|
| `upstream/closure-gc` | ocgtk suite | 28 suites, 367 tests, 0 failures |
| `upstream/gobject-ownership` | ocgtk suite | 28 suites, 366 tests, 0 failures |
| `upstream/gir-gen-ownership` | ocgtk suite + `gir_gen` | 28 suites, 366 tests, 0 failures; gir_gen 561 tests, 0 failures |
| `upstream/simple-action-variant` | ocgtk suite | 29 suites, 368 tests, 0 failures |
| `upstream/glib-bytes` | ocgtk suite | 28 suites, 370 tests, 0 failures |
| `upstream/style-display` | ocgtk suite | 28 suites, 366 tests, 0 failures |

366 is the `upstream/main` baseline; the deltas are each branch's own new
tests, all confirmed present and passing by name in the run output.

Two "fails before the fix" claims in the drafts were verified rather than
assumed, by applying only the new test onto `upstream/main`:

- theme 1's `argv survives Gc.full_major inside the handler` — **SIGSEGV**
  (core dumped) after the three pre-existing cases pass;
- theme 4's `accel attribute survives Gc.compact`, reduced to a standalone
  file — **SIGSEGV** (core dumped).

### A build-command correction

Run the ocgtk build from `~/src/ocgtk/ocgtk`, not the repo root: at the root,
the default alias pulls in `gir_gen`, which the `bonsai_gtk#ocgtk` shell cannot
build (no `sexplib` / `ppx_sexp_conv` / `containers`).

Do **not** wrap the command in `env -u OCAMLPATH -u OPAM_SWITCH_PREFIX -u
CAML_LD_LIBRARY_PATH`. The nix dev shell sets `OCAMLPATH` itself — that is
where `alcotest` and the rest live — so unsetting it makes every test stanza
fail with `Library "alcotest" not found`. `OPAM_SWITCH_PREFIX` is already empty
in that shell; there is nothing to strip.

Give the two shells **separate build directories**. They ship different dune
versions and sharing `_build` yields stale source copies in `_build/default`,
which shows up as compile errors against code that is not in the tree any more
(e.g. `Unbound value Result.bind` at a line that reads `Stdlib.Result.bind`).
Use `--build-dir=/home/dlobraico/src/ocgtk/_build_ocgtk` and
`--build-dir=/home/dlobraico/src/ocgtk/_build_girgen` respectively, and confirm
freshness by grepping the copied source under the build dir after a build.

Each commit builds and passes the full test suite on its own:

```
cd ~/src/ocgtk/ocgtk
nix develop ~/src/bonsai_gtk#ocgtk -c sh -c \
  'dune build --build-dir=/home/dlobraico/src/ocgtk/_build_ocgtk \
   && xvfb-run -a dune runtest --build-dir=/home/dlobraico/src/ocgtk/_build_ocgtk --force'
```

`--force` matters — after one full run dune considers the test aliases up to
date and a plain `runtest` prints nothing, which looks like a pass without
running anything.

`gir_gen` (commit 3) cannot be built in that shell: it needs `sexplib`,
`ppx_sexp_conv` and `containers`, which `bonsai_gtk#ocgtk` does not provide.
It was built and tested with

```
cd ~/src/ocgtk
nix develop ~/src/stavekeeper#girgen -c sh -c \
  'dune build --build-dir=/home/dlobraico/src/ocgtk/_build_girgen @gir_gen/all \
   && dune runtest --build-dir=/home/dlobraico/src/ocgtk/_build_girgen gir_gen --force'
```

**This is a cross-repo dependency and should not stay one.** Anyone verifying
commit 3 today needs a stavekeeper checkout. `bonsai_gtk`'s own flake should
gain an equivalent dev shell (an `ocgtk` shell plus `sexplib`,
`ppx_sexp_conv`, `containers`, `re`, `xmlm`, `logs`, `ppx_deriving`), after
which this section should name only `bonsai_gtk` shells.

The branch tip reproduces stavekeeper's vendored tree byte-for-byte
(`diff -rq`, empty).

When a PR merges, rebase `bonsai-gtk` onto upstream `main`, re-run
`nix build .#ocgtk`, and move the pin.

## Where the split differs from the original theme plan

Three hunks landed in a different commit than the milestone plan's file table
predicted, because that table mislocated them:

- **`ocgtk/src/common/ml_glib.c` → commit 1, not commit 5.** Its single hunk is
  the `ml_raise_gerror` `caml_alloc_small` → `caml_alloc` + `Store_field` fix —
  the same GC-safety class as the closure-marshal boxing, and named in theme 1's
  own description. It has nothing to do with `Glib_bytes`.
- **`ocgtk/src/common/gobject.ml` / `gobject.mli` → commit 4, not commit 1.**
  Their only change is `Gobject.Value.get_variant_opt`, which exists solely for
  the SimpleAction NULL-parameter fix. The marshal boxing is entirely C-side and
  needs no OCaml signature change.
- **`ocgtk/tests/dune` → commit 4 only.** Upstream already has a
  `test_closure_with_gc` stanza, so commit 1 extends that file's existing test
  rather than adding a stanza. The only `tests/dune` hunk is the new
  `test_gio_simple_action` stanza.

Two changes are in the vendored tree but were not in any theme; both went into
the commit whose files they touch:

- **`gtk_settings_get_default` binding** (`Style_display.settings_default`, its
  `ml_gtk.c` stub, and the `--pkg-optional gio-unix-2.0` line in
  `ocgtk/src/gtk/dune`) — commit 6. It is a second hand-written GTK binding
  added alongside the style-provider one; the `gio-unix-2.0` cflags are a hard
  requirement once `ml_gtk.c` includes `generated/gtk_decls.h`, which
  transitively includes `gio/gunixfdmessage.h`.
- **`ocgtk/src/gtk/generated/ocgtk_gtk.ml`** — commit 6, one line re-exporting
  the new `Style_display` module.

Commit 3 also carries an incidental portability fix: `gir_gen`'s
`let* = Result.bind` definitions are now `Stdlib.Result.bind`, at **9 sites in
7 files** — `c_stub_bitfield.ml:54`, `c_stub_class.ml:20`, `c_stub_enum.ml:32`,
`c_stub_record.ml:39`, `signal_gen.ml:162`, `override_parser.ml:38` (one each)
and `version_guard.ml:55,82,101` (three). The legacy `result` compatibility
library shadows `Stdlib.Result` with a module that has no `bind`, and
`gir_gen` does not compile at all where that package is in scope — verified
against upstream `40ab0b6` in the `girgen` shell. No unqualified `Result.bind`
remains in `gir_gen/`.

## Comment scrubbing (done on the topic branches)

`bonsai-gtk` reproduces the vendored tree exactly, which means the code
*comments* on **that** branch still carry internal references, and they stay
there — it is the pinned branch and must not change. The commit *messages* were
already written as upstream contributions and contain none of these; it was
only the comments that needed scrubbing.

**This has been applied to the six `upstream/*` topic branches** (each
cherry-pick was amended with the rewritten comments), and the grep below
returns zero on all six. The section is kept for reference and for re-checking
after any future rebase. Everything below describes the state of `bonsai-gtk`,
not of the topic branches.

Do not scrub by searching for individual literals: several of these references
are paraphrased rather than repeated verbatim (only one of the eight `T5 fix`
sites says "T5 fix round 1"; the other seven say "ml_memory_texture_gen.c's T5
fix"). Use this pattern set instead, which was verified to cover every hit.

### The grep

```bash
cd ~/src/ocgtk
git diff --name-only 40ab0b6b..d98d9397 > /tmp/changed.txt
git grep -n -E 'score-library-|task-|T5 fix|stavekeeper|dev-notes\.md|re-apply|vendor re-sync' \
  d98d9397 -- $(cat /tmp/changed.txt)
```

Restricting to the changed-file list matters: `task-` and `re-apply` occur in
untouched upstream files too, and those are not ours to edit.

As of `d98d9397` this returns **50 lines across 23 files**. Per pattern:
`score-library-` 28, `dev-notes.md` 10, `T5 fix` 8, `re-apply`/`vendor
re-sync` 11 (overlapping the previous two), `task-` 2, `stavekeeper` 2.

The complete ticket-id set is six: **`score-library-9mm`, `-eqr`, `-ole`,
`-owx`, `-rkw`, `-wnv`** — plus `task-16b` and `task-5-review.md`. (`-owx`
appears once, in `test_glib_bytes.ml`, and is easy to miss.)

### What each pattern is catching

- `score-library-*`, `task-16b`, `task-5-review.md` — internal ticket and
  review-document ids.
- `T5 fix` — an internal milestone-task label, used both as "T5 fix round 1"
  and as cross-references to it from seven other stubs.
- `stavekeeper` — two references to the consuming application, including one
  to a source file of it (`viewer_window.ml`) that no upstream reader can see.
- `dev-notes.md` — points at a document that lives in stavekeeper, not here.
- `re-apply` / `vendor re-sync` — instructions for re-applying these edits
  after re-vendoring ocgtk. They are meaningless once the generator fix
  (commit 3) is upstream, and actively misleading in an upstream tree.

### Every hit

| file:line | context |
|---|---|
| `gir_gen/lib/c_stub_list_conv.ml:26` | handled per the return's transfer mode (score-library-ole). |
| `gir_gen/lib/c_stub_list_conv.ml:103` | original behind, so it must be freed here (score-library-ole) |
| `gir_gen/lib/generate/c_stub_constructor.ml:202` | unbounded GdkMemoryTexture leak (score-library-eqr). Mirrors the |
| `gir_gen/lib/generate/c_stub_helpers.ml:346` | score-library-eqr follow-up: gtk_widget_add_controller is the |
| `gir_gen/lib/type_mappings.ml:317` | score-library-rkw: Val_GBytes ADOPTS (its finalizer unrefs), so |
| `gir_gen/test/c_stubs/generation_tests.ml:802` | Constructor return-transfer ref_sink gating (score-library-eqr) *) |
| `gir_gen/test/c_stubs/generation_tests.ml:844` | score-library-eqr follow-up: a transfer-full GObject IN-parameter is |
| `gir_gen/test/c_stubs/generation_tests.ml:878` | score-library-rkw: Val_GBytes adopts (finalizer unrefs), so a |
| `gir_gen/test/c_stubs/generation_tests.ml:909` | GList return element ownership (score-library-ole) *) |
| `gir_gen/test/c_stubs/generation_tests.ml:1020` | Constructor ref_sink gating (score-library-eqr) *) |
| `gir_gen/test/c_stubs/generation_tests.ml:1035` | GList element ownership (score-library-ole) *) |
| `ocgtk/src/common/ml_glib.c:234` | score-library-9mm, on the GError path. caml_alloc fills scannable blocks |
| `ocgtk/src/common/ml_gobject.c:457` | score-library-wnv: NULL is not always an error here -- e.g. GAction's |
| `ocgtk/src/common/ml_gobject.c:777` | pointer and died dereferencing it (score-library-9mm). Abstract_tag |
| `ocgtk/src/common/ml_gvariant.c:115` | score-library-wnv fix round 1: "transfer-full" here means a genuine |
| `ocgtk/src/gdk/generated/ml_memory_texture_gen.c:23` | T5 fix round 1: gdk_memory_texture_new is transfer-full, and GdkTexture is |
| `ocgtk/src/gdk/generated/ml_memory_texture_gen.c:30` | RSS growth in task-5-review.md). Deliberately dropped -- re-apply this |
| `ocgtk/src/gdk/generated/ml_memory_texture_gen.c:31` | removal on any vendor re-sync (docs/dev-notes.md's "re-apply on any |
| `ocgtk/src/gdk/generated/ml_memory_texture_gen.c:32` | vendor re-sync" list). */ |
| `ocgtk/src/gio/generated/ml_menu_gen.c:26` | score-library-eqr: g_menu_new is transfer-full and GMenu is NOT |
| `ocgtk/src/gio/generated/ml_menu_gen.c:30` | class as ml_memory_texture_gen.c's T5 fix; gir_gen now gates ref_sink |
| `ocgtk/src/gio/generated/ml_menu_gen.c:32` | re-apply this removal on any vendor re-sync (docs/dev-notes.md). */ |
| `ocgtk/src/gio/generated/ml_menu_item_gen.c:26` | score-library-eqr: g_menu_item_new is transfer-full and GMenuItem is NOT |
| `ocgtk/src/gio/generated/ml_menu_item_gen.c:30` | class as ml_memory_texture_gen.c's T5 fix; gir_gen now gates ref_sink |
| `ocgtk/src/gio/generated/ml_menu_item_gen.c:32` | re-apply this removal on any vendor re-sync (docs/dev-notes.md). */ |
| `ocgtk/src/gio/generated/ml_simple_action_gen.c:26` | score-library-eqr: g_simple_action_new is transfer-full and GSimpleAction is… |
| `ocgtk/src/gio/generated/ml_simple_action_gen.c:30` | class as ml_memory_texture_gen.c's T5 fix; gir_gen now gates ref_sink |
| `ocgtk/src/gio/generated/ml_simple_action_gen.c:32` | re-apply this removal on any vendor re-sync (docs/dev-notes.md). */ |
| `ocgtk/src/gio/generated/simple_action.mli:62` | score-library-wnv: e.g. [new_ name None]) -- GAction's "activate" signal |
| `ocgtk/src/gtk/core/ml_gtk.c:130` | docs/dev-notes.md in the stavekeeper repo, "vendor/ocgtk now diverges"). |
| `ocgtk/src/gtk/generated/ml_event_controller_key_gen.c:25` | score-library-eqr: gtk_event_controller_key_new is transfer-full and GtkEven… |
| `ocgtk/src/gtk/generated/ml_event_controller_key_gen.c:29` | class as ml_memory_texture_gen.c's T5 fix; gir_gen now gates ref_sink |
| `ocgtk/src/gtk/generated/ml_event_controller_key_gen.c:31` | re-apply this removal on any vendor re-sync (docs/dev-notes.md). */ |
| `ocgtk/src/gtk/generated/ml_flow_box_gen.c:232` | CRITICAL (task-16b). */ |
| `ocgtk/src/gtk/generated/ml_gesture_click_gen.c:25` | score-library-eqr: gtk_gesture_click_new is transfer-full and GtkGestureClic… |
| `ocgtk/src/gtk/generated/ml_gesture_click_gen.c:29` | class as ml_memory_texture_gen.c's T5 fix; gir_gen now gates ref_sink |
| `ocgtk/src/gtk/generated/ml_gesture_click_gen.c:31` | re-apply this removal on any vendor re-sync (docs/dev-notes.md). */ |
| `ocgtk/src/gtk/generated/ml_gesture_drag_gen.c:25` | score-library-eqr: gtk_gesture_drag_new is transfer-full and GtkGestureDrag … |
| `ocgtk/src/gtk/generated/ml_gesture_drag_gen.c:29` | class as ml_memory_texture_gen.c's T5 fix; gir_gen now gates ref_sink |
| `ocgtk/src/gtk/generated/ml_gesture_drag_gen.c:31` | re-apply this removal on any vendor re-sync (docs/dev-notes.md). */ |
| `ocgtk/src/gtk/generated/ml_gesture_stylus_gen.c:25` | score-library-eqr: gtk_gesture_stylus_new is transfer-full and GtkGestureSty… |
| `ocgtk/src/gtk/generated/ml_gesture_stylus_gen.c:29` | class as ml_memory_texture_gen.c's T5 fix; gir_gen now gates ref_sink |
| `ocgtk/src/gtk/generated/ml_gesture_stylus_gen.c:31` | re-apply this removal on any vendor re-sync (docs/dev-notes.md). */ |
| `ocgtk/src/gtk/generated/ml_widget_gen.c:1418` | score-library-eqr follow-up: the `controller` parameter is |
| `ocgtk/src/gtk/generated/ml_widget_gen.c:1426` | re-apply on any vendor re-sync (docs/dev-notes.md). */ |
| `ocgtk/tests/test_closure_with_gc.ml:36` | Regression test for score-library-9mm: [ml_closure_marshal] used to store |
| `ocgtk/tests/test_gio_simple_action.ml:1` | Regression tests for score-library-wnv. |
| `ocgtk/tests/test_gio_simple_action.ml:4` | [GSimpleAction]s (stavekeeper's viewer_window.ml), both in GVariant |
| `ocgtk/tests/test_gio_simple_action.ml:63` | run "GIO SimpleAction/MenuItem GVariant lifetime (score-library-wnv)" |
| `ocgtk/tests/test_glib_bytes.ml:115` | {2 of_bigstring Tests (score-library-owx)} |

### Sanity check after scrubbing

Re-run the grep above; it must return nothing. Then rebuild — several of these
comments sit inside `/* … */` blocks whose deletion is easy to get wrong in C:

```
cd ~/src/ocgtk/ocgtk
nix develop ~/src/bonsai_gtk#ocgtk -c sh -c \
  'dune build --build-dir=/home/dlobraico/src/ocgtk/_build_ocgtk \
   && xvfb-run -a dune runtest --build-dir=/home/dlobraico/src/ocgtk/_build_ocgtk --force'
```

See "A build-command correction" above for why the build dir is explicit and
why the command runs from `ocgtk/`, not the repo root.

Both were done for all six topic branches; results are in the verification
table above.
