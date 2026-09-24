###############################################################################
# projectbluefin/common — the ublue runtime layer
###############################################################################
# Installs the vendor-neutral half of projectbluefin/common
# (`system_files/shared/`): the ujust base recipes, the Homebrew integration,
# and the ublue setup services. The `bluefin/` half is Bluefin's product
# opinion (branding, wallpapers, gschema overrides) and is deliberately not
# installed — a fork opts in through the `custom/` seam.
#
# No patches. frameless installs upstream clean; patch a demonstrated defect
# with `kind: patch` and a note saying why, never for taste.
###############################################################################
kind: manual

sources:
- kind: git_repo
  url: github:projectbluefin/common.git
  track: main
  ref: v2026.08-152-g69c4e8b8cfb3eeb8c16129cfefda40d5dc7e7f2f

build-depends:
- core/sandbox-tools.bst
  # `just` generates the ujust shell completions below.
- gnome-build-meta.bst:gnomeos-deps/just.bst

depends:
- freedesktop-sdk.bst:public-stacks/runtime-minimal.bst
- freedesktop-sdk.bst:components/sed.bst

public:
  bst:
    # shared/ ships files that overlap the GNOME OS base.
    overlap-whitelist:
    - /etc/environment
    - /etc/containers/policy.json

variables:
  strip-binaries: ""

config:
  install-commands:
  - install -d "%{install-root}%{prefix}" "%{install-root}%{sysconfdir}"
  - cp -r system_files/shared/usr/. "%{install-root}%{prefix}/"
  - cp -r system_files/shared/etc/. "%{install-root}%{sysconfdir}/"
    # Generate ujust completions to match the upstream common image.
  - |
    install -d \
      "%{install-root}%{datadir}/bash-completion/completions" \
      "%{install-root}%{datadir}/zsh/site-functions" \
      "%{install-root}%{datadir}/fish/vendor_completions.d"
    just --completions bash | sed -E 's/([\(_" ])just/\1ujust/g' > "%{install-root}%{datadir}/bash-completion/completions/ujust"
    just --completions zsh | sed -E 's/([\(_" ])just/\1ujust/g' > "%{install-root}%{datadir}/zsh/site-functions/_ujust"
    just --completions fish | sed -E 's/([\(_" ])just/\1ujust/g' > "%{install-root}%{datadir}/fish/vendor_completions.d/ujust.fish"
  - "%{install-extra}"
