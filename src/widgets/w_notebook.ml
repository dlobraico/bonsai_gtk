open! Core
open Bonsai_gtk_vtree
open Gtk_import

(* {b The third keyed container, and the one that settles the functor question.}

   [w_flow_box.ml] opens with an argument for why it is not a functor over
   [w_list_box.ml], and ends it by saying that this file is what would decide it: if a
   shared abstraction still fitted after a container keyed on the page's own content
   widget, it would be a real one. It does not fit, and the reason is worth recording
   rather than re-deriving.

   The other two containers share a shape: wrap the child, key the wrapper's child, turn
   the patcher's [~after] widget into an index through the wrapper's own [get_index],
   remove-and-re-insert to move. A notebook shares {i none} of those four steps. It wraps
   nothing, so there is no wrapper to key on and no [get_parent] climb back to one; its
   pages are addressed by [page_num] rather than by a wrapper's [get_index]; and it has a
   real [reorder_child], so [move] is a single call rather than a removal and a re-insert.
   What is actually common to all three is "a [Child_keys] table, a controlled selection
   compared against the widget from the fixup pass" -- which is two ideas, and both of
   them are already shared, as [Child_keys] and as [Patcher.enqueue_fixups]' arms. The
   remaining per-container code is the part that differs. So: no functor, and the question
   is closed rather than deferred again.

   {b Binding safety.} Every getter this file calls was read in the generated stub rather
   than in the GIR, on Task 6's rule (a transfer-container or transfer-none getter whose
   stub does not [g_object_ref_sink] hands out an unbalanced unref per call, and this
   file's getters run on every frame). The only one that returns an object is
   [gtk_notebook_get_nth_page], and it sinks ([ml_notebook_gen.c:303-310] -- and the
   [_opam] copy the build actually links is byte-identical to the [.ocgtk-src] one, both
   checked). [page_num], [get_n_pages], [get_current_page], [get_tab_label_text] and the
   four property getters return an [int], a [const char*], a [gboolean] or an enum and
   have nothing to sink; [gtk_notebook_get_tab_label] would ([:245-252]) and is not
   called. The [page] argument the [switch-page] marshaller hands the callback comes
   through [Gobject.Value.get_object_exn], whose stub sinks ([ml_gobject.c:362-391], whose
   comment describes the very bug this rule exists for). [gtk_notebook_get_pages] is the
   one that does {i not} sink -- correctly, since it is transfer-full -- and nothing here
   calls it. *)

let tab_position : Tab_position.t -> Gtk_enums.positiontype = function
  | Top -> `TOP
  | Bottom -> `BOTTOM
  | Left -> `LEFT
  | Right -> `RIGHT
;;

(* This module's own table, per [Child_keys]' "one per container module" rule.

   Keyed on the page's {i content widget}, which here is not a choice between a wrapper
   and a child but the only thing there is: a notebook interposes no widget of its own on
   the page side (the tab label it builds lives in the header), so the widget GTK hands
   [switch-page] and the widget the patcher stores in [live.widget] are the same object.
   That is exactly the lifetime [child_keys.mli] requires -- the entry lives as long as
   the OCaml value the patcher retains -- and it is why this container is the one place
   where the invariant is satisfied by construction rather than by care. *)
let page_keys = Child_keys.create ()

(* The table's live-binding count, for tests: [live_lists.ml]'s Child_keys cases pin that
   a removal and a teardown both drop their entries (see [Child_keys.length]). *)
let tracked_keys () = Child_keys.length page_keys

