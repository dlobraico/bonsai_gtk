open! Core
open Bonsai_gtk_vtree
open Gtk_import

(* What the library last wrote into each live search entry, and has not yet seen come back
   as a [search-changed].

   The reentrancy guard (spec §4.4) covers a programmatic write because GTK emits the
   resulting signal synchronously, from inside the setter, while the patcher is still on
   the stack. [search-changed] is the one signal in M1 that does not work that way: GTK
   emits it from a [g_timeout] armed by [GtkEditable::changed], [search_delay] ms later
   (150 by default), long after [Driver.frame] has returned and cleared the guard. So a
   model that rewrites what the user typed — uppercasing it, trimming it, clearing the box
   from elsewhere in the UI — had its own text handed back to it as a search the user
   never performed: one spurious query per programmatic write, and an oscillation at the
   debounce interval for any normalisation that is not a fixed point.

   A synchronous flag cannot cover an asynchronous emission, so the text is recorded here
   instead and an emission that still carries it is dropped. Weakly keyed on the widget,
   so an entry that is destroyed takes its record with it rather than pinning the GObject
   alive. *)
module Echo = Stdlib.Ephemeron.K1.Make (struct
    type t = Widget.t

    let equal = Gobject.same
    let hash = Stdlib.Hashtbl.hash
  end)

let echoes : string Echo.t = Echo.create 8

(* Recorded only when the write actually happened: a write that changed nothing provokes
   no signal to decline. *)
let set_text w text =
  if W_entry.set_text_if_needed (W_entry.editable w) text then Echo.replace echoes w text
;;

(* Consumed whether or not it matched, so that a record outlives at most one emission.

   For a write to a non-empty string that is exact: [gtk_search_entry_changed] arms one
   timeout and a second write before it elapses resets the same source, so the next
   emission is the only one that record could ever have explained. A write that *empties*
   the box is the exception — GTK emits [search-changed] synchronously there and cancels
   any pending timeout — and since that emission happens inside the patch,
   [Signals.dispatch] drops it on [in_patch] before [fire] is reached and the record
   survives. It is a [""] record, matched against a later [""] emission at a moment when
   the model already holds [""], so what it can cost is a duplicate rather than a search;
   the first non-empty emission flushes it. Worth knowing before anything makes a patch
   iterate the main loop. See docs/m1-backlog.md. *)
let was_our_own_write w text =
  match Echo.find_opt echoes w with
  | None -> false
  | Some recorded ->
    Echo.remove echoes w;
    String.equal recorded text
;;

(* GTK's debounced signal, emitted [search_delay] ms after typing stops. It is the search
   entry's own; [changed] (immediate) reaches it through [GtkEditable] like the other two
   entries, and both are connected — see [Node.search_entry]'s doc for which to use. *)
let search_changed : Signals.spec =
  { attr = Attr.Name.On_search_changed
  ; connect =
      (fun w ~callback ->
        Signals.connected w (W.Search_entry.on_search_changed (cast w) ~callback))
  ; fire =
      (fun w (attr : Attr.t) ->
        match attr with
        | On_search_changed handler ->
          let text = W.Editable.get_text (W_entry.editable w) in
          (* The one case this cannot tell apart is a user who edits the box back to
             exactly what the library last wrote, before the debounce elapses. That search
             is dropped — and it would have reported the text the model already holds. *)
          if was_our_own_write w text then None else Some (handler text)
        | _ -> None)
  }
;;

let impl : Widget_impl.t =
  { name = "SearchEntry"
  ; create =
      (fun (kind : Kind.t) ->
        match kind with
        | Search_entry p ->
          let e = W.Search_entry.new_ () in
          let w = (e :> Widget.t) in
          Widget_impl.batch w (fun () ->
            (* As in [w_entry.ml]: writing [None] builds an empty placeholder label. *)
            Option.iter p.placeholder ~f:(fun t ->
              W.Search_entry.set_placeholder_text e (Some t));
            Option.iter p.search_delay ~f:(W.Search_entry.set_search_delay e);
            (* Recorded like any other write: the slots are filled in immediately after
               [create], so the debounce this arms outlives the mount and would otherwise
               reach the application as a search performed before the widget was ever on
               screen. *)
            set_text w p.text);
          w
        | k -> Widget_impl.wrong_kind "SearchEntry" k)
  ; update =
      (fun w ~(old : Kind.t) (new_ : Kind.t) ->
        match old, new_ with
        | Search_entry old, Search_entry new_ ->
          let e : W.Search_entry.t = cast w in
          Widget_impl.batch w (fun () ->
            if not (Option.equal String.equal old.placeholder new_.placeholder)
            then W.Search_entry.set_placeholder_text e new_.placeholder;
            (* [None] means "leave GTK's own 150 ms alone", so going from [Some] back to
               [None] writes nothing rather than guessing a value to restore. *)
            if not (Option.equal Int.equal old.search_delay new_.search_delay)
            then Option.iter new_.search_delay ~f:(W.Search_entry.set_search_delay e))
          (* [text] is controlled: see [reassert]. *)
        | _, k -> Widget_impl.wrong_kind "SearchEntry" k)
  ; reassert =
      Some
        (fun w (kind : Kind.t) ->
          match kind with
          | Search_entry p -> Widget_impl.batch w (fun () -> set_text w p.text)
          | k -> Widget_impl.wrong_kind "SearchEntry" k)
  ; signals =
      [ W_entry.changed
      ; search_changed
      ; W_entry.activate ~connect:(fun w ~callback ->
          Signals.connected w (W.Search_entry.on_activate (cast w) ~callback))
      ]
  ; children = Widget_impl.No_children
  }
;;
