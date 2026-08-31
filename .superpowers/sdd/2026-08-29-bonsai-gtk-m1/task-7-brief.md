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

