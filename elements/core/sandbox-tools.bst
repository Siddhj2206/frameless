###############################################################################
# Shell and coreutils for element build sandboxes
###############################################################################
# freedesktop-sdk 26.08 slimmed public-stacks/runtime-minimal.bst down to
# libraries only; on 25.08 it also carried bash and coreutils, which gave
# manual elements a working shell for their configure/build/install commands.
# Every element that runs sandbox commands build-depends on this stack instead
# of relying on its runtime base to smuggle in a shell.
#
# Widen this stack — not the individual elements — if commands need more tools
# than bash and coreutils provide.
###############################################################################
kind: stack

depends:
  - freedesktop-sdk.bst:bootstrap/bash.bst
  - freedesktop-sdk.bst:bootstrap/coreutils.bst
  # 26.08 coreutils links libgcc_s.so.1; stage its provider too.
  - freedesktop-sdk.bst:components/gcc-libs.bst
