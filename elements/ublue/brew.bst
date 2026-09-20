###############################################################################
# ublue-os/brew — the Homebrew integration scripts
###############################################################################
# Copies ublue-os/brew's `system_files`: the brew-setup/brew-update units and
# the managed-prefix helpers. The Homebrew tree itself comes from
# ublue/brew-tarball.bst, which runtime-depends on this element.
###############################################################################
kind: manual

sources:
  - kind: git_repo
    url: github:ublue-os/brew.git
    track: main
    ref: 373e0ac907ba33269522e37fd38f45894f1bd984

build-depends:
  - core/sandbox-tools.bst

depends:
  - freedesktop-sdk.bst:public-stacks/runtime-minimal.bst

variables:
  strip-binaries: ""

config:
  install-commands:
    - install -d "%{install-root}%{prefix}" "%{install-root}%{sysconfdir}"
    - cp -r system_files/usr/. "%{install-root}%{prefix}/"
    - cp -r system_files/etc/. "%{install-root}%{sysconfdir}/"
    - "%{install-extra}"
