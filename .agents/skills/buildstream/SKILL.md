---
name: buildstream
description: >-
  BuildStream from zero: what a project, element, junction, and directive are,
  and the commands to inspect and build the graph. Use when you have never
  worked with BuildStream, or when you need the correct kind, variable, or
  directive for a .bst file.
---

# BuildStream

If you have only ever built images with a Containerfile, this is the mental
model shift. A Containerfile is a recipe: commands run in order and each layer
is the diff. A **BuildStream project** is a *graph*: you declare what the image
is made of, and BuildStream works out how to build it, caches every step, and
composes the result. Nothing is imperative.

## The pieces

- **Project** — `project.conf` at the repo root. It names the project, sets the
  BuildStream version it needs, lists the **junctions**, the caches, and the
  default build target.
- **Element** — one `.bst` file under `elements/`. It is a node in the graph:
  either something that *builds* (`kind: manual`, `kind: autotools`, …) or
  something that *groups* other elements (`kind: stack`, `kind: compose`).
- **Junction** — a `.bst` that mounts another whole BuildStream project, so you
  can depend on its elements as `junction.bst:path/to/element.bst`. frameless
  junctions two: **freedesktop-sdk** (the OS) and **gnome-build-meta** (the
  desktop). You never copy their code; you point at it.
- **Source** — where an element's input comes from: `kind: git_repo`,
  `kind: tar`, `kind: docker`, `kind: local`, `kind: remote`.

An element's `depends:` are the runtime closure (what ends up in the image);
`build-depends:` are staged into the sandbox only while it builds.

## The directives

| Directive | Meaning |
| --- | --- |
| `(@):` | include another YAML file, merging its keys. `variables:(@)` merges into `variables:`. |
| `(?)` | a conditional block, keyed by a variable like `arch`. |
| `(>)` / `(<)` | assert a variable's version is newer / older. |

## The frameless layout

```
project.conf              the project: junctions, options, caches, default target
elements/
  freedesktop-sdk.bst     junction — the OS
  gnome-build-meta.bst    junction — the desktop
  plugins/                junction — the BuildStream plugin packages
  core/sandbox-tools.bst  shared build-sandbox shell
  desktop/gnome.bst       the desktop layer (swap this for KDE/niri/none)
  runtime/                  the bundled ublue runtime
  custom/custom.bst       your own declarations, from custom/
  oci/image.bst           the default target: the OCI image
include/                  shared YAML fragments, merged with (@)
files/                    local source payloads
scripts/                  repository tooling (validators)
custom/                   where an adopter changes the image
```

## Commands

`bst` is not installed locally. `just bst` runs it in the pinned container.

| Goal | Command |
| --- | --- |
| Validate the whole graph without building | `just bst show oci/image.bst --deps none` |
| Inspect one element's variables | `just bst show oci/image.bst --format '%{name}--%{state}'` |
| Build one element | `just bst build oci/os-release.bst` |
| Build the image | `just build` |
| Check out an element's artifact | `just bst artifact checkout oci/image.bst --directory /src/out` |
| Read a build log | `just bst artifact log runtime/common.bst` |
| Drop a cached artifact | `just bst artifact delete runtime/common.bst` |
| Refresh tracked source refs | `just track <group>` (wraps `bst source track`; `just track-groups` lists groups) |
| Enter a build sandbox | `just bst shell --build runtime/common.bst` |

When passing `--format`, avoid spaces — the Justfile recipe word-splits its
arguments. Use a separator like `--`.

## Hard-won rules

- **`bst show` before `bst build`.** It loads every element in seconds and
  catches YAML, junction, and `(@)` errors — including ones a full build would
  only hit hours in. CI enforces this in `validate-bst.yml`.
- **`include/fsdk-version.yml` is generated** by `just bst` from the pinned FSDK
  junction ref, and gitignored. Consume it inside a `variables:(@)` block; a
  bare top-level key is rejected.
- **`min-version` and the runner are one decision.** The project's `min-version`
  is a floor the installed BuildStream must clear; the pinned `bst2` container
  digest is what provides it. Bump them together.
- **freedesktop-sdk 26.08's `runtime-minimal` has no shell.** Any element that
  runs build commands build-depends on `core/sandbox-tools.bst`.
- **An upstream element can be unloadable in a fork.** gnome-build-meta's
  `signed-modules.bst` needs a private key that is not public; frameless
  overrides it at the junction (`gnomeos/initramfs/signed-modules.bst:
  kernel/unsigned-modules.bst`). Overrides are how you replace an upstream
  element without forking upstream.
- **Element names are relative to `elements/`.** `bst source track
  freedesktop-sdk.bst`, never `elements/freedesktop-sdk.bst` — BuildStream
  resolves names inside the elements directory and errors with "Did you mean…?".
- **`bst source track` rewrites the whole element, not just the ref.** It
  re-serialises the YAML in BuildStream's own style, so the first track of a
  hand-formatted element arrives with formatting churn beside the ref change.
  That is a one-time normalisation — read such a diff for its `ref:` lines.

## Where to go next

- The image graph, its caches, and the local loop → the `build` skill.
- Adding a package, app, or command → the `customize` skill.
- CI, releases, and the two-branch model → the `ci` skill.
- Something is failing → the `troubleshooting` skill.
