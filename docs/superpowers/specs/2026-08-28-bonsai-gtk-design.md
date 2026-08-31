# bonsai_gtk — design

Date: 2026-08-28
Status: approved design, pre-implementation

## 1. Goal

`bonsai_gtk` is a general-purpose OCaml library for building GTK4 desktop
applications with [Bonsai](https://github.com/janestreet/bonsai), in the same
spirit as `bonsai_web` (browser) and `bonsai_term` (terminal). An app is a pure
function `local_ Bonsai.graph -> Node.t Bonsai.t`; the library owns the GTK
main loop, turns GTK signals into Bonsai events, and keeps a live GTK widget
tree in sync with the declarative `Node.t` the app computes.

Non-goals for this design: Async integration, `ListView`/`ColumnView` with
`GListModel` factories, GTK accessibility APIs beyond what falls out of the
widgets, Windows/macOS support (GTK4 on Linux only, via ocgtk).

## 2. Constraints and dependencies

| Item | Decision |
|---|---|
| Toolchain | OxCaml (`ocaml-variants.5.2.0+ox`), same switch family as stavekeeper. Bonsai `v0.18~preview.130.106+341` (Cont API, `local_ graph`). Not buildable on stock OCaml / nixpkgs `bonsai` 0.17. |
| GTK binding | [`ocgtk`](https://github.com/chris-armstrong/ocgtk) 0.1~preview2, pinned to a commit on the `dlobraico/ocgtk` fork's `bonsai-gtk` branch (upstream `40ab0b6` + fixes being upstreamed, see §2.1). GTK 4. Dune libraries used: `ocgtk.gtk`, `ocgtk.gio`, `ocgtk.gdk`, `ocgtk.common` (unwrapped: `Gobject`, `Glib`). |
| Event loop | GLib main loop only. No Async. `GtkApplication` is the entry point. |
| Bonsai libs | `bonsai`, `bonsai.driver`, `virtual_dom.ui_effect` (for `Ui_effect`), `bonsai_test` (for the test handle). |
| Nix | `flake.nix` provides the dev shell (opam, pkg-config, GTK4 stack, xvfb-run) and a `packages.ocgtk` derivation. `ocamlformat` comes from the opam switch, not the shell, so it is the version the project pins rather than nixpkgs'. The library itself is built by dune in the opam switch, not by Nix, because Bonsai v0.18 is OxCaml-only. |

### 2.1 ocgtk fork and upstreaming

stavekeeper's `vendor/ocgtk` diverges from upstream `40ab0b6` by fourteen
in-place edits (documented in stavekeeper `docs/dev-notes.md`): a GC
heap-corruption fix in the signal-closure marshaller (a naked `GValue *` in a
GC-scanned record), missing `g_object_ref_sink` in `ml_g_value_get_object`
(which backs every object-typed signal parameter), spurious `ref_sink` on
transfer-full constructors (a leak class), a floating-`GVariant` use-after-free
in the Gio action marshaller, GBytes external-memory accounting, and the
`Glib_bytes.of_bigstring` addition. The closure fix alone is load-bearing for
a library whose whole job is connecting signals, so an unpatched upstream pin
is not acceptable.

Decision: **fork upstream to `dlobraico/ocgtk` and upstream the fixes.**

- The fork's `main` tracks upstream. A long-lived branch `bonsai-gtk` is based
  on `40ab0b6` and carries the fixes as clean, themed commits, re-derived by
  diffing stavekeeper's vendored tree against `40ab0b6` (stavekeeper's own
  history interleaves them with app changes). Themes: (1) closure-marshal GC
  safety, (2) GObject ref-count corrections in generated stubs + the gir_gen
  ownership fixes behind them, (3) floating-GVariant fix, (4) `Glib_bytes`
  additions. Each theme becomes one upstream PR against `chris-armstrong/ocgtk`
  `main`, with ocgtk's own regression tests (`tests/test_closure_with_gc.ml`
  etc.) included.
- `bonsai_gtk` pins the fork: `scripts/setup-switch.sh` clones the fork to
  `.ocgtk-src`, checks out the pinned commit, and *path*-pins it
  (`opam pin add ocgtk ./.ocgtk-src/ocgtk`) rather than using a git pin — opam
  rsyncs the directory, which keeps the switch reproducible from a checkout the
  script controls and makes local fork edits testable without a push. The script
  asserts the checkout is at the pinned commit, and reinstalls ocgtk when the
  commit moves (opam does not notice a directory pin's contents changing on its
  own). `flake.nix` `packages.ocgtk` uses
  `fetchFromGitHub { owner = "dlobraico"; rev = <commit>; }`.
  One commit hash, recorded in `ocgtk-pin.json` and read by both.
- As PRs merge upstream, the branch rebases toward upstream `main` and the
  pin moves; when everything is merged the pin returns to upstream.
- The fork is also where any C stubs bonsai_gtk turns out to need
  (`add_provider_for_display`, `DrawingArea.set_draw_func`, tick callbacks)
  are developed and proposed upstream, rather than as private stubs inside
  bonsai_gtk.

### 2.2 ocgtk facts the design relies on

- Two API layers: Layer 1 modules of externals over a contravariant phantom
  pointer (`Gtk.Wrappers.Button.set_label : Button.t -> string -> unit`,
  `(b : Button.t :> Widget.t)` is free) and Layer 2 OCaml classes. The
  runtime uses **Layer 1 only**: uniform `Widget.t`, no per-call `:>` on
  class types, no wrapper allocation.
- Every C→OCaml crossing allocates a fresh `Gobject.obj` block for the same
  pointer, so `==` is meaningless, but `compare`/`Hashtbl.hash`/`Gobject.same`
  are pointer-based; `Hashtbl` keyed on `Widget.t` is correct.
- A wrapper owns one GObject ref and unrefs on finalization: an **unparented
  widget whose OCaml handle is dropped is destroyed**. The shadow tree must
  hold every handle it has created until it is parented or destroyed.
- Signal closures register the OCaml callback as a GC global root until
  disconnected; a connected handler pins everything it captures. Handlers must
  be disconnected on unmount, and an exception escaping a callback into C is
  undefined behaviour — every trampoline is exception-guarded.
- Not bound (callback/boxed/out params or namespace-level functions):
  `Widget.add_tick_callback`, `DrawingArea.set_draw_func`,
  `SignalListItemFactory` signals (so `ListView`/`GridView`/`ColumnView`
  cannot be populated), `ListBox`/`FlowBox` sort/filter/header funcs,
  `TextBuffer::insert-text`/`mark-set`, `Editable::insert-text`,
  `AlertDialog.choose` (async), `gtk_style_context_add_provider_for_display`,
  detailed `notify::*` signals. The last is worked around: `Gobject.Signal.connect_simple obj ~name:"notify::active"` accepts the raw
  detailed name.
- `open Ocgtk_gtk.Gtk` shadows `unit` (`Gtk_enums.unit`); runtime modules
  never `open` it.

## 3. Architecture

```
 app : local_ graph -> Node.t Bonsai.t
        │
        ▼
 ┌────────────────┐  schedule_event   ┌───────────────┐
 │ Bonsai_driver  │◄──────────────────│ Signal        │◄── GTK signals
 │ (flush/result/ │                   │ trampolines   │
 │  lifecycles)   │                   └───────────────┘
 └───────┬────────┘                          ▲
         │ Node.t (new)                      │ handler slots
         ▼                                   │
 ┌────────────────┐   ocgtk calls    ┌───────┴───────┐
 │ Patcher        │─────────────────►│ Live widgets  │
 │ (shadow tree)  │                  │ (GtkWidget)   │
 └────────────────┘                  └───────────────┘
         ▲
         │ request_frame (coalesced Glib.Idle) + fps tick (Glib.Timeout)
 ┌───────┴────────┐
 │ Scheduler      │
 └────────────────┘
```

Two libraries, because `ppx_inline_test`/`ppx_expect` cannot link against
anything depending on ocgtk (the installed archive contains modules whose C
stubs are absent; the `-linkall` test runner fails to link):

**`bonsai_gtk.vtree`** (`vtree/`, ocgtk-free, fully expect-testable):
- `Node`, `Kind`, `Attr`, `Attrs`, `Key`, `Children` — the virtual widget tree
  and its sexp printer.
