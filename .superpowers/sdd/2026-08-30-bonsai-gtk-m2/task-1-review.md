# Task 1 review — Seal the attr surface, and the vtree event table

Reviewer pass over `git diff a19c1db..09ee6f7` (29 files, +787/−133) with
`task-1-brief.md`, the plan's Pre-flight corrections and Global Constraints, and
`task-1-report.md` in hand.

**Verification I ran myself** (checkout was clean before and after; `git status` shows only
the pre-existing untracked `.beads/issues.jsonl`):

- `nix develop -c dune build @test/runtest` → exit 0, no output.
- `BONSAI_GTK_LIVE_TESTS=1 nix develop -c xvfb-run -a dune build @test/live/runtest` → exit 0.
- `nix develop -c ./scripts/ci.sh` → `all green`.
- Compiled a **downstream probe** against the built `bonsai_gtk_vtree` cmis to establish
  exactly what the seal does and does not stop (see Important 1).
- Compiled three miniature `.mli` spellings to check the deviation-1 premise and its
  alternatives (see Important 1 and Deviation 1).

I could **not** re-run the report's deliberate table corruption: editing tracked files is
blocked for this reviewer. I verified the guard by inspection instead, and by an argument
that makes it non-vacuous — see "Proof the guard bites" below.

---

## Summary

The commit does what the task asked, and it does the hard parts well. `Events.for_kind` is
a single wildcard-free match over `Kind.t`; `Signals.require_specs` and
`Bonsai_gtk_test.Result_spec.view` are now the same predicate over the same data;
`test/live/live_events.ml` compares the table against `(Registry.for_kind k).signals` for
all 29 kinds and is provably non-vacuous. The headless rejection is **byte-identical** to
the runtime's — `test/handle/test_handle.ml:446` expects
`(Invalid_argument "root/0: Label does not emit On_toggled")` and
`test/live/expected_controls.txt:91` records `rejected: root/0: Label does not emit On_toggled`
from the real patcher. I checked the two path spellings independently:
`Children.iteri` (`vtree/children.ml:25-33`) and the patcher's `child_path` /
`mount_slots` (`src/patcher.ml:81`, `src/patcher.ml:265`) produce the same strings for
`Single`, `List` and `Slots`, and both walk parent-before-child, left-to-right, so "the
first offending node" is the same node on both sides. Both directions are tested
(rejection at `test_handle.ml:432-446`, acceptance two levels deep at `:448-476`).
`Attr.Name.all` lands with a golden that pins all 32 names across `is_event` (10/22), plus
a cross-check that no table entry names a non-event. No existing expected file churned,
no ocgtk leaked into `vtree` or `test_lib`, no `Obj`, no conversion, no allocation, and
nothing out of scope crept in.

Three things need answering. The seal, as landed, is a documented promise and not a
compiler-enforced one — and there **is** a zero-cost spelling that enforces it, contrary to
the report's deviation note; I verified both halves of that empirically. Separately, the
move from "check the impl's own spec list" to "check the shared table" gives up an
invariant that used to hold unconditionally at mount, and now rests on a test that only
runs under `BONSAI_GTK_LIVE_TESTS=1`. And the tripwire that catches a kind nobody added to
the agreement test is a hand-maintained integer, in the milestone whose next six tasks
each add a kind.

---

## Per-deviation judgement

**Deviation 1 — "the seal is spelled the other way round; the plan's spelling does not
typecheck."**
*Premise: sound, verified. Conclusion: unsound.*

The plan's spelling really does fail, with exactly the error quoted. I reproduced it:

```
type t
module Private : sig type nonrec t = t = A | B of int end
```
```
Error: This variant or record definition does not match that of type t
       The original is abstract, but this is a variant.
```

