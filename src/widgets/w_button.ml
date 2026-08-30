open! Core
open Bonsai_gtk_vtree
open Gtk_import

let clicked : Signals.spec =
  { attr = Attr.Name.On_clicked
  ; connect =
      (fun w ~callback -> Signals.connected w (W.Button.on_clicked (cast w) ~callback))
  ; fire =
      (fun _w attr ->
        match (attr :> Attr.Private.t) with
        | On_clicked handler -> Some (handler ())
        | _ -> None)
  }
;;

(* Shared with [w_toggle_button.ml]: a [GtkToggleButton] *is* a [GtkButton], so its label
   / icon-name / has-frame props are set through the same calls.

   [old = None] is the create path, where "differs" is true of everything. *)
let apply_button_props
  (b : W.Button.t)
  ~(old : (string option * string option * bool) option)
  ~label
  ~icon_name
  ~has_frame
  =
  let changed get =
    match old with
    | None -> true
    | Some o -> not (Poly.equal (get o) (get (label, icon_name, has_frame)))
  in
  if changed (fun (l, _, _) -> l)
  then
    (* GTK has no "unset label"; [set_label ""] is the closest thing, and it is what a
       [None] label renders as anyway. *)
    W.Button.set_label b (Option.value label ~default:"");
  (* Set when present, never cleared: [set_icon_name] takes a plain [string], so there is
     no "no icon" value to write. Going back to text is expressed by setting the label,
     which replaces the icon child.

     Which wins when a node carries both, on this update path: the icon, because it is
     written second and [set_icon_name] replaces whatever child [set_label] just built.
     But only while the icon itself changed — a node that keeps its icon and changes only
     its label writes the label and stops, so the button flips to text. That asymmetry is
     the "going back to text" rule above, not an accident, and it matches [create], where
     [new_from_icon_name] is preferred over [new_with_label]. Carrying both is a GTK
     warning either way; [Node.button]'s doc says so. *)
  if changed (fun (_, i, _) -> i) then Option.iter icon_name ~f:(W.Button.set_icon_name b);
  if changed (fun (_, _, f) -> f) then W.Button.set_has_frame b has_frame
;;

(* The child slot of a [GtkButton] (and of a [GtkToggleButton], which shares it) is the
   same slot its label and its icon live in: [set_label] and [set_icon_name] both build a
   child and replace whatever was there.

   The patcher applies props before children, so by the time this runs a [label] or [icon]
   the node now carries has *already* replaced the custom child — there is nothing left to
   unparent, and an unconditional [set_child None] would remove that fresh label instead.
   The same reading covers mount, where [new_with_label] installed the label child before
   the patcher offered its (absent) child. *)
let set_child_slot w child =
  let b : W.Button.t = cast w in
  match child with
  | Some _ -> W.Button.set_child b child
  | None ->
    if Option.is_none (W.Button.get_label b) && Option.is_none (W.Button.get_icon_name b)
    then W.Button.set_child b None
;;

let impl : Widget_impl.t =
  { name = "Button"
  ; create =
      (fun (kind : Kind.t) ->
        match kind with
        | Button p ->
          (* The constructor that already applies the prop is preferred over [new_] plus a
             setter: [new_with_label] builds the label child directly, and
             [new_from_icon_name] the image child. *)
          let b =
            match p.icon_name, p.label with
            | Some icon, _ -> W.Button.new_from_icon_name icon
            | None, Some label -> W.Button.new_with_label label
            | None, None -> W.Button.new_ ()
          in
          if not p.has_frame then W.Button.set_has_frame b false;
          (b :> Widget.t)
        | k -> Widget_impl.wrong_kind "Button" k)
  ; update =
      (fun w ~(old : Kind.t) (new_ : Kind.t) ->
        match old, new_ with
        | Button old, Button new_ ->
          Widget_impl.batch w (fun () ->
            apply_button_props
              (cast w)
              ~old:(Some (old.label, old.icon_name, old.has_frame))
              ~label:new_.label
              ~icon_name:new_.icon_name
              ~has_frame:new_.has_frame)
        | _, k -> Widget_impl.wrong_kind "Button" k)
  ; reassert = None
  ; signals = [ clicked ]
  ; children = Widget_impl.Single { set = set_child_slot }
  }
;;
