# M1 final review — tests, test library, examples, scripts

Branch `m1`, HEAD `886b1d5`, base `9f80cd4`. No tracked file was modified.

## CI result

`scripts/ci.sh` must be run inside `nix develop` — `xvfb-run` comes from the flake's dev
shell, not the opam switch. Run bare it aborts at the live-test step with
`xvfb-run: command not found` (exit 127, correctly propagated by `set -e`; my first
invocation piped it through `tail`, which masked the code — that was my error, not the
script's).

```
$ nix develop -c ./scripts/ci.sh
CI_EXIT=0
== nix: ocgtk pin builds and passes its tests
== format
== build
== generated opam files are committed
== pure + headless tests
== live tests (xvfb)
bonsai_gtk: exception in frame, stopping the driver: (Invalid_argument
  "root/0/1: a Node.window may only be the root node, not a child of another node")
== example smoke
all green
```

Exit 0, `all green`. The `exception in frame` line is `live_driver.ml`'s `breaking_app`
logging to stderr on purpose; it is not a failure.

Exit-code propagation verified independently:

```
$ nix develop -c bash -c 'xvfb-run -a false; echo $?'   ->  1
$ nix develop -c bash -c 'xvfb-run -a true;  echo $?'   ->  0
```

`set -euo pipefail` plus a bare `BONSAI_GTK_LIVE_TESTS=1 xvfb-run -a dune build
@test/live/runtest` means a live-test diff does abort the script. The gating env var is
set by the script and matches `test/live/dune`'s
`(enabled_if (= %{env:BONSAI_GTK_LIVE_TESTS=0} 1))`; the live tests demonstrably ran (the
stderr line above only appears when they do).

## Summary

The test suite is unusually honest. Every reassert ("decline the edit") test I checked
first drives the widget away from the model's value through the real GTK setter and then
observes it come back — none of them is a no-op dressed up as a test. `live_driver.ml`
proves the reentrancy guard and the controlled rule end to end through a real
`Driver.frame` and a real GLib idle, with no sleeps anywhere: every live test pumps the
loop explicitly with `while Glib.Main.pending () do ignore (Glib.Main.iteration false)`,
so they are deterministic. `test_reconcile.ml`'s quickcheck with a stricter
`checked_apply` that asserts `Update`'s identity claim is better than the property it was
asked for. The `Live_tree` dumps are read carefully enough that the accepted files really
do encode intended behaviour (`attr_view []` restoring a bare `(GtkLabel (text styled))`,
`(unmeasured (1)) -> (unmeasured (2)) -> (unmeasured (1))` for the overlay flip).

What is missing is breadth in three places, and one packaging break.

1. **`opam install --with-test` is broken for both packages.** `dune build -p <pkg>
   @runtest` — the exact command in both generated `.opam` files — fails, because
   `test/dune` straddles the two packages. `ci.sh` never runs `-p`, so this is invisible.
2. **Nine of the twenty-eight kinds are mounted and unmounted but never patched with a
   changed property** — including `Window`, `Box` and `Grid`. Their `update` functions
   have never executed a single write in any test.
3. **`Bonsai_gtk_test` cannot see `require_specs` or the impl registry**, so a headless
   test suite can be entirely green for an app that raises `Invalid_argument` the moment
   it is mounted.

Nothing here is a false-passing assertion; it is all absent coverage plus one build
break. Everything already listed in `docs/m1-backlog.md` is excluded.

## Critical

None. CI is green and I found no test whose accepted output encodes behaviour the author
did not intend.

## Important

### I1. `dune build -p <pkg> @runtest` fails for both packages — `opam install --with-test` cannot work

`test/dune:1-11`, `dune-project:29-33`.

Both generated `.opam` files carry `["dune" "build" "-p" name ... "@runtest" {with-test}]`.
Neither succeeds:

```
$ dune build -p bonsai_gtk @runtest
File "test/dune", line 6, characters 2-17:
6 |   bonsai_gtk_test
Error: Library "bonsai_gtk_test" not found.
-> required by library "bonsai_gtk_tests" in _build/default/test
EXIT=1

$ dune build -p bonsai_gtk_test @runtest
File "test/dune", line 5, characters 2-18:
5 |   bonsai_gtk.vtree
Error: Library "bonsai_gtk.vtree" not found.
EXIT=1
```

`test/`'s inline-test library depends on `bonsai_gtk.vtree` (package `bonsai_gtk`) *and*
`bonsai_gtk_test` (package `bonsai_gtk_test`), so `--only-packages` masks one of them
whichever way round you go. `dune-project:29-33` states the opposite in a comment:

> `; test/dune's requirements, so `opam install bonsai_gtk --with-test` resolves on a
> clean switch.`

Adding `bonsai_gtk_test` to `bonsai_gtk`'s `depends` is not the fix — that is a package
cycle. The fix is to move the tests that need `Bonsai_gtk_test` (`test/test_handle.ml`,
`test/test_gallery.ml`) into a directory owned by the `bonsai_gtk_test` package, leaving
`test/` depending on `bonsai_gtk` alone; or to drop `@runtest` from the opam build.

Failure scenario: anyone doing `opam install bonsai_gtk --with-test`, or an opam CI job,
gets a hard build failure on a package whose own CI is green. Correct the comment either
way — as written it asserts something demonstrably false.

### I2. `Bonsai_gtk_test` bypasses `require_specs`, so a green headless suite can still raise at mount

`test_lib/bonsai_gtk_test.ml:33-71`, `test_lib/dune:3`.

`Result_spec.incoming` looks the handler up with `Attrs.find n.attrs On_clicked` and
calls it. It never consults the widget's kind (except `Toggle`, which needs `active` to
read), and `test_lib/dune` deliberately depends only on `bonsai_gtk.vtree` — not
`bonsai_gtk` — so it has no access to the impl registry that `Signals.require_specs`
(`src/signals.ml:74-85`) checks against.

