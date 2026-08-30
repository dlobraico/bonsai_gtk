open! Core
open Bonsai_gtk_vtree
module Gobject = Bonsai_gtk.Private.Gtk_import.Gobject
module Glib = Bonsai_gtk.Private.Gtk_import.Glib
module Live_tree = Bonsai_gtk.Private.Live_tree
module P = Bonsai_gtk.Private.Patcher
module Scheduler = Bonsai_gtk.Private.Scheduler
module W = Bonsai_gtk.Private.Gtk_import.W
module W_flow_box = Bonsai_gtk.Private.W_flow_box
module W_list_box = Bonsai_gtk.Private.W_list_box
module W_notebook = Bonsai_gtk.Private.W_notebook
module Registry = Bonsai_gtk.Private.Registry
module Widget_impl = Bonsai_gtk.Private.Widget_impl
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

let () = ignore (Ocgtk_gtk.GMain.init () : string array)

(* Regression for the [get_selected_rows] use-after-free (review C1), and it runs before
   everything else in this file for the reason [live_controllers.ml]'s heap-churn test
   does: every selection line below is a read of the selection, so if that read is what
   destroys the rows then the whole golden is measuring a tree that is quietly falling
   apart.

   [gtk_list_box_get_selected_rows] is transfer-container -- the [GList] is the caller's
   to free, the rows in it are borrowed -- and ocgtk's generated stub wraps each row with
   no [g_object_ref_sink] while the wrapper's finaliser unconditionally unrefs it
   ([ml_list_box_gen.c:229-238]). So every call handed out one unbalanced unref per
   selected row, and [apply_selection] makes that call on every mount, every patch and
   every no-change frame. Ten idle frames and one major collection were enough to dispose
   a still-parented row: the selection emptied itself, GTK logged "has a parent GtkListBox
   during dispose", and a couple of hundred reads took SIGSEGV.

   The fork fixed the identical bug on [GtkFlowBoxChild] one file over
   ([ml_flow_box_gen.c:222-233], whose comment describes exactly this); the [GtkListBox]
   twin is unfixed in the pinned binding, which is why [W_list_box.selected_keys] walks
   [get_row_at_index] + [is_selected] instead. See docs/m1-backlog.md.

   The frames here are the real thing: [reassert_only] + [run_fixups] inside the patch
   guard is what [Driver.frame] runs when a computation hands back the physically same
   node, which is what an idle application does sixty times a second. *)
let () =
  let scheduler = Scheduler.create ~run_frame:(fun () -> ()) in
  let ctx =
    P.create_ctx
      ~signals:
        { schedule = (fun _ -> ())
        ; in_patch = (fun () -> Scheduler.in_patch scheduler)
        ; on_exn =
            (fun ~node_path exn -> printf "EXN at %s: %s\n" node_path (Exn.to_string exn))
        }
      ~on_window_created:(fun _ -> ())
  in
  let live =
    P.mount
      ctx
      ~path:"gc"
      ~is_root:true
      (Node.window
         ~title:"gc"
         (Node.list_box
            ~selection_mode:Multiple
            ~selected:[ "a"; "b" ]
            [ Node.label ~key:"a" "A"; Node.label ~key:"b" "B"; Node.label ~key:"c" "C" ]))
  in
  P.run_fixups ctx;
  printf "gc: mounted, selected %s\n" (selected_keys live);
  Out_channel.flush stdout;
  for batch = 1 to 5 do
    for _ = 1 to 50 do
      Scheduler.with_patch_guard scheduler (fun () ->
        P.reassert_only ctx ~path:"gc" live;
        P.run_fixups ctx)
    done;
    (* [full_major] rather than [minor]: the wrappers are custom blocks with finalisers,
       and it is the finaliser running that does the damage. *)
    Gc.full_major ();
    printf
      "gc: after %d frames + full_major, selected %s\n"
      (batch * 50)
      (selected_keys live);
    (* Flushed per batch, because the failure this guards against is a {i crash}: with the
       buffer held to exit, a regression prints nothing at all and the golden diff says
       only "got signal SEGV". Flushed, it says how many frames it survived. *)
    Out_channel.flush stdout
  done;
  (* The rows are still there and still parented, which is the half a selection count
     alone would not show. *)
  print_s (Live_tree.dump live.widget);
  P.destroy ctx live
;;

let drain () =
  while Glib.Main.pending () do
    ignore (Glib.Main.iteration false : bool)
  done
;;

