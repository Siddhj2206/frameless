###############################################################################
# ublue first-boot services
###############################################################################
# The generic ublue first-boot helpers: set the boot menu timeout once, record
# the install date for fastfetch, and guard the flatpak preinstall service on
# older Flatpak. Product-specific first-boot units (Bluefin's wallpaper, the
# bootc-installer removal) are not bundled — a fork adds them via `custom/`.
###############################################################################
kind: manual

sources:
  - kind: local
    path: files/firstboot
  - kind: local
    path: files/service-overrides

build-depends:
  - core/sandbox-tools.bst
  - freedesktop-sdk.bst:public-stacks/runtime-minimal.bst

variables:
  strip-binaries: ""

config:
  install-commands:
    - install -Dm644 ublue-boot-timeout.service "%{install-root}%{indep-libdir}/systemd/system/ublue-boot-timeout.service"
    - install -Dm644 ublue-firstboot-date.service "%{install-root}%{indep-libdir}/systemd/system/ublue-firstboot-date.service"
    - install -d "%{install-root}%{indep-libdir}/systemd/system/multi-user.target.wants"
    - ln -sf ../ublue-boot-timeout.service "%{install-root}%{indep-libdir}/systemd/system/multi-user.target.wants/ublue-boot-timeout.service"
    - ln -sf ../ublue-firstboot-date.service "%{install-root}%{indep-libdir}/systemd/system/multi-user.target.wants/ublue-firstboot-date.service"
    - install -Dm644 "flatpak-preinstall.service.d/condition-check.conf" "%{install-root}%{indep-libdir}/systemd/system/flatpak-preinstall.service.d/condition-check.conf"
    - "%{install-extra}"
