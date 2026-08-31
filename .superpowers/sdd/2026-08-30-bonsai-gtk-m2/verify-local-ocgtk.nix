# Build bonsai_gtk's *own* ocgtk derivation -- same buildDunePackage, same
# xvfb-run checkPhase, same nix sandbox -- but from a local tree instead of
# fetchFromGitHub, so a fork commit can be verified hermetically before it is
# pushed and the pin moved.
let
  flake = builtins.getFlake "path:/home/dlobraico/src/bonsai_gtk";
  system = builtins.currentSystem;
  base = flake.packages.${system}.ocgtk;
in
base.overrideAttrs (_: {
  src = /tmp/ocgtk-verify/source;
  sourceRoot = "source/ocgtk";
})
