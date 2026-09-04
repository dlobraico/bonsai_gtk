# Task 13 report — README, spec M3 amendments, `docs/m3-backlog.md`

Commits `a35ebec..db26888` (4): the Task 12 minors (`a35ebec`), the backlog rewrite
(`6e5c8aa`), the spec amendments (`670a438`), the README (`db26888` — the post-amend
hash; `8132f44`, this report's original citation, is the pre-amend orphan, off-branch
and red on the fmt gate). ci.sh exit 0 with `all green` after the final amend.

## The Task 12 minors first (`a35ebec`)

The autofocus stack-page reasoning moved from the report into the gallery example's own
comment; both examples' `Menu.section ~label:""` became label-less (the separator idiom —
the empty string renders an empty header row, which is what copy-paste would inherit);
examples/dune's header counts three ocgtk-free examples.

## What was read before writing

The plan's Task 13 in full plus the fork-round-3 candidate list at its bottom; the
entire ledger (all twelve entries); every review's out-of-scope section (tasks 1–12);
`docs/m2-backlog.md` complete (994 lines); the README complete; the spec's §4.1, §5.2,
§5.3, §5.4, §6.4, §6.5, §7, §8 and both prior milestones' amendment blocks for the
voice.

## `docs/m3-backlog.md` (`6e5c8aa`, step 3)

In the m2 format, with the rename note and — per the Task 1 review's carry — a header
translation table for the split files (`live_controllers.ml` → the per-family four;
`test_gallery.ml` → tree + sweeps). Contents:

- **Closed during M3**: every "do first in M3" bullet accounted for by name — nine
  closed with task cites (click claiming, contains-focus, focus `?phase` +
  `family_phase_rejection`, cursor, `Child_keys.length`, the two report-once memos, the
  `~selected` dedup, `require_slots`-on-patch, `close-request`), and the not-taken ones
  said plainly (propagation modeling, Keyval curation, the nullable behavioural half,
  the `Activate_row` revisit). The **functorise trigger** is recorded as fired and
  *promoted from declined to scheduled early-M4 motion-only* (the Task 3 ruling,
  verbatim in spirit). The other M2 carries M3 closed get their own list (Update arm,
  `on_window_created`, the splits, the `root_widget` break, the wrong paned prediction).
- **Do first in M4**: the focus model first (with `Attr.autofocus` named as the interim
  floor), the scheduled functorise, the enabled-state story for conditional chords
  (task-7 out-of-scope, placed beside targeted shortcuts as instructed there), targeted
  shortcuts, `notify::visible` popover-open reporting, the free popover, the
  named-widget registry, the gallery-twin sweep (with the stale 36/38 counts re-recorded
  against the 42-kind catalogue and the derived-count caveat), the `Activate_row`-class
  honesty revisit (noting M3 added the documented `Close_request` sibling), the nullable
  behavioural half, and the multi-driver hook slot.
- **Input residuals**, stated as one family: the M2 real-display residual (now carrying
  menus/dialogs/chords), Down+Return-never-reaches-a-popup (task-6), and the chooser's
  undrivable ACCEPT half (task-10).
- **Carried out of M3's task reviews**: the eight out-of-scope items (the
  doubly-degenerate transient string split, present-before-transient, CSS precedence,
  prefers-contrast, permanent settings connections, what the chrome smoke covers,
  `on_closed`'s direct-effect signature, handlerless-dismissal latency).
- **Carried forward from M2** as a structured digest with citations (m2-backlog stays
  the authoritative text for each — the alternative was duplicating ~300 lines verbatim;
  a deliberate deviation from a full copy, stated in the section's own preamble).
- **Tests worth adding / dump quirks / plumbing**: M2's still-open ones carried, plus
  M3's new entries (the three CSS quirks, the transient-by-title dump, the
  `GSETTINGS_SCHEMA_DIR` packaging note, `Effect.Window.present`-under-a-window-root
  unexercised).
- **The fork section**: m2-backlog's ledger remains authoritative (M3 shipped no fork
  round); the plan's round-3 candidate list is copied in as the round-3 ledger, with
  the four known round-2 carries appended and the read-the-stub rule restated.

`docs/m2-backlog.md` got strike-throughs on closures only, each naming the closing task
and pointing at m3-backlog; the functorise entry got a status note (not a strike — it is
promoted, not closed); the "Recorded during M3" section is marked swept. In-code
pointers whose cited content *moved* (targeted shortcuts ×3, the hook-slot item) now
cite m3-backlog with the right section; citations of content still resident in
m2-backlog stay.

## The spec (`670a438`, step 1)

Seven M3 amendment blocks, dated 2026-09-01, in the dated-block/measured-claim voice:

- **§4.1**: the `Windows` root (anchor ruling; `windows []` = declarative quit,
  measured), `root_widget → None` beside `Driver.windows` (model order, pinned),
  embed's unchanged rejection, and `?global_css` with the mirror
  (verified-against-`gtkcssprovider.c`). `?flags` noted still unimplemented.
