open! Core
open Bonsai_gtk_vtree
open Gtk_import

(* A [GtkSpinButton] is *not* a [GtkRange] — it owns its own [GtkAdjustment] and its own
   setters — so nothing here can be shared with [w_scale.ml] beyond the shape. *)
let value_changed : Signals.spec =
  { attr = Attr.Name.On_value_changed
  ; connect =
      (fun w ~callback ->
        Signals.connected w (W.Spin_button.on_value_changed (cast w) ~callback))
  ; fire =
      (fun w attr ->
        match (attr :> Attr.Private.t) with
        (* The value read back off the widget, not one carried by the signal: GTK's
           [value-changed] has no payload, and the widget's number is the clamped and
           rounded one the user is actually looking at (spec §6.4). *)
        | On_value_changed handler -> Some (handler (W.Spin_button.get_value (cast w)))
        | _ -> None)
  }
;;

(* Controlled (spec §6.5), on the identical rule to [w_entry.ml]'s text and against
   the *widget's* value rather than the previous node's: the user may have spun it since
   the last render, and a model that declined the change renders the same props it
   rendered before — so [update] is skipped and this is the only thing left to pull the
   widget back. Hence [reassert] rather than a line in [update].

   The comparison is exact [Float.equal], not an epsilon. GTK clamps what is written into
   [min, max] and rounds it to [digits], so a model value the widget cannot represent
   never compares equal and is re-written on every patch — but [gtk_adjustment_set_value]
   is itself a no-op when the clamped result is unchanged, so that costs one C call and
   emits nothing. An epsilon would trade that for the opposite and worse failure: a real
   divergence small enough to fall inside it would be left standing, which is precisely
   what §6.5 exists to prevent. *)
let needs_value (s : W.Spin_button.t) value =
  Float.( <> ) (W.Spin_button.get_value s) value
;;

let set_value_if_needed (s : W.Spin_button.t) value =
  if needs_value s value then W.Spin_button.set_value s value
;;

(* GTK needs a page increment (Page Up/Down) as well as a step, and [new_with_range] picks
   one; [step *. 10.] is what this library writes rather than adding a prop no caller has
   wanted to name. See [Node.spin_button]. *)
let page step = step *. 10.

let impl : Widget_impl.t =
  { name = "SpinButton"
  ; create =
      (fun (kind : Kind.t) ->
        match kind with
        | Spin_button p ->
          (* [new_with_range] builds the [GtkAdjustment] for us; there is no reason to
             hold one on the OCaml side, since every prop that touches it is re-derived
             from the node. *)
          let s = W.Spin_button.new_with_range p.min p.max p.step in
          let w = (s :> Widget.t) in
          Widget_impl.batch w (fun () ->
            (* [new_with_range] derives both the page increment and [digits] from [step];
               both are then said explicitly, so a node and the widget it built agree. *)
            W.Spin_button.set_increments s p.step (page p.step);
            W.Spin_button.set_digits s p.digits;
            W.Spin_button.set_numeric s p.numeric;
            W.Spin_button.set_wrap s p.wrap;
            if p.activates_default then W.Spin_button.set_activates_default s true;
            (* Value last, here as in [reassert]: [set_digits] rounds the value it finds,
               so writing it first would hand the rounding a number the model never chose. *)
            set_value_if_needed s p.value);
          w
        | k -> Widget_impl.wrong_kind "SpinButton" k)
  ; update =
      (fun w ~(old : Kind.t) (new_ : Kind.t) ->
        match old, new_ with
        | Spin_button old, Spin_button new_ ->
          let s : W.Spin_button.t = cast w in
          Widget_impl.batch w (fun () ->
            if Float.( <> ) old.min new_.min || Float.( <> ) old.max new_.max
            then W.Spin_button.set_range s new_.min new_.max;
            if Float.( <> ) old.step new_.step
            then W.Spin_button.set_increments s new_.step (page new_.step);
            if old.digits <> new_.digits then W.Spin_button.set_digits s new_.digits;
            if not (Bool.equal old.numeric new_.numeric)
            then W.Spin_button.set_numeric s new_.numeric;
            if not (Bool.equal old.wrap new_.wrap) then W.Spin_button.set_wrap s new_.wrap;
            if not (Bool.equal old.activates_default new_.activates_default)
            then W.Spin_button.set_activates_default s new_.activates_default)
          (* [value] is deliberately absent: it is controlled, so it belongs to
             [reassert], which the patcher runs immediately after this and on every other
             patch too — including the ones where a new [min]/[max] has just clamped the
             value out from under the model. *)
        | _, k -> Widget_impl.wrong_kind "SpinButton" k)
  ; reassert =
      Some
        (fun w (kind : Kind.t) ->
          match kind with
          | Spin_button p ->
            let s : W.Spin_button.t = cast w in
            let writes = needs_value s p.value in
            Widget_impl.batch_if writes w (fun () ->
              if writes then W.Spin_button.set_value s p.value)
          | k -> Widget_impl.wrong_kind "SpinButton" k)
  ; signals = [ value_changed ]
  ; children = Widget_impl.No_children
  }
;;