So deviating was right. But the report goes on to claim "there is no arrangement of
`nonrec`, `private`, or a second compilation unit that changes this — a signature cannot be
abstract to one client and concrete to another." That is false, and the counter-example is
one word away from what landed. See Important 1; grading the deviation as unsound is about
that sentence and the choice it justified, not about abandoning the plan's literal text.

**Deviation 2 — annotation form everywhere, no `open Attr.Private`.** *Sound.*
I confirmed the stated collision: `src/attr_apply.ml:128-161`'s `unset` matches
`Attr.Name.t` with unqualified `Test_id`, `Measure_overlay`, `Grid_cell`, `Page_title` and
every `On_*`, all of which are also `Attr.Private.t` constructors. An `open` at the top of
that file would put both sets in scope in one function. The annotation form is also what
the plan already preferred for the `Signals.spec` bodies, so this is consistent rather than
novel.

**Deviation 3 — all 29 kinds in `test/test_events.ml`, not the plan's sample of 10.**
*Sound, and strictly better.* The plan's own comment on that snippet said "one row per
kind"; ten rows would not have delivered it. I counted `Kind.t`'s constructors
(`vtree/kind.mli:261-290`): 29, matching both `all_kinds` lists and `kinds checked: 29`.

**Deviation 4 — no `Level_bar` arm.** *Sound.* `Kind.t` has no `Level_bar` constructor;
the plan's sample table was written against M2's end state. Task 10 adds it, and
`Events.for_kind`'s missing wildcard makes that a compile error rather than an omission.

**Deviation 5 — two extra tests.** *Sound.* Both close holes a reviewer would otherwise
raise. "the table and `is_event` cover the same names" (`test/test_events.ml:143-166`) is
the more valuable of the two, and its choice to *print* rather than assert the
`event_names_no_kind_emits` half is correct foresight: Task 4's controller attrs are event
names no kind's table will list, and that golden will legitimately grow.

---

## Critical

None.

---

## Important

### Important 1 — the seal is documentation only, and a zero-cost enforced spelling exists

`vtree/attr.mli:121-124` publishes `type t = Private.t`, a transparent alias. The report
and the mli both say plainly that this makes the seal a documented promise rather than a
barrier, which is honest — but it means the task's stated reason for going first ("each M2
attr added before the seal is another line of a downstream exhaustive match that will break
later") is not actually addressed, and the commit message's headline claim — "M2's and M3's
attrs stop being breaking changes for a downstream exhaustive match" — is false as shipped.

I compiled a downstream module against the built `bonsai_gtk_vtree` cmis. With nothing but
`open Bonsai_gtk_vtree`, never naming `Private`, this compiles clean (exit 0, no warning
under the default flag set):

```ocaml
let describe (a : Attr.t) =
  match a with
  | Css_class _ -> "css"
  | Margin_start _ | Margin_end _ | ... (* all 33 constructors *)
  | Many _ -> "many"
;;
let built : Attr.t = Test_id "x"          (* construction, unqualified *)
```

So today a downstream can still match exhaustively **and** construct raw constructors, and
Task 4's `On_key_pressed` will break exactly the code the seal was meant to protect.

**The fix, which needs no conversion function and no allocation.** A private type
abbreviation blocks both directions while leaving the library full access by coercion. I
verified all four halves of this in miniature:

```ocaml
(* attr.mli *)
module Private : sig type t = Css_class of string | ... | Many of t list end
type t = private Private.t
```

- client match, unqualified → `Error: Unbound constructor A`
- client match, qualified as `Private.A` → `Error: This pattern matches values of type
  Priv_abbrev.Private.t but a pattern was expected which matches values of type
  Priv_abbrev.t`
- client construction `let g : t = Private.A` → same rejection
- library access `match (x :> Private.t) with A -> … | B n -> …` → compiles, including
  through `option`: `match (xs :> Private.t option) with Some (Private.B n) -> …`

