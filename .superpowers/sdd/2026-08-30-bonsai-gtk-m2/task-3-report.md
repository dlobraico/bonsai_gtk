# Task 3 report — the diagnostics backlog: silent inertness becomes `Invalid_argument`

**Commit:** `b458449` on `m2` (base `ee64cc6`). One commit, 19 files, +828/−83.
**Gate:** `nix develop -c ./scripts/ci.sh` → `all green` (exit 0). Tails at the bottom.

All five items land, plus the two carries from `task-2-review.md` (Minor M1 and M3).
Nothing was left undone; four deviations from the task text are recorded below, one of
them a correction to the task's own prescription and one a ruling the task text asked for
explicitly.

## What changed, per step

### Step 1–2: the failing tests, and proof that they fail

Written first as goldens with empty `[%expect]`s / new `raises` lines, then — because the
implementation had to exist for `~max_length` to typecheck at all — re-proved against the
finished tree by **temporarily neutering the four checks** (placement loop emptied,
claims applied in one loop instead of two, `W_stack.select` returned `()`, the bounds
check `ignore`d) and re-running both suites. Every new assertion moved, and nothing else
did:

```
test/test_widgets.ml
-|    (Invalid_argument "Node.scrolled_window: min_content_width (400) is above max_content_width (200)")
+|    "did not raise"                      (and the same for the height pair)

test/live/expected_containers.txt
+|swap rejected: swap/0/2: two Node.stacks are named "beta" in one tree
+|grid_cell on a box child: NO RAISE
+|page_title outside a stack: NO RAISE
+|measure_overlay outside an overlay: NO RAISE
+|grid_cell on the root: NO RAISE
+|page_title added by a patch: NO RAISE
+|visible_child names no page: NO RAISE
```

The swap line is item 5 reproducing itself verbatim under the one-loop ordering, which is
the evidence that the two-loop application is what fixes it rather than something else in
the diff. The neutering was reverted from saved copies and the suites re-run green.

### Step 3: `Node.scrolled_window`'s bounds check — `vtree/node.ml`, `vtree/node.mli`

`check_bounds` before `make`, per axis, skipping `-1` on either side; equal bounds are a
fixed size, not a conflict. This is the first constructor in `Node` that raises, so there
is a note at the top of `node.ml` saying constructors are otherwise total and why this one
is the exception (the mistake has no later diagnostic, and the two numbers are in the
call), and an `@raise` block on `scrolled_window` in the mli saying the same to a reader
of the docs.

Test: `test/test_widgets.ml`, "a scrolled window rejects a min content bound above its
max" — both axes raise with the exact message; `-1` on either side, equal bounds, and a
both-axes-consistent call all print a node.

### Step 4: `entry_props.max_length`

Verified in the pinned checkout before writing anything, as the task asked:

- `.ocgtk-src/ocgtk/src/gtk/generated/entry.mli:74,305` — `set_max_length : t -> int ->
  unit`, `get_max_length : t -> int`. Present on `Entry` only.
- `editable.mli`, `password_entry.mli`, `search_entry.mli` — **no** `max_length` of any
  kind. `GtkEditable` has no `set_max_length`, so the task's contingency ("if `Editable`
  does have it, add it to all three") does not fire: `Node.password_entry` and
  `Node.search_entry` do not get it, and `node.mli` says so.
- `.ocgtk-src/gir/Gtk-4.0.gir:51070` — `<property name="max-length" … default-value="0">`.
  **The default is `0`, GTK's "no maximum", not `-1`.** `Defaults.Entry.max_length = 0`,
  with a comment saying why this one is `0` while the size requests beside it are `-1`.

`Kind.entry_props` gains `max_length : int [@sexp_drop_if Int.equal
Defaults.Entry.max_length]` (both `.ml` and `.mli`); `Node.entry` gains `?max_length`;
`w_entry.ml`'s `create` writes it when it differs from GTK's default and `update` when it
differs from `old`, both inside the existing `batch`. In `create` it is written *before*
the text, so a `~text` longer than `~max_length` is truncated by the same rule a typed one
would be. It is **not** controlled and `reassert` is untouched.

`Live_tree.dump`'s `GtkEntry` arm gains `int_prop "max-length" … ~default:0`.

