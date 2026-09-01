open! Core

module Name = struct
  module T = struct
    type t =
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
      | Autofocus
      | Actions
      | Widget_name
      | Cursor_name
      | Test_id
      | Measure_overlay
      | Grid_cell
      | Page_title
      | Row_selectable
      | Row_activatable
      | Tab_label
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
      (* The controller attrs, after every signal name so that no existing [Attrs.diff]
         output reorders. *)
      | On_click
      | On_focus_enter
      | On_focus_leave
      | On_contains_focus_changed
      | On_key_pressed
      | On_key_released
      | Shortcut
    [@@deriving sexp_of, compare, equal, enumerate]

    (* Exhaustive on purpose, never [_ -> false]: every widget task adds [On_*] names, and
       the compiler is what forces each new one to be classified here. A name that says
       [true] is one [Signals.require_specs] insists some widget impl claims. *)
    let is_event = function
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
      (* The controller attrs are events too -- they carry a handler and a widget that
         cannot deliver one is a mistake worth a diagnostic. What they are not is any
         impl's *signal*: no [Widget_impl.signals] declares one and no slot for one lives
         on the widget, so the two mount-time checks treat them apart --
         [Events.is_supported] short-circuits (they are legal on every kind) and
         [Signals.require_slots] skips them (their slots belong to [Controllers], which
         creates them from the attr itself). [Events.is_controller_attr] is that
         distinction, and it is the one place it is written down. *)
      | On_click
      | On_focus_enter
      | On_focus_leave
      | On_contains_focus_changed
      | On_key_pressed
      | On_key_released
      (* Carries no handler -- the action it names does -- but it is behaviour a widget
         delivers and a controller family owns, so the event diagnostics apply exactly as
         they do to [On_click]. *)
      | Shortcut -> true
      (* Carries handlers, so a mistake around it deserves the event diagnostics -- but
         like the controller attrs it is no impl's signal: [Events.is_actions_attr] is the
         carve-out that makes it legal on every kind, and [src/actions.ml] is what builds
         its slots. *)
      | Actions -> true
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
      | Autofocus
      | Widget_name
      | Cursor_name
      | Test_id
      | Measure_overlay
      | Grid_cell
      | Page_title
      | Row_selectable
      | Row_activatable
      | Tab_label -> false
    ;;
  end

  include T
  include Comparable.Make_plain (T)

  let to_string t = Sexp.to_string (sexp_of_t t)
end

(* The variant lives in [Private] and reaches the rest of this file through [include],
   which is what lets [attr.mli] publish [type t = Private.t] -- the constructors
   documented in one place that carries no stability promise, and the type itself
   documented without them.

   [include] rather than a second spelling of the constructor list: [Attr.t] and
   [Attr.Private.t] are the same type, so nothing converts and nothing allocates, and
   there is no duplicated list to drift.

   [private] lives in the mli only ([type t = private Private.t]); in here [t] is the
   plain variant, so this file constructs and matches freely. Outside, neither is possible
   without spelling the coercion [(a :> Attr.Private.t)] -- which is what makes the seal
   compiler-enforced rather than merely documented. The coercion runs one way, which is
   why [flatten] below exists. *)
