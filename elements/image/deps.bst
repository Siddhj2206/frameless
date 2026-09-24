###############################################################################
# Image package manifest
###############################################################################
# The default image's dependency list, and the map of the image. `kind: stack`
# groups elements without producing content; add or remove image content here,
# never by editing a build script.
#
# Read it top to bottom:
#   desktop/   the desktop — swap this element for KDE, niri, or nothing
#   runtime/     the bundled ublue runtime (ujust, Homebrew, first-boot)
#   custom/    your own declarations, from the custom/ directory
###############################################################################
kind: stack

depends:
  # ── desktop ────────────────────────────────────────────────────────────
  - desktop/gnome.bst
  # ujust needs `just` at runtime; the ublue elements only build with it.
  - gnome-build-meta.bst:gnomeos-deps/just.bst

  # ── ublue runtime ──────────────────────────────────────────────────────
  - runtime/common.bst
  - runtime/brew.bst
  - runtime/brew-tarball.bst
  - runtime/firstboot.bst

  # ── adopter declarations ───────────────────────────────────────────────
  - custom/custom.bst
