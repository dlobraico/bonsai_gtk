# Task 11 review — display-wide CSS, and `Attr.css_provider`

Range `0417419..ccbea26` (46f85c0 the Task-10 minors, 55cc710 the implementation,
ccbea26 live_css + census + gallery smoke), reviewed against the plan's "### Task 11",
task-10-review.md's two Minors, the ledger, and task-11-report.md. Claims verified
against the code, the pin's sources in `.ocgtk-src/`, GTK 4.22.4's own
`gtkcssprovider.c` (unpacked from the nix store), and a throwaway probe run under xvfb
at the pin (built in the session scratchpad, not the repo).

**Verdict: APPROVE the implementation — the ephemeron, the mirror, and the threading
are all sound, and the endorsed color-scheme deviation is correctly built — with three
Importants, every one documentation/test-pin scale (no code path is wrong), routed per
series convention to the Task 12 start.**

## The assigned scrutiny, point by point

**1. The mirror (`Global_css.install`).** Sound.

- *Connection lifetime*: the two `notify::` connections on the default `GtkSettings`
  are never disconnected — but each closes over its own provider, so a second
  `start` (or a second embed with css) gives two providers each mirroring the same
  settings value onto *itself*: no fighting, just N independent copies of the same
  write. The leak is bounded at one provider + two connections per install, and the
  impl comment says exactly this ("the connections close over the provider, so an
  installed provider lives for the process — exactly the accumulate-and-keep contract
  above"); `global_css.mli` carries "Never removed". So yes, the
  accumulation-documented-not-engineered stance covers the settings connections too —
  in the *internal* mli (see Important 2 for where it does not appear).
- *C-called-frame guard*: the notify callbacks run `mirror ()` under `try`, report via
  the doctrine's named eprintf, and the eprintf itself is swallow-guarded. Verbatim
  the trampoline shape. `connect_simple` discards argv in its closure
  (`gobject.ml:174`), so notify's GParamSpec argument is safely ignored, and it goes
  through `g_signal_connect_closure`, which accepts the detailed `notify::<prop>`
  names.
- *Enum mapping*: "default" mirrors to `` `DEFAULT``, and GTK 4.22.4's source settles
  that this is exactly right: `gtkcssprovider.c:558-568` evaluates
  `DEFAULT`/`LIGHT`/`UNSUPPORTED` all as media-feature value `"light"` — so light
  blocks are NOT dead under `DEFAULT`, and `DEFAULT` vs `LIGHT` is a distinction
  without a difference for query matching. The live pin covers the
  default→dark→default round trip at the property level; my probe additionally
  confirmed the *evaluation* round-trips (to_string shows the light block, then the
  dark block, then the light block again — GTK re-parses the stored source on every
  property change, `maybe_rerender_style_sheet`, `gtkcssprovider.c:911`).
- *Install order*: `load_from_string` before `mirror ()` before `add_provider` — the
  source bytes exist for the re-parse, and the provider joins the display already at
  the right scheme. No flash.

**2. `Attr.css_provider`'s ephemeron.** Sound, including the part I went in
expecting to find broken.

- *Key hygiene*: keyed on the widget with `equal = Gobject.same`,
  `hash = Stdlib.Hashtbl.hash`. This pairing is consistent *by the pin's design*: the
  gobject custom block installs a pointer-compare and pointer-hash
  (`wrappers.c:146-174`, `compare_gobject`/`hash_gobject`), and `Gobject.same` is the
  same pointer equality — so two distinct OCaml wrappers of one GObject hash and
  compare equal, and the polymorphic hash the ephemeron uses agrees with `same`.
  Pointer reuse cannot alias entries: while a wrapper (the key) is uncollected it
  holds a ref (finalize unrefs), so the C address cannot be recycled under a live
  entry.
- *Two widgets, same CSS string*: one provider each — the table is keyed per widget,
  and `set_css_provider`'s fresh-arm runs per widget. Correct.
- *Unset*: `remove_provider` on `Widget.get_style_context w` — the same context the
  add used — then `Css_providers.remove`. Absence-is-exact holds (no snapshot field;
  the un-styled state is no provider), and the live suite pins `no provider` after
  the unset plus a *fresh* provider (`not (Gobject.same …)`) after the re-add.
- *Widget destroyed with the attr applied*: unset never runs; the entry lives until
  the widget wrapper is GC'd, then the K1 ephemeron drops it, the provider wrapper
  becomes unreachable, and `finalize_gobject` unrefs it (under the
  finalizer-depth guard, so a dispose cascade cannot re-enter OCaml). GTK's style
  context held its own ref while the widget lived. Bounded; rides the ephemeron out.
- *Identity across reload*: found-arm reloads the same provider;
  pinned live with `Gobject.same` across a string change.

**3. Invalid CSS.** "Never raises" is true and tested with genuinely invalid CSS; the
parsing-error signal is unbound, and GTK's *default class handler* g_warnings to
stderr when no handler is connected (`gtkcssprovider.c:205-231`) — my forced run and
probe both show the three messages (one "Theme parser error", two warnings), so an
author can debug. **But the mli's "keeps the previous ruleset" is false** — see
Important 1.

**4. `?global_css` threading.** `start` installs in activate's first-activation arm,
before the driver — and the stub's own mli confirms `add_provider_for_default_display`
"Raises `Failure` if GTK has no default display yet", so activate is the first legal
moment; under xvfb the ci smoke (gallery now passes `~global_css`) exercised exactly
this path, green. `embed` installs at create under the caller's-GTK-up contract; the
default-display-only honesty is stated in `embed.ml`'s comment and `global_css.mli` —
in-tree, but nowhere a user of the public API looks (Important 2). Priority is
`priority_application` (600) for both halves. What beats what between the global
provider and a per-widget attr provider at equal priority is stated nowhere; I did not
establish GTK's cross-cascade tie-break from source and the docs don't claim one —
authors get specificity, which is the honest tool anyway (out-of-scope note 7).

**5. The x-display lock.** Census verified by count: 21 `(alias runtest)` rules,
17 real `(locks x-display)` occurrences (19 grep hits minus the two inside the header
comment); ci.sh's comment matches ("seventeen of the twenty-one"). The lock on a
suite that presents nothing is right — its global half mutates the default display's
`GtkSettings`, and live_css.ml's header says so. But the *dune header's* taxonomy —
where Task 4's fix put the conservative-lock reasoning — still reads "every one whose
executable presents a toplevel, plus the two dump-only suites (`live_containers`,
`live_chrome`)": live_css is neither, so a reader counting by the stated rule gets 16
and the header says 17 (Minor 4).

**6. Structural honesty.** The golden header states plainly that everything is
structural and why (no computed-style read-back in the pin — verified: the probe
surface is `Css_provider.to_string` + the property getters; nothing else exists).
The mirror pin observes `get_prefers_color_scheme` — i.e., reads back the very value
the mirror wrote, plus proves the notify plumbing fires synchronously. Nothing in the
suite proves the media query *consumes* that property. My probe shows a stronger
structural pin was available for one line: setting the property re-parses the source
synchronously, so `to_string` after the dark flip shows the dark block's rules where
it previously showed none (and the golden's own global dump already silently depends
on this — the `@media` block is absent from it precisely because to_string is
scheme-evaluated). One extra `to_string` dump after the flip would prove the
query-evaluation consequence, not just the property write (Minor 2).

**7. The deviations.** All four judged on the merits, all fine:
new `src/global_css.ml(i)` is the right call (loop and embed share it and cannot
depend on each other; the plan's file list simply didn't anticipate the sharing);
default-display-only is *more* honest than the plan's "caller's display"
parenthetical (the stub reaches nothing else — its mli says so); the
`Attr_apply.live_css_provider` probe is the only read-back that exists;
the mirror itself was endorsed and is correctly built (point 1). And 46f85c0 is
exactly the two Task-10 Minors: both trampoline bodies under their own
report-then-swallow `try`, both dialog mlis carrying the shown-dialog-at-stop
sentence. Diffstat contains nothing else.

**8. Runs.** ci.sh at ccbea26 by this review: exit 0, tail `all green` (sections:
nix pin, format, build, opam files, pure+headless, per-package, live (xvfb), example
smoke; only the usual libEGL noise). One forced live re-run
(`rm _build/default/test/live/output_css.txt` + `BONSAI_GTK_LIVE_TESTS=1 xvfb-run -a
dune build @test/live/runtest`): exit 0, 0-diff, and live_css demonstrably re-executed
(its invalid-CSS parser warnings are in the captured stderr).

## Findings

### Important

1. **`Attr.css_provider`'s mli claims invalid CSS "keeps the previous ruleset" — it
   does not.** GTK clears on every load (`gtk_css_provider_load_from_bytes` calls
   `gtk_css_provider_reset` before parsing, `gtkcssprovider.c:1727`; the binding's own
   mli for `load_from_string` says "This clears any previously loaded information"),
   and the probe confirms it: valid `margin: 7px` load, then the suite's own invalid
   string, and `to_string` returns *empty*. So a frame that changes the attr to an
   invalid string silently strips the widget's styling — never-raises holds, but the
   documented recovery story is the opposite of the real one. Fix is one sentence in
   `vtree/attr.mli` (and the live suite should dump the provider after its invalid
   load — that one line would have caught this; see Minor 2). The same wrong sentence
   is in 55cc710's commit message; the report avoided repeating it.

2. **`?global_css` is invisible in the public documentation.** The plan said "note it
   in the mli rather than engineering removal"; the accumulation note, the
   default-display-only limit, the activate timing, the priority, and the entire
   color-scheme mirror behavior all landed in `global_css.mli` — a `Private`
   no-stability module — and in impl comments. `bonsai_gtk.mli`'s `start` doc,
   `Expert.embed`'s doc, and `embed.mli`'s `create` doc gained only the parameter
   line: a user cannot learn what `?global_css` does, that dark `@media` blocks work
   (the mirror is a *feature* — currently a secret one), that a second start re-adds
   a provider, or that embed styles only the default display, without reading
   private source. A short paragraph on `start` (with `embed` deferring to it) closes
   this.

3. **The mirror's own rationale applies verbatim to `Attr.css_provider`, and nothing
   addresses it there.** Per-widget providers are left at `` `DEFAULT``, so a dark
   `@media` block in an `Attr.css_provider` string can never match — exactly the
   "dark blocks silently dead" disease the report says justified the global mirror
   ("Without the mirror, `?global_css` would ship with dark blocks silently dead").
   The attr half of the same task ships with them dead and undocumented. Decide one
   way: either a sentence at `Attr.css_provider` ("media queries in a per-widget
   sheet evaluate against this provider's own unset preference — effectively always
   light; put scheme-dependent styling in `?global_css`"), or mirror these providers
   too (heavier: per-provider writes on the same two notify signals — the ephemeron
   would need iteration). The documentation sentence is the proportionate fix; the
   review only asks that the inconsistency stop being silent.

### Minor

4. **The dune header's lock taxonomy no longer derives its own count.** It says
   seventeen carry the lock because "every one whose executable presents a toplevel,
   plus the two dump-only suites" — live_css presents nothing and is not one of the
   two named suites; its (different, good) reason lives only in live_css.ml. One
   clause in the dune header ("plus `live_css`, which presents nothing but mutates
   the default display's `GtkSettings`") restores the header as the place where the
   lock reasoning lives, per Task 4's convention.

5. **The mirror pin proves the write, not the consumption.** One `to_string` dump
   after the dark flip would show the dark block's rules materialising (and vanishing
   after the flip back) — the strongest structural proof available in the pin, and
   the probe confirms it works synchronously. Pairs with the Important-1 fix: a dump
   after the invalid load pins the actual (cleared) post-invalid state.

6. **Only the fallback knob is exercised live.** `set_gtk_interface_color_scheme` is
   bound (`settings.mli:242`), so the primary arm of `scheme_of_settings` (`` `DARK``
   /`` `LIGHT`` from the interface-color-scheme setting, and its precedence over
   prefer-dark) and the first of the two notify connections are both reachable in the
   suite — today neither ever runs. Two lines in live_css's global half.

### Out-of-scope / of record

7. **Global-vs-per-widget provider precedence at equal priority is unstated** — and
   this review did not establish GTK's cross-cascade tie-break from source either.
   Authors resolve conflicts with selector specificity regardless; a doc sentence is
   only worth writing if someone first pins the truth. Backlog-grade.

8. **The settings connections are permanent by design** — bounded per install,
   consistent with the accumulate-and-keep contract, documented internally. No action
   beyond Important 2's public surfacing.

9. **`prefers-contrast` unmirrored** — deliberate, report says so, the enum and
   setters are bound if ever wanted. No action.

10. **"Written first, failing" for live_css** is process narrative the commit range
    cannot show (suite commit lands after the implementation commit, per the branch's
    squash convention) — same note as the Task 9 and 10 reviews, for the record.

## Process

Tree left as found (the untracked SDD reports and the bd-hook's `.beads/issues.jsonl`
delta predate this review; this file is the review's one addition, following the
series convention). No commits, no pushes, no bd operations. Builds one at a time in
this checkout: ci.sh once at ccbea26, then the forced live re-run, then the probe
(built and run in the session scratchpad against the pin, not in the repo).