Concretely:

```ocaml
Node.label ~attrs:[ Attr.test_id "x"; Attr.on_clicked (set_count 1) ] "hi"
```

`Handle.do_actions handle [ Click "x" ]` fires the handler and the expect test goes green.
Mounting the same app raises `Invalid_argument "root/…: Label does not emit On_clicked"`
on the first frame. The same holds for `On_changed`, `On_activate`,
`On_search_changed`, `On_value_changed` — every action except `Toggle`, which is saved
only incidentally by `current_active` needing a toggle-shaped kind
(`test_lib/bonsai_gtk_test.ml:20-27`, and `test/test_handle.ml:113-131` tests exactly
that).

The `create` docstring (`test_lib/bonsai_gtk_test.mli:34-36`) says "no GTK, no display,
just the `Node.t` sexp tree", which is accurate about the mechanism but does not warn
that the headless handle accepts trees the runtime rejects. The architectural constraint
is real (test_lib must not depend on ocgtk), but the spec table `require_specs` consults
is pure data — a vtree-level table of `Kind.t -> Attr.Name.t list`, or an explicit
sentence in the mli saying "structural validation happens at mount, not here", would
close it.

### I3. Nine kinds are never patched with a changed property

Verified by reading every live test and grepping the props they pass:

| Kind | `update` never runs a write because | evidence |
|---|---|---|
| `Window` | no live test ever changes `~title` or `~default_size` | every `Node.window` in a patch sequence repeats the same title; `grep -c default_size test/live/*.ml` is 0 in all five files |
| `Box` | `~spacing` is `4` in both `live_patcher` renders and absent elsewhere; `~orientation` is `Vertical` in 22 of 25 uses and never changes within a sequence; `~homogeneous` appears nowhere in `test/` or `examples/` | `src/widgets/w_box.ml:20-33` |
| `Grid` | `~row_spacing:6 ~column_spacing:12` in both `grid_view` renders; `row_homogeneous`/`column_homogeneous` used nowhere | `src/widgets/w_grid.ml` update, 4 branches |
| `Paned` | `~position:120` is the only paned prop used anywhere in `test/live/`; `wide_handle`, `resize_start`, `resize_end`, `shrink_start`, `shrink_end` appear in no test or example | `src/widgets/w_paned.ml:52-70`, 6 branches |
| `Spinner` | `~spinning:true` in `scale_view`, mounted and patched twice unchanged | `src/widgets/w_spinner.ml` |
| `Password_entry` | props constant in `live_controls.ml:71-77`; no other live use | — |
| `Search_entry` | props constant in `live_controls.ml:78-87` | — |
| `Stack_switcher` | `~stack:"nav"`/`"all"` never changes | see I4 |
| `Stack_sidebar` | same | see I4 |
| `Center_box` | its one prop `shrink_center_last` (`vtree/kind.ml:208-212`) is set nowhere in `test/` or `examples/` | — |

