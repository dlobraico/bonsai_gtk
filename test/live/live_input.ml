open! Core
open Bonsai_gtk_vtree
module Glib = Bonsai_gtk.Private.Gtk_import.Glib
module P = Bonsai_gtk.Private.Patcher
module Scheduler = Bonsai_gtk.Private.Scheduler
module W = Bonsai_gtk.Private.Gtk_import.W
module Rect = Ocgtk_graphene.Graphene.Wrappers.Rect

(* The stdlib's Unix, which [Core] shadows with a deprecated stub. Three calls are wanted
   ([create_process], [waitpid], [getpid]) and none is one [Core_unix] improves on, so
   this links `core_kernel.caml_unix` rather than adding `core_unix` to the suite. *)
module Unix = Caml_unix

let cast = Bonsai_gtk.Private.Gtk_import.cast

(* The one test in this repository that delivers a real button press and a real keystroke.

   Every other live suite proves an {i input} to GTK's event routing -- that the attr
   attached a controller with the button and the phase it asked for
   ([live_controllers.ml]), that the trampoline hands GTK the right answer
   ([live_signals.ml]) -- and [test/handle/test_handle.ml] proves the handler half
   headlessly. The routing in between is GTK's own, and it was the milestone's one
   genuinely uncovered claim. This file closes it by driving the X server the live suite
   already runs on: `xdotool` issues XTEST requests, the server delivers ordinary button
   and key events to this process's window, and GTK routes them through the controllers
   this library attached.

   {b It must be XTEST and not XSendEvent.} GTK drops events whose `send_event` record is
   set, so `xdotool key --window $WID` (which is XSendEvent) delivers nothing at all,
   while `xdotool windowfocus` followed by a plain `key` (which is XTEST, aimed at
   whatever holds the input focus) works. That is the first thing someone will reach for
   when "simplifying" the focus dance below, so it is written here rather than only in the
   backlog.

   {b No sleeps, no screenshots, no hardcoded pixels.} This executable is both the
   application and the driver, which is what makes all three avoidable:

   - coordinates come from the target's own widget box -- [Widget.translate_coordinates]
     of its (0,0), plus [get_width]/[get_height] -- in the toplevel's coordinate space, so
     nothing here encodes a window size, a font or a theme. {b Not [compute_bounds]},
     which is the obvious call, is the one the design sketch named, and is the wrong one
     for aiming a click: it answers with the region the widget {i draws} in, which on a
     themed [GtkButton] is inset by (17,5) from the box a gesture reports coordinates in.
     [box_of] below measures the difference on every run and puts it in the golden;
   - the settling wait is [pump_until], which pumps this process's own main loop until the
     handler's counter moves. Its bound is a GLib timeout source that exists only so that
     a {i failure} terminates: on the passing path it is removed without having fired, and
     no assertion below waits on wall-clock time;
   - and the readouts are values diffed against a golden, not pixels read off a
     screenshot.

   {b The one thing assumed about the display} is that the toplevel sits at screen (0,0),
   which is what an Xvfb with no window manager does (Task 16 established it). It is not
   taken on trust: every click is aimed at a point computed from the widget's box and then
   checked against the widget-local coordinates the handler reports, and the "miss" block
   aims 10 px past the target's bottom edge and asserts that nothing fires. A window
   anywhere else fails both. *)

(* ------------------------------------------------------------------ the log *)

(* Handlers append here; each block prints and clears it.

   Three counters rather than one, because each block waits for {i its own} event. A
   single "something fired" counter is not enough: `xdotool keydown ctrl` is a real key
   press, so the ctrl-click block would be woken by [Control_L] reaching the key
   controllers and would print its line before the click it is actually waiting for had
   been delivered. *)
let log : string list ref = ref []
let clicks = ref 0
let keys = ref 0
let focuses = ref 0
let record s = log := s :: !log

let take () =
  let l = List.rev !log in
  log := [];
  l
;;

let show label = printf "%s: (%s)\n" label (String.concat ~sep:" " (take ()))

