### Task 2: The cross-cutting attrs a real app needs, and Label's text properties

Everything stavekeeper's five screens reach for that is not a widget: `css_class` (done in M0), `margin_*`, size requests, `halign`/`valign`, `hexpand`/`vexpand`, `tooltip`, `sensitive`, `visible` (all done in M0), plus **cursor name**, **opacity**, **focusable**/**can_focus**, **widget name**, and on `Label` — which stavekeeper sets on nearly every label it builds — **ellipsize**, **xalign**, **max-width-chars**, **width-chars**, **wrap**, **selectable**, **use-markup**. Also the backlog's per-kind unset-defaults bug, fixed generically.

Read `~/src/stavekeeper/lib/stavekeeper_app/dialog.ml` before starting: `field`, `row`, `hint`, `section` are four helpers and they use `set_xalign`, `set_wrap`, `set_ellipsize`, `set_size_request`, `set_hexpand`, `add_css_class` between them. That is the shape M1's attrs have to make expressible without an escape hatch.

**Files:**
- Create: `vtree/ellipsize.ml`, `test/test_widgets.ml`
- Modify: `vtree/attr.ml`, `vtree/attr.mli`, `vtree/kind.ml`, `vtree/kind.mli`, `vtree/node.ml`, `vtree/node.mli`, `vtree/bonsai_gtk_vtree.ml`, `src/dune`, `src/attr_apply.ml`, `src/attr_apply.mli`, `src/patcher.ml`, `src/widgets/w_label.ml`, `src/live_tree.ml`, `src/bonsai_gtk.ml`, `src/bonsai_gtk.mli`, `test/test_attrs.ml`, `test/live/live_patcher.ml`

**Interfaces:**
- Produces:
  ```ocaml
  (* vtree/ellipsize.ml — absent means "do not ellipsize"; there is no [None]
     constructor, so [Ellipsize.t option] carries that and never shadows [Option]. *)
  type t = Start | Middle | End [@@deriving sexp_of, equal, compare]

  (* Attr *)
  val opacity : float -> t          (* 0. .. 1. *)
  val focusable : bool -> t
  val can_focus : bool -> t
  val widget_name : string -> t     (* GtkWidget's [name], the CSS "#id" selector *)
  val cursor_name : string -> t     (* "pointer", "text", "default", ... *)

  (* Node *)
  val label
    :  ?key:Key.t -> ?attrs:Attr.t list
    -> ?wrap:bool -> ?xalign:float -> ?ellipsize:Ellipsize.t
    -> ?max_width_chars:int -> ?width_chars:int -> ?selectable:bool -> ?use_markup:bool
    -> string -> t

  (* Attr_apply *)
  type defaults
  val snapshot : Widget.t -> defaults      (* call once, on a freshly created widget *)
  val apply : defaults:defaults -> Widget.t -> Attrs.op -> unit
  val apply_all : Widget.t -> Attrs.t -> unit
  ```
- Consumes: `Widget.set_opacity/set_focusable/set_can_focus/set_name/set_cursor_from_name`, `Widget.get_cursor`, `Label.set_wrap/set_xalign/set_ellipsize/set_max_width_chars/set_width_chars/set_selectable/set_markup`, `Ocgtk_pango.Pango.ellipsizemode`.

Note on `Widget.set_name`: ocgtk's widget module has `set_name : t -> string -> unit` / `get_name : t -> string` (the `string option` pair in the same generated file belongs to `Event_controller`, a different module — no shadowing). The attr is called `widget_name`, not `name`, because `Attr.name : Attr.t -> Attr.Name.t option` already exists.

**The defaults snapshot.** `Attr_apply.unset` currently restores a constant it guesses (`Visible -> true`, `Halign -> \`FILL`). The backlog flags `Unset Visible -> true` as wrong for `GtkWindow`, and M1 makes that class of bug much bigger: `focusable` is FALSE on a `GtkLabel` and TRUE on a `GtkButton`, `can_focus` differs the same way, and a `GtkPicture`'s `can_shrink` default is not a `GtkImage`'s. Rather than a per-kind table that has to be maintained for 27 widgets, read the answer off the widget GTK just made: `Patcher.mount` calls `Attr_apply.snapshot` immediately after `impl.create` and before `apply_all`, stores the record in `live`, and every later `Unset` restores from it. Fifteen getter calls per widget creation, once, and it is right by construction for every widget the library will ever add.

