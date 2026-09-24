###############################################################################
# Chunkah ownership for the image layer
###############################################################################
# Generates the ownership basis for the exact compose artifact the OCI image is
# built from, without replaying it. `oci/image.bst` consumes this at
# /ownership and finalizes it after build-oci; `just chunkify` turns the result
# into content-chunked layers so updates are smaller.
#
# See docs/research/07-dakota-alpha-6.md and the `buildstream` skill.
###############################################################################
kind: chunkah-ownership

build-depends:
  - oci/layers/image.bst
  - oci/layers/image-stack.bst

config:
  # The compose layer whose surviving paths are owned.
  layer-dependency: oci/layers/image.bst
  # The stack whose runtime closure supplied files to that layer.
  provenance-dependencies:
    - oci/layers/image-stack.bst
