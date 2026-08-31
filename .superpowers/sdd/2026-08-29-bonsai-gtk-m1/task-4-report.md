# Task 4 report — controlled text: Entry, PasswordEntry, SearchEntry

Branch `m1`, commit **`813bbf9`** (`Entry, PasswordEntry, SearchEntry as controlled text widgets`),
on top of `bc70731`. 32 files, +936/-22. `./scripts/ci.sh` is green.

---

## 1. Changes

### `vtree/attr.ml(i)` — three event attrs

- `Name.On_changed | On_activate | On_search_changed`, all three `is_event = true`
  (the match is exhaustive by design, so the compiler forced the classification).
- `On_changed of string Handler.t`, `On_activate of unit Handler.t`,
  `On_search_changed of string Handler.t`, with the `name` / `equal` / constructor arms.
- `src/attr_apply.ml` gains inert `set` and `unset` arms for all three.
- Doc comments: `on_changed` carries the widget's *full text afterwards* (not the inserted
  characters) and fires for programmatic writes too, the reentrancy guard being what stops
  a re-render feeding itself; `on_activate` carries nothing (read the model);
  `on_search_changed` is GTK's debounced signal and a search entry carrying both fires both.

### `vtree/kind.ml(i)` / `vtree/node.ml(i)`

- `entry_props` (text, placeholder, editable, visibility, width_chars, max_width_chars,
  xalign, activates_default), `password_entry_props` (text, placeholder, show_peek_icon,
  activates_default), `search_entry_props` (text, placeholder, search_delay), with
  `Entry` / `Password_entry` / `Search_entry` constructors and the
  `name` / `same_kind` / `equal_props` arms.
- `[@sexp_drop_if]` on every field whose value is GTK's own default. `text` deliberately
  has none — it is a required labelled argument, so it is never a default, the same
  treatment `active` and `Box`'s `orientation` get.
- All three constructors take `~text` required, and the mli says why: an uncontrolled text
  widget in a declarative tree is the "my entry resets when something unrelated
  re-renders" bug, and the required argument makes it impossible to write by accident.
- Not exposed, and named in the doc comments: `GtkEntry`'s icon API (its
  `icon-press`/`icon-release` carry a `GtkEntryIconPosition`, better designed alongside
  M3's action routing), `GtkEditable::insert-text` (ocgtk does not bind it — in-out `int`
  position), and `Search_entry.set_key_capture_widget` (it names another *live* widget,
  which a vtree cannot; `Node.native` is the escape hatch).

### `src/widgets/w_entry.ml` — and the two that reuse it

- `editable : Widget.t -> W.Editable.t` (`from_gobject`) and `set_text_if_needed`, the
  §6.5 rule, shared by all three impls. The write saves `get_position` and puts it back
  afterwards (`set_text` moves the caret to the end; GTK clamps the restored position when
  the model shortened the text).
- `changed` is one `Signals.spec` for all three kinds, because `changed` is a
  `GtkEditable` signal; `activate ~connect` is parameterised over the connector, because
  `activate` lives on each concrete class.
- `w_entry.ml`'s `update` writes the text **last**, after `width_chars` — a size change
  re-lays-out the entry and would otherwise re-run the caret placement the write just
  decided. Its `create` writes `set_editable false` last for the mirror-image reason: a
  read-only entry still has to be given its text.
- `w_password_entry.ml` — `set_placeholder_text` is the one non-nullable setter of the
  three, hence `Option.value ~default:""` on the update path.
- `w_search_entry.ml` — `search_changed` spec alongside `W_entry.changed` (ruling 5:
  both are exposed), and `search_delay = None` means "leave GTK's own 150 ms alone", so
  going `Some` → `None` writes nothing rather than guessing a value to restore.

### `src/widgets/registry.ml`, `src/patcher.ml`, `src/live_tree.ml`

- Three registry arms; three arms in `destroy`'s kind match.
- `Live_tree` gains one arm for all three types (everything but the placeholder and each
  class's own extra reads through `GtkEditable`): text, placeholder, width-chars,
  max-width-chars, xalign, `read-only`, then `masked` / `no-peek-icon` / `search-delay`.
  GTK's internal children (the `GtkText`, the caps-lock indicator, the search and clear
  icons) print like any other child, per ruling 6.