- [ ] **Step 1: Write the failing tests**

`test/test_attrs.ml` — append:

```ocaml
let%expect_test "M1 widget-wide attrs round-trip through of_list and diff" =
  let attrs =
    Attrs.of_list
      [ Attr.opacity 0.5
      ; Attr.focusable true
      ; Attr.can_focus false
      ; Attr.widget_name "sidebar"
      ; Attr.cursor_name "pointer"
      ]
  in
  print_s [%sexp (attrs : Attrs.t)];
  [%expect {| |}];
  print_s
    [%sexp
      (Attrs.diff ~old:attrs ~new_:(Attrs.of_list [ Attr.opacity 1.0 ]) : Attrs.op list)];
  [%expect {| |}]
;;
```

`test/test_widgets.ml` — new file, the home for every "does this constructor make the node I meant" test M1 adds. Start it with `Label`:

```ocaml
open! Core
open Bonsai_gtk_vtree

let%expect_test "label defaults match GTK's, and every text property reaches the kind" =
  print_s [%sexp (Node.label "plain" : Node.t)];
  [%expect {| |}];
  print_s
    [%sexp
      (Node.label
         ~wrap:true
         ~xalign:0.
         ~ellipsize:End
         ~max_width_chars:14
         ~width_chars:6
         ~selectable:true
         ~use_markup:true
         "styled"
       : Node.t)];
  [%expect {| |}]
;;

let%expect_test "label props take part in equal_props" =
  let a = (Node.label ~xalign:0. "x").kind in
  let b = (Node.label ~xalign:1. "x").kind in
  print_s [%sexp (Kind.same_kind a b, Kind.equal_props a b : bool * bool)];
  [%expect {| |}]
;;
```

`test/dune` needs no change — the library stanza globs the directory.

- [ ] **Step 2: Run to verify failure** — `dune build @test/runtest` → unbound `Attr.opacity`, unknown labelled argument `~wrap`.

- [ ] **Step 3: `vtree/ellipsize.ml`**

```ocaml
open! Core

(** Where a `GtkLabel`/`GtkProgressBar` drops characters when its text does not fit. There
    is deliberately no "none" constructor: the absence of ellipsization is
    [None : t option], which keeps the constructor list from shadowing [Option.None] in
    every match. *)
type t =
  | Start
  | Middle
  | End
[@@deriving sexp_of, equal, compare]
```

Add `module Ellipsize = Ellipsize` to `vtree/bonsai_gtk_vtree.ml` and to `src/bonsai_gtk.ml(i)`.

- [ ] **Step 4: `vtree/attr.ml(i)`** — five constructors, five names, five `equal` arms, five smart constructors

```ocaml
(* Name.t gains, in this order (Name order is the order [Attrs.diff] emits Sets in, so
   keep related attrs adjacent): *)
  | Opacity
  | Focusable
  | Can_focus
  | Widget_name
  | Cursor_name

(* t gains: *)
  | Opacity of float
  | Focusable of bool
  | Can_focus of bool
  | Widget_name of string
  | Cursor_name of string

(* name: *)
  | Opacity _ -> Some Name.Opacity
  | Focusable _ -> Some Focusable
  | Can_focus _ -> Some Can_focus
  | Widget_name _ -> Some Widget_name
  | Cursor_name _ -> Some Cursor_name

(* equal: *)
  | Opacity a, Opacity b -> Float.equal a b
  | Focusable a, Focusable b | Can_focus a, Can_focus b -> Bool.equal a b
  | Widget_name a, Widget_name b | Cursor_name a, Cursor_name b -> String.equal a b

(* constructors: *)
let opacity f = Opacity f
let focusable b = Focusable b
let can_focus b = Can_focus b
let widget_name s = Widget_name s
let cursor_name s = Cursor_name s
```

