###############################################################################
# Image identity: os-release and image-info.json
###############################################################################
# Instantiates the shared generator in include/os-release.yml. The layer stack
# depends on this element, and the gnome-build-meta junction overrides its
# oci/integration/os-release.bst with this one, so the image carries frameless's
# identity rather than GNOME OS's.
#
# Values come from project.conf; change the name and vendor there.
###############################################################################
kind: manual

(@):
  - include/os-release.yml
