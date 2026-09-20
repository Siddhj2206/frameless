###############################################################################
# Desktop layer: gnome-build-meta
###############################################################################
# The GNOME desktop stack, and the supplier of the plugin junctions and
# collect_initial_scripts. Elements reference it as
# gnome-build-meta.bst:<path>.bst.
#
# gnome-51 is the current stable branch; it expects the freedesktop-sdk-26.08
# stream that the FSDK junction tracks. Update the pin with:
#   just bst source track elements/gnome-build-meta.bst
###############################################################################
kind: junction

sources:
- kind: git_repo
  url: gnome:gnome-build-meta.git
  track: gnome-51
  ref: 51.0-3-ge34f1eb8c12742aedb1ee65b855c5d88741d9f92

config:
  options:
    arch: '%{arch}'

  overrides:
    # Use our freedesktop-sdk junction, not the one this project carries.
    freedesktop-sdk.bst: freedesktop-sdk.bst
    # Use our pinned plugin junctions so the whole graph agrees on versions.
    plugins/buildstream-plugins.bst: plugins/buildstream-plugins.bst
    plugins/buildstream-plugins-community.bst: plugins/buildstream-plugins-community.bst
    # Use our os-release, so the image carries frameless's identity.
    oci/integration/os-release.bst: oci/os-release.bst
    # gnome-build-meta's signed-modules.bst needs a private signing key that is
    # not in the public repository; stage the modules unsigned instead.
    gnomeos/initramfs/signed-modules.bst: kernel/unsigned-modules.bst