mli doc comments worth writing, because each is a trap:
- `opacity`: "0. is fully transparent, 1. fully opaque. GTK still lays the widget out and still routes input to it — use `visible false` to take it out of the layout."
- `focusable` / `can_focus`: "`focusable` is whether the widget takes keyboard focus itself; `can_focus` is whether focus may travel *into* it or its children. GTK's defaults differ per widget class (a `GtkButton` is focusable, a `GtkLabel` is not), so unsetting either restores that widget's own class default rather than a constant."
- `cursor_name`: "A CSS cursor name — `pointer`, `text`, `not-allowed`, `default`. An unknown name is GTK's problem, not ours: it logs and falls back."

- [ ] **Step 5: `src/attr_apply.ml(i)` — the defaults snapshot**

```ocaml
open! Core
open Bonsai_gtk_vtree
open Gtk_import

let align : Align.t -> Gtk_enums.align = function
  | Fill -> `FILL
  | Start -> `START
  | End -> `END
  | Center -> `CENTER
  | Baseline -> `BASELINE_FILL
;;

(* Everything [unset] has to be able to put back. Read once off a freshly created widget,
   before any attr has been applied to it, so it is that widget class's own default rather
   than a constant this module would otherwise have to guess per kind ([focusable] is
   false on a label and true on a button; [visible] is true on most widgets and false on a
   GtkWindow, which is the case the M0 review caught). *)
type defaults =
  { margin_start : int
  ; margin_end : int
  ; margin_top : int
  ; margin_bottom : int
  ; halign : Gtk_enums.align
  ; valign : Gtk_enums.align
  ; hexpand : bool
  ; vexpand : bool
  ; sensitive : bool
  ; visible : bool
  ; tooltip : string option
  ; size_request : int * int
  ; opacity : float
  ; focusable : bool
  ; can_focus : bool
  ; widget_name : string
  ; cursor : Ocgtk_gdk.Gdk.Wrappers.Cursor.t option
  }

let snapshot (w : Widget.t) =
  { margin_start = Widget.get_margin_start w
  ; margin_end = Widget.get_margin_end w
  ; margin_top = Widget.get_margin_top w
  ; margin_bottom = Widget.get_margin_bottom w
  ; halign = Widget.get_halign w
  ; valign = Widget.get_valign w
  ; hexpand = Widget.get_hexpand w
  ; vexpand = Widget.get_vexpand w
  ; sensitive = Widget.get_sensitive w
  ; visible = Widget.get_visible w
  ; tooltip = Widget.get_tooltip_text w
  ; size_request = Widget.get_size_request w
  ; opacity = Widget.get_opacity w
  ; focusable = Widget.get_focusable w
  ; can_focus = Widget.get_can_focus w
  ; widget_name = Widget.get_name w
  ; cursor = Widget.get_cursor w
  }
;;

(* GTK exposes width and height as a single [set_size_request] call, so setting one
   requires reading the current pair back to preserve the other. *)
let set_width (w : Widget.t) width =
  let _, height = Widget.get_size_request w in
  Widget.set_size_request w width height
;;

let set_height (w : Widget.t) height =
  let width, _ = Widget.get_size_request w in
  Widget.set_size_request w width height
;;

let set (w : Widget.t) (attr : Attr.t) =
  match attr with
  | Css_class c -> Widget.add_css_class w c
  | Margin_start n -> Widget.set_margin_start w n
  | Margin_end n -> Widget.set_margin_end w n
  | Margin_top n -> Widget.set_margin_top w n
  | Margin_bottom n -> Widget.set_margin_bottom w n
  | Halign a -> Widget.set_halign w (align a)
  | Valign a -> Widget.set_valign w (align a)
  | Hexpand b -> Widget.set_hexpand w b
  | Vexpand b -> Widget.set_vexpand w b
  | Sensitive b -> Widget.set_sensitive w b
  | Visible b -> Widget.set_visible w b
  | Tooltip s -> Widget.set_tooltip_text w (Some s)
  | Width_request n -> set_width w n
  | Height_request n -> set_height w n
  | Opacity f -> Widget.set_opacity w f
  | Focusable b -> Widget.set_focusable w b
  | Can_focus b -> Widget.set_can_focus w b
  | Widget_name s -> Widget.set_name w s
  | Cursor_name s -> Widget.set_cursor_from_name w (Some s)
  (* [Test_id] is inert at runtime; the [On_*] attrs are handled by [Signals]; the
     container-placement attrs ([Measure_overlay], [Page_title], [Grid_cell]) are read by
     the *parent* impl's child ops, not applied to the child. [Many] is flattened away by
     [Attrs.of_list] and never reaches here. *)
  | Test_id _ | Many _ -> ()
  | On_clicked _ -> ()
