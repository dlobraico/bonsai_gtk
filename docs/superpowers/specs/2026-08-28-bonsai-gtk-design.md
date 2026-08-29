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

### 4.2 Frame

A frame is, in order:

1. `Bonsai.Time_source.advance_clock time_source ~to_:(Time_ns.now ())`
   (skipped when a custom time source is supplied).
2. `Bonsai_driver.flush`.
3. `Bonsai_driver.result` → `Node.t`.
4. If the new root is not `phys_equal` to the last rendered root:
   `Patcher.patch` under the `in_patch` guard.
5. `Bonsai_driver.trigger_lifecycles`.
6. If `Bonsai_driver.has_after_display_events`, request another frame.

Frames run only from the GLib main loop, never synchronously inside a signal
handler.

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
  `Clock.sleep`, `Clock.now`. When nothing changed, flush is a no-op and the
  patch is skipped by the `phys_equal` check, so an idle tick costs one
  stabilization. Suspending the tick while idle is a noted future
  optimization, not part of this design.
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

### 5.3 Children shapes

Fixed per kind, encoded in constructor arguments:

| Shape | Widgets | Live operations |
|---|---|---|
| `None` | Label, Entry, Switch, ... | — |
| `Single` | Window, ScrolledWindow, Frame, Expander, Revealer, Button(child), ... | `set_child (Some w)` / `set_child None` |
| `List` (keyed, ordered) | Box, ListBox, FlowBox, Stack, Notebook | `append` / `insert_child_after` / `reorder_child_after` / `remove`, or the widget's page API |
| `Slots` (named) | HeaderBar (`start`/`title`/`end`), Paned (`start`/`end`), Overlay (`child` + `overlays`), CenterBox, Grid (`attach` coords), ActionBar | per-slot single/list patch |

### 5.4 Keys

`Key.t = string`. A node without a key is matched by position + kind. A keyed
node is matched by key within its sibling list; a key appearing twice among
siblings is an error at patch time. Keys are what preserve widget state
(focus, entry text, scroll position) across reorders.

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
Signals ocgtk does not generate as `on_*` but which GLib can deliver through
the generic marshaller — the `notify::<prop>` family (`Switch` `active`,
`DropDown` `selected`, `Revealer` `child-revealed`) — are connected with
`Gobject.Signal.connect_simple obj ~name:"notify::active"` and read the value
back with the class getter. Key and pointer events come from
`Event_controller_key` / `Gesture_click` / `Event_controller_motion` attached
to the widget. Signals ocgtk cannot bind at all (boxed-record or out
parameters) are omitted from the API and listed in the widget's doc comment.

### 6.5 Controlled text widgets

`Entry`, `SearchEntry`, `PasswordEntry`, `EditableLabel`, `TextView`:
`update` sets the widget text only when it differs from the widget's *current*
text (not the previous node's), so a model that echoes what the user typed
causes no caret jump, while a model that rewrites input (e.g. uppercasing)
still wins.

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
- **M1 — core & layout:** Button, ToggleButton, CheckButton, Switch, Entry,
  PasswordEntry, SearchEntry, SpinButton, Scale, ProgressBar, Spinner,
  Image, Picture, Separator, ScrolledWindow, Frame, Expander, Grid,
  CenterBox, Paned, Overlay, Revealer, Stack + StackSwitcher + StackSidebar,
  `Node.native`.
- **M2 — lists & text:** ListBox (keyed rows, selection), FlowBox, Notebook,
  TextView (controlled buffer), DropDown (string list), LevelBar, Calendar,
  EditableLabel.
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
filtering are done in the Bonsai model (the GTK callbacks are unbound);
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
test/                       pure + headless expect tests
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