`Window`, `Box`, `Grid` and `Paned` are the ones that matter: they are the layout
skeleton of every app, and a regression in `W.Window.set_title`,
`W.Box.set_spacing`/`set_orientation`, `W.Grid.set_row_spacing` or
`W.Paned.set_position` would not be caught by anything on this branch. The backlog's
"untested-but-implemented update branches" list (`Frame.label_align`,
`Expander.use_markup`, `Revealer.transition`, `W_image.update` pixel_size) does not
include any of these, so they are new.

Cheapest fix: one extra live sequence that mounts a window/box/grid/paned with one set of
props and patches it to another, dumping both. `Live_tree.dump` already prints
window title, box spacing, grid spacings and paned position, so it is a pure test
addition.

### I4. Retargeting a `stack_switcher`/`stack_sidebar`, and renaming a stack a switcher points at, are untested

`src/patcher.ml:159-168` re-enqueues the switcher fixup on *every* patch, precisely so a
switcher keeps following a stack that was replaced or renamed. Nothing exercises it:
`live_containers.ml:451-460` and `examples/gallery.ml:210-220` use a single constant
`~stack:"nav"` / `~stack:"gallery"`.

Two untested paths, both reachable from ordinary app code:

- A patch that changes `~stack:"a"` to `~stack:"b"` on a live switcher. If the fixup were
  ever moved back inline (`w_stack_switcher.ml`'s `update` is empty with the comment
  "Re-pointing at a different stack is also a fixup; nothing to do inline"), the switcher
  would silently keep driving the old stack — no exception, no diagnostic.
- A patch that renames a stack to a *free* name while a switcher still names the old one.
  `note_interest`'s `Patch` arm does `Hashtbl.remove ctx.stacks old_name`
  (`src/patcher.ml:146-152`), so this must raise `no Node.stack is named "..."`. Only the
  rename-*onto*-a-taken-name collision is tested (`expected_containers.txt:338`).

### I5. Stack: no frame ever adds a page and selects that same new page

`live_containers.ml:453-490`. The three stack renders are:

1. mount, pages `[library; practice]`, visible `library`
2. patch, pages `[library; practice; setlists]`, visible **`practice`** — a page that
   already existed
3. patch, pages `[practice; setlists]`, visible **`setlists`** — a page that already
   existed

So the selection never lands on a page created in the same pass. That is the single case
the fixup queue exists for: `W_stack.select` (`src/widgets/w_stack.ml:42-57`) is a no-op
when `get_child_by_name` returns `None`, and the enqueue at `src/patcher.ml:156-159` is
what guarantees the pages have been attached by the time it runs. Failure scenario: a
wizard that renders `~visible_child:"step2"` in the same frame that appends the `step2`
page — if the fixup ordering regressed, the stack would silently stay on `step1` and only
catch up on the *next* frame, which for a settled app never comes. Rendering
`~visible:"setlists"` in step 2 instead of `"practice"` would cover it at zero cost.

### I6. `~after` list placement: nothing is ever inserted before an existing sibling, and no `Move` ever targets index 0

`src/patcher.ml:421-445`. `after_of cur index` returns `None` at index 0 and
`Some cur[index-1]` otherwise; `w_box.ml:41-45` passes it straight to
`insert_child_after` / `reorder_child_after`.

- `insert ~after:None` **is** exercised, but only by `mount_list` (`src/patcher.ml:222-225`),
  where the container is empty at the time — and once by `live_patcher.ml:128` inserting
  the native counter into a box the same patch had just emptied. No patch ever prepends a
  child in front of siblings that are already there.
