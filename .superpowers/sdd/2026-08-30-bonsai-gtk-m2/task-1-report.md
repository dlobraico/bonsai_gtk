# Task 1 report — Seal the attr surface, and the vtree event table

Branch `m2`. Base `a19c1db`. One commit: **`09ee6f7`** — *Seal Attr.t behind
Attr.Private; one event table for the runtime and the harness* (29 files, +787/−133).

`nix develop -c ./scripts/ci.sh` ends **`all green`**.

---

## What each step did

**Step 1 — the failing tests.** Three new test artefacts, written before any
implementation:

- `test/test_events.ml` — five `ppx_expect` tests over `vtree` alone.
  - *every kind's event attrs*: `all_kinds`, one value per `Kind.t` constructor (29 rows,
    including `Native`, built from `Native.Unit` since no impl is needed headlessly),
    printed as `(kind-name (names…))`. This is the golden the table diffs against.
  - *unsupported finds the offending name, and only event names*: `Attr.css_class` +
    `Attr.test_id` + `Attr.on_toggled` against a `Label` → `(On_toggled)`; against a
    `Switch` → `()`.
  - *is_supported over a kind that emits nothing and one that emits something*: pins that
    a non-event name (`Test_id`) is supported on every kind while `On_toggled` /
    `On_clicked` follow the table.
  - *is_event over every name*: partitions `Attr.Name.all` — 10 events, 22 plain.
  - *the table and `is_event` cover the same names*: every name in the table is one
    `is_event` agrees is an event (`(not_events ())`), and every event name is emitted by
    some kind (`(event_names_no_kind_emits ())`). The second half is printed rather than
    asserted because M2's later tasks will legitimately add an event name before the
    widget that emits it.
- `test/handle/test_handle.ml` — four new tests: the two new actions reaching real
  `Bonsai.state` handlers (both models are live state, so a golden here would change if
  the handler were not reached); the two new actions against nodes carrying no handler;
  the `Events`-backed rejection; and the positive control — a supported event attr two
  levels deep is *not* rejected.
- `test/live/live_events.ml` + `expected_events.txt` — the agreement test between
  `Events.for_kind` and `(Registry.for_kind kind).signals |> List.map ~f:Signals.spec_attr`,
  for every kind, sorted before comparison. Expected file is exactly
  `kinds checked: 29` / `agreed`.

**Step 2 — verified failure.** `dune build @test/runtest` →
`Error: Unbound module "Events"` and
`There is no constructor "Search_changed" within type "Bonsai_gtk_test.Action.t"`.

**Step 3 — `vtree/attr.ml(i)`.** `Name.t` gains `enumerate` (so `Name.all`) and
`Name.to_string = Sexp.to_string (sexp_of_t _)`. `Name.t` keeps its concrete surface, and
its new doc paragraph says why (only reachable through `Attrs.op`; `Attr_apply.unset`'s
exhaustive match is what makes restore-to-default impossible to forget; sealing it would
trade a compile error for a silent omission). The variant moved into `Attr.Private` —
see the deviation below for the spelling.

**Step 4 — every matcher gets one word.** `(attr : Attr.t)` → `(attr : Attr.Private.t)` in
`src/attr_apply.ml` and 12 `src/widgets/w_*.ml`; the same annotation on the five
`Attrs.find` scrutinees in `test_lib/bonsai_gtk_test.ml`; one qualified constructor
(`Attr.Private.Many`) in `vtree/attrs.ml`. No `open Attr.Private` anywhere — see the
deviation below.

**Step 5 — `vtree/events.ml(i)`.** `for_kind` is one `match` over `Kind.t` with **no
wildcard arm**; `is_supported` is `not (is_event name) || List.mem (for_kind kind) name`;
`unsupported` is `List.find_map` over `Attrs.to_list`, which yields the keyed attrs in
`Attr.Name` order, so "the first one" is stable. `Native _ -> []` is present and
commented as load-bearing. `Events` is re-exported from `vtree/bonsai_gtk_vtree.ml`.

**Step 6 — `src/signals.ml(i)`.** `require_specs` now takes a `Kind.t` instead of a
`spec list` and its body is `match Events.unsupported kind attrs with …`. The message
shape is unchanged (`"%s: %s does not emit %s"` with `Attr.Name.to_string`, which is the
same text the old `%{sexp:Attr.Name.t}` produced) — **no existing expected file churned**.
`spec_attr : spec -> Attr.Name.t` added for Task 4. `Patcher` passes `node.kind` at both
call sites (`mount` and `patch`).

