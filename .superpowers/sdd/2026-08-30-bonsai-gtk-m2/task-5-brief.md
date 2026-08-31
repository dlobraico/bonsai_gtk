### Task 5: Key controllers — the `bool` return, phases, and a keyval table `vtree` can name

The second controller family, and the one that forced `Payload`'s `'r`. Stavekeeper cannot port a single dialog without it (`dialog.ml:37-51`), and the shell's Ctrl+W / Ctrl+Return routing (`shell.ml:264-296`) is the same shape.

**Files:**
- Modify: `vtree/attr.ml`, `vtree/attr.mli`, `vtree/events.ml`, `vtree/bonsai_gtk_vtree.ml`, `src/controllers.ml`, `src/gtk_import.ml`, `src/bonsai_gtk.ml(i)`, `test_lib/bonsai_gtk_test.ml(i)`, `test/test_attrs.ml`, `test/handle/test_handle.ml`, `test/live/live_controllers.ml`, `test/live/dune`
- Create: `vtree/keyval.ml`, `vtree/keyval.mli`, `vtree/key_event.ml`, `vtree/key_response.ml`, `test/live/live_keyvals.ml`, `test/live/expected_keyvals.txt`

**Interfaces:**
- Produces:
  ```ocaml
  (* vtree/key_response.ml *)
  type t =
    | Propagate
    | Handled
    | Propagate_and of unit Ui_effect.t
    | Handled_and of unit Ui_effect.t

  (* vtree/key_event.ml *)
  type t = { keyval : int; keycode : int; modifiers : Modifiers.t } [@@deriving sexp_of]

  (* vtree/keyval.mli — X11 keysyms, as ints *)
  val escape : int
  val return : int
  val kp_enter : int
  val tab : int
  val iso_left_tab : int
  val space : int
  val backspace : int
  val delete : int
  val up : int
  val down : int
  val left : int
  val right : int
  val home : int
  val end_ : int
  val page_up : int
  val page_down : int
  val slash : int
  val f : int -> int          (* f 1 .. f 12 *)
  val of_char : char -> int

  (* Attr *)
  val on_key_pressed : ?phase:Phase.t -> (Key_event.t -> Key_response.t) -> t
  val on_key_released : ?phase:Phase.t -> Key_event.t Handler.t -> t
  ```
- Consumes: `W.Event_controller_key.{new_,on_key_pressed,on_key_released}`, `W.Event_controller.set_propagation_phase`, `Gdk_constants.{key_*,event_stop,event_propagate}`.

**Why `on_key_pressed`'s handler is not a `Handler.t`.** Every other event attr's handler is `'a -> unit Ui_effect.t`, because every other event is something that already happened. A key press is a *question* — GTK asks "did anything handle this?" and routes accordingly, on the C stack, before the frame that would answer it. So the handler is `Key_event.t -> Key_response.t`: the decision is a pure function of the event, and the effect (if any) rides along. This is what stavekeeper writes by hand today and it is the only shape that can be both synchronous and declarative.

Four constructors rather than two, because all four combinations are wanted and each reads plainly at the call site:

| | schedules nothing | schedules an effect |
|---|---|---|
| **GTK keeps routing** | `Propagate` | `Propagate_and eff` |
| **GTK stops** | `Handled` | `Handled_and eff` |

`Propagate_and` is the one a reader will ask about: it is for observing a key without consuming it — a "last activity" timestamp, a type-to-search that forwards to a search entry, `viewer_window.ml`'s auto-repeat suppression on key *release*. Without it, an observer would have to lie about handling the key.

**`vtree/keyval.ml` hard-codes X11 keysyms, and a live test pins them.** `vtree` may not link ocgtk, so it cannot read `Gdk_constants`; and an application that keeps its view functions ocgtk-free (which is the whole point of the vtree/runtime split, and what stavekeeper already does) needs to name Escape. The values are X11 keysyms, unchanged since 1987, and stavekeeper already hard-codes `0xff1b` for Escape in `dialog.ml:4`. What makes this safe rather than merely likely-safe is `test/live/live_keyvals.ml`, which asserts every entry against `Ocgtk_gdk.Gdk_constants.key_*`. Write that test **first**; if a single value disagrees, the whole approach is suspect and the fallback (expose the raw int and make applications depend on `bonsai_gtk` for the constants, losing the ocgtk-free view library) needs the controller's ruling.

- [ ] **Step 1: Write the failing tests**

`test/live/live_keyvals.ml`:

