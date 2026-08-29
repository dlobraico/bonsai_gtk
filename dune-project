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
