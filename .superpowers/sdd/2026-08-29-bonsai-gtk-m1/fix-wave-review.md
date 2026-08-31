# Re-review of the M1 final-review fix wave

Branch `m1`, base `886b1d5`, head `1eeba76`, eleven commits. Read-only: no tracked file was
modified in this checkout. Verification that needed mutation was done in a throwaway
`git worktree` at `1eeba76` (borrowing the main checkout's opam switch via
`opam env --switch=/home/dlobraico/src/bonsai_gtk`), which has been removed;
`git status` in the repo is clean and HEAD is `1eeba76`.

## CI result

`nix develop -c ./scripts/ci.sh` — **exit 0, `all green`**.

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

The `exception in frame` line is `live_driver.ml`'s `breaking_app` logging to stderr on
purpose, as before the wave.

## Per finding

Verdicts are against the *original* failure scenario, re-derived from the new code rather
than taken from the fix-wave report. "Test non-vacuous" means I disabled the fix in the
worktree and watched the cited test fail.

| # | Finding | Verdict | Evidence |
|---|---|---|---|
| Core #1 | Hand-driven `Driver.frame` that raises does not set `broken` | **Closed** | `src/driver.ml:83-113`: the body moved to `frame_body`, and the `exception exn` arm calls `Scheduler.mark_broken` + `Patcher.abandon_fixups` before `raise_with_backtrace`. `Scheduler.mark_broken` (`scheduler.ml:60-77`) is `broken <- true; stop t` — idempotent, so `guarded_frame` calling it again is free. Mutation: delete `Scheduler.mark_broken t.scheduler;` → `live_driver.exe` dies with an **uncaught** `Invalid_argument` on the very call the test labels "the frame after that was a no-op", i.e. the driver keeps patching the half-written shadow tree. That is the finding's scenario, reproduced. |
| Core #1b | Stale `ctx.fixups` survive a raising pass | **Closed** | `Patcher.abandon_fixups` (`patcher.ml:70`), called from `Driver.frame`'s exception arm and from `Driver.stop` (`driver.ml:180-182`). Mutation: make `abandon_fixups` a no-op → `fixups left behind by the failed pass: 1 → 3` and `fixups after abandon_fixups: 0 → 3`. Non-vacuous. |
| Core #2 / containers I1 | Duplicate sibling keys not checked at mount; message carries no path | **Closed** | `Patcher.mount_list` (`patcher.ml:233-234`) calls `Reconcile.check_unique_keys` inside `child_op ~path`; `patch_list`'s `Reconcile.diff` is now wrapped too (`patcher.ml:443-450`). Message reworded (`reconcile.ml:24-35`) and no longer says `Reconcile.diff:`. Mutation: drop the `mount_list` call → `BUG: duplicate sibling keys accepted at mount` **and** `BUG: duplicate stack page names accepted at mount`. Paths verified in the goldens: `dupkey/0`, `duppage/0`, `patchdup/0`. |
| Core #3 | `register_stack` collides on an ordinary refactor | **Closed in code; NOT covered by a test** | `drop_stack_names` (`patcher.ml:343-359`) runs before the mount in `patch`'s kind-change arm (`patcher.ml:369`); `unregister_stack`'s `Gobject.same` guard (`patcher.ml:31-37`) is what keeps `destroy` from unregistering the replacement. I wrote the core report's own scenario as a probe — `window (box [stack ~name:"nav"])` → `window (frame (stack ~name:"nav"))`, which reaches the arm through `patch_single` — and it raises `root/0/0: two Node.stacks are named "nav" in one tree` without the fix and succeeds with it. **But the cited test is vacuous**: see Important 1. |
| Core #4 | `Signals.spec.connect` returns a bare handler id | **Closed** | `Signals.connection` carries `source` + `handler_id` (`signals.ml:11-20`); `disconnect` is `connection list -> unit` (`signals.ml:97-99`). I audited all ten specs: five go through `Signals.notify` (which now returns a `connection`), five build one with `Signals.connected`, and the entry family's `changed` correctly names the `GtkEditable` it connected to while each kind's `activate` names its own class. No spec pairs an id with a different object. No test, correctly — the change is type-driven: a spec returning a bare id no longer typechecks. |
| Controls #1 | Programmatic write to a `Node.search_entry` fires `on_search_changed` | **Closed** (one wrong premise in the comments — Minor 1) | `w_search_entry.ml:5-47`. Mutation (make `was_our_own_write` always `false`): `searches after the mount wrote the text: 0 → 1`, `after the model rewrote it: 0 → 2`, `after a real edit: BACHS → bach,BACH,BACHS`. Exactly the reported numbers, and the real user edit still reaches Bonsai in both. The `Ephemeron.K1` key is sound: ocgtk installs `hash_gobject` in `ocgtk_gobject_ops` (`wrappers.c:137-146`), so `Stdlib.Hashtbl.hash` is pointer-derived and agrees with `Gobject.same`; weak keys mean a destroyed entry drops its record. |
| Containers I2 | Grid re-attach drops focus; comment claims the opposite | **Closed as ruled** (the fix is untested insurance, disclosed) | `w_grid.ml:64-95`. Comment corrected. The restore only fires when the focus was *inside* the moved child (`Widget.is_ancestor focused child` — right direction), runs inside the patch guard so it cannot re-enter Bonsai, and reuses the root captured before the unparent, which is the same window after. No focus theft, no re-entrancy. Deviation (c) verified: see below. |
| Tests I1 | `dune build -p <pkg> @runtest` fails for both packages | **Closed** | Both `-p` builds pass at HEAD in a clean worktree. Non-vacuous both ways: breaking an expect in `test/handle/test_handle.ml` fails `-p bonsai_gtk_test @runtest`; breaking one in `test/test_node.ml` fails `-p bonsai_gtk @runtest`. `dune-project`'s comment corrected; `bonsai_gtk.opam` correctly drops `bonsai_test {with-test}` (nothing under `test/` needs it any more) and `bonsai_gtk_test.opam` gains `expect_test_helpers_core {with-test}`. |
| Tests I2 | Headless handle vs `require_specs` | **Closed as ruled** | `test_lib/bonsai_gtk_test.mli:39-50` says plainly that structural validation happens at mount and lists what the runtime rejects; README gains a matching paragraph and a Limitations bullet; the vtree-level table is on "Do first in M2". The table itself was not built, which is what was ruled. |
| Tests I3 | Nine kinds never patched with a changed property | **Closed** | The `layout ~alt` sweep (`live_containers.ml:384-443`) moves every prop of `Window`, `Box`, `Grid`, `Paned`, `Center_box` and `Spinner` across one patch, with an off-dump for `default_size` and `homogeneous` because `Live_tree.dump` prints neither (`default size 320x240, box homogeneous false` → `400x300 / true`). `Password_entry` and `Search_entry` get a kind-specific prop each in the parameterised entry sweep. |
| Tests I4 | Switcher/sidebar retargeting, and rename onto a free name, untested | **Closed** | `live_containers.ml:683-745`: `re-pointed at stack b -- switcher true, sidebar true`, and `rejected: rn/0/0: no Node.stack is named "old"`. |
| Tests I5 | No frame adds a page and selects that same page | **Closed** | `live_containers.ml:597-617`, golden `(GtkStack (visible (encores)))`. |
| Tests I6 | `~after` head placement and `Move` to index 0 | **Closed** | `live_containers.ml:747-766`: `(b c)` → `(a b c)` → `(c a b)`. |
| Tests I7 | Non-window root, `frame` on a stopped driver | **Closed** | `expected_driver.txt`: `rejected: Bonsai_gtk: the root node must be a Node.window, got Label` and `rejected: … Driver.frame on a stopped driver …`. |
| Tests I8 | CSS classes never added or removed by a patch | **Closed** | `live_patcher.ml:206-228`, golden `(css (selected))` → `(css (row))` → none. |
| Tests I9 | Reassert untested for `Password_entry` and `Search_entry` | **Closed** | The decline-the-edit block is parameterised over all three kinds; goldens show `password_entry echo is a no-op: ab (the patch wrote: false)` and the same for the search entry. |
| Tests M4 | `find_by_test_id` silently first-matches duplicates | **Closed** | `vtree/node.ml:431-455` walks the whole tree and raises naming every path. `Children.iteri`'s spelling matches the patcher's exactly — `mount_single`/`patch_single` use `path/0`, lists use `path/i`, `mount_slots`/`patch_slots` use `path/<slot>` — so a path from `iteri` names the same node a patcher message would. |
| Tests M5 | Example smoke can pass without the example launching | **Closed** | `ci.sh` builds `counter.exe`/`gallery.exe` first and runs them out of `_build/default`; the 3 s budget now covers the run alone. |
| Tests M6 | Gallery leaks a temp file per run | **Closed** (see Minor 7) | Fixed name under `get_temp_dir_name ()`. |
| Extra | `Live_tree.dump` segfaults on a password entry with no placeholder | **Closed, and correctly shaped** | Mutation: revert to `W.Password_entry.get_placeholder_text` → `live_controls.exe` dies with **`Command got signal SEGV`**. The generated stub does `caml_copy_string(g_value_get_string(&prop_gvalue))` with no NULL check (`ml_password_entry_gen.c:105-107`); `ml_g_value_get_string` maps NULL to `""` (`ml_gobject.c:294-309`), which is already what the surrounding code treats as "no placeholder". Reading through the GValue is the right shape. Nullable-binding audit below. |

