open! Core
open Bonsai_gtk_vtree
open Gtk_import

let mode : Level_bar_mode.t -> Gtk_enums.levelbarmode = function
  | Continuous -> `CONTINUOUS
  | Discrete -> `DISCRETE
;;

(* The bounds, written in an order that never leaves the minimum above the maximum.

   That state is reachable and GTK does not defend against it:
   [gtk_level_bar_set_min_value] checks nothing about the maximum, so writing [min] first
   on a bar moving from [0.]-[1.] to [2.]-[10.] leaves it holding [min=2 max=1] for the
   length of one call -- and, worse than transiently, it clamps [value] {i up} to the new
   minimum on the way through, so a value the model is about to write correctly is briefly
   wrong and a bar whose bounds move without its value moving is left showing the minimum.
   Measured on GTK 4.22: a fresh bar given [set_min_value 2.] reads back
   [min=2 max=1 value=2], with nothing on stderr.

   The rule is one comparison. Writing [max] first passes through [(old_min, new_max)],
   which is bad exactly when [old_min > new_max]; writing [min] first passes through
   [(new_min, old_max)], which is bad exactly when [new_min > old_max]. Both invariants
   ([old_min <= old_max] and [new_min <= new_max]) hold -- the second because
   [Node.level_bar] rejects a [~min] above its [~max] -- so the two conditions cannot both
   be true, and testing either one picks a safe order. This tests the second, which is the
   "the range moved up, so widen at the top first" case.

   [old_min]/[old_max] are the {i previous node's} numbers rather than the widget's, and
   that is sound here for the reason it is not sound for a controlled prop: a level bar
   has no interaction at all, so nothing but this code has ever written those two
   properties. *)
let set_bounds (b : W.Level_bar.t) ~old_min ~old_max ~min ~max =
  let write_min () = if Float.( <> ) old_min min then W.Level_bar.set_min_value b min in
  let write_max () = if Float.( <> ) old_max max then W.Level_bar.set_max_value b max in
  if Float.( > ) min old_max
  then (
    write_max ();
    write_min ())
  else (
    write_min ();
    write_max ())
;;

let impl : Widget_impl.t =
  { name = "LevelBar"
  ; create =
      (fun (kind : Kind.t) ->
        match kind with
        | Level_bar p ->
          (* [new_for_interval] rather than [new_ ()] followed by two setters: it hands
             both bounds to [g_object_new], so the create path has no intermediate state
             at all and does not have to reason about the order above. *)
          let b = W.Level_bar.new_for_interval p.min p.max in
          let w = (b :> Widget.t) in
          Widget_impl.batch w (fun () ->
            (match p.mode with
             (* GTK's own, so writing it would be a no-op with a [notify::] attached. *)
             | Continuous -> ()
             | m -> W.Level_bar.set_mode b (mode m));
            if p.inverted then W.Level_bar.set_inverted b true;
            (* Value last, here as in [update]: the bounds clamp it, so writing it first
               would hand the clamp a range the node never asked for. *)
            W.Level_bar.set_value b p.value);
          w
        | k -> Widget_impl.wrong_kind "LevelBar" k)
  ; update =
      (fun w ~(old : Kind.t) (new_ : Kind.t) ->
        match old, new_ with
        | Level_bar old, Level_bar new_ ->
          let b : W.Level_bar.t = cast w in
          Widget_impl.batch w (fun () ->
            set_bounds b ~old_min:old.min ~old_max:old.max ~min:new_.min ~max:new_.max;
            if not (Level_bar_mode.equal old.mode new_.mode)
            then W.Level_bar.set_mode b (mode new_.mode);
            if not (Bool.equal old.inverted new_.inverted)
            then W.Level_bar.set_inverted b new_.inverted;
            (* Value last, and written whenever it differs from the {i previous node's} --
               which is what an uncontrolled prop compares against, unlike every
               controlled one in this directory.

               It is also written when only the {i bounds} moved, and it has to be. The
               clamping is asymmetric: [set_min_value] and [set_max_value] drag the live
               value into the new range, while [set_value] does not clamp at all. So a bar
               moved from 0-1 to 0.8-1 with its value standing at 0.5 has had that 0.5
               clamped to 0.8 by the bound write, and only an unconditional rewrite puts
               the model's number back. [test/live/live_text.ml] pins that line, and
               deleting either disjunct here makes it print GTK's number instead. *)
            if Float.( <> ) old.value new_.value
               || Float.( <> ) old.min new_.min
               || Float.( <> ) old.max new_.max
            then W.Level_bar.set_value b new_.value)
        | _, k -> Widget_impl.wrong_kind "LevelBar" k)
  ; (* Nothing here is controlled, and that is not an omission: a [GtkLevelBar] has no
       interaction -- no drag, no scroll, no keyboard -- so its properties only ever
       change because this code wrote them, and there is nothing for a re-assertion to
       correct. [Node.level_bar] says so to the application in the same words. *)
    reassert = None
  ; (* [GtkLevelBar::offset-changed] exists and is bound, but it reports a change to a
       named offset {i marker}, which this library exposes no way to add -- so a handler
       for it could never fire. Omitted rather than bound to something inert (spec §11);
       [Events.for_kind] says the same from the other side. *)
    signals = []
  ; children = Widget_impl.No_children
  }
;;
