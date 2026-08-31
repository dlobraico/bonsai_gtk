open! Core

(* Which parent-held attrs each container reads off its children. A child carrying one the
   container does not read is a typo -- [Attr.grid_cell] on a box child, [Attr.page_title]
   on a stack's switcher rather than on one of its pages -- and there is no other
   diagnostic for it: nothing applies these to the child, so a wrong one is simply never
   read.

   The empty list is the common case and the wildcard is deliberate: a container that
   reads none of them rejects all of them, which is what makes this a diagnostic rather
   than a list of exceptions. A container that reads a parent-held attr adds an arm here.

   The granularity is the parent's kind, not the parent's slot: [Attr.measure_overlay] on
   an overlay's *main* child is accepted here and is still inert, because only the
   [~overlays] slot reads it. Tightening that means threading the slot name in beside the
   kind, which is worth doing when a slot container reads two different placement attrs on
   two different slots and not before. *)
let read_by : Kind.t -> Attr.Name.t list = function
  | Grid _ -> [ Grid_cell ]
  | Stack _ -> [ Page_title ]
  | Overlay _ -> [ Measure_overlay ]
  | List_box _ -> [ Row_selectable; Row_activatable ]
  | Notebook _ -> [ Tab_label ]
  (* [Flow_box] is deliberately not here, and falls into the wildcard: a [GtkFlowBoxChild]
     has neither [selectable] nor [activatable] -- unlike a [GtkListBoxRow], which has
     both -- so a flow box holds nothing on behalf of an individual child and
     [Attr.row_selectable] on one of its children is a mistake with no other symptom.
     Rejecting it is the whole point of the wildcard. *)
  | _ -> []
;;

(* Which container reads each parent-held attr -- the other half of the table above, and
   the useful half of the message: a misplaced placement attr is nearly always a child
   that ended up in the wrong parent, so naming the container that *does* read it says
   what to do about it.

   Exhaustive with no wildcard, so an attribute added to [Attr.Name] cannot skip the
   decision "is this held by the parent?". [None] is every ordinary widget property and
   every event. *)
let reader : Attr.Name.t -> string option = function
  | Grid_cell -> Some "Grid"
  | Page_title -> Some "Stack"
  | Measure_overlay -> Some "Overlay"
  | Row_selectable | Row_activatable -> Some "ListBox"
  | Tab_label -> Some "Notebook"
  | Margin_start
  | Margin_end
  | Margin_top
  | Margin_bottom
  | Halign
  | Valign
  | Hexpand
  | Vexpand
  | Sensitive
  | Visible
  | Tooltip
  | Width_request
  | Height_request
  | Opacity
  | Focusable
  | Can_focus
  | Widget_name
  | Cursor_name
  | Test_id
  | On_clicked
  | On_toggled
  | On_changed
  | On_activate
  | On_search_changed
  | On_value_changed
  | On_expanded_changed
  | On_revealed
  | On_position_changed
  | On_visible_child_changed
  | On_row_activated
  | On_selected_rows_changed
  | On_child_activated
  | On_selected_children_changed
  | On_page_changed
  | On_selected_changed
  | On_day_selected
  | On_editing_changed
  | On_cursor_moved
  | On_closed
  | Autofocus
  | On_click
  | On_focus_enter
  | On_focus_leave
  | On_contains_focus_changed
  | On_key_pressed
  | On_key_released -> None
;;

(* Derived from [reader] rather than written again, so the two cannot disagree about which
   names are placement attrs. In [Attr.Name] order, which is what makes "the first one" a
   stable answer. *)
let names = List.filter Attr.Name.all ~f:(fun name -> Option.is_some (reader name))

let is_read_by ~(parent : Kind.t option) name =
  match reader name with
  | None -> true
  | Some _ ->
    (match parent with
     | None -> false
     | Some parent -> List.mem (read_by parent) name ~equal:Attr.Name.equal)
;;

let misplaced ~parent attrs =
  List.find names ~f:(fun name ->
    Option.is_some (Attrs.find attrs name) && not (is_read_by ~parent name))
;;

(* The smart constructor's spelling, which is what the caller wrote: [Attr.Name] prints
   [Grid_cell] and the mistake is in a line that says [Attr.grid_cell]. *)
let spelling name = String.lowercase (Attr.Name.to_string name)

let rejection ~path ~(parent : Kind.t option) attrs =
  Option.bind (misplaced ~parent attrs) ~f:(fun name ->
    Option.map (reader name) ~f:(fun container ->
      match parent with
      | Some parent ->
        sprintf
          "%s: Attr.%s is not read by %s (a placement attribute is read by the \
           container, and this one holds children for %s)"
          path
          (spelling name)
          (Kind.name parent)
          container
      | None ->
        sprintf
          "%s: Attr.%s is on the root node, which has no container to read it (a \
           placement attribute is read by the container, and this one holds children for \
           %s)"
          path
          (spelling name)
          container))
;;
