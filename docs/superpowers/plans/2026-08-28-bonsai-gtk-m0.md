# bonsai_gtk M0 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Stand up the `bonsai_gtk` repository end to end — Nix dev environment, OxCaml opam switch, a forked-and-patched ocgtk pin, the ocgtk-free virtual widget tree with its reconciler and headless test handle, and a runtime that renders a Bonsai counter app (Window/Box/Label/Button) in a real GTK4 window.

**Architecture:** Two dune libraries. `bonsai_gtk.vtree` (dir `vtree/`) is pure OCaml: `Node`/`Attr`/`Attrs`/`Kind`/`Children`/`Key`/`Native`/`Reconcile`, fully expect-testable. `bonsai_gtk` (dir `src/`) depends on `vtree` + ocgtk and owns the shadow tree (`Patcher`), signal trampolines (`Signals`), per-widget impls (`src/widgets/`), and the GLib-driven frame loop (`Scheduler`/`Driver`/`Loop`). `bonsai_gtk_test` (dir `test_lib/`) is an ocgtk-free `Bonsai_test.Result_spec` over `Node.t`. ocgtk is consumed from a fork (`dlobraico/ocgtk`, branch `bonsai-gtk`) that carries stavekeeper's fixes as themed commits headed upstream.

**Tech Stack:** OxCaml `ocaml-variants.5.2.0+ox`, dune ≥ 3.17, Bonsai `v0.18~preview.130.106+341` (Cont API), `bonsai.driver`, `bonsai_test`, `virtual_dom.ui_effect`, ocgtk 0.1~preview2 (GTK 4.22, fork pin), Nix flake (nixpkgs unstable) for the dev shell and the ocgtk sanity package, `xvfb-run` for live tests.

**Spec:** `docs/superpowers/specs/2026-08-28-bonsai-gtk-design.md`

## Global Constraints

- OxCaml only: `ocaml-variants.5.2.0+ox` from `ox=git+https://github.com/oxcaml/opam-repository.git` plus `default`. Bonsai `v0.18~preview.130.106+341`. Not buildable on stock OCaml; the flake never builds `bonsai_gtk` itself.
- ocgtk pin is a commit on `dlobraico/ocgtk` branch `bonsai-gtk`, based on upstream `40ab0b6b4c6ae98bfc79c390c4164a6c72508726`. One pin record, `ocgtk-pin.json`, read by both `flake.nix` and `scripts/setup-switch.sh`.
- GLib main loop only. No Async anywhere in `bonsai_gtk`.
- The runtime uses ocgtk **Layer 1** (`Ocgtk_gtk.Gtk.Wrappers.*`) exclusively. Never `open Ocgtk_gtk.Gtk` (it shadows `unit`).
- No `ppx_inline_test`/`ppx_expect` in any library that depends on ocgtk (`src/`, `test/live/`). Only `vtree/`, `test_lib/`, `test/` use ppx_expect.
- Every signal trampoline is exception-guarded; no exception may cross into C.
- `.ocamlformat` is `profile=janestreet`; run `dune fmt` before each commit.
- Commit messages end with the Co-Authored-By / Claude-Session trailer used by this session's tooling (see "Commit trailer" below).
- Widget kinds in M0: `Label`, `Button`, `Box`, `Window`, `Native`. Attrs in M0: `css_class`, `margin_*`, `halign`, `valign`, `hexpand`, `vexpand`, `sensitive`, `visible`, `tooltip`, `width_request`, `height_request`, `test_id`, `on_clicked`. Root must be a single `Node.window` (`Node.windows` is M3).

**Commit trailer** (append to every commit body):

```
Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01Xg8Viv7XX6YLdVMuT4Gffm
```

Use `GIT_EDITOR=true git commit -F -` with a heredoc; plain `git commit -m` hung once in this environment.

**Reference sources** (already unpacked in the session scratchpad; re-fetch if missing):
- Bonsai v0.18: `https://github.com/janestreet/bonsai/archive/51347bc8121aa8f07f751ed77e351a3d923ef20e.tar.gz` — `src/cont.mli` (public API), `src/driver/bonsai_driver.mli`.
- bonsai_test: `https://github.com/janestreet/bonsai_test/archive/63f73007dd003b9af9c826c6522bfa9830e48929.tar.gz` — `proc.mli` (`Result_spec`, `Handle`).
- bonsai_concrete (`Ui_time_source`): `https://github.com/janestreet/bonsai_concrete/archive/645a7cfb859ec768b80b5b4ecc9973cf33383df6.tar.gz`.
- ocgtk upstream: `https://github.com/chris-armstrong/ocgtk` at `40ab0b6`; stavekeeper's patched copy: `~/src/stavekeeper/vendor/ocgtk`.

## File structure

```
flake.nix, flake.lock          dev shells (default = OxCaml/opam; ocgtk = stock OCaml for fork work), packages.ocgtk
ocgtk-pin.json                 {owner, repo, rev, hash}
dune-project                   packages bonsai_gtk, bonsai_gtk_test
.ocamlformat, .gitignore, README.md
scripts/setup-switch.sh        create ./_opam, pin ocgtk from ocgtk-pin.json, install deps
scripts/ci.sh                  fmt check, build, runtest, live tests under xvfb
vtree/dune                     (library (name bonsai_gtk_vtree) (public_name bonsai_gtk.vtree))
vtree/key.ml(i)                Key.t = string
vtree/orientation.ml           Horizontal | Vertical
vtree/align.ml                 Fill | Start | End | Center | Baseline
vtree/handler.ml(i)            'a Handler.t = 'a -> unit Ui_effect.t (sexp <handler>, phys equality)
vtree/attr.ml(i)               Attr.t variant + Attr.Name.t + constructors
vtree/attrs.ml(i)              merged map, css classes, diff ops
vtree/native.ml(i)             extensible payload
vtree/kind.ml(i)               widget kinds with typed props
vtree/children.ml(i)           No_children | Single | List
vtree/node.ml(i)               Node.t + constructors + find_by_test_id
vtree/reconcile.ml(i)          keyed list diff
vtree/bonsai_gtk_vtree.ml      re-exports
test/dune, test/test_attrs.ml, test/test_node.ml, test/test_reconcile.ml, test/test_handle.ml
test_lib/dune                  (library (name bonsai_gtk_test) (public_name bonsai_gtk_test))
test_lib/bonsai_gtk_test.ml(i) Action, Result_spec, Handle re-export
src/dune                       (library (name bonsai_gtk) (public_name bonsai_gtk))
src/gtk_import.ml              aliases: Gtk, W (=Wrappers), Widget, cast
src/attr_apply.ml(i)           Attrs.op -> live widget
src/signals.ml(i)              ctx, slots, trampolines
src/widget_impl.ml(i)          per-kind impl record + child ops
src/widgets/label.ml, button.ml, box.ml, window.ml, registry.ml
src/patcher.ml(i)              live tree: mount / patch / destroy
src/debug.ml(i)                dump_live_tree
src/scheduler.ml(i)            request_frame, tick, in_patch
src/driver.ml(i)               Bonsai_driver + Patcher + Scheduler
src/loop.ml(i)                 GtkApplication lifecycle; start
src/effect.ml(i)               Ui_effect + quit
src/bonsai_gtk.ml(i)           public API
test/live/dune, test/live/live_patcher.ml, expected_patcher.txt, live_driver.ml, expected_driver.txt
examples/dune, examples/counter.ml
docs/upstream/                 PR drafts for the ocgtk fixes
```

---

### Task 1: Repository scaffold, Nix flake, dune project

**Files:**
- Create: `flake.nix`, `ocgtk-pin.json`, `dune-project`, `.ocamlformat`, `.gitignore`, `README.md`, `dune` (root, excludes `.ocgtk-src`)

**Interfaces:**
- Produces: `nix develop` (OxCaml shell: opam, pkg-config, GTK4 stack, xvfb-run, jq, git), `nix develop .#ocgtk` (stock OCaml + alcotest, for fork work), `nix build .#ocgtk`, `ocgtk-pin.json` schema `{ "owner": string, "repo": string, "rev": string, "hash": string }`.

- [ ] **Step 1: Write `ocgtk-pin.json` pointing at upstream for now** (Task 3 moves it to the fork)

```json
{
  "owner": "chris-armstrong",
  "repo": "ocgtk",
  "rev": "40ab0b6b4c6ae98bfc79c390c4164a6c72508726",
  "hash": ""
}
```

- [ ] **Step 2: Write `flake.nix`**

```nix
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
            opam pkg-config gnumake gcc autoconf git jq xvfb-run
          ];
          buildInputs = gtkStack ++ [ pkgs.gobject-introspection ];
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
```

- [ ] **Step 3: Write `dune-project`**

```lisp
(lang dune 3.17)
(name bonsai_gtk)
(generate_opam_files true)
(source (github dlobraico/bonsai_gtk))
(license MIT)
(authors "Dominick LoBraico")
(maintainers "Dominick LoBraico")

(package
 (name bonsai_gtk)
 (synopsis "Build GTK4 desktop applications with Bonsai")
 (depends
  (ocaml (>= 5.2.0))
  (dune (>= 3.17))
  bonsai
  core
  ppx_jane
  virtual_dom
  ocgtk))

(package
 (name bonsai_gtk_test)
 (synopsis "Headless test handle for bonsai_gtk apps")
 (depends
  (bonsai_gtk (= :version))
  bonsai_test
  ppx_expect))
```

- [ ] **Step 4: Write `.ocamlformat`, `.gitignore`, root `dune`, `README.md`**

`.ocamlformat`:
```
profile=janestreet
```

`.gitignore`:
```
_build/
_opam/
.ocgtk-src/
result
result-*
.direnv/
*.install
```

Root `dune` (keeps the pinned ocgtk checkout out of the workspace):
```lisp
(dirs :standard \ .ocgtk-src)
```

`README.md` — short, will grow in Task 12:
```markdown
# bonsai_gtk

Build GTK4 desktop applications with [Bonsai](https://github.com/janestreet/bonsai), in the
spirit of `bonsai_web` and `bonsai_term`. Status: pre-alpha (M0).

## Development

    nix develop                 # dev shell (GTK4 stack, opam, xvfb)
    ./scripts/setup-switch.sh   # once: creates ./_opam (OxCaml) and pins ocgtk
    dune build && dune runtest

See `docs/superpowers/specs/2026-08-28-bonsai-gtk-design.md` for the design.
```

- [ ] **Step 5: Get the ocgtk source hash and fill it in**

Run: `nix flake lock` then `nix build .#ocgtk 2>&1 | grep -A2 'hash mismatch'` — copy the `got: sha256-...` value into `ocgtk-pin.json` `hash`. Re-run `nix build .#ocgtk`.
Expected: builds and its alcotest suite passes under xvfb. If a test fails at upstream `40ab0b6`, record which in the commit message; Task 3 re-verifies at the fork commit where the GC fixes exist.

- [ ] **Step 6: Verify both shells**

Run: `nix develop -c sh -c 'opam --version && pkg-config --modversion gtk4 && xvfb-run --help >/dev/null && echo ok'`
Expected: prints opam version, `4.22.x`, `ok`.
Run: `nix develop .#ocgtk -c sh -c 'ocaml -version && dune --version'`
Expected: stock OCaml (5.x) and dune 3.x.

- [ ] **Step 7: Commit**

```bash
git add flake.nix flake.lock ocgtk-pin.json dune-project .ocamlformat .gitignore dune README.md
GIT_EDITOR=true git commit -F - <<'MSG'
Scaffold repo: flake (OxCaml + ocgtk shells, ocgtk package), dune-project

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01Xg8Viv7XX6YLdVMuT4Gffm
MSG
```

---

### Task 2: Fork ocgtk and rebuild stavekeeper's fixes as themed commits

**Files:**
- Create (outside this repo): `~/src/ocgtk` — clone of the fork `dlobraico/ocgtk`, branch `bonsai-gtk` from `40ab0b6`.
- Create: `docs/upstream/README.md` (in bonsai_gtk) — index of the themed commits and their upstream status.

**Interfaces:**
- Consumes: stavekeeper's patched tree `~/src/stavekeeper/vendor/ocgtk` (no git history of its own; compare by `diff -ru`).
- Produces: branch `bonsai-gtk` on `github.com/dlobraico/ocgtk` whose head commit is the pin for Task 3; each commit builds and passes `dune runtest` in `nix develop .#ocgtk`.

The diff (upstream `40ab0b6` → stavekeeper vendored) touches ~50 files / ~840 lines. Group into these commits, in this order (later ones may depend on earlier):