(* Only the modifiers that are down, by name: [Modifiers.t]'s sexp is six fields wide and
   five of them are [false] on every line here. *)
let mods (m : Modifiers.t) =
  [ "shift", m.shift
  ; "control", m.control
  ; "alt", m.alt
  ; "super", m.super
  ; "hyper", m.hyper
  ; "meta", m.meta
  ]
  |> List.filter_map ~f:(fun (n, b) -> if b then Some n else None)
  |> String.concat ~sep:"+"
  |> function
  | "" -> "none"
  | s -> s
;;

(* Keyvals as names, so the golden says what was pressed rather than which number arrived.
   The X11 keysym of a printable ASCII character is its own code point ([Keyval.of_char]'s
   contract), which is what makes the printable arm exact rather than a guess. *)
let keyval_name k =
  if k = Keyval.escape
  then "Escape"
  else if k = Keyval.tab
  then "Tab"
  else if k = Keyval.return
  then "Return"
  else if k = 0xffe3
  then "Control_L"
  else if k >= 0x20 && k <= 0x7e
  then String.of_char (Char.of_int_exn k)
  else (
    match List.find (List.range 1 13) ~f:(fun n -> Keyval.f n = k) with
    | Some n -> sprintf "F%d" n
    | None -> sprintf "0x%x" k)
;;

(* ------------------------------------------------------------- the main loop *)

(* Pump until [ready ()], and stop the instant it is true.

   Blocking iterations rather than a spin: [Glib.Main.iteration true] returns as soon as
   the X connection has something to read, so a click is serviced when the server delivers
   it rather than after an interval a test author guessed. That is the whole difference
   between this file and the nineteen [sleep]s in the by-hand script it replaces.

   The bound is a GLib timeout source rather than an iteration count, because a
   {i blocking} iteration that never returns cannot be counted out of. It is not a
   settling wait: it fires only when the awaited thing never happens, and the failure it
   produces is a golden diff naming the block that hung. The iteration count under it is a
   second bound, for a loop spinning on a source that is always ready. *)
let watchdog_ms = 10_000

let pump_until ~label ~ready =
  if not (ready ())
  then (
    let expired = ref false in
    let id =
      Glib.Timeout.add
        ~ms:watchdog_ms
        ~callback:(fun () ->
          expired := true;
          false)
        ()
    in
    let iterations = ref 0 in
    while (not (ready ())) && (not !expired) && !iterations < 100_000 do
      ignore (Glib.Main.iteration true : bool);
      incr iterations
    done;
    if not !expired then Glib.Timeout.remove id;
    if not (ready ()) then printf "%s: TIMED OUT\n" label)
;;

(* Everything still queued behind the event that satisfied [pump_until]: GTK's own
   bookkeeping -- a focus change, a redraw -- rides on later iterations, and a block that
   reads a widget back wants them done. Bounded and non-blocking, the [live_embed.ml]
   [drain] shape.

   Note what this is {i not} needed for: a controller in the capture phase and one in the
   bubble phase see the same event inside one [gtk_main_do_event], so a block that waited
   for the capture handler has already had whatever the bubble handler was going to do.
   That is why "Escape did not reach the entry" can be asserted without waiting for
   something that must not happen. *)
let drain () =
  let iterations = ref 0 in
  while Glib.Main.pending () && !iterations < 10_000 do
    ignore (Glib.Main.iteration false : bool);
    incr iterations
  done
;;

(* --------------------------------------------------------------- the driver *)

(* The absolute path of the xdotool the dune rule depends on, taken from argv rather than
   looked up on PATH: the rule names it with [%{bin:xdotool}], so a shell without it fails
   at the rule, naming xdotool, instead of somewhere in here. The by-hand script this
   replaces reached xdotool through a hardcoded /nix/store path and reported its absence
   as "no window". *)
let xdotool_path =
  lazy
    (let argv = Sys.get_argv () in
     if Array.length argv < 2
     then
       failwith
         "live_input: pass the path to xdotool as argv(1). The dune rule supplies it \
          with           %{bin:xdotool}; running this executable by hand needs `$(which \
          xdotool)`."
     else argv.(1))