Tests: `test/test_widgets.ml` (reaches the kind, `~max_length:0` drops from the sexp,
takes part in `equal_props`) and a new block in `test/live/live_controls.ml` that walks a
cap up, down and back to the default. The down step is the one worth reading:

```
(GtkEntry (text abcdefg) (max-length 8) …)
(GtkEntry (text abc) (max-length 3) …)      <- GTK truncated the text itself
(GtkEntry (text abc) …)                     <- back to 0, dropped by the dump
```

`expected_controls.txt` grew by exactly those four dumps and nothing else, which is the
task's stated check that the default is right.

### Step 5: the placement-attr table — `src/patcher.ml`

Two tables, both in the patcher:

```ocaml
let placement_attrs_read_by : Kind.t -> Attr.Name.t list = function
  | Grid _ -> [ Grid_cell ] | Stack _ -> [ Page_title ] | Overlay _ -> [ Measure_overlay ]
  | _ -> []

let placement_attr_reader : Attr.Name.t -> string option = function
  | Grid_cell -> Some "Grid" | Page_title -> Some "Stack" | Measure_overlay -> Some "Overlay"
  | Margin_start | … | On_visible_child_changed -> None    (* exhaustive, no wildcard *)
```

The first is as the task prescribed, wildcard and all, with the comment saying the
wildcard is the point and naming the arms Tasks 6–8 add. The second is the inverse and
supplies the *"and this one holds children for Grid"* half of the message; it is
exhaustive with no wildcard, so a new `Attr.Name` constructor cannot skip the question
"is this held by the parent?". `placement_attr_names` is derived from it by filtering
`Attr.Name.all`, so the check iterates three `Attrs.find`s rather than the node's attrs.

Messages (both `Invalid_argument`, both node-path-first, §11-shaped):

```
root/0/0: Attr.grid_cell is not read by Box (a placement attribute is read by the
container, and this one holds children for Grid)

root: Attr.grid_cell is on the root node, which has no container to read it (a placement
attribute is read by the container, and this one holds children for Grid)
```

The attr is spelled the way the caller wrote it (`Attr.grid_cell`, not `Grid_cell`) by
lowercasing `Attr.Name.to_string`.

Tests in `test/live/live_containers.ml`: `grid_cell` on a box child, `page_title` on a box
child, `measure_overlay` on a box child, `grid_cell` on the root, and `page_title`
*added by a patch* (rejected on the frame that adds it, path `mis/0/0`). Plus a positive
case mounting a grid, a stack and an overlay each carrying the attr it does read, so the
table is pinned in both directions.

### Step 6: `w_stack.select` raises on an absent name

`page_names` walks `Widget.get_first_child`/`get_next_sibling` and reads
`Stack_page.get_name` off `Stack.get_page` (all four verified present in the pinned
checkout). `select` now matches on `get_child_by_name` and raises when it is `None`,
listing the names the stack does have.

**The premise was checked as the task demanded.** `live_containers.ml`'s
add-and-select-in-one-pass case (`~visible:"encores"` on the frame that adds the
`"encores"` page) runs with the raise in place and does **not** raise: the fixup queue
means the pages are attached before `select` runs. Every other mounted stack in the repo —
the four `stack_view` renders, `two_stacks`, `renamed_view`, `wrapped`, `twins`, `pair`,
`live_patcher.ml`, `live_driver.ml`, `examples/gallery.ml` — names a page it renders.
`test/test_events.ml:36` and `live_events.ml:50` build `Node.stack … ~visible_child:"a" []`
but only read `.kind`, so they never mount.

Message, with the path the patcher now prefixes (see deviation 1):

```
typo/0: Node.stack ~visible_child:"lbrary" names no page (a page's name is its ~key; this
stack has library, practice)
```

### Step 7: the same-frame name swap

See deviation 2 for why the task's prescription does not fit the code. The fix: a pass
records what each stack node gives up and takes into `ctx.stack_claims`, and
`apply_stack_claims` runs at the end of the top-level `mount`/`patch` in **two loops** —
every give-up, then every take. A genuine collision still raises from the second loop,
from `mount`/`patch` (not from `run_fixups`), with the same message and the same path;
every existing rejection golden is byte-identical, which is the evidence.