```ocaml
open! Core
open Bonsai_gtk_vtree
module K = Ocgtk_gdk.Gdk_constants

(* [vtree/keyval.ml] hard-codes X11 keysyms because [vtree] cannot link ocgtk. This is
   what makes that safe: every constant, checked against the binding. A mismatch here is
   not a test failure to promote past -- it means an application matching on
   [Keyval.escape] would silently never match. *)
let check name ours theirs =
  if ours <> theirs then printf "MISMATCH %s: vtree=%#x gdk=%#x\n" name ours theirs
;;

let () =
  check "escape" Keyval.escape K.key_escape;
  check "return" Keyval.return K.key_return;
  check "kp_enter" Keyval.kp_enter K.key_kp_enter;
  check "tab" Keyval.tab K.key_tab;
  check "iso_left_tab" Keyval.iso_left_tab K.key_iso_left_tab;
  check "space" Keyval.space K.key_space;
  check "backspace" Keyval.backspace K.key_backspace;
  check "delete" Keyval.delete K.key_delete;
  check "up" Keyval.up K.key_up;
  check "down" Keyval.down K.key_down;
  check "left" Keyval.left K.key_left;
  check "right" Keyval.right K.key_right;
  check "home" Keyval.home K.key_home;
  check "end" Keyval.end_ K.key_end;
  check "page_up" Keyval.page_up K.key_page_up;
  check "page_down" Keyval.page_down K.key_page_down;
  check "slash" Keyval.slash K.key_slash;
  check "f1" (Keyval.f 1) K.key_f1;
  check "f12" (Keyval.f 12) K.key_f12;
  (* [of_char] is the claim that an ASCII printable's keysym is its codepoint, which is
     what makes [Keyval.of_char 'w'] a legitimate way to spell Ctrl+W. Check both ends of
     the range and a couple in the middle rather than asserting it in a comment. *)
  check "of_char a" (Keyval.of_char 'a') K.key_a;
  check "of_char z" (Keyval.of_char 'z') K.key_z;
  check "of_char A" (Keyval.of_char 'A') K.key_A;
  check "of_char 0" (Keyval.of_char '0') K.key_0;
  check "of_char w" (Keyval.of_char 'w') K.key_w;
  printf "keyvals agree\n"
;;
```

The expected file is one line. Check the exact spellings of `K.key_A` and `K.key_0` in `gdk_constants.mli` first — the generator may lowercase or prefix differently for capitals and digits; if `key_A` does not exist, drop that line and say so in `of_char`'s doc.

`test/handle/test_handle.ml` — the shape stavekeeper's dialog has:

```ocaml
let%expect_test "Escape is handled, other keys propagate" =
  let app (graph @ local) =
    let open_, set_open = Bonsai.state true graph in
    let%arr open_ and set_open in
    Node.window ~title:"dialog"
      (Node.box ~orientation:Vertical
         ~attrs:
           [ Attr.test_id "sheet"
           ; Attr.on_key_pressed ~phase:Capture (fun (e : Key_event.t) ->
               if e.keyval = Keyval.escape
               then Key_response.Handled_and (set_open false)
               else Propagate)
           ]
         [ Node.label ~attrs:[ Attr.test_id "state" ] (if open_ then "open" else "closed") ])
  in
  let handle = Bonsai_gtk_test.create app in
  Bonsai_gtk_test.Handle.show handle;
  [%expect {| |}];
  (* The action prints what the handler answered, which is the half a headless test can
     see and the half an application's logic actually lives in. *)
  Bonsai_gtk_test.Handle.do_actions handle
    [ Key_press ("sheet", { keyval = Keyval.of_char 'x'; keycode = 0; modifiers = Modifiers.none }) ];
  Bonsai_gtk_test.Handle.show_diff handle;
  [%expect {| |}];
  Bonsai_gtk_test.Handle.do_actions handle
    [ Key_press ("sheet", { keyval = Keyval.escape; keycode = 0; modifiers = Modifiers.none }) ];
  Bonsai_gtk_test.Handle.show_diff handle;
  [%expect {| |}]
;;
```

`test/live/live_controllers.ml` — append the live half. Unlike a click, a key press **is** deliverable: `W.Event_controller_key.forward : t -> Widget.t -> bool` exists, and so does the ordinary route of `Gobject.Signal.emit_by_name` (which cannot carry the arguments, so it is useless here). Check whether a `GdkEvent` can be synthesised from the binding; if not, the honest live assertions are the same three as the click gesture's — attach, detach, survive — plus one that *is* directly observable and worth having:

```ocaml
  (* The phase really is written onto the controller. Nothing else in this file can see a
     controller's properties, but the propagation phase is readable, and a wrong phase is
     the failure mode stavekeeper's dialog.ml comment is entirely about: in BUBBLE a key
     controller a caller adds later runs first and swallows Escape. *)
  printf "phase: %s\n" (phase_of_only_key_controller live);
```

which needs a way to reach the controller — `Controllers` is `Private`, so expose `Bonsai_gtk.Private.Controllers` and a `Controllers.Private.key_controller : t -> W.Event_controller.t option` for the test. A test-only accessor is better than an untested phase.

- [ ] **Step 2: Run to verify failure.**

- [ ] **Step 3: `vtree/keyval.ml(i)`, `key_event.ml`, `key_response.ml`**

`keyval.mli`'s header carries the reasoning:

```ocaml
(** X11 keysyms, as the plain [int]s GTK delivers.

    Hard-coded rather than re-exported from GDK because this library's whole vtree/runtime
    split exists so that an application's view functions can be written against
    [bonsai_gtk.vtree] alone, with no ocgtk dependency and therefore headless-testable —
    and a view that handles Escape has to be able to name Escape. The values are X11
    keysyms and have not changed since 1987; [test/live/live_keyvals.ml] checks every one
    of them against [Ocgtk_gdk.Gdk_constants] on every CI run, which is what turns "has not
    changed" into "is checked".

    Only the keys an application actually branches on are here. A keyval this module does
    not name is still an ordinary [int] and can be compared to one — {!of_char} covers the
    printable ASCII range, and the rest are in GDK's headers. *)

val of_char : char -> int
(** The keysym of a printable ASCII character, which for [0x20]–[0x7e] is its own code
    point — so [of_char 'w'] is Ctrl+W's keyval and [of_char '/'] is the "start a search"
    key. Raises [Invalid_argument] outside that range: a keysym for [\n] or [\255] is not
    the codepoint and quietly returning one would be a wrong answer rather than an
    error. *)
```

`key_response.ml` is the four-constructor variant with the table above as its doc, plus:

```ocaml
(** [sexp_of_t] prints the effect as [<effect>], like every other handler in this
    library: an effect is not inspectable and a test comparing two of them is comparing
    closures. *)
```

- [ ] **Step 4: `vtree/attr.ml(i)`**

```ocaml
  | On_key_pressed of
      { phase : Phase.t
      ; handler : Key_event.t -> Key_response.t
      }
  | On_key_released of
      { phase : Phase.t
      ; handler : Key_event.t Handler.t
      }
```

with, on `on_key_pressed`:

```ocaml
val on_key_pressed : ?phase:Phase.t -> (Key_event.t -> Key_response.t) -> t
(** A [GtkEventControllerKey] on this widget.

    The handler is not a {!Handler.t}: it returns a {!Key_response.t} rather than an
    effect, because GTK asks a key press a {i question} — "did anything handle this?" — and
    routes the event on the answer, synchronously, on its own stack, long before the frame
    that an effect would run in. So the decision is a pure function of the event and the
    consequence rides along: [Handled_and eff] stops the routing {i and} schedules [eff].

    [phase] defaults to {!Phase.Bubble}, GTK's own. Use {!Phase.Capture} for a
    window-or-dialog-wide key: in bubble phase GTK runs the {i last} controller added
    first, so any controller a child adds afterwards sees the key first and can swallow
    it, and "afterwards" is not something a declarative tree controls. A [GtkPopover] has
    its own surface and so is not below the window in the capture chain — an open popover
    still takes its own Escape.

    Both this and {!on_key_released} share one controller, so a widget carrying both pays
    for one; giving them different phases is [Invalid_argument] at mount, because there is
    only one phase to write.

    The keyval is a plain [int]; {!Bonsai_gtk_vtree.Keyval} names the ones worth naming. *)
```

`on_key_released`'s handler *is* an ordinary `Handler.t`: GTK's `key-released` callback returns `unit`, so there is no question to answer.

- [ ] **Step 5: `src/controllers.ml` — the key family**

One `GtkEventControllerKey` serves both attrs. `wanted` is "either attr present". The phase comes from whichever attr carries it, and **differing phases raise**:

