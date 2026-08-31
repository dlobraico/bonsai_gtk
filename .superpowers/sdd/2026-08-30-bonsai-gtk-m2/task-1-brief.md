### Task 1: Seal the attr surface, and the vtree event table

Three backlog items that all live in `vtree/attr.mli` and `test_lib/`, and that every task after this one depends on. They go first because each M2 attr added before the seal is another line of a downstream exhaustive match that will break later, and because the event table is what stops the headless suite certifying an app the runtime refuses.

**Files:**
- Modify: `vtree/attr.ml`, `vtree/attr.mli`, `vtree/bonsai_gtk_vtree.ml`, `src/attr_apply.ml`, `src/signals.ml`, `src/signals.mli`, every `src/widgets/w_*.ml` that matches on `Attr.t`, `test_lib/bonsai_gtk_test.ml`, `test_lib/bonsai_gtk_test.mli`, `test/test_attrs.ml`, `test/handle/test_handle.ml`, `test/live/dune`
- Create: `vtree/events.ml`, `vtree/events.mli`, `test/test_events.ml`, `test/live/live_events.ml`, `test/live/expected_events.txt`

**Interfaces:**
- Produces:
  ```ocaml
  (* vtree/attr.mli — the whole variant moves behind [Private]. *)
  type t

  val sexp_of_t : t -> Sexp.t
  (* every existing smart constructor stays exactly where it is *)

  module Name : sig
    type t = ... (* still concrete: see the ruling below *)
    val all : t list
    val is_event : t -> bool
    val to_string : t -> string
    include Comparable.S_plain with type t := t
  end

  module Private : sig
    (** No stability promise. The library's own runtime and test harness match on this;
        an application that does is choosing to break on the next milestone. *)
    type nonrec t = t =
      | Css_class of string
      | ...
      | Many of t list
  end

  (* vtree/events.mli *)
  val for_kind : Kind.t -> Attr.Name.t list
  val is_supported : Kind.t -> Attr.Name.t -> bool
  val unsupported : Kind.t -> Attrs.t -> Attr.Name.t option

  (* test_lib/bonsai_gtk_test.mli — Action.t gains *)
  | Search_changed of string * string
  | Set_expanded of string * bool
  ```
- Consumes: nothing new from ocgtk.

**The seal, and why it is cheap.** `type nonrec t = t = | Css_class of string | …` inside `module Private` re-exports the *same* type with its constructors visible there and nowhere else. `Attr.t` and `Attr.Private.t` are the same type, so nothing needs converting; a file that matches on the variant adds one line — `open Attr.Private` at the top, or `match (attr : Attr.Private.t) with` at the site — and its existing match compiles unchanged. This is the same idiom `Bonsai_gtk.Private` already uses, and it is what makes the "real refactor touching four files plus every task below it" the M1 ruling feared into a mechanical edit. **Do not** invent a separate `repr` type and a conversion function: that would be a real refactor, it would allocate, and it buys nothing the type re-export does not.

`Attr.Name.t` stays concrete in the documented surface, per M1's ruling: it is only reachable through `Attrs.op`, which is `Private`-adjacent already, and `Attr_apply.unset` matching on it exhaustively is the mechanism that makes "unset restores the creation-time default" impossible to forget for a new attr. Sealing it would trade a compile error for a silent omission. Say this in the mli.

**The event table, and the two sources of truth.** `Events.for_kind` is pure data in `vtree`; `(Registry.for_kind kind).signals` is the real thing in `src`. They must agree, and nothing but a test can make them. That test cannot be a `ppx_expect` test — it links ocgtk — so it is `test/live/live_events.ml`, which needs no display but lives under the live gate for the ocgtk-free rule. It is the *only* thing standing between the two lists, so write it first and make its failure message say which kind and which direction.

- [ ] **Step 1: Write the failing tests**

`test/test_events.ml` — new file:

