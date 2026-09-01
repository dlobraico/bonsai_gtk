open! Core
open Bonsai_gtk_vtree
module Attr_apply = Bonsai_gtk.Private.Attr_apply
module Global_css = Bonsai_gtk.Private.Global_css
module Gobject = Bonsai_gtk.Private.Gtk_import.Gobject
module P = Bonsai_gtk.Private.Patcher
module Scheduler = Bonsai_gtk.Private.Scheduler
module Style_display = Bonsai_gtk.Private.Gtk_import.Style_display
module W = Bonsai_gtk.Private.Gtk_import.W

(* CSS against real GTK (M3 Task 11), and every assertion here is {b structural}: the pin
   has no computed-style read-back (no snapshot/render API is bound), so what can be
   proven is what GTK was handed -- the provider exists, holds the css it was given (its
   own [to_string]), keeps its identity across a string change, and is gone on unset --
   plus the color-scheme mirroring read back off the provider property GTK 4.20+ actually
   evaluates [@media (prefers-color-scheme)] against. Whether the pixels changed is a
   real-display question this suite says it is not answering.

   The suite takes the x-display lock not for a toplevel (it presents none) but because
   its global half MUTATES the default display's [GtkSettings] -- a neighbour suite
   restyling mid-run is exactly the interference the lock exists for. *)

let () = ignore (Ocgtk_gtk.GMain.init () : string array)

(* --- the per-widget provider: [Attr.css_provider] through the patcher, probed with
   [Attr_apply.live_css_provider] (the §2.2 keep-alive: the provider is owned by the
   runtime for as long as the widget lives). *)
let () =
  let scheduler = Scheduler.create ~run_frame:(fun () -> ()) in
  let ctx =
    P.create_ctx
      ~signals:
        { schedule = (fun _ -> ())
        ; in_patch = (fun () -> Scheduler.in_patch scheduler)
        ; on_exn =
            (fun ~node_path exn -> printf "EXN at %s: %s\n" node_path (Exn.to_string exn))
        }
      ~on_window_created:(fun _ -> ())
      ()
  in
  let view ?css () =
    Node.window
      ~title:"css"
      (Node.label
         ~attrs:
           (match css with
            | None -> []
            | Some css -> [ Attr.css_provider css ])
         "styled")
  in
  let live =
    P.mount ctx ~path:"css" ~is_root:true (view ~css:"label { margin: 1px; }" ())
  in
  P.run_fixups ctx;
  let label (live : P.live) =
    match live.children with
    | Single (Some l) -> l.P.widget
    | _ -> assert false
  in
  let provider () = Attr_apply.live_css_provider (label live) in
  let dump_provider () =
    match provider () with
    | None -> printf "no provider\n"
    | Some p -> printf "provider holds: %s" (W.Css_provider.to_string p)
  in
  dump_provider ();
  let before = provider () in
  let patch live v =
    Scheduler.with_patch_guard scheduler (fun () ->
      P.patch ctx ~path:"css" ~is_root:true live v)
  in
  (* A changed string reloads the SAME provider -- GTK restyles in place; a fresh provider
     per frame would be an accumulating pile the style context never drops. *)
  let live = patch live (view ~css:"label { margin: 2px; }" ()) in
  dump_provider ();
  printf
    "same provider across the change: %b\n"
    (match before, provider () with
     | Some a, Some b -> Gobject.same a b
     | _ -> false);
  (* Unset removes the provider from the style context and the runtime's table. *)
  let live = patch live (view ()) in
  dump_provider ();
  (* Re-adding after an unset is a fresh provider, like any Set on a widget without one. *)
  let live = patch live (view ~css:"label { margin: 3px; }" ()) in
  dump_provider ();
  printf
    "fresh provider after the round trip: %b\n"
    (match before, provider () with
     | Some a, Some b -> not (Gobject.same a b)
     | _ -> false);
  (* Invalid CSS: GTK reports a parsing warning through its own log (not this golden) and
     keeps the previous ruleset; the frame must not raise. *)
  let live = patch live (view ~css:"label { this is not css !!" ()) in
  printf "an invalid stylesheet did not raise\n";
  P.destroy ctx live;
  printf "per-widget css done\n"
;;

(* --- the global provider: what [start ?global_css] and [embed ?global_css] install,
   driven directly. The color-scheme half is the stavekeeper Theme.install lesson: GTK
   4.20+ evaluates [@media (prefers-color-scheme)] per provider against the provider's own
   property, and only GTK's built-in theme provider tracks GtkSettings -- an application
   provider that does not mirror the setting can never match its dark block, whatever the
   desktop says. The mirror and its notify re-mirror are asserted off the provider
   property itself. *)
let () =
  let provider =
    Global_css.install
      ~css:
        ".bonsai-css-test { margin: 1px; }\n\
         @media (prefers-color-scheme: dark) { .bonsai-css-test { margin: 2px; } }"
  in
  printf "global provider holds: %s" (W.Css_provider.to_string provider);
  let scheme () =
    match W.Css_provider.get_prefers_color_scheme provider with
    | `DARK -> "dark"
    | `LIGHT -> "light"
    | `DEFAULT -> "default"
    | `UNSUPPORTED -> "unsupported"
  in
  printf "scheme as installed: %s\n" (scheme ());
  let settings = Style_display.settings_default () in
  W.Settings.set_gtk_application_prefer_dark_theme settings true;
  printf "scheme after prefer-dark flips on: %s\n" (scheme ());
  W.Settings.set_gtk_application_prefer_dark_theme settings false;
  printf "scheme after prefer-dark flips off: %s\n" (scheme ());
  printf "global css done\n"
;;
