open! Core
open Bonsai_gtk_vtree
module Gdk = Ocgtk_gdk.Gdk
module Gobject = Bonsai_gtk.Private.Gtk_import.Gobject
module Live_tree = Bonsai_gtk.Private.Live_tree
module P = Bonsai_gtk.Private.Patcher
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
  let ctx : P.ctx =
    { signals =
        { schedule = (fun _ -> ())
        ; in_patch = (fun () -> false)
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
  Stdlib.Sys.remove png
;;
