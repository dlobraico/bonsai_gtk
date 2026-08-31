# Task 14 report — ocgtk fork changes, prepared locally and not pushed

**Fork branch:** `m2-bindings` in `/home/dlobraico/src/bonsai_gtk/.ocgtk-src`, five commits on
top of the pin `d98d9397`. **Nothing was pushed, anywhere. `ocgtk-pin.json` was not touched
in either repository.**

```
4ea70268 gtk gio gdk gsk pango: stop ref_sinking constructors that already transferred
a913c307 gtk gio gdk pango: sink the elements of transfer-container list returns
bcd39f14 gtk: Widget.set_name, StackPage.set_title and PasswordEntry placeholder take NULL
e281d8f3 gir_gen: a (nullable) override, and fix the nullable-property class wrapper
7619876c common: refuse OCaml callbacks reached from a GObject finalizer
```

257 files, +1219 / −373 across the branch. Per commit: 5 / 10 / 20 / 22 / 208 files.

The checkout is clean and left on `m2-bindings`. The opam switch in `bonsai_gtk` was put
back to the **pinned** build after verification, so the repository is exactly as green as
it was found — see "What ran against what" below.

---

## The finding that reframes items (b) and (c)

**The fork's generated tree is stale relative to its own generator.** Fork commit
`3322e3b6` ("gir_gen: fix GObject ownership classes") changed `gir_gen/` and its tests and
**never regenerated `ocgtk/src/*/generated/`**. Both of the memory bugs M2 found are
already fixed in the generator and were simply never emitted into the tree.

Regenerating the whole tree today (`./scripts/generate-bindings.sh`) produces:

| | files | what |
|---|---|---|
| C stubs | 236 | **+61 / −413, all semantic.** The ownership fixes below. |
| `.ml` / `.mli` | 936 | 929 of them **doc-comment rewrapping only** (a different ocamlformat); 7 with real changes, of which **4 revert fork commit `2ed607d2`** — the SimpleAction `parameter:Gvariant.t option` fix, which the generator does not know about. |

So a wholesale `git add` of a regeneration is not an option: it would silently undo a
shipped fix and bury 61 real lines under ~29 000 lines of formatting churn. Every generated
hunk in commits `bcd39f14`, `a913c307` and `4ea70268` was therefore **taken verbatim from
the regenerated file and applied by hand**, and the result was checked by regenerating
again and diffing (below).

---

## Per item

### Items 1–3 — nullable string bindings. **Generator (override table), not hand stubs.**

**Decided before writing code, as the brief asked.** The generator is *not* wrong: it
honours `nullable="1"` faithfully — 142 generated `.mli` files carry a `string option`
because of it. What is wrong is the input data:

| binding | GIR says |
|---|---|
| `gtk_widget_set_name`'s `name` param | no `nullable` (the C function `g_strdup`s it, and NULL resets to the class default) |
| `gtk_stack_page_set_title`'s `setting` param | no `nullable` — while its own `glib:get-property` partner `gtk_stack_page_get_title` **is** annotated, so the GIR contradicts itself |
| `GtkPasswordEntry:placeholder-text` | `default-value="NULL"`, no `nullable` — and it is a *property*, with no accessor methods, which is why `GtkEntry`'s correctly-annotated twin did not help |

`gtk_event_controller_set_name` is already annotated and was already `string option`; the
backlog's "Event_controller nullable name" item is **not a defect** and can be struck.

The override system (`ocgtk/overrides/*.sexp`) is where this project already corrects GIR
that does not match reality, but it only had `(ignore)` and `(version ...)`. Commit
`e281d8f3` adds a third action:

```lisp
(class Widget        (method set_name (nullable name)))
(class StackPage     (method set_title (nullable setting)))
(class PasswordEntry (property placeholder-text (nullable)))
```

`(nullable)` bare is for a property (one type, shared by getter and setter); `(nullable
return)` marks a return; any other atom names a parameter, several allowed. It removes
nothing — the one component action that is not a filter — and an entity-level `(nullable)`
warns and generates the entity unchanged.

**Why not hand-patched stubs:** the patch is lost on the next regeneration and the GIR gap
it works around is recorded nowhere. The fork's own history says the same thing — commit
`2ed607d2` hand-patched stubs that commit `3322e3b6`'s generator later emits.

**A generator bug fell out of it.** The property override immediately produced code that
does not compile:

```
method placeholder_text : string option option
method set_placeholder_text v =
  match v with Some v -> P.set_placeholder_text obj v | None -> P.set_placeholder_text obj None
```

Two defects in `class_gen_property.ml`: the signature appended `" option"` to a type
`resolve_ocaml_type` had already optioned, and the setter took the option apart, handing the
layer-1 setter (which takes the option) a bare string. Neither had ever been reachable:
**every** nullable property in the bundled GIRs also has explicit accessor methods, which
take the correct `class_gen_method` route. `GtkPasswordEntry:placeholder-text` is the first
property-only one. Both fixed; non-nullable output is byte-identical.

**Regression tests.** `gir_gen`: seven parser cases, five apply cases, one class-generation
case (one option not two on both sides; the setter body forwards rather than unwraps).
`ocgtk`: `tests/gtk/test_nullable_strings.ml` round-trips all three.

**One GTK fact worth not re-deriving**, measured on 4.22 and pinned in that test: writing
`None` to the password entry's placeholder does **not** restore its unset state — it reads
back as `Some ""`, because the placeholder lives on an internal `GtkText` whose own setter
normalises NULL to `""` once it exists. `Widget.name` and `StackPage.title` **do** restore
theirs. The getter is genuinely three-state (unset / `Some ""` / `Some s`), which is the
whole reason a `string` binding could not express it.

Two call sites inside ocgtk moved with the signatures (`tests/gtk/test_box.ml`,
`examples/login_form.ml`). Everything else already passed `Some` to `Window.set_title`,
which has been nullable all along.

### Item 4 (a) — the finaliser re-entry segfault. **Marshaller refusal, not a deferred unref.**

`finalize_gobject` is a custom-block finalizer: the collector calls it, from inside a
collection, and it drops the wrapper's reference. When that is the last one GTK runs
`dispose`, dispose emits `destroy` (and `notify::`s), and the emission reaches
`ml_closure_marshal`, which allocates an argv record and a GValue wrapper and then calls
`caml_callback_exn` — allocating in the OCaml heap from inside the collector.

Reproduced first, with nothing above ocgtk involved (the `task-12-review.md` A2 shape):

```
counting destroy handler                survived, 10 emissions
destroy handler allocating ~200 words   *** SIGSEGV (core dumped) ***
```

three runs, three crashes, always at the same case. After the fix, five cases, three runs,
all green.

**Chose: the marshaller refuses.** `wrappers.c` keeps a thread-local depth counter that is
non-zero only across `finalize_gobject`'s `g_object_unref`; `ml_closure_marshal` checks it
*before touching the OCaml runtime at all* and drops the emission with a `g_warning` that
names the signal and says what to do about it.

**Why not defer the unref to `g_idle_add`** (the other option in the brief): it makes every
wrapper's disposal conditional on a main loop actually iterating, so any program — and
**every test in this suite**, none of which runs a loop — would free nothing at all; and it
moves destruction to an unpredictable later point, which changes what every existing
ref-count and lifetime assertion in the suite means. Refusing the callback leaves object
lifetime exactly where it was and costs only a handler that could not have run safely. It
is also correct under any GC, with or without a loop, which the deferral is not.

A counter rather than a flag (one collection finalizes many wrappers, and a dispose can
nest). Thread-local rather than global (the collector runs a finalizer on whichever thread
triggered the collection and the dispose emits on that same thread; a process-wide flag
could silence a legitimate emission on another thread).

**Regression:** `tests/gtk/test_dispose_reentry.ml` — five cases. The allocating handler and
a handler that itself collects both segfault without the change; two controls (a
hand-emitted `destroy`, and one *after* a collection) prove the refusal is scoped to
finalization and does not latch.

**Residual, not fixed:** `ml_closure_invalidate` calls `caml_remove_global_root` from the
same finalizer context when dispose destroys closures. It does not allocate, and the
counting case exercises it and passes, so it is empirically fine on this runtime — but it is
the same *class* of hazard and nothing pins it.

### Item 4 (b) — transfer-container list returns. **Regeneration, applied by hand.**

`ml_gobject_val_of_ext`'s contract is that a borrowed pointer is sunk before it is wrapped,
"since the wrapper's finalizer unconditionally `g_object_unref`s on GC". A
`transfer-ownership="container"` return borrows its elements. Of the 21 such sites, **20
took no reference** — 19 missing a `g_object_ref_sink`, one (`gtk_gesture_get_sequences`,
whose elements are boxed `GdkEventSequence`s) missing a `g_boxed_copy` — one unbalanced
unref or free per element, per call. Only the hand-patched FlowBox site was correct.

`gir_gen` has emitted the sink since `3322e3b6`. Applied across gtk (list_box, widget,
gesture, tree_view, cell_area, cell_layout, size_group, application, window_group,
accessible_list, text_iter), gio (emblemed_icon), gdk (display, display_manager, seat,
file_list) and pango (attr_list, attr_iterator, glyph_item). Three of those are GSList
returns of *boxed* records (Pango attributes ×2, glyph items ×1), where the same reasoning
adds a `g_boxed_free` loop before the `g_slist_free`. The FlowBox site keeps its explanatory comment and is
respelled to match generated output, so that file now differs from the generator by the
comment alone.

**Regression, mutation-verified:** `tests/gtk/test_transfer_container_lists.ml` — ten reads
of a ten-row selection, wrappers dropped, two `Gc.full_major`s, rows read back through
`get_row_at_index` and asserted still present/indexed/selected; a ref-count reading that
must not move across twenty round trips; the FlowBox twin as control. With the sink removed
from `ml_list_box_gen.c` again, **the same invocation produces no output and is still
running when killed at 60 s and again at 90 s**; with it, the suite passes in 11 ms. (It
hangs rather than crashing — the shape `docs/m1-backlog.md` already notes for drain loops.)

