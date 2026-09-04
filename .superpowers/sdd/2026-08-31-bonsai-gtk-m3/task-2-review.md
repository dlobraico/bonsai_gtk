# Task 2 review — the click that can claim, and the focus family grows up

Range `b7484cc..919f77d` (five commits), reviewed against the plan's Task 2 text,
Global Constraints, pre-flight corrections, and the controller rulings in
progress.md. CI re-run by the reviewer at `919f77d`: **all green** (tail below),
plus one forced re-run of the live alias: green.

## Verdict: Request changes

One Important finding, and it is a documentation-level fix (a sentence in
`vtree/attr.mli`, plus a backlog bead if the controller wants a real fix later).
Everything else checked out; the minors are at the implementer's discretion.

## The discrepancy the review was asked to settle

**The true ordering is: present first, then the grab, then the map.**
`on_window_created` (which `Loop` answers with `Window.present`, src/loop.ml:26)
is called from `note_interest` *during* the mount walk
(src/patcher_fixups.ml:354); `run_fixups` — and with it `apply_autofocus` — runs
after the walk (src/driver.ml:110). So the fixup-queue grab runs **after the
present call and before the window maps**, which is exactly what the live test's
comment says (test/live/live_controllers_focus.ml, the autofocus block).

There is no conflict with pre-flight correction 5. The scout proved the *weaker*
position sticks — a grab issued before present survives the map — as a
sufficiency statement ("no post-present ordering needed"), not a description of
the implementation. The implementation lands later than that, still pre-map, and
the live golden (`autofocus at mount: e1=true e2=false` probed after `pump ()`)
pins that the grab sticks across the map. The mli says only "from the patcher's
fixup queue, after the whole tree exists", which is accurate and does not
overclaim. For windowed trees the difference is immaterial.

For `Expert.embed` the difference **does** matter, but not because of present
ordering — see Important 1.

## Important

**1. Under `Expert.embed`, a mount-frame `Attr.autofocus true` is a guaranteed
silent no-op, and the public contract does not say so.**
At `run_fixups` time in an embed's create frame the tree is parented only into
the wrapper `Overlay`, which has no `GtkRoot`. Verified against the GTK 4.22.4
source (the pinned version): `gtk_widget_grab_focus` returns FALSE outright when
`priv->root == NULL` (gtk/gtkwidget.c:5158-5161). Fire-once means the grab is
never retried, so "the entry a dialog opens with focus in" — the attr's stated
reason to exist — silently does not happen on the embed path, which is the exact
integration path the stavekeeper port uses. A later false→true flip (after the
caller has rooted the wrapper) works; only the mount-frame grab is lost.

