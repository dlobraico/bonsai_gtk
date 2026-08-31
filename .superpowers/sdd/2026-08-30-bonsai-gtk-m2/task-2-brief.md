### Task 2: What a patch does — the phys-equal walk, the unordered marker, the batch cost, `w_switch`

Four backlog items, all about the patch path, and all cheaper to do before eight widgets are built on top of them.

**Files:**
- Modify: `vtree/reconcile.ml`, `vtree/reconcile.mli`, `src/widget_impl.ml`, `src/widget_impl.mli`, `src/patcher.ml`, `src/patcher.mli`, `src/driver.ml`, `src/driver.mli`, `src/widgets/w_stack.ml`, `src/widgets/w_grid.ml`, `src/widgets/w_overlay.ml`, `src/widgets/w_box.ml`, `src/widgets/w_switch.ml`, `test/test_reconcile.ml`, `test/live/live_containers.ml`, `test/live/live_driver.ml`
- Create: nothing

**Interfaces:**
- Changed:
  ```ocaml
  (* Reconcile *)
  val diff
    :  ?ordered:bool  (** default [true] *)
    -> key:('a -> Key.t option)
    -> same_kind:('a -> 'a -> bool)
    -> old:'a list
    -> new_:'a list
    -> 'a op list

  (* Widget_impl *)
  type list_ops =
    { insert : Widget.t -> after:Widget.t option -> node:Node.t -> Widget.t -> unit
    ; move : (Widget.t -> child:Widget.t -> after:Widget.t option -> unit) option
    ; remove : Widget.t -> Widget.t -> unit
    ; updated : Widget.t -> old:Node.t -> node:Node.t -> Widget.t -> unit
    }

  val batch_if : bool -> Widget.t -> (unit -> unit) -> unit

  (* Patcher *)
  val reassert_only : ctx -> live -> unit
  ```
- Unchanged: everything else. `Reconcile.apply` keeps its meaning; the op type does not change.

**Why `move` becomes an option rather than a `bool` beside it.** M1's ruling 4 deferred this pending a container with a real reorder; Notebook (Task 8) is that container. Two facts have to stay in step — "this container can reorder" and "here is how" — and a `bool` field next to a `move` function lets them disagree. An `option` makes the illegal states unrepresentable: `None` *is* the marker, and the patcher cannot call a `move` that a container does not have. `Overlay`, `Stack` and `Grid` take `None`; `Box` and (in Task 8) `Notebook` take `Some`.

The patcher then passes `~ordered:(Option.is_some move)` to `Reconcile.diff`, and `diff` emits no `Move` ops at all for an unordered list. That is strictly better than M1's no-op `move`: the ops the reconciler produces and the ops the patcher can apply are the same set, so the `cur` bookkeeping never records a move that did not happen, and a reader of a `Reconcile.diff` sexp in a test is not looking at ops that are silently discarded.

**What `?ordered:false` must and must not change.** It drops the `Move` ops. It must not change which items are *matched* — matching is by key, and an unordered container's children still have keys and still preserve identity across a reorder. Concretely: for `old = [a; b; c]`, `new_ = [c; a; b]`, ordered gives `Move` ops plus three `Update`s; unordered gives three `Update`s and nothing else, in `new_`'s order. The children stay where GTK put them; only the paint or tab order goes unreconciled, which is what spec §5.3 already documents for those three.

- [ ] **Step 1: Write the failing tests**

`test/test_reconcile.ml` — append:

```ocaml
let%expect_test "an unordered diff matches by key but emits no Move" =
  let item k = k in
  let diff ?ordered old new_ =
    Reconcile.diff
      ?ordered
      ~key:(fun k -> Some k)
      ~same_kind:(fun _ _ -> true)
      ~old:(List.map old ~f:item)
      ~new_:(List.map new_ ~f:item)
  in
  print_s [%sexp (diff [ "a"; "b"; "c" ] [ "c"; "a"; "b" ] : string Reconcile.op list)];
  [%expect {| |}];
  print_s
    [%sexp
      (diff ~ordered:false [ "a"; "b"; "c" ] [ "c"; "a"; "b" ] : string Reconcile.op list)];
  [%expect {| |}];
  (* Removals and insertions are unaffected: an unordered container still adds and drops
     children, it just cannot say where. *)
  print_s
    [%sexp
      (diff ~ordered:false [ "a"; "b" ] [ "b"; "c" ] : string Reconcile.op list)];
  [%expect {| |}]
;;
```