```ocaml
(* One controller, one phase. Two attrs asking for different ones is a mistake with no
   good resolution -- picking either silently gives one of them behaviour its author did
   not ask for -- so it is [Invalid_argument] with the node path, like every other
   structural rejection (spec §11). *)
let key_phase attrs =
  match Attrs.find attrs On_key_pressed, Attrs.find attrs On_key_released with
  | Some (On_key_pressed p), Some (On_key_released r) when not (Phase.equal p.phase r.phase) ->
    invalid_argf
      "on_key_pressed is %s and on_key_released is %s, but they share one \
       GtkEventControllerKey and so one phase"
      (Phase.to_string p.phase) (Phase.to_string r.phase) ()
  | Some (On_key_pressed p), _ -> Some p.phase
  | _, Some (On_key_released r) -> Some r.phase
  | _ -> None
;;
```

The pressed spec is the `Payload` with `'r = bool`:

```ocaml
let key_pressed_spec (kc : W.Event_controller_key.t) : Signals.spec =
  Payload
    { attr = Attr.Name.On_key_pressed
    ; connect =
        (fun _w ~callback ->
          Signals.connected
            kc
            (W.Event_controller_key.on_key_pressed kc ~callback:(fun ~keyval ~keycode ~state ->
               callback ({ keyval; keycode; modifiers = Gtk_import.modifiers state } : Key_event.t))))
    ; fire =
        (fun _w attr e ->
          match (attr : Attr.Private.t) with
          | On_key_pressed { handler; _ } ->
            (match handler e with
             | Propagate -> false, None
             | Handled -> true, None
             | Propagate_and eff -> false, Some eff
             | Handled_and eff -> true, Some eff)
          | _ -> false, None)
    ; declined = false
      (* [Gdk_constants.event_propagate]. A widget whose slot is empty, or whose handler
         raised, has certainly not handled the key; returning [true] there would make a
         window with a broken handler swallow every keystroke in the application. *)
    }
;;
```

Use the literal `false` with that comment rather than `Gdk_constants.event_propagate`, or use the constant and drop the comment's first sentence — either, but say which and be consistent with `key_released_spec`.

- [ ] **Step 6: `test_lib` — the `Key_press` action, and what it can honestly claim**

```ocaml
| Key_press of string * Key_event.t
(** test_id of a node carrying [Attr.on_key_pressed], and the key to deliver. Fires that
    handler with exactly that event and performs the effect of whatever
    {!Bonsai_gtk_vtree.Key_response.t} it returns.

    What this {i cannot} model is propagation. A real key press walks GTK's capture and
    bubble chains and stops where a handler says [Handled]; here it is delivered to one
    node, by [test_id], and the [Handled]/[Propagate] half of the answer is not acted on —
    there is no chain to act on it in. So a test can show that a handler decided to
    consume Escape and what that decision did to the model; it cannot show that the
    keystroke then failed to reach a sibling. That half is a live test, or the
    application. *)

| Key_release of string * Key_event.t
```

Say the same thing, shorter, in the mli's opening paragraph about what the handle validates — this is the second known gap after the structural one, and both belong in the same place.

- [ ] **Step 7: `Events`** — add `On_key_pressed`/`On_key_released` to `is_controller_attr`.

- [ ] **Step 8: Run, read, promote, gate.** `expected_keyvals.txt` is `keyvals agree`. Any `MISMATCH` line is a stop-and-report.

- [ ] **Step 9: Commit**

```bash
dune fmt 2>/dev/null; git add vtree src test test_lib
GIT_EDITOR=true git commit -F - <<'MSG'
Key controllers: a synchronous answer to GTK, an effect for Bonsai

[Attr.on_key_pressed]'s handler returns a [Key_response.t] rather than an
effect, because GTK asks a key press a question and routes on the answer, on
its own stack, before any frame could run. [Handled]/[Propagate] is that
answer; [Handled_and]/[Propagate_and] carry an effect alongside it, which is
what lets a handler consume Escape *and* update the model.

Both key attrs share one GtkEventControllerKey, so differing ~phase arguments
are Invalid_argument rather than one of them silently losing.

vtree/keyval.ml hard-codes the X11 keysyms an application branches on, so a
view function stays ocgtk-free and headless-testable; test/live/live_keyvals.ml
checks every one of them against Gdk_constants on every run.

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01Sg3Ci8U8kUKR8C3PL1pNSs
MSG
```

**Review focus:** that `declined = false` is right and commented; that the differing-phase rejection has a test; that `Keyval`'s table is checked in full — count the `check` lines against the `val`s in `keyval.mli`, they must match; that `Key_press`'s inability to model propagation is stated in the mli and not only in the plan; that `of_char`'s range check raises rather than returning a wrong keysym.

---

