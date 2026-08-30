open! Core
open Bonsai_gtk_vtree
open Gtk_import

(* All three entry kinds implement [GtkEditable], and text, editability, width-chars,
   max-width-chars and alignment all go through it — as does [changed], which is why one
   spec serves every one of them. [from_gobject] is how the interface is reached. *)
let editable (w : Widget.t) : W.Editable.t = W.Editable.from_gobject w

(* Against the *widget's* text, never against the previous node's. The user has typed
   since the last render, so the previous node's text is stale; comparing to it would
   either write on every keystroke (moving the caret to the end of what the user is still
   typing) or skip a write the model genuinely wanted. Comparing to the widget gets both
   right: a model that echoes what was typed is a no-op, and a model that rewrites it
   (uppercasing, clamping, rejecting) still wins. Spec §6.5.

   The write itself moves the caret to the end, so the position is saved and put back. GTK
   clamps it to the new text's length, which is the right answer when the model shortened
   the text.

   Returns whether it wrote. Most callers do not care, but [w_search_entry.ml] does: a
   write there arms a debounce whose emission arrives long after the patch is over, and it
   has to know which writes armed one. *)
let needs_text (e : W.Editable.t) text = not (String.equal (W.Editable.get_text e) text)

let set_text_if_needed (e : W.Editable.t) text =
  if not (needs_text e text)
  then false
  else (
    let position = W.Editable.get_position e in
    W.Editable.set_text e text;
    W.Editable.set_position e position;
    true)
;;

let changed : Signals.spec =
  { attr = Attr.Name.On_changed
  ; connect =
      (fun w ~callback ->
        (* The [GtkEditable] is where [changed] is emitted, so it is also what the
           connection has to name -- even though [from_gobject] is a checked cast to the
           same instance for all three entry kinds. *)
        let e = editable w in
        Signals.connected e (W.Editable.on_changed e ~callback))
  ; fire =
      (fun w attr ->
        match (attr :> Attr.Private.t) with
        | On_changed handler -> Some (handler (W.Editable.get_text (editable w)))
        | _ -> None)
  }
;;

(* [activate] is on each concrete class rather than on [GtkEditable], so the connector is
   the one thing the three kinds cannot share. Each one passes a [connect] that names the
   object it connected to, the same as any other spec. *)
let activate ~connect : Signals.spec =
  { attr = Attr.Name.On_activate
  ; connect
  ; fire =
      (fun _w attr ->
        match (attr :> Attr.Private.t) with
        | On_activate handler -> Some (handler ())
        | _ -> None)
  }
;;

let impl : Widget_impl.t =
  { name = "Entry"
  ; create =
      (fun (kind : Kind.t) ->
        match kind with
        | Entry p ->
          let e = W.Entry.new_ () in
          let w = (e :> Widget.t) in
          Widget_impl.batch w (fun () ->
            (* Only when there is one: writing [None] still builds GTK's placeholder
               label, empty, which a dump then reports as a placeholder that is not there. *)
            Option.iter p.placeholder ~f:(fun t ->
              W.Entry.set_placeholder_text e (Some t));
            if not p.visibility then W.Entry.set_visibility e false;
            if p.activates_default then W.Entry.set_activates_default e true;
            let ed = editable w in
            if p.width_chars <> -1 then W.Editable.set_width_chars ed p.width_chars;
            if p.max_width_chars <> -1
            then W.Editable.set_max_width_chars ed p.max_width_chars;
            if Float.( <> ) p.xalign 0. then W.Editable.set_alignment ed p.xalign;
            if not p.editable then W.Editable.set_editable ed false;
            (* Before the text, so a [~text] longer than [~max_length] is truncated by the
               same rule a typed one would be rather than surviving until the next edit.
               Not controlled: it constrains the widget rather than naming a value the
               model owns. *)
            if p.max_length <> 0 then W.Entry.set_max_length e p.max_length;
            (* Text last, here as in [reassert]: a width or alignment change re-lays-out
               the entry, and doing that after the write would re-run the caret placement
               the write just decided. [set_editable] is not a barrier — it gates the
               user's edits, not the program's. *)
            ignore (set_text_if_needed ed p.text : bool));
          w
        | k -> Widget_impl.wrong_kind "Entry" k)
  ; update =
      (fun w ~(old : Kind.t) (new_ : Kind.t) ->
        match old, new_ with
        | Entry old, Entry new_ ->
          let e : W.Entry.t = cast w in
          let ed = editable w in
          Widget_impl.batch w (fun () ->
            if not (Option.equal String.equal old.placeholder new_.placeholder)
            then W.Entry.set_placeholder_text e new_.placeholder;
            if not (Bool.equal old.visibility new_.visibility)
            then W.Entry.set_visibility e new_.visibility;
            if not (Bool.equal old.activates_default new_.activates_default)
            then W.Entry.set_activates_default e new_.activates_default;
            if not (Bool.equal old.editable new_.editable)
            then W.Editable.set_editable ed new_.editable;
            if old.width_chars <> new_.width_chars
            then W.Editable.set_width_chars ed new_.width_chars;
            if old.max_width_chars <> new_.max_width_chars
            then W.Editable.set_max_width_chars ed new_.max_width_chars;
            if Float.( <> ) old.xalign new_.xalign
            then W.Editable.set_alignment ed new_.xalign;
            if old.max_length <> new_.max_length
            then W.Entry.set_max_length e new_.max_length)
          (* [text] is deliberately absent, so [create] and [update] agree on writing it
             last: it is controlled, which makes it [reassert]'s, and the patcher runs
             that immediately after this and on every other patch too. *)
        | _, k -> Widget_impl.wrong_kind "Entry" k)
  ; reassert =
      Some
        (fun w (kind : Kind.t) ->
          match kind with
          | Entry p ->
            (* The comparison comes first because the bracket has to be outside the
               decision: an entry patched with the text it already shows -- which is every
               patch of an entry the model echoes -- must pay neither the write nor the
               freeze/thaw. See [Widget_impl.batch_if]. *)
            let e = editable w in
            let writes = needs_text e p.text in
            Widget_impl.batch_if writes w (fun () ->
              if writes then ignore (set_text_if_needed e p.text : bool))
          | k -> Widget_impl.wrong_kind "Entry" k)
  ; signals =
      [ changed
      ; activate ~connect:(fun w ~callback ->
          Signals.connected w (W.Entry.on_activate (cast w) ~callback))
      ]
  ; children = Widget_impl.No_children
  }
;;