let () =
  let scheduled = ref 0 in
  let reported = ref [] in
  let activated = ref [] in
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
           [ Attr.on_row_activated (fun key ->
               activated := key :: !activated;
               Ui_effect.Ignore)
           ; Attr.on_selected_rows_changed (fun keys ->
               reported := keys :: !reported;
               Ui_effect.Ignore)
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
  (* Two selected before it goes, so the line below distinguishes the reduced selection
     from the empty one. *)
  let live =
    patch
      live
      (view
         ~placeholder:(Node.label "nothing here")
         ~selected:[ "a"; "d" ]
         ~rows:[ "hdr"; "c"; "a"; "b"; "d" ]
         ())
  in
  printf "two selected before the removal: %s\n" (selected_keys live);
  reported := [];
  let live =
    patch
      live
      (view
         ~placeholder:(Node.label "nothing here")
         ~selected:[ "a"; "d" ]
         ~rows:[ "hdr"; "c"; "a"; "b" ]
         ())
  in
  printf "selected row removed: %s\n" (selected_keys live);
  (* And what the handler was told while the row was leaving: the reduced selection, never
     the key of the row on its way out. [selected_keys] answers by walking the rows the
     list box still holds, so a departed row cannot appear in it whatever [Child_keys]
     still remembers -- which is why [remove]'s "drop the key before the GTK call"
     ordering is belt-and-braces rather than the load-bearing step this file used to
     claim. See the comment there, corrected in Task 7. *)
  printf
    "the handler saw, as the row left: %s\n"
    (String.concat
       ~sep:" | "
       (List.rev_map !reported ~f:(fun keys ->
          if List.is_empty keys then "(none)" else String.concat ~sep:"," keys)));
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
  (* ... and *inert*, not merely harmless. [current] can only hold keys of rows that
     exist, so comparing it against the unfiltered [~selected] would be false forever the
     moment the model holds one extra id, and every frame would unselect everything and
     re-select the survivors -- the very thing the sorting above exists to prevent. This
     line reads 2 without the narrowing in [apply_selection] and 0 with it. *)
  let before = !scheduled in
  let live =
    patch
      live
      (view
         ~placeholder:(Node.label "nothing here")
         ~selected:[ "a"; "ghost" ]
         ~rows:[ "hdr"; "c"; "a"; "b" ]
         ())
  in
  printf "writes on an identical frame with a ghost key held: %d\n" (!scheduled - before);
  (* And the row is selected on the frame it arrives, without the model having changed its
     mind: the filter lifted, not the selection. This is the same-frame rule the selection
     fixup exists for, reached from the other direction than "add a row and select it". *)
  let live =
    patch
      live
      (view
         ~placeholder:(Node.label "nothing here")
         ~selected:[ "a"; "ghost" ]
         ~rows:[ "hdr"; "c"; "a"; "ghost"; "b" ]
         ())
  in
  printf "the ghost row arrived: %s\n" (selected_keys live);
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
  (* The two [Live_tree] spellings nothing else in this file reaches. GTK's own defaults
     are [SINGLE] and single-click activation, so the dump suppresses both -- which means
     the branches that print the *other* modes and [activate-on-double-click] are only
     reachable from a node that asks for them, and they are the two properties a reader is
     most likely to have backwards. *)
  let live =
    patch
      live
      (Node.window
         ~title:"lists"
         (Node.list_box
            ~selection_mode:Browse
            ~activate_on_single_click:false
            ~show_separators:true
            ~selected:[ "a" ]
            [ Node.label ~key:"a" "A"; Node.label ~key:"b" "B" ]))
  in
  print_s (Live_tree.dump live.widget);
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
  (* The activation handler, end to end through GTK's own emission chain, which nothing
     delivered in M2 until now. There is still no synthetic click in the pinned binding --
     but [GtkListBoxRow::activate] is an action signal and it is what a click ends in, so
     emitting it makes GTK emit [row-activated] on the list box, which reaches this
     library's trampoline, which looks the key up in [Child_keys] and hands it to the
     attr's handler. That is the whole of the [Payload] spec's claim: the key an
     application receives is the key of the row that was activated, and not merely that a
     handler exists. (Found while writing the flow box's half in Task 7; the same emission
     is what [live_lists]' flow box block uses.) *)
  let live = patch live (view ~selected:[ "a" ] ~rows:[ "hdr"; "c"; "a"; "b" ] ()) in
  let w = list_box live in
  Option.iter (W_list_box.row_by_key w "c") ~f:(fun row ->
    Gobject.Signal.emit_by_name (row :> Widget.t) ~name:"activate");
  printf "activation delivered the key: %s\n" (String.concat ~sep:"," !activated);
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

(* ------------------------------------------------------------------------------------ *)
(* [GtkFlowBox]: the same machinery as above, over a grid of cards. *)
(* ------------------------------------------------------------------------------------ *)

let flow_box (live : P.live) =
  match live.children with
  | Single (Some fb) -> fb.P.widget
  | No_children | Single None | List _ | Slots _ -> assert false
;;

let card_widgets (live : P.live) =
  let b : W.Flow_box.t = cast (flow_box live) in
  let rec go i acc =
    match W.Flow_box.get_child_at_index b i with
    | None -> List.rev acc
    | Some c -> go (i + 1) (c :: acc)
  in
  go 0 []
;;

let card_positions cards =
  String.concat
    ~sep:","
    (List.map cards ~f:(fun c -> Int.to_string (W.Flow_box_child.get_index c)))
;;

let card_labels (live : P.live) =
  String.concat
    ~sep:","
    (List.map (card_widgets live) ~f:(fun c ->
       match W.Flow_box_child.get_child c with
       | Some inner
         when String.equal (Bonsai_gtk.Private.Gtk_import.type_name inner) "GtkLabel" ->
         W.Label.get_text (cast inner)
       | Some _ | None -> "?"))
;;

let card_keys (live : P.live) =
  match W_flow_box.selected_keys (flow_box live) with
  | [] -> "(none)"
  | keys -> String.concat ~sep:"," keys
;;

let select_card_by_hand (live : P.live) key =
  let w = flow_box live in
  match W_flow_box.child_by_key w key with
  | Some c -> W.Flow_box.select_child (cast w) c
  | None -> printf "BUG: no card for key %s\n" key
;;

(* The [Child_keys] lifetime regression, for the flow box and first among its blocks, for
   the reason the list box's runs first: every selection line below is a read {i through}
   that table, so if the table empties itself under GC the whole golden is measuring
   nothing.

   This is not the [get_selected_rows] use-after-free --
   [gtk_flow_box_get_selected_children] is transfer-container too, but the pinned fork's
   stub {i does} [g_object_ref_sink] each element before wrapping it
   ([ml_flow_box_gen.c:216-233]), which is the fix the [GtkListBox] twin is still missing.
   Every other getter this impl calls ([get_child_at_index], [flow_box_child_get_child],
   [widget_get_parent]) sinks as well; all four were read in the stub rather than in the
   GIR, which is the rule that catches this class.

   What it {i is} a regression for is [child_keys.mli]'s invariant: the ephemeron is weak
   in the OCaml value, so keying it on the [GtkFlowBoxChild] this impl makes and drops --
   rather than on the card the patcher retains -- loses every entry at the first major
   collection, with the cards still parented and still selected and no error anywhere. The
   frames are the real thing: [reassert_only] + [run_fixups] inside the patch guard is
   what [Driver.frame] runs on a physically-same-node frame. *)
let () =
  let scheduler = Scheduler.create ~run_frame:(fun () -> ()) in
  let ctx =
    P.create_ctx
      ~signals:
        { schedule = (fun _ -> ())
        ; in_patch = (fun () -> Scheduler.in_patch scheduler)
        ; on_exn =
            (fun ~node_path exn -> printf "EXN at %s: %s\n" node_path (Exn.to_string exn))
        }
      ~on_window_created:(fun _ -> ())
  in
  let live =
    P.mount
      ctx
      ~path:"fbgc"
      ~is_root:true
      (Node.window
         ~title:"fbgc"
         (Node.flow_box
            ~selection_mode:Multiple
            ~selected:[ "a"; "b" ]
            [ Node.label ~key:"a" "A"; Node.label ~key:"b" "B"; Node.label ~key:"c" "C" ]))
  in
  P.run_fixups ctx;
  printf "fb gc: mounted, selected %s\n" (card_keys live);
  Out_channel.flush stdout;
  for batch = 1 to 5 do
    for _ = 1 to 50 do
      Scheduler.with_patch_guard scheduler (fun () ->
        P.reassert_only ctx ~path:"fbgc" live;
        P.run_fixups ctx)
    done;
    Gc.full_major ();
    printf
      "fb gc: after %d frames + full_major, selected %s\n"
      (batch * 50)
      (card_keys live);
    Out_channel.flush stdout
  done;
  print_s (Live_tree.dump live.widget);
  P.destroy ctx live
;;

let () =
  let scheduled = ref 0 in
  let activated = ref [] in
  let reported = ref [] in
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
  (* stavekeeper's [build_grid], prop for prop, as the baseline; [view] then varies the
     geometry so that the "grid view / list view" patch below is a diff of these. *)
  let view
    ?(mode = Selection_mode.Multiple)
    ?(activate_on_single_click = false)
    ?(min_per_line = 1)
    ?(max_per_line = 10)
    ?(row_spacing = 28)
    ?(column_spacing = 20)
    ?(homogeneous = false)
    ?(orientation = Orientation.Horizontal)
    ~selected
    ~cards
    ()
    =
    Node.window
      ~title:"grid"
      (Node.flow_box
         ~attrs:
           [ Attr.on_child_activated (fun key ->
               activated := key :: !activated;
               Ui_effect.Ignore)
           ; Attr.on_selected_children_changed (fun keys ->
               reported := keys :: !reported;
               Ui_effect.Ignore)
           ]
         ~selection_mode:mode
         ~activate_on_single_click
         ~min_children_per_line:min_per_line
         ~max_children_per_line:max_per_line
         ~row_spacing
         ~column_spacing
         ~homogeneous
         ~orientation
         ~selected
         (List.map cards ~f:(fun key -> Node.label ~key (String.uppercase key))))
  in
  let patch live node =
    let live = P.patch ctx ~path:"root" ~is_root:true live node in
    P.run_fixups ctx;
    live
  in
  (* 1. The mount golden: the cards GTK holds, each in the [GtkFlowBoxChild] this impl
        made, and the grid's own geometry. Note what the dump does {i not} print --
        [max-children-per-line] shows because 10 is not GTK's default, and GTK's default
        is 7 rather than "unlimited". *)
  let live =
    P.mount
      ctx
      ~path:"root"
      ~is_root:true
      (view ~selected:[ "b" ] ~cards:[ "a"; "b"; "c" ] ())
  in
  P.run_fixups ctx;
  print_s (Live_tree.dump live.widget);
  printf "fb after mount: %s\n" (card_keys live);
  (* 2. The runtime reconfiguration stavekeeper does by hand. [configure_grid_for_view]
     writes four setters and toggles a CSS class from a function both call sites have to
     remember to call; here the same change is four fields of the next render, and the
     diff writes exactly the ones that moved inside one [Widget_impl.batch]. Six props
     change in this one patch. *)
  let live =
    patch
      live
      (view
         ~mode:Single
         ~activate_on_single_click:true
         ~max_per_line:1
         ~row_spacing:0
         ~column_spacing:0
         ~homogeneous:true
         ~orientation:Vertical
         ~selected:[ "b" ]
         ~cards:[ "a"; "b"; "c" ]
         ())
  in
  print_s (Live_tree.dump live.widget);
  (* ...and back, which is the half that shows the diff is a diff and not a one-way trip:
     every one of those six returns to the value the mount had, so the dump prints the
     mount's line again. *)
  let live = patch live (view ~selected:[ "b" ] ~cards:[ "a"; "b"; "c" ] ()) in
  print_s (Live_tree.dump live.widget);
  (* 3. A keyed reorder moves the same GObjects. The wrappers matter here as much as the
     cards: [move] is remove-and-re-insert, and re-inserting the {i card} rather than the
     wrapper would have GTK build a second [GtkFlowBoxChild] -- which is exactly how a
     reorder would silently drop the selection. *)
  let cards_before = card_widgets live in
  let live = patch live (view ~selected:[ "b" ] ~cards:[ "c"; "a"; "b" ] ()) in
  printf
    "fb same GObjects after reorder: %b\n"
    (same_rows
       (List.map cards_before ~f:(fun c -> (c :> Widget.t)))
       (List.map (card_widgets live) ~f:(fun c -> (c :> Widget.t))));
  printf "fb the original cards are now at: %s\n" (card_positions cards_before);
  printf "fb order after reorder: %s\n" (card_labels live);
  printf "fb selection survived the reorder: %s\n" (card_keys live);
  (* A middle insert and a middle removal, which is the index arithmetic from both sides:
     the index comes from the predecessor's own [get_index], not from the reconciler's. *)
  let live = patch live (view ~selected:[ "b" ] ~cards:[ "c"; "a"; "new"; "b" ] ()) in
  printf "fb after a middle insert: %s\n" (card_labels live);
  let live = patch live (view ~selected:[ "b" ] ~cards:[ "c"; "a"; "b" ] ()) in
  printf "fb after the middle card went away: %s\n" (card_labels live);
  (* 4. The declined selection: the user clicks "a", the model keeps "b", and the frame
     that renders the same selection puts the widget back. Spec §6.5 for a container. *)
  select_card_by_hand live "a";
  printf "fb after the user clicked: %s\n" (card_keys live);
  let live = patch live (view ~selected:[ "b" ] ~cards:[ "c"; "a"; "b" ] ()) in
  printf "fb after the declining frame: %s\n" (card_keys live);
  (* Add a card and select it in one frame: the card does not exist when [reassert] would
     have run, which is why the selection is a fixup. *)
  let live = patch live (view ~selected:[ "d" ] ~cards:[ "c"; "a"; "b"; "d" ] ()) in
  printf "fb add-and-select: %s\n" (card_keys live);
  (* 5. Removing the selected card, which is the case the imperative version has a crash
     comment about ([library_window.ml]: a [selected_widget] ref left pointing at a
     destroyed card, found live as a `GTK_IS_WIDGET` critical).

     Measured here rather than assumed, because the claim in circulation is wrong:
     [gtk_flow_box_remove] {i does} emit [selected-children-changed] as the card goes (and
     so does [remove_all], which this library never calls). Either way it does not matter,
     which is the point of asserting the recovery rather than the divergence: the
     selection is re-derived from the widget on the next pass, so what the model still
     holds is by then a key naming no card -- inert -- and nothing selected is the answer
     both sides agree on. Nothing raises, and no dangling widget is reachable because
     nothing here holds a widget. *)
  (* Two selected before the removal, so that the line below can tell "the reduced
     selection" from "the empty selection" -- with only [d] selected both print [(none)]
     and a handler that reported nothing at all would pass. *)
  let live = patch live (view ~selected:[ "a"; "d" ] ~cards:[ "c"; "a"; "b"; "d" ] ()) in
  printf "fb two selected before the removal: %s\n" (card_keys live);
  reported := [];
  let live = patch live (view ~selected:[ "a"; "d" ] ~cards:[ "c"; "a"; "b" ] ()) in
  printf "fb selected card removed: %s\n" (card_keys live);
  (* What the handler was told while the card was leaving: the reduced selection, and
     never the name of the card on its way out. That is
     [Attr.on_selected_children_changed]'s promise and it is the half of "the selection
     can diverge for less than a frame" that an application can actually observe -- GTK
     emits [selected-children-changed] synchronously from [gtk_flow_box_remove], so this
     handler runs while the patch is half-done.

     Measured, and it does {i not} depend on [remove] dropping the [Child_keys] entry
     before the GTK call: [selected_keys] answers by walking the children the box still
     holds, so a departed card cannot appear in it whatever the table remembers. Moving
     that line down changes nothing here (checked). The ordering is kept because it is the
     right instinct and costs nothing, but it is belt-and-braces -- which is a correction
     to what [w_list_box.ml] claimed for it, made in both files. *)
  printf
    "fb the handler saw, as the card left: %s\n"
    (String.concat
       ~sep:" | "
       (List.rev_map !reported ~f:(fun keys ->
          if List.is_empty keys then "(none)" else String.concat ~sep:"," keys)));
  (* 6. The stale key is {i inert}, not merely tolerated. [current] can only hold keys of
     cards that exist, so comparing it against the unnarrowed [~selected] is false forever
     the moment the model holds one extra id, and every frame would then [unselect_all]
     and re-select the survivors -- so the frame below, which renders exactly what the
     frame above did, is the one that has to be silent. Without the narrowing in
     [apply_selection] it writes twice and the selection flickers off and back on sixty
     times a second. *)
  let before = !scheduled in
  let live = patch live (view ~selected:[ "a"; "d" ] ~cards:[ "c"; "a"; "b" ] ()) in
  printf
    "fb writes on an identical frame with the removed key held: %d\n"
    (!scheduled - before);
  (* ...and the card comes back selected on the frame it returns, without the model having
     changed its mind. The same-frame rule the fixup exists for, reached from the "the
     filter lifted" direction. *)
  let live = patch live (view ~selected:[ "a"; "d" ] ~cards:[ "c"; "a"; "d"; "b" ] ()) in
  printf "fb the removed card came back: %s\n" (card_keys live);
  (* 7. A multi-selection listed the other way round is not a change. GTK answers in
     widget order; the model lists whatever order it built; an unsorted comparison would
     rewrite the selection on every frame and the user could never keep one. Only the
     write count moves, which is why it is what is printed. *)
  let live = patch live (view ~selected:[ "a"; "b" ] ~cards:[ "c"; "a"; "d"; "b" ] ()) in
  printf "fb multi-selection: %s\n" (card_keys live);
  let before = !scheduled in
  let live = patch live (view ~selected:[ "b"; "a" ] ~cards:[ "c"; "a"; "d"; "b" ] ()) in
  printf "fb same selection, listed the other way: %s\n" (card_keys live);
  printf "fb writes for a re-ordered but equal selection: %d\n" (!scheduled - before);
  (* The mode and the model can disagree and GTK arbitrates: three keys handed to a
     [Single] grid leaves whichever one GTK kept. Written as asked and read back. *)
  let live =
    patch
      live
      (view ~mode:Single ~selected:[ "c"; "a"; "b" ] ~cards:[ "c"; "a"; "d"; "b" ] ())
  in
  printf "fb three keys in Single mode: %s\n" (card_keys live);
  (* A [None_] grid selects nothing however hard the model asks. *)
  let live =
    patch live (view ~mode:None_ ~selected:[ "a" ] ~cards:[ "c"; "a"; "d"; "b" ] ())
  in
  printf "fb asking a None_ grid for a selection: %s\n" (card_keys live);
  print_s (Live_tree.dump live.widget);
  (* [Browse] is the mode whose behaviour is worth pinning, and the only one that reaches
     [Live_tree]'s [(selection-mode browse)] spelling. GTK keeps exactly one child
     selected there and [unselect_all] is a no-op (measured), so a model that renders an
     empty selection to a [Browse] grid is asking for something GTK does not do: the write
     goes out as asked, GTK keeps what it kept, and the comparison differs again next
     frame. That is the documented "a model that disagrees with its mode" case, and this
     is what it looks like -- the selection does not empty, and nothing raises. *)
  let live =
    patch live (view ~mode:Browse ~selected:[ "a" ] ~cards:[ "c"; "a"; "d"; "b" ] ())
  in
  printf "fb in Browse mode: %s\n" (card_keys live);
  print_s (Live_tree.dump live.widget);
  let live =
    patch live (view ~mode:Browse ~selected:[] ~cards:[ "c"; "a"; "d"; "b" ] ())
  in
  printf "fb Browse asked for an empty selection: %s\n" (card_keys live);
  (* 8. The activation handler, end to end through GTK's own emission chain. There is no
     synthetic click in the pinned binding, but [GtkFlowBoxChild::activate] is an action
     signal and it is what a click ends in: emitting it makes GTK emit [child-activated]
     on the flow box, which reaches this library's trampoline, which looks the key up in
     [Child_keys] and hands it to the attr's handler. So this really does check that the
     key an application receives is the key of the card that was activated -- the
     [Payload] spec's whole reason to exist -- rather than only that the handler exists.

     (The same trick drives [GtkListBox::row-activated] from [GtkListBoxRow::activate];
     the list box's own live test predates the discovery and is a carry, not a gap
     introduced here.) *)
  let live =
    patch live (view ~mode:Single ~selected:[] ~cards:[ "c"; "a"; "d"; "b" ] ())
  in
  Option.iter
    (W_flow_box.child_by_key (flow_box live) "d")
    ~f:(fun c -> Gobject.Signal.emit_by_name (c :> Widget.t) ~name:"activate");
  printf "fb activation delivered the key: %s\n" (String.concat ~sep:"," !activated);
  (* 9. Teardown fires no handler: GTK emits [selected-children-changed] as the cards go
     away, and [scheduled] must not move across the destroy. *)
  let before = !scheduled in
  P.destroy ctx live;
  printf "fb handlers fired during teardown: %d\n" (!scheduled - before);
  (* 10. And the declined selection once more through a real [Driver.frame], which is the
     only thing that proves the fixup survives the frame the driver does {i not} walk: the
     view is built once and handed back by reference, so every frame after the first is
     the physically-same-node frame. *)
  let selection_seen = ref 0 in
  let declining_view =
    Node.window
      ~title:"declined-grid"
      (Node.flow_box
         ~attrs:
           [ Attr.on_selected_children_changed
               (Bonsai_gtk.Effect.of_sync_fun (fun (_ : Key.t list) ->
                  incr selection_seen))
           ]
         ~selection_mode:Single
         ~activate_on_single_click:false
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
  let driven_grid () =
    let root = Option.value_exn (Bonsai_gtk.Expert.Driver.root_widget d) in
    List.hd_exn (Bonsai_gtk.Private.Gtk_import.widget_children root)
  in
  let driven_keys () =
    match W_flow_box.selected_keys (driven_grid ()) with
    | [] -> "(none)"
    | keys -> String.concat ~sep:"," keys
  in
  printf "fb driver, after mount: %s\n" (driven_keys ());
  let w = driven_grid () in
  Option.iter (W_flow_box.child_by_key w "b") ~f:(W.Flow_box.select_child (cast w));
  printf "fb driver, after the user clicked: %s\n" (driven_keys ());
  drain ();
  printf
    "fb driver, after the frame the click armed: %s (Bonsai saw %d)\n"
    (driven_keys ())
    !selection_seen;
  Bonsai_gtk.Expert.Driver.frame d;
  printf
    "fb driver, after one more frame: %s (Bonsai saw %d)\n"
    (driven_keys ())
    !selection_seen;
  Bonsai_gtk.Expert.Driver.stop d
;;

(* ------------------------------------------------------------------------------------ *)
(* [GtkNotebook]: the same keyed machinery again, over the one container in this library
   whose children really move. *)
(* ------------------------------------------------------------------------------------ *)

let notebook (live : P.live) =
  match live.children with
  | Single (Some nb) -> nb.P.widget
  | No_children | Single None | List _ | Slots _ -> assert false
;;

(* The pages, in GTK's own order. Not [widget_children]: a [GtkNotebook]'s two children
   are an internal [GtkBox] of tabs and an internal [GtkStack] of pages, and the stack's
   child order does {i not} follow the page order (measured). [get_nth_page] is the only
   thing that answers the question this file keeps asking. *)
let page_widgets (live : P.live) = W_notebook.pages (cast (notebook live))

(* The notebook node's own kind, for the one test that reaches [Registry] for the impl
   rather than going through the patcher. *)
let notebook_kind (live : P.live) =
  match live.children with
  | Single (Some nb) -> nb.P.node.kind
  | No_children | Single None | List _ | Slots _ -> assert false
;;

(* The pages in GTK's order, named by the label each one is. The dump says the tab order
   at length (the header box's labels are in page order); this is for the cases whose
   whole claim is the {i page} order, which the dump cannot show. *)
let page_labels (live : P.live) =
  String.concat
    ~sep:","
    (List.map (page_widgets live) ~f:(fun p ->
       if String.equal (Bonsai_gtk.Private.Gtk_import.type_name p) "GtkLabel"
       then W.Label.get_text (cast p)
       else "?"))
;;

let tab_texts (live : P.live) =
  let nb : W.Notebook.t = cast (notebook live) in
  String.concat
    ~sep:","
    (List.map (page_widgets live) ~f:(fun p ->
       Option.value (W.Notebook.get_tab_label_text nb p) ~default:"<none>"))
;;

(* The page GTK is showing, as the key the node carried -- read back through the same
   [Child_keys] table every handler answers in, so this line is an assertion about the
   mapping and not only about the index. *)
let current_key (live : P.live) =
  match W_notebook.current_key (cast (notebook live)) with
  | Some key -> key
  | None -> "(none)"
;;

(* The tab order as [Live_tree.dump] shows it: the [GtkLabel]s GTK built for the tabs,
   collected in order out of the header [GtkBox] subtree of the dumped notebook.

   {b Not the same question as [tab_texts]}, which is why both are printed. [tab_texts]
   and [page_labels] are both indexed {i by page} ([get_nth_page] then
   [get_tab_label_text page]), so neither can catch a tab that failed to follow its page
   -- they would agree with each other on a notebook whose header was in a completely
   different order. This reads the header's own widget tree, which is the only independent
   answer available, and it is the reading the brief asked the reorder cases to assert.

   The header box's other children when [~scrollable] is on are [GtkButton]s holding
   [GtkImage]s, so collecting labels from this subtree picks up tabs and nothing else. *)
let tabs_in_dump (live : P.live) =
  let rec labels acc (sexp : Sexp.t) =
    match sexp with
    | Sexp.List (Atom "GtkLabel" :: rest) ->
      List.fold rest ~init:acc ~f:(fun acc field ->
        match field with
        | Sexp.List [ Atom "text"; Atom t ] -> t :: acc
        | _ -> acc)
    | Sexp.List l -> List.fold l ~init:acc ~f:labels
    | Sexp.Atom _ -> acc
  in
  let header =
    match Live_tree.dump (notebook live) with
    | Sexp.List (Atom "GtkNotebook" :: rest) ->
      List.find_map rest ~f:(function
        | Sexp.List (Atom "children" :: first :: _) -> Some first
        | _ -> None)
    | _ -> None
  in
  match header with
  | None -> "BUG: no header box in the dump"
  | Some header -> String.concat ~sep:"," (List.rev (labels [] header))
;;

let page_positions pages nb =
  String.concat
    ~sep:","
    (List.map pages ~f:(fun p -> Int.to_string (W.Notebook.page_num nb p)))
;;

(* How many of [pages] still resolve to a key in [W_notebook]'s [Child_keys] table.

   The direction the GC block does not test. That block asserts entries {i surviving} a
   major collection; this asserts them being {i dropped} when they should be -- by
   [list_ops.remove] for a page the model took away, and by [Patcher.destroy]'s
   [forget_pages] for a notebook that went away whole. Neither has a test in any of the
   three keyed containers, and both are leaks in a process-wide table if they regress: the
   ephemeron makes them bounded rather than unbounded, but "the next GC" is no more a
   bound for a tab the user closed than it is for a filtered row.

   Asked through [key_of_page] rather than through a count, because [Child_keys] exposes
   no size: the question "is this particular departed widget still remembered" is the one
   that matters, and it is answerable with what is already public. *)
let still_remembered pages =
  List.count pages ~f:(fun p -> Option.is_some (W_notebook.key_of_page p))
;;

let same_pages before after =
  List.length before = List.length after
  && List.for_all after ~f:(fun a -> List.exists before ~f:(fun b -> Gobject.same a b))
;;

(* The user clicking a tab, as far as a test can get: there is no synthetic click in the
   pinned binding, so the page is switched with the same setter GTK's own tab handler
   calls. What matters for the claim is that the widget's page differs from the model's
   when the next frame runs. *)
let switch_page_by_hand (live : P.live) key =
  let nb : W.Notebook.t = cast (notebook live) in
  match W_notebook.page_index_by_key nb key with
  | Some i -> W.Notebook.set_current_page nb i
  | None -> printf "BUG: no page for key %s\n" key
;;

(* The [Child_keys] lifetime regression for the notebook, first among its blocks for the
   reason the other two containers' run first: every line below reads the current page
   {i through} that table, so a table that empties itself under GC would leave the whole
   golden measuring nothing.

   This container is the one where [child_keys.mli]'s invariant is satisfied by
   {i construction} rather than by care -- a notebook interposes no wrapper, so the widget
   the table is keyed on is the widget the patcher retains, and there is no second
   candidate to get wrong. The regression still earns its place, because there is a
   plausible way to break it: keying on the value [get_nth_page] hands back (a fresh OCaml
   wrapper around the same GObject, unreachable the moment the walk moves on) rather than
   on the [child] the list op is given. That is one word's difference in [insert], it
   type-checks, it works perfectly until the first major collection, and then every
   [current_key] answers "(none)" and [~current_page] raises with a message listing
   [<unkeyed>] pages.

   The frames are the real thing: [reassert_only] + [run_fixups] inside the patch guard is
   what [Driver.frame] runs on a physically-same-node frame. *)
let () =
  let scheduler = Scheduler.create ~run_frame:(fun () -> ()) in
  let ctx =
    P.create_ctx
      ~signals:
        { schedule = (fun _ -> ())
        ; in_patch = (fun () -> Scheduler.in_patch scheduler)
        ; on_exn =
            (fun ~node_path exn -> printf "EXN at %s: %s\n" node_path (Exn.to_string exn))
        }
      ~on_window_created:(fun _ -> ())
  in
  let live =
    P.mount
      ctx
      ~path:"nbgc"
      ~is_root:true
      (Node.window
         ~title:"nbgc"
         (Node.notebook
            ~current_page:"b"
            [ Node.label ~key:"a" ~attrs:[ Attr.tab_label "A" ] "A"
            ; Node.label ~key:"b" ~attrs:[ Attr.tab_label "B" ] "B"
            ; Node.label ~key:"c" ~attrs:[ Attr.tab_label "C" ] "C"
            ]))
  in
  P.run_fixups ctx;
  printf "nb gc: mounted, current %s\n" (current_key live);
  Out_channel.flush stdout;
  for batch = 1 to 5 do
    for _ = 1 to 50 do
      Scheduler.with_patch_guard scheduler (fun () ->
        P.reassert_only ctx ~path:"nbgc" live;
        P.run_fixups ctx)
    done;
    Gc.full_major ();
    printf
      "nb gc: after %d frames + full_major, current %s\n"
      (batch * 50)
      (current_key live);
    Out_channel.flush stdout
  done;
  print_s (Live_tree.dump live.widget);
  P.destroy ctx live
;;

let () =
  let scheduled = ref 0 in
  let switched = ref [] in
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
  let page ?tab key =
    let attrs =
      match tab with
      | Some t -> [ Attr.tab_label t ]
      | None -> []
    in
    Node.label ~key ~attrs (String.uppercase key)
  in
  let view
    ?(scrollable = false)
    ?(show_tabs = true)
    ?(show_border = true)
    ?(tab_pos = Tab_position.Top)
    ~current
    ~pages
    ()
    =
    Node.window
      ~title:"tabs"
      (Node.notebook
         ~attrs:
           [ Attr.on_page_changed (fun key ->
               switched := key :: !switched;
               Ui_effect.Ignore)
           ]
         ~scrollable
         ~show_tabs
         ~show_border
         ~tab_pos
         ~current_page:current
         (List.map pages ~f:(fun key -> page ~tab:(String.capitalize key) key)))
  in
  let patch live node =
    let live = P.patch ctx ~path:"root" ~is_root:true live node in
    P.run_fixups ctx;
    live
  in
  (* 6, taken first because it is a claim about the {i mount}: GTK emits [switch-page]
     while the first page is being inserted -- measured on a bare [GtkNotebook], and it
     survives [freeze_notify], so [Widget_impl.batch] is not what stops it. What stops it
     is the [in_patch] guard, and this mount is inside one because that is what
     [Driver.frame] does. [scheduled] unchanged across the mount is the whole assertion,
     and it fails (reading 1) if the guard is taken away. *)
  let before_mount = !scheduled in
  let live = ref None in
  Scheduler.with_patch_guard scheduler (fun () ->
    live
    := Some
         (P.mount
            ctx
            ~path:"root"
            ~is_root:true
            (view ~current:"score" ~pages:[ "score"; "parts"; "notes" ] ()));
    P.run_fixups ctx);
  let live = Option.value_exn !live in
  printf "handlers fired during the mount: %d\n" (!scheduled - before_mount);
  (* 1. The pages, their tab labels, and which one is current. The dump shows the tab
        order (the header box's labels are in page order) and the two counters; the page
        order itself comes from [page_labels], because a notebook's internal stack does
        not hold its children in page order. *)
  print_s (Live_tree.dump live.widget);
  printf
    "pages: %s | tabs: %s | current: %s\n"
    (page_labels live)
    (tab_texts live)
    (current_key live);
  (* 2. A real reorder. [GtkNotebook] has [reorder_child], so this is the one container in
     the library for which [Reconcile.diff] emits [Move] at all -- [list_ops.move] is
     [Some], which is what [~ordered] is derived from. The mirror image is
     [live_containers.ml]'s overlay case: same GObjects, order unchanged, because that
     container's [move] is [None]. Between them they say what the marker means.

     Both halves are asserted, and neither is enough alone: identity alone is satisfied by
     a patch that moved nothing, and an order alone is satisfied by a patch that destroyed
     and rebuilt every page (which is what an unkeyed list would do, and which loses
     scroll positions, focus and any state the page's widgets hold). *)
  let before = page_widgets live in
  let nb : W.Notebook.t = cast (notebook live) in
  (* A tail page to the middle: [score;parts;notes] -> [score;notes;parts]. *)
  let live = patch live (view ~current:"score" ~pages:[ "score"; "notes"; "parts" ] ()) in
  printf "same GObjects after the reorder: %b\n" (same_pages before (page_widgets live));
  printf "the original pages are now at: %s\n" (page_positions before nb);
  printf "pages: %s | tabs: %s\n" (page_labels live) (tab_texts live);
  (* The tab order moved with them, which is the half [page_labels] and [tab_texts] cannot
     claim between them -- both are indexed by page. [tabs_in_dump] reads the header box's
     own widget tree out of [Live_tree.dump], so it is the independent answer, and it is
     printed after every one of the four moves below. The full dump is printed once, here,
     for the shape; the four one-liners are what actually pin the order. *)
  printf "tabs, from the dump: %s\n" (tabs_in_dump live);
  print_s (Live_tree.dump live.widget);
  (* The head page to the tail, which is the move [reorder_child]'s clamp would hide if
     the index were computed one too high: GTK clamps a position past the end to last, so
     a move that lands last cannot tell a correct index from an over-large one. This one
     is checked by the two moves either side of it rather than by itself. *)
  let live = patch live (view ~current:"score" ~pages:[ "notes"; "parts"; "score" ] ()) in
  printf "after the head moved to the tail: %s\n" (page_labels live);
  printf "  tabs, from the dump: %s\n" (tabs_in_dump live);
  (* A middle page to the head -- destination index 0, which is the [after = None] arm. *)
  let live = patch live (view ~current:"score" ~pages:[ "parts"; "notes"; "score" ] ()) in
  printf "after a middle page moved to index 0: %s\n" (page_labels live);
  printf "  tabs, from the dump: %s\n" (tabs_in_dump live);
  (* And one that leaves a page behind the moved one, so that an index one place out in
     either direction is visible rather than clamped away. *)
  let live = patch live (view ~current:"score" ~pages:[ "parts"; "score"; "notes" ] ()) in
  printf "after a rightward move with a page behind it: %s\n" (page_labels live);
  printf "  tabs, from the dump: %s\n" (tabs_in_dump live);
  printf "current survived every reorder: %s\n" (current_key live);
  (* A page inserted in the middle, which is the same arithmetic from the other side: the
     index comes from the predecessor's own [page_num], not from the reconciler's. *)
  let live =
    patch live (view ~current:"score" ~pages:[ "parts"; "score"; "draft"; "notes" ] ())
  in
  printf "after a middle insert: %s | tabs: %s\n" (page_labels live) (tab_texts live);
  let departing =
    List.filter (page_widgets live) ~f:(fun p ->
      Option.exists (W_notebook.key_of_page p) ~f:(String.equal "draft"))
  in
  let live = patch live (view ~current:"score" ~pages:[ "parts"; "score"; "notes" ] ()) in
  printf "after the middle page went away: %s\n" (page_labels live);
  (* And its [Child_keys] entry went with it. [list_ops.remove] drops the key before it
     tells GTK to remove the page; without that line the process-wide table keeps an entry
     for every tab any application has ever closed until the widget itself is collected.
     Nothing in any of the three keyed containers tested this direction before. *)
  printf
    "the removed page is still remembered: %d of %d\n"
    (still_remembered departing)
    (List.length departing);
  (* 3. The declined page change. The user clicks the "notes" tab; the model renders the
     same node; the frame that renders it must put the notebook back. This is spec §6.5
     for a container, and it is the reason [~current_page] is a fixup rather than an
     [update]. *)
  switch_page_by_hand live "notes";
  printf "after the user clicked a tab: %s\n" (current_key live);
  let live = patch live (view ~current:"score" ~pages:[ "parts"; "score"; "notes" ] ()) in
  printf "after the declining frame: %s\n" (current_key live);
  (* 4. Add a page and make it current in one frame. The page does not exist when
     [reassert] would have run, which is why this is a fixup; without the fixup this shows
     the old page. *)
  let live =
    patch live (view ~current:"draft" ~pages:[ "parts"; "score"; "notes"; "draft" ] ())
  in
  printf "add-and-select: %s (pages %s)\n" (current_key live) (page_labels live);
  (* A page whose kind changes is a different page to the reconciler: a fresh widget in
     the same position, keeping its key and its tab. *)
  let kinded live ~button =
    let node =
      Node.window
        ~title:"tabs"
        (Node.notebook
           ~current_page:"parts"
           [ Node.label ~key:"parts" ~attrs:[ Attr.tab_label "Parts" ] "PARTS"
           ; (if button
              then
                Node.button
                  ~key:"score"
                  ~attrs:[ Attr.tab_label "Score" ]
                  ~label:"SCORE"
                  ()
              else Node.label ~key:"score" ~attrs:[ Attr.tab_label "Score" ] "SCORE")
           ])
    in
    patch live node
  in
  let live = kinded live ~button:false in
  let before_kind_change = page_widgets live in
  let live = kinded live ~button:true in
  printf
    "kind change replaced the page widget: %b\n"
    (not (same_pages before_kind_change (page_widgets live)));
  printf
    "kind change kept the tab and the current page: %s | %s\n"
    (tab_texts live)
    (current_key live);
  (* The tab label is re-read when it changes, and -- the half an [Option.iter] over the
     new attrs would miss -- dropping the attr puts GTK's unnamed tab back rather than
     leaving the old text or drawing a blank one. *)
  let live =
    patch
      live
      (Node.window
         ~title:"tabs"
         (Node.notebook
            ~current_page:"parts"
            [ Node.label ~key:"parts" ~attrs:[ Attr.tab_label "Renamed" ] "PARTS"
            ; Node.label ~key:"score" "SCORE"
            ]))
  in
  printf "after a tab rename and a tab dropped: %s\n" (tab_texts live);
  (* The four props, as one diff in one batch, read back off the widget. *)
  let live =
    patch
      live
      (view
         ~scrollable:true
         ~show_tabs:false
         ~show_border:false
         ~tab_pos:Left
         ~current:"parts"
         ~pages:[ "parts"; "score" ]
         ())
  in
  print_s (Live_tree.dump live.widget);
  let live = patch live (view ~current:"parts" ~pages:[ "parts"; "score" ] ()) in
  printf "props back to GTK's own: %s\n" (Sexp.to_string (Live_tree.dump (notebook live)));
  (* The page-change handler, end to end through GTK's own emission chain: switching the
     page really does emit [switch-page], which reaches this library's trampoline, which
     looks the page widget up in [Child_keys] and hands the attr's handler a key. This
     patch is not inside a patch guard, so the emission is not swallowed. *)
  switched := [];
  switch_page_by_hand live "score";
  printf "the page change delivered the key: %s\n" (String.concat ~sep:"," !switched);
  (* A page carrying [Attr.visible false] cannot be made current: GTK emits [switch-page]
     and then leaves [get_current_page] where it was (measured). Nothing is clamped here,
     so the model's key is written on every frame and the widget keeps answering with the
     page it can show -- documented on [Node.notebook], and the only way [~current_page]
     can name a page that exists and still not land. *)
  let hidden ~current =
    Node.window
      ~title:"tabs"
      (Node.notebook
       (* The handler is what makes the write count below observable: a [set_current_page]
          that does not land still emits [switch-page], and these patches are not inside a
          patch guard, so every attempt reaches [scheduled]. *)
         ~attrs:
           [ Attr.on_page_changed (fun key ->
               switched := key :: !switched;
               Ui_effect.Ignore)
           ]
         ~current_page:current
         [ Node.label ~key:"parts" ~attrs:[ Attr.tab_label "Parts" ] "PARTS"
         ; Node.label
             ~key:"score"
             ~attrs:[ Attr.tab_label "Score"; Attr.visible false ]
             "SCORE"
         ])
  in
  let live = patch live (hidden ~current:"parts") in
  let live = patch live (hidden ~current:"score") in
  printf "asking for a hidden page: %s\n" (current_key live);
  (* Two more identical frames, each of which rewrites: the comparison is a read-back of
     the live widget, which never moves, so it never comes out equal. That is the cost the
     constructor documents -- a model to bring into line, not a loop and not an error --
     and it is the only way [~current_page] can name a page that exists and still not
     land.

     What this does {i not} show is any difference between comparing indices and comparing
     keys: [W_notebook.current_key] is [get_current_page] with two lookups on top, so the
     two are the same predicate and this line reads 2 either way. The comparison that
     would report success here is one against the {i previous node} -- an [update]-style
     comparison -- which is exactly what makes this a fixup instead. *)
  let before = !scheduled in
  let live = patch live (hidden ~current:"score") in
  let live = patch live (hidden ~current:"score") in
  printf "and it is rewritten on every identical frame: %d\n" (!scheduled - before);
  let live = patch live (hidden ~current:"parts") in
  printf "back to a visible page: %s\n" (current_key live);
  (* 5. Removing the current page. GTK picks a neighbour; the model still names the page
     that left; the fixup then {b raises}, because [~current_page] names no page.

     This is the documented behaviour and it is the {i application's} bug: a model that
     removes the page it is showing without moving its selection has rendered a view it
     does not have, and it will render the same inconsistency on every frame afterwards
     while the notebook shows whatever GTK picked. Raising says so once and loudly; the
     alternative -- clamp to GTK's choice and let the model hear about it through
     [Attr.on_page_changed] -- would leave the divergence spec §6.5 exists to prevent
     sitting in the tree, and would do it silently.

     Note the shape of the assertion: [P.patch] itself succeeds (the page really is gone
     and the tree really is patched), and it is [P.run_fixups] that raises. The queue is
     emptied on the way out, so the frames after this one are unaffected. *)
  let live = patch live (view ~current:"score" ~pages:[ "parts"; "score"; "notes" ] ()) in
  let live =
    P.patch
      ctx
      ~path:"root"
      ~is_root:true
      live
      (view ~current:"score" ~pages:[ "parts"; "notes" ] ())
  in
  printf "the page was removed: %s\n" (page_labels live);
  (match P.run_fixups ctx with
   | () -> printf "BUG: no raise\n"
   | exception exn -> printf "the fixup raised: %s\n" (Exn.to_string exn));
  printf "GTK picked: %s\n" (current_key live);
  (* And the model bringing itself into line is an ordinary frame again. *)
  let live = patch live (view ~current:"notes" ~pages:[ "parts"; "notes" ] ()) in
  printf "after the model moved its selection: %s\n" (current_key live);
  (* An empty notebook is the one frame on which a [~current_page] that resolves to
     nothing is not a mistake: the argument is required, so a model rendering no pages has
     no key it could pass that would be right. Left inert, and the frame that adds the
     first page shows it -- which is the same-frame rule from the other direction. *)
  let live = patch live (view ~current:"notes" ~pages:[] ()) in
  printf
    "an empty notebook: pages=%d current=%s (no raise)\n"
    (List.length (page_widgets live))
    (current_key live);
  (* Dumped, because this is the only tree in which [get_current_page] answers GTK's [-1]
     sentinel and the dump is where a reader would meet it. It prints as [()], the same
     "nothing" a stack's [(visible ())] prints and the same one [current_key] answers. *)
  print_s (Live_tree.dump (notebook live));
  let live = patch live (view ~current:"notes" ~pages:[ "parts"; "notes" ] ()) in
  printf "the first page arrived: %s\n" (current_key live);
  (* 7. Teardown does not fire a handler. GTK emits [switch-page] as pages go away;
     [scheduled] must not move across the destroy, because [Patcher.destroy] empties the
     slots before anything is unparented. *)
  let before = !scheduled in
  let torn_down = page_widgets live in
  P.destroy ctx live;
  printf "handlers fired during teardown: %d\n" (!scheduled - before);
  (* The other half of the table's bookkeeping, and the path [list_ops.remove] never
     covers: a notebook torn down whole has its pages walked by the patcher rather than
     removed from their parent, so [Patcher.destroy]'s [forget_pages] arm is the only
     thing that drops their entries. Deleting that arm leaves this line reading 2. *)
  printf
    "pages still remembered after teardown: %d of %d\n"
    (still_remembered torn_down)
    (List.length torn_down)
;;

(* The [move] arm no frame reaches.

   [Reconcile.diff] emits every [Move] with [from > to_] -- it scans left to right and
   always finds its match at or after the index it is filling -- so [w_notebook.ml]'s
   [if from < a] branch is unreachable through the patcher, and the four moves above all
   take the [else]. That was pointed out in review ([task-8-review.md] N1), and the report
   had claimed the four moves covered "both directions"; they do not.

   The branch is kept (see the comment there for why an [assert] was rejected), so it is
   exercised here directly instead: [Registry] hands back the impl, and its
   [list_ops.move] is called by hand with an [~after] that sits {i after} the page being
   moved, which is the shape a forward [Move] would produce. Four pages rather than three,
   because [reorder_child] clamps a position past the end -- with only three, the wrong
   index and the right one both land on the same order and the test would pass either way.

   A,B,C,D with A moved to sit after B must give B,A,C,D. The shipped conditional computes
   [from=0 < a=1], so [position = 1]. The unconditional [a + 1] a reader might "simplify"
   it to computes 2, and GTK gives B,C,A,D -- which is the line that changes if the hedge
   is deleted. *)
let () =
  let scheduler = Scheduler.create ~run_frame:(fun () -> ()) in
  let ctx =
    P.create_ctx
      ~signals:
        { schedule = (fun _ -> ())
        ; in_patch = (fun () -> Scheduler.in_patch scheduler)
        ; on_exn =
            (fun ~node_path exn -> printf "EXN at %s: %s\n" node_path (Exn.to_string exn))
        }
      ~on_window_created:(fun _ -> ())
  in
  let live =
    P.mount
      ctx
      ~path:"fwd"
      ~is_root:true
      (Node.window
         ~title:"fwd"
         (Node.notebook
            ~current_page:"a"
            (List.map [ "a"; "b"; "c"; "d" ] ~f:(fun k ->
               Node.label
                 ~key:k
                 ~attrs:[ Attr.tab_label (String.uppercase k) ]
                 (String.uppercase k)))))
  in
  P.run_fixups ctx;
  printf "forward move: before %s\n" (page_labels live);
  let move =
    match (Registry.for_kind (notebook_kind live)).children with
    | Widget_impl.List { move = Some move; _ } -> move
    | _ -> failwith "the notebook impl has no list move"
  in
  let nb = notebook live in
  let page key = Option.value_exn (List.nth (page_widgets live) key) in
  (* [~child] is at index 0 and [~after] at index 1, so [from < a] -- the arm the
     reconciler never produces. *)
  move nb ~child:(page 0) ~after:(Some (page 1));
  printf "forward move: after %s\n" (page_labels live);
  printf "forward move: tabs, from the dump: %s\n" (tabs_in_dump live);
  P.destroy ctx live
;;

(* The declined page change through a real [Driver.frame], which is the claim the
   hand-driven patch above cannot make: a frame that hands back the physically same node
   is not diffed at all, so the fixups are the only thing that runs -- and a driver that
   skipped them would lose the correction. [live_driver.ml] makes this claim for a toggle
   ([Widget_impl.reassert]) and for a stack page; this is the notebook's. *)
let () =
  let page_seen = ref 0 in
  let declining_view =
    Node.window
      ~title:"declined"
      (Node.notebook
         ~attrs:
           [ Attr.on_page_changed
               (Bonsai_gtk.Effect.of_sync_fun (fun (_ : Key.t) -> incr page_seen))
           ]
         ~current_page:"score"
         [ Node.label ~key:"score" ~attrs:[ Attr.tab_label "Score" ] "SCORE"
         ; Node.label ~key:"parts" ~attrs:[ Attr.tab_label "Parts" ] "PARTS"
         ])
  in
  let time_source = Bonsai.Time_source.create ~start:Time_ns.epoch in
  let d =
    Bonsai_gtk.Expert.Driver.create
      ~time_source
      ~on_window_created:(fun _ -> ())
      (fun (_graph @ local) -> Bonsai.return declining_view)
  in
  Bonsai_gtk.Expert.Driver.frame d;
  let driven_notebook () =
    let root = Option.value_exn (Bonsai_gtk.Expert.Driver.root_widget d) in
    List.hd_exn (Bonsai_gtk.Private.Gtk_import.widget_children root)
  in
  let driven_key () =
    match W_notebook.current_key (cast (driven_notebook ())) with
    | Some key -> key
    | None -> "(none)"
  in
  (* The mount happened inside a real frame, so the [switch-page] GTK emits while the
     first page is inserted was swallowed by the guard: [page_seen] is 0. *)
  printf "nb driver, after mount: %s (Bonsai saw %d)\n" (driven_key ()) !page_seen;
  let nb : W.Notebook.t = cast (driven_notebook ()) in
  Option.iter
    (W_notebook.page_index_by_key nb "parts")
    ~f:(W.Notebook.set_current_page nb);
  (* Printed before the drain as well as after: the emission arms a GLib idle, and by the
     time the loop is handed back the correcting frame has already run -- so without this
     line the claim would be indistinguishable from a click that never landed. *)
  printf "nb driver, after the user clicked a tab: %s\n" (driven_key ());
  drain ();
  printf
    "nb driver, after the frame the click armed: %s (Bonsai saw %d)\n"
    (driven_key ())
    !page_seen;
  (* And a further no-diff frame writes nothing: [select] compares against the widget
     before it writes, so nothing here should move and [switch-page] should not fire
     again. *)
  Bonsai_gtk.Expert.Driver.frame d;
  printf
    "nb driver, after one more frame: %s (Bonsai saw %d)\n"
    (driven_key ())
    !page_seen;
  Bonsai_gtk.Expert.Driver.stop d
;;

(* ------------------------------------------------------------------------------------ *)

(* The selection fixup's cost per idle frame, at the scale the flow box is the container
   for. This is a regression rather than a benchmark: its job is to fail if the shape of
   [apply_selection] ever goes back to being quadratic in the selection.

   The shape it guards against ([task-7-review.md]'s I1): [apply_selection] runs from the
   fixup queue on every mount, every patch {i and} every no-change frame through
   [reassert_only], so its cost is paid sixty times a second by an application doing
   nothing. Resolving each key with a linear walk of the children made that O(|selected| x
   n): measured on the shipped-then-fixed code at n=1000 with 200 selected, an {i idle}
   frame cost 16.5 ms -- the whole 16.7 ms budget, spent deciding that nothing had changed
   -- and 500-of-500 cost 24 ms, at which point the driver cannot reach 60 fps at all
   while the selection is held. With the per-call map the same frame is 0.39 ms.

   {b What is asserted is a ratio, not a wall-clock bound}, and that is
   [task-7-review.md]'s N1 taken in its second form. The bound used to be "under 2 ms per
   idle frame", which has five times the headroom on an idle machine and about 3% on a
   contended one: the reviewer reproduced a real failure (2.312 ms) at 2x CPU
   oversubscription, with three more samples within 3% of the line, and a CI runner
   sharing a host reaches that. Raising the bound to 8 ms would have been the one-line
   fix. This is the other one, and it is a better instrument for the same price: the
   property under test is that the cost does {i not} scale with the size of the selection,
   so the same fixup is timed at two selection sizes over one child list and the {i ratio}
   is what the golden gets. Contention scales both measurements, so it cancels. The fixed
   code measures ~1.1 and the quadratic code ~57 (the reviewer's numbers, and mine); a
   bound of 5 is an order of magnitude clear of both ends and is not a timing at all.

   The frames are the real thing: [reassert_only] + [run_fixups] inside the patch guard is
   what [Driver.frame] runs when a computation hands back the physically same node.

   The golden gets the verdict rather than the numbers, because a timing is not
   reproducible; the numbers go to stderr, which is not compared, so a failure says how
   far over it went rather than only [false]. *)
let () =
  let n = 1000 in
  let many = 200 in
  let bound_ratio = 5.0 in
  let frames = 200 in
  let scheduler = Scheduler.create ~run_frame:(fun () -> ()) in
  let ctx =
    P.create_ctx
      ~signals:
        { schedule = (fun _ -> ())
        ; in_patch = (fun () -> Scheduler.in_patch scheduler)
        ; on_exn =
            (fun ~node_path exn -> printf "EXN at %s: %s\n" node_path (Exn.to_string exn))
        }
      ~on_window_created:(fun _ -> ())
  in
  let key i = sprintf "k%d" i in
  let cards = List.init n ~f:(fun i -> Node.label ~key:(key i) (Int.to_string i)) in
  (* One measurement: mount a grid of [n] cards with [sel] of them selected, run [frames]
     idle frames through the fixup queue, and answer the milliseconds each one cost. The
     selection is spread through the list rather than taken from the front, so that
     neither the walk nor the map is flattered by locality. *)
  let idle_frame_ms ~sel =
    let selected = List.init sel ~f:(fun i -> key (i * (n / sel))) in
    let live =
      P.mount
        ctx
        ~path:"bench"
        ~is_root:true
        (Node.window
           ~title:"bench"
           (Node.flow_box ~selection_mode:Multiple ~selected cards))
    in
    P.run_fixups ctx;
    (* The selection is exactly the one asked for, which is what stops this from timing a
       fixup that has quietly stopped doing anything. *)
    let selected_count = List.length (W_flow_box.selected_keys (flow_box live)) in
    printf "bench: n=%d, selected %d of %d\n" n selected_count sel;
    let start = Time_ns.now () in
    for _ = 1 to frames do
      Scheduler.with_patch_guard scheduler (fun () ->
        P.reassert_only ctx ~path:"bench" live;
        P.run_fixups ctx)
    done;
    let ms =
      Time_ns.Span.to_ms (Time_ns.diff (Time_ns.now ()) start) /. Int.to_float frames
    in
    P.destroy ctx live;
    ms
  in
  let one = idle_frame_ms ~sel:1 in
  let lots = idle_frame_ms ~sel:many in
  let ratio = lots /. one in
  printf
    "bench: %d idle frames at 1 and at %d selected, cost ratio under %g: %b\n"
    frames
    many
    bound_ratio
    Float.(ratio < bound_ratio);
  eprintf
    "bench: %.3f ms at sel=1, %.3f ms at sel=%d, ratio %.2f (bound %g)\n%!"
    one
    lots
    many
    ratio
    bound_ratio
;;
