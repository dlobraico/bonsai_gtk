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