;;

let devnull = lazy (Unix.openfile "/dev/null" [ Unix.O_WRONLY ] 0o644)

(* xdotool's own stdout is discarded -- [search] prints the window ids it found when it
   ends a chain, and this file's stdout is a golden. Its stderr is left alone, so a real
   failure is still readable beside the diff. *)
let xdotool args =
  let path = force xdotool_path in
  let pid =
    Unix.create_process
      path
      (Array.of_list (path :: args))
      Unix.stdin
      (force devnull)
      Unix.stderr
  in
  match Unix.waitpid [] pid with
  | _, Unix.WEXITED 0 -> ()
  | _, _ ->
    (* Printed rather than raised: a golden diff naming the step is a better failure than
       a backtrace, and the blocks after it still say what did work. *)
    printf "xdotool %s: FAILED\n" (String.concat ~sep:" " args)
;;

(* ------------------------------------------------------------------ the tree *)

(* Unique per process, because [xdotool search --name] matches every window on the display
   and this suite's rules share one. They are serialised by [(locks x-display)] as well;
   the pid is the belt to that suspenders and costs nothing. *)
let title = sprintf "bonsai_gtk live_input %d" (Unix.getpid ())

(* What the click currently in flight was aimed at, in the target's own coordinates, and
   how big that target is. Set by the driver immediately before each click, read by the
   handler: it is what turns "some coordinates arrived" into "the coordinates that arrived
   are the ones this click was aimed at", which is the assertion that makes the widget box
   [box_of] computed and the (0,0) toplevel real rather than assumed. *)
let aim = ref (0., 0.)
let target_size = ref (0., 0.)

let click_line name (e : Click_event.t) =
  let ax, ay = !aim
  and w, h = !target_size in
  sprintf
    "%s button=%d n_press=%d hit-aim=%b in-bounds=%b mods=%s"
    name
    e.button
    e.n_press
    (Float.(abs (e.x -. ax) <= 1.) && Float.(abs (e.y -. ay) <= 1.))
    (* Implied by [hit-aim] for every aim point used today, all of which are fractions
       strictly inside the box; kept as the guard for an aim point that is not. *)
    (Float.(e.x >= 0.) && Float.(e.x < w) && Float.(e.y >= 0.) && Float.(e.y < h))
    (mods e.modifiers)
;;

let on_click_recording name =
  Attr.on_click (fun (e : Click_event.t) ->
    incr clicks;
    record (click_line name e);
    Ui_effect.Ignore)
;;

(* The target's size is requested rather than inherited from its text, for a reason that
   decides the golden: the click points below are fractions of its height, and GTK resets
   a [GtkGestureClick]'s press count only when two presses are more than
   [gtk-double-click-distance] (5 px) apart. A one-line label is about 20 px tall, so its
   quarter-points are inside that distance and the {i second} single click would arrive as
   [n_press = 2]. At 120 px they are 30 px apart and a single click is a single click. *)
let target_attrs name =
  [ Attr.width_request 320
  ; Attr.height_request 120
  ; Attr.halign Align.Start
  ; on_click_recording name
  ]
;;

let entry_attrs name =
  [ Attr.on_focus_enter (fun () ->
      incr focuses;
      record (sprintf "focus-enter %s" name);
      Ui_effect.Ignore)
  ; Attr.on_focus_leave (fun () ->
      incr focuses;
      record (sprintf "focus-leave %s" name);
      Ui_effect.Ignore)
  ]
;;

