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

config:
  options:
    target_arch: '%{arch}'
    (?):
    - arch == 'x86_64':
        bootstrap_build_arch: 'x86_64'
    - arch == 'aarch64':
        bootstrap_build_arch: 'aarch64'

  # Overrides replace freedesktop-sdk components with gnome-build-meta's
  # versions so the desktop stack is coherent. The list is part of the image
  # graph (#17); add entries here as needed, for example:
  # overrides:
  #   components/glib.bst: gnome-build-meta.bst:sdk/glib.bst