- **§5.2**: the M3 attrs on both sides of the signal/controller line; focus `?phase`
  closing the section's own asymmetry; the `Click_response` source break; the
  neither-kind four (`actions`/`shortcut`/`autofocus`/`css_provider`) each with its
  ruling; `on_map`/`on_unmap` still unshipped.
- **§5.3**: the `Slots` row made real (header title is a *widget* slot — no
  title-string setter in GTK 4), pack-area identity semantics, the popover's one legal
  position with the constructor+walk backstop, the `Windows` list row.
- **§6.4**: the `Shortcut` family's no-slot/no-trampoline asymmetry, determinism and
  the disabled-chord fall-through (measured); `close-request` as the third
  synchronous-answer `Payload`, with the constant-true wrinkle.
- **§6.5**: popover `~open_` in the fixup queue, action `enabled`/`state` against the
  GAction read-backs, `~transient_for`; **the close ruling written as the
  controlled-prop story**, with the M2 behaviour change named and the README pointed at.
- **§7**: M3 marked *done* — the shipped list, 42 constructors sweep-checked,
  twenty-nine actions, chrome.ml as the milestone's counter — plus the four details the
  section did not anticipate (both dialog contingencies, the actions-not-closures
  shortcut design and why it turned out right, the overruled-in `autofocus`, the
  slot-only popover). The out-of-scope note's display-wide-CSS clause updated to done.
- **§8**: the shipped-vs-list accounting — `Clipboard.get_text` and
  `Window.close`/`set_title` unshipped with the reasons the mlis carry, `?cancel`
  making the alert total (DELETE_EVENT −4, measured), both contingencies fired, and the
  two mechanics §8 under-specified (respond_to running the continuation; the dialog
  keep-alive tables).

## The README (`db26888`, step 2)

(Heading hash corrected in the fix wave: this section originally cited `8132f44`, a red
off-branch orphan left by an amend and not bisect-reachable; `db26888` is the real
step-2 commit, as the ledger's Task 13 entry records.)

Status/tables/counts to M3 (42 constructors, 21 signal attrs, 7 controller attrs over
four families, 29 actions); new Chrome and Window table rows; new **Effects** and
**CSS** sections; the Input section gains claiming clicks, the contains-focus query and
the shortcut family (untargeted, accel-display-vs-installation, disabled-chord
fall-through); the headless section's action table gains the M3 row and the validation
list covers everything the handle now rejects (including the M2 table's omission of
`Set_revealed`/`Set_position`/`Set_visible_child`, fixed in passing).

**Limitations rewritten**, migration note first: *the close button is vetoed* — an M2
app without `Attr.on_close_request` has an inert X button; the one-attr fix shown, the
multi-window alternative stated, and the desync rationale in two sentences. The input
residual paragraph now covers menus/dialogs/chords plus the two
unreachable-even-on-Xvfb inputs; the focus-model gap leads the Input limitations; the
stale on_click/contains-focus/cursor items are replaced by what shipped; not-bound-yet
now says free popover / clipboard read / menubar / initial folders. Every backlog
pointer moves to m3-backlog (m2-backlog named once, as the M2 record). The verbatim
counter example includes its new close handler.

## Verification and process

- ci.sh **exit 0, `all green`**, checked by real exit code — because the first run after
  the doc commits was *not* green: my last direct `attr.mli` edit had an unpromoted
  ocamlformat rewrap, and the `tail -1` pipeline masked it exactly as it had once
  before. Caught by re-running un-piped, formatted, and amended (producing `db26888`;
  local, minutes old). The docs build is `dune build @all` per the plan's step 4; there is no
  doc toolchain, so the reviewer proofreads.
- Headless suite green throughout (the retargeted comment pointers touch three vtree
  files and one test comment; no goldens moved).

## Deviations

1. The "Carried forward from M2" section digests rather than copies the ~60 still-open
   M2 minors (citations intact; m2-backlog remains their authoritative text). The full
   copy would have been ~300 lines of drift-prone duplication; the m2 file is one hop
   away and now clearly marked as the M2 record.
2. Backlog pointers inside code comments were retargeted only where the cited content
   moved; m2-backlog citations for still-resident content stand (the file is not going
   away).
3. `docs/m3-backlog.md` also absorbs the plan's fork-round-3 list verbatim-in-substance
   rather than by reference, per step 3's "the fork section below copied in as the
   round-3 ledger".

## Fix round 1

task-13-review's five items, one commit: the `bonsai_gtk-vdy` embed-autofocus hole
named in the M4 focus bullet (I1); this report's range and final hash corrected to
`a35ebec..db26888` with the red off-branch `8132f44` orphan called what it is, and the
eight-vs-nine count fixed (I2, above); the menubar given its backlog home in the fork
round-3 list with the task-6 disposal's error stated (M1); the four line-range
citations refreshed against the file's *final* layout — including the +3 shift the M3
strike itself introduced, and `child_keys.mli`'s citation retargeted to the entry its
sentence actually describes (the `Child_keys` entry; `158-166` never pointed there)
(M2); and the synthetic-click Do-first bullet struck, attributed to M2's own
`xtest-input` close-out (M3). ci.sh exit 0, `all green`, real exit code checked.
