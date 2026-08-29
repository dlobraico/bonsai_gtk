#!/usr/bin/env bash
# Creates the local OxCaml opam switch in ./_opam and installs bonsai_gtk's
# dependencies, pinning ocgtk to the fork commit in ocgtk-pin.json.
# Run inside `nix develop` (needs opam, pkg-config, gtk4, jq).
set -euo pipefail
cd "$(dirname "$0")/.."

OX_REPO="git+https://github.com/oxcaml/opam-repository.git"
COMPILER="ocaml-variants.5.2.0+ox"

if [ ! -d _opam ]; then
  # --assume-depexts: opam's system-package detection doesn't recognize
  # NixOS (no dpkg/rpm/apk database), so it always reports build tools like
  # autoconf as "missing" even when nix develop has put them on PATH. This
  # tells opam to trust that they're present rather than blocking on an
  # interactive prompt (or defaulting to abort under a non-interactive
  # stdin, per opam's own suggested workaround in that prompt's message).
  opam switch create . --no-install --assume-depexts \
    --repos "ox=$OX_REPO,default" \
    --packages "$COMPILER"
fi
eval "$(opam env --switch=. --set-switch)"

owner=$(jq -r .owner ocgtk-pin.json)
repo=$(jq -r .repo ocgtk-pin.json)
rev=$(jq -r .rev ocgtk-pin.json)

url="https://github.com/$owner/$repo.git"

# Path pin (opam rsyncs the directory), so the checkout must exist locally. An existing
# checkout of a *different* fork is discarded rather than fetched into: `owner`/`repo` are
# part of the pin record, so a stale remote would silently resolve `rev` against the wrong
# history (or fail to find it at all).
if [ -d .ocgtk-src/.git ] &&
   [ "$(git -C .ocgtk-src remote get-url origin 2>/dev/null)" != "$url" ]; then
  echo "ocgtk checkout points at a different remote; re-cloning $url" >&2
  rm -rf .ocgtk-src
fi
if [ ! -d .ocgtk-src/.git ]; then
  git clone "$url" .ocgtk-src
fi
git -C .ocgtk-src fetch -q origin
git -C .ocgtk-src checkout -q "$rev"

# The whole point of ocgtk-pin.json is that one commit reaches both Nix and opam, so a
# checkout that is not at that commit must stop the script rather than build something
# nobody recorded.
head=$(git -C .ocgtk-src rev-parse HEAD)
if [ "$head" != "$rev" ]; then
  echo "ocgtk checkout is at $head, expected $rev (from ocgtk-pin.json)" >&2
  exit 1
fi

opam pin add -y -n --assume-depexts ocgtk ./.ocgtk-src/ocgtk

# opam 2.5 re-syncs a directory pin's sources but does not schedule a rebuild for them:
# `opam pin add` (with or without `-n`), `opam install` and `opam upgrade` all report
# "Nothing to do" for an already-installed ocgtk even after the checkout has moved. So
# bumping `rev` would update .ocgtk-src and silently leave the *old* ocgtk in ./_opam --
# which shows up as GC crashes at runtime rather than as a build error. This script
# therefore tracks the built commit itself and forces the reinstall when it moves.
stamp=_opam/.opam-switch/bonsai-gtk-ocgtk-rev
if [ -n "$(opam list --installed --short ocgtk)" ] &&
   [ "$(cat "$stamp" 2>/dev/null || true)" != "$rev" ]; then
  echo "ocgtk in ./_opam was not built from $rev; reinstalling"
  opam reinstall -y --assume-depexts ocgtk
fi

opam install -y --assume-depexts \
  ocgtk \
  bonsai bonsai_test \
  core ppx_jane virtual_dom \
  dune ocamlformat ocaml-lsp-server

# Only after a successful install: a stamp written earlier would make a failed run look
# up to date on the next one.
echo "$rev" > "$stamp"

echo "Switch ready. In a shell: eval \$(opam env --switch=. --set-switch)"
