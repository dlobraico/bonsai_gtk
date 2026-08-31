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

