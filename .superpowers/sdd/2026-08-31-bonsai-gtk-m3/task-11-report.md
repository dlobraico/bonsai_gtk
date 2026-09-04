# Task 11 report — display-wide CSS, and `Attr.css_provider`

Commits `46f85c0..ccbea26` (3): the Task 10 review minors (`46f85c0`), the
implementation (`55cc710`), the live suite + census (`ccbea26`). ci.sh green; the css
suite forced 2× clean after its golden landed.

## The Task 10 minors first (`46f85c0`)

Both `on_response` trampoline bodies (the remove/destroy/read-back chains) now run
under their own `try` with the doctrine's named eprintf on catch — no-raise-into-C is
syntactic, not argued. Both dialog mlis state the shown-dialog-at-`Driver.stop` story:
it stays up, resolves whenever answered under the dropped-hooks contract, and leaks
nothing (the response empties the table either way).

## What changed (`55cc710`)

**`Attr.css_provider : string -> t`** — a plain string attr (equalable, diffed frame to
frame) whose provider object is the runtime's. The state lives in `attr_apply` as an
ephemeron keyed weakly on the widget — §2.2: the provider must live exactly as long as
the widget, and `attr_apply` had no per-widget state anywhere else so the table lives
there. Set on a fresh widget = `Css_provider.new_` + `load_from_string` +
`Style_context.add_provider` at application priority (the deprecated-since-4.10,
functional-in-4.22, only-per-widget path — the mli says so per the plan); a changed
string = `load_from_string` on the **same** provider (GTK restyles; identity pinned
live); Unset = `remove_provider` + drop, with no snapshot field — the un-styled state
is the absence of the provider, and removing it is exact. The mli also carries a
scoping note (the style context is consulted for descendants too; key the selectors
with a `css_class`).

**`?global_css` on `start` and `Expert.embed`** — both call the new
`src/global_css.ml(i)` (`Global_css.install ~css`), one small internal module because
loop and embed share the code and neither can depend on the other (a deviation from the
plan's modify-only file list, noted). `install` = provider + `load_from_string` +
`Style_display.add_provider_for_default_display` at `priority_application`. `start`
installs at activate — `add_provider_for_default_display` raises before GTK init, so
activate is the first legal moment (the plan's own note); `embed` installs at create
(its caller's GTK is up by contract). The plan's "caller's display" parenthetical
overstates what the stub reaches: it is default-display-only, said in embed's comment.
Accumulation on a second `start` (or two embeds with css) is documented in the mli, not
engineered away, per the plan. `gtk_import` gains the `Style_display` alias (top-level
`Ocgtk_gtk.Style_display`, not under `Wrappers` — the fact-table trap, noted at the
alias).

**The color-scheme mirror — the flagged addition.** The plan is silent on
`prefers-color-scheme`; the team lead asked me to check and flag, and the flag's
resolution is implemented rather than documented-away, deliberately: GTK 4.20+
evaluates `@media (prefers-color-scheme)` **per provider**, against that provider's own
`prefers-color-scheme` property, and GTK syncs only its own theme provider with
`GtkSettings` — an application provider left at `` `DEFAULT`` can never match a dark
block, whatever the desktop says (the stavekeeper `Theme.install` lesson, verified
downstream on 4.22 — the very GTK this repo pins, 4.22.4). Without the mirror,
`?global_css` would ship with dark blocks silently dead. `install` mirrors
`gtk-interface-color-scheme` (falling back to `gtk-application-prefer-dark-theme`, the
older knob) via `set_prefers_color_scheme` — all bound in the pin — and re-mirrors on
both properties' `notify::` (`connect_simple` takes detailed names), guarded like every
C-called frame. Owned by the runtime so no port carries `Theme.install` again — the
same argument that put the popover focus repair behind the API. **If the review wants
this out, it is one isolated function in one commit.**

## What the tests prove (`ccbea26`)

`live_css.ml`, `(locks x-display)` — not for a toplevel (it presents none) but because
its global half mutates the default display's `GtkSettings`, which would restyle a
neighbour suite mid-run; census seventeen of twenty-one, ci.sh comment matches. The
header says why everything is structural: the pin binds no computed-style read-back
(the plan's step 1 asks for exactly this statement). Pins:

- the provider's own `to_string` holding each css it was handed (GTK's normalized
  form — margins expanded four ways — which also proves the load really parsed);
- **same provider across a string change** (`Gobject.same`), fresh provider after an
  unset round trip, `no provider` after unset;
- an invalid stylesheet not raising (GTK's three parser warnings go to its log, not
  the golden);
- the mirror: scheme `default` as installed under xvfb, `dark` after
  `set_gtk_application_prefer_dark_theme true` (through the notify re-mirror,
  synchronously), `default` after flipping back — read off the very property the media
  query is evaluated against.

Census: the gallery tree's Input-page frame carries the attr (`Attr.Name.all` sweep),
sweeps' `action_for` gains the non-event arm, `test_placement`'s count is 50,
`test_events`' plain-names golden gains the name. `examples/gallery.ml` gains
`~global_css` so the ci smoke exercises the activate-time install (step 3).

## Deviations

1. **The color-scheme mirror** (above) — additive, flagged, isolated.
2. **`src/global_css.ml(i)` is a new file** the plan's file list did not name — shared
   by loop and embed, which cannot depend on each other.
3. `Attr_apply.live_css_provider` added as the live suite's structural probe (the
   "style context read-back where bound" the plan gestures at does not exist — there is
   no provider-enumeration API in GTK at all — so the probe is the runtime's own table
   plus `Css_provider.to_string`).
4. The plan's "one visual-truth line if Snapshot/render read-back exists" — pre-flight
   said it does not; the golden header says structural-only, as instructed.

## Deliberately not done

- No provider removal on a second `start` (documented accumulation, per the plan).
- No per-display story for embed (the stub is default-display-only; said in-tree).
- No `prefers-contrast` mirroring (bound, but nothing asked; one line beside the
  scheme mirror if ever wanted).

## ci.sh

`all green` with everything in tree; the two forced live re-runs after the golden were
0-diff. The bd hook's `.beads/issues.jsonl` delta remains uncommitted.
