# Task 2 report — the phys-equal walk, the unordered marker, the batch cost, `w_switch`

Branch `m2`. Base `1daa1b5`. One commit: **`ee64cc6`** — *Unordered containers, cheaper
reasserts, and a no-diff frame that still reasserts* (27 files, +596/−121).

`nix develop -c ./scripts/ci.sh` ends **`all green`**.

---

## What each step did

**Step 1 — the failing tests**, written before any implementation.

- `test/test_reconcile.ml`, two additions. An expect test *an unordered diff matches by
  key but emits no Move*, which prints the same reorder ordered and unordered side by
  side, then the removal/insertion case, then a list nothing reordered both ways round
  (the claim that `~ordered:false` costs an ordinary patch nothing). And a
  `[%test_unit]` quickcheck, *an unordered diff still matches, and its indices still
  describe the list*: over the same generator as the existing round-trip property, it
  asserts no `Move` is ever emitted, and runs the ops through both `Reconcile.apply` and
  the file's stricter `checked_apply` — the second is the load-bearing one, because
  `checked_apply`'s `Update: stale index/identity` assertion is exactly the claim that
  matching was untouched and that the indices describe the *un-reordered* list.
- `test/live/live_driver.ml` — `phys_view` is built once outside the computation and
  handed back by `Bonsai.return`, so every frame after the first returns the physically
  same node by construction rather than incidentally. The user flips a switch *and*
  navigates a stack; one frame must undo both. The stack half is there because it
  exercises the fixup half of the walk rather than the `reassert` half.
- `test/live/live_containers.ml` — the same three keyed overlay children rendered in
  three different orders. Each label's text is `"item " ^ key`, so a positional match
  rather than a keyed one would repaint child 0 with child 2's text and move the golden;
  and `Gobject.same` against handles taken at mount says the widgets are the same
  GObjects. The only overlay reorder that existed before this changes the list's length
  as well, so this claim had no test.

**Step 2 — verified failure.** `dune build @test/runtest` →
`Error: The function "Reconcile.diff" ... is applied to too many arguments / This extra
argument is not expected` on `~ordered`.

**Step 3 — `vtree/reconcile.ml(i)`.** `diff` gains `?(ordered = true)`. The single
change in the body is at the one point the plan names: where a matched pair's position
change emitted a `Move`, the branch is now

```ocaml
if from = i || not ordered
then [ Update { index = from; ... } ]
else (… ; [ Move { from; to_ = i }; Update { index = i; ... } ])
```

`from = i` takes the same branch (with `index = from = i`), which is why the ordered
path's ops are byte-identical to what they were before — no ordered golden moved anywhere
in the tree. The mli gains the paragraph the task specifies plus one the task did not
ask for and which the code forces (see deviation 2).

**Step 4 — `src/widget_impl.ml(i)`.** `move` becomes an option with the rewritten doc,
including the "why an option rather than a `bool` beside it" paragraph. `batch_if` is
three tokens of implementation and the documented contract from the task text, with the
measured numbers in the doc comment so the abstraction carries its own justification.

**Step 5 — the containers and every controlled kind.** `w_box` takes `Some`; `w_stack`,
`w_grid` and `w_overlay` take `None`, each with its old "documented no-op" comment
rewritten to "this container is unordered; see `Widget_impl.list_ops.move`".

`w_switch`'s `reassert` is hoisted to a top-level `let` and `create` ends with
`reassert w kind` instead of its own `set_active`/`set_state` pair, so the one controlled
prop has one implementation. `set_active_if_needed` is gone; `needs_active` (the
comparison alone) is what `reassert` calls before deciding whether to bracket.

