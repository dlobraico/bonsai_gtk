# M3 ledger — chrome & popups

Branch `m3` from `main` (= `c2580b5`, pin `72cc75f2`). Plan:
`docs/superpowers/plans/2026-08-31-bonsai-gtk-m3.md` (committed `4cfa12d`; pre-flight
corrections folded in). Epic `bonsai_gtk-0d0`. Protocol: per task one implementer → one
reviewer → fix rounds → scoped re-review; final whole-branch review by four lenses
(core / chrome / menus-and-input / tests) → fix wave → re-review → ff-merge → push.

## Controller rulings at plan time (2026-08-31)

Accepted from the planner: close-request always-veto (examples gain handlers; README
migration note); Popover only as menu_button's slot; Effects deviations from spec §8
(no Window.close/set_title, no Clipboard.get_text, Alert ?cancel); on_click re-typed to
Click_response (source-breaking, taken now); menu/shortcut names that resolve to nothing
raise at fixup; `Node.windows []` = declarative quit.

Overruled: "no focus story". Task 2 gains `Attr.autofocus` — fire-once fixup-queue grab
on mount or false→true, at most one per frame per toplevel, NOT a controlled prop —
because the plan's own "palette.ml is portable" claim requires an entry you can type
into, and keyboard-first UX is a standing user preference. Full focus-is-state design
stays on the backlog.

## Task log

(One entry per task: verdicts, rulings, carries.)

### Task 1 — file splits + paned golden debt: APPROVED
413b415..ac7ca30 (4 commits) + controller fix `README.md` (review M1, one line).
Review: motion proved pure (mli untouched, definitions land per plan, goldens
byte-identical by concatenation/multiset, rename sweep comment-only). Deviations
accepted: patcher.ml 747 lines (the walk is one mutual let-rec — splitting it is not
motion), sweeps 608. Ruling of record: the backlog's paned-golden prediction was wrong —
no existing golden had a droppable None; one new `(position ())` golden pins the drop
removal. Carry for Task 13: docs/m2-backlog.md's five live_controllers.ml refs translate
in the rewrite (review Out-of-scope note). Update kind-change comment still in
patcher.ml's patch_list, awaiting Task 8.

### Task 2 — claimable click, focus family, autofocus: APPROVED (after fix round 1)
b7484cc..919f77d (5 commits) + fix round `6869497`. Review settled the ordering
question: present happens during the mount walk, the grab in fixups after it; pre-flight
5 proved sufficiency of the weaker ordering, not the implementation. Important 1: the
mount-frame autofocus grab is a rootless silent no-op under Expert.embed — RULED doc-only
for M3, real fix filed as bead `bonsai_gtk-vdy` (map/notify::root retry candidate).
key_phase_rejection deleted (no external caller). require_slots untestability accepted
with reasoning. Carries: gallery tree vs examples/gallery.ml drifted by one attr —
Task 12 reconciles (review Minor 5); Events.attr_phase now exhaustive so Task 7's
phased attr must add its row explicitly.

### Task 3 — report-once memos, Child_keys.length, caret: APPROVED
028d150..accd8d9 (4 commits) + comment-minors folded into the Task 4 start. Review
verified one memo shape serving both twins (Refusal functor), dedup safe by construction
(duplicate sibling keys already raise), the Flow_box mutation now caught by golden
(reviewer re-applied it), and the controlled-write caret restore suppressed by the patch
guard with the golden's numbers each mapped to a cause. Bench correction of record: the
report's ~13x parked-frame figure did not reproduce (reviewer: ~1.1x, noise-bound);
conclusion (negligible, scales with page count, nothing accumulates) stands — do not
quote 13x. RULING (standing trigger): the ~selected dedup is the confirmed third copy of
the list-pair shape; functorise as an early-M4 motion-only task, promoted from declined
to scheduled in Task 13's backlog rewrite — not in the fix wave (no churn under the
lenses' feet), not in Task 13 itself. The new both-copy goldens are the safety net that
makes that motion cheap.

### Task 4 — HeaderBar + ActionBar: APPROVED
629ae6a..6749003 (task-3 minors + task + lock bookkeeping) + doc-minors folded into the
Task 5 start. Review confirmed: slots shape loud and ordered; within-area reorder is
silently-insertion-order-with-identity as the mli says (pinned in test_reconcile +
live_containers); `revealed` plain is right (GTK sets it synchronously, animation is the
internal revealer's business); coverage mechanism real; both deferrals recorded in-tree.
Minors to the Task 5 start: node.mli:1451's move=None precedent citation inverted
(list_box is ordered — cite overlay); the live dune header's presents-a-toplevel sentence
false for two dump-only rules + conservative-lock reasoning nowhere in-tree; cross-area
pack move = remove+insert identity loss undocumented (+ optional two-line cross-area
duplicate-key pin); live_chrome identity-survival comment overclaims (real pins are
test_reconcile + sweep 1U). Carry: examples/gallery.ml still lacks the new kinds —
Task 12 (existing carry, reconfirmed).

### Task 5 — MenuButton + Popover: APPROVED (after fix round 1)
eabcd47..aca5db6 (task-4 minors + headless + live) + fix round `f268f39`. Rulings of
record: controlled ~open_ lives in the FIXUP QUEUE (parenting precondition; converges in
one write, no memo needed — reviewer verified all three pass coverages and the guard);
the focus-repair connection rides w_popover's spec list (teardown traced clean incl.
destroy-with-open-popover); Popover legal only in the slot, non-Popover kinds rejected at
the constructor AND the shared walk (smuggling test proves the backstop). Importants
closed: the slot type hole; the focus-repair overclaim tempered — what is proven is the
plain-popover Escape chain.
CARRIES FOR TASK 6 (named, mandatory): (a) re-prove the F1-afterward/focus-not-stranded
line after REAL menu item activation on GtkPopoverMenu (the stavekeeper bug's actual
trigger; viewer_window.ml:750-797) and design the fallback if the synchronous repair
misses (one-shot idle may be short — stavekeeper needed 60ms×8); (b) user-open reporting
via notify::visible is recorded in m2-backlog "Recorded during M3" — Task 13 sweeps it.

### Task 6 — Actions + Node.menu: APPROVED (after fix round 1)
681c5dd..a79981a (headless + live) + fix round `bc0adc6`. The riskiest design landed as
planned: Menu pure data, Action_spec carries handlers, one group per node, resolution one
vtree function raising one string from wrappers AND handle (sibling non-resolving,
across-frames raises). Measured facts of record: an in-place menu edit RE-BINDS the item
tracker (rows built before a late group stay insensitive; after, bind — goldened); GTK's
muxer UNIONS same-scope groups with ancestor fall-through, matching the union env
exactly; activate_action_variant is the routing (get_action_group is GTK3-only).
Task 5 carry (a) PROVEN — and it found the real gap first: a ~menu button's PopoverMenu
is GTK-internal, so the spec-borne repair never connected there; w_menu_button now
connects the repair to the internal popover's closed (forget_menu release hook, dispose
rule traced). Synchronous repair suffices after real item activation — no idle fallback.
Consumer mapping total: Command.Registry {id;label;accel;scope;enabled;run} →
Action_spec + Menu.Item + Attr.actions ~scope, doc completed in the fix round.
CARRY FOR TASK 13 (review M4): the Down+Return residual — WM-less Xvfb never gives a
popup surface X focus, so no keyboard path reaches any popover menu (Escape works only
via the toplevel's own grab); belongs beside the M2 input residual in the rewrite.
