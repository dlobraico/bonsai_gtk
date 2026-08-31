# Final review — M1 controls & media widgets

Scope: `src/widgets/w_button.ml`, `w_toggle_button.ml`, `w_check_button.ml`, `w_switch.ml`,
`w_entry.ml`, `w_password_entry.ml`, `w_search_entry.ml`, `w_spin_button.ml`, `w_scale.ml`,
`w_progress_bar.ml`, `w_spinner.ml`, `w_image.ml`, `w_picture.ml`, `w_separator.ml`,
`src/paintable_picture.ml(i)`, at `886b1d5`. Read-only; no build was run.

Items already in `docs/m1-backlog.md` are not re-reported.

## Summary

The fourteen widgets are unusually consistent for a set this size. Every controlled prop
(`Toggle_button.active`, `Check_button.active`, `Switch.active`, the three entries' `text`,
`Spin_button.value`, `Scale.value`) is written on `create` *and* re-applied from `reassert`,
every `*_if_needed` helper compares against the live widget rather than the previous node,
and every one reads the property the user actually manipulates. Ordering is right where it
matters: bounds before value on both numeric kinds (`w_spin_button.ml:73-74` then the
reassert at `:88-94`; `w_scale.ml:72-73` then `:85-91`), text last on the entries'
create path, `set_digits` before the value on both. Uncontrolled kinds correctly declare
`reassert = None` — a progress bar, spinner, image, picture and separator have no user input
to decline. Handler lifetime is sound: `connect_all` runs after `create`, so creation-time
writes cannot reach a handler at all, and every spec connects on the same GObject that
`Signals.disconnect` is later called with, including the `GtkEditable` interface specs.
Image and Picture both short-circuit an unchanged source, which `test/live/live_containers.ml:120-145`
asserts by paintable identity, and `Native.Picture`'s per-frame-texture path — the Stavekeeper
case — is asserted end to end at `live_containers.ml:87-118`.

One real defect: `GtkSearchEntry::search-changed` is emitted from a GLib timeout, so the
`in_patch` reentrancy guard — which is synchronous by construction — does not cover it, and
a programmatic text write fires the application's handler ~150 ms later. Everything else I
found is a consistency or documentation gap.

## Critical

None.

## Important

### 1. A programmatic write to a `Node.search_entry` fires `Attr.on_search_changed`, because the debounce outlives the patch guard

`src/widgets/w_search_entry.ml:8-18` (the spec), `:33` (create), `:50-57` (reassert);
`src/scheduler.ml:41-44`, `src/driver.ml:70-79`, `src/signals.ml:19-20`.

The M1 convention is that programmatic writes happen with `Scheduler.in_patch` set so the
signals GTK emits during a patch are swallowed. That works for every other spec in this
area because every other signal here is emitted *synchronously* from the setter —
`toggled`, `notify::active`, `changed`, `value-changed` all reach `Signals.dispatch` while
the stack is still inside `Scheduler.with_patch_guard`. `search-changed` is not. GTK
4.22.4's own GIR is explicit:

```
<glib:signal name="search-changed" when="last">
  Emitted with a delay. The length of the delay can be
  changed with the [property@Gtk.SearchEntry:search-delay] property.
```

with `search-delay` defaulting to 150 ms. The emission comes off a `g_timeout` source armed
by `GtkSearchEntry`'s own `GtkEditable::changed` handler, which does not distinguish who
wrote the text. So `W_entry.set_text_if_needed` at `w_search_entry.ml:33` or `:56` arms the
timeout inside the patch, the guard is released when `Driver.frame` returns, and the
callback runs with `ctx.in_patch () = false`. `Signals.dispatch` then finds a populated
slot and `fire` reads the text back off the widget — the text the *library* just wrote.

Failure scenario. A model that normalises what is typed:

```ocaml
Node.search_entry ~attrs:[ Attr.on_search_changed (fun s -> set_query s) ] ~text:model.query ()
(* set_query uppercases *)
```

1. User types `ab`. 150 ms later `search-changed` fires (outside any patch, correctly) →
   `set_query "ab"` → model holds `"AB"`.
2. Next frame, `reassert` writes `"AB"` into the widget. The guard swallows `changed`, as
   designed — but the write arms a fresh debounce.
3. 150 ms later `search-changed` fires again, with `"AB"`. The application sees a second
   search event that no user action produced.