### Carried review items from Task 3

1. **`require_specs` at patch time** (`src/patcher.ml:139`). The attrs diff is computed
   once, and when it is non-empty `Signals.require_specs` runs before anything is written,
   so the raise leaves the widget untouched. Guarded on the diff because re-walking every
   attr of every unchanged node each frame is pure cost. Pinned live:
   `rejected at patch: late/0: Label does not emit On_toggled`.
   `src/signals.ml(i)`'s comments say mount *and* patch, and why a conditionally-added
   attr can only be caught here.
2. **`test/test_widgets.ml`'s misnamed test** is now
   `"is_event classifies the handler-carrying attr names"`, which is what it asserts.
3. **`w_button.ml`'s `apply_button_props`** now states which of label/icon wins on the
   update path: the icon, because it is written second and `set_icon_name` replaces the
   child `set_label` just built — but only while the icon itself changed, so a node that
   keeps its icon and changes only its label flips the button to text. That asymmetry is
   the documented "going back to text" rule, and it matches `create`, where
   `new_from_icon_name` is preferred over `new_with_label`.

### `test_lib/bonsai_gtk_test.ml(i)`

- `Action.Set_text of string * string` and `Activate of string`. `Set_text` deliberately
  does not consult the node's `text` prop: it means "the user made the text be this",
  which is what a real edit produces regardless of what the widget was showing.

---

## 2. The bug the task's own live test found, and the fix

**`Patcher.patch` skipped `update` whenever a node's props were unchanged** —
`if not (Kind.equal_props ...) then impl.update ...`, an M0 optimisation. That is exactly
the case a model which *declines* the user's edit produces: the user types a letter into a
digits-only field, the model keeps its old string, and the new node's props are identical
to the previous frame's. `update` never ran, so §6.5's "compare against the widget" never
executed and the widget kept showing the value the model had refused. The brief's own
expected output (`model wins: a`) is unreachable without fixing this — the first live run
printed `model wins: ab`.

This is not specific to text. `ToggleButton`, `CheckButton` and `Switch` shipped in Task 3
with the identical hole: a model that ignores `Attr.on_toggled` leaves the widget flipped.
Task 3's live test happened to patch `active` from `false` to `true`, so the props always
differed and the hole never showed.

The fix is a new field on `Widget_impl.t`:

```ocaml
; controlled : bool
```

`true` for the three entries and the three toggles, `false` for Label / Button / Box /
Window / Native. The patcher reads it:

```ocaml
if live.impl.controlled || not (Kind.equal_props live.node.kind node.kind)
then live.impl.update live.widget ~old:live.node.kind node.kind;
```