let page_key (node : Node.t) =
  match node.key with
  | Some key -> key
  | None ->
    (* Unreachable through [Node.notebook], which rejects an unkeyed page at the
       constructor; kept for the paths that constructor did not build, on
       [w_list_box.ml]'s reasoning. *)
    invalid_arg
      "notebook page has no ~key (a page's key is what ~current_page names and every \
       handler receives)"
;;

(* The tab label the {i notebook} draws for this page, read off the page node's attrs on
   the rule [Attr.page_title] and [Attr.grid_cell] follow.

   An [option] rather than [Attr.row_selectable]'s "GTK's default if absent": the absence
   of a tab label is a real GTK state ([gtk_notebook_set_tab_label] with NULL) rather than
   a value, so [None] is what [updated] writes back when the attr goes away.

   What that state {i draws} is not nothing, which this comment used to claim. With
   [show_tabs] on, NULL makes GTK build a [GtkLabel] reading "Page N" from the page's
   {i position}, and renumber every such label from its current position on each insert,
   remove and reorder (gtknotebook.c:6627-6641 and :4410-4448; measured in
   [test/live/live_lists.ml]). So an unlabelled page is captioned by where it sits.
   [Attr.tab_label]'s doc says so and tells applications to label every page of a
   tab-showing notebook; this impl still writes NULL, because [Some ""] would replace a
   positional caption with a blank clickable tab -- the trade [w_stack.ml] already refused
   for a switcher button. *)
let tab_label (node : Node.t) =
  match (Attrs.find node.attrs Tab_label :> Attr.Private.t option) with
  | Some (Tab_label text) -> Some text
  | Some _ | None -> None
;;

(* Every page, in GTK's own order, walked with [get_nth_page] until it answers [None].

   This is the notebook's answer rather than a list this impl keeps, and it has to be:
   [Widget.get_first_child] on a [GtkNotebook] gives its two internal children -- a
   [GtkBox] of tabs and a [GtkStack] of pages -- and the stack's child order does not
   track the page order at all (measured: after a reorder, the tabs move and the stack's
   children do not). So the pages are reachable only through this call, and a dump of the
   widget tree shows the tab order rather than the page order, which is why
   [test/live/live_lists.ml] prints the page order separately. *)
let pages (nb : W.Notebook.t) =
  let rec go i acc =
    match W.Notebook.get_nth_page nb i with
    | None -> List.rev acc
    | Some p -> go (i + 1) (p :: acc)
  in
  go 0 []
;;

let key_of_page (page : Widget.t) = Child_keys.find page_keys page

let key_of_page_exn (page : Widget.t) =
  Child_keys.find_exn page_keys page ~what:"notebook page"
;;

(* The page a key names, and where it currently sits. Derived from the notebook on every
   call rather than cached beside it, on [W_flow_box.child_by_key]'s reasoning: a map that
   outlived a removal would answer with a page the notebook no longer holds, and
   [set_current_page] takes an {i index} -- so a stale answer would not merely be inert,
   it would show the wrong page. *)
let page_index_by_key (nb : W.Notebook.t) key =
  List.findi (pages nb) ~f:(fun _ page ->
    Option.exists (key_of_page page) ~f:(String.equal key))
  |> Option.map ~f:fst
;;

(* Only for the message below, on [W_stack.page_names]' terms: listing the keys a notebook
   does have is what turns "no such page" from an accusation into a fix. *)
let page_key_list (nb : W.Notebook.t) =
  List.map (pages nb) ~f:(fun p -> Option.value (key_of_page p) ~default:"<unkeyed>")
;;

(* Every entry dropped at once, for the notebook that is going away whole: its pages never
   pass through [list_ops.remove], because the patcher tears a subtree down by walking it
   rather than by removing each child from its parent. [W_list_box.forget_rows]' argument,
   and the same placement requirement in [Patcher.destroy] -- the arm goes {i above} the
   or-pattern chain, not after it. *)
let forget_pages (w : Widget.t) =
  List.iter (pages (cast w)) ~f:(Child_keys.remove page_keys)
;;

(* The page GTK is showing, as the key the node carried.

   {b Not an independent source of truth}: this is [get_current_page] with two lookups on
   top of it, so it answers whatever GTK answers and cannot disagree with it. It exists so
   that handlers and tests can speak in keys, not so that the key becomes the thing being
   tracked -- [Child_keys] is never authoritative over the notebook, and a reader who
   believes otherwise is one step from the stale-map bug [page_index_by_key]'s own comment
   warns against. *)
let current_key (nb : W.Notebook.t) =
  match W.Notebook.get_current_page nb with
  | -1 -> None
  | i -> Option.bind (W.Notebook.get_nth_page nb i) ~f:key_of_page
;;

(* Controlled, on spec §6.5's rule and compared against the widget rather than against the
   previous node -- so the frame on which the model {i declines} a tab click puts the
   notebook back.

   From the fixup pass rather than [reassert] because the pages do not exist when
   [reassert] runs; the frame that both adds a page and switches to it is the case, and it
   is the same reason [W_stack.select] is a fixup.

   {b A key naming no page raises}, exactly as [W_stack.select] does and deliberately
   unlike a list box's or a flow box's [~selected]: a container that shows exactly one of
   its children raises when told to show one that does not exist; a container with a
   plural selection ignores the keys it cannot find. A notebook shows one page, so a key
   that never resolves is a model rendering a view it does not have -- most often a page
   removed without its selection being moved -- and every frame after it renders the same
   inconsistency while the notebook shows whatever neighbour GTK picked. That divergence
   is the one spec §6.5 exists to prevent, and the fixup pass is the earliest point at
   which it is knowable: by then the whole tree exists, so a key absent here is absent
   from the rendered tree rather than merely not added yet.

   The one exception is a notebook with no pages at all, which is left inert:
   [~current_page] is a required argument, so a model rendering an empty page list has no
   key it could pass that would be right, and the frame that adds the first page runs this
   again.

   The comparison is against the {i widget} and not against the previous node, which is
   the whole of spec §6.5 and is what the fixup queue is for: a model that declines a tab
   click renders the props it rendered last frame, so [update] is skipped and nothing but
   a read-back of the live widget can put the notebook where the model says it is.

   Indices rather than keys is a spelling and not a decision -- {!current_key} is
   [get_current_page] with two lookups on top, and keys are unique among a notebook's
   pages, so [current_key nb = Some current_page] holds exactly when
   [get_current_page nb = index]. Comparing keys instead would be the same predicate one
   walk slower. (An earlier version of this comment claimed a key comparison would report
   a write as having landed when it had not; it would not, and substituting one for the
   other leaves the live golden byte-identical.)

   What the read-back really buys is the case that {i cannot} be made to converge: GTK
   refuses to switch to a page whose child is hidden -- it emits [switch-page] and then
   leaves [get_current_page] where it was (measured) -- so the comparison stays unequal
   and the write is repeated on every frame. Nothing is clamped, which is the same bargain
   [W_list_box.apply_selection] strikes with a mode that cannot hold the selection it is
   given. Both are documented on their constructors.

   That divergence is {i reported once} rather than left silent or said per frame:
   [w_stack.ml]'s [Select_memo] shape exactly, keyed on the offending page key, cleared by
   the write that finally lands (the fixup still tries on every frame -- the page may
   become visible). The patcher polls [take_report] right after the fixup. *)
module Select_memo = Refusal.Make (String) (Refusal.No_extra)

let take_report = Select_memo.take_report

let select (w : Widget.t) ~current_page =
  let nb : W.Notebook.t = cast w in
  match page_index_by_key nb current_page with
  | Some index ->
    let st = Select_memo.state w in
    if W.Notebook.get_current_page nb = index
    then Select_memo.landed st
    else (
      W.Notebook.set_current_page nb index;
      if W.Notebook.get_current_page nb = index
      then Select_memo.landed st
      else if not (Select_memo.already_refused st current_page)
      then
        Select_memo.refuse
          st
          current_page
          ~reason:
            (sprintf
               "~current_page names the hidden page %S; GTK will not switch to it"
               current_page))
  | None ->
    (match page_key_list nb with
     | [] -> ()
     | keys ->
       invalid_argf
         "Node.notebook ~current_page:%S names no page (a page's key is its ~key; this \
          notebook has %s)"
         current_page
         (String.concat ~sep:", " keys)
         ())
;;

(* [switch-page] carries the page's {i content widget} and a page number, so this is a
   [Payload] spec: the widget is the one thing an application could be told about that has
   a name it recognises, once [Child_keys] has turned it back into the node's key.

   The payload type is [Widget.t] with no downcast anywhere, which is the one respect in
   which this is simpler than its two siblings: GTK hands over the application's own child
   rather than a [GtkListBoxRow] or a [GtkFlowBoxChild] this library made, so there is no
   wrapper type to name and no [cast] to get wrong.

   [page_num] is deliberately ignored. It is GTK's answer to "which page", and it is the
   answer that goes stale: it moves whenever a page is added, removed or reordered, so an
   application acting on it has to keep an array beside the notebook -- which is the whole
   thing [Child_keys] exists to replace.

   The lookup is in [fire] rather than in [connect], where the payload is otherwise
   assembled: [Child_keys.find_exn] raises, [connect]'s closure is called straight from C,
   and [Signals.dispatch_payload] is the only thing standing between a raise and GTK's
   stack frame. It is also not reached at all when the slot is empty, which is what makes
   a teardown safe -- [Patcher.destroy] empties the slots before anything is unparented,
   and GTK emits [switch-page] as pages go away. *)
let page_changed : Signals.spec =
  Payload
    { attr = Attr.Name.On_page_changed
    ; connect =
        (fun w ~callback ->
          Signals.connected
            w
            (W.Notebook.on_switch_page (cast w) ~callback:(fun ~page ~page_num:_ ->
               callback page)))
    ; fire =
        (fun _w attr page ->
          match (attr :> Attr.Private.t) with
          | On_page_changed handler -> (), Some (handler (key_of_page_exn page))
          | _ -> (), None)
    ; declined = ()
    }
;;

let write_props (nb : W.Notebook.t) (p : Kind.notebook_props) =
  W.Notebook.set_scrollable nb p.scrollable;
  W.Notebook.set_show_tabs nb p.show_tabs;
  W.Notebook.set_show_border nb p.show_border;
  W.Notebook.set_tab_pos nb (tab_position p.tab_pos)
;;

(* The index of a page this impl is about to act on.

   Unreachable in a tree [Node.notebook] built, on [page_key]'s pattern: every widget this
   is handed comes from [Patcher.patch_list]'s own [!cur], which mirrors GTK's page list
   after every op, so [-1] cannot happen. It is kept because [gtk_notebook_page_num]
   answers [-1] rather than raising and the three methods that take an index disagree
   about what to do with a bad one -- [remove_page] silently does nothing, [reorder_child]
   logs a [Gtk-CRITICAL] and carries on -- so the failure mode without this is a patch
   that quietly did not happen. It is this file's counterpart to [W_list_box.row_of]'s
   type-name check: the one assumption every op rests on, stated once.

   No noun in the message: the patcher's [child_op] prefixes the node path, and [what]
   already says which page. *)
let page_num_exn (nb : W.Notebook.t) ~what (page : Widget.t) =
  match W.Notebook.page_num nb page with
  | -1 -> invalid_argf "%s is not a page of this notebook" what ()
  | i -> i
;;

let impl : Widget_impl.t =
  { name = "Notebook"
  ; create =
      (fun (kind : Kind.t) ->
        match kind with
        | Notebook p ->
          let nb = W.Notebook.new_ () in
          let w = (nb :> Widget.t) in
          Widget_impl.batch w (fun () -> write_props nb p);
          (* [current_page] is deliberately not applied here: the pages do not exist yet
             (the patcher attaches children after [create]), and [set_current_page] on a
             notebook with no pages is a silent no-op rather than an error. [select] does
             it from the fixup pass. *)
          w
        | k -> Widget_impl.wrong_kind "Notebook" k)
  ; update =
      (fun w ~(old : Kind.t) (new_ : Kind.t) ->
        match old, new_ with
        | Notebook old, Notebook new_ ->
          let nb : W.Notebook.t = cast w in
          Widget_impl.batch w (fun () ->
            if not (Bool.equal old.scrollable new_.scrollable)
            then W.Notebook.set_scrollable nb new_.scrollable;
            if not (Bool.equal old.show_tabs new_.show_tabs)
            then W.Notebook.set_show_tabs nb new_.show_tabs;
            if not (Bool.equal old.show_border new_.show_border)
            then W.Notebook.set_show_border nb new_.show_border;
            if not (Tab_position.equal old.tab_pos new_.tab_pos)
            then W.Notebook.set_tab_pos nb (tab_position new_.tab_pos))
        | _, k -> Widget_impl.wrong_kind "Notebook" k)
      (* [current_page] is controlled, but not from here, for [w_stack.ml]'s reason:
         [reassert] runs before the children are patched, so on the frame that both adds a
         page and switches to it there would be nothing to switch to. The patcher enqueues
         [select] instead. *)
  ; reassert = None
  ; signals = [ page_changed ]
  ; children =
      (* A plain list. Unlike a list box there is no placeholder slot, and unlike either
         of the other two keyed containers there is no wrapper: the nodes in this list are
         the notebook's pages. *)
      Widget_impl.List
        { insert =
            (fun parent ~after ~node child ->
              let nb : W.Notebook.t = cast parent in
              (* [GtkNotebook] has insert-at-index, so the patcher's [after] widget is
                 turned back into an index with GTK's own [page_num] -- which is the right
                 answer here precisely because a notebook interposes nothing: its pages
                 are exactly the children this list holds, in this order. [None] is index
                 0.

                 [after] is always a page already inserted: the patcher runs its ops in
                 order and computes [after] from its own bookkeeping, so the predecessor
                 is in the notebook by the time this runs. *)
              let index =
                match after with
                | None -> 0
                | Some w -> page_num_exn nb ~what:"the preceding page" w + 1
              in
              (* Recorded {i before} the GTK call, and here that ordering is load-bearing
                 rather than belt-and-braces (which is the opposite of the list box's
                 [remove], and worth the contrast): GTK emits [switch-page] synchronously
                 from the insert of the {i first} page, and the page it names is the one
                 being inserted. Inside a patch the reentrancy guard swallows it; outside
                 one -- a test driving [Patcher.mount] by hand -- the handler really runs,
                 and [key_of_page_exn] would raise if the entry were not yet there. *)
              Child_keys.set page_keys child (page_key node);
              (* The tab label is a widget GTK owns from here on. Built rather than passed
                 through: [Attr.tab_label] is a [string] (see its doc), and [None] leaves
                 GTK to caption the page positionally (see [tab_label] above). The [int]
                 result is the index the page landed at, which is the [index] just
                 computed. *)
              let tab =
                Option.map (tab_label node) ~f:(fun text ->
                  (W.Label.new_ (Some text) :> Widget.t))
              in
              ignore (W.Notebook.insert_page nb child tab index : int))
        ; move =
            Some
              (fun parent ~child ~after ->
                (* {b The one real reorder among the keyed containers.} (A [Node.box]
                   reorders for real too, with [W.Box.reorder_child_after] -- see
                   [w_box.ml], which counts the two.) [GtkNotebook] has [reorder_child],
                   so this is a single call rather than the remove-and-re-insert its two
                   siblings do -- which means the page keeps not only its GObject but its
                   tab label, its scroll position and its place in the focus chain, none
                   of which survives an unparenting.

                   [reorder_child]'s [position] is the page's index
                   {i in the resulting list}, which is not what the docstring's "so that
                   it appears in position @position" settles on its own -- GTK deletes the
                   page from its list and then [g_list_insert]s it at [position], and
                   clamps a [position] past the end to last. Established by experiment
                   rather than read: A,B,C,D with D moved to 1 gives A,D,B,C; the head
                   moved to 3 gives B,A,C,D; index 2 moved to 0 gives C,B,A,D. The live
                   test's four moves are the regression.

                   The patcher hands a [~after] widget rather than an index, and [after]
                   was computed over the sibling list with this child
                   {i already taken out of it} while [page_num] answers about the list
                   that still holds it. The two differ by one exactly when the child
                   currently sits before [after], so that is what is asked.

                   {b The [from < a] arm is unreachable through the reconciler today}, and
                   is a hedge rather than a case anyone has seen: [Reconcile.diff] scans
                   left to right and always finds its match at an index at or after the
                   one it is filling, so every [Move] it emits has [from > to_], which
                   forces [a = to_ - 1 < from]. Deleting the conditional and writing
                   [a + 1] unconditionally leaves the whole live golden unchanged
                   (checked). It is kept because the alternative is for this file to
                   depend silently on a property of a module in another library; the two
                   sibling containers make the same refusal by reading the predecessor's
                   index {i after} their removal, which a notebook cannot do because
                   [reorder_child] removes internally. An [assert] was considered and
                   rejected -- it would turn a reconciler change into a crash where this
                   arithmetic already handles it, and it would make the notebook the one
                   container that encodes the invariant while the other two quietly
                   survive it. [test/live/live_lists.ml] calls this very function with a
                   forward [~after], so the arm is exercised against GTK even though no
                   frame reaches it. *)
                let nb : W.Notebook.t = cast parent in
                let from = page_num_exn nb ~what:"the page being moved" child in
                let position =
                  match after with
                  | None -> 0
                  | Some w ->
                    let a = page_num_exn nb ~what:"the preceding page" w in
                    if from < a then a else a + 1
                in
                W.Notebook.reorder_child nb child position)
        ; remove =
            (fun parent child ->
              let nb : W.Notebook.t = cast parent in
              (* Read before the entry is dropped and before the removal, because
                 [remove_page] takes an index and [page_num] is how one is got. *)
              let index = page_num_exn nb ~what:"the page being removed" child in
              (* Dropped here rather than left to the GC: the table is shared by every
                 notebook in the process, so a model that closes tabs would otherwise
                 accumulate entries until the page widgets themselves were collected.

                 Before the GTK call, and -- as in [w_list_box.ml] and [w_flow_box.ml],
                 where this ordering was mutation-tested -- belt-and-braces rather than
                 load-bearing: GTK does emit [switch-page] synchronously from the removal
                 of the current page, but the page it names is the {i neighbour} it
                 switched to, which is still in the notebook and so still in the table.
                 The order is kept because it is free and keeps the table matching the
                 tree at every point a handler could look. *)
              Child_keys.remove page_keys child;
              W.Notebook.remove_page nb index)
        ; updated =
            (fun parent ~old ~node child ->
              (* The key cannot change -- a changed key is a different page to the
                 reconciler -- so the tab label is the only thing to re-read. Writing
                 [None] as [set_tab_label ... None] rather than as an empty string is what
                 hands the page back to GTK's positional "Page N" default (see [tab_label]
                 above) instead of drawing a blank clickable tab. *)
              if not (Option.equal String.equal (tab_label old) (tab_label node))
              then (
                let nb : W.Notebook.t = cast parent in
                match tab_label node with
                | Some text -> W.Notebook.set_tab_label_text nb child text
                | None -> W.Notebook.set_tab_label nb child None))
        }
  }
;;
