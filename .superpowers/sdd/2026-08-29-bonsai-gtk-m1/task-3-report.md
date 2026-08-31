# Task 3 report — signals that carry a value; Button (extended), ToggleButton, CheckButton, Switch

Branch `m1`, commit **`bc70731`** (`ToggleButton, CheckButton, Switch; Button gains icon/child/frame`),
on top of `09f0a5a`. 32 files, +995/-61. `./scripts/ci.sh` is green.

---

## 1. Changes

### `Signals` — a spec's `fire` receives the widget

- `src/signals.ml:14`, `src/signals.mli:23` — `fire : Widget.t -> Attr.t -> unit Ui_effect.t option`
  (was `Attr.t -> ...`). `src/signals.ml:19` `dispatch ctx w slot spec` threads the widget
  through; `connect_all`'s callback (`src/signals.ml:47`) already had it in scope, so the
  exception guard and the `in_patch` early return are untouched.
- `src/signals.ml:63` / `src/signals.mli:56` — `notify ~prop w ~callback`, i.e.
  `Gobject.Signal.connect_simple ~name:("notify::" ^ prop) ~after:false`. Detailed signal
  names go through the generic marshaller, which carries no payload at all, so the handler
  reads the property back with the class getter — the same shape `fire` now has for
  `toggled`, which is why one `spec` type covers both.
- `src/signals.ml:70` / `src/signals.mli:65` — `require_specs ~node_path ~impl_name specs attrs`
  raises `Invalid_argument` for any `Attr.Name.is_event` attr no spec claims. Called from
  `src/patcher.ml:46`, immediately before `connect_all` and after `create`.

### `Widget_impl.batch`

- `src/widget_impl.ml:29` / `src/widget_impl.mli:41` — `freeze_notify` / `thaw_notify`
  around `f`, via `Exn.protect` (a raise between the two would leave the object frozen for
  good, and a frozen widget silently stops updating).
- Used by every impl that writes more than one property, including the two Task 2 left
  unbracketed and the two older ones:
  `w_label.ml:45,52` (create + update, the retrofit the task asked for),
  `w_button.ml:84`, `w_toggle_button.ml:25,41`, `w_check_button.ml:26,39`,
  `w_switch.ml:39,49`, `w_box.ml:25`, `w_window.ml:12,24`.
  `w_button.ml`'s `create` is the one multi-prop-looking impl without it: the label/icon go
  into the constructor and only `set_has_frame` can follow, so there is nothing to batch.

### `vtree/attr.ml(i)`

- `Name.On_toggled` (`attr.ml:26`), `On_toggled of bool Handler.t` (`attr.ml:82`), plus the
  `name` (`:108`), `equal` (`:133`) and constructor (`:160`) arms.
- `Attr.Name.is_event` (`attr.ml:32`) — written as an exhaustive match with every
  non-event name spelled out, never `_ -> false`, so each `On_*` a later task adds has to
  be classified by hand.
- `src/attr_apply.ml` gains `On_toggled _ -> ()` in `set` and `On_toggled -> ()` in `unset`.

### `vtree/kind.ml(i)`, `vtree/node.ml(i)`

- `button_props` gains `icon_name : string option` and `has_frame : bool`; new
  `toggle_button_props`, `check_button_props`, `switch_props`; new `Toggle_button`,
  `Check_button`, `Switch` constructors, with `name`/`same_kind`/`equal_props` arms.
- `[@sexp_drop_if]` on every field whose value is GTK's own default (`has_frame` drops when
  `true`, `inconsistent` when `false`, the options when `None`). `active` deliberately has
  none: it is a *required* labelled argument, so it is always something the caller asked
  for, never a default — the same treatment `Box`'s `orientation` and `Label`'s `text` get.
- `Node.button` (`node.ml:45`) is now `Single child` — a plain `~label:"+"` button prints
  `(children (Single ()))`, which is why `test/test_node.ml` and `test/test_handle.ml`
  moved. `toggle_button` (`:49`) likewise; `check_button` (`:53`) and `switch` (`:59`) are
  `No_children`.
- Doc comments on all four cover the label/icon/child slot competition, the controlled
  `active` rule, why radio groups are out of scope, and why `state-set` is not exposed.

### Widget impls

- `src/widgets/w_button.ml` — rewritten. `apply_button_props` (`:20`) is the shared
  label/icon/has-frame setter (a `GtkToggleButton` *is* a `GtkButton`); `create` prefers the
  prop-applying constructor (`new_from_icon_name` / `new_with_label`); `children` is now
  `Single`.