| # | Theme | Files (relative to repo root) |
|---|---|---|
| 1 | `common: box the GValue* in closure marshal so the GC never scans a naked C pointer` | `ocgtk/src/common/ml_gobject.c` (only the `ml_closure_marshal` / `ml_raise_gerror` hunks), `ocgtk/src/common/gobject.ml`, `ocgtk/src/common/gobject.mli` (marshal-related hunks), `ocgtk/tests/test_closure_with_gc.ml`, `ocgtk/tests/dune` (that test's stanza) |
| 2 | `common: ref_sink objects read from GValues; ref transfer-full in-params; fix borrowed GList elements` | `ocgtk/src/common/ml_gobject.c` (`ml_g_value_get_object` hunk), `ocgtk/src/gtk/generated/ml_flow_box_gen.c`, `ml_widget_gen.c`, `ml_event_controller_key_gen.c`, `ml_gesture_click_gen.c`, `ml_gesture_drag_gen.c`, `ml_gesture_stylus_gen.c`, `ocgtk/src/gio/generated/ml_menu_gen.c`, `ml_menu_item_gen.c`, `ml_simple_action_gen.c`, `ocgtk/src/gdk/generated/ml_memory_texture_gen.c` |
| 3 | `gir_gen: fix GObject ownership classes (transfer-full ctors, in-params, GList elements); GBytes as boxed` | everything under `gir_gen/` |
| 4 | `gio: fix floating-GVariant use-after-free in SimpleAction activate marshaller` | `ocgtk/src/common/ml_gvariant.c`, `ocgtk/src/gio/generated/simple_action.ml`, `simple_action.mli`, `gSimple_action.ml`, `gSimple_action.mli`, `ocgtk/tests/test_gio_simple_action.ml`, `ocgtk/tests/dune` (its stanza) |
| 5 | `common: Glib_bytes.of_bigstring and external-memory accounting for GBytes` | `ocgtk/src/common/glib_bytes.ml`, `glib_bytes.mli`, `ml_glib_bytes.c`, `ml_glib.c`, `ocgtk/src/common/dune`, `ocgtk/src/configurator/dune`, `ocgtk/src/configurator/probe_custom_dep.ml`, `ocgtk/tests/test_glib_bytes.ml` |
| 6 | `gtk: add Style_display.add_provider_for_default_display (app-wide CSS)` | `ocgtk/src/gtk/core/style_display.ml`, `style_display.mli`, `ocgtk/src/gtk/core/ml_gtk.c`, `ocgtk/src/gtk/dune` |

If while splitting you find a hunk that belongs to none of these, put it in the theme whose files it touches and note it in `docs/upstream/README.md`.

- [ ] **Step 1: Fork and clone**

```bash
gh repo fork chris-armstrong/ocgtk --clone=false --default-branch-only
git clone git@github.com:dlobraico/ocgtk.git ~/src/ocgtk
cd ~/src/ocgtk
git remote add upstream https://github.com/chris-armstrong/ocgtk.git
git fetch upstream
git checkout -b bonsai-gtk 40ab0b6b4c6ae98bfc79c390c4164a6c72508726
```

- [ ] **Step 2: Produce the full diff and the per-file split**

```bash
cd ~/src/ocgtk
diff -ruN --exclude=_build --exclude='*.install' --exclude=compile_commands.json --exclude=.git \
  . ~/src/stavekeeper/vendor/ocgtk > /tmp/ocgtk-full.diff || true
# strip the absolute prefix so the patch applies with -p1 from the repo root
sed -i "s|$HOME/src/stavekeeper/vendor/ocgtk/|b/|g; s|^--- \./|--- a/|; s|^+++ b/|+++ b/|" /tmp/ocgtk-full.diff
grep '^diff ' /tmp/ocgtk-full.diff | wc -l   # expect ~50
```

For each theme in the table: `filterdiff -i 'b/<path>' ...` is not available; instead apply the whole diff for that theme's files with `git apply --include='<glob>' /tmp/ocgtk-full.diff` and then, for `ml_gobject.c` and `tests/dune` (shared between themes 1/2 and 1/4), apply the full file and manually revert the hunks that belong to the other theme with an editor before committing. After each theme's commit, `git diff --stat HEAD` should be empty and the next `git apply --include` should apply cleanly.

- [ ] **Step 3: For each theme — apply, build, test, commit**

```bash
nix develop ~/src/bonsai_gtk#ocgtk -c sh -c 'cd ocgtk && dune build 2>&1 | tail -20 && xvfb-run -a dune runtest 2>&1 | tail -20'
```
Expected after every theme: build clean, all tests pass (theme 1 adds `test_closure_with_gc`, theme 4 adds `test_gio_simple_action`, theme 5 extends `test_glib_bytes`).

Commit message = the theme's title line, then a body explaining the bug and fix in upstream-PR terms (no stavekeeper ticket ids), then the trailer.

- [ ] **Step 4: Verify the branch reproduces the vendored tree exactly**

```bash
cd ~/src/ocgtk && diff -rq --exclude=_build --exclude='*.install' --exclude=compile_commands.json --exclude=.git \
  . ~/src/stavekeeper/vendor/ocgtk
```
Expected: no output (or only `_build`-adjacent artifacts). Any remaining difference means a hunk was dropped — go back to Step 3.

- [ ] **Step 5: Push and record**

```bash
git push -u origin bonsai-gtk
git rev-parse HEAD
```

Write `docs/upstream/README.md` in bonsai_gtk:

```markdown
# ocgtk upstreaming status

Fork: https://github.com/dlobraico/ocgtk, branch `bonsai-gtk` (based on upstream `40ab0b6`).
bonsai_gtk pins the head of this branch via `ocgtk-pin.json`.

| # | Commit | Theme | Upstream PR |
|---|--------|-------|-------------|
| 1 | <sha> | closure-marshal GC safety | (Task 4) |
| 2 | <sha> | GObject ownership in generated stubs | (Task 4) |
| 3 | <sha> | gir_gen ownership fixes | (Task 4) |
| 4 | <sha> | floating-GVariant UAF in SimpleAction | (Task 4) |
| 5 | <sha> | Glib_bytes.of_bigstring + GBytes memory accounting | (Task 4) |
| 6 | <sha> | Style_display.add_provider_for_default_display | (Task 4) |

When a PR merges, rebase `bonsai-gtk` onto upstream `main`, re-run `nix build .#ocgtk`, and move the pin.
```

- [ ] **Step 6: Commit (bonsai_gtk repo)**

```bash
git add docs/upstream/README.md
GIT_EDITOR=true git commit -F - <<'MSG'
Document the ocgtk fork branch and its themed commits

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01Xg8Viv7XX6YLdVMuT4Gffm
MSG
```

---

### Task 3: Point the pin at the fork; OxCaml switch setup script

**Files:**
- Modify: `ocgtk-pin.json`
- Create: `scripts/setup-switch.sh`

**Interfaces:**
- Produces: `./_opam` switch with `ocaml-variants.5.2.0+ox`, `bonsai`, `bonsai_test`, `core`, `ppx_jane`, `virtual_dom`, `ocgtk` (fork pin), `ocamlformat`, `ocaml-lsp-server`, `dune`.

- [ ] **Step 1: Update `ocgtk-pin.json`** to `owner: "dlobraico"`, `rev: <head of bonsai-gtk>`, `hash: ""`, then `nix build .#ocgtk` → copy the `got:` hash in → `nix build .#ocgtk` again.
Expected: builds; the alcotest suite (now including `test_closure_with_gc`, `test_gio_simple_action`) passes under xvfb.

- [ ] **Step 2: Write `scripts/setup-switch.sh`**

```bash
#!/usr/bin/env bash
# Creates the local OxCaml opam switch in ./_opam and installs bonsai_gtk's
# dependencies, pinning ocgtk to the fork commit in ocgtk-pin.json.
# Run inside `nix develop` (needs opam, pkg-config, gtk4, jq).
set -euo pipefail
cd "$(dirname "$0")/.."

OX_REPO="git+https://github.com/oxcaml/opam-repository.git"
COMPILER="ocaml-variants.5.2.0+ox"

if [ ! -d _opam ]; then
  opam switch create . --no-install \
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
opam install -y \
  ocgtk \
  bonsai bonsai_test \
  core ppx_jane virtual_dom \
  dune ocamlformat ocaml-lsp-server

echo "Switch ready. In a shell: eval \$(opam env --switch=. --set-switch)"
```

`chmod +x scripts/setup-switch.sh`.

- [ ] **Step 3: Run it**

Run: `nix develop -c ./scripts/setup-switch.sh 2>&1 | tail -30`
Expected: ends with "Switch ready". Takes a while (OxCaml compiler build + ~50 packages). If `conf-gtk4` fails, pkg-config cannot see gtk4 — run inside `nix develop`. If opam's solver removes `oxcaml-*` guard packages, that is expected (they conflict with js_of_ocaml pulled by bonsai).

- [ ] **Step 4: Smoke-link bonsai + ocgtk together**

Create a throwaway `scratch/dune` + `scratch/smoke.ml`:
```lisp
(executable (name smoke) (libraries bonsai ocgtk.gtk ocgtk.common core) (preprocess (pps ppx_jane)))
```
```ocaml
open! Core
let () =
  let _ : _ Ocgtk_gtk.Gtk.Wrappers.Application.t =
    Ocgtk_gtk.Gtk.Wrappers.Application.new_ (Some "org.bonsai_gtk.smoke") [ `DEFAULT_FLAGS ]
  in
  let _ = Bonsai.Time_source.create ~start:(Time_ns.now ()) in
  print_endline "bonsai + ocgtk link ok"
```
Run: `nix develop -c sh -c 'dune build ./scratch/smoke.exe && ./_build/default/scratch/smoke.exe'`
Expected: `bonsai + ocgtk link ok`. Then `rm -rf scratch`.

- [ ] **Step 5: Commit**

```bash
git add ocgtk-pin.json scripts/setup-switch.sh
GIT_EDITOR=true git commit -F - <<'MSG'
Pin ocgtk to the dlobraico fork; add OxCaml switch setup script

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01Xg8Viv7XX6YLdVMuT4Gffm
MSG
```

---

### Task 4: Upstream PR drafts (user gate before opening)

**Files:**
- Create: `docs/upstream/pr-1-closure-gc.md` … `pr-6-style-display.md`
- Modify: `docs/upstream/README.md`

**Interfaces:**
- Consumes: the six commits on `~/src/ocgtk` `bonsai-gtk`.
- Produces: one topic branch per theme on the fork (`upstream/closure-gc`, `upstream/gobject-ownership`, …), each cherry-picked from `bonsai-gtk` onto `upstream/main`, and PR drafts.

- [ ] **Step 1: Create topic branches**

For each theme N with commit `<shaN>`:
```bash
cd ~/src/ocgtk
git fetch upstream
git checkout -b upstream/<theme-slug> upstream/main
git cherry-pick <shaN>          # theme 3 (gir_gen) depends on nothing; theme 2 on theme 1's gobject.ml? if a pick conflicts, pick the dependency first and say so in the PR body
nix develop ~/src/bonsai_gtk#ocgtk -c sh -c 'cd ocgtk && dune build && xvfb-run -a dune runtest'
git push -u origin upstream/<theme-slug>
```

- [ ] **Step 2: Write a PR draft per theme** in `docs/upstream/pr-N-<slug>.md` with: title, the bug (symptom → root cause, citing the C function), the fix, how it was verified (test name), and any relation to other PRs. No stavekeeper references. Example for theme 1:

```markdown
Title: Fix GC heap corruption from a naked GValue* in the closure marshaller

`ml_closure_marshal` stored the C `GValue *` for the signal parameters inside an
OCaml record that the GC scans. When a minor collection ran during the callback,
the collector treated that pointer as an OCaml value; with enough closures this
corrupted the heap (crash in `caml_oldify_local_roots` or silent memory
corruption). This change boxes the pointer in an `Abstract_tag` custom block, so
the GC never dereferences it, and fixes an allocation-order bug in
`ml_raise_gerror` found while auditing the same file.

Verification: new `tests/test_closure_with_gc.ml` connects a signal handler,
forces `Gc.full_major` from inside it repeatedly, and asserts the values arrive
intact. It fails on `main` and passes with this change.
```

- [ ] **Step 3: STOP — present the drafts to the user.** Opening PRs against a third-party repository is outward-facing; do not run `gh pr create` until the user has approved the drafts (they may want to edit wording or open them themselves). Record in `docs/upstream/README.md` that the branches exist and PRs are pending approval.

- [ ] **Step 4 (after approval): open PRs**

```bash
gh pr create --repo chris-armstrong/ocgtk --head dlobraico:upstream/<slug> \
  --title "<title>" --body-file ~/src/bonsai_gtk/docs/upstream/pr-N-<slug>.md
```
Fill the PR URLs into `docs/upstream/README.md`.

- [ ] **Step 5: Commit**

```bash
git add docs/upstream
GIT_EDITOR=true git commit -F - <<'MSG'
Add upstream PR drafts for the ocgtk fixes

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01Xg8Viv7XX6YLdVMuT4Gffm
MSG
```

---

### Task 5: vtree — Key, Orientation, Align, Handler, Attr, Attrs

**Files:**
- Create: `vtree/dune`, `vtree/key.ml`, `vtree/key.mli`, `vtree/orientation.ml`, `vtree/align.ml`, `vtree/handler.ml`, `vtree/handler.mli`, `vtree/attr.ml`, `vtree/attr.mli`, `vtree/attrs.ml`, `vtree/attrs.mli`
- Test: `test/dune`, `test/test_attrs.ml`

**Interfaces:**
- Produces:
  - `Key.t = string` with `sexp_of`, `compare`, `equal`, `hash`.
  - `Orientation.t = Horizontal | Vertical`; `Align.t = Fill | Start | End | Center | Baseline` (all `[@@deriving sexp_of, equal, compare]`).
  - `'a Handler.t = 'a -> unit Ui_effect.t`; `Handler.sexp_of_t` prints `<handler>`; `Handler.equal` is `phys_equal`.
  - `Attr.t`, `Attr.Name.t`, `Attr.name : t -> Name.t option`, `Attr.equal`, constructors listed below.
  - `Attrs.t`, `Attrs.empty`, `Attrs.of_list : Attr.t list -> t`, `Attrs.find : t -> Attr.Name.t -> Attr.t option`, `Attrs.css_classes : t -> string list`, `Attrs.test_id : t -> string option`, `Attrs.to_list : t -> Attr.t list`, `Attrs.diff : old:t -> new_:t -> Attrs.op list`, `Attrs.op = Set of Attr.t | Unset of Attr.Name.t | Add_css_class of string | Remove_css_class of string`, `Attrs.sexp_of_t`.

- [ ] **Step 1: dune files**

`vtree/dune`:
```lisp
(library
 (name bonsai_gtk_vtree)
 (public_name bonsai_gtk.vtree)
 (libraries core virtual_dom.ui_effect)
 (preprocess
  (pps ppx_jane)))
```

`test/dune`:
```lisp
(library
 (name bonsai_gtk_tests)
 (libraries core bonsai_gtk.vtree bonsai bonsai_test expect_test_helpers_core)
 (inline_tests)
 (preprocess
  (pps ppx_jane ppx_expect bonsai.ppx_bonsai)))
