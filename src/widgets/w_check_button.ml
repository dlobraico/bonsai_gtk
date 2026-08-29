open! Core
open Bonsai_gtk_vtree
open Gtk_import

let toggled : Signals.spec =
  { attr = Attr.Name.On_toggled
  ; connect = (fun w ~callback -> W.Check_button.on_toggled (cast w) ~callback)
  ; fire =
      (fun w (attr : Attr.t) ->
        match attr with
        | On_toggled handler -> Some (handler (W.Check_button.get_active (cast w)))
        | _ -> None)
  }
;;

(* A [GtkCheckButton] is *not* a [GtkButton] — it derives straight from [GtkWidget] — so
   none of [w_button.ml]'s setters apply to it, and it has its own [set_label] (which,
   unlike [Button]'s, does take an option). *)
let impl : Widget_impl.t =
  { name = "CheckButton"
  ; create =
      (fun (kind : Kind.t) ->
        match kind with
        | Check_button p ->
          let c = W.Check_button.new_ () in
          Widget_impl.batch
            (c :> Widget.t)
            (fun () ->
              W.Check_button.set_label c p.label;
              if p.active then W.Check_button.set_active c true;
              if p.inconsistent then W.Check_button.set_inconsistent c true);
          (c :> Widget.t)
        | k -> Widget_impl.wrong_kind "CheckButton" k)
  ; update =
      (fun w ~(old : Kind.t) (new_ : Kind.t) ->
        match old, new_ with
        | Check_button old, Check_button new_ ->
          let c : W.Check_button.t = cast w in
          Widget_impl.batch w (fun () ->
            if not (Option.equal String.equal old.label new_.label)
            then W.Check_button.set_label c new_.label;
            if not (Bool.equal old.inconsistent new_.inconsistent)
            then W.Check_button.set_inconsistent c new_.inconsistent;
            (* Controlled, on the same rule as [w_toggle_button.ml]'s: against the
               widget's live value, not [old.active]. *)
            if not (Bool.equal (W.Check_button.get_active c) new_.active)
            then W.Check_button.set_active c new_.active)
        | _, k -> Widget_impl.wrong_kind "CheckButton" k)
  ; controlled = true
  ; signals = [ toggled ]
  ; children = Widget_impl.No_children
  }
;;