### Item 4 (c) — constructor `ref_sink` on plain GObjects. **Regeneration, applied by hand.**

`g_object_ref_sink` claims a *floating* reference; only `GInitiallyUnowned` descendants are
ever floating. On a plain `GObject` it degenerates to `g_object_ref`, so the wrapper held
two references to an object the constructor had already transferred, and its finalizer
dropped one — a leak of the object and everything it owns, per call.

**279 constructors** in 190 files across gtk, gio, gdk, gsk and pango.

**Audited before applying, not trusted:** for every one of the 279 I walked the constructed
type's parent chain in the bundled GIRs. **None descends from `GInitiallyUnowned`.** The 162
that keep the sink are the floating ones. The tree's `g_object_ref_sink(obj)` count went
441 → 162, exactly equalling the regenerated tree (16 of the removals sat in hunks the
generator also rewrites for the in-parameter class held back below, and were taken
line-by-line so that only the sink moved).

**Regression:** `tests/gtk/test_constructor_ownership.ml` — four plain GObjects
(`GtkStringList`, `GtkTextBuffer`, `GtkSizeGroup`, `GtkAdjustment`) at one reference when
fresh; three widgets also at one, with a parent/unparent round trip showing the container's
reference arrive and leave (the thing an unsunk widget would not survive); two hundred
consecutive constructions that never see a second reference.

This is the one change with an **observable effect on a bonsai_gtk golden** — see below.

### Item 4 (d) — found, deliberately not applied

Everything here is written up so the lead can decide; none of it is in the branch.

1. **Transfer-full GObject in-parameters (~30 sites).** The generator now emits
   `g_object_ref` on a `transfer-ownership="full"` in-param (`gtk_widget_set_layout_manager`,
   `gtk_shortcut_set_trigger`, `gtk_single_selection_new`, …). Correct in principle and it
   closes a real double-drop. **Held back because at least six of those sites would
   `g_object_ref` a `GtkExpression`** (`gtk_string_filter_new`, `gtk_bool_filter_new`,
   `gtk_numeric_sorter_new`, `gtk_string_sorter_new`, `gtk_property_expression_new`,
   `gtk_drop_down_new`), and a `GtkExpression` **is not a `GObject`** — it has its own
   `gtk_expression_ref`/`unref`. Applying it wholesale trades a leak for a probable
   `G_OBJECT` cast critical. Needs a generator change first (recognise the ref-counted
   non-GObject types), then regeneration. This is the same defect `docs/m1-backlog.md`
   already records for `gtk_drop_down_get_expression`, from the other end.
2. **GBytes returns (6 sites)** now get `if (result) result = g_boxed_copy(g_bytes_get_type(), result);`
   because `Val_GBytes` adopts. Same "stale tree" family, well covered by `gir_gen` tests,
   held back only to keep this branch to the two classes I audited by hand.
3. **11 constructors keep a sink on a non-`GInitiallyUnowned` type** even after
   regeneration: `GskFillNode`, `GskStrokeNode` (whose type is not a `GObject` at all —
   `GskRenderNode` has its own ref/unref), `GskGLRenderer`, `GskVulkanRenderer`, and five
   Gio-Unix constructors. The generator gates on the GIR's *return transfer*, not on the
   type hierarchy, and these have `transfer-ownership="none"` or sit behind a version guard
   that takes a different code path. A tighter rule would be "sink iff `GInitiallyUnowned`".
4. **`gtk_text_buffer_get_text` and every other transfer-full `char*` return leak** — the
   generator does **not** fix this, so it is genuine new work, not a regeneration. It is the
   most expensive item M2 measured (1 MB leaked per keystroke in a 1 MB buffer; 201 MB over
   200 whole-buffer reads). The generator already emits `g_free(result)` for a transfer-full
   *array*; the single-`char*` path is the miss. Sized as a small `gir_gen` change plus a
   regeneration of the affected stubs. **The highest-value remaining fork item.**
5. **`gtk_drop_down_get_selected_item` is broken twice over** (no sink, and returns a bare
   custom block where the `.mli` promises an `option`). Unchanged; nothing calls it.
6. **`Gobject.unref` is still not exposed.** It exists as `ml_g_object_unref` in
   `ml_gobject.c` with no `val` in `gobject.mli`. Not needed by anything; noted because
   `test_dispose_reentry.ml` had to emit `destroy` by hand rather than drop a reference
   explicitly, and a control that disposes deliberately would be a better test than one
   that emits.
7. **`Widget.destroy` is not bound either** (no `gtk_widget_destroy` in GTK 4, but
   `gtk_window_destroy` and `g_object_run_dispose` are unbound too).