`test/live/live_driver.ml` — the phys-equal walk. This is the test that says the optimisation did not break the thing M1's comment refused to break:

```ocaml
  (* Bonsai handing back the *physically same* node must still put a declined edit back.
     M1 paid a full tree walk for this; the walk is now reassert-and-fixups only, and this
     is what says the two are equivalent where it matters.

     The node is built once and returned by reference, which is what a Bonsai computation
     whose state did not change does. Then the widget is changed behind the driver's back,
     the way a user does, and one frame must undo it. *)
  let view = Node.window ~title:"phys" (Node.switch ~attrs:[ ... ] ~active:false ()) in
  let d = Driver.create ~on_window_created:(fun _ -> ()) (fun (_ : local_ Bonsai.graph) ->
    Bonsai.return view)
  in
  Driver.frame d;
  printf "after mount: %b\n" (switch_active d);
  set_switch_active d true;              (* the user flips it *)
  printf "after the user flipped it: %b\n" (switch_active d);
  Driver.frame d;                        (* same node, reassert-only walk *)
  printf "after the declining frame: %b\n" (switch_active d);
```

Expected: `false`, `true`, `false`. And the same shape for a stack whose `~visible_child` the user navigated away from with a switcher click, which exercises the *fixup* half rather than the `reassert` half — that one is the reason the walk cannot be "call `reassert` and stop".

- [ ] **Step 2: Run to verify failure** — `dune build @test/runtest` → unknown labelled argument `?ordered`.

- [ ] **Step 3: `vtree/reconcile.ml(i)`**

Add `?(ordered = true)` and, at the single point where a matched pair's position change emits a `Move`, guard it. The mli gains:

```ocaml
    [ordered] is [false] for a container GTK gives no reorder primitive for — an
    overlay, a stack, a grid. Matching is unaffected (identity is by key either way, and
    state still survives a reorder); what changes is that no [Move] is emitted, because
    the patcher would have nothing to apply it with. Emitting one and discarding it is
    worse than not emitting it: the discarded op is still counted in the patcher's index
    bookkeeping, and it shows up in a test's [op list] as though something happened.
```

- [ ] **Step 4: `src/widget_impl.ml(i)` — `move` becomes an option, and `batch_if`**

The doc on `move` is rewritten:

```ocaml
  ; move : (Widget.t -> child:Widget.t -> after:Widget.t option -> unit) option
  (** Move a child already in the container to sit directly after [after] ([None] =
      first). [after] is computed over the sibling list with [child] already taken out of
      it, which is the order GTK's [reorder_child_after] expects.

      [None] means this container has no reorder primitive — [GtkOverlay], [GtkStack] and
      [GtkGrid] have none — and is not a no-op but a *marker*: the patcher passes
      [~ordered:false] to [Reconcile.diff], which then emits no [Move] at all. Keys still
      preserve identity; children stay in the order they were first added, and for a stack
      or a grid that order is invisible anyway (a grid's placement is its
      {!Bonsai_gtk_vtree.Attr.grid_cell}). *)
```

and `batch_if`:

```ocaml
val batch_if : bool -> Widget.t -> (unit -> unit) -> unit
(** [batch_if writes w f] is {!batch} when [writes], and [f ()] otherwise.

    For [reassert], which runs on every patch of every node of its kind — including the
    overwhelming majority that write nothing — and which was paying a
    [freeze_notify]/[thaw_notify] pair each time. The caller decides [writes] by the same
    comparison it was about to make anyway: [reassert] for a single-prop kind computes
    "does the widget already hold this" first, and brackets only when the answer is no.

    A [reassert] that writes two or more props still has to bracket before the first
    write, so its [writes] is the disjunction of its per-prop comparisons. Getting that
    wrong is a correctness bug (an unbracketed multi-prop write emits a [notify::] per
    setter), so a kind with several controlled props should prefer plain {!batch} unless
    the saving was measured. *)
```

