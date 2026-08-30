open! Core
open Bonsai_gtk_vtree
open Gtk_import

let toggled : Signals.spec =
  { attr = Attr.Name.On_toggled
  ; connect =
      (fun w ~callback ->
        Signals.connected w (W.Check_button.on_toggled (cast w) ~callback))
  ; fire =
      (fun w attr ->
        match (attr :> Attr.Private.t) with
        | On_toggled handler -> Some (handler (W.Check_button.get_active (cast w)))
        | _ -> None)
  }
;;

(* Controlled, on the same rule (and for the same reason) as [w_toggle_button.ml]'s. *)
let set_active_if_needed (c : W.Check_button.t) active =
  if not (Bool.equal (W.Check_button.get_active c) active)
  then W.Check_button.set_active c active
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
              set_active_if_needed c p.active;
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
            then W.Check_button.set_inconsistent c new_.inconsistent)
          (* [active] is controlled: see [reassert]. *)
        | _, k -> Widget_impl.wrong_kind "CheckButton" k)
  ; reassert =
      Some
        (fun w (kind : Kind.t) ->
          match kind with
          | Check_button p ->
            Widget_impl.batch w (fun () -> set_active_if_needed (cast w) p.active)
          | k -> Widget_impl.wrong_kind "CheckButton" k)
  ; signals = [ toggled ]
  ; children = Widget_impl.No_children
  }
;;
