# Image identity: one source, consumed by reference

Established while wiring frameless's identity: `project.conf` is the only place
the image name and vendor are literal. `include/os-release.yml` generates
`/usr/lib/os-release`, the `/etc/os-release` symlink, and
`/usr/share/ublue-os/image-info.json`, reading `%{project-name}` and
`%{image-vendor}`.

Two durable patterns: the **junction override** (`oci/integration/os-release.bst:
oci/os-release.bst`) substitutes an upstream element with ours without forking
upstream — the same lever as the plugin junctions; and `IMAGE_REF` must match the
OCI `ref.name` because it is the `bootc upgrade` origin.

Implication: finpilot's three-site identity test is gone, replaced by a contract
test asserting a single source. Future identity work changes `project.conf`, not
the elements.
