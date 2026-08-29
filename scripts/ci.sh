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
# The root `dune` and `dune-project` are not covered by any of those aliases
# (they belong to the root directory, whose `@fmt` alias is the one that walks
# `result/`). `dune format-dune-file` is the same formatter the alias runs.
for f in dune dune-project; do
  dune format-dune-file "$f" | diff -u "$f" - || {
    echo "$f needs formatting"; exit 1;
  }
done

echo "== build"
dune build @all

# `generate_opam_files true` rewrites the .opam files during the build, so a
# dune-project edit committed without its regenerated .opam would otherwise
# leave CI green and the tree dirty.
echo "== generated opam files are committed"
git diff --exit-code -- '*.opam'

echo "== pure + headless tests"
dune build @test/runtest

# `opam install <pkg> --with-test` runs `dune build -p <pkg> ... @runtest`, which
# is not what the line above does: `--only-packages` hides every library owned by
# another package in this workspace, so a test directory needing one from each
# package builds here and fails there. Both packages are checked, in build
# directories of their own so that the release-mode flags do not invalidate the
# main `_build`.
echo "== per-package builds, the way opam --with-test runs them"
dune build --build-dir=_build.pkg -p bonsai_gtk @runtest
# bonsai_gtk_test depends on bonsai_gtk, and `-p` hides it -- so it has to come
# from an installed copy, which is what opam does for real.
dune build --build-dir=_build.pkg -p bonsai_gtk @install
prefix=$(mktemp -d)
trap 'rm -rf "$prefix"' EXIT
dune install --build-dir=_build.pkg --prefix "$prefix" --libdir "$prefix/lib" \
  bonsai_gtk >/dev/null
OCAMLPATH="$prefix/lib${OCAMLPATH:+:$OCAMLPATH}" \
  dune build --build-dir=_build.pkgtest -p bonsai_gtk_test @runtest

echo "== live tests (xvfb)"
BONSAI_GTK_LIVE_TESTS=1 xvfb-run -a dune build @test/live/runtest

echo "== example smoke"
# Built first, and run out of `_build` rather than through `dune exec`: the
# three-second budget has to cover the run alone. `dune exec` would spend it on
# the build as well, and a cold cache or a contended dune lock would have
# `timeout` kill the compiler at 124 -- which the check below would read as "the
# window came up and stayed up".
dune build examples/counter.exe examples/gallery.exe
for ex in counter gallery; do
  set +e
  xvfb-run -a timeout -k 2 3 "_build/default/examples/$ex.exe"
  code=$?
  set -e
  # 124 is timeout's "still running when time ran out", which is what a GUI that
  # came up and stayed up looks like. Anything else means it fell over.
  [ "$code" = 124 ] || { echo "$ex example exited with $code"; exit 1; }
done
echo "all green"