;;

let unset (d : defaults) (w : Widget.t) (name : Attr.Name.t) =
  match name with
  | Margin_start -> Widget.set_margin_start w d.margin_start
  | Margin_end -> Widget.set_margin_end w d.margin_end
  | Margin_top -> Widget.set_margin_top w d.margin_top
  | Margin_bottom -> Widget.set_margin_bottom w d.margin_bottom
  | Halign -> Widget.set_halign w d.halign
  | Valign -> Widget.set_valign w d.valign
  | Hexpand -> Widget.set_hexpand w d.hexpand
  | Vexpand -> Widget.set_vexpand w d.vexpand
  | Sensitive -> Widget.set_sensitive w d.sensitive
  | Visible -> Widget.set_visible w d.visible
  | Tooltip -> Widget.set_tooltip_text w d.tooltip
  | Width_request -> set_width w (fst d.size_request)
  | Height_request -> set_height w (snd d.size_request)
  | Opacity -> Widget.set_opacity w d.opacity
  | Focusable -> Widget.set_focusable w d.focusable
  | Can_focus -> Widget.set_can_focus w d.can_focus
  | Widget_name -> Widget.set_name w d.widget_name
  | Cursor_name -> Widget.set_cursor w d.cursor
  | Test_id -> ()
  | On_clicked -> ()
;;

let apply ~defaults w (op : Attrs.op) =
  match op with
  | Set a -> set w a
  | Unset n -> unset defaults w n
  | Add_css_class c -> Widget.add_css_class w c
  | Remove_css_class c -> Widget.remove_css_class w c
;;

let apply_all w attrs = List.iter (Attrs.to_list attrs) ~f:(set w)
```

`src/dune`: add `ocgtk.gdkpixbuf`? No — `Ocgtk_gdk` is already there via `ocgtk.gdk`. Add only `ocgtk.pango` (Step 6 needs it).

The mli replaces the old `Width_request`/`Height_request` paragraph with:

```ocaml
(** Every attribute value [unset] can restore, read off a widget before anything has been
    applied to it. Take one per widget at creation and keep it for the widget's lifetime;
    it is what makes "drop this attribute" mean "put back whatever GTK had", which differs
    per widget class ([focusable] on a button vs a label, [visible] on a window vs
    anything else) and which no constant could get right for all of them. *)
type defaults

val snapshot : Widget.t -> defaults
```

- [ ] **Step 6: `src/patcher.ml`** — `live` carries the defaults

```ocaml
type live =
  { mutable node : Node.t
  ; widget : Widget.t
  ; impl : Widget_impl.t
  ; defaults : Attr_apply.defaults
  ; slots : Signals.slots
  ; handler_ids : Gobject.Signal.handler_id list
  ; mutable children : live Children.t
  }