- `Reconcile` — pure keyed list diff.
- `Native` — the escape-hatch payload type (an extensible variant, §6.6).
- `Handler` — typed handler values (`unit Effect.t`, `string -> unit Effect.t`,
  key-event handlers, ...).

**`bonsai_gtk`** (`src/`, depends on `vtree` and ocgtk):
- `Bonsai_gtk` — public entry: `start`, re-exports `Node`/`Attr`/`Key`/
  `Native`/`Effect`/`Bonsai`, `Expert`.
- `Patcher` — shadow tree; creates/updates/removes live widgets.
- `Widget_impl` — the per-widget interface; `widgets/*.ml` implement it.
- `Signals` — trampoline construction, handler slots, disconnect bookkeeping.
- `Scheduler` — frame requests, fps tick, `in_patch` guard.
- `Driver` — wraps `Bonsai_driver` + `Patcher` + `Scheduler`; one frame API.
- `Loop` — `GtkApplication` lifecycle; implements `start`.
- `Effect` — `Ui_effect` plus GTK-specific effects.
- `Live_tree` — `dump` reads back the live GTK tree as a sexp, for live tests.

## 4. Runtime loop

### 4.1 Entry point

```ocaml
val start
  :  ?application_id:string             (* default "org.bonsai_gtk.app" *)
  -> ?flags:Gio.Application_flags.t list
  -> ?time_source:Bonsai.Time_source.t  (* default: wall clock *)
  -> ?optimize:bool                      (* passed to Bonsai_driver.create *)
  -> ?target_frames_per_second:float     (* default 60. *)
  -> (local_ Bonsai.graph -> Node.t Bonsai.t)
  -> int                                 (* GtkApplication exit status *)
```

- The root `Node.t` must be `Node.window` or `Node.windows [...]` (a virtual
  root holding keyed `Node.window`s). Any other root raises at first frame.
- `start` creates a `GtkApplication`; on `activate` it creates the `Driver`,
  computes the first frame, mounts the window(s) onto the application, and
  blocks in `app#run`. Returns the status when the application quits.
- `Expert.Driver` is the same machinery without the `GtkApplication` around it:
  `Driver.create ?time_source ?optimize ~on_window_created app` builds a driver that
  renders nothing until the first `Driver.frame` call, which mounts the tree; `frame` can
  then be called by hand, or `Driver.start_tick ~fps` hands it a repeating timeout the way
  `start` does internally; `Driver.stop` tears the widget tree down. This is what `start`
  itself is built on (plus a `GtkApplication` to own the main loop and present the
  window), and what the live tests and embedders with their own main loop use directly.

**M2 amendment (2026-08-30).** There is a second entry point, and it is the one an
existing GTK application uses: `Bonsai_gtk.Expert.embed` (`Expert.Embedded`, `src/embed.ml`).

```ocaml
val embed
  :  ?time_source:Bonsai.Time_source.t
  -> ?optimize:bool
  -> ?target_frames_per_second:float
  -> (local_ Bonsai.graph -> Node.t Bonsai.t)
  -> Embedded.t
```

It builds the computation, mounts it with one frame, and starts a tick on whatever main
context the embedder is already running; it creates no `GtkApplication` and runs no main
loop. Three things follow from "the caller owns the window", and all three invert a rule
`start` states above:

- **The root must *not* be a `Node.window`.** `Driver.create` therefore takes a
  `?root_kind`, and `check_root` rejects each way round with a message naming the other
  entry point. The rule "a `Node.window` anywhere below the root is rejected" is unchanged
  and, for an embedded tree, means *anywhere at all*.
- **`Embedded.widget` is a wrapper `embed` owns, not the rendered root.** The root node's
  *kind* may change between frames, and the patcher answers a kind change by mounting a
  replacement and destroying the original — so a caller handed the rendered root would
  afterwards hold a widget nothing renders into again, with no exception and nothing on
  stderr. The wrapper is a `GtkOverlay` holding the tree as its main child: measured, it is
  the only single-child container in GTK 4 that allocates its child exactly as the caller's
  own container would (a box or a grid drops the child's alignment on one axis; only an
  overlay forwards `halign`/`valign` as well as the expand flags).
- **`stop` empties the wrapper but does not unparent it**, because it did not parent it.

The obligation embedding adds is about waste rather than safety — the shadow tree holds a
reference to every widget it built, so an embedded tree survives its host and a frame after
the host is gone patches a tree nobody can see rather than freeing memory. But it is a real
obligation: an embed dropped without `stop` is permanently unreclaimable, because the
patcher's signal closures hold the runtime, which holds the shadow tree, which holds
GObject references back. `stop` is what breaks the cycle, and it is also what disconnects
the `destroy` backstop `create` installs — see the §11 amendment on finalisation.

### 4.2 Frame

A frame is, in order:

1. `Bonsai.Time_source.advance_clock time_source ~to_:(Time_ns.now ())`
   (skipped when a custom time source is supplied).
2. `Bonsai_driver.flush`.
3. `Bonsai_driver.result` → `Node.t`.
4. `Patcher.patch` under the `in_patch` guard, followed by `Patcher.run_fixups`
   (still inside the guard).
5. `Bonsai_driver.trigger_lifecycles`.
6. If `Bonsai_driver.has_after_display_events`, request another frame.

Frames run only from the GLib main loop, never synchronously inside a signal
handler.

**M1 amendment (2026-08-29).** Step 4 originally read "if the new root is not
`phys_equal` to the last rendered root", and the driver kept a `last` field for
that test. Both are gone: *every* frame patches. A model that **declines** a
user's edit — the digits-only field handed a letter, the switch the model
refuses to flip, the stack page it will not navigate to — leaves its state
exactly as it was, so it renders the physically same node, so the patch a
phys-equal guard throws away is precisely the patch that would put the widget
back. Both halves of the cure (`Widget_impl.reassert`, §6.5, and the
stack-selection fixup pass) live inside that patch. The cost is bounded rather
than free: an unchanged frame still walks the shadow tree, but `Kind.equal_props`
skips every impl `update` and `Attrs.diff` writes nothing, so no GTK call is
made. A walk restricted to the re-assert and fixup passes for a phys-equal root
is on the backlog.

**M2 amendment (2026-08-30).** That walk landed. `Patcher.reassert_only` runs
`Widget_impl.reassert` and the fixup enqueues over the shadow tree and nothing else, and
`Driver.frame` takes it whenever the new root is `phys_equal` to the live one. The
reasoning the M1 amendment gives is unchanged and is what makes the narrowing safe rather
than a re-introduction of the guard it removed: what the phys-equal argument rules out is
skipping the frame, not diffing it, and with the node physically identical there is nothing
for `Attrs.diff` to find and nothing for `Kind.equal_props` to admit — so a full patch
would walk the same tree to reach the same two calls. An idle tick is now nearly free, and
a declined edit is still put back.

### 4.3 Scheduling