Test: two keyed stacks whose `~name`s trade in one patch, with a `stack_switcher` naming
each. The assertion is not "nothing raised" but that each switcher resolves to the *right*
stack afterwards, read back through which page it is showing:

```
before the swap, switchers drive: pa, pb
after the swap, switchers drive: pb, pa
```

### Steps 8–9: gate and commit

`dune build @test/runtest` + promote, `BONSAI_GTK_LIVE_TESTS=1 xvfb-run -a dune build
@test/live/runtest` + promote, `./scripts/ci.sh`. **No golden line was deleted or
changed** — `grep -c '^-|'` over the live diff was `0`; all three expected files grew by
addition only.

## The two carries from `task-2-review.md`

**Minor M1 (one-line test change).** `test/live/live_driver.ml`'s `phys` driver now takes
`~on_window_created:(fun _ -> print_endline "phys window created")`, with a comment saying
what it pins: a `reassert_only` that routed `Window` to `on_window_created` would
re-present and refocus a real window on every idle tick and, until now, would have left
every golden byte-identical. `expected_driver.txt` grew by that one line, and it appears
once.

The related observation ("nothing distinguishes the fast path from the slow one; replacing
`phys_equal` with `false` leaves the suite green") was ruled a backlog line rather than a
fix, and is now one, in `docs/m1-backlog.md` under "Tests worth adding", attributed to the
task-2 review.

**Minor M3 (spec amendment).** `docs/superpowers/specs/2026-08-28-bonsai-gtk-design.md`
§5.3 gains an **M2 amendment (2026-08-30)** in the style §5.3 and §11 already use: the
`Unordered` marker exists as `list_ops.move : … option`, no `Move` is emitted rather than
emitted and ignored, `Notebook` takes `Some`, a `Move` reaching a container without one
raises, and an unordered container's ops satisfy `apply ops old = new_` only as a set. The
two superseded sentences are left standing above it, as the file's other amendments do.

**Minor M2** was ruled "leave it" and is left.

## Deviations from the task text

1. **The placement check lives in `check_placement`, called from `mount` and `patch`, not
   in the list and single child helpers.** The task said "add one check there". The
   helpers do not know the parent's *kind* — `mount_single`/`mount_list` are handed the
   parent's `Widget.t` — so either way a `parent_kind` has to be threaded through
   `mount_children`/`mount_slots`/`mount_single`/`mount_list` and their patch twins.
   Threading it one level further, into `mount` and `patch` themselves, buys **one** check
   site per pass instead of five (`mount_single`, `mount_list`, and `patch_list`'s
   `Insert` *and* `Update` arms, plus `patch_single`), each of which would have had to
   spell the child's path again. `check_placement` already existed, already took
   `~path ~is_root`, and already ran at exactly those two points, so the placement rules
   are now in one function. `parent_kind : Kind.t option` is `None` only at the root,
   where every placement attr is rejected.

   Consequence worth knowing: the public `mount`/`patch` keep their signatures — the
   recursive ones take `~parent_kind` and are shadowed at the bottom of the file by
   wrappers that pass `None` and then apply the stack claims.

2. **The swap fix is per *pass*, not per child list.** The task said "two loops over the
   same child list rather than one", which assumes the rename arm runs inside a
   per-children loop. It does not: `note_interest` is called once per *node*, from `mount`
   and from `patch`, so there is no child list to loop over twice — and two stacks
   exchanging names need not be siblings. The generalisation is the same shape one level
   up: collect the pass's give-ups and takes, then apply all the give-ups and then all the
   takes.

   Applied at the end of the **walk**, not from `run_fixups`: it is `mount` and `patch`
   that have to raise, which is what spec §11's "loud and early" and every existing caller
   and golden expect. Two consequences, both checked:
   - the unchanged-name arm's `Hashtbl.set` (the "heal a lost registration" line) becomes
     give-up-then-take of the same name, which still heals and additionally *detects* a
     collision the `set` used to overwrite silently;
   - `abandon_fixups` now clears the claims too, and `apply_stack_claims` empties its own
     queue even when a claim raises, for the reason `run_fixups` does — a failed pass's
     registrations must not be carried into the next frame. `live_containers.ml`'s
     `fixups left behind by the failed pass: 1` line is unchanged.

   `drop_stack_names` is now belt-and-braces (a destroyed subtree's own `unregister_stack`
   runs before any claim is applied). It is kept, with a comment saying so, because it
   states the mount-before-destroy ordering requirement at the place that creates it.

3. **A stack with no pages at all is exempt from the `~visible_child` raise.** The task's
   ruling said to stop and report if there is "any legitimate frame where a stack's chosen
   page is not yet added". There is exactly one, and it is not the race the ruling was
   about: `~visible_child` is a **required** argument, so a model rendering an empty page
   list has no name it could pass that would be right, and every name is absent. The raise
   therefore fires only when the stack has at least one page — at which point the argument
   is a claim about that set and a name outside it is a typo. This is narrower than
   "stop and report": the add-and-select premise the ruling actually asked about holds, and
   the exemption is a strictly smaller carve-out than leaving the whole item inert. Both
   sides are pinned in `live_containers.ml` (`visible_child names no page` raises; `an
   empty stack with an unmatched visible_child is left alone` does not).

4. **The `select` rejection is path-prefixed by the patcher, not by `select`.** As first
   written the message arrived with no node path, because `enqueue_fixups`'s closure is
   not wrapped the way the container ops are — which spec §11 forbids. The enqueue now
   wraps the call in the existing `child_op ~path`, so the message reads `typo/0: …`, the
   stack's own path. `select` still knows nothing about where it is, exactly like every
   other container op.

Also, on the ordering the plan asks for: the tests were written before the code for the
two constructor-level items, but `~max_length` cannot compile before `Kind` has the field,
so the live diagnostics were written alongside their implementations and then proved
failing by neutering (Step 1–2 above). That is weaker than red-then-green in sequence and
stronger than a golden nobody checked; the neutered diff is reproduced above so a reviewer
can re-run it.

## Deliberately not done

- **Slot-level granularity for placement attrs.** The table is keyed by the parent's
  *kind*, so `Attr.measure_overlay` on an overlay's **main** child is accepted and remains
  inert (only the `~overlays` slot reads it). Tightening it means threading the slot name
  in beside the kind; the comment on `placement_attrs_read_by` says so and says when it
  becomes worth doing (a slot container reading two different placement attrs on two
  different slots).
- `Defaults` is not exported from `Bonsai_gtk_vtree`, so `w_entry.ml` compares against the
  literal `0`, matching the `-1`s already in that file rather than adding an export.
- No `Attr.Name.is_placement`. `placement_attr_reader` in the patcher carries the same
  information and the message needs the container name anyway; putting the predicate in
  `attr.mli` would have split one fact across two files.

## Carries for later tasks

- **Tasks 6–8 extend `placement_attrs_read_by`** — `List_box -> [ Row_selectable;
  Row_activatable ]`, `Notebook -> [ Tab_label ]` — **and `placement_attr_reader`**, which
  is exhaustive over `Attr.Name.t` and will therefore refuse to compile until the new
  names are classified. That is the intended forcing function; both tables are adjacent in
  `src/patcher.ml`.
- **Task 12 (`Expert.embed`)** mounts a subtree that is not the tree's root. It must decide
  what `parent_kind` an embedded root has: `None` (reject every placement attr, which is
  what `mount ~is_root:true` does today) is almost certainly right, since the host
  container is an application's own `GtkStack` and nothing in the vtree reads a placement
  attr off it. It must also call `apply_stack_claims` — using the public `mount`/`patch`
  gets that for free.
- **Task 15 (backlog rewrite)**: five "Do first in M2" entries are now closed by this
  commit (`entry_props.max_length`, `min > max` bounds, `grid_cell`/`page_title` inert
  outside their container, the same-frame stack name swap). One new line was added under
  "Tests worth adding" (the unpinned phys-equal fast path).
- **`Node.stack`'s empty-page-list case** is the one place `~visible_child` is
  unsatisfiable by construction. If a later milestone wants that to be expressible rather
  than exempted, the answer is `?visible_child` — a breaking change to a required
  argument, so it belongs with the other API-shape decisions rather than here.

## Verification tails

```
$ nix develop -c ./scripts/ci.sh
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

(The `exception in frame` line is `live_driver.ml`'s deliberately-broken app and is
pre-existing.)

```
$ BONSAI_GTK_LIVE_TESTS=1 xvfb-run -a dune build @test/live/runtest   # clean
$ dune build @test/runtest                                           # clean
$ dune build @all                                                    # clean
```

New golden lines, all additions:

```
test/live/expected_containers.txt
  before the swap, switchers drive: pa, pb
  after the swap, switchers drive: pb, pa
  grid_cell on a box child: root/0/0: Attr.grid_cell is not read by Box (…holds children for Grid)
  page_title outside a stack: root/0/0: Attr.page_title is not read by Box (…for Stack)
  measure_overlay outside an overlay: root/0/0: Attr.measure_overlay is not read by Box (…for Overlay)
  grid_cell on the root: root: Attr.grid_cell is on the root node, which has no container to read it (…for Grid)
  page_title added by a patch: mis/0/0: Attr.page_title is not read by Box (…for Stack)
  the three containers that read a placement attr accept it
  visible_child names no page: typo/0: Node.stack ~visible_child:"lbrary" names no page (a page's name is its ~key; this stack has library, practice)
  an empty stack with an unmatched visible_child is left alone

test/live/expected_controls.txt   four GtkEntry dumps: max-length 4, 8, 3 (text truncated), default
test/live/expected_driver.txt     phys window created
```

---

# Fix round 1

Review: `task-3-review.md`, verdict **Needs fixes** — three Important, six Minor.
Controller rulings: I2 "move it now, don't carry it"; I3 "do (a) AND the honest doc";
M1–M3 as suggested; M4–M6 taken or argued in this report.

**Commits** (both on `m2`, no history rewrite):

| Commit | Covers |
|---|---|
| `a9b7b34` | I2, M6 — the placement table moves to `vtree/`, both consumers read it |
| `3ea4594` | I1, I3, M1, M2, M3, M4, M5 — the two contradicted contracts, and the durability minors |

**Gate:** `nix develop -c ./scripts/ci.sh` on the committed tree → `all green` (exit 0).
No golden line was deleted or changed in either commit; `grep -c '^-|'` over the live diff
was `0` both times. Files touched: `vtree/placement.ml(i)` (new),
`vtree/bonsai_gtk_vtree.ml`, `vtree/node.mli`, `src/patcher.ml`, `src/patcher.mli`,
`src/widgets/w_entry.ml`, `test_lib/bonsai_gtk_test.ml(i)`, `test/handle/test_handle.ml`,
`test/test_placement.ml` (new), `test/live/live_{containers,controls,driver}.ml`,
`test/live/expected_{containers,controls}.txt`, `docs/m1-backlog.md`.

## I1 — the `~visible_child` contract (`3ea4594`)

**Change.** `vtree/node.mli`'s `stack` doc loses *"Naming a page that does not exist leaves
the selection alone rather than raising"* and gains the shipped rule: `Invalid_argument`
from the fixup pass, carrying the stack's node path and the page names it does have; why
the fixup pass is the earliest point the mistake is knowable (a name absent once the whole
tree exists is absent from the *rendered* tree); the consequence the reviewer's failure
scenario names, in the reviewer's own terms — *"a `~visible_child` fed by state that can
lag the page list by a frame (closing a tab, where one effect rewrites the list and
another the selection) must render the two together"*, and *"it stops the driver for good,
like any exception from a frame"*; and the zero-page carve-out, which is **M5** and belongs
exactly there, since it is the contract of a required argument.

`src/patcher.mli`'s `run_fixups` "Raises" paragraph gains the second clause, with the
one-sentence reason it can only be decided from that queue.

**Test.** None added for the doc itself; the behaviour it now describes is pinned by three
goldens — the mount case, the new patch case (M1), and the empty-stack case.

## I2 — the placement table moves to `vtree/` (`a9b7b34`)

Ruled "move it now". Done, and it turned out to be more than a relocation.

**Change.** `vtree/placement.ml(i)`, beside `Events`: `read_by : Kind.t -> Attr.Name.t
list` (the wildcard table, comment intact, including the slot-granularity note), `reader :
Attr.Name.t -> string option` (exhaustive, no wildcard), `names` (derived from `reader`, so
the two cannot disagree about which names are placement attrs), `is_read_by`, `misplaced`,
and `rejection : path:… -> parent:Kind.t option -> Attrs.t -> string option`.

`src/patcher.ml`'s `check_placement` is now two lines:

```ocaml
Option.iter (Placement.rejection ~path ~parent:parent_kind node.attrs) ~f:invalid_arg
```

`test_lib/bonsai_gtk_test.ml`'s `require_supported_events` becomes `require_supported`,
threading `~parent` (`None` at the root) and checking **placement first, then events** —
the order a mount reaches them, so a node carrying both mistakes reports the same one
headlessly and live.

**One departure from the `Events` precedent, deliberately.** `Events`' two consumers
rebuild the message from the same two ingredients and are identical *by convention*
(`Signals.require_specs` says so in a comment). Placement's message has two shapes and
names three things, which is more than a convention can hold, so both consumers call
`Placement.rejection` and raise the string it returns. They are identical outright. The
`.mli` says why the two modules differ here.

**Tests.** `test/handle/test_handle.ml` gains four cases: misplaced `page_title`,
misplaced `grid_cell`, a placement attr on the root, and a positive case mounting a grid,
a stack and an overlay each carrying the attr it reads. The messages are byte-identical to
the live goldens:

```
root/0/0: Attr.page_title is not read by Box (a placement attribute is read by the
container, and this one holds children for Stack)
```

`test/test_placement.ml` (new, `test/`, vtree-only) pins the table itself, which nothing
did before: which names are placement attrs and who reads each; that `reader` classifies
the other 29 of the 32 `Attr.Name.t`s as non-placement; that `read_by` and `reader` are
inverses; that every placement name is read by exactly one container (so none is left with
nowhere legal to go); and that a container reading none rejects all.

`test_lib/bonsai_gtk_test.mli`'s "what is validated here" paragraph is rewritten: two
bullets for the two tables, the note that a misplaced placement attr is *unobservable* so
the handle was the only place it could have been caught, and a corrected list of what is
still mount-only (which now also names `~visible_child`, per I1).

## I3 — `max_length` truncation: the divergence and the per-frame write (`3ea4594`)

Ruled "(a) AND the honest doc". Both done.

**(a) The code.** `w_entry.ml` gains `capped ~max_length text`, and `create` and `reassert`
both compare and write *that* rather than the node's raw text. GTK's `GtkEntryBuffer`
truncates in **characters**, so `capped` counts characters (a byte starts one unless its
top two bits are `10`), not bytes.

**(b) The doc.** `Node.entry`'s `max_length` paragraph loses the `Attr.on_changed` claim
entirely and says: the truncation is silent because the write happens inside the patch
guard, which drops every signal GTK emits there; the node keeps the untruncated value, so
model and screen disagree until a later render or a user edit; the library does not
rewrite the text every frame, so this costs correctness rather than performance; and if
the model must see the truncated value it should clamp where it owns the text. It is
labelled what it is — an inconsistency in the application that the library tolerates.

**Tests**, in `test/live/live_controls.ml`, and both were checked to fail without the fix:

```
two idle frames over an over-long text wrote: 0 (text still abc)
an idle frame over a multi-byte text wrote: 0
(GtkEntry (text "h\195\169l") (max-length 3) …)
```

The counter is `W.Editable.on_changed` on the widget — GTK emits it for the library's own
writes, which is why the patch guard exists, so it is exactly a "did the library write"
probe. The frames are `Patcher.reassert_only` inside the patch guard: the idle-tick path,
i.e. the one Task 2 exists for. With `capped` neutered to the identity the same two lines
read **`wrote: 4`** and **`wrote: 2`** (two `changed` per write — the delete and the
insert), which is the review's "a write on every frame" measured.

The multi-byte case pins the character/byte distinction from the other side: with `capped`
changed to `String.prefix text max_length` the golden becomes `(text "h\195\169")` — two
characters where GTK would have allowed three, so the entry quietly holds less than the
user was permitted to type. Invisible in ASCII, which is why the case exists. (My first
comment there said a byte-wise cap would also write every frame; it does not — it settles
on the wrong string. The comment now says what actually happens.)

## Minors

**M1 — the `visible_child` raise pinned at patch as well as at mount.** Taken.
`live_containers.ml` gains a stack mounted with a correct `~visible_child` and then patched
to a typo'd one: `visible_child typo introduced by a patch: retyped/0: Node.stack
~visible_child:"libary" names no page (a page's name is its ~key; this stack has library,
practice)`.

**M2 — the add-and-select case says it is load-bearing.** Taken. Its comment now ends
*"Do not simplify this case away … It is the only test that distinguishes 'not yet' from
'never'"*, and says what a regression would look like (the case would stop selecting the
wrong page and start killing the driver).

**M3 — a failed pass leaves no stack claims.** Taken. Two prints beside the existing fixup
counts: `stack claims left behind: 1` / `stack claims after abandon_fixups: 0`. Worth
noting the `1` is real coverage — the `halfbuilt` pass mounts a stack and then raises on a
nested window, so there genuinely is a claim to strand.

**M4 — `live_driver.ml`'s comment claimed a pin this task removed.** Taken, and the
reviewer is right on the mechanism. The parenthetical now says the stack half *used to be*
pinned, that stack names became claims applied at the end of `mount`/`patch`, that
`reassert_only` applies none, and that a claim enqueued from the reassert walk would
therefore raise from the next real patch — one frame late, or never for a constant app.
Labelled "unpinned rather than broken", which is what it is: the walk still enqueues
nothing.

**M5 — the empty-stack carve-out is public contract.** Folded into I1's `node.mli` rewrite,
as the finding said.

**M6 — `measure_overlay` on an overlay's main child.** Taken as the backlog line the
reviewer asked for, in `docs/m1-backlog.md` under "Tests worth adding", with the trigger
for revisiting it (a slot container reading two different placement attrs on two different
slots) and attributed to this review.

## Not changed, and why

**The two residuals under Deviation 2, both explicitly non-blocking.**

- *`apply_stack_claims` can mutate `ctx.stacks` partially before raising.* Left. It matches
  the existing contract exactly: `Driver.frame` marks the scheduler broken and every later
  `frame` is a no-op, so no production pass ever observes the half-applied table. The
  affected reader is a hand-driven test that continues past a rejection, and every such
  test in `live_containers.ml` already calls `abandon_fixups` before doing anything that
  would notice. Making it atomic means building the whole next table before installing it,
  which is a real change to a data structure three other things read, for a case that
  cannot arise outside a test that is already cleaning up.
- *The `Insert`-frees-a-name-via-`Remove` false positive the deferral incidentally fixed.*
  Left unpinned, as the reviewer suggested ("nothing pins that, and nothing needs to
  today"). It is a consequence of the ordering that `apply_stack_claims`'s comment already
  states; a test would pin the symptom rather than the rule.

**The `Overlay` slot granularity** stays as it was — M6's backlog line, not a fix. Nothing
in M2 has a container reading two placement attrs on two different slots, which is the
trigger the comment names.

## Carries updated for later tasks

- **Tasks 6–8** extend `Bonsai_gtk_vtree.Placement`, not `src/patcher.ml`, and extending
  `reader` is compulsory (exhaustive, no wildcard) while extending `read_by` is not. Both
  are now covered headlessly *and* live from the same table, so a new row is validated in
  both suites for free — but `test/test_placement.ml`'s "read by exactly one container"
  golden will need its containers list extended when `List_box` and `Notebook` arrive.
- **Task 12 (`Expert.embed`)** — unchanged from the first report: it must decide the
  embedded root's `parent_kind` (`None` is almost certainly right) and must call
  `apply_stack_claims`, which using the public `mount`/`patch` gets for free.
- **New:** `reassert_only` applies no stack claims and enqueues none, which is correct
  today because the walk never calls `note_interest`. If a later task gives the walk any
  reason to register a name, it must call `apply_stack_claims` too or the claim raises a
  frame late. `live_driver.ml`'s comment (M4) is where that is written down.