**Step 7 — `test_lib/bonsai_gtk_test.ml(i)`.** `Action.t` gains `Search_changed of
string * string` and `Set_expanded of string * bool`, both documented as the plan
specifies (neither consults the node's own prop). Validation is
`require_supported_events ~path:"root"`, called from `Result_spec.view` — so it runs on
every `show`/`recompute_view`, not only the first, and applies to anyone using the
exported `result_spec` too. It walks with `Children.iteri` and reports with `Kind.name`,
so the message and path are byte-identical to the patcher's:
`(Invalid_argument "root/0: Label does not emit On_toggled")` — compare
`test/live/expected_controls.txt:91`. The "Structural validation happens at mount, not
here" paragraph in the mli is rewritten: event attrs *are* rejected here now, by the same
table; what is still mount-only is the structural half (grid cell, stack page key,
duplicate stack names, duplicate sibling keys, off-root window), and the escape is still a
live test or running the app.

**Step 8 — `test/live/dune`.** `live_events` appended to `(names …)` and one
`(rule (alias runtest) …)` in the shape of the existing five.

**Step 9 — run, read, promote.** Only the two files I edited produced `.corrected`
output; every other expected file is untouched (verified by grepping the whole
`@test/runtest` output for `^------` — two hits, both mine). `expected_events.txt` says
`agreed` and `kinds checked: 29`, which equals the number of arms reachable in
`Registry.for_kind` (28 concrete kinds + `Native`).

---

## Deviations from the plan, and why

**1. The seal is spelled the other way round. The plan's spelling does not typecheck.**

The plan asks for an abstract `type t` in `attr.mli` plus, at the bottom:

```ocaml
module Private : sig
  type nonrec t = t = | Css_class of string | … end
```

That is a compile error:

```
Error: This variant or record definition does not match that of type "t"
       The original is abstract, but this is a variant.
```

OCaml cannot re-expose the constructors of a type its own signature has just made
abstract, and there is no arrangement of `nonrec`, `private`, or a second compilation unit
that changes this — a signature cannot be abstract to one client and concrete to another.

What landed instead, which is the same type and the same absence of conversion:

```ocaml
(* attr.mli *)
module Private : sig
  type t = | Css_class of string | … | Many of t list
end

type t = Private.t
val sexp_of_t : t -> Sexp.t
```

and in `attr.ml` the variant is declared once inside `Private` and reaches the rest of the
file through `include Private` — so, unlike the plan's version, there is **no duplicated
constructor list at all**, in the `.ml` or the `.mli` beyond the signature's own copy.

The consequence a reviewer should know, and which both files state in their doc comments:
because `t` is an alias rather than an abstract type, OCaml's type-directed disambiguation
still resolves an unqualified `Css_class` against a scrutinee annotated `Attr.t`. So the
seal is a documented promise, not a compiler-enforced barrier — an application *can* still
match on the variant, and if it does it breaks on the next milestone, which is exactly
what the plan's own doc text says ("an application that does is choosing to break on the
next milestone"). What the seal genuinely buys: the constructors are out of `Attr`'s
published surface, so nobody reaches them by accident, and everything internal that does
reach them now names `Private` at the site.

No `Obj`, no conversion, no allocation: `Attr.t` and `Attr.Private.t` are one type.

**2. `open Attr.Private` was not used anywhere; the annotation form was used everywhere.**
The plan preferred the `open` in `src/attr_apply.ml`. That file also matches exhaustively
on `Attr.Name.t` in `unset`, and eight names are spelled identically in both variants
(`Test_id`, `Measure_overlay`, `Grid_cell`, `Page_title`, `On_clicked`, …). An `open`
would put both in scope at once and make those patterns ambiguous. `(attr :
Attr.Private.t)` is one word, has no such interaction, and is what the plan already
preferred for the `Signals.spec` bodies.

**3. `test/test_events.ml` lists every kind, not the ten in the plan's sample.** The
plan's own comment on that snippet says "one row per kind"; ten rows would not deliver
that. Listing all 29 makes the golden a complete statement of the table and costs
nothing.

**4. `Level_bar` is not in `Events.for_kind`.** The plan's sample table names
`Level_bar _ -> []`, but `Kind.t` has no `Level_bar` constructor yet — it arrives in Task
10, which adds the arm. `Stack_switcher`/`Stack_sidebar` were folded into the empty arm as
the plan intends.

**5. Two extra tests beyond the plan's list**, both cheap and both closing a hole a
reviewer would otherwise ask about: `test_events.ml`'s "the table and `is_event` cover the
same names" (a table entry for a name `is_event` calls plain would be dead code that
`unsupported` never looks at), and `test_handle.ml`'s "a supported event attr passes
validation at every depth" (without it, a validation walk that rejected *everything* would
still go green on the negative tests).

