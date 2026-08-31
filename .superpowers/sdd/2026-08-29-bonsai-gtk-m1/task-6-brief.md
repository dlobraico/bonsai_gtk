### Task 6: Image, Picture, Separator — and `Node.native`'s first shipped widget

`Node.native` itself landed in M0 (spec §6.6); what M1 owes it is a *use*: a widget the library ships, built on the escape hatch, that could not be a `Kind.t` because its input is an ocgtk type the vtree may not mention. `GtkPicture` fed a `GdkPaintable` is exactly that case — and it is exactly what stavekeeper needs (`ink_mode.ml` and `viewer_window.ml` both push a `Gdk.Memory_texture` into a `GtkPicture` every frame), alongside the plain filename-backed `Picture` that `cards.ml` uses for thumbnails.

Read `~/src/stavekeeper/lib/stavekeeper_app/cards.ml` first, in particular the comment at the top: it is a precise account of why a `GtkPicture` needs `can_shrink` + `CONTAIN` + an unmeasured overlay child to be size-controlled, and Task 8's `Overlay` is the other half of it.

**Files:**
- Create: `vtree/content_fit.ml`, `vtree/icon_size.ml`, `vtree/image_source.ml`, `vtree/picture_source.ml`, `src/widgets/w_image.ml`, `src/widgets/w_picture.ml`, `src/widgets/w_separator.ml`, `src/paintable_picture.ml`, `src/paintable_picture.mli`, `test/live/live_containers.ml`, `test/live/expected_containers.txt`
- Modify: `vtree/kind.ml(i)`, `vtree/node.ml(i)`, `vtree/bonsai_gtk_vtree.ml`, `src/widgets/registry.ml`, `src/live_tree.ml`, `src/bonsai_gtk.ml(i)`, `test/test_widgets.ml`, `test/live/dune`

**Interfaces:**
- Produces:
  ```ocaml
  (* vtree *)
  module Content_fit : sig type t = Fill | Contain | Cover | Scale_down end
  module Icon_size   : sig type t = Inherit | Normal | Large end
  module Image_source : sig
    type t = Empty | Icon_name of string | File of string | Resource of string
  end
  module Picture_source : sig
    type t = Empty | Filename of string | Resource of string
  end

  (* Node *)
  val image
    :  ?key:Key.t -> ?attrs:Attr.t list -> ?pixel_size:int -> ?icon_size:Icon_size.t
    -> Image_source.t -> t
  val picture
    :  ?key:Key.t -> ?attrs:Attr.t list -> ?content_fit:Content_fit.t -> ?can_shrink:bool
    -> ?alternative_text:string -> Picture_source.t -> t
  val separator : ?key:Key.t -> ?attrs:Attr.t list -> orientation:Orientation.t -> t

  (* Bonsai_gtk.Native.Picture — the runtime's own native widget *)
  val node
    :  ?key:Key.t -> ?attrs:Attr.t list -> ?content_fit:Content_fit.t -> ?can_shrink:bool
    -> Ocgtk_gdk.Gdk.Wrappers.Paintable.t option
    -> Node.t
  ```
- Consumes: `W.Image.{new_,set_from_icon_name,set_from_file,set_from_resource,clear,set_pixel_size,set_icon_size}`, `W.Picture.{new_,set_filename,set_resource,set_paintable,set_content_fit,set_can_shrink,set_alternative_text}`, `W.Separator.new_`, `Ocgtk_gdk.Gdk.Wrappers.{Paintable,Texture}`, `Gobject.same`.

`Image_source`/`Picture_source` are variants rather than four optional arguments because the sources are mutually exclusive and GTK's setters do not compose: setting a file after an icon name silently wins, and there is no "which one is set" you can diff. A closed variant makes the exclusivity a type error instead, and gives `equal_props` one line.

- [ ] **Step 1: Failing headless test** (`test/test_widgets.ml`)

```ocaml
let%expect_test "images, pictures and separators" =
  print_s
    [%sexp
      (Node.box
         ~orientation:Vertical
         [ Node.image ~pixel_size:16 (Icon_name "list-add-symbolic")
         ; Node.image Empty
         ; Node.picture ~content_fit:Contain ~can_shrink:true (Filename "/tmp/thumb.png")
         ; Node.separator ~orientation:Horizontal
         ]
       : Node.t)];
  [%expect {| |}]
;;
```

- [ ] **Step 2: Failing live test** — new file `test/live/live_containers.ml`

