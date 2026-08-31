open! Core
open Bonsai_gtk_vtree
open Gtk_import

(* {1 Neither method is the one you would look for}

   [GtkEditableLabel] binds four methods and no signals: [new_], [start_editing],
   [stop_editing] and [get_editing]. There is no [set_text] on it and no [set_editing]
   anywhere.

   {b The text goes through [GtkEditable]}, exactly as an entry's does. [from_gobject] is
   a checked interface cast and [GtkEditableLabel] implements [GtkEditable], so [set_text]
   / [get_text] / [get_position] / [set_position] and the [changed] signal all work
   through it -- which is why this file reuses [w_entry.ml]'s
   {!W_entry.set_text_if_needed} and its {!W_entry.changed} spec outright rather than
   copying either. One consequence worth naming: while the label is being edited,
   [GtkEditable] reads and writes the {i in-progress} text in the internal [GtkText], so
   the controlled prop controls the edit as it happens, and [changed] fires per keystroke
   (measured: one inserted character, one [changed]).

   {b [editing] is read-only in GTK.} Making it a controlled prop therefore means
   [start_editing ()] to enter and [stop_editing ~commit:true] to leave -- two methods
   that are not symmetric with each other and are certainly not a property write. In
   particular [stop_editing false] would {i discard} what the user typed and put the
   previous text back (measured: it emits [changed] three times doing so), so committing
   is the only defensible choice for a declarative library. A model that renders
   [~editing:false] is saying "stop editing", not "throw away the edit"; the edit already
   reached it through [Attr.on_changed], keystroke by keystroke, so a model that wanted to
   reject it has rejected it in [~text] already.

   Observed with [notify::editing] and [get_editing], there being no signal. *)
let editing (w : Widget.t) : W.Editable_label.t = cast w

(* {1 Text a [GtkEditableLabel] will not hold}

   Nothing here, any more, and that is the point. [gtk_editable_set_text] truncates at an
   embedded NUL silently, which is the divergence this widget refuses -- and it refuses it
   through {!W_entry.set_text_if_needed}, the same function it already wrote its text
   through, which now refuses a NUL for all four [GtkEditable] widgets at once. The
   private copy of the refuse-record-report machinery that used to live here (a [Cache], a
   [state], a [take_report], an [already_refused] -- byte-identical to the text view's
   modulo the record) went with it: see {!Refusal}, which is the mechanism once, and
   [w_entry.ml], which is this rule once.

   {b Invalid UTF-8 is still not refused}, and that is a measured difference rather than
   an oversight: a [GtkTextBuffer] empties itself and then declines the insert, so
   [w_text_view.ml] has to refuse it; a [GtkEditable] stores the bytes and reads them back
   unchanged (measured: ["caf\xe9 latte"] round-trips), so there is nothing to refuse and
   the controlled comparison settles on the first frame. *)

(* Whether a [GtkEditableLabel] is now in editing mode.

   There is no [editing-changed] signal -- the class binds none at all -- so this is a
   [notify::editing] through the generic marshaller, which carries no payload, and the
   handler reads [get_editing] back off the widget (spec §6.4). The same shape
   [w_switch.ml] and [w_drop_down.ml] use, needing no new machinery.

   [start_editing] and [stop_editing] both emit it {i synchronously}, so every one the
   library's own writes provoke arrives inside the patch and is dropped by the guard --
   which matters here more than for most signals, because entering and leaving editing
   mode is a write the library makes on the user's behalf on any frame the model's
   [~editing] moves. *)
let editing_changed : Signals.spec =
  Read_back
    { attr = Attr.Name.On_editing_changed
    ; connect = Signals.notify ~prop:"editing"
    ; fire =
        (fun w attr ->
          match (attr :> Attr.Private.t) with
          | On_editing_changed handler ->
            Some (handler (W.Editable_label.get_editing (editing w)))
          | _ -> None)
    }
;;

