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