Every other kind with a `reassert` was converted: `w_toggle_button`, `w_check_button`,
`w_spin_button`, `w_scale`, `w_expander`, `w_revealer`, `w_entry`, `w_password_entry`,
`w_search_entry`. Each gained a `needs_*` predicate holding the comparison the
`set_*_if_needed` helper already made, so the comparison has exactly one spelling and the
existing helper keeps its contract (`w_entry.set_text_if_needed` still returns whether it
wrote, which `w_search_entry`'s echo table depends on). Every one of these is a
single-prop `reassert`, so `writes` is one comparison rather than a disjunction; nothing
in the tree today is a multi-prop `reassert`, so the doc's warning about disjunctions is
forward-looking rather than describing existing code.

**Step 6 — `src/patcher.ml`.** The kind-keyed dispatch was already factored, as
`note_interest`, but it mixes the immediate half (present a window, register a stack
name) with the deferred half. `enqueue_fixups ctx ~path ~widget ~interest` is the
deferred half alone; `note_interest` now does its registrations and then calls it, and
`reassert_only` calls it directly. See deviation 3 for the signature.

`reassert_only ctx ~path live` is a plain `let rec` after the `mount`/`patch` chain (it
needs nothing from it). It threads `~path` through `Children.iteri`, which already spells
child paths exactly the way `mount` and `patch` do — so this walk did not need a `path`
field on `live` and the backlog item about that stays untouched.

`patch_list` passes `~ordered:(Option.is_some ops.move)`, and its `Move` arm resolves the
option with an `invalid_argf` on `None` rather than silently ignoring the op. That branch
is unreachable by construction; it is written as a raise because a silently dropped
`Move` is precisely the bookkeeping bug the option exists to prevent.

**Step 7 — `src/driver.ml(i)`.** `frame_body` branches on
`phys_equal node live.Patcher.node`. The old comment's *reasoning* is kept verbatim
(declining a user's edit is what makes a no-change frame the important one); its
*conclusion* now says why re-asserting is the whole of what the skipped patch did. The
mli's `frame` doc gains the paragraph the task specifies, plus the sentence that this is
not the same as skipping the frame and must not become that.

The two facts the task asked to confirm from the pre-flight scan, re-confirmed against
the code: `patch` writes `live.node <- node` as its last statement, and a frame that
raises leaves the old node there — but `Driver.frame` marks the scheduler broken on the
way out and every later frame returns without touching the tree, so the comparison can
never see a stale node in a driver that is still running.

**Step 8 — run, read, promote.** Both goldens that changed did so by **addition only**:
`grep -c '^-|'` over the whole live diff was `0`, and only `expected_driver.txt` and
`expected_containers.txt` appeared at all. No existing expected file churned.

**Step 9 — gate + commit.** `./scripts/ci.sh` → `all green`; `dune fmt` via the
per-directory aliases `ci.sh` uses (plain `dune fmt` fails in this checkout trying to
promote into the read-only `result/` nix symlink — pre-existing, which is why `ci.sh`
lists the directories).

---

## Measured numbers

The pre-flight's escape hatch ("if `freeze_notify`/`thaw_notify` on an unchanged object
is free, delete `batch_if`") did **not** trigger, and pre-flight correction 4 says
`batch_if` stays. Independently re-measured here with a throwaway executable under
`test/live/` (deleted afterwards; `test/live/dune` is unchanged in the commit), 100 000
calls on a real `GtkLabel` after a warm-up pass of the same size, under `xvfb-run`:

| | total | per call |
|---|---|---|
| `Widget_impl.batch w (fun () -> ())` | 5.52 ms | **55.2 ns** |
| `Widget_impl.batch_if false w (fun () -> ())` | 0.23 ms | **2.3 ns** |
| `Widget_impl.batch_if true w (fun () -> ())` | 5.08 ms | **50.8 ns** |

The pre-flight scout measured 7.95 ms / **79.5 ns** per `batch` call on the same shape;
same order of magnitude, and the difference is machine noise between runs rather than a
disagreement. Either way the finding is the same one the plan recorded: cheap, **not**
free. What `batch_if` buys is the third row against the second — roughly **24×** on the
path that writes nothing, which is the overwhelming majority of `reassert` calls. In
absolute terms a 1 000-widget frame saves ~53 µs per frame, ~3 ms/s at 60 fps. The doc
comment on `batch_if` carries the per-call number so the abstraction states its own
justification.

---

## Deviations from the plan, and why

**1. `Reconcile.diff` gained a trailing `unit`, which the task text does not have.** The
task's signature is `?ordered:bool -> key:… -> new_:'a list -> 'a op list`, and it does
not compile:

```
File "vtree/reconcile.ml", line 63, characters 11-18:
Error (warning 16 [unerasable-optional-argument]): this optional argument cannot be erased.
```

Every argument after `?ordered` is labelled and there is no positional one, so OCaml
cannot tell a partial application from a defaulted one. The two ways out are a trailing
`unit` or making `ordered` a required labelled argument. I took the `unit`: it keeps the
plan's "default `[true]`", so the reconciler's ordinary callers and every existing test
say nothing about ordering, and the trailing-`()` idiom is already everywhere in this
repository's node constructors. Three call sites gained `()`. The mli says why the
`unit` is there, so nobody deletes it and rediscovers warning 16.

**2. The mli documents one consequence the task text does not mention, because the code
forces it: an unordered `Update` is indexed by `from`, not by `i`.** The task says
unordered gives "three `Update`s and nothing else, in `new_`'s order". The op *order* is
`new_`'s; the *indices* cannot be, and this is not a choice. If nothing moves, the item
matched at `new_` position 0 is still sitting at its old live position, and an
`Update { index = 0 }` would patch whichever child happens to be there — for
`old = [a;b;c]`, `new_ = [c;a;b]` it would patch `a`'s widget with `c`'s node. So
unordered emits `Update {index=2}`, `Update {index=0}`, `Update {index=1}`, in that
order. The knock-on, also documented: `apply ops old = new_` no longer holds for
`~ordered:false` — only the *set* does, which is the whole content of "the children stay
where GTK put them". The mli's `diff` doc and the new quickcheck both state this
explicitly, and the quickcheck compares sorted lists for that reason.

**3. `enqueue_fixups` takes `~path ~widget ~interest` rather than `ctx ~path live`.** The
plan sketched `enqueue_fixups ctx ~path (live : live)`, but the dispatch it factors out
lives inside `note_interest`, which is called from `mount` *before* a `live` record
exists (the record is built from the result of the call). Taking the three things it
actually needs lets `note_interest` reuse it unchanged; `reassert_only` computes
`interest_of_kind live.node.kind` at its one call site. Same three callers, same
exhaustive `interest` match, no `live` threaded through `mount`.

**4. `note_interest` was already a shared function, not "inline in `mount` and again in
`patch`".** The plan's Step 6 predicts two copies. What the factoring actually achieved
is splitting the immediate half from the deferred half inside that one function, which is
what `reassert_only` needs: it must re-run the selections but must *not* re-present a
window or re-register a stack name. The `Nothing | Window -> ()` arm of `enqueue_fixups`
is where that distinction is stated.

**5. `Move` on a container with no `move` raises rather than being ignored.** Not
specified either way. Written as a raise because the whole point of the option is that
the two sides cannot disagree; if they ever do, a message is better than a child that
silently stops being reconciled.

---

## Proof the new tests bite

Both done against the promoted goldens, then reverted from byte copies (`git diff` clean
afterwards, verified).

**The `enqueue_fixups` call in `reassert_only`** — the task's review focus names this
one. Deleting it turns three lines red across two tests:

```
-|declined page: visible a, Bonsai saw 1
+|declined page: visible b, Bonsai saw 1
-|after the declining frame: switch false, page a
+|after the declining frame: switch false, page b
-|    (GtkStack (visible (a))
+|    (GtkStack (visible (b))
```

The switch line stays `false` throughout, which is the evidence that the two halves are
independently pinned: `reassert` alone passes the switch and fails the stack.

Worth recording separately: the *first* of those lines is the pre-existing
`declining_app` test, unchanged by this task. So that app was already rendering a
physically identical node every frame and is now taking the new no-diff path — its
golden's survival is not a vacuous pass.

**That `~ordered:false` did not change matching.** Corrupting the new branch to
`Update { index = i }` (the plausible wrong answer) is caught three independent ways:

```
-|    (GtkLabel (text "item a")) (GtkLabel (text "item b"))
+|    (GtkLabel (text "item c")) (GtkLabel (text "item a"))
```

in the new overlay test; the *pre-existing* grid-reorder golden
(`(cells (0 0 1 1) (1 0 1 1) (0 1 2 1))` → `(0 1 2 1) (0 0 1 1) (1 0 1 1)`), which is a
container the plan had not flagged as covering this; and the new quickcheck, with
`"Update: stale index/identity: comparison failed"`.

**`w_switch.create` calling `reassert` cannot fire a handler** — checked against
`Patcher.mount` rather than assumed. The order there is `create` → `Attr_apply.snapshot`
→ `apply_all` → `require_specs` → `connect_all` → `require_slots` → `update_slots`. So
`create` runs before `connect_all`: it is not that the slot is empty, it is that no
connection exists at all. The comment in `w_switch.ml` says exactly that rather than the
weaker claim in the task text.

---

## Test output tails

`nix develop -c dune build @test/runtest` — clean, no output. 8 tests in
`test_reconcile.ml`, all passing.

Live suite — new lines only:

```
after mount: switch false, page a
after the user changed them: switch true, page b
after the declining frame: switch false, page a
…
same overlay widgets after one reorder: true
same overlay widgets after another: true
```

`nix develop -c ./scripts/ci.sh`:

```
== nix: ocgtk pin builds and passes its tests
== format
== build
== generated opam files are committed
== pure + headless tests
== per-package builds, the way opam --with-test runs them
== live tests (xvfb)
bonsai_gtk: exception in frame, stopping the driver: (Invalid_argument
  "root/0/1: a Node.window may only be the root node, not a child of another node")
== example smoke
all green
```

---

## Carries for later tasks

- **Task 8 (Notebook)** is the second container with a real reorder: `move = Some …`, and
  it therefore gets `~ordered:true` and real `Move` ops. It is also the first container
  since `Box` whose `move` will be exercised by a live test — `Box` is currently the only
  `Some` in the tree, so the `Move` arm of `patch_list` has exactly one exerciser today.
- **Tasks 6 and 7 (ListBox, FlowBox)** must decide `move` deliberately. `GtkListBox` does
  have insert-at-position but no reorder primitive, and `GtkFlowBox` the same; if either
  takes `None`, its list op comments should say so in the wording the other three now use.
- **`Reconcile.diff` now takes a trailing `()`.** Any new call site needs it; the compiler
  says so, but the error (warning 16, or a type mismatch on the result) is confusing the
  first time.
- **`reassert_only` runs on every idle tick of a settled app**, once per node. It calls
  `Widget_impl.reassert` and `interest_of_kind`, so a new kind whose `reassert` is
  expensive — a `TextView` reading the whole buffer back, Task 9 — is now paying that cost
  on frames that used to at least skip `update`. It always did pay it (`reassert` ran
  unconditionally in `patch` too), so this is not a regression, but Task 9 should know the
  reassert is the *only* thing an idle frame does and size it accordingly.
- **Multi-prop `reassert`.** Nothing in the tree has one yet. The first kind that does
  (Task 9's TextView is the candidate) must make `writes` the disjunction of its per-prop
  comparisons or use plain `batch`; `Widget_impl.batch_if`'s doc says so, and it is a
  correctness matter rather than a performance one.
- **`Patcher.enqueue_fixups` is not exported**, only `reassert_only` is. Tasks 6–8 add
  selection fixups; they extend the `interest` type and the `enqueue_fixups` match, which
  is exhaustive and compiler-checked, exactly as `note_interest` was.