The internal comment half-knows this (`src/patcher_fixups.ml`: rootless claims
are grouped, "the [bool] answer of [grab_focus] is dropped … Fire-once means
exactly that"), but `vtree/attr.mli`'s doc — the public contract — scopes
nothing, the headless handle happily certifies an embed tree carrying the attr
(`check_autofocus` runs under `` `Not_window`` too), no test covers it, and the
report's "four contract facts are all live-pinned" does not mention it.

Asked for: one honest sentence in `Attr.autofocus`'s mli doc (mount-frame grabs
in an embedded tree are dropped, because the grab needs a root and the embed's
tree has none until the caller parents it), and — implementer/controller's call
— a backlog bead for a real fix (e.g. deferring rootless claims to a
root-change). The rejection-grouping code itself is right and needs no change.

## Minor

**2. The headless approximation diverges from the live rule in a second,
undocumented direction.** Row 17's caveat covers the moving keyed child (path
changes → headless over-fires). The opposite direction is undocumented: a
kind-change remount at the same path with a steady `autofocus true` re-fires
live (`src/patcher.ml`'s mount comment says so, deliberately) but is no edge to
the path-keyed headless model — so a tree pairing such a remount with a second
widget's false→true flip in one frame raises live and is certified headlessly.
Same class as the documented caveat; worth a clause in row 17 / the
`autofocus_fired` comment.

**3. Three stale doc references to the deleted `key_phase_rejection`:**
`vtree/attr.mli:732`, `test_lib/bonsai_gtk_test.mli:384`,
`test/handle/test_gallery_tree.ml:283`. The code break was taken cleanly (no
callers, no shim — verified by grep); these comments now name a function that
does not exist.

**4. `Events.attr_phase` ends in a wildcard** (`| _ -> None`,
vtree/events.ml). A future phase-carrying controller attr (Task 7's shortcut
family is already planned) that is not added here silently loses its phase
instead of failing to compile. The neighbouring tables spell every constructor
out precisely to make such an addition a compile error
(test_gallery_sweeps.ml says so in as many words). Suggest spelling it out.

**5. Report wording: "the gallery entry now carries the attr".** It is the
*handle* gallery tree (`test/handle/test_gallery_tree.ml:83`) that carries
`Attr.autofocus true` — which is what the attr sweep checks — not
`examples/gallery.ml`, which does not demo the attr at all. Since
test_gallery_tree's header claims to reproduce examples/gallery.ml, the two have
now drifted by one attr. Task 12 owns the gallery/examples; fine to leave, but
the drift is worth a note there.

## Out of scope (already routed correctly)

- README's Limitations still says a click cannot be consumed — Task 13 owns it,
  as the report says.
- examples/gallery.ml demonstrating autofocus — Task 12.
- The full focus-is-state design — backlog, by the controller's own ruling.

## What was verified and held

- **Click_response / trampoline**: `dispatch_payload` calls `fire` synchronously
  inside the C callback (src/signals.ml), so `Gesture.set_state … `CLAIMED``
  really runs on the C stack while the sequence is current; the `bool` is
  dropped with a `: bool` type annotation, not a blanket ignore. The three
  no-handler paths (in-patch, empty slot, fire raised) return `declined = ()`
  and never reach `set_state` — claim nothing, M2 behaviour preserved. The
  source break was taken everywhere: no `Click_event.t Handler.t` remnants, no
  compat shim; every caller (tests, live suites, gallery example) updated.
- **live_input nested-gesture proof**: the golden's claim line shows the inner
  handler only; the Continue control shows `inner … outer b1` — inner fires,
  outer silenced under Claim only. The geometry line
  (`compute_bounds=true origin=true box-positive=true bounds-is-box=true`) plus
  `hit-aim=true in-bounds=true` in both click lines prove the horizontal-pair
  layout keeps the target on the 640x480 screen; the deviation from the plan's
  "two overlapping targets as a row" is sound and stated.
- **family_phase_rejection**: the Key message is byte-identical by construction
  (`attr_spelling` lowercases `Attr.Name.to_string`, template matches the old
  string verbatim, `controller_class Key = "GtkEventControllerKey"`) and by
  evidence — the M2 key-phase golden is untouched by the diff and CI is green.
  Walk order (Attr.Name order) makes "first two that disagree" deterministic.
  `key_phase`/`key_phase_rejection` deletion: no code caller existed (vtree is
  unreleased); the implementer's choice the plan offered, stated in the report.
- **contains-focus**: connected with `Signals.notify_connection ~prop:
  "contains-focus" fc` — the connection names the *controller*, as required;
  `fire` reads the property back off the captured controller; no `?phase`, and
  the mli says why ("a property notification fires in no propagation phase at
  all"); it does not vote in the family phase (`attr_phase` returns None), with
  a headless test pinning phaseless-beside-phased acceptance and a live golden
  pinning real focus motion and the `contains=true,enter` emission order, plus
  CAPTURE read back off the live controller and re-phase to BUBBLE on patch.
- **Autofocus contract (windowed)**: mount fires (including kind-change remount,
  per the patcher comment); the patch edge is read against the old node before
  `live.node <- node`; a removal-then-remount at the same path counts as a
  fresh mount headlessly (the fired-set is recomputed from each frame's
  requested paths, and reset per `create`); reassert-only frames never reach the
  patch code, so parked frames enqueue nothing by construction. Not a controlled
  prop is pinned by something *stronger* than the plan's parked-frame golden: a
  real patch with no edge after the user moved focus
  (`autofocus re-rendered with no flip: e1=true e2=false`). The duplicate raise
  names both paths in deterministic walk order, identical live and headless
  (`af2/0/0`/`af2/0/1` vs `root/0/0`/`root/0/1`, one `Events.autofocus_rejection`);
  `Exn.protect` empties the claims queue on the raise, and the driver's
  `abandon_fixups` covers the generic-queue-raise path. Per-toplevel grouping
  uses `Widget.get_root` + `Gobject.same`; rootless claims grouping as one tree
  is sound for the one-driver-one-tree world (Task 8 widens it).
- **require_slots on patch**: sits beside `require_specs` under the same
  non-empty-`attr_ops` guard, reads the slots built at mount — exactly the
  mount/patch asymmetry the M2 review named. The untestability claim holds: the
  check only fires on Events-table/impl drift, the registry is a closed
  exhaustive match with no injection seam from the public surface, and
  live_events.ml fails CI on drift. Accepted with the reasoning recorded.
- **Sweeps and tables**: Autofocus and On_contains_focus_changed threaded
  through every exhaustive table (Name, is_event, placement reader, attr_apply
  set/unset, gallery sweep, live controller-attr sweep with its golden row);
  the what-is-checked table gains row 17 with the path-identity caveat spelled
  out (see Minor 2 for the missing half).

## CI evidence (reviewer's own run, at 919f77d)

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

Exit 0. One additional forced re-run of
`BONSAI_GTK_LIVE_TESTS=1 xvfb-run -a dune build --force @test/live/runtest`:
green. The report's 10/10 and 5/5 stability loops were not repeated (per review
scope); the single re-run is consistent with them.

# Re-review (fix round 1)

Range `919f77d..6869497` (one commit). **Done — all four items land; nothing is
still open.** Headless suite re-run by the reviewer at `6869497`: green.

- **Important 1**: the `Attr.autofocus` mli paragraph is honest and complete —
  rootless mount-frame no-op stated, the mechanism named (no `GtkRoot` at fixup
  time; `gtk_widget_grab_focus` returns FALSE), unretried-by-design stated, the
  post-rooting false→true edge stated to work, and the real fix cited as bead
  `bonsai_gtk-vdy` (present in the export with the matching title). Doc-only per
  the controller's ruling.
- **Minor 2**: row 17 and the `autofocus_fired` comment now name both divergence
  directions (moving keyed child over-fires headlessly; same-path kind-change
  remount re-fires live with no headless edge), each with the consequence spelled
  out.
- **Minor 3**: all three stale references now say `family_phase_rejection`, with
  the key-specific prose generalised where it had to be. The one remaining
  `key_phase_rejection` mention (`vtree/events.mli:84`) is the deliberately
  historical "Generalises M2's …" provenance note on the successor's own doc —
  correct as is.
- **Minor 4**: `Events.attr_phase` is exhaustive with no wildcard, every arm
  spelled out, all newly-listed arms answering `None` exactly as the wildcard
  did — behaviour-neutral, and the diff touches no golden or expect block
  (verified: five files, docs/comments plus this one match).
- Minor 5 deferred to Task 12 by the controller — recorded, fine.
- Nothing else snuck in: the diff is exactly the five files the four items
  require.