- `Scheduler.request_frame` arms one coalesced
  `Glib.Idle.add ~prio:(Glib.int_of_priority `HIGH_IDLE)` source (idempotent
  while armed; `HIGH_IDLE` is GTK's redraw priority, so the patch lands before
  the next paint). Signal trampolines call `Driver.schedule_event eff` then
  `request_frame`. (`Widget.add_tick_callback` is not bound by ocgtk;
  `Gdk.Frame_clock.on_update` is a possible later refinement.)
- A `Glib.Timeout` at `1 / target_frames_per_second` runs a frame
  unconditionally when `target_frames_per_second` is positive (the default,
  60). This is what advances the clock for `Bonsai.Clock.every`,
  `Clock.sleep`, `Clock.now`. When nothing changed, flush is a no-op — but
  since the M1 amendment to §4.2 the patch is no longer skipped, so an idle
  tick costs one stabilization *plus* one walk of the shadow tree that issues
  no GTK calls. Suspending the tick while idle, and a re-assert-and-fixup-only
  walk for a phys-equal root, are noted future optimizations, not part of this
  design. **M2 amendment (2026-08-30):** the second of those two landed
  (`Patcher.reassert_only`, §4.2), so an idle tick now costs one stabilization
  plus a re-assert-and-fixup walk rather than a full one. Suspending the tick
  while idle is still not done.
- A non-positive `target_frames_per_second` installs no tick at all
  (`Scheduler.start_tick` with `fps <= 0.`). Frames still happen on
  interaction via `request_frame`. After-display handlers still need to be
  re-serviced without a tick to drive them, so a frame that finds one pending
  (`Bonsai_driver.has_after_display_events`, §4.2 step 6) calls
  `Scheduler.request_frame_soon` instead of nothing: a coalesced one-shot
  `Glib.Timeout` at a fixed ~16 ms, the same cadence a 60 fps tick would give,
  rather than an idle (which has no rate cap and would spin as fast as the
  CPU allows). This keeps after-display handlers alive without standing in
  for the tick — `Bonsai.Clock` only advances inside a frame, and a tickless
  app gets no frames beyond what interaction and pending after-display work
  produce.

### 4.4 Reentrancy guard

Programmatic widget updates fire GTK signals (`set_text` → `changed`,
`set_active` → `notify::active`). `Scheduler.in_patch` is set for the duration
of `Patcher.patch`; every signal trampoline returns immediately while it is
set. Consequence: the model is the single source of truth and a patch can
never re-enter the driver.

### 4.5 Exit

`Effect.quit : unit Effect.t` calls `app#quit` on whichever application `start` is
currently running. The library holds that application through a single reference for the
duration of the call — one application per process — so two overlapping `start`s fight
over it (the second warns on stderr and takes over the reference). Outside `start` —
before it has run, under `Expert.Driver`, in a headless test, or after `start` has
returned — there is nothing to quit, so performing `quit` logs and does nothing rather
than raising. There is no Ctrl-C handling; GTK/GLib own process signals.

## 5. Node / Attr model

### 5.1 `Node.t`

```ocaml
type t =
  { kind : Kind.t                (* which widget; carries typed props *)
  ; key : Key.t option
  ; attrs : Attrs.t              (* merged map of common widget attrs *)
  ; children : Children.t        (* shape fixed by kind, see 5.3 *)
  }
[@@deriving sexp_of]
```

`Kind.t` is a closed variant; each constructor carries that widget's typed
props record (e.g. `Button of Button_props.t`). Nodes are immutable values;
`sexp_of_t` prints a readable tree (handlers print as `<handler>`), used by
expect tests.

Constructors are typed, one per widget, with widget-specific properties as
labeled arguments and shared properties in `~attrs`:

```ocaml
val label   : ?key:Key.t -> ?attrs:Attr.t list -> ?wrap:bool -> ?xalign:float -> string -> t
val button  : ?key:Key.t -> ?attrs:Attr.t list -> ?label:string -> ?child:t -> ?icon_name:string -> unit -> t
val box     : ?key:Key.t -> ?attrs:Attr.t list -> ?spacing:int -> ?homogeneous:bool -> orientation:[ `Horizontal | `Vertical ] -> t list -> t
val entry   : ?key:Key.t -> ?attrs:Attr.t list -> ?placeholder:string -> ?text:string -> unit -> t
val window  : ?key:Key.t -> ?attrs:Attr.t list -> ?title:string -> ?default_size:int * int -> ?titlebar:t -> t -> t
val windows : t list -> t
val native  : ?key:Key.t -> (module Native_gtk.S with type input = 'a) -> 'a -> t   (* runtime library only, §6.6 *)
```

Widget-specific *events* are attrs too (`Attr.on_clicked`, `Attr.on_changed`,
`Attr.on_toggled`, `Attr.on_value_changed`, ...); attaching one to a widget
that does not emit that signal is a runtime error at creation time.

### 5.2 `Attr.t` / `Attrs.t`

`Attr.t` covers what every `GtkWidget` has:
`css_class` (repeatable), `margin_start/end/top/bottom`, `halign`, `valign`,
`hexpand`, `vexpand`, `sensitive`, `visible`, `tooltip`, `width_request`,
`height_request`, `opacity`, `focusable`, `can_focus`, `name`, `test_id`,
`css_provider` (per-widget style context, §7),
`on_key_pressed`, `on_key_released`, `on_focus_enter`, `on_focus_leave`,
`on_map`, `on_unmap`, and the widget-specific signal handlers listed per
widget. `Attr.many : t list -> t`.

`Attrs.t` is a map keyed by attribute name (`css_class` accumulates into a
set); `Attrs.diff old new` yields `Set`/`Unset` ops, mirroring `virtual_dom`.
Two nodes with the same attrs are equal by value except handlers, which are
compared physically (they are re-created each frame anyway; equality only
short-circuits slot writes).

**M2 amendment (2026-08-30).** Two changes to what this section describes.

*The variant is sealed.* `Attr.t` is `private Attr.Private.t`: the constructors live in
`Attr.Private`, and an application can neither build one from a raw constructor nor match
on one without spelling `(a :> Attr.Private.t)` — which is legal for anyone, deliberately,
and carries no stability promise. The alias form the M1 plan wrote down does not typecheck;
`type t = private Private.t` is what does, and it is compiler-enforced rather than
promised. `Attr.Name.t` stays concrete on purpose: `Attr_apply.unset`'s exhaustive match
over it is the mechanism that makes "unset restores the creation-time default" impossible
to forget for a new attribute, and sealing it would trade a compile error inside the
library for a silent omission.

*The controller attrs ship in M2, not M3.* `on_key_pressed`, `on_key_released`,
`on_focus_enter` and `on_focus_leave` — listed above as if they were ordinary widget-wide
attrs — are here, joined by `on_click`, and all five take the shape this section does not
anticipate: `on_click` and the two key attrs take a `?phase` (`Phase.t`, GTK's propagation
phase, defaulting to `Bubble`), `on_click` also takes a `?button`, and `on_key_pressed`'s
handler is **not** a `Handler.t` — it returns a `Key_response.t`, because GTK asks a key
press whether anything handled it and routes the event on the answer synchronously (§6.4).
`on_map` and `on_unmap` do **not** ship: nothing has wanted them, and a lifecycle attr on a
declarative tree wants a design of its own. `css_provider` is likewise still M3.

The five are also unlike every other event attr in being legal on *any* node: they are not
signals of a widget class but controllers the runtime attaches to whatever carries the
attr, and the controller exists exactly as long as the attr does.

### 5.3 Children shapes

Fixed per kind, encoded in constructor arguments:

| Shape | Widgets | Live operations |
|---|---|---|
| `None` | Label, Entry, Switch, ... | — |
| `Single` | Window, ScrolledWindow, Frame, Expander, Revealer, Button(child), ... | `set_child (Some w)` / `set_child None` |
| `List` (keyed, ordered) | Box, Grid, Stack, ListBox, FlowBox, Notebook | `append` / `insert_child_after` / `reorder_child_after` / `remove`, or the widget's page API |
| `Slots` (named) | HeaderBar (`start`/`title`/`end`), Paned (`start`/`end`), Overlay (`child` slot + `overlays` list), CenterBox, ActionBar | per-slot single/list patch |

**M1 amendment (2026-08-29).** `Grid` is a `List`, not `Slots`: its children are
an ordinary keyed list and the cell is an attribute on the child
(`Attr.grid_cell ~column ~row ?width ?height`), which keeps one code path for
every list container and lets a cell change be a prop diff rather than a
re-shape. A child whose cell changes is re-`attach`ed, which moves it to the end
of GTK's child list; the cell is the placement, so nothing moves on screen.
`Overlay`'s two slots are the `child` (a `Single`) and `overlays` (a `List`).

Also: `Overlay`, `Stack` and `Grid` accept no reorder. GTK exposes no
`reorder_child_after` for them, so `Reconcile`'s `Move` op is a **no-op** in
those three; keys still preserve identity (state survives), but children stay in
the order they were first added. `Notebook` (M2) does have `reorder_child`,
which is where an explicit `Unordered` marker on `list_ops` should be
reconsidered.

