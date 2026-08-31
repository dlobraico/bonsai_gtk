# SDD ledger — plan: docs/superpowers/plans/2026-08-29-bonsai-gtk-m1.md
Repo /home/dlobraico/src/bonsai_gtk, branch m1 from main 9f80cd4. Spec: docs/superpowers/specs/2026-08-28-bonsai-gtk-design.md (§7 M1). Tracking epic in stavekeeper: score-library-9ob.
Standing authorization (user 2026-08-29): "do all the things bonsai_gtk would need to be used by Stavekeeper" — branch commits + local merge; pushes only for stavekeeper were authorised — ask before pushing bonsai_gtk.
Rulings: the six open questions accepted as recommended (appended to the plan).
Pre-flight scan: delegated (plan is 176 KB); result recorded below.
## Pre-flight scan (delegated, sonnet) — findings and rulings
- Ruling #1 (seal Attr.t in Task 2) is not implemented by any task; every widget matches Attr.t constructors directly. Ruling (revised): DEFER sealing to the M2 backlog; Task 11 records it in docs/m1-backlog.md. Plan's rulings section to be amended when the tree is quiet. Cost if wrong: a later API-breaking seal.
- Task 5 L2540–2553: the Live_tree sample wrongly combines GtkScale|GtkSpinButton under W.Range.get_value; the prose is right — carry to Task 5's dispatch: split the arm.
- Task 8: list_ops.insert gains ~node; the Insert and kind-changed Update branches of the op loop must pass it (plan understates) — carry to Task 8's dispatch.
- Task 9 L4772: `ctx_widget` undefined → use the mount's `widget` / `live.widget` — carry to Task 9's dispatch.
- Everything else consistent (interfaces T1→T3–9, T8→T9 file lists, controlled-value rule, ordering).
Task 1: dispatched (opus) BASE ce22d83.
Task 1: implementer DONE (14f9312); review dispatched
Task 1: complete (commits ce22d83..14f9312, review clean). Carry to Task 3: an end-to-end test that Scheduler.in_patch is true during a real patch (producer side); Task 11 must not strike the backlog line before that lands. Minors deferred: live_signals.ml:44 comment overstates (effect scheduled, not run); patcher.ml:183 comment should cite native_gtk.mli's no-unparent contract; after_of lost sibling_before's drift check.
Task 2: dispatched (opus) BASE 8381f7e.
Task 2: implementer DONE (b477828). Concerns: Kind props → named records (expect churn, promoted); widget name suppression vs type_name; opacity quantised in dumps. Review dispatched.
Task 2: review Approved with 2 Important: widget_name unset not exact (docs); Node sexp readability. Ruling: adopt [@sexp_drop_if] on default-valued prop fields NOW (before Tasks 3–9 multiply the pattern) — cost if wrong: expect-file churn once. Minors: snapshot comments say "class defaults" (creation-time); selectable+cursor_name interplay; opacity clamp doc; ellipsize live coverage; pristine label leak in a live test; backlog line 25 → Task 11.
Carry to Task 3: Widget_impl.batch (freeze/thaw) must retrofit w_label.ml. Fix round 1 dispatched.
Task 2: fix round 1/5 (commit 09f0a5a); re-review dispatched
Task 2: fix round 1/5 (3 addressed; commits b477828..09f0a5a)
Task 2: complete (commits 8381f7e..09f0a5a, review clean). Task 10 sweep: drop_if predicates duplicate Node.label defaults (consider a shared constant). Task 11: ocgtk-fork backlog item — Widget.set_name : t -> string option -> unit.
Task 3: dispatched (opus) BASE 09f0a5a — carries: end-to-end in_patch proof; Widget_impl.batch retrofit on w_label.
Task 3: implementer DONE (bc70731). Departures: in_patch e2e proof via controlled toggle through Driver.frame (Native impls have signals=[]); check_button No_children; button child-slot preservation fix; require_specs rejects event attrs on native nodes. Review dispatched.
Task 3: complete (commits 09f0a5a..bc70731, review clean). Carry to Task 4: call Signals.require_specs in Patcher.patch too (guarded on attrs changed) — §11 "mount/patch time"; rename test_widgets.ml:60's overclaiming test; comment in apply_button_props on label-vs-icon precedence. Minors deferred: w_switch set_state rationale comment; rejected node's widget not destroyed on require_specs raise (same as check_placement).
Task 4: dispatched (opus) BASE bc70731.
Task 4: implementer DONE (813bbf9). Found+fixed: patch skipped impl.update when props unchanged → controlled rule never ran (new Widget_impl.controlled flag; Task 5/7/9 must set it; Paned must not). Review dispatched.
Task 4: review Approved with 3 Important. Ruling: replace Widget_impl.controlled with an always-called `reassert : (Widget.t -> Kind.t -> unit) option` hook (unforgeable; no freeze/thaw for uncontrolled kinds) — cost if wrong: one refactor across 6 impls now. Also: toggle write-back test; set_editable ordering. Minors: require_specs guard comment; caret/IME doc; backlog: headless On_search_changed action; Live_tree collapses placeholder "". Fix round 1 dispatched.
Task 4: fix round 1/5 (commit bff0794); re-review dispatched
Task 4: fix round 1/5 (all addressed; commits 813bbf9..bff0794)
Task 4: complete (commits bc70731..bff0794, review clean). Minors deferred: w_switch create hand-rolls the active write; w_entry create/update editable position differs (inert); per-reassert batch cost.
Task 5: dispatched (opus) BASE bff0794 — carries: split the GtkScale|GtkSpinButton Live_tree arm; reassert (not a flag) for Scale/SpinButton values.
Task 5: implementer DONE (c0ba9fd). Notes: SpinButton numeric default true vs GTK false (constant dump line); exact float compare ruled; review dispatched.
Task 5: complete (commits bff0794..c0ba9fd, review clean). Minors: duplicated `page` helper; SpinButton numeric default true (constant dump line, documented).
Task 6: dispatched (opus) BASE c0ba9fd.
Task 6: implementer DONE (5ae4aa4); review dispatched
Task 6: complete (commits c0ba9fd..5ae4aa4, review clean). Coverage minors → Task 10 sweep: Resource sources, non-default Icon_size, unchanged-filename no-reload; GtkImage icon names in dumps may churn on GTK bumps (accepted per plan).
Task 7: dispatched (opus) BASE 5ae4aa4 — Expander/Revealer expanded/revealed states via reassert (ruling 2 applies: controlled like text).
Task 7: implementer DONE (e33a69b); review dispatched
Task 7: complete (commits 5ae4aa4..e33a69b, review clean). Minors → Task 10 sweep: min/max content write order (direction check); expander open+swap in one patch untested; require_specs test for the two new attrs.
Task 8: dispatched (opus) BASE e33a69b — pre-flight: list_ops.insert gains ~node; the Insert and kind-changed Update branches must pass it; Paned position NOT controlled (reassert None).
Task 8: implementer DONE (7323228); review dispatched
Task 8: review Approved with 1 Important (plan error): measure_overlay library default true vs GTK FALSE. Ruling: flip default to false (matches GTK and every Stavekeeper overlay) — cost if wrong: an Attr.measure_overlay true in the ports. Minors: node.mli reorder advice; unmeasured index comment; slot-name message. Fix round 1 dispatched.
Task 8: fix round 1/5 (commit ff8edea); re-review dispatched
Task 8: fix round 1/5 (4 addressed; commits 7323228..ff8edea)
Task 8: complete (commits e33a69b..ff8edea, review clean)
Task 9: dispatched (opus) BASE ff8edea — pre-flight: `ctx_widget` in the mount fixup is undefined → use `widget`/`live.widget`; ruling 3 (Stack name registry + fixup pass); Stack's visible child is controlled via reassert.
Task 9: implementer DONE (28b1d6b). Note: stack visible_child written by the fixup pass not reassert (ordering: reassert precedes patch_children); same-name replace in one frame raises. Review dispatched.
Task 9: review Approved with 1 Important (stack rename clobbers registry). Controller promoted a minor to a fix: Driver.frame skips the patch when Bonsai returns a phys-equal root, so reassert/fixups never run for a declined edit through the real driver. Ruling: patch every frame (drop the short-circuit) + a driver-level decline test — cost if wrong: one cheap no-op patch per frame. Minors folded: widget_impl.mli reassert=None doc; keyless page test; run_fixups skip note; grid re-attach order note. Fix round 1 dispatched.
Spec drift to note at Task 11: §5.3 table lists Grid under Slots; implementation is List + Attr.grid_cell (brief/plan choice).
Task 9: fix round 1/5 (commit 545c67d). Ruling: patch-every-frame accepted for M1; Task 11 backlog: a reassert+fixup-only walk for phys-equal roots (idle-tick cost), and spec §4.2/§4.3 must be updated (Task 11 doc sweep) — cost if wrong: idle CPU until the walk lands. Re-review dispatched.
Task 9: fix round 1/5 (all addressed; commits 28b1d6b..545c67d)
Task 9: complete (commits ff8edea..545c67d, review clean). Backlog (Task 11): same-frame stack name swap/reuse raises loudly (fold into one item); reassert-only walk for phys-equal roots; spec §4.2/§4.3/§5.3 drift.
Task 10: dispatched (opus) BASE 545c67d — sweep items: drop_if predicates duplicate Node.label defaults; Resource sources & Icon_size untested; unchanged-filename no-reload; min/max content order; expander open+swap; require_specs for on_expanded/on_revealed.
Task 10: implementer DONE (082f12a, 5db453e); review dispatched
Task 10: complete (commits 545c67d..5db453e, review clean). Owed: real-display gallery click-through (no display here); min>max scrolled bounds not rejected at the constructor.
Task 11: dispatched (opus) BASE 5db453e — backlog items collected in this ledger; spec drift: §4.2/§4.3 (patch every frame), §5.3 (Grid is List + Attr.grid_cell), §7 (Native.Picture, controlled via reassert/fixup).
Task 11: agent lost connection after committing 886b1d5 (report missing); an unrequested 'bd init' commit 58ac3d1 landed (beads scaffolding; flagged to user). Review dispatched; Task 12 CI pass dispatched in parallel.
Task 12: complete (ci.sh all green from clean tree, 30s; 25 M1 widgets + M0's 3 present; 29 constructors in the gallery). Final review after Task 11 clears.

Task 11: complete (commit 886b1d5, review Approved — every constructor count, action list, commit hash, error string and default verified against HEAD; minors: commit-message paraphrase, README Escape-hatch wording). Out-of-scope commit 58ac3d1 (bd init) flagged; user ruled 2026-08-29: KEEP — bonsai_gtk tracks its own beads from now on (not under Stavekeeper epic 9ob).
Task 12: complete (ci.sh all green, 30 s; 25/25 widgets, 29 constructors + find_by_test_id).

## Final whole-branch review (9f80cd4..886b1d5)
Split by area because the full diff is 763 KB: final-core.diff (205 KB), final-controls.diff (51 KB), final-containers.diff (43 KB), final-tests.diff (149 KB); reviewers final-core / final-controls / final-containers / final-tests (opus), reports final-<area>-report.md. Only final-tests runs ci.sh.
User rulings 2026-08-29: push bonsai_gtk to GitHub once m1 merges into main.
Final review results (reports final-<area>-report.md): no Critical anywhere. core: Approved w/ fixes (4 Important: Driver.frame raise doesn't set broken / leaves ctx.fixups; duplicate keys unchecked at mount + no path; register_stack collision on wrap-in-frame refactor (re-rated: fix now); Signals.spec disconnect object). controls: Needs fixes (search-changed debounce echoes programmatic writes). containers: Approved w/ fixes (dup keys at mount; grid re-attach drops focus + wrong comment). tests: Needs fixes (dune build -p @runtest broken both packages; headless handle bypasses require_specs; 9 kinds never patched; switcher retarget/rename untested; stack add+select same frame; prepend/move-to-0; non-window root + frame-on-stopped; css class add/remove; password/search reassert). Fix wave: agent m1-fixes on branch m1, then scoped re-review, ci.sh, merge, push.
Fix wave: complete (94d9cbc..1eeba76, 11 commits, ci.sh all green; report fix-wave-report.md). Extra: Live_tree.dump segfault on password entry without placeholder (NULL from gtk_password_entry_get_placeholder_text; nullable binding → ocgtk fork list). Deviations accepted: guarded_frame still calls idempotent mark_broken; stale-fixup test at patcher level; grid focus premise doesn't reproduce on 4.22 (restore kept as insurance, test pins behaviour); -p bonsai_gtk_test needs an install step (ci.sh installs bonsai_gtk to a temp prefix). Scoped re-review: agent m1-rereview over 886b1d5..1eeba76.
Re-review: Approved conditional on Important 1 (vacuous wrapped test) → 86224d9 keys the pair so the kind-change arm runs; mutation-verified. Round 2 ci all green.
M1 COMPLETE 2026-08-29: m1 merged --ff-only into main (HEAD 86224d9), main + m1 pushed to origin.
