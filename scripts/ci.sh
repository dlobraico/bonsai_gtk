#!/usr/bin/env bash
# Full local gate. Run inside `nix develop` with the opam switch created
# (./scripts/setup-switch.sh).
set -euo pipefail
cd "$(dirname "$0")/.."
eval "$(opam env --switch=. --set-switch)"

echo "== nix: ocgtk pin builds and passes its tests"
nix build .#ocgtk --no-link

echo "== format"
# Plain `dune fmt` / `dune build @fmt` walks the whole tree, including the
# `result` symlink `nix build` leaves behind (a read-only Nix store path full
# of ocgtk's own generated sources) and reports bogus diffs against it. Check
# each real source directory's `@<dir>/fmt` alias instead; each exits
# non-zero when its files need formatting.
dune build @vtree/fmt @src/fmt @test/fmt @test_lib/fmt @test/live/fmt @examples/fmt

echo "== build"
dune build @all

echo "== pure + headless tests"
dune build @test/runtest

echo "== live tests (xvfb)"
BONSAI_GTK_LIVE_TESTS=1 xvfb-run -a dune build @test/live/runtest

echo "== example smoke"
set +e
xvfb-run -a timeout -k 2 3 dune exec examples/counter.exe
code=$?
set -e
[ "$code" = 124 ] || { echo "counter example exited with $code"; exit 1; }
echo "all green"