let view =
  Node.window
    ~title
    ~default_size:(640, 560)
    (Node.box
       ~orientation:Vertical
         (* 40 px of nothing under each child, which is where the "miss" block aims: 10 px
            past the target's bottom edge has to land on a widget with no handler of ours
            for the negative to mean anything. *)
       ~spacing:40
       [ Node.label ~attrs:(target_attrs "label") "click target"
       ; Node.box
           ~orientation:Vertical
           ~spacing:12
           ~attrs:
             [ (* The capture-phase handler, on an {i ancestor} of both entries: capture
                  runs top-down from the toplevel, so this sees a key before either
                  entry's own bubble-phase controller does. Escape is [Handled], which
                  stops the routing dead -- and the entry's controller not firing is the
                  only direct evidence anywhere that [Handled] does what it says.
                  Everything else propagates. *)
               Attr.on_key_pressed ~phase:Capture (fun (e : Key_event.t) ->
                 incr keys;
                 record
                   (sprintf
                      "capture %s mods=%s"
                      (keyval_name e.keyval)
                      (mods e.modifiers));
                 if e.keyval = Keyval.escape then Handled else Propagate)
             ]
           [ Node.entry
               ~attrs:
                 (Attr.on_key_pressed ~phase:Bubble (fun (e : Key_event.t) ->
                    incr keys;
                    record (sprintf "entry1 %s" (keyval_name e.keyval));
                    Propagate)
                  :: entry_attrs "e1")
               ~text:""
               ()
           ; Node.entry ~attrs:(entry_attrs "e2") ~text:"" ()
           ]
         (* A second click target that {i is} a [GtkButton], for one empirical question
            the label cannot answer: a [GtkButton] has a [GtkGestureClick] of its own, and
            a gesture that claims the event sequence cancels every other gesture handling
            it. Whether an [Attr.on_click] on a button still sees the press -- and with
            which [n_press] -- is a fact about GTK that this suite had no way to ask
            before. The golden records the answer; the assertions that have to be exact
            are on the label above. *)
       ; Node.button ~attrs:(target_attrs "button") ~label:"button target" ()
       ])
;;

(* ------------------------------------------------------------------- the run *)

let () = ignore (Ocgtk_gtk.GMain.init () : string array)

