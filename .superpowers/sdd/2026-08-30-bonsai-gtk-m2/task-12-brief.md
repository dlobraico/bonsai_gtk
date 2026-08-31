### Task 12: `Expert.embed` — a bonsai tree inside a container someone else owns

The entry point that makes the stavekeeper port incremental. `Bonsai_gtk.start` is unchanged and stays the answer for an application that is bonsai_gtk all the way down.

**Files:**
- Modify: `src/bonsai_gtk.ml`, `src/bonsai_gtk.mli`, `src/driver.ml`, `src/driver.mli`, `src/patcher.ml`, `test/live/dune`
- Create: `src/embed.ml`, `src/embed.mli`, `test/live/live_embed.ml`, `test/live/expected_embed.txt`

**Interfaces:**
- Produces:
  ```ocaml
  (* Bonsai_gtk.Expert *)
  module Embedded : sig
    type t
    val widget : t -> Widget.t
    val frame : t -> unit
    val schedule_event : t -> unit Ui_effect.t -> unit
    val broken : t -> bool
    val stop : t -> unit
  end

  val embed
    :  ?time_source:Bonsai.Time_source.t
    -> ?optimize:bool
    -> ?target_frames_per_second:float
    -> host:Widget.t
    -> (local_ Bonsai.graph -> Node.t Bonsai.t)
    -> Embedded.t
  ```
- Changed: `Driver.create` gains `?root_may_be_window:bool` (or equivalent — see the ruling), and `Patcher.mount`'s `~is_root` grows a meaning.

**Six questions the entry point has to answer, and the answers this plan rules on:**

1. **What is a legal root?** For `start`, exactly a `Node.window` (spec §11). For `embed`, exactly **not** a `Node.window`: a `GtkWindow` is a toplevel and cannot be parented, so embedding one would produce the GTK critical §11 exists to prevent. So the root check inverts rather than relaxes, and the message says which entry point the caller wanted:

```
Bonsai_gtk.embed: the root node is a Node.window, but an embedded tree is
parented into ~host and a GtkWindow is a toplevel that cannot be parented. Use
Bonsai_gtk.start for a tree that owns its window, or make the root a container.
```

The below-the-root rule is unchanged: a `Node.window` anywhere but the root is still `Invalid_argument`, and for an embedded tree that means anywhere at all. Implement it as a `root_kind : [ \`Window | \`Not_window ]` argument to `Driver.create` rather than a bool, so the two messages are written once each and neither entry point can pass the wrong one silently.

2. **Who parents the widget?** The caller. `embed` mounts the tree and hands back the root widget through `Embedded.widget`; the host is *not* written to. This is deliberate and is what makes `embed` composable with a `GtkStack` (`add_named` returns a page), a `GtkBox` (`append`), a `GtkNotebook` (`insert_page`) and a `GtkListBox` (`insert`) alike, none of which is `set_child`. **Then why does `embed` take `~host` at all?** Because the driver needs a widget to hang the frame tick's lifetime on and to answer "am I still in a tree" — and because a future `Attr` that names an ancestor (a search entry's key-capture widget, a mnemonic target) will need it. If Step 3 finds neither use is real yet, **drop `~host` and say so in the report**: an unused argument in a new public entry point is worse than adding it in M3.

3. **What drives frames?** Not `Bonsai_gtk.start`'s `GtkApplication`, which the embedder owns. `embed` installs its own tick with `Driver.start_tick ~fps:target_frames_per_second` (default 60) on the GLib main loop the embedder is already running, and `Embedded.frame` lets a test drive by hand. If there is no main loop running, the tick simply never fires and `Embedded.frame` is the only path — which is exactly what `test/live/live_embed.ml` does, and it is worth stating because it is how a headless-ish live test of an embedded tree works.

4. **When does `require_specs` run?** Unchanged — at mount and at each patch, from the patcher, for every node including the root. Nothing about embedding changes what a node may carry.

5. **What does teardown do?** `Embedded.stop` tears the widget tree down and invalidates the Bonsai observers, exactly as `Driver.stop` does — **but it does not unparent the root widget**, because it did not parent it. The embedder removes it from its container, before or after `stop`, and the mli says so with the order that is safe (either; the widget survives `stop` as a plain unparented `GtkWidget` and the embedder may drop it on the floor, since nothing holds a reference). Stavekeeper's `shell.ml:87` already does `t.stack#remove viewer.widget` after `viewer.teardown ()`, which is the shape.

6. **What happens if the embedder destroys the host first?** GTK destroys the subtree with it, and the shadow tree then describes widgets that are gone. There is no way to detect this cheaply and no good behaviour to fall back on, so: `Embedded.stop` must be called before the host goes away, and calling a frame afterwards is undefined in the way any use-after-destroy is. Say that in the mli, plainly, as the one obligation embedding puts on the caller that `start` does not. If `Widget.on_destroy` is bound (check — the M2 signature survey says `on_destroy` exists on `Widget`), connect to the *root* widget's `destroy` and mark the embedded driver broken from it; that turns undefined behaviour into a no-op and is worth the one connection. Do that if it is a handful of lines, and say in the report which you did.

- [ ] **Step 1: Write the failing test** (`test/live/live_embed.ml`)

