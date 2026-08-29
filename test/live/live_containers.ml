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
     | No_children | Single _ -> assert false)
  | No_children | Single None | List _ -> assert false
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
  let ctx : P.ctx =
    { signals =
        { schedule = (fun _ -> incr scheduled)
        ; in_patch = (fun () -> Scheduler.in_patch scheduler)
        ; on_exn =
            (fun ~node_path exn -> printf "EXN at %s: %s\n" node_path (Exn.to_string exn))
        }
    ; on_window_created = (fun _ -> ())
    }
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
          | No_children | Single _ -> assert false)
       | No_children | Single None | List _ -> assert false)
    | No_children | Single None | List _ -> assert false
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
  P.destroy ctx live
;;