`attr.ml` is unchanged (`type t = Private.t` there; `private` is a sealing-only annotation
in the `.mli`). The cost is confined to the 23 internal sites the earlier grep found, and
every one of them is a **pattern** position — I checked; nothing outside `attr.ml`
constructs a `Private.t` and needs it back as an `Attr.t`, so no injection function is
needed:

- `src/attr_apply.ml:80` and the 13 `src/widgets/w_*.ml` lambdas
  (`(fun w (attr : Attr.Private.t) -> …)`) become
  `(fun w attr -> match (attr :> Attr.Private.t) with …)`.
- `vtree/attrs.ml:28`'s `add` gains one coercion on its scrutinee.
- `test_lib/bonsai_gtk_test.ml`'s five `(Attrs.find … : Attr.Private.t option)` become
  `(Attrs.find … :> Attr.Private.t option)`.

I verified the miniature, not the real `attr.mli` — the read-only constraint stopped me
from trying it in place, so this needs a build to confirm nothing in `examples/` builds an
attr from a raw constructor. If it turns out to cost more than the above, arguing it down
is reasonable; what is not reasonable is leaving the commit message claiming a property the
code does not have. **At minimum, fix the commit message** (and `docs/` if it repeats the
claim) to say what `attr.mli:76-81` already says honestly.

### Important 2 — the mount-time "every event attr has a slot" invariant is now live-gated

Before this commit, `Signals.require_specs` consulted `impl.signals` — the same list
`connect_all` builds slots from — so "this attr will reach a handler" was guaranteed
unconditionally at every mount. After it (`src/signals.ml:91-105`), the verdict comes from
`Events`, and the only thing tying `Events` to the impls is
`test/live/live_events.ml`, which is behind `(enabled_if (= %{env:BONSAI_GTK_LIVE_TESTS=0} 1))`
(`test/live/dune:85-95`).

Concrete failure: Task 6 adds `On_row_activated` to `Events.for_kind (List_box _)` but
`w_list_box.ml`'s `signals` omits the spec. `require_specs` accepts the attr,
`connect_all` creates no slot for it, `update_slots` (`src/signals.ml:64`) iterates the
*slots* and so never notices the orphan attr, and the handler silently never fires — which
is precisely the bug the function's own comment (`src/signals.ml:82-85`) says it exists to
prevent. In this repo `scripts/ci.sh` runs the live suite, so CI catches it; a contributor
running plain `dune test`, or `opam install bonsai_gtk --with-test`, does not.

Cheap belt-and-braces that restores the old guarantee without undoing the shared-table
design: after `connect_all` in `Patcher.mount` (`src/patcher.ml:210-212`), assert that
every event name in `node.attrs` has a slot, and raise naming the kind and the attr if not.
It is a handful of `List.Assoc.mem` calls on lists of length ≤ 3, runs unconditionally, and
turns a silent no-op into a loud `Invalid_argument` even if the table and the impl drift.

### Important 3 — `kinds checked: 29` is the only net for a new kind, and it is a hand-typed integer

`Events.for_kind`'s missing wildcard forces a *decision* for every new kind (good), but
nothing forces that decision to be *checked against the impl*. Both `all_kinds` lists —
`test/test_events.ml:13-41` and `test/live/live_events.ml:26-56` — are hand-maintained, and
the tripwire is the literal `29` in `test/live/expected_events.txt`. A Task 6–11
implementer who adds `Kind.List_box`, adds the `for_kind` arm, and does not touch either
list gets a green build with the new kind's table entry never compared to
`w_list_box.ml`'s `signals` — straight back into Important 2's failure mode. The report
names this ("bump it deliberately") and the plan sanctioned it, but a compiler-derived
count is available for free: `ppx_jane` bundles `ppx_variants_conv`, so adding `variants`
to `Kind.t`'s deriving list gives `Kind.Variants.descriptions`, and

```ocaml
assert (List.length all_kinds = List.length Kind.Variants.descriptions)
```

