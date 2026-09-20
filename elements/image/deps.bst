###############################################################################
# Image package manifest
###############################################################################
# The default image's dependency list. `kind: stack` groups elements without
# producing content; add or remove image content here, never by editing a
# build script.
#
# The base is gnome-build-meta's GNOME OS deps. The ublue runtime layer
# (common, brew, firstboot) and the `custom/` seam sit on top.
###############################################################################
kind: stack

depends:
  - gnome-build-meta.bst:gnomeos-deps/deps.bst

  # ujust needs `just` at runtime; common only needs it to build completions.
  - gnome-build-meta.bst:gnomeos-deps/just.bst

  # ── ublue runtime layer ────────────────────────────────────────────────
  - ublue/common.bst
  - ublue/brew.bst
  - ublue/brew-tarball.bst
  - ublue/firstboot.bst

  # ── adopter declarations ───────────────────────────────────────────────
  - custom/custom.bst