```
(`bonsai_gtk_test` is added to this library's deps in Task 8.)

- [ ] **Step 2: Write the failing tests** (`test/test_attrs.ml`)

```ocaml
open! Core
open Bonsai_gtk_vtree

let noop = Ui_effect.Ignore

let%expect_test "of_list merges by name, last wins, css classes accumulate in order" =
  let attrs =
    Attrs.of_list
      [ Attr.css_class "a"
      ; Attr.margin_start 4
      ; Attr.css_class "b"
      ; Attr.margin_start 8
      ; Attr.css_class "a"
      ; Attr.many [ Attr.sensitive false; Attr.test_id "btn" ]
      ]
  in
  print_s [%sexp (attrs : Attrs.t)];
  [%expect
    {|
    ((css_classes (a b)) (Margin_start 8) (Sensitive false) (Test_id btn))
    |}];
  print_s [%sexp (Attrs.css_classes attrs : string list)];
  [%expect {| (a b) |}];
  print_s [%sexp (Attrs.test_id attrs : string option)];
  [%expect {| (btn) |}]
;;

let%expect_test "diff emits set/unset/add/remove; unchanged attrs produce nothing" =
  let old = Attrs.of_list [ Attr.css_class "a"; Attr.css_class "b"; Attr.margin_start 4; Attr.visible false ] in
  let new_ = Attrs.of_list [ Attr.css_class "b"; Attr.css_class "c"; Attr.margin_start 4; Attr.tooltip "hi" ] in
  print_s [%sexp (Attrs.diff ~old ~new_ : Attrs.op list)];
  [%expect
    {|
    ((Remove_css_class a) (Add_css_class c) (Unset Visible) (Set (Tooltip hi)))
    |}]
;;

let%expect_test "handlers compare physically" =
  let h = Attr.on_clicked noop in
  let old = Attrs.of_list [ h ] in
  print_s [%sexp (Attrs.diff ~old ~new_:(Attrs.of_list [ h ]) : Attrs.op list)];
  [%expect {| () |}];
  print_s [%sexp (Attrs.diff ~old ~new_:(Attrs.of_list [ Attr.on_clicked noop ]) : Attrs.op list)];
  [%expect {| ((Set (On_clicked <handler>))) |}]
;;
```

- [ ] **Step 3: Run to verify failure**

Run: `dune build @test/runtest 2>&1 | head -20`
Expected: compile errors — `Attr`, `Attrs` unbound.

- [ ] **Step 4: Implement**

`vtree/key.mli` / `key.ml`:
```ocaml
(* key.mli *)
open! Core
type t = string [@@deriving sexp_of, compare, equal, hash]
include Comparable.S_plain with type t := t
```
```ocaml
(* key.ml *)
open! Core
module T = struct
  type t = string [@@deriving sexp_of, compare, equal, hash]
