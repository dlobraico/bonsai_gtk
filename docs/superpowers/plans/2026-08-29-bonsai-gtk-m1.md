# bonsai_gtk M1 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Grow the M0 scaffold (Label/Button/Box/Window + `Node.native`) into the spec's **M1 — core & layout** catalogue: ToggleButton, CheckButton, Switch, Entry, PasswordEntry, SearchEntry, SpinButton, Scale, ProgressBar, Spinner, Image, Picture, Separator, ScrolledWindow, Frame, Expander, Grid, CenterBox, Paned, Overlay, Revealer, Stack + StackSwitcher + StackSidebar, an extended Button, and the shared attrs a real app needs — enough surface that stavekeeper (`~/src/stavekeeper`, an ocgtk app) can start porting screens onto bonsai_gtk. Land the three backlog items M0's reviews deferred first, because every widget added after them pays the cost twice.

**Architecture:** Unchanged from M0. `bonsai_gtk.vtree` (`vtree/`, ocgtk-free) owns `Node`/`Kind`/`Attr`/`Attrs`/`Children`/`Key`/`Native`/`Reconcile` plus the small pure enum modules widget props need (`Align`, `Orientation`, and M1's `Ellipsize`, `Content_fit`, `Icon_size`, `Image_source`, `Picture_source`, `Policy`, `Reveal_transition`, `Stack_transition`, `Grid_cell`). `bonsai_gtk` (`src/`) owns the runtime: `Patcher` (shadow tree), `Signals` (trampolines and handler slots), `Attr_apply`, one `src/widgets/w_<name>.ml` per widget implementing `Widget_impl.t`, `Registry`, `Scheduler`/`Driver`/`Loop`, `Live_tree`. `bonsai_gtk_test` (`test_lib/`) stays ocgtk-free and grows the actions the new widgets need. M1 changes three shared shapes — `Widget_impl.child_ops` (positional `~index` becomes `~after`, list ops become node-aware, named `Slots` appear), `Signals.spec` (`fire` receives the widget so a handler can carry the value GTK just changed), and `Attr_apply` (unset restores the widget's *own* creation-time default rather than a guessed one).

