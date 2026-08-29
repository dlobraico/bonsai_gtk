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
  | Spin_button _ -> W_spin_button.impl
  | Scale _ -> W_scale.impl
  | Progress_bar _ -> W_progress_bar.impl
  | Spinner _ -> W_spinner.impl
  | Image _ -> W_image.impl
  | Picture _ -> W_picture.impl
  | Separator _ -> W_separator.impl
  | Box _ -> W_box.impl
  | Window _ -> W_window.impl
  | Native n -> Native_gtk.impl_of_payload n
;;
