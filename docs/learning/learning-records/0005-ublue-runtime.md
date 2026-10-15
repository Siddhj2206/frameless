# The ublue runtime layer, and two load blockers

Established the bundled ublue runtime as `elements/runtime/{common,brew,brew-tarball,firstboot}.bst`
plus `core/sandbox-tools.bst` and the `custom/custom.bst` seam, following
finpilot's split: `common`'s `shared/` half only, never `bluefin/`'s product
opinion. All six elements build and their artifacts were checked out and
verified (Brewfiles, the concatenated `60-custom.just`, all three ujust
completions, flatpak preinstalls, skel config, os-release + image-info.json).

Two load blockers surfaced, both durable:

- **`min-version` and the runner are one decision.** `project.conf` declared
  `min-version: 2.8` while the pinned bst2 image carried BuildStream 2.7, so
  every `just bst` failed at load. The `:latest` bst2 image carries 2.8; the
  Justfile now pins its digest. Recorded in research 05 §7.
- **An upstream element can be unloadable in a fork.** GBM's
  `gnomeos/initramfs/signed-modules.bst` needs a private signing key absent from
  the public repo. `kernel/unsigned-modules.bst` overrides it at the junction —
  the override lever used to replace something that cannot work, not something
  disliked.

Decision: no patches against `projectbluefin/common`. A template does not
inherit another distro's taste patches; add one only for a demonstrated defect.

The full image has still not been built end to end — the graph now *loads*
(`bst show oci/image.bst` succeeds), but the first real build will tune the
overlap lists and surface build-time overrides (bootc version, plymouth theme).