For an idempotent handler this settles after one extra round; for a handler with a side
effect it is one spurious effect per programmatic write — a redundant store query, a second
entry in search history, a results pane re-opened after the user dismissed it. A
non-idempotent model (one whose normalisation is not a fixed point) does not settle at all
and oscillates at the debounce interval. The same fires for the "clear the search box from
elsewhere in the UI" case: rendering `~text:""` produces a `search-changed ""` that the user
did not ask for.

`Node.search_entry`'s doc (`vtree/node.mli:163-176`) describes `on_search_changed` as firing
"`search_delay` ms after typing stops", which is precisely the assumption that breaks —
nothing there or in `w_search_entry.ml` acknowledges that the delay defeats the guard. The
existing coverage does not catch it: `test/live/live_controls.ml:79-83` and
`test/test_gallery.ml:75-76` only attach the attr, and the headless
`Bonsai_gtk_test.Action.t` has no `Search_changed` (the known-deferred item), so no test
drives this signal at all.

The fix is not the guard — a synchronous flag cannot cover a deferred emission. The shape
that works is to record on the live widget the text the library last wrote and have
`search_changed`'s `fire` return `None` when the widget's current text still equals it, so
only a text the user produced reaches Bonsai. (Blocking the debounce by writing through
`GtkText` directly, or by resetting `search-delay` around the write, is not available:
`gtk_editable_set_text` is the only way in and the timeout is private.) Whichever shape is
chosen, it needs an entry in the M2 backlog if it is not fixed now, because a downstream
app cannot work around it — it has no way to tell a real user search from an echo.

## Minor

### 2. `apply_button_props` writes an empty label on the toggle-button create path; its `Button` sibling deliberately does not

`src/widgets/w_toggle_button.ml:35-45`, `src/widgets/w_button.ml:20-36`, `:79-84`.

`apply_button_props`' `changed` helper treats `old = None` (the create path) as "everything
differs" (`w_button.ml:27-31`), so a `Node.toggle_button ~active:false ()` with no label, no
icon and no child still reaches `W.Button.set_label b ""` at `w_button.ml:36`. GTK 4's
`gtk_button_set_label` does not special-case the empty string when the current child is not
a label child: it builds a fresh `GtkLabel` and sets the button's child type to
`LABEL_CHILD`. `W_button.impl.create` (`w_button.ml:79-84`) exists specifically to avoid
this — it picks `new_from_icon_name` / `new_with_label` / `new_` so that a label-less button
never gets a label child.

So two siblings that share `apply_button_props` produce different live widgets for
equivalent descriptions: `Node.button ()` yields a childless `GtkButton`, while
`Node.toggle_button ~active:false ()` yields a `GtkToggleButton` carrying an empty
`GtkLabel` (and, since `gtk_button_set_label` also manages the style classes, the
`text-button` class). The icon-only toggle button additionally builds and immediately
discards that label before `set_icon_name` replaces it at `w_button.ml:48`.

Not visible in any current expectation file — every toggle button in `test/live/live_controls.ml:43`
and `test/test_widgets.ml` carries a label. Cosmetic rather than functional, but it is the
sibling divergence the review brief asks about, and the fix is one line: pass the create
path's `label` through the same `Option.iter` that `icon_name` already gets, or give
`apply_button_props` a `~creating:bool` that suppresses the `None` write.

### 3. Placeholder: `create` skips the `None` write, `update` does not — so mount and patch build different widgets

`src/widgets/w_entry.ml:60-64` vs `:87-88`; `src/widgets/w_search_entry.ml:29-31` vs `:42-43`.

Both create paths use `Option.iter`, with the comment "writing `None` still builds GTK's
placeholder label, empty, which a dump then reports as a placeholder that is not there".
That is right — `gtk_entry_set_placeholder_text` constructs the label unconditionally,
NULL included. But the update paths pass the option straight through, so going
`~placeholder:"x"` → no placeholder writes NULL and builds exactly the empty label that
`create` went out of its way to avoid.

Consequence: `Node.entry ~placeholder:"x" ~text:"" ()` patched to `Node.entry ~text:"" ()`
is not the same live widget as a freshly mounted `Node.entry ~text:"" ()`. This is the one
place in the area where dropping a prop does not restore the created state, which is the
invariant the creation-time snapshot establishes for widget-wide attrs. The backlog's
"`Live_tree.dump` collapses a placeholder `\"\"`" item means no golden file can catch it.

### 4. `Password_entry`'s placeholder is the third spelling of the same rule, and wants a fork binding

`src/widgets/w_password_entry.ml:14-17`, `:29-33`.