- `move ~after:None` — a `Move` to index 0 — is called **nowhere**. Walking every live
  list patch: `live_patcher.ml` `[label;a;b] -> [label;b;c;a]` moves `b` to index 1
  (predecessor `label`) and inserts `c` at index 2; the grid explicitly drops `Move`
  (backlog); the overlay only appends and removes at the tail; the stack only appends and
  removes at the head.

Failure scenario: a list whose first row is keyed and gets a new keyed row prepended (a
newest-first feed, a "pinned" item appearing) takes both untested branches at once. GTK's
`gtk_box_reorder_child_after(box, child, NULL)` does prepend, so this is unlikely to be
broken today — but it is the M1 child-ops headline (`~after:(Widget.t option)` replacing
`~index`, backlog "Closed during M1") and it has no test at the head.

### I7. §11's non-window root, and `Driver.frame` on a stopped driver, have no test

- `src/driver.ml:25-31`, `"Bonsai_gtk: the root node must be a Node.window, got %s"`.
  Spec §11 names "non-window root" first in its list of structural misuse. `grep -rl` over
  `test/` finds nothing. The *nested*-window half of the same sentence is well covered
  (`expected_patcher.txt:60`, and again through a real frame in `live_driver.ml`), so this
  is the one half nobody wrote.
- `src/driver.ml:33-38`, `"Driver.frame on a stopped driver …"`. `live_driver.ml:139`
  calls `Expert.Driver.stop d` and then never touches `d` again; the file's comment at
  line 156-160 carefully tests `frame` on a *broken* driver instead, and the mli's
  contract for the stopped case is unasserted.

Both are three-line additions to `live_driver.ml`.

### I8. CSS classes are never added or removed by a patch

`vtree/attrs.ml`'s `Add_css_class`/`Remove_css_class` ops are covered purely
(`test/test_attrs.ml:29-42`), but the GTK side is not. The only live use is
`live_patcher.ml:58` and `:99`, both `Attr.css_class "title"` on the same label in both
renders — so `W.Widget.add_css_class` runs at mount and `remove_css_class` runs never.

Failure scenario: `Attr.css_class (if active then "selected" else "")` — the ordinary way
an app expresses selection state — exercises exactly the untested path.
`Live_tree.dump` already prints `(css (...))`, so adding a class in one render and
dropping it in the next would show in the golden with no new machinery.

### I9. Reassert is untested for `Password_entry` and `Search_entry`

`src/widgets/w_password_entry.ml:40-47` and `src/widgets/w_search_entry.ml:50-57` both
carry `reassert = Some` writing `text` through `W_entry.set_text_if_needed`. Ten impls
have a non-`None` `reassert`; eight have a decline-the-edit test (toggle_button,
check_button, switch, entry, spin_button, scale in `live_controls.ml`; expander, revealer
in `live_containers.ml:207-224`; stack via its fixup in both `live_containers.ml:497-517`
and `live_driver.ml:214-226`). These two do not.

They are not redundant with `Entry`: both route through `W_entry.editable w`, which for a
`GtkPasswordEntry` and a `GtkSearchEntry` is a *different* `GtkEditable` delegate than the
one a plain `GtkEntry` exposes. A password field the model rejects (too short, wrong
charset) is the exact case where a missing reassert leaves the user's rejected text
sitting in the widget.

The `live_controls.ml` `entry_view` block (lines 219-268) already has the shape; the
cheapest fix is to parameterise it over the three entry constructors.

## Minor

### M1. `Attr.Name.is_event` is tested on 2 of 32 names, and 7 of 10 event attrs have no negative `require_specs` test

`vtree/attr.ml:43-75`. `test/test_widgets.ml:60-66` checks `On_toggled -> true` and
`Tooltip -> false`. Live negative tests exist for `On_toggled` (at mount *and* at patch),
`On_expanded_changed` and `On_revealed` (`expected_controls.txt:98-101`). Missing:
`On_clicked`, `On_changed`, `On_activate`, `On_search_changed`, `On_value_changed`,
`On_position_changed`, `On_visible_child_changed`.