```ocaml
open! Core
open Bonsai_gtk_vtree

(* One row per kind, so that adding a kind without an [Events] arm is a compile error and
   adding one with the wrong arm is a diff here. The kinds are built with their cheapest
   constructor; only the constructor, not the props, decides the answer. *)
let%expect_test "every kind's event attrs" =
  let kinds =
    [ (Node.label "x").kind
    ; (Node.button ()).kind
    ; (Node.toggle_button ~active:false ()).kind
    ; (Node.switch ~active:false ()).kind
    ; (Node.entry ()).kind
    ; (Node.search_entry ()).kind
    ; (Node.scale ~min:0. ~max:1. ~value:0. ()).kind
    ; (Node.expander ~expanded:false ~label:"e" (Node.label "x")).kind
    ; (Node.stack ~name:"s" ~visible_child:"a" []).kind
    ; (Node.box ~orientation:Vertical []).kind
    ]
  in
  List.iter kinds ~f:(fun kind ->
    print_s [%sexp (Kind.name kind : string), (Events.for_kind kind : Attr.Name.t list)]);
  [%expect {| |}]
;;

let%expect_test "unsupported finds the offending name, and only event names" =
  let attrs =
    Attrs.of_list
      [ Attr.css_class "c"; Attr.test_id "t"; Attr.on_toggled (fun _ -> Ui_effect.Ignore) ]
  in
  print_s [%sexp (Events.unsupported (Node.label "x").kind attrs : Attr.Name.t option)];
  [%expect {| |}];
  print_s
    [%sexp
      (Events.unsupported (Node.switch ~active:false ()).kind attrs : Attr.Name.t option)];
  [%expect {| |}]
;;

(* [Attr.Name.all] exists so that [is_event]'s classification is pinned rather than
   assumed -- the M1 final review found it tested on 2 names of 32, and adding an [On_foo]
   to the wrong branch compiles. *)
let%expect_test "is_event over every name" =
  let events, plain = List.partition_tf Attr.Name.all ~f:Attr.Name.is_event in
  print_s [%sexp `events (events : Attr.Name.t list)];
  [%expect {| |}];
  print_s [%sexp `plain (plain : Attr.Name.t list)];
  [%expect {| |}]
;;
```

`test/handle/test_handle.ml` — append the two new actions and the rejection:

```ocaml
let searcher (graph @ local) =
  let query, set_query = Bonsai.state "" graph in
  let%arr query and set_query in
  Node.window
    ~title:"Search"
    (Node.box
       ~orientation:Vertical
       [ Node.search_entry
           ~attrs:[ Attr.test_id "q"; Attr.on_search_changed set_query ]
           ~text:query
           ()
       ; Node.expander
           ~attrs:[ Attr.test_id "adv"; Attr.on_expanded_changed (fun _ -> Ui_effect.Ignore) ]
           ~expanded:false
           ~label:"advanced"
           (Node.label ~attrs:[ Attr.test_id "hits" ] query)
       ])
;;

let%expect_test "Search_changed and Set_expanded reach their handlers" =
  let handle = Bonsai_gtk_test.create searcher in
  Bonsai_gtk_test.Handle.show handle;
  [%expect {| |}];
  Bonsai_gtk_test.Handle.do_actions handle [ Search_changed ("q", "bach") ];
  Bonsai_gtk_test.Handle.show_diff handle;
  [%expect {| |}];
  Bonsai_gtk_test.Handle.do_actions handle [ Set_expanded ("adv", true) ];
  Bonsai_gtk_test.Handle.show_diff handle;
  [%expect {| |}]
;;

(* The whole point of [Events]: a handle that would have gone green on a tree the runtime
   refuses at mount now refuses it here, with the same message shape. *)
let%expect_test "an event attr the kind cannot emit is rejected by the handle" =
  let bad (_graph @ local) =
    Bonsai.return
      (Node.window
         ~title:"bad"
         (Node.label ~attrs:[ Attr.on_toggled (fun _ -> Ui_effect.Ignore) ] "not a switch"))
  in
  Expect_test_helpers_core.require_does_raise (fun () ->
    let handle = Bonsai_gtk_test.create bad in
    Bonsai_gtk_test.Handle.show handle);
  [%expect {| |}]
;;
```

`test/live/live_events.ml` — the agreement test:

```ocaml
open! Core
open Bonsai_gtk_vtree
module Registry = Bonsai_gtk.Private.Registry
module Signals = Bonsai_gtk.Private.Signals

(* Every kind, built with its cheapest constructor. This list is the one place that has to
   grow with [Kind.t]; there is no exhaustive-match trick that produces a *value* per
   constructor, so a new kind missing from here is caught by the count assertion below
   rather than by the compiler. *)
let all_kinds : Kind.t list = [ (* ... every Node constructor, one call each ... *) ]

let () =
  (* No display is needed: [Registry.for_kind] only reads a record. The file lives under
     the live gate because it links ocgtk, which ppx_expect cannot. *)
  List.iter all_kinds ~f:(fun kind ->
    let from_impl =
      (Registry.for_kind kind).signals
      |> List.map ~f:Signals.spec_attr
      |> List.sort ~compare:Attr.Name.compare
    in
    let from_table = List.sort (Events.for_kind kind) ~compare:Attr.Name.compare in
    if not (List.equal Attr.Name.equal from_impl from_table)
    then
      print_s
        [%message
          "MISMATCH"
            ~kind:(Kind.name kind)
            ~impl:(from_impl : Attr.Name.t list)
            ~table:(from_table : Attr.Name.t list)]);
  printf "kinds checked: %d\n" (List.length all_kinds);
  printf "agreed\n"
;;
```

The expected file is two lines. A mismatch prints a third and the diff fails. `kinds checked` is what catches a kind nobody added to `all_kinds`: bump it deliberately, and Task 13's gallery sweep is the second net under it.

- [ ] **Step 2: Run to verify failure** — `dune build @test/runtest` → unbound `Events`, unbound `Attr.Name.all`, unknown constructor `Search_changed`.

- [ ] **Step 3: `vtree/attr.ml(i)` — the seal and `Name.all`**

In `attr.mli`, replace the bare `type t = | Css_class of string | …` with `type t` plus `val sexp_of_t : t -> Sexp.t`, keep every smart constructor and `val name`/`val equal` where they are, and add at the bottom:

```ocaml
module Private : sig
  (** {b No stability promise.} The variant, for the library's own runtime
      ([Attr_apply], [Signals], the widget impls) and its test harness. It is the same
      type as {!t} — [Attr.Private.Css_class "x"] and [Attr.css_class "x"] are the same
      value — so nothing converts and nothing allocates.

      It is here rather than in the documented surface because every milestone adds
      constructors, and an application matching on them exhaustively would break on each
      one. Build attrs with the constructors above; if you find yourself needing to take
      one apart, that is a missing accessor and worth an issue. *)
  type nonrec t = t =
    | Css_class of string
    | Margin_start of int
    (* ... every constructor, unchanged and in the same order ... *)
    | Many of t list
end
```

`attr.ml` needs `module Private = struct type nonrec t = t = Css_class of string | … end`, spelled out. That duplication is the price of the idiom; a comment in `attr.ml` says so and points at the compiler error a divergence produces (it is a type error, not a silent drift — the two definitions must be structurally identical or `type nonrec t = t = …` does not typecheck, which is exactly the safety we want).

`Name.t` gains `[@@deriving enumerate]` alongside its existing derivings, and:

```ocaml
val all : t list
(** Every attribute name, for tests that must not be able to forget one. The M1 review
    found [is_event] pinned on 2 of 32 names, which is the same as unpinned. *)

val to_string : t -> string
(** The name as it appears in error messages — [Sexp.to_string (sexp_of_t t)]. *)
```

Add a paragraph to `Name.t`'s doc saying why *it* is not sealed: `Attr_apply.unset`'s exhaustive match over it is what makes an attr's restore-to-default impossible to forget, and it is only reachable through `Attrs.op`.

- [ ] **Step 4: Every matcher gets one line**

`grep -ln 'Attr\.' src/*.ml src/widgets/*.ml test_lib/*.ml` and, for each file that *matches on* the variant, add `open Attr.Private` after the existing `open Bonsai_gtk_vtree` — or, where the file already writes `(attr : Attr.t)` in a match scrutinee annotation, change it to `(attr : Attr.Private.t)`. Prefer the annotation form in `Signals.spec` bodies (it is one word and keeps the constructor namespace out of the file); prefer the `open` in `src/attr_apply.ml`, which is nothing but matches.

Files expected to need it: `src/attr_apply.ml`, `src/signals.ml`, `src/widgets/w_{button,entry,search_entry,password_entry,toggle_button,check_button,switch,spin_button,scale,expander,revealer,paned,stack,grid,overlay}.ml`, `test_lib/bonsai_gtk_test.ml`. The pre-flight scan produces the real list; if it is longer than this, that is fine — each is one line.

- [ ] **Step 5: `vtree/events.ml(i)`**

```ocaml
open! Core

(** Which event attributes each kind can carry.

    Pure data, in [vtree] rather than in the runtime, because two things need it and only
    one of them may link ocgtk: [Signals.require_specs] rejects an unsupported event attr
    at mount, and [Bonsai_gtk_test] must reject the same tree at handle time — otherwise a
    suite that is entirely headless certifies an application that raises the moment it is
    shown, which is exactly what M1 shipped (see [bonsai_gtk_test.mli]'s warning, which
    Task 1 rewrites).

    This table and each widget impl's [Widget_impl.signals] are two statements of one
    fact. [test/live/live_events.ml] compares them for every kind and fails the build if
    they disagree; that test is the only thing keeping them honest, so do not weaken it. *)
val for_kind : Kind.t -> Attr.Name.t list

(** [is_supported kind name] is [true] if [name] is not an event name, or is one this kind
    emits. A non-event name is always supported: this answers "may this attr be here",
    and layout attrs may be anywhere. *)
val is_supported : Kind.t -> Attr.Name.t -> bool

(** The first event attr in [attrs] that [kind] cannot emit, in [Attr.Name] order. [None]
    when every event attr present is one this kind emits. *)
val unsupported : Kind.t -> Attrs.t -> Attr.Name.t option
```

The implementation is one `match` over `Kind.t` with no wildcard arm:

```ocaml
let for_kind : Kind.t -> Attr.Name.t list = function
  | Label _ | Image _ | Picture _ | Separator _ | Spinner _ | Progress_bar _
  | Level_bar _ | Stack_switcher _ | Stack_sidebar _ | Native _ -> []
  | Button _ -> [ On_clicked ]
  | Toggle_button _ | Check_button _ | Switch _ -> [ On_toggled ]
  | Entry _ | Password_entry _ -> [ On_changed; On_activate ]
  | Search_entry _ -> [ On_changed; On_activate; On_search_changed ]
  | Spin_button _ | Scale _ -> [ On_value_changed ]
  | Expander _ -> [ On_expanded_changed ]
  | Revealer _ -> [ On_revealed ]
  | Paned _ -> [ On_position_changed ]
  | Stack _ -> [ On_visible_child_changed ]
  | Window _ | Box _ | Grid _ | Center_box _ | Overlay _ | Frame _
  | Scrolled_window _ -> []
  (* M2's kinds are added by their own tasks. *)
;;
```

`Native _ -> []` is load-bearing and matches spec §6.6: a native node declares no specs, so any event attr on one is rejected.

The **controller attrs are not in this table** and must not be: `On_key_pressed`, `On_click` and the rest are handled by `Controllers`, not by any impl's `signals`, and they are legal on *every* kind. `is_supported` therefore returns `true` for them unconditionally. Task 4 adds that arm and a comment saying why, and extends `live_events.ml` to assert that no impl declares a controller name in its `signals`.

- [ ] **Step 6: `src/signals.ml(i)` — `require_specs` reads the table**

`require_specs` currently walks the impl's specs. Change it to take the kind and consult `Events.unsupported`, so that the mount-time rejection and the headless rejection are the *same* function of the *same* data:

```ocaml
val require_specs
  :  node_path:string
  -> impl_name:string
  -> Kind.t
  -> Attrs.t
  -> unit
```

and its body is `match Events.unsupported kind attrs with None -> () | Some name -> invalid_argf "%s: %s cannot emit %s" node_path impl_name (Attr.Name.to_string name) ()`. Keep the message shape M1 used so the existing expected files do not churn; if it does churn, read the diff and promote deliberately.

The `spec list` argument goes away, which means `Patcher` passes `live.node.kind` instead of `impl.signals`. That is one call site each in `mount` and `patch`.

`spec_attr : spec -> Attr.Name.t` is added now (trivially `fun s -> s.attr`) because Task 4 turns `spec` into a variant and `live_events.ml` should not have to change then.

- [ ] **Step 7: `test_lib/bonsai_gtk_test.ml(i)` — two actions, and the validation**

```ocaml
| Search_changed of string * string
(** test_id of a [search_entry] carrying [Attr.on_search_changed], and the text the
    user typed. Fires that handler with exactly that string.

    Distinct from [Set_text] on the same node, which fires [Attr.on_changed]: the two
    are different signals on the real widget — [changed] is immediate, [search-changed]
    arrives [search_delay] ms after typing stops — and an app that attaches both wants
    to test them apart. Neither consults the node's own [text] prop, for the reason
    [Set_text] documents. *)

| Set_expanded of string * bool
(** test_id of an [expander] carrying [Attr.on_expanded_changed], and the state the user
    dragged it to. Fires that handler with exactly that bool; the node's own [expanded]
    prop is not consulted, so a test can show a model that declines to open. *)
```

And in `create`, before returning the handle, install validation: the result spec's `view` (or a wrapper around it) walks the node tree and raises `Invalid_argument` on the first node whose `Events.unsupported node.kind node.attrs` is `Some name`, with the same `path: kind cannot emit name` shape the patcher uses. Walk with `Children.iteri` so the path spelling matches the patcher's exactly.

Then **rewrite the "Structural validation happens at mount, not here" paragraph** in `bonsai_gtk_test.mli`. It is now half wrong, which is worse than wholly wrong. The new text says: event attrs a kind cannot emit *are* rejected here, by the same table the runtime uses; what is still only checked at mount is the structural half — a `Node.grid` child with no `Attr.grid_cell`, a `Node.stack` page with no `~key`, two stacks under one `~name`, duplicate sibling keys, a `Node.window` off-root — and the escape from that is still a live test or running the app.

- [ ] **Step 8: `test/live/dune`** — add `live_events` to the `(names …)` list and a rule in the shape of the existing ones.

- [ ] **Step 9: Run, read, promote**

```
dune build @test/runtest && dune promote
BONSAI_GTK_LIVE_TESTS=1 xvfb-run -a dune build @test/live/runtest && dune promote
./scripts/ci.sh
```

Read `expected_events.txt` before promoting: it must say `agreed`, and `kinds checked` must equal the number of arms in `Registry.for_kind`. Every other expected file must be **unchanged** — this task changes no runtime behaviour. A diff anywhere else means the `require_specs` message shape moved; decide deliberately.

- [ ] **Step 10: Commit**

```bash
dune fmt 2>/dev/null; git add vtree src test test_lib
GIT_EDITOR=true git commit -F - <<'MSG'
Seal Attr.t behind Attr.Private; one event table for the runtime and the harness

Attr.t's variant moves into Attr.Private, which carries no stability promise,
so M2's and M3's attrs stop being breaking changes for a downstream exhaustive
match. It is a type re-export, not a conversion: Attr.t and Attr.Private.t are
the same type, and every internal matcher needed one line.

Events.for_kind is the Kind.t -> Attr.Name.t list table that Signals.require_specs
and Bonsai_gtk_test now share, so the headless suite refuses exactly the trees
the runtime refuses instead of certifying an app that raises at mount.
test/live/live_events.ml is the only thing keeping the table and the widget
impls' own signal lists in agreement.

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01Sg3Ci8U8kUKR8C3PL1pNSs
MSG
```

**Review focus:** that the seal really is the same type (no conversion, no allocation, no `Obj`); that `Events.for_kind` has no wildcard arm; that `live_events.ml` would actually fail if a table entry were wrong — try breaking one deliberately and confirm the diff goes red before promoting; that the rewritten `bonsai_gtk_test.mli` paragraph does not now overclaim in the other direction.

---

