###############################################################################
# OCI layer: filtered root
###############################################################################
# Selects the runtime filesystem out of the composed stack, dropping the
# development, debug, and static-blocklist domains. One layer for v1; chunking
# is deliberately out of scope.
###############################################################################
kind: compose

build-depends:
  - oci/layers/image-stack.bst

config:
  exclude:
    - devel
    - debug
    - static-blocklist