### Nullable-binding audit (brief item 4)

The only `string`-returning (non-`option`) getters M1 calls anywhere in `src/` are
`Widget.get_name`, `W.Label.get_text` and `W.Editable.get_text`. All three stubs call the
C function directly (`ml_widget_gen.c:927`, `ml_label_gen.c:318`, `ml_editable_gen.c:113`)
and all three C functions are non-nullable by contract — `gtk_widget_get_name` falls back
to the class name, `gtk_label_get_text` and `gtk_editable_get_text` return the buffer.
Every other placeholder / label / title / icon-name / tooltip getter M1 uses
(`Entry.get_placeholder_text`, `Search_entry.get_placeholder_text`, `Button.get_label`,
`Check_button.get_label`, `Frame.get_label`, `Expander.get_label`, `Window.get_title`,
`Image.get_icon_name`, `Progress_bar.get_text`, `Picture.get_alternative_text`,
`Widget.get_tooltip_text`, `Stack.get_visible_child_name`, `Cursor.get_name`) is already
bound as `string option`. **No further NULL-as-`string` hazard exists in `Live_tree.dump`
or the widget impls.** The password entry's getter was the only one.

## Deviations

**(a) `guarded_frame` still calls `mark_broken`. Sound.** `mark_broken` is
`t.broken <- true; stop t` and `stop` is itself idempotent, so the second call costs
nothing. The reason given is the right one: `Scheduler.broken`'s documented contract
should not depend on which `run_frame` the scheduler was built with, and a scheduler whose
thunk raises without marking broken would otherwise keep ticking. `Driver.frame` genuinely
owns the transition now, which is what the ruling was about.