- [ ] **Step 5: `src/widgets/*.ml` — the four containers, and `w_switch`**

`w_box.ml`: `move = Some (fun parent ~child ~after -> W.Box.reorder_child_after (cast parent) child after)`.
`w_stack.ml`, `w_grid.ml`, `w_overlay.ml`: `move = None`, and each one's existing "this is a documented no-op" comment becomes "this container is unordered; see `Widget_impl.list_ops.move`".

`w_switch.ml`'s `create` currently hand-writes `active`. Route it through `reassert` instead, so the controlled prop has exactly one implementation:

```ocaml
let reassert w (kind : Kind.t) =
  match kind with
  | Switch p ->
    let s : W.Switch.t = cast w in
    let writes = not (Bool.equal (W.Switch.get_active s) p.active) in
    Widget_impl.batch_if writes w (fun () -> if writes then W.Switch.set_active s p.active)
  | k -> Widget_impl.wrong_kind "Switch" k
;;
```
and `create` ends with `reassert w kind` rather than its own `set_active`. Two consequences worth stating in a comment: the widget is created inactive and then written, which is one extra property write on the create path for an initially-active switch, and it is the same write the patcher would have made on the next frame; and `create` runs *outside* the patch guard on the very first mount, so the `notify::active` it emits is real — harmless, because the slots are empty until `Signals.update_slots` runs, which is after `create`. Confirm that ordering in `Patcher.mount` before writing the comment.

Do the same audit for every other kind with a `reassert` — `w_entry`, `w_password_entry`, `w_search_entry`, `w_toggle_button`, `w_check_button`, `w_spin_button`, `w_scale`, `w_expander`, `w_revealer` — and convert each unconditional `Widget_impl.batch` in `reassert` to `batch_if`. Where the kind has one controlled prop this is mechanical. `w_entry` is the interesting one: `set_text_if_needed` already returns whether it wrote, but the bracket has to be *outside* the decision, so restructure to compare first (`String.equal (W.Editable.get_text e) text`), then `batch_if`, then write.

If the pre-flight scan's timing says `freeze_notify`/`thaw_notify` on an unchanged object is free, skip this step entirely, delete `batch_if`, and record the measurement in the task report. Do not add an abstraction to avoid a cost that is not there.

- [ ] **Step 6: `src/patcher.ml` — `enqueue_fixups`, and `reassert_only`**

Factor the kind-keyed fixup dispatch (currently inline in `mount` and again in `patch`) into one function, because a third caller is about to need it:

```ocaml
(* What a node of this kind wants done once the whole pass is over: a stack selecting a
   page that does not exist while the stack is being built, a switcher resolving the stack
   it names. Called from [mount], from [patch], and from [reassert_only] -- the last is
   why it is a function rather than two copies: a frame that skips the walk must still
   re-apply the selections, since a selection is a controlled prop and the frame that
   declines a navigation is exactly the frame where nothing else moved. *)
let enqueue_fixups ctx ~path (live : live) = ...
```

and add the walk:

```ocaml
(** Re-applies every controlled prop in the tree and re-runs the pass's fixups, without
    diffing anything.

    For the frames on which Bonsai hands back the physically same node it handed back last
    frame. Nothing in the tree can have changed — it is the same value — so there is no
    [update] to run, no [Attrs.diff] to compute and no child list to reconcile. What there
    still is, and what M1's full walk was really paying for, is the two halves of the
    controlled-prop rule: [Widget_impl.reassert] and the selection fixups. A model that
    *declines* a user's edit renders the same value it rendered last frame, so this is
    precisely the frame on which the widget has to be put back. Skipping it entirely — the
    obvious optimisation, and the one [Driver.frame_body]'s comment refused — leaves the
    declined edit standing on screen.

    Does not touch [live.node] (it is already the node), does not run [require_specs] (the
    attrs are the same values), and does not run lifecycles. Raises what a [reassert]
    raises. *)
let rec reassert_only ctx (live : live) =
  Option.iter live.impl.reassert ~f:(fun f -> f live.widget live.node.kind);
  enqueue_fixups ctx ~path:live_path live;
  Children.iter live.children ~f:(reassert_only ctx)
;;
```

