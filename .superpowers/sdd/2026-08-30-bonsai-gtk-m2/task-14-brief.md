### Task 14: ocgtk fork changes, prepared locally and not pushed

Everything M2 wanted from the binding and did not have, collected into one commit series on the fork, listed, and **left for the user to decide about**. An agent does not push the fork.

**Files:** none in this repository, except `docs/upstream/README.md` if it has a list to extend.

**Context.** `ocgtk-pin.json` pins `dlobraico/ocgtk` at `d98d9397`. The fork's six commits are all memory/ownership fixes plus `Style_display`; **there is no nullable-setter patch**, so every item below is new work. `.ocgtk-src/` is the checkout (gitignored, created by `scripts/setup-switch.sh`). `docs/upstream/README.md` describes the upstreaming process and says six PRs are open as drafts.

**The list, in the order they should be committed:**

1. **`Widget.set_name : t -> string option -> unit`.** From `docs/m1-backlog.md`: upstream binds only `string`, so `Unset Widget_name` cannot write NULL and restores `""` instead. `""` and NULL differ to GTK's CSS matcher.
2. **`Stack_page.set_title : t -> string option -> unit`.** A page that loses its `Attr.page_title` currently gets `""`, which is a blank *clickable* switcher button rather than no button (M1 containers M1).
3. **`Password_entry.get_placeholder_text : t -> string option`** and **`set_placeholder_text : t -> string option -> unit`.** The getter is a **crash**, not a wrong value: the C function returns NULL when unset and the stub copies it. `Live_tree` works around it by reading the property through a GValue; the three entry kinds could share one rule if the setter were nullable too.
4. **Whatever M2 discovered.** Fill this in from the task reports rather than from this plan — the candidates the signature survey suggests are `List_box.set_header_func` / `set_sort_func` / `set_filter_func` (the generator skips every GIR callback-taking method, so this is a generator change, not a binding one, and is a much larger piece of work than 1–3), a `GLib.DateTime` binding (there is no `GLib-2.0.gir` in the checkout at all, so this is "add a namespace"), and `gdk_keyval_name`/`from_name` (namespace-level functions, which the generator emits none of). **None of these is a small patch**, and none is needed by M2 — the plan routed around all three. List them as *findings*, with the workaround M2 used, and let the user decide whether any is worth a milestone of its own.

- [ ] **Step 1: Confirm the checkout is clean and at the pin**

```bash
cd ~/src/bonsai_gtk/.ocgtk-src
git status --porcelain     # expect empty
git log --oneline -1       # expect d98d9397
```

A dirty checkout means someone (or a previous run of this task) already started; read it before adding to it. Do **not** `rm -rf` and re-clone — `scripts/setup-switch.sh`'s reinstall stamp keys on the rev, and the backlog already notes it does not notice a dirty tree.

- [ ] **Step 2: Find how nullability is expressed**

The generator reads GIR `nullable=` annotations; these four are cases where the C API takes or returns NULL and the annotation is missing or ignored. Before writing anything, determine which:

```bash
cd ~/src/bonsai_gtk/.ocgtk-src
grep -n 'set_name' gir/Gtk-4.0.gir | head -20
grep -rn 'nullable' gir_gen/ | head -20
```

If the GIR *does* say nullable and the generator ignored it, the fix is in the generator and covers all four at once — much better, and worth saying so. If the GIR does not say it, the fix is either a GIR override table (check whether `gir_gen` has one) or a hand-patched stub. **Report which before writing code**: a generator fix and a hand patch are different sizes and different upstreaming stories, and ocgtk's own history (fork commit `2ed607d2` hand-patches stubs that commit `3322e3b6`'s generator later emits) says the maintainer prefers regeneration.

- [ ] **Step 3: One commit per item, on a topic branch**

```bash
git switch -c bonsai-gtk-m2-nullable
# ... item 1 ...
git commit -F - <<'MSG'
gtk: Widget.set_name accepts NULL

gtk_widget_set_name(w, NULL) resets the widget to its class default name, which
is distinguishable from "" by the CSS matcher. The generated binding takes a
plain string, so a caller that wants to *unset* the name cannot.

MSG
```

Follow ocgtk's own commit style (read `git log` in the checkout), not this repository's — and **do not add the bonsai_gtk `Co-Authored-By`/`Claude-Session` trailer to fork commits** unless the fork's existing commits carry one. Check.

- [ ] **Step 4: Verify locally, without moving the pin**

```bash
cd ~/src/bonsai_gtk/.ocgtk-src && dune build @all && dune runtest
cd ~/src/bonsai_gtk && opam reinstall ocgtk       # spec §2.1's missing step
./scripts/ci.sh                                    # must still pass, unchanged
```

`scripts/ci.sh` must pass **without any bonsai_gtk change**: these are additive binding changes and nothing in M2 depends on them (that is R5, and it is why this task is last among the code tasks). If something in bonsai_gtk breaks, a signature changed rather than being added, and that is a compatibility problem to report rather than to absorb.

- [ ] **Step 5: Do not push. Do not move the pin.** Report:

- the branch name and `git log --oneline` of the new commits, in the checkout;
- for each item: whether it was a generator fix or a hand patch, and why;
- the M2 findings from item 4 with their workarounds;
- the exact commands the user would run to push and re-pin (`git push`, then `nix-prefetch-github` or whatever `ocgtk-pin.json`'s hash comes from — read `flake.nix` and `scripts/setup-switch.sh` for the real procedure and quote it), so that accepting the work is one paste.

**Review focus:** that `scripts/ci.sh` passes with the fork changes *and* would pass without them; that nothing was pushed; that the report is specific enough for the user to act on without re-deriving anything.

---