**(b) The stale-fixup test lives at patcher level. Sound.** I re-derived it: once
`Driver.frame` marks the driver broken, the guard at `driver.ml:88-93` makes the next call
a no-op, so "the stale fixup does not run in the next frame" has no next frame to be
observed in. Asserting it where it *is* observable — a raising pass leaves its queue
populated, `abandon_fixups` empties it — is the right call, and the assertion is
non-vacuous (mutation above).

**(c) The grid-focus premise does not reproduce, and the fix is insurance. Accurate, and
the fix is harmless.** I confirmed the second half independently: with the
`W.Root.set_focus` restore removed, the whole live suite is still green — so
`focus survives the re-attach: true` pins GTK 4.22's behaviour, not the fix. No focus
theft (only a focus *inside* the moved child is restored) and no re-entrancy (the hook runs
inside `Scheduler.with_patch_guard`, and no M1 spec connects to a focus signal anyway).
The situation is disclosed in three places — the fix-wave report, the test comment, and the
backlog's "known-and-accepted dump quirks" — so nobody will read the assertion as proof.
Accept, noting that what landed for containers I2 is a corrected comment plus untested
insurance rather than a repair, which is what the evidence supports.

**(d) The temp-prefix install in `ci.sh`. Sound; verified.** Both `-p` builds use
`--build-dir` overrides (`_build.pkg`, `_build.pkgtest`), both gitignored, so the main
`_build` is untouched. `dune install --prefix "$prefix" --libdir "$prefix/lib"` writes only
into the `mktemp -d`; nothing reaches the opam switch. `trap 'rm -rf "$prefix"' EXIT`
removes it on any exit, and with `set -u` an unset `$prefix` would error rather than delete
anything. It fails loudly: `set -euo pipefail` is in force and the `>/dev/null` on the
install redirects stdout only. I ran the whole sequence in a worktree and confirmed
nothing outside it changed.

**(e) `Attr.margin` came along with the css test. Accurate.** `expected_patcher.txt` shows
`(margin-start 7) (margin-end 7) (margin-top 7) (margin-bottom 7)` and then their absence,
so the one-attr-to-four-writes expansion is asserted for the first time.

## New findings

### Important

**1. The test cited as proof of Core #3 does not exercise the fix, so nothing would catch
its regression.**
`test/live/live_containers.ml:770-812` (`wrapped ~framed`), against `src/patcher.ml:369`.

