open! Core
open Bonsai_gtk_vtree
module Gdk = Ocgtk_gdk.Gdk
module Gobject = Bonsai_gtk.Private.Gtk_import.Gobject
module Live_tree = Bonsai_gtk.Private.Live_tree
module P = Bonsai_gtk.Private.Patcher
module Scheduler = Bonsai_gtk.Private.Scheduler
module W = Bonsai_gtk.Private.Gtk_import.W

let cast = Bonsai_gtk.Private.Gtk_import.cast

(* The n'th child of the window's box, as a live GTK widget: how the test gets at one
   widget's identity across a patch. *)
let nth_child (live : P.live) i =
  match live.children with
  | Single (Some box) ->
    (match box.children with
     | List children -> (List.nth_exn children i).P.widget
     | No_children | Single _ | Slots _ -> assert false)
  | No_children | Single None | List _ | Slots _ -> assert false
;;

(* A 2x2 opaque texture, built in memory. [Gdk.Wrappers.Texture.save_to_png] then gives us
   a real PNG on disk for the filename-backed [Node.picture], so the test carries no
   fixture and the two Picture paths -- filename and paintable -- are exercised from one
   source. *)
let texture pixels =
  let bytes = Glib_bytes.of_bigstring (Bigstring.of_string pixels) in
  (* Stride is the byte length of one row: 2 pixels of RGBA. *)
  Gdk.Wrappers.Memory_texture.new_ 2 2 `R8G8B8A8 bytes (Gsize.of_int 8)
;;

let () =
  ignore (Ocgtk_gtk.GMain.init () : string array);
  (* The media half of this file schedules nothing; the container half below counts, so
     the patch guard has to be the real one rather than a constant [false]. *)
  let scheduled = ref 0 in
  let scheduler = Scheduler.create ~run_frame:(fun () -> ()) in
  let ctx =
    P.create_ctx
      ~signals:
        { schedule = (fun _ -> incr scheduled)
        ; in_patch = (fun () -> Scheduler.in_patch scheduler)
        ; on_exn =
            (fun ~node_path exn -> printf "EXN at %s: %s\n" node_path (Exn.to_string exn))
        }
      ~on_window_created:(fun _ -> ())
  in
  let tex = texture "\255\000\000\255\000\255\000\255\000\000\255\255\255\255\255\255" in
  let png = Stdlib.Filename.temp_file "bonsai_gtk" ".png" in
  ignore (Gdk.Wrappers.Texture.save_to_png (tex :> Gdk.Wrappers.Texture.t) png : bool);
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
         ; Node.separator ~orientation:Horizontal ()
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
            ; Node.separator ~orientation:Vertical ()
            ]))
  in
  print_s (Live_tree.dump live.widget);
  (* The point of [Native.Picture]: a new texture every frame must reach the *same*
     [GtkPicture], not build another one. Both halves are asserted -- the widget is the
     same GObject across the patch, and the paintable it now holds is the new texture. *)
  let native_before = nth_child live 3 in
  let tex2 = texture "\000\000\255\255\255\255\000\255\255\000\255\255\000\255\255\255" in
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
            ; Bonsai_gtk.Native.Picture.node
                ~content_fit:Cover
                (Some (Gdk.Wrappers.Paintable.from_gobject tex2))
            ; Node.separator ~orientation:Vertical ()
            ]))
  in
  let native_after = nth_child live 3 in
  printf "same widget across the swap: %b\n" (Gobject.same native_before native_after);
  printf
    "shows the new texture: %b\n"
    (match W.Picture.get_paintable (cast native_after) with
     | None -> false
     | Some p -> Gobject.same p tex2);
  print_s (Live_tree.dump live.widget);
  P.destroy ctx live;
  (* A picture whose filename did not change must not have its source written again:
     [gtk_picture_set_filename] loads the file and builds a fresh [GdkTexture], so a
     source re-set on every frame re-reads from disk and hands the widget a different
     image to draw. Whether that happened is not visible in a props dump, but it is
     visible in the paintable's identity: the same [GdkTexture] across a patch that
     changed some other prop is a source the patch left alone. *)
  let same_file ~alt =
    Node.window
      ~title:"file"
      (Node.picture ~alternative_text:(if alt then "after" else "before") (Filename png))
  in
  let paintable (live : P.live) =
    match live.children with
    | Single (Some p) -> W.Picture.get_paintable (cast p.widget)
    | No_children | Single None | List _ | Slots _ -> assert false
  in
  let live = P.mount ctx ~path:"root" ~is_root:true (same_file ~alt:false) in
  let before = paintable live in
  let live = P.patch ctx ~path:"root" ~is_root:true live (same_file ~alt:true) in
  printf
    "same paintable across a patch that left the filename alone: %b\n"
    (Option.value_map
       (Option.both before (paintable live))
       ~default:false
       ~f:(fun (a, b) -> Gobject.same a b));
  P.destroy ctx live;
  Stdlib.Sys.remove png;
  (* Controlled [expanded] / [reveal], and the Single-child swap the patcher already
     handles: the frame's child changes kind, so the widget is replaced in place. *)
  let containers ~expanded ~reveal ~framed ~clipped =
    Node.window
      ~title:"containers"
      (* [clipped] flips every scrolled-window prop at once, so the second render covers
         each setter in the impl's [update] rather than only the ones the node happens to
         name. [External_] is stavekeeper's clipping idiom: no scrollbar, and the content
         does not get to dictate the size either. *)
      (Node.scrolled_window
         ~hpolicy:(if clipped then External_ else Never)
         ~vpolicy:(if clipped then Never else Automatic)
         ~min_content_height:(if clipped then 60 else 120)
         ~min_content_width:(if clipped then 80 else -1)
         ~max_content_height:(if clipped then 400 else -1)
         ~max_content_width:(if clipped then 300 else -1)
         ~propagate_natural_height:(not clipped)
         ~propagate_natural_width:clipped
         ~has_frame:clipped
         ~kinetic_scrolling:(not clipped)
         ~overlay_scrolling:(not clipped)
         (Node.box
            ~orientation:Vertical
            [ Node.frame
                ~label:(if clipped then "Renamed" else "Group")
                (if framed then Node.label "framed" else Node.button ~label:"framed" ())
            ; Node.expander
                ~attrs:[ Attr.on_expanded_changed (fun _ -> Ui_effect.Ignore) ]
                ~label:(if clipped then "Fewer" else "More")
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
    P.mount
      ctx
      ~path:"root"
      ~is_root:true
      (containers ~expanded:false ~reveal:false ~framed:true ~clipped:false)
  in
  print_s (Live_tree.dump live.widget);
  let live =
    P.patch
      ctx
      ~path:"root"
      ~is_root:true
      live
      (containers ~expanded:true ~reveal:true ~framed:false ~clipped:true)
  in
  print_s (Live_tree.dump live.widget);
  (* The three containers' children, reached through the patcher's own tree rather than
     GTK's: a [GtkScrolledWindow] interposes a [GtkViewport] around a non-scrollable
     child, so the live widget tree has a level the node tree does not. *)
  let boxed (live : P.live) i : P.live =
    match live.children with
    | Single (Some scroller) ->
      (match scroller.children with
       | Single (Some box) ->
         (match box.children with
          | List children -> List.nth_exn children i
          | No_children | Single _ | Slots _ -> assert false)
       | No_children | Single None | List _ | Slots _ -> assert false)
    | No_children | Single None | List _ | Slots _ -> assert false
  in
  (* Both specs are connected at all: outside a patch, each [notify::] reaches Bonsai. *)
  let before = !scheduled in
  Gobject.Property.notify (boxed live 1).widget ~name:"expanded";
  Gobject.Property.notify (boxed live 2).widget ~name:"child-revealed";
  printf "notify reaching Bonsai outside a patch: %d\n" (!scheduled - before);
  (* The controlled rule's other half (spec 6.5): flip both behind the model's back, then
     re-render the *same* props. [update] is skipped -- nothing in the tree moved -- so
     only [Widget_impl.reassert] is left to put the widgets back, and none of the writes
     may reach Bonsai. *)
  W.Expander.set_expanded (cast (boxed live 1).widget) false;
  W.Revealer.set_reveal_child (cast (boxed live 2).widget) false;
  let before = !scheduled in
  let live =
    Scheduler.with_patch_guard scheduler (fun () ->
      P.patch
        ctx
        ~path:"root"
        ~is_root:true
        live
        (containers ~expanded:true ~reveal:true ~framed:false ~clipped:true))
  in
  printf
    "declined expander %b, revealer %b (revealed %b); reached Bonsai: %d\n"
    (W.Expander.get_expanded (cast (boxed live 1).widget))
    (W.Revealer.get_reveal_child (cast (boxed live 2).widget))
    (W.Revealer.get_child_revealed (cast (boxed live 2).widget))
    (!scheduled - before);
  P.destroy ctx live;
  (* A scrolled window's [min_content_*] and [max_content_*] are not independent props:
     GTK's setters assert min <= max and *drop* the write when they do not, so the order
     the two are written in decides whether the widget ends up where the node says. Moving
     the width's bounds up, past where the old max was, needs max written first; moving
     the height's max down, below where the old min was, needs min written first. Both are
     in one patch, so an impl that picked either order unconditionally fails one half. *)
  let bounds ~raised =
    Node.window
      ~title:"bounds"
      (Node.scrolled_window
         ~min_content_width:(if raised then 400 else 80)
         ~max_content_width:(if raised then 600 else 300)
         ~min_content_height:(if raised then 20 else 100)
         ~max_content_height:(if raised then 60 else 500)
         (Node.label "content"))
  in
  let live = P.mount ctx ~path:"root" ~is_root:true (bounds ~raised:false) in
  let scroller (live : P.live) : W.Scrolled_window.t =
    match live.children with
    | Single (Some s) -> cast s.widget
    | No_children | Single None | List _ | Slots _ -> assert false
  in
  let show_bounds label live =
    let s = scroller live in
    printf
      "%s: width %d..%d, height %d..%d\n"
      label
      (W.Scrolled_window.get_min_content_width s)
      (W.Scrolled_window.get_max_content_width s)
      (W.Scrolled_window.get_min_content_height s)
      (W.Scrolled_window.get_max_content_height s)
  in
  show_bounds "mounted" live;
  let live = P.patch ctx ~path:"root" ~is_root:true live (bounds ~raised:true) in
  show_bounds "crossed" live;
  let live = P.patch ctx ~path:"root" ~is_root:true live (bounds ~raised:false) in
  show_bounds "back" live;
  P.destroy ctx live;
  (* Each container's [Single] slot on its own: the child's kind changes, so the patcher
     mounts a replacement and the container's [set] has to put it in the slot. The
     expander is opened for this, because a collapsed [GtkExpander] does not parent its
     child at all -- GTK adds and removes it as the expander opens and closes -- so a
     collapsed one would make the swap unobservable.

     Removal is not tested because it is not reachable: all four constructors take their
     child positionally, so none of them can produce [Single None]. *)
  let slots ~swapped =
    let child text = if swapped then Node.button ~label:text () else Node.label text in
    Node.window
      ~title:"slots"
      (Node.box
         ~orientation:Vertical
         [ Node.scrolled_window ~hpolicy:Never (child "scrolled")
         ; Node.frame (child "framed")
         ; Node.expander ~expanded:true (child "expanded")
         ; Node.revealer ~reveal:true (child "revealed")
         ])
  in
  let live = P.mount ctx ~path:"root" ~is_root:true (slots ~swapped:false) in
  print_s (Live_tree.dump live.widget);
  let live = P.patch ctx ~path:"root" ~is_root:true live (slots ~swapped:true) in
  print_s (Live_tree.dump live.widget);
  P.destroy ctx live;
  (* Opening an expander and changing its child in the same patch. A collapsed
     [GtkExpander] does not parent its child at all -- GTK adds and removes it as the
     expander opens and closes -- so this is the one child swap that happens while the
     container is rearranging itself underneath it, and the replacement has to end up in
     the slot either way round. *)
  let opening ~open_ =
    Node.window
      ~title:"opening"
      (Node.expander
         ~label:"detail"
         ~expanded:open_
         (if open_ then Node.button ~label:"after" () else Node.label "before"))
  in
  let live = P.mount ctx ~path:"root" ~is_root:true (opening ~open_:false) in
  print_s (Live_tree.dump live.widget);
  let live = P.patch ctx ~path:"root" ~is_root:true live (opening ~open_:true) in
  print_s (Live_tree.dump live.widget);
  P.destroy ctx live;
  (* Slots: each is patched independently, so clearing one and replacing another's child
     outright must leave the third alone. The overlay case is stavekeeper's thumbnail
     trick -- an unmeasured overlay over a sized spacer -- so [measure-overlay] is checked
     as a live property, not just a node, and is flipped false -> true -> false so the
     [updated] hook is seen writing in both directions. [extra], which names no attr, is
     unmeasured throughout: that is GTK's default and this library's. *)
  let slots ~center ~badge =
    Node.window
      ~title:"slots"
      (Node.paned
         ~attrs:[ Attr.on_position_changed (fun _ -> Ui_effect.Ignore) ]
         ~orientation:Horizontal
         ~position:120
         ~start:
           (Node.center_box
              ~start:(Node.label "L")
              ?center:(if center then Some (Node.label "C") else None)
                (* The [end] slot's *kind* changes across the patch, so the patcher mounts
                   a replacement and the slot's [set] has to install it -- the [Single]
                   swap, driven through a named slot rather than a whole container. *)
              ~end_:(if center then Node.button ~label:"R" () else Node.label "R")
              ())
         ~end_:
           (Node.overlay
              ~overlays:
                (Node.label ~key:"badge" ~attrs:[ Attr.measure_overlay badge ] "9"
                 :: (if badge then [ Node.label ~key:"extra" "+" ] else []))
              (Node.box
                 ~orientation:Vertical
                 ~attrs:[ Attr.width_request 150; Attr.height_request 60 ]
                 []))
         ())
  in
  let live = P.mount ctx ~path:"root" ~is_root:true (slots ~center:true ~badge:false) in
  print_s (Live_tree.dump live.widget);
  let live =
    P.patch ctx ~path:"root" ~is_root:true live (slots ~center:false ~badge:true)
  in
  print_s (Live_tree.dump live.widget);
  let live =
    P.patch ctx ~path:"root" ~is_root:true live (slots ~center:true ~badge:false)
  in
  print_s (Live_tree.dump live.widget);
  (* [Attr.on_position_changed] is informative rather than corrective -- a paned's
     [position] is the documented exception to the controlled rule -- so all there is to
     check is that its spec is connected at all. *)
  let paned : P.live =
    match live.children with
    | Single (Some p) -> p
    | No_children | Single None | List _ | Slots _ -> assert false
  in
  let before = !scheduled in
  Gobject.Property.notify paned.widget ~name:"position";
  printf "paned notify reaching Bonsai: %d\n" (!scheduled - before);
  (* A slot mismatch -- a name or a shape the impl does not have -- is structural misuse
     like a nested window, and the patcher raises on it rather than dropping the child.
     There is nothing here that can provoke it: every [Slots] node comes from a
     constructor whose slot list is written beside the impl's. *)
  P.destroy ctx live;
  (* An overlay is *unordered*: [Widget_impl.list_ops.move] is [None] for it, so the
     patcher passes [~ordered:false] to [Reconcile.diff] and no [Move] is emitted at all.
     What that must not cost is identity. Rendering the same three keyed overlays in two
     different orders has to leave GTK exactly as it was: the same three widgets, in the
     same painting order, each still showing its own text -- which is the half a
     positional match would break, since a mis-match would repaint child 0 with child 2's
     text.

     This is the claim [~ordered:false] is *for*, and until now nothing tested it: the
     only overlay reorder in this file changes the child list's length as well. *)
  let unordered ~overlays =
    Node.window
      ~title:"unordered"
      (Node.overlay
         ~overlays:(List.map overlays ~f:(fun k -> Node.label ~key:k ("item " ^ k)))
         (Node.box
            ~orientation:Vertical
            ~attrs:[ Attr.width_request 40; Attr.height_request 20 ]
            []))
  in
  let overlay_widgets (live : P.live) =
    match live.children with
    | Single (Some ov) ->
      (match ov.P.children with
       | Slots slots ->
         (match List.Assoc.find_exn slots "overlays" ~equal:String.equal with
          | Children.List cs -> List.map cs ~f:(fun (l : P.live) -> l.P.widget)
          | No_children | Single _ | Slots _ -> assert false)
       | No_children | Single _ | List _ -> assert false)
    | No_children | Single None | List _ | Slots _ -> assert false
  in
  let live =
    P.mount ctx ~path:"root" ~is_root:true (unordered ~overlays:[ "a"; "b"; "c" ])
  in
  print_s (Live_tree.dump live.widget);
  let mounted = overlay_widgets live in
  let same_widgets live =
    match List.for_all2 mounted (overlay_widgets live) ~f:Gobject.same with
    | Ok b -> b
    | Unequal_lengths -> false
  in
  let live =
    P.patch ctx ~path:"root" ~is_root:true live (unordered ~overlays:[ "c"; "a"; "b" ])
  in
  print_s (Live_tree.dump live.widget);
  printf "same overlay widgets after one reorder: %b\n" (same_widgets live);
  let live =
    P.patch ctx ~path:"root" ~is_root:true live (unordered ~overlays:[ "b"; "c"; "a" ])
  in
  print_s (Live_tree.dump live.widget);
  printf "same overlay widgets after another: %b\n" (same_widgets live);
  P.destroy ctx live;
  (* The layout skeleton, patched. [Window], [Box], [Grid], [Paned], [Center_box] and
     [Spinner] were all mounted and unmounted by these tests and never once patched with a
     property that changed, so their [update] functions had never executed a write:
     [W.Window.set_title], [W.Box.set_spacing], [W.Grid.set_row_spacing] and
     [W.Paned.set_position] could all have been broken with nothing to say so. Every prop
     each of them has moves across this one patch. *)
  let layout ~alt =
    Node.window
      ~title:(if alt then "after" else "before")
      ~default_size:(if alt then 400, 300 else 320, 240)
      (Node.box
         ~orientation:(if alt then Horizontal else Vertical)
         ~spacing:(if alt then 12 else 4)
         ~homogeneous:alt
         [ Node.grid
             ~row_spacing:(if alt then 2 else 6)
             ~column_spacing:(if alt then 3 else 12)
             ~row_homogeneous:alt
             ~column_homogeneous:(not alt)
             [ Node.label ~key:"g" ~attrs:[ Attr.grid_cell ~column:0 ~row:0 () ] "g" ]
         ; Node.paned
             ~orientation:Horizontal
             ~position:(if alt then 200 else 120)
             ~wide_handle:alt
             ~resize_start:(not alt)
             ~resize_end:alt
             ~shrink_start:alt
             ~shrink_end:(not alt)
             ~start:(Node.label "s")
             ~end_:(Node.label "e")
             ()
         ; Node.center_box ~shrink_center_last:alt ~start:(Node.label "c") ()
         ; Node.spinner ~spinning:alt ()
         ])
  in
  let layout_live = P.mount ctx ~path:"root" ~is_root:true (layout ~alt:false) in
  (* A box's orientation is visible in its css classes and a window's title in its own
     line, but a box's homogeneity and a window's default size are printed by nothing, so
     they are read straight back off the widgets. *)
  let layout_off_dump (live : P.live) =
    let width, height = W.Window.get_default_size (cast live.P.widget) in
    let box =
      match live.P.children with
      | Single (Some box) -> box.P.widget
      | No_children | Single None | List _ | Slots _ -> assert false
    in
    printf
      "default size %dx%d, box homogeneous %b\n"
      width
      height
      (W.Box.get_homogeneous (cast box))
  in
  print_s (Live_tree.dump layout_live.widget);
  layout_off_dump layout_live;
  let layout_live =
    P.patch ctx ~path:"root" ~is_root:true layout_live (layout ~alt:true)
  in
  print_s (Live_tree.dump layout_live.widget);
  layout_off_dump layout_live;
  P.destroy ctx layout_live;
  (* Grid: the third child moves cell without changing key, so it must be detached and
     re-attached at the new coordinates -- and be the same GObject afterwards. *)
  let grid_view ~span =
    Node.window
      ~title:"grid"
      (Node.grid
         ~row_spacing:6
         ~column_spacing:12
         [ Node.label ~key:"k" ~attrs:[ Attr.grid_cell ~column:0 ~row:0 () ] "Name"
         ; Node.label ~key:"v" ~attrs:[ Attr.grid_cell ~column:1 ~row:0 () ] "Bach"
         ; Node.label
             ~key:"note"
             ~attrs:
               [ (if span
                  then Attr.grid_cell ~column:0 ~row:1 ~width:2 ()
                  else Attr.grid_cell ~column:0 ~row:2 ())
               ]
             "note"
         ])
  in
  let grid_child (live : P.live) i =
    match live.children with
    | Single (Some g) ->
      (match g.children with
       | List cs -> (List.nth_exn cs i).P.widget
       | No_children | Single _ | Slots _ -> assert false)
    | No_children | Single None | List _ | Slots _ -> assert false
  in
  let live = P.mount ctx ~path:"root" ~is_root:true (grid_view ~span:false) in
  print_s (Live_tree.dump live.widget);
  let note_before = grid_child live 2 in
  let live = P.patch ctx ~path:"root" ~is_root:true live (grid_view ~span:true) in
  print_s (Live_tree.dump live.widget);
  printf
    "same widget after re-attach: %b\n"
    (Gobject.same note_before (grid_child live 2));
  (* Reordering the children without changing their cells is a [Move] the grid drops:
     nothing in GTK may shift. *)
  let live =
    P.patch
      ctx
      ~path:"root"
      ~is_root:true
      live
      (Node.window
         ~title:"grid"
         (Node.grid
            ~row_spacing:6
            ~column_spacing:12
            [ Node.label
                ~key:"note"
                ~attrs:[ Attr.grid_cell ~column:0 ~row:1 ~width:2 () ]
                "note"
            ; Node.label ~key:"k" ~attrs:[ Attr.grid_cell ~column:0 ~row:0 () ] "Name"
            ; Node.label ~key:"v" ~attrs:[ Attr.grid_cell ~column:1 ~row:0 () ] "Bach"
            ]))
  in
  print_s (Live_tree.dump live.widget);
  P.destroy ctx live;
  (* Re-attaching a grid child unparents it, so its whole subtree is unrooted and
     re-rooted between the two calls. The window's focus widget is the thing that hangs
     off that lifecycle, and the field the user is filling in is exactly what a widening
     row moves. The entry below is focused and then given a wider cell; the focus has to
     still be in it afterwards.

     GTK 4.22 leaves the focus alone across an unroot on its own, so this passes with or
     without [w_grid.ml]'s save and restore; what it pins is the behaviour, on whichever
     GTK the tests run against. The focus lands on the entry's internal [GtkText] rather
     than on the [GtkEntry], which is why this asks whether the focus is *inside* the
     moved child rather than whether it is the child. *)
  let focus_view ~span =
    Node.window
      ~title:"focus"
      (Node.grid
         [ Node.entry
             ~key:"e"
             ~attrs:
               [ (if span
                  then Attr.grid_cell ~column:0 ~row:0 ~width:2 ()
                  else Attr.grid_cell ~column:0 ~row:0 ())
               ]
             ~text:"typing"
             ()
         ; Node.label ~key:"l" ~attrs:[ Attr.grid_cell ~column:0 ~row:1 () ] "note"
         ])
  in
  let focus_live = P.mount ctx ~path:"focus" ~is_root:true (focus_view ~span:false) in
  let focus_root = Option.value_exn (W.Widget.get_root focus_live.widget) in
  let focused_in_entry (live : P.live) =
    match W.Root.get_focus focus_root with
    | None -> false
    | Some f ->
      let entry = grid_child live 0 in
      Gobject.same f entry || W.Widget.is_ancestor f entry
  in
  W.Root.set_focus focus_root (Some (grid_child focus_live 0));
  printf "focus is in the entry: %b\n" (focused_in_entry focus_live);
  let focus_live =
    P.patch ctx ~path:"focus" ~is_root:true focus_live (focus_view ~span:true)
  in
  printf "focus survives the re-attach: %b\n" (focused_in_entry focus_live);
  P.destroy ctx focus_live;
  (* A grid child with no cell is a bug worth failing on. *)
  (match
     P.mount
       ctx
       ~path:"root"
       ~is_root:true
       (Node.window ~title:"g" (Node.grid [ Node.label "cell-less" ]))
   with
   | (_ : P.live) -> print_endline "BUG: grid child without a cell accepted"
   | exception Invalid_argument msg -> printf "rejected: %s\n" msg);
  (* Stack: the switcher is declared *above* the stack it drives, so it can only be wired
     up after the whole tree exists -- which is what [run_fixups] is for. *)
  let stack_view ~visible ~pages =
    Node.window
      ~title:"stack"
      (Node.box
         ~orientation:Vertical
         [ Node.stack_switcher ~stack:"nav" ()
         ; Node.stack_sidebar ~stack:"nav" ()
         ; Node.stack
             ~name:"nav"
             ~transition:None_
             ~visible_child:visible
             ~attrs:[ Attr.on_visible_child_changed (fun _ -> Ui_effect.Ignore) ]
             (List.map pages ~f:(fun (key, title) ->
                Node.label ~key ~attrs:[ Attr.page_title title ] key))
         ])
  in
  let live =
    P.mount
      ctx
      ~path:"root"
      ~is_root:true
      (stack_view
         ~visible:"library"
         ~pages:[ "library", "Library"; "practice", "Practice" ])
  in
  P.run_fixups ctx;
  print_s (Live_tree.dump live.widget);
  let live =
    P.patch
      ctx
      ~path:"root"
      ~is_root:true
      live
      (stack_view
         ~visible:"practice"
         ~pages:[ "library", "Library!"; "practice", "Practice"; "setlists", "Setlists" ])
  in
  P.run_fixups ctx;
  print_s (Live_tree.dump live.widget);
  (* A page added and selected in the *same* pass, which is the one case the fixup queue
     exists for: [W_stack.select] is a no-op while [get_child_by_name] has nothing, and
     the enqueue is what guarantees the pages are attached by the time it runs. The
     renders above only ever selected a page that already existed, so a regression in that
     ordering would have left a wizard's "next" step silently on the previous one. *)
  let live =
    P.patch
      ctx
      ~path:"root"
      ~is_root:true
      live
      (stack_view
         ~visible:"encores"
         ~pages:
           [ "library", "Library!"
           ; "practice", "Practice"
           ; "setlists", "Setlists"
           ; "encores", "Encores"
           ])
  in
  P.run_fixups ctx;
  print_s (Live_tree.dump live.widget);
  (* A page dropped from the list leaves the stack, and the selection moves with the model
     rather than with whatever GTK fell back to. *)
  let live =
    P.patch
      ctx
      ~path:"root"
      ~is_root:true
      live
      (stack_view
         ~visible:"setlists"
         ~pages:[ "practice", "Practice"; "setlists", "Setlists" ])
  in
  P.run_fixups ctx;
  print_s (Live_tree.dump live.widget);
  (* The visible child is controlled: the user clicking a switcher button moves it, and a
     model that renders the same [~visible_child] again must put it back. *)
  let stack : P.live =
    match live.children with
    | Single (Some box) ->
      (match box.children with
       | List cs -> List.nth_exn cs 2
       | No_children | Single _ | Slots _ -> assert false)
    | No_children | Single None | List _ | Slots _ -> assert false
  in
  W.Stack.set_visible_child_name (cast stack.widget) "practice";
  let before = !scheduled in
  let live =
    Scheduler.with_patch_guard scheduler (fun () ->
      let live =
        P.patch
          ctx
          ~path:"root"
          ~is_root:true
          live
          (stack_view
             ~visible:"setlists"
             ~pages:[ "practice", "Practice"; "setlists", "Setlists" ])
      in
      P.run_fixups ctx;
      live)
  in
  printf
    "declined visible child: %s; reached Bonsai: %d\n"
    (Option.value (W.Stack.get_visible_child_name (cast stack.widget)) ~default:"?")
    (!scheduled - before);
  (* Outside a patch the same notify is a user click, and does reach Bonsai. *)
  let before = !scheduled in
  Gobject.Property.notify stack.widget ~name:"visible-child-name";
  printf "visible-child notify reaching Bonsai: %d\n" (!scheduled - before);
  (* An unresolvable stack name names both ends of the mistake. *)
  (match
     let stray =
       P.mount
         ctx
         ~path:"stray"
         ~is_root:true
         (Node.window ~title:"s" (Node.stack_switcher ~stack:"nope" ()))
     in
     P.run_fixups ctx;
     stray
   with
   | (_ : P.live) -> print_endline "BUG: unresolvable stack name accepted"
   | exception Invalid_argument msg -> printf "rejected: %s\n" msg);
  P.destroy ctx live;
  (* A switcher and a sidebar follow the stack they name across a patch that re-points
     them. [note_interest] re-enqueues that fixup on every patch precisely so this works,
     and nothing exercised it: every [~stack] in these tests was a constant, so a switcher
     whose resolution had been moved back inline would have gone on driving the old stack
     with no exception and no diagnostic. *)
  let two_stacks ~target =
    Node.window
      ~title:"t"
      (Node.box
         ~orientation:Vertical
         [ Node.stack_switcher ~stack:target ()
         ; Node.stack_sidebar ~stack:target ()
         ; Node.stack
             ~key:"a"
             ~name:"a"
             ~transition:None_
             ~visible_child:"pa"
             [ Node.label ~key:"pa" ~attrs:[ Attr.page_title "A" ] "pa" ]
         ; Node.stack
             ~key:"b"
             ~name:"b"
             ~transition:None_
             ~visible_child:"pb"
             [ Node.label ~key:"pb" ~attrs:[ Attr.page_title "B" ] "pb" ]
         ])
  in
  let retargeted = P.mount ctx ~path:"re" ~is_root:true (two_stacks ~target:"a") in
  P.run_fixups ctx;
  let both_point_at live ~index =
    let target = nth_child live index in
    let same = Option.value_map ~default:false ~f:(fun s -> Gobject.same s target) in
    ( same (W.Stack_switcher.get_stack (cast (nth_child live 0)))
    , same (W.Stack_sidebar.get_stack (cast (nth_child live 1))) )
  in
  let switcher, sidebar = both_point_at retargeted ~index:2 in
  printf "wired to stack a -- switcher %b, sidebar %b\n" switcher sidebar;
  let retargeted =
    P.patch ctx ~path:"re" ~is_root:true retargeted (two_stacks ~target:"b")
  in
  P.run_fixups ctx;
  let switcher, sidebar = both_point_at retargeted ~index:3 in
  printf "re-pointed at stack b -- switcher %b, sidebar %b\n" switcher sidebar;
  P.destroy ctx retargeted;
  (* Renaming a stack drops the registration it held, so a switcher still naming the old
     name fails loudly rather than driving a stack the tree no longer calls that. Only the
     rename *onto a name another stack holds* was tested; this is the same rename onto a
     free one. *)
  let renamed_view ~name =
    Node.window
      ~title:"r"
      (Node.box
         ~orientation:Vertical
         [ Node.stack_switcher ~stack:"old" ()
         ; Node.stack ~key:"s" ~name ~visible_child:"p" [ Node.label ~key:"p" "p" ]
         ])
  in
  let renamed_live = P.mount ctx ~path:"rn" ~is_root:true (renamed_view ~name:"old") in
  P.run_fixups ctx;
  (match
     let live =
       P.patch ctx ~path:"rn" ~is_root:true renamed_live (renamed_view ~name:"new")
     in
     P.run_fixups ctx;
     live
   with
   | (_ : P.live) -> print_endline "BUG: a switcher naming a renamed-away stack accepted"
   | exception Invalid_argument msg -> printf "rejected: %s\n" msg);
  (* Placement at the *head* of a keyed list: an insert in front of siblings that are
     already there, and a [Move] to index 0. Both are [~after:None], and both are what a
     newest-first feed or a newly pinned row does on its first frame; every list patch in
     these tests so far has inserted and moved into the middle or the tail. *)
  let ordered keys =
    Node.window
      ~title:"o"
      (Node.box ~orientation:Vertical (List.map keys ~f:(fun k -> Node.label ~key:k k)))
  in
  let ordered_live = P.mount ctx ~path:"ord" ~is_root:true (ordered [ "b"; "c" ]) in
  print_s (Live_tree.dump ordered_live.widget);
  let ordered_live =
    P.patch ctx ~path:"ord" ~is_root:true ordered_live (ordered [ "a"; "b"; "c" ])
  in
  print_s (Live_tree.dump ordered_live.widget);
  let ordered_live =
    P.patch ctx ~path:"ord" ~is_root:true ordered_live (ordered [ "c"; "a"; "b" ])
  in
  print_s (Live_tree.dump ordered_live.widget);
  P.destroy ctx ordered_live;
  (* Wrapping a named stack in another container is ordinary UI work, and it changes the
     kind of the node at that position -- so the patcher mounts the replacement subtree,
     which re-declares the stack's name, while the subtree it replaces still holds it. The
     one stack in this tree must not be reported as two, and the switcher above it has to
     come out of the refactor driving the new widget.

     Both the stack and the frame that wraps it carry [~key:"nav"], and that is what makes
     this test the test it claims to be. Without a key the reconciler cannot match a
     [Stack] against a [Frame] -- [same_kind] fails, so the unkeyed positional matcher
     leaves both unmatched -- and it emits [Remove] then [Insert] instead of an [Update].
     Removes come first, so [destroy] would give the name up before [mount] re-took it and
     [patch]'s kind-change arm, the only caller of [drop_stack_names], would never run.
     The shared key makes the pair an [Update] with a differing kind, which is the arm. *)
  let wrapped ~framed =
    let stack ?key () =
      Node.stack
        ?key
        ~name:"refactor"
        ~transition:None_
        ~visible_child:"a"
        [ Node.label ~key:"a" "a"; Node.label ~key:"b" "b" ]
    in
    Node.window
      ~title:"w"
      (Node.box
         ~orientation:Vertical
         [ Node.stack_switcher ~stack:"refactor" ()
         ; (if framed
            then Node.frame ~key:"nav" ~label:"Nav" (stack ())
            else stack ~key:"nav" ())
         ])
  in
  let wrapped_live = P.mount ctx ~path:"wrap" ~is_root:true (wrapped ~framed:false) in
  P.run_fixups ctx;
  let wrapped_live =
    P.patch ctx ~path:"wrap" ~is_root:true wrapped_live (wrapped ~framed:true)
  in
  P.run_fixups ctx;
  let framed_stack (live : P.live) =
    match live.children with
    | Single (Some box) ->
      (match box.children with
       | List [ _switcher; frame ] ->
         (match frame.children with
          | Single (Some stack) -> stack.P.widget
          | No_children | Single None | List _ | Slots _ -> assert false)
       | No_children | Single _ | List _ | Slots _ -> assert false)
    | No_children | Single None | List _ | Slots _ -> assert false
  in
  printf
    "stack wrapped in a frame; switcher drives the surviving stack: %b\n"
    (match W.Stack_switcher.get_stack (cast (nth_child wrapped_live 0)) with
     | None -> false
     | Some s -> Gobject.same s (framed_stack wrapped_live));
  P.destroy ctx wrapped_live;
  (* The check itself is unchanged: a kind change that leaves *two* live stacks under one
     name still raises, because the stack it collides with is not in the subtree being
     replaced. *)
  let twins ~both =
    Node.window
      ~title:"c"
      (Node.box
         ~orientation:Vertical
         [ Node.stack
             ~key:"one"
             ~name:"twin"
             ~visible_child:"a"
             [ Node.label ~key:"a" "a" ]
         ; (if both
            then
              Node.frame
                ~key:"two"
                (Node.stack ~name:"twin" ~visible_child:"b" [ Node.label ~key:"b" "b" ])
            else Node.label ~key:"two" "not yet")
         ])
  in
  let twins_live = P.mount ctx ~path:"twin" ~is_root:true (twins ~both:false) in
  P.run_fixups ctx;
  (match P.patch ctx ~path:"twin" ~is_root:true twins_live (twins ~both:true) with
   | (_ : P.live) -> print_endline "BUG: two live stacks under one name accepted"
   | exception Invalid_argument msg -> printf "rejected: %s\n" msg);
  (* A stack page's name is its key, so a page without one has nothing to be selected by
     and nothing for the reconciler to match on. *)
  (match
     P.mount
       ctx
       ~path:"keyless"
       ~is_root:true
       (Node.window
          ~title:"k"
          (Node.stack ~name:"solo" ~visible_child:"a" [ Node.label "keyless" ]))
   with
   | (_ : P.live) -> print_endline "BUG: stack page without a key accepted"
   | exception Invalid_argument msg -> printf "rejected: %s\n" msg);
  (* Two siblings under one key is structural misuse (spec §11), and it has to be rejected
     on the frame that builds the tree rather than the frame after it: the reconciler only
     runs on a patch, so a mount that let this through would leave the app to die on its
     second frame. For a stack it is worse than late -- a page's key is its GTK page name,
     so the first mount would hand [gtk_stack_add_named] the same name twice, leaving
     [get_child_by_name] ambiguous and the second page unreachable behind a switcher
     button that does nothing. *)
  (match
     P.mount
       ctx
       ~path:"dupkey"
       ~is_root:true
       (Node.window
          ~title:"k"
          (Node.box
             ~orientation:Vertical
             [ Node.label ~key:"a" "one"; Node.label ~key:"a" "two" ]))
   with
   | (_ : P.live) -> print_endline "BUG: duplicate sibling keys accepted at mount"
   | exception Invalid_argument msg -> printf "rejected: %s\n" msg);
  (match
     P.mount
       ctx
       ~path:"duppage"
       ~is_root:true
       (Node.window
          ~title:"k"
          (Node.stack
             ~name:"dup-pages"
             ~visible_child:"detail"
             [ Node.label ~key:"detail" "a"; Node.label ~key:"detail" "b" ]))
   with
   | (_ : P.live) -> print_endline "BUG: duplicate stack page names accepted at mount"
   | exception Invalid_argument msg -> printf "rejected: %s\n" msg);
  (* A patch that introduces one is the same mistake a frame later, and carries the same
     message and the same path -- which is the half that used to name neither. *)
  let keyed keys =
    Node.window
      ~title:"k"
      (Node.box ~orientation:Vertical (List.map keys ~f:(fun k -> Node.label ~key:k k)))
  in
  let keyed_live = P.mount ctx ~path:"patchdup" ~is_root:true (keyed [ "a"; "b" ]) in
  (match P.patch ctx ~path:"patchdup" ~is_root:true keyed_live (keyed [ "a"; "a" ]) with
   | (_ : P.live) -> print_endline "BUG: duplicate sibling keys accepted at patch"
   | exception Invalid_argument msg -> printf "rejected: %s\n" msg);
  P.destroy ctx keyed_live;
  (* Two stacks under one name would make [~stack] ambiguous, so the second one to be
     mounted says so rather than quietly winning or losing the registration. *)
  (match
     P.mount
       ctx
       ~path:"dup"
       ~is_root:true
       (Node.window
          ~title:"d"
          (Node.box
             ~orientation:Vertical
             [ Node.stack ~name:"nav" ~visible_child:"a" [ Node.label ~key:"a" "a" ]
             ; Node.stack ~name:"nav" ~visible_child:"b" [ Node.label ~key:"b" "b" ]
             ]))
   with
   | (_ : P.live) -> print_endline "BUG: two stacks with one name accepted"
   | exception Invalid_argument msg -> printf "rejected: %s\n" msg);
  (* A pass that raises never reaches [run_fixups], so what it deferred is still sitting
     in the queue: closures over widgets from a tree that was only half built. The stack
     below is mounted (and enqueues its [select]) before the nested window beside it is
     rejected. [abandon_fixups] is what [Driver.frame] calls on its way out of a frame
     that raised; without it a later pass would drain this one's work along with its own
     -- which is exactly what the rejections earlier in this file have been quietly
     accumulating, so the queue is emptied first to make the count below about this pass
     alone. *)
  P.abandon_fixups ctx;
  (match
     P.mount
       ctx
       ~path:"halfbuilt"
       ~is_root:true
       (Node.window
          ~title:"h"
          (Node.box
             ~orientation:Vertical
             [ Node.stack ~name:"halfbuilt" ~visible_child:"a" [ Node.label ~key:"a" "a" ]
             ; Node.window ~title:"nested" (Node.label "x")
             ]))
   with
   | (_ : P.live) -> print_endline "BUG: a nested window accepted"
   | exception Invalid_argument msg -> printf "rejected: %s\n" msg);
  printf "fixups left behind by the failed pass: %d\n" (Queue.length ctx.fixups);
  P.abandon_fixups ctx;
  printf "fixups after abandon_fixups: %d\n" (Queue.length ctx.fixups);
  (* And renaming one stack *onto* another's name is the same collision arriving a frame
     later, so it has to be the same rejection: a patch that quietly rebound the name
     would silently re-point every switcher in the tree at the wrong stack. *)
  let pair ~second_name =
    Node.window
      ~title:"r"
      (Node.box
         ~orientation:Vertical
         [ Node.stack
             ~key:"one"
             ~name:"first"
             ~visible_child:"x"
             [ Node.label ~key:"x" "x" ]
         ; Node.stack
             ~key:"two"
             ~name:second_name
             ~visible_child:"y"
             [ Node.label ~key:"y" "y" ]
         ])
  in
  let renamed = P.mount ctx ~path:"ren" ~is_root:true (pair ~second_name:"second") in
  P.run_fixups ctx;
  match P.patch ctx ~path:"ren" ~is_root:true renamed (pair ~second_name:"first") with
  | (_ : P.live) -> print_endline "BUG: a stack renamed onto another's name accepted"
  | exception Invalid_argument msg -> printf "rejected: %s\n" msg
;;