(* One shortcut: what fires ([trigger]), where it runs ([phase]), and the {i name} of what
   it does ([action], "scope.name" -- resolved exactly as a menu item's is). No handler
   anywhere, so the whole record is structural data and a shortcuts diff fires only on
   real changes. *)
type shortcut =
  { trigger : Trigger.t
  ; phase : Phase.t
  ; action : string
  }
[@@deriving sexp_of, equal, compare]

module Private = struct
  type t =
    | Css_class of string
    | Margin_start of int
    | Margin_end of int
    | Margin_top of int
    | Margin_bottom of int
    | Halign of Align.t
    | Valign of Align.t
    | Hexpand of bool
    | Vexpand of bool
    | Sensitive of bool
    | Visible of bool
    | Tooltip of string
    | Width_request of int
    | Height_request of int
    | Opacity of float
    | Focusable of bool
    | Can_focus of bool
    (* Fire-once, not a controlled prop, and applied by the {i patcher} rather than
       [Attr_apply]: the grab needs the whole tree to exist, so it runs from the fixup
       queue -- on the frame this widget mounts carrying [true], or the frame the attr
       flips false-to-true -- and never afterwards. See [Attr.autofocus]'s doc. *)
    | Autofocus of bool
    (* One [GSimpleActionGroup] under [scope], inserted on whatever widget carries the
       attr -- the [Controllers] shape over GTK's action system rather than an event
       controller, owned by [src/actions.ml]. The specs list is the one place in the menu
       system that carries handlers. *)
    | Actions of
        { scope : string
        ; specs : Action_spec.t list
        }
    | Widget_name of string
    | Cursor_name of string
    | Test_id of string
    | Measure_overlay of bool
    | Grid_cell of Grid_cell.t
    | Page_title of string
    | Row_selectable of bool
    | Row_activatable of bool
    (* The tab label a [GtkNotebook] draws for this page, held by the {i notebook} on the
       page's behalf exactly as [Page_title] is held by a stack. A [string] and not a
       node: the tab label is a widget GTK builds and owns, and a node there would mean a
       second child list, a second patch path and a second lifetime for something that is
       always a label. *)
    | Tab_label of string
    | On_clicked of unit Handler.t
    | On_toggled of bool Handler.t
    | On_changed of string Handler.t
    | On_activate of unit Handler.t
    | On_search_changed of string Handler.t
    | On_value_changed of float Handler.t
    | On_expanded_changed of bool Handler.t
    | On_revealed of bool Handler.t
    | On_position_changed of int Handler.t
    | On_visible_child_changed of string Handler.t
    (* Both carry the row's {!Key.t} rather than the row or its index: the key is what the
       node said, and it is the only thing about a live [GtkListBoxRow] the application
       has a name for. See [src/child_keys.ml]. *)
    | On_row_activated of Key.t Handler.t
    | On_selected_rows_changed of Key.t list Handler.t
    (* A flow box's pair of the same two, named after the GTK signals they carry
       ([child-activated], [selected-children-changed]) exactly as the list box's are
       ([row-activated], [selected-rows-changed]). One naming scheme, and it is GTK's: the
       alternative -- one shared [On_item_activated] over both -- would have to be
       accepted on both kinds by [Events.for_kind], and a copied line would then be inert
       rather than rejected. *)
    | On_child_activated of Key.t Handler.t
    | On_selected_children_changed of Key.t list Handler.t
    (* The page's {!Key.t}, on the rule the other four container handlers follow:
       [switch-page] hands GTK's callback the page's {i content widget} and an index that
       moves, and the key is the only name the application has for either. *)
    | On_page_changed of Key.t Handler.t
    (* The position of the item a [GtkDropDown] now shows, and [-1] for none -- the
       vtree's spelling of GTK's [GTK_INVALID_LIST_POSITION], translated at the boundary
       and nowhere else (see [src/widgets/w_drop_down.ml]).

       An index rather than a name, which makes it the one container-ish handler in this
       list that does not carry a {!Key.t}. A drop-down's items are a {i prop} of the
       node, not children, so the handler already holds the list the index points into and
       can take the string out of it; a list box's rows are children, and their keys are
       the only name the application has for them. Carrying the string as well would also
       make the attr claim more than GTK says: [notify::selected] reports a position and
       nothing else. *)
    | On_selected_changed of int Handler.t
    (* The date a [GtkCalendar] now shows, as a {!Core.Date.t} and never as GTK's three
       integers. GTK's [day-selected] carries no payload and its [month] property is
       zero-based; both stop inside [src/widgets/w_calendar.ml], which reads the three
       getters back and assembles the date. So this handler is handed the one thing an
       application can act on, and the off-by-one that makes December look like November
       has no path to it. *)
    | On_day_selected of Date.t Handler.t
    (* Whether a [GtkEditableLabel] is now in editing mode.

       [editing] is read-only in GTK -- there is no [gtk_editable_label_set_editing] --
       and there is no [editing-changed] signal either, so this rides on [notify::editing]
       and the handler reads [get_editing] back ([src/widgets/w_editable_label.ml]). The
       {i text} the user typed does not come through here: it arrives through [On_changed]
       like an entry's, because a [GtkEditableLabel] reaches its text through
       [GtkEditable] like an entry does. *)
    | On_editing_changed of bool Handler.t
    (* The caret of a [GtkTextView], as a character offset into the buffer, whenever it
       moves -- a click, an arrow key, a selection drag's insertion point. Rides on
       [notify::cursor-position] of the {i buffer} (the view has no such property), so the
       connection names the buffer and the offset is read back with [get_cursor_position].
       This is the attr that closes the controlled write's "approximate caret" caveat: an
       application that owns the caret can put it where its model says. *)
    | On_cursor_moved of int Handler.t
    (* A [GtkPopover] was dismissed -- by the user (click-away, Escape) or by anything
       else that popped it down; the reentrancy guard keeps the library's own [popdown]s
       out, and pre-flight correction 8 is what makes that sufficient ([closed] is emitted
       synchronously inside [popdown]). Carries nothing: the popover that closed is the
       node the attr rides on. *)
    | On_closed of unit Handler.t
    (* [button] and [phase] ride in the constructor rather than being captured by the
       handler because they are properties of the *controller*: [Controllers.update] has
       to see a change in either without the handler having to change, and a view that
       rebuilds its closures every frame changes the handler on every frame regardless.

       The handler is not a [Handler.t]: it returns a [Click_response.t] rather than an
       effect, because whether the gesture claims the event sequence is decided
       synchronously inside the [pressed] trampoline, on the C stack -- see
       [Click_response]. *)
    | On_click of
        { button : int
        ; phase : Phase.t
        ; handler : Click_response.handler
        }
    (* [phase] rides in the constructor for the reason [On_click]'s does: it is a property
       of the *controller*, and [Controllers.update] has to see it change without the
       handler having to. The two focus attrs share one [GtkEventControllerFocus] -- as
       [On_contains_focus_changed] does, though that one carries no phase of its own: a
       [notify::] fires in no propagation phase at all -- so carrying it on both is what
       lets either appear alone, at the price of a rejection when both appear and disagree
       ([Events.family_phase_rejection]). *)
    | On_focus_enter of
        { phase : Phase.t
        ; handler : unit Handler.t
        }
    | On_focus_leave of
        { phase : Phase.t
        ; handler : unit Handler.t
        }
    (* The [contains_focus] {i query} stavekeeper polls, as an event: rides on
       [notify::contains-focus] of the shared Focus-family controller, and the handler is
       handed the property read back. No phase field -- see the pair above. *)
    | On_contains_focus_changed of bool Handler.t
    (* [phase] rides in the constructor for the same reason [On_click]'s does: it is a
       property of the *controller*, and [Controllers.update] has to see it change without
       the handler having to. The two key attrs share one [GtkEventControllerKey], so
       there is exactly one phase to write and carrying it on both is what lets either
       attr appear alone -- at the price of a rejection when both appear and disagree
       ([Events.family_phase_rejection]). *)
    | On_key_pressed of
        { phase : Phase.t
        ; handler : Key_response.handler
        }
    | On_key_released of
        { phase : Phase.t
        ; handler : Key_event.t Handler.t
        }
    (* A {i list}, because the attr is repeatable: [Attrs.of_list] merges every
       [Attr.shortcut] on one node into this single keyed entry (the css-class
       accumulation, keyed), so all of a node's shortcuts reach the one
       [GtkShortcutController] together and the phase rejection can see them all. *)
    | Shortcut of shortcut list
    | Many of t list
  [@@deriving sexp_of]
end

include Private

(* [Many] flattened away, so that [Attrs.of_list] -- the one caller that has to
   look *inside* a [Many] -- never needs to turn a [Private.t] back into a [t], which the
   private abbreviation forbids. Depth-first and left to right, so "last one wins" in
   [Attrs.of_list] still means what it says. *)
let flatten ts =
  let rec go acc = function
    | Many l -> List.fold l ~init:acc ~f:go
    | attr -> attr :: acc
  in
  List.rev (List.fold ts ~init:[] ~f:go)
;;

let name = function
  | Css_class _ | Many _ -> None
  | Margin_start _ -> Some Name.Margin_start
  | Margin_end _ -> Some Margin_end
  | Margin_top _ -> Some Margin_top
  | Margin_bottom _ -> Some Margin_bottom
  | Halign _ -> Some Halign
  | Valign _ -> Some Valign
  | Hexpand _ -> Some Hexpand
  | Vexpand _ -> Some Vexpand
  | Sensitive _ -> Some Sensitive
  | Visible _ -> Some Visible
  | Tooltip _ -> Some Tooltip
  | Width_request _ -> Some Width_request
  | Height_request _ -> Some Height_request
  | Opacity _ -> Some Opacity
  | Focusable _ -> Some Focusable
  | Can_focus _ -> Some Can_focus
  | Autofocus _ -> Some Autofocus
  | Actions _ -> Some Actions
  | Widget_name _ -> Some Widget_name
  | Cursor_name _ -> Some Cursor_name
  | Test_id _ -> Some Test_id
  | Measure_overlay _ -> Some Measure_overlay
  | Grid_cell _ -> Some Grid_cell
  | Page_title _ -> Some Page_title
  | Row_selectable _ -> Some Row_selectable
  | Row_activatable _ -> Some Row_activatable
  | Tab_label _ -> Some Tab_label
  | On_clicked _ -> Some On_clicked
  | On_toggled _ -> Some On_toggled
  | On_changed _ -> Some On_changed
  | On_activate _ -> Some On_activate
  | On_search_changed _ -> Some On_search_changed
  | On_value_changed _ -> Some On_value_changed
  | On_expanded_changed _ -> Some On_expanded_changed
  | On_revealed _ -> Some On_revealed
  | On_position_changed _ -> Some On_position_changed
  | On_visible_child_changed _ -> Some On_visible_child_changed
  | On_row_activated _ -> Some On_row_activated
  | On_selected_rows_changed _ -> Some On_selected_rows_changed
  | On_child_activated _ -> Some On_child_activated
  | On_selected_children_changed _ -> Some On_selected_children_changed
  | On_page_changed _ -> Some On_page_changed
  | On_selected_changed _ -> Some On_selected_changed
  | On_day_selected _ -> Some On_day_selected
  | On_editing_changed _ -> Some On_editing_changed
  | On_cursor_moved _ -> Some On_cursor_moved
  | On_closed _ -> Some On_closed
  | On_click _ -> Some On_click
  | On_focus_enter _ -> Some On_focus_enter
  | On_focus_leave _ -> Some On_focus_leave
  | On_contains_focus_changed _ -> Some On_contains_focus_changed
  | On_key_pressed _ -> Some On_key_pressed
  | On_key_released _ -> Some On_key_released
  | Shortcut _ -> Some Shortcut
;;

let rec equal a b =
  match a, b with
  | Css_class a, Css_class b
  | Tooltip a, Tooltip b
  | Test_id a, Test_id b
  | Widget_name a, Widget_name b
  | Cursor_name a, Cursor_name b
  | Page_title a, Page_title b
  | Tab_label a, Tab_label b -> String.equal a b
  | Margin_start a, Margin_start b
  | Margin_end a, Margin_end b
  | Margin_top a, Margin_top b
  | Margin_bottom a, Margin_bottom b
  | Width_request a, Width_request b
  | Height_request a, Height_request b -> Int.equal a b
  | Halign a, Halign b | Valign a, Valign b -> Align.equal a b
  | Hexpand a, Hexpand b
  | Vexpand a, Vexpand b
  | Sensitive a, Sensitive b
  | Visible a, Visible b
  | Focusable a, Focusable b
  | Can_focus a, Can_focus b
  | Autofocus a, Autofocus b
  | Measure_overlay a, Measure_overlay b
  | Row_selectable a, Row_selectable b
  | Row_activatable a, Row_activatable b -> Bool.equal a b
  | Opacity a, Opacity b -> Float.equal a b
  | Grid_cell a, Grid_cell b -> Grid_cell.equal a b
  | Actions a, Actions b ->
    String.equal a.scope b.scope && List.equal Action_spec.equal a.specs b.specs
  | On_clicked a, On_clicked b -> Handler.equal a b
  | On_toggled a, On_toggled b -> Handler.equal a b
  | On_changed a, On_changed b -> Handler.equal a b
  | On_activate a, On_activate b -> Handler.equal a b
  | On_search_changed a, On_search_changed b -> Handler.equal a b
  | On_value_changed a, On_value_changed b -> Handler.equal a b
  | On_expanded_changed a, On_expanded_changed b -> Handler.equal a b
  | On_revealed a, On_revealed b -> Handler.equal a b
  | On_position_changed a, On_position_changed b -> Handler.equal a b
  | On_visible_child_changed a, On_visible_child_changed b -> Handler.equal a b
  | On_row_activated a, On_row_activated b -> Handler.equal a b
  | On_selected_rows_changed a, On_selected_rows_changed b -> Handler.equal a b
  | On_child_activated a, On_child_activated b -> Handler.equal a b
  | On_selected_children_changed a, On_selected_children_changed b -> Handler.equal a b
  | On_page_changed a, On_page_changed b -> Handler.equal a b
  | On_selected_changed a, On_selected_changed b -> Handler.equal a b
  | On_day_selected a, On_day_selected b -> Handler.equal a b
  | On_editing_changed a, On_editing_changed b -> Handler.equal a b
  | On_cursor_moved a, On_cursor_moved b -> Handler.equal a b
  | On_closed a, On_closed b -> Handler.equal a b
  (* The two controller properties compare structurally and the handler physically: a
     frame that moves the gesture to another button, or into the capture phase, is a
     change [Controllers.update] must see even though the closure is rebuilt (and so
     unequal) on every frame anyway. The handler is a [Click_response.handler] rather than
     a [Handler.t], so [phys_equal] is spelled out, as [On_key_pressed]'s is. *)
  | On_click a, On_click b ->
    Int.equal a.button b.button
    && Phase.equal a.phase b.phase
    && phys_equal a.handler b.handler
  | On_focus_enter a, On_focus_enter b ->
    Phase.equal a.phase b.phase && Handler.equal a.handler b.handler
  | On_focus_leave a, On_focus_leave b ->
    Phase.equal a.phase b.phase && Handler.equal a.handler b.handler
  | On_contains_focus_changed a, On_contains_focus_changed b -> Handler.equal a b
  (* Same rule as [On_click]: the controller property structurally, the handler
     physically. [On_key_pressed]'s handler is not a [Handler.t] -- it returns a
     [Key_response.t] rather than an effect -- but it is still a closure the view rebuilds
     every frame, so [phys_equal] is the only honest comparison and [Handler.equal] is
     spelled out here rather than reached for. *)
  | On_key_pressed a, On_key_pressed b ->
    Phase.equal a.phase b.phase && phys_equal a.handler b.handler
  | On_key_released a, On_key_released b ->
    Phase.equal a.phase b.phase && Handler.equal a.handler b.handler
  (* Fully structural -- a shortcut names its action rather than carrying a closure -- so
     unlike every other event attr this one diffs to nothing on an unchanged frame. *)
  | Shortcut a, Shortcut b -> List.equal equal_shortcut a b
  | Many a, Many b -> List.equal equal a b
  | _ -> false
;;

let css_class s = Css_class s
let margin_start n = Margin_start n
let margin_end n = Margin_end n
let margin_top n = Margin_top n
let margin_bottom n = Margin_bottom n
let margin n = Many [ Margin_start n; Margin_end n; Margin_top n; Margin_bottom n ]
let halign a = Halign a
let valign a = Valign a
let hexpand b = Hexpand b
let vexpand b = Vexpand b
let sensitive b = Sensitive b
let visible b = Visible b
let tooltip s = Tooltip s
let width_request n = Width_request n
let height_request n = Height_request n
let opacity f = Opacity f
let focusable b = Focusable b
let can_focus b = Can_focus b
let autofocus b = Autofocus b

(* Two structural rejections, both at the line that made the mistake. A duplicate name
   would be two [GSimpleAction]s fighting over one lookup; a dotted (or empty) scope would
   make every "scope.name" reference ambiguous, since resolution splits on the first dot.
   Action {i names} may contain dots -- GTK allows them, and the first-dot split still
   finds the scope. *)
let actions ~scope specs =
  if String.is_empty scope || String.mem scope '.'
  then
    invalid_argf
      "Attr.actions: scope %S must be non-empty and contain no '.' (action references \
       split on the first dot)"
      scope
      ();
  (match
     List.find_a_dup
       (List.map specs ~f:(fun (s : Action_spec.t) -> s.name))
       ~compare:String.compare
   with
   | Some name ->
     invalid_argf "Attr.actions: two specs are named %S in scope %S" name scope ()
   | None -> ());
  Actions { scope; specs }
;;

let widget_name s = Widget_name s
let cursor_name s = Cursor_name s
let test_id s = Test_id s

(* A setting the *overlay* holds about this child, not a property of the child, so it is
   read by [w_overlay] from the child node's attrs rather than written by [Attr_apply];
   see the mli. *)
let measure_overlay b = Measure_overlay b

(* [gtk_grid_attach] is a call on the *grid*, so a child's coordinates are something the
   grid holds about it rather than a property of the child; they ride on the child node's
   attrs and are read by [w_grid]. See the mli. *)
let grid_cell ~column ~row ?(width = 1) ?(height = 1) () =
  Grid_cell { Grid_cell.column; row; width; height }
;;

let page_title s = Page_title s

(* Two settings the *list box* holds about each row, on the same rule as
   [Attr.page_title]: the impl wraps every child in a [GtkListBoxRow] of its own, and
   these are properties of that wrapper rather than of the child. See the mli. *)
let row_selectable b = Row_selectable b
let row_activatable b = Row_activatable b

(* The one setting a *notebook* holds about each page, on [Attr.page_title]'s rule. See
   the mli for why it is a string rather than a node. *)
let tab_label s = Tab_label s
let on_clicked eff = On_clicked (fun () -> eff)
let on_toggled f = On_toggled f
let on_changed f = On_changed f
let on_activate eff = On_activate (fun () -> eff)
let on_search_changed f = On_search_changed f
let on_value_changed f = On_value_changed f
let on_expanded_changed f = On_expanded_changed f
let on_revealed f = On_revealed f
let on_position_changed f = On_position_changed f
let on_visible_child_changed f = On_visible_child_changed f
let on_row_activated f = On_row_activated f
let on_selected_rows_changed f = On_selected_rows_changed f
let on_child_activated f = On_child_activated f
let on_selected_children_changed f = On_selected_children_changed f
let on_page_changed f = On_page_changed f
let on_selected_changed f = On_selected_changed f
let on_day_selected f = On_day_selected f
let on_editing_changed f = On_editing_changed f
let on_cursor_moved f = On_cursor_moved f
let on_closed eff = On_closed (fun () -> eff)

let on_click ?(button = 0) ?(phase = Phase.Bubble) handler =
  On_click { button; phase; handler }
;;

let on_focus_enter ?(phase = Phase.Bubble) f = On_focus_enter { phase; handler = f }
let on_focus_leave ?(phase = Phase.Bubble) f = On_focus_leave { phase; handler = f }
let on_contains_focus_changed f = On_contains_focus_changed f
let on_key_pressed ?(phase = Phase.Bubble) handler = On_key_pressed { phase; handler }
let on_key_released ?(phase = Phase.Bubble) handler = On_key_released { phase; handler }

(* Repeatable: each call is one entry, and [Attrs.of_list] merges a node's entries into
   one keyed list (see [Private.Shortcut]). A "::target" is rejected here because M3 ships
   untargeted shortcuts only: activation goes through [GtkNamedAction], which passes no
   parameter. Targeted shortcuts are {i feasible} -- [Shortcut.set_arguments] is bound --
   and deliberately unshipped (docs/m2-backlog.md, "Recorded during M3"); see
   [Attr.shortcut]'s doc. *)
let shortcut ?(phase = Phase.Bubble) ~trigger ~action () =
  if String.is_substring action ~substring:"::"
  then
    invalid_argf
      "Attr.shortcut: action %S carries a \"::target\", but targeted shortcuts are not \
       shipped in M3 (activation goes through a parameterless GtkNamedAction; \
       Shortcut.set_arguments is the unshipped path)"
      action
      ();
  Shortcut [ { trigger; phase; action } ]
;;

(* For [Attrs.of_list] only: the merge that makes the attr repeatable. [Attr.t] is a
   private abbreviation outside this file, so the merged value can only be built here. *)
let merge_shortcuts a b =
  match a, b with
  | Shortcut a, Shortcut b -> Shortcut (a @ b)
  | _ -> invalid_arg "Attr.merge_shortcuts: both arguments must be Shortcut attrs"
;;

let many l = Many l
let empty = Many []
