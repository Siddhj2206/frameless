###############################################################################
# Desktop: GNOME
###############################################################################
# The desktop layer, as one element on purpose. An adopter who wants KDE, niri,
# or no desktop replaces THIS element (and the gnome-build-meta junction) and
# nothing else in the graph changes. See the `customize` skill.
#
# gnome-build-meta's gnomeos-deps carries both the freedesktop-sdk-derived OS
# base and the GNOME desktop, so this element is where "the desktop" begins and
# ends for a fork. A no-GUI image depends on a freedesktop-sdk stack here
# instead; the rest of the manifest does not move.
###############################################################################
kind: stack

depends:
  - gnome-build-meta.bst:gnomeos-deps/deps.bst
