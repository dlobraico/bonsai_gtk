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

# Path pin (opam rsyncs the directory), so the checkout must exist locally.
if [ ! -d .ocgtk-src/.git ]; then
  git clone "https://github.com/$owner/$repo.git" .ocgtk-src
fi
git -C .ocgtk-src fetch -q origin
git -C .ocgtk-src checkout -q "$rev"

opam pin add -y -n ocgtk ./.ocgtk-src/ocgtk
opam install -y --assume-depexts \
  ocgtk \
  bonsai bonsai_test \
  core ppx_jane virtual_dom \
  dune ocamlformat ocaml-lsp-server

echo "Switch ready. In a shell: eval \$(opam env --switch=. --set-switch)"
