open! Core
open Gtk_import

(* The display-wide half of M3 Task 11: one [GtkCssProvider] on the default display -- the
   only display the fork's [Style_display] stub reaches -- at application priority,
   holding the caller's [?global_css]. Installed from [Loop.start]'s activate and from
   [Embed.create]; never removed (GTK accumulates providers, and the one-app-per-process
   warning in [Gtk_effect.For_start.set_app] covers the second-start situation -- the mli
   says so rather than this module engineering removal).

   The color-scheme mirror is the stavekeeper Theme.install lesson, owned by the runtime
   so no port carries it again: GTK 4.20+ evaluates [@media (prefers-color-scheme)]
   {b per provider}, against that provider's own [prefers-color-scheme] property, and GTK
   syncs only its own theme provider with [GtkSettings] -- an application provider left at
   [`DEFAULT] stays light regardless of GTK_THEME or settings.ini (verified downstream on
   4.22). So the provider mirrors [gtk-interface-color-scheme] (falling back to
   [gtk-application-prefer-dark-theme], the older knob) and re-mirrors on both properties'
   [notify::], which is what lets a desktop flipping to dark re-theme the app without a
   restart. The [Settings] is process-global and the connections close over the provider,
   so an installed provider lives for the process -- exactly the accumulate-and-keep
   contract above. *)

let scheme_of_settings settings : Gtk_enums.interfacecolorscheme =
  match W.Settings.get_gtk_interface_color_scheme settings with
  | `DARK -> `DARK
  | `LIGHT -> `LIGHT
  | `DEFAULT | `UNSUPPORTED ->
    if W.Settings.get_gtk_application_prefer_dark_theme settings then `DARK else `DEFAULT
;;

let install ~css =
  let provider = W.Css_provider.new_ () in
  W.Css_provider.load_from_string provider css;
  let settings = Style_display.settings_default () in
  let mirror () =
    W.Css_provider.set_prefers_color_scheme provider (scheme_of_settings settings)
  in
  mirror ();
  (* [connect_simple] goes through [g_signal_connect_closure], which accepts a detailed
     "notify::<prop>" name. The callbacks run on C-called frames, so they are
     report-then-swallow like every trampoline. *)
  List.iter
    [ "notify::gtk-interface-color-scheme"; "notify::gtk-application-prefer-dark-theme" ]
    ~f:(fun name ->
      ignore
        (Gobject.Signal.connect_simple
           settings
           ~name
           ~callback:(fun () ->
             try mirror () with
             | exn ->
               (try
                  eprintf
                    "bonsai_gtk: exception re-mirroring the global css color scheme: %s\n\
                     %!"
                    (Exn.to_string exn)
                with
                | _ -> ()))
           ~after:false
         : Gobject.Signal.handler_id));
  Style_display.add_provider_for_default_display
    (W.Style_provider.from_gobject provider)
    Style_display.priority_application;
  provider
;;