(* Both props are controlled (spec §6.5), compared against the {i widget} rather than
   against the previous node: the user may have typed or double-clicked since the last
   render, and a model that declined either renders exactly the props it rendered before
   -- so [update] is skipped and this is the only thing left to put the widget back.

   {b Text first, then editing}, which is the reverse of how the two read. Entering
   editing mode selects the whole text, and a text write {i after} [start_editing] would
   collapse that selection and leave the caret where a write puts it rather than where the
   user is about to type. On the way out the order is what makes [stop_editing true]
   commit the {i model's} text: by the time it runs the widget already holds it, so
   committing and discarding would differ only in the case the model has already decided.

   Both decisions come first so the bracket is outside them: a label patched with the text
   and the mode it already has -- which is every idle frame -- pays neither write nor
   freeze/thaw. See [Widget_impl.batch_if]. [W_entry.needs_write] asks the refusal memo
   before it reads the widget, on [w_text_view.ml]'s reasoning (task-9-review.md R1):
   after a refusal the widget holds the old text and the node holds the unstorable one, so
   the comparison answers "differs" on every frame forever, and asking the memo first
   makes the parked frame a pointer comparison.

   {b The text refusal is not written here any more.} It is
   [W_entry.set_text_if_needed]'s, which refuses a NUL for every [GtkEditable] widget and
   leaves the widget untouched when it does, so this file states the {i order} of the two
   props and nothing about the refusal. While a text is parked, [~editing] goes on being
   enforced -- the two decisions are independent, which is deliberate: a label whose text
   the library will not write is still a label the model says is or is not being edited. *)
let reassert w (kind : Kind.t) =
  match kind with
  | Editable_label p ->
    let l = editing w in
    let writes_text = W_entry.needs_write w p.text in
    let writes_editing = not (Bool.equal (W.Editable_label.get_editing l) p.editing) in
    Widget_impl.batch_if (writes_text || writes_editing) w (fun () ->
      if writes_text then ignore (W_entry.set_text_if_needed w p.text : bool);
      if writes_editing
      then
        if p.editing
        then W.Editable_label.start_editing l
        else
          (* [true], and this is the ruling: discarding would throw away an edit the model
             has already seen through [Attr.on_changed] and may already have accepted. *)
          W.Editable_label.stop_editing l true)
  | k -> Widget_impl.wrong_kind "EditableLabel" k
;;

let impl : Widget_impl.t =
  { name = "EditableLabel"
  ; create =
      (fun (kind : Kind.t) ->
        match kind with
        | Editable_label _ ->
          (* [gtk_editable_label_new] takes the text, so the constructor sets it -- but
             the node's text is written through [reassert] below rather than passed here,
             so that the one controlled prop has exactly one implementation including its
             refusal. [""] rather than [p.text] is what makes that true: passing the text
             here and refusing it there would leave an unstorable text half-applied at
             mount and stored at patch. *)
          let l = W.Editable_label.new_ "" in
          let w = (l :> Widget.t) in
          Widget_impl.batch w (fun () ->
            (* Both props at once, through the same code every later frame uses. A fresh
               label is not editing and holds [""], so a node asking for anything else
               pays the writes here that the next patch would have made anyway. *)
            reassert w kind);
          w
        | k -> Widget_impl.wrong_kind "EditableLabel" k)
  ; update =
      (fun _w ~(old : Kind.t) (new_ : Kind.t) ->
        match old, new_ with
        (* Nothing at all: both props are controlled, so both belong to [reassert], which
           the patcher runs immediately after this and on every other patch too.

           The fields are spelled out rather than matched with [_], which is what makes
           the claim true: warning 9 is on, so a prop added to [Kind.editable_label_props]
           is a compile error {i here} and its author has to decide whether it is
           controlled (and so [reassert]'s) or an ordinary property this function must
           write. The first round wrote [Editable_label _, Editable_label _] and claimed
           the same thing, which binds nothing and would have let a new prop be silently
           ignored (task-11-review.md Minor 1). *)
        | ( Editable_label { text = _; editing = _ }
          , Editable_label { text = _; editing = _ } ) -> ()
        | _, k -> Widget_impl.wrong_kind "EditableLabel" k)
  ; reassert =
      Some reassert
      (* [W_entry.changed] rather than one of this file's own. [changed] is a
         [GtkEditable] signal, the spec connects to the [GtkEditable] the widget {i is},
         and the fire reads [W.Editable.get_text] -- none of which mentions an entry.
         Copying it here would be a second place for the connection-names-the-Editable
         rule to be got wrong. *)
  ; signals = [ W_entry.changed; editing_changed ]
  ; children = Widget_impl.No_children
  }
;;
