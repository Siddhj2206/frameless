# BuildStream image assembly: the ladder and the choices

Established while defining frameless's default target: an OCI image is assembled
as `stack` (manifest) → `stack` with integration commands (bootc filesystem) →
`compose` (domain filter) → `collect_initial_scripts` → `script` (post-install +
`build-oci`). Integration commands run after all staging, so they win path
conflicts deterministically.

Decisions recorded: keep GNOME core apps for a usable first image (revisit
later); a single layer, no chunking; FSDK's default kernel (dakota's custom
kernel element is out of scope); dakota's FSDK→GBM component overrides ported as
the coherence set.

Implication: the graph is written but has not been built end to end. The first
build is where the override list gets tuned — treat that as the next real
milestone, and teach from its failures.
