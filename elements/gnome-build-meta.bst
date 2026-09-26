###############################################################################
# Desktop layer: gnome-build-meta
###############################################################################
# The GNOME desktop stack, and the supplier of the plugin junctions and
# collect_initial_scripts. Elements reference it as
# gnome-build-meta.bst:<path>.bst.
#
# gnome-51 is the current stable branch; it expects the freedesktop-sdk-26.08
# stream that the FSDK junction tracks. Update the pin with:
#   just track gnome-build-meta
###############################################################################
kind: junction

sources:
- kind: git_repo
  url: gnome:gnome-build-meta.git
  track: gnome-51
  ref: 51.0-5-gbe7cb317ee21d45197ba5139c77317f171e20c38
# The kernel build-depends (strict) on gnome-build-meta's boot-key certificate,
# and gnome-build-meta's CI generates files/boot-keys/modules/linux-module-cert.crt
# before building (make -C files/boot-keys generate-keys IMPORT_MODE=snakeoil).
# The file is gitignored, so a clean checkout lacks it, the cert element's
# source digest differs, and the kernel gets a cache key the public caches do
# not hold — so it rebuilds from source instead of being pulled. This patch
# recreates exactly what CI generates, from the two snakeoil certificates it
# concatenates.
- kind: patch_queue
  path: patches/gnome-build-meta

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