**Not a deviation, recorded because the plan flagged it:** `w_password_entry.ml` needed no
change — it has no `Attr.t` match of its own, it reuses `W_entry.changed`/`activate`. The
pre-flight report predicted this. `vtree/attrs.ml` *did* need a change the plan's file
list omits (one qualified `Attr.Private.Many`), because its `add` function matches with no
annotation to disambiguate from.

---

## Proof the guard bites

The plan's review focus asks for it, so it was done before promoting: `| Paned _ -> [
On_position_changed ]` was temporarily changed to `[ On_position_changed; On_clicked ]`
and the live suite re-run. `live_events`'s diff went red with both directions named:

```
------ test/live/expected_events.txt
++++++ test/live/output_events.txt
+|(MISMATCH (kind Paned) (impl_declares (On_position_changed))
+| (table_says (On_clicked On_position_changed)))
 |kinds checked: 29
 |agreed
```

The corruption was reverted immediately and `vtree/events.ml` restored from a byte copy.

---

## Test output tails

`nix develop -c dune build @test/runtest` — clean, no output.

Live suite (`BONSAI_GTK_LIVE_TESTS=1 nix develop -c xvfb-run -a dune build
@test/live/runtest`) — exit 0. Its only stdout is a line the driver test expects:

```
bonsai_gtk: exception in frame, stopping the driver: (Invalid_argument
  "root/0/1: a Node.window may only be the root node, not a child of another node")
```

`_build/default/test/live/output_events.txt`:

```
kinds checked: 29
agreed
```

`nix develop -c ./scripts/ci.sh` — exit 0:

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

## Left for later tasks

- **Task 4** adds the controller-attr arm to `Events.is_supported` (controller attrs are
  legal on every kind and are handled by `Controllers`, not by any impl's `signals`), the
  comment saying why, and the `live_events.ml` assertion that no impl declares a
  controller name in its `signals`. `Signals.spec_attr` is already in place so that
  `live_events.ml` does not have to change when `spec` becomes a variant.
- **Task 10** adds the `Level_bar` arm.
- Every widget task adds its kind to **three** lists that must move together:
  `Events.for_kind` (compiler-enforced), `test/test_events.ml`'s `all_kinds`, and
  `test/live/live_events.ml`'s `all_kinds` — the last two are not compiler-enforced, and
  `kinds checked: N` in `expected_events.txt` is the tripwire. Bump it deliberately.
- The structural half of mount-time validation is still invisible to `Bonsai_gtk_test`
  (grid cell, stack page key, duplicate stack names, duplicate sibling keys, off-root
  window). The rewritten `bonsai_gtk_test.mli` paragraph says so explicitly rather than
  overclaiming in the other direction.

---

# Fix round 1

Commit **`1daa1b5`** — *Task 1 fixes: make the attr seal compiler-enforced, and back it
with a mount assertion* (32 files, +251/−83), on top of `09ee6f7`. History not rewritten.

`nix develop -c ./scripts/ci.sh` ends **`all green`**.

## Important 1 — the seal is now compiler-enforced

The reviewer is right and my deviation note was wrong. The sentence "there is no
arrangement of `nonrec`, `private`, or a second compilation unit that changes this" was
the error: a **private type abbreviation** does exactly what was wanted, and it is one
word from what shipped. `vtree/attr.mli` now reads

```ocaml
module Private : sig type t = Css_class of string | … | Many of t list  val sexp_of_t : … end
type t = private Private.t
```

`attr.ml` is unchanged in structure (`include Private`, so `t` is the plain variant in
there); `private` is a sealing-only annotation in the signature.

**Proof.** Four scratch modules (in the session scratchpad, not committed) compiled
against the rebuilt `bonsai_gtk_vtree` cmis with
`ocamlfind ocamlc -package core,virtual_dom.ui_effect -I _build/default/vtree/.bonsai_gtk_vtree.objs/byte`.

*Unqualified match, never naming `Private`* — this is the exhaustive match the seal exists
to stop, and it compiled clean before the fix:

```
File "probe_match.ml", line 8, characters 4-13:
8 |   | Css_class _ -> "css"
        ^^^^^^^^^
