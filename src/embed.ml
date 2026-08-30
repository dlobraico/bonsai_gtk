open! Core
open Gtk_import

type t =
  { driver : Driver.t
  ; (* The widget the caller parents, and the only one it ever sees. See [create] for why
       there is a wrapper at all and why it is a [GtkOverlay]. *)
    wrapper : W.Overlay.t
  ; (* The destroy backstop's handler until {!stop} disconnects it, and [None] afterwards:
       [stop] is idempotent and [g_signal_handler_disconnect] on an id that is already
       gone is a GLib critical, not a no-op. *)
    mutable backstop : Gobject.Signal.handler_id option
  }

let widget t : Widget.t = cast t.wrapper
let frame t = Driver.frame t.driver
let schedule_event t effect = Driver.schedule_event t.driver effect
let broken t = Driver.broken t.driver

let stop t =
  (* Teardown before unparenting, which is the patcher's own order and for its reason: GTK
     emits signals synchronously from [set_child], and [Driver.stop] has emptied every
     slot in the tree by the time this runs, so nothing a teardown provokes can reach
     Bonsai. *)
  (* [Driver.stop] can raise (a native node's [destroy] is application code), and the two
     steps below are not tidiness: leaving the tree parented in the wrapper with the
     backstop still connected is the configuration this comment calls actively unsafe, and
     a caller holding an exception instead of a returned [t] is exactly the caller least
     likely to call [stop] again. So they run whatever the driver did, and the exception
     goes on up afterwards. *)
  Exn.protect
    ~f:(fun () -> Driver.stop t.driver)
    ~finally:(fun () ->
      W.Overlay.set_child t.wrapper None;
      (* And the backstop goes with it, which is not tidiness but a requirement.

         Its job is to notice a disposal that happens {i while this embed is rendering};
         after [stop] there is nothing left to protect, and leaving it connected is
         actively unsafe. [stop] is what makes the wrapper collectable (it drops the
         driver's reference to it), so the very next thing that can happen to a
         stopped-and-dropped wrapper is OCaml finalisation: ocgtk's finaliser unrefs the
         GObject, GTK disposes it, and dispose emits [destroy] -- which would re-enter
         OCaml, from inside the collector's finalisation pass, to run a callback holding
         this driver. Measured: with the handler left connected, the second [embed]
         created after a stopped embed had been dropped never returns; the same re-entry
         with a callback that allocates segfaults, which is the ocgtk defect the fork has
         to fix (see [Signals]' rule about dispose-time signals). Removing the only path
         on which [destroy] can reach OCaml at all removes it.

         And the two states are mutually exclusive by construction rather than merely
         sequenced: the wrapper {i cannot} be finalised while this handler is connected --
         the callback's GClosure holds the driver, and the driver's
         [on_root_widget_changed] holds the wrapper -- so disconnecting here is what
         {i creates} the finalisable state, and it must happen in the same call that
         creates it. Measured (task-12-review.md, probe B): a [t] dropped without [stop],
         including one over a signal-free tree, finalises 0 wrappers of 1. *)
      Option.iter t.backstop ~f:(Gobject.Signal.disconnect (cast t.wrapper : Widget.t));
      t.backstop <- None)
;;

let create ?time_source ?optimize ?(target_frames_per_second = 60.) app =
  (* {b Why there is a wrapper.}

     The obvious design hands the caller the root widget itself. It is wrong, and silently
     so. The root node's {i kind} may change between frames -- [Node.label "Loading..."]
     on one and [Node.box [...]] on the next is an ordinary page, not a corner case -- and
     when it does the patcher mounts a replacement widget and destroys the original
     (`Patcher.patch`'s kind-change arm). A caller that did
     [stack#add_named (Embedded.widget e)] once, at mount, would then be holding a widget
     nothing renders into again: no exception, no stderr line, [broken] still false, and
     the page frozen and inert on screen because its handlers have been disconnected.
     Under [Bonsai_gtk.start] the arm is unreachable, since a windowed root is always a
     [Window]; [embed] is what makes an arbitrary node the root and the arm reachable.

     So [embed] owns one container of its own, hands the caller {i that}, and re-parents
     the rendered root into it whenever the driver reports a new one. The caller's
     container holds a widget whose identity never changes, which is the promise [widget]
     makes.

     {b Why a [GtkOverlay].} The wrapper has to be invisible to layout: the tree must be
     allocated exactly as it would have been had the caller parented it directly. Measured
     under GTK 4 -- a non-expanding child with [halign]/[valign] [`CENTER] in a 400x300
     [GtkStack] page, child position relative to the stack:

     {v
       parented directly     (196,142)
       inside a GtkBox `VERTICAL     (196,0)     -- valign lost
       inside a GtkBox `HORIZONTAL     (0,142)   -- halign lost
       inside a GtkGrid cell             (0,0)   -- both lost
       inside a GtkOverlay           (196,142)   -- identical to direct
     v}

     A box packs along its orientation and a grid packs into a cell, so both hand the
     child its natural size and drop the alignment on that axis. [GtkOverlay] gives its
     main child the whole allocation, which is what [set_child] on a window or a stack
     page does -- it is [GtkBinLayout] under a public name. All four forward
     [hexpand]/[vexpand] from the child correctly; only the overlay also forwards
     alignment. It draws nothing and adds no CSS. *)
  let wrapper = W.Overlay.new_ () in
  let driver =
    Driver.create
      ?time_source
      ?optimize
      ~root_kind:`Not_window
      ~on_root_widget_changed:(fun root ->
        (* Explicitly in two steps rather than relying on [gtk_overlay_set_child] to
           unparent the outgoing child for us: this runs on the kind-change frame, and the
           widget being displaced has just been destroyed by the patcher (slots cleared,
           handlers disconnected) but is still parented here. Unparenting it is the last
           thing anybody does with it. *)
        W.Overlay.set_child wrapper None;
        W.Overlay.set_child wrapper (Some root))
      ~on_window_created:(fun _ ->
        (* Unreachable: [root_kind] refuses a window at the root and the patcher refuses
           one anywhere below it, so no [Window] node ever reaches a mount here. It is a
           [failwith] rather than a no-op because reaching it would mean one of those two
           checks had a hole, and a silently unpresented window is the failure mode §11
           exists to prevent. *)
        failwith
          "bonsai_gtk: a window was mounted inside an embedded tree, which the root-kind \
           check and the patcher should both have rejected")
      app
  in
  (* The first frame is what mounts the tree, and it is the frame most likely to raise: a
     constructor's [Invalid_argument], a window at the root, a misplaced placement attr.
     It runs before the tick is installed so that a failure leaves no timeout behind, and
     it runs under a [stop] on the way out because the caller is about to receive an
     exception instead of a [t] and would otherwise have no handle to tear the partial
     tree down. [Patcher.mount] is exception-safe, so by the time [stop] runs there is
     nothing of the failed tree left for it to walk; what it still has to do is stop the
     scheduler and invalidate the Bonsai graph. *)
  (match Driver.frame driver with
   | () -> ()
   | exception exn ->
     let backtrace = Stdlib.Printexc.get_raw_backtrace () in
     Driver.stop driver;
     Stdlib.Printexc.raise_with_backtrace exn backtrace);
  (* The backstop for a host that disposes its children rather than dropping the last
     reference to them, connected to the wrapper because the wrapper is what the caller
     parents and therefore what a host's disposal would reach. Measured under GTK 4:
     neither [gtk_window_destroy] on an ancestor nor the unparenting that a container's
     own dispose performs emits [destroy] on a widget something still holds a reference to
     -- and the shadow tree holds one for every widget in this tree -- so in every
     ordinary teardown this handler stays silent and the tree simply survives, off screen
     and still patchable. The one path it covers is an embedder that runs dispose on the
     tree outright, after which patching would touch widgets GTK has already emptied.

     [mark_broken] rather than [stop]: [stop] would walk this very subtree disconnecting
     handlers from the widgets whose disposal is the thing being reported, and we are
     inside one of their signal emissions while it happens. Marking broken removes the
     tick and makes every later frame the no-op [Driver.broken] promises, and touches no
     widget at all. The embedder still calls [stop] itself, which is then a tear-down of a
     driver that has already stopped rendering.

     Disconnected by [stop], which is not optional -- see there. *)
  let backstop =
    W.Widget.on_destroy
      (cast wrapper : Widget.t)
      ~callback:(fun () -> Driver.mark_broken driver)
  in
  Driver.start_tick driver ~fps:target_frames_per_second;
  { driver; wrapper; backstop = Some backstop }
;;