Why a flag rather than calling `update` unconditionally (which is what spec §6.2's "widget
props diffed by the impl's `update ~old ~new`" literally describes): every impl's `update`
is already guarded field by field, so an unconditional call would be correct — but it would
also `freeze_notify`/`thaw_notify` every widget in the tree on every frame, and it would
leave "which widgets are controlled" as something a reader has to infer from the bodies.
The flag makes it a declaration the mli can explain, and the compiler forced every existing
impl to answer it. `Native_gtk` sets it `false` with a note that a native widget wanting to
re-assert can do so from its own `create`-installed handlers.

---

## 3. Two smaller departures from the brief

**(a) `set_placeholder_text` is not called when there is no placeholder.** The brief writes
it unconditionally. Empirically, `W.Entry.set_placeholder_text e None` still builds GTK's
placeholder label (empty), and `get_placeholder_text` then reports `Some ""` — so a plain
`Node.entry ~text:"ab" ()` dumped as `(GtkEntry (text ab) (placeholder ""))` with a stray
`GtkLabel` child. All three impls now write the placeholder only when there is one, and
`Live_tree` treats `Some ""` as absent (which also covers the update path, where clearing
one has to write something, and `GtkPasswordEntry`'s non-nullable getter).

**(b) The live test observes "nothing was written" directly, rather than inferring it.**
The brief's sequence — correct the widget to `"a"`, then re-render `"ab"` and claim
"the widget already shows it, so nothing is written" — is inconsistent once the correction
lands: after the first patch the widget shows `"a"`, so the second patch *does* write.
The test now types into the widget a second time before the echoing patch, and counts
writes with a counter connected to the widget's own `changed` signal (which fires for
`set_text` whatever the reentrancy guard does). Both of the brief's claims survive, as two
separate measurements, and the `scheduled` count remains the third:

```
model wins: a (the patch wrote: true)
echo is a no-op: ab (the patch wrote: false)
changed events reaching Bonsai from patches: 0
```

The boolean rather than a count is deliberate: `gtk_editable_set_text` is a delete followed
by an insert, so one write emits `changed` twice.

---

## 4. RED / GREEN, verbatim

### RED — headless (`dune build @test/runtest`)

```
File "test/test_widgets.ml", line 81, characters 11-21:
81 |          [ Node.entry ~placeholder:"name" ~text:"" ()
                ^^^^^^^^^^
Error: Unbound value "Node.entry"
File "test/test_handle.ml", line 150, characters 9-19:
150 |        [ Node.entry
               ^^^^^^^^^^
Error: Unbound value "Node.entry"
```

### RED — live (`BONSAI_GTK_LIVE_TESTS=1 xvfb-run -a dune build @test/live/runtest`)

```
File "test/live/live_controls.ml", line 53, characters 11-21:
53 |          ; Node.entry ~placeholder:"name" ~width_chars:8 ~text:"typed" ()
                ^^^^^^^^^^
Error: Unbound value "Node.entry"
```

### RED — the second one, after the impls compiled: the controlled rule not firing

```
-|model wins: a
+|model wins: ab
```

(the run that produced §2's fix.)

### GREEN — headless

```
$ dune build @test/runtest
warning: Git tree '/home/dlobraico/src/bonsai_gtk' is dirty
```

(no diff output; exit 0)

The promoted blocks, in short:

- `test/test_widgets.ml` — `the entry family's constructors`:
  ```
  ((kind (Entry ((text "") (placeholder (name))))) ...)
  ((kind (Entry ((text x) (editable false) (width_chars 6) (xalign 1)))) ...)
  ((kind (Password_entry ((text "") (placeholder (passphrase))))) ...)
  ((kind (Search_entry ((text bach) (search_delay (150))))) ...)
  ```
- `test/test_handle.ml` — `Set_text ("e", "hello")` against a model that uppercases gives
  `-| (Entry ((text "") ...))` → `+| (Entry ((text HELLO) ...))` and the echo label with
  it; `Activate "e"` then moves the `submitted` label from `-` to `HELLO`; and both
  actions fail loudly on a node with no matching handler
  (`Bonsai_gtk_test: node echo has no on_changed handler`).

### GREEN — live, the new lines of `test/live/expected_controls.txt`

```
    (GtkEntry (text typed) (placeholder name) (width-chars 8)
     (children
      (GtkText (cursor text)
       (children
        (GtkLabel (text name) (xalign 0) (ellipsize end) (max-width-chars 3))))))
    (GtkEntry (text secret) (max-width-chars 20) (xalign 1) read-only masked
     (children (GtkText (cursor text))))
    (GtkPasswordEntry (text "") (placeholder passphrase) no-peek-icon
     (css (password))
     (children
      (GtkText (cursor text)
       (children
        (GtkLabel (text passphrase) (xalign 0) (ellipsize end)
         (max-width-chars 3))))
      (GtkImage (css (caps-lock-indicator)) (tooltip "Caps Lock is on")
       (cursor text))))
    (GtkSearchEntry (text bach) (placeholder filter) (search-delay 200)
     (css (search))
     (children (GtkImage)
      (GtkText hexpand (cursor text)
       (children
        (GtkLabel (text filter) (xalign 0) (ellipsize end)
         (max-width-chars 3))))
      (GtkImage (tooltip "Clear Entry"))))
...
scheduled outside patch: 3
entry signals reaching Bonsai: 8
rejected: root/0: Label does not emit On_toggled
rejected at patch: late/0: Label does not emit On_toggled
...
model wins: a (the patch wrote: true)
echo is a no-op: ab (the patch wrote: false)
changed events reaching Bonsai from patches: 0
(GtkWindow (title (e)) (css (background)) hidden
 (children (GtkEntry (text ab) (children (GtkText (cursor text))))))
```

`entry signals reaching Bonsai: 8` is every spec the three impls declare, fired from its
own widget: `changed` on all four entries (through `GtkEditable`), `activate` on the three
that carry `Attr.on_activate`, and `search-changed` on the search entry. A spec that failed
to connect would drop the count. `scheduled during patch: 0` is unchanged — the entry nodes
are identical in both views, so their (now unconditional) `update` writes nothing.

`expected_patcher.txt`, `expected_driver.txt` and `expected_signals.txt` did not change:
no entry appears in them, and `controlled` only affects kinds that set it.

### `scripts/ci.sh`, tail

```
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

(The `Invalid_argument` line is `live_driver`'s pre-existing broken-driver case writing to
stderr, not a failure.)

---

## 5. Self-review

- **Three entries with create / update / signals / tests** — `w_entry.ml`,
  `w_password_entry.ml`, `w_search_entry.ml` each fill all five fields of
  `Widget_impl.t`, are wired into `registry.ml` and `patcher.ml`'s `destroy`, and appear in
  both the headless constructor test and the live dump.
- **Both SearchEntry signals** — `W_entry.changed` *and* `search_changed` in its
  `signals` list, both fired in the live test, and the choice between them documented on
  `Node.search_entry` per ruling 5.
- **Patch-time `require_specs`** — `src/patcher.ml:139`, guarded on the attrs diff, pinned
  by `rejected at patch: late/0: ...`.
- **`Set_text`/`Activate` with headless tests** — three expect tests in
  `test/test_handle.ml`: the uppercasing model, the activate round trip, and both
  missing-handler failures.
- **`scripts/ci.sh` green** — tail above.

---

## 6. Concerns for later tasks

1. **`Widget_impl.controlled` is now the switch every later controlled prop hangs off.**
   Task 5's `Scale`/`SpinButton` values (ruling 2), Task 7's `Expander.expanded` and
   `Revealer.reveal`, Task 9's `Stack.visible_child` all need `controlled = true` or they
   ship the same silent divergence Task 3's toggles did. `Paned`'s position is the
   documented exception (ruling 2) and must stay `false`.
2. **A controlled impl's `update` runs on every patch, so it must stay cheap and
   idempotent.** Each one currently opens a `Widget_impl.batch` (a freeze/thaw pair) even
   when it writes nothing. That is two C calls per controlled widget per frame; fine at M1
   sizes, worth measuring if a later milestone renders long controlled lists.
3. **The caret restore in `set_text_if_needed` is untested.** `set_position` is called
   after every write, but no test asserts where the caret lands — GTK's own clamping is
   doing the interesting part, and a live test would have to drive real focus. Worth a
   line in Task 10's sweep or the M2 backlog.
4. **`Live_tree` treats `Some ""` as "no placeholder".** True for all three widgets today
   (GTK builds an empty placeholder label for a `NULL` write), but it means a node that
   genuinely sets `~placeholder:""` is indistinguishable in a dump from one that sets none.
   No test depends on the difference.
5. **`Attr.Name.is_event`'s exhaustive match keeps earning its keep** — three more names
   this task, each forced through it. Task 3's note stands.

---

# Fix report — review round 1 of 5

Commit **`bff0794`** (`patcher: reassert hook replaces the controlled flag; toggle write-back test`),
on top of `813bbf9`. 18 files, +173/-71. `./scripts/ci.sh` green.

## 1. `Widget_impl.controlled : bool` → `reassert : (Widget.t -> Kind.t -> unit) option`

The flag only *described* the classification. Nothing stopped an impl from setting
`controlled = true` and still writing its controlled prop from `update` — which is where I
had in fact left it — so the guarantee rested on every future impl author reading the doc
and putting the write in the right half of a function the type system said nothing about.
The hook makes it unforgeable:

- `src/widget_impl.ml(i)` — `reassert : (Widget.t -> Kind.t -> unit) option`. The mli says
  what it is for (a model that *declines* renders last frame's props, so `update` is
  skipped and this is all that is left), what it must compare against (the widget), that
  it runs inside the reentrancy guard and should bracket its writes in `batch`, and that
  it is handed the *new* kind and must `wrong_kind` on anything else. `update`'s doc now
  says outright that a controlled prop must not be written there.
- `src/patcher.ml` — `update` keeps its `equal_props` skip; `reassert` is
  `Option.iter`-ed unconditionally, immediately after. `src/patcher.mli`'s `patch` doc
  carries the §6.2 sentence.
- Six impls set it, and — the point of the exercise — each one's `update` no longer
  mentions the controlled prop at all:
  `w_entry` / `w_password_entry` / `w_search_entry` (`set_text_if_needed`),
  `w_toggle_button` / `w_check_button` / `w_switch` (a new `set_active_if_needed` each,
  also reused by `create`, so the create and re-assert paths cannot drift).
  `w_switch`'s `update` is now an explicit no-op with a comment: `active` is the only prop
  a switch has and it is controlled, so there is nothing left to diff.
- `None` for Label, Button, Box, Window and `Native_gtk`. Task 5/7/9 set it for
  Scale/SpinButton/Expander/Revealer/Stack; `Paned`'s position stays `None`.

## 2. The toggle half of the rule, pinned

`test/live/live_controls.ml` now flips all three toggles behind the model's back
(`set_active` on the widget, outside any patch) and then patches with the tree unchanged at
`~active:true` — the shape of a model that declined. New expected line:

```
declined toggle true, check true, switch true (state true); reached Bonsai: 0
```

Without `reassert` this reads `false false false`: `equal_props` holds, `update` is
skipped, and the widgets keep the state the model refused. The switch's `state` is printed
alongside `active` because `set_active_if_needed` goes through `set_both`, and a switch
whose two halves diverge is the pending look `w_switch.ml` exists to avoid.

`test/live/expected_controls.txt` gained **exactly this one line** and nothing else — the
mechanism swap is invisible to every other assertion, which is the check the ruling asked
for.

## 3. `set_editable` ordering

`create` now writes `set_editable` with the other plain props and the text last, which is
the order `update` + `reassert` produce (`update` never touches the text; `reassert` runs
after it). The old comment claimed `set_editable` had to follow the text — "a read-only
entry still has to be given its text" — which is not true: `set_editable` gates the
*user's* edits, not the program's, and the live test's `~text:"secret" ~editable:false`
entry still dumps `(text secret) ... read-only` with the new order. The comment now states
the constraint that is real (text last, because a width or alignment change re-lays-out the
entry and would re-run the caret placement) and says why `set_editable` is not a barrier.

## 4. Minors

- `src/patcher.ml`'s `require_specs` guard comment is honest now: computing the attrs diff
  first is about *ordering* (the raise lands before any write), and the guard itself saves
  little, since handlers are rebuilt every frame and compare physically, so any node
  carrying an `on_*` attr has a non-empty diff every frame. It is the attr-free subtrees
  that get skipped.
- `Node.entry`'s doc now says what a write-back costs when it does happen: the caret goes
  to the end whenever the model shortened the text past the old position, the selection is
  dropped, and an input method's in-flight preedit is disturbed — the price of a model that
  rewrites as you type, and the reason the widget is left alone when it already agrees.

## 5. Verification

```
$ dune build @check
(exit 0, no output)

$ dune runtest test
dune exit=0

$ BONSAI_GTK_LIVE_TESTS=1 xvfb-run -a dune build @test/live/runtest
bonsai_gtk: exception in frame, stopping the driver: (Invalid_argument
  "root/0/1: a Node.window may only be the root node, not a child of another node")
dune exit=0
```

(that line is `live_driver`'s pre-existing broken-driver case on stderr, not a failure.)

```
$ nix develop -c ./scripts/ci.sh
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
ci exit=0
```

## 6. For Task 11's backlog

- **A headless action that fires `On_search_changed`.** `Bonsai_gtk_test.Action` has
  `Set_text`, which fires `On_changed`; a search entry whose model hangs off the debounced
  signal instead has no headless way to be driven. The natural shape is
  `Search_changed of string * string` next to `Set_text`, deliberately separate rather than
  making `Set_text` fire both — the whole point of ruling 5 is that they are different
  events with different timing, and a test that cannot tell them apart cannot test a
  component that picks one.
