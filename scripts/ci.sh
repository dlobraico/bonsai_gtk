#!/usr/bin/env bash
# Full local gate. Run inside `nix develop` with the opam switch created
# (./scripts/setup-switch.sh).
set -euo pipefail
cd "$(dirname "$0")/.."
# Two lines rather than `eval "$(opam env ...)"`, because `set -e` does not fire
# on a command substitution used as an argument and `eval ""` succeeds: with the
# one-liner, a missing or broken local switch left the gate running against
# whatever OCaml and dune were on PATH inside the dev shell. Usually that fails
# confusingly two lines later; the case worth guarding is a *usable but
# different* switch, where the gate silently certifies against the wrong
# dependency set.
opam_env=$(opam env --switch=. --set-switch)
eval "$opam_env"

# The live rules are enabled by this variable, and they must run only under the
# xvfb line at the bottom. A developer who has been running live tests by hand --
# exactly the developer who has `export BONSAI_GTK_LIVE_TESTS=1` in their shell,
# because `test/live/dune`'s header tells them to type it -- otherwise changes
# what three earlier sections do: `@test/runtest` is recursive and reaches
# `test/live/runtest`, and both `-p` builds reach it too (the `executables` and
# `rule` stanzas in `test/live/dune` name no package, so `--only-packages` does
# not filter them out). The live suites then run inside "pure + headless tests",
# in parallel, and the real live section finds every target up to date and runs
# nothing: a false green that silently deletes the serialisation. On a host with
# no DISPLAY the same leak aborts the gate at that step with "GTK initialization
# failed" reported under the wrong heading. Neutralised here and pinned again on
# each step below, so every line says which it means.
export BONSAI_GTK_LIVE_TESTS=0

echo "== nix: ocgtk pin builds and passes its tests"
nix build .#ocgtk --no-link

echo "== format"
# Plain `dune fmt` / `dune build @fmt` walks the whole tree, including the
# `result` symlink a bare `nix build` leaves behind (a read-only Nix store path
# full of ocgtk's own generated sources) and reports bogus diffs against it.
# This script's own `nix build` passes `--no-link` and creates no such symlink;
# the hazard is a developer who ran `nix build` by hand, which is common enough
# that the aliases below are worth keeping. Check
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
BONSAI_GTK_LIVE_TESTS=0 dune build @test/runtest

# `opam install <pkg> --with-test` runs `dune build -p <pkg> ... @runtest`, which
# is not what the line above does: `--only-packages` hides every library owned by
# another package in this workspace, so a test directory needing one from each
# package builds here and fails there. Both packages are checked, in build
# directories of their own so that the release-mode flags do not invalidate the
# main `_build`.
echo "== per-package builds, the way opam --with-test runs them"
BONSAI_GTK_LIVE_TESTS=0 dune build --build-dir=_build.pkg -p bonsai_gtk @runtest
# bonsai_gtk_test depends on bonsai_gtk, and `-p` hides it -- so it has to come
# from an installed copy, which is what opam does for real.
dune build --build-dir=_build.pkg -p bonsai_gtk @install
prefix=$(mktemp -d)
trap 'rm -rf "$prefix"' EXIT
dune install --build-dir=_build.pkg --prefix "$prefix" --libdir "$prefix/lib" \
  bonsai_gtk >/dev/null
OCAMLPATH="$prefix/lib${OCAMLPATH:+:$OCAMLPATH}" BONSAI_GTK_LIVE_TESTS=0 \
  dune build --build-dir=_build.pkgtest -p bonsai_gtk_test @runtest

echo "== live tests (xvfb)"
# The serialisation these need lives on the rules now, as `(locks x-display)` in
# `test/live/dune` -- see that file's header for the measurements and for why
# thirteen of the sixteen rules carry it. It used to be a `-j 1` on this line, which
# protected this line and nothing else: `dune test`, an editor's run-tests
# action, and the leaked-environment path this script now closes above all
# reached the same rules unserialised.
#
# The `rm` is load-bearing too. Each of these rules declares a target, so dune
# will not re-run one whose dependencies are unchanged -- and `--force` does not
# either. That is sound for an ordinary rule and wrong for these five: their
# goldens include wall-clock *ratios*, which are not a function of their deps, so
# the caching is asymmetric in the worst direction -- a run that got lucky stays
# green until an executable changes, while a red is re-run every time. It also
# means a second `ci.sh` in the same tree exercised the live suite not at all
# (4 s, zero bench lines, and a green section), which is exactly the state anyone
# investigating a flaky bench would be in.
rm -f _build/default/test/live/output_*.txt
BONSAI_GTK_LIVE_TESTS=1 xvfb-run -a dune build @test/live/runtest

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
  # came up and stayed up looks like. Anything else means it fell over. Note what
  # this does *not* say: a main loop that came up and then deadlocked satisfies it
  # too. It is a "did not crash on startup" check, not a liveness assertion.
  [ "$code" = 124 ] || { echo "$ex example exited with $code"; exit 1; }
done
echo "all green"