Error: Unbound constructor "Css_class"
```

*Construction from a raw constructor*, which also compiled clean before the fix:

```
File "probe_construct.ml", line 4, characters 21-28:
4 | let built : Attr.t = Test_id "x"
                         ^^^^^^^
Error: Unbound constructor "Test_id"
```

Two more, run for completeness. Qualifying the constructor does not get round it:

```
File "probe_qualified.ml", line 6, characters 4-26:
6 |   | Attr.Private.Test_id _ -> "test_id"
        ^^^^^^^^^^^^^^^^^^^^^^
Error: This pattern matches values of type "Bonsai_gtk_vtree.Attr.Private.t"
       but a pattern was expected which matches values of type
         "Bonsai_gtk_vtree.Attr.t"
```

```
File "probe_construct_qualified.ml", line 4, characters 21-45:
4 | let built : Attr.t = Attr.Private.Test_id "x"
                         ^^^^^^^^^^^^^^^^^^^^^^^^
Error: This expression has type "Bonsai_gtk_vtree.Attr.Private.t"
       but an expression was expected of type "Bonsai_gtk_vtree.Attr.t"
```

And the supported gesture — `match (a :> Attr.Private.t) with …` plus
`Attr.test_id "x"` — compiles clean (exit 0, no output). That coercion is available to
anyone, deliberately: it is what the library does in 23 places, and an application that
writes it has named `Private` at the site rather than stumbling in. **Construction is
impossible outside `attr.ml`; matching is impossible without the coercion.** Both mlis and
the README now say exactly that and nothing more.

**Sites changed.** The reviewer's list plus three the earlier grep missed, all found by
`dune build @all`: `src/widgets/w_grid.ml:13` (`Some (Grid_cell c)`),
`w_overlay.ml:11` (`Some (Measure_overlay b)`) and `w_stack.ml:37` (`Some (Page_title t)`)
match an `Attrs.find` result with no annotation, and used to work by disambiguation
through the alias. Each took the same `(… :> Attr.Private.t option)` coercion.

**One addition the reviewer's plan did not anticipate: `Attr.flatten`.** The claim
"nothing outside `attr.ml` constructs a `Private.t` and needs it back as an `Attr.t`" has
one counter-example — `Attrs.of_list`'s `add`, whose `Many` arm recurses on the payload.
With `private`, destructuring `Many l` yields `Attr.Private.t list` and the coercion does
not run that way, so the recursion cannot be typed and the map cannot be fed. The three
ways out were an identity `of_private : Private.t -> t` (which would have handed
applications back the construction power `private` just took away), storing
`Attr.Private.t` in `Attrs.t` (which pushes the same problem into `Attrs.find`'s return
type and into `Attrs.op`), and exposing the flatten itself. I took the third:

```ocaml
val flatten : t list -> t list
```

implemented in `attr.ml` where the type is transparent, documented as existing for
`Attrs.of_list` and giving no construction power. `Attrs.of_list` is now a flat fold with
one coercion. The existing `of_list` golden (css-class order, last-write-wins) is
unchanged, which is the evidence that the flatten preserves depth-first left-to-right
order.

**No downstream construction sites existed.** `dune build @all` — which covers
`examples/counter.ml`, `examples/gallery.ml` and every test — passed with only the three
pattern sites above needing a change. Nothing built an attr from a raw constructor.

**`README.md`'s Limitations bullet** claimed `Attr.t` was an unsealed public variant. It
now describes what the code enforces, keeps the (still true) half about
`Bonsai_gtk_test.Action.t`, and repeats why `Attr.Name.t` stays concrete.
`docs/m1-backlog.md`'s "Do first in M2 — seal `Attr.t`" entry is left alone: it is a
statement of what M2 should do, not a claim about current behaviour, and Task 15 rewrites
that file as `docs/m2-backlog.md`.

## Important 2 — the mount-time slot invariant is restored, ungated

`Signals.require_slots : node_path:string -> impl_name:string -> slots -> Attrs.t -> unit`
raises if any event attr in the node's attrs has no slot. `Patcher.mount` calls it
immediately after `connect_all` and before `update_slots`, unconditionally — a handful of
`List.Assoc.mem` lookups over lists of length ≤ 3. Message:

```
root/1: Button connected no signal for On_clicked, which Events says it emits (the widget impl and the table disagree)
```

`impl_name` rather than `Kind.name` here, because unlike `require_specs` the thing at
fault is the impl.

**The test.** There is no way to make a *real* impl disagree with the table without
editing one — `live_events.ml` proves none of them does — so I tested the assertion at the
level it actually operates on, in `test/live/live_signals.ml`, which already has a display
and a `Signals.ctx`: `connect_all` with an **empty spec list** produces exactly the slots
an impl that forgot a spec would produce, and the attrs carry the event the table would
have said it emits. Both directions are pinned in `expected_signals.txt`:

```
missing slot: root/1: Button connected no signal for On_clicked, which Events says it emits (the widget impl and the table disagree)
present slot: accepted
```

The second line also pins that `clear_slots` (which runs just before, in the same test)
empties the cells without removing the names, so teardown does not make the assertion
spuriously fire.

## Important 3 — the kind count is compiler-derived

`Kind.t` gains `[@@deriving variants]` (in both `kind.ml` and `kind.mli`, with a comment
in the mli saying it is there for exactly this), and both `all_kinds` lists now carry

```ocaml
let () = assert (List.length all_kinds = List.length Kind.Variants.descriptions)
```

— `test/test_events.ml:50` and the same line in `test/live/live_events.ml`. This is
Minor 3's "put it in both" as well.

**Confirmed non-vacuous**: deleting the `Node.spinner` row from `test/test_events.ml`'s
list and running `dune build @test/runtest` gives

```
Uncaught exception:
  "Assert_failure test/test_events.ml:50:9"
