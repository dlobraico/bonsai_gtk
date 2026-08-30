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
# `HEAD` rather than the bare form: without it the check compares the index, so an
# .opam file that was regenerated and then `git add`ed but not committed reads as clean.
git diff --exit-code HEAD -- '*.opam'

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
# `-j 1` is load-bearing, not caution. One `xvfb-run` wraps the whole dune
# invocation, so all eleven live executables share a single X display, and dune
# runs them in parallel -- `live_text` alone takes 25 s of the section's 29, so
# it overlaps every other test in the directory. Each of them presents a real
# toplevel, and a window mapping on an X display takes the input focus off
# whichever window held it. `live_controllers.ml`'s focus block sees that as a
# `focus-leave` arriving before the `grab_focus` that is supposed to cause it,
# and reports it as a golden diff that looks exactly like a regression in the
# focus controller, which is the expensive part.
#
# Measured, because the failure is rare enough to be dismissed as noise: 1 fail
# in 10 parallel runs of this alias, 0 in 15 serial ones, 0 in 15 solo runs of
# `live_controllers.exe` alone, and 2 in 8 when other toplevels are deliberately
# mapped on the display throughout the test. (Note for anyone re-measuring:
# `--force` does NOT re-run these rules, because each declares a target --
# delete `_build/default/test/live/output_*.txt` between runs instead, or a loop
# of "passes" will be measuring nothing at all.)
#
# Serialising costs 2 s of 29 (28.6 s -> 30.8 s) on a warm tree -- which this
# is, since `dune build @all` above has already built the executables -- because
# one test dominates the section either way. Two alternatives are on the backlog
# rather than here: an `xvfb-run` per rule (eleven displays, but it adds
# `xvfb-run -a`'s own race for a free display number), and `(locks x-display)` on
# the eleven rules, which is dune's own answer to "these must not run at once"
# and binds the constraint to the rules rather than to this one flag on this one
# call site. The second is probably the right end state; it is a change to eleven
# rules with no review round behind it, which is not a thing a CI pass should
# decide on its own.
BONSAI_GTK_LIVE_TESTS=1 xvfb-run -a dune build @test/live/runtest -j 1

echo "== example smoke"
# Built first, and run out of `_build` rather than through `dune exec`: the
# three-second budget has to cover the run alone. `dune exec` would spend it on
# the build as well, and a cold cache or a contended dune lock would have
# `timeout` kill the compiler at 124 -- which the check below would read as "the
# window came up and stayed up".
dune build examples/counter.exe examples/gallery.exe examples/embed.exe
for ex in counter gallery embed; do
  set +e
  xvfb-run -a timeout -k 2 3 "_build/default/examples/$ex.exe"
  code=$?
  set -e
  # 124 is timeout's "still running when time ran out", which is what a GUI that
  # came up and stayed up looks like. Anything else means it fell over.
  [ "$code" = 124 ] || { echo "$ex example exited with $code"; exit 1; }
done
echo "all green"
