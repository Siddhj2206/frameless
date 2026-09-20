###############################################################################
# custom/ — the adopter's runtime declarations
###############################################################################
# One element, one folder. Everything under custom/ is installed here, so a
# fork changes its image by editing custom/, not by editing elements:
#
#   custom/brew/*.Brewfile        → /usr/share/ublue-os/homebrew/
#   custom/ujust/**/*.just        → /usr/share/ublue-os/just/60-custom.just
#                                   (every *.just concatenated, recursively)
#   custom/flatpaks/*.preinstall  → /usr/share/flatpak/preinstall.d/
#   custom/files/                 → / (the tree mirrors the filesystem root,
#                                   excluding README.md)
#   custom/config/                → /etc/skel/.config/
#
# Empty directories are fine. Nothing here installs packages at build time;
# image packages belong in the `image/deps.bst` stack.
###############################################################################
kind: manual

sources:
  - kind: local
    path: custom

build-depends:
  - core/sandbox-tools.bst
  # `just` generates the ujust shell completions below.
  - gnome-build-meta.bst:gnomeos-deps/just.bst

depends:
  - freedesktop-sdk.bst:public-stacks/runtime-minimal.bst
  - freedesktop-sdk.bst:components/sed.bst

variables:
  strip-binaries: ""

config:
  install-commands:
    # Homebrew bundles, installed for users to run on demand.
    - |
      if compgen -G "brew/*.Brewfile" >/dev/null; then
        install -d "%{install-root}%{datadir}/ublue-os/homebrew"
        install -m644 brew/*.Brewfile -t "%{install-root}%{datadir}/ublue-os/homebrew/"
      fi
    # ujust recipes: concatenate every *.just, recursively, into the one file
    # the base ublue just imports, then generate the shell completions.
    - |
      shopt -s globstar nullglob
      install -d "%{install-root}%{datadir}/ublue-os/just"
      out="%{install-root}%{datadir}/ublue-os/just/60-custom.just"
      : > "${out}"
      for recipe in ujust/**/*.just; do
        cat "${recipe}" >> "${out}"
        printf '\n' >> "${out}"
      done
      install -d \
        "%{install-root}%{datadir}/bash-completion/completions" \
        "%{install-root}%{datadir}/zsh/site-functions" \
        "%{install-root}%{datadir}/fish/vendor_completions.d"
      just --completions bash | sed -E 's/([\(_" ])just/\1ujust/g' > "%{install-root}%{datadir}/bash-completion/completions/ujust"
      just --completions zsh | sed -E 's/([\(_" ])just/\1ujust/g' > "%{install-root}%{datadir}/zsh/site-functions/_ujust"
      just --completions fish | sed -E 's/([\(_" ])just/\1ujust/g' > "%{install-root}%{datadir}/fish/vendor_completions.d/ujust.fish"
    # Flatpak first-boot preinstalls.
    - |
      if compgen -G "flatpaks/*.preinstall" >/dev/null; then
        install -d "%{install-root}%{datadir}/flatpak/preinstall.d"
        install -m644 flatpaks/*.preinstall -t "%{install-root}%{datadir}/flatpak/preinstall.d/"
      fi
    # The root-mirror seam: custom/files/ maps onto /.
    - |
      if [ -d files ]; then
        cp -r files/. "%{install-root}/"
      fi
    # Per-user configuration, seeded into the skeleton.
    - |
      if [ -d config ]; then
        install -d "%{install-root}%{sysconfdir}/skel/.config"
        cp -r config/. "%{install-root}%{sysconfdir}/skel/.config/"
      fi
    # READMEs document the seam for adopters; they are not image content.
    # dotglob so the sweep also reaches hidden directories like .config/.
    - |
      shopt -s globstar nullglob dotglob
      rm -f "%{install-root}"/**/README.md
    - "%{install-extra}"