**M2 amendment (2026-08-30).** The marker exists, and no `Move` is emitted
rather than emitted and ignored. `Widget_impl.list_ops.move` is an
`option`: `None` means "this container has no reorder primitive", and
`Patcher.patch_list` passes `Reconcile.diff ~ordered:(Option.is_some ops.move)`.
`Overlay`, `Stack` and `Grid` take `None`; `Notebook` takes `Some`. A `Move` op
reaching a container without one is `Invalid_argument` rather than a silent
drop, because a dropped `Move` desynchronises the patcher's child list from
GTK's. The consequence for an unordered container is stated in
`vtree/reconcile.mli`: its ops satisfy `apply ops old = new_` only as a *set*,
not as a sequence, and an `Update` is therefore indexed by the child's position
in the *live* list rather than in `new_`.

The table's `List` row is also now complete: `ListBox`, `FlowBox` and `Notebook` are all
`List`, and **their children require keys** — a child without one is `Invalid_argument`
from the *constructor* (`Node.require_child_keys`, retrofitted to `Node.stack`), naming the
child's index, because at that point there is no tree to prefix a path onto and the mistake
is in the call. A list box's rows and a flow box's children are wrapped by the impl in a
`GtkListBoxRow` / `GtkFlowBoxChild` it owns — there is no `Node.list_box_row` — and per-row
settings arrive as placement attrs on the child (`Attr.row_selectable`,
`Attr.row_activatable`). A notebook interposes nothing: its pages *are* its children's
widgets, and `Attr.tab_label` is a string GTK builds a label from.

### 5.4 Keys

`Key.t = string`. A node without a key is matched by position + kind. A keyed
node is matched by key within its sibling list; a key appearing twice among
siblings is an error at patch time. Keys are what preserve widget state
(focus, entry text, scroll position) across reorders.

**M2 amendment (2026-08-30).** With three keyed containers whose *selection* is also named
by key, one rule decides what a key that names no child does, and it is a rule about
arity rather than about the container:

> A container that shows exactly **one** of its children raises when told to show one that
> does not exist. A container with a **plural** selection ignores keys it cannot find.

So `Node.stack ~visible_child` and `Node.notebook ~current_page` are `Invalid_argument`
(from the fixup pass, which is the first point at which the child list is known — with an
empty-container carve-out, since a model rendering no pages has no name it could pass that
would be right), while a `list_box`'s or `flow_box`'s `~selected` filters itself down to the
keys that have children. The asymmetry is not arbitrary: a required single-child argument is
a claim about a set the caller can see, so a name outside it is a typo, whereas a plural
selection and the child list routinely come from different Bonsai state and a key naming a
child that has not arrived yet is a frame a correct model passes *through*. Such a ghost key
is inert while it names nothing and selected on the frame its child arrives — the same frame,
pinned in both directions.

Duplicate sibling keys are checked at mount as well as at patch (§11), and `Child_keys` —
the ephemeron table each container keeps from child widget to key — is keyed on the child
widget the patcher retains, never on the wrapper row, or the entry dies with the wrapper.

## 6. Patcher

### 6.1 Shadow tree

```ocaml
type live =
  { node : Node.t                       (* last rendered description *)
  ; widget : Widget.t                    (* Layer-1 ocgtk handle; keeps the GObject alive *)
  ; impl : Widget_impl.packed            (* create/update/children for this kind *)
  ; slots : Handler_slots.t              (* mutable current handlers, by signal *)
  ; handler_ids : Gobject.Signal.handler_id list  (* for disconnect on destroy *)
  ; mutable children : live Children.t   (* mirrors node.children *)
  }
```

The shadow tree is the *only* OCaml owner of unparented widgets (§2.2), so a
widget is created and parented within the same patch step, and `destroy`
disconnects then unparents before dropping the record.

`Patcher.mount : Node.t -> live` and `Patcher.patch : live -> Node.t -> live`.

### 6.2 Algorithm

`patch live new_node`:

1. Different `kind` (or different `Native` module) → `destroy live`, then
   `mount new_node`, and tell the parent to replace the widget in place.
2. Same kind → `Attrs.diff` applied via `Widget_impl.set_attr`, widget props
   diffed by the impl's `update ~old ~new`, handler slots overwritten, then
   children patched according to the shape:
   - `Single`: none↔some → mount/destroy + `set_child`; some↔some → recurse.
   - `List`: `Reconcile.diff ~old ~new` (§6.3) → apply ops in order; matched
     pairs recurse.
   - `Slots`: per-slot `Single` or `List` patch.
3. Return the updated `live` (physically the same record, mutated).

`destroy live` recursively: clears the slots, disconnects every `handler_id`
(`Gobject.Signal.disconnect`), recurses into children, then — a window has no parent to
unparent it, so it is destroyed explicitly (`Window.destroy`); a native node's payload
module gets its `destroy` called, to release whatever `create` acquired; anything else
needs nothing further here, since the caller already detached it from its parent (below) —
and drops the OCaml reference so the wrapper and closures can be collected. Disconnecting
matters: a connected closure is a GC root and would otherwise pin the captured handler slot
and its environment forever.

A `Single` child cleared or a `List` `Remove` unparents the live widget via the parent
impl's remove op (`set_child None`, `Box.remove`, ...) — and that op emits GTK signals
synchronously, so a handler could fire against a node Bonsai is already in the middle of
dropping if `destroy` (which clears slots) hasn't run yet. Rather than run `destroy` first
and only then remove — which would really destroy a `Window` live before the remove op
that names it — those call sites first call `disarm live`, which clears every slot in the
subtree, recursively, without disconnecting anything or touching the widget; then the
remove op; then `destroy` for real. `disarm` is `destroy`'s slot-clearing step split out so
it can close that window ahead of everything else.

**M1 amendment (2026-08-29).** Step 1 is the other way round in the
implementation, deliberately: `mount new_node` runs *first*, and only then is
the old `live` destroyed, so that the subtree being replaced stays alive and
parented until the replacement exists. Two consequences follow. A native node's
replacement has its `create` called while the instance it replaces has not yet
had its `destroy` — an impl that acquires an exclusive resource must expect the
overlap. And the old subtree's `Stack` name registrations are given up before
the mount (`Patcher.drop_stack_names`), because otherwise re-declaring the same
`Node.stack ~name` inside the replacement — which is all that wrapping a stack
in a `Node.frame` does — would collide with the copy of itself on its way out.
The collision check is not weakened by that: a genuine collision is two stacks
both still in the tree, and the other one is by definition not in the subtree
being discarded.

Step 2's order is likewise props → `reassert` (§6.5) → attrs → slots → children,
rather than attrs before props.

### 6.3 `Reconcile.diff` (pure)

```ocaml
type 'a op =
  | Insert of { index : int; item : 'a }
  | Move   of { from : int; to_ : int }
  | Remove of { index : int }
  | Update of { index : int; old : 'a; item : 'a }

val diff : key:('a -> Key.t option) -> same_kind:('a -> 'a -> bool)
  -> old:'a list -> new_:'a list -> 'a op list
```

Two-pass: keyed items match by key; unkeyed items match by position among the
unkeyed remainder if `same_kind`. Emits removes (descending index) first, then
inserts/moves in ascending target order, so indices in the op stream are
always valid against the live list at that moment. Property-tested against a
reference implementation (apply ops to `old`, compare to `new_`).

### 6.4 Signals and handler slots

Each impl declares the signals it supports. At `create`, every declared signal
is connected **once** to a trampoline closure that:

1. is wrapped in a catch-all exception guard (an exception crossing into C
   is undefined behaviour); caught exceptions are logged with the node path;
2. returns immediately if `Scheduler.in_patch` is set;
3. reads the current handler from the slot (`None` → return);
4. converts GTK arguments to the OCaml event value (e.g. reads the entry text
   via `Editable.get_text`, builds a key-event record);
5. `Driver.schedule_event (handler event)`; `Scheduler.request_frame`.

Updating a handler is a slot write. Nothing is disconnected until `destroy`.

**M1 amendment (2026-08-29).** A spec's `connect` returns a
`Signals.connection` — the handler id *and the GObject it was issued for* —
rather than a bare `handler_id`, and `Signals.disconnect` disconnects each from
its own object. A handler id is only unique per object, so an id returned by a
connection to something other than the widget (a `GtkTextBuffer`, a list model,
one of the event controllers named below) cannot be disconnected from the
widget: at best a GLib critical, at worst it disconnects an unrelated handler
that happens to share the number while the real one stays connected, pinning its
slot and closure alive as the GC root §6.1 warns about. Every spec builds its
result with `Signals.connected obj id`.