**Findings the plan asked to list and route around** (`List_box.set_header_func`/`sort_func`/
`filter_func`, a `GLib.DateTime` binding, `gdk_keyval_name`/`from_name`): confirmed
unchanged and still out of reach. The generator emits no GIR-callback-taking method, no
namespace-level function, and there is no `GLib-2.0.gir` in the checkout. M2's workarounds
(sorting/filtering in OCaml before the node is built; no date formatting through the
binding; key names via `Attr.on_key`'s own enum) all stand. Each is a milestone of its own,
not a patch.

---

## Test results

**ocgtk's own suite** (`xvfb-run dune test ocgtk/ --force`, in `nix develop
~/src/stavekeeper#girgen`):

| | suites | tests | failures |
|---|---|---|---|
| baseline at `d98d9397` | 29 | 373 | 0 |
| branch head `4ea70268` | **33** | **388** | **0** |

Four new suites (`test_dispose_reentry`, `test_nullable_strings`,
`test_transfer_container_lists`, `test_constructor_ownership`), 15 new cases.

**`gir_gen`** (`dune test gir_gen/ --force`): 561 → **574 tests, 0 failures** (+7 parser,
+5 apply, +1 class generation).

**Convergence check.** Regenerating the whole tree with the branch's generator and with the
pin's generator, then diffing the two regenerations, gives **46 differing lines, every one
of them one of the three nullability corrections** — i.e. the `gir_gen` changes have no
collateral effect anywhere else.

## What ran against what

`scripts/ci.sh`'s first step, `nix build .#ocgtk`, builds the **pinned** fork from GitHub
(`ocgtk-pin.json` → `fetchFromGitHub`). It cannot see `.ocgtk-src` and therefore **always
ran against the pin**. Every other step reads the opam switch's `ocgtk`, which is a **path
pin to `./.ocgtk-src/ocgtk`** — so those ran against whatever was installed at the time.

| ci.sh step | run 1 (patched fork installed) | run 2 (pin reinstalled, tree as left) |
|---|---|---|
| `nix: ocgtk pin builds and passes its tests` | pin | pin |
| format | — | — |
| build | **patched** | pin |
| generated opam files are committed | — | — |
| pure + headless tests | **patched** | pin |
| per-package builds | **patched** | pin |
| live tests (xvfb) | **patched** | pin |
| example smoke | **patched** | pin |
| result | **all green** | **all green** |

Run 1 needed a six-line adaptation in bonsai_gtk (below) plus one promoted golden line.
Run 2 is the state I am leaving: switch rebuilt from `d98d9397`, `.ocgtk-src` checked out on
`m2-bindings`, bonsai_gtk carrying only the docs/comment commit.

**Correction to the brief's step 4.** "`ci.sh` must pass without any bonsai_gtk change:
these are additive binding changes" is **not true of items 1–3**, and could not be: making
an existing setter nullable changes its type, and OCaml has no overloading. `ci.sh` passes
green in both directions, but not with the *same* bonsai_gtk sources — see the patch. Items
(a), (b) and (c) genuinely are additive and need no source change at all; item (c) changes
one printed number.

---

## Exactly what the lead does next

### 1. Push the fork branch

```bash
cd ~/src/bonsai_gtk/.ocgtk-src
git push origin m2-bindings
```

`origin` here is the **https** remote (`https://github.com/dlobraico/ocgtk.git`) — the
checkout `setup-switch.sh` clones. `~/src/ocgtk` is a *different* checkout with an ssh
remote and is currently sitting on `upstream/gobject-ownership`; **I did not touch it**, and
pushing from it is not what this branch lives in.

### 2. Compute the new pin

```bash
nix-prefetch-github dlobraico ocgtk --rev 4ea70268   # use the real 40-char sha
```

(That is `nix/ocgtk/README.md`'s own recipe, and `docs/dev-notes.md:113` in Stavekeeper says
the same.)

### 3. Edit the pin — **one file per repository, not three**

The brief anticipated `flake.nix` and `scripts/setup-ocgtk.sh` needing edits. They do not:
**both** repositories read `rev` and `hash` out of `ocgtk-pin.json`
(`builtins.fromJSON (builtins.readFile ./ocgtk-pin.json)` in each `flake.nix`; `jq -r .rev`
in the setup scripts). So:

- `~/src/bonsai_gtk/ocgtk-pin.json` — `rev` + `hash`
- `~/src/stavekeeper/ocgtk-pin.json` — `rev` + `hash` (identical values)

Stavekeeper's `nix/ocgtk/` contains **no `*.patch` files**, so there is nothing to rebase or
delete there.

### 4. Apply the bonsai_gtk source adaptation

**Required** — bonsai_gtk does not compile against the new signatures without it. Saved at
`.superpowers/sdd/2026-08-30-bonsai-gtk-m2/task-14-pin-bump.patch` (114 lines, 5 files;
untracked, like every other file under `.superpowers/`, which this repository gitignores —
so it lives on disk only and will not survive a clean checkout). Verified to apply cleanly
to the tree as left (`git apply --check`):

```bash
cd ~/src/bonsai_gtk
git apply .superpowers/sdd/2026-08-30-bonsai-gtk-m2/task-14-pin-bump.patch
```

What it contains, and why each line:

| file | change |
|---|---|
| `src/attr_apply.ml` ×2 | `Widget.set_name w s` → `(Some s)`; `… d.widget_name` → `(Some d.widget_name)` |
| `src/widgets/w_stack.ml` | wraps the existing `Option.value ~default:""` in `Some` |
| `src/widgets/w_password_entry.ml` ×2 | `Option.iter … ~f:(fun t -> … (Some t))`; wraps the update path's `""` in `Some` |
| `test/live/live_text.ml` + `test/live/expected_text.txt` | the `GtkStringList` ref-count probe now reads **1** instead of 2 (item (c) landing); the comment above it is rewritten to say so |

**It is deliberately behaviour-preserving, not the improvement.** Every site keeps writing
`Some ""` where it wrote `""`. Taking the actual benefit is a separate, deliberate change:

- `Unset Widget_name` should write `None`, not `Some d.widget_name` — `attr_apply.ml`'s own
  docstring says restoring the name is "the one field that cannot be restored exactly", and
  now it can. That paragraph (and `vtree/attr.mli:234-239`) should be rewritten when it is.
- `w_stack.ml` should pass `(page_title node)` straight through, so a page that loses its
  `Attr.page_title` gets **no switcher button** rather than a blank clickable one — the
  containers-M1 behaviour item 2 exists for.
- `w_password_entry.ml` can drop its `""` too, but with no visible effect: GTK normalises
  the NULL back to `""` (measured, above).

I did not make those changes: they are behaviour changes to M2 code with goldens attached,
and the brief scoped this task to the fork.

### 5. Rebuild and re-verify

```bash
cd ~/src/bonsai_gtk
./scripts/setup-switch.sh          # notices the moved rev and forces the reinstall
nix develop . -c ./scripts/ci.sh   # expect "all green"

cd ~/src/stavekeeper
./scripts/setup-ocgtk.sh
nix build .#ocgtk
```

Stavekeeper needs **no source change**: it has zero `Password_entry` uses, zero
`Widget.set_name`/`#set_name` uses, zero `Stack_page.set_title` uses, zero
`get_selected_rows` uses, and zero `destroy` handlers. Its four `#set_placeholder_text` calls
are on `GtkEntry`/`GtkSearchEntry`, which were already nullable, and its `#add_named` calls
are unchanged. **That claim is grep-based, not build-verified** — I did not reinstall
Stavekeeper's own switch, which is not mine to disturb.

### 6. Before offering any of it upstream

None of these five has a scrubbed topic branch or a PR. They need the same
cherry-pick-onto-`upstream/main`-and-scrub treatment as #173–#178, and the scrub grep in
`docs/upstream/README.md` should be re-run: my commit messages and comments are clean of
ticket ids, but `a913c307` and `4ea70268` *edit files that still carry them* (the
`score-library-*` comments in the generated stubs are untouched and would go up with the
diff context).

---

## Committed in bonsai_gtk (branch `m2`)

Only what the brief allows:

- `docs/upstream/README.md` — a new "Not yet pushed: the M2 branch" section listing the five
  commits, what each closes, and a pointer here.
- `src/widgets/w_list_box.ml` — the "do not use `get_selected_rows`" comment now names
  commit `a913c307` and says the prohibition lifts when the pin moves past it, and not
  before. (Reformatted by `dune build @src/fmt`; `ci.sh` was re-run green afterwards.)
- this report and `task-14-pin-bump.patch` are **not** committed: `.superpowers/` is in
  this repository's `.gitignore`, as it has been for tasks 1–13.

No source behaviour changed; `ci.sh` is green on the tree as committed.

---

## Deviations

1. **Commit order.** The brief's order is 1, 2, 3, then item 4 (a)…(d); I committed (a)
   first. I needed the A2 reproducer running before I could choose between the two candidate
   fixes, it is the highest-priority item, and the five commits are independent (different
   files; they rebase into any order without conflict). Say the word and I will reorder.
2. **Items 1–3 are two commits, not three.** The override mechanism plus the generator bug
   it exposed is one change (`e281d8f3`); the three override entries, their regenerated
   stubs and their runtime test are the second (`bcd39f14`). Splitting further would put the
   machinery in commit 1 and leave commits 2 and 3 as one-line data edits that do not justify
   a message of their own.
3. **Generated output applied by hand, not by committing a regeneration.** Reasons and
   evidence in "The finding that reframes items (b) and (c)". Each hunk was taken verbatim
   from the regenerated file, and the whole result was re-checked by regenerating again.
4. **`ci.sh` does not pass "without any bonsai_gtk change"** once the pin moves — see the
   correction above. It passes in both directions, with different sources.
5. **Item 4 (d) is reported, not implemented.** Four of its seven entries are real fixes I
   could have written; the in-param one is actively unsafe as the generator currently emits
   it, and the transfer-full `char*` leak is new generator work rather than a regeneration.
   Both are sized in the list.
6. **The fork commits carry the `Co-Authored-By` / `Claude-Session` trailers.** The brief
   said to check first — I did: all six existing fork commits carry them, so the lead's
   instruction and the fork's convention agree.
7. **A `gir_gen` change beyond the brief.** `class_gen_property.ml`'s nullable-property path
   had to be fixed for item 3 to compile at all. It is in the same commit as the mechanism,
   with its own test.

## Carries

- The behavioural half of items 1–3 (see step 4 above): three small bonsai_gtk changes plus
  the two doc paragraphs that currently say the binding cannot do this.
- Item 4 (d) #4 — the transfer-full `char*` return leak — is the largest remaining win and
  is not covered by any regeneration.
- Item 4 (d) #1 — the transfer-full in-param class — should not be regenerated until the
  generator learns that `GtkExpression` and `GskRenderNode` are ref-counted non-GObjects.
  That same knowledge fixes `gtk_drop_down_get_expression`.
- `docs/m1-backlog.md`'s ocgtk section is now partly stale: the `get_selected_rows` entry,
  the constructor-`ref_sink` entry and the finaliser entry are all fixed on the branch, and
  the "Event_controller nullable name" item was never a defect. It should be re-cut when the
  pin moves, not now — until then the backlog correctly describes the *pinned* binding.
- The `caml_remove_global_root`-from-a-finalizer residual (item (a)) has no test.
- `bonsai_gtk`'s flake still has no `gir_gen`-capable dev shell, so every command in this
  task ran through `nix develop ~/src/stavekeeper#girgen`. That cross-repo dependency is
  already on the backlog and is now load-bearing for anyone reproducing this work.

---

# Checkpoint (reboot)

Written 2026-08-30 for a server reboot. **Task 14 was already finished when the checkpoint
was requested** — this is not a WIP park. Nothing was left half-applied, no WIP commit was
needed, and no new work was started to reach this point. The one thing added for the
reboot is a git bundle of the unpushed branch (see "Reboot risk" below).

## Both trees are clean of tracked changes

```
/home/dlobraico/src/bonsai_gtk        HEAD cc762d1 (branch m2)   git status: clean *
/home/dlobraico/src/bonsai_gtk/.ocgtk-src  HEAD 4ea70268 (branch m2-bindings)  git status: clean
```

\* one untracked file, `bonsai_gtk/.beads/issues.jsonl`. **Not mine** — I ran no `bd`
commands (the brief forbade it). Beads' own git hooks rewrote it at 13:25 while my commits
ran; it is the passive export `CLAUDE.md` describes. Left in place: deleting a tool's export
is not my call, and it is untracked so it blocks nothing.

## Fork branch: `m2-bindings`, five commits, none pushed

Based on the pin `d98d9397`. 257 files, +1219 / −373.

| # | hash | covers | what |
|---|------|--------|------|
| 1 | `7619876c` | **4a** | Finaliser re-entry segfault. Thread-local depth counter around `finalize_gobject`'s `g_object_unref`; `ml_closure_marshal` refuses to call into OCaml while it is set, `g_warning`s, and drops the emission. Chose this over deferring the unref to `g_idle_add` (that would make disposal depend on a main loop iterating — no test here runs one — and move destruction to an unpredictable point). |
| 2 | `e281d8f3` | **1, 2, 3** (mechanism) | `gir_gen`: a `(nullable ...)` override action, because the generator is right and the GIR is wrong. Also fixes `class_gen_property.ml`'s nullable-property class wrapper, which emitted `string option option` and a setter that does not typecheck — a bug this override was the first thing ever to reach. |
| 3 | `bcd39f14` | **1, 2, 3** (bindings) | `Widget.set_name`, `Stack_page.set_title`, `Password_entry.get/set_placeholder_text` now take/report `string option`. Three override entries plus the regenerated stubs, applied by hand. |
| 4 | `a913c307` | **4b** | Transfer-container list returns sink their elements. 21 sites; 20 were wrong (19 missing `g_object_ref_sink`, 1 missing `g_boxed_copy`). Includes `gtk_list_box_get_selected_rows`, the one M2 hit. |
| 5 | `4ea70268` | **4c** | 279 constructors over plain `GObject`s stop `g_object_ref_sink`ing a reference the constructor already transferred. Audited: none of the 279 descends from `GInitiallyUnowned`. |

**Commits 4 and 5 are regenerations applied by hand** — `gir_gen` has emitted both since
fork commit `3322e3b6`, which never regenerated the tree. A wholesale regeneration is not
usable: it reverts fork commit `2ed607d2` and rewraps ~929 files' doc comments.

## What remains

**Item 4d is reported, not implemented** — by design, per the brief ("list them as
*findings*"). Full detail in the "Item 4 (d)" section above. In priority order:

1. **Transfer-full `char*` return leak** (`gtk_text_buffer_get_text` and siblings) —
   *genuine new generator work, not a regeneration*. The largest remaining win: 1 MB leaked
   per keystroke in a 1 MB buffer.
2. **Transfer-full GObject in-parameters** (~30 sites) — **must not be regenerated yet**: at
   least 6 sites would `g_object_ref` a `GtkExpression`, which is not a `GObject`.
3. GBytes boxed-copy returns (6 sites) — same stale-tree family, held back only for scope.
4. 11 constructors still sink a non-`GInitiallyUnowned` type (4 Gsk, 5 Gio-Unix, 2 more).
5. `gtk_drop_down_get_selected_item` broken twice over; `Gobject.unref` and `Widget.destroy`
   unbound.

Nothing from items 1–3, 4a, 4b or 4c is outstanding.

## Test results — what was run against the patched fork

**ocgtk's own suite: run against the patched fork, green.**

| | suites | tests | failures |
|---|---|---|---|
| baseline `d98d9397` | 29 | 373 | 0 |
| branch head `4ea70268` | **33** | **388** | **0** |

`gir_gen`: 561 → **574 tests, 0 failures**. Four new ocgtk suites, 15 new cases. The
list-box fix is mutation-verified: without the sink the same invocation hangs (killed at
60 s and again at 90 s); with it, 11 ms.

**bonsai_gtk `ci.sh`: run twice, green both times.** Note `ci.sh`'s first step
(`nix build .#ocgtk`) always builds the *pin* from GitHub — it cannot see `.ocgtk-src`.
Every other step reads the opam path pin.

| run | switch held | bonsai_gtk sources | result |
|---|---|---|---|
| 1 | **patched fork** | + the 6-line adaptation patch, + 1 promoted golden line | **all green** |
| 2 | **pin** | as committed (docs + comment only) | **all green** |

Run 2 is the state being checkpointed.

## Opam switch state: **pointing at the PIN**, not the patched checkout

Verified two ways, not just by the stamp:

- `_opam/.opam-switch/bonsai-gtk-ocgtk-rev` = `d98d939711d315cfb595d472594407044ff4f147`
- the finaliser guard's `g_warning` string is **absent** from `_opam/lib/ocgtk/*.a`

This matches `ocgtk-pin.json`, so `setup-switch.sh` will correctly do nothing, and anyone
running `ci.sh` after the reboot gets green with no surprises. `.ocgtk-src` is left checked
out on `m2-bindings` (so the branch is ready to push) — that is the one deliberate
inconsistency, and it is invisible to every tool because opam only re-syncs the path pin on
an explicit reinstall.

### To install the patched fork (exact commands)

```bash
cd ~/src/bonsai_gtk
git -C .ocgtk-src checkout m2-bindings     # already there; harmless
nix develop . -c sh -c 'eval "$(opam env --switch=. --set-switch)" \
  && opam reinstall -y --assume-depexts ocgtk'
git apply .superpowers/sdd/2026-08-30-bonsai-gtk-m2/task-14-pin-bump.patch
```

The patch is **not optional** — bonsai_gtk does not compile against the new signatures
without it (`src/attr_apply.ml`, `src/widgets/w_stack.ml`,
`src/widgets/w_password_entry.ml`, plus the `live_text.ml` ref-count probe and its golden).

### To restore the pin (exact commands)

```bash
cd ~/src/bonsai_gtk
git checkout -- src/ test/                 # drop the adaptation patch, if applied
git -C .ocgtk-src checkout d98d9397
nix develop . -c sh -c 'eval "$(opam env --switch=. --set-switch)" \
  && opam reinstall -y --assume-depexts ocgtk'
git -C .ocgtk-src checkout m2-bindings     # leave the branch ready to push
```

Each reinstall takes roughly two minutes.

## Reboot risk, and the insurance taken

`.ocgtk-src` is **gitignored inside bonsai_gtk and the branch is unpushed**, so those five
commits exist in exactly one place on disk. `setup-switch.sh` has an `rm -rf .ocgtk-src`
path (it fires when the checkout's `origin` does not match the pin's owner/repo), and the
backlog already notes it does not notice a dirty tree. So I bundled the branch:

```
.superpowers/sdd/2026-08-30-bonsai-gtk-m2/task-14-ocgtk-m2-bindings.bundle   (87 KB)
```

`git bundle verify` passes; it contains `refs/heads/m2-bindings` at `4ea70268` and requires
`d98d9397` as its base. To recover into a fresh checkout:

```bash
git -C ~/src/bonsai_gtk/.ocgtk-src fetch \
  ~/src/bonsai_gtk/.superpowers/sdd/2026-08-30-bonsai-gtk-m2/task-14-ocgtk-m2-bindings.bundle \
  m2-bindings:m2-bindings
```

Caveat: the bundle, this report and `task-14-pin-bump.patch` all live under `.superpowers/`,
which bonsai_gtk gitignores — they survive a reboot but **not** a clean re-clone. Pushing
the branch (step 1 below) retires this whole risk.

## Precise next steps

1. **Push the branch** — `cd ~/src/bonsai_gtk/.ocgtk-src && git push origin m2-bindings`.
   `origin` here is the https remote. `~/src/ocgtk` is a *different* checkout, on
   `upstream/gobject-ownership`, which I did not touch.
2. `nix-prefetch-github dlobraico ocgtk --rev 4ea702684784253cf4823d0725f6ad867cb8e6be`
3. Bump `rev` + `hash` in **`ocgtk-pin.json` in both repos** — bonsai_gtk and Stavekeeper.
   *One file each, not three*: both `flake.nix` files and both setup scripts read the pin
   file. Stavekeeper has no `nix/ocgtk/*.patch` to rebase.
4. `git apply .superpowers/sdd/2026-08-30-bonsai-gtk-m2/task-14-pin-bump.patch` in
   bonsai_gtk. Stavekeeper needs **no** source change (grep-verified: zero uses of the three
   changed functions, zero `destroy` handlers; not build-verified).
5. `./scripts/setup-switch.sh && nix develop . -c ./scripts/ci.sh` in bonsai_gtk, then
   `./scripts/setup-ocgtk.sh && nix build .#ocgtk` in Stavekeeper.
6. Optional follow-up, deliberately not taken: the *behavioural* half of items 1–3 — make
   `Unset Widget_name` write `None`, and let a page that loses its `Attr.page_title` get no
   switcher button. The patch is behaviour-preserving on purpose; these are M2 behaviour
   changes with goldens attached.
7. Before any of it goes upstream: cherry-pick onto `upstream/main` and re-run the scrub
   grep — my messages are clean, but `a913c307` and `4ea70268` edit files that still carry
   `score-library-*` comments in their diff context.

---

# Fix round 1

Six commits on `m2-bindings`, on top of `4ea70268`, one per finding and in the
order the review set. **Nothing was pushed. `ocgtk-pin.json` was not touched.**
42 files, +1527 / −90.

```
cd071aa1 docs tests: the GtkAdjustment comment, the override reference, and a lost entry
af8a0916 docs: the finaliser guard is a behaviour change, and CHANGELOG says so
3c9e781b common: say the emission was dropped once, and do not make it fatal
d06c88fb common: the finaliser guard covers all three finalisers, not one
95c1d6e8 gtk gio: a bare GObject is a GObject, and borrowed ones need a reference
03ba87f8 pango: GlyphItem.apply_attrs must not free the record its caller owns
```

| finding | commit | files | generator vs stub |
|---|---|---|---|
| **C1** | `03ba87f8` | 23 (+880/−34) | generator (new override action) + 1 regenerated stub |
| **I1** | `95c1d6e8` | 14 (+233/−6) | generator (type mapping) + 11 regenerated stubs |
| **I2** | `d06c88fb` | 4 (+132/−17) | hand-written C (`common/`), no generated file |
| **I3** | `3c9e781b` | 3 (+81/−12) | hand-written C, no generated file |
| **I4** | `af8a0916` | 1 (+67) | `CHANGELOG.md` only |
| **I5, I6, minors** | `cd071aa1` | 3 (+135/−22) | generator (`bin/`) + docs + one test |

**One deviation from the ruling, argued below**: I1's fix is at the type
mapping rather than in the list-conversion branch, which takes 12 sibling sites
with it. The narrow fix was written first and does not survive the test the
ruling itself asks for. Everything else follows the ruling as written.

---

## C1 — `Glyph_item.apply_attrs` (`03ba87f8`)

**Generator, via a new override action**, exactly as ruled.
`(return-aliases-instance)` on a method sets `gir_method.return_aliases_instance`,
which `C_stub_list_conv.generate_list_cleanup` reads to emit the list-node free
without the per-element `g_boxed_free` loop, and a C comment saying why.

- Type: `Override_types.override_action` gains `Return_aliases_instance`.
- Parser: `(return-aliases-instance)` bare or parenthesised, rejected on any
  component kind but `method`.
- Data: `(record GlyphItem (method apply_attrs (return-aliases-instance)))` in
  `ocgtk/overrides/pango.sexp`, with the whole story in a comment above it.
- Stub: `ocgtk/src/pango/generated/ml_glyph_item_gen.c` — one hunk, taken from a
  regeneration and verified byte-identical to it afterwards. No other pango
  stub changes (the one other difference in that namespace,
  `ml_fontset_simple_gen.c`, is the held-back transfer-full in-param class and
  was not touched).
- Docs: `architecture/gir_gen/overrides.md` — a section for the action, an
  applicability table, and a corrected `override_action` type (it still read
  `Ignore | Set_version of string`).

**What it does not fix, stated in the override comment and in `overrides.md`:**
the other elements now leak again, as they did before `a913c307` added the loop.
Closing that needs the transfer-full *instance-parameter* class handled — the
stub hands a callee that takes ownership the wrapper's only pointer — which is
the same family as held-back item 4d #1 and is not a one-line change.

### The aliasing audit

An XML pass over all nine bundled GIRs, looking at every `<method>`,
`<function>` and `<constructor>` whose `<return-value>` is a `GLib.List` or
`GLib.SList`:

| | count |
|---|---|
| list-returning callables, all namespaces | **93** |
| …whose `<instance-parameter>` is `transfer-ownership="full"` | **1** — `pango_glyph_item_apply_attrs` |
| …with any *ordinary* parameter `transfer-ownership="full"` | **0** |
| …with an instance-parameter transfer that is neither `none` nor absent nor `full` | **0** |

So there is no second aliasing site to fix, and the reviewer's two confirmed
siblings are kept: `ml_attr_list_gen.c:149` and `ml_attr_iterator_gen.c:65`
still free their elements, correctly — their instance parameters are transfer
none and Pango returns freshly allocated attributes. Those three are also the
*only* three per-element free loops in the whole generated tree
(`grep -rn "for (_l = c_result"`), so the audit is closed from both ends.

### Regressions

**gir_gen** (+19 tests, 574 → 593). Parser: the action on a record method,
alongside `(os …)`, and rejected on a constructor and on a property. Apply: the
flag lands on the named method and not on its sibling, and the method survives
(it is not a filter). Generation, both directions: a transfer-full GSList of a
value-like boxed record emits `g_boxed_free(pango_glyph_item_get_type(), …)` by
default and does not with the flag, still frees the nodes, and still says why;
plus the same pair end-to-end through `generate_c_method` from a `gir_method`,
so the plumbing is covered and not just the leaf function. One more asserts the
flag is inert on `transfer-ownership="container"` (byte-identical output).

*Mutation:* with the `when aliases_instance` guard disabled in
`generate_list_cleanup`, `"no per-element free when the elements alias the
instance"` fails.

**ocgtk** — `tests/gtk/test_glyph_item_alias.ml`, a new suite, four cases.

Nothing in the bindings produces a `PangoGlyphItem`: `pango_itemize` and
`pango_shape` are namespace-level functions, of which the generator emits none,
and `PangoLayoutLine`'s runs are not bound. So `test_glyph_item_alias_stubs.c`
shapes one through a `GtkWidget`'s `PangoContext`, copies the first run, and
wraps it in the same `gir_record` custom block a generated stub would — same
`g_boxed_free` finaliser, same ownership — and exposes `item->num_chars` so the
test can read the original back *through the wrapper* after the call.

*Mutation:* with the free loop restored in `ml_glyph_item_gen.c`, that suite is
`Segmentation fault (core dumped)` and `dune build @ocgtk/tests/gtk/runtest`
exits 1 naming `test_glyph_item_alias`. With the fix, four cases in 19 ms.

---

## I1 — bare-GObject elements, and the eleven siblings (`95c1d6e8`)

**Generator**, but at the type mapping rather than the list branch. This is the
one place I went past the ruling, so here is the whole of why.

`GObject.Object` and `GObject.InitiallyUnowned` are the two GObject-namespace
types `gir_gen` maps by hand — there is no `GObject-2.0.gir` in the checkout —
and both carried `transfer_strategy = Ts_none`. `Ts_none` reads as
"ownership-agnostic value" to **two** consumers, not one:
`c_stub_list_conv`'s borrowed-element branch (the ruling's target) and
`generate_ref_sink_stmt`, which decides whether a borrowed *scalar return*
takes a reference. Both then hand the pointer to `ml_gobject_val_of_ext`, which
by its own contract does not ref, while `finalize_gobject` unconditionally
unrefs.

I wrote the narrow fix first — an `is_bare_gobject` predicate in
`Gir_type_pred`, consulted from the list branch only — and it regenerates to
exactly the one line the review asks for. Then the test the ruling asks for
("a builder that constructs objects then `Gc.full_major`") has to read an
object back, and the only way to do that is `Builder.get_object`, which is the
*return* half of the same hole. With only the list branch fixed, the suite does
this:

```
Gtk-CRITICAL: GtkLabel 0x… has a parent GtkBox 0x… during dispose.
Did you call g_object_unref() instead of gtk_widget_unparent()?
Gtk-CRITICAL: gtk_widget_unparent: assertion 'GTK_IS_WIDGET (widget)' failed
   … forever …
```

GtkBox's dispose drains its child list against a freed child and never stops:
1.9 GB of stderr in about thirty seconds, 100% CPU, no output from the test.
That is the hang shape `docs/m1-backlog.md` records for drain loops, and it is
also the closest thing to a reproduction of the reviewer's own failure scenario
for I1 ("the next `Builder.get_object b "id"` returns a freed pointer"). So the
narrow fix leaves the branch in a state where the regression test for the
finding cannot be written honestly.

The fix is one word in each of two mapping entries: `Ts_gobject`, which is what
these types are.

### Blast radius, measured rather than reasoned

The whole tree regenerated twice — once at `4ea70268`'s generator, once with
the change — and diffed in full (`diff -rq`, not just `.c`):

**13 lines in 11 files. Nothing else. No `.ml`, no `.mli`, no other `.c`.**

| | site |
|---|---|
| list element (the ruling's line) | `gtk_builder_get_objects` |
| borrowed returns (12) | `gtk_builder_get_object`, `gtk_builder_get_current_object`, `gtk_widget_get_template_child`, `gtk_drop_down_get_selected_item`, `gtk_single_selection_get_selected_item`, `gtk_list_item_get_item`, `gtk_list_header_get_item`, `gtk_column_view_cell_get_item`, `gtk_column_view_row_get_item`, `gtk_object_expression_get_object`, `g_task_get_source_object`, `g_file_info_get_attribute_object` |

All twelve are `transfer-ownership="none"` or floating, because
`generate_ref_sink_stmt` emits nothing for `full` or `container` — an owned
return is untouched by construction.

**The held-back transfer-full GObject *in-parameter* class gains not one site.**
That was the risk worth checking and it does not materialise: those parameters
are typed classes (`GtkExpression`, `GtkLayoutManager`, `GListModel`), not bare
`GObject.Object`, so nothing in `nullable_ml_to_c_expr`'s `Ts_gobject` branch
changes. The three files that already carry hand-applied in-param hunks
(`ml_drop_down_gen.c`, `ml_single_selection_gen.c`, `ml_widget_gen.c`) took
*only* their `ref_sink` line, applied by hand; the other eight are byte-identical
to regeneration.

Side effect worth recording: this closes half of the report's own item 4d #5,
`gtk_drop_down_get_selected_item` "broken twice over". The sink is now there;
the `.mli`'s `option` promise is still unkept.

### The bare-GObject audit

Two independent passes, agreeing:

- **GIR scan** — of the 93 list-returning callables, exactly **one** has bare
  `GObject.Object` elements: `gtk_builder_get_objects`, `transfer-ownership="container"`,
  doc *"this function does not increment the reference counts of the returned objects"*.
- **Regeneration diff** — the only list-element line that changes anywhere in
  the tree is that same function's.

Neither `Gio` nor `Gdk` nor any other namespace has a second one.

### Regressions

**gir_gen** (+3 cases). A borrowed bare-GObject return takes a reference; an
owned one does not; borrowed bare-GObject list elements are `g_object_ref_sink`ed
*and* still go through `ml_gobject_val_of_ext`. Each runs for both
`GObject.Object` and `GObject.InitiallyUnowned`.

**ocgtk** — three cases added to `tests/gtk/test_transfer_container_lists.ml`.
A `GtkBuilder` built from XML, `get_objects` taken ten times, the wrappers
dropped, two major collections, and then the objects read back by id: their
type names must still be `GtkLabel` and `GtkBox`, which `G_OBJECT_TYPE` on a
freed pointer is not. Plus a `refcount_invariant` helper — take the list twenty
times, assert the element's reference count has not moved — now applied to
Builder and FlowBox as well as ListBox.

*Mutation:* the 1.9 GB drain loop above **is** the mutation result. It is what
the branch does with the element sink applied and the return path left alone,
which is the state the narrow fix would have shipped.

---

## I2 — the guard covers all three finalisers (`d06c88fb`)

Named in the commit, and in `wrappers.h`'s own comment, which previously
described a contract only one of them kept:

- `finalize_gobject` (`wrappers.c`) — its own `g_object_unref`; already guarded.
- `finalize_gvalue` (`ml_gobject.c`) — `g_value_unset` on an object-typed
  GValue **is** a `g_object_unref`, and `ml_g_object_get_property` hands OCaml a
  GValue holding a strong reference as a matter of course.
- `finalize_gir_record` (`wrappers.c`) — `g_boxed_free` only. The `g_free`
  branch beside it cannot run user code and is deliberately left alone, so the
  guard stays as narrow as the hazard.

**Regression:** a fourth case in `test_dispose_reentry.ml`, reaching the crash
through `finalize_gvalue`, as ruled. Ten labels with allocating `destroy`
handlers are parked in ten GValues; the widget wrappers are dropped and
collected *first* (nothing is disposed — the GValues still own them), and only
then are the GValues dropped, which makes `finalize_gvalue`'s unref the last one
deterministically rather than `finalize_gobject`'s, which was already guarded
and would have masked it.

*Mutation, two ways.* Removing the two new lines around `g_value_unset`:

- with the handler at 200 words, it **runs, ten times out of ten**, and the case
  fails on `no handler ran during GValue finalization: expected 0, received 10`;
- with the same handler at 20 000 words, the process **wedges instead** — 100%
  CPU inside the case, no output, killed at 2m40s.

Which of the two a given allocation produces is the unstable threshold
`7619876c` already measured, and it is exactly why the deterministic assertion
was worth adding (see M8 below).

**`finalize_gir_record`'s guard has no test, and I did not invent one.** Reaching
the crash through it needs a boxed type that owns a GObject whose dispose emits
a signal an OCaml handler is connected to; no *bound* boxed type in this binding
qualifies today. It is guarded because the same reasoning applies to it, not
because a test forced it, and the commit says so.

---

## I3 — the report is rate-limited and no longer fatal (`3c9e781b`)

**Chosen: `G_LOG_LEVEL_MESSAGE` once per process behind a `g_once_init_enter`
gate, then `G_LOG_LEVEL_DEBUG`.** That is the reviewer's "`g_warning` once then
`g_debug`" with one change — the first one is `MESSAGE`, not `WARNING` — which
is what makes it satisfy *both* halves of the finding at once:

- **Rate-limited.** Measured on the existing suite: ten warnings per case × four
  cases → **one message in the whole process**.
- **Not fatal.** `G_DEBUG=fatal-warnings` and
  `g_log_set_always_fatal(G_LOG_LEVEL_WARNING)` both cover `WARNING` and
  `CRITICAL` and neither covers `MESSAGE`. A one-shot `g_warning` would have
  fixed the flood and left the abort.

`MESSAGE` is printed by GLib's default handler, so the diagnostic survives; the
per-signal detail moves to `DEBUG`, which `G_MESSAGES_DEBUG=all` turns back on;
and the first message says that later drops are logged at debug level, so nobody
concludes it happened once.

**Pinned, not measured once.** `ocgtk/tests/gtk/dune` gains a `(rule (alias
runtest) (action (setenv G_DEBUG fatal-warnings (run …))))` that runs the same
binary a second time. *Mutation:* with the per-occurrence `g_warning` restored,
that invocation is `Aborted (core dumped)`, exit **134**. As it stands it is six
cases in 11 ms.

---

## I4 — the semantic change, where a consumer reads it (`af8a0916`)

`CHANGELOG.md` gains an `[Unreleased]` section whose **first** heading is
"Behaviour change — signal handlers reached from a GObject finaliser no longer
run", written in the second person: what stops working, that it is not a no-op
(the handler ran ten of ten before), what to do instead (disconnect before the
object can become collectable), why running it is not an option, and why the
`g_idle_add` alternative is not either. The other four M2 fixes and the two from
this round are listed under it.

The marshaller's header comment carries the same statement — the paragraph
beginning `BEHAVIOUR CHANGE, and the reason this is in the CHANGELOG rather
than only in a comment` — and also records the reviewer's `return_value`
question: the early return leaves it at the type's default, every signal that
reaches the branch is dispose-emitted, and none of them returns a value. **That
comment landed in `3c9e781b` rather than `af8a0916`**, because it was one edit
away from the log change in the same function; the CHANGELOG is its own commit.

The bonsai_gtk line is in that repository, not the fork — see "In bonsai_gtk"
below.

---

## I5, I6 and the Minors (`cd071aa1`, and where else they landed)

**I5 — `GtkAdjustment`.** Confirmed: `gir/Gtk-4.0.gir:6774` says
`parent="GObject.InitiallyUnowned"`, and `ml_adjustment_gen.c:26` correctly
keeps its sink. Rather than move it into `test_widgets_are_still_sunk` (it is
not a widget, and that case is about the widget rule), it gets its own case,
`a non-widget GInitiallyUnowned is still sunk`, which asserts the **parentage**
— `Gobject.Type.is_a "GInitiallyUnowned"`, and *not* a `GtkWidget` — rather than
only the refcount. The refcount is what made the wrong comment look right; the
parentage is what a maintainer needs to see before deleting the sink.

**I6 — the override reference.** `architecture/gir_gen/overrides.md` gains a
`(nullable ...)` section: the three forms and what each means, where each is
valid, that it removes nothing (the one component action that is not a filter),
and one paragraph per live entry on why it is a *data* bug rather than a
generator bug. The `override_action` type and the `(return-aliases-instance)`
grammar went in with C1, because a type snippet has to be correct as a whole.

**A bug found while writing I6, fixed in the same commit.** `gir_gen overrides`
— the regenerator that same document tells you to run when GTK upgrades —
rebuilds enum, bitfield and record entries from their component lists, and for
records it only ever looked at `fields`. A record's constructors, methods and
functions were dropped silently. Nothing was exposed to that before this branch:
`(record GlyphItem (method apply_attrs (return-aliases-instance)))` is the only
record override in the tree with a non-field component, and losing it puts C1's
double free straight back. *Mutation:* with the new `~get_extra_components`
neutered, regenerating `pango.sexp` writes `(record GlyphItem\n  )` — the entry,
emptied. With it, the method survives verbatim.

### Minors

| | disposition |
|---|---|
| **M1** — `override_apply.ml` claims a validation that does not exist | **Fixed in `03ba87f8`.** The claim is now true: `Override_parser` rejects a named target on a property's `(nullable)` outright, and the comment says so and says why the function ignores its argument. |
| **M2** — `(nullable …)` a silent no-op on constructors, signals, members, fields | **Fixed in `03ba87f8`**, as a hard parse error rather than the warning the review suggested. Unlike an unknown method *name*, which needs the GIR and is therefore a warning, a qualifier on the wrong component kind is decidable from the sexp the parser is already holding — and the fork's parser already hard-errors on everything it can decide (malformed sexp, duplicates, unknown kinds). Five cases pin it. |
| **M3** — `4ea70268`'s message miscounts (190 vs 206 files; `gdkpixbuf` unlisted) | **Not fixed, and cannot be**: the branch is pushed and the brief forbids rewriting history. The count is wrong in a message, not in the code. |
| **M4** — `a913c307`'s message misclassifies 7 of 24 sites | **Not fixed, same reason** — but the part that *matters* is repaired where it can be: the review's point is that "the stated container rationale is what makes C1 look correct", and C1's own commit, the override comment, and `overrides.md` now all state the actual classification (transfer-full on both ends, aliasing stated only in prose). A reader who follows the code rather than the message gets the right story. |
| **M5** — the vacuous switch-state proof (`_opam/lib/ocgtk/*.a`) | **Accepted; not repeated.** The check below uses `_opam/lib/ocgtk/common/libocgtk_common_stubs.a`, which is where the string actually lives, and reports both readings. |
| **M6** — the pin-bump patch leaves a comment that becomes false | **Fixed**: `task-14-pin-bump.patch` now also rewrites `w_password_entry.ml`'s "this setter is not nullable" paragraph. |
| **M7** — the ListBox mutation does not reproduce as described | **Accepted, and now explained.** The reviewer's fast `[FAIL]` is what that mutation does on its own. The report's hang is real too and I reproduced its *shape* independently (see I1): an unbalanced unref on a parented widget puts GtkBox's dispose into a drain loop that never terminates. Which of the two you see depends on whether the corrupted object is reached by an assertion or by a drain loop first. The report should have said "hangs *or* fails" and given the condition; it said only the first. |
| **M8** — `test_dispose_reentry.ml` asserts nothing | **Fixed in `d06c88fb`.** All three finalisation cases now assert `no handler ran during finalization = 0`. It is a real statement — before the fix the counting handler ran ten of ten — and it is what caught I2's mutation deterministically when the crash did not come. |
| **M9** — the transfer-container test pins 2 of 24 sites | **Partly fixed, deliberately.** The refcount-invariance technique is lifted into a `refcount_invariant` helper and applied to three sites (ListBox, FlowBox, Builder), so adding a fourth is three lines. I did not table-drive the remaining 21: several need non-trivial setup (`text_iter`, `tree_view`, `cell_layout`, `window_group`, `accessible_list`), four of the 24 are `transfer-ownership="none"` and take no sink at all (M4's own point), and doing it properly is a task rather than a fix-round minor. The comment above the helper says so and names the gap. The `require_gtk` skip the reviewer notes is inherent — the objects are GTK widgets — and CI runs under Xvfb. |
| **M10** — 31 constructors build non-GObject fundamentals | **Not fixed; agreed it deserves its own issue.** It is pre-existing, it is the same root cause as held-back 4d #1, and fixing it means teaching the generator about ref-counted non-GObjects (`GskRenderNode`, `GtkExpression`) — which is the prerequisite the report already records for 4d #1. Filed here rather than in `bd`, which the brief forbids. |
| **M11** — `expected_controllers.txt` focus flake | **Not Task 14's, and not touched.** Recorded below under "Carries" so it is not misattributed to the pin bump. I did not hit it in this round's `ci.sh` runs. |

---

## Test results

**gir_gen** (`dune test gir_gen/ --force`):

| | tests | failures |
|---|---|---|
| `4ea70268` | 574 | 0 |
| this round | **593** | **0** |

**ocgtk** (`xvfb-run -a dune test ocgtk/ --force`):

| | suites | tests | failures |
|---|---|---|---|
| baseline `d98d9397` | 29 | 373 | 0 |
| `4ea70268` | 33 | 388 | 0 |
| this round | **34** | **397** | **0** |

One new suite (`test_glyph_item_alias`) and nine new cases: four in it, three in
`test_transfer_container_lists`, one in `test_dispose_reentry`, one in
`test_constructor_ownership`. Dune reports **35 runs / 403 tests** because
`test_dispose_reentry` is executed twice — once normally and once under
`G_DEBUG=fatal-warnings`, which is I3's gate.

## In bonsai_gtk

One commit on `m2`, and one refreshed patch.

- `docs/upstream/README.md` — the "Not yet pushed: the M2 branch" table gains
  the six fix-round commits, and a paragraph stating the finaliser guard's
  behaviour change for anyone reading this repository rather than the fork's
  CHANGELOG (ruling I4's third place).
- `task-14-pin-bump.patch` — **refreshed**, and it is still the only bonsai_gtk
  source change the pin bump needs. Nothing in this round changes a signature:
  the two memory fixes are internal to the C stubs. The one edit is M6's: the
  `w_password_entry.ml` comment that said "this setter is not nullable" is
  rewritten, since it becomes false the moment the pin moves. `git apply
  --check` clean against the tree as left.

**Neither repository needs any other source change.** Grepped, in both, for all
thirteen functions this round touches (`get_template_child`,
`get_selected_item`, `get_source_object`, `get_attribute_object`,
`get_current_object`, `get_objects`, `Builder.*`, `List_item.get_item`,
`List_header.get_item`, `Column_view_cell/Row`, `Object_expression`): **zero
uses in bonsai_gtk and zero in Stavekeeper**, the only mention being a comment
in `src/live_tree.ml:138` naming `gtk_drop_down_get_selected_item` as a call
that is *missing*. `Glyph_item` is unreachable from OCaml at all. The
`live_text.ml` `GtkStringList` refcount probe is unaffected — `GtkStringList` is
not one of the thirteen — so the golden line the patch already changes is the
only golden this round moves, and it moves for `4ea70268`'s reason, not for
anything added here.

## What ran against what

`scripts/ci.sh`'s first step, `nix build .#ocgtk`, builds the **pinned** fork
from GitHub and cannot see `.ocgtk-src`; every other step reads the opam
switch's `ocgtk`, which is a path pin to `./.ocgtk-src/ocgtk`.

| ci.sh step | run 1 (patched fork installed) | run 2 (pin restored, tree as committed) |
|---|---|---|
| `nix: ocgtk pin builds and passes its tests` | pin | pin |
| format | — | — |
| build | **patched** | pin |
| generated opam files are committed | — | — |
| pure + headless tests | **patched** | pin |
| per-package builds | **patched** | pin |
| live tests (xvfb) | **patched** | pin |
| example smoke | **patched** | pin |
| result | **all green**, exit 0 | **all green**, exit 0 |

Run 1 needed `task-14-pin-bump.patch` applied (it is not optional — bonsai_gtk
does not compile against the nullable signatures without it). Run 2 is the
state being left.

*One correction to the previous report's method.* `ci.sh` failed on its **first**
attempt of run 1 — at the format step, on my own new comment in
`w_password_entry.ml`, which was not wrapped the way this repository's
ocamlformat wants. Reflowed and re-run. That is the patch's formatting, not a
binding problem, and the refreshed patch carries the corrected wrapping.

## Switch state

**Pointing at the PIN**, restored with the report's own commands. Verified two
ways, and this time the second one is not vacuous (M5):

- `_opam/.opam-switch/bonsai-gtk-ocgtk-rev` = `d98d939711d315cfb595d472594407044ff4f147`, matching `ocgtk-pin.json`.
- `strings _opam/lib/ocgtk/common/libocgtk_common_stubs.a | grep -c 'dropping a'` → ****0**, and **2** while the patched fork was installed (the two log strings the rate-limited report uses)**. That is where the string lives; `_opam/lib/ocgtk/ocgtk.a` contains no C-stub strings at all and answers 0 either way, which is what made the previous report's check uninformative.

**A trap worth naming**, found while doing this: `opam reinstall ocgtk` does
**not** update `bonsai-gtk-ocgtk-rev`. That stamp is written by
`scripts/setup-switch.sh`. So with the patched fork installed the stamp still
read `d98d9397…` and was actively misleading — the string check was the only
honest evidence. Anyone verifying switch state after a manual reinstall must
use the string, not the stamp.

### `ci.sh` tails

Run 1, patched fork installed + `task-14-pin-bump.patch` applied:

```
== nix: ocgtk pin builds and passes its tests
== format
== build
== generated opam files are committed
== pure + headless tests
== per-package builds, the way opam --with-test runs them
== live tests (xvfb)
== example smoke
all green
```
exit 0.

Run 2, pin restored, tree exactly as committed (`m2` at `ffd827c`):

```
== nix: ocgtk pin builds and passes its tests
== format
== build
== generated opam files are committed
== pure + headless tests
== per-package builds, the way opam --with-test runs them
== live tests (xvfb)
== example smoke
all green
```
exit 0. No `expected_controllers.txt` flake in either run.

## Found while doing this, not asked for

1. **`gir_gen overrides` silently dropped a record's method overrides.** Fixed
   in `cd071aa1` because C1's own entry was the first thing exposed to it and
   losing it re-introduces a double free. Detail above under I6.

2. **`opam reinstall ocgtk` does not update `bonsai-gtk-ocgtk-rev`.** The stamp
   is written by `scripts/setup-switch.sh`, so between a manual reinstall and
   the next `setup-switch.sh` run the stamp says whatever it last said. With
   the patched fork installed it still read `d98d9397…`. That is worse than no
   evidence, because it looks like evidence. Every switch-state claim in this
   round is backed by the string check instead. Worth either having
   `setup-switch.sh` document it or having the reinstall path clear the stamp.

3. **The fork has no working `dune build @fmt`.** `gir_gen/.ocamlformat` pins
   version `0.29.0` and the `#girgen` shell ships a different build, so
   `ocamlformat` refuses gir_gen files outright; `ocgtk/.ocamlformat` pins no
   version, so the same build reformats most of the tree (`bounded_int.mli`,
   `gError.ml`, …) and `@fmt` fails on files nobody touched. I formatted the new
   files I wrote and left every pre-existing line alone, so the diffs here are
   semantic. Anyone who runs `@fmt` on this branch will see churn that predates
   it. This is the fork's problem, not the branch's, and it should be a bead of
   its own.

4. **The bare-GObject return path had eleven more sites than the review saw**,
   listed under I1. They are fixed here, and one of them is half of the report's
   own item 4d #5.

## Carries

Unchanged from the previous report except where noted.

- **Item 4d is still reported, not implemented** — with one exception: 4d #5's
  missing sink on `gtk_drop_down_get_selected_item` is fixed as a side effect of
  I1. Its `.mli`-promises-an-`option` half is not.
- **4d #1, the transfer-full GObject in-parameter class, is still held back**,
  and this round confirms the reason is still live: regeneration still wants to
  `g_object_ref` a `GtkExpression`. I1 measurably does **not** touch it.
- **4d #4, the transfer-full `char*` return leak**, is still the largest
  remaining win and still genuine new generator work.
- **M10** — 31 constructors building non-GObject fundamentals (28 `GskRenderNode`
  subclasses, 3 `GtkExpression`) whose wrappers go through
  `ml_gobject_val_of_ext` and finalise with `g_object_unref(G_OBJECT(ptr))`: an
  invalid cast plus a leak, pre-existing, not caused by any commit on this
  branch, and the *same* prerequisite as 4d #1. It should be one issue with 4d #1
  rather than two.
- **M11** — the `test/live/expected_controllers.txt` focus flake. I did not hit
  it in either `ci.sh` run this round, which is consistent with a timing flake
  rather than a regression. Still worth its own bead so a future pin bump is not
  blamed for it.
- **`caml_remove_global_root` from `ml_closure_invalidate`** — the residual
  `7619876c` flagged. Still unpinned. It does not allocate, and the counting
  case exercises it, but nothing asserts it.
- **The behavioural half of items 1–3** (make `Unset Widget_name` write `None`;
  let a page with no `Attr.page_title` get no switcher button) is still not
  taken, and the refreshed patch is still deliberately behaviour-preserving.
  M6's comment rewrite says so in the file.
- **`test_glyph_item_alias` needs a display** (`require_gtk`), like every other
  GTK suite here, because a `PangoGlyphItem` has to be shaped through a real
  `PangoContext`. On a display-less runner it skips, and so does the C1
  regression; the gir_gen half of C1's regression does not.
- **bonsai_gtk still has no `gir_gen`-capable dev shell**; every command in this
  round ran through `nix develop ~/src/stavekeeper#girgen`.
## State left

- `.ocgtk-src` on **`m2-bindings`** at `cd071aa1`, eleven commits on the pin
  `d98d9397`, `git status --porcelain` empty. **Not pushed.** The five commits
  that were already on GitHub are untouched — this round only adds on top, as
  instructed.
- `bonsai_gtk` on `m2` at `ffd827c` (one new commit, `docs/upstream/README.md`
  only), working tree clean apart from the pre-existing untracked
  `.beads/issues.jsonl`, which is Beads' own export and not mine.
- The opam switch is back on the **pin**, restored with the report's own
  commands, and verified as above.
- `task-14-pin-bump.patch` refreshed in place, `git apply --check` clean against
  the tree as left.
- The two mutation edits to generated stubs, the four to `common/`, the one to
  the generator and the one to the overrides regenerator were all reverted, and
  every `git status` above is the proof.
- **Nothing was pushed anywhere. `ocgtk-pin.json` was not touched in either
  repository. No `bd` command was run.**

## Precise next steps, updated

Unchanged from the previous report except for the SHA and the count:

1. `cd ~/src/bonsai_gtk/.ocgtk-src && git push origin m2-bindings` — now
   **eleven** commits, head `cd071aa1`. `origin` is the https remote; `~/src/ocgtk`
   is a different checkout and was not touched.
2. `nix-prefetch-github dlobraico ocgtk --rev <the real 40-char sha of cd071aa1>`
3. Bump `rev` + `hash` in `ocgtk-pin.json` in **both** repositories.
4. `git apply .superpowers/sdd/2026-08-30-bonsai-gtk-m2/task-14-pin-bump.patch`
   in bonsai_gtk. Stavekeeper still needs no source change (re-grepped this
   round, including the thirteen functions I1 touches).
5. `./scripts/setup-switch.sh && nix develop . -c ./scripts/ci.sh`, then
   `./scripts/setup-ocgtk.sh && nix build .#ocgtk` in Stavekeeper.
6. Before offering any of it upstream: the scrub grep still applies, and it now
   has to cover eleven commits rather than five. My messages and comments carry
   no ticket ids, but `a913c307`, `4ea70268` and now `95c1d6e8` edit generated
   files that still contain `score-library-*` comments in their diff context.

---

# Fix round 2 — the `fatal-warnings` rule broke the pin's hermetic build

One commit on `m2-bindings`, on top of `cd071aa1`. **Not pushed.**

```
649498b4 tests: assert the report's log level, do not run the suite under fatal-warnings
```

4 files, all under `ocgtk/tests/gtk/`. No production code changed — the
marshaller, the guard and the report level are exactly as `3c9e781b` left them.

## What broke

`nix build .#ocgtk` — `ci.sh`'s first step, and the hermetic proof that the pin
builds and passes its own tests — fails at the `(rule (alias runtest) (setenv
G_DEBUG fatal-warnings …))` that fix round 1 added. The dune log shows the rule,
the alcotest header, the run ID, and then nothing:

```
File "tests/gtk/dune", lines 152-158, characters 0-114:
…
(cd _build/default/tests/gtk && ./test_dispose_reentry.exe)
Testing `GObject finalizer re-entry'.
This run has ID `DYFVNF2D'.
```

No `[OK]`, no `[SKIP]`, no OCaml exception — the signature of a signal, with
alcotest's per-test capture swallowing whatever was written.

## The cause, and it is not our message

Alcotest writes each case's stderr to a file rather than the terminal, which is
why dune's log shows nothing useful. Reproduced outside nix, in a stripped
environment (`env -i`, `HOME=/homeless-shelter`, no D-Bus, no `XDG_*`, under
`xvfb-run`, which is what the derivation's `checkPhase` provides):

```
exit=134
_build/_tests/GObject finalizer re-entry/dispose during finalization.000.output:
(process:589989): Gtk-WARNING **: Unable to acquire session bus:
                                  Could not connect: No such file or directory
```

**GTK's own warning**, emitted the first time a widget is touched when there is
no session bus. It lands during case 0, i.e. after the header — which is exactly
the reported signature. `G_DEBUG=fatal-warnings` is *process-wide*: it makes
every `g_warning` fatal, including ones this binding neither emits nor can
prevent. `SIGABRT`, exit 134.

Our own report was never involved, and the same run without the env var proves
it — it still goes out at the level `3c9e781b` chose:

```
** Message: ocgtk: dropping a "destroy" emission that reached an OCaml handler …
```

`** Message:` is `G_LOG_LEVEL_MESSAGE`. Same run, `exit=0`.

So: the *property* fix round 1 asserted is true and unchanged. The
*instrument* was wrong — it armed a global switch to observe a local fact, and
the sandbox is simply the first environment whose incidental warnings it caught.

## The fix

Assert the level in-process instead. `tests/gtk/ml_gobject_test_helpers.c`
gains a log-capture handler for the default domain (the one `ml_gobject.c` logs
under), and the **first** case of `test_dispose_reentry.ml` asserts, across two
batches of dropped emissions:

- the first report is `G_LOG_LEVEL_MESSAGE`;
- `level land (G_LOG_LEVEL_WARNING lor G_LOG_LEVEL_CRITICAL)` is `0` — i.e. the
  mask `glib-init.c` arms for `G_DEBUG=fatal-warnings` does not cover it. The
  mask comes from GLib's own constants through a C helper, not spelled as a
  number, so it tracks the library actually compiled against;
- exactly **one** MESSAGE in the whole process, every other report `DEBUG`, and
  **still** one MESSAGE after a second batch;
- and no handler ran, either time.

It must stay first — the report is once per process by design, so a later case
would see the `DEBUG` follow-up. A reorder therefore fails loudly on the level
assertion rather than passing silently; the comment says so.

**This is narrower and strictly stronger than the env var.** Narrower: nothing
else in the process is made fatal, so no environment can break it. Stronger: it
pins *which* level we emit rather than observing that one environment happened
not to abort, and it pins the rate limit, which the env-var run could not see at
all.

*Mutation-verified against both halves of the bug it exists for:*

| mutation | result |
|---|---|
| restore the per-occurrence `g_warning` (the original defect) | `FAIL the first report is at G_LOG_LEVEL_MESSAGE — Expected: 32, Received: 16` |
| keep `MESSAGE` but drop the `g_once_init_enter` gate | `FAIL exactly one MESSAGE so far — Expected: 1, Received: 4` |

The env-var rule caught only the first of those.

**A second problem removed with it.** The rule ran the same binary twice under
one `dune runtest`, and both runs wrote into the same
`_build/_tests/GObject finalizer re-entry/` directory. ocgtk's suite is back to
34 runs from 35.

## Verified

| check | result |
|---|---|
| `dune test gir_gen/ --force` | **593 tests, 0 failures** |
| `xvfb-run -a dune test ocgtk/ --force` | **34 runs, 398 tests, 0 failures** (was 35/403 — the duplicate invocation is gone; 397 → 398 distinct for the new case) |
| the suite in the environment that produced the abort | **exit 0, 7/7 `[OK]`** (see below) |
| the derivation, same `checkPhase`, from the local commit | **not completed — see below** |

**The direct proof**, and the cheapest one to re-run. Same stripped environment
that reproduced the failure — `env -i`, `HOME=/homeless-shelter`, no D-Bus, no
`XDG_*`, under `xvfb-run`:

```
exit in the sandbox-like env = 0
  [OK]  dispose during finalization  0  the dropped-emission...
  [OK]  dispose during finalization  1  counting destroy han...
  … 7 tests run.
```

and the warning that used to kill it is **still being emitted**, which is the
point — the fix is "stop making unrelated warnings fatal", not "make the
warning go away":

```
(process:601043): Gtk-WARNING **: Unable to acquire session bus:
                                  Could not connect: No such file or directory
```

Before the commit, that same invocation with `G_DEBUG=fatal-warnings` was
`exit=134`.

### What I did NOT verify, precisely

`flake.nix` builds ocgtk with `fetchFromGitHub` at `ocgtk-pin.json`'s `rev`, so
the pin build necessarily fetches `cd071aa1` from GitHub — which does not
contain this commit. There is no flake *input* for ocgtk, so `--override-input`
has nothing to bind.

The right substitute is to build **bonsai_gtk's own `ocgtk` derivation** — same
`buildDunePackage`, same `doCheck`, same
`xvfb-run dune runtest -p ocgtk -j $NIX_BUILD_CORES` `checkPhase`, same nix
sandbox — with only `src` and `sourceRoot` overridden to a `git archive` of the
local commit:

```nix
let flake = builtins.getFlake "path:/home/dlobraico/src/bonsai_gtk";
    base  = flake.packages.${builtins.currentSystem}.ocgtk;
in base.overrideAttrs (_: {
     src = /tmp/ocgtk-verify/source;      # git archive --prefix=source/ HEAD
     sourceRoot = "source/ocgtk";
   })
```

**I started that build twice and stopped it both times: it does not fit on this
machine's disk right now.** A full ocgtk build in the sandbox needs more than
the ~30 GB free on `/`; the second attempt took the filesystem from 30 GB free
to 0 and had to be killed to keep the machine usable (it had already broken
this session's own temp writes once). Nothing about the failure was ocgtk's —
it never reported a build error, it ran out of room. `/` is back to 30 GB free
and the killed build's tree was reclaimed.

So, plainly: **the fixed commit has not been built inside a nix sandbox.** What
has been verified is the layer that actually failed —

- `nix build .#ocgtk` at `cd071aa1` **did** complete and **did** reproduce the
  failure, so the diagnosis is nix-verified, not inferred;
- the fixed suite passes in an environment reproducing the sandbox properties
  the failure depended on (no session bus, no `HOME`, `xvfb-run`), where the
  old code was `exit=134` and the new code is `exit=0` with the same GTK
  warning still emitted;
- and the commit touches only `tests/gtk/`, removing an env var and adding a
  test — there is no build-system change for the sandbox to trip over.

**Please re-run `nix build .#ocgtk` against the real pin after pushing
`649498b4` and re-prefetching.** If you want it checked before pushing, the
expression is kept at
`.superpowers/sdd/2026-08-30-bonsai-gtk-m2/verify-local-ocgtk.nix` and wants
roughly 30 GB of free space on `/`:

```bash
cd ~/src/bonsai_gtk/.ocgtk-src
rm -rf /tmp/ocgtk-verify && mkdir -p /tmp/ocgtk-verify
git archive --format=tar --prefix=source/ HEAD | tar -x -C /tmp/ocgtk-verify
nix build --impure --no-link -L \
  -f ~/src/bonsai_gtk/.superpowers/sdd/2026-08-30-bonsai-gtk-m2/verify-local-ocgtk.nix
```

It is worth keeping either way: it is the only way to test a fork commit
against the pin's own derivation before pushing, and this round is the second
time that gap has cost a round trip.

## State left

- `.ocgtk-src` on **`m2-bindings`** at `649498b4`, twelve commits on the pin,
  `git status --porcelain` empty. **Not pushed** — the remote is still at
  `cd071aa1`.
- `bonsai_gtk` untouched by me this round: `ocgtk-pin.json`, `src/` and `test/`
  keep the lead's uncommitted pin bump and adaptation patch, and `m2` is still
  at `ffd827c`. Only the report file (gitignored) changed.
- The opam switch is left as found, on the **patched fork** via its path pin.
  Note it now holds `649498b4`'s sources rather than `cd071aa1`'s, because the
  fork checkout is the path pin's source and I rebuilt the tests from it; the
  change is test-only, so nothing bonsai_gtk links against moved.
- Two mutation edits to `ml_gobject.c` were reverted; `git status` above is the
  proof.
- Housekeeping: a `--keep-failed` build directory from the diagnosis is left at
  `/nix/var/nix/builds/nix-569151-476386038` (753 MB). I created it and tried to
  remove it; its contents are owned by `nixbld1`, so it needs root. Everything
  else I created under `/tmp` is gone and `/` is back to 30 GB free.
