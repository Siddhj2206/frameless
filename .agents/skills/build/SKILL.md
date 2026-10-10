---
name: build
description: >-
  The BuildStream graph and the local loop: project.conf, junctions, the image
  layers, the Justfile recipes, identity and versioning. Use when changing how
  the image is assembled or running a build locally.
---

# Build

## The graph

`project.conf` is the source of truth for the project. It sets `min-version`,
the `arch` option, the identity variables, the read-only public caches, the
plugin junctions, and `defaults.targets` (the OCI image).

The two junctions are pinned in their own elements. Their `track`/`ref` pairs are
the base pin; `just track <group>` moves them (`bst source track`), and
`track-bst-sources.yml` opens one pull request per group. Renovate cannot:
`track:` is BuildStream's symbolic-tracking field — see
`docs/research/11-renovate-config.md`. Bumping a junction moves the image version
with it (see Versioning).

| Layer | Element | Swap it for |
| --- | --- | --- |
| Desktop | `desktop/gnome.bst` | KDE, niri, or a freedesktop-sdk stack (no GUI) |
| Runtime | `runtime/*.bst` | nothing, or your own runtime elements |
| Adopter | `custom/custom.bst` | — (this is the point) |
| Base OS | the freedesktop-sdk junction | another OS junction |

Adding image content is a line in `elements/image/deps.bst`. Never add content by
editing a built artifact.

## Caches and cache keys

BuildStream pulls before it builds. `bst build` walks the graph and, for each
element, pulls the artifact from the configured remote caches if it is there and
builds only what is missing. There is no "build everything" switch, and no way to
pull a whole image in one step: the unit is the element.

Whether an element is pulled or built is decided by its **cache key**: a SHA256
over the element's configuration, its sources, its build dependencies' own cache
keys, and the environment (project configuration and variables). The artifact is
stored under that key; the name in `bst artifact` output is only a label for it.
Two projects that compute the same key share the artifact.

That is what lets a cold build skip GNOME. Our desktop elements are
`gnome-build-meta.bst:<path>`, so their keys are GBM's own keys — and GBM pushes
its artifacts to `gbm.gnome.org:11003`. We pull them instead of building the
desktop from source.

**The project name is not in the key, and a junction boundary resets the
environment.** GBM's elements see GBM's `project.conf`, not ours, so our identity
variables cannot perturb their keys. What we pass on the junction element —
options, plugin pins, overrides, the patch queue — is the environment beneath it,
and any of it differing from GBM's own junction changes the key of *everything*
beneath, rebuilding from source: hours, not minutes. This is the rule behind
`elements/freedesktop-sdk.bst`'s "must match gnome-build-meta exactly".

The junction's `ref` is the exception, and it is cheap: bumping it only changes
the sources of the elements those upstream commits touched, because the elements
inside the junction are keyed in the junction's own project. Measured
2026-09-25: `gnome-build-meta` `51.0-3` → `51.0-5` processed **9** elements and
skipped 769. A junction bump is not automatically "the big one".

Two caches, easily conflated:

- The **remote artifact caches** in `project.conf` are upstream's artifacts —
  read-only, and the reason a first build is tractable.
- The **Actions cache** (`~/.cache/buildstream`, `save-always`) is *our* local
  cache, saved and restored between our own runs. It speeds up the second run,
  not the first.

Measured on frameless: a cold build is ~2.5 h; with the Actions cache restored,
the same graph re-runs in ~30 min and rebuilds only the elements whose inputs
changed (12 of 1098). A project-variable change reaches only the elements that
reference it, not the whole graph. The `Pipeline Summary` at the end of a build
reports `Total` and `Build Queue processed` — that is the number to watch.

The top element is always ours: `oci/image.bst` embeds our identity, so its key
is unique and it always builds. It is a compose plus a metadata step, seconds of
work; the expensive layers are the ones upstream hands us.

```bash
just bst build --deps all oci/image.bst   # pull what is cached, build the rest
just bst artifact pull oci/image.bst      # fetch without building at all
```

## The local loop

`bst` is not installed locally; `just bst` runs it in the pinned container.

```bash
just bst show oci/image.bst --deps none   # load the graph, no build
just build                                # build + load the OCI image into podman
just generate-bootable-image              # install it to bootable.raw via bootc
just boot-vm                              # boot that disk in QEMU
```

`just export` (which `just build` calls) checks out the built OCI layout, loads
it into podman as `{{image_name}}:{{image_tag}}`, and applies provenance labels.
It does not touch the graph.

The `bst` recipe regenerates `include/fsdk-version.yml` from the FSDK junction ref
on every invocation, so elements can read `%{fsdk-version}`.

## Identity and versioning

Identity is literal only in `project.conf`. `include/os-release.yml` writes
`/usr/lib/os-release`, symlinks `/etc/os-release`, and writes the ublue
`image-info.json`, reading the project name and vendor by reference. The
gnome-build-meta junction overrides its own os-release element with ours.

The version is parsed from the FSDK junction ref (`just fsdk_version`) into
`%{fsdk-version}`; os-release and the OCI label read it. `just tags` prints the
minor stream and the exact release.

## The Justfile

Groups: `info`, `build`, `run`, `test`, `dev`. `just --list` shows them all.
`just bst` is the only recipe that talks to BuildStream; everything else wraps
it or the resulting image.

`just track [group]` refreshes BuildStream source refs with `bst source track`,
grouped by element directory so a junction bump stays apart from a cheap runtime
bump; `just track-groups` lists the groups, and `scripts/bst-track-groups.sh`
derives them from the tree so a fork maintains no list. `just patch-sync` re-syncs
the FSDK patch queue after a gnome-build-meta bump.

## Rules that cost hours

- **`min-version` and the pinned `bst2` container are one decision.** The project
  needs a BuildStream at least as new as `min-version`; the container provides it.
- **Run `just bst show` before `just bst build`.** It catches graph errors in
  seconds. CI does this in `validate-bst.yml`.
- **Keep the FSDK junction in lockstep with gnome-build-meta's.** Same override
  list, same patch queue (GBM's own `elements/freedesktop-sdk.bst` is the source
  of truth; `just patch-sync` aligns the queue). Drift changes the cache key of
  every element beneath it, so the SDK rebuilds from source — see Caches and
  cache keys.
- **Parity is not only the junction.** gnome-build-meta's CI *generates* files
  before building — e.g. `files/boot-keys/modules/linux-module-cert.crt`, which
  the kernel build-depends on with `strict: true`. A clean checkout lacks them,
  so the element computes a key the public caches do not hold and rebuilds from
  source while everything around it pulls. Reproduce the generated file with a
  patch queue; `patches/gnome-build-meta` is the live example. Symptom: *one*
  upstream element rebuilds although the junction matches exactly.

## Removing an upstream element that cannot load

Override it at the junction rather than patching it:

```yaml
overrides:
  gnomeos/initramfs/signed-modules.bst: kernel/unsigned-modules.bst
```

See `elements/gnome-build-meta.bst` for the live examples.