With `drop_stack_names ctx live;` disabled (`if false then drop_stack_names ctx live;`) the
**entire live suite stays green** — `stack wrapped in a frame; switcher drives the
surviving stack: true` prints either way.

Why: in `wrapped`, the stack sits in a `Node.box`'s **unkeyed** child list beside the
switcher. `Reconcile.diff`'s unkeyed matcher pairs positionally only when `same_kind`
holds, and `Stack` vs `Frame` fails it — so the reconciler emits `Remove {index=1}` and
`Insert {index=1}` rather than an `Update`, and `removes @ ops` (`vtree/reconcile.ml:101`)
puts the remove first. `destroy` therefore unregisters `"refactor"` before `mount`
re-registers it, and `patch`'s kind-change arm — the only caller of `drop_stack_names` — is
never entered.

The fix is correct; I verified the real scenario with a probe of the core report's own
shape, reached through `patch_single`:

```ocaml
let v ~framed =
  Node.window ~title:"w"
    (if framed then Node.frame ~label:"Nav" (stack ())
     else Node.box ~orientation:Vertical [ stack () ])
```

Without `drop_stack_names`: `RAISED: root/0/0: two Node.stacks are named "nav" in one
tree`. With it: `OK`.

Fix: give the stack and the frame the same `~key` in `wrapped` (so the reconciler emits
`Update` with a differing kind), or move the wrapping up to the window's single child as
above. Two lines either way. The neighbouring `twins` test *does* enter the kind-change arm
and usefully proves the fix is not over-broad — a genuine collision still raises
`twin/0/1/0: two Node.stacks are named "twin"` — but it raises with or without the fix, so
it is not a substitute.

### Minor

**1. The invariant the search-entry fix rests on is wrong for a write that empties the
box.** `src/widgets/w_search_entry.ml:32-47`.

`gtksearchentry.c` (GTK 4.22.4, `gtk_search_entry_changed`, lines 775-793) emits
`search-changed` **synchronously**, cancelling any pending timeout, whenever the text
becomes empty; only a non-empty change goes through `reset_timeout`. So a library write
that clears the entry does `Echo.replace` and arms *no* timeout, and its synchronous
emission is swallowed by `Scheduler.in_patch` in `Signals.dispatch` before `fire` runs — the
record is never consumed and survives to be matched against some later, unrelated emission.
`was_our_own_write`'s comment ("a write arms exactly one timeout … this emission is the only
one that record could ever have explained") and `set_text`'s ("only a write arms a timeout")
are both false for that case.

Consequence today is benign: the orphaned record is always `""`, the model also holds `""`
at that moment, and the first non-empty search flushes it — so what gets dropped is a
duplicate, not a search. I could not construct a reachable M1 sequence that loses a
meaningful event. It is worth recording anyway because the reasoning the fix rests on does
not hold, and because M2's headless `Search_changed` action, or anything that iterates the
main loop mid-patch, changes the calculus. `test/live/live_controls.ml:358-362` already
knows about the synchronous empty-string emission; the impl's comments do not.

**2. `test/live/live_controls.ml:129-133`'s comment now contradicts its own expectation, and
the claim it makes has weakened.** It says "Eight in all", while the accepted output is
`entry signals reaching Bonsai: 7` (`expected_controls.txt`, changed by this wave). The
missing one is `search-changed`: the synthetic `emit_by_name` fires immediately after the
mount wrote the text, so the echo record suppresses it. The comment's stated purpose —
"each spec that failed to connect would drop this count" — therefore no longer holds for
`search_changed`, which now contributes 0 whether or not it connected. No coverage is lost
overall (the new dedicated block proves the spec connects), but the comment and the count's
claim both need correcting.

