(lang dune 3.17)

(name bonsai_gtk)

(generate_opam_files true)

(source
 (github dlobraico/bonsai_gtk))

(license MIT)

(authors "Dominick LoBraico")

(maintainers "Dominick LoBraico")

(package
 (name bonsai_gtk)
 (synopsis "Build GTK4 desktop applications with Bonsai")
 (depends
  (ocaml
   (>= 5.2.0))
  bonsai
  core
  ppx_jane
  virtual_dom
  ; Not the released ocgtk: this needs the fork commit recorded in
  ; ocgtk-pin.json, which scripts/setup-switch.sh path-pins and flake.nix
  ; fetches. The lower bound only rules out older releases; opam cannot
  ; express "this exact commit", so the pin record is the real constraint.
  (ocgtk
   (>= "0.1~preview2"))
  ; test/dune's requirements, so `opam install bonsai_gtk --with-test`
  ; resolves on a clean switch.
  (bonsai_test :with-test)
  (expect_test_helpers_core :with-test)
  (ppx_expect :with-test)))

(package
 (name bonsai_gtk_test)
 (synopsis "Headless test handle for bonsai_gtk apps")
 (depends
  (bonsai_gtk
   (= :version))
  bonsai_test
  ppx_expect))