`fire` returning `None` means "nothing to schedule", which covers two cases: the
attr in the slot is not the one this spec handles, and this particular emission
is not one the application should hear about. The second is what
`GtkSearchEntry` needs — see §6.5.

Signals ocgtk does not generate as `on_*` but which GLib can deliver through
the generic marshaller — the `notify::<prop>` family (`Switch` `active`,
`DropDown` `selected`, `Revealer` `child-revealed`) — are connected with
`Gobject.Signal.connect_simple obj ~name:"notify::active"` and read the value
back with the class getter. Key and pointer events come from
`Event_controller_key` / `Gesture_click` / `Event_controller_motion` attached
to the widget. Signals ocgtk cannot bind at all (boxed-record or out
parameters) are omitted from the API and listed in the widget's doc comment.

**M2 amendment (2026-08-30).** `spec` is a variant with two arms, because step 4 above —
"reads the current handler ... converts GTK arguments to the OCaml event value" — is not
always possible.

- `Read_back` is the M1 shape and still the ordinary one: GTK's callback carries nothing
  useful, the value the user just changed is on the widget, and `fire` reads it back with
  the class getter. Every M1 signal and every `notify::` one is one of these. Its `connect`
  now returns a `connection` **list**, because one attr may need more than one GTK emission
  to be complete: a `GtkCalendar`'s date moves by a day click (`day-selected`) *or* by a
  heading walk (which emits only `notify::month`/`notify::year` and no `day-selected` at
  all — measured), and an attr that heard one and not the other would be a prop the model
  cannot keep up with. All of them share one attr name and therefore one slot, so
  `update_slots` and `require_slots` are unchanged.
- `Payload : ('p, 'r) payload -> spec` is for the signals whose arguments cannot be
  recovered afterwards, and which ones those are is two rules rather than a list of
  exceptions (stated as rules so that a milestone adding a signal need not update a
  count). **Every signal whose argument is a child widget**, because the child is gone
  by the time anything could look for it: `GtkListBox::row-activated`,
  `GtkFlowBox::child-activated` and `GtkNotebook::switch-page`. And **every controller
  signal**, because a controller remembers nothing about the event it has just delivered:
  `GtkGestureClick::pressed` (the coordinates are stored nowhere),
  `GtkEventControllerKey::key-pressed` (the keyval, and a `bool` GTK wants back) and
  `GtkEventControllerKey::key-released` (the keyval; its answer to GTK is `unit`). A new
  signal of either shape is a `Payload`, not a `Read_back`. `'p` is what the `connect` closure
  assembles — it may combine the callback's arguments with things read off the object,
  which is how a click's button and modifiers get in — and `'r` is what the callback hands
  **back** to GTK. Both are existential.

`fire` on a `Payload` spec returns `'r * unit Ui_effect.t option` rather than
`'r Ui_effect.t`, and that shape is load-bearing: the return value has to reach GTK
synchronously on the C stack, and a Bonsai effect is scheduled and performed later. So the
*decision* is a pure function of the event, made in the trampoline, and the *consequence*
is an ordinary effect. `Attr.on_key_pressed`'s `Key_response.t` is that split, surfaced.
Each `Payload` spec also carries a `declined` value — what the trampoline answers GTK on
the three paths that reach no handler (an empty slot, an emission during a patch, a `fire`
that raised) — because the inert answer differs per signal and nothing else knows it: for a
key controller it is `false`, "not handled", or a widget with no handler would swallow every
key it saw.

Event controllers are the other change. `Attr.on_click`, `on_key_pressed`,
`on_key_released`, `on_focus_enter` and `on_focus_leave` are declared by **no impl**: they
are legal on every kind, so there is no `signals` list they could belong to. `Controllers`
attaches them on demand, one controller per *family* (`Click`, `Focus`, `Key` —
`Events.Family.t`, the single exhaustive table `Events.is_controller_attr`,
`Signals.require_slots`'s skip list and `Controllers.update`'s dispatch all derive from),
and detaches a family the moment its last attr goes. The controllers are named
(`Event_controller.set_name`, never `set_static_name` — that stores the pointer uncopied,
and a computed OCaml string is reclaimed heap) so that a live test can tell this library's
controllers apart from the three a `GtkButton` brings of its own.

### 6.5 Controlled text widgets

`Entry`, `SearchEntry`, `PasswordEntry`, `EditableLabel`, `TextView`:
`update` sets the widget text only when it differs from the widget's *current*
text (not the previous node's), so a model that echoes what the user typed
causes no caret jump, while a model that rewrites input (e.g. uppercasing)
still wins.

**M1 amendment (2026-08-29).** The rule is not implemented in `update`, because
the patcher skips `update` entirely when the two nodes' props are equal — which
is exactly the case a *declined* edit produces. It lives instead in
`Widget_impl.reassert : (Widget.t -> Kind.t -> unit) option`, a hook the patcher
calls on **every** patch of a node of that kind, after `update` and before the
attrs and children, and which compares against the live widget rather than
against the previous node. It runs inside the `in_patch` guard, so the signals
its writes provoke are dropped, and it brackets them in `Widget_impl.batch`
(freeze/thaw). It is `None` for a kind with no controlled prop.

The rule reaches beyond text: `ToggleButton`, `CheckButton` and `Switch`
(`active`), `SpinButton` and `Scale` (`value`), `Expander` (`expanded`) and
`Revealer` (`reveal_child`) all re-assert the same way. Two exceptions:

- **`Stack`'s visible child** is applied by the post-patch fixup pass, not by
  `reassert` — `reassert` runs before `patch_children`, so the page a frame
  selects may not exist yet. The fixup pass runs after the whole tree is built
  and inside the same guard, and is also where a `StackSwitcher`/`StackSidebar`
  resolves the stack it names through the patcher's name registry.
- **`SearchEntry`'s debounced signal is filtered rather than guarded.** Every
  other signal in M1 is emitted synchronously from the setter, which is what
  makes the `in_patch` guard (§4.4) work. `GtkSearchEntry::search-changed` is
  emitted from a `g_timeout` armed by the text change, `search_delay` ms later,
  long after the frame has returned — so a controlled write would come back to
  the application as a search the user never performed, once per write, and
  oscillate for any model whose normalisation is not a fixed point. The widget
  impl records what the library last wrote (weakly, keyed on the widget) and the
  spec's `fire` declines the next emission if the widget's text still equals it.
  The record is consumed on that first emission either way, so it can never
  suppress more than the one signal the write armed. Any later deferred signal
  needs the same treatment; the synchronous guard cannot cover one.
- **`Paned`'s position is deliberately uncontrolled** (`reassert = None`):
  writing it every frame would fight the user's drag handle.
  `Attr.on_position_changed` reports where it was left, and an app that wants it
  controlled can round-trip it through its own model.

**M2 amendment (2026-08-30).** The list of controlled props grows, the fixup-pass exception
grows with it, and the rule gains a third case for a value the widget cannot hold.

*New controlled props.* A `TextView`'s buffer text, a `DropDown`'s `~selected`, a
`Calendar`'s `~date`, an `EditableLabel`'s `~text` **and** its `~editing` flag all
re-assert. Three details each cost a round to find: a text view's `reassert` compares
against a **cached** last-written string rather than reading the buffer back, because
`gtk_text_buffer_get_text` is transfer-full and nothing frees it (a megabyte of notes would
leak a megabyte per idle frame); a calendar's date is written **day-1-first**, then year,
then month, then the real day, because each GTK setter rebuilds the whole date and refuses
outright if the result is not a real day (the obvious year-month-day order gets four of five
transitions wrong — measured, pinned); and an editable label's two props are written
text-then-editing, because entering editing mode selects the whole text and a write after
`start_editing` would collapse the selection.

*New fixup-pass cases.* Joining a stack's visible child, for the same reason (the child may
not exist when `reassert` runs): a `ListBox`'s and `FlowBox`'s `~selected`, and a
`Notebook`'s `~current_page` — the last of which reads the live widget back rather than
trusting an index, because `set_current_page` on a page whose child is hidden emits
`switch-page` and leaves the current page unchanged (measured).

