{
  description = "bonsai_gtk — build GTK4 desktop apps with Bonsai (OCaml)";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs = { self, nixpkgs, flake-utils }:
    flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = nixpkgs.legacyPackages.${system};
        ocamlPackages = pkgs.ocamlPackages;
        pin = builtins.fromJSON (builtins.readFile ./ocgtk-pin.json);

        gtkStack = with pkgs; [ gtk4 glib graphene pango cairo gdk-pixbuf ];

        # ocgtk at the pinned fork commit, built with stock nixpkgs OCaml.
        # Not a dependency of the OxCaml build (that comes from the opam pin);
        # this is the hermetic proof that the pin builds and its own GC
        # regression tests pass.
        ocgtkSrc = pkgs.fetchFromGitHub {
          owner = pin.owner;
          repo = pin.repo;
          rev = pin.rev;
          hash = pin.hash;
        };
        ocgtk = ocamlPackages.buildDunePackage {
          pname = "ocgtk";
          version = "0.1-preview2-${builtins.substring 0 7 pin.rev}";
          src = ocgtkSrc;
          sourceRoot = "${ocgtkSrc.name}/ocgtk";
          # The upstream repo root (one level above sourceRoot) has its own
          # dune-workspace file. `dune install` (run by the default
          # installPhase with --docdir/--mandir) walks up past the ocgtk/
          # dune-project boundary, finds that sibling dune-workspace, and
          # then expects the install file at a path namespaced by the
          # subdirectory (_build/default/ocgtk/ocgtk.install) instead of
          # _build/default/ocgtk.install. Removing the stray file makes
          # ocgtk/ unambiguously the workspace root.
          postUnpack = ''
            chmod u+w "$(dirname "$sourceRoot")"
            rm -f "$(dirname "$sourceRoot")/dune-workspace"
          '';
          nativeBuildInputs = [ pkgs.pkg-config ];
          buildInputs = [ ocamlPackages.dune-configurator ];
          propagatedBuildInputs = gtkStack;
          doCheck = true;
          checkInputs = [ ocamlPackages.alcotest ];
          nativeCheckInputs = [ pkgs.xvfb-run ];
          checkPhase = ''
            runHook preCheck
            xvfb-run -a dune runtest -p ocgtk -j $NIX_BUILD_CORES
            runHook postCheck
          '';
        };
      in {
        packages = { inherit ocgtk; default = ocgtk; };
        checks = { inherit ocgtk; };

        # Stock-OCaml shell for working on the ocgtk fork checkout
        # (~/src/ocgtk): dune build / dune runtest inside its ocgtk/ dir.
        devShells.ocgtk = pkgs.mkShell {
          nativeBuildInputs = [ pkgs.pkg-config ];
          buildInputs = gtkStack ++ [ pkgs.xvfb-run ] ++ (with ocamlPackages; [
            ocaml dune_3 findlib dune-configurator alcotest
          ]);
        };

        # OxCaml shell: opam owns the compiler and libraries (./_opam).
        devShells.default = pkgs.mkShell {
          nativeBuildInputs = with pkgs; [
            # xdotool drives real X input events (XTEST) at the X server that
            # `xvfb-run` starts, which is what `test/live/live_input.ml` uses to
            # deliver a button press and a keystroke GTK cannot tell from a
            # human's. It has to be here rather than found on the host: the
            # by-hand Task 16 script reached it through a hardcoded /nix/store
            # path that is not a GC root, and a missing binary surfaced there as
            # "no window" rather than as "no xdotool".
            opam pkg-config gnumake gcc autoconf git jq xvfb-run xdotool
          ];
          # gmp: conf-gmp (a dependency of zarith, pulled in transitively by
          # js_of_ocaml <- bonsai) probes via `pkg-config --exists gmp`
          # during `opam install`; without it in the shell that check fails
          # and takes the whole opam install transaction down with it.
          buildInputs = gtkStack ++ [ pkgs.gobject-introspection pkgs.gmp ];
          shellHook = ''
            if [ -d "$PWD/_opam" ]; then
              eval "$(opam env --switch=. --set-switch 2>/dev/null || true)"
            else
              echo "No ./_opam switch yet: run ./scripts/setup-switch.sh"
            fi
          '';
        };
      });
}