```

The row was restored. `kinds checked: 29` stays in `expected_events.txt` because a reader
of the golden wants to see it, but it is no longer the tripwire, and both the comment
beside the `printf` and `vtree/events.mli`'s doc now say so. That mli sentence also now
states that `live_events.ml` is live-gated and that `Signals.require_slots` is the
unconditional backstop under it.

## Minors

- **1 — taken**, the first of the reviewer's two options: `require_specs` drops
  `~impl_name` and names the widget with `Kind.name kind`. Parity with
  `Bonsai_gtk_test`'s message is now by construction rather than by inspection, and the
  function has one argument fewer. No golden churned, which is the evidence that the two
  spellings already agreed for every kind exercised.
- **2 — taken.** "so 'the handle accepted it' really does mean 'the runtime will connect
  it'" is narrowed to *that attr*, and the sentence now names both checks and says which
  one is behind `BONSAI_GTK_LIVE_TESTS=1`.
- **3 — taken** as part of Important 3. The two `all_kinds` lists are still duplicated
  (they differ in the `Native` row: the headless one uses `Native.Unit`, the live one a
  real `Native_gtk.impl`, because `Registry.for_kind` rejects a payload-free native), but
  each is now independently checked against `Kind.t` rather than against nothing.
- **4 — taken.** `test/handle/test_handle.ml` pins
  `(Invalid_argument "root/0: Native:thing does not emit On_clicked")`, so a wildcard
  slipping into `Events.for_kind` would now move a golden. The `Native:thing` spelling in
  that message is also incidental evidence for Minor 1: `Kind.name` reproduces
  `Native_gtk`'s `"Native:" ^ impl.name` exactly.
- **5 — taken.** A new case passes `on_toggled` then `on_clicked` (argument order) to a
  `Label` and gets `(On_clicked)` — `Attr.Name` declaration order, not argument order —
  and the same attrs against a `Button`, where `On_clicked` is legal, give `(On_toggled)`.
  The claim would have survived the old single-attr test whatever the function did.
- **6 — taken**, since it is free: `Attr.Private`'s signature now exports `sexp_of_t`
  (`attr.ml`'s `Private` already derived it). It matters slightly more after this round
  than before: with `private`, a value that has been coerced to `Attr.Private.t` can no
  longer be handed to `Attr.sexp_of_t`.
- **7 — no action, as the reviewer intended.** Validation stays in `Result_spec.view`, for
  the two reasons the finding itself gives.

## Guard re-verified after the refactor

The deliberate `Paned` corruption was re-run against the fixed tree, since `require_specs`
and the mount path both changed:

```
------ test/live/expected_events.txt
++++++ test/live/output_events.txt
+|(MISMATCH (kind Paned) (impl_declares (On_position_changed))
+| (table_says (On_clicked On_position_changed)))
 |kinds checked: 29
 |agreed
```

Reverted from a byte copy; `git diff vtree/events.ml` against the committed state is
empty.

## ci.sh tail

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

## Still open for later tasks

Unchanged from the first report, plus: every widget task must now add its kind to the two
`all_kinds` lists or the `Kind.Variants.descriptions` assertion fails — which is the
point, but it is a failure a Task 6–11 implementer will meet and should recognise rather
than route around by bumping a number.
