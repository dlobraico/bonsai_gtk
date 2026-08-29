open! Core
open Bonsai_gtk_vtree
open Gtk_import

let orientation : Orientation.t -> Gtk_enums.orientation = function
  | Horizontal -> `HORIZONTAL
  | Vertical -> `VERTICAL
;;

(* A [GtkScale] *is* a [GtkRange]: the value, the bounds, the increments and [inverted]
   all live there, and so does [value-changed]. Only the presentation props are the
   scale's own. [Range] has no [from_gobject], so the downcast is [Gtk_import.cast], which
   is sound because [Scale.t]'s phantom row already contains [`range]. *)
let value_changed : Signals.spec =
  { attr = Attr.Name.On_value_changed
  ; connect = (fun w ~callback -> W.Range.on_value_changed (cast w) ~callback)
  ; fire =
      (fun w (attr : Attr.t) ->
        match attr with
        (* Read back off the widget for the same reason as [w_spin_button.ml]'s. *)
        | On_value_changed handler -> Some (handler (W.Range.get_value (cast w)))
        | _ -> None)
  }
;;

(* Controlled against the widget's live value, on the rule and with the exact-equality
   argument set out in [w_spin_button.ml]. The slider is where the rule bites hardest: a
   drag the model declines is pulled back mid-gesture, which is jarring, and is still the
   right answer — the alternative is a slider and a model that disagree with nothing to
   say so. The plan's Open Question 2 rules on this. *)
let set_value_if_needed (r : W.Range.t) value =
  if Float.( <> ) (W.Range.get_value r) value then W.Range.set_value r value
;;

(* As on the spin button, and for the same reason: GTK needs a page increment (Page
   Up/Down) as well as a step, [new_with_range] has to pick one, and no caller has wanted
   to name it separately. See [Node.scale]. *)
let page step = step *. 10.

let impl : Widget_impl.t =
  { name = "Scale"
  ; create =
      (fun (kind : Kind.t) ->
        match kind with
        | Scale p ->
          let s = W.Scale.new_with_range (orientation p.orientation) p.min p.max p.step in
          let w = (s :> Widget.t) in
          Widget_impl.batch w (fun () ->
            (* [new_with_range] derives the page increment and [digits] from [step]; both
               are then said explicitly, so a node and the widget it built agree. *)
            W.Range.set_increments (cast w) p.step (page p.step);
            W.Scale.set_digits s p.digits;
            W.Scale.set_draw_value s p.draw_value;
            W.Scale.set_has_origin s p.has_origin;
            if p.inverted then W.Range.set_inverted (cast w) true;
            (* Value last: [set_digits] also sets the range's rounding. *)
            set_value_if_needed (cast w) p.value);
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
            then W.Range.set_increments r new_.step (page new_.step);
            if old.digits <> new_.digits then W.Scale.set_digits s new_.digits;
            if not (Bool.equal old.draw_value new_.draw_value)
            then W.Scale.set_draw_value s new_.draw_value;
            if not (Bool.equal old.has_origin new_.has_origin)
            then W.Scale.set_has_origin s new_.has_origin;
            if not (Bool.equal old.inverted new_.inverted)
            then W.Range.set_inverted r new_.inverted)
          (* [value] is deliberately absent: controlled, hence [reassert]'s. *)
        | _, k -> Widget_impl.wrong_kind "Scale" k)
  ; reassert =
      Some
        (fun w (kind : Kind.t) ->
          match kind with
          | Scale p ->
            Widget_impl.batch w (fun () -> set_value_if_needed (cast w) p.value)
          | k -> Widget_impl.wrong_kind "Scale" k)
  ; signals = [ value_changed ]
  ; children = Widget_impl.No_children
  }
;;