*Refuse, record, report.* A controlled prop may name a value the widget genuinely cannot
hold: text that is not valid UTF-8 or contains a NUL for a `GtkTextBuffer`, a NUL for a
`GtkEditableLabel`, a `Date.t` in year 0 for a `GtkCalendar` (GTK's year range is 1–9999).
Raising would end the application (§11), and writing would corrupt — GTK empties a text
buffer *before* refusing invalid UTF-8, so the previous contents are lost. So the impl
**refuses** the write before touching the widget, **records** it so the frames after it cost
nothing, and **reports** it once through `Patcher.ctx.report` with the node's path — once
per offending value, not once per frame. The refusal decision is made *before* any
comparison, or a parked frame would take the compare's cost forever. The next value GTK will
take is written normally.

*`batch_if`.* `reassert` runs on every patch of a node of its kind, including the patches
that write nothing, and `Widget_impl.batch`'s freeze/thaw measured ~80 ns per call. So
`reassert` brackets **conditionally**: `Widget_impl.batch_if writes`, with the condition
being whether this frame is going to write anything at all.

### 6.6 `Node.native`

`vtree` cannot mention ocgtk types, so the native payload is an extensible
variant defined in `vtree` and extended by the runtime:

```ocaml
(* vtree/native.ml *)
type payload = ..
type t = { name : string; payload : payload }   (* sexp prints <native name> *)

(* src/native_gtk.ml *)
module type S = sig
  type input
  val name : string
  val create : input -> Widget.t
  val update : Widget.t -> old:input -> input -> unit
  val destroy : Widget.t -> unit
end

(* An impl, plus the [Type_equal.Id.t] witness that lets the patcher recover [input]
   from a node's existentially typed payload. *)
type 'a impl
val Native_gtk.impl : (module S with type input = 'a) -> 'a impl

type Native.payload += Gtk : 'a impl * 'a -> Native.payload
val Native_gtk.node : ?key:Key.t -> ?attrs:Attr.t list -> 'a impl -> 'a -> Node.t
```

Build the `impl` once, at the top level of the module that defines the widget, and reuse
that value for every node. The patcher treats two `native` nodes as the same kind iff their
payloads carry the same `impl`'s `Type_equal.Id.t` witness (checked with
`Type_equal.Id.same_witness`, not a physical-module comparison — modules aren't
first-class values to compare that way); then calls `update`; otherwise replaces. Two
`impl`s built from the same module are different widgets as far as the patcher is
concerned — building a fresh `impl` per render, rather than reusing one, is a bug the
witness turns into a loud `Invalid_argument` rather than a misread input. This is how an
existing hand-written ocgtk widget, or a `Picture` fed from a `Gdk.Memory_texture`, plugs
in. (Custom Cairo drawing via `DrawingArea` is *not* possible: ocgtk does not bind
`set_draw_func`.)

**M1 amendment (2026-08-29).** The `Picture` case is no longer hypothetical:
`Native.Picture` ships as a supported impl, taking a `Gdk.Paintable` (a
`Gdk.Memory_texture`, say) where the declarative `Node.picture` takes a file,
resource or icon source. `Node.image` has no paintable source by design — it
would be a second native widget, and paintables belong on `GtkPicture`.

Because of §6.2's mount-before-destroy order, a native node whose parent's kind
changes has its replacement `create`d before the instance it replaces is
`destroy`ed. An impl that acquires something exclusive — a port, a lock, a
singleton subscription — has to tolerate the two overlapping.

Native nodes carry `Attr.t`s like any other node, but they declare no signal
specs, so `Signals.require_specs` **rejects an event attribute on a native node**
with `Invalid_argument` at mount and at patch (§11) rather than silently
dropping it. A native widget that needs to talk back connects its own signals
inside its impl.

## 7. Widget catalogue and milestones

Each widget is one file `src/widgets/<name>.ml` implementing:

```ocaml
module type Widget_impl.S = sig
  type props
  val name : string
  val signals : Signal_spec.t list
  val create : props -> Widget.t
  val update : Widget.t -> old:props -> props -> unit
  val children : Children.shape
  (* child operations for this kind's shape *)
  val set_child : Widget.t -> Widget.t option -> unit
  val insert_child : Widget.t -> index:int -> Widget.t -> unit
  val move_child : ...
  val remove_child : Widget.t -> Widget.t -> unit
end
```

Milestones, each merged only with its tests green:

- **M0 — scaffold:** flake, dune-project, opam switch script, library skeleton,
  `Reconcile`, `Attrs`, `Node` with `Label` + `Box` + `Window`, runtime loop,
  counter example, `Bonsai_gtk_test` handle.
- **M1 — core & layout:** *done* (2026-08-29). Button, ToggleButton,
  CheckButton, Switch, Entry, PasswordEntry, SearchEntry, SpinButton, Scale,
  ProgressBar, Spinner, Image, Picture, Separator, ScrolledWindow, Frame,
  Expander, Grid, CenterBox, Paned, Overlay, Revealer, Stack + StackSwitcher +
  StackSidebar, `Node.native` — 29 `Node.*` constructors in all, plus
  `Native.Picture`, an `examples/gallery.ml` that renders one of each, and
  `Bonsai_gtk_test` actions `Click`/`Toggle`/`Set_text`/`Activate`/`Set_value`.
  Two shipped details this section did not anticipate:
  `Attr.measure_overlay` defaults to **`false`**, matching
  `GtkOverlayLayoutChild:measure` (an overlay child is unmeasured unless it says
  otherwise), and `Attr.on_position_changed` ships for `Paned` because its
  position is uncontrolled (§6.5).
- **M2 — lists & text:** *done* (2026-08-30). ListBox (keyed rows, controlled
  selection, per-row `Attr.row_selectable`/`row_activatable`, `?placeholder`),
  FlowBox (keyed children, controlled selection, geometry as props), Notebook
  (keyed pages, `Attr.tab_label`, controlled `~current_page`, and, with `box`, one
  of the two containers in the library whose children really move — it has
  `gtk_notebook_reorder_child`), TextView (controlled buffer), DropDown (string
  list spliced in place, controlled `~selected`), LevelBar, Calendar,
  EditableLabel — **37 `Node.*` constructors in all**, checked against
  `Kind.Variants.descriptions` by `test/handle/test_gallery.ml` rather than
  counted by hand. With them: the five event-controller attrs `Attr.on_click`,
  `on_key_pressed`, `on_key_released`, `on_focus_enter`, `on_focus_leave`
  (§5.2, §6.4); `Bonsai_gtk.Expert.embed` (§4.1); four new enum modules
  (`Selection_mode`, `Tab_position`, `Wrap_mode`, `Level_bar_mode`) and six
  new event-value modules (`Phase`, `Modifiers`, `Click_event`, `Keyval`,
  `Key_event`, `Key_response`); and `Bonsai_gtk_test.Action.t` grown from five
  constructors to **nineteen** (§9).

  Two details this section did not anticipate. **The controller attrs came
  forward from M3**, because the mechanism M2 had to build for
  `ListBox::row-activated` — a signal whose payload cannot be read back off the
  widget — is the same `Payload` mechanism they need (§6.4), and building it
  twice would have been the waste. **`Calendar` takes a `Core.Date.t`**, not
  GTK's three integers and not a `GDateTime`: `gtk_calendar_get_date` and
  `gtk_calendar_select_day` trade in `GDateTime`, this binding has no
  `GDateTime` anywhere, and there is no `GLib-2.0.gir` in the checkout to
  generate one from — so the year/month/day conversion (GTK's month is
  zero-based; its day is not) exists exactly once, in `w_calendar.ml`.
- **M3 — chrome & popups:** HeaderBar, ActionBar, Popover, MenuButton +
  `Node.menu` (GMenu model + GAction routing), AlertDialog / FileDialog
  effects, `Node.windows` multi-window, `Attr.shortcut` (GtkShortcutController).