in both files turns "someone remembered to bump a number" into "the compiler counted".
Two lines and one deriving attribute. If `variants` on `Kind.t` is unwelcome, say so and
the `29` stands — but then it is worth a sentence in `vtree/events.mli`'s doc, which
currently asserts flatly that `live_events.ml` "compares them for every kind".

---

## Minor

1. **`impl_name` vs `Kind.name` parity is by convention, untested.**
   `Signals.require_specs` reports `~impl_name` (`src/patcher.ml:209` passes `impl.name`);
   the harness reports `Kind.name node.kind` (`test_lib/bonsai_gtk_test.ml:39`). They agree
   today — I checked all 28 `{ name = "…" }` literals in `src/widgets/` against
   `vtree/kind.ml:299-329`, and `src/native_gtk.ml:38` deliberately spells
   `"Native:" ^ impl.name` with a comment saying why. Nothing tests it, so the mli's claim
   of "the message … the patcher would have produced" can quietly become false. Two fixes,
   either fine: drop the `~impl_name` parameter and use `Kind.name kind` inside
   `require_specs` (parity by construction, and it removes an argument), or assert
   `String.equal (Kind.name k) (Registry.for_kind k).name` in `live_events.ml`, which
   already iterates every kind.

2. **`bonsai_gtk_test.mli` overclaims by one sentence.** "so 'the handle accepted it' really
   does mean 'the runtime will connect it'" reads as a global statement; the next paragraph
   correctly says structural misuse is still unchecked, which contradicts it on a literal
   reading. Narrow it to the attr ("…means the runtime will connect *that attr*"). Worth
   adding, given Important 2, that the table/impl agreement is checked by a live-gated test.

3. **`all_kinds` is duplicated verbatim across two files** (`test/test_events.ml:13-41` and
   `test/live/live_events.ml:26-56`, identical but for the `Native` row). Neither is checked
   against the other; the `kinds checked` count only guards the live copy. Not worth a
   shared library on its own, but if Important 3's count assertion lands, put it in both.

4. **No test that a `Native` node with an event attr is rejected.** `Native _ -> []` is
   called out as load-bearing (`vtree/events.ml:14-16`, spec §6.6), and the table row is
   pinned by `test_events.ml`'s golden `(Native:thing ())`, but neither the handle test nor
   the live `rejected:` lines exercise it — the four recorded rejections in
   `expected_controls.txt:91-94` are all `Label`. One more `require_does_raise` in
   `test_handle.ml` against a `Node.native` carrying `Attr.on_clicked` would close it.

5. **`Events.unsupported`'s documented ordering is untested.** `vtree/events.mli:22-24`
   promises "the first event attr … in `Attr.Name` order". I traced it and it holds —
   `Attrs.to_list` (`vtree/attrs.ml:50`) is css classes then `Map.data`, keyed by
   `Attr.Name.compare`, which `deriving compare` gives as declaration order, and events are
   declared last — but the existing test passes a single offending attr, so the ordering
   claim would survive the function returning any of them. A two-event-attr case pins it.

