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
the base pin; `Renovate` moves them. Bumping a junction moves the image version
with it (see Versioning).

| Layer | Element | Swap it for |
| --- | --- | --- |
| Desktop | `desktop/gnome.bst` | KDE, niri, or a freedesktop-sdk stack (no GUI) |
| Runtime | `runtime/*.bst` | nothing, or your own runtime elements |
| Adopter | `custom/custom.bst` | — (this is the point) |
| Base OS | the freedesktop-sdk junction | another OS junction |

Adding image content is a line in `elements/image/deps.bst`. Never add content by
editing a built artifact.

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

## Two rules that cost hours

- **`min-version` and the pinned `bst2` container are one decision.** The project
  needs a BuildStream at least as new as `min-version`; the container provides it.
- **Run `just bst show` before `just bst build`.** It catches graph errors in
  seconds. CI does this in `validate-bst.yml`.

## Removing an upstream element that cannot load

Override it at the junction rather than patching it:

```yaml
overrides:
  gnomeos/initramfs/signed-modules.bst: kernel/unsigned-modules.bst
```

See `elements/gnome-build-meta.bst` for the live examples.