Out of scope until a follow-up design: ListView/ColumnView/GridView (ocgtk
generates no `SignalListItemFactory` signals, so they cannot be populated
without new C stubs), Assistant, ColorDialog/FontDialog, drag & drop, custom
Cairo drawing (`DrawingArea.set_draw_func` unbound), display-wide CSS
(`add_provider_for_display` is unbound upstream; the fork already carries the
stub as commit 6, awaiting the upstream PR, so M3 wires it up rather than
writing it. Until then `Attr.css_provider` applies a provider to a widget's own
style context).

Implementation notes carried from the survey: `ListBox`/`FlowBox` sorting and
filtering are done in the Bonsai model (the GTK callbacks are unbound — **M2
amendment (2026-08-30):** confirmed against the fork, and it covers headers too;
`set_sort_func`, `set_filter_func` and `set_header_func` are unreachable because
ocgtk's generator emits no GIR-callback-taking method at all, so a header is an
ordinary row carrying `Attr.row_selectable false` and `Attr.row_activatable
false`);
`Grid` children are re-`attach`ed on any coordinate change; `Notebook` reorders
use `reorder_child`; `Stack` pages are keyed by `name`; prop batches are
bracketed with `Gobject.Property.freeze_notify`/`thaw_notify`.

## 8. Effects

`Bonsai_gtk.Effect` = `Ui_effect` re-export plus:

- `quit : unit t`
- `of_thunk : (unit -> 'a) -> 'a t` (re-export)
- `after : Time_ns.Span.t -> unit t` — `Glib.Timeout`-backed.
- `on_idle : unit t` — resolves on the next `Glib.Idle`.
- `Clipboard.set_text : string -> unit t`, `Clipboard.get_text : string option t`
- `Alert_dialog.show : ?detail:string -> buttons:string list -> string -> int t`
  (index of the chosen button). ocgtk binds `AlertDialog.show` but not the
  async `choose`; M3 uses `Gtk.Dialog`/`MessageDialog` + `on_response` if
  `choose` cannot be reached, and documents which.
- `File_dialog.open_file / save_file / select_folder : ... -> string option t`
- `Window.present / close / set_title : key:Key.t -> ...`

Asynchronous ones are built with `Ui_effect.Private.make`; the GLib callback
resolves the effect's callback, then `request_frame`.

M0 implements only `quit` (§4.5); the rest of this list is M3 scope (§7).

## 9. Testing

Three layers, each in its own dune directory so the pure/headless suites run
without a display:

1. **Pure** (`test/`, against `bonsai_gtk.vtree`): `Reconcile.diff` unit +
   property tests; `Attrs.diff`; `Node` sexp printing. ppx_expect.
2. **Headless app tests** (`test_lib/` = `bonsai_gtk_test`, ocgtk-free, used
   from `test/`): a `Bonsai_test.Result_spec` for `Node.t` whose `view` is the
   sexp tree and whose `incoming` actions are
   `Click of Key.t | Set_text of Key.t * string | Toggle of Key.t | Key_press of ...`,
   dispatched by locating the node by `test_id` and invoking its handler.
   `Handle.create`, `show`, `show_diff`, `do_actions`, `advance_clock_by`
   come from `Bonsai_test.Handle` unchanged. Apps that want headless tests
   keep their view functions in ocgtk-free libraries (depending on
   `bonsai_gtk.vtree` only) — same rule stavekeeper already follows.
3. **Live** (`test/live/`): runs under `xvfb-run`. Because ppx_expect cannot
   link against ocgtk, these are plain `(test)` executables that print
   `Live_tree.dump` (real widget type names, key props, child order)
   and are compared with `(diff expected.txt output.txt)` rules. They use
   `Expert.Driver` (`Driver.create`, `Driver.frame`, ...) and drive frames by hand. `scripts/ci.sh` runs
   them; the directory is `(enabled_if (= %{env:BONSAI_GTK_LIVE_TESTS=0} 1))`
   so plain `dune runtest` without a display stays green.

**M1 amendment (2026-08-29).** No test directory may straddle the two packages.
Each generated `.opam` runs `dune build -p <pkg> ... @runtest` under
`--with-test`, and `--only-packages` hides every library owned by another
package in the workspace — so a directory depending on `bonsai_gtk.vtree` *and*
`bonsai_gtk_test` fails whichever package is being built, while `dune build
@all` stays green. Layer 1 (`test/`, package `bonsai_gtk`) therefore depends on
`bonsai_gtk.vtree` alone, and the tests that exercise the handle live in
`test/handle/` (package `bonsai_gtk_test`). `scripts/ci.sh` runs both `-p`
builds; the second needs `bonsai_gtk` installed first, as opam installs it, so
the script installs it into a temporary prefix.

**M2 amendment (2026-08-30).** Layer 2 no longer certifies trees the runtime refuses. The
handle validates three things, and all three come from tables that live in `vtree` — which
is what lets `test_lib` consult them without depending on ocgtk:

- **`Events.for_kind`**, the `Kind.t -> Attr.Name.t list` table (exhaustive, no wildcard
  arm), so an `Attr.on_clicked` on a `Node.label` raises here exactly as
  `Signals.require_specs` raises it at mount. This closes the M1 hole where a headless suite
  went green on a tree whose first frame would raise.
- **`Placement.read_by`/`reader`**, so a placement attr on a container that does not read it
  raises here too, naming the container that does. This one matters more than it looks: a
  misplaced placement attr is applied by nobody and read by nobody, so without the check a
  headless suite is the *only* place it could ever have been caught, and it passed.
- **`Events.key_phase_rejection`**, so two key attrs asking for different propagation phases
  raise here as well.

Both sides call the same function for each message, so they are identical outright rather
than by convention. All three run on **every** entry point that advances a handle —
`show`, `show_into_string`, `show_diff`, `store_view`, `recompute_view`,
`recompute_view_until_stable` — which is why `Bonsai_gtk_test.Handle` is a hand-written
signature rather than an alias for `Bonsai_test.Handle`: the checks live in the
`Result_spec`'s `view`, and three of those six never built one. The first run of the fixed
version found a call site certifying a tree the runtime refuses. (`Handle.t` is still
`Bonsai_test.Handle.t`, so `Bonsai_test.Handle.recompute_view` typechecks and still skips
the check; making `t` abstract would cost the interop the four omitted values depend on.)

`Action.t` is now nineteen constructors: M1's five, nine more for the M2 signals
(`Search_changed`, `Set_expanded`, `Activate_row`, `Activate_child`, `Set_selection`,
`Set_page`, `Set_selected`, `Select_day`, `Set_editing`), and five for the controllers
(`Click_at`, `Key_press`, `Key_release`, `Focus_enter`, `Focus_leave`). `Key_press` prints
the `Key_response.t` the handler answered, because that half of a key press is a value GTK
reads synchronously and there is no GTK here.

**What layer 2 still cannot see** is the other half, and it is two halves. First, the
*structural* checks that need the widget implementations or a live tree: a `grid` child with
no `Attr.grid_cell`, a `stack` page with no `~key` or a `~visible_child` naming no page, two
stacks under one `~name`, a `stack_switcher` naming no stack, duplicate sibling keys, a
`Node.window` anywhere but the root. Second, *routing*: every action is delivered to one
node named by `Attr.test_id`, and there is no widget hierarchy for an event to travel
through — so a `Key_press` answering `Handled` does not stop a sibling from seeing the key,
a `Click_at` does not also reach the container that would have handled it, and
`~phase` (which decides only who sees a key *first*) has no effect here at all. Nor does the
live suite close that: the pinned binding can synthesise neither a click nor a key press, so
what the live tests assert is the plumbing on one side (`test/live/live_controllers.ml`,
which prints `armed=` on every line because an attached controller and one that would
actually call a handler are otherwise indistinguishable for an event nothing can deliver)
and the trampoline in the middle. Focus is the exception and is covered end to end.

## 10. Repository layout and packaging

