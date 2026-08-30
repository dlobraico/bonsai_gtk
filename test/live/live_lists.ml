open! Core
open Bonsai_gtk_vtree
module Gobject = Bonsai_gtk.Private.Gtk_import.Gobject
module Glib = Bonsai_gtk.Private.Gtk_import.Glib
module Live_tree = Bonsai_gtk.Private.Live_tree
module P = Bonsai_gtk.Private.Patcher
module Scheduler = Bonsai_gtk.Private.Scheduler
module W = Bonsai_gtk.Private.Gtk_import.W
module W_list_box = Bonsai_gtk.Private.W_list_box
module Widget = Bonsai_gtk.Private.Gtk_import.Widget

let cast = Bonsai_gtk.Private.Gtk_import.cast

(* The [GtkListBox] under the window root. The tests below are about the rows GTK holds,
   so they need the container itself rather than the tree's root. *)
let list_box (live : P.live) =
  match live.children with
  | Single (Some lb) -> lb.P.widget
  | No_children | Single None | List _ | Slots _ -> assert false
;;

(* The rows GTK holds, in GTK's own order, read through [get_row_at_index] rather than
   through the widget children: a placeholder is a child of the list box too, and it is
   not a row. *)
let row_widgets (live : P.live) =
  let b : W.List_box.t = cast (list_box live) in
  let rec go i acc =
    match W.List_box.get_row_at_index b i with
    | None -> List.rev acc
    | Some r -> go (i + 1) (r :: acc)
  in
  go 0 []
;;

(* The same GObjects, as a set: a reorder is exactly the case where the two lists hold the
   same rows in different positions, so comparing them pairwise would answer [false] for
   the one reason that is not a failure. Where they ended up is printed separately. *)
let same_rows before after =
  List.length before = List.length after
  && List.for_all after ~f:(fun a -> List.exists before ~f:(fun b -> Gobject.same a b))
;;

(* The index each of [rows] now has, in GTK's own numbering. Identity alone would be
   satisfied by a patch that moved nothing. *)
let positions rows =
  String.concat
    ~sep:","
    (List.map rows ~f:(fun r -> Int.to_string (W.List_box_row.get_index r)))
;;

(* The rows in GTK's order, named by the label each one holds. The dump says the same
   thing at length; this is for the cases whose whole claim is the order. *)
let row_labels (live : P.live) =
  String.concat
    ~sep:","
    (List.map (row_widgets live) ~f:(fun r ->
       match W.List_box_row.get_child r with
       | Some c when String.equal (Bonsai_gtk.Private.Gtk_import.type_name c) "GtkLabel"
         -> W.Label.get_text (cast c)
       | Some _ | None -> "?"))
;;

(* Through [W_list_box]'s own [Child_keys] lookup, which is the mapping every handler
   answers in: printing GTK's row indices instead would say nothing about whether the key
   a handler receives is the right one. *)
let selected_keys (live : P.live) =
  match W_list_box.selected_keys (list_box live) with
  | [] -> "(none)"
  | keys -> String.concat ~sep:"," keys
;;

(* The user clicking a row, as far as a test can get: there is no synthetic click in the
   pinned binding (see [test/live/live_controllers.ml]), so the selection is moved with
   the same setter GTK's own click handler calls. What matters for the claim below is that
   the widget's selection differs from the model's when the next frame runs. *)
let select_row_by_hand (live : P.live) key =
  let w = list_box live in
  match W_list_box.row_by_key w key with
  | Some row -> W.List_box.select_row (cast w) (Some row)
  | None -> printf "BUG: no row for key %s\n" key
;;

let drain () =
  while Glib.Main.pending () do
    ignore (Glib.Main.iteration false : bool)
  done
;;

let () =
  ignore (Ocgtk_gtk.GMain.init () : string array);
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
  let row key =
    match key with
    (* One non-selectable, non-activatable row, which is what a header row is: GTK's
       [set_header_func] is not in the binding, so a header is an ordinary row that
       refuses both. Its flags ride on the child node's attrs. *)
    | "hdr" ->
      Node.label
        ~key
        ~attrs:[ Attr.row_selectable false; Attr.row_activatable false ]
        "HEADER"
    | key -> Node.label ~key (String.uppercase key)
  in
  let view ?(mode = Selection_mode.Multiple) ?placeholder ~selected ~rows () =
    Node.window
      ~title:"lists"
      (Node.list_box
         ~attrs:
           [ Attr.on_row_activated (fun (_ : Key.t) -> Ui_effect.Ignore)
           ; Attr.on_selected_rows_changed (fun (_ : Key.t list) -> Ui_effect.Ignore)
           ]
         ~selection_mode:mode
         ~show_separators:true
         ?placeholder
         ~selected
         (List.map rows ~f:row))
  in
  let patch live node =
    let live = P.patch ctx ~path:"root" ~is_root:true live node in
    P.run_fixups ctx;
    live
  in
  (* 1. The rows GTK holds, in order, with the wrapper's own props. The placeholder is a
        child of the list box and is not one of them. *)
  let live =
    P.mount
      ctx
      ~path:"root"
      ~is_root:true
      (view
         ~placeholder:(Node.label "nothing here")
         ~selected:[ "b" ]
         ~rows:[ "hdr"; "a"; "b"; "c" ]
         ())
  in
  P.run_fixups ctx;
  print_s (Live_tree.dump live.widget);
  printf "after mount: %s\n" (selected_keys live);
  (* 2. A keyed reorder moves the same GObjects. Take handles first, patch, compare with
     [Gobject.same] -- the dump alone cannot say this, because two rows holding the same
     label print identically. *)
  let rows_before = row_widgets live in
  let live =
    patch
      live
      (view
         ~placeholder:(Node.label "nothing here")
         ~selected:[ "b" ]
         ~rows:[ "hdr"; "c"; "a"; "b" ]
         ())
  in
  printf "same GObjects after reorder: %b\n" (same_rows rows_before (row_widgets live));
  (* And they really did move: identity alone would be satisfied by a patch that did
     nothing at all. [hdr;a;b;c] became [hdr;c;a;b], so the four original rows are now at
     0, 2, 3, 1. *)
  printf "the original rows are now at: %s\n" (positions rows_before);
  print_s (Live_tree.dump live.widget);
  (* A reorder that leaves a row behind the moved one, so that a [move] landing one place
     too far in either direction is visible: GTK clamps an index past the end, so a
     reorder whose moved row ends up last cannot tell a correct index from an off-by-one. *)
  let live =
    patch
      live
      (view
         ~placeholder:(Node.label "nothing here")
         ~selected:[ "b" ]
         ~rows:[ "c"; "a"; "hdr"; "b" ]
         ())
  in
  printf "rows after a rightward move: %s\n" (row_labels live);
  (* A row inserted in the middle, which is the other half of the same arithmetic: the
     index comes from the predecessor's own [get_index], not from the reconciler's. *)
  let live =
    patch
      live
      (view
         ~placeholder:(Node.label "nothing here")
         ~selected:[ "b" ]
         ~rows:[ "c"; "a"; "new"; "hdr"; "b" ]
         ())
  in
  printf "rows after a middle insert: %s\n" (row_labels live);
  let live =
    patch
      live
      (view
         ~placeholder:(Node.label "nothing here")
         ~selected:[ "b" ]
         ~rows:[ "hdr"; "c"; "a"; "b" ]
         ())
  in
  printf "rows after the middle row went away: %s\n" (row_labels live);
  (* 3. The declined selection. The user clicks row "c"; the model keeps "b"; the frame
     that renders the *same* selection must put the widget back. This is spec §6.5 for a
     container, and the reason selection is a fixup rather than an [update]. *)
  select_row_by_hand live "c";
  printf "after the user clicked: %s\n" (selected_keys live);
  let live =
    patch
      live
      (view
         ~placeholder:(Node.label "nothing here")
         ~selected:[ "b" ]
         ~rows:[ "hdr"; "c"; "a"; "b" ]
         ())
  in
  printf "after the declining frame: %s\n" (selected_keys live);
  (* 4. Add a row and select it in one frame. The row does not exist when [reassert] would
     have run, which is why this is a fixup; without the fixup this prints nothing
     selected. *)
  let live =
    patch
      live
      (view
         ~placeholder:(Node.label "nothing here")
         ~selected:[ "d" ]
         ~rows:[ "hdr"; "c"; "a"; "b"; "d" ]
         ())
  in
  printf "add-and-select: %s\n" (selected_keys live);
  (* 5. Removing the selected row. GTK drops the selection; the model still says "d", and
     the next frame must not resurrect a row that is gone. Nothing selected, no raise. *)
  let live =
    patch
      live
      (view
         ~placeholder:(Node.label "nothing here")
         ~selected:[ "d" ]
         ~rows:[ "hdr"; "c"; "a"; "b" ]
         ())
  in
  printf "selected row removed: %s\n" (selected_keys live);
  (* 6. A key in ~selected that no row carries is ignored, not an error -- deliberately
     unlike [Node.stack ~visible_child], which raises. *)
  let live =
    patch
      live
      (view
         ~placeholder:(Node.label "nothing here")
         ~selected:[ "a"; "ghost" ]
         ~rows:[ "hdr"; "c"; "a"; "b" ]
         ())
  in
  printf "selection with a ghost key: %s\n" (selected_keys live);
  (* A multi-selection, and the order it is written in. GTK reports selected rows
     in *widget* order; the model listed them the other way round, and the two orderings
     of one selection must not look like a change -- or the fixup would write on every
     frame and the user could never keep a multi-selection. The count of writes is not
     observable, so what is asserted is that the selection is stable across a frame that
     lists it differently again. *)
  let live = patch live (view ~selected:[ "a"; "b" ] ~rows:[ "hdr"; "c"; "a"; "b" ] ()) in
  printf "multi-selection: %s\n" (selected_keys live);
  (* The widget now holds the selection in *its* order, which for these rows is "a" then
     "b". The frame below asks for the same selection listed the other way round. *)
  let before = !scheduled in
  let live = patch live (view ~selected:[ "b"; "a" ] ~rows:[ "hdr"; "c"; "a"; "b" ] ()) in
  printf "same selection, listed the other way: %s\n" (selected_keys live);
  (* Nothing was written, which is the whole of the sorting claim and the only observable
     form of it: an unsorted comparison would call these two frames different, rewrite the
     selection, and land on the identical set -- so the line above would be unchanged and
     only the write count would move. These patches are not inside a patch guard, so every
     [selected-rows-changed] the fixup provokes reaches [scheduled]. *)
  printf "writes for a re-ordered but equal selection: %d\n" (!scheduled - before);
  (* A row that says it is not selectable cannot be selected, whatever the model asks for
     -- GTK's answer, read back rather than pre-empted. *)
  let live = patch live (view ~selected:[ "hdr" ] ~rows:[ "hdr"; "c"; "a"; "b" ] ()) in
  printf "asking for the header row: %s\n" (selected_keys live);
  (* The row flags are re-read when they change, so a header that stops being a header
     becomes an ordinary row -- and, the half an [Option.iter] over the new attrs would
     miss, a row that simply drops the attrs goes back to GTK's [true]. *)
  let live =
    patch
      live
      (Node.window
         ~title:"lists"
         (Node.list_box
            ~selection_mode:Multiple
            ~show_separators:true
            ~selected:[ "hdr" ]
            [ Node.label ~key:"hdr" "HEADER"
            ; Node.label
                ~key:"c"
                ~attrs:[ Attr.row_selectable false; Attr.row_activatable false ]
                "C"
            ; Node.label ~key:"a" "A"
            ; Node.label ~key:"b" "B"
            ]))
  in
  printf "after the flags swapped: %s\n" (selected_keys live);
  print_s (Live_tree.dump live.widget);
  (* The mode and the model can disagree, and GTK arbitrates: three keys handed to a
     [Single] list box leaves the last one selected. Written as asked and read back,
     rather than clamped in the impl. *)
  let live =
    patch
      live
      (view ~mode:Single ~selected:[ "c"; "a"; "b" ] ~rows:[ "hdr"; "c"; "a"; "b" ] ())
  in
  printf "three keys in Single mode: %s\n" (selected_keys live);
  (* A row whose kind changes is a different child to the reconciler: a fresh widget in a
     fresh wrapper, in the same position. *)
  let kinded live ~button =
    P.patch
      ctx
      ~path:"root"
      ~is_root:true
      live
      (Node.window
         ~title:"lists"
         (Node.list_box
            ~selection_mode:Single
            ~show_separators:true
            ~selected:[ "b" ]
            [ Node.label ~key:"a" "A"
            ; (if button
               then Node.button ~key:"b" ~label:"B" ()
               else Node.label ~key:"b" "B")
            ]))
  in
  let live = kinded live ~button:false in
  P.run_fixups ctx;
  let before_kind_change = row_widgets live in
  let live = kinded live ~button:true in
  P.run_fixups ctx;
  printf
    "kind change replaced the wrapper: %b\n"
    (not (same_rows before_kind_change (row_widgets live)));
  printf "kind change kept the selection: %s\n" (selected_keys live);
  print_s (Live_tree.dump live.widget);
  (* 7. Teardown does not fire a handler. GTK emits [selected-rows-changed] as rows go
     away; [scheduled] must not move across the destroy. *)
  let before = !scheduled in
  P.destroy ctx live;
  printf "handlers fired during teardown: %d\n" (!scheduled - before);
  (* The same claim through a real frame. [live_driver.ml] makes it for a toggle
     ([Widget_impl.reassert]) and for a stack page (a fixup); a list box's selection is
     the second fixup, and a driver that skipped the walk on a no-change frame would lose
     it in the same way. The view is built once and handed back by reference, so every
     frame after the first is the physically-same-node frame [Driver.frame] does not diff. *)
  let selection_seen = ref 0 in
  let declining_view =
    Node.window
      ~title:"declined"
      (Node.list_box
         ~attrs:
           [ Attr.on_selected_rows_changed
               (Bonsai_gtk.Effect.of_sync_fun (fun (_ : Key.t list) ->
                  incr selection_seen))
           ]
         ~selection_mode:Single
         ~selected:[ "a" ]
         [ Node.label ~key:"a" "A"; Node.label ~key:"b" "B" ])
  in
  let time_source = Bonsai.Time_source.create ~start:Time_ns.epoch in
  let d =
    Bonsai_gtk.Expert.Driver.create
      ~time_source
      ~on_window_created:(fun _ -> ())
      (fun (_graph @ local) -> Bonsai.return declining_view)
  in
  Bonsai_gtk.Expert.Driver.frame d;
  let driven_box () =
    let root = Option.value_exn (Bonsai_gtk.Expert.Driver.root_widget d) in
    List.hd_exn (Bonsai_gtk.Private.Gtk_import.widget_children root)
  in
  let driven_keys () =
    match W_list_box.selected_keys (driven_box ()) with
    | [] -> "(none)"
    | keys -> String.concat ~sep:"," keys
  in
  printf "driver, after mount: %s\n" (driven_keys ());
  (* The user selects the other row. The model declines -- it renders the same node -- so
     the frame that click arms is the only thing that can put it back.

     Printed *before* the drain as well as after: the emission arms a GLib idle, and by
     the time the loop has been handed back the correcting frame has already run, so
     without this line the claim would be indistinguishable from a click that never
     reached the widget at all. *)
  let w = driven_box () in
  W.List_box.select_row (cast w) (W_list_box.row_by_key w "b");
  printf "driver, after the user clicked: %s\n" (driven_keys ());
  drain ();
  printf
    "driver, after the frame the click armed: %s (Bonsai saw %d)\n"
    (driven_keys ())
    !selection_seen;
  (* And a further no-diff frame is idempotent rather than a second write the model never
     asked for -- [apply_selection] compares before it writes, so nothing here should move
     and [selected-rows-changed] should not fire again. *)
  Bonsai_gtk.Expert.Driver.frame d;
  printf
    "driver, after one more frame: %s (Bonsai saw %d)\n"
    (driven_keys ())
    !selection_seen;
  Bonsai_gtk.Expert.Driver.stop d
;;
