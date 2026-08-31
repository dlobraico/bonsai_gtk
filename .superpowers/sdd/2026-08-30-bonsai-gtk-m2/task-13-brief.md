### Task 13: The gallery, and a headless sweep over every M2 widget

M1's Task 10, repeated for M2's eight widgets and five attrs. Two nets under the per-task tests: a headless sweep that names every constructor once, and a runnable window that shows them.

**Files:**
- Modify: `examples/gallery.ml`, `test/handle/test_gallery.ml`, `test/live/live_events.ml`
- Create: nothing

- [ ] **Step 1: `test/handle/test_gallery.ml`** — extend the single tree with every M2 constructor and every M2 attr, and print its sexp. What this catches that the per-task tests do not: a constructor whose defaults changed under it, a `[@sexp_drop_if]` that drops a value the caller asked for (the M1 backlog's "three expect tests pass props the sexp then drops"), and a kind nobody added to `Events` or `Registry`.

Add the assertion M1's file could not make, now that `Attr.Name.all` exists:

```ocaml
(* Every attr constructor appears somewhere in this tree. Not "every attr is exercised" --
   the sexp cannot say that -- but "no attr was added and then forgotten", which is the
   failure this file is a net under. The list is derived from [Attr.Name.all], so a new
   name fails here until someone puts it in the gallery. *)
let%expect_test "the gallery names every attr" =
  let used = names_in_tree gallery_tree in
  let missing =
    List.filter Attr.Name.all ~f:(fun n -> not (List.mem used n ~equal:Attr.Name.equal))
  in
  print_s [%sexp (missing : Attr.Name.t list)];
  [%expect {| () |}]
;;
```

Some names legitimately cannot appear (`Grid_cell` only inside a grid, `Row_selectable` only inside a list box) — but they *can* appear, in the right container, and the gallery has one of each. If a name genuinely cannot be placed, exempt it explicitly by name with a comment rather than weakening the check.

- [ ] **Step 2: `examples/gallery.ml`** — a section per M2 widget. Keep the existing structure (one `Node.frame`-labelled block per family) and add: **Lists** (a list box with header/normal/placeholder rows and a live selection count; a flow box of eight coloured cards with the grid/list toggle stavekeeper has), **Text** (a text view with a word-wrap toggle; an editable label), **Pickers** (a dropdown driving the text view's wrap mode, a calendar, a level bar fed by a scale), **Notebook** (three pages with a reorder button), and **Input** (a box with `Attr.on_key_pressed` that shows the last key, and a card with `Attr.on_click` that shows the last button and modifiers).

That last section is the only *runnable* demonstration that the controllers work end to end, given the live tests may only be able to assert attach/detach (Task 4, Step 1). It is therefore load-bearing rather than decorative — say so in a comment, and check it by hand under a real display before the milestone closes (`docs/m2-backlog.md` carries "real-display click-through of the gallery" forward from M1 either way).

- [ ] **Step 3: `live_events.ml`'s `all_kinds`** — add the eight new kinds and bump the count.

- [ ] **Step 4: `./scripts/ci.sh`** — the gallery smoke run already covers `examples/gallery.exe`; confirm it still exits 124 (came up and stayed up) rather than crashing, and read stderr for `Gtk-CRITICAL` even though the gate does not fail on one.

- [ ] **Step 5: Commit.**

**Review focus:** that the attr-coverage check has no blanket exemption; that the gallery's input section actually reacts (run it); that no expected file in `test/handle/` was promoted without being read.

---