**Tech Stack:** OxCaml `ocaml-variants.5.2.0+ox`, dune ≥ 3.17, Bonsai `v0.18~preview.130.106+341` (Cont API), `bonsai.driver`, `bonsai_test`, `virtual_dom.ui_effect`, ocgtk 0.1~preview2 (GTK 4.22, fork pin in `ocgtk-pin.json`) — dune libraries `ocgtk.gtk`, `ocgtk.gio`, `ocgtk.gdk`, `ocgtk.common`, and newly `ocgtk.pango` (Pango's `ellipsizemode`), Nix flake for the dev shell, `xvfb-run` for live tests.

**Spec:** `docs/superpowers/specs/2026-08-28-bonsai-gtk-design.md`

## Global Constraints

Carried from the spec and from what M0 established. These hold for every task below.

- **One widget, one file.** Each widget is `src/widgets/w_<name>.ml` exposing a single `let impl : Widget_impl.t` (spec §7). File names are prefixed `w_` because `src/dune` uses `(include_subdirs unqualified)`, so `w_switch.ml` becomes module `W_switch` in the `bonsai_gtk` library and cannot collide with ocgtk's own `Switch`. `src/widgets/registry.ml` maps `Kind.t` to the impl and must stay an exhaustive match — adding a kind without a registry arm is a compile error, which is the point.
- **Props vs attrs.** Widget-specific properties are typed fields of that widget's `Kind.t` constructor and labelled arguments of its `Node.*` constructor. Properties every `GtkWidget` has are `Attr.t` values passed in `~attrs` (spec §5.1–5.2). Widget-specific *events* are also attrs (`Attr.on_toggled`, `Attr.on_changed`, ...); attaching an event attr to a widget whose impl declares no matching `Signals.spec` is silently inert today and must not be — see Task 3, which makes it an `Invalid_argument` at mount time (spec §5.1, §11).
- **Prop batches are bracketed.** Any `update` that may write more than one GTK property in a frame wraps the writes in `Gobject.Property.freeze_notify w` / `thaw_notify w` (spec §7). Use the `Widget_impl.batch` helper Task 3 adds; never hand-roll the pair (an exception between them would leave the object frozen).
- **Keyed children.** List children are matched by `Key.t` where present and positionally otherwise (`Reconcile.diff`, spec §5.4/§6.3). A duplicate key among siblings is `Invalid_argument`. `Stack` pages *require* a key: the key is the GTK page name.
- **Signal slots.** Every signal a widget supports is connected exactly once at `create`, to a trampoline that (1) cannot let an exception cross into C, (2) returns immediately when `Scheduler.in_patch` is set, (3) reads the handler out of a mutable slot, (4) converts GTK state into the OCaml event value, (5) schedules and requests a frame (spec §6.4). Re-rendering rewrites slots; nothing is disconnected before `destroy`. Signals ocgtk exposes only through the generic marshaller — the `notify::<prop>` family — are connected with `Gobject.Signal.connect_simple obj ~name:"notify::<prop>" ~after:false` and read back with the class getter. Signals ocgtk cannot bind at all are omitted from the API and named in the widget's doc comment; never bound to a silent no-op (spec §11).
- **Controlled text (and value) widgets.** `Entry`, `PasswordEntry`, `SearchEntry` — and by the same rule `Switch`/`ToggleButton`/`CheckButton` `active`, `SpinButton`/`Scale` `value`, `Stack` `visible_child` — write the widget only when the new value differs from the widget's *current* value, not from the previous node's (spec §6.5). Two reasons, both load-bearing: a model that echoes what the user typed must not move the caret or the slider under their finger, and every programmatic write emits a GTK signal that the `in_patch` guard then has to swallow.
- **Every GTK call site is guarded.** Structural misuse (non-window root, `Node.window` below the root, duplicate sibling keys, a child shape the container does not have, a missing `Attr.grid_cell` on a grid child, an unresolvable `Stack` name) raises `Invalid_argument` carrying the node path, at mount/patch time. Exceptions inside a trampoline are caught, logged with the node path, and do not tear down the loop. Exceptions inside a frame stop the driver for good. (spec §11)
- **Testing, two suites.** Behaviour that is decidable from the `Node.t` tree — constructor defaults, sexp shape, attr diffing, reconciliation, what a click/edit does to the model — is a `ppx_expect` test in `test/` against `bonsai_gtk.vtree` and `bonsai_gtk_test`, no display. Behaviour that is GTK's — that `set_active` really flips the widget, that a moved keyed child is the same GObject, that unsetting an attr restores GTK's default, that a programmatic write's signal is swallowed — is a plain executable under `test/live/` printing `Live_tree.dump`, compared by a `(diff expected.txt output.txt)` rule and gated on `(enabled_if (= %{env:BONSAI_GTK_LIVE_TESTS=0} 1))`. No `ppx_inline_test`/`ppx_expect` in anything linking ocgtk (spec §9).
- **`scripts/ci.sh` must pass** at the end of every task: `nix build .#ocgtk`, per-directory `@fmt` aliases, `dune build @all`, committed `.opam` files, `@test/runtest`, `BONSAI_GTK_LIVE_TESTS=1 xvfb-run -a dune build @test/live/runtest`, and the counter smoke run. `dune fmt` before every commit; `.ocamlformat` is `profile=janestreet`.
- The runtime uses ocgtk **Layer 1** (`Ocgtk_gtk.Gtk.Wrappers.*`, aliased `W` in `Gtk_import`) exclusively, and never `open`s `Ocgtk_gtk.Gtk` (it shadows `unit`). Downcasts go through `Gtk_import.cast`; upcasts are plain `(x :> Widget.t)` coercions.

**Commit trailer** (append to every commit body):

```
Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01Sg3Ci8U8kUKR8C3PL1pNSs
```

Use `GIT_EDITOR=true git commit -F -` with a heredoc; plain `git commit -m` hung once in this environment.

**Reference sources:**
- The pinned ocgtk checkout is `.ocgtk-src/` (created by `scripts/setup-switch.sh`, gitignored). Every ocgtk signature quoted in this plan was read from `.ocgtk-src/ocgtk/src/gtk/generated/<module>.mli`; check there first when a call does not typecheck.
- stavekeeper, the downstream driver for this milestone: `~/src/stavekeeper/lib/stavekeeper_app/{library_window,cards,sidebar,practice_bar,dialog}.ml`. It is a Layer-2 (`#method`) app, so read it for *which* widgets and properties a real screen needs, not for call syntax.
- `docs/m1-backlog.md` — the items M0's reviews deferred. Task 1 clears the "Do first in M1" three; Task 12 rewrites the file.

## File structure

| Path | Change | What |
|---|---|---|
| `vtree/attr.ml(i)` | modify | `Opacity`, `Focusable`, `Can_focus`, `Widget_name`, `Cursor_name`, `Measure_overlay`, `Page_title`, `Grid_cell`; event attrs `On_toggled`, `On_changed`, `On_activate`, `On_search_changed`, `On_value_changed`, `On_expanded_changed`, `On_revealed`, `On_visible_child_changed`, `On_position_changed` |
| `vtree/ellipsize.ml` | create | `Start \| Middle \| End` (absent = no ellipsization) |
| `vtree/content_fit.ml` | create | `Fill \| Contain \| Cover \| Scale_down` |
| `vtree/icon_size.ml` | create | `Inherit \| Normal \| Large` |
| `vtree/image_source.ml` | create | `Empty \| Icon_name \| File \| Resource` |
| `vtree/picture_source.ml` | create | `Empty \| Filename \| Resource` |
| `vtree/policy.ml` | create | `Always \| Automatic \| Never \| External_` |
| `vtree/reveal_transition.ml` | create | Revealer transition types |
| `vtree/stack_transition.ml` | create | Stack transition types |
| `vtree/grid_cell.ml` | create | `{ column; row; width; height }` |
| `vtree/kind.ml(i)` | modify | one constructor per M1 widget |
| `vtree/node.ml(i)` | modify | one constructor per M1 widget; `Slots`-aware `find_by_test_id` |
| `vtree/children.ml` + `children.mli` | modify/create | `Slots of (string * 'a t) list`; the mli M0 never wrote |
| `src/dune` | modify | add `ocgtk.pango` |
| `src/widget_impl.ml(i)` | modify | `~after` list ops, node-aware list ops, `Slots`, `batch` |
| `src/signals.ml(i)` | modify | `fire` receives the widget; `notify` helper; `require_specs` |
| `src/attr_apply.ml(i)` | modify | creation-time `defaults` snapshot; new attrs |
| `src/patcher.ml(i)` | modify | `~after` bookkeeping, slot patching, stack registry + fixups |
| `src/driver.ml(i)` | modify | `broken` guard on `frame`/`schedule_event`; drain fixups |
| `src/live_tree.ml` | modify | per-type props for every new widget |
| `src/paintable_picture.ml(i)` | create | the library's own `Node.native` widget: a `GtkPicture` fed a `GdkPaintable` |
| `src/widgets/w_button.ml` | modify | `icon_name`, `has_frame`, `?child` |
| `src/widgets/w_label.ml` | modify | `wrap`, `xalign`, `ellipsize`, `max_width_chars`, `width_chars`, `selectable`, `use_markup` |
| `src/widgets/w_box.ml` | modify | `~after` child ops |
| `src/widgets/w_toggle_button.ml` … `w_stack_sidebar.ml` | create | 24 new widget impls |
| `src/widgets/registry.ml` | modify | an arm per kind |
| `src/bonsai_gtk.ml(i)` | modify | re-export the new vtree enum modules; `Native.Picture` |
| `test_lib/bonsai_gtk_test.ml(i)` | modify | `Set_text`, `Toggle`, `Activate`, `Set_value` actions |
| `test/test_attrs.ml`, `test_node.ml`, `test_handle.ml` | modify | new attrs/constructors/actions |
| `test/test_widgets.ml` | create | one headless expect test per widget group |
| `test/live/live_signals.ml` (+ expected) | create | `in_patch` trampoline guard (Task 1) |
| `test/live/live_controls.ml` (+ expected) | create | Tasks 3–5 widgets, live |
| `test/live/live_containers.ml` (+ expected) | create | Tasks 6–9 widgets, live |
| `test/live/dune` | modify | rules for the new executables |
| `test/test_gallery.ml` | create | the headless sweep: every M1 constructor in one tree (Task 10) |
| `examples/gallery.ml`, `examples/dune` | create/modify | every M1 widget in one window (Task 10) |
| `scripts/ci.sh` | modify | smoke the gallery beside the counter (Task 10) |
| `README.md`, `docs/m1-backlog.md` | modify | widget catalogue; backlog rolled forward (Task 11) |

## What M1 still does not give the stavekeeper port

The port is the reason for this milestone's shape, so be explicit about the gap it will
still have when M1 lands. Reading `~/src/stavekeeper/lib/stavekeeper_app/`, the screens
divide cleanly:

- **`dialog.ml`, `cards.ml`, `practice_bar.ml`'s metronome and audio rows** are portable
  on M1 alone: box/grid/center-box layout, labels with ellipsize and xalign, buttons
  (labelled, icon, ghost), entries with placeholders and width-chars, a scale, pictures
  with content-fit and can-shrink, and the overlay-over-a-spacer size cap.
- **`library_window.ml` and `sidebar.ml` are not**, and deliberately: they are built on
  `GtkFlowBox`, `GtkListBox`/`GtkListBoxRow` and `GtkDropDown`, all of which spec §7 puts
  in **M2** (lists & text). `practice_bar.ml`'s three `Drop_down.new_from_strings` pills
  are the same story.
- **`viewer_window.ml` / `ink_mode.ml`** need `GtkPicture` fed a `Gdk.Memory_texture`,
  which Task 6's `Native.Picture` covers, plus `Node.native` for anything else.

So M1's honest claim is: dialogs, cards and the practice bar can be ported; the library
grid and the sidebar wait for M2. Say that in the README's Limitations section (Task 11)
rather than letting the porter discover it.

---

### Task 1: Backlog first — `~after` child ops, the broken-driver guard, the reentrancy test

The three items `docs/m1-backlog.md` marks "Do first in M1". Each gets more expensive per container M1 adds, so they land before any widget does.

**Files:**
- Modify: `src/widget_impl.ml`, `src/widget_impl.mli`, `src/widgets/w_box.ml`, `src/patcher.ml`, `src/driver.ml`, `src/driver.mli`, `test/live/dune`
- Create: `test/live/live_signals.ml`, `test/live/expected_signals.txt`

**Interfaces:**
- Changed:
  ```ocaml
  (* Widget_impl *)
  type child_ops =
    | No_children
    | Single of { set : Widget.t -> Widget.t option -> unit }
    | List of
        { insert : Widget.t -> after:Widget.t option -> Widget.t -> unit
        ; move : Widget.t -> child:Widget.t -> after:Widget.t option -> unit
        ; remove : Widget.t -> Widget.t -> unit
        }
  (* [sibling_before] is deleted. *)
  (* Driver *)
  val frame : t -> unit          (* now a no-op once [broken t] *)
  val schedule_event : t -> unit Ui_effect.t -> unit   (* now a no-op once [broken t] *)
  ```
- Unchanged: everything else. `Reconcile` op indices keep their meaning; only the translation from an index to a GTK placement moves from reading GTK's live child list to reading the patcher's own `cur` list.

Why: `Widget_impl.sibling_before` walks `Widget.get_first_child`/`get_next_sibling` to turn an index into the sibling to place after. That is only correct while GTK's live child list is exactly the list the reconciler computed indices against — which stops being true the moment a container interposes children of its own (`GtkListBox` wraps rows, `GtkStack` keeps pages, `GtkOverlay` holds a main child beside its overlays). The patcher already maintains `cur`, a list of the live children in the order it believes them to be in; feeding the placement from `cur` is both correct for interposing containers and cheaper (no GTK round-trip per insert).

- [ ] **Step 1: Write the failing live test** (`test/live/live_signals.ml`)

This is the `in_patch` reentrancy guard test the backlog asks for, at the level M0's widget set can express it: a real `GtkButton`, a real `Signals.spec`, a real trampoline, and a `ctx` whose `in_patch` the test controls. The end-to-end version — a widget whose *programmatic* update emits its own signal — needs `ToggleButton`, and lands in Task 3.

```ocaml
open! Core
open Bonsai_gtk_vtree
module Gobject = Bonsai_gtk.Private.Gtk_import.Gobject
module Signals = Bonsai_gtk.Private.Signals
module W = Bonsai_gtk.Private.Gtk_import.W

let cast = Bonsai_gtk.Private.Gtk_import.cast

let () =
  ignore (Ocgtk_gtk.GMain.init () : string array);
  let scheduled = ref 0 in
  let in_patch = ref false in
  let ctx : Signals.ctx =
    { schedule = (fun _ -> incr scheduled)
    ; in_patch = (fun () -> !in_patch)
    ; on_exn = (fun ~node_path exn -> printf "EXN at %s: %s\n" node_path (Exn.to_string exn))
    }
  in
  let button = (W.Button.new_with_label "b" :> Bonsai_gtk.Widget.t) in
  let slots, _ids =
    Signals.connect_all ctx ~node_path:"root/0" button [ W_button_clicked.spec ]
  in
  (* An empty slot is inert even outside a patch: nothing is connected until the first
     [update_slots]. *)
  Gobject.Signal.emit_by_name button ~name:"clicked";
  printf "empty slot: %d\n" !scheduled;
  Signals.update_slots slots (Attrs.of_list [ Attr.on_clicked Ui_effect.Ignore ]);
  Gobject.Signal.emit_by_name button ~name:"clicked";
  printf "armed slot: %d\n" !scheduled;
  (* The guard: a signal GTK emits synchronously from inside a patch must never reach
     Bonsai, however the handler slot is armed. *)
  in_patch := true;
  Gobject.Signal.emit_by_name button ~name:"clicked";
  in_patch := false;
  printf "during patch: %d\n" !scheduled;
  Gobject.Signal.emit_by_name button ~name:"clicked";
  printf "after patch: %d\n" !scheduled;
  (* A raising handler is logged, not propagated into GTK's C frame. *)
  Signals.update_slots
    slots
    (Attrs.of_list [ Attr.on_clicked (Ui_effect.of_thunk (fun () -> failwith "boom")) ]);
  Gobject.Signal.emit_by_name button ~name:"clicked";
  printf "after raising handler: %d\n" !scheduled;
  (* [clear_slots] disarms without disconnecting, which is what [Patcher.disarm] relies on
     when GTK is about to emit during teardown. *)
  Signals.clear_slots slots;
  Gobject.Signal.emit_by_name button ~name:"clicked";
  printf "after clear: %d\n" !scheduled
;;
```

`W_button_clicked.spec` does not exist: expose M0's `w_button.ml` `clicked` value instead. Add to `src/widgets/w_button.ml` nothing — it is already `let clicked : Signals.spec`, and `W_button` is a module of the `bonsai_gtk` library — so reach it as `Bonsai_gtk.Private.W_button.clicked` after adding `module W_button = W_button` to `src/bonsai_gtk.ml`'s and `.mli`'s `Private` block. Use that name in the test.

Note the raising-handler line: `Ui_effect.of_thunk (fun () -> failwith "boom")` builds an effect, and building it does not run it — the trampoline schedules it and `schedule` here just counts, so the count goes up and nothing raises. That is the honest shape: the trampoline's guard covers exceptions from `fire`/`schedule`/`in_patch`, not from effects Bonsai later performs. Keep the line and its expected count; it documents the boundary.

- [ ] **Step 2: `test/live/dune`** — add the executable and its rule

```lisp
(executables
 (names live_patcher live_driver live_signals)
 (libraries
  core
  bonsai
  bonsai_gtk
  bonsai_gtk.vtree
  virtual_dom.ui_effect
  ocgtk.gtk
  ocgtk.common)
 (preprocess
  (pps ppx_jane bonsai.ppx_bonsai)))

(rule
 (alias runtest)
 (enabled_if
  (= %{env:BONSAI_GTK_LIVE_TESTS=0} 1))
 (deps live_signals.exe)
 (action
  (progn
   (with-stdout-to
    output_signals.txt
    (run %{exe:live_signals.exe}))
   (diff expected_signals.txt output_signals.txt))))
```

- [ ] **Step 3: Run to verify failure** — `BONSAI_GTK_LIVE_TESTS=1 xvfb-run -a dune build @test/live/runtest`
Expected: unbound `Bonsai_gtk.Private.W_button`.

- [ ] **Step 4: `src/widget_impl.ml(i)` — replace `~index` with `~after`**

```ocaml
(* widget_impl.ml *)
type child_ops =
  | No_children
  | Single of { set : Widget.t -> Widget.t option -> unit }
  | List of
      { insert : Widget.t -> after:Widget.t option -> Widget.t -> unit
      ; move : Widget.t -> child:Widget.t -> after:Widget.t option -> unit
      ; remove : Widget.t -> Widget.t -> unit
      }

type t =
  { name : string
  ; create : Kind.t -> Widget.t
  ; update : Widget.t -> old:Kind.t -> Kind.t -> unit
  ; signals : Signals.spec list
  ; children : child_ops
  }

let wrong_kind name kind = invalid_argf "%s impl received %s" name (Kind.name kind) ()
```

Delete `sibling_before` and its doc comment; the mli documents the new contract instead:

```ocaml
(* widget_impl.mli *)
type child_ops =
  | No_children
  | Single of { set : Widget.t -> Widget.t option -> unit }
  | List of
      { insert : Widget.t -> after:Widget.t option -> Widget.t -> unit
      (** Add a child that is not yet in the container, placing it directly after
          [after] — or first when [after] is [None]. [after] is the live widget the
          patcher's own bookkeeping says precedes this position, never a widget read back
          out of GTK: a container that interposes children of its own (list-box rows,
          stack pages) has a live child list that does not match the reconciler's
          indices, and only the patcher's list is authoritative. *)
      ; move : Widget.t -> child:Widget.t -> after:Widget.t option -> unit
      (** Move a child already in the container to sit directly after [after] ([None] =
          first). [after] is computed over the sibling list with [child] already taken
          out of it, which is the order GTK's [reorder_child_after] expects. *)
      ; remove : Widget.t -> Widget.t -> unit
      }
```

- [ ] **Step 5: `src/widgets/w_box.ml`** — the ops become one-liners

```ocaml
  ; children =
      Widget_impl.List
        { insert =
            (fun parent ~after child -> W.Box.insert_child_after (cast parent) child after)
        ; move =
            (fun parent ~child ~after ->
              W.Box.reorder_child_after (cast parent) child after)
        ; remove = (fun parent child -> W.Box.remove (cast parent) child)
        }
```

- [ ] **Step 6: `src/patcher.ml`** — feed placements from `cur`

In `mount`, thread the previous child through the fold instead of indexing:

```ocaml
    | List cs, List { insert; _ } ->
      let lives =
        List.mapi cs ~f:(fun i c -> mount ctx ~path:(child_path path i) ~is_root:false c)
      in
      List.fold lives ~init:None ~f:(fun after l ->
        insert widget ~after l.widget;
        Some l.widget)
      |> (ignore : Widget.t option -> unit);
      List lives
```

In `patch_children`'s `List` arm, add the helper and use it in every op:

```ocaml
    (* The widget a child at [index] must be placed after, read off the patcher's own
       list rather than GTK's. [cur] is kept in step with the ops exactly as
       [Reconcile.apply] would keep a node list, so [index] indexes it directly. *)
    let after_of cur index =
      if index = 0 then None else Some (List.nth_exn cur (index - 1)).widget
    in
    let cur = ref olds in
    List.iter ops ~f:(fun (op : Node.t Reconcile.op) ->
      match op with
      | Remove { index } ->
        let l = List.nth_exn !cur index in
        disarm l;
        remove live.widget l.widget;
        destroy ctx l;
        cur := List.filteri !cur ~f:(fun i _ -> i <> index)
      | Insert { index; item } ->
        let l = mount ctx ~path:(child_path path index) ~is_root:false item in
        insert live.widget ~after:(after_of !cur index) l.widget;
        cur := List.take !cur index @ (l :: List.drop !cur index)
      | Move { from; to_ } ->
        let l = List.nth_exn !cur from in
        (* [to_] indexes the list as it will be *after* the move, so the predecessor is
           computed with [l] already removed. *)
        let without = List.filteri !cur ~f:(fun i _ -> i <> from) in
        move live.widget ~child:l.widget ~after:(after_of without to_);
        cur := List.take without to_ @ (l :: List.drop without to_)
      | Update { index; item; old = _ } ->
        let l = List.nth_exn !cur index in
        let l' = patch ctx ~path:(child_path path index) ~is_root:false l item in
        if not (phys_equal l l')
        then (
          (* The kind changed, so [patch] mounted a replacement and destroyed [l]; [l]'s
             widget is still parented here. Remove it, then place the replacement where
             it was — [after] over the list with [l] taken out. *)
          let without = List.filteri !cur ~f:(fun i _ -> i <> index) in
          remove live.widget l.widget;
          insert live.widget ~after:(after_of without index) l'.widget);
        cur := List.mapi !cur ~f:(fun i x -> if i = index then l' else x));
    List !cur
```

- [ ] **Step 7: `src/driver.ml(i)` — the broken guard**

```ocaml
let schedule_event t effect =
  (* A broken driver renders nothing again (see [frame]), so queueing effects into it only
     grows a queue nobody drains — a frozen window whose memory keeps climbing. *)
  if not (Scheduler.broken t.scheduler)
  then (
    Bonsai_driver.schedule_event t.bonsai effect;
    Scheduler.request_frame t.scheduler)
;;

let frame t =
  if t.stopped
  then
    invalid_arg
      "Bonsai_gtk: Driver.frame on a stopped driver (stop invalidates the Bonsai graph \
       and tears the widget tree down; build a new driver instead)";
  if Scheduler.broken t.scheduler
  then
    (* A frame already raised. The shadow tree describes a GTK tree that no longer
       exists, so diffing against it again is worse than doing nothing. Unlike [stopped]
       this is not caller error — the scheduler's own guarded path reaches here too — so
       it returns rather than raising. *)
    ()
  else (
    ... existing body ...)
;;
```

`driver.mli`, on `frame`: add "Once a frame has raised (`broken` is `true`) this is a no-op: the promise that nothing updates the tree again holds for hand-driven frames as well as for the scheduler's." On `schedule_event`: "A no-op once the driver is broken."

- [ ] **Step 8: `src/bonsai_gtk.ml(i)`** — add `module W_button = W_button` to the `Private` block (both files), so the live test can name M0's `clicked` spec.

- [ ] **Step 9: Run, read the output, promote**

Run: `BONSAI_GTK_LIVE_TESTS=1 xvfb-run -a dune build @test/live/runtest 2>&1 | head -60`
Expected `output_signals.txt`, read critically before promoting: `empty slot: 0`, `armed slot: 1`, `during patch: 1`, `after patch: 2`, `after raising handler: 3`, `after clear: 3`. The two numbers that carry the claim are `during patch` (unchanged from the line before it) and `after clear`. Then `dune promote`.
`output_patcher.txt` and `output_driver.txt` must be **unchanged** — the `~after` rewrite is a refactor, and a diff there means the placement logic changed behaviour. If `live_patcher` diffs, the `Move`/`Update` predecessor arithmetic is wrong; re-read Step 6.

- [ ] **Step 10: Full gate + commit**

```bash
./scripts/ci.sh
dune fmt 2>/dev/null; git add src test/live
GIT_EDITOR=true git commit -F - <<'MSG'
Child placement by predecessor widget, not GTK's live child list

[Widget_impl.sibling_before] read children back out of GTK to turn a
reconciler index into a placement, which is only correct for containers whose
live child list is exactly the list the reconciler indexed. It is not for the
containers M1 adds. Feed the placement from the patcher's own [cur] list
instead, as [~after:(Widget.t option)].

Also: a broken driver now refuses hand-driven frames and drops scheduled
events, as driver.mli already promised, and a live test pins the [in_patch]
trampoline guard.

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01Sg3Ci8U8kUKR8C3PL1pNSs
MSG
```

---

### Task 2: The cross-cutting attrs a real app needs, and Label's text properties

Everything stavekeeper's five screens reach for that is not a widget: `css_class` (done in M0), `margin_*`, size requests, `halign`/`valign`, `hexpand`/`vexpand`, `tooltip`, `sensitive`, `visible` (all done in M0), plus **cursor name**, **opacity**, **focusable**/**can_focus**, **widget name**, and on `Label` — which stavekeeper sets on nearly every label it builds — **ellipsize**, **xalign**, **max-width-chars**, **width-chars**, **wrap**, **selectable**, **use-markup**. Also the backlog's per-kind unset-defaults bug, fixed generically.

Read `~/src/stavekeeper/lib/stavekeeper_app/dialog.ml` before starting: `field`, `row`, `hint`, `section` are four helpers and they use `set_xalign`, `set_wrap`, `set_ellipsize`, `set_size_request`, `set_hexpand`, `add_css_class` between them. That is the shape M1's attrs have to make expressible without an escape hatch.

**Files:**
- Create: `vtree/ellipsize.ml`, `test/test_widgets.ml`
- Modify: `vtree/attr.ml`, `vtree/attr.mli`, `vtree/kind.ml`, `vtree/kind.mli`, `vtree/node.ml`, `vtree/node.mli`, `vtree/bonsai_gtk_vtree.ml`, `src/dune`, `src/attr_apply.ml`, `src/attr_apply.mli`, `src/patcher.ml`, `src/widgets/w_label.ml`, `src/live_tree.ml`, `src/bonsai_gtk.ml`, `src/bonsai_gtk.mli`, `test/test_attrs.ml`, `test/live/live_patcher.ml`

**Interfaces:**
- Produces:
  ```ocaml
  (* vtree/ellipsize.ml — absent means "do not ellipsize"; there is no [None]
     constructor, so [Ellipsize.t option] carries that and never shadows [Option]. *)
  type t = Start | Middle | End [@@deriving sexp_of, equal, compare]

  (* Attr *)
  val opacity : float -> t          (* 0. .. 1. *)
  val focusable : bool -> t
  val can_focus : bool -> t
  val widget_name : string -> t     (* GtkWidget's [name], the CSS "#id" selector *)
  val cursor_name : string -> t     (* "pointer", "text", "default", ... *)

  (* Node *)
  val label
    :  ?key:Key.t -> ?attrs:Attr.t list
    -> ?wrap:bool -> ?xalign:float -> ?ellipsize:Ellipsize.t
    -> ?max_width_chars:int -> ?width_chars:int -> ?selectable:bool -> ?use_markup:bool
    -> string -> t

  (* Attr_apply *)
  type defaults
  val snapshot : Widget.t -> defaults      (* call once, on a freshly created widget *)
  val apply : defaults:defaults -> Widget.t -> Attrs.op -> unit
  val apply_all : Widget.t -> Attrs.t -> unit
  ```
- Consumes: `Widget.set_opacity/set_focusable/set_can_focus/set_name/set_cursor_from_name`, `Widget.get_cursor`, `Label.set_wrap/set_xalign/set_ellipsize/set_max_width_chars/set_width_chars/set_selectable/set_markup`, `Ocgtk_pango.Pango.ellipsizemode`.

Note on `Widget.set_name`: ocgtk's widget module has `set_name : t -> string -> unit` / `get_name : t -> string` (the `string option` pair in the same generated file belongs to `Event_controller`, a different module — no shadowing). The attr is called `widget_name`, not `name`, because `Attr.name : Attr.t -> Attr.Name.t option` already exists.

**The defaults snapshot.** `Attr_apply.unset` currently restores a constant it guesses (`Visible -> true`, `Halign -> \`FILL`). The backlog flags `Unset Visible -> true` as wrong for `GtkWindow`, and M1 makes that class of bug much bigger: `focusable` is FALSE on a `GtkLabel` and TRUE on a `GtkButton`, `can_focus` differs the same way, and a `GtkPicture`'s `can_shrink` default is not a `GtkImage`'s. Rather than a per-kind table that has to be maintained for 27 widgets, read the answer off the widget GTK just made: `Patcher.mount` calls `Attr_apply.snapshot` immediately after `impl.create` and before `apply_all`, stores the record in `live`, and every later `Unset` restores from it. Fifteen getter calls per widget creation, once, and it is right by construction for every widget the library will ever add.

- [ ] **Step 1: Write the failing tests**

`test/test_attrs.ml` — append:

```ocaml
let%expect_test "M1 widget-wide attrs round-trip through of_list and diff" =
  let attrs =
    Attrs.of_list
      [ Attr.opacity 0.5
      ; Attr.focusable true
      ; Attr.can_focus false
      ; Attr.widget_name "sidebar"
      ; Attr.cursor_name "pointer"
      ]
  in
  print_s [%sexp (attrs : Attrs.t)];
  [%expect {| |}];
  print_s
    [%sexp
      (Attrs.diff ~old:attrs ~new_:(Attrs.of_list [ Attr.opacity 1.0 ]) : Attrs.op list)];
  [%expect {| |}]
;;
```

`test/test_widgets.ml` — new file, the home for every "does this constructor make the node I meant" test M1 adds. Start it with `Label`:

```ocaml
open! Core
open Bonsai_gtk_vtree

let%expect_test "label defaults match GTK's, and every text property reaches the kind" =
  print_s [%sexp (Node.label "plain" : Node.t)];
  [%expect {| |}];
  print_s
    [%sexp
      (Node.label
         ~wrap:true
         ~xalign:0.
         ~ellipsize:End
         ~max_width_chars:14
         ~width_chars:6
         ~selectable:true
         ~use_markup:true
         "styled"
       : Node.t)];
  [%expect {| |}]
;;

let%expect_test "label props take part in equal_props" =
  let a = (Node.label ~xalign:0. "x").kind in
  let b = (Node.label ~xalign:1. "x").kind in
  print_s [%sexp (Kind.same_kind a b, Kind.equal_props a b : bool * bool)];
  [%expect {| |}]
;;
```

`test/dune` needs no change — the library stanza globs the directory.

- [ ] **Step 2: Run to verify failure** — `dune build @test/runtest` → unbound `Attr.opacity`, unknown labelled argument `~wrap`.

- [ ] **Step 3: `vtree/ellipsize.ml`**

```ocaml
open! Core

(** Where a `GtkLabel`/`GtkProgressBar` drops characters when its text does not fit. There
    is deliberately no "none" constructor: the absence of ellipsization is
    [None : t option], which keeps the constructor list from shadowing [Option.None] in
    every match. *)
type t =
  | Start
  | Middle
  | End
[@@deriving sexp_of, equal, compare]
```

Add `module Ellipsize = Ellipsize` to `vtree/bonsai_gtk_vtree.ml` and to `src/bonsai_gtk.ml(i)`.

- [ ] **Step 4: `vtree/attr.ml(i)`** — five constructors, five names, five `equal` arms, five smart constructors

```ocaml
(* Name.t gains, in this order (Name order is the order [Attrs.diff] emits Sets in, so
   keep related attrs adjacent): *)
  | Opacity
  | Focusable
  | Can_focus
  | Widget_name
  | Cursor_name

(* t gains: *)
  | Opacity of float
  | Focusable of bool
  | Can_focus of bool
  | Widget_name of string
  | Cursor_name of string

(* name: *)
  | Opacity _ -> Some Name.Opacity
  | Focusable _ -> Some Focusable
  | Can_focus _ -> Some Can_focus
  | Widget_name _ -> Some Widget_name
  | Cursor_name _ -> Some Cursor_name

(* equal: *)
  | Opacity a, Opacity b -> Float.equal a b
  | Focusable a, Focusable b | Can_focus a, Can_focus b -> Bool.equal a b
  | Widget_name a, Widget_name b | Cursor_name a, Cursor_name b -> String.equal a b

(* constructors: *)
let opacity f = Opacity f
let focusable b = Focusable b
let can_focus b = Can_focus b
let widget_name s = Widget_name s
let cursor_name s = Cursor_name s
```

mli doc comments worth writing, because each is a trap:
- `opacity`: "0. is fully transparent, 1. fully opaque. GTK still lays the widget out and still routes input to it — use `visible false` to take it out of the layout."
- `focusable` / `can_focus`: "`focusable` is whether the widget takes keyboard focus itself; `can_focus` is whether focus may travel *into* it or its children. GTK's defaults differ per widget class (a `GtkButton` is focusable, a `GtkLabel` is not), so unsetting either restores that widget's own class default rather than a constant."
- `cursor_name`: "A CSS cursor name — `pointer`, `text`, `not-allowed`, `default`. An unknown name is GTK's problem, not ours: it logs and falls back."

- [ ] **Step 5: `src/attr_apply.ml(i)` — the defaults snapshot**

```ocaml
open! Core
open Bonsai_gtk_vtree
open Gtk_import

let align : Align.t -> Gtk_enums.align = function
  | Fill -> `FILL
  | Start -> `START
  | End -> `END
  | Center -> `CENTER
  | Baseline -> `BASELINE_FILL
;;

(* Everything [unset] has to be able to put back. Read once off a freshly created widget,
   before any attr has been applied to it, so it is that widget class's own default rather
   than a constant this module would otherwise have to guess per kind ([focusable] is
   false on a label and true on a button; [visible] is true on most widgets and false on a
   GtkWindow, which is the case the M0 review caught). *)
type defaults =
  { margin_start : int
  ; margin_end : int
  ; margin_top : int
  ; margin_bottom : int
  ; halign : Gtk_enums.align
  ; valign : Gtk_enums.align
  ; hexpand : bool
  ; vexpand : bool
  ; sensitive : bool
  ; visible : bool
  ; tooltip : string option
  ; size_request : int * int
  ; opacity : float
  ; focusable : bool
  ; can_focus : bool
  ; widget_name : string
  ; cursor : Ocgtk_gdk.Gdk.Wrappers.Cursor.t option
  }

let snapshot (w : Widget.t) =
  { margin_start = Widget.get_margin_start w
  ; margin_end = Widget.get_margin_end w
  ; margin_top = Widget.get_margin_top w
  ; margin_bottom = Widget.get_margin_bottom w
  ; halign = Widget.get_halign w
  ; valign = Widget.get_valign w
  ; hexpand = Widget.get_hexpand w
  ; vexpand = Widget.get_vexpand w
  ; sensitive = Widget.get_sensitive w
  ; visible = Widget.get_visible w
  ; tooltip = Widget.get_tooltip_text w
  ; size_request = Widget.get_size_request w
  ; opacity = Widget.get_opacity w
  ; focusable = Widget.get_focusable w
  ; can_focus = Widget.get_can_focus w
  ; widget_name = Widget.get_name w
  ; cursor = Widget.get_cursor w
  }
;;

(* GTK exposes width and height as a single [set_size_request] call, so setting one
   requires reading the current pair back to preserve the other. *)
let set_width (w : Widget.t) width =
  let _, height = Widget.get_size_request w in
  Widget.set_size_request w width height
;;

let set_height (w : Widget.t) height =
  let width, _ = Widget.get_size_request w in
  Widget.set_size_request w width height
;;

let set (w : Widget.t) (attr : Attr.t) =
  match attr with
  | Css_class c -> Widget.add_css_class w c
  | Margin_start n -> Widget.set_margin_start w n
  | Margin_end n -> Widget.set_margin_end w n
  | Margin_top n -> Widget.set_margin_top w n
  | Margin_bottom n -> Widget.set_margin_bottom w n
  | Halign a -> Widget.set_halign w (align a)
  | Valign a -> Widget.set_valign w (align a)
  | Hexpand b -> Widget.set_hexpand w b
  | Vexpand b -> Widget.set_vexpand w b
  | Sensitive b -> Widget.set_sensitive w b
  | Visible b -> Widget.set_visible w b
  | Tooltip s -> Widget.set_tooltip_text w (Some s)
  | Width_request n -> set_width w n
  | Height_request n -> set_height w n
  | Opacity f -> Widget.set_opacity w f
  | Focusable b -> Widget.set_focusable w b
  | Can_focus b -> Widget.set_can_focus w b
  | Widget_name s -> Widget.set_name w s
  | Cursor_name s -> Widget.set_cursor_from_name w (Some s)
  (* [Test_id] is inert at runtime; the [On_*] attrs are handled by [Signals]; the
     container-placement attrs ([Measure_overlay], [Page_title], [Grid_cell]) are read by
     the *parent* impl's child ops, not applied to the child. [Many] is flattened away by
     [Attrs.of_list] and never reaches here. *)
  | Test_id _ | Many _ -> ()
  | On_clicked _ -> ()
;;

let unset (d : defaults) (w : Widget.t) (name : Attr.Name.t) =
  match name with
  | Margin_start -> Widget.set_margin_start w d.margin_start
  | Margin_end -> Widget.set_margin_end w d.margin_end
  | Margin_top -> Widget.set_margin_top w d.margin_top
  | Margin_bottom -> Widget.set_margin_bottom w d.margin_bottom
  | Halign -> Widget.set_halign w d.halign
  | Valign -> Widget.set_valign w d.valign
  | Hexpand -> Widget.set_hexpand w d.hexpand
  | Vexpand -> Widget.set_vexpand w d.vexpand
  | Sensitive -> Widget.set_sensitive w d.sensitive
  | Visible -> Widget.set_visible w d.visible
  | Tooltip -> Widget.set_tooltip_text w d.tooltip
  | Width_request -> set_width w (fst d.size_request)
  | Height_request -> set_height w (snd d.size_request)
  | Opacity -> Widget.set_opacity w d.opacity
  | Focusable -> Widget.set_focusable w d.focusable
  | Can_focus -> Widget.set_can_focus w d.can_focus
  | Widget_name -> Widget.set_name w d.widget_name
  | Cursor_name -> Widget.set_cursor w d.cursor
  | Test_id -> ()
  | On_clicked -> ()
;;

let apply ~defaults w (op : Attrs.op) =
  match op with
  | Set a -> set w a
  | Unset n -> unset defaults w n
  | Add_css_class c -> Widget.add_css_class w c
  | Remove_css_class c -> Widget.remove_css_class w c
;;

let apply_all w attrs = List.iter (Attrs.to_list attrs) ~f:(set w)
```

`src/dune`: add `ocgtk.gdkpixbuf`? No — `Ocgtk_gdk` is already there via `ocgtk.gdk`. Add only `ocgtk.pango` (Step 6 needs it).

The mli replaces the old `Width_request`/`Height_request` paragraph with:

```ocaml
(** Every attribute value [unset] can restore, read off a widget before anything has been
    applied to it. Take one per widget at creation and keep it for the widget's lifetime;
    it is what makes "drop this attribute" mean "put back whatever GTK had", which differs
    per widget class ([focusable] on a button vs a label, [visible] on a window vs
    anything else) and which no constant could get right for all of them. *)
type defaults

val snapshot : Widget.t -> defaults
```

- [ ] **Step 6: `src/patcher.ml`** — `live` carries the defaults

```ocaml
type live =
  { mutable node : Node.t
  ; widget : Widget.t
  ; impl : Widget_impl.t
  ; defaults : Attr_apply.defaults
  ; slots : Signals.slots
  ; handler_ids : Gobject.Signal.handler_id list
  ; mutable children : live Children.t
  }
```

In `mount`, between `create` and `apply_all`:

```ocaml
  let widget = impl.create node.kind in
  (* Before any attr touches it: this is the widget class's own defaults. *)
  let defaults = Attr_apply.snapshot widget in
  Attr_apply.apply_all widget node.attrs;
```
and in `patch`, `~f:(Attr_apply.apply ~defaults:live.defaults live.widget)`.

- [ ] **Step 7: `vtree/kind.ml(i)` and `vtree/node.ml(i)`** — Label's props

```ocaml
  | Label of
      { text : string
      ; wrap : bool
      ; xalign : float
      ; ellipsize : Ellipsize.t option
      ; max_width_chars : int
      ; width_chars : int
      ; selectable : bool
      ; use_markup : bool
      }
```

`equal_props`:
```ocaml
  | Label a, Label b ->
    String.equal a.text b.text
    && Bool.equal a.wrap b.wrap
    && Float.equal a.xalign b.xalign
    && Option.equal Ellipsize.equal a.ellipsize b.ellipsize
    && a.max_width_chars = b.max_width_chars
    && a.width_chars = b.width_chars
    && Bool.equal a.selectable b.selectable
    && Bool.equal a.use_markup b.use_markup
```

`Node.label` — every default is GTK's own, so a `Node.label "x"` still produces the widget M0 produced:
```ocaml
let label
  ?key
  ?attrs
  ?(wrap = false)
  ?(xalign = 0.5)
  ?ellipsize
  ?(max_width_chars = -1)
  ?(width_chars = -1)
  ?(selectable = false)
  ?(use_markup = false)
  text
  =
  make
    ?key
    ?attrs
    (Label
       { text; wrap; xalign; ellipsize; max_width_chars; width_chars; selectable; use_markup })
    No_children
;;
```

- [ ] **Step 8: `src/widgets/w_label.ml`**

```ocaml
open! Core
open Bonsai_gtk_vtree
open Gtk_import

let ellipsize : Ellipsize.t option -> Ocgtk_pango.Pango.ellipsizemode = function
  | None -> `NONE
  | Some Start -> `START
  | Some Middle -> `MIDDLE
  | Some End -> `END
;;

(* Only the props that differ are written: [set_text] and [set_markup] both reset the
   label's attribute list, and [set_ellipsize] forces a re-layout. *)
let apply_props (l : W.Label.t) (p : Kind.label_props) ~(old : Kind.label_props option) =
  let changed field equal = match old with
    | None -> true
    | Some o -> not (equal (field o) (field p))
  in
  if changed (fun p -> p.Kind.text) String.equal
     || changed (fun p -> p.Kind.use_markup) Bool.equal
  then if p.use_markup then W.Label.set_markup l p.text else W.Label.set_text l p.text;
  if changed (fun p -> p.Kind.wrap) Bool.equal then W.Label.set_wrap l p.wrap;
  if changed (fun p -> p.Kind.xalign) Float.equal then W.Label.set_xalign l p.xalign;
  if changed (fun p -> p.Kind.ellipsize) (Option.equal Ellipsize.equal)
  then W.Label.set_ellipsize l (ellipsize p.ellipsize);
  if changed (fun p -> p.Kind.max_width_chars) Int.equal
  then W.Label.set_max_width_chars l p.max_width_chars;
  if changed (fun p -> p.Kind.width_chars) Int.equal
  then W.Label.set_width_chars l p.width_chars;
  if changed (fun p -> p.Kind.selectable) Bool.equal
  then W.Label.set_selectable l p.selectable
;;

let impl : Widget_impl.t =
  { name = "Label"
  ; create =
      (fun (kind : Kind.t) ->
        match kind with
        | Label p ->
          let l = W.Label.new_ None in
          apply_props l p ~old:None;
          (l :> Widget.t)
        | k -> Widget_impl.wrong_kind "Label" k)
  ; update =
      (fun w ~(old : Kind.t) (new_ : Kind.t) ->
        match old, new_ with
        | Label old, Label new_ -> apply_props (cast w) new_ ~old:(Some old)
        | _, k -> Widget_impl.wrong_kind "Label" k)
  ; signals = []
  ; children = Widget_impl.No_children
  }
;;
```

This needs the inline record to be nameable. Give `Kind` a named props type rather than an inline record for `Label`:

```ocaml
(* vtree/kind.ml(i) *)
type label_props =
  { text : string
  ; wrap : bool
  ; xalign : float
  ; ellipsize : Ellipsize.t option
  ; max_width_chars : int
  ; width_chars : int
  ; selectable : bool
  ; use_markup : bool
  }
[@@deriving sexp_of, equal]

type t =
  | Label of label_props
  | ...
```
and use `Kind.equal_label_props` in `equal_props` instead of the hand-written conjunction. **Adopt this shape for every M1 widget**: a named `<widget>_props` record with `[@@deriving sexp_of, equal]`, so `equal_props` is one call per kind and impls can name the record. Migrate `Button`/`Box`/`Window` to it in this task too — three small mechanical edits that every later task benefits from. `Kind.t`'s sexp changes shape slightly (an inline record and a named one print the same, so expect files are unaffected — confirm by running the suite).

- [ ] **Step 9: `src/live_tree.ml`** — print the new widget-wide props and the label ones

```ocaml
let float_prop name value ~default =
  if Float.equal value default
  then []
  else [ Sexp.List [ Atom name; Atom (sprintf "%g" value) ] ]
;;

let string_prop name value ~default =
  if String.equal value default then [] else [ Sexp.List [ Atom name; Atom value ] ]
;;
```
extend `layout_props` with `float_prop "opacity" (Widget.get_opacity w) ~default:1.`, `string_prop "name" (Widget.get_name w) ~default:""`, and a `cursor` line: `(match Widget.get_cursor w with None -> [] | Some c -> [ Sexp.List [ Atom "cursor"; Atom (Option.value (Ocgtk_gdk.Gdk.Wrappers.Cursor.get_name c) ~default:"?") ] ])`. Do **not** print `focusable`/`can_focus`: their defaults are per class, so an unconditional print would churn every expected file; print them only when they differ from the value a freshly created widget of that type has, which the dump has no access to. Instead, cover them in the attr round-trip section of the live test, which sets and then unsets them and asserts the *dump is identical* to a widget that never had them.

In `dump`'s per-type match, extend the `"GtkLabel"` arm:
```ocaml
     | "GtkLabel" ->
       let l = cast w in
       [ [%sexp `text (W.Label.get_text l : string)] ]
       @ flag_prop "wrap" (W.Label.get_wrap l)
       @ float_prop "xalign" (W.Label.get_xalign l) ~default:0.5
       @ (match W.Label.get_ellipsize l with
          | `NONE -> []
          | e -> [ Sexp.List [ Atom "ellipsize"; Atom (Sexp.to_string [%sexp (e : [`NONE|`START|`MIDDLE|`END])]) ] ])
       @ int_prop "max-width-chars" (W.Label.get_max_width_chars l) ~default:(-1)
       @ int_prop "width-chars" (W.Label.get_width_chars l) ~default:(-1)
       @ flag_prop "selectable" (W.Label.get_selectable l)
```
(The ellipsize polymorphic variant has no `sexp_of`; if `[%sexp]` on it does not compile, write a three-line `ellipsize_name` function beside `align_name` — that is the pattern `Live_tree` already uses.)

- [ ] **Step 10: Extend `test/live/live_patcher.ml`'s attr section**

In the existing `attr_view` block, add the five new attrs to the set-then-unset list:
```ocaml
         ; Attr.opacity 0.5
         ; Attr.focusable true
         ; Attr.can_focus false
         ; Attr.widget_name "styled-label"
         ; Attr.cursor_name "pointer"
```
and add, after it, the case the defaults snapshot exists for — unsetting `visible` on a window must not turn a window visible:
```ocaml
  (* A [GtkWindow] is created hidden; a [GtkLabel] is created visible. "Unset" means "put
     back what this widget had", not a constant, so the same op restores different values
     here. *)
  let live = P.mount ctx ~path:"root" ~is_root:true (Node.window ~attrs:[ Attr.visible true ] ~title:"vis" (Node.label ~attrs:[ Attr.visible false ] "l")) in
  print_s (Live_tree.dump live.widget);
  let live = P.patch ctx ~path:"root" ~is_root:true live (Node.window ~title:"vis" (Node.label "l")) in
  print_s (Live_tree.dump live.widget);
  P.destroy ctx live;
```
Expected on the second dump: the window is `hidden` again and the label is not. Promote after reading.

- [ ] **Step 11: Run, promote, gate**

```
dune build @test/runtest && dune promote
BONSAI_GTK_LIVE_TESTS=1 xvfb-run -a dune build @test/live/runtest && dune promote
./scripts/ci.sh
```

- [ ] **Step 12: Commit**

```bash
dune fmt 2>/dev/null; git add vtree src test
GIT_EDITOR=true git commit -F - <<'MSG'
Widget-wide attrs (opacity, focus, name, cursor) and Label's text properties

Unsetting an attribute now restores the value the widget was created with,
snapshotted per widget at mount, rather than a constant guessed per attribute
-- which was already wrong for [visible] on a GtkWindow and would have been
wrong for [focusable] on every widget M1 adds.

Kind's props become named records so widget impls can name them.

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01Sg3Ci8U8kUKR8C3PL1pNSs
MSG
```

---

### Task 3: Signals carry a value — Button (extended), ToggleButton, CheckButton, Switch

The first task to add widgets, and the one that generalises `Signals`. M0's `Signals.spec.fire : Attr.t -> unit Effect.t option` can only build handlers that take no argument, because ocgtk's `on_*` callbacks are mostly `unit -> unit` and the value the user just changed lives on the widget. Spec §6.4 step 4 ("converts GTK arguments to the OCaml event value") is satisfied by giving `fire` the widget and reading the value back with the class getter — which is also exactly how the `notify::<prop>` family has to work, since the generic marshaller carries no payload at all.

**Files:**
- Create: `src/widgets/w_toggle_button.ml`, `src/widgets/w_check_button.ml`, `src/widgets/w_switch.ml`, `test/live/live_controls.ml`, `test/live/expected_controls.txt`
- Modify: `src/signals.ml`, `src/signals.mli`, `src/widget_impl.ml`, `src/widget_impl.mli`, `src/patcher.ml`, `src/widgets/w_button.ml`, `src/widgets/registry.ml`, `src/live_tree.ml`, `vtree/attr.ml(i)`, `vtree/kind.ml(i)`, `vtree/node.ml(i)`, `test_lib/bonsai_gtk_test.ml(i)`, `test/test_widgets.ml`, `test/test_handle.ml`, `test/live/dune`

**Interfaces:**
- Produces:
  ```ocaml
  (* Signals *)
  type spec =
    { attr : Attr.Name.t
    ; connect : Widget.t -> callback:(unit -> unit) -> Gobject.Signal.handler_id
    ; fire : Widget.t -> Attr.t -> unit Ui_effect.t option
    }
  val notify : prop:string -> Widget.t -> callback:(unit -> unit) -> Gobject.Signal.handler_id
  val require_specs : node_path:string -> impl_name:string -> spec list -> Attrs.t -> unit

  (* Widget_impl *)
  val batch : Widget.t -> (unit -> unit) -> unit   (* freeze_notify / thaw_notify *)

  (* Attr *)
  val on_toggled : (bool -> unit Ui_effect.t) -> t

  (* Node *)
  val button
    :  ?key:Key.t -> ?attrs:Attr.t list -> ?label:string -> ?icon_name:string
    -> ?has_frame:bool -> ?child:t -> unit -> t
  val toggle_button
    :  ?key:Key.t -> ?attrs:Attr.t list -> ?label:string -> ?icon_name:string
    -> ?has_frame:bool -> ?child:t -> active:bool -> unit -> t
  val check_button
    :  ?key:Key.t -> ?attrs:Attr.t list -> ?label:string -> ?inconsistent:bool
    -> active:bool -> unit -> t
  val switch : ?key:Key.t -> ?attrs:Attr.t list -> active:bool -> unit -> t

  (* Bonsai_gtk_test.Action *)
  type t = Click of string | Toggle of string
  ```
- Consumes: `W.Button.{new_,new_with_label,new_from_icon_name,set_label,set_icon_name,set_has_frame,set_child,on_clicked}`, `W.Toggle_button.{new_,set_active,get_active,on_toggled}`, `W.Check_button.{new_,set_label,set_active,get_active,set_inconsistent,set_child,on_toggled}`, `W.Switch.{new_,set_active,get_active,set_state}`, `Gobject.Signal.connect_simple`, `Gobject.Property.{freeze_notify,thaw_notify}`.

Three shape notes before the code:

1. **Button gains a child slot.** Spec §5.1 gives `button` a `?child`. `Widget_impl.children` is fixed per kind, so `Button` becomes `Single` and `Node.button` always produces `Single child_opt` — a plain `~label:"+"` button now has `(children (Single ()))` instead of `(children No_children)` in its sexp. Update `test/test_node.ml`, `test/test_handle.ml` and the live expected files accordingly; they are the only readers.
2. **Switch has no `toggled`.** GTK4's `GtkSwitch` emits `state-set` (whose callback returns `bool`, "handled") and `notify::active`. `state-set` is the wrong hook for a controlled widget — returning `true` suppresses GTK's own state update and desynchronises `active` from `state`. Connect `notify::active` and read `get_active`. Documented on `Node.switch`.
3. **An event attr on a widget that cannot emit it is an error.** `Attr.on_toggled` on a `Node.label` is a typo the library should catch, and spec §5.1 says so. `Signals.require_specs` checks, at mount, that every `On_*` attr in the node's attrs is claimed by one of the impl's specs, and raises `Invalid_argument` with the node path otherwise. It needs to know which names are event names: add `Attr.Name.is_event : t -> bool` (a match listing the `On_*` constructors) beside it.

- [ ] **Step 1: Write the failing headless tests** (`test/test_widgets.ml`, append)

```ocaml
let%expect_test "the toggle family's constructors" =
  print_s
    [%sexp
      (Node.box
         ~orientation:Vertical
         [ Node.button ~label:"go" ()
         ; Node.button ~icon_name:"list-add-symbolic" ~has_frame:false ()
         ; Node.button ~child:(Node.label "boxed") ()
         ; Node.toggle_button ~label:"bold" ~active:true ()
         ; Node.check_button ~label:"agree" ~active:false ()
         ; Node.switch ~active:true ()
         ]
       : Node.t)];
  [%expect {| |}]
;;
```

`test/test_handle.ml` — a component whose state is driven by a `Toggle` action, which is the whole reason `Bonsai_gtk_test` grows one:

```ocaml
let toggler (graph @ local) =
  let on, set_on = Bonsai.state false graph in
  let%arr on and set_on in
  Node.window
    ~title:"Toggler"
    (Node.box
       ~orientation:Vertical
       [ Node.switch ~attrs:[ Attr.test_id "sw"; Attr.on_toggled set_on ] ~active:on ()
       ; Node.label ~attrs:[ Attr.test_id "state" ] (if on then "on" else "off")
       ])
;;

let%expect_test "Toggle fires the handler with the value the widget would take" =
  let handle = Bonsai_gtk_test.create toggler in
  Bonsai_gtk_test.Handle.show handle;
  [%expect {| |}];
  Bonsai_gtk_test.Handle.do_actions handle [ Toggle "sw" ];
  Bonsai_gtk_test.Handle.show_diff handle;
  [%expect {| |}]
;;
```

- [ ] **Step 2: Write the failing live test** (`test/live/live_controls.ml`)

This file grows through Tasks 3–5; start it with the toggle family, and with the end-to-end reentrancy case the backlog wants — a widget whose *programmatic* update emits its own signal.

```ocaml
open! Core
open Bonsai_gtk_vtree
module Gobject = Bonsai_gtk.Private.Gtk_import.Gobject
module Live_tree = Bonsai_gtk.Private.Live_tree
module P = Bonsai_gtk.Private.Patcher
module Scheduler = Bonsai_gtk.Private.Scheduler

let nth_child (live : P.live) i : P.live =
  match live.children with
  | Single (Some box) ->
    (match box.children with
     | List children -> List.nth_exn children i
     | _ -> assert false)
  | _ -> assert false
;;

let () =
  ignore (Ocgtk_gtk.GMain.init () : string array);
  let scheduled = ref 0 in
  let scheduler = Scheduler.create ~run_frame:(fun () -> ()) in
  let ctx : P.ctx =
    { signals =
        { schedule = (fun _ -> incr scheduled)
        ; in_patch = (fun () -> Scheduler.in_patch scheduler)
        ; on_exn = (fun ~node_path exn -> printf "EXN at %s: %s\n" node_path (Exn.to_string exn))
        }
    ; on_window_created = (fun _ -> ())
    }
  in
  let view ~active =
    Node.window
      ~title:"controls"
      (Node.box
         ~orientation:Vertical
         [ Node.button ~label:"plain" ()
         ; Node.button ~icon_name:"list-add-symbolic" ~has_frame:false ()
         ; Node.button ~child:(Node.label "boxed") ()
         ; Node.toggle_button
             ~attrs:[ Attr.on_toggled (fun _ -> Ui_effect.Ignore) ]
             ~label:"bold"
             ~active
             ()
         ; Node.check_button
             ~attrs:[ Attr.on_toggled (fun _ -> Ui_effect.Ignore) ]
             ~label:"agree"
             ~active
             ()
         ; Node.switch ~attrs:[ Attr.on_toggled (fun _ -> Ui_effect.Ignore) ] ~active ()
         ])
  in
  let live = P.mount ctx ~path:"root" ~is_root:true (view ~active:false) in
  print_s (Live_tree.dump live.widget);
  (* THE reentrancy case the M0 backlog asks for: flipping [active] from the model makes
     GTK emit [toggled] / [notify::active] synchronously, inside the patch. Nothing may
     reach Bonsai from there -- the model is the single source of truth (spec §4.4). *)
  let before = !scheduled in
  let live =
    Scheduler.with_patch_guard scheduler (fun () ->
      P.patch ctx ~path:"root" ~is_root:true live (view ~active:true))
  in
  printf "scheduled during patch: %d\n" (!scheduled - before);
  print_s (Live_tree.dump live.widget);
  (* Outside the patch the same signals do reach Bonsai. *)
  Gobject.Signal.emit_by_name (nth_child live 3).widget ~name:"toggled";
  Gobject.Signal.emit_by_name (nth_child live 4).widget ~name:"toggled";
  printf "scheduled outside patch: %d\n" (!scheduled - before);
  (* An event attr the widget cannot emit is a typo, and a loud one. *)
  (match
     P.mount
       ctx
       ~path:"root"
       ~is_root:true
       (Node.window ~title:"bad" (Node.label ~attrs:[ Attr.on_toggled (fun _ -> Ui_effect.Ignore) ] "x"))
   with
   | (_ : P.live) -> print_endline "BUG: on_toggled on a label accepted"
   | exception Invalid_argument msg -> printf "rejected: %s\n" msg);
  P.destroy ctx live
;;
```

Add `live_controls` to `test/live/dune`'s `(names ...)` and a matching rule (copy the `live_signals` one).

- [ ] **Step 3: Run to verify failure** — both suites; unbound `Node.toggle_button`, `Attr.on_toggled`, `Scheduler.create` not exported.
`Scheduler` is already in `Bonsai_gtk.Private`; check `scheduler.mli` exposes `create`, `in_patch`, `with_patch_guard` and add them if not.

- [ ] **Step 4: `src/signals.ml(i)`**

```ocaml
type spec =
  { attr : Attr.Name.t
  ; connect : Widget.t -> callback:(unit -> unit) -> Gobject.Signal.handler_id
  ; fire : Widget.t -> Attr.t -> unit Ui_effect.t option
  }

let dispatch ctx w slot spec =
  if ctx.in_patch ()
  then ()
  else (
    match !slot with
    | None -> ()
    | Some attr ->
      (match spec.fire w attr with
       | None -> ()
       | Some effect -> ctx.schedule effect))
;;

(* [connect_all] is otherwise unchanged; the callback becomes
   [fun () -> match dispatch ctx w slot spec with ...]. *)

(* ocgtk generates no [on_notify_*]: detailed signal names go through the generic
   marshaller, which carries no payload, so the handler reads the property back off the
   widget with the class getter (spec §6.4). [~after:false] matches every generated
   [on_*], which defaults [?after] to false. *)
let notify ~prop w ~callback =
  Gobject.Signal.connect_simple w ~name:("notify::" ^ prop) ~callback ~after:false
;;

(* An [on_*] attr on a widget whose impl declares no spec for it is a typo that would
   otherwise be silently inert -- the slot is never written, so the handler never runs and
   nothing says why (spec §5.1, §11). *)
let require_specs ~node_path ~impl_name specs attrs =
  List.iter (Attrs.to_list attrs) ~f:(fun attr ->
    match Attr.name attr with
    | Some name when Attr.Name.is_event name ->
      if not (List.exists specs ~f:(fun s -> Attr.Name.equal s.attr name))
      then
        invalid_argf
          !"%s: %s does not emit %{sexp:Attr.Name.t}"
          node_path
          impl_name
          name
          ()
    | Some _ | None -> ())
;;
```

`Attr.Name.is_event`, in `vtree/attr.ml(i)`:
```ocaml
(** [true] for the handler-carrying names -- the ones a widget impl must declare a signal
    spec for. *)
let is_event = function
  | On_clicked | On_toggled -> true
  | Margin_start | Margin_end | Margin_top | Margin_bottom | Halign | Valign | Hexpand
  | Vexpand | Sensitive | Visible | Tooltip | Width_request | Height_request | Opacity
  | Focusable | Can_focus | Widget_name | Cursor_name | Test_id -> false
;;
```
Write it as an exhaustive match, never a `_ -> false`: every task below adds `On_*` names, and the compiler must force each one to be classified.

Call it from `Patcher.mount`, right before `connect_all`:
```ocaml
  Signals.require_specs ~node_path:path ~impl_name:impl.name impl.signals node.attrs;
```

- [ ] **Step 5: `src/widget_impl.ml(i)` — `batch`**

```ocaml
(* Spec §7: a prop batch is bracketed, so GTK emits one round of [notify::] at the end
   rather than one per setter -- which matters here beyond tidiness, because every
   [notify::] we emit is one the [in_patch] guard has to swallow. [protect] rather than a
   bare pair: an exception between the two would leave the object frozen forever. *)
let batch (w : Widget.t) f =
  Gobject.Property.freeze_notify w;
  Exn.protect ~f ~finally:(fun () -> Gobject.Property.thaw_notify w)
;;
```
Use it in every `update` that writes more than one property, starting with the impls below.

- [ ] **Step 6: `vtree/attr.ml(i)`** — `On_toggled of bool Handler.t`

```ocaml
(* Name.t: *) | On_toggled
(* t:      *) | On_toggled of bool Handler.t
(* name:   *) | On_toggled _ -> Some On_toggled
(* equal:  *) | On_toggled a, On_toggled b -> Handler.equal a b

(** Fires when the user flips a [toggle_button], [check_button] or [switch], carrying the
    value the widget now has. Programmatic changes -- the ones a re-render makes -- do not
    fire it: the patcher's reentrancy guard drops them, because the model is already the
    source of that value. *)
let on_toggled f = On_toggled f
```
Add `| On_toggled _ -> ()` to `Attr_apply.set` and `| On_toggled -> ()` to `unset`.

- [ ] **Step 7: `vtree/kind.ml(i)` / `node.ml(i)`**

```ocaml
type button_props =
  { label : string option
  ; icon_name : string option
  ; has_frame : bool
  }
[@@deriving sexp_of, equal]

type toggle_button_props =
  { label : string option
  ; icon_name : string option
  ; has_frame : bool
  ; active : bool
  }
[@@deriving sexp_of, equal]

type check_button_props =
  { label : string option
  ; active : bool
  ; inconsistent : bool
  }
[@@deriving sexp_of, equal]

type switch_props = { active : bool } [@@deriving sexp_of, equal]

type t =
  | Label of label_props
  | Button of button_props
  | Toggle_button of toggle_button_props
  | Check_button of check_button_props
  | Switch of switch_props
  | Box of box_props
  | Window of window_props
  | Native of Native.t
```
`name`: `"Button" | "ToggleButton" | "CheckButton" | "Switch"`. `same_kind`: one arm each. `equal_props`: `equal_button_props a b`, etc.

```ocaml
let button ?key ?attrs ?label ?icon_name ?(has_frame = true) ?child () =
  make ?key ?attrs (Button { label; icon_name; has_frame }) (Single child)
;;

let toggle_button ?key ?attrs ?label ?icon_name ?(has_frame = true) ?child ~active () =
  make ?key ?attrs (Toggle_button { label; icon_name; has_frame; active }) (Single child)
;;

let check_button ?key ?attrs ?label ?(inconsistent = false) ~active () =
  make ?key ?attrs (Check_button { label; active; inconsistent }) (Single None)
;;

let switch ?key ?attrs ~active () = make ?key ?attrs (Switch { active }) No_children
```
`check_button` takes no `?child`: GTK allows one, but a check button with both a label and a child is a GTK warning, and `?label` covers every real use. Note it in the mli.

mli doc comments to write:
- `button`: "`label`, `icon_name` and `child` are alternatives; giving more than one is a GTK warning, and the last one GTK applies wins. `has_frame:false` is the flat/ghost button stavekeeper spells `stk-btn-ghost`."
- `toggle_button` / `check_button` / `switch`: "`active` is *controlled*: the widget is written only when the model's value differs from what the widget currently shows, so a model that ignores `Attr.on_toggled` pins the widget rather than fighting the user. Pair it with `Attr.on_toggled` or the control is inert."
- `switch`: "GTK's `state-set` signal is deliberately not exposed: returning `true` from it suppresses GTK's own state update and desynchronises `state` from `active`. `Attr.on_toggled` is `notify::active`."

- [ ] **Step 8: `src/widgets/w_button.ml`**

```ocaml
open! Core
open Bonsai_gtk_vtree
open Gtk_import

let clicked : Signals.spec =
  { attr = Attr.Name.On_clicked
  ; connect = (fun w ~callback -> W.Button.on_clicked (cast w) ~callback)
  ; fire =
      (fun _w (attr : Attr.t) ->
        match attr with
        | On_clicked handler -> Some (handler ())
        | _ -> None)
  }
;;

(* Shared with [w_toggle_button.ml]: a GtkToggleButton *is* a GtkButton, so the label /
   icon-name / has-frame props are set through the same calls. *)
let apply_button_props
  (b : W.Button.t)
  ~(old : (string option * string option * bool) option)
  ~label
  ~icon_name
  ~has_frame
  =
  let changed get = match old with
    | None -> true
    | Some o -> not (Poly.equal (get o) (get (label, icon_name, has_frame)))
  in
  if changed (fun (l, _, _) -> l)
  then
    (* GTK has no "unset label"; [set_label ""] is the closest thing, and it is what a
       [None] label renders as anyway. *)
    W.Button.set_label b (Option.value label ~default:"");
  if changed (fun (_, i, _) -> i)
  then Option.iter icon_name ~f:(W.Button.set_icon_name b);
  if changed (fun (_, _, f) -> f) then W.Button.set_has_frame b has_frame
;;

let impl : Widget_impl.t =
  { name = "Button"
  ; create =
      (fun (kind : Kind.t) ->
        match kind with
        | Button p ->
          let b =
            match p.icon_name, p.label with
            | Some icon, _ -> W.Button.new_from_icon_name icon
            | None, Some label -> W.Button.new_with_label label
            | None, None -> W.Button.new_ ()
          in
          if not p.has_frame then W.Button.set_has_frame b false;
          (b :> Widget.t)
        | k -> Widget_impl.wrong_kind "Button" k)
  ; update =
      (fun w ~(old : Kind.t) (new_ : Kind.t) ->
        match old, new_ with
        | Button old, Button new_ ->
          Widget_impl.batch w (fun () ->
            apply_button_props
              (cast w)
              ~old:(Some (old.label, old.icon_name, old.has_frame))
              ~label:new_.label
              ~icon_name:new_.icon_name
              ~has_frame:new_.has_frame)
        | _, k -> Widget_impl.wrong_kind "Button" k)
  ; signals = [ clicked ]
  ; children = Widget_impl.Single { set = (fun w child -> W.Button.set_child (cast w) child) }
  }
;;
```

`icon_name` is set only when present, never cleared: `Button.set_icon_name` takes a plain `string`, so there is no "no icon" value, and switching a button from an icon back to a label is expressed by setting the label (which replaces the icon child). Say so in the mli.

- [ ] **Step 9: `src/widgets/w_toggle_button.ml`**

```ocaml
open! Core
open Bonsai_gtk_vtree
open Gtk_import

let toggled : Signals.spec =
  { attr = Attr.Name.On_toggled
  ; connect = (fun w ~callback -> W.Toggle_button.on_toggled (cast w) ~callback)
  ; fire =
      (fun w (attr : Attr.t) ->
        match attr with
        | On_toggled handler -> Some (handler (W.Toggle_button.get_active (cast w)))
        | _ -> None)
  }
;;

let impl : Widget_impl.t =
  { name = "ToggleButton"
  ; create =
      (fun (kind : Kind.t) ->
        match kind with
        | Toggle_button p ->
          let b =
            match p.icon_name, p.label with
            | Some _, _ | None, _ -> W.Toggle_button.new_ ()
          in
          let as_button : W.Button.t = cast b in
          W_button.apply_button_props
            as_button
            ~old:None
            ~label:p.label
            ~icon_name:p.icon_name
            ~has_frame:p.has_frame;
          if p.active then W.Toggle_button.set_active b true;
          (b :> Widget.t)
        | k -> Widget_impl.wrong_kind "ToggleButton" k)
  ; update =
      (fun w ~(old : Kind.t) (new_ : Kind.t) ->
        match old, new_ with
        | Toggle_button old, Toggle_button new_ ->
          Widget_impl.batch w (fun () ->
            W_button.apply_button_props
              (cast w)
              ~old:(Some (old.label, old.icon_name, old.has_frame))
              ~label:new_.label
              ~icon_name:new_.icon_name
              ~has_frame:new_.has_frame;
            (* Controlled, per the global constraints: compare against what the widget
               currently shows, not against [old.active]. The user may have flipped it
               since the last render, and a model that chose not to follow must pin the
               widget back rather than skip the write. *)
            let b : W.Toggle_button.t = cast w in
            if not (Bool.equal (W.Toggle_button.get_active b) new_.active)
            then W.Toggle_button.set_active b new_.active)
        | _, k -> Widget_impl.wrong_kind "ToggleButton" k)
  ; signals = [ toggled ]
  ; children = Widget_impl.Single { set = (fun w child -> W.Button.set_child (cast w) child) }
  }
;;
```
The `match p.icon_name, p.label with Some _, _ | None, _ -> W.Toggle_button.new_ ()` is deliberate and should be written as plain `W.Toggle_button.new_ ()`: `GtkToggleButton` has `new_with_label` but no `new_from_icon_name`, so both props go through the shared setter path. Simplify it when writing the file.

- [ ] **Step 10: `src/widgets/w_check_button.ml`**

```ocaml
open! Core
open Bonsai_gtk_vtree
open Gtk_import

let toggled : Signals.spec =
  { attr = Attr.Name.On_toggled
  ; connect = (fun w ~callback -> W.Check_button.on_toggled (cast w) ~callback)
  ; fire =
      (fun w (attr : Attr.t) ->
        match attr with
        | On_toggled handler -> Some (handler (W.Check_button.get_active (cast w)))
        | _ -> None)
  }
;;

let impl : Widget_impl.t =
  { name = "CheckButton"
  ; create =
      (fun (kind : Kind.t) ->
        match kind with
        | Check_button p ->
          let c = W.Check_button.new_ () in
          W.Check_button.set_label c p.label;
          if p.active then W.Check_button.set_active c true;
          if p.inconsistent then W.Check_button.set_inconsistent c true;
          (c :> Widget.t)
        | k -> Widget_impl.wrong_kind "CheckButton" k)
  ; update =
      (fun w ~(old : Kind.t) (new_ : Kind.t) ->
        match old, new_ with
        | Check_button old, Check_button new_ ->
          let c : W.Check_button.t = cast w in
          Widget_impl.batch w (fun () ->
            if not (Option.equal String.equal old.label new_.label)
            then W.Check_button.set_label c new_.label;
            if not (Bool.equal old.inconsistent new_.inconsistent)
            then W.Check_button.set_inconsistent c new_.inconsistent;
            if not (Bool.equal (W.Check_button.get_active c) new_.active)
            then W.Check_button.set_active c new_.active)
        | _, k -> Widget_impl.wrong_kind "CheckButton" k)
  ; signals = [ toggled ]
  ; children = Widget_impl.No_children
  }
;;
```
Radio groups (`Check_button.set_group`) are out of scope: a group is a reference to a *sibling widget*, which the vtree cannot name, and modelling "which of these is chosen" in Bonsai state and rendering N check buttons is both simpler and what a Bonsai app wants. Say that in `Node.check_button`'s doc comment.

- [ ] **Step 11: `src/widgets/w_switch.ml`**

```ocaml
open! Core
open Bonsai_gtk_vtree
open Gtk_import

(* [state-set] is the signal that looks right and is not: its callback's [bool] return
   suppresses GTK's own state update, which desynchronises [state] from [active] the first
   time a handler returns [true]. ocgtk exposes no [on_notify_active], so this goes through
   the generic marshaller by detailed name (spec §6.4). *)
let toggled : Signals.spec =
  { attr = Attr.Name.On_toggled
  ; connect = Signals.notify ~prop:"active"
  ; fire =
      (fun w (attr : Attr.t) ->
        match attr with
        | On_toggled handler -> Some (handler (W.Switch.get_active (cast w)))
        | _ -> None)
  }
;;

let impl : Widget_impl.t =
  { name = "Switch"
  ; create =
      (fun (kind : Kind.t) ->
        match kind with
        | Switch { active } ->
          let s = W.Switch.new_ () in
          if active
          then (
            W.Switch.set_active s true;
            (* [active] is what the user asked for, [state] what the app has actually
               done about it. bonsai_gtk has no asynchronous confirmation step, so they
               are always equal; setting both keeps the switch from rendering its
               "pending" look. *)
            W.Switch.set_state s true);
          (s :> Widget.t)
        | k -> Widget_impl.wrong_kind "Switch" k)
  ; update =
      (fun w ~(old : Kind.t) (new_ : Kind.t) ->
        match old, new_ with
        | Switch _, Switch { active } ->
          let s : W.Switch.t = cast w in
          if not (Bool.equal (W.Switch.get_active s) active)
          then
            Widget_impl.batch w (fun () ->
              W.Switch.set_active s active;
              W.Switch.set_state s active)
        | _, k -> Widget_impl.wrong_kind "Switch" k)
  ; signals = [ toggled ]
  ; children = Widget_impl.No_children
  }
;;
```

- [ ] **Step 12: `src/widgets/registry.ml`** — three arms

```ocaml
  | Toggle_button _ -> W_toggle_button.impl
  | Check_button _ -> W_check_button.impl
  | Switch _ -> W_switch.impl
```

- [ ] **Step 13: `src/live_tree.ml`** — per-type props

```ocaml
     | "GtkToggleButton" ->
       [ [%sexp `label (W.Button.get_label (cast w) : string option)] ]
       @ flag_prop "active" (W.Toggle_button.get_active (cast w))
     | "GtkCheckButton" ->
       [ [%sexp `label (W.Check_button.get_label (cast w) : string option)] ]
       @ flag_prop "active" (W.Check_button.get_active (cast w))
       @ flag_prop "inconsistent" (W.Check_button.get_inconsistent (cast w))
     | "GtkSwitch" -> flag_prop "active" (W.Switch.get_active (cast w))
```
and extend the existing `"GtkButton"` arm with `@ (match W.Button.get_icon_name (cast w) with None -> [] | Some i -> [ Sexp.List [ Atom "icon"; Atom i ] ])` and `@ (if W.Button.get_has_frame (cast w) then [] else [ Sexp.Atom "frameless" ])`.

- [ ] **Step 14: `test_lib/bonsai_gtk_test.ml(i)` — the `Toggle` action**

```ocaml
module Action = struct
  type t =
    | Click of string
    | Toggle of string
  [@@deriving sexp_of]
end

let node_exn node id =
  match Node.find_by_test_id node id with
  | Some n -> n
  | None -> failwithf "Bonsai_gtk_test: no node with test_id %s" id ()
;;

(* The value a real toggle would take: whatever the node is *not* showing now. Reading it
   off the node rather than taking it as an argument is what makes the action mean "the
   user clicked this", which is the only thing a test can actually claim. *)
let current_active (node : Node.t) id =
  match node.kind with
  | Toggle_button { active; _ } | Check_button { active; _ } | Switch { active } -> active
  | k -> failwithf "Bonsai_gtk_test: %s (test_id %s) has no toggle state" (Kind.name k) id ()
;;

module Result_spec = struct
  type t = Node.t
  type incoming = Action.t

  let view node = Sexp.to_string_hum (Node.sexp_of_t node)

  let incoming node (action : Action.t) =
    match action with
    | Click id ->
      let n = node_exn node id in
      (match Attrs.find n.attrs On_clicked with
       | Some (On_clicked h) -> h ()
       | _ -> failwithf "Bonsai_gtk_test: node %s has no on_clicked handler" id ())
    | Toggle id ->
      let n = node_exn node id in
      (match Attrs.find n.attrs On_toggled with
       | Some (On_toggled h) -> h (not (current_active n id))
       | _ -> failwithf "Bonsai_gtk_test: node %s has no on_toggled handler" id ())
  ;;
end
```
The mli documents `Toggle`: "Fires the node's `on_toggled` with the negation of the `active` prop it currently renders — what clicking the real widget would produce. Fails if the node is not a toggle, or carries no handler."

- [ ] **Step 15: Run, read, promote, gate**

```
dune build @test/runtest && dune promote
BONSAI_GTK_LIVE_TESTS=1 xvfb-run -a dune build @test/live/runtest && dune promote
```
In `output_controls.txt`, read before promoting: `scheduled during patch: 0` (the claim), then `scheduled outside patch: 2`, and the second dump showing `active` on all three toggles. `output_patcher.txt` and `output_driver.txt` change here — the button's `(children (Single ()))` and the new `frameless`/`icon` props — so re-read those diffs too rather than promoting blind.
Then `./scripts/ci.sh`.

- [ ] **Step 16: Commit**

```bash
dune fmt 2>/dev/null; git add vtree src test test_lib
GIT_EDITOR=true git commit -F - <<'MSG'
ToggleButton, CheckButton, Switch; Button gains icon/child/frame

Signal specs now receive the widget, so a handler can carry the value GTK
just changed -- which is the only way to build one for the notify:: family,
whose generic marshaller carries no payload at all. An on_* attr on a widget
that declares no matching spec is now Invalid_argument at mount rather than
silently inert.

The toggles' [active] is controlled: written only when it differs from what
the widget shows, and the signals that write provokes are dropped by the
in_patch guard -- pinned by a live test, which is the end-to-end version of
the reentrancy case M0's backlog asked for.

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01Sg3Ci8U8kUKR8C3PL1pNSs
MSG
```

---

### Task 4: Controlled text — Entry, PasswordEntry, SearchEntry

Spec §6.5's rule, implemented for real. stavekeeper has three entries (`dialog.ml`'s `field`, `practice_bar.ml`'s `bpm_entry` and `link_entry`) and a search entry in `library_window.ml`; between them they set `placeholder_text`, `width_chars`, `text`, `hexpand`, and `search_delay`, and read text back on `changed`.

**Files:**
- Create: `src/widgets/w_entry.ml`, `src/widgets/w_password_entry.ml`, `src/widgets/w_search_entry.ml`
- Modify: `vtree/attr.ml(i)`, `vtree/kind.ml(i)`, `vtree/node.ml(i)`, `src/widgets/registry.ml`, `src/live_tree.ml`, `test_lib/bonsai_gtk_test.ml(i)`, `test/test_widgets.ml`, `test/test_handle.ml`, `test/live/live_controls.ml`

**Interfaces:**
- Produces:
  ```ocaml
  (* Attr *)
  val on_changed : (string -> unit Ui_effect.t) -> t          (* GtkEditable::changed *)
  val on_activate : unit Ui_effect.t -> t                      (* Enter pressed *)
  val on_search_changed : (string -> unit Ui_effect.t) -> t    (* SearchEntry, debounced *)

  (* Node *)
  val entry
    :  ?key:Key.t -> ?attrs:Attr.t list -> ?placeholder:string -> ?editable:bool
    -> ?visibility:bool -> ?width_chars:int -> ?max_width_chars:int -> ?xalign:float
    -> ?activates_default:bool -> text:string -> unit -> t
  val password_entry
    :  ?key:Key.t -> ?attrs:Attr.t list -> ?placeholder:string -> ?show_peek_icon:bool
    -> ?activates_default:bool -> text:string -> unit -> t
  val search_entry
    :  ?key:Key.t -> ?attrs:Attr.t list -> ?placeholder:string -> ?search_delay:int
    -> text:string -> unit -> t

  (* Bonsai_gtk_test.Action *)
  | Set_text of string * string
  | Activate of string
  ```
- Consumes: `W.Editable.{from_gobject,get_text,set_text,set_editable,set_width_chars,set_max_width_chars,set_alignment,on_changed}`, `W.Entry.{new_,set_placeholder_text,set_visibility,set_activates_default,on_activate}`, `W.Password_entry.{new_,set_show_peek_icon,set_placeholder_text,set_activates_default,on_activate}`, `W.Search_entry.{new_,set_placeholder_text,set_search_delay,on_search_changed,on_activate}`.

Three facts from ocgtk that shape the code:

- All three widgets implement `GtkEditable`, and `W.Editable.from_gobject : 'a Gobject.obj -> t` is how you get there. Text, editability, width-chars, max-width-chars and alignment all go through `Editable`, and so does `changed` — one spec serves all three widgets.
- `Password_entry.set_placeholder_text : t -> string -> unit` takes a plain string, unlike `Entry`'s and `Search_entry`'s `string option`. Pass `Option.value ~default:""`.
- `Search_entry` has `on_search_changed` (GTK's debounced one, fired `search_delay` ms after typing stops) *and*, through `Editable`, `changed` (immediate). Both are exposed; a filter-as-you-type field wants the former, a controlled model wants the latter. `library_window.ml` uses the debounced one with `set_search_delay`.

**The controlled-text rule, stated precisely,** because it is the one place where "diff the props" is the wrong algorithm:

```ocaml
let set_text_if_needed (e : W.Editable.t) text =
  (* Against the *widget's* text, never against the previous node's. The user has typed
     since the last render, so the previous node's text is stale; comparing to it would
     either write on every keystroke (moving the caret to the end of what the user is
     still typing) or skip a write the model genuinely wanted. Comparing to the widget
     gets both right: a model that echoes what was typed is a no-op, and a model that
     rewrites it (uppercasing, clamping, rejecting) still wins. *)
  if not (String.equal (W.Editable.get_text e) text) then W.Editable.set_text e text
;;
```
Put it in `src/widgets/w_entry.ml` and reuse it from the other two.

- [ ] **Step 1: Write the failing headless test** (`test/test_handle.ml`, append)

The test that actually pins the semantics is a Bonsai one — an entry whose model uppercases what you type:

```ocaml
let shouty (graph @ local) =
  let text, set_text = Bonsai.state "" graph in
  let%arr text and set_text in
  Node.window
    ~title:"Shouty"
    (Node.box
       ~orientation:Vertical
       [ Node.entry
           ~attrs:[ Attr.test_id "e"; Attr.on_changed (fun s -> set_text (String.uppercase s)) ]
           ~placeholder:"type"
           ~text
           ()
       ; Node.label ~attrs:[ Attr.test_id "echo" ] text
       ])
;;

let%expect_test "Set_text runs the model, and the model's rewrite comes back as the prop" =
  let handle = Bonsai_gtk_test.create shouty in
  Bonsai_gtk_test.Handle.show handle;
  [%expect {| |}];
  Bonsai_gtk_test.Handle.do_actions handle [ Set_text ("e", "hello") ];
  Bonsai_gtk_test.Handle.show_diff handle;
  [%expect {| |}]
;;
```

And in `test/test_widgets.ml`, the constructor shapes:

```ocaml
let%expect_test "the entry family's constructors" =
  print_s
    [%sexp
      (Node.box
         ~orientation:Vertical
         [ Node.entry ~placeholder:"name" ~text:"" ()
         ; Node.entry ~text:"x" ~width_chars:6 ~xalign:1. ~editable:false ()
         ; Node.password_entry ~text:"" ~placeholder:"passphrase" ()
         ; Node.search_entry ~text:"bach" ~search_delay:150 ()
         ]
       : Node.t)];
  [%expect {| |}]
;;
```

- [ ] **Step 2: Write the failing live test** — append to `test/live/live_controls.ml`

The claim that only a live test can make: the widget's text wins over a stale node.

```ocaml
  (* Controlled text (spec §6.5). Render "a", then let the "user" type "ab" straight into
     the widget, then re-render a node that still says "a" -- the model has not caught up
     -- and the widget must be corrected back to "a". Then re-render with "ab", which the
     widget already shows, and nothing must be written (no [changed] reaches Bonsai). *)
  let entry_view text = Node.window ~title:"e" (Node.entry ~attrs:[ Attr.on_changed (fun _ -> Ui_effect.Ignore) ] ~text ()) in
  let live = P.mount ctx ~path:"root" ~is_root:true (entry_view "a") in
  let editable () =
    W.Editable.from_gobject
      (match live.children with
       | Single (Some e) -> e.widget
       | _ -> assert false)
  in
  W.Editable.set_text (editable ()) "ab";
  let before = !scheduled in
  let live =
    Scheduler.with_patch_guard scheduler (fun () ->
      P.patch ctx ~path:"root" ~is_root:true live (entry_view "a"))
  in
  printf "model wins: %s\n" (W.Editable.get_text (editable ()));
  let live =
    Scheduler.with_patch_guard scheduler (fun () ->
      P.patch ctx ~path:"root" ~is_root:true live (entry_view "ab"))
  in
  printf "echo is a no-op: %s\n" (W.Editable.get_text (editable ()));
  printf "changed events reaching Bonsai from patches: %d\n" (!scheduled - before);
  print_s (Live_tree.dump live.widget);
  P.destroy ctx live
```
(`editable ()` re-reads through the current `live`; rebind it after each `patch` or make it a function of the `live` value — write whichever is cleaner when the file is in front of you. `W` here is `Bonsai_gtk.Private.Gtk_import.W`.)

Also add a plain three-entry dump to `live_controls.ml`'s main view so the placeholder / width-chars / peek-icon props are covered.

- [ ] **Step 3: Run to verify failure.**

- [ ] **Step 4: `vtree/attr.ml(i)`** — three event attrs

```ocaml
(* Name.t: *) | On_changed | On_activate | On_search_changed
(* t: *)
  | On_changed of string Handler.t
  | On_activate of unit Handler.t
  | On_search_changed of string Handler.t
```
`name`, `equal` (`Handler.equal`), `is_event` (all three `true`), `Attr_apply.set`/`unset` (all inert) arms. Constructors:
```ocaml
(** Fires on every edit -- each keystroke, a paste, an undo -- carrying the widget's full
    text. This is [GtkEditable::changed], so it fires for programmatic writes too; the
    patcher's reentrancy guard is what keeps a re-render from feeding itself. *)
let on_changed f = On_changed f

(** Fires when the user presses Enter in a text entry. *)
let on_activate eff = On_activate (fun () -> eff)

(** [search_entry] only: GTK's debounced search signal, [search_delay] ms after typing
    stops. Use it for "filter as you type" against a store; use [on_changed] when the
    model owns the text. *)
let on_search_changed f = On_search_changed f
```

- [ ] **Step 5: `vtree/kind.ml(i)` / `node.ml(i)`**

```ocaml
type entry_props =
  { text : string
  ; placeholder : string option
  ; editable : bool
  ; visibility : bool
  ; width_chars : int
  ; max_width_chars : int
  ; xalign : float
  ; activates_default : bool
  }
[@@deriving sexp_of, equal]

type password_entry_props =
  { text : string
  ; placeholder : string option
  ; show_peek_icon : bool
  ; activates_default : bool
  }
[@@deriving sexp_of, equal]

type search_entry_props =
  { text : string
  ; placeholder : string option
  ; search_delay : int option
  }
[@@deriving sexp_of, equal]
```
Defaults in the constructors are GTK's: `editable = true`, `visibility = true`, `width_chars = -1`, `max_width_chars = -1`, `xalign = 0.`, `activates_default = false`, `show_peek_icon = true`. `search_delay = None` leaves GTK's own (150 ms) alone.

All three take `~text` as a required labelled argument, not `?text`: a text widget with no text prop is uncontrolled, and an uncontrolled text widget in a declarative tree is a bug that shows up as "my entry resets when something unrelated re-renders". Document that in the mli.

- [ ] **Step 6: `src/widgets/w_entry.ml`**

```ocaml
open! Core
open Bonsai_gtk_vtree
open Gtk_import

let editable (w : Widget.t) : W.Editable.t = W.Editable.from_gobject w

(* Against the *widget's* text, never the previous node's -- see the plan's §6.5 note. *)
let set_text_if_needed (e : W.Editable.t) text =
  if not (String.equal (W.Editable.get_text e) text) then W.Editable.set_text e text
;;

(* Shared by all three entry kinds: they all implement GtkEditable. *)
let changed : Signals.spec =
  { attr = Attr.Name.On_changed
  ; connect = (fun w ~callback -> W.Editable.on_changed (editable w) ~callback)
  ; fire =
      (fun w (attr : Attr.t) ->
        match attr with
        | On_changed handler -> Some (handler (W.Editable.get_text (editable w)))
        | _ -> None)
  }
;;

let activate ~connect : Signals.spec =
  { attr = Attr.Name.On_activate
  ; connect
  ; fire =
      (fun _w (attr : Attr.t) ->
        match attr with
        | On_activate handler -> Some (handler ())
        | _ -> None)
  }
;;

let impl : Widget_impl.t =
  { name = "Entry"
  ; create =
      (fun (kind : Kind.t) ->
        match kind with
        | Entry p ->
          let e = W.Entry.new_ () in
          let w = (e :> Widget.t) in
          Widget_impl.batch w (fun () ->
            W.Entry.set_placeholder_text e p.placeholder;
            if not p.visibility then W.Entry.set_visibility e false;
            if p.activates_default then W.Entry.set_activates_default e true;
            let ed = editable w in
            set_text_if_needed ed p.text;
            if not p.editable then W.Editable.set_editable ed false;
            if p.width_chars <> -1 then W.Editable.set_width_chars ed p.width_chars;
            if p.max_width_chars <> -1
            then W.Editable.set_max_width_chars ed p.max_width_chars;
            if Float.( <> ) p.xalign 0. then W.Editable.set_alignment ed p.xalign);
          w
        | k -> Widget_impl.wrong_kind "Entry" k)
  ; update =
      (fun w ~(old : Kind.t) (new_ : Kind.t) ->
        match old, new_ with
        | Entry old, Entry new_ ->
          let e : W.Entry.t = cast w in
          let ed = editable w in
          Widget_impl.batch w (fun () ->
            if not (Option.equal String.equal old.placeholder new_.placeholder)
            then W.Entry.set_placeholder_text e new_.placeholder;
            if not (Bool.equal old.visibility new_.visibility)
            then W.Entry.set_visibility e new_.visibility;
            if not (Bool.equal old.activates_default new_.activates_default)
            then W.Entry.set_activates_default e new_.activates_default;
            if not (Bool.equal old.editable new_.editable)
            then W.Editable.set_editable ed new_.editable;
            if old.width_chars <> new_.width_chars
            then W.Editable.set_width_chars ed new_.width_chars;
            if old.max_width_chars <> new_.max_width_chars
            then W.Editable.set_max_width_chars ed new_.max_width_chars;
            if Float.( <> ) old.xalign new_.xalign
            then W.Editable.set_alignment ed new_.xalign;
            set_text_if_needed ed new_.text)
        | _, k -> Widget_impl.wrong_kind "Entry" k)
  ; signals =
      [ changed; activate ~connect:(fun w ~callback -> W.Entry.on_activate (cast w) ~callback) ]
  ; children = Widget_impl.No_children
  }
;;
```
`set_text_if_needed` goes last in `update` deliberately: a `width_chars` change re-lays-out the entry, and doing that after the text write would re-run the caret placement the write just decided.

Not exposed, and named in the mli's doc comment: `GtkEntry`'s icon API (`set_icon_from_icon_name` and friends) — the icons come with `icon-press`/`icon-release` signals whose `entryiconposition` argument makes them a per-icon handler story better designed alongside M3's action routing — and `GtkEditable::insert-text`, which ocgtk does not bind (it has an in-out `int` position parameter).

- [ ] **Step 7: `src/widgets/w_password_entry.ml`**

```ocaml
open! Core
open Bonsai_gtk_vtree
open Gtk_import

let impl : Widget_impl.t =
  { name = "PasswordEntry"
  ; create =
      (fun (kind : Kind.t) ->
        match kind with
        | Password_entry p ->
          let e = W.Password_entry.new_ () in
          let w = (e :> Widget.t) in
          Widget_impl.batch w (fun () ->
            (* Unlike GtkEntry's, this setter is not nullable. *)
            W.Password_entry.set_placeholder_text e (Option.value p.placeholder ~default:"");
            if not p.show_peek_icon then W.Password_entry.set_show_peek_icon e false;
            if p.activates_default then W.Password_entry.set_activates_default e true;
            W_entry.set_text_if_needed (W_entry.editable w) p.text);
          w
        | k -> Widget_impl.wrong_kind "PasswordEntry" k)
  ; update =
      (fun w ~(old : Kind.t) (new_ : Kind.t) ->
        match old, new_ with
        | Password_entry old, Password_entry new_ ->
          let e : W.Password_entry.t = cast w in
          Widget_impl.batch w (fun () ->
            if not (Option.equal String.equal old.placeholder new_.placeholder)
            then
              W.Password_entry.set_placeholder_text
                e
                (Option.value new_.placeholder ~default:"");
            if not (Bool.equal old.show_peek_icon new_.show_peek_icon)
            then W.Password_entry.set_show_peek_icon e new_.show_peek_icon;
            if not (Bool.equal old.activates_default new_.activates_default)
            then W.Password_entry.set_activates_default e new_.activates_default;
            W_entry.set_text_if_needed (W_entry.editable w) new_.text)
        | _, k -> Widget_impl.wrong_kind "PasswordEntry" k)
  ; signals =
      [ W_entry.changed
      ; W_entry.activate ~connect:(fun w ~callback ->
          W.Password_entry.on_activate (cast w) ~callback)
      ]
  ; children = Widget_impl.No_children
  }
;;
```

- [ ] **Step 8: `src/widgets/w_search_entry.ml`**

```ocaml
open! Core
open Bonsai_gtk_vtree
open Gtk_import

let search_changed : Signals.spec =
  { attr = Attr.Name.On_search_changed
  ; connect = (fun w ~callback -> W.Search_entry.on_search_changed (cast w) ~callback)
  ; fire =
      (fun w (attr : Attr.t) ->
        match attr with
        | On_search_changed handler ->
          Some (handler (W.Editable.get_text (W_entry.editable w)))
        | _ -> None)
  }
;;

let impl : Widget_impl.t =
  { name = "SearchEntry"
  ; create =
      (fun (kind : Kind.t) ->
        match kind with
        | Search_entry p ->
          let e = W.Search_entry.new_ () in
          let w = (e :> Widget.t) in
          Widget_impl.batch w (fun () ->
            W.Search_entry.set_placeholder_text e p.placeholder;
            Option.iter p.search_delay ~f:(W.Search_entry.set_search_delay e);
            W_entry.set_text_if_needed (W_entry.editable w) p.text);
          w
        | k -> Widget_impl.wrong_kind "SearchEntry" k)
  ; update =
      (fun w ~(old : Kind.t) (new_ : Kind.t) ->
        match old, new_ with
        | Search_entry old, Search_entry new_ ->
          let e : W.Search_entry.t = cast w in
          Widget_impl.batch w (fun () ->
            if not (Option.equal String.equal old.placeholder new_.placeholder)
            then W.Search_entry.set_placeholder_text e new_.placeholder;
            if not (Option.equal Int.equal old.search_delay new_.search_delay)
            then Option.iter new_.search_delay ~f:(W.Search_entry.set_search_delay e);
            W_entry.set_text_if_needed (W_entry.editable w) new_.text)
        | _, k -> Widget_impl.wrong_kind "SearchEntry" k)
  ; signals =
      [ W_entry.changed
      ; search_changed
      ; W_entry.activate ~connect:(fun w ~callback ->
          W.Search_entry.on_activate (cast w) ~callback)
      ]
  ; children = Widget_impl.No_children
  }
;;
```
`set_key_capture_widget` (which `library_window.ml` uses to make typing anywhere focus the search box) is *not* exposed: it names another live widget, which the vtree cannot. `Node.native` is the escape hatch until a later milestone designs cross-node references. Say so in the mli.

- [ ] **Step 9: Registry arms, `Live_tree` arms**

```ocaml
  | Entry _ -> W_entry.impl
  | Password_entry _ -> W_password_entry.impl
  | Search_entry _ -> W_search_entry.impl
```
`Live_tree`, for all three types, prints the editable text and the placeholder:
```ocaml
     | "GtkEntry" | "GtkPasswordEntry" | "GtkSearchEntry" ->
       [ [%sexp `text (W.Editable.get_text (W.Editable.from_gobject w) : string)] ]
       @ (match ty with
          | "GtkEntry" ->
            (match W.Entry.get_placeholder_text (cast w) with
             | None -> []
             | Some p -> [ Sexp.List [ Atom "placeholder"; Atom p ] ])
          | _ -> [])
       @ int_prop "width-chars" (W.Editable.get_width_chars (W.Editable.from_gobject w)) ~default:(-1)
```
These widgets have internal children (a `GtkText`, icons), which `widget_children` will print. That is fine and even useful — it is what GTK actually holds — but it makes the expected files verbose; if a dump is unreadable, add an `internal_children` suppression keyed on type name to `Live_tree` and document it in the mli rather than trimming the expected file by hand.

- [ ] **Step 10: `test_lib/bonsai_gtk_test.ml(i)`** — two more actions

```ocaml
    | Set_text (id, text) ->
      let n = node_exn node id in
      (match Attrs.find n.attrs On_changed with
       | Some (On_changed h) -> h text
       | _ -> failwithf "Bonsai_gtk_test: node %s has no on_changed handler" id ())
    | Activate id ->
      let n = node_exn node id in
      (match Attrs.find n.attrs On_activate with
       | Some (On_activate h) -> h ()
       | _ -> failwithf "Bonsai_gtk_test: node %s has no on_activate handler" id ())
```
`Set_text` deliberately does *not* consult the node's `text` prop: it means "the user made the text be this", which is what a real edit produces regardless of what the widget showed before.

- [ ] **Step 11: Run, read, promote, `./scripts/ci.sh`.**
In `output_controls.txt`: `model wins: a`, `echo is a no-op: ab`, `changed events reaching Bonsai from patches: 0`. The last is the reason the guard exists — a `set_text` from a patch that reached Bonsai would loop.

- [ ] **Step 12: Commit**

```bash
dune fmt 2>/dev/null; git add vtree src test test_lib
GIT_EDITOR=true git commit -F - <<'MSG'
Entry, PasswordEntry, SearchEntry as controlled text widgets

Text is written only when it differs from what the widget currently shows --
not from the previous node's text, which is stale the moment the user types.
A model that echoes causes no caret jump; a model that rewrites still wins.
Pinned by a live test that types into the widget behind the model's back.

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01Sg3Ci8U8kUKR8C3PL1pNSs
MSG
```

---

### Task 5: Numbers and feedback — SpinButton, Scale, ProgressBar, Spinner

`Scale` is the one stavekeeper already uses (`page_scrubber.ml`: `Scale.new_with_range \`HORIZONTAL first last 1.0`), and it is the widget the "controlled" question is sharpest for — see Open Question 2.

**Files:**
- Create: `src/widgets/w_spin_button.ml`, `src/widgets/w_scale.ml`, `src/widgets/w_progress_bar.ml`, `src/widgets/w_spinner.ml`
- Modify: `vtree/attr.ml(i)`, `vtree/kind.ml(i)`, `vtree/node.ml(i)`, `src/widgets/registry.ml`, `src/live_tree.ml`, `test_lib/bonsai_gtk_test.ml(i)`, `test/test_widgets.ml`, `test/live/live_controls.ml`

**Interfaces:**
- Produces:
  ```ocaml
  (* Attr *)
  val on_value_changed : (float -> unit Ui_effect.t) -> t

  (* Node *)
  val spin_button
    :  ?key:Key.t -> ?attrs:Attr.t list -> ?digits:int -> ?numeric:bool -> ?wrap:bool
    -> ?step:float -> ?activates_default:bool
    -> min:float -> max:float -> value:float -> unit -> t
  val scale
    :  ?key:Key.t -> ?attrs:Attr.t list -> ?step:float -> ?digits:int -> ?draw_value:bool
    -> ?has_origin:bool -> ?inverted:bool -> orientation:Orientation.t
    -> min:float -> max:float -> value:float -> unit -> t
  val progress_bar
    :  ?key:Key.t -> ?attrs:Attr.t list -> ?text:string -> ?show_text:bool
    -> ?inverted:bool -> ?ellipsize:Ellipsize.t -> fraction:float -> unit -> t
  val spinner : ?key:Key.t -> ?attrs:Attr.t list -> spinning:bool -> unit -> t

  (* Bonsai_gtk_test.Action *)
  | Set_value of string * float
  ```
- Consumes: `W.Spin_button.{new_with_range,set_value,get_value,set_range,set_increments,set_digits,set_numeric,set_wrap,set_activates_default,on_value_changed}`, `W.Scale.{new_with_range,set_digits,set_draw_value,set_has_origin}`, `W.Range.{set_value,get_value,set_range,set_increments,set_inverted,on_value_changed}`, `W.Orientable.{from_gobject,set_orientation}`, `W.Progress_bar.{new_,set_fraction,set_text,set_show_text,set_inverted,set_ellipsize}`, `W.Spinner.{new_,set_spinning}`.

`GtkScale` is a `GtkRange`, so its value, range, increments and `inverted` come from `W.Range` via `cast`, and `value-changed` is `W.Range.on_value_changed`. Its own module only adds the presentation props (`digits`, `draw_value`, `has_origin`, marks). `Range` has no `from_gobject`; `Gtk_import.cast` does the downcast, which is sound because `Scale.t`'s phantom row already contains `` `range ``.

`gtk_scale_add_mark` is bound but not exposed: marks are a list-valued property with no "clear one" operation (only `clear_marks`), so diffing them means clearing and re-adding the whole set on any change. That is implementable and not worth M1's budget; note it in the mli as a `Node.native` case.

- [ ] **Step 1: Failing headless test** (`test/test_widgets.ml`)

```ocaml
let%expect_test "the numeric family's constructors" =
  print_s
    [%sexp
      (Node.box
         ~orientation:Vertical
         [ Node.spin_button ~min:40. ~max:280. ~value:120. ~step:1. ()
         ; Node.scale ~orientation:Horizontal ~min:1. ~max:32. ~value:7. ~draw_value:false ()
         ; Node.progress_bar ~fraction:0.25 ~text:"loading" ~show_text:true ()
         ; Node.spinner ~spinning:true ()
         ]
       : Node.t)];
  [%expect {| |}]
;;
```

and in `test/test_handle.ml`, a `Set_value` round-trip on a scale whose model clamps:

```ocaml
let clamped (graph @ local) =
  let v, set_v = Bonsai.state 5. graph in
  let%arr v and set_v in
  Node.window
    ~title:"Clamped"
    (Node.scale
       ~attrs:
         [ Attr.test_id "s"
         ; Attr.on_value_changed (fun x -> set_v (Float.min x 8.))
         ]
       ~orientation:Horizontal
       ~min:0.
       ~max:10.
       ~value:v
       ())
;;

let%expect_test "Set_value goes through the model, which may refuse it" =
  let handle = Bonsai_gtk_test.create clamped in
  Bonsai_gtk_test.Handle.show handle;
  [%expect {| |}];
  Bonsai_gtk_test.Handle.do_actions handle [ Set_value ("s", 9.5) ];
  Bonsai_gtk_test.Handle.show_diff handle;
  [%expect {| |}]
;;
```

- [ ] **Step 2: Failing live test** — append to `test/live/live_controls.ml`

```ocaml
  (* The controlled-value rule, the numeric twin of the entry case above: drag the scale
     behind the model's back, re-render the old value, and the model wins. *)
  let scale_view value =
    Node.window
      ~title:"n"
      (Node.box
         ~orientation:Vertical
         [ Node.scale
             ~attrs:[ Attr.on_value_changed (fun _ -> Ui_effect.Ignore) ]
             ~orientation:Horizontal
             ~min:0.
             ~max:10.
             ~value
             ()
         ; Node.spin_button
             ~attrs:[ Attr.on_value_changed (fun _ -> Ui_effect.Ignore) ]
             ~min:0.
             ~max:100.
             ~value
             ()
         ; Node.progress_bar ~fraction:(value /. 10.) ~text:"p" ~show_text:true ()
         ; Node.spinner ~spinning:true ()
         ])
  in
  let live = P.mount ctx ~path:"root" ~is_root:true (scale_view 3.) in
  print_s (Live_tree.dump live.widget);
  let scale_widget = (nth_child live 0).widget in
  W.Range.set_value (cast scale_widget) 7.;
  let before = !scheduled in
  let live =
    Scheduler.with_patch_guard scheduler (fun () ->
      P.patch ctx ~path:"root" ~is_root:true live (scale_view 3.))
  in
  printf "model wins: %g\n" (W.Range.get_value (cast (nth_child live 0).widget));
  printf "value-changed reaching Bonsai from patches: %d\n" (!scheduled - before);
  let live =
    Scheduler.with_patch_guard scheduler (fun () ->
      P.patch ctx ~path:"root" ~is_root:true live (scale_view 6.))
  in
  print_s (Live_tree.dump live.widget);
  P.destroy ctx live
```

- [ ] **Step 3: Run to verify failure.**

- [ ] **Step 4: `vtree/attr.ml(i)`**

```ocaml
(* Name.t: *) | On_value_changed
(* t: *)      | On_value_changed of float Handler.t

(** Fires when a [scale] or [spin_button]'s value changes, carrying the new value. As with
    the toggles, only user-driven changes reach the handler: a value the patcher writes is
    dropped by the reentrancy guard. *)
let on_value_changed f = On_value_changed f
```
plus `name`, `equal`, `is_event`, and the inert `Attr_apply` arms.

- [ ] **Step 5: `vtree/kind.ml(i)` / `node.ml(i)`**

```ocaml
type spin_button_props =
  { value : float
  ; min : float
  ; max : float
  ; step : float
  ; digits : int
  ; numeric : bool
  ; wrap : bool
  ; activates_default : bool
  }
[@@deriving sexp_of, equal]

type scale_props =
  { orientation : Orientation.t
  ; value : float
  ; min : float
  ; max : float
  ; step : float
  ; digits : int
  ; draw_value : bool
  ; has_origin : bool
  ; inverted : bool
  }
[@@deriving sexp_of, equal]

type progress_bar_props =
  { fraction : float
  ; text : string option
  ; show_text : bool
  ; inverted : bool
  ; ellipsize : Ellipsize.t option
  }
[@@deriving sexp_of, equal]

type spinner_props = { spinning : bool } [@@deriving sexp_of, equal]
```
Constructor defaults: `step = 1.`, `digits = 0` for `spin_button` and `1` for `scale` (GTK's own), `numeric = true` (a spin button whose text can be arbitrary is a trap), `wrap = false`, `draw_value = true`, `has_origin = true`, `inverted = false`, `show_text = false`.

`min`/`max`/`value` are required labelled arguments on both `spin_button` and `scale`: a range widget with an implicit 0–100 is a bug generator, and every real use names its own.

- [ ] **Step 6: `src/widgets/w_spin_button.ml`**

```ocaml
open! Core
open Bonsai_gtk_vtree
open Gtk_import

let value_changed : Signals.spec =
  { attr = Attr.Name.On_value_changed
  ; connect = (fun w ~callback -> W.Spin_button.on_value_changed (cast w) ~callback)
  ; fire =
      (fun w (attr : Attr.t) ->
        match attr with
        | On_value_changed handler -> Some (handler (W.Spin_button.get_value (cast w)))
        | _ -> None)
  }
;;

let impl : Widget_impl.t =
  { name = "SpinButton"
  ; create =
      (fun (kind : Kind.t) ->
        match kind with
        | Spin_button p ->
          (* [new_with_range] builds the GtkAdjustment for us; there is no reason to hold
             one on the OCaml side, since every prop that touches it is re-derived from
             the node. *)
          let s = W.Spin_button.new_with_range p.min p.max p.step in
          let w = (s :> Widget.t) in
          Widget_impl.batch w (fun () ->
            W.Spin_button.set_digits s p.digits;
            W.Spin_button.set_numeric s p.numeric;
            W.Spin_button.set_wrap s p.wrap;
            if p.activates_default then W.Spin_button.set_activates_default s true;
            W.Spin_button.set_value s p.value);
          w
        | k -> Widget_impl.wrong_kind "SpinButton" k)
  ; update =
      (fun w ~(old : Kind.t) (new_ : Kind.t) ->
        match old, new_ with
        | Spin_button old, Spin_button new_ ->
          let s : W.Spin_button.t = cast w in
          Widget_impl.batch w (fun () ->
            if Float.( <> ) old.min new_.min || Float.( <> ) old.max new_.max
            then W.Spin_button.set_range s new_.min new_.max;
            if Float.( <> ) old.step new_.step
            then W.Spin_button.set_increments s new_.step (new_.step *. 10.);
            if old.digits <> new_.digits then W.Spin_button.set_digits s new_.digits;
            if not (Bool.equal old.numeric new_.numeric)
            then W.Spin_button.set_numeric s new_.numeric;
            if not (Bool.equal old.wrap new_.wrap) then W.Spin_button.set_wrap s new_.wrap;
            if not (Bool.equal old.activates_default new_.activates_default)
            then W.Spin_button.set_activates_default s new_.activates_default;
            (* Controlled, and against the widget: clamping to a new range may already
               have moved the value, and the user may have spun it since the last
               render. *)
            if Float.( <> ) (W.Spin_button.get_value s) new_.value
            then W.Spin_button.set_value s new_.value)
        | _, k -> Widget_impl.wrong_kind "SpinButton" k)
  ; signals = [ value_changed ]
  ; children = Widget_impl.No_children
  }
;;
```
The page increment is `step *. 10.` rather than another prop: GTK needs one, `new_with_range` picks its own, and no caller has ever wanted to name it separately. Note it in the mli.

- [ ] **Step 7: `src/widgets/w_scale.ml`**

```ocaml
open! Core
open Bonsai_gtk_vtree
open Gtk_import

let orientation : Orientation.t -> Gtk_enums.orientation = function
  | Horizontal -> `HORIZONTAL
  | Vertical -> `VERTICAL
;;

(* A GtkScale is a GtkRange: value, bounds, increments and [inverted] all live there, and
   so does [value-changed]. Only the presentation props are Scale's own. *)
let value_changed : Signals.spec =
  { attr = Attr.Name.On_value_changed
  ; connect = (fun w ~callback -> W.Range.on_value_changed (cast w) ~callback)
  ; fire =
      (fun w (attr : Attr.t) ->
        match attr with
        | On_value_changed handler -> Some (handler (W.Range.get_value (cast w)))
        | _ -> None)
  }
;;

let impl : Widget_impl.t =
  { name = "Scale"
  ; create =
      (fun (kind : Kind.t) ->
        match kind with
        | Scale p ->
          let s = W.Scale.new_with_range (orientation p.orientation) p.min p.max p.step in
          let w = (s :> Widget.t) in
          Widget_impl.batch w (fun () ->
            W.Scale.set_digits s p.digits;
            W.Scale.set_draw_value s p.draw_value;
            W.Scale.set_has_origin s p.has_origin;
            if p.inverted then W.Range.set_inverted (cast w) true;
            W.Range.set_value (cast w) p.value);
          w
        | k -> Widget_impl.wrong_kind "Scale" k)
  ; update =
      (fun w ~(old : Kind.t) (new_ : Kind.t) ->
        match old, new_ with
        | Scale old, Scale new_ ->
          let s : W.Scale.t = cast w in
          let r : W.Range.t = cast w in
          Widget_impl.batch w (fun () ->
            if not (Orientation.equal old.orientation new_.orientation)
            then
              W.Orientable.set_orientation
                (W.Orientable.from_gobject w)
                (orientation new_.orientation);
            if Float.( <> ) old.min new_.min || Float.( <> ) old.max new_.max
            then W.Range.set_range r new_.min new_.max;
            if Float.( <> ) old.step new_.step
            then W.Range.set_increments r new_.step (new_.step *. 10.);
            if old.digits <> new_.digits then W.Scale.set_digits s new_.digits;
            if not (Bool.equal old.draw_value new_.draw_value)
            then W.Scale.set_draw_value s new_.draw_value;
            if not (Bool.equal old.has_origin new_.has_origin)
            then W.Scale.set_has_origin s new_.has_origin;
            if not (Bool.equal old.inverted new_.inverted)
            then W.Range.set_inverted r new_.inverted;
            (* Controlled against the widget: the user may be mid-drag, and a model that
               did not follow the drag must pull the slider back rather than let the two
               diverge. See the plan's Open Question 2. *)
            if Float.( <> ) (W.Range.get_value r) new_.value
            then W.Range.set_value r new_.value)
        | _, k -> Widget_impl.wrong_kind "Scale" k)
  ; signals = [ value_changed ]
  ; children = Widget_impl.No_children
  }
;;
```

- [ ] **Step 8: `src/widgets/w_progress_bar.ml`**

```ocaml
open! Core
open Bonsai_gtk_vtree
open Gtk_import

let ellipsize : Ellipsize.t option -> Ocgtk_pango.Pango.ellipsizemode = function
  | None -> `NONE
  | Some Start -> `START
  | Some Middle -> `MIDDLE
  | Some End -> `END
;;

let impl : Widget_impl.t =
  { name = "ProgressBar"
  ; create =
      (fun (kind : Kind.t) ->
        match kind with
        | Progress_bar p ->
          let b = W.Progress_bar.new_ () in
          let w = (b :> Widget.t) in
          Widget_impl.batch w (fun () ->
            W.Progress_bar.set_fraction b p.fraction;
            W.Progress_bar.set_text b p.text;
            W.Progress_bar.set_show_text b p.show_text;
            if p.inverted then W.Progress_bar.set_inverted b true;
            W.Progress_bar.set_ellipsize b (ellipsize p.ellipsize));
          w
        | k -> Widget_impl.wrong_kind "ProgressBar" k)
  ; update =
      (fun w ~(old : Kind.t) (new_ : Kind.t) ->
        match old, new_ with
        | Progress_bar old, Progress_bar new_ ->
          let b : W.Progress_bar.t = cast w in
          Widget_impl.batch w (fun () ->
            if Float.( <> ) old.fraction new_.fraction
            then W.Progress_bar.set_fraction b new_.fraction;
            if not (Option.equal String.equal old.text new_.text)
            then W.Progress_bar.set_text b new_.text;
            if not (Bool.equal old.show_text new_.show_text)
            then W.Progress_bar.set_show_text b new_.show_text;
            if not (Bool.equal old.inverted new_.inverted)
            then W.Progress_bar.set_inverted b new_.inverted;
            if not (Option.equal Ellipsize.equal old.ellipsize new_.ellipsize)
            then W.Progress_bar.set_ellipsize b (ellipsize new_.ellipsize))
        | _, k -> Widget_impl.wrong_kind "ProgressBar" k)
  ; signals = []
  ; children = Widget_impl.No_children
  }
;;
```
`gtk_progress_bar_pulse` is not exposed: pulsing is a stateful animation the widget owns, driven by a timer, which is not a property a declarative tree can describe. An indeterminate progress indicator is `Node.spinner`; a pulsing bar is a `Node.native`. Say so in the mli.

- [ ] **Step 9: `src/widgets/w_spinner.ml`**

```ocaml
open! Core
open Bonsai_gtk_vtree
open Gtk_import

let impl : Widget_impl.t =
  { name = "Spinner"
  ; create =
      (fun (kind : Kind.t) ->
        match kind with
        | Spinner { spinning } ->
          let s = W.Spinner.new_ () in
          W.Spinner.set_spinning s spinning;
          (s :> Widget.t)
        | k -> Widget_impl.wrong_kind "Spinner" k)
  ; update =
      (fun w ~(old : Kind.t) (new_ : Kind.t) ->
        match old, new_ with
        | Spinner old, Spinner new_ ->
          if not (Bool.equal old.spinning new_.spinning)
          then W.Spinner.set_spinning (cast w) new_.spinning
        | _, k -> Widget_impl.wrong_kind "Spinner" k)
  ; signals = []
  ; children = Widget_impl.No_children
  }
;;
```

- [ ] **Step 10: Registry, `Live_tree`, `Bonsai_gtk_test.Set_value`**

Registry: four arms. `Live_tree`:
```ocaml
     | "GtkScale" | "GtkSpinButton" ->
       [ Sexp.List [ Atom "value"; Atom (sprintf "%g" (W.Range.get_value (cast w))) ] ]
     | "GtkProgressBar" ->
       [ Sexp.List
           [ Atom "fraction"
           ; Atom (sprintf "%g" (W.Progress_bar.get_fraction (cast w)))
           ]
       ]
       @ (match W.Progress_bar.get_text (cast w) with
          | None -> []
          | Some t -> [ Sexp.List [ Atom "text"; Atom t ] ])
     | "GtkSpinner" -> flag_prop "spinning" (W.Spinner.get_spinning (cast w))
```
Careful: `GtkSpinButton` is *not* a `GtkRange` (it has its own adjustment), so its arm must use `W.Spin_button.get_value`, not `W.Range.get_value`. Split the arm.

`Bonsai_gtk_test`: `| Set_value of string * float`, dispatched to `On_value_changed`.

- [ ] **Step 11: Run, read, promote, `./scripts/ci.sh`.**
`model wins: 3` and `value-changed reaching Bonsai from patches: 0` are the lines that carry the claim.

- [ ] **Step 12: Commit**

```bash
dune fmt 2>/dev/null; git add vtree src test test_lib
GIT_EDITOR=true git commit -F - <<'MSG'
SpinButton, Scale, ProgressBar, Spinner

Scale and SpinButton values are controlled on the same rule as text: written
only when they differ from what the widget currently shows, so a drag the
model declines is pulled back rather than left diverged.

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01Sg3Ci8U8kUKR8C3PL1pNSs
MSG
```

---

### Task 6: Image, Picture, Separator — and `Node.native`'s first shipped widget

`Node.native` itself landed in M0 (spec §6.6); what M1 owes it is a *use*: a widget the library ships, built on the escape hatch, that could not be a `Kind.t` because its input is an ocgtk type the vtree may not mention. `GtkPicture` fed a `GdkPaintable` is exactly that case — and it is exactly what stavekeeper needs (`ink_mode.ml` and `viewer_window.ml` both push a `Gdk.Memory_texture` into a `GtkPicture` every frame), alongside the plain filename-backed `Picture` that `cards.ml` uses for thumbnails.

Read `~/src/stavekeeper/lib/stavekeeper_app/cards.ml` first, in particular the comment at the top: it is a precise account of why a `GtkPicture` needs `can_shrink` + `CONTAIN` + an unmeasured overlay child to be size-controlled, and Task 8's `Overlay` is the other half of it.

**Files:**
- Create: `vtree/content_fit.ml`, `vtree/icon_size.ml`, `vtree/image_source.ml`, `vtree/picture_source.ml`, `src/widgets/w_image.ml`, `src/widgets/w_picture.ml`, `src/widgets/w_separator.ml`, `src/paintable_picture.ml`, `src/paintable_picture.mli`, `test/live/live_containers.ml`, `test/live/expected_containers.txt`
- Modify: `vtree/kind.ml(i)`, `vtree/node.ml(i)`, `vtree/bonsai_gtk_vtree.ml`, `src/widgets/registry.ml`, `src/live_tree.ml`, `src/bonsai_gtk.ml(i)`, `test/test_widgets.ml`, `test/live/dune`

**Interfaces:**
- Produces:
  ```ocaml
  (* vtree *)
  module Content_fit : sig type t = Fill | Contain | Cover | Scale_down end
  module Icon_size   : sig type t = Inherit | Normal | Large end
  module Image_source : sig
    type t = Empty | Icon_name of string | File of string | Resource of string
  end
  module Picture_source : sig
    type t = Empty | Filename of string | Resource of string
  end

  (* Node *)
  val image
    :  ?key:Key.t -> ?attrs:Attr.t list -> ?pixel_size:int -> ?icon_size:Icon_size.t
    -> Image_source.t -> t
  val picture
    :  ?key:Key.t -> ?attrs:Attr.t list -> ?content_fit:Content_fit.t -> ?can_shrink:bool
    -> ?alternative_text:string -> Picture_source.t -> t
  val separator : ?key:Key.t -> ?attrs:Attr.t list -> orientation:Orientation.t -> t

  (* Bonsai_gtk.Native.Picture — the runtime's own native widget *)
  val node
    :  ?key:Key.t -> ?attrs:Attr.t list -> ?content_fit:Content_fit.t -> ?can_shrink:bool
    -> Ocgtk_gdk.Gdk.Wrappers.Paintable.t option
    -> Node.t
  ```
- Consumes: `W.Image.{new_,set_from_icon_name,set_from_file,set_from_resource,clear,set_pixel_size,set_icon_size}`, `W.Picture.{new_,set_filename,set_resource,set_paintable,set_content_fit,set_can_shrink,set_alternative_text}`, `W.Separator.new_`, `Ocgtk_gdk.Gdk.Wrappers.{Paintable,Texture}`, `Gobject.same`.

`Image_source`/`Picture_source` are variants rather than four optional arguments because the sources are mutually exclusive and GTK's setters do not compose: setting a file after an icon name silently wins, and there is no "which one is set" you can diff. A closed variant makes the exclusivity a type error instead, and gives `equal_props` one line.

- [ ] **Step 1: Failing headless test** (`test/test_widgets.ml`)

```ocaml
let%expect_test "images, pictures and separators" =
  print_s
    [%sexp
      (Node.box
         ~orientation:Vertical
         [ Node.image ~pixel_size:16 (Icon_name "list-add-symbolic")
         ; Node.image Empty
         ; Node.picture ~content_fit:Contain ~can_shrink:true (Filename "/tmp/thumb.png")
         ; Node.separator ~orientation:Horizontal
         ]
       : Node.t)];
  [%expect {| |}]
;;
```

- [ ] **Step 2: Failing live test** — new file `test/live/live_containers.ml`

This file is Tasks 6–9's home. It needs an image on disk; make one rather than committing a fixture, so the test has no data dependency:

```ocaml
open! Core
open Bonsai_gtk_vtree
module Gdk = Ocgtk_gdk.Gdk
module Live_tree = Bonsai_gtk.Private.Live_tree
module P = Bonsai_gtk.Private.Patcher
module W = Bonsai_gtk.Private.Gtk_import.W

(* A 2x2 opaque texture, built in memory. [Gdk.Texture.save_to_png] then gives us a real
   PNG on disk for the filename-backed [Node.picture], so the test carries no fixture and
   the two Picture paths -- filename and paintable -- are exercised from one source. *)
let texture () =
  let bytes =
    Glib_bytes.of_bigstring
      (Bigstring.of_string "\255\000\000\255\000\255\000\255\000\000\255\255\255\255\255\255")
  in
  Gdk.Memory_texture.new_ 2 2 `R8G8B8A8_PREMULTIPLIED bytes
;;

let () =
  ignore (Ocgtk_gtk.GMain.init () : string array);
  let ctx : P.ctx =
    { signals =
        { schedule = (fun _ -> ())
        ; in_patch = (fun () -> false)
        ; on_exn = (fun ~node_path exn -> printf "EXN at %s: %s\n" node_path (Exn.to_string exn))
        }
    ; on_window_created = (fun _ -> ())
    }
  in
  let tex = texture () in
  let png = Filename.temp_file "bonsai_gtk" ".png" in
  ignore (Gdk.Texture.save_to_png (cast tex) png : bool);
  let view =
    Node.window
      ~title:"media"
      (Node.box
         ~orientation:Vertical
         [ Node.image ~pixel_size:16 (Icon_name "list-add-symbolic")
         ; Node.image Empty
         ; Node.picture ~content_fit:Contain ~can_shrink:true (Filename png)
         ; Bonsai_gtk.Native.Picture.node
             ~content_fit:Cover
             (Some (Gdk.Wrappers.Paintable.from_gobject tex))
         ; Node.separator ~orientation:Horizontal
         ])
  in
  let live = P.mount ctx ~path:"root" ~is_root:true view in
  print_s (Live_tree.dump live.widget);
  (* Swapping an image's source kind must reach GTK, not just the node. *)
  let live =
    P.patch
      ctx
      ~path:"root"
      ~is_root:true
      live
      (Node.window
         ~title:"media"
         (Node.box
            ~orientation:Vertical
            [ Node.image ~pixel_size:16 (File png)
            ; Node.image (Icon_name "edit-find-symbolic")
            ; Node.picture ~content_fit:Cover ~can_shrink:false Empty
            ; Bonsai_gtk.Native.Picture.node ~content_fit:Cover None
            ; Node.separator ~orientation:Vertical
            ]))
  in
  print_s (Live_tree.dump live.widget);
  P.destroy ctx live;
  Core_unix.unlink png
;;
```
(`Core_unix` may not be a dependency of `test/live`; `Sys_unix.remove` or simply leaving the temp file is fine — pick whatever keeps the dune stanza small, and note that the file lives in the sandbox anyway.)

Add `live_containers` to `test/live/dune`'s `(names ...)`, its rule, and `ocgtk.gdk` to that stanza's libraries.

- [ ] **Step 3: The four vtree enum modules**

```ocaml
(* vtree/content_fit.ml *)
open! Core

(** How a [Node.picture] scales its image into the space it is given. [Contain] letterboxes,
    [Cover] crops, [Fill] stretches, [Scale_down] shrinks but never enlarges. Paired with
    [can_shrink], which is what lets the widget be *smaller* than its image at all. *)
type t =
  | Fill
  | Contain
  | Cover
  | Scale_down
[@@deriving sexp_of, equal, compare]

(* vtree/icon_size.ml *)
open! Core

type t =
  | Inherit
  | Normal
  | Large
[@@deriving sexp_of, equal, compare]

(* vtree/image_source.ml *)
open! Core

(** Where a [Node.image] gets its picture. The alternatives are a closed variant rather
    than four optional arguments because GTK's setters do not compose -- setting a file
    after an icon name silently wins, and nothing tells you which one is live. *)
type t =
  | Empty
  | Icon_name of string
  | File of string
  | Resource of string
[@@deriving sexp_of, equal, compare]

(* vtree/picture_source.ml *)
open! Core

(** Where a [Node.picture] gets its image. A [GdkPaintable] source -- a texture the
    application rendered -- is not here: the vtree may not mention ocgtk types. Use
    [Bonsai_gtk.Native.Picture] for that. *)
type t =
  | Empty
  | Filename of string
  | Resource of string
[@@deriving sexp_of, equal, compare]
```
Add all four to `vtree/bonsai_gtk_vtree.ml` and re-export from `src/bonsai_gtk.ml(i)`.

- [ ] **Step 4: `vtree/kind.ml(i)` / `node.ml(i)`**

```ocaml
type image_props =
  { source : Image_source.t
  ; pixel_size : int
  ; icon_size : Icon_size.t
  }
[@@deriving sexp_of, equal]

type picture_props =
  { source : Picture_source.t
  ; content_fit : Content_fit.t
  ; can_shrink : bool
  ; alternative_text : string option
  }
[@@deriving sexp_of, equal]

type separator_props = { orientation : Orientation.t } [@@deriving sexp_of, equal]
```
Defaults: `pixel_size = -1` (GTK's "derive from icon size"), `icon_size = Inherit`, `content_fit = Contain`, `can_shrink = true`.

- [ ] **Step 5: `src/widgets/w_image.ml`**

```ocaml
open! Core
open Bonsai_gtk_vtree
open Gtk_import

let icon_size : Icon_size.t -> Gtk_enums.iconsize = function
  | Inherit -> `INHERIT
  | Normal -> `NORMAL
  | Large -> `LARGE
;;

(* One call per source, and [clear] for [Empty]: GTK keeps whichever source was set last,
   so switching kinds has to go through the new kind's setter, and switching *to* nothing
   has to go through [clear] -- [set_from_icon_name w None] leaves a previously set file
   in place. *)
let set_source (i : W.Image.t) (source : Image_source.t) =
  match source with
  | Empty -> W.Image.clear i
  | Icon_name name -> W.Image.set_from_icon_name i (Some name)
  | File path -> W.Image.set_from_file i (Some path)
  | Resource path -> W.Image.set_from_resource i (Some path)
;;

let impl : Widget_impl.t =
  { name = "Image"
  ; create =
      (fun (kind : Kind.t) ->
        match kind with
        | Image p ->
          let i = W.Image.new_ () in
          let w = (i :> Widget.t) in
          Widget_impl.batch w (fun () ->
            set_source i p.source;
            if p.pixel_size <> -1 then W.Image.set_pixel_size i p.pixel_size;
            W.Image.set_icon_size i (icon_size p.icon_size));
          w
        | k -> Widget_impl.wrong_kind "Image" k)
  ; update =
      (fun w ~(old : Kind.t) (new_ : Kind.t) ->
        match old, new_ with
        | Image old, Image new_ ->
          let i : W.Image.t = cast w in
          Widget_impl.batch w (fun () ->
            if not (Image_source.equal old.source new_.source) then set_source i new_.source;
            if old.pixel_size <> new_.pixel_size
            then W.Image.set_pixel_size i new_.pixel_size;
            if not (Icon_size.equal old.icon_size new_.icon_size)
            then W.Image.set_icon_size i (icon_size new_.icon_size))
        | _, k -> Widget_impl.wrong_kind "Image" k)
  ; signals = []
  ; children = Widget_impl.No_children
  }
;;
```
`set_from_gicon` and `set_from_pixbuf` are not exposed: a `GIcon` and a `GdkPixbuf` are both ocgtk values, so they belong on the native side like `Paintable` does. Named in the mli.

- [ ] **Step 6: `src/widgets/w_picture.ml`**

```ocaml
open! Core
open Bonsai_gtk_vtree
open Gtk_import

let content_fit : Content_fit.t -> Gtk_enums.contentfit = function
  | Fill -> `FILL
  | Contain -> `CONTAIN
  | Cover -> `COVER
  | Scale_down -> `SCALE_DOWN
;;

(* Same rule as [W_image.set_source]: [Empty] goes through a setter that actually clears,
   which for GtkPicture is [set_paintable None] (there is no [clear]). *)
let set_source (p : W.Picture.t) (source : Picture_source.t) =
  match source with
  | Empty -> W.Picture.set_paintable p None
  | Filename path -> W.Picture.set_filename p (Some path)
  | Resource path -> W.Picture.set_resource p (Some path)
;;

let apply_props (p : W.Picture.t) ~content_fit:cf ~can_shrink ~alternative_text =
  W.Picture.set_content_fit p (content_fit cf);
  W.Picture.set_can_shrink p can_shrink;
  W.Picture.set_alternative_text p alternative_text
;;

let impl : Widget_impl.t =
  { name = "Picture"
  ; create =
      (fun (kind : Kind.t) ->
        match kind with
        | Picture props ->
          let p = W.Picture.new_ () in
          let w = (p :> Widget.t) in
          Widget_impl.batch w (fun () ->
            set_source p props.source;
            apply_props
              p
              ~content_fit:props.content_fit
              ~can_shrink:props.can_shrink
              ~alternative_text:props.alternative_text);
          w
        | k -> Widget_impl.wrong_kind "Picture" k)
  ; update =
      (fun w ~(old : Kind.t) (new_ : Kind.t) ->
        match old, new_ with
        | Picture old, Picture new_ ->
          let p : W.Picture.t = cast w in
          Widget_impl.batch w (fun () ->
            if not (Picture_source.equal old.source new_.source)
            then set_source p new_.source;
            if not (Content_fit.equal old.content_fit new_.content_fit)
            then W.Picture.set_content_fit p (content_fit new_.content_fit);
            if not (Bool.equal old.can_shrink new_.can_shrink)
            then W.Picture.set_can_shrink p new_.can_shrink;
            if not (Option.equal String.equal old.alternative_text new_.alternative_text)
            then W.Picture.set_alternative_text p new_.alternative_text)
        | _, k -> Widget_impl.wrong_kind "Picture" k)
  ; signals = []
  ; children = Widget_impl.No_children
  }
;;
```
Doc-comment note for `Node.picture`, lifted from stavekeeper's hard-won comment: "`Attr.width_request`/`height_request` raise a picture's *minimum* size but not its *natural* one, which GTK derives from the image's own pixel dimensions — so a homogeneous container still sizes to the image. To cap the allocated size, put the picture in an `Overlay` as an unmeasured overlay (`Attr.measure_overlay false`) over a spacer sized with `width_request`/`height_request`, and use `~can_shrink:true ~content_fit:Contain`."

- [ ] **Step 7: `src/widgets/w_separator.ml`**

```ocaml
open! Core
open Bonsai_gtk_vtree
open Gtk_import

let orientation : Orientation.t -> Gtk_enums.orientation = function
  | Horizontal -> `HORIZONTAL
  | Vertical -> `VERTICAL
;;

let impl : Widget_impl.t =
  { name = "Separator"
  ; create =
      (fun (kind : Kind.t) ->
        match kind with
        | Separator { orientation = o } -> (W.Separator.new_ (orientation o) :> Widget.t)
        | k -> Widget_impl.wrong_kind "Separator" k)
  ; update =
      (fun w ~(old : Kind.t) (new_ : Kind.t) ->
        match old, new_ with
        | Separator old, Separator new_ ->
          if not (Orientation.equal old.orientation new_.orientation)
          then
            W.Orientable.set_orientation
              (W.Orientable.from_gobject w)
              (orientation new_.orientation)
        | _, k -> Widget_impl.wrong_kind "Separator" k)
  ; signals = []
  ; children = Widget_impl.No_children
  }
;;
```

- [ ] **Step 8: `src/paintable_picture.ml(i)` — the library's own native widget**

```ocaml
open! Core
open Bonsai_gtk_vtree
open Gtk_import
module Paintable = Ocgtk_gdk.Gdk.Wrappers.Paintable

module Input = struct
  type t =
    { paintable : Paintable.t option
    ; content_fit : Content_fit.t
    ; can_shrink : bool
    }

  (* [Gobject.same] rather than [phys_equal]: every C-to-OCaml crossing allocates a fresh
     wrapper block for the same pointer, so two handles to one texture are never
     physically equal (spec §2.2). *)
  let same_paintable a b =
    match a, b with
    | None, None -> true
    | Some a, Some b -> Gobject.same a b
    | None, Some _ | Some _, None -> false
  ;;

  let equal a b =
    same_paintable a.paintable b.paintable
    && Content_fit.equal a.content_fit b.content_fit
    && Bool.equal a.can_shrink b.can_shrink
  ;;
end

module M = struct
  type input = Input.t

  let name = "picture(paintable)"

  let apply (p : W.Picture.t) (i : Input.t) =
    W.Picture.set_paintable p i.paintable;
    W.Picture.set_content_fit p (W_picture.content_fit i.content_fit);
    W.Picture.set_can_shrink p i.can_shrink
  ;;

  let create (i : Input.t) =
    let p = W.Picture.new_ () in
    apply p i;
    (p :> Widget.t)
  ;;

  (* [update] runs on every re-render, not only when the input changed (see
     [Native_gtk.S]'s doc comment): the patcher compares native payloads physically and a
     fresh payload is allocated each frame. Hence the explicit [Input.equal]. *)
  let update w ~old i = if not (Input.equal old i) then apply (cast w) i

  (* The widget's reference to the paintable is GTK's business; nothing was acquired here
     that outlives it. *)
  let destroy _ = ()
end

(* Built once, at the top level, as every [Native_gtk.impl] must be: the impl carries the
   type witness the patcher matches on, so one per render would be a different widget. *)
let impl = Native_gtk.impl (module M)

let node ?key ?attrs ?(content_fit = Content_fit.Contain) ?(can_shrink = true) paintable =
  Native_gtk.node ?key ?attrs impl { Input.paintable; content_fit; can_shrink }
;;
```
`w_picture.ml` must expose `content_fit` (drop it from the `let`-private list — it is already top-level, so nothing to do beyond not shadowing it).

The mli:
```ocaml
(** A [GtkPicture] fed a [GdkPaintable] -- a texture the application rendered itself,
    typically a [Gdk.Memory_texture] built from pixels it owns.

    This is the library's own use of {!Bonsai_gtk.Native}: the input is an ocgtk value, and
    [bonsai_gtk.vtree] may not mention ocgtk types, so it cannot be a [Kind.t] and a
    [Node.picture] cannot take it. It is also the worked example to copy when an
    application needs a widget of its own.

    The paintable is compared with [Gobject.same], not [phys_equal]: ocgtk allocates a
    fresh wrapper for the same GObject on every crossing, so physical equality on these
    handles is always false. Keeping the *same* texture across renders therefore costs
    nothing; building a new one each frame re-uploads it, which is the caller's decision to
    make. *)
val node
  :  ?key:Key.t
  -> ?attrs:Attr.t list
  -> ?content_fit:Content_fit.t
  -> ?can_shrink:bool
  -> Ocgtk_gdk.Gdk.Wrappers.Paintable.t option
  -> Node.t
```
Expose it as `Bonsai_gtk.Native.Picture` in `src/bonsai_gtk.ml(i)`:
```ocaml
module Native = struct
  module type S = Native_gtk.S
  type 'a impl = 'a Native_gtk.impl
  let impl = Native_gtk.impl
  let node = Native_gtk.node
  module Picture = Paintable_picture
end
```

- [ ] **Step 9: Registry, `Live_tree`**

```ocaml
  | Image _ -> W_image.impl
  | Picture _ -> W_picture.impl
  | Separator _ -> W_separator.impl
```
```ocaml
     | "GtkImage" ->
       (match W.Image.get_icon_name (cast w) with
        | None -> []
        | Some n -> [ Sexp.List [ Atom "icon"; Atom n ] ])
       @ int_prop "pixel-size" (W.Image.get_pixel_size (cast w)) ~default:(-1)
     | "GtkPicture" ->
       flag_prop "has-paintable" (Option.is_some (W.Picture.get_paintable (cast w)))
       @ flag_prop "can-shrink" (W.Picture.get_can_shrink (cast w))
```
Print `has-paintable` rather than anything about the paintable itself: a texture's identity is not stable across runs and its pixels are not what the test is claiming.

- [ ] **Step 10: Run, read, promote, `./scripts/ci.sh`.**
Watch for: the filename-backed picture reporting `has-paintable` (GTK loads the file into a texture, so it does), and the second dump showing the swapped sources — the first image gains a file (so loses its `icon`), the second gains an icon, the third loses its paintable and its `can-shrink`.

- [ ] **Step 11: Commit**

```bash
dune fmt 2>/dev/null; git add vtree src test test/live
GIT_EDITOR=true git commit -F - <<'MSG'
Image, Picture, Separator, and Native.Picture for paintable sources

Image and Picture sources are closed variants rather than optional arguments:
GTK's setters do not compose, so exclusivity has to be a type error.

Native.Picture is the library's first shipped Node.native widget -- a
GtkPicture fed a GdkPaintable, which cannot be a Kind.t because the vtree may
not name ocgtk types. It is also the worked example applications copy.

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01Sg3Ci8U8kUKR8C3PL1pNSs
MSG
```

---

### Task 7: Single-child containers — ScrolledWindow, Frame, Expander, Revealer

Four containers whose child shape M0 already supports (`Widget_impl.Single`), so this task is props and signals only. `ScrolledWindow` is the one stavekeeper leans on hardest (`library_window.ml`, `practice_bar.ml`: `set_policy`, `set_kinetic_scrolling`, `set_overlay_scrolling`, `set_propagate_natural_height`).

**Files:**
- Create: `vtree/policy.ml`, `vtree/reveal_transition.ml`, `src/widgets/w_scrolled_window.ml`, `src/widgets/w_frame.ml`, `src/widgets/w_expander.ml`, `src/widgets/w_revealer.ml`
- Modify: `vtree/attr.ml(i)`, `vtree/kind.ml(i)`, `vtree/node.ml(i)`, `vtree/bonsai_gtk_vtree.ml`, `src/widgets/registry.ml`, `src/live_tree.ml`, `src/bonsai_gtk.ml(i)`, `test/test_widgets.ml`, `test/live/live_containers.ml`

**Interfaces:**
- Produces:
  ```ocaml
  module Policy : sig type t = Always | Automatic | Never | External_ end
  module Reveal_transition : sig
    type t = None_ | Crossfade | Slide_right | Slide_left | Slide_up | Slide_down
           | Swing_right | Swing_left | Swing_up | Swing_down
  end

  (* Attr *)
  val on_expanded_changed : (bool -> unit Ui_effect.t) -> t
  val on_revealed : (bool -> unit Ui_effect.t) -> t

  (* Node *)
  val scrolled_window
    :  ?key:Key.t -> ?attrs:Attr.t list -> ?hpolicy:Policy.t -> ?vpolicy:Policy.t
    -> ?min_content_width:int -> ?min_content_height:int
    -> ?max_content_width:int -> ?max_content_height:int
    -> ?propagate_natural_width:bool -> ?propagate_natural_height:bool
    -> ?has_frame:bool -> ?kinetic_scrolling:bool -> ?overlay_scrolling:bool
    -> t -> t
  val frame : ?key:Key.t -> ?attrs:Attr.t list -> ?label:string -> ?label_align:float -> t -> t
  val expander
    :  ?key:Key.t -> ?attrs:Attr.t list -> ?label:string -> ?use_markup:bool
    -> expanded:bool -> t -> t
  val revealer
    :  ?key:Key.t -> ?attrs:Attr.t list -> ?transition:Reveal_transition.t
    -> ?transition_duration:int -> reveal:bool -> t -> t
  ```

Naming: `Policy.External_` and `Reveal_transition.None_` carry trailing underscores because `External` is an OCaml keyword-adjacent identifier in some positions and `None` would shadow `Option.None` in every match — the same reason `Ellipsize` has no `None`. `Reveal_transition` keeps a `None_` (unlike `Ellipsize`) because "no transition" is a real, selectable GTK value here, not the absence of a property.

`Expander`'s `expanded` and `Revealer`'s `reveal_child` are controlled on the same rule as the toggles. Their signals come from `notify::` (`GtkExpander` has only `activate`, which fires before the property settles; `GtkRevealer`'s `child-revealed` is a read-only property that flips when the *animation* finishes, which is what makes it useful — it is how you unmount a subtree after it has slid away).

- [ ] **Step 1: Failing headless test** (`test/test_widgets.ml`)

```ocaml
let%expect_test "single-child containers" =
  print_s
    [%sexp
      (Node.scrolled_window
         ~vpolicy:Automatic
         ~hpolicy:Never
         ~propagate_natural_height:true
         (Node.box
            ~orientation:Vertical
            [ Node.frame ~label:"Group" (Node.label "framed")
            ; Node.expander ~label:"More" ~expanded:false (Node.label "hidden")
            ; Node.revealer ~reveal:true ~transition:Slide_down (Node.label "shown")
            ])
       : Node.t)];
  [%expect {| |}]
;;
```

- [ ] **Step 2: Failing live test** — append to `test/live/live_containers.ml`

```ocaml
  (* Controlled [expanded] / [reveal], and the Single-child swap the patcher already
     handles: the frame's child changes kind, so the widget is replaced in place. *)
  let containers ~expanded ~reveal ~framed =
    Node.window
      ~title:"containers"
      (Node.scrolled_window
         ~hpolicy:Never
         ~vpolicy:Automatic
         ~min_content_height:120
         ~propagate_natural_height:true
         (Node.box
            ~orientation:Vertical
            [ Node.frame
                ~label:"Group"
                (if framed then Node.label "framed" else Node.button ~label:"framed" ())
            ; Node.expander
                ~attrs:[ Attr.on_expanded_changed (fun _ -> Ui_effect.Ignore) ]
                ~label:"More"
                ~expanded
                (Node.label "detail")
            ; Node.revealer
                ~attrs:[ Attr.on_revealed (fun _ -> Ui_effect.Ignore) ]
                ~transition:None_
                ~reveal
                (Node.label "revealed")
            ]))
  in
  let live =
    P.mount ctx ~path:"root" ~is_root:true (containers ~expanded:false ~reveal:false ~framed:true)
  in
  print_s (Live_tree.dump live.widget);
  let live =
    P.patch ctx ~path:"root" ~is_root:true live (containers ~expanded:true ~reveal:true ~framed:false)
  in
  print_s (Live_tree.dump live.widget);
  P.destroy ctx live
```
`~transition:None_` on the revealer is deliberate: with an animation, `child-revealed` and the widget's visibility settle on a timer, and the dump would race it.

- [ ] **Step 3: Run to verify failure.**

- [ ] **Step 4: The two enum modules**

```ocaml
(* vtree/policy.ml *)
open! Core

(** When a scrolled window shows a scrollbar. [External_] means "never show one, but do not
    let the content dictate the size either" -- for sharing a scrollbar between views. *)
type t =
  | Always
  | Automatic
  | Never
  | External_
[@@deriving sexp_of, equal, compare]

(* vtree/reveal_transition.ml *)
open! Core

type t =
  | None_
  | Crossfade
  | Slide_right
  | Slide_left
  | Slide_up
  | Slide_down
  | Swing_right
  | Swing_left
  | Swing_up
  | Swing_down
[@@deriving sexp_of, equal, compare]
```

- [ ] **Step 5: `vtree/attr.ml(i)`** — two more event attrs, same five edits each (`Name.t`, `t`, `name`, `equal`, `is_event`, inert `Attr_apply` arms)

```ocaml
(** Fires when the user opens or closes an [expander], carrying its new state. *)
let on_expanded_changed f = On_expanded_changed f

(** Fires when a [revealer]'s *animation* finishes, carrying whether the child ended up
    revealed. This is what to hang "now that it has slid away, drop it from the model" on;
    [reveal] itself is the input, not the outcome. *)
let on_revealed f = On_revealed f
```

- [ ] **Step 6: `vtree/kind.ml(i)` / `node.ml(i)`**

```ocaml
type scrolled_window_props =
  { hpolicy : Policy.t
  ; vpolicy : Policy.t
  ; min_content_width : int
  ; min_content_height : int
  ; max_content_width : int
  ; max_content_height : int
  ; propagate_natural_width : bool
  ; propagate_natural_height : bool
  ; has_frame : bool
  ; kinetic_scrolling : bool
  ; overlay_scrolling : bool
  }
[@@deriving sexp_of, equal]

type frame_props =
  { label : string option
  ; label_align : float
  }
[@@deriving sexp_of, equal]

type expander_props =
  { label : string option
  ; expanded : bool
  ; use_markup : bool
  }
[@@deriving sexp_of, equal]

type revealer_props =
  { reveal : bool
  ; transition : Reveal_transition.t
  ; transition_duration : int
  }
[@@deriving sexp_of, equal]
```
GTK's defaults: policies `Automatic`, min/max content sizes `-1`, propagate flags `false`, `has_frame = false`, `kinetic_scrolling = true`, `overlay_scrolling = true`, `label_align = 0.`, `use_markup = false`, `transition = None_`, `transition_duration = 250`.

All four constructors take the child positionally (like `Node.window`), so `Children.Single (Some child)`.

- [ ] **Step 7: `src/widgets/w_scrolled_window.ml`**

```ocaml
open! Core
open Bonsai_gtk_vtree
open Gtk_import

let policy : Policy.t -> Gtk_enums.policytype = function
  | Always -> `ALWAYS
  | Automatic -> `AUTOMATIC
  | Never -> `NEVER
  | External_ -> `EXTERNAL
;;

let impl : Widget_impl.t =
  { name = "ScrolledWindow"
  ; create =
      (fun (kind : Kind.t) ->
        match kind with
        | Scrolled_window p ->
          let s = W.Scrolled_window.new_ () in
          let w = (s :> Widget.t) in
          Widget_impl.batch w (fun () ->
            W.Scrolled_window.set_policy s (policy p.hpolicy) (policy p.vpolicy);
            W.Scrolled_window.set_min_content_width s p.min_content_width;
            W.Scrolled_window.set_min_content_height s p.min_content_height;
            W.Scrolled_window.set_max_content_width s p.max_content_width;
            W.Scrolled_window.set_max_content_height s p.max_content_height;
            W.Scrolled_window.set_propagate_natural_width s p.propagate_natural_width;
            W.Scrolled_window.set_propagate_natural_height s p.propagate_natural_height;
            W.Scrolled_window.set_has_frame s p.has_frame;
            W.Scrolled_window.set_kinetic_scrolling s p.kinetic_scrolling;
            W.Scrolled_window.set_overlay_scrolling s p.overlay_scrolling);
          w
        | k -> Widget_impl.wrong_kind "ScrolledWindow" k)
  ; update =
      (fun w ~(old : Kind.t) (new_ : Kind.t) ->
        match old, new_ with
        | Scrolled_window old, Scrolled_window new_ ->
          let s : W.Scrolled_window.t = cast w in
          Widget_impl.batch w (fun () ->
            (* GTK sets both policies in one call, so either one changing rewrites both. *)
            if not
                 (Policy.equal old.hpolicy new_.hpolicy
                  && Policy.equal old.vpolicy new_.vpolicy)
            then W.Scrolled_window.set_policy s (policy new_.hpolicy) (policy new_.vpolicy);
            if old.min_content_width <> new_.min_content_width
            then W.Scrolled_window.set_min_content_width s new_.min_content_width;
            if old.min_content_height <> new_.min_content_height
            then W.Scrolled_window.set_min_content_height s new_.min_content_height;
            if old.max_content_width <> new_.max_content_width
            then W.Scrolled_window.set_max_content_width s new_.max_content_width;
            if old.max_content_height <> new_.max_content_height
            then W.Scrolled_window.set_max_content_height s new_.max_content_height;
            if not (Bool.equal old.propagate_natural_width new_.propagate_natural_width)
            then W.Scrolled_window.set_propagate_natural_width s new_.propagate_natural_width;
            if not (Bool.equal old.propagate_natural_height new_.propagate_natural_height)
            then
              W.Scrolled_window.set_propagate_natural_height s new_.propagate_natural_height;
            if not (Bool.equal old.has_frame new_.has_frame)
            then W.Scrolled_window.set_has_frame s new_.has_frame;
            if not (Bool.equal old.kinetic_scrolling new_.kinetic_scrolling)
            then W.Scrolled_window.set_kinetic_scrolling s new_.kinetic_scrolling;
            if not (Bool.equal old.overlay_scrolling new_.overlay_scrolling)
            then W.Scrolled_window.set_overlay_scrolling s new_.overlay_scrolling)
        | _, k -> Widget_impl.wrong_kind "ScrolledWindow" k)
  ; signals = []
  ; children =
      Widget_impl.Single { set = (fun w child -> W.Scrolled_window.set_child (cast w) child) }
  }
;;
```
Scroll *position* is deliberately not a prop: it lives on the adjustments, changes continuously while the user scrolls, and a controlled version would fight every scroll event. Preserving it across re-renders is what `Key.t` is for. Say so in the mli, and note that `edge-reached`/`edge-overshot` (useful for infinite lists) are left to M2 along with `ListBox`.

- [ ] **Step 8: `src/widgets/w_frame.ml`**

```ocaml
open! Core
open Bonsai_gtk_vtree
open Gtk_import

let impl : Widget_impl.t =
  { name = "Frame"
  ; create =
      (fun (kind : Kind.t) ->
        match kind with
        | Frame p ->
          let f = W.Frame.new_ p.label in
          if Float.( <> ) p.label_align 0. then W.Frame.set_label_align f p.label_align;
          (f :> Widget.t)
        | k -> Widget_impl.wrong_kind "Frame" k)
  ; update =
      (fun w ~(old : Kind.t) (new_ : Kind.t) ->
        match old, new_ with
        | Frame old, Frame new_ ->
          let f : W.Frame.t = cast w in
          Widget_impl.batch w (fun () ->
            if not (Option.equal String.equal old.label new_.label)
            then W.Frame.set_label f new_.label;
            if Float.( <> ) old.label_align new_.label_align
            then W.Frame.set_label_align f new_.label_align)
        | _, k -> Widget_impl.wrong_kind "Frame" k)
  ; signals = []
  ; children = Widget_impl.Single { set = (fun w child -> W.Frame.set_child (cast w) child) }
  }
;;
```
`set_label_widget` (an arbitrary widget as the frame's title) is not exposed: it is a second child slot, which `Widget_impl.Slots` could express, but no caller in sight wants it. Named in the mli; `Node.native` covers it.

- [ ] **Step 9: `src/widgets/w_expander.ml`**

```ocaml
open! Core
open Bonsai_gtk_vtree
open Gtk_import

(* [GtkExpander::activate] fires before [expanded] settles, so the handler would read the
   old value. [notify::expanded] fires after (spec §6.4). *)
let expanded_changed : Signals.spec =
  { attr = Attr.Name.On_expanded_changed
  ; connect = Signals.notify ~prop:"expanded"
  ; fire =
      (fun w (attr : Attr.t) ->
        match attr with
        | On_expanded_changed handler -> Some (handler (W.Expander.get_expanded (cast w)))
        | _ -> None)
  }
;;

let impl : Widget_impl.t =
  { name = "Expander"
  ; create =
      (fun (kind : Kind.t) ->
        match kind with
        | Expander p ->
          let e = W.Expander.new_ p.label in
          let w = (e :> Widget.t) in
          Widget_impl.batch w (fun () ->
            if p.use_markup then W.Expander.set_use_markup e true;
            if p.expanded then W.Expander.set_expanded e true);
          w
        | k -> Widget_impl.wrong_kind "Expander" k)
  ; update =
      (fun w ~(old : Kind.t) (new_ : Kind.t) ->
        match old, new_ with
        | Expander old, Expander new_ ->
          let e : W.Expander.t = cast w in
          Widget_impl.batch w (fun () ->
            if not (Option.equal String.equal old.label new_.label)
            then W.Expander.set_label e new_.label;
            if not (Bool.equal old.use_markup new_.use_markup)
            then W.Expander.set_use_markup e new_.use_markup;
            if not (Bool.equal (W.Expander.get_expanded e) new_.expanded)
            then W.Expander.set_expanded e new_.expanded)
        | _, k -> Widget_impl.wrong_kind "Expander" k)
  ; signals = [ expanded_changed ]
  ; children = Widget_impl.Single { set = (fun w child -> W.Expander.set_child (cast w) child) }
  }
;;
```

- [ ] **Step 10: `src/widgets/w_revealer.ml`**

```ocaml
open! Core
open Bonsai_gtk_vtree
open Gtk_import

let transition : Reveal_transition.t -> Gtk_enums.revealertransitiontype = function
  | None_ -> `NONE
  | Crossfade -> `CROSSFADE
  | Slide_right -> `SLIDE_RIGHT
  | Slide_left -> `SLIDE_LEFT
  | Slide_up -> `SLIDE_UP
  | Slide_down -> `SLIDE_DOWN
  | Swing_right -> `SWING_RIGHT
  | Swing_left -> `SWING_LEFT
  | Swing_up -> `SWING_UP
  | Swing_down -> `SWING_DOWN
;;

(* [child-revealed] is read-only and flips when the animation *finishes*, which is the
   useful moment: it is when a hidden subtree can be dropped from the model. *)
let revealed : Signals.spec =
  { attr = Attr.Name.On_revealed
  ; connect = Signals.notify ~prop:"child-revealed"
  ; fire =
      (fun w (attr : Attr.t) ->
        match attr with
        | On_revealed handler -> Some (handler (W.Revealer.get_child_revealed (cast w)))
        | _ -> None)
  }
;;

let impl : Widget_impl.t =
  { name = "Revealer"
  ; create =
      (fun (kind : Kind.t) ->
        match kind with
        | Revealer p ->
          let r = W.Revealer.new_ () in
          let w = (r :> Widget.t) in
          Widget_impl.batch w (fun () ->
            W.Revealer.set_transition_type r (transition p.transition);
            W.Revealer.set_transition_duration r p.transition_duration;
            W.Revealer.set_reveal_child r p.reveal);
          w
        | k -> Widget_impl.wrong_kind "Revealer" k)
  ; update =
      (fun w ~(old : Kind.t) (new_ : Kind.t) ->
        match old, new_ with
        | Revealer old, Revealer new_ ->
          let r : W.Revealer.t = cast w in
          Widget_impl.batch w (fun () ->
            if not (Reveal_transition.equal old.transition new_.transition)
            then W.Revealer.set_transition_type r (transition new_.transition);
            if old.transition_duration <> new_.transition_duration
            then W.Revealer.set_transition_duration r new_.transition_duration;
            (* Against the widget's own [reveal-child], which is the input property (and
               so is not moved by the animation); [child-revealed] is the outcome. *)
            if not (Bool.equal (W.Revealer.get_reveal_child r) new_.reveal)
            then W.Revealer.set_reveal_child r new_.reveal)
        | _, k -> Widget_impl.wrong_kind "Revealer" k)
  ; signals = [ revealed ]
  ; children = Widget_impl.Single { set = (fun w child -> W.Revealer.set_child (cast w) child) }
  }
;;
```

- [ ] **Step 11: Registry, `Live_tree`**

```ocaml
     | "GtkFrame" -> [ [%sexp `label (W.Frame.get_label (cast w) : string option)] ]
     | "GtkExpander" ->
       [ [%sexp `label (W.Expander.get_label (cast w) : string option)] ]
       @ flag_prop "expanded" (W.Expander.get_expanded (cast w))
     | "GtkRevealer" ->
       flag_prop "reveal" (W.Revealer.get_reveal_child (cast w))
       @ flag_prop "revealed" (W.Revealer.get_child_revealed (cast w))
     | "GtkScrolledWindow" ->
       int_prop "min-content-height" (W.Scrolled_window.get_min_content_height (cast w)) ~default:(-1)
       @ int_prop "min-content-width" (W.Scrolled_window.get_min_content_width (cast w)) ~default:(-1)
```
A `GtkScrolledWindow` has two internal `GtkScrollbar` children, which `widget_children` will print. Leave them: they are the honest tree, and their presence in the expected file is itself a check that the child really landed inside the viewport rather than beside it.

- [ ] **Step 12: Run, read, promote, `./scripts/ci.sh`. Commit**

```bash
dune fmt 2>/dev/null; git add vtree src test
GIT_EDITOR=true git commit -F - <<'MSG'
ScrolledWindow, Frame, Expander, Revealer

Expander's [expanded] and Revealer's [reveal] are controlled like the toggles,
and their signals come from notify:: rather than the activate/state signals
that fire before the property settles.

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01Sg3Ci8U8kUKR8C3PL1pNSs
MSG
```

---

### Task 8: Named slots — CenterBox, Paned, Overlay

The first task to need a children shape M0 does not have. Spec §5.3's fourth row: `Slots` (named), for containers whose children are addressed by role rather than position. It also needs list ops that can see the child *node*, because an overlay's children carry a per-child layout flag (`measure-overlay`) that lives on the parent, not on the child widget — which is the same mechanism Task 9's `Grid` cells and `Stack` page titles need.

stavekeeper uses both: `cards.ml` and `library_window.ml` put an unmeasured overlay over a spacer to cap a `GtkPicture`'s allocated size (`overlay#set_measure_overlay picture_widget false`), which is the single trick that makes their thumbnail grid work.

**Files:**
- Create: `vtree/children.mli`, `src/widgets/w_center_box.ml`, `src/widgets/w_paned.ml`, `src/widgets/w_overlay.ml`
- Modify: `vtree/children.ml`, `vtree/node.ml(i)`, `vtree/kind.ml(i)`, `vtree/attr.ml(i)`, `src/widget_impl.ml(i)`, `src/patcher.ml`, `src/widgets/w_box.ml`, `src/widgets/registry.ml`, `src/live_tree.ml`, `test/test_widgets.ml`, `test/test_reconcile.ml` (nothing — check), `test/live/live_containers.ml`

**Interfaces:**
- Produces:
  ```ocaml
  (* vtree/children.ml *)
  type 'a t =
    | No_children
    | Single of 'a option
    | List of 'a list
    | Slots of (string * 'a t) list       (* slot name -> that slot's own shape *)
  [@@deriving sexp_of]

  (* Widget_impl *)
  type list_ops =
    { insert : Widget.t -> after:Widget.t option -> node:Node.t -> Widget.t -> unit
    ; move : Widget.t -> child:Widget.t -> after:Widget.t option -> unit
    ; remove : Widget.t -> Widget.t -> unit
    ; updated : Widget.t -> old:Node.t -> node:Node.t -> Widget.t -> unit
    }
  type single_ops = { set : Widget.t -> Widget.t option -> unit }
  type slot_ops =
    | Slot_single of single_ops
    | Slot_list of list_ops
  type child_ops =
    | No_children
    | Single of single_ops
    | List of list_ops
    | Slots of (string * slot_ops) list
  val no_list_update : Widget.t -> old:Node.t -> node:Node.t -> Widget.t -> unit

  (* Attr *)
  val measure_overlay : bool -> t

  (* Node *)
  val center_box
    :  ?key:Key.t -> ?attrs:Attr.t list -> ?shrink_center_last:bool
    -> ?start:t -> ?center:t -> ?end_:t -> unit -> t
  val paned
    :  ?key:Key.t -> ?attrs:Attr.t list -> ?position:int -> ?wide_handle:bool
    -> ?resize_start:bool -> ?resize_end:bool -> ?shrink_start:bool -> ?shrink_end:bool
    -> orientation:Orientation.t -> start:t -> end_:t -> t
  val overlay : ?key:Key.t -> ?attrs:Attr.t list -> ?overlays:t list -> t -> t
  ```

**Why the list ops gain `node`.** A list container's per-child settings sometimes live on the *parent*: `gtk_overlay_set_measure_overlay(overlay, child, bool)`, `gtk_grid_attach(grid, child, col, row, w, h)`, `gtk_stack_page_set_title(page, title)`. None of them is a property of the child widget, so `Attr_apply` cannot apply them and the child impl cannot know them. They are attrs on the child *node* that the parent impl reads. Hence: `insert` receives the node it is inserting, and a new `updated` hook fires after a child is patched in place so the parent can react to those attrs changing. `move` does not need the node (nothing positional depends on it).

`Widget_impl.no_list_update` is the do-nothing `updated` for the containers with no such attrs (`Box`, and Task 9's nothing-else); write it once rather than a lambda per impl.

- [ ] **Step 1: Failing headless test** (`test/test_widgets.ml`)

The sexp of a slotted node is the thing to pin, because it is a new `Children.t` constructor and every expect file that ever prints one depends on its shape:

```ocaml
let%expect_test "slot containers print their slots by name" =
  print_s
    [%sexp
      (Node.center_box
         ~start:(Node.label "l")
         ~center:(Node.label "c")
         ~end_:(Node.button ~label:"r" ())
         ()
       : Node.t)];
  [%expect {| |}];
  print_s
    [%sexp
      (Node.paned
         ~orientation:Horizontal
         ~position:240
         ~start:(Node.label "sidebar")
         ~end_:(Node.label "content")
       : Node.t)];
  [%expect {| |}];
  print_s
    [%sexp
      (Node.overlay
         ~overlays:
           [ Node.picture ~attrs:[ Attr.measure_overlay false ] (Filename "/tmp/t.png") ]
         (Node.box ~orientation:Vertical ~attrs:[ Attr.width_request 150 ] [])
       : Node.t)];
  [%expect {| |}]
;;

let%expect_test "find_by_test_id descends into slots" =
  let view =
    Node.overlay
      ~overlays:[ Node.label ~attrs:[ Attr.test_id "badge" ] "9" ]
      (Node.label "under")
  in
  print_s [%sexp (Option.is_some (Node.find_by_test_id view "badge") : bool)];
  [%expect {| |}]
;;
```

- [ ] **Step 2: Failing live test** — append to `test/live/live_containers.ml`

```ocaml
  (* Slots: each is patched independently, and clearing one must not disturb the others.
     The overlay case is stavekeeper's thumbnail trick -- an unmeasured overlay over a
     sized spacer -- so [measure-overlay] is checked as a live property, not just a node. *)
  let slots ~center ~badge =
    Node.window
      ~title:"slots"
      (Node.paned
         ~orientation:Horizontal
         ~position:120
         ~start:
           (Node.center_box
              ~start:(Node.label "L")
              ?center:(if center then Some (Node.label "C") else None)
              ~end_:(Node.button ~label:"R" ())
              ())
         ~end_:
           (Node.overlay
              ~overlays:
                (Node.label ~key:"badge" ~attrs:[ Attr.measure_overlay badge ] "9"
                 :: (if badge then [ Node.label ~key:"extra" "+" ] else []))
              (Node.box
                 ~orientation:Vertical
                 ~attrs:[ Attr.width_request 150; Attr.height_request 60 ]
                 [])))
  in
  let live = P.mount ctx ~path:"root" ~is_root:true (slots ~center:true ~badge:false) in
  print_s (Live_tree.dump live.widget);
  let live = P.patch ctx ~path:"root" ~is_root:true live (slots ~center:false ~badge:true) in
  print_s (Live_tree.dump live.widget);
  (* A slot the impl does not have is structural misuse, like a nested window. *)
  P.destroy ctx live
```

- [ ] **Step 3: Run to verify failure.**

- [ ] **Step 4: `vtree/children.ml(i)`**

```ocaml
(* children.ml *)
open! Core

type 'a t =
  | No_children
  | Single of 'a option
  | List of 'a list
  | Slots of (string * 'a t) list
[@@deriving sexp_of]

let rec iter t ~f =
  match t with
  | No_children -> ()
  | Single c -> Option.iter c ~f
  | List l -> List.iter l ~f
  | Slots slots -> List.iter slots ~f:(fun (_, s) -> iter s ~f)
;;

let rec find_map t ~f =
  match t with
  | No_children -> None
  | Single c -> Option.bind c ~f
  | List l -> List.find_map l ~f
  | Slots slots -> List.find_map slots ~f:(fun (_, s) -> find_map s ~f)
;;
```
The mli M0 never wrote (a backlog hygiene item), documenting the invariant that makes the patcher's matching sound:

```ocaml
(* children.mli *)
open! Core

(** The shape of a node's children, fixed by its {!Kind.t} (spec §5.3).

    [Slots] is for containers whose children are addressed by role rather than by
    position: a [center_box]'s [start]/[center]/[end], a [paned]'s two halves, an
    [overlay]'s main child and its overlays. Each slot carries its own shape, so a slot is
    itself a [Single] or a [List] and is patched by the same code.

    The patcher requires a node's shape and its impl's [child_ops] to agree, including the
    slot *names* and their order; a mismatch is [Invalid_argument] rather than a silently
    dropped child, because both sides are written in this repository and a mismatch is
    always a bug in one of them. *)
type 'a t =
  | No_children
  | Single of 'a option
  | List of 'a list
  | Slots of (string * 'a t) list
[@@deriving sexp_of]

val iter : 'a t -> f:('a -> unit) -> unit
val find_map : 'a t -> f:('a -> 'b option) -> 'b option
```

Rewrite `Node.find_by_test_id`'s recursion with `Children.find_map`, which is what it should have been:
```ocaml
let rec find_by_test_id t id =
  if Option.equal String.equal (Attrs.test_id t.attrs) (Some id)
  then Some t
  else Children.find_map t.children ~f:(fun c -> find_by_test_id c id)
;;
```

- [ ] **Step 5: `src/widget_impl.ml(i)`**

```ocaml
type single_ops = { set : Widget.t -> Widget.t option -> unit }

type list_ops =
  { insert : Widget.t -> after:Widget.t option -> node:Node.t -> Widget.t -> unit
  ; move : Widget.t -> child:Widget.t -> after:Widget.t option -> unit
  ; remove : Widget.t -> Widget.t -> unit
  ; updated : Widget.t -> old:Node.t -> node:Node.t -> Widget.t -> unit
  }

type slot_ops =
  | Slot_single of single_ops
  | Slot_list of list_ops

type child_ops =
  | No_children
  | Single of single_ops
  | List of list_ops
  | Slots of (string * slot_ops) list

(* For containers with no per-child settings of their own -- the common case. *)
let no_list_update _parent ~old:_ ~node:_ _child = ()
```
mli, on `list_ops`:
```ocaml
  { insert : Widget.t -> after:Widget.t option -> node:Node.t -> Widget.t -> unit
  (** Add a child not yet in the container, directly after [after] ([None] = first).
      [node] is the child's description: some containers keep per-child settings of their
      own -- an overlay's measure flag, a grid cell, a stack page's title -- which are not
      properties of the child widget and so are read from the child node's attrs here
      rather than applied by [Attr_apply]. *)
  ; ...
  ; updated : Widget.t -> old:Node.t -> node:Node.t -> Widget.t -> unit
  (** Called after a child that stayed in place was patched, with its previous and new
      descriptions. This is where those same parent-held settings are re-applied when they
      change. [no_list_update] for containers that have none. *)
  }
```

- [ ] **Step 6: `src/patcher.ml` — factor the shapes, then add `Slots`**

`mount`'s and `patch_children`'s bodies become dispatch over three helpers, so a slot reuses exactly the code a top-level shape uses. Sketch (write it out properly in the file):

```ocaml
and mount_children ctx ~path (widget : Widget.t) impl_name
  (children : Node.t Children.t) (ops : Widget_impl.child_ops) : live Children.t =
  match children, ops with
  | No_children, _ -> Children.No_children
  | Single c, Single { set } -> Single (mount_single ctx ~path widget ~set c)
  | List cs, List ops -> List (mount_list ctx ~path widget ~ops cs)
  | Slots node_slots, Slots op_slots ->
    Slots
      (List.map2_exn_or_invalid ~path node_slots op_slots ~f:(fun (name, cs) (op_name, op) ->
         if not (String.equal name op_name)
         then invalid_argf "%s: slot %s does not exist on %s" path name impl_name ();
         let path = sprintf "%s/%s" path name in
         match cs, op with
         | Single c, Slot_single { set } -> name, Children.Single (mount_single ctx ~path widget ~set c)
         | List cs, Slot_list ops -> name, Children.List (mount_list ctx ~path widget ~ops cs)
         | _ -> invalid_argf "%s: slot %s has the wrong shape for %s" path name impl_name ()))
  | (Single _ | List _ | Slots _), _ ->
    invalid_argf "%s: node's children do not match %s's shape" path impl_name ()
```
`List.map2_exn_or_invalid` is not a real function: use `match List.zip node_slots op_slots with Ok pairs -> ... | Unequal_lengths -> invalid_argf "%s: %s has %d slots, node has %d" ...`. Slot lists are written by this repository on both sides and are short and fixed, so equal length and equal order is a fair requirement — and a loud one when broken.

`patch_children` gets the same three-way split (`patch_single`, `patch_list`, and the `Slots` arm zipping live slots, node slots and op slots), and `patch_list` is Task 1's op loop verbatim plus one line: after a same-kind `Update`, call the container's hook.

```ocaml
      | Update { index; item; old = _ } ->
        let l = List.nth_exn !cur index in
        let old_node = l.node in
        let l' = patch ctx ~path:(child_path path index) ~is_root:false l item in
        if phys_equal l l'
        then ops.updated parent ~old:old_node ~node:item l'.widget
        else (
          let without = List.filteri !cur ~f:(fun i _ -> i <> index) in
          ops.remove parent l.widget;
          ops.insert parent ~after:(after_of without index) ~node:item l'.widget);
        cur := List.mapi !cur ~f:(fun i x -> if i = index then l' else x)
```
Note `old_node` is captured *before* `patch` writes `live.node <- node`, which it does at the end — reading it afterwards would hand the hook two identical nodes and every parent-held setting would silently stop updating. That is the single most likely bug in this task; the live test's `measure_overlay` flip is what catches it.

`destroy` and `disarm` recurse with `Children.iter`, which handles `Slots` for free.

- [ ] **Step 7: `src/widgets/w_box.ml`** — adapt to the new record: `insert = (fun parent ~after ~node:_ child -> ...)`, `updated = Widget_impl.no_list_update`.

- [ ] **Step 8: `vtree/attr.ml(i)` — `measure_overlay`**

```ocaml
(* Name.t: *) | Measure_overlay
(* t:      *) | Measure_overlay of bool

(** For a child of [Node.overlay]'s [~overlays]: whether the overlay's own size request
    takes this child into account. [false] -- the useful case -- lets an overlay be laid
    out at the size of its *main* child and merely painted over, which is how an image is
    kept from dictating the size of what contains it.

    Inert on any other widget: it is a setting the *overlay* holds about this child, not a
    property of the child, so no other container reads it. *)
let measure_overlay b = Measure_overlay b
```
`is_event` → `false`. `Attr_apply.set`/`unset` → inert arms, with the comment already drafted in Task 2 covering the whole "container-placement attrs" group.

- [ ] **Step 9: `vtree/kind.ml(i)` / `node.ml(i)`**

```ocaml
type center_box_props = { shrink_center_last : bool } [@@deriving sexp_of, equal]

type paned_props =
  { orientation : Orientation.t
  ; position : int option
  ; wide_handle : bool
  ; resize_start : bool
  ; resize_end : bool
  ; shrink_start : bool
  ; shrink_end : bool
  }
[@@deriving sexp_of, equal]

type overlay_props = unit [@@deriving sexp_of, equal]
```
```ocaml
let center_box ?key ?attrs ?(shrink_center_last = true) ?start ?center ?end_ () =
  make
    ?key
    ?attrs
    (Center_box { shrink_center_last })
    (Slots [ "start", Single start; "center", Single center; "end", Single end_ ])
;;

let paned
  ?key ?attrs ?position ?(wide_handle = false) ?(resize_start = true) ?(resize_end = true)
  ?(shrink_start = false) ?(shrink_end = false) ~orientation ~start ~end_
  =
  make
    ?key
    ?attrs
    (Paned
       { orientation; position; wide_handle; resize_start; resize_end; shrink_start; shrink_end })
    (Slots [ "start", Single (Some start); "end", Single (Some end_) ])
;;

let overlay ?key ?attrs ?(overlays = []) child =
  make ?key ?attrs (Overlay ()) (Slots [ "child", Single (Some child); "overlays", List overlays ])
;;
```
`Paned` takes both halves as required arguments: a paned with one side is a box, and GTK renders an empty half as dead space with a draggable handle into nothing. `position = None` leaves GTK's own (the halves' natural split); `Some n` pins it, and — unlike the toggles — it is *not* controlled, because the user drags the handle continuously and pinning it every frame makes it undraggable. Document that on the constructor, and expose `Attr.on_position_changed` so an app that wants to own the position can store what the user chose. (Deferred: `on_position_changed` is not in M1's attr list; if it is wanted, it is three lines beside `on_expanded_changed`. Note it in the mli as available on request rather than shipping an untested attr.)

- [ ] **Step 10: `src/widgets/w_center_box.ml`**

```ocaml
open! Core
open Bonsai_gtk_vtree
open Gtk_import

let impl : Widget_impl.t =
  { name = "CenterBox"
  ; create =
      (fun (kind : Kind.t) ->
        match kind with
        | Center_box p ->
          let b = W.Center_box.new_ () in
          if not p.shrink_center_last then W.Center_box.set_shrink_center_last b false;
          (b :> Widget.t)
        | k -> Widget_impl.wrong_kind "CenterBox" k)
  ; update =
      (fun w ~(old : Kind.t) (new_ : Kind.t) ->
        match old, new_ with
        | Center_box old, Center_box new_ ->
          if not (Bool.equal old.shrink_center_last new_.shrink_center_last)
          then W.Center_box.set_shrink_center_last (cast w) new_.shrink_center_last
        | _, k -> Widget_impl.wrong_kind "CenterBox" k)
  ; signals = []
  ; children =
      Widget_impl.Slots
        [ "start", Slot_single { set = (fun w c -> W.Center_box.set_start_widget (cast w) c) }
        ; "center", Slot_single { set = (fun w c -> W.Center_box.set_center_widget (cast w) c) }
        ; "end", Slot_single { set = (fun w c -> W.Center_box.set_end_widget (cast w) c) }
        ]
  }
;;
```

- [ ] **Step 11: `src/widgets/w_paned.ml`**

```ocaml
open! Core
open Bonsai_gtk_vtree
open Gtk_import

let orientation : Orientation.t -> Gtk_enums.orientation = function
  | Horizontal -> `HORIZONTAL
  | Vertical -> `VERTICAL
;;

let impl : Widget_impl.t =
  { name = "Paned"
  ; create =
      (fun (kind : Kind.t) ->
        match kind with
        | Paned p ->
          let pane = W.Paned.new_ (orientation p.orientation) in
          let w = (pane :> Widget.t) in
          Widget_impl.batch w (fun () ->
            Option.iter p.position ~f:(W.Paned.set_position pane);
            W.Paned.set_wide_handle pane p.wide_handle;
            W.Paned.set_resize_start_child pane p.resize_start;
            W.Paned.set_resize_end_child pane p.resize_end;
            W.Paned.set_shrink_start_child pane p.shrink_start;
            W.Paned.set_shrink_end_child pane p.shrink_end);
          w
        | k -> Widget_impl.wrong_kind "Paned" k)
  ; update =
      (fun w ~(old : Kind.t) (new_ : Kind.t) ->
        match old, new_ with
        | Paned old, Paned new_ ->
          let pane : W.Paned.t = cast w in
          Widget_impl.batch w (fun () ->
            if not (Orientation.equal old.orientation new_.orientation)
            then
              W.Orientable.set_orientation
                (W.Orientable.from_gobject w)
                (orientation new_.orientation);
            (* Not controlled: the user drags the handle continuously, and re-asserting the
               position every frame would make it undraggable. Only an actual change in
               what the model asks for moves it. *)
            if not (Option.equal Int.equal old.position new_.position)
            then Option.iter new_.position ~f:(W.Paned.set_position pane);
            if not (Bool.equal old.wide_handle new_.wide_handle)
            then W.Paned.set_wide_handle pane new_.wide_handle;
            if not (Bool.equal old.resize_start new_.resize_start)
            then W.Paned.set_resize_start_child pane new_.resize_start;
            if not (Bool.equal old.resize_end new_.resize_end)
            then W.Paned.set_resize_end_child pane new_.resize_end;
            if not (Bool.equal old.shrink_start new_.shrink_start)
            then W.Paned.set_shrink_start_child pane new_.shrink_start;
            if not (Bool.equal old.shrink_end new_.shrink_end)
            then W.Paned.set_shrink_end_child pane new_.shrink_end)
        | _, k -> Widget_impl.wrong_kind "Paned" k)
  ; signals = []
  ; children =
      Widget_impl.Slots
        [ "start", Slot_single { set = (fun w c -> W.Paned.set_start_child (cast w) c) }
        ; "end", Slot_single { set = (fun w c -> W.Paned.set_end_child (cast w) c) }
        ]
  }
;;
```

- [ ] **Step 12: `src/widgets/w_overlay.ml`**

```ocaml
open! Core
open Bonsai_gtk_vtree
open Gtk_import

(* The overlay holds this about each of its overlay children; it is not a property of the
   child, so it rides on the child node's attrs and is read here (see [Attr.measure_overlay]).
   Default [true] is GTK's. *)
let measure (node : Node.t) =
  match Attrs.find node.attrs Measure_overlay with
  | Some (Measure_overlay b) -> b
  | _ -> true
;;

let impl : Widget_impl.t =
  { name = "Overlay"
  ; create =
      (fun (kind : Kind.t) ->
        match kind with
        | Overlay () -> (W.Overlay.new_ () :> Widget.t)
        | k -> Widget_impl.wrong_kind "Overlay" k)
  ; update =
      (fun _w ~(old : Kind.t) (new_ : Kind.t) ->
        match old, new_ with
        | Overlay (), Overlay () -> ()
        | _, k -> Widget_impl.wrong_kind "Overlay" k)
  ; signals = []
  ; children =
      Widget_impl.Slots
        [ "child", Slot_single { set = (fun w c -> W.Overlay.set_child (cast w) c) }
        ; ( "overlays"
          , Slot_list
              { insert =
                  (fun parent ~after:_ ~node child ->
                    (* GTK has no "insert an overlay at a position": overlays stack in the
                       order added, and [after] is unusable. Order among overlays is
                       therefore *not* reconciled -- a reorder in the node list leaves the
                       painting order alone. Keys still preserve identity, which is what
                       matters; a stack whose paint order must change is a case for
                       separate keys per layer. *)
                    W.Overlay.add_overlay (cast parent) child;
                    W.Overlay.set_measure_overlay (cast parent) child (measure node))
              ; move = (fun _parent ~child:_ ~after:_ -> ())
              ; remove = (fun parent child -> W.Overlay.remove_overlay (cast parent) child)
              ; updated =
                  (fun parent ~old ~node child ->
                    if not (Bool.equal (measure old) (measure node))
                    then W.Overlay.set_measure_overlay (cast parent) child (measure node))
              } )
        ]
  }
;;
```

- [ ] **Step 13: Registry, `Live_tree`**

`Live_tree` cannot read `measure-overlay` off a child without the parent, so print it from the parent's side: in `dump`, when `ty` is `"GtkOverlay"`, print `(unmeasured (<index> ...))` listing the indices of children the overlay does not measure. Concretely:
```ocaml
     | "GtkOverlay" ->
       let o = cast w in
       (match
          List.filter_mapi (widget_children w) ~f:(fun i c ->
            if W.Overlay.get_measure_overlay o c then None else Some i)
        with
        | [] -> []
        | idxs -> [ [%sexp `unmeasured (idxs : int list)] ])
```

- [ ] **Step 14: Run, read, promote, `./scripts/ci.sh`.**
Read for: the center box's middle slot disappearing without disturbing start/end; the overlay's second dump listing the badge as unmeasured *and* holding the new `extra` overlay; the paned printing both halves. Then commit.

- [ ] **Step 15: Commit**

```bash
dune fmt 2>/dev/null; git add vtree src test
GIT_EDITOR=true git commit -F - <<'MSG'
Named child slots; CenterBox, Paned, Overlay

Children.t gains [Slots], the spec's fourth shape: children addressed by role,
each slot carrying its own Single/List shape and patched by the same code.

List child ops now see the child node, and gain an [updated] hook, because
some per-child settings live on the parent -- an overlay's measure flag, and
Task 9's grid cells and stack page titles. They ride on the child node's attrs
and the parent impl reads them.

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01Sg3Ci8U8kUKR8C3PL1pNSs
MSG
```

---

### Task 9: Placement-by-attr — Grid, Stack, StackSwitcher, StackSidebar

The last four widgets, and the two remaining pieces of container machinery: children placed by *coordinates* rather than by order (`Grid`), and widgets that refer to *another widget in the tree* (`StackSwitcher`/`StackSidebar` need the `GtkStack` they drive). Task 8's node-aware list ops carry the first; the second needs a name registry and a post-patch fixup pass.

**Files:**
- Create: `vtree/grid_cell.ml`, `vtree/stack_transition.ml`, `src/widgets/w_grid.ml`, `src/widgets/w_stack.ml`, `src/widgets/w_stack_switcher.ml`, `src/widgets/w_stack_sidebar.ml`
- Modify: `vtree/attr.ml(i)`, `vtree/kind.ml(i)`, `vtree/node.ml(i)`, `vtree/bonsai_gtk_vtree.ml`, `src/patcher.ml`, `src/patcher.mli`, `src/driver.ml`, `src/widgets/registry.ml`, `src/live_tree.ml`, `src/bonsai_gtk.ml(i)`, `test/test_widgets.ml`, `test/live/live_patcher.ml`, `test/live/live_controls.ml`, `test/live/live_containers.ml`

**Interfaces:**
- Produces:
  ```ocaml
  (* vtree *)
  module Grid_cell : sig
    type t = { column : int; row : int; width : int; height : int }
    [@@deriving sexp_of, equal, compare]
  end
  module Stack_transition : sig
    type t = None_ | Crossfade | Slide_right | Slide_left | Slide_up | Slide_down
           | Slide_left_right | Slide_up_down | Over_up | Over_down | Over_left | Over_right
           | Under_up | Under_down | Under_left | Under_right | Rotate_left | Rotate_right
  end

  (* Attr *)
  val grid_cell : column:int -> row:int -> ?width:int -> ?height:int -> unit -> t
  val page_title : string -> t
  val on_visible_child_changed : (string -> unit Ui_effect.t) -> t

  (* Node *)
  val grid
    :  ?key:Key.t -> ?attrs:Attr.t list -> ?row_spacing:int -> ?column_spacing:int
    -> ?row_homogeneous:bool -> ?column_homogeneous:bool -> t list -> t
  val stack
    :  ?key:Key.t -> ?attrs:Attr.t list -> ?transition:Stack_transition.t
    -> ?transition_duration:int -> ?hhomogeneous:bool -> ?vhomogeneous:bool
    -> name:string -> visible_child:string -> t list -> t
  val stack_switcher : ?key:Key.t -> ?attrs:Attr.t list -> stack:string -> unit -> t
  val stack_sidebar : ?key:Key.t -> ?attrs:Attr.t list -> stack:string -> unit -> t

  (* Patcher *)
  val create_ctx
    :  signals:Signals.ctx
    -> on_window_created:(Widget.t -> unit)
    -> ctx
  val run_fixups : ctx -> unit
  ```

Three design points, each with a live-test consequence:

1. **Grid children are placed by an attr.** `gtk_grid_attach(grid, child, col, row, w, h)` is a call on the *parent*, so the coordinates ride on the child node's attrs exactly as `measure_overlay` does, and are read by the grid's `insert`/`updated` ops. A grid child with no `Attr.grid_cell` is `Invalid_argument` naming the path — there is no sensible default, and silently stacking every child at (0,0) is the worst possible failure. Spec §7's note ("`Grid` children are re-`attach`ed on any coordinate change") is what `updated` implements: GTK has no "move an attached child", so a cell change is `remove` then `attach`.
2. **Grid's `move` is a no-op.** Order in the node list carries no meaning for a grid; the cell does. Reordering the children of a `Node.grid` without changing their cells must not touch GTK, and the reconciler's `Move` ops are therefore dropped. `Key.t` still governs identity, which is what preserves a cell's widget (and its focus, and its entry text) across a re-render.
3. **StackSwitcher/StackSidebar name their stack.** They need a live `GtkStack` handle, which the vtree cannot hold. `Node.stack ~name:"nav"` registers its widget under that name in the patcher's ctx, and the switcher/sidebar enqueue a *fixup* — a closure run after the whole tree has been mounted or patched — that resolves the name and calls `set_stack`. Resolving after the pass, rather than during it, makes the order of the two nodes in the tree irrelevant (a switcher above its stack is the common layout). An unresolvable name is `Invalid_argument` at fixup time, naming both the switcher's path and the name it wanted. See Open Question 3.

`Stack`'s own list ops need one more accommodation: GTK offers no way to insert a page at a position or reorder pages, so `insert` ignores `after` (pages land in add order) and `move` is a no-op, like `Overlay`'s. Page *order* only affects the button order in a `StackSwitcher`; page *identity* and *selection* are by name, which is the node's `Key.t` and is fully reconciled. Document it on `Node.stack`.

- [ ] **Step 1: Failing headless test** (`test/test_widgets.ml`)

```ocaml
let%expect_test "grid children carry their cells; stack pages carry their keys" =
  print_s
    [%sexp
      (Node.grid
         ~row_spacing:6
         ~column_spacing:12
         [ Node.label ~attrs:[ Attr.grid_cell ~column:0 ~row:0 () ] "Name"
         ; Node.entry ~attrs:[ Attr.grid_cell ~column:1 ~row:0 () ] ~text:"" ()
         ; Node.label
             ~attrs:[ Attr.grid_cell ~column:0 ~row:1 ~width:2 () ]
             "spans both columns"
         ]
       : Node.t)];
  [%expect {| |}];
  print_s
    [%sexp
      (Node.box
         ~orientation:Vertical
         [ Node.stack_switcher ~stack:"nav" ()
         ; Node.stack
             ~name:"nav"
             ~visible_child:"library"
             [ Node.label ~key:"library" ~attrs:[ Attr.page_title "Library" ] "L"
             ; Node.label ~key:"practice" ~attrs:[ Attr.page_title "Practice" ] "P"
             ]
         ]
       : Node.t)];
  [%expect {| |}]
;;
```

- [ ] **Step 2: Failing live test** — append to `test/live/live_containers.ml`

Two claims only a live test can make: a re-celled child is re-attached rather than duplicated, and a switcher finds a stack declared *after* it.

```ocaml
  (* Grid: the third child moves cell without changing key, so it must be detached and
     re-attached at the new coordinates -- and be the same GObject afterwards. *)
  let grid_view ~span =
    Node.window
      ~title:"grid"
      (Node.grid
         ~row_spacing:6
         ~column_spacing:12
         [ Node.label ~key:"k" ~attrs:[ Attr.grid_cell ~column:0 ~row:0 () ] "Name"
         ; Node.label ~key:"v" ~attrs:[ Attr.grid_cell ~column:1 ~row:0 () ] "Bach"
         ; Node.label
             ~key:"note"
             ~attrs:
               [ (if span
                  then Attr.grid_cell ~column:0 ~row:1 ~width:2 ()
                  else Attr.grid_cell ~column:0 ~row:2 ())
               ]
             "note"
         ])
  in
  let live = P.mount ctx ~path:"root" ~is_root:true (grid_view ~span:false) in
  print_s (Live_tree.dump live.widget);
  let note_before =
    match live.children with
    | Single (Some g) ->
      (match g.children with
       | List cs -> (List.nth_exn cs 2).widget
       | _ -> assert false)
    | _ -> assert false
  in
  let live = P.patch ctx ~path:"root" ~is_root:true live (grid_view ~span:true) in
  print_s (Live_tree.dump live.widget);
  (match live.children with
   | Single (Some g) ->
     (match g.children with
      | List cs ->
        printf
          "same widget after re-attach: %b\n"
          (Gobject.same note_before (List.nth_exn cs 2).widget)
      | _ -> assert false)
   | _ -> assert false);
  (* A grid child with no cell is a bug worth failing on. *)
  (match
     P.mount
       ctx
       ~path:"root"
       ~is_root:true
       (Node.window ~title:"g" (Node.grid [ Node.label "cell-less" ]))
   with
   | (_ : P.live) -> print_endline "BUG: grid child without a cell accepted"
   | exception Invalid_argument msg -> printf "rejected: %s\n" msg);
  P.destroy ctx live;
  (* Stack: the switcher is declared *above* the stack it drives, so it can only be wired
     up after the whole tree exists -- which is what [run_fixups] is for. *)
  let stack_view ~visible ~pages =
    Node.window
      ~title:"stack"
      (Node.box
         ~orientation:Vertical
         [ Node.stack_switcher ~stack:"nav" ()
         ; Node.stack_sidebar ~stack:"nav" ()
         ; Node.stack
             ~name:"nav"
             ~transition:None_
             ~visible_child:visible
             ~attrs:[ Attr.on_visible_child_changed (fun _ -> Ui_effect.Ignore) ]
             (List.map pages ~f:(fun (key, title) ->
                Node.label ~key ~attrs:[ Attr.page_title title ] key))
         ])
  in
  let live =
    P.mount
      ctx
      ~path:"root"
      ~is_root:true
      (stack_view ~visible:"library" ~pages:[ "library", "Library"; "practice", "Practice" ])
  in
  P.run_fixups ctx;
  print_s (Live_tree.dump live.widget);
  let live =
    P.patch
      ctx
      ~path:"root"
      ~is_root:true
      live
      (stack_view
         ~visible:"practice"
         ~pages:[ "library", "Library!"; "practice", "Practice"; "setlists", "Setlists" ])
  in
  P.run_fixups ctx;
  print_s (Live_tree.dump live.widget);
  (* An unresolvable stack name names both ends of the mistake. *)
  (match
     let live =
       P.mount
         ctx
         ~path:"root"
         ~is_root:true
         (Node.window ~title:"s" (Node.stack_switcher ~stack:"nope" ()))
     in
     P.run_fixups ctx;
     live
   with
   | (_ : P.live) -> print_endline "BUG: unresolvable stack name accepted"
   | exception Invalid_argument msg -> printf "rejected: %s\n" msg);
  P.destroy ctx live
```

- [ ] **Step 3: Run to verify failure.**

- [ ] **Step 4: The two vtree modules**

```ocaml
(* vtree/grid_cell.ml *)
open! Core

(** Where a child sits in a [Node.grid], and how many cells it covers. Columns and rows are
    zero-based and may be sparse -- a grid is not a table, and nothing has to fill row 1
    for something to sit in row 2. *)
type t =
  { column : int
  ; row : int
  ; width : int
  ; height : int
  }
[@@deriving sexp_of, equal, compare]

(* vtree/stack_transition.ml *)
open! Core

type t =
  | None_
  | Crossfade
  | Slide_right
  | Slide_left
  | Slide_up
  | Slide_down
  | Slide_left_right
  | Slide_up_down
  | Over_up
  | Over_down
  | Over_left
  | Over_right
  | Under_up
  | Under_down
  | Under_left
  | Under_right
  | Rotate_left
  | Rotate_right
[@@deriving sexp_of, equal, compare]
```
GTK also has `OVER_UP_DOWN`, `OVER_DOWN_UP`, `OVER_LEFT_RIGHT`, `OVER_RIGHT_LEFT` and `ROTATE_LEFT_RIGHT`; leave them out and say so in the mli — they are the "pick a direction from the child order" variants, and the child order of a `Node.stack` is explicitly not meaningful (point 3 above), so offering them would promise something the widget does not deliver.

- [ ] **Step 5: `vtree/attr.ml(i)` — three attrs**

```ocaml
(* Name.t: *) | Grid_cell | Page_title | On_visible_child_changed
(* t: *)
  | Grid_cell of Grid_cell.t
  | Page_title of string
  | On_visible_child_changed of string Handler.t
```
`equal`: `Grid_cell.equal`, `String.equal`, `Handler.equal`. `is_event`: only the last is `true`. `Attr_apply.set`/`unset`: all three inert (they are read by the parent impl, in the "container-placement attrs" group).

```ocaml
(** Where this child sits in its parent [Node.grid]. Required on every grid child --
    there is no default, and defaulting to (0,0) would stack the whole grid in one cell
    and look like a layout bug rather than a missing attribute.

    [width]/[height] (default 1) are the number of columns and rows spanned. Inert on any
    widget whose parent is not a grid. *)
let grid_cell ~column ~row ?(width = 1) ?(height = 1) () =
  Grid_cell { Grid_cell.column; row; width; height }
;;

(** The label a [Node.stack]'s switcher or sidebar shows for this page. The page's *name*
    -- what [~visible_child] selects it by -- is the node's [Key.t], not this. Inert
    outside a stack. *)
let page_title s = Page_title s

(** Fires when a [Node.stack]'s visible page changes, carrying the new page's name (the
    child's [Key.t]). Programmatic changes -- what [~visible_child] does -- are dropped by
    the reentrancy guard, as always; this is the user clicking a switcher button. *)
let on_visible_child_changed f = On_visible_child_changed f
```

- [ ] **Step 6: `vtree/kind.ml(i)` / `node.ml(i)`**

```ocaml
type grid_props =
  { row_spacing : int
  ; column_spacing : int
  ; row_homogeneous : bool
  ; column_homogeneous : bool
  }
[@@deriving sexp_of, equal]

type stack_props =
  { name : string
  ; visible_child : string
  ; transition : Stack_transition.t
  ; transition_duration : int
  ; hhomogeneous : bool
  ; vhomogeneous : bool
  }
[@@deriving sexp_of, equal]

type stack_ref_props = { stack : string } [@@deriving sexp_of, equal]

(* ... in Kind.t: *)
  | Grid of grid_props
  | Stack of stack_props
  | Stack_switcher of stack_ref_props
  | Stack_sidebar of stack_ref_props
```
`Kind.name`: `"Grid" | "Stack" | "StackSwitcher" | "StackSidebar"`. GTK defaults: spacings `0`, homogeneous flags `false`, `transition = None_`, `transition_duration = 200`, `hhomogeneous = true`, `vhomogeneous = true`.

```ocaml
let grid
  ?key ?attrs ?(row_spacing = 0) ?(column_spacing = 0) ?(row_homogeneous = false)
  ?(column_homogeneous = false) children
  =
  make
    ?key
    ?attrs
    (Grid { row_spacing; column_spacing; row_homogeneous; column_homogeneous })
    (List children)
;;

let stack
  ?key ?attrs ?(transition = Stack_transition.None_) ?(transition_duration = 200)
  ?(hhomogeneous = true) ?(vhomogeneous = true) ~name ~visible_child children
  =
  make
    ?key
    ?attrs
    (Stack
       { name; visible_child; transition; transition_duration; hhomogeneous; vhomogeneous })
    (List children)
;;

let stack_switcher ?key ?attrs ~stack () = make ?key ?attrs (Stack_switcher { stack }) No_children
let stack_sidebar ?key ?attrs ~stack () = make ?key ?attrs (Stack_sidebar { stack }) No_children
```

`Node.stack`'s doc comment carries the three rules a caller must know:
```
    Every child needs a [~key]: it is the GTK page name, it is what [~visible_child]
    selects by, and it is what preserves a page's widgets across a re-render. A child
    without one is [Invalid_argument] at mount.

    Child *order* is not reconciled: GTK offers no way to insert a page at a position or
    to reorder pages, so pages land in the order they are first added and reordering the
    list does nothing. Order only affects the button order in a [stack_switcher]; identity
    and selection are entirely by key.

    [~name] is how a [stack_switcher] or [stack_sidebar] elsewhere in the tree finds this
    stack. Two stacks with the same name in one tree is [Invalid_argument].
```

- [ ] **Step 7: `src/patcher.ml(i)` — the name registry and fixups**

`ctx` gains two mutable fields, and a constructor so callers stop writing the record literal (there are four such literals in `test/live/` and one in `driver.ml`; a constructor means the next field costs nothing):

```ocaml
type ctx =
  { signals : Signals.ctx
  ; on_window_created : Widget.t -> unit
  ; (* Live [GtkStack]s by their [Node.stack ~name]. A [stack_switcher] cannot hold a
       widget -- the vtree has no way to name one -- so it names a stack and is wired up
       after the pass that mounts them both. *)
    stacks : (string, Widget.t) Hashtbl.t
  ; (* Work deferred to the end of a mount/patch pass, so that a node may refer to another
       node regardless of which of them the walk reaches first. *)
    fixups : (unit -> unit) Queue.t
  }

let create_ctx ~signals ~on_window_created =
  { signals
  ; on_window_created
  ; stacks = Hashtbl.create (module String)
  ; fixups = Queue.create ()
  }
;;

let register_stack ctx ~path ~name widget =
  match Hashtbl.add ctx.stacks ~key:name ~data:widget with
  | `Ok -> ()
  | `Duplicate ->
    invalid_argf "%s: two Node.stacks are named %S in one tree" path name ()
;;

let resolve_stack ctx ~path ~name : Widget.t =
  match Hashtbl.find ctx.stacks name with
  | Some w -> w
  | None ->
    invalid_argf
      "%s: no Node.stack is named %S (a stack_switcher/stack_sidebar must name a stack \
       that exists somewhere in the same tree)"
      path
      name
      ()
;;

(* Runs everything deferred by the pass just finished, then empties the queue. Called by
   [Driver.frame] inside the patch guard; live tests call it by hand. Fixups may not
   enqueue further fixups -- nothing needs to, and a queue that feeds itself is a hang. *)
let run_fixups ctx =
  Queue.iter ctx.fixups ~f:(fun f -> f ());
  Queue.clear ctx.fixups
;;
```

In `mount`, after the widget exists and its children are attached, beside the existing `on_window_created` dispatch:

```ocaml
  (match node.kind with
   | Window _ -> ctx.on_window_created widget
   | Stack { name; _ } -> register_stack ctx ~path ~name widget
   | Stack_switcher { stack } ->
     Queue.enqueue ctx.fixups (fun () ->
       W.Stack_switcher.set_stack (cast widget) (Some (cast (resolve_stack ctx ~path ~name:stack))))
   | Stack_sidebar { stack } ->
     Queue.enqueue ctx.fixups (fun () ->
       W.Stack_sidebar.set_stack (cast widget) (cast (resolve_stack ctx ~path ~name:stack)))
   | _ -> ());
```
`Patcher` may not call `W.*` for a specific widget directly if that muddles the layering — if it does, put the two setter closures behind `W_stack_switcher.attach : Widget.t -> Widget.t -> unit` and `W_stack_sidebar.attach` and call those. Prefer that; the patcher should stay widget-agnostic.

In `patch`, the same three cases, because a stack may have been re-created (kind change) or renamed, and a switcher may now name a different stack:
```ocaml
    (match node.kind with
     | Stack { name; _ } ->
       (* Re-register under the (possibly new) name; the old entry is dropped by
          [destroy], which runs before this only in the kind-changed path. *)
       Hashtbl.set ctx.stacks ~key:name ~data:live.widget
     | Stack_switcher { stack } | Stack_sidebar { stack } ->
       Queue.enqueue ctx.fixups (fun () -> ... same as mount ...)
     | _ -> ());
```
Re-enqueueing on every patch, rather than only when the name changed, is deliberate: it is one hashtable lookup and one setter per switcher per frame, and it is the only thing that keeps a switcher pointing at a stack that was itself replaced.

In `destroy`, drop the registration:
```ocaml
  | Stack { name; _ } -> Hashtbl.remove ctx.stacks name
```
placed with the existing `Window`/`Native` arms.

`Driver.frame` drains the queue inside the guard, immediately after the mount/patch:
```ocaml
    Scheduler.with_patch_guard t.scheduler (fun () ->
      t.root <- Some (match t.root with ... );
      Patcher.run_fixups t.ctx);
```
and `Driver.create` builds its ctx with `Patcher.create_ctx`.

- [ ] **Step 8: `src/widgets/w_grid.ml`**

```ocaml
open! Core
open Bonsai_gtk_vtree
open Gtk_import

(* A grid child's coordinates are an argument to a call on the *grid*, not a property of
   the child, so they ride on the child node's attrs and are read here (spec §7). There is
   no default: a grid child with no cell would stack at (0,0) with every other, which
   looks like a layout bug rather than the missing attribute it is. *)
let cell (node : Node.t) =
  match Attrs.find node.attrs Grid_cell with
  | Some (Grid_cell c) -> c
  | _ ->
    invalid_argf
      "Grid child has no Attr.grid_cell (every child of a Node.grid needs one)"
      ()
;;

let attach parent (node : Node.t) child =
  let c = cell node in
  W.Grid.attach (cast parent) child c.column c.row c.width c.height
;;

let impl : Widget_impl.t =
  { name = "Grid"
  ; create =
      (fun (kind : Kind.t) ->
        match kind with
        | Grid p ->
          let g = W.Grid.new_ () in
          let w = (g :> Widget.t) in
          Widget_impl.batch w (fun () ->
            W.Grid.set_row_spacing g p.row_spacing;
            W.Grid.set_column_spacing g p.column_spacing;
            W.Grid.set_row_homogeneous g p.row_homogeneous;
            W.Grid.set_column_homogeneous g p.column_homogeneous);
          w
        | k -> Widget_impl.wrong_kind "Grid" k)
  ; update =
      (fun w ~(old : Kind.t) (new_ : Kind.t) ->
        match old, new_ with
        | Grid old, Grid new_ ->
          let g : W.Grid.t = cast w in
          Widget_impl.batch w (fun () ->
            if old.row_spacing <> new_.row_spacing
            then W.Grid.set_row_spacing g new_.row_spacing;
            if old.column_spacing <> new_.column_spacing
            then W.Grid.set_column_spacing g new_.column_spacing;
            if not (Bool.equal old.row_homogeneous new_.row_homogeneous)
            then W.Grid.set_row_homogeneous g new_.row_homogeneous;
            if not (Bool.equal old.column_homogeneous new_.column_homogeneous)
            then W.Grid.set_column_homogeneous g new_.column_homogeneous)
        | _, k -> Widget_impl.wrong_kind "Grid" k)
  ; signals = []
  ; children =
      Widget_impl.List
        { insert = (fun parent ~after:_ ~node child -> attach parent node child)
        ; (* Order in the node list means nothing to a grid; the cell is the placement, so
             a reorder that keeps the cells must not touch GTK. *)
          move = (fun _parent ~child:_ ~after:_ -> ())
        ; remove = (fun parent child -> W.Grid.remove (cast parent) child)
        ; updated =
            (fun parent ~old ~node child ->
              (* GTK has no "move an attached child": a coordinate change is a detach and
                 a re-attach of the same widget (spec §7). *)
              if not (Grid_cell.equal (cell old) (cell node))
              then (
                W.Grid.remove (cast parent) child;
                attach parent node child))
        }
  }
;;
```
The `cell` error message has no path in it; `Patcher` is what knows the path. Either thread it (make `cell` take `~path`, and have the ops take it from... they cannot) or catch and re-raise in the patcher. Simplest correct answer: have `insert`/`updated` raise as above, and let `Patcher.mount_list`/`patch_list` wrap each op call in a `try ... with Invalid_argument msg -> invalid_argf "%s: %s" path msg ()`. Add that wrapper once in the patcher's list helpers; it improves every container's errors, not just the grid's.

- [ ] **Step 9: `src/widgets/w_stack.ml`**

```ocaml
open! Core
open Bonsai_gtk_vtree
open Gtk_import

let transition : Stack_transition.t -> Gtk_enums.stacktransitiontype = function
  | None_ -> `NONE
  | Crossfade -> `CROSSFADE
  | Slide_right -> `SLIDE_RIGHT
  | Slide_left -> `SLIDE_LEFT
  | Slide_up -> `SLIDE_UP
  | Slide_down -> `SLIDE_DOWN
  | Slide_left_right -> `SLIDE_LEFT_RIGHT
  | Slide_up_down -> `SLIDE_UP_DOWN
  | Over_up -> `OVER_UP
  | Over_down -> `OVER_DOWN
  | Over_left -> `OVER_LEFT
  | Over_right -> `OVER_RIGHT
  | Under_up -> `UNDER_UP
  | Under_down -> `UNDER_DOWN
  | Under_left -> `UNDER_LEFT
  | Under_right -> `UNDER_RIGHT
  | Rotate_left -> `ROTATE_LEFT
  | Rotate_right -> `ROTATE_RIGHT
;;

(* A page's name is the child's key: it is what [~visible_child] selects by and what the
   reconciler matches on, so making them the same value is what keeps the two agreeing. *)
let page_name (node : Node.t) =
  match node.key with
  | Some key -> key
  | None ->
    invalid_arg "Stack child has no ~key (a stack page's key is its GTK page name)"
;;

let page_title (node : Node.t) =
  match Attrs.find node.attrs Page_title with
  | Some (Page_title t) -> Some t
  | _ -> None
;;

(* ocgtk exposes no [on_notify_visible_child_name]; the detailed name goes through the
   generic marshaller (spec §6.4). *)
let visible_child_changed : Signals.spec =
  { attr = Attr.Name.On_visible_child_changed
  ; connect = Signals.notify ~prop:"visible-child-name"
  ; fire =
      (fun w (attr : Attr.t) ->
        match attr with
        | On_visible_child_changed handler ->
          (* [None] only while the stack is empty, which the user cannot click their way
             into; nothing to report then. *)
          Option.map (W.Stack.get_visible_child_name (cast w)) ~f:handler
        | _ -> None)
  }
;;

let impl : Widget_impl.t =
  { name = "Stack"
  ; create =
      (fun (kind : Kind.t) ->
        match kind with
        | Stack p ->
          let s = W.Stack.new_ () in
          let w = (s :> Widget.t) in
          Widget_impl.batch w (fun () ->
            W.Stack.set_transition_type s (transition p.transition);
            W.Stack.set_transition_duration s p.transition_duration;
            W.Stack.set_hhomogeneous s p.hhomogeneous;
            W.Stack.set_vhomogeneous s p.vhomogeneous);
          (* [visible_child] is deliberately not set here: the pages do not exist yet
             (the patcher attaches children after [create]), and naming a page that is not
             there is a GTK warning. The first [update] after mount cannot run either, so
             the selection is applied by the child ops -- see [insert] below. *)
          w
        | k -> Widget_impl.wrong_kind "Stack" k)
  ; update =
      (fun w ~(old : Kind.t) (new_ : Kind.t) ->
        match old, new_ with
        | Stack old, Stack new_ ->
          let s : W.Stack.t = cast w in
          Widget_impl.batch w (fun () ->
            if not (Stack_transition.equal old.transition new_.transition)
            then W.Stack.set_transition_type s (transition new_.transition);
            if old.transition_duration <> new_.transition_duration
            then W.Stack.set_transition_duration s new_.transition_duration;
            if not (Bool.equal old.hhomogeneous new_.hhomogeneous)
            then W.Stack.set_hhomogeneous s new_.hhomogeneous;
            if not (Bool.equal old.vhomogeneous new_.vhomogeneous)
            then W.Stack.set_vhomogeneous s new_.vhomogeneous;
            (* Controlled, against the widget: the user may have clicked a switcher
               button since the last render, and a model that did not follow must put the
               selection back. Skipped when the named page does not exist yet -- children
               are patched after this, and the [insert] below re-asserts it. *)
            if (not
                  (Option.equal
                     String.equal
                     (W.Stack.get_visible_child_name s)
                     (Some new_.visible_child)))
               && Option.is_some (W.Stack.get_child_by_name s new_.visible_child)
            then W.Stack.set_visible_child_name s new_.visible_child)
        | _, k -> Widget_impl.wrong_kind "Stack" k)
  ; signals = [ visible_child_changed ]
  ; children =
      Widget_impl.List
        { insert =
            (fun parent ~after:_ ~node child ->
              (* GTK has no positional insert for pages; they land in add order, which only
                 affects switcher button order. *)
              let name = page_name node in
              (match page_title node with
               | Some title ->
                 ignore (W.Stack.add_titled (cast parent) child (Some name) title : W.Stack_page.t)
               | None ->
                 ignore (W.Stack.add_named (cast parent) child (Some name) : W.Stack_page.t));
              (* The first page GTK receives becomes visible whether or not it is the one
                 the model asked for, and [update] could not assert the selection before
                 the pages existed. Re-assert it here, now that this page does. *)
              ())
        ; move = (fun _parent ~child:_ ~after:_ -> ())
        ; remove = (fun parent child -> W.Stack.remove (cast parent) child)
        ; updated =
            (fun parent ~old ~node child ->
              if not (Option.equal String.equal (page_title old) (page_title node))
              then (
                let page = W.Stack.get_page (cast parent) child in
                W.Stack_page.set_title page (Option.value (page_title node) ~default:"")))
        }
  }
;;
```

The empty `()` and its comment in `insert` mark a real ordering problem that has to be solved rather than commented: `create` cannot select a page (none exist), and `update` runs *before* children are patched, so on the very first frame the stack shows whichever page was added first. Fix it in the patcher rather than in the impl, with the mechanism Step 7 already added — have the `Stack` arm of `mount`/`patch` enqueue a fixup that asserts the selection after the pass:

```ocaml
   | Stack { name; visible_child; _ } ->
     register_stack ctx ~path ~name widget;
     Queue.enqueue ctx.fixups (fun () -> W_stack.select ctx_widget ~visible_child)
```
with, in `w_stack.ml`:
```ocaml
(* Applied as a post-pass fixup: the pages exist only after the children have been
   patched, and naming a page GTK does not have yet is a warning and a no-op. *)
let select (w : Widget.t) ~visible_child =
  let s : W.Stack.t = cast w in
  if (not (Option.equal String.equal (W.Stack.get_visible_child_name s) (Some visible_child)))
     && Option.is_some (W.Stack.get_child_by_name s visible_child)
  then W.Stack.set_visible_child_name s visible_child
;;
```
and the same enqueue in `patch`'s `Stack` arm. Then drop the selection block from `impl.update` entirely — one place decides it, after the tree is complete. Do it that way; the version inside `update` above is left in the plan only to show why it does not work.

- [ ] **Step 10: `src/widgets/w_stack_switcher.ml` and `w_stack_sidebar.ml`**

```ocaml
(* w_stack_switcher.ml *)
open! Core
open Bonsai_gtk_vtree
open Gtk_import

(* Called from the patcher's fixup pass, once the named stack is known to exist. *)
let attach (switcher : Widget.t) (stack : Widget.t) =
  W.Stack_switcher.set_stack (cast switcher) (Some (cast stack))
;;

let impl : Widget_impl.t =
  { name = "StackSwitcher"
  ; create =
      (fun (kind : Kind.t) ->
        match kind with
        (* The stack is wired up by a fixup after the pass, not here: the stack may be
           mounted after this switcher, and often is (a switcher above the stack it
           drives is the ordinary layout). *)
        | Stack_switcher _ -> (W.Stack_switcher.new_ () :> Widget.t)
        | k -> Widget_impl.wrong_kind "StackSwitcher" k)
  ; update =
      (fun _w ~(old : Kind.t) (new_ : Kind.t) ->
        match old, new_ with
        (* Re-pointing at a different stack is also a fixup; nothing to do inline. *)
        | Stack_switcher _, Stack_switcher _ -> ()
        | _, k -> Widget_impl.wrong_kind "StackSwitcher" k)
  ; signals = []
  ; children = Widget_impl.No_children
  }
;;
```
`w_stack_sidebar.ml` is the same file with `Stack_sidebar`, `W.Stack_sidebar.new_`, and `attach` calling `W.Stack_sidebar.set_stack (cast sidebar) (cast stack)` — note the non-optional argument, unlike the switcher's.

- [ ] **Step 11: Registry, `Live_tree`, ctx literals**

Registry: four arms. `Live_tree`:
```ocaml
     | "GtkGrid" ->
       int_prop "row-spacing" (W.Grid.get_row_spacing (cast w)) ~default:0
       @ int_prop "column-spacing" (W.Grid.get_column_spacing (cast w)) ~default:0
       @ (* A grid child's cell is held by the grid, so print it from here. *)
       (match
          List.map (widget_children w) ~f:(fun c ->
            let col, row, width, height = W.Grid.query_child (cast w) c in
            [%sexp (col : int), (row : int), (width : int), (height : int)])
        with
        | [] -> []
        | cells -> [ Sexp.List (Atom "cells" :: cells) ])
     | "GtkStack" ->
       [ [%sexp `visible (W.Stack.get_visible_child_name (cast w) : string option)] ]
```
Print the grid's cells in `widget_children` order so the list lines up with the children printed underneath it. A `GtkStack`'s pages are not `widget_children` in the page sense — the child widgets themselves are what `get_first_child` walks — so the existing recursion is right as it stands.

Replace the four `P.ctx` record literals in `test/live/*.ml` with `P.create_ctx ~signals:{...} ~on_window_created:(...)`.

- [ ] **Step 12: Run, read, promote, `./scripts/ci.sh`.**
Read for: `same widget after re-attach: true` (the claim that a cell change moves rather than rebuilds), the grid's `cells` list changing from `((0 0 1 1) (1 0 1 1) (0 2 1 1))` to `(... (0 1 2 1))`, both rejection messages naming their path, the stack's `visible` following `~visible_child` on both frames — including the first, which is what the fixup exists for — and the switcher gaining a button when the third page appears.

- [ ] **Step 13: Commit**

```bash
dune fmt 2>/dev/null; git add vtree src test
GIT_EDITOR=true git commit -F - <<'MSG'
Grid, Stack, StackSwitcher, StackSidebar

Grid children are placed by Attr.grid_cell -- a call on the parent, so it
rides on the child node and is read by the grid's child ops -- and a cell
change is a detach and re-attach of the same widget, since GTK has no move.
A grid child without a cell is Invalid_argument rather than a silent pile at
(0,0).

StackSwitcher and StackSidebar name their stack, and are wired up by a fixup
pass that runs after the whole tree exists, so a switcher may be declared
above the stack it drives. The stack's own page selection is applied there
too: at [create] time it has no pages to select.

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01Sg3Ci8U8kUKR8C3PL1pNSs
MSG
```

---

### Task 10: The gallery example, and a headless sweep over every M1 widget

Spec §10 lists `examples/` as growing per milestone (`counter, todo, gallery`). The gallery is not decoration: it is the only place every M1 widget is instantiated together, under the real runtime, with a real GTK theme — which catches the class of mistake no unit test does (a widget that mounts fine and lays out at zero height, a container whose child never becomes visible, a signal that fires at 60 Hz because a prop is written unconditionally).

**Files:**
- Create: `examples/gallery.ml`, `test/test_gallery.ml`
- Modify: `examples/dune`, `scripts/ci.sh`

- [ ] **Step 1: `examples/dune`**

```lisp
(executables
 (names counter gallery)
 (libraries core bonsai bonsai_gtk)
 (preprocess
  (pps ppx_jane bonsai.ppx_bonsai)))
```

- [ ] **Step 2: `examples/gallery.ml`**

Structure it as a `Node.stack` with a `Node.stack_switcher` above it — which exercises the two widgets that are hardest to get right — and one page per task group. Every control is wired to real state, because an unwired control proves nothing: the point is that clicking, typing and dragging move a model and the model moves the widgets back.

```ocaml
open! Core
open Bonsai_gtk
open Bonsai.Let_syntax

(* Page 1: the toggle family and the entries, all controlled by one record of state. *)
let controls (graph @ local) =
  let toggled, set_toggled = Bonsai.state false graph in
  let checked, set_checked = Bonsai.state true graph in
  let switched, set_switched = Bonsai.state false graph in
  let text, set_text = Bonsai.state "" graph in
  let search, set_search = Bonsai.state "" graph in
  let%arr toggled and set_toggled and checked and set_checked and switched and set_switched
  and text and set_text and search and set_search in
  Node.grid
    ~row_spacing:8
    ~column_spacing:12
    ~attrs:[ Attr.margin 12 ]
    [ Node.label ~attrs:[ Attr.grid_cell ~column:0 ~row:0 (); Attr.xalign 0. ] "Toggle"
    ; Node.toggle_button
        ~attrs:[ Attr.grid_cell ~column:1 ~row:0 (); Attr.on_toggled set_toggled ]
        ~label:(if toggled then "on" else "off")
        ~active:toggled
        ()
    ; Node.label ~attrs:[ Attr.grid_cell ~column:0 ~row:1 (); Attr.xalign 0. ] "Check"
    ; Node.check_button
        ~attrs:[ Attr.grid_cell ~column:1 ~row:1 (); Attr.on_toggled set_checked ]
        ~label:"agree"
        ~active:checked
        ()
    ; Node.label ~attrs:[ Attr.grid_cell ~column:0 ~row:2 (); Attr.xalign 0. ] "Switch"
    ; Node.switch
        ~attrs:
          [ Attr.grid_cell ~column:1 ~row:2 ()
          ; Attr.halign Start
          ; Attr.on_toggled set_switched
          ]
        ~active:switched
        ()
    ; Node.label ~attrs:[ Attr.grid_cell ~column:0 ~row:3 (); Attr.xalign 0. ] "Entry"
    ; Node.entry
        ~attrs:[ Attr.grid_cell ~column:1 ~row:3 (); Attr.hexpand true; Attr.on_changed set_text ]
        ~placeholder:"type here"
        ~text
        ()
    ; Node.label ~attrs:[ Attr.grid_cell ~column:0 ~row:4 (); Attr.xalign 0. ] "Password"
    ; Node.password_entry
        ~attrs:[ Attr.grid_cell ~column:1 ~row:4 (); Attr.hexpand true ]
        ~placeholder:"passphrase"
        ~text:""
        ()
    ; Node.label ~attrs:[ Attr.grid_cell ~column:0 ~row:5 (); Attr.xalign 0. ] "Search"
    ; Node.search_entry
        ~attrs:
          [ Attr.grid_cell ~column:1 ~row:5 ()
          ; Attr.hexpand true
          ; Attr.on_search_changed set_search
          ]
        ~text:search
        ()
    ; Node.label
        ~attrs:[ Attr.grid_cell ~column:0 ~row:6 ~width:2 (); Attr.xalign 0.; Attr.ellipsize End ]
        (sprintf "text=%S search=%S" text search)
    ]
;;

(* Page 2: numbers and feedback, where one value drives four widgets. *)
let numbers (graph @ local) =
  let value, set_value = Bonsai.state 40. graph in
  let%arr value and set_value in
  Node.box
    ~orientation:Vertical
    ~spacing:8
    ~attrs:[ Attr.margin 12 ]
    [ Node.scale
        ~attrs:[ Attr.on_value_changed set_value; Attr.hexpand true ]
        ~orientation:Horizontal
        ~min:0.
        ~max:100.
        ~value
        ()
    ; Node.spin_button
        ~attrs:[ Attr.on_value_changed set_value; Attr.halign Start ]
        ~min:0.
        ~max:100.
        ~value
        ()
    ; Node.progress_bar ~fraction:(value /. 100.) ~show_text:true ()
    ; Node.separator ~orientation:Horizontal
    ; Node.box
        ~orientation:Horizontal
        ~spacing:8
        [ Node.spinner ~spinning:Float.(value > 50.) ()
        ; Node.label (sprintf "spinning above 50 (value = %.0f)" value)
        ]
    ]
;;

(* Page 3: the containers, including the overlay-over-a-spacer trick that caps a
   picture's allocated size. *)
let layout (graph @ local) =
  let expanded, set_expanded = Bonsai.state false graph in
  let revealed, set_revealed = Bonsai.state true graph in
  let%arr expanded and set_expanded and revealed and set_revealed in
  Node.paned
    ~orientation:Horizontal
    ~position:220
    ~start:
      (Node.scrolled_window
         ~hpolicy:Never
         ~vpolicy:Automatic
         (Node.box
            ~orientation:Vertical
            ~spacing:8
            ~attrs:[ Attr.margin 12 ]
            [ Node.frame ~label:"Frame" (Node.label ~attrs:[ Attr.margin 8 ] "framed")
            ; Node.expander
                ~attrs:[ Attr.on_expanded_changed set_expanded ]
                ~label:"Expander"
                ~expanded
                (Node.label ~attrs:[ Attr.margin 8 ] "detail")
            ; Node.button
                ~attrs:[ Attr.on_clicked (set_revealed (not revealed)) ]
                ~label:(if revealed then "Hide" else "Show")
                ()
            ; Node.revealer
                ~transition:Slide_down
                ~reveal:revealed
                (Node.label ~attrs:[ Attr.margin 8 ] "revealed")
            ]))
    ~end_:
      (Node.center_box
         ~attrs:[ Attr.margin 12 ]
         ~start:(Node.label "start")
         ~center:
           (Node.overlay
              ~overlays:
                [ Node.image
                    ~attrs:[ Attr.measure_overlay false; Attr.halign Center; Attr.valign Center ]
                    ~pixel_size:48
                    (Icon_name "image-x-generic-symbolic")
                ]
              (Node.box
                 ~orientation:Vertical
                 ~attrs:[ Attr.width_request 150; Attr.height_request 194 ]
                 []))
         ~end_:(Node.label "end")
         ())
;;

let app (graph @ local) =
  let page, set_page = Bonsai.state "controls" graph in
  let controls = controls graph in
  let numbers = numbers graph in
  let layout = layout graph in
  let%arr page and set_page and controls and numbers and layout in
  Node.window
    ~title:"bonsai_gtk gallery"
    ~default_size:(900, 560)
    (Node.box
       ~orientation:Vertical
       [ Node.stack_switcher
           ~attrs:[ Attr.halign Center; Attr.margin 8 ]
           ~stack:"gallery"
           ()
       ; Node.stack
           ~name:"gallery"
           ~visible_child:page
           ~transition:Crossfade
           ~attrs:[ Attr.vexpand true; Attr.on_visible_child_changed set_page ]
           [ Node.box
               ~key:"controls"
               ~attrs:[ Attr.page_title "Controls" ]
               ~orientation:Vertical
               [ controls ]
           ; Node.box
               ~key:"numbers"
               ~attrs:[ Attr.page_title "Numbers" ]
               ~orientation:Vertical
               [ numbers ]
           ; Node.box
               ~key:"layout"
               ~attrs:[ Attr.page_title "Layout" ]
               ~orientation:Vertical
               [ layout ]
           ]
       ])
;;

let () = exit (Bonsai_gtk.start ~application_id:"org.bonsai_gtk.examples.gallery" app)
```

The `stack_switcher` above the `stack` is deliberate: it is the layout that only works because the fixup pass resolves names after the whole tree exists (Task 9), so the example doubles as that feature's demonstration.

- [ ] **Step 3: `test/test_gallery.ml` — the headless sweep**

The gallery links ocgtk, so it cannot be expect-tested. Reproduce the *view* half of it — the part that is pure `bonsai_gtk.vtree` — as a component in `test/` and snapshot it, which is both a coverage check that every M1 constructor still builds a legal node and a worked example of the rule the README states ("keep your view functions in a vtree-only library and they are testable").

```ocaml
open! Core
open Bonsai_gtk_vtree
open Bonsai.Let_syntax

(* Every M1 node constructor, once, in one tree. Its value is coverage: a constructor
   whose defaults change, or a children shape that stops being legal, shows up here as a
   diff rather than as a runtime failure in somebody's app. *)
let every_widget (graph @ local) =
  let n, set_n = Bonsai.state 0 graph in
  let%arr n and set_n in
  Node.window
    ~title:"every widget"
    (Node.stack
       ~name:"all"
       ~visible_child:"a"
       [ Node.box
           ~key:"a"
           ~attrs:[ Attr.page_title "A" ]
           ~orientation:Vertical
           [ Node.label ~xalign:0. ~ellipsize:End ~max_width_chars:14 "label"
           ; Node.button ~attrs:[ Attr.on_clicked (set_n (n + 1)) ] ~label:"button" ()
           ; Node.button ~icon_name:"list-add-symbolic" ~has_frame:false ()
           ; Node.toggle_button ~label:"toggle" ~active:(n % 2 = 0) ()
           ; Node.check_button ~label:"check" ~active:false ()
           ; Node.switch ~active:true ()
           ; Node.entry ~placeholder:"entry" ~text:"" ()
           ; Node.password_entry ~text:"" ()
           ; Node.search_entry ~text:"" ()
           ; Node.spin_button ~min:0. ~max:10. ~value:(Float.of_int n) ()
           ; Node.scale ~orientation:Horizontal ~min:0. ~max:10. ~value:0. ()
           ; Node.progress_bar ~fraction:0.5 ()
           ; Node.spinner ~spinning:true ()
           ; Node.image (Icon_name "list-add-symbolic")
           ; Node.picture Empty
           ; Node.separator ~orientation:Horizontal
           ]
       ; Node.box
           ~key:"b"
           ~attrs:[ Attr.page_title "B" ]
           ~orientation:Vertical
           [ Node.scrolled_window (Node.label "scrolled")
           ; Node.frame ~label:"frame" (Node.label "framed")
           ; Node.expander ~label:"expander" ~expanded:false (Node.label "detail")
           ; Node.revealer ~reveal:true (Node.label "revealed")
           ; Node.grid [ Node.label ~attrs:[ Attr.grid_cell ~column:0 ~row:0 () ] "cell" ]
           ; Node.center_box ~start:(Node.label "s") ~end_:(Node.label "e") ()
           ; Node.paned ~orientation:Vertical ~start:(Node.label "t") ~end_:(Node.label "b")
           ; Node.overlay ~overlays:[ Node.label "over" ] (Node.label "under")
           ; Node.stack_switcher ~stack:"all" ()
           ; Node.stack_sidebar ~stack:"all" ()
           ]
       ])
;;

let%expect_test "every M1 widget builds a legal node" =
  let handle = Bonsai_gtk_test.create every_widget in
  Bonsai_gtk_test.Handle.show handle;
  [%expect {| |}]
;;
```

- [ ] **Step 4: `scripts/ci.sh`** — smoke the gallery beside the counter

Factor the existing smoke block into a loop, so a third example costs one word:

```bash
echo "== example smoke"
for ex in counter gallery; do
  set +e
  xvfb-run -a timeout -k 2 3 dune exec "examples/$ex.exe"
  code=$?
  set -e
  # 124 is timeout's "still running when time ran out", which is what a GUI that
  # came up and stayed up looks like. Anything else means it fell over.
  [ "$code" = 124 ] || { echo "$ex example exited with $code"; exit 1; }
done
```
Also add `@examples/fmt` — it is already in the `dune build @...` line; confirm rather than assume.

- [ ] **Step 5: Run it for real, and look at it**

```
dune build @test/runtest && dune promote
xvfb-run -a timeout -k 2 5 dune exec examples/gallery.exe
```
Under Xvfb there is nothing to see, so also run it on a real display if one is available (`dune exec examples/gallery.exe`) and click through all three pages. Things this catches that nothing else does: a page that renders at zero height (a missing `vexpand`), a switcher with no buttons (the fixup never ran), a scale that jumps back to its old value when released (the controlled rule applied against the node rather than the widget), a spinner that never spins, an overlay that sizes to its image rather than its spacer.

Fix what it shows *in the widget impl*, and add a live-test line for whatever was wrong — a bug the gallery can find and the suite cannot is a hole in the suite.

- [ ] **Step 6: `./scripts/ci.sh`, then commit**

```bash
dune fmt 2>/dev/null; git add examples test scripts
GIT_EDITOR=true git commit -F - <<'MSG'
Gallery example, and a headless sweep over every M1 widget

The gallery is the only place every M1 widget is instantiated together under
the real runtime and a real theme, which is what catches the mistakes unit
tests do not: zero-height pages, controls that fight the user, a switcher
whose stack never got wired up.

test/test_gallery.ml mirrors its view half in a vtree-only component, so the
constructors are covered headlessly too -- and it is the worked example of the
rule the README states about keeping view functions ocgtk-free.

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01Sg3Ci8U8kUKR8C3PL1pNSs
MSG
```

---

### Task 11: README's widget list, and rewriting `docs/m1-backlog.md`

**Files:**
- Modify: `README.md`, `docs/m1-backlog.md`

- [ ] **Step 1: README**

Four edits, no rewrite:

1. **Status line.** Replace "Status: pre-alpha (M0) — four widgets (`Label`, `Button`, `Box`, `Window`), the `Native` escape hatch, the runtime loop, and headless testing." with a sentence naming M1's coverage and pointing at the widget table below.
2. **A widget table**, new section after "Libraries", because "which widgets are there" is the first question anyone has:

```markdown
## Widgets

| | |
|---|---|
| **Display** | `Label` (wrap, xalign, ellipsize, max-width-chars, markup), `Image`, `Picture`, `Separator`, `ProgressBar`, `Spinner` |
| **Controls** | `Button` (label / icon / arbitrary child / frameless), `ToggleButton`, `CheckButton`, `Switch`, `SpinButton`, `Scale` |
| **Text** | `Entry`, `PasswordEntry`, `SearchEntry` — controlled: the widget is written only when the model disagrees with what it currently shows, so echoing what the user typed never moves the caret |
| **Layout** | `Box`, `Grid` (`Attr.grid_cell`), `CenterBox`, `Paned`, `Overlay` (`Attr.measure_overlay`), `Frame`, `Expander`, `Revealer`, `ScrolledWindow` |
| **Navigation** | `Stack` + `StackSwitcher` + `StackSidebar` (pages keyed by `Key.t`, switchers name their stack) |
| **Window** | `Window` (one per app until M3) |
| **Escape hatch** | `Node.native` for anything else, plus `Native.Picture` for a `GdkPaintable` source |

Shared attributes on every widget: `css_class`, `margin_*`, `halign`/`valign`,
`hexpand`/`vexpand`, `width_request`/`height_request`, `sensitive`, `visible`, `tooltip`,
`opacity`, `focusable`/`can_focus`, `widget_name`, `cursor_name`, `test_id`. Dropping an
attribute restores the value that widget was created with, not a global default.

See §7 of the design doc for what M2 (lists & text) and M3 (chrome & popups) add.
```
3. **Headless testing section**: mention the four actions (`Click`, `Toggle`, `Set_text`, `Set_value`, `Activate`) rather than just `Click`.
4. **Limitations**: drop "M0 covers four widgets"; keep single-window, no custom Cairo drawing, no `ListView`/`ColumnView`/`GridView`, and add the M1-specific ones this milestone chose deliberately, so nobody rediscovers them as bugs:
   - `Stack` and `Overlay` children are not reordered (GTK has no API for it); keys still preserve identity.
   - No radio groups (`CheckButton.set_group`): model the choice in Bonsai state.
   - No `Scale` marks, no `ProgressBar.pulse`, no `Entry` icons, no `SearchEntry.set_key_capture_widget`, no `Frame.set_label_widget` — each is a `Node.native` case and each is named in its widget's doc comment.
   - `Paned`'s position is not controlled (it would fight the drag handle).

- [ ] **Step 2: `docs/m1-backlog.md`** — rewrite as the *M2* backlog

The file's job is "what the last milestone's reviews deferred", so rewrite it rather than appending. Retitle it `# Backlog carried out of M1` (keep the filename; a rename churns links for nothing, and note the retitle in the commit message). Sections:

- **Done in M1** (a short list, so the next reader knows these are closed): child ops by predecessor widget; `Driver.frame`/`schedule_event` guarding `broken`; the reentrancy guard's live tests (`live_signals.ml` for the trampoline, `live_controls.ml` for the end-to-end programmatic-write case); per-widget unset defaults via the creation-time snapshot; `vtree/children.mli`.
- **Do first in M2**: whatever the M1 task reviews defer. Seed it now with what this plan already knows it is leaving:
  - `Attr.t` is still a public variant, so every M2 attr is a breaking change for an exhaustive match downstream — see Open Question 1; if the ruling was "defer", this is where it lives.
  - `Overlay` and `Stack` `move` ops are no-ops; if M2's `Notebook` (which *does* have `reorder_child`) shares the list machinery, revisit whether a no-op `move` should instead be an explicit `Unordered` marker on `list_ops` so the reconciler can skip emitting `Move` at all.
  - `Signals.spec.fire` reads state back off the widget; a signal with a genuinely un-readable payload (`ListBox::row-activated`'s row, key events' keyval) needs the existential-event version of `spec`. M2's `ListBox` is the forcing case.
- **API shape decisions before they become breaking**: carry forward whichever of M0's four are still open (`Expert.Driver.root_widget` vs `Node.windows`; `start ?flags`), drop the two M1 closed (per-kind unset defaults), and add: `Bonsai_gtk_test.Action.t` is a public variant with the same exhaustive-match exposure as `Attr.t`.
- **Tests worth adding**: carry forward the GC/lifetime test (remove a keyed child, `Gc.full_major`, assert finalization) and the after-display spin regression, both still unwritten; add "a `Live_tree.dump` of a tree containing every M1 widget, as one golden file" if the per-task live tests turn out to leave gaps.
- **Plumbing / hygiene**: carry forward the surviving M0 items (`scripts/setup-switch.sh`'s dirty-checkout check, the gir_gen flake shell, node paths frozen at mount, `Signals.slots`' dead `ref`, `Driver.t.last` duplicating `root.node`, exception-safety of `mount`, the hard-coded 16 ms cadence, `request_frame` not cancelling a pending `request_frame_soon`), and strike the ones M1 closed.
- **ocgtk fork**: carry the section over unchanged unless the PR status moved during M1.

- [ ] **Step 3: Commit**

```bash
git add README.md docs/m1-backlog.md
GIT_EDITOR=true git commit -F - <<'MSG'
README's widget catalogue; roll the backlog forward to M1's leftovers

docs/m1-backlog.md keeps its filename but is now "carried out of M1": M0's
three "do first" items are done, and the file lists what M1's reviews defer
instead.

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01Sg3Ci8U8kUKR8C3PL1pNSs
MSG
```

---

### Task 12: `scripts/ci.sh` end to end, from a clean tree

The gate has been run per task; this runs it once against the finished milestone, from a state that matches what a fresh clone would produce, and fixes whatever only shows up there.

**Files:**
- Modify: whatever the run turns up (expected: nothing, or `.opam` regeneration and formatting)

- [ ] **Step 1: Clean and rebuild**

```bash
cd ~/src/bonsai_gtk
git status --porcelain          # expect empty; commit or stash anything here first
dune clean
nix develop -c ./scripts/ci.sh
```
Expect `all green`. A clean build is not the same build: `dune clean` removes promoted expect output and stale `.opam` files, so this is where a test that only passed because of a leftover artifact fails.

- [ ] **Step 2: Work through whatever fails, in this order**

- **`nix build .#ocgtk`** — unrelated to M1; if it fails, the pin or nixpkgs moved. Do not "fix" it by moving the pin: report it and stop, per `docs/upstream/README.md`'s process.
- **format** — `dune fmt`, then re-check that the root `dune`/`dune-project` pass `dune format-dune-file` (the loop in `ci.sh` covers them; the `@fmt` aliases do not).
- **`git diff --exit-code -- '*.opam'`** — `dune-project` gained no new dependency in M1 except through `src/dune`, which does not regenerate `.opam`; if this fails, someone added a package dependency without recording it. Add it to `dune-project`'s `(depends ...)` (`ocgtk` already covers `ocgtk.pango`, since dune's public names all belong to the one `ocgtk` opam package — verify that rather than assuming) and commit the regenerated file.
- **`@test/runtest`** — a diff here after a clean build means a promoted expect block depended on ordering that a fresh build changes. Read the diff; do not promote it blind.
- **live tests** — the most likely genuine failure, because they depend on the GTK theme Xvfb gives them. Symptoms and causes: an extra internal child in a dump (a GTK version difference — accept and promote, noting it in the commit), a `css` list gaining a class (same), a timing-dependent value like `child-revealed` (a transition that should have been `None_` in the test — fix the test, not the expectation).
- **example smoke** — a non-124 exit means the example crashed. Run it under `xvfb-run -a dune exec` directly to see the message; a `Gtk-CRITICAL` on stderr with exit 124 is *not* a failure of this gate but is worth fixing anyway, so read the output rather than only the status.

- [ ] **Step 3: Verify the milestone against the spec, by hand**

Open `docs/superpowers/specs/2026-08-28-bonsai-gtk-design.md` §7's M1 line and check off each name against `src/widgets/`:

```bash
ls src/widgets/
grep -c '| [A-Z]' src/widgets/registry.ml   # one arm per kind, plus Native
```
Every name in the spec's M1 line must have a file and a registry arm. `Node.native` is M0's, extended in Task 6 with `Native.Picture`.

- [ ] **Step 4: Final commit (only if Step 2 changed anything)**

```bash
dune fmt 2>/dev/null; git add -A
GIT_EDITOR=true git commit -F - <<'MSG'
M1: clean-tree CI pass

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01Sg3Ci8U8kUKR8C3PL1pNSs
MSG
```

---

## Spec coverage (M1 slice)

| Spec section | Task |
|---|---|
| §5.1 constructors (`label`, `button`, `entry`, ...) | 2, 3, 4, 5, 6, 7, 8, 9 |
| §5.2 `Attr.t` (opacity, focusable, can_focus, name, cursor, event attrs) | 2, 3, 4, 5, 7, 8, 9 |
| §5.3 children shapes — `None`, `Single`, `List`, `Slots` | 1 (`List` placement), 8 (`Slots`), 9 (grid/stack list ops) |
| §5.4 keys | 1, 8, 9 (`Stack` pages keyed; `Grid`/`Overlay` identity by key) |
| §6.2 patcher algorithm | 1, 8, 9 |
| §6.4 signals, handler slots, `notify::` family | 3 (mechanism), 4, 5, 7, 9 |
| §6.5 controlled text widgets | 4 (text), 3 and 5 and 7 and 9 (the same rule for `active`, `value`, `expanded`, `reveal`, `visible_child`) |
| §6.6 `Node.native` | 6 (`Native.Picture`, the first shipped one) |
| §7 M1 catalogue | 3 (Button, ToggleButton, CheckButton, Switch), 4 (Entry, PasswordEntry, SearchEntry), 5 (SpinButton, Scale, ProgressBar, Spinner), 6 (Image, Picture, Separator, `Node.native`), 7 (ScrolledWindow, Frame, Expander, Revealer), 8 (CenterBox, Paned, Overlay), 9 (Grid, Stack, StackSwitcher, StackSidebar) |
| §7 `freeze_notify`/`thaw_notify` batches | 3 (`Widget_impl.batch`), used by every impl after |
| §7 grid children re-attached on coordinate change | 9 |
| §7 stack pages keyed by name | 9 |
| §8 effects | none — M3 |
| §9 testing (pure/headless/live) | every task; 10 sweeps |
| §11 error handling | 3 (`require_specs`), 8 (slot mismatch), 9 (missing cell, missing key, unresolvable stack name), 1 (broken driver) |
| M0 backlog "Do first in M1" | 1 (all three) |

## Open questions

The controller rules on these before execution; each has a recommendation and the task that would change if the ruling goes the other way.

1. **Seal `Attr.t` (and `Bonsai_gtk_test.Action.t`) in the public surface?** M0's backlog flags this: `Attr.t` is a public variant, so each of M1's ~14 new constructors breaks any downstream exhaustive match. Sealing properly means making `Attr.t` abstract in `vtree/attr.mli` and exposing the variant as `Attr.Private.repr : t -> repr`, which `Attr_apply`, `Signals` and `Bonsai_gtk_test` (all outside the module) would go through. That is a real refactor touching four files plus every task below it. **Recommendation: seal `Attr.t` in Task 2, before the constructors land, and leave `Attr.Name.t` and `Action.t` concrete** — `Name.t` is only reachable through `Attrs.op`, which is `Private`-adjacent already, and `Action.t` is written by test authors as a literal (`do_actions handle [ Click "inc" ]`), where a constructor is the ergonomic form and a breaking change is a test-file edit, not a downstream outage. If the ruling is "defer", move the item to the M2 backlog in Task 11 and drop the sealing step from Task 2.

2. **Is `Scale`'s (and `SpinButton`'s) value controlled like text?** The spec names only the text widgets in §6.5. Applying the same rule to a slider means a drag the model declines snaps back, which is correct-but-jarring; not applying it means the widget and the model can diverge silently, which is worse and is the exact class of bug §6.5 exists to prevent. **Recommendation: yes, controlled, on the identical rule (compare against the widget's current value, not the previous node's)** — as written in Task 5, with the caveat documented on `Node.scale`. Note the deliberate exception already in the plan: `Paned`'s position is *not* controlled, because it is dragged continuously and re-asserting it every frame makes the handle immovable; that asymmetry is worth the controller's explicit blessing.

3. **How do `StackSwitcher`/`StackSidebar` refer to their `Stack`?** They need a live widget handle, which the vtree cannot hold. The options are (a) a string name registered by `Node.stack ~name` and resolved by a post-patch fixup pass — Task 9 as written; (b) making the switcher a container whose child is the stack, which is wrong (they must be siblings); (c) leaving both to `Node.native`, which drops two widgets from the M1 line. **Recommendation: (a).** It costs one hashtable and one queue on `Patcher.ctx`, it is order-independent (a switcher above its stack is the ordinary layout), and the same mechanism is what M3's `Node.windows` and `Attr.mnemonic_widget` will need. The cost is a second kind of name alongside `Key.t`; if that is judged too much, the fallback is (c) plus a backlog item.

4. **Should `Overlay`'s and `Stack`'s `move` be a silent no-op, or should `list_ops` say "unordered" out loud?** GTK offers no reorder for either. Task 8 and 9 make `move` a no-op and document it. A cleaner shape is a flag on `list_ops` that tells the patcher not to emit `Move` at all, so the reconciler's ops and GTK's reality never disagree even in principle. **Recommendation: no-op for M1, with the doc comment, and revisit in M2 when `Notebook` (which does have `reorder_child`) shares the machinery** — the flag is easy to add later and hard to design well against one example.

5. **Does `Attr.on_changed` fire on `SearchEntry` as well as `on_search_changed`?** Task 4 connects both: `changed` (immediate, via `GtkEditable`) and `search-changed` (debounced). An app that attaches both gets two events per keystroke burst. **Recommendation: expose both, as written, and document the choice on `Node.search_entry`** ("`on_changed` when the model owns the text, `on_search_changed` when a store is being queried") — the alternative, suppressing `changed` on search entries, would make `SearchEntry` the one text widget whose controlled-text story differs from the others'.

6. **`Live_tree.dump` verbosity.** GTK's internal children (a `GtkEntry`'s `GtkText`, a `GtkScrolledWindow`'s two scrollbars, a `GtkButton`'s label) appear in every dump and will make the expected files long. **Recommendation: keep them.** They are what GTK actually holds, which is the whole point of a live dump, and their presence is itself a check that a child landed inside a viewport rather than beside it. If a file becomes genuinely unreadable, add a type-keyed suppression list to `Live_tree` and document it in the mli — do not trim expected files by hand.

## Rulings on the open questions (controller, 2026-08-29)

1. Seal `Attr.t` in Task 2 via `Attr.Private.repr`; `Attr.Name.t` and `Bonsai_gtk_test.Action.t` stay concrete.
2. `Scale`/`SpinButton` values are controlled exactly like text (compare against the widget's live value, not the previous node); `Paned`'s position is the documented exception.
3. `StackSwitcher`/`StackSidebar` find their `Stack` by a string name registered with `Node.stack ~name`, resolved by an order-independent post-patch fixup pass.
4. `Overlay`/`Stack` `move` is a silent no-op with a doc comment in M1; revisit when `Notebook` (M2) shares the list machinery.
5. `SearchEntry` exposes both `Attr.on_changed` and `Attr.on_search_changed`, documented on `Node.search_entry`.
6. `Live_tree.dump` keeps GTK's internal children.
