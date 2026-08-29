Title: Add Style_display: application-wide CSS providers and gtk_settings_get_default

Branch: `dlobraico:upstream/style-display` (one commit on top of `main`)

## The gap

There is no way to install a `GtkCssProvider` application-wide. The generated
bindings cover `GtkStyleContext`'s per-widget provider API, but
`gtk_style_context_add_provider_for_display` — the supported GTK4 way to apply
a stylesheet to every widget on a display — is unreachable, and so is
`gdk_display_get_default()`, which you would need to name the display in the
first place. An application that wants its own stylesheet currently cannot have
one.

## The change

A small hand-written `Style_display` module (not GIR-generated, hence
`gtk/core` rather than `gtk/generated`) exposing three things:

- **`priority_application`** — the `GTK_STYLE_PROVIDER_PRIORITY_APPLICATION`
  constant.

- **`add_provider_for_default_display : Style_provider.t -> int -> unit`** —
  resolves the default display itself and raises `Failure` if GTK has none yet
  (i.e. before `gtk_init`) rather than passing NULL into GTK. Both arguments
  are transfer-none and GTK takes its own reference on the provider, so there
  is no ref-sink bookkeeping on this path.

- **`settings_default : unit -> Settings.t`** (`gtk_settings_get_default`) —
  the only handle on `gtk-interface-color-scheme` /
  `gtk-application-prefer-dark-theme`, which an application setting up its own
  stylesheet generally needs alongside it. GIR marks this return transfer-none,
  so the stub `g_object_ref_sink()`s before wrapping — the convention the
  generated bindings already use for a borrowed object return, see
  `ml_gtk_widget_get_settings` — because ocgtk's wrapper claims a reference
  that its finalizer later drops. It too returns NULL before `gtk_init`, which
  becomes a `Failure` rather than a wrapped NULL.

## One build-system consequence, worth a look

`ml_gtk.c` now includes `generated/gtk_decls.h` for the `GtkStyleProvider_val`
and `Val_GtkSettings` wrapper macros. That header transitively includes
`gio_core.h`, which includes `gio/gunixfdmessage.h`, so the gtk stubs now need
the `gio-unix-2.0` include path. `gtk/dune` requests it through the
configurator's existing `--pkg-optional`, which silently skips it where the
package is absent.

This is a hard requirement of the include, not a preference — without it the
gtk stubs do not compile. If you would rather not take a new pkg-config
dependency in `src/gtk`, the alternative is to declare the two wrapper macros
locally instead of including the generated header; say the word and I will
respin it that way.

## Verification

Full suite on the branch: 28 suites, 366 tests, 0 failures
(`dune build && xvfb-run -a dune runtest --force`).

No new tests. Both entry points are thin bindings whose only branch is the
"no default display yet" path, and exercising the success path meaningfully
needs a real display and a stylesheet to observe. If you would like coverage
here, the testable piece is the `Failure` on a pre-`gtk_init` call — happy to
add it.

## Relation to the other PRs

Independent of all five others: it shares **no changed file** with any of them,
and applies to `main` on its own. It touches `src/gtk/core/ml_gtk.c`,
`src/gtk/dune`, one re-export line in `src/gtk/generated/ocgtk_gtk.ml`, and the
two new `style_display.{ml,mli}` files — none of which any other branch
modifies, so it merges in any order.
