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