```

In `mount`, between `create` and `apply_all`:

```ocaml
  let widget = impl.create node.kind in
  (* Before any attr touches it: this is the widget class's own defaults. *)
  let defaults = Attr_apply.snapshot widget in
  Attr_apply.apply_all widget node.attrs;
```
and in `patch`, `~f:(Attr_apply.apply ~defaults:live.defaults live.widget)`.

- [ ] **Step 7: `vtree/kind.ml(i)` and `vtree/node.ml(i)`** — Label's props

```ocaml
  | Label of
      { text : string
      ; wrap : bool
      ; xalign : float
      ; ellipsize : Ellipsize.t option
      ; max_width_chars : int
      ; width_chars : int
      ; selectable : bool
      ; use_markup : bool
      }
```

`equal_props`:
```ocaml
  | Label a, Label b ->
    String.equal a.text b.text
    && Bool.equal a.wrap b.wrap
    && Float.equal a.xalign b.xalign
    && Option.equal Ellipsize.equal a.ellipsize b.ellipsize
    && a.max_width_chars = b.max_width_chars
    && a.width_chars = b.width_chars
    && Bool.equal a.selectable b.selectable
    && Bool.equal a.use_markup b.use_markup
```

`Node.label` — every default is GTK's own, so a `Node.label "x"` still produces the widget M0 produced:
```ocaml
let label
  ?key
  ?attrs
  ?(wrap = false)
  ?(xalign = 0.5)
  ?ellipsize
  ?(max_width_chars = -1)
  ?(width_chars = -1)
  ?(selectable = false)
  ?(use_markup = false)
  text
  =
  make
    ?key
    ?attrs
    (Label
       { text; wrap; xalign; ellipsize; max_width_chars; width_chars; selectable; use_markup })
    No_children
;;
```

- [ ] **Step 8: `src/widgets/w_label.ml`**

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

(* Only the props that differ are written: [set_text] and [set_markup] both reset the
   label's attribute list, and [set_ellipsize] forces a re-layout. *)
let apply_props (l : W.Label.t) (p : Kind.label_props) ~(old : Kind.label_props option) =
  let changed field equal = match old with
    | None -> true
    | Some o -> not (equal (field o) (field p))
  in
  if changed (fun p -> p.Kind.text) String.equal
     || changed (fun p -> p.Kind.use_markup) Bool.equal
  then if p.use_markup then W.Label.set_markup l p.text else W.Label.set_text l p.text;
  if changed (fun p -> p.Kind.wrap) Bool.equal then W.Label.set_wrap l p.wrap;
  if changed (fun p -> p.Kind.xalign) Float.equal then W.Label.set_xalign l p.xalign;
  if changed (fun p -> p.Kind.ellipsize) (Option.equal Ellipsize.equal)
  then W.Label.set_ellipsize l (ellipsize p.ellipsize);
  if changed (fun p -> p.Kind.max_width_chars) Int.equal
  then W.Label.set_max_width_chars l p.max_width_chars;
  if changed (fun p -> p.Kind.width_chars) Int.equal
  then W.Label.set_width_chars l p.width_chars;
  if changed (fun p -> p.Kind.selectable) Bool.equal
  then W.Label.set_selectable l p.selectable
;;

let impl : Widget_impl.t =
  { name = "Label"
  ; create =
      (fun (kind : Kind.t) ->
        match kind with
        | Label p ->
          let l = W.Label.new_ None in
          apply_props l p ~old:None;
          (l :> Widget.t)
        | k -> Widget_impl.wrong_kind "Label" k)
  ; update =
      (fun w ~(old : Kind.t) (new_ : Kind.t) ->
        match old, new_ with
        | Label old, Label new_ -> apply_props (cast w) new_ ~old:(Some old)
        | _, k -> Widget_impl.wrong_kind "Label" k)
  ; signals = []
  ; children = Widget_impl.No_children
  }
;;
```

This needs the inline record to be nameable. Give `Kind` a named props type rather than an inline record for `Label`:

```ocaml
(* vtree/kind.ml(i) *)
type label_props =
  { text : string
  ; wrap : bool
  ; xalign : float
  ; ellipsize : Ellipsize.t option
  ; max_width_chars : int
  ; width_chars : int
  ; selectable : bool
  ; use_markup : bool
  }
[@@deriving sexp_of, equal]

type t =
  | Label of label_props
  | ...
```
and use `Kind.equal_label_props` in `equal_props` instead of the hand-written conjunction. **Adopt this shape for every M1 widget**: a named `<widget>_props` record with `[@@deriving sexp_of, equal]`, so `equal_props` is one call per kind and impls can name the record. Migrate `Button`/`Box`/`Window` to it in this task too — three small mechanical edits that every later task benefits from. `Kind.t`'s sexp changes shape slightly (an inline record and a named one print the same, so expect files are unaffected — confirm by running the suite).

- [ ] **Step 9: `src/live_tree.ml`** — print the new widget-wide props and the label ones

```ocaml
let float_prop name value ~default =
  if Float.equal value default
  then []
  else [ Sexp.List [ Atom name; Atom (sprintf "%g" value) ] ]
;;

let string_prop name value ~default =
  if String.equal value default then [] else [ Sexp.List [ Atom name; Atom value ] ]
;;
```
extend `layout_props` with `float_prop "opacity" (Widget.get_opacity w) ~default:1.`, `string_prop "name" (Widget.get_name w) ~default:""`, and a `cursor` line: `(match Widget.get_cursor w with None -> [] | Some c -> [ Sexp.List [ Atom "cursor"; Atom (Option.value (Ocgtk_gdk.Gdk.Wrappers.Cursor.get_name c) ~default:"?") ] ])`. Do **not** print `focusable`/`can_focus`: their defaults are per class, so an unconditional print would churn every expected file; print them only when they differ from the value a freshly created widget of that type has, which the dump has no access to. Instead, cover them in the attr round-trip section of the live test, which sets and then unsets them and asserts the *dump is identical* to a widget that never had them.

In `dump`'s per-type match, extend the `"GtkLabel"` arm:
```ocaml
     | "GtkLabel" ->
       let l = cast w in
       [ [%sexp `text (W.Label.get_text l : string)] ]
       @ flag_prop "wrap" (W.Label.get_wrap l)
       @ float_prop "xalign" (W.Label.get_xalign l) ~default:0.5
       @ (match W.Label.get_ellipsize l with
          | `NONE -> []
          | e -> [ Sexp.List [ Atom "ellipsize"; Atom (Sexp.to_string [%sexp (e : [`NONE|`START|`MIDDLE|`END])]) ] ])
       @ int_prop "max-width-chars" (W.Label.get_max_width_chars l) ~default:(-1)
       @ int_prop "width-chars" (W.Label.get_width_chars l) ~default:(-1)
       @ flag_prop "selectable" (W.Label.get_selectable l)
```
(The ellipsize polymorphic variant has no `sexp_of`; if `[%sexp]` on it does not compile, write a three-line `ellipsize_name` function beside `align_name` — that is the pattern `Live_tree` already uses.)

- [ ] **Step 10: Extend `test/live/live_patcher.ml`'s attr section**

In the existing `attr_view` block, add the five new attrs to the set-then-unset list:
```ocaml
         ; Attr.opacity 0.5
         ; Attr.focusable true
         ; Attr.can_focus false
         ; Attr.widget_name "styled-label"
         ; Attr.cursor_name "pointer"
```
and add, after it, the case the defaults snapshot exists for — unsetting `visible` on a window must not turn a window visible:
```ocaml
  (* A [GtkWindow] is created hidden; a [GtkLabel] is created visible. "Unset" means "put
     back what this widget had", not a constant, so the same op restores different values
     here. *)
  let live = P.mount ctx ~path:"root" ~is_root:true (Node.window ~attrs:[ Attr.visible true ] ~title:"vis" (Node.label ~attrs:[ Attr.visible false ] "l")) in
  print_s (Live_tree.dump live.widget);
  let live = P.patch ctx ~path:"root" ~is_root:true live (Node.window ~title:"vis" (Node.label "l")) in
  print_s (Live_tree.dump live.widget);
  P.destroy ctx live;
```
Expected on the second dump: the window is `hidden` again and the label is not. Promote after reading.

- [ ] **Step 11: Run, promote, gate**

```
dune build @test/runtest && dune promote
BONSAI_GTK_LIVE_TESTS=1 xvfb-run -a dune build @test/live/runtest && dune promote
./scripts/ci.sh
```

- [ ] **Step 12: Commit**

```bash
dune fmt 2>/dev/null; git add vtree src test
GIT_EDITOR=true git commit -F - <<'MSG'
Widget-wide attrs (opacity, focus, name, cursor) and Label's text properties

Unsetting an attribute now restores the value the widget was created with,
snapshotted per widget at mount, rather than a constant guessed per attribute
-- which was already wrong for [visible] on a GtkWindow and would have been
wrong for [focusable] on every widget M1 adds.

Kind's props become named records so widget impls can name them.

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01Sg3Ci8U8kUKR8C3PL1pNSs
MSG
```

---

