open! Core
open Bonsai_gtk_vtree
module Native_gtk = Bonsai_gtk.Private.Native_gtk
module Registry = Bonsai_gtk.Private.Registry
module Signals = Bonsai_gtk.Private.Signals
module Widget = Bonsai_gtk.Private.Gtk_import.Widget
module W = Bonsai_gtk.Private.Gtk_import.W

(* A native node needs a real impl to reach [Registry.for_kind]: [Native.Unit] has no Gtk
   payload. Nothing here creates the widget -- the impl's [signals] is a record field --
   but the impl has to exist for the lookup to succeed. *)
module Native_thing = struct
  type input = unit

  let name = "thing"
  let create () = (W.Label.new_ (Some "thing") :> Widget.t)
  let update _ ~old:() () = ()
  let destroy _ = ()
end

let thing_impl = Native_gtk.impl (module Native_thing)

(* Every kind, built with its cheapest constructor. This list is the one place that has to
   grow with [Kind.t]; there is no exhaustive-match trick that produces a *value* per
   constructor, so a new kind missing from here is caught by the count assertion below
   rather than by the compiler. *)
let all_kinds : Kind.t list =
  let child () = Node.label "x" in
  [ (Node.label "x").kind
  ; (Node.button ()).kind
  ; (Node.toggle_button ~active:false ()).kind
  ; (Node.check_button ~active:false ()).kind
  ; (Node.switch ~active:false ()).kind
  ; (Node.entry ~text:"" ()).kind
  ; (Node.password_entry ~text:"" ()).kind
  ; (Node.search_entry ~text:"" ()).kind
  ; (Node.text_view ~text:"" ()).kind
  ; (Node.spin_button ~min:0. ~max:1. ~value:0. ()).kind
  ; (Node.scale ~orientation:Horizontal ~min:0. ~max:1. ~value:0. ()).kind
  ; (Node.progress_bar ~fraction:0. ()).kind
  ; (Node.spinner ~spinning:false ()).kind
  ; (Node.level_bar ~value:0. ()).kind
  ; (Node.image (Icon_name "x")).kind
  ; (Node.picture (Filename "x")).kind
  ; (Node.separator ~orientation:Horizontal ()).kind
  ; (Node.scrolled_window (child ())).kind
  ; (Node.frame (child ())).kind
  ; (Node.expander ~expanded:false ~label:"e" (child ())).kind
  ; (Node.revealer ~reveal:false (child ())).kind
  ; (Node.box ~orientation:Vertical []).kind
  ; (Node.grid []).kind
  ; (Node.stack ~name:"s" ~visible_child:"a" []).kind
  ; (Node.stack_switcher ~stack:"s" ()).kind
  ; (Node.stack_sidebar ~stack:"s" ()).kind
  ; (Node.list_box ~selected:[] []).kind
  ; (Node.flow_box ~selected:[] []).kind
  ; (Node.notebook ~current_page:"a" []).kind
  ; (Node.drop_down ~items:[] ~selected:(-1) ()).kind
  ; (Node.calendar ~date:(Date.of_string "2026-08-30") ()).kind
  ; (Node.editable_label ~text:"" ()).kind
  ; (Node.center_box ()).kind
  ; (Node.paned ~orientation:Horizontal ~start:(child ()) ~end_:(child ()) ()).kind
  ; (Node.overlay (child ())).kind
  ; (Node.window (child ())).kind
  ; (Native_gtk.node thing_impl ()).kind
  ]
;;

(* The list above is hand-maintained; [Kind.Variants.descriptions] is not. A kind added to
   [Kind.t] without a row here fails this assertion rather than quietly going unchecked --
   which matters because [Events.for_kind]'s missing wildcard forces a *decision* for a
   new kind but nothing forces that decision to be *tested*.

   By {i name} and not by count. A count is satisfied by a duplicated row plus an omitted
   one, which is exactly the drift Task 1 recorded as a carry when it left the two
   [all_kinds] lists duplicated; [test/handle/test_gallery.ml]'s sweeps subtract names for
   the same reason, and this is that idiom brought here (task-13-review.md N6). The names
   are [Kind.Variants.to_name]'s -- the OCaml constructor -- because that is the one the
   compiler writes; [Kind.name] is the GTK class and is a different string. *)
let () =
  let covered = List.map all_kinds ~f:Kind.Variants.to_name in
  let missing =
    List.filter_map Kind.Variants.descriptions ~f:(fun (name, _) ->
      if List.mem covered name ~equal:String.equal then None else Some name)
  in
  if not (List.is_empty missing)
  then raise_s [%message "kinds with no row in all_kinds" (missing : string list)]
;;

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
            ~impl_declares:(from_impl : Attr.Name.t list)
            ~table_says:(from_table : Attr.Name.t list)]);
  (* Still printed, because a reader of the golden wants to see it -- but no longer the
     only thing standing between a new kind and an unchecked table entry: the assertion
     above derives the number from [Kind.t] itself. *)
  printf "kinds checked: %d\n" (List.length all_kinds);
  printf "agreed\n"
;;

(* No widget impl may declare a controller attr in its [Widget_impl.signals].

   [Controllers] connects those, from the attr itself, on the frame the attr appears -- so
   an impl that also declared one would connect a second handler to the *widget*, which
   nothing ever removes (teardown disconnects what [Controllers] connected, not what the
   impl did behind its back) and which would fire alongside the controller's. It would
   also hide the mistake: [Signals.require_slots] skips controller attrs precisely because
   no impl declares one, and a slot appearing under that name would make the skip look
   unnecessary rather than wrong.

   [Events.for_kind] already says none of them is any kind's signal and [live_events]'
   comparison above already fails if an impl declares a name the table omits -- so this is
   the same fact from the other side, stated where a reader looking for it will find it. *)
let () =
  List.iter all_kinds ~f:(fun kind ->
    List.iter (Registry.for_kind kind).signals ~f:(fun spec ->
      let name = Signals.spec_attr spec in
      if Events.is_controller_attr name
      then
        print_s
          [%message
            "IMPL DECLARES A CONTROLLER ATTR" ~kind:(Kind.name kind) (name : Attr.Name.t)]));
  printf "no impl declares a controller attr\n"
;;