`create` uses `Option.iter`; `update` writes `Option.value ~default:""`. The `""` is forced
— ocgtk binds the setter as non-nullable:

```
_opam/lib/ocgtk/gtk/generated/password_entry.mli:46
external set_placeholder_text : t -> string -> unit = "ml_gtk_password_entry_set_placeholder_text"
```

whereas `entry.mli:53` and `search_entry.mli:16` both bind `string option`. The C API is
nullable, so this is a generator gap, and it is the second one M1 has hit after
`Widget.set_name` (already in the backlog's "ocgtk fork" section). Worth adding
`Password_entry.set_placeholder_text : t -> string option -> unit` to that same list so the
three entries can share one rule.

### 5. `w_entry.ml`'s shared-machinery comment overclaims, and the entry family's prop surface is uneven

`src/widgets/w_entry.ml:5-7`:

> All three entry kinds implement `GtkEditable`, and text, editability, width-chars,
> max-width-chars and alignment all go through it — as does `changed`, which is why one
> spec serves every one of them.

Only `text` (via `set_text_if_needed`) and `changed` are actually shared. `editable`,
`width_chars`, `max_width_chars` and `xalign` are written only by `W_entry.impl`
(`w_entry.ml:68-72`, `:93-100`) and appear only in `Kind.entry_props`
(`vtree/kind.ml:55-65`) and `Node.entry` (`vtree/node.mli:133-145`).
`Node.password_entry` and `Node.search_entry` expose none of them, although the interface
they would go through is the same one the comment names.

Nothing is broken, but a caller cannot size a search entry in characters or right-align a
password field, and the comment reads as though they could. Either narrow the comment to
"text and `changed`", or lift the four `GtkEditable` props onto all three constructors —
they are the same three `W.Editable` setters either way.

### 6. `Paintable_picture.apply` is the one multi-prop write in this area outside `Widget_impl.batch`

`src/paintable_picture.ml:35-39`.

`apply` writes `paintable`, `content_fit` and `can_shrink` unbracketed. `Widget_impl`'s doc
(`src/widget_impl.mli`, on `batch`) says "Every `update` that writes more than one property
should be wrapped in this", and all thirteen other impls do. It also re-writes
`set_paintable` whenever *either* of the other two changed, because `Input.equal`
(`:23-27`) is all-or-nothing — a `content_fit` change alone re-sets the paintable, which
GTK treats as a source change (it clears `GtkPicture:file` and re-arms the paintable's
invalidation handlers).

Neither costs anything measurable in the Stavekeeper shape — a new texture every frame
means `apply` runs every frame regardless, and `set_content_fit`/`set_can_shrink` are
ordinary early-returning GTK setters — but the file is the "worked example to copy when an
application needs a widget of its own" (`paintable_picture.mli:9-10`), so it should model
the convention rather than be the exception to it. Splitting `apply` into three guarded
writes inside a `batch` also makes the "unchanged source must not reload" rule that
`W_picture` and `W_image` follow hold here too.

### 7. `Native.Picture` has no `alternative_text`, unlike `Node.picture`

`src/paintable_picture.mli:22-28` vs `vtree/node.mli:317-324`.

`Node.picture` carries `?alternative_text` ("the accessible description, the 'alt'
attribute's equivalent"); the paintable-backed node does not. The app-rendered surface is
the one case where GTK can infer nothing at all about the content, so it is the picture that
most needs the description. One field on `Input.t` and one line in `apply`.

### 8. The spin button's reassert compares the committed value, not what the user is looking at

`src/widgets/w_spin_button.ml:34-36`.

`set_value_if_needed` reads `W.Spin_button.get_value`, which is the adjustment's value —
`GtkSpinButton` does not parse its entry text into it until the edit is committed (focus
out, Enter, or a stepper click). While the user has typed an uncommitted number, the widget
*displays* something the model has never seen and `reassert` writes nothing, because the
property it compares still agrees.

Concretely: `~min:0. ~max:100. ~value:5.`; the user selects the text and types `7`; an
unrelated re-render (a clock tick, another widget's event) runs a frame. The spin button
shows `7`, the model says `5`, and `reassert` is a no-op. It resolves on commit — GTK then
emits `value-changed` and `Attr.on_value_changed` catches up — so this is GTK's editing
model rather than a library defect, and comparing the editable text instead would fight the
user mid-keystroke.

It is worth a sentence in `Node.spin_button`'s doc, though: `vtree/node.mli:188-194` says
the widget is written "only when the model's value differs from the one the widget currently
holds", which a reader will take to mean "what is on screen". The entry family's text
comparison genuinely does mean that; the spin button's does not, and it is the only
controlled widget in the set where the two differ.

### 9. Three different conventions for writing a default-valued prop at create

`src/widgets/w_image.ml:32-35`, `src/widgets/w_picture.ml:37-43`, `src/widgets/w_entry.ml:60-77`.

- `W_image.create` guards `pixel_size` on `<> -1` but writes `icon_size` unconditionally.
- `W_picture.create` writes all three props unconditionally via `apply_props`.
- The entries, toggles and numeric kinds guard every optional write (`if not p.visibility`,
  `if p.activates_default`, `if p.inverted`, …).

All three are correct — each unconditional write is of GTK's own default — so this is
readability rather than behaviour. But since the guarded form is what makes a `create`
diffable against its `update` sibling by eye, and since `W_image` uses both forms in
adjacent lines, one convention would be worth settling.

### 10. `w_switch`'s reassert cannot see a `state`/`active` divergence

`src/widgets/w_switch.ml:27-35`.

`set_active_if_needed` gates on `active` alone but `set_both` writes `active` and `state`.
If `state` ever diverged while `active` agreed, the switch would wear its "pending" look
permanently and the reassert would never correct it. No M1 path produces that — the library
never connects `state-set`, so GTK's default handler keeps the two equal — so this is
latent, not live. Guarding on both getters is one extra `Bool.equal` and removes the
reasoning step. (Distinct from the backlog's "`w_switch`'s `create` hand-rolls the active
write", which is about `create` bypassing `reassert`.)

## Out-of-scope observations

- **Verified correct, listed so it is not re-reviewed.** `W_button.set_child_slot`'s `None`
  branch (`w_button.ml:61-68`) looked unsafe — `gtk_button_get_label` on a button whose
  child is a `GtkLabel` — but GTK 4 tracks a private child type, so `get_label` returns NULL
  for a child installed via `gtk_button_set_child`. `test/live/expected_controls.txt:10-11`
  and `:111-112` confirm it directly: a `Node.button ~child:(Node.label "boxed") ()` dumps as
  `(GtkButton (label ()) … (children (GtkLabel (text boxed))))`. Removing a label or image
  child from a button therefore works.
- **Also verified.** `Node.check_button`'s claim that GTK does not clear `inconsistent` when
  the user clicks is right — the GTK 4.22.4 GIR for `gtk_check_button_set_inconsistent` says
  "You should turn off the inconsistent state again if the user checks the check button.
  This has to be done manually." So leaving `inconsistent` as an ordinary diffed prop rather
  than a controlled one is correct.
- `Kind.entry_props` has no `max_length`. The review brief listed it among the entry-family
  specifics, but it is absent from the design spec's §7 signature as well
  (`docs/superpowers/specs/2026-08-28-bonsai-gtk-design.md:278`), so this is a
  never-scoped prop rather than a dropped one. Worth a line in the backlog's "do first in
  M2" if it is wanted, since `GtkEntry:max-length` is the usual companion to a controlled
  `text`.
- `W_spin_button` declares only `value_changed`, so `Attr.on_changed` on a spin button is
  rejected by `require_specs` even though `GtkSpinButton` implements `GtkEditable`. That is
  a defensible line — per-keystroke events from a numeric field are rarely what anyone wants
  — but it is undocumented in `Node.spin_button`, and the rejection message will read as a
  bug to the caller who tries it.
- `Native_gtk.widget_impl` (`src/native_gtk.ml:35-61`) builds a fresh `Widget_impl.t` record
  on every `Registry.for_kind` call. Harmless — the type witness is the stable
  `Type_equal.Id.t`, not the record — but it is an allocation per node per frame on the
  native path, which is the path `Native.Picture` and Stavekeeper both take. Not a controls
  finding; noting it for whoever owns `src/registry.ml`.

## Verdict

**Needs fixes** — for finding 1 only.

The one Important finding is a genuine correctness break in a stated invariant, in a widget
a downstream app will reach for, with no workaround available to that app. It is small in
blast radius (one signal, one widget) and the fix is local to `w_search_entry.ml`. Everything
else here is a consistency or documentation cleanup that would be reasonable to land as
follow-ups.

If M1 is to ship as-is, finding 1 needs at minimum a documented entry in
`docs/m1-backlog.md` alongside the existing "headless `Search_changed` action" item — the
two are related and should be fixed together, since the test that would prove the fix is the
one the backlog already wants.
