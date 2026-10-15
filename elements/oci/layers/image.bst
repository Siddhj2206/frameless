###############################################################################
# OCI layer: filtered root
###############################################################################
# Selects the runtime filesystem out of the composed stack, dropping the
# development, debug, and static-blocklist domains. It is one layer; `just
# chunkify` turns it into content-chunked layers at export time.
###############################################################################
kind: compose

build-depends:
  - oci/layers/image-stack.bst

config:
  exclude:
    - devel
    - debug
    - static-blocklist