let () =
  let scheduler = Scheduler.create ~run_frame:(fun () -> ()) in
  let ctx =
    P.create_ctx
      ~signals:
        { schedule = (fun e -> Ui_effect.Expert.eval e ~f:Fn.id ~on_exn:raise)
        ; in_patch = (fun () -> Scheduler.in_patch scheduler)
        ; on_exn =
            (fun ~node_path exn -> printf "EXN at %s: %s\n" node_path (Exn.to_string exn))
        }
      ~on_window_created:(fun w -> W.Window.present (cast w))
      ()
  in
  let live = P.mount ctx ~path:"root" ~is_root:true view in
  P.run_fixups ctx;
  let window = live.widget in
  let children (l : P.live) =
    match l.children with
    | List l -> List.map l ~f:(fun (c : P.live) -> c)
    | No_children | Single _ | Slots _ -> assert false
  in
  let box =
    match live.children with
    | Single (Some b) -> b
    | No_children | Single None | List _ | Slots _ -> assert false
  in
  let kids = children box in
  let label_target = (List.nth_exn kids 0).widget in
  let button_target = (List.nth_exn kids 2).widget in
  let entries = List.map (children (List.nth_exn kids 1)) ~f:(fun c -> c.widget) in
  let entry1 = List.nth_exn entries 0
  and entry2 = List.nth_exn entries 1 in
  (* A [GtkEntry] never has the focus itself: the focus lands on the [GtkText] it wraps,
     which is why [Attr.on_focus_enter] is documented as firing for a widget
     {i or any of its children} and why [has_focus] on the entry reads [false] throughout. *)
  let focus_in w =
    W.Widget.has_focus w
    ||
    match W.Window.get_focus (cast window) with
    | None -> false
    | Some f -> W.Widget.is_ancestor f w
  in
  (* Mapped, not merely presented: [compute_bounds] answers with the zero rectangle until
     the widget has an allocation, and there is no window for xdotool to find either. *)
  pump_until ~label:"map" ~ready:(fun () -> W.Widget.get_mapped window);
  drain ();
  printf "mapped: %b\n" (W.Widget.get_mapped window);
  (* The rectangle a gesture's coordinates are relative to, in the toplevel's coordinate
     space -- and, since the toplevel is at (0,0), in the screen's.

     That rectangle is the widget's own box: [translate_coordinates] of its (0,0) for the
     origin, [get_width]/[get_height] for the size. [compute_bounds] is the obvious call
     and is the one the design sketch named, and for a plain widget the two agree exactly
     -- the label below reports [bounds-is-box=true]. They do {i not} agree for a themed
     [GtkButton]: measured under this Adwaita, a button allocated 320x120 has a widget box
     of 286x110 inset by (17,5), and [compute_bounds] answers with the whole 320x120,
     which is what its documentation says it does ("the region that it is expected to draw
     in", and CSS draws outside the box). Aiming at the centre of {i that} rectangle lands
     17 px left and 5 px above the centre of the button -- exactly the kind of miss that
     made a working handler look broken in the by-hand run this file replaces. So the aim
     comes from the box and [compute_bounds] is reported beside it, per target, rather
     than trusted.

     The numbers themselves are a function of the theme and the font, so the golden gets
     only the facts that are not. *)
  let box_of w ~name =
    let bounds_ok, r = W.Widget.compute_bounds w window in
    (* Read out of the [graphene_rect_t] before anything else touches ocgtk -- and know
       that this is luck rather than a rule.

       [ml_gtk_widget_compute_bounds] declares a [graphene_rect_t] as a C {i stack local}
       and hands its address to [Val_graphene_rect_t], which is a val_ptr wrapper and does
       not copy. So the OCaml value points into a frame that [CAMLreturn] destroys, and
       every read through it is a read-after-return: undefined behaviour, not a
       stale-but-defined buffer. Reading "immediately" still dereferences the dead frame
       -- each accessor is itself a C call that pushes a frame which may or may not land
       on the same bytes -- so this works by stack layout on this build and is not
       guaranteed by anything. It is a workaround for a bug to be fixed in the generator
       (there are 153 stubs of this shape; see [docs/m2-backlog.md]), not a pattern to
       copy. *)
    let rx = Rect.get_x r
    and ry = Rect.get_y r
    and rw = Rect.get_width r
    and rh = Rect.get_height r in
    let origin_ok, x, y = W.Widget.translate_coordinates w window 0. 0. in
    let bw = Float.of_int (W.Widget.get_width w)
    and bh = Float.of_int (W.Widget.get_height w) in
    printf
      "%s geometry: compute_bounds=%b origin=%b box-positive=%b bounds-is-box=%b\n"
      name
      bounds_ok
      origin_ok
      (Float.(bw > 0.) && Float.(bh > 0.))
      (Float.equal rx x && Float.equal ry y && Float.equal rw bw && Float.equal rh bh);
    x, y, bw, bh
  in
  let lx, ly, lw, lh = box_of label_target ~name:"label" in
  (* The hazard [box_of] works around, asserted rather than only described, because it is
     invisible until a coordinate is wrong and it would break this file first: the
     [graphene_rect_t] that [Widget.compute_bounds] answers with points into a destroyed
     stack frame. Reading a width off it after one more call into the binding gave 0 where
     the widget is 320 wide.

     This line and the [bounds-is-box] fields above it are canaries rather than assertions
     about this library: both are reading undefined behaviour, so both could move on an
     ocgtk rebuild with no change here. Nothing the test actually asserts depends on them
     -- the aim comes from [translate_coordinates] and [get_width]/[get_height], so every
     click, every [hit-aim] and the negative are unaffected -- and in 20 recorded runs
     neither moved. If this line ever prints [true], the generator started copying and the
     comment in [box_of] can go. *)
  let () =
    let (_ : bool), r = W.Widget.compute_bounds label_target window in
    let w0 = Rect.get_width r in
    let (_ : bool * float * float) =
      W.Widget.translate_coordinates label_target window 0. 0.
    in
    printf
      "compute_bounds rect survives a later ocgtk call: %b\n"
      (Float.equal (Rect.get_width r) w0)
  in
  (* A widget-local point, as the screen point to aim at and the local point to expect
     back. Setting [aim] here rather than at each call site is what keeps the two from
     drifting: the handler's [hit-aim] is a comparison against this very computation. *)
  let target ~x ~y ~w ~h fx fy =
    let ax = w *. fx
    and ay = h *. fy in
    aim := ax, ay;
    target_size := w, h;
    Int.of_float (x +. ax), Int.of_float (y +. ay)
  in
  let on_label = target ~x:lx ~y:ly ~w:lw ~h:lh in
  let click ?(button = 1) ?(repeat = 1) ~label (sx, sy) =
    let before = !clicks in
    xdotool
      ([ "mousemove"; Int.to_string sx; Int.to_string sy; "click" ]
       @ (if repeat > 1 then [ "--repeat"; Int.to_string repeat; "--delay"; "80" ] else [])
       @ [ Int.to_string button ]);
    pump_until ~label ~ready:(fun () -> !clicks >= before + repeat);
    drain ()
  in
  (* --- the keyboard needs the input focus, and only XTEST can give it.

     There is no window manager under Xvfb, so `windowactivate` fails and is not needed;
     `windowfocus` is an XSetInputFocus and is what makes the plain `key` commands below
     land here. *)
  xdotool [ "search"; "--onlyvisible"; "--name"; title; "windowfocus" ];
  pump_until ~label:"activate" ~ready:(fun () -> W.Window.is_active (cast window));
  drain ();
  printf "window active: %b\n" (W.Window.is_active (cast window));
  (* GTK gives the focus to the first focusable widget when the toplevel becomes active,
     which is the first entry. Printed rather than suppressed: it is the baseline the
     focus assertions below are differences from. *)
  printf "entry 1 has focus on activation: %b\n" (focus_in entry1);
  show "on activation";
  (* --- buttons 1, 2 and 3, each at its own point so that no two of them are within GTK's
     double-click distance of each other *)
  click ~button:1 ~label:"click1" (on_label 0.25 0.5);
  show "button 1";
  click ~button:2 ~label:"click2" (on_label 0.5 0.5);
  show "button 2";
  click ~button:3 ~label:"click3" (on_label 0.75 0.5);
  show "button 3";
  (* --- a double click: GTK emits the gesture once per press, the second with n_press 2 *)
  click ~button:1 ~repeat:2 ~label:"double" (on_label 0.5 0.2);
  show "double click";
  (* --- ctrl held across a click. The [keydown] is a real key press and reaches the key
     controllers first, which is why the golden line carries it. *)
  let before = !clicks in
  let csx, csy = on_label 0.25 0.8 in
  xdotool [ "keydown"; "ctrl" ];
  xdotool [ "mousemove"; Int.to_string csx; Int.to_string csy; "click"; "1" ];
  xdotool [ "keyup"; "ctrl" ];
  pump_until ~label:"ctrl-click" ~ready:(fun () -> !clicks > before);
  drain ();
  show "ctrl click";
  (* --- the negative: 10 px past the bottom edge moves nothing.

     There is no counter to wait on for a click that must not register, so this does not
     wait for one: it fires the miss, then a click on the target that must register, and
     waits for that. X delivers in order, so by the time the sentinel's handler has run
     the miss has already been routed to whatever it was going to reach. The line carries
     only the sentinel, and a miss that did land would show up in front of it. *)
  let before = !clicks in
  let msx, msy = on_label 0.5 1.0 in
  xdotool [ "mousemove"; Int.to_string msx; Int.to_string (msy + 10); "click"; "1" ];
  let ssx, ssy = on_label 0.75 0.8 in
  xdotool [ "mousemove"; Int.to_string ssx; Int.to_string ssy; "click"; "1" ];
  pump_until ~label:"miss" ~ready:(fun () -> !clicks > before);
  drain ();
  show "10 px below the target, then a sentinel on it";
  (* --- the same click on a [GtkButton], which has a [GtkGestureClick] of its own.

     A gesture that claims the event sequence cancels every other gesture handling it, and
     a button claims on press -- so whether an [Attr.on_click] on a button sees the press
     at all is a fact about GTK this suite had no way to ask before. It does; the golden
     line says so, with the same coordinate and modifier assertions as the label's.

     A button also takes the focus on a click, which is why this block sits here: the
     [focus-leave e1] on its line is the first half of the focus story, and the blocks
     below are the rest of it. *)
  let bx, by, bw, bh = box_of button_target ~name:"button" in
  let on_button = target ~x:bx ~y:by ~w:bw ~h:bh in
  click ~button:1 ~label:"button-click" (on_button 0.5 0.5);
  show "primary click on a GtkButton";
  (* --- focus moves on a click, and the two attrs are two halves of one controller: the
     entry that gains it reports [enter] and the one that loses it reports [leave]. *)
  let click_into w ~name ~expect =
    let before = !focuses in
    let ok, x, y = W.Widget.translate_coordinates w window 0. 0. in
    ignore (ok : bool);
    let sx = Int.of_float (x +. (Float.of_int (W.Widget.get_width w) /. 2.))
    and sy = Int.of_float (y +. (Float.of_int (W.Widget.get_height w) /. 2.)) in
    xdotool [ "mousemove"; Int.to_string sx; Int.to_string sy; "click"; "1" ];
    pump_until ~label:name ~ready:(fun () -> !focuses >= before + expect);
    drain ()
  in
  (* One event: the button holds the focus at this point and carries no focus attrs. *)
  click_into entry2 ~name:"focus-click-e2" ~expect:1;
  show "click into entry 2";
  printf "focus: e1=%b e2=%b\n" (focus_in entry1) (focus_in entry2);
  (* Two: this is the leave-and-enter pair, on a click. *)
  click_into entry1 ~name:"focus-click-e1" ~expect:2;
  show "click back into entry 1";
  printf "focus: e1=%b e2=%b\n" (focus_in entry1) (focus_in entry2);
  (* --- a printable key propagates through the capture handler and into the entry.

     [entry1]'s own bubble-phase controller does not see it, and that is GTK rather than
     this library: the [GtkText] inside a [GtkEntry] consumes a printable key to insert
     it, so the bubble phase never reaches the [GtkEntry] the attr is on. The evidence
     that the key reached the entry is therefore the entry's text -- which is the stronger
     statement anyway, and the reason the block after this one exists. *)
  let key ~name k =
    let before = !keys in
    xdotool [ "key"; "--clearmodifiers"; k ];
    pump_until ~label:name ~ready:(fun () -> !keys > before);
    drain ()
  in
  key ~name:"key-x" "x";
  show "key x";
  printf "entry 1 text after x: %S\n" (W.Editable.get_text (cast entry1));
  (* --- a key the [GtkText] does {i not} consume, which is the control that makes the
     Escape line below mean something: F1 propagates out of the capture handler and
     reaches entry 1's own controller. *)
  key ~name:"key-f1" "F1";
  show "key F1 (capture propagates)";
  (* --- Escape is [Handled] in the capture phase, so the routing stops there: entry 1's
     controller never runs and the entry's text is untouched. This line and the F1 line
     differ in exactly one thing, and that difference is [Key_response.Handled] working.

     No wait is needed for the thing that must not happen: a capture-phase controller and
     a bubble-phase one see the same event inside one [gtk_main_do_event], so by the time
     the capture handler's counter has moved, the bubble handler has already either run or
     been skipped. *)
  key ~name:"key-escape" "Escape";
  show "key Escape (capture handles)";
  printf "entry 1 text after Escape: %S\n" (W.Editable.get_text (cast entry1));
  (* --- and focus moves on Tab as well as on a click *)
  let before = !focuses in
  xdotool [ "key"; "--clearmodifiers"; "Tab" ];
  pump_until ~label:"tab" ~ready:(fun () -> !focuses >= before + 2);
  drain ();
  show "Tab";
  printf "focus after Tab: e1=%b e2=%b\n" (focus_in entry1) (focus_in entry2)
;;
