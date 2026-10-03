###############################################################################
# Plugins: buildstream-plugins-community
###############################################################################
# Community element and source plugins: flatpak_image, ostree,
# collect_manifest, pyproject; git_repo, git_module, cargo2, patch_queue, zip
# sources. We use git_repo and patch_queue for the junctions themselves.
# Update with:
#   just bst source track elements/plugins/buildstream-plugins-community.bst
###############################################################################
kind: junction

sources:
- kind: tar
  url: pypi:a8/3e/4827d60845eab67d93a3e0adf0ea86a86f80de75a07c8f410128c9cf9fe4/buildstream_plugins_community-2.3.3.tar.gz
  ref: 28ccf91c48044ea2889b2dc2a5b5644e5e625479d87a8feb7214a4d1bfd6179a
