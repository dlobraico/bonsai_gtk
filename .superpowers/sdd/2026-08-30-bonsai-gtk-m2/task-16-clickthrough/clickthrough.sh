#!/usr/bin/env bash
# Task 16 Step 4, adapted: the gallery's Input page driven by real X input events
# (XTEST via xdotool) under Xvfb, with ImageMagick screenshots of the readouts
# before and after each step. No real display is available on this host, so this
# is the closest honest substitute: the events are delivered by the X server to
# GTK exactly as a mouse and keyboard would, not synthesised inside the process.
set -euo pipefail
SHOTS="$1"
# `xdotool` and ImageMagick used to be reached here through hardcoded /nix/store
# paths, which are not GC roots: one `nix-collect-garbage` and this script fails,
# and it fails *misleadingly*, because the `xdotool search` below is guarded by
# `|| true` and a missing binary surfaces as "no window". `xdotool` is now in the
# devShell (`flake.nix`), so run this under `nix develop`; ImageMagick is only
# for the human-facing screenshots and is not needed by the test that replaced
# this script (`test/live/live_input.ml`).
command -v xdotool >/dev/null || {
  echo "xdotool not on PATH: run this under \`nix develop\` (flake.nix devShell)"; exit 1; }
# ImageMagick is deliberately NOT in the devShell -- it is only for the screenshots these
# scripts take for a human, and the test that replaced them
# (test/live/live_input.ml) reads values instead. So it has to come from somewhere on the
# host, and this says so rather than pointing at a shell that does not provide it.
for prog in import magick; do
  command -v "$prog" >/dev/null || {
    echo "$prog (ImageMagick) not on PATH; it is not in the devShell -- install it or add"
    echo "pkgs.imagemagick to flake.nix if you want these screenshots"; exit 1; }
done
cd /home/dlobraico/src/bonsai_gtk

shot () { import -window root "$SHOTS/$1.png"; echo "shot $1"; }
# The readout block, cropped so a diff between two shots is about the readouts
# and nothing else. x=150 y=240 w=700 h=95 covers the four lines.
crop () { magick "$SHOTS/$1.png" -crop 700x95+150+240 +repage "$SHOTS/$1-readouts.png"; }

./_build/default/examples/gallery.exe &
APP=$!
trap 'kill $APP 2>/dev/null || true' EXIT
for i in $(seq 1 60); do
  WID=$(xdotool search --onlyvisible --name "bonsai_gtk gallery" 2>/dev/null | head -1) || true
  [ -n "${WID:-}" ] && break
  sleep 0.5
done
[ -n "${WID:-}" ] || { echo "no window"; exit 1; }
echo "WID=$WID"
xdotool windowfocus "$WID"; sleep 1

# 1. navigate to the Input page by clicking its stack-sidebar row
xdotool mousemove 36 288 click 1; sleep 1.5
shot 10-input-before; crop 10-input-before

# 2. primary click on the "click me" card
xdotool mousemove 680 146 click 1; sleep 1.0
shot 11-after-left-click; crop 11-after-left-click

# 3. secondary click, same card: ~button defaults to 0 ("any"), so the readout
#    should report button 3, which a GtkButton would never see
xdotool mousemove 700 160 click 3; sleep 1.0
shot 12-after-right-click; crop 12-after-right-click

# 4. double click: n_press should reach 2
xdotool mousemove 660 130 click --repeat 2 --delay 80 1; sleep 1.0
shot 13-after-double-click; crop 13-after-double-click

# 5. focus the first entry by clicking it
xdotool mousemove 415 208 click 1; sleep 1.0
shot 14-after-focus-entry; crop 14-after-focus-entry

# 6. type into it -- every keystroke goes through the capture-phase key handler
xdotool type --delay 120 "hello"; sleep 1.0
shot 15-after-typing; crop 15-after-typing

# 7. Escape: consumed in the capture phase, so the escapes counter moves, the
#    "last key" line names it, and the entry keeps its text
xdotool key --clearmodifiers Escape; sleep 1.0
shot 16-after-escape; crop 16-after-escape

# 8. Ctrl+Shift+a: the modifiers should show up in the "last key" readout
xdotool key --clearmodifiers ctrl+shift+a; sleep 1.0
shot 17-after-ctrl-shift-a; crop 17-after-ctrl-shift-a

# 9. Tab to the second entry: focus_leave then focus_enter
xdotool key --clearmodifiers Tab; sleep 1.0
shot 18-after-tab; crop 18-after-tab

echo "CLICKTHROUGH_OK"