**3. The backlog removal overshoots.** `docs/m1-backlog.md` drops "Same-frame stack name
reuse or swap raises" as fixed. Probed at HEAD: the **swap** still raises — two stacks
exchanging names in one frame gives `root/0/0: two Node.stacks are named "b" in one tree`,
because `note_interest`'s rename arm (`src/patcher.ml:158-166`) does
`Hashtbl.remove old; register_stack new` per child left to right and the second stack still
holds the new name. The **reuse** half the item actually described (remove the stack named
`"nav"`, insert a different one with that name) is fine — and was fine before the wave too,
since `Reconcile.diff` emits removes first. So the item was half-wrong to begin with, and
removing it loses the still-true half. Spec §11 does still cover the case ("identically
when a patch renames a stack onto a name another stack holds"), so this is backlog hygiene
rather than a doc contradiction.

**4. `drop_stack_names` runs before `mount`, so a raising mount now drops registrations the
old subtree still needs.** `src/patcher.ml:369`. The old widgets are still alive (its
`destroy` never ran) but their stack names are gone. Bounded — the frame is broken — and it
is the mirror image of containers M3, which the wave already folded into the backlog; that
entry mentions only registrations *kept* by a failed mount, not registrations *dropped
early* by a failed kind change. One sentence on the same entry.

**5. `docs/superpowers/specs/2026-08-28-bonsai-gtk-design.md:455-459`: missing blank line.**
The new `fire`-returns-`None` paragraph ends "… see §6.5." and the pre-existing "Signals
ocgtk does not generate as `on_*` …" follows on the next line with no blank between, so
Markdown renders them as one paragraph.

**6. §6.5's wording of the search-entry rule is slightly off.** Line 502: "returns `None`
while the widget's text still equals it" reads as persistent suppression; the
implementation consumes the record on the first emission either way, which is the better
behaviour and is what `vtree/node.mli:173-182` describes correctly.

**7. `test_lib/bonsai_gtk_test.mli` does not mention the new raise.**
`Handle.do_actions` can now raise `Invalid_argument` (two nodes under one `test_id`) as
well as the documented `Failure "Bonsai_gtk_test: no node with test_id …"`, because
`Node.find_by_test_id` changed under it. Documented on the vtree function, not where a test
author reads it.

**8. `examples/gallery.ml:20-32` trades a leak for a symlink follow.**
`Filename.temp_file` created with `O_EXCL`; a fixed path in a shared `$TMPDIR` means
`Out_channel.write_all` follows whatever is already at
`$TMPDIR/bonsai_gtk_gallery.png`. Example-only and the goal (stop littering) is right;
noting it only because the previous code was safer in that one respect.

## Regressions elsewhere

I looked specifically at the two wide edits.

- **The `Signals` contract touched all ten specs.** Audited each: five use
  `Signals.notify` point-free (which now returns a `connection`), five wrap with
  `Signals.connected`, and the three entry kinds each pass their own class's `activate`
  connector. None pairs an id with the wrong object. One behavioural side effect, correct
  by design: a `connection` now holds a strong ocgtk wrapper ref on its source until
  `destroy`. In M1 the source is always the widget, which `live.widget` already pins, so
  nothing changes; for M2 it is exactly what keeps a buffer alive long enough to be
  disconnected from. `Signals.connected` remains trusting — nothing enforces that the id was
  issued for `obj` — which the mli says explicitly.
- **The patcher's kind-change arm changed order.** Only `drop_stack_names ctx live;` was
  added ahead of the existing mount-before-destroy; `patch_list`'s `Update` remove/insert
  branch is byte-identical to `886b1d5`. The `Gobject.same` guard that the wave factored out
  into `unregister_stack` is what keeps `destroy` from unregistering the replacement, and
  the `twins` test confirms the collision check is not weakened.
- `mount_list`'s new key check applies to slot lists too (`mount_slots` → `mount_list`),
  which is correct and is what makes `duppage/0` fire for a stack's pages.
- Everything else in the diff is additive test coverage, docs, or the packaging split, all
  of which CI exercises.

## Spec / README / backlog accuracy

Accurate, with the exceptions in Minor 3, 5 and 6. Checked specifically: §6.2's
mount-before-destroy amendment matches `patcher.ml:365-372`; §6.4's `connection` amendment
matches `signals.mli`; §6.5's deferred-signal rule matches `w_search_entry.ml`; §6.6's
native `create`/`destroy` overlap follows from the same ordering; §9/§10's package split
matches `test/dune`, `test/handle/dune` and `dune-project`; §11's mount-time key check and
its rename-onto-a-free-name sentence both match the code and the goldens. README's
`test/handle/test_handle.ml` path, its Limitations bullet, and its per-package-build
paragraph are all correct.

## Verdict

**Approved to merge**, conditional on Important 1 — a two-line change to
`live_containers.ml`'s `wrapped` test so that it actually enters the kind-change arm.

All sixteen Important findings are closed in code, and fifteen of them are backed by a test
I confirmed fails without the fix. Core #3 is the exception: the fix is right (I reproduced
the original collision and watched it disappear), but the regression test passes with the
fix removed, and the fix-wave report presents it as proof. The extra segfault fix is real
and correctly shaped, and the nullable-binding audit turns up nothing else. The five
deviations are all sound and honestly reported; (c) in particular is disclosed rather than
oversold. The remaining eight items are Minor and belong on the backlog.