```
flake.nix / flake.lock
dune-project                (lang dune 3.17); generate_opam_files
bonsai_gtk.opam             generated
bonsai_gtk_test.opam        generated
vtree/                      library bonsai_gtk.vtree (ocgtk-free)
src/                        library bonsai_gtk (runtime)
src/widgets/                one module per widget
test_lib/                   library bonsai_gtk_test (ocgtk-free)
test/                       pure expect tests (package bonsai_gtk)
test/handle/                headless expect tests (package bonsai_gtk_test; see §9)
test/live/                  xvfb tests (plain executables + diff rules)
examples/                   counter, todo, gallery (grows per milestone)
ocgtk-pin.json              the fork commit both opam and Nix pin (owner/repo/rev/hash)
scripts/setup-switch.sh     create ./_opam OxCaml switch, pin ocgtk to the fork commit, install deps
scripts/ci.sh               dune build @all; dune runtest; BONSAI_GTK_LIVE_TESTS=1 xvfb-run -a dune runtest test/live
.ocamlformat                profile=janestreet (as bonsai_term)
```

`flake.nix`:
- `devShells.default`: opam, pkg-config, gcc, gnumake, autoconf, gtk4, glib,
  graphene, pango, cairo, gdk-pixbuf, gobject-introspection, xvfb-run;
  `shellHook` activates `./_opam` if present. `ocamlformat` is not in the shell:
  it is installed into the opam switch by `scripts/setup-switch.sh`, so `dune
  fmt` uses the version `.ocamlformat` pins.
- `packages.ocgtk`: `buildDunePackage` from `fetchFromGitHub` at the fork
  commit in `ocgtk-pin.json`, nixpkgs OCaml, tests under xvfb — proves the
  pinned fork builds and passes ocgtk's own GC regression tests, independent
  of the opam switch.
- No `packages.bonsai_gtk`: documented limitation (Bonsai v0.18 is not in
  nixpkgs / not stock-OCaml buildable).

## 11. Error handling

- Structural misuse (non-window root, a `Node.window` anywhere *below* the
  root — a `GtkWindow` is a toplevel and cannot be parented — duplicate sibling
  keys, event attr on a widget that lacks the signal) raises `Invalid_argument`
  with the node path at mount/patch time — loud and early.
- **M1 amendment (2026-08-29).** "Mount/patch time" is literal, and so is "the
  node path". Duplicate sibling keys are checked by `Patcher.mount_list` as well
  as by `Reconcile.diff` — the reconciler only runs on a patch, so without the
  mount-time check a duplicate was accepted on the first frame and rejected on
  the second, which for a `Node.stack` means GTK had already been handed two
  pages under one name and `get_child_by_name` was already ambiguous. Both call
  sites are wrapped in the patcher's path-prefixing helper, as every other
  child-list rejection already was.
- **M1 amendment (2026-08-29).** "Mount/patch time" is literal:
  `Signals.require_specs` is called from `Patcher.mount` and again from
  `Patcher.patch` (guarded on the attrs having changed), because handlers are
  connected once at mount, so a patch that *adds* an unsupported event attr has
  no slot to fail on otherwise. Native nodes declare no specs, so any event attr
  on one is rejected (§6.6). M1 added two further families of structural
  message, all `Invalid_argument` and all prefixed with the node path:
  slot misuse — `slot <name> does not exist on <impl>`, `slot <name> has the
  wrong shape for <impl>`, `<impl>'s slots changed shape under an unchanged
  kind`, `node's children do not match <impl>'s shape` — and the stack name
  registry: `two Node.stacks are named "<name>" in one tree` (at mount, and
  identically when a patch renames a stack onto a name another stack holds), and
  a `stack_switcher`/`stack_sidebar` naming a stack no node declares. That last
  one is also what a rename onto a *free* name produces for a switcher still
  naming the old one — a renamed stack drops its old registration rather than
  answering to both. A subtree being replaced gives its registrations up before
  the replacement is mounted (§6.2), so re-declaring the same stack inside the
  replacement is not a collision.
- **M2 amendment (2026-08-30).** Six further families of structural message, all
  `Invalid_argument`, all raised at mount and at patch, and — where a tree exists to
  prefix one onto — all carrying the node path:
  - **A placement attr on a container that does not read it.** `Attr.grid_cell` on a box
    child, `Attr.page_title` on anything but a stack page, `Attr.row_selectable` on a flow
    box child. The message names the container that *does* read it, because a misplaced
    placement attr is nearly always a child that ended up in the wrong parent. The table
    (`vtree/placement.ml`) is exhaustive with a wildcard on the *container* side, so a
    container that reads none of them rejects all of them — which is what makes this a
    diagnostic rather than a list of exceptions.
  - **A `~visible_child` or `~current_page` naming no child**, from the fixup pass, listing
    the names the container does have. Carve-out: a container with *no* children is left
    inert, because a required argument leaves a model rendering an empty page list no name
    it could pass that would be right.
  - **A `list_box`, `flow_box`, `notebook` or `stack` child with no `~key`**, from the
    *constructor*, naming the child's index. This one carries no node path deliberately:
    the constructor runs before there is a tree, and the point of the mistake is the call.
  - **A `min > max` content bound on `Node.scrolled_window`**, plus the same family of
    constructor-time arithmetic rejections M2 added elsewhere: a negative
    `level_bar` bound or an inverted range, a `flow_box` `~max_children_per_line < 1` or a
    negative `~min_children_per_line`/spacing (GTK reads these as unsigned, so a negative
    one arrives as a very large positive one with no error), a `calendar`
    `~marked_days` entry outside 1–31, a `drop_down` `~selected < -1`.
  - **Two key attrs asking for different propagation phases**
    (`Events.key_phase_rejection`) — they share one `GtkEventControllerKey` and therefore
    one phase, so there is nothing the runtime could mount.
  - **A window root under `embed`, and a non-window root under `start`** (§4.1). Each
    message names the other entry point, because a caller who returned a window from an
    embedded computation wanted `start`.

  Every one of these is checked in `Bonsai_gtk_test` as well as at mount, except the
  structural half §9 lists — and the checks that are shared are shared as *functions*, not
  as duplicated strings.
- **M2 amendment (2026-08-30).** One rule that is not a message. **A GTK signal handler
  reached from OCaml's finaliser is a memory-safety bug**, not an inconvenience: ocgtk's
  finaliser unrefs the GObject, GTK disposes it, dispose emits `destroy`, and the
  marshaller calls back into OCaml from the collector — measured as a hang, and as a
  segfault when the callback allocates, with no bonsai_gtk involved at all. The rule is
  stated in `src/signals.mli`, the fork carries a guard that makes the emission a
  once-reported no-op rather than a crash, and `Embed.stop` disconnects its own `destroy`
  backstop for exactly this reason: `stop` is what makes the wrapper collectable, so a
  stopped-and-dropped embed's wrapper is precisely the one GTK will dispose from inside
  finalisation.
- Exceptions inside a signal trampoline are caught before they reach C
  (undefined behaviour otherwise), logged to stderr with the node path, and
  do not tear down the main loop.
- Exceptions inside a frame (flush/patch) are likewise caught before reaching C,
  but are *not* survivable: the frame is logged once and the driver stops for
  good (`Driver.broken`). A frame is not atomic — the patcher mutates GTK as it
  walks its ops and records what it did only on success — so a frame that dies
  part-way leaves the shadow tree describing a GTK tree that no longer exists,
  and every later frame would diff against it (wrong ordering at best, the same
  exception at tick rate at worst). The main loop keeps running so the window
  stays on screen at its last good state; nothing renders into it again, and
  `start` returns a non-zero status. The `in_patch` flag is reset in a
  `protect ~finally` either way.
- ocgtk unsupported signals are omitted at the API level, never silently
  no-op.
- **M2 amendment (2026-08-30).** Not every wrong value is a raise, and the line between
  them is now written down — in `vtree/node.mli`'s opening section, because it is not
  discoverable from a type. A constructor's `Invalid_argument` runs inside the Bonsai
  computation, so it comes out of `Driver.frame`, which marks the driver broken, abandons
  the pending fixups and re-raises: **every later frame is a no-op and the window never
  repaints again.** The rule the checks follow is therefore *reject only what no later
  frame could make valid*. A state a correct model passes *through* — a `drop_down`
  `~selected` past the end of a list that is about to grow, a `~selected` key whose row has
  not arrived — is not rejected: it is inert while it names nothing, applied on the frame it
  becomes meaningful, and reported once through `Patcher.ctx.report` with the node's path,
  so that a model which is *permanently* wrong is not silent either. The same channel
  carries the refuse-record-report cases of §6.5.