```ocaml
(* An embedded tree inside a container the test owns, which is what stavekeeper's Shell
   is: a GtkStack that holds pages, none of which is a window. *)
let () =
  ignore (Ocgtk_gtk.GMain.init () : string array);
  let window = W.Window.new_ () in
  let stack = W.Stack.new_ () in
  W.Window.set_child window (Some (stack :> Widget.t));
  let clicks = ref 0 in
  let app (graph @ local) =
    let n, set_n = Bonsai.state 0 graph in
    let%arr n and set_n in
    (* No Node.window: the root is a box, which is what an embedded tree must be. *)
    Node.box ~orientation:Vertical
      [ Node.label (sprintf "count %d" n)
      ; Node.button ~attrs:[ Attr.on_clicked (set_n (n + 1)) ] ~label:"+" ()
      ]
  in
  let embedded = Bonsai_gtk.Expert.embed ~host:(stack :> Widget.t) app in
  ignore (W.Stack.add_named stack (Bonsai_gtk.Expert.Embedded.widget embedded) (Some "page")
          : W.Stack_page.t);
  print_s (Live_tree.dump (window :> Widget.t));
  (* A frame driven by hand, because this test runs no main loop. *)
  Bonsai_gtk.Expert.Embedded.frame embedded;
  print_s (Live_tree.dump (window :> Widget.t));
  (* The root really is inside the stack, not a sibling toplevel: the dump above says so
     structurally, which is the point of dumping from the *window* rather than from the
     embedded root. *)
  ...
  (* A window root is refused, with a message naming [start]. *)
  (match Bonsai_gtk.Expert.embed ~host:(stack :> Widget.t)
           (fun (_ : local_ Bonsai.graph) -> Bonsai.return (Node.window ~title:"no" (Node.label "x")))
   with
   | _ -> printf "window root: NO RAISE\n"
   | exception Invalid_argument m -> printf "window root: %s\n" m);
  (* Teardown leaves the host alone. *)
  Bonsai_gtk.Expert.Embedded.stop embedded;
  printf "after stop, stack still has %d children\n" (n_children stack);
  W.Stack.remove stack (...);
  printf "removed cleanly\n"
```

The `after stop` line is the interesting one: it must be `1`, because `stop` does not unparent. If the implementation unparents, this catches it.

- [ ] **Step 2: Run to verify failure** — unbound `Bonsai_gtk.Expert.embed`.

- [ ] **Step 3: `src/driver.ml(i)`** — the root-kind argument, and nothing else. `check_root` gains the two messages. Confirm that `Driver.create`'s existing callers (there is one, in `bonsai_gtk.ml`) pass `` `Window ``.

- [ ] **Step 4: `src/embed.ml(i)`** — thin. It is `Driver.create` + `Driver.frame` (once, to mount) + `Driver.start_tick`, wrapped in a record that exposes four of the driver's operations and hides `root_widget` (whose `option` is meaningless once the first frame has run) behind a total `widget`.

```ocaml
(** A Bonsai computation rendering into a widget the caller parents.

    The counterpart to {!Bonsai_gtk.start}, for an application that already has a GTK main
    loop and a window and wants a Bonsai-rendered subtree inside it — porting a screen at
    a time rather than all at once, or embedding a declarative panel in an imperative app.

    Three things differ from {!Bonsai_gtk.start}, and all three follow from "the caller owns
    the window":

    - The root node must {i not} be a [Node.window]: the result is parented into an
      existing container, and a [GtkWindow] is a toplevel that cannot be parented. (A
      [Node.window] below the root is rejected as it always is, which for an embedded tree
      means anywhere.)
    - Nothing is parented for you. {!widget} is the root, and the caller puts it wherever
      its container puts children — [set_child], [append], [add_named], [insert_page]. That
      is why there is no "attach" here: there is no one call that covers them.
    - {!stop} tears the tree down but does not unparent it. Remove it from your container
      yourself, before or after; the widget survives {!stop} as an ordinary unparented
      widget and may then be dropped.

    The one obligation embedding adds: {!stop} before the host is destroyed. GTK destroys a
    subtree with its parent, and a frame after that would diff against widgets that are
    gone. [embed] connects to the root's [destroy] and marks itself broken if it happens
    anyway, so the failure is a no-op rather than a crash — but the frames between the
    destroy and the next tick are wasted and the effects they queue are dropped. *)
```

- [ ] **Step 5: `src/bonsai_gtk.ml(i)`** — `Expert` gains `module Embedded` and `val embed`, with the mli doc pointing at `Embed`'s. Keep `Expert.Driver` exposed: `embed` is a convenience over it, not a replacement, and the existing live tests use `Driver` directly.

- [ ] **Step 6: Run, read, promote, gate, commit**

```bash
./scripts/ci.sh
dune fmt 2>/dev/null; git add src test
GIT_EDITOR=true git commit -F - <<'MSG'
Expert.embed: a Bonsai subtree inside a container the caller owns

The entry point that makes an incremental port possible -- an existing GTK app
with its own main loop and window can render one page with Bonsai and keep the
rest imperative. The root must not be a Node.window (an embedded tree is
parented, and a GtkWindow cannot be), nothing is parented for the caller
(add_named, append and set_child are not one call), and stop tears the tree
down without unparenting it.

Bonsai_gtk.start is unchanged.

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01Sg3Ci8U8kUKR8C3PL1pNSs
MSG
```

**Review focus:** that the window-root rejection names `start` in its message; that `stop` does not unparent and there is a test that would notice; that `~host` is used for something or was dropped; that the destroy-the-host-first obligation is in the mli and not only here; that `Driver`'s existing behaviour is unchanged for `start` (its live tests must not diff).

---