This file is Tasks 6–9's home. It needs an image on disk; make one rather than committing a fixture, so the test has no data dependency:

```ocaml
open! Core
open Bonsai_gtk_vtree
module Gdk = Ocgtk_gdk.Gdk
module Live_tree = Bonsai_gtk.Private.Live_tree
module P = Bonsai_gtk.Private.Patcher
module W = Bonsai_gtk.Private.Gtk_import.W

(* A 2x2 opaque texture, built in memory. [Gdk.Texture.save_to_png] then gives us a real
   PNG on disk for the filename-backed [Node.picture], so the test carries no fixture and
   the two Picture paths -- filename and paintable -- are exercised from one source. *)
let texture () =
  let bytes =
    Glib_bytes.of_bigstring
      (Bigstring.of_string "\255\000\000\255\000\255\000\255\000\000\255\255\255\255\255\255")
  in
  Gdk.Memory_texture.new_ 2 2 `R8G8B8A8_PREMULTIPLIED bytes
;;

let () =
  ignore (Ocgtk_gtk.GMain.init () : string array);
  let ctx : P.ctx =
    { signals =
        { schedule = (fun _ -> ())
        ; in_patch = (fun () -> false)
        ; on_exn = (fun ~node_path exn -> printf "EXN at %s: %s\n" node_path (Exn.to_string exn))
        }
    ; on_window_created = (fun _ -> ())
    }
  in
  let tex = texture () in
  let png = Filename.temp_file "bonsai_gtk" ".png" in
  ignore (Gdk.Texture.save_to_png (cast tex) png : bool);
  let view =
    Node.window
      ~title:"media"
      (Node.box
         ~orientation:Vertical
         [ Node.image ~pixel_size:16 (Icon_name "list-add-symbolic")
         ; Node.image Empty
         ; Node.picture ~content_fit:Contain ~can_shrink:true (Filename png)
         ; Bonsai_gtk.Native.Picture.node
             ~content_fit:Cover
             (Some (Gdk.Wrappers.Paintable.from_gobject tex))
         ; Node.separator ~orientation:Horizontal
         ])
  in
  let live = P.mount ctx ~path:"root" ~is_root:true view in
  print_s (Live_tree.dump live.widget);
  (* Swapping an image's source kind must reach GTK, not just the node. *)
  let live =
    P.patch
      ctx
      ~path:"root"
      ~is_root:true
      live
      (Node.window
         ~title:"media"
         (Node.box
            ~orientation:Vertical
            [ Node.image ~pixel_size:16 (File png)
            ; Node.image (Icon_name "edit-find-symbolic")
            ; Node.picture ~content_fit:Cover ~can_shrink:false Empty
            ; Bonsai_gtk.Native.Picture.node ~content_fit:Cover None
            ; Node.separator ~orientation:Vertical
            ]))
  in
  print_s (Live_tree.dump live.widget);
  P.destroy ctx live;
  Core_unix.unlink png
;;
```
(`Core_unix` may not be a dependency of `test/live`; `Sys_unix.remove` or simply leaving the temp file is fine — pick whatever keeps the dune stanza small, and note that the file lives in the sandbox anyway.)

Add `live_containers` to `test/live/dune`'s `(names ...)`, its rule, and `ocgtk.gdk` to that stanza's libraries.

- [ ] **Step 3: The four vtree enum modules**

```ocaml
(* vtree/content_fit.ml *)
open! Core

(** How a [Node.picture] scales its image into the space it is given. [Contain] letterboxes,
    [Cover] crops, [Fill] stretches, [Scale_down] shrinks but never enlarges. Paired with
    [can_shrink], which is what lets the widget be *smaller* than its image at all. *)
type t =
  | Fill
  | Contain
  | Cover
  | Scale_down
[@@deriving sexp_of, equal, compare]

(* vtree/icon_size.ml *)
open! Core

type t =
  | Inherit
  | Normal
  | Large
[@@deriving sexp_of, equal, compare]

(* vtree/image_source.ml *)
open! Core

(** Where a [Node.image] gets its picture. The alternatives are a closed variant rather
    than four optional arguments because GTK's setters do not compose -- setting a file
    after an icon name silently wins, and nothing tells you which one is live. *)
type t =
  | Empty
  | Icon_name of string
  | File of string
  | Resource of string
[@@deriving sexp_of, equal, compare]

(* vtree/picture_source.ml *)
open! Core

(** Where a [Node.picture] gets its image. A [GdkPaintable] source -- a texture the
    application rendered -- is not here: the vtree may not mention ocgtk types. Use
    [Bonsai_gtk.Native.Picture] for that. *)
type t =
  | Empty
  | Filename of string
  | Resource of string
[@@deriving sexp_of, equal, compare]
```
Add all four to `vtree/bonsai_gtk_vtree.ml` and re-export from `src/bonsai_gtk.ml(i)`.

- [ ] **Step 4: `vtree/kind.ml(i)` / `node.ml(i)`**

```ocaml
type image_props =
  { source : Image_source.t
  ; pixel_size : int
  ; icon_size : Icon_size.t
  }
[@@deriving sexp_of, equal]

type picture_props =
  { source : Picture_source.t
  ; content_fit : Content_fit.t
  ; can_shrink : bool
  ; alternative_text : string option
  }
[@@deriving sexp_of, equal]

type separator_props = { orientation : Orientation.t } [@@deriving sexp_of, equal]
```
Defaults: `pixel_size = -1` (GTK's "derive from icon size"), `icon_size = Inherit`, `content_fit = Contain`, `can_shrink = true`.

- [ ] **Step 5: `src/widgets/w_image.ml`**

```ocaml
open! Core
open Bonsai_gtk_vtree
open Gtk_import

let icon_size : Icon_size.t -> Gtk_enums.iconsize = function
  | Inherit -> `INHERIT
  | Normal -> `NORMAL
  | Large -> `LARGE
;;

(* One call per source, and [clear] for [Empty]: GTK keeps whichever source was set last,
   so switching kinds has to go through the new kind's setter, and switching *to* nothing
   has to go through [clear] -- [set_from_icon_name w None] leaves a previously set file
   in place. *)
let set_source (i : W.Image.t) (source : Image_source.t) =
  match source with
  | Empty -> W.Image.clear i
  | Icon_name name -> W.Image.set_from_icon_name i (Some name)
  | File path -> W.Image.set_from_file i (Some path)
  | Resource path -> W.Image.set_from_resource i (Some path)
;;

let impl : Widget_impl.t =
  { name = "Image"
  ; create =
      (fun (kind : Kind.t) ->
        match kind with
        | Image p ->
          let i = W.Image.new_ () in
          let w = (i :> Widget.t) in
          Widget_impl.batch w (fun () ->
            set_source i p.source;
            if p.pixel_size <> -1 then W.Image.set_pixel_size i p.pixel_size;
            W.Image.set_icon_size i (icon_size p.icon_size));
          w
        | k -> Widget_impl.wrong_kind "Image" k)
  ; update =
      (fun w ~(old : Kind.t) (new_ : Kind.t) ->
        match old, new_ with
        | Image old, Image new_ ->
          let i : W.Image.t = cast w in
          Widget_impl.batch w (fun () ->
            if not (Image_source.equal old.source new_.source) then set_source i new_.source;
            if old.pixel_size <> new_.pixel_size
            then W.Image.set_pixel_size i new_.pixel_size;
            if not (Icon_size.equal old.icon_size new_.icon_size)
            then W.Image.set_icon_size i (icon_size new_.icon_size))
        | _, k -> Widget_impl.wrong_kind "Image" k)
  ; signals = []
  ; children = Widget_impl.No_children
  }
;;
```
`set_from_gicon` and `set_from_pixbuf` are not exposed: a `GIcon` and a `GdkPixbuf` are both ocgtk values, so they belong on the native side like `Paintable` does. Named in the mli.

- [ ] **Step 6: `src/widgets/w_picture.ml`**

```ocaml
open! Core
open Bonsai_gtk_vtree
open Gtk_import

let content_fit : Content_fit.t -> Gtk_enums.contentfit = function
  | Fill -> `FILL
  | Contain -> `CONTAIN
  | Cover -> `COVER
  | Scale_down -> `SCALE_DOWN
;;

(* Same rule as [W_image.set_source]: [Empty] goes through a setter that actually clears,
   which for GtkPicture is [set_paintable None] (there is no [clear]). *)
let set_source (p : W.Picture.t) (source : Picture_source.t) =
  match source with
  | Empty -> W.Picture.set_paintable p None
  | Filename path -> W.Picture.set_filename p (Some path)
  | Resource path -> W.Picture.set_resource p (Some path)
;;

let apply_props (p : W.Picture.t) ~content_fit:cf ~can_shrink ~alternative_text =
  W.Picture.set_content_fit p (content_fit cf);
  W.Picture.set_can_shrink p can_shrink;
  W.Picture.set_alternative_text p alternative_text
;;

let impl : Widget_impl.t =
  { name = "Picture"
  ; create =
      (fun (kind : Kind.t) ->
        match kind with
        | Picture props ->
          let p = W.Picture.new_ () in
          let w = (p :> Widget.t) in
          Widget_impl.batch w (fun () ->
            set_source p props.source;
            apply_props
              p
              ~content_fit:props.content_fit
              ~can_shrink:props.can_shrink
              ~alternative_text:props.alternative_text);
          w
        | k -> Widget_impl.wrong_kind "Picture" k)
  ; update =
      (fun w ~(old : Kind.t) (new_ : Kind.t) ->
        match old, new_ with
        | Picture old, Picture new_ ->
          let p : W.Picture.t = cast w in
          Widget_impl.batch w (fun () ->
            if not (Picture_source.equal old.source new_.source)
            then set_source p new_.source;
            if not (Content_fit.equal old.content_fit new_.content_fit)
            then W.Picture.set_content_fit p (content_fit new_.content_fit);
            if not (Bool.equal old.can_shrink new_.can_shrink)
            then W.Picture.set_can_shrink p new_.can_shrink;
            if not (Option.equal String.equal old.alternative_text new_.alternative_text)
            then W.Picture.set_alternative_text p new_.alternative_text)
        | _, k -> Widget_impl.wrong_kind "Picture" k)
  ; signals = []
  ; children = Widget_impl.No_children
  }
;;
```
Doc-comment note for `Node.picture`, lifted from stavekeeper's hard-won comment: "`Attr.width_request`/`height_request` raise a picture's *minimum* size but not its *natural* one, which GTK derives from the image's own pixel dimensions — so a homogeneous container still sizes to the image. To cap the allocated size, put the picture in an `Overlay` as an unmeasured overlay (`Attr.measure_overlay false`) over a spacer sized with `width_request`/`height_request`, and use `~can_shrink:true ~content_fit:Contain`."

- [ ] **Step 7: `src/widgets/w_separator.ml`**

```ocaml
open! Core
open Bonsai_gtk_vtree
open Gtk_import

let orientation : Orientation.t -> Gtk_enums.orientation = function
  | Horizontal -> `HORIZONTAL
  | Vertical -> `VERTICAL
;;

let impl : Widget_impl.t =
  { name = "Separator"
  ; create =
      (fun (kind : Kind.t) ->
        match kind with
        | Separator { orientation = o } -> (W.Separator.new_ (orientation o) :> Widget.t)
        | k -> Widget_impl.wrong_kind "Separator" k)
  ; update =
      (fun w ~(old : Kind.t) (new_ : Kind.t) ->
        match old, new_ with
        | Separator old, Separator new_ ->
          if not (Orientation.equal old.orientation new_.orientation)
          then
            W.Orientable.set_orientation
              (W.Orientable.from_gobject w)
              (orientation new_.orientation)
        | _, k -> Widget_impl.wrong_kind "Separator" k)
  ; signals = []
  ; children = Widget_impl.No_children
  }
;;
```

- [ ] **Step 8: `src/paintable_picture.ml(i)` — the library's own native widget**

```ocaml
open! Core
open Bonsai_gtk_vtree
open Gtk_import
module Paintable = Ocgtk_gdk.Gdk.Wrappers.Paintable

module Input = struct
  type t =
    { paintable : Paintable.t option
    ; content_fit : Content_fit.t
    ; can_shrink : bool
    }

  (* [Gobject.same] rather than [phys_equal]: every C-to-OCaml crossing allocates a fresh
     wrapper block for the same pointer, so two handles to one texture are never
     physically equal (spec §2.2). *)
  let same_paintable a b =
    match a, b with
    | None, None -> true
    | Some a, Some b -> Gobject.same a b
    | None, Some _ | Some _, None -> false
  ;;

  let equal a b =
    same_paintable a.paintable b.paintable
    && Content_fit.equal a.content_fit b.content_fit
    && Bool.equal a.can_shrink b.can_shrink
  ;;
end

module M = struct
  type input = Input.t

  let name = "picture(paintable)"

  let apply (p : W.Picture.t) (i : Input.t) =
    W.Picture.set_paintable p i.paintable;
    W.Picture.set_content_fit p (W_picture.content_fit i.content_fit);
    W.Picture.set_can_shrink p i.can_shrink
  ;;

  let create (i : Input.t) =
    let p = W.Picture.new_ () in
    apply p i;
    (p :> Widget.t)
  ;;

  (* [update] runs on every re-render, not only when the input changed (see
     [Native_gtk.S]'s doc comment): the patcher compares native payloads physically and a
     fresh payload is allocated each frame. Hence the explicit [Input.equal]. *)
  let update w ~old i = if not (Input.equal old i) then apply (cast w) i

  (* The widget's reference to the paintable is GTK's business; nothing was acquired here
     that outlives it. *)
  let destroy _ = ()
end

(* Built once, at the top level, as every [Native_gtk.impl] must be: the impl carries the
   type witness the patcher matches on, so one per render would be a different widget. *)
let impl = Native_gtk.impl (module M)

let node ?key ?attrs ?(content_fit = Content_fit.Contain) ?(can_shrink = true) paintable =
  Native_gtk.node ?key ?attrs impl { Input.paintable; content_fit; can_shrink }
;;
```
`w_picture.ml` must expose `content_fit` (drop it from the `let`-private list — it is already top-level, so nothing to do beyond not shadowing it).

The mli:
```ocaml
(** A [GtkPicture] fed a [GdkPaintable] -- a texture the application rendered itself,
    typically a [Gdk.Memory_texture] built from pixels it owns.

    This is the library's own use of {!Bonsai_gtk.Native}: the input is an ocgtk value, and
    [bonsai_gtk.vtree] may not mention ocgtk types, so it cannot be a [Kind.t] and a
    [Node.picture] cannot take it. It is also the worked example to copy when an
    application needs a widget of its own.

    The paintable is compared with [Gobject.same], not [phys_equal]: ocgtk allocates a
    fresh wrapper for the same GObject on every crossing, so physical equality on these
    handles is always false. Keeping the *same* texture across renders therefore costs
    nothing; building a new one each frame re-uploads it, which is the caller's decision to
    make. *)
val node
  :  ?key:Key.t
  -> ?attrs:Attr.t list
  -> ?content_fit:Content_fit.t
  -> ?can_shrink:bool
  -> Ocgtk_gdk.Gdk.Wrappers.Paintable.t option
  -> Node.t
```
Expose it as `Bonsai_gtk.Native.Picture` in `src/bonsai_gtk.ml(i)`:
```ocaml
module Native = struct
  module type S = Native_gtk.S
  type 'a impl = 'a Native_gtk.impl
  let impl = Native_gtk.impl
  let node = Native_gtk.node
  module Picture = Paintable_picture
end
```

- [ ] **Step 9: Registry, `Live_tree`**

```ocaml
  | Image _ -> W_image.impl
  | Picture _ -> W_picture.impl
  | Separator _ -> W_separator.impl
```
```ocaml
     | "GtkImage" ->
       (match W.Image.get_icon_name (cast w) with
        | None -> []
        | Some n -> [ Sexp.List [ Atom "icon"; Atom n ] ])
       @ int_prop "pixel-size" (W.Image.get_pixel_size (cast w)) ~default:(-1)
     | "GtkPicture" ->
       flag_prop "has-paintable" (Option.is_some (W.Picture.get_paintable (cast w)))
       @ flag_prop "can-shrink" (W.Picture.get_can_shrink (cast w))
```
Print `has-paintable` rather than anything about the paintable itself: a texture's identity is not stable across runs and its pixels are not what the test is claiming.

- [ ] **Step 10: Run, read, promote, `./scripts/ci.sh`.**
Watch for: the filename-backed picture reporting `has-paintable` (GTK loads the file into a texture, so it does), and the second dump showing the swapped sources — the first image gains a file (so loses its `icon`), the second gains an icon, the third loses its paintable and its `can-shrink`.

- [ ] **Step 11: Commit**

```bash
dune fmt 2>/dev/null; git add vtree src test test/live
GIT_EDITOR=true git commit -F - <<'MSG'
Image, Picture, Separator, and Native.Picture for paintable sources

Image and Picture sources are closed variants rather than optional arguments:
GTK's setters do not compose, so exclusivity has to be a type error.

Native.Picture is the library's first shipped Node.native widget -- a
GtkPicture fed a GdkPaintable, which cannot be a Kind.t because the vtree may
not name ocgtk types. It is also the worked example applications copy.

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01Sg3Ci8U8kUKR8C3PL1pNSs
MSG
```

---

