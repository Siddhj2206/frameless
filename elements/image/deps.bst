###############################################################################
# Image package manifest
###############################################################################
# The default image's dependency list. `kind: stack` groups elements without
# producing content; add or remove image content here, never by editing a
# build script.
#
# The base is gnome-build-meta's GNOME OS deps. The ublue runtime layer
# (common, brew, flatpak, ujust) lands here in #19.
###############################################################################
kind: stack

depends:
  - gnome-build-meta.bst:gnomeos-deps/deps.bst
