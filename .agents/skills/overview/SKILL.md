---
name: overview
description: >-
  Architecture, repository layout, and file map for this template. Use when
  orienting to the repository, tracing how the image is assembled, or deciding
  which skill covers a task.
---

# Overview

frameless builds a bootc operating system image from a **BuildStream graph**. You
declare what the image is made of; BuildStream builds and caches each piece and
composes the result. There is no Containerfile and no shell script that installs
packages.

If BuildStream is new to you, read the `buildstream` skill first.

## How the image is assembled

The graph has four layers, and the default target is the OCI image:

```
elements/oci/image.bst                     the default target (kind: script)
  └── elements/image/deps.bst              the manifest (kind: stack)
        ├── elements/desktop/gnome.bst     the desktop        — swap for KDE/niri/none
        ├── elements/runtime/*.bst           the ublue runtime  — ujust, brew, firstboot
        └── elements/custom/custom.bst     your declarations  — from custom/
```

The two junctions supply everything else:

- **freedesktop-sdk** (`elements/freedesktop-sdk.bst`) — the OS: the runtime,
  libraries, systemd, and the kernel.
- **gnome-build-meta** (`elements/gnome-build-meta.bst`) — the desktop: GNOME and
  its dependency tree, plus the plugin junctions and `collect_initial_scripts`.

`elements/oci/layers/` filters the composed graph into the image layer, and
`elements/oci/image.bst` runs the bootc filesystem steps and hands the layer to
`build-oci`. Identity lives in `include/os-release.yml`; the version comes from
the FSDK junction ref.

## Layout

| Path | Holds |
|---|---|
| `project.conf` | The project: name, `min-version`, junctions, options, caches, default target. |
| `Justfile` | `just bst` and the local loop: build, export, boot a VM, tests. |
| `elements/` | The graph. `desktop/`, `runtime/`, `custom/`, `oci/`, `core/`, `kernel/`, plus the junctions. |
| `include/` | Shared YAML merged with `(@)`: aliases, os-release, the generated version. |
| `files/` | The template's local source payloads: first-boot units, service overrides, the fakecap helper. |
| `scripts/` | Repository tooling: the Brewfile and Flatpak validators, the chunkah metadata tool. |
| `patches/` | The freedesktop-sdk patch queue, synced from gnome-build-meta. |
| `plugins/` | The local `chunkah-ownership` BuildStream plugin. |
| `custom/` | Where an adopter changes the image: Brewfiles, ujust, Flatpaks, files, config. |
| `tests/` | `contract/` (interfaces the image must satisfy) and `template/` (this repository's build wiring). |
| `docs/` | `research/` (findings), `learning/` (lessons and records), `agents/` (tracker conventions). |
| `.github/` | Workflows and Renovate config. |

Each directory above carries a small `README.md` explaining what it holds. Two
pairs share a leaf name and are easy to confuse:

- **`files/` vs `custom/files/`** — `files/` is the *template's* build input,
  referenced by an element as `kind: local`; `custom/files/` is the *adopter's*
  seam, a tree that mirrors `/` and is copied in by `custom/custom.bst`. Editing
  the first means editing an element; adding to the second does not.
- **`plugins/` vs `elements/plugins/`** — `plugins/` is the local chunkah plugin
  (`origin: local` in `project.conf`); `elements/plugins/` holds the junction
  elements for the upstream plugin packages.

## Which skill

| I need to… | Load |
|---|---|
| Understand the repository, or find the right skill | `overview` |
| Learn BuildStream — project, element, junction, directive | `buildstream` |
| Fork it and reach a first green build | `onboarding` |
| Add or remove a package, app, or command | `customize` |
| Change the image graph or the Justfile | `build` |
| Change a workflow, Renovate, or the release model | `ci` |
| Fix something broken, or check before a pull request | `troubleshooting` |

## Upstream

The template consumes upstream rather than copying it:

- `freedesktop-sdk` — the OS, via a junction.
- `gnome-build-meta` — the desktop, via a junction (swap it for another desktop).
- `projectbluefin/common` and `ublue-os/brew` — the ublue runtime, as git and
  docker sources in `elements/runtime/`.
- `projectbluefin/actions` — the reusable CI workflows.

Changes stay in this repository. `ublue-os/*` is read-only.
