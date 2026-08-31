#!/usr/bin/env bash
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
shot () { import -window root "$SHOTS/$1.png"; magick "$SHOTS/$1.png" -crop 700x95+150+240 +repage "$SHOTS/$1-readouts.png"; echo "shot $1"; }
./_build/default/examples/gallery.exe &
APP=$!
trap 'kill $APP 2>/dev/null || true' EXIT
for i in $(seq 1 60); do
  WID=$(xdotool search --onlyvisible --name "bonsai_gtk gallery" 2>/dev/null | head -1) || true
  [ -n "${WID:-}" ] && break
  sleep 0.5
done
xdotool windowfocus "$WID"; sleep 1
xdotool mousemove 36 288 click 1; sleep 1.5
shot 20-input-before
# every click now on the same point the primary click proved is inside the label
xdotool mousemove 680 146 click 3; sleep 1.0
shot 21-right-click-on-target
xdotool mousemove 680 146 click 2; sleep 1.0
shot 22-middle-click-on-target
xdotool mousemove 680 146 click --repeat 2 --delay 60 1; sleep 1.0
shot 23-double-click-on-target
# and a click deliberately 14px below the text baseline, to show where the
# label's allocation ends
xdotool mousemove 680 160 click 1; sleep 1.0
shot 24-click-below-label
# ctrl-held primary click, for the modifiers half of Click_event
xdotool keydown ctrl; xdotool mousemove 680 146 click 1; xdotool keyup ctrl; sleep 1.0
shot 25-ctrl-click
echo "PASS2_OK"