`require_specs` is generic over the name, so the *mechanism* is covered. The real hole is
classification: `is_event`'s match is exhaustive, so adding an attr forces a decision, but
adding `On_foo` to the `false` branch compiles and silently makes the typo check stop
applying to it. A table-driven test over `Attr.Name.all` asserting the exact event set
would pin it in one place. Lower severity than it looks because the *positive* direction
is well covered — `expected_controls.txt:97` counts eight distinct entry signals actually
reaching Bonsai, which would drop if any spec failed to connect.

### M2. Expect tests pass properties whose acceptance the accepted output cannot show

`Kind.t`'s `[@sexp_drop_if]` (backlog: "Kind.t's sexps are lossy") silently erases
default-valued arguments, so several test arguments assert nothing:

- `test/test_widgets.ml:137` `Node.picture ~content_fit:Contain ~can_shrink:true` — both
  are the defaults (`vtree/defaults.ml:80-83`) and neither appears in the expected sexp
  at `:157`. A constructor that dropped `~content_fit` entirely would still pass.
- `test/test_widgets.ml:180` `Node.scrolled_window ~vpolicy:Automatic` — default
  (`vtree/defaults.ml:87`), absent from the expected output at `:191`.
- `test/test_widgets.ml:110` `Node.spin_button ~step:1.` — default
  (`vtree/defaults.ml:55`), absent at `:125`.