- `src/widgets/w_toggle_button.ml`, `w_check_button.ml`, `w_switch.ml` — new. Each has
  `create`/`update`/`signals`/`children`, and each writes `active` only when it differs from
  **the widget's live value**, per spec §6.5's controlled rule.
- `src/widgets/registry.ml` — three new arms. `src/patcher.ml`'s `destroy` match likewise.

### `src/live_tree.ml`

- `button_props` helper (`:80`) shared by the `GtkButton` (`:108`) and `GtkToggleButton`
  (`:109`) arms: label, `icon` when set, `frameless` when the frame is off.
- New `GtkCheckButton` (`:111`, label/active/inconsistent) and `GtkSwitch` (`:116`,
  active **and** state) arms. `state` is printed because `w_switch` keeps the two equal
  deliberately; printing only one would not show that.

### `test_lib/bonsai_gtk_test.ml(i)`

- `Action.Toggle of string` alongside `Click`; `node_exn` factored out; `current_active`
  reads the `active` prop off the node so the action means "the user clicked this", and
  fails loudly on a node with no toggle state.

---

## 2. Ambiguities resolved

**Switch's `state-set`.** Not connected, per the resolution. `Attr.on_toggled` on a switch
is `notify::active`; `create`/`update` write `set_active` *and* `set_state` together
(`w_switch.ml:31`), and `active` is controlled against `W.Switch.get_active`. What
returning `true`/`false` from `state-set` would do is documented on `Node.switch` and at the
top of `w_switch.ml`: `true` means "handled", which suppresses GTK's own update of `state`
and leaves it out of step with `active` — the pending look a switch wears while an
asynchronous confirmation is outstanding. bonsai_gtk has no such step, hence no `state-set`.

**CheckButton's `inconsistent`.** The brief lists it (`?inconsistent` on `Node.check_button`,
`set_inconsistent` in the impl, `inconsistent` in the dump), so it is in scope and shipped.

---

## 3. Two departures from the brief, both forced