Note the path: `enqueue_fixups` wants one for its error messages. `live` does not carry its path today (the backlog's "node paths are frozen at mount" item is about this). Either thread `~path` through the recursion the way `mount`/`patch` do — cheap, and what this plan assumes — or add a `path` field to `live`. Prefer threading; adding the field is a bigger change than this task should make and the backlog item that would justify it is about staleness after a move, which threading also fixes for this walk.

- [ ] **Step 7: `src/driver.ml(i)`**

In `frame_body`, replace the "every frame patches" comment's *conclusion* while keeping its reasoning, and branch:

```ocaml
  check_root node;
  Scheduler.with_patch_guard t.scheduler (fun () ->
    match t.root with
    | Some live when phys_equal node live.node ->
      (* Bonsai handed back the same value. Nothing to diff -- but the controlled props
         still have to be re-asserted, because the frame on which the model declines a
         user's edit is exactly the frame on which its view did not change. See
         [Patcher.reassert_only]. *)
      Patcher.reassert_only t.patcher_ctx live;
      Patcher.run_fixups t.patcher_ctx
    | _ ->
      t.root <- Some (... the existing mount-or-patch ...);
      Patcher.run_fixups t.patcher_ctx)
```

The comparison is against `live.node`, which `patch` writes back. Confirm from the pre-flight scan that `patch` assigns `live.node <- node` and that a frame which raised does not leave a stale one (it does not: the driver is broken and never runs another frame).

`driver.mli` on `frame` gains: "A frame on which the computation returns the physically same node as the previous frame does not diff: it re-asserts the tree's controlled props and re-runs its fixups, which is the whole of what a no-change frame ever did. This is what makes an idle tick nearly free."

- [ ] **Step 8: Run, read, promote**

Every existing `expected_*.txt` must be **unchanged**. This task is a refactor plus an optimisation; a diff in `expected_containers.txt` means the unordered marker changed a placement, which it must not. If `live_containers.ml`'s overlay or stack section diffs, re-read Step 3 — the likeliest bug is dropping `Move` *and* the matching that produced it.

Add to `live_containers.ml` the case the marker exists for: an overlay whose three keyed children are rendered in a new order, twice, asserting the dump is identical both times *and* that each child is the same GObject (compare `Gobject.same` against handles taken before the patch). That is the claim "keys still preserve identity" and it had no test.

- [ ] **Step 9: Full gate + commit**

```bash
./scripts/ci.sh
dune fmt 2>/dev/null; git add vtree src test
GIT_EDITOR=true git commit -F - <<'MSG'
Unordered containers, cheaper reasserts, and a no-diff frame that still reasserts

[list_ops.move] is an option: [None] is the marker for a container GTK gives no
reorder primitive for, and [Reconcile.diff ~ordered:false] then emits no [Move]
at all rather than emitting one for the patcher to discard. Overlay, Stack and
Grid take it; Notebook (M2) will not.

A frame on which Bonsai returns the physically same node takes a
reassert-and-fixups-only walk instead of a full diff. M1 paid the full walk
deliberately, because that frame is exactly the one on which a declined edit has
to be put back -- so the new walk does both halves of that (reassert and the
selection fixups) and nothing else.

[Widget_impl.batch_if] stops every controlled kind from bracketing a
freeze/thaw around the patches that write nothing, and [w_switch] now creates
through its own [reassert] like every other controlled kind.

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01Sg3Ci8U8kUKR8C3PL1pNSs
MSG
```

**Review focus:** that `?ordered:false` changed matching in no way (read the diff of `Reconcile.diff` line by line); that `reassert_only` really does run the fixups and not only the reasserts — the stack case in `live_driver.ml` is the test that says so, and it should fail if the `enqueue_fixups` call is deleted; that `batch_if`'s `writes` argument is the disjunction of the comparisons in every multi-prop `reassert` that uses it; that `w_switch.create` calling `reassert` cannot fire a handler (slots are empty until after `create`).

---