The comment at `test/test_widgets.ml:129-132` ("What is checkable headlessly is that both
reach the kind and print") is true for `Resource` and `~icon_size:Large`, which do print
— but the picture line beside it does not hold up. Either use non-default values, or drop
the arguments so the test does not look like it covers them.

### M3. `test_gallery.ml`'s "exactly once" comment is inaccurate

`test/test_gallery.ml:9` — "Every M1 `Node` constructor appears here exactly once".
`Node.button` appears three times (`:44`, `:48`, `:49`) and `Node.label`/`Node.box` many
times. The substance of the claim (every constructor appears at least once) is true and
verified — `Node.native` at `:150` included. Only the wording is wrong.

Separately, `every_widget` is a single `Handle.show` with no actions: `n` never leaves 0,
so `~active:(n % 2 = 0)` at `:55` is a constant and `Attr.test_id "inc"` at `:47` is never
clicked. That is fine for a constructor snapshot; the name of the test
("every M1 widget builds a legal node") is honest about it.

### M4. `find_by_test_id` silently first-matches duplicate ids

`vtree/node.ml:431-435` — a plain DFS returning the first hit. `vtree/node.mli:645`
documents "Depth-first search", which implies it, but `Bonsai_gtk_test`'s mli says nothing
and nothing tests it. Failure scenario: a component rendered twice (two rows of the same
sub-view, both carrying `Attr.test_id "delete"`) makes `Click "delete"` hit whichever the
walk reaches first, and the test passes while asserting nothing about which one. Raising
on a duplicate, or at least a test pinning first-match, would be worth it before
`Action.t` grows further.

"After unmount" behaves correctly and is covered: a node absent from the current snapshot
raises `no node with test_id …` (`test/test_handle.ml:57-63`), which is the same path.

### M5. The `ci.sh` example smoke can pass without the example ever launching

`scripts/ci.sh:43-52`. `xvfb-run -a timeout -k 2 3 dune exec "examples/$ex.exe"` and then
`[ "$code" = 124 ]`. The 3-second budget covers `dune exec`'s build step as well as the
run. It is warm in practice — `dune build @all` runs at line 33 — but on a cold cache, or
under dune lock contention, `timeout` kills dune mid-build and returns 124, which the
script reads as "the GUI came up and stayed up". Building the exe explicitly and running
`_build/default/examples/$ex.exe` would make 124 mean what the comment says it means.

Note that the smoke is otherwise doing its job: a gallery that fell over at startup would
exit non-124 and fail the build. And the backlog already carries "Real-display
click-through of `examples/gallery.exe`", so the absence of interaction is known.

### M6. `examples/gallery.ml` leaks a temp file per run

`examples/gallery.ml:21-25` — `Stdlib.Filename.temp_file "bonsai_gtk_gallery" ".png"` is
written and never removed, so every `ci.sh` run and every manual launch leaves a PNG in
`$TMPDIR`. `live_containers.ml:130` does the right thing with `Stdlib.Sys.remove png`.

### M7. `Attr.margin` (the combined convenience) is exercised only by the unasserted example smoke

`grep -rn "Attr.margin " test/ examples/` finds it eight times in `examples/gallery.ml`
and once in `examples/counter.ml`, and never in `test/`. `live_patcher.ml`'s attr sweep
sets the four `margin_*` attrs individually. So the expansion — one `Attr.t` becoming four
— is only ever compiled and run, never asserted. One line in the `attr_view` sweep would
cover it.

## Coverage table

`mount` = created through a real `Patcher.mount`; `patch` = `impl.update` (or `reassert`,
where the prop is controlled) executes an actual write during a live patch; `unmount` =
destroyed live; `reassert` = a decline-the-edit test that first drives the widget away
from the model's value; `event` = a signal fired live and observed reaching Bonsai.
`n/a` = the impl has no such thing.

| Widget | mount | patch | unmount | reassert | event |
|---|---|---|---|---|---|
| Label | yes | yes (text, wrap, xalign, ellipsize, max/width_chars, selectable, use_markup) | yes | n/a | n/a |
| Button | yes | yes (label ↔ child ↔ icon_name) | yes | n/a | yes (clicked) |
| Toggle_button | yes | yes (active) | yes | **yes** (patcher + `Driver.frame`) | yes (toggled) |
| Check_button | yes | yes (active) | yes | **yes** | yes (toggled) |
| Switch | yes | yes (active, via reassert; `update` is empty by design) | yes | **yes** | yes (notify::active) |
| Entry | yes | yes (text) | yes | **yes** | yes (changed, activate) |
| Password_entry | yes | **no** | yes | **no** (I9) | yes (changed, activate) |
| Search_entry | yes | **no** | yes | **no** (I9) | yes (changed, activate, search-changed) |
| Spin_button | yes | yes (value) | yes | **yes** | yes (value-changed) |
| Scale | yes | yes (value) | yes | **yes** | yes (value-changed) |
| Progress_bar | yes | yes (fraction) | yes | n/a | n/a |
| Spinner | yes | **no** | yes | n/a | n/a |
| Image | yes | yes (source kind swap, pixel_size) | yes | n/a | n/a |
| Picture | yes | yes (source, content_fit, can_shrink, alternative_text) | yes | n/a | n/a |
| Separator | yes | yes (orientation) | yes | n/a | n/a |
| Scrolled_window | yes | yes (all eleven props, incl. min/max write order) | yes | n/a | n/a |
| Frame | yes | yes (label) | yes | n/a | n/a |
| Expander | yes | yes (label, expanded) | yes | **yes** | yes (notify::expanded) |
| Revealer | yes | yes (reveal) | yes | **yes** | yes (notify::child-revealed) |
| Box | yes | children yes; **props no** (I3) | yes | n/a | n/a |
| Grid | yes | cells yes; **props no** (I3) | yes | n/a | n/a |
| Stack | yes | yes (visible_child, page add/remove/retitle) | yes | **yes** (fixup, patcher + `Driver.frame`) | yes (notify::visible-child-name) |
| Stack_switcher | yes | **no** (I3, I4) | yes | n/a | n/a |
| Stack_sidebar | yes | **no** (I3, I4) | yes | n/a | n/a |
| Center_box | yes | slots yes (Some→None→Some, kind change); **prop no** | yes | n/a | n/a |
| Paned | yes | slots yes; **props no** (I3) | yes | n/a (uncontrolled by design) | yes (notify::position) |
| Overlay | yes | overlays yes (add/remove, measure_overlay both directions) | yes | n/a | n/a |
| Window | yes | child yes; **props no** (I3) | yes | n/a | n/a |
| Native (escape hatch) | yes | yes (`update` with a changed input, same widget) | yes (`destroy` observed) | n/a | n/a |

All 28 kinds are mounted and unmounted at least once live. `examples/gallery.ml`
constructs 28 of 28 (`Node.native` excepted, which is the escape hatch rather than a
catalogue widget) and is built by `dune build @all` and launched by the `ci.sh` smoke, so
a changed widget signature does break CI.

Structural cases explicitly asked about:

- **Slot `Some → None → Some`** — covered, `live_containers.ml:340-365` (`center_box`'s
  `?center` across three renders).
- **Kind change in place** — covered three ways: keyed list child
  (`live_patcher.ml:88-105`), `Single` slot on all four single-child containers
  (`live_containers.ml:274-296`), named slot (`center_box`'s `~end_`,
  `live_containers.ml:345-348`).
- **Expander opening and swapping its child in one patch** — covered,
  `live_containers.ml:298-325`.
- **Stack same-frame add + switch** — **not** covered for the newly-added page (I5).
- **`~after` head / middle / tail** — middle and tail covered; head only at mount, and
  `Move`-to-head never (I6).

## Out-of-scope observations

These are in `src/`, not my area, and I did not verify them beyond reading:

- `src/patcher.ml:234-270` and `:478-509` carry six slot-shape `Invalid_argument` messages
  (`slot %s does not exist on %s`, `slot %s has the wrong shape for %s`,
  `%s's slots changed shape under an unchanged kind`, `node's children do not match %s's
  shape`, `%s has %d slots, node has %d`, `slot %d is %s in the live tree, …`). None has a
  test, and `live_containers.ml:379-382` explains why: every `Slots` node comes from a
  constructor whose slot list is written beside the impl's, so nothing reachable through
  `Node`'s public API can provoke them. `Node.t`'s record *is* public
  (`vtree/node.mli:3-9`), so a hand-built record could — but that is not an M1 use case.
  I agree with the file's reasoning; recording it here only so the §11 checklist reads
  honestly rather than as "untested".
- `src/native_gtk.ml:45-50` (`node carries a different Native_gtk.impl`) and `:67`/`:78`
  (`Native node %s has no Gtk payload`) are likewise untested. The first one is reachable
  from user code — building the impl inside the render function instead of at the top
  level is the mistake the message exists for, and `live_patcher.ml:26-28` deliberately
  demonstrates the *right* way without ever testing the wrong one. Worth one test in M2.
- `src/widget_impl.ml:45` `wrong_kind` fires in every impl's fallthrough arm and is
  untested everywhere; it is a "the patcher handed me the wrong kind" internal assertion,
  unreachable while the registry is right.
- `Node.window ~default_size` never reaches GTK in any live test (`grep -c default_size
  test/live/*.ml` is 0 across all five), so `W.Window.set_default_size` in
  `w_window.ml:15-17` is exercised only by the example smoke.

## Verdict

**Needs fixes.**

One of the nine Important findings is a genuine build break rather than a coverage gap:
**I1**, `dune build -p <pkg> @runtest` failing for both packages, means the shipped
`.opam` files do not install with tests, and `dune-project` asserts the opposite in a
comment. That should be fixed or the comment corrected before M1 is called done, and it
is the only item I would block on.

The rest are absent coverage, not wrong tests. **I3** (nine kinds never patched —
`Window`, `Box`, `Grid`, `Paned` most of all), **I5** (stack add-and-select in one frame)
and **I9** (password/search reassert) are the three I would want closed inside M1, because
each is a small addition to an existing live sequence and each guards a path an ordinary
app takes on its first day. **I2** deserves at least a sentence in
`test_lib/bonsai_gtk_test.mli` now, even if the vtree-level spec table waits for M2;
shipping a test library that certifies apps the runtime will reject is the kind of thing
that is much cheaper to caveat than to retract. **I4**, **I6**, **I7** and **I8** are fair
M2 backlog material.

Everything I checked for test honesty held up. The reassert tests all establish real
divergence before asserting recovery, the signal-count assertions are arithmetically
exact, the live tests are deterministic without a single sleep, and the accepted golden
files encode intended behaviour rather than whatever the code happened to print.