**(a) The end-to-end `in_patch` proof does not use a `Native` impl.** The task suggested "a
`Native` impl whose `update` emits a signal during a patch, observed as dropped". That
cannot be observed: `Native_gtk.widget_impl` sets `signals = []` (`src/native_gtk.ml:57`),
so an `Attr.on_*` on a native node connects nothing — and, after `require_specs`, is
rejected outright. A native emitter's signal has no Bonsai-side handler to be dropped.
I wrote the test with the *real* mechanism instead (`test/live/live_driver.ml:44` and
`:143`): an app whose `Node.toggle_button` is controlled by model state, and a `flip`
button that changes that state. The frame that renders the flip calls `set_active`, GTK
emits `toggled` synchronously from inside `Patcher.patch`, and the dump reads
`on: true toggled: 0`. Emitting the identical signal outside a frame gives `toggled: 1`,
which is what rules out "the handler was never armed". This is strictly closer to spec §4.4
than a synthetic emit would have been, and it is what actually exercises `driver.ml`'s
`with_patch_guard`. The backlog line can be struck in Task 11.
I documented the native consequence in `src/native_gtk.mli` (`node`'s doc): an event attr
on a native node is now `Invalid_argument` at mount rather than silently inert, and a
native widget that needs to reach Bonsai connects its own handler in `create`.

**(b) `Node.check_button` produces `No_children`, not `Single None`.** The brief's step 7
writes `(Single None)` while its step 10 gives the impl `Widget_impl.No_children`. Those
disagree: `Patcher.mount`'s shape match falls through to
`"%s: node has children but %s takes none"`, so every `Node.check_button` would have raised
on mount. Since the brief is explicit that a check button has no child slot, `No_children`
is the arm that was meant. `vtree/node.ml:53` carries the reason in a comment.

---

## 4. A bug the brief's shape would have shipped

`Node.button` becoming `Single` means the patcher offers a child on every mount, including
`Single None`. `Patcher.mount` calls `set widget None` unconditionally there — and a
`GtkButton`'s child slot is the *same slot* its label and icon live in, so
`gtk_button_set_child (b, NULL)` would have stripped the label `new_with_label` had just
installed. Every plain labelled button in the library would have rendered empty.

The same slot collision bites on a transition: `update` runs before `patch_children`, so a
button going from `?child:x` to `?label:"y"` has *already* had its custom child replaced by
GTK when the child pass runs, and an unconditional `set_child None` would then remove the
fresh label instead.

`w_button.ml:53` `set_child_slot` handles both in one place, and is shared by
`w_toggle_button.ml`: clear the slot only when the button has neither a label nor an icon
to show, because in every other case GTK has already replaced the child itself. I chose this
over touching `Patcher.mount` so the fix stays local to the widget whose slot is
overloaded. `test/live/live_controls.ml:84` pins all three transitions
(child → label → child).

---

## 5. RED / GREEN, verbatim

### RED — headless (`dune build @test/runtest`)

```
File "test/test_handle.ml", line 72, characters 9-20:
72 |        [ Node.switch ~attrs:[ Attr.test_id "sw"; Attr.on_toggled set_on ] ~active:on ()
              ^^^^^^^^^^^
Error: Unbound value "Node.switch"
File "test/test_widgets.ml", line 42, characters 34-53:
42 |          ; Node.button ~icon_name:"list-add-symbolic" ~has_frame:false ()
                                       ^^^^^^^^^^^^^^^^^^^
Error: The function applied to this argument has type
         ?key:Bonsai_gtk_vtree.Key.t ->
         ?attrs:Bonsai_gtk_vtree.Attr.t list -> ?label:string -> Node.t
This argument cannot be applied with label "~icon_name"
```

### RED — live (`BONSAI_GTK_LIVE_TESTS=1 xvfb-run -a dune build @test/live/runtest`)

```
File "test/live/live_controls.ml", line 37, characters 34-53:
37 |          ; Node.button ~icon_name:"list-add-symbolic" ~has_frame:false ()
                                       ^^^^^^^^^^^^^^^^^^^
Error: The function applied to this argument has type
         ?key:Bonsai_gtk_vtree.Key.t ->
         ?attrs:Bonsai_gtk_vtree.Attr.t list -> ?label:string -> Node.t
This argument cannot be applied with label "~icon_name"
```

(`Scheduler` already exposed `create`, `in_patch` and `with_patch_guard`, and was already in
`Bonsai_gtk.Private`, so step 3's contingency was not needed.)

### GREEN — headless

```
$ dune build @test/runtest
warning: Git tree '/home/dlobraico/src/bonsai_gtk' is dirty
```

(no diff output; exit 0)

### GREEN — live, `test/live/expected_controls.txt` in full

```
(GtkWindow (title (controls)) (css (background)) hidden
 (children
  (GtkBox (spacing 0) (css (vertical))
   (children
    (GtkButton (label (plain)) (css (text-button))
     (children (GtkLabel (text plain))))
    (GtkButton (label ()) (icon list-add-symbolic) frameless
     (css (flat image-button)) (children (GtkImage (valign center))))
    (GtkButton (label ()) (css (text-button))
     (children (GtkLabel (text boxed))))
    (GtkToggleButton (label (bold)) (css (text-button toggle))
     (children (GtkLabel (text bold))))
    (GtkCheckButton (label (agree)) (css (text-button))
     (children (GtkBuiltinIcon (halign center) (valign center))
      (GtkLabel (text agree) (xalign 0) hexpand)))
    (GtkSwitch
     (children (GtkImage (opacity 0)) (GtkImage (opacity 0)) (GtkGizmo)))))))
scheduled during patch: 0
(GtkWindow (title (controls)) (css (background)) hidden
 (children
  (GtkBox (spacing 0) (css (vertical))
   (children
    (GtkButton (label (plain)) (css (text-button))
     (children (GtkLabel (text plain))))
    (GtkButton (label ()) (icon list-add-symbolic) frameless
     (css (flat image-button)) (children (GtkImage (valign center))))
    (GtkButton (label ()) (css (text-button))
     (children (GtkLabel (text boxed))))
    (GtkToggleButton (label (bold)) active (css (text-button toggle))
     (children (GtkLabel (text bold))))
    (GtkCheckButton (label (agree)) active (css (text-button))
     (children (GtkBuiltinIcon (halign center) (valign center))
      (GtkLabel (text agree) (xalign 0) hexpand)))
    (GtkSwitch active state
     (children (GtkImage (opacity 0)) (GtkImage (opacity 0)) (GtkGizmo)))))))
scheduled outside patch: 3
rejected: root/0: Label does not emit On_toggled
(GtkWindow (title (slot)) (css (background)) hidden
 (children
  (GtkBox (spacing 0) (css (vertical))
   (children
    (GtkButton (label ()) (css (text-button))
     (children (GtkLabel (text custom))))))))
(GtkWindow (title (slot)) (css (background)) hidden
 (children
  (GtkBox (spacing 0) (css (vertical))
   (children
    (GtkButton (label (text)) (css (text-button))
     (children (GtkLabel (text text))))))))
(GtkWindow (title (slot)) (css (background)) hidden
 (children
  (GtkBox (spacing 0) (css (vertical))
   (children
    (GtkButton (label ()) (css (text-button))
     (children (GtkLabel (text "custom again"))))))))
```

`scheduled during patch: 0` is the claim; `scheduled outside patch: 3` is the control
(`toggled`, `toggled`, `notify::active` — the switch's is emitted with
`Gobject.Property.notify`, since `emit_by_name` cannot carry a detailed name's payload).
`active` is on all three toggles in the second dump, so the writes did land; they simply did
not reach Bonsai.

### GREEN — live, the new tail of `test/live/expected_driver.txt` (the end-to-end guard)

```
(GtkWindow (title (reentry)) (css (background)) hidden
 (children
  (GtkBox (spacing 0) (css (vertical))
   (children
    (GtkButton (label (flip)) (css (text-button))
     (children (GtkLabel (text flip))))
    (GtkToggleButton (label (t)) active (css (text-button toggle))
     (children (GtkLabel (text t))))
    (GtkLabel (text "on: true toggled: 0"))))))
(GtkWindow (title (reentry)) (css (background)) hidden
 (children
  (GtkBox (spacing 0) (css (vertical))
   (children
    (GtkButton (label (flip)) (css (text-button))
     (children (GtkLabel (text flip))))
    (GtkToggleButton (label (t)) active (css (text-button toggle))
     (children (GtkLabel (text t))))
    (GtkLabel (text "on: true toggled: 1"))))))
```

`test/live/expected_patcher.txt` did **not** change: `Live_tree` prints only non-default
properties, so `Node.button`'s new children shape and the new icon/frameless props are
invisible to a tree that uses neither.

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

## 6. Self-review

- **Every widget has create/update/children/signals** — Button, ToggleButton, CheckButton,
  Switch each fill all four fields of `Widget_impl.t`; all three new ones are wired into
  `registry.ml` and into `patcher.ml`'s `destroy` match.
- **`drop_if` on default props** — every field whose value is GTK's own default drops from
  the sexp; `active` intentionally does not (required argument, never a default).
- **Headless + live tests** — headless: `test/test_widgets.ml` (constructors, `is_event`),
  `test/test_handle.ml` (the `Toggle` action, plus both of its failure modes).
  Live: `test/live/live_controls.ml` (all four widgets mounted and patched, the guard,
  `require_specs`, the button slot transitions) and `test/live/live_driver.ml` (the
  end-to-end guard through a real frame).
- **`batch` in every multi-prop impl** — listed in §1; `w_label` retrofitted in both
  `create` and `update`, and `w_box`/`w_window` swept in for the same reason.
- **The reentrancy test proves the producer side** — yes, and at two levels: with a
  hand-bracketed `Scheduler` in `live_controls`, and through `Driver.frame`'s own
  `with_patch_guard` in `live_driver`.
- **`scripts/ci.sh` green** — yes, tail above.

---

## 7. Concerns for later tasks

1. **`require_specs` is a behaviour change for `Node.native`.** An `Attr.on_clicked` on a
   native node used to be silently inert and is now `Invalid_argument` at mount. That is the
   right call (§5.1, §11) and is documented on `Native.node`, but if a later task wants
   natives to carry event attrs, `Native_gtk.S` needs a `signals` member — worth a backlog
   line in Task 11 if Task 6's `Native.Picture` wants one.
2. **The button slot is a three-way collision GTK does not resolve for us.** `set_child_slot`
   makes every transition I could construct correct, but the rule it encodes ("do not clear
   when a label or icon is showing") is a heuristic over GTK's behaviour, not a guarantee
   from its API. Any later widget with the same label/child overload (Task 7's `Expander`
   has one) should reuse this helper rather than re-derive it.
3. **`Live_tree` prints `state` for `GtkSwitch`.** Intentional — it is what shows
   `set_state` landed — but it is one more line per switch in every future expected file.
4. **`Attr.Name.is_event`'s exhaustive match is load-bearing.** Tasks 4–9 each add `On_*`
   names; the compiler will force a decision, but a name classified `false` by mistake makes
   `require_specs` silently stop protecting it. Worth a glance in Task 10's sweep.
