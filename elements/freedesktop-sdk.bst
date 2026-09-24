###############################################################################
# Base stack: freedesktop-sdk
###############################################################################
# The OS base layer. This junction is the window into freedesktop-sdk; elements
# reference its components as freedesktop-sdk.bst:components/<name>.bst.
#
# Update the pin with:
#   just bst source track elements/freedesktop-sdk.bst
# The `track` glob follows the 26.08 stream. Renovate keeps the ref fresh once
# its custom manager lands (#22).
###############################################################################
kind: junction

sources:
- kind: git_repo
  url: gitlab:freedesktop-sdk/freedesktop-sdk.git
  track: freedesktop-sdk-26.08*
  ref: freedesktop-sdk-26.08.1-0-gb02b59ffe19a49a402f357fd5fcb1d552ebc50d7
# The same patch queue gnome-build-meta applies to freedesktop-sdk, kept in
# sync by `just patch-sync`. Without it the FSDK elements differ from the ones
# in the public caches and rebuild from source.
- kind: patch_queue
  path: patches/freedesktop-sdk

config:
  options:
    target_arch: '%{arch}'
    (?):
    - x86_64_v3:
        x86_64_v3: true
    - arch == 'x86_64':
        bootstrap_build_arch: 'x86_64'
    - arch == 'aarch64':
        bootstrap_build_arch: 'aarch64'

  # Overrides replace freedesktop-sdk components with gnome-build-meta's
  # versions so the desktop stack is coherent. Ported from dakota; the exact
  # list is tuned during the first build. Add entries here as needed, for
  # example:
  overrides:
    components/at-spi2-core.bst: gnome-build-meta.bst:sdk/at-spi2-core.bst
    components/cairo.bst: gnome-build-meta.bst:sdk/cairo.bst
    components/fcitx5-gtk.bst: gnome-build-meta.bst:sdk/fcitx5-gtk.bst
    components/gcab.bst: gnome-build-meta.bst:sdk/gcab.bst
    components/gdk-pixbuf.bst: gnome-build-meta.bst:sdk/gdk-pixbuf.bst
    components/glib-networking.bst: gnome-build-meta.bst:sdk/glib-networking.bst
    components/glib.bst: gnome-build-meta.bst:sdk/glib.bst
    components/glycin.bst: gnome-build-meta.bst:sdk/glycin.bst
    components/gobject-introspection.bst: gnome-build-meta.bst:sdk/gobject-introspection.bst
    components/python3-gi-docgen.bst: gnome-build-meta.bst:sdk/gi-docgen.bst
    components/graphene.bst: gnome-build-meta.bst:sdk/graphene.bst
    components/gsettings-desktop-schemas.bst: gnome-build-meta.bst:sdk/gsettings-desktop-schemas.bst
    components/gtk3.bst: gnome-build-meta.bst:sdk/gtk+-3.bst
    components/libibus.bst: gnome-build-meta.bst:sdk/libibus.bst
    components/json-glib.bst: gnome-build-meta.bst:sdk/json-glib.bst
    components/libglycin.bst: gnome-build-meta.bst:sdk/libglycin.bst
    components/libnotify.bst: gnome-build-meta.bst:sdk/libnotify.bst
    components/librsvg.bst: gnome-build-meta.bst:sdk/librsvg.bst
    components/libsoup.bst: gnome-build-meta.bst:sdk/libsoup.bst
    components/pango.bst: gnome-build-meta.bst:sdk/pango.bst
    components/pygobject.bst: gnome-build-meta.bst:sdk/pygobject.bst
    components/vala.bst: gnome-build-meta.bst:sdk/vala.bst
    components/libsecret.bst: gnome-build-meta.bst:sdk/libsecret.bst
    # Kept identical to gnome-build-meta's own list: a missing override makes
    # the graph diverge from the cache and the affected elements rebuild.
    components/zenity.bst: gnome-build-meta.bst:void/zenity.bst
    components/linux-module-cert.bst: gnome-build-meta.bst:gnomeos/linux-module-cert.bst
    components/libical.bst: gnome-build-meta.bst:core-deps/libical3.bst
    components/_private/systemd-base.bst: gnome-build-meta.bst:core-deps/systemd-base.bst
    components/systemd.bst: gnome-build-meta.bst:core-deps/systemd.bst
    components/systemd-ukify.bst: gnome-build-meta.bst:core-deps/systemd-ukify.bst
    components/systemd-libs.bst: gnome-build-meta.bst:core-deps/systemd-libs.bst
    components/_private/xdg-desktop-portal-base.bst: gnome-build-meta.bst:core-deps/xdg-desktop-portal-base.bst
    components/xdg-desktop-portal.bst: gnome-build-meta.bst:core-deps/xdg-desktop-portal.bst
    components/flatpak.bst: gnome-build-meta.bst:core-deps/flatpak.bst