6. **`Attr.Private` exports no `sexp_of_t`.** `attr.ml`'s `module Private` derives it and
   `include Private` re-exports it as `Attr.sexp_of_t`, but the mli's `module Private : sig
   … end` omits it, so `Attr.Private.sexp_of_t` does not exist. Harmless; noted only because
   the module is documented as "for the library's own runtime", which might want it.

7. **Validation lives in `Result_spec.view`**, so a test that calls `create` and
   `do_actions` without ever calling `show`/`recompute_view` is unvalidated. The mli says
   "on the first `Handle.show`/`Handle.recompute_view`", which is accurate — recording this
   only so the next reader does not mistake it for a gap. Putting it in `view` rather than
   in `create` is the right call: it also covers anyone using the exported `result_spec`
   (`bonsai_gtk_test.mli:50`), and it re-checks every frame rather than only the first.

---

## Proof the guard bites

I could not re-run the report's deliberate `Paned` corruption (read-only). What I did
establish:

- The rule is wired: `test/live/dune:85-95` runs `live_events.exe` into `output_events.txt`
  and `(diff expected_events.txt output_events.txt)`, in the same shape as the five
  existing rules, and it is in the `runtest` alias.
- The comparison is **not vacuous**. `expected_events.txt` says `agreed`, and
  `Events.for_kind` returns non-empty lists for 11 kinds. For the run to print `agreed`,
  `(Registry.for_kind k).signals |> List.map ~f:Signals.spec_attr` must have produced those
  same non-empty lists — so both sides carry real data and a disagreement on any of them
  would print a `MISMATCH` line the diff does not expect. `kinds checked: 29` in the real
  output confirms the executable ran over the full list rather than short-circuiting.
- The failure message names both directions (`~impl_declares` / `~table_says`) and the
  kind, which is what the task asked for.

The report's recorded red diff is consistent with all of the above, and the file's sha256
is unchanged from the committed state, so the corruption was in fact reverted.

---

## Verdict

**Needs fixes.**

Important 1 (fix the seal with the private abbreviation, or argue it down and correct the
commit message, which currently claims a property the code does not have), Important 2 (a
runtime assertion that restores the "every event attr has a slot" guarantee without the
live gate) and Important 3 (make the kind count compiler-derived) each need a fix or a
written argument. The Minor items are cheap; 1, 2 and 4 are the ones I would take. Nothing
in the diff is out of scope, and no finding here belongs on the backlog rather than in this
task.

---

# Re-review — fix commit `1daa1b5`

Scoped to `git diff 09ee6f7..1daa1b5` (32 files, +251/−83) against the findings above.
Checkout clean before and after; only the pre-existing untracked `.beads/issues.jsonl`.

**Verification I ran myself**, not relying on the report's transcripts:

- `nix develop -c dune build @test/runtest` → exit 0.
- `BONSAI_GTK_LIVE_TESTS=1 nix develop -c xvfb-run -a dune build @test/live/runtest` → exit 0.
- `nix develop -c ./scripts/ci.sh` → `all green`.
- Five scratch modules of my own, compiled against the **rebuilt** cmis with
  `ocamlfind ocamlc -package core,virtual_dom.ui_effect -I _build/default/vtree/.bonsai_gtk_vtree.objs/byte`.
- One more probe to measure what `[@@deriving variants]` added to `Kind`'s published
  surface.

## Important 1 — resolved

`vtree/attr.mli:132` is now `type t = private Private.t`. I re-ran my own probes; all four
rejections are real:

| probe | result |
|---|---|
| `match (a : Attr.t) with Css_class _ -> …` (never naming `Private`) | `Error: Unbound constructor "Css_class"` |
| `let built : Attr.t = Test_id "x"` | `Error: Unbound constructor "Test_id"` |
| `let built : Attr.t = Attr.Private.Test_id "x"` | `This expression has type Attr.Private.t but … was expected of type Attr.t` |
| `match (a : Attr.t) with Attr.Private.Test_id _ -> …` | `This pattern matches values of type Attr.Private.t but a pattern was expected which matches values of type Attr.t` |
| `match (a :> Attr.Private.t) with …` + `Attr.test_id "x"` + `Attr.flatten` | compiles, exit 0 |

The first of those is the *same program* I compiled clean against `09ee6f7`. It no longer
compiles. Construction is impossible outside `attr.ml`; matching requires the coercion,
which is deliberate and named. `attr.mli:74-89`, `bonsai_gtk_test.mli` and `README.md:223-232`
now describe what the code enforces, with the earlier "honest caveat" paragraph removed
rather than left standing next to a contradicting implementation.

**`Attr.flatten` is a sound answer to the injection problem I missed.** My finding claimed
"nothing outside `attr.ml` constructs a `Private.t` and needs it back as an `Attr.t`";
`Attrs.of_list`'s `Many` arm is the counter-example, since destructuring yields
`Attr.Private.t list` and the coercion runs one way. Of the three ways out the report
lists, exposing `flatten : t list -> t list` is the right one: it hands back no
construction power (both sides are the sealed `t`), it leaves `Attrs.t` storing `Attr.t`
so `Attrs.find` and `Attrs.op` keep their types, and an identity `of_private` would have
returned exactly the power `private` just removed. I read the implementation
(`vtree/attr.ml:140-149`): `go` folds `Many` payloads left to right into a reversed
accumulator with a single `List.rev` at the end, so it is depth-first left-to-right and
`of_list`'s last-write-wins still means what it says. `test/test_attrs.ml:14` exercises a
one-level `Attr.many` in an `of_list` golden and that golden is unchanged, which is real
evidence rather than an assertion.

**The three sites the first review's list missed are themselves evidence.**
`w_grid.ml:13`, `w_overlay.ml:11` and `w_stack.ml:37` match an unannotated `Attrs.find`
result and used to typecheck by disambiguation *through the alias* — precisely the
accidental matching the seal exists to stop. The compiler found all three. That is the
clearest demonstration that the old spelling was not enforcing anything.

## Important 2 — resolved, with one residual gap (now Minor 8)

`Signals.require_slots` (`src/signals.ml:112-127`) is called from `Patcher.mount:214`,
after `connect_all` and before `update_slots`, with no guard — unconditional, as asked. It
is `List.Assoc.mem` over lists of length ≤ 3.

**The test really trips it.** `test/live/live_signals.ml:57` builds slots from an *empty*
spec list — structurally identical to what an impl that forgot a spec produces — and
passes attrs carrying `On_clicked`; `expected_signals.txt` pins the raised message. The
positive control uses the real slots and runs *after* `clear_slots`, which additionally
pins that clearing empties the cells without dropping the names, so teardown cannot make
the assertion fire spuriously. Both directions, both in the golden. Testing at the
`Signals` level rather than through `mount` is the right call and the report's reason is
correct: `live_events.ml` proves no real impl disagrees with the table, so the drift cannot
be produced without editing one.

Residual, carried as **Minor 8** below: `require_slots` is on the mount path only, while
`require_specs` is on both. The mli says "every mount" and the patcher comment says the
same, so nothing overclaims — but the patch path is where `require_specs` needed its
second call for a reason, and the same reason applies here.

## Important 3 — resolved

`Kind.t` gains `[@@deriving variants]` and both `all_kinds` lists assert
`List.length all_kinds = List.length Kind.Variants.descriptions`
(`test/test_events.ml:47`, `test/live/live_events.ml:61`). This is non-vacuous by
construction, not just by the report's deletion experiment: the right-hand side is
ppx-derived from the type definition, so a constructor added to `Kind.t` moves it whether
or not anyone touches the test. Both suites pass, so `descriptions` has 29 entries,
matching the 29 constructors I counted in `kind.mli:262-290`. The literal `29` stays in
`expected_events.txt` but is demoted to a thing a reader wants to see, and both the
`printf` comment and `vtree/events.mli:14-18` now say so rather than calling it the
tripwire. This also takes Minor 3 — the two lists are still duplicated, but each is now
checked against `Kind.t` instead of against nothing.

## Minors 1, 2, 4, 5, 6, 7

All correct.

- **1.** `require_specs` drops `~impl_name` and names the widget with `Kind.name kind`
  (`src/signals.ml:104`), so parity with the harness is by construction. No golden churned,
  which is the evidence the two spellings already agreed everywhere exercised.
- **2.** Narrowed to "that attr", and the sentence now names both checks and says which one
  is behind `BONSAI_GTK_LIVE_TESTS=1`. No longer readable as a global claim.
- **4.** `test_handle.ml:479-496` pins
  `(Invalid_argument "root/0: Native:thing does not emit On_clicked")`. That golden is also
  incidental proof for Minor 1: `Kind.name` reproduces `Native_gtk`'s `"Native:" ^ impl.name`
  exactly.
- **5.** The new case (`test/test_events.ml:106-118`) passes `on_toggled` first and gets
  `(On_clicked)` back, then gets `(On_toggled)` from a `Button` — declaration order, and it
  would have failed under argument order. Pins the claim the old single-attr test could not.
- **6.** `Attr.Private.sexp_of_t` exported. The report's reason for it mattering more after
  `private` is right: a coerced value can no longer be handed to `Attr.sexp_of_t`.
- **7.** No action, as intended.

## No coercion site regressed

I read all 20 changed sites. `Attr_apply.set` takes `Attr.t` and coerces at the scrutinee,
and its match is still wildcard-free through `| Many _ -> ()` — the coercion did not let an
exhaustive match go slack, which was the thing worth checking. The `spec.fire` lambdas drop
their parameter annotation and coerce instead; the parameter type still comes from the
`Signals.spec` record field, so nothing was loosened. `Attrs.of_list`'s `| _ ->` arm is the
same catch-all the pre-fix code had as `| attr ->`, with `Many` now an explicit dead arm
carrying a comment. Three suites plus `ci.sh` pass.

## New Minor findings

**Minor 8 — `require_slots` is not called on the patch path.** `Patcher.patch:390` calls
`require_specs` inside `if not (List.is_empty attr_ops)` but not `require_slots`. Scenario:
`Events.for_kind (Button _)` lists `On_clicked`, `w_button.ml` has drifted and declares no
spec, and the app adds `Attr.on_clicked` conditionally on frame 2. Mount saw no event attr,
so `require_slots` passed; the patch's `require_specs` consults the table and passes;
`update_slots` iterates the slots and never sees the orphan; the handler silently never
fires — the failure Important 2 was raised about, reached by the exact route that made
`require_specs` need a patch-path call. One line beside it:
`Signals.require_slots ~node_path:path ~impl_name:live.impl.name live.slots node.attrs`.
Minor because it needs a pre-existing drift that `live_events.ml` catches in CI, and because
nothing in the docs claims more than "every mount".

**Minor 9 — `[@@deriving variants]` in `kind.mli` widens the surface by about thirty names.**
I compiled a probe: `Kind.label : label_props -> t`, `Kind.Variants.descriptions` and
`Kind.Variants.to_rank` are all public, so the mli now publishes a lowercase constructor
function per kind plus the whole `Variants` module (`fold`, `iter`, `map`, `make_matcher`,
`to_rank`, `to_name`, …). Nothing unsafe — `Kind.t` was already a concrete public variant —
but it is a ~30-name widening in the commit whose theme is narrowing, on the type every
widget task extends, and only one derived value is actually wanted. Derive in `kind.ml`
only and expose the slice in the mli: `module Variants : sig val descriptions : (string * int) list end`,
or plainly `val constructor_count : int`.

**Minor 10 — nested `Attr.many` has no golden.** `test/test_attrs.ml:14` covers one level.
`flatten` is now a named function whose documented depth-first left-to-right order is what
makes `of_list`'s last-write-wins meaningful, and the recursion is correct by inspection,
but a `many` inside a `many` is unpinned. Pre-existing (the old recursion had the same gap);
one extra attr in that existing test would close it.

## Re-review verdict

**Approved.**

All three Important findings are genuinely fixed, and I verified each independently rather
than from the report — the seal by compiling my own probes against the rebuilt cmis, the
mount assertion by reading the call site and the golden that pins both directions, the
derived count by confirming it compares against a ppx-derived list. The `Attr.flatten`
addition the fix needed is the least-powerful of the available options and is correct. The
three new Minors (8, 9, 10) are small, none blocks the task, and Minor 8 is the one I would
take before Task 4 lands the controller attrs.
