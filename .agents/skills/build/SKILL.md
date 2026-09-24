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
variables cannot perturb their keys. Only what we pass on the junction element
crosses: the ref, the options, the plugin pins, and the overrides. Any of those
differing from GBM's own junction changes the key of everything beneath it, and
those elements rebuild from source — hours, not minutes. This is the rule behind
`elements/freedesktop-sdk.bst`'s "must match gnome-build-meta exactly".

Two caches, easily conflated:

- The **remote artifact caches** in `project.conf` are upstream's artifacts —
  read-only, and the reason a first build is tractable.
- The **Actions cache** (`~/.cache/buildstream`, `save-always`) is *our* local
  cache, saved and restored between our own runs. It speeds up the second run,
  not the first.

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

## Removing an upstream element that cannot load

Override it at the junction rather than patching it:

```yaml
overrides:
  gnomeos/initramfs/signed-modules.bst: kernel/unsigned-modules.bst
```

See `elements/gnome-build-meta.bst` for the live examples.
