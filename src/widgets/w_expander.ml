open! Core
open Bonsai_gtk_vtree
open Gtk_import

(* [GtkExpander::activate] fires before [expanded] settles, so the handler would read the
   old value. [notify::expanded] fires after (spec 6.4). *)
let expanded_changed : Signals.spec =
  { attr = Attr.Name.On_expanded_changed
  ; connect = Signals.notify ~prop:"expanded"
  ; fire =
      (fun w attr ->
        match (attr :> Attr.Private.t) with
        | On_expanded_changed handler -> Some (handler (W.Expander.get_expanded (cast w)))
        | _ -> None)
  }
;;

(* Controlled (spec 6.5), on the toggles' rule: compare against what the widget currently
   shows rather than against the previous node, because the user may have opened or closed
   it since the last render and a model that declines must pin it back. That is a patch on
   which the props did not move, so [update] is skipped and this is all that runs. *)
let needs_expanded (e : W.Expander.t) expanded =
  not (Bool.equal (W.Expander.get_expanded e) expanded)
;;

let set_expanded_if_needed (e : W.Expander.t) expanded =
  if needs_expanded e expanded then W.Expander.set_expanded e expanded
;;

let impl : Widget_impl.t =
  { name = "Expander"
  ; create =
      (fun (kind : Kind.t) ->
        match kind with
        | Expander p ->
          let e = W.Expander.new_ p.label in
          let w = (e :> Widget.t) in
          Widget_impl.batch w (fun () ->
            if p.use_markup then W.Expander.set_use_markup e true;
            set_expanded_if_needed e p.expanded);
          w
        | k -> Widget_impl.wrong_kind "Expander" k)
  ; update =
      (fun w ~(old : Kind.t) (new_ : Kind.t) ->
        match old, new_ with
        | Expander old, Expander new_ ->
          let e : W.Expander.t = cast w in
          Widget_impl.batch w (fun () ->
            if not (Option.equal String.equal old.label new_.label)
            then W.Expander.set_label e new_.label;
            if not (Bool.equal old.use_markup new_.use_markup)
            then W.Expander.set_use_markup e new_.use_markup)
          (* [expanded] is deliberately absent: it is controlled, so it belongs to
             [reassert]. *)
        | _, k -> Widget_impl.wrong_kind "Expander" k)
  ; reassert =
      Some
        (fun w (kind : Kind.t) ->
          match kind with
          | Expander p ->
            let e : W.Expander.t = cast w in
            let writes = needs_expanded e p.expanded in
            Widget_impl.batch_if writes w (fun () ->
              if writes then W.Expander.set_expanded e p.expanded)
          | k -> Widget_impl.wrong_kind "Expander" k)
  ; signals = [ expanded_changed ]
  ; children =
      Widget_impl.Single { set = (fun w child -> W.Expander.set_child (cast w) child) }
  }
;;
