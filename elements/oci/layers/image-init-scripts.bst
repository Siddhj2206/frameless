###############################################################################
# OCI layer: initial scripts
###############################################################################
# Collects the initial scripts the composed root declares (systemd units,
# sysusers, tmpfiles, …) so the image-assembly script can apply them with
# prepare-image.sh.
###############################################################################
kind: collect_initial_scripts

build-depends:
  - oci/layers/image-stack.bst

config:
  path: /initial_scripts
