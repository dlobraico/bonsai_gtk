open! Core
open Bonsai_gtk_vtree

let for_kind : Kind.t -> Widget_impl.t = function
  | Label _ -> W_label.impl
  | Button _ -> W_button.impl
  | Toggle_button _ -> W_toggle_button.impl
  | Check_button _ -> W_check_button.impl
  | Switch _ -> W_switch.impl
  | Entry _ -> W_entry.impl
  | Password_entry _ -> W_password_entry.impl
  | Search_entry _ -> W_search_entry.impl
  | Text_view _ -> W_text_view.impl
  | Spin_button _ -> W_spin_button.impl
  | Scale _ -> W_scale.impl
  | Progress_bar _ -> W_progress_bar.impl
  | Spinner _ -> W_spinner.impl
  | Level_bar _ -> W_level_bar.impl
  | Image _ -> W_image.impl
  | Picture _ -> W_picture.impl
  | Separator _ -> W_separator.impl
  | Scrolled_window _ -> W_scrolled_window.impl
  | Frame _ -> W_frame.impl
  | Expander _ -> W_expander.impl
  | Revealer _ -> W_revealer.impl
  | Box _ -> W_box.impl
  | Grid _ -> W_grid.impl
  | Stack _ -> W_stack.impl
  | Stack_switcher _ -> W_stack_switcher.impl
  | Stack_sidebar _ -> W_stack_sidebar.impl
  | List_box _ -> W_list_box.impl
  | Flow_box _ -> W_flow_box.impl
  | Notebook _ -> W_notebook.impl
  | Drop_down _ -> W_drop_down.impl
  | Calendar _ -> W_calendar.impl
  | Editable_label _ -> W_editable_label.impl
  | Center_box _ -> W_center_box.impl
  | Paned _ -> W_paned.impl
  | Overlay _ -> W_overlay.impl
  | Header_bar _ -> W_header_bar.impl
  | Action_bar _ -> W_action_bar.impl
  | Window _ -> W_window.impl
  | Native n -> Native_gtk.impl_of_payload n
;;