end
include T
include Comparable.Make_plain (T)
```

`vtree/orientation.ml`:
```ocaml
open! Core
type t = Horizontal | Vertical [@@deriving sexp_of, equal, compare]
```

`vtree/align.ml`:
```ocaml
open! Core
type t = Fill | Start | End | Center | Baseline [@@deriving sexp_of, equal, compare]
```

`vtree/handler.mli` / `handler.ml`:
```ocaml
(* handler.mli *)
open! Core
type 'a t = 'a -> unit Ui_effect.t
val sexp_of_t : ('a -> Sexp.t) -> 'a t -> Sexp.t
val equal : 'a t -> 'a t -> bool
```
```ocaml
(* handler.ml *)
open! Core
type 'a t = 'a -> unit Ui_effect.t
let sexp_of_t _ _ = Sexp.Atom "<handler>"
let equal = phys_equal
```

`vtree/attr.mli`:
```ocaml
open! Core

module Name : sig
  type t =
    | Margin_start | Margin_end | Margin_top | Margin_bottom
    | Halign | Valign | Hexpand | Vexpand
    | Sensitive | Visible | Tooltip
    | Width_request | Height_request
    | Test_id
    | On_clicked
  [@@deriving sexp_of, compare, equal]
  include Comparable.S_plain with type t := t
end

type t =
  | Css_class of string
  | Margin_start of int | Margin_end of int | Margin_top of int | Margin_bottom of int
  | Halign of Align.t | Valign of Align.t
  | Hexpand of bool | Vexpand of bool
  | Sensitive of bool | Visible of bool | Tooltip of string
  | Width_request of int | Height_request of int
  | Test_id of string
  | On_clicked of unit Handler.t
  | Many of t list
[@@deriving sexp_of]

(** [None] for [Css_class] (accumulates, not keyed) and [Many]. *)
val name : t -> Name.t option

(** Structural, except handlers compare physically. *)
val equal : t -> t -> bool

val css_class : string -> t
val margin_start : int -> t
val margin_end : int -> t
val margin_top : int -> t
val margin_bottom : int -> t
val margin : int -> t   (** all four sides *)
val halign : Align.t -> t
val valign : Align.t -> t
val hexpand : bool -> t
val vexpand : bool -> t
val sensitive : bool -> t
val visible : bool -> t
val tooltip : string -> t
val width_request : int -> t
val height_request : int -> t
val test_id : string -> t
val on_clicked : unit Ui_effect.t -> t
val many : t list -> t
val empty : t
```

`vtree/attr.ml`:
```ocaml
open! Core

module Name = struct
  module T = struct
    type t =
      | Margin_start | Margin_end | Margin_top | Margin_bottom
      | Halign | Valign | Hexpand | Vexpand
      | Sensitive | Visible | Tooltip
      | Width_request | Height_request
      | Test_id
      | On_clicked
    [@@deriving sexp_of, compare, equal]
  end
  include T
  include Comparable.Make_plain (T)
end

type t =
  | Css_class of string
  | Margin_start of int | Margin_end of int | Margin_top of int | Margin_bottom of int
  | Halign of Align.t | Valign of Align.t
  | Hexpand of bool | Vexpand of bool
  | Sensitive of bool | Visible of bool | Tooltip of string
  | Width_request of int | Height_request of int
  | Test_id of string
  | On_clicked of unit Handler.t
  | Many of t list
[@@deriving sexp_of]

let name = function
  | Css_class _ | Many _ -> None
  | Margin_start _ -> Some Name.Margin_start
  | Margin_end _ -> Some Margin_end
  | Margin_top _ -> Some Margin_top
  | Margin_bottom _ -> Some Margin_bottom
  | Halign _ -> Some Halign
  | Valign _ -> Some Valign
  | Hexpand _ -> Some Hexpand
  | Vexpand _ -> Some Vexpand
  | Sensitive _ -> Some Sensitive
  | Visible _ -> Some Visible
  | Tooltip _ -> Some Tooltip
  | Width_request _ -> Some Width_request
  | Height_request _ -> Some Height_request
  | Test_id _ -> Some Test_id
  | On_clicked _ -> Some On_clicked
;;

let rec equal a b =
  match a, b with
  | Css_class a, Css_class b | Tooltip a, Tooltip b | Test_id a, Test_id b -> String.equal a b
  | Margin_start a, Margin_start b | Margin_end a, Margin_end b
  | Margin_top a, Margin_top b | Margin_bottom a, Margin_bottom b
  | Width_request a, Width_request b | Height_request a, Height_request b -> Int.equal a b
  | Halign a, Halign b | Valign a, Valign b -> Align.equal a b
  | Hexpand a, Hexpand b | Vexpand a, Vexpand b | Sensitive a, Sensitive b | Visible a, Visible b -> Bool.equal a b
  | On_clicked a, On_clicked b -> Handler.equal a b
  | Many a, Many b -> List.equal equal a b
  | _ -> false
;;

let css_class s = Css_class s
let margin_start n = Margin_start n
let margin_end n = Margin_end n
let margin_top n = Margin_top n
let margin_bottom n = Margin_bottom n
let margin n = Many [ Margin_start n; Margin_end n; Margin_top n; Margin_bottom n ]
let halign a = Halign a
let valign a = Valign a
let hexpand b = Hexpand b
let vexpand b = Vexpand b
let sensitive b = Sensitive b
let visible b = Visible b
let tooltip s = Tooltip s
let width_request n = Width_request n
let height_request n = Height_request n
let test_id s = Test_id s
let on_clicked eff = On_clicked (fun () -> eff)
let many l = Many l
let empty = Many []
```

`vtree/attrs.mli`:
```ocaml
open! Core

type t [@@deriving sexp_of]

type op =
  | Set of Attr.t
  | Unset of Attr.Name.t
  | Add_css_class of string
  | Remove_css_class of string
[@@deriving sexp_of]

val empty : t
val of_list : Attr.t list -> t
val find : t -> Attr.Name.t -> Attr.t option
val css_classes : t -> string list
val test_id : t -> string option
val to_list : t -> Attr.t list

(** Ops to turn a widget carrying [old] into one carrying [new_]. Order:
    css removals, css additions, then keyed attrs in [Attr.Name] order
    (Set for changed/new, Unset for gone). *)
val diff : old:t -> new_:t -> op list
```

`vtree/attrs.ml`:
```ocaml
open! Core

type t =
  { by_name : Attr.t Attr.Name.Map.t
  ; css_classes : string list (* insertion order, unique *)
  }

type op =
  | Set of Attr.t
  | Unset of Attr.Name.t
  | Add_css_class of string
  | Remove_css_class of string
[@@deriving sexp_of]

let empty = { by_name = Attr.Name.Map.empty; css_classes = [] }

let sexp_of_t t =
  let css = if List.is_empty t.css_classes then [] else [ [%sexp `css_classes (t.css_classes : string list)] ] in
  Sexp.List (css @ List.map (Map.data t.by_name) ~f:Attr.sexp_of_t)
;;

let of_list attrs =
  let rec add t = function
    | Attr.Many l -> List.fold l ~init:t ~f:add
    | Css_class c ->
      if List.mem t.css_classes c ~equal:String.equal then t
      else { t with css_classes = t.css_classes @ [ c ] }
    | attr ->
      (match Attr.name attr with
       | None -> t
       | Some name -> { t with by_name = Map.set t.by_name ~key:name ~data:attr })
  in
  List.fold attrs ~init:empty ~f:add
;;

let find t name = Map.find t.by_name name
let css_classes t = t.css_classes
let test_id t = match find t Test_id with Some (Test_id s) -> Some s | _ -> None
let to_list t = List.map t.css_classes ~f:Attr.css_class @ Map.data t.by_name

let diff ~old ~new_ =
  let removed = List.filter old.css_classes ~f:(fun c -> not (List.mem new_.css_classes c ~equal:String.equal)) in
  let added = List.filter new_.css_classes ~f:(fun c -> not (List.mem old.css_classes c ~equal:String.equal)) in
  let keyed =
    Map.fold_symmetric_diff old.by_name new_.by_name ~data_equal:Attr.equal ~init:[] ~f:(fun acc (name, change) ->
      match change with
      | `Left _ -> Unset name :: acc
      | `Right a | `Unequal (_, a) -> Set a :: acc)
    |> List.rev
  in
  List.map removed ~f:(fun c -> Remove_css_class c)
  @ List.map added ~f:(fun c -> Add_css_class c)
  @ keyed
;;
```

- [ ] **Step 5: Run tests; fix expect output if the printed form differs only cosmetically** (`dune promote` after eyeballing)

Run: `dune build @test/runtest`
Expected: PASS.

- [ ] **Step 6: Commit**

```bash
dune fmt 2>/dev/null; git add vtree test
GIT_EDITOR=true git commit -F - <<'MSG'
vtree: Key, Align, Orientation, Handler, Attr, Attrs with diff

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01Xg8Viv7XX6YLdVMuT4Gffm
MSG
```

---

### Task 6: vtree — Native, Kind, Children, Node

**Files:**
- Create: `vtree/native.ml`, `vtree/native.mli`, `vtree/kind.ml`, `vtree/kind.mli`, `vtree/children.ml`, `vtree/node.ml`, `vtree/node.mli`, `vtree/bonsai_gtk_vtree.ml`
- Test: `test/test_node.ml`

**Interfaces:**
- Produces:
  - `Native.payload = ..`, `Native.t = { name : string; payload : payload }`, `Native.sexp_of_t`.
  - `Kind.t = Label of { text : string } | Button of { label : string option } | Box of { orientation : Orientation.t; spacing : int; homogeneous : bool } | Window of { title : string option; default_size : (int * int) option } | Native of Native.t`; `Kind.same_kind : t -> t -> bool`; `Kind.name : t -> string`; `Kind.equal_props : t -> t -> bool` (structural for non-native; `phys_equal` payload for native).
  - `'a Children.t = No_children | Single of 'a option | List of 'a list`.
  - `Node.t = { kind : Kind.t; key : Key.t option; attrs : Attrs.t; children : t Children.t }`; constructors `label`, `button`, `box`, `window`, `native`; `Node.find_by_test_id : t -> string -> t option`; `Node.sexp_of_t`.
  - `Bonsai_gtk_vtree` re-exports all modules.

- [ ] **Step 1: Write the failing test** (`test/test_node.ml`)

```ocaml
open! Core
open Bonsai_gtk_vtree

let%expect_test "constructors and sexp" =
  let view =
    Node.window ~title:"Counter" ~default_size:(200, 100)
      (Node.box ~orientation:Vertical ~spacing:6
         [ Node.label ~key:"count" "Count: 0"
         ; Node.button ~attrs:[ Attr.test_id "inc"; Attr.on_clicked Ui_effect.Ignore ] ~label:"+" ()
         ])
  in
  print_s [%sexp (view : Node.t)];
  [%expect
    {|
    ((kind (Window (title (Counter)) (default_size ((200 100)))))
     (attrs ())
     (children
      (Single
       (((kind (Box (orientation Vertical) (spacing 6) (homogeneous false)))
         (attrs ())
         (children
          (List
           (((kind (Label (text "Count: 0"))) (key count) (attrs ())
             (children No_children))
            ((kind (Button (label (+)))) (attrs ((Test_id inc) (On_clicked <handler>)))
             (children No_children))))))))))
    |}]
;;

let%expect_test "find_by_test_id" =
  let view =
    Node.box ~orientation:Horizontal
      [ Node.label "a"; Node.button ~attrs:[ Attr.test_id "b" ] ~label:"B" () ]
  in
  print_s [%sexp (Option.map (Node.find_by_test_id view "b") ~f:(fun n -> n.kind) : Kind.t option)];
  [%expect {| ((Button (label (B)))) |}];
  print_s [%sexp (Node.find_by_test_id view "zzz" : Node.t option)];
  [%expect {| () |}]
;;

let%expect_test "same_kind ignores props; native compares by name" =
  let open Kind in
  print_s [%sexp (same_kind (Label { text = "a" }) (Label { text = "b" }) : bool)];
  [%expect {| true |}];
  print_s [%sexp (same_kind (Label { text = "a" }) (Button { label = None }) : bool)];
  [%expect {| false |}];
  let n name = Native { Native.name; payload = Native.Unit } in
  print_s [%sexp (same_kind (n "canvas") (n "canvas"), same_kind (n "canvas") (n "other") : bool * bool)];
  [%expect {| (true false) |}]
;;
```

- [ ] **Step 2: Run to verify failure** — `dune build @test/runtest` → unbound `Node`/`Kind`/`Native`.

- [ ] **Step 3: Implement**

`vtree/native.mli` / `native.ml`:
```ocaml
(* native.mli *)
open! Core
type payload = ..
type payload += Unit   (** placeholder payload, used by tests *)
type t = { name : string; payload : payload }
val sexp_of_t : t -> Sexp.t
```
```ocaml
(* native.ml *)
open! Core
type payload = ..
type payload += Unit
type t = { name : string; payload : payload }
let sexp_of_t t = [%sexp `native (t.name : string)]
```

`vtree/kind.mli` / `kind.ml`:
```ocaml
(* kind.mli *)
open! Core
type t =
  | Label of { text : string }
  | Button of { label : string option }
  | Box of { orientation : Orientation.t; spacing : int; homogeneous : bool }
  | Window of { title : string option; default_size : (int * int) option }
  | Native of Native.t
[@@deriving sexp_of]

(** Same constructor (and, for [Native], same [name]). Props ignored. *)
val same_kind : t -> t -> bool
val name : t -> string
(** Structural on props; [Native] payloads compare physically. *)
val equal_props : t -> t -> bool
```
```ocaml
(* kind.ml *)
open! Core
type t =
  | Label of { text : string }
  | Button of { label : string option }
  | Box of { orientation : Orientation.t; spacing : int; homogeneous : bool }
  | Window of { title : string option; default_size : (int * int) option }
  | Native of Native.t
[@@deriving sexp_of]

let name = function
  | Label _ -> "Label" | Button _ -> "Button" | Box _ -> "Box" | Window _ -> "Window"
  | Native n -> "Native:" ^ n.name
;;

let same_kind a b =
  match a, b with
  | Label _, Label _ | Button _, Button _ | Box _, Box _ | Window _, Window _ -> true
  | Native a, Native b -> String.equal a.name b.name
  | _ -> false
;;

let equal_props a b =
  match a, b with
  | Label { text = a }, Label { text = b } -> String.equal a b
  | Button { label = a }, Button { label = b } -> Option.equal String.equal a b
  | Box a, Box b ->
    Orientation.equal a.orientation b.orientation && a.spacing = b.spacing && Bool.equal a.homogeneous b.homogeneous
  | Window a, Window b ->
    Option.equal String.equal a.title b.title
    && Option.equal (fun (w, h) (w', h') -> w = w' && h = h') a.default_size b.default_size
  | Native a, Native b -> String.equal a.name b.name && phys_equal a.payload b.payload
  | _ -> false
;;
```

`vtree/children.ml`:
```ocaml
open! Core
type 'a t = No_children | Single of 'a option | List of 'a list [@@deriving sexp_of]
```

`vtree/node.mli`:
```ocaml
open! Core

type t =
  { kind : Kind.t
  ; key : Key.t option [@sexp.option]
  ; attrs : Attrs.t
  ; children : t Children.t
  }
[@@deriving sexp_of]

val label : ?key:Key.t -> ?attrs:Attr.t list -> string -> t
val button : ?key:Key.t -> ?attrs:Attr.t list -> ?label:string -> unit -> t
val box
  :  ?key:Key.t -> ?attrs:Attr.t list -> ?spacing:int -> ?homogeneous:bool
  -> orientation:Orientation.t -> t list -> t
val window
  :  ?key:Key.t -> ?attrs:Attr.t list -> ?title:string -> ?default_size:int * int -> t -> t
val native : ?key:Key.t -> ?attrs:Attr.t list -> Native.t -> t

(** Depth-first search for a node whose attrs carry [Test_id id]. *)
val find_by_test_id : t -> string -> t option
```

`vtree/node.ml`:
```ocaml
open! Core

type t =
  { kind : Kind.t
  ; key : Key.t option [@sexp.option]
  ; attrs : Attrs.t
  ; children : t Children.t
  }
[@@deriving sexp_of]

let make ?key ?(attrs = []) kind children = { kind; key; attrs = Attrs.of_list attrs; children }
let label ?key ?attrs text = make ?key ?attrs (Label { text }) No_children
let button ?key ?attrs ?label () = make ?key ?attrs (Button { label }) No_children

let box ?key ?attrs ?(spacing = 0) ?(homogeneous = false) ~orientation children =
  make ?key ?attrs (Box { orientation; spacing; homogeneous }) (List children)
;;

let window ?key ?attrs ?title ?default_size child =
  make ?key ?attrs (Window { title; default_size }) (Single (Some child))
;;

let native ?key ?attrs n = make ?key ?attrs (Native n) No_children

let rec find_by_test_id t id =
  if Option.equal String.equal (Attrs.test_id t.attrs) (Some id)
  then Some t
  else (
    let kids =
      match t.children with
      | No_children -> []
      | Single c -> Option.to_list c
      | List l -> l
    in
    List.find_map kids ~f:(fun c -> find_by_test_id c id))
;;
```

`vtree/bonsai_gtk_vtree.ml`:
```ocaml
module Key = Key
module Orientation = Orientation
module Align = Align
module Handler = Handler
module Attr = Attr
module Attrs = Attrs
module Native = Native
module Kind = Kind
module Children = Children
module Node = Node
```
(`Reconcile` is added here in Task 7.)

- [ ] **Step 4: Run tests** — `dune build @test/runtest`; promote cosmetic differences after checking they are only layout.

- [ ] **Step 5: Commit**

```bash
dune fmt 2>/dev/null; git add vtree test
GIT_EDITOR=true git commit -F - <<'MSG'
vtree: Native, Kind, Children, Node with constructors and test-id lookup

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01Xg8Viv7XX6YLdVMuT4Gffm
MSG
```

---

### Task 7: vtree — Reconcile (keyed list diff)

**Files:**
- Create: `vtree/reconcile.ml`, `vtree/reconcile.mli`
- Modify: `vtree/bonsai_gtk_vtree.ml` (add `module Reconcile = Reconcile`)
- Test: `test/test_reconcile.ml`

**Interfaces:**
- Produces:
  ```ocaml
  type 'a op =
    | Insert of { index : int; item : 'a }
    | Move of { from : int; to_ : int }
    | Remove of { index : int }
    | Update of { index : int; old : 'a; item : 'a }
  val diff : key:('a -> Key.t option) -> same_kind:('a -> 'a -> bool) -> old:'a list -> new_:'a list -> 'a op list
  val apply : 'a op list -> 'a list -> 'a list   (** reference semantics, used by tests and by the patcher's index bookkeeping *)
  ```
  Semantics: ops are applied left to right to a mutable list that starts as `old`. `Remove {index}` deletes position `index`. `Insert {index; item}` inserts so that `item` ends up at `index`. `Move {from; to_}` removes position `from` and re-inserts at `to_`. `Update {index; old; item}` replaces position `index` (same identity; the patcher recurses). After all ops the list equals `new_`.

- [ ] **Step 1: Write the failing tests** (`test/test_reconcile.ml`)

```ocaml
open! Core
open Bonsai_gtk_vtree

(* items are (key option, kind) *)
type item = string option * string [@@deriving sexp_of, equal, compare, quickcheck]

let key (k, _) = k
let same_kind (_, a) (_, b) = String.equal a b
let diff ~old ~new_ = Reconcile.diff ~key ~same_kind ~old ~new_
let show ~old ~new_ = print_s [%sexp (diff ~old ~new_ : item Reconcile.op list)]
let k s kind = Some s, kind
let u kind = None, kind

let%expect_test "identical lists -> updates only" =
  show ~old:[ k "a" "L"; u "B" ] ~new_:[ k "a" "L"; u "B" ];
  [%expect {| ((Update (index 0) (old ((a) L)) (item ((a) L))) (Update (index 1) (old (() B)) (item (() B)))) |}]
;;

let%expect_test "append and remove" =
  show ~old:[ k "a" "L" ] ~new_:[ k "a" "L"; k "b" "L" ];
  [%expect {| ((Update (index 0) (old ((a) L)) (item ((a) L))) (Insert (index 1) (item ((b) L)))) |}];
  show ~old:[ k "a" "L"; k "b" "L" ] ~new_:[ k "b" "L" ];
  [%expect {| ((Remove (index 0)) (Update (index 0) (old ((b) L)) (item ((b) L)))) |}]
;;

let%expect_test "keyed reorder produces moves, not remove+insert" =
  show ~old:[ k "a" "L"; k "b" "L"; k "c" "L" ] ~new_:[ k "c" "L"; k "a" "L"; k "b" "L" ];
  [%expect
    {|
    ((Move (from 2) (to_ 0))
     (Update (index 0) (old ((c) L)) (item ((c) L)))
     (Update (index 1) (old ((a) L)) (item ((a) L)))
     (Update (index 2) (old ((b) L)) (item ((b) L))))
    |}]
;;

let%expect_test "unkeyed items match positionally only when kinds agree" =
  show ~old:[ u "L"; u "B" ] ~new_:[ u "B"; u "L" ];
  [%expect
    {|
    ((Remove (index 1)) (Remove (index 0))
     (Insert (index 0) (item (() B))) (Insert (index 1) (item (() L))))
    |}]
;;

let%expect_test "duplicate keys raise" =
  Expect_test_helpers_core.require_does_raise (fun () -> diff ~old:[] ~new_:[ k "a" "L"; k "a" "L" ]);
  [%expect {| (Invalid_argument "Reconcile.diff: duplicate key a") |}]
;;

let%test_unit "apply (diff old new) old = new" =
  let gen =
    let open Quickcheck.Generator.Let_syntax in
    let%bind n = Int.gen_incl 0 6 in
    List.gen_with_length n
      (let%map key = Option.quickcheck_generator (String.gen_with_length 1 (Char.gen_uniform_inclusive 'a' 'e'))
       and kind = Quickcheck.Generator.of_list [ "L"; "B" ] in
       key, kind)
  in
  let dedup l =
    List.fold l ~init:([], String.Set.empty) ~f:(fun (acc, seen) ((key, _) as it) ->
      match key with
      | Some kk when Set.mem seen kk -> acc, seen
      | Some kk -> it :: acc, Set.add seen kk
      | None -> it :: acc, seen)
    |> fst |> List.rev
  in
  Quickcheck.test (Quickcheck.Generator.both gen gen) ~sexp_of:[%sexp_of: item list * item list]
    ~f:(fun (old, new_) ->
      let old = dedup old and new_ = dedup new_ in
      let ops = diff ~old ~new_ in
      [%test_result: item list] (Reconcile.apply ops old) ~expect:new_)
;;
```

- [ ] **Step 2: Run to verify failure** — unbound `Reconcile`.

- [ ] **Step 3: Implement** (`vtree/reconcile.mli` is the interface above with doc comments; `reconcile.ml`:)

```ocaml
open! Core

type 'a op =
  | Insert of { index : int; item : 'a }
  | Move of { from : int; to_ : int }
  | Remove of { index : int }
  | Update of { index : int; old : 'a; item : 'a }
[@@deriving sexp_of]

let check_unique_keys ~key items =
  ignore
    (List.fold items ~init:Key.Set.empty ~f:(fun seen item ->
       match key item with
       | None -> seen
       | Some k ->
         if Set.mem seen k then invalid_argf "Reconcile.diff: duplicate key %s" k ();
         Set.add seen k)
     : Key.Set.t)
;;

(* Match every new item to at most one old index. Keyed: by key. Unkeyed: the
   k-th unkeyed new item pairs with the k-th unkeyed old item iff same_kind. *)
let matches ~key ~same_kind ~old ~new_ =
  let old_by_key =
    List.filter_mapi old ~f:(fun i o -> Option.map (key o) ~f:(fun k -> k, i)) |> Key.Map.of_alist_exn
  in
  let old_unkeyed = List.filter_mapi old ~f:(fun i o -> if Option.is_none (key o) then Some i else None) |> Array.of_list in
  let unkeyed_seen = ref 0 in
  List.map new_ ~f:(fun n ->
    match key n with
    | Some k -> Map.find old_by_key k
    | None ->
      let j = !unkeyed_seen in
      incr unkeyed_seen;
      if j < Array.length old_unkeyed && same_kind (List.nth_exn old old_unkeyed.(j)) n
      then Some old_unkeyed.(j)
      else None)
;;

let diff ~key ~same_kind ~old ~new_ =
  check_unique_keys ~key old;
  check_unique_keys ~key new_;
  let matched = matches ~key ~same_kind ~old ~new_ in
  let old_arr = Array.of_list old in
  let kept = Int.Set.of_list (List.filter_opt matched) in
  (* 1. removes, descending, so earlier indices stay valid *)
  let removes =
    List.init (Array.length old_arr) ~f:Fn.id
    |> List.filter ~f:(fun i -> not (Set.mem kept i))
    |> List.rev
    |> List.map ~f:(fun index -> Remove { index })
  in
  (* current = surviving old indices in old order *)
  let current = ref (List.init (Array.length old_arr) ~f:Fn.id |> List.filter ~f:(Set.mem kept)) in
  let ops =
    List.concat_mapi (List.zip_exn new_ matched) ~f:(fun i (item, m) ->
      match m with
      | None ->
        current := List.take !current i @ [ -1 ] @ List.drop !current i;
        [ Insert { index = i; item } ]
      | Some old_idx ->
        let from = List.findi_exn !current ~f:(fun _ x -> x = old_idx) |> fst in
        let move =
          if from = i then []
          else (
            let without = List.filteri !current ~f:(fun j _ -> j <> from) in
            current := List.take without i @ [ old_idx ] @ List.drop without i;
            [ Move { from; to_ = i } ])
        in
        move @ [ Update { index = i; old = old_arr.(old_idx); item } ])
  in
  removes @ ops
;;

let apply ops list =
  List.fold ops ~init:list ~f:(fun l op ->
    match op with
    | Remove { index } -> List.filteri l ~f:(fun i _ -> i <> index)
    | Insert { index; item } -> List.take l index @ [ item ] @ List.drop l index
    | Move { from; to_ } ->
      let item = List.nth_exn l from in
      let l = List.filteri l ~f:(fun i _ -> i <> from) in
      List.take l to_ @ [ item ] @ List.drop l to_
    | Update { index; item; _ } -> List.mapi l ~f:(fun i x -> if i = index then item else x))
;;
```

Add `module Reconcile = Reconcile` to `vtree/bonsai_gtk_vtree.ml`.

- [ ] **Step 4: Run tests** — `dune build @test/runtest`. The quickcheck test is the real check; if an expect test differs only in op ordering that is still valid under `apply`, prefer fixing the implementation to match the documented order (removes descending, then left-to-right) rather than promoting.

- [ ] **Step 5: Commit**

```bash
dune fmt 2>/dev/null; git add vtree test
GIT_EDITOR=true git commit -F - <<'MSG'
vtree: keyed list reconciler with apply-based property test

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01Xg8Viv7XX6YLdVMuT4Gffm
MSG
```

---

### Task 8: bonsai_gtk_test — headless Result_spec and a counter component test

**Files:**
- Create: `test_lib/dune`, `test_lib/bonsai_gtk_test.ml`, `test_lib/bonsai_gtk_test.mli`
- Modify: `test/dune` (add `bonsai_gtk_test` to libraries)
- Test: `test/test_handle.ml`

**Interfaces:**
- Consumes: `Node.find_by_test_id`, `Attrs.find`, `Attr.On_clicked`.
- Produces:
  ```ocaml
  module Action : sig type t = Click of string [@@deriving sexp_of] end
  val result_spec : (Node.t, Action.t) Bonsai_test.Result_spec.t
  module Handle = Bonsai_test.Handle
  val create : ?start_time:Time_ns.t -> ?optimize:bool -> (local_ Bonsai.graph -> Node.t Bonsai.t) -> (Node.t, Action.t) Handle.t
  ```

- [ ] **Step 1: Write the failing test** (`test/test_handle.ml`)

```ocaml
open! Core
open Bonsai_gtk_vtree
open Bonsai.Let_syntax

let counter (graph @ local) =
  let count, set_count = Bonsai.state 0 graph in
  let%arr count and set_count in
  Node.window ~title:"Counter"
    (Node.box ~orientation:Vertical
       [ Node.label ~attrs:[ Attr.test_id "count" ] (sprintf "Count: %d" count)
       ; Node.button ~attrs:[ Attr.test_id "inc"; Attr.on_clicked (set_count (count + 1)) ] ~label:"+" ()
       ])
;;

let%expect_test "clicking the button re-renders the label" =
  let handle = Bonsai_gtk_test.create counter in
  Bonsai_gtk_test.Handle.show handle;
  [%expect
    {|
    ((kind (Window (title (Counter)) (default_size ())))
     (attrs ())
     (children
      (Single
       (((kind (Box (orientation Vertical) (spacing 0) (homogeneous false)))
         (attrs ())
         (children
          (List
           (((kind (Label (text "Count: 0"))) (attrs ((Test_id count)))
             (children No_children))
            ((kind (Button (label (+)))) (attrs ((Test_id inc) (On_clicked <handler>)))
             (children No_children))))))))))
    |}];
  Bonsai_gtk_test.Handle.do_actions handle [ Click "inc"; Click "inc" ];
  Bonsai_gtk_test.Handle.show_diff handle;
  [%expect
    {|
    -|            (((kind (Label (text "Count: 0"))) (attrs ((Test_id count)))
    +|            (((kind (Label (text "Count: 2"))) (attrs ((Test_id count)))
    |}]
;;

let%expect_test "clicking an unknown test id raises" =
  let handle = Bonsai_gtk_test.create counter in
  Expect_test_helpers_core.require_does_raise (fun () ->
    Bonsai_gtk_test.Handle.do_actions handle [ Click "nope" ]);
  [%expect {| (Failure "Bonsai_gtk_test: no node with test_id nope") |}]
;;
```

- [ ] **Step 2: Run to verify failure** — unbound `Bonsai_gtk_test`.

- [ ] **Step 3: Implement**

`test_lib/dune`:
```lisp
(library
 (name bonsai_gtk_test)
 (public_name bonsai_gtk_test)
 (libraries core bonsai bonsai_test bonsai_gtk.vtree virtual_dom.ui_effect)
 (preprocess
  (pps ppx_jane)))
```

`test_lib/bonsai_gtk_test.mli`:
```ocaml
open! Core
open Bonsai_gtk_vtree

module Action : sig
  type t = Click of string (** test_id of a node carrying [Attr.on_clicked] *)
  [@@deriving sexp_of]
end

val result_spec : (Node.t, Action.t) Bonsai_test.Result_spec.t

module Handle = Bonsai_test.Handle

val create
  :  ?start_time:Time_ns.t
  -> ?optimize:bool
  -> (local_ Bonsai.graph -> Node.t Bonsai.t)
  -> (Node.t, Action.t) Handle.t
```

`test_lib/bonsai_gtk_test.ml`:
```ocaml
open! Core
open Bonsai_gtk_vtree

module Action = struct
  type t = Click of string [@@deriving sexp_of]
end

module Result_spec = struct
  type t = Node.t
  type incoming = Action.t

  let view node = Sexp.to_string_hum (Node.sexp_of_t node)

  let incoming node (Action.Click id) =
    match Node.find_by_test_id node id with
    | None -> failwithf "Bonsai_gtk_test: no node with test_id %s" id ()
    | Some n ->
      (match Attrs.find n.attrs On_clicked with
       | Some (On_clicked h) -> h ()
       | _ -> failwithf "Bonsai_gtk_test: node %s has no on_clicked handler" id ())
  ;;
end

let result_spec : (Node.t, Action.t) Bonsai_test.Result_spec.t = (module Result_spec)

module Handle = Bonsai_test.Handle

let create ?start_time ?optimize app = Handle.create ?start_time ?optimize result_spec app
```

Add `bonsai_gtk_test` to `test/dune` libraries.

- [ ] **Step 4: Run tests** — `dune build @test/runtest`. `Bonsai_test.Handle.create` has a `here:[%call_pos]` parameter; if the compiler complains, thread `?(here = Stdlib.Lexing.dummy_pos)`… no: pass it through as `let create ~(here : [%call_pos]) ...` and call `Handle.create ~here`. `show_diff` output format may differ slightly (patdiff style); promote after confirming the `Count: 0 → Count: 2` line is there.

- [ ] **Step 5: Commit**

```bash
dune fmt 2>/dev/null; git add test_lib test
GIT_EDITOR=true git commit -F - <<'MSG'
bonsai_gtk_test: headless Result_spec over Node.t with click actions

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01Xg8Viv7XX6YLdVMuT4Gffm
MSG
```

---

### Task 9: runtime — Gtk_import, Attr_apply, Signals, Widget_impl, the four widgets

**Files:**
- Create: `src/dune`, `src/gtk_import.ml`, `src/attr_apply.ml`, `src/attr_apply.mli`, `src/signals.ml`, `src/signals.mli`, `src/widget_impl.ml`, `src/widget_impl.mli`, `src/widgets/label.ml`, `src/widgets/button.ml`, `src/widgets/box.ml`, `src/widgets/window.ml`, `src/widgets/registry.ml`

**Interfaces:**
- Consumes: `Attrs.op`, `Attr.Name`, `Kind.t`, ocgtk Layer 1 (`Ocgtk_gtk.Gtk.Wrappers.*`, `Gobject`, `Glib`).
- Produces:
  ```ocaml
  (* Gtk_import *)
  module Gtk = Ocgtk_gtk.Gtk   module W = Gtk.Wrappers   module Widget = W.Widget
  val cast : 'a Gobject.obj -> 'b Gobject.obj          (* Gobject.unsafe_cast *)
  val widget_children : Widget.t -> Widget.t list      (* first_child / next_sibling walk *)
  (* Attr_apply *)
  val apply : Widget.t -> Attrs.op -> unit
  val apply_all : Widget.t -> Attrs.t -> unit          (* for freshly created widgets *)
  (* Signals *)
  type ctx = { schedule : unit Ui_effect.t -> unit; in_patch : unit -> bool; on_exn : node_path:string -> exn -> unit }
  type spec = { attr : Attr.Name.t; connect : Widget.t -> callback:(unit -> unit) -> Gobject.Signal.handler_id; fire : Attr.t -> unit Ui_effect.t option }
  type slots
  val connect_all : ctx -> node_path:string -> Widget.t -> spec list -> slots * Gobject.Signal.handler_id list
  val update_slots : slots -> Attrs.t -> unit
  val clear_slots : slots -> unit
  val disconnect : Widget.t -> Gobject.Signal.handler_id list -> unit
  (* Widget_impl *)
  type child_ops =
    | No_children
    | Single of { set : Widget.t -> Widget.t option -> unit }
    | List of { insert : Widget.t -> index:int -> Widget.t -> unit
              ; move : Widget.t -> child:Widget.t -> to_:int -> unit
              ; remove : Widget.t -> Widget.t -> unit }
  type t = { name : string; create : Kind.t -> Widget.t; update : Widget.t -> old:Kind.t -> Kind.t -> unit; signals : Signals.spec list; children : child_ops }
  (* Widgets.Registry *)
  val for_kind : Kind.t -> Widget_impl.t     (* raises Invalid_argument for Native in M0 until Task 10 wires Native_gtk *)
  ```

No tests in this task (ocgtk-linked code cannot use ppx_expect); Task 10's live test exercises everything here. Compile cleanly with `dune build src`.

- [ ] **Step 1: `src/dune`**

```lisp
(include_subdirs unqualified)

(library
 (name bonsai_gtk)
 (public_name bonsai_gtk)
 (libraries core bonsai bonsai.driver virtual_dom.ui_effect bonsai_gtk.vtree
  ocgtk.gtk ocgtk.gio ocgtk.gdk ocgtk.common)
 (flags (:standard -w +a-4-40-41-42-44-45-70 -open Core))
 (preprocess
  (pps ppx_jane)))
```
(`include_subdirs unqualified` makes `src/widgets/*.ml` modules of the same library. Module names `Label`, `Button`, `Box`, `Window` would clash with nothing in scope because we never `open` Gtk, but to be safe name the files `w_label.ml`, `w_button.ml`, `w_box.ml`, `w_window.ml`.)

- [ ] **Step 2: `src/gtk_import.ml`**

```ocaml
open! Core
module Gtk = Ocgtk_gtk.Gtk
module W = Gtk.Wrappers
module Widget = W.Widget
module Gobject = Gobject
module Glib = Glib

let cast = Gobject.unsafe_cast

let widget_children (w : Widget.t) : Widget.t list =
  let rec go acc = function
    | None -> List.rev acc
    | Some c -> go (c :: acc) (Widget.get_next_sibling c)
  in
  go [] (Widget.get_first_child w)
;;

let type_name (w : Widget.t) = Gobject.Type.name (Gobject.get_type w)
```

- [ ] **Step 3: `src/attr_apply.ml(i)`**

```ocaml
open! Core
open Bonsai_gtk_vtree
open Gtk_import

let align : Align.t -> _ = function
  | Fill -> `FILL | Start -> `START | End -> `END | Center -> `CENTER | Baseline -> `BASELINE_FILL
;;

let set (w : Widget.t) (attr : Attr.t) =
  match attr with
  | Css_class c -> Widget.add_css_class w c
  | Margin_start n -> Widget.set_margin_start w n
  | Margin_end n -> Widget.set_margin_end w n
  | Margin_top n -> Widget.set_margin_top w n
  | Margin_bottom n -> Widget.set_margin_bottom w n
  | Halign a -> Widget.set_halign w (align a)
  | Valign a -> Widget.set_valign w (align a)
  | Hexpand b -> Widget.set_hexpand w b
  | Vexpand b -> Widget.set_vexpand w b
  | Sensitive b -> Widget.set_sensitive w b
  | Visible b -> Widget.set_visible w b
  | Tooltip s -> Widget.set_tooltip_text w (Some s)
  | Width_request n -> Widget.set_size_request w n (-1)   (* see note *)
  | Height_request n -> Widget.set_size_request w (-1) n
  | Test_id _ | On_clicked _ | Many _ -> ()
;;

(* Reset to GTK defaults. Width/Height share set_size_request; unsetting one
   resets both, which is acceptable for M0 and noted in the mli. *)
let unset (w : Widget.t) (name : Attr.Name.t) =
  match name with
  | Margin_start -> Widget.set_margin_start w 0
  | Margin_end -> Widget.set_margin_end w 0
  | Margin_top -> Widget.set_margin_top w 0
  | Margin_bottom -> Widget.set_margin_bottom w 0
  | Halign -> Widget.set_halign w `FILL
  | Valign -> Widget.set_valign w `FILL
  | Hexpand -> Widget.set_hexpand w false
  | Vexpand -> Widget.set_vexpand w false
  | Sensitive -> Widget.set_sensitive w true
  | Visible -> Widget.set_visible w true
  | Tooltip -> Widget.set_tooltip_text w None
  | Width_request | Height_request -> Widget.set_size_request w (-1) (-1)
  | Test_id | On_clicked -> ()
;;

let apply w (op : Attrs.op) =
  match op with
  | Set a -> set w a
  | Unset n -> unset w n
  | Add_css_class c -> Widget.add_css_class w c
  | Remove_css_class c -> Widget.remove_css_class w c
;;

let apply_all w attrs = List.iter (Attrs.to_list attrs) ~f:(set w)
```
Note for `Width_request`/`Height_request`: GTK only offers `set_size_request w h` together; to set one without clobbering the other, read the current pair first with `Widget.get_size_request` if ocgtk binds it (check `grep get_size_request` in the widget mli; it returns `int * int` if bound). Use it if present; otherwise the `-1` form above.

- [ ] **Step 4: `src/signals.ml(i)`**

```ocaml
open! Core
open Bonsai_gtk_vtree
open Gtk_import

type ctx =
  { schedule : unit Ui_effect.t -> unit
  ; in_patch : unit -> bool
  ; on_exn : node_path:string -> exn -> unit
  }

type spec =
  { attr : Attr.Name.t
  ; connect : Widget.t -> callback:(unit -> unit) -> Gobject.Signal.handler_id
  ; fire : Attr.t -> unit Ui_effect.t option
  }

type slots = (Attr.Name.t, Attr.t option ref) List.Assoc.t ref

let connect_all ctx ~node_path (w : Widget.t) specs : slots * Gobject.Signal.handler_id list =
  let slots = ref [] in
  let ids =
    List.map specs ~f:(fun spec ->
      let slot = ref None in
      slots := (spec.attr, slot) :: !slots;
      spec.connect w ~callback:(fun () ->
        (* Never let an exception cross into C. *)
        match
          if ctx.in_patch () then ()
          else (
            match !slot with
            | None -> ()
            | Some attr ->
              (match spec.fire attr with
               | None -> ()
               | Some eff -> ctx.schedule eff))
        with
        | () -> ()
        | exception exn -> (try ctx.on_exn ~node_path exn with _ -> ())))
  in
  slots, ids
;;

let update_slots (slots : slots) attrs =
  List.iter !slots ~f:(fun (name, slot) -> slot := Attrs.find attrs name)
;;

let clear_slots (slots : slots) = List.iter !slots ~f:(fun (_, slot) -> slot := None)
let disconnect (w : Widget.t) ids = List.iter ids ~f:(fun id -> Gobject.Signal.disconnect w id)
```

- [ ] **Step 5: `src/widget_impl.ml(i)`** — the record type above, plus one helper used by list containers:

```ocaml
open! Core
open Gtk_import

type child_ops =
  | No_children
  | Single of { set : Widget.t -> Widget.t option -> unit }
  | List of
      { insert : Widget.t -> index:int -> Widget.t -> unit
      ; move : Widget.t -> child:Widget.t -> to_:int -> unit
      ; remove : Widget.t -> Widget.t -> unit
      }

type t =
  { name : string
  ; create : Bonsai_gtk_vtree.Kind.t -> Widget.t
  ; update : Widget.t -> old:Bonsai_gtk_vtree.Kind.t -> Bonsai_gtk_vtree.Kind.t -> unit
  ; signals : Signals.spec list
  ; children : child_ops
  }

(* The sibling a child must be placed *after* so it lands at [index] in
   [parent]'s child list, ignoring [except] (the child being moved). *)
let sibling_before parent ~index ~except : Widget.t option =
  if index = 0
  then None
  else (
    let kids =
      widget_children parent
      |> List.filter ~f:(fun c -> match except with None -> true | Some e -> not (Gobject.same c e))
    in
    List.nth kids (index - 1))
;;

let wrong_kind name kind = invalid_argf "%s impl received %s" name (Bonsai_gtk_vtree.Kind.name kind) ()
```

- [ ] **Step 6: widgets**

`src/widgets/w_label.ml`:
```ocaml
open! Core
open Bonsai_gtk_vtree
open Gtk_import

let impl : Widget_impl.t =
  { name = "Label"
  ; create = (function
      | Label { text } -> (W.Label.new_ (Some text) :> Widget.t)
      | k -> Widget_impl.wrong_kind "Label" k)
  ; update = (fun w ~old new_ ->
      match old, new_ with
      | Label { text = o }, Label { text = n } -> if not (String.equal o n) then W.Label.set_text (cast w) n
      | _, k -> Widget_impl.wrong_kind "Label" k)
  ; signals = []
  ; children = No_children
  }
;;
```

`src/widgets/w_button.ml`:
```ocaml
open! Core
open Bonsai_gtk_vtree
open Gtk_import

let clicked : Signals.spec =
  { attr = On_clicked
  ; connect = (fun w ~callback -> W.Button.on_clicked (cast w) ~callback)
  ; fire = (function On_clicked h -> Some (h ()) | _ -> None)
  }
;;

let impl : Widget_impl.t =
  { name = "Button"
  ; create = (function
      | Button { label = Some l } -> (W.Button.new_with_label l :> Widget.t)
      | Button { label = None } -> (W.Button.new_ () :> Widget.t)
      | k -> Widget_impl.wrong_kind "Button" k)
  ; update = (fun w ~old new_ ->
      match old, new_ with
      | Button { label = o }, Button { label = n } ->
        if not (Option.equal String.equal o n) then W.Button.set_label (cast w) (Option.value n ~default:"")
      | _, k -> Widget_impl.wrong_kind "Button" k)
  ; signals = [ clicked ]
  ; children = No_children
  }
;;
```

`src/widgets/w_box.ml`:
```ocaml
open! Core
open Bonsai_gtk_vtree
open Gtk_import

let orientation : Orientation.t -> _ = function Horizontal -> `HORIZONTAL | Vertical -> `VERTICAL

let impl : Widget_impl.t =
  { name = "Box"
  ; create = (function
      | Box { orientation = o; spacing; homogeneous } ->
        let b = W.Box.new_ (orientation o) spacing in
        W.Box.set_homogeneous b homogeneous;
        (b :> Widget.t)
      | k -> Widget_impl.wrong_kind "Box" k)
  ; update = (fun w ~old new_ ->
      match old, new_ with
      | Box o, Box n ->
        let b = cast w in
        if not (Orientation.equal o.orientation n.orientation) then W.Orientable.set_orientation (cast w) (orientation n.orientation);
        if o.spacing <> n.spacing then W.Box.set_spacing b n.spacing;
        if not (Bool.equal o.homogeneous n.homogeneous) then W.Box.set_homogeneous b n.homogeneous
      | _, k -> Widget_impl.wrong_kind "Box" k)
  ; signals = []
  ; children =
      List
        { insert = (fun parent ~index child ->
            W.Box.insert_child_after (cast parent) child (Widget_impl.sibling_before parent ~index ~except:None))
        ; move = (fun parent ~child ~to_ ->
            (* [to_] is the index the child must occupy after the move, so the
               sibling is computed over the other children only. *)
            W.Box.reorder_child_after (cast parent) child (Widget_impl.sibling_before parent ~index:to_ ~except:(Some child)))
        ; remove = (fun parent child -> W.Box.remove (cast parent) child)
        }
  }
;;
```

`src/widgets/w_window.ml`:
```ocaml
open! Core
open Bonsai_gtk_vtree
open Gtk_import

let impl : Widget_impl.t =
  { name = "Window"
  ; create = (function
      | Window { title; default_size } ->
        let w = W.Window.new_ () in
        W.Window.set_title w title;
        Option.iter default_size ~f:(fun (width, height) -> W.Window.set_default_size w width height);
        (w :> Widget.t)
      | k -> Widget_impl.wrong_kind "Window" k)
  ; update = (fun w ~old new_ ->
      match old, new_ with
      | Window o, Window n ->
        if not (Option.equal String.equal o.title n.title) then W.Window.set_title (cast w) n.title;
        (match n.default_size with
         | Some (width, height) when not (Option.equal [%equal: int * int] o.default_size n.default_size) ->
           W.Window.set_default_size (cast w) width height
         | _ -> ())
      | _, k -> Widget_impl.wrong_kind "Window" k)
  ; signals = []
  ; children = Single { set = (fun w child -> W.Window.set_child (cast w) child) }
  }
;;
```

`src/widgets/registry.ml`:
```ocaml
open! Core
open Bonsai_gtk_vtree

let for_kind : Kind.t -> Widget_impl.t = function
  | Label _ -> W_label.impl
  | Button _ -> W_button.impl
  | Box _ -> W_box.impl
  | Window _ -> W_window.impl
  | Native n -> Native_gtk.impl_of_payload n   (* defined in Task 10 *)
;;
```
Until Task 10 exists, make the `Native` arm `invalid_argf "Native node %s: no runtime registered" n.name ()`.

- [ ] **Step 7: Build**

Run: `dune build src 2>&1 | head -40`
Expected: clean. Likely fixes: exact ocgtk function names (`W.Box.set_homogeneous`, `W.Orientable.set_orientation`, `W.Button.new_`, `W.Window.set_child` option-ness) — check them with `grep -n "external <name>" .ocgtk-src/ocgtk/src/gtk/generated/<file>.mli` and adapt; the phantom-type coercions `(x :> Widget.t)` must compile without `cast` for the create functions (contravariant `obj`), use `cast` only when going *down* from `Widget.t`.

- [ ] **Step 8: Commit**

```bash
dune fmt 2>/dev/null; git add src
GIT_EDITOR=true git commit -F - <<'MSG'
runtime: attr application, signal trampolines, widget impls for Label/Button/Box/Window

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01Xg8Viv7XX6YLdVMuT4Gffm
MSG
```

---

### Task 10: runtime — Native_gtk, Patcher, Debug, first live test

**Files:**
- Create: `src/native_gtk.ml`, `src/native_gtk.mli`, `src/patcher.ml`, `src/patcher.mli`, `src/debug.ml`, `src/debug.mli`
- Modify: `src/widgets/registry.ml` (Native arm)
- Test: `test/live/dune`, `test/live/live_patcher.ml`, `test/live/expected_patcher.txt`

**Interfaces:**
- Consumes: Task 9 modules; `Reconcile.diff`; `Kind.same_kind`, `Kind.equal_props`; `Attrs.diff`.
- Produces:
  ```ocaml
  (* Native_gtk *)
  module type S = sig
    type input
    val name : string
    val create : input -> Widget.t
    val update : Widget.t -> old:input -> input -> unit
    val destroy : Widget.t -> unit
  end
  type Native.payload += Gtk : (module S with type input = 'a) * 'a -> Native.payload
  val node : ?key:Key.t -> ?attrs:Attr.t list -> (module S with type input = 'a) -> 'a -> Node.t
  val impl_of_payload : Native.t -> Widget_impl.t
  (* Patcher *)
  type ctx = { signals : Signals.ctx; on_window_created : Widget.t -> unit }
  type live = { mutable node : Node.t; widget : Widget.t; impl : Widget_impl.t; slots : Signals.slots; handler_ids : Gobject.Signal.handler_id list; mutable children : live Children.t }
  val mount : ctx -> path:string -> Node.t -> live       (* creates + attaches children; does NOT attach [live] to a parent *)
  val patch : ctx -> path:string -> live -> Node.t -> live (* returns the same record, or a new one if the kind changed; caller re-parents in that case *)
  val destroy : ctx -> live -> unit                       (* disconnects, destroys children, and for Window kinds calls W.Window.destroy *)
  (* Debug *)
  val dump_live_tree : Widget.t -> Sexp.t   (* (GtkWindow (title X) (children (...))) style *)
  ```

- [ ] **Step 1: `src/native_gtk.ml(i)`**

```ocaml
open! Core
open Bonsai_gtk_vtree
open Gtk_import

module type S = sig
  type input
  val name : string
  val create : input -> Widget.t
  val update : Widget.t -> old:input -> input -> unit
  val destroy : Widget.t -> unit
end

type Native.payload += Gtk : (module S with type input = 'a) * 'a -> Native.payload

let node ?key ?attrs (type a) (module M : S with type input = a) (input : a) =
  Node.native ?key ?attrs { Native.name = M.name; payload = Gtk ((module M), input) }
;;

let impl_of_payload (n : Native.t) : Widget_impl.t =
  match n.payload with
  | Gtk ((module M), _) ->
    let get = function
      | Kind.Native { payload = Gtk ((module M'), input); _ } when phys_equal (Obj.repr (module M : S)) (Obj.repr (module M' : S)) ->
        (Obj.magic input : M.input)
      | k -> Widget_impl.wrong_kind ("Native:" ^ M.name) k
    in
    { name = "Native:" ^ M.name
    ; create = (fun k -> M.create (get k))
    ; update = (fun w ~old new_ -> M.update w ~old:(get old) (get new_))
    ; signals = []
    ; children = No_children
    }
  | _ -> invalid_argf "Native node %s has no Gtk payload" n.name ()
;;
```
The `Obj.magic` is justified by the physical-module check immediately before it (same first-class module value ⇒ same `input` type); document this in the mli. `Kind.equal_props` already forces a replace when the payload is not physically equal, so `update` runs only for the same module.

- [ ] **Step 2: `src/patcher.ml(i)`**

```ocaml
open! Core
open Bonsai_gtk_vtree
open Gtk_import

type ctx =
  { signals : Signals.ctx
  ; on_window_created : Widget.t -> unit
  }

type live =
  { mutable node : Node.t
  ; widget : Widget.t
  ; impl : Widget_impl.t
  ; slots : Signals.slots
  ; handler_ids : Gobject.Signal.handler_id list
  ; mutable children : live Children.t
  }

let child_path path i = sprintf "%s/%d" path i

let rec mount ctx ~path (node : Node.t) : live =
  let impl = Registry.for_kind node.kind in
  let widget = impl.create node.kind in
  Attr_apply.apply_all widget node.attrs;
  let slots, handler_ids = Signals.connect_all ctx.signals ~node_path:path widget impl.signals in
  Signals.update_slots slots node.attrs;
  let children =
    match node.children, impl.children with
    | No_children, _ -> Children.No_children
    | Single c, Single { set } ->
      let live_c = Option.map c ~f:(mount ctx ~path:(child_path path 0)) in
      set widget (Option.map live_c ~f:(fun l -> l.widget));
      Single live_c
    | List cs, List { insert; _ } ->
      let lives = List.mapi cs ~f:(fun i c -> mount ctx ~path:(child_path path i)) in
      List.iteri lives ~f:(fun i l -> insert widget ~index:i l.widget);
      List lives
    | (Single _ | List _), _ -> invalid_argf "%s: node has children but %s takes none" path impl.name ()
  in
  (match node.kind with Window _ -> ctx.on_window_created widget | _ -> ());
  { node; widget; impl; slots; handler_ids; children }

and destroy ctx (live : live) =
  Signals.clear_slots live.slots;
  Signals.disconnect live.widget live.handler_ids;
  (match live.children with
   | No_children -> ()
   | Single c -> Option.iter c ~f:(destroy ctx)
   | List l -> List.iter l ~f:(destroy ctx));
  match live.node.kind with
  | Window _ -> W.Window.destroy (cast live.widget)
  | _ -> ()

and patch ctx ~path (live : live) (node : Node.t) : live =
  if not (Kind.same_kind live.node.kind node.kind)
  then (
    let fresh = mount ctx ~path node in
    destroy ctx live;
    fresh)
  else (
    if not (Kind.equal_props live.node.kind node.kind) then live.impl.update live.widget ~old:live.node.kind node.kind;
    List.iter (Attrs.diff ~old:live.node.attrs ~new_:node.attrs) ~f:(Attr_apply.apply live.widget);
    Signals.update_slots live.slots node.attrs;
    live.children <- patch_children ctx ~path live node;
    live.node <- node;
    live)

and patch_children ctx ~path (live : live) (node : Node.t) : live Children.t =
  match live.children, node.children, live.impl.children with
  | No_children, No_children, _ -> No_children
  | Single old_c, Single new_c, Single { set } ->
    (match old_c, new_c with
     | None, None -> Single None
     | Some o, None -> set live.widget None; destroy ctx o; Single None
     | None, Some n -> let l = mount ctx ~path:(child_path path 0) n in set live.widget (Some l.widget); Single (Some l)
     | Some o, Some n ->
       let l = patch ctx ~path:(child_path path 0) o n in
       if not (phys_equal l o) then set live.widget (Some l.widget);
       Single (Some l))
  | List olds, List news, List { insert; move; remove } ->
    let ops = Reconcile.diff ~key:(fun (n : Node.t) -> n.key) ~same_kind:(fun a b -> Kind.same_kind a.Node.kind b.Node.kind)
                ~old:(List.map olds ~f:(fun l -> l.node)) ~new_:news in
    (* Mirror the ops onto a mutable array of lives, applying GTK ops as we go. *)
    let cur = ref olds in
    List.iter ops ~f:(function
      | Remove { index } ->
        let l = List.nth_exn !cur index in
        remove live.widget l.widget;
        destroy ctx l;
        cur := List.filteri !cur ~f:(fun i _ -> i <> index)
      | Insert { index; item } ->
        let l = mount ctx ~path:(child_path path index) item in
        insert live.widget ~index l.widget;
        cur := List.take !cur index @ [ l ] @ List.drop !cur index
      | Move { from; to_ } ->
        let l = List.nth_exn !cur from in
        move live.widget ~child:l.widget ~to_;
        let without = List.filteri !cur ~f:(fun i _ -> i <> from) in
        cur := List.take without to_ @ [ l ] @ List.drop without to_
      | Update { index; item; _ } ->
        let l = List.nth_exn !cur index in
        let l' = patch ctx ~path:(child_path path index) l item in
        if not (phys_equal l l') then (
          (* kind changed: replace in place *)
          remove live.widget l.widget;
          insert live.widget ~index l'.widget);
        cur := List.mapi !cur ~f:(fun i x -> if i = index then l' else x));
    List !cur
  | _ -> invalid_argf "%s: children shape changed under the same kind" path ()
;;
```
Note on `Update` when the kind changed: `patch` already destroyed the old live *after* mounting the fresh one, and the old widget was still parented at that moment — that is fine for GTK (destroy of a non-window live only disconnects; the `remove` here unparents it). For a Window live inside a list (not possible in M0) this ordering would matter; leave a comment.

- [ ] **Step 3: `src/debug.ml(i)`**

```ocaml
open! Core
open Gtk_import

let rec dump_live_tree (w : Widget.t) : Sexp.t =
  let ty = type_name w in
  let props =
    (match ty with
     | "GtkLabel" -> [ [%sexp `text (W.Label.get_text (cast w) : string)] ]
     | "GtkButton" -> [ [%sexp `label (W.Button.get_label (cast w) : string option)] ]
     | "GtkWindow" -> [ [%sexp `title (W.Window.get_title (cast w) : string option)] ]
     | "GtkBox" -> [ [%sexp `spacing (W.Box.get_spacing (cast w) : int)] ]
     | _ -> [])
    @ (match Array.to_list (Widget.get_css_classes w) with
       | [] -> [] | l -> [ [%sexp `css (l : string list)] ])
    @ (if Widget.get_visible w then [] else [ Sexp.Atom "hidden" ])
    @ (if Widget.get_sensitive w then [] else [ Sexp.Atom "insensitive" ])
  in
  let kids = widget_children w in
  let kids = if List.is_empty kids then [] else [ Sexp.List (Sexp.Atom "children" :: List.map kids ~f:dump_live_tree) ] in
  Sexp.List (Sexp.Atom ty :: props @ kids)
;;
```
(GtkButton with a label has an internal GtkLabel child; GtkWindow has no internal children exposed via `get_first_child` beyond its child — verify in the expected output and accept what GTK reports.)

- [ ] **Step 4: Live test** — `test/live/dune`:

```lisp
(executables
 (names live_patcher)
 (libraries core bonsai_gtk bonsai_gtk.vtree virtual_dom.ui_effect ocgtk.gtk ocgtk.common)
 (preprocess (pps ppx_jane)))

(rule
 (alias runtest)
 (enabled_if (= %{env:BONSAI_GTK_LIVE_TESTS=0} 1))
 (deps live_patcher.exe)
 (action
  (progn
   (with-stdout-to output_patcher.txt (run %{exe:live_patcher.exe}))
   (diff expected_patcher.txt output_patcher.txt))))
```

`test/live/live_patcher.ml`:
```ocaml
open! Core
open Bonsai_gtk_vtree
module P = Bonsai_gtk.Private.Patcher

let () =
  ignore (Ocgtk_gtk.GMain.init () : string array);
  let scheduled = ref [] in
  let ctx : P.ctx =
    { signals =
        { schedule = (fun e -> scheduled := e :: !scheduled)
        ; in_patch = (fun () -> false)
        ; on_exn = (fun ~node_path e -> printf "EXN at %s: %s\n" node_path (Exn.to_string e))
        }
    ; on_window_created = (fun _ -> print_endline "window created")
    }
  in
  let view label items =
    Node.window ~title:"T"
      (Node.box ~orientation:Vertical ~spacing:4
         (Node.label ~attrs:[ Attr.css_class "title" ] label
          :: List.map items ~f:(fun (k, txt) -> Node.button ~key:k ~attrs:[ Attr.on_clicked (Ui_effect.print_s [%message k]) ] ~label:txt ())))
  in
  let live = P.mount ctx ~path:"root" (view "v1" [ "a", "A"; "b", "B" ]) in
  print_s (Bonsai_gtk.Private.Debug.dump_live_tree live.widget);
  let live = P.patch ctx ~path:"root" live (view "v2" [ "b", "B"; "c", "C"; "a", "A!" ]) in
  print_s (Bonsai_gtk.Private.Debug.dump_live_tree live.widget);
  (* fire a signal: the trampoline must schedule the current handler *)
  (match live.children with
   | Single (Some box) ->
     (match box.children with
      | List (_ :: btn_b :: _) -> Gobject.Signal.emit_by_name btn_b.widget ~name:"clicked"
      | _ -> assert false)
   | _ -> assert false);
  printf "scheduled effects: %d\n" (List.length !scheduled);
  let live = P.patch ctx ~path:"root" live (Node.window ~title:"T" (Node.label "replaced")) in
  print_s (Bonsai_gtk.Private.Debug.dump_live_tree live.widget);
  P.destroy ctx live;
  print_endline "destroyed"
;;
```
Expose `Private.Patcher` and `Private.Debug` from `src/bonsai_gtk.ml` (Task 11 finalizes the public module; for now create a minimal `src/bonsai_gtk.ml` with `module Private = struct module Patcher = Patcher module Debug = Debug end`).

- [ ] **Step 5: Run live test, create the expected file from the first run after reading it critically**

Run: `BONSAI_GTK_LIVE_TESTS=1 xvfb-run -a dune build @test/live/runtest 2>&1 | head -60`
Expected first run: diff failure because `expected_patcher.txt` is empty. Inspect `_build/default/test/live/output_patcher.txt`: it must show (1) `window created` once, (2) the v1 tree with `(GtkLabel (text v1) (css (title)))` and two buttons A, B in order, (3) the v2 tree with buttons B, C, A! in that order — key `a`'s button was *moved and relabeled*, not recreated (GTK cannot show identity, so also print `Gobject.get_ref_count`-free evidence: add a `printf "same widget for a: %b\n"` comparing the `a` live's widget before/after with `Gobject.same`), (4) `scheduled effects: 1`, (5) the replaced tree with a single label, (6) `destroyed`. Then `dune promote`.

- [ ] **Step 6: Commit**

```bash
dune fmt 2>/dev/null; git add src test/live
GIT_EDITOR=true git commit -F - <<'MSG'
runtime: patcher (mount/patch/destroy), native escape hatch, live tree dump, first xvfb test

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01Xg8Viv7XX6YLdVMuT4Gffm
MSG
```

---

### Task 11: runtime — Scheduler, Driver, Loop, Effect, public API, counter example, driver live test

**Files:**
- Create: `src/scheduler.ml(i)`, `src/driver.ml(i)`, `src/effect.ml(i)`, `src/loop.ml(i)`, `src/bonsai_gtk.mli`, `examples/dune`, `examples/counter.ml`
- Modify: `src/bonsai_gtk.ml`
- Test: `test/live/live_driver.ml`, `test/live/expected_driver.txt`, `test/live/dune`

**Interfaces:**
- Consumes: `Patcher`, `Bonsai_driver`, `Bonsai.Time_source`, `Glib.Idle`, `Glib.Timeout`, `W.Application`.
- Produces (public, `src/bonsai_gtk.mli`):
  ```ocaml
  module Bonsai = Bonsai
  module Node = Bonsai_gtk_vtree.Node   module Attr = Bonsai_gtk_vtree.Attr   module Key = Bonsai_gtk_vtree.Key
  module Align = Bonsai_gtk_vtree.Align   module Orientation = Bonsai_gtk_vtree.Orientation
  module Native : sig include module type of Native_gtk end   (* S, node *)
  module Effect : sig include module type of Ui_effect  val quit : unit t end
  val start
    :  ?application_id:string -> ?time_source:Bonsai.Time_source.t -> ?optimize:bool
    -> ?target_frames_per_second:float -> (local_ Bonsai.graph -> Node.t Bonsai.t) -> int
  module Expert : sig
    module Driver : sig
      type t
      val create : ?time_source:Bonsai.Time_source.t -> ?optimize:bool -> on_window_created:(Gtk_import.Widget.t -> unit) -> (local_ Bonsai.graph -> Node.t Bonsai.t) -> t
      val frame : t -> unit
      val schedule_event : t -> unit Ui_effect.t -> unit
      val root_widget : t -> Gtk_import.Widget.t option
      val start_tick : t -> fps:float -> unit
      val stop : t -> unit
    end
  end
  module Private : sig module Patcher = Patcher  module Debug = Debug  module Scheduler = Scheduler end
  ```

- [ ] **Step 1: `src/scheduler.ml(i)`**

```ocaml
open! Core
open Gtk_import

type t =
  { run_frame : unit -> unit
  ; mutable idle_armed : bool
  ; mutable in_patch : bool
  ; mutable tick : Glib.Timeout.id option
  ; mutable stopped : bool
  }

let create ~run_frame = { run_frame; idle_armed = false; in_patch = false; tick = None; stopped = false }
let in_patch t = t.in_patch

let with_patch_guard t f =
  t.in_patch <- true;
  Exn.protect ~f ~finally:(fun () -> t.in_patch <- false)
;;

let guarded_frame t =
  match t.run_frame () with
  | () -> ()
  | exception exn -> eprintf "bonsai_gtk: exception in frame: %s\n%!" (Exn.to_string exn)
;;

let request_frame t =
  if (not t.stopped) && not t.idle_armed
  then (
    t.idle_armed <- true;
    ignore
      (Glib.Idle.add ~prio:(Glib.int_of_priority `HIGH_IDLE) (fun () ->
         t.idle_armed <- false;
         guarded_frame t;
         false)
       : Glib.Idle.id))
;;

let start_tick t ~fps =
  let ms = Int.max 1 (Float.to_int (1000. /. fps)) in
  t.tick <- Some (Glib.Timeout.add ~ms ~callback:(fun () -> if t.stopped then false else (guarded_frame t; true)) ())
;;

let stop t =
  t.stopped <- true;
  Option.iter t.tick ~f:Glib.Timeout.remove;
  t.tick <- None
;;
```

- [ ] **Step 2: `src/driver.ml(i)`**

```ocaml
open! Core
open Bonsai_gtk_vtree
open Gtk_import

type t =
  { bonsai : Node.t Bonsai_driver.t
  ; time_source : Bonsai.Time_source.t
  ; advance_wall_clock : bool
  ; scheduler : Scheduler.t
  ; ctx : Patcher.ctx
  ; mutable root : Patcher.live option
  ; mutable last : Node.t option
  }

let schedule_event t eff =
  Bonsai_driver.schedule_event t.bonsai eff;
  Scheduler.request_frame t.scheduler
;;

let check_root (node : Node.t) =
  match node.kind with
  | Window _ -> ()
  | k -> invalid_argf "Bonsai_gtk: the root node must be a Node.window, got %s" (Kind.name k) ()
;;

let frame t =
  if t.advance_wall_clock then (
    Bonsai.Time_source.advance_clock t.time_source ~to_:(Time_ns.now ());
    Bonsai.Time_source.Private.flush t.time_source);
  Bonsai_driver.flush t.bonsai;
  let node = Bonsai_driver.result t.bonsai in
  let changed = match t.last with None -> true | Some prev -> not (phys_equal prev node) in
  if changed then (
    check_root node;
    Scheduler.with_patch_guard t.scheduler (fun () ->
      t.root <- Some (match t.root with
        | None -> Patcher.mount t.ctx ~path:"root" node
        | Some live -> Patcher.patch t.ctx ~path:"root" live node));
    t.last <- Some node);
  Bonsai_driver.trigger_lifecycles t.bonsai;
  if Bonsai_driver.has_after_display_events t.bonsai then Scheduler.request_frame t.scheduler
;;

let create ?time_source ?(optimize = true) ~on_window_created app =
  let advance_wall_clock = Option.is_none time_source in
  let time_source = Option.value_or_thunk time_source ~default:(fun () -> Bonsai.Time_source.create ~start:(Time_ns.now ())) in
  let bonsai =
    Bonsai_driver.create ~optimize ~time_source
      ~instrumentation:(Bonsai_driver.Instrumentation.default_for_test_handles ())
      app
  in
  let rec t =
    { bonsai; time_source; advance_wall_clock; scheduler; ctx; root = None; last = None }
  and scheduler = Scheduler.create ~run_frame:(fun () -> frame t)
  and ctx : Patcher.ctx =
    { signals =
        { schedule = (fun eff -> schedule_event t eff)
        ; in_patch = (fun () -> Scheduler.in_patch scheduler)
        ; on_exn = (fun ~node_path exn -> eprintf "bonsai_gtk: exception in handler at %s: %s\n%!" node_path (Exn.to_string exn))
        }
    ; on_window_created
    }
  in
  t
;;
```
If OCaml rejects the `let rec` of records with function fields ("this kind of expression is not allowed as right-hand side of let rec"), build `scheduler` and `ctx` against a `t option ref` cell instead: `let cell = ref None in ... schedule = (fun eff -> schedule_event (Option.value_exn !cell) eff) ...; cell := Some t; t`.

```ocaml
let root_widget t = Option.map t.root ~f:(fun l -> l.Patcher.widget)
let start_tick t ~fps = Scheduler.start_tick t.scheduler ~fps
let stop t = Scheduler.stop t.scheduler; Option.iter t.root ~f:(Patcher.destroy t.ctx); t.root <- None
```

- [ ] **Step 3: `src/effect.ml(i)`**

```ocaml
open! Core
include Ui_effect

let app : Gtk_import.W.Application.t option ref = ref None

let quit =
  of_thunk (fun () ->
    match !app with
    | Some a -> Ocgtk_gio.Gio.Application.quit (Gtk_import.cast a)
    | None -> eprintf "bonsai_gtk: Effect.quit outside of Bonsai_gtk.start\n%!")
;;

module Private = struct
  let set_app a = app := Some a
end
```
Note: `quit` lives on `Ocgtk_gio.Gio.Application` (`external quit : t -> unit`); prefer the coercion `(a :> Ocgtk_gio.Gio.Application.t)` over `cast` if the phantom rows permit it.

- [ ] **Step 4: `src/loop.ml(i)`**

```ocaml
open! Core
open Gtk_import

let start ?(application_id = "org.bonsai_gtk.app") ?time_source ?optimize ?(target_frames_per_second = 60.) app =
  let gapp = W.Application.new_ (Some application_id) [ `DEFAULT_FLAGS ] in
  Effect.Private.set_app gapp;
  let driver = ref None in
  let on_window_created (w : Widget.t) =
    W.Application.add_window gapp (cast w);
    W.Window.present (cast w)
  in
  ignore
    (Ocgtk_gio.Gio.Application.on_activate (gapp :> Ocgtk_gio.Gio.Application.t) ~callback:(fun () ->
       match !driver with
       | Some _ -> ()   (* second activation: GTK re-presents the window itself *)
       | None ->
         let d = Driver.create ?time_source ?optimize ~on_window_created app in
         driver := Some d;
         Driver.frame d;
         Driver.start_tick d ~fps:target_frames_per_second)
     : Gobject.Signal.handler_id);
  let status = Ocgtk_gio.Gio.Application.run (gapp :> Ocgtk_gio.Gio.Application.t) 0 None in
  Option.iter !driver ~f:Driver.stop;
  status
;;
```
`run`'s second/third arguments are `argc`/`argv` (`int -> string array option`); passing `0 None` means GTK does not parse the command line.

- [ ] **Step 5: `src/bonsai_gtk.ml` / `.mli`** — assemble the public API exactly as in the Interfaces block; `Expert.Driver = Driver`, `Private` as before plus `Scheduler`.

- [ ] **Step 6: Example** — `examples/dune`:
```lisp
(executable
 (name counter)
 (libraries core bonsai bonsai_gtk)
 (preprocess (pps ppx_jane bonsai.ppx_bonsai)))
```
`examples/counter.ml`:
```ocaml
open! Core
open Bonsai_gtk
open Bonsai.Let_syntax

let app (graph @ local) =
  let count, set_count = Bonsai.state 0 graph in
  let%arr count and set_count in
  Node.window ~title:"bonsai_gtk counter" ~default_size:(240, 120)
    (Node.box ~orientation:Vertical ~spacing:8 ~attrs:[ Attr.margin 12 ]
       [ Node.label ~attrs:[ Attr.css_class "title-2" ] (sprintf "Count: %d" count)
       ; Node.box ~orientation:Horizontal ~spacing:8 ~attrs:[ Attr.halign Center ]
           [ Node.button ~attrs:[ Attr.on_clicked (set_count (count - 1)) ] ~label:"−" ()
           ; Node.button ~attrs:[ Attr.on_clicked (set_count (count + 1)); Attr.css_class "suggested-action" ] ~label:"+" ()
           ; Node.button ~attrs:[ Attr.on_clicked (set_count 0); Attr.sensitive (count <> 0) ] ~label:"Reset" ()
           ]
       ; Node.button ~attrs:[ Attr.on_clicked Effect.quit; Attr.halign End ] ~label:"Quit" ()
       ])
;;

let () = exit (Bonsai_gtk.start ~application_id:"org.bonsai_gtk.examples.counter" app)
```

- [ ] **Step 7: Driver live test** — add `live_driver` to `test/live/dune` `names` and a second rule identical to the patcher one with `live_driver.exe` / `output_driver.txt` / `expected_driver.txt`.

`test/live/live_driver.ml`:
```ocaml
open! Core
open Bonsai_gtk
open Bonsai.Let_syntax

let app (graph @ local) =
  let count, set_count = Bonsai.state 0 graph in
  let%arr count and set_count in
  Node.window ~title:"drv"
    (Node.box ~orientation:Vertical
       [ Node.label (sprintf "Count: %d" count)
       ; Node.button ~attrs:[ Attr.on_clicked (set_count (count + 1)) ] ~label:"+" ()
       ])
;;

let () =
  ignore (Ocgtk_gtk.GMain.init () : string array);
  let time_source = Bonsai.Time_source.create ~start:Time_ns.epoch in
  let d = Expert.Driver.create ~time_source ~on_window_created:(fun _ -> print_endline "window created") app in
  let dump () = print_s (Private.Debug.dump_live_tree (Option.value_exn (Expert.Driver.root_widget d))) in
  Expert.Driver.frame d;
  dump ();
  (* find the button and click it through GTK's signal machinery *)
  let root = Option.value_exn (Expert.Driver.root_widget d) in
  let box = List.hd_exn (Bonsai_gtk.Private.Gtk_import.widget_children root) in
  let button = List.nth_exn (Bonsai_gtk.Private.Gtk_import.widget_children box) 1 in
  Gobject.Signal.emit_by_name button ~name:"clicked";
  Gobject.Signal.emit_by_name button ~name:"clicked";
  (* the trampoline scheduled the events and armed an idle; drain the main loop *)
  while Glib.Main.pending () do ignore (Glib.Main.iteration false : bool) done;
  dump ();
  Expert.Driver.stop d;
  print_endline "stopped"
;;
```
(Expose `Gtk_import` under `Private` too.) Expected: the second dump shows `Count: 2`. If the idle did not run because `Glib.Main.pending` returned false before the idle source was checked, call `Expert.Driver.frame d` explicitly after the emits instead and note in the expected file comment that the test drives frames manually.

- [ ] **Step 8: Run everything**

Run: `dune build @all 2>&1 | head -40 && dune build @test/runtest && BONSAI_GTK_LIVE_TESTS=1 xvfb-run -a dune build @test/live/runtest`
Expected: all green after promoting the driver expected file.

Run: `xvfb-run -a timeout 3 dune exec examples/counter.exe; echo "exit=$?"`
Expected: `exit=124` (the app ran until the timeout, i.e. the window opened and the loop was alive). Any other code or a stack trace is a failure.

- [ ] **Step 9: Commit**

```bash
dune fmt 2>/dev/null; git add src examples test/live
GIT_EDITOR=true git commit -F - <<'MSG'
runtime: scheduler, driver, GtkApplication loop, Effect.quit, public API, counter example

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01Xg8Viv7XX6YLdVMuT4Gffm
MSG
```

---

### Task 12: CI script, README, docs

**Files:**
- Create: `scripts/ci.sh`
- Modify: `README.md`

- [ ] **Step 1: `scripts/ci.sh`**

```bash
#!/usr/bin/env bash
# Full local gate. Run inside `nix develop` with the opam switch created.
set -euo pipefail
cd "$(dirname "$0")/.."
eval "$(opam env --switch=. --set-switch)"

echo "== nix: ocgtk pin builds and passes its tests"
nix build .#ocgtk --no-link

echo "== format"
dune fmt --preview >/dev/null 2>&1 || { echo "run dune fmt"; dune fmt 2>&1 | head; exit 1; }

echo "== build"
dune build @all

echo "== pure + headless tests"
dune build @test/runtest

echo "== live tests (xvfb)"
BONSAI_GTK_LIVE_TESTS=1 xvfb-run -a dune build @test/live/runtest

echo "== example smoke"
set +e
xvfb-run -a timeout 3 dune exec examples/counter.exe
code=$?
set -e
[ "$code" = 124 ] || { echo "counter example exited with $code"; exit 1; }
echo "all green"
```
`chmod +x scripts/ci.sh`. (`dune fmt --preview` may not exist in this dune; if not, use `dune build @fmt` and check `git diff --exit-code` after `dune fmt`.)

- [ ] **Step 2: README** — replace with: what it is, the counter example verbatim, the three-library layout (`bonsai_gtk`, `bonsai_gtk.vtree`, `bonsai_gtk_test`), the headless test pattern (`Bonsai_gtk_test.create` + `Handle.show`/`do_actions`), development commands (`nix develop`, `scripts/setup-switch.sh`, `dune build`, `dune runtest`, `scripts/ci.sh`), the ocgtk fork/upstreaming status link (`docs/upstream/README.md`), and the M0 limitations (four widgets, single window, no custom drawing, no ListView) with a pointer to the spec's milestone table.

- [ ] **Step 3: Run `scripts/ci.sh`** — Expected: `all green`.

- [ ] **Step 4: Commit**

```bash
git add scripts/ci.sh README.md
GIT_EDITOR=true git commit -F - <<'MSG'
Add CI gate script and README for M0

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01Xg8Viv7XX6YLdVMuT4Gffm
MSG
```

---

## Spec coverage (M0 slice)

| Spec section | Task |
|---|---|
| §2 toolchain, §2.1 fork, §2.2 ocgtk facts | 1, 2, 3, 4 |
| §3 two libraries | 5–8 (vtree, test lib), 9–11 (runtime) |
| §4.1 `start`, §4.2 frame, §4.3 scheduling, §4.4 reentrancy, §4.5 quit | 11 |
| §5.1–5.4 Node/Attr/Attrs/children/keys | 5, 6 |
| §6.1–6.4 patcher, reconcile, signals | 7, 9, 10 |
| §6.5 controlled text widgets | M1 (no text widgets in M0) |
| §6.6 `Node.native` | 10 |
| §7 catalogue | M0 subset only; M1–M3 are separate plans |
| §8 effects | `quit` only in M0; rest M3 |
| §9 testing, three layers | 5–8 (pure/headless), 10–11 (live) |
| §10 layout & packaging | 1, 3, 12 |
| §11 error handling | 9 (trampoline guard), 10 (root/kind checks), 11 (frame guard) |
