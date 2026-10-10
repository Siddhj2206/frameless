# Project Bluefin BuildStream use: dakota, fsdk-containers, server

Research note for the frameless template. It surveys three Project Bluefin
repositories that use [BuildStream 2](https://buildstream.build/) to build OS
or container images, records how each is wired, and separates the shared
pattern from the repo-specific parts.

## Scope and method

Repositories examined locally at the time of writing:

- `/var/home/sid/Projects/dakota` — branch `testing`, HEAD `3d549f4`
- `/var/home/sid/Projects/fsdk-containers` — branch `main`, HEAD `c2f584a`
- `/var/home/sid/Projects/server` — branch `main`, HEAD `5ebfeae`

The three are read-only for this note. Findings come from the files named in
the text; nothing is inferred from memory of upstream repos. Where a repo's
prose and its executable configuration disagreed, the configuration wins, in
line with dakota's own stated source-of-truth rule
(`/var/home/sid/Projects/dakota/AGENTS.md`).

### At a glance

| Axis | dakota | fsdk-containers | server |
|---|---|---|---|
| BuildStream project name | `bluefin` | `fsdk-containers` | `bluefin-server` |
| Product | bootc OCI desktop OS (GNOME OS/GBM, from source) | distroless OCI utility images from FSDK components | FSDK server OS: XFS DDI, systemd installer, k0s sysext |
| Upstream base | freedesktop-sdk + gnome-build-meta | freedesktop-sdk (raw `components/*`) + gnome-build-meta | freedesktop-sdk 26.08 (`components/*`) + gnome-build-meta |
| Element layout | hand-written namespaces (`bluefin/`, `oci/`, `gaming/`, …) | generated per-image dirs from `catalog/*.yaml` | hand-written namespaces (`bluefin-server/`, `installer/`, `oci/`, …) |
| Local plugin | `plugins/chunkah-ownership.py` | none | none |
| Container outputs | OCI to GHCR | OCI to GHCR | raw disk/DDI/sysext to GitHub Releases |
| Release model | `:testing`/`:next` streams → cosign → `:stable` promotion | FSDK-derived immutable point tags → cosign + SBOM + attestation | Renovate merge → GPG-signed `SHA256SUMS` → GitHub Release |
| Version axis | image streams (branch/gnome-build-meta) | pinned FSDK release | pinned FSDK release (`release-version`) |

---

## 1. dakota — bootc desktop image

### 1.1 Purpose and product

`dakota/README.md` describes "Bluefin built on GNOME OS, assembled entirely from
source." `dakota/AGENTS.md` is explicit that this is a BuildStream 2 bootc OCI
image, **not** an RPM-based build: no `dnf`, no `rpm-ostree`, no Containerfiles
for package content. The sole Containerfile
(`dakota/Containerfile`) is a lint helper that runs `bootc container lint` on an
already-built image.

It publishes four image variants — default, `-nvidia`, `-gaming`,
`-nvidia-gaming` — through three streams: `:testing` (dev), `:next`/`:btw`
(rolling GNOME master), and `:stable` (production, promoted from `:testing`).
Docs: `dakota/docs/build.md`, `dakota/docs/oci-assembly.md`,
`dakota/docs/ci.md`, plus per-topic `.agents/skills/dakota-*` packages.

### 1.2 `project.conf`

`dakota/project.conf`:

- `name: bluefin`; `min-version: 2.5`; `element-path: elements`.
- `(@):` includes `gnome-build-meta.bst:freedesktop-sdk.bst:include/runtime.yml`
  and the local `include/aliases.yml` (a `gnome-build-meta.bst:include/aliases.yml`
  entry is present but commented out with a FIXME).
- `options:` declares `arch` (type `arch`, variable `arch`, `aarch64`/`x86_64`),
  `x86_64_v3` (bool, default `false`), and `gaming` (bool, default `false`).
  The gaming option selects the gaming userspace stack and the OGC kernel
  (`core/linux-ogc.bst`) vs the FSDK stable kernel.
- `sandbox.build-arch: "%{arch}"`.
- `variables:` sets `branch: main`, and per-arch `go-arch` (`amd64`/`arm64`).
- `artifacts:` and `source-caches:` both list the two read-only public CAS
  endpoints used by all three repos: `https://gbm.gnome.org:11003` and
  `https://cache.projectbluefin.io:11001`, each with keepalive/retry/timeout
  connection config.
- `plugins:` registers four origins:
  - `origin: local, path: plugins` → the `chunkah-ownership` element plugin;
  - `origin: junction, junction: plugins/buildstream-plugins.bst` → `autotools`,
    `meson`, `cmake`, `make`, and the `patch`/`docker` sources;
  - `origin: junction, junction: plugins/buildstream-plugins-community.bst` →
    `collect_manifest`, `flatpak_image`, `flatpak_repo`, `ostree`, `pyproject`,
    and sources `gen_cargo_lock`, `cargo2`, `git_module`, `git_repo`,
    `go_module`, `patch_queue`, `zip`;
  - `origin: junction, junction: gnome-build-meta.bst` → `collect_initial_scripts`.
- `sources.git_repo.config.ref-format: git-describe`.

### 1.3 `elements/`

Hand-maintained tree:

- `elements/freedesktop-sdk.bst` and `elements/gnome-build-meta.bst` — the two
  junctions. FSDK tracks `freedesktop-sdk-26.08*` and carries
  `patches/freedesktop-sdk`; it overrides a long list of `components/*` onto
  gnome-build-meta versions (glib, gtk3, systemd, xdg-desktop-portal, flatpak,
  …) and swaps `components/linux.bst` for `core/linux-fdsdk.bst` (or
  `core/linux-ogc.bst` under gaming). gnome-build-meta tracks `gnome-51`,
  carries `patches` via the junction, and overrides FSDK/systemd/bootc/os-release/
  signed-modules back to local elements.
- `elements/plugins/buildstream-plugins.bst` — junction to
  `buildstream-plugins-2.5.0.tar.gz` with a local `patch_queue`
  (`patches/buildstream-plugins`, PR #91 for OCI media types in the docker source).
- `elements/plugins/buildstream-plugins-community.bst` — junction to
  `buildstream_plugins_community-2.3.1.tar.gz`.
- `elements/bluefin/` — ~60 desktop/OS elements (GNOME extensions,
  `flatpak-apps.bst`, `brew.bst`, `tailscale.bst`, `uutils-coreutils.bst`,
  `sudo-rs.bst`, dconf/firstboot/wallpaper helpers, `deps.bst`).
- `elements/bluefin-nvidia/` — NVIDIA driver and container-toolkit elements plus
  its own `os-release.bst`.
- `elements/core/` — kernel overrides (`linux-fdsdk.bst`, `linux-ogc.bst`),
  `meta-gnome-core-apps.bst`, `sandbox-tools.bst`.
- `elements/gaming/` — gaming stack, Steam compat, gamescope, inputplumber.
- `elements/gnomeos-deps/bootc.bst` — bootc element tracking ahead of GBM.
- `elements/oci/` — the image-assembly graph:
  - `oci/layers/bluefin-stack.bst` — `kind: stack`. The aggregation element:
    depends on `bluefin/deps.bst`, `oci/os-release.bst`, Linux firmware, the
    GBM initramfs, bootc, useradd/sudo config; under gaming it appends
    `gaming/deps.bst`. It carries `public.bst.integration-commands` that disable
    zram, wipe/recreate `/var` and the FHS symlinks, and create `/boot`, `/run`,
    `/sysroot/ostree` for bootc.
  - `oci/layers/bluefin.bst` — `kind: compose`, depending on the stack; excludes
    `devel`, `debug`, `static-blocklist`.
  - `oci/layers/bluefin-init-scripts.bst` — `kind: collect_initial_scripts`
    (path `/initial_scripts`).
  - `oci/bluefin.bst` — `kind: script`. The final image: stages the layer at
    `/layer` (and chunkah metadata), runs `prepare-image.sh`, `systemd-sysusers`,
    `glib-compile-schemas`, `dconf update`, `ldconfig -r /layer`, then calls the
    FSDK `build-oci` tool with an `images:` heredoc (labels, index annotation
    `org.opencontainers.image.ref.name: ghcr.io/projectbluefin/<repo>:latest`,
    `containers.bootc: '1'`).
  - `oci/os-release.bst` — `kind: manual` instantiating `include/os-release.yml`.
  - `oci/chunkah*.bst` — ownership-metadata companions (see §1.5).

Naming convention: lowercase hyphenated element names grouped by namespace
directory; the `oci/` prefix marks image-assembly elements; `layers/` holds the
stack/compose/init-scripts trio; `chunkah/` holds ownership companions.

### 1.4 `include/`

- `include/aliases.yml` — a large source-alias table (`pypi`, `github`, `gnome`,
  `kernel`, `crates`, …) used by element `url:` fields.
- `include/os-release.yml` — shared os-release/image-info generator. It sets
  `build-depends`, `depends` on `freedesktop-sdk.bst:public-stacks/runtime-minimal.bst`,
  and merges `environment` plus `config.build-commands`; instantiating elements
  supply `%{os-release-repo}`. A `(?): - gaming == true:` block appends a
  `VARIANT`/`VARIANT_ID` to os-release.

### 1.5 `plugins/` — the custom BuildStream plugin

dakota is the only one of the three with a top-level `plugins/` directory, and
its contents are Python, not Rust:

- `plugins/chunkah-ownership.py` — a `ChunkahOwnershipElement(Element)` and its
  `setup()` entry point.
- `plugins/chunkah-ownership.yaml` — default `config` values
  (`metadata-path`, `layer-dependency`, `provenance-dependencies`,
  `metadata-dependencies`, `inherit-from-components`).

The plugin builds **Chunkah component-ownership metadata**, not a filesystem
layer. It stages the already-composed `kind: compose` artifact, derives claims
from the compose inputs' manifests, records the surviving path/type structure,
and writes `ownership/basis.json`. It is registered through
`project.conf`'s `origin: local, path: plugins`, and used by
`elements/oci/chunkah/bluefin.bst`, `bluefin-nvidia.bst`, `brew-toolchain.bst`.
Its companion finalizer `scripts/ownership_metadata.py` is staged by
`elements/oci/chunkah-metadata-tool.bst` (`kind: import`, target
`ownership-tool`). The design and export-time rebinding are documented in
`dakota/docs/oci-assembly.md`.

The plugin API used is the BuildStream Python API (`from buildstream import
Element, ElementError`; `BST_MIN_VERSION`, `BST_RUN_COMMANDS = False`,
`stage_dependency_artifacts`, `compute_manifest`, `export_to_tar`).

### 1.6 `patches/`, `files/`

`patches/` holds per-upstream queues consumed by `patch_queue` sources:
`patches/freedesktop-sdk/`, `patches/gnome-build-meta` (via junction),
`patches/buildstream-plugins/`, `patches/linux/`, `patches/linux-ogc/`,
`patches/ghostty/`, `patches/gsconnect/`, `patches/tilingshell/`,
`patches/shell-extensions/`. `patches/freedesktop-sdk.manifest.json` records a
hash of each patch and the gnome-build-meta SHA so `just patch-drift-check` can
verify the queue offline.

`files/` holds all static content installed by elements, grouped by feature:
`bindmounts/`, `bootc-install/`, `chairlift/`, `countme/`, `dconf/`,
`distrobox/`, `fakecap/` (C helpers compiled into the image), `firstboot/`,
`just-overrides/` (end-user `ujust` recipes), `linux/` and `linux-ogc/`
(kernel config fragments), `migrate-var-home-passwd/`, `nvidia-device-nodes/`,
`oci/`, `plymouth/`, `scripts/` (`bst-progress.py`,
`generate_cargo_sources.py`), `service-overrides/`, `swapfile/`, `sysusers/`,
`tailscale/`, `udev/`, `user-avatars/`, `wallpaper-month/`, `wireplumber/`.

There is no `catalog/` and no `Formula/` in dakota.

### 1.7 `Justfile` and `scripts/`

`dakota/Justfile` is ~65 KB and is the local orchestrator. Key settings and
recipes:

- Environment: `BUILD_IMAGE_NAME` (default `dakota`), `BUILD_GAMING`,
  `BST2_IMAGE` (default the FSDK `bst2` image, unpinned tag), `OCI_IMAGE_*`.
- `bst *ARGS` — runs any `bst` command inside the `bst2` container via
  `podman run --privileged --device /dev/fuse --network=host`, bind-mounting the
  repo at `/src` and `~/.cache/buildstream`, defaulting to
  `-o x86_64_v3 false -o gaming <gaming> --no-interactive`. Honours
  `BST_FLAGS`, `BST_FLAGS_OVERRIDE`, `BST_RUNNER`, `BST_PODMAN_EXTRA_ARGS`.
- `validate` — local graph check plus Python tests; CI runs
  `check-publish-workflow` (the suite registered for CI).
- `build [variant]` — `bst build` then `just export`.
- `export [variant]` — `bst artifact checkout` into `.build-out`, loads with
  podman, squashes to one layer, rewrites `VERSION_ID`/`IMAGE_VERSION` in
  `os-release` while preserving mtimes, then rebinds the exact image ID to
  Chunkah ownership metadata under `.build-ownership/`.
- `chunkify` — Chunkah layer generation using the fakecap xattr shim.
- `sbom [variant]` — installs `buildstream-sbom` (pinned GitLab commit) inside
  the bst2 container and emits `dakota.spdx.json`.
- `lint`, `swap-audit`, `avatar-audit`, `boot-test`, `boot-fast`,
  `show-me-the-future`, `patch-drift-check`/`patch-sync`.
- `scripts/` holds Python tooling: `check_publish_workflow.py`,
  `compare_oci_layers.py`, `ownership_metadata.py`, `image_variants.py`,
  `render_card.py`, `sbom_diff.py`, and their `test_*.py` suites plus
  `scripts/fixtures/`.

### 1.8 CI and release

Workflows live in `dakota/.github/workflows/`.

- `build.yml` — "Build Bluefin dakota". Triggers on push to `testing`/`next`, a
  daily schedule, `workflow_dispatch`, and a label-gated `pull_request`.
  Verifies the default branch is `testing`, runs a stale-check against queued
  runs (`concurrency: queue: max`), then builds a 4-variant matrix
  (`default`/`nvidia`/`gaming`/`nvidia-gaming`) with
  `projectbluefin/actions/bootc-build/setup-runner` and the local
  `generate-bst-ci-config` composite action. It builds
  `--deps none <element>` with remote execution and asserts the remote-execution
  banner appeared. `pr-image` pushes a `:pr-N` tag for labelled PRs (never signed
  or promoted).
- `publish.yml` — "Publish Bluefin dakota". Triggered by `workflow_run` of
  `build.yml` on `next`/`testing`. Exports the image from the remote CAS
  (fetch-only config), runs `chunkify`, `bootc container lint`, audits, pushes
  an immutable `:<sha>`, signs with cosign and attests via
  `projectbluefin/actions/bootc-build/sign-and-publish`. SBOM attach/sign is a
  separate job. `promote` uses `skopeo copy --preserve-digests` to move `:<sha>`
  onto `:testing`/`:next` (and `:btw` for next) and verifies the resulting digest.
- `execute-release.yml` — "Execute Release". Freshness-check resolves the
  published `testing` digest and compares against `:stable`; then calls
  `projectbluefin/actions/.github/workflows/reusable-execute-release.yml@v1` to
  promote to `stable` with a cosign identity regexp anchored to `publish.yml`,
  force-updates the `main` bookmark, generates release notes via
  `reusable-release.yml`, updates variant digests, and optionally builds a
  `:stable-multiarch` manifest from a SHA-pinned aarch64 image.
- Supporting workflows: `build-aarch64.yml`, `boot-test-aarch64.yml`, `e2e.yml`,
  `nightly-next-build.yml`, `sync-next.yml`, `track-bst-sources.yml`,
  `track-next-junctions.yml`, `rollback-stable.yml`, `publish-smoke.yml`,
  `run-testsuite.yml`, plus validate/security/renovate/scorecard/triage.

Artifact cache and remote execution are configured by
`.github/actions/generate-bst-ci-config/action.yml`: it writes
`buildstream-ci.conf` with a writable `https://cache.projectbluefin.io:11002`
CAS (mTLS client cert/key from `CASD_CLIENT_*`), read-only
`gbm.gnome.org:11003` and `cache.freedesktop-sdk.io:11001`, and — when remote
execution is enabled — `remote-execution`/`storage-service`/`action-cache-service`
stanzas pointing at the same endpoint. `cache.cache-buildtrees: never`.

### 1.9 Rust/Cargo tooling

There is **no Rust or Cargo workspace** in any of the three repos, and none of
them builds a custom BuildStream plugin in Rust. Rust software is consumed as a
packaged element:

- `elements/bluefin/sudo-rs.bst` (`kind: make`) depends on
  `freedesktop-sdk.bst:components/rust.bst` and sources sudo-rs from git plus a
  `cargo2` source block listing crates.
- `elements/bluefin/uutils-coreutils.bst` likewise uses `cargo2`.
- `files/scripts/generate_cargo_sources.py` is a small Python helper that reads
  a `Cargo.lock` and prints the `cargo2` `sources:` YAML (`kind: registry` entries
  with name/version/sha). `dakota/AGENTS.md` documents the invocation:
  `python3 files/scripts/generate_cargo_sources.py <Cargo.lock>`.

The `cargo2` source itself comes from the `buildstream-plugins-community`
junction. So "custom tooling that builds bst plugins" is Python in dakota, and
Rust enters only as build input.

---

## 2. fsdk-containers — distroless OCI images

### 2.1 Purpose and product

`fsdk-containers/README.md`: "Bringing distroless patterns to freedesktop-sdk
(FSDK) containers." It carves runtime-only, slim-by-default images out of raw
FSDK `components/*` instead of maintaining a package set. Published targets
(`elements/targets.json` `oci_images`): `base`, `static`, `skopeo`,
`lab-runner`, `python`, `buildah`, `qemu-img`, `review-runtime`. There is also
a non-OCI `brew` systemd-nspawn machine image and a `podman-vm` guest disk.

Hard rules from `fsdk-containers/AGENTS.md`: compose from `components/*`, never
`platform.bst`; no `x86_64_v3`; don't duplicate upstream distroless images;
distroless means no shell (the SLIM recipe removes it explicitly). Versioning is
the FSDK release parsed from `elements/freedesktop-sdk.bst`; the repository
deliberately publishes **no `:latest`**.

### 2.2 `project.conf`

`fsdk-containers/project.conf`:

- `name: fsdk-containers`; `min-version: 2.5`; `element-path: elements`.
- `(@):` includes `gnome-build-meta.bst:freedesktop-sdk.bst:include/runtime.yml`
  and local `include/aliases.yml`.
- `options.arch` (`aarch64`, `x86_64`); `sandbox.build-arch: "%{arch}"`;
  per-arch `go-arch`.
- `artifacts:`/`source-caches:` — the same two read-only public caches as the
  other repos (`gbm.gnome.org:11003`, `cache.projectbluefin.io:11001`); the
  comment states "Pull-only".
- `plugins:` — two junction origins: `buildstream-plugins-community.bst` with
  `git_repo`, `go_module`, `patch_queue`; and `gnome-build-meta.bst` with
  `collect_initial_scripts`.
- `sources.git_repo.config.ref-format: git-describe`.

Unlike dakota, it does **not** register `buildstream-plugins.bst` sources at the
project level (the junction exists but is only overridden into GBM).

### 2.3 `elements/` — generated from a catalog

The distinctive feature: elements are **generated**, not hand-edited. Each image
is a record in `catalog/<name>.yaml`; `scripts/generate_image_elements.py`
(`just catalog-write`) writes the elements, and `just catalog-check` fails CI if
they are stale. Generated files carry a `DO NOT EDIT` header.

Layout per target (`elements/<name>/`):

- `<name>-stack.bst` — `kind: stack` listing `freedesktop-sdk.bst:...` and base
  dependencies.
- `<name>-runtime.bst` — `kind: compose`, excluding the canonical domains
  (`debug`, `devel`, `doc`, `locale`, `shells`, `static-blocklist`, `tests`,
  `vm-only`).
- `<name>-init-script.bst` — `kind: collect_initial_scripts` (default
  `base/base-init-script.bst`).
- `elements/oci/<name>.bst` — `kind: script`, the `build-oci` assembly with the
  `include/slim.yml` and `include/fsdk-version.yml` variables.

Example (`elements/oci/base.bst`): build-depends on `bootstrap/bash.bst`,
`bootstrap/coreutils.bst`, `components/oci-builder.bst`, `base/base-init-script.bst`,
and stages `base/base-runtime.bst` at `/layer`; commands run
`%{slim-distroless-commands}`, run any `/initial_scripts/*`, then `build-oci`
with the OCI/ArtifactHub label set and index annotation
`ghcr.io/projectbluefin/base:%{fsdk-version}`.

`elements/targets.json` is the canonical manifest: `oci_images`, per-image
`image_paths` (path ownership), `shared_paths`, `canary_image: base`, and
`vm_guest_paths`. It drives the CI matrices, `just validate`, and the PR
`changed-targets` gate.

`elements/freedesktop-sdk.bst` tracks `freedesktop-sdk-26.08*`, carries
`patches/freedesktop-sdk`, and documents that FSDK 26.08's own systemd is used
because gnome-build-meta still targets 25.08.
`elements/gnome-build-meta.bst` tracks `gnome-50`, carries
`patches/gnome-build-meta`, and overrides `freedesktop-sdk.bst` and the two
plugin junctions back to local ones.

Image families each have their own directory building a CLI or runtime from
FSDK: `buildah/`, `curl/`, `falco/`, `go/`, `go-md2man/`, `kubestellar-hive/`,
`lab-runner/`, `mariadb/`, `nginx/`, `node/`, `postgres/`, `python/`,
`qemu-img/`, `review-runtime/`, `skopeo/`, `static/`, `valkey/`, `volcano/`,
plus `podman-vm/` and `brew/` for the non-OCI lanes.

### 2.4 `include/`

- `include/aliases.yml` — a deliberately small alias table (`pypi`, `github`,
  `gitlab`, `gnome`, `k8s-bin`), with a comment that only referenced aliases are
  listed.
- `include/slim.yml` — the shared runtime-domain cleanup shell, defining
  `slim-distroless-commands` (remove shells, sanitizers, gconv long tail,
  `locale-archive`, `localedef`/`ldconfig`, pcre extras; keep terminfo) and
  `slim-shell-enabled-commands` (also drop Perl, plus git's perl scripts).
- `include/slim-python.yml` — per-family bloat stripping for Python
  (`slim-python-commands`); the file explains the per-family fragment pattern
  and lists measured candidates deliberately not applied yet.
- `include/fsdk-version.yml` is **generated and gitignored** (see
  `.gitignore`); `just bst` writes it from the pinned FSDK ref into a
  `%{fsdk-version}` variable.

### 2.5 `plugins/`

There is no top-level `plugins/` directory and no custom element plugin. The
same two junction elements exist (`elements/plugins/buildstream-plugins.bst`,
`elements/plugins/buildstream-plugins-community.bst`), both plain tarball
junctions (the dakota docker patch is absent).

### 2.6 `patches/`, `catalog/`, `scripts/`, `tests/`

- `patches/freedesktop-sdk/0001-project.conf-Add-GNOME-CAS-servers.patch` and
  `patches/gnome-build-meta/disable-lorry-mirrors.patch`.
- `catalog/` — base/buildah/lab-runner/python/qemu-img/review-runtime/skopeo/
  static records plus `schema.json` (JSON Schema draft 2020-12). A record
  declares name, kind (`distroless`/`shell-enabled`), description, optional
  entrypoint, `smoke`, `size_ceiling_mib`, ordered `stack.depends`, compose
  omissions, slim includes, gates, init script, notes, keywords.
- `scripts/` — `catalog.py` (load/validate records), `verify_contract.py`
  (derive verification gates/smoke argv from a record), `generate_image_elements.py`
  (render elements), `check_multiarch_refs.py`, `generate_skill_index.py`.
- `tests/` — catalog conformance/gate-coverage/tracked-refs tests, generated
  element tests, `verify_contract` tests, `vm-boot.sh`,
  `oci-publish-smoke-contract.sh`, `podman-vm-contract.sh`.

No `files/` at the top level; file payloads are element-local, e.g.
`elements/base/files/xterm-ghostty.terminfo` and
`elements/kubestellar-hive/files/{go.mod,go.sum,modules.txt}`.

### 2.7 `Justfile` and scripts

`fsdk-containers/Justfile`:

- `bst *ARGS` regenerates `include/fsdk-version.yml` from `fsdk_version`, then
  runs `bst` in the SHA-pinned `bst2` container. By default it submits to the
  ghost cluster's BuildBarn remote-execution grid via `kubectl port-forward`
  and writes `.bst-re.conf`; `BST_LOCAL=1` (or `GITHUB_ACTIONS=true`) forces
  local execution, and an unreachable cluster fails loudly.
- `tags` derives the FSDK minor line and point release (no `:latest`);
  `image-list`/`image-matrix` read `elements/targets.json`.
- `changed-targets BASE HEAD` implements the PR path-ownership gate.
- `catalog-write` / `catalog-check` / `skill-catalog-check`.
- `validate` resolves every image plus the podman-vm EFI element for both
  arches; `build` builds + exports; `export` squashes to one layer and applies
  labels from the catalog record; `tag-push`/`push-quay`; `verify` derives its
  gates and smoke command from the catalog via `verify_contract.py`.
- `sboms`, `podman-vm-*`, `brew-*` recipes.

### 2.8 CI and release

`fsdk-containers/.github/workflows/`:

- `build.yml` — orchestrator. On PR: `validate`, `changed-targets`,
  `pr-build-oci` (build + verify per selected image × `x86_64`/`aarch64`, no
  login/push/sign path), `pr-guest-contract`, `pr-build-vm-guest`, and a
  multi-arch ref-parity check. On push/dispatch: resolves the image matrix from
  `elements/targets.json` and calls the reusable `oci-images.yml` once per image;
  also calls `vm-guest.yml`.
- `oci-images.yml` — reusable per-image pipeline. `build` job per arch:
  build + `just verify`, then push to `ghcr.io/<owner>/<image>-<arch>`. `manifest`
  job: derives tags with `just tags`, assembles per-arch images into a multi-arch
  index with `docker buildx imagetools create` (promoting image config labels to
  index annotations because podman 4.9 can't annotate an index), treats the FSDK
  point-release tag as immutable, generates a BuildStream-native SBOM
  (`just sbom`), keyless-signs with cosign, attaches and signs the SBOM with
  `oras`, publishes a GitHub attestation, and registers the image with Artifact
  Hub. `publish-smoke` pulls the published per-arch image, runs the
  catalog-derived smoke command, verifies the cosign signature and the SBOM
  referrer.
- Other workflows: `auto-update-fsdk.yml`, `refresh-bst-refs.yml`,
  `image-catalog.yml`, `skill-catalog.yml`, `ghcr-cleanup.yml`,
  `vulnerability-scan.yml`, `renovate.yml`, `actionlint.yml`, `ci-alert.yml`,
  `brew-nspawn.yml`, `vm-guest.yml`, `scorecard.yml`.

### 2.9 Rust/Cargo tooling

None. Rust/Go binaries are built as elements with `go_module` / `cargo2` sources
from the community plugins junction. The `kubestellar-hive` and `volcano`
elements keep `go.mod`/`go.sum` as element-local sources.

---

## 3. server — FSDK-based server OS

### 3.1 Purpose and product

`server/README.md`: "An FSDK-based, image-based Linux server OS." It targets the
Flatcar/CoreOS/Talos space but is built from FSDK 26.08 components and uutils
coreutils, using a DDI-first design. Products (declared in `server/AGENTS.md`):

- `elements/oci/bluefin-server-ddi.bst` — compressed XFS DDI OS payload.
- `elements/oci/bluefin-server-installer.bst` — offline, systemd-native raw disk
  installer.
- `elements/oci/k0s-sysext.bst` — optional k0s `systemd-sysext`.

`server/CONTEXT.md` is the domain glossary (OS DDI, Installer, Sysext,
Transfer, countme); `server/NOTES.md` records the tooling stack, release
lifecycle, and sysupdate contracts.

### 3.2 `project.conf`

`server/project.conf`:

- `name: bluefin-server`; `min-version: 2.5`; `element-path: elements`.
- `(@):` includes `gnome-build-meta.bst:freedesktop-sdk.bst:include/runtime.yml`
  and local `include/aliases.yml`.
- `options.arch` (`aarch64`, `x86_64`); `sandbox.build-arch: "%{arch}"`.
- `variables.release-version: "26.08.0"` — the single asset-version axis, which
  must match the FSDK point release pinned in `elements/freedesktop-sdk.bst`;
  enforced by `.github/scripts/check-release-version.py`.
- `artifacts:`/`source-caches:` — the same two read-only public caches,
  "Pull-only".
- `plugins:` — `buildstream-plugins-community.bst` with `git_repo`,
  `patch_queue`, `cargo2`; and `gnome-build-meta.bst` with
  `collect_initial_scripts`.
- `sources.git_repo.config.ref-format: git-describe`.

### 3.3 `elements/`

Hand-maintained namespaces:

- `elements/freedesktop-sdk.bst` — FSDK 26.08 junction with
  `patches/freedesktop-sdk`; same systemd note as fsdk. Pinned ref carries a
  `# renovate:` marker.
- `elements/gnome-build-meta.bst` — junction tracking `gnome-50` with
  `patches/gnome-build-meta`, overriding FSDK and the plugin junctions back to
  local.
- `elements/base/base-stack.bst` — minimal distroless runtime stack
  (`runtime-gnu` + `runtime-minimal`, ca-certificates, tzdata, os-release,
  extra-fs, ldconfig).
- `elements/bluefin-server/` — the OS build:
  - `os-stack.bst` — `kind: stack` aggregating the entire OS (runtime, uutils,
    systemd, SSH, Flatcar kernel/ZFS, sysupdate configs, keys, gpg, podman,
    countme, justfile, issue banner).
  - `os-rootfs.bst` — `kind: compose`, excludes `debug`/`devel`/`doc` and sets
    `integrate: False`.
  - identity/update elements: `os-image-info.bst`, `os-release-flatcar.bst`,
    `os-sysupdate.bst`, `os-sysupdate-keys.bst`, `os-k0s-sysupdate.bst`,
    `os-k0s-first-boot.bst`, `os-networkd.bst`, `os-countme.bst`,
    `os-sshd-*.bst`, `os-creds-prov.bst`, `os-kured-hook.bst`, `os-issue.bst`,
    `os-justfile.bst`, `uutils-coreutils.bst`, `linux-firmware-split.bst`.
- `elements/flatcar/` — `flatcar-kernel.bst`, `flatcar-zfs.bst` (Flatcar LTS
  kernel/ZFS from upstream Flatcar sources).
- `elements/installer/` — `installer-stack.bst` (live installer rootfs) and
  `installer-repart.bst` (`kind: import` of `files/installer/repart.d`).
- `elements/k0s/k0s-bin.bst`.
- `elements/oci/` — the three products described above. `bluefin-server-ddi.bst`
  and `bluefin-server-installer.bst` are `kind: script`; `k0s-sysext.bst` is
  `kind: manual`. The installer script embeds the DDI via `systemd-repart`,
  packs a cpio initrd, builds a UKI with `ukify`, and emits
  `.raw.zst` + `SHA256SUMS`. The sysext builds an EROFS image with `mkfs.erofs`
  and compresses it.
- `elements/plugins/` — the two plugin junctions.

### 3.4 `include/`

- `include/aliases.yml` — small alias table (`pypi`, `github`, `gitlab`, `gnome`,
  `crates`, `flatcar`).
- `include/arch.yml` — maps `%{arch}` to `systemd-arch` and `flatcar-board`
  identity strings.
- `include/flatcar.yml` — `flatcar-version` / `flatcar-kver` lockstep values.
- `include/k0s.yml` — the two k0s atoms and derived `%{k0s-version}`,
  `%{k0s-upstream-tag}`.

### 3.5 `plugins/`

No top-level `plugins/` and no custom element plugin; only the two junction
elements under `elements/plugins/`.

### 3.6 `patches/`, `files/`, `Formula/`

- `patches/` — `flatcar-kernel/` (seven `z000*.patch` files for reproducible
  builds, secure boot, partition UUIDs), `freedesktop-sdk/` (five patches
  including CAS servers, glib stage1 tests, symlinks), `gnome-build-meta/`
  (`disable-lorry-mirrors.patch`, `upgrade-systemd-v261.patch`).
- `files/` — `bin/` (`bluefin-kubestellar`, `system-container` shell tools),
  `installer/repart.d/` (`10-esp.conf`, `20-root-a.conf`, `30-var.conf`),
  `k0s/` (kiosk, kubeflex, manifests, sysext, extension-release),
  `lima/`, `os/` (`issue.d/`, `justfile`, `ssh/`, `systemd/`,
  `sysupdate.d/50-root.transfer` + `60-uki.transfer`, `sysupdate.k0s.d/`,
  `sysupdate-keys/`, `sysusers.d/`).
- `Formula/` — Homebrew formulae for developer workstations, not image content:
  `bluefin-kubestellar.rb` and `kc-agent.rb`.
- `scripts/lima-e2e-kubestellar-test.sh`; `tests/unit/` (pytest + bats) and
  `tests/e2e/`.
- There is no `catalog/` in server. There is a top-level `workflows/`
  directory holding `server-release-watch-and-fix.md`, a design document for a
  release watch/fix loop — note this is *not* the GitHub Actions directory
  (that is `.github/workflows/`).

### 3.7 `Justfile` and scripts

`server/Justfile`:

- `bst *ARGS` — runs `bst` inside the SHA-pinned `bst2` container (same digest
  as fsdk), with `--no-interactive --error-lines 500` and `%{BST_FLAGS}`.
- `fsdk_version` parsed from the FSDK junction; `version`; `tags` prints
  `latest`, minor line, and point release.
- `validate` — runs version-alignment checks and `bst show --deps all` for the
  three products.
- `build-ddi`/`export-ddi`, `build-installer`/`export-installer`, `export-pxe`,
  `build-sysext`/`export-sysext`, `build-kernel`/`build-zfs`/`export-kernel` —
  each builds with `bst` and checks out to `dist/`.
- `cluster-build` submits to Argo (`wftmpl/bluefin-server-build-pipeline`);
  `AGENTS.md` says heavy builds must run on the ghost cluster.
- `test-unit` (pytest + bats), `show-me-the-future` (build → export → QEMU
  installer smoke), `install-vm`, `test-e2e-lima`.

### 3.8 CI and release

`server/.github/workflows/`:

- `build.yml` — "Build DDI artifacts", triggered on PR, push to `main`, and
  `workflow_dispatch`. Workflow default token is read-only. Jobs:
  - `track-refs` (only `renovate/*` PRs) runs `bst source track` and pushes the
    resolved refs back with a write token.
  - `build` runs `just validate`, builds and exports DDI, installer/UKI/PXE,
    sysext, kernel + ZFS; uploads installer test artifacts; on `main` it also
    combines all assets into `dist/release/`, writes `SHA256SUMS`, GPG-signs it
    (`SHA256SUMS.gpg`, secret `SYSUPDATE_SIGNING_KEY`), and uploads a
    `release-assets` artifact.
  - `installer-test` calls the reusable
    `projectbluefin/actions/.github/workflows/server-installer-test.yml` pinned
    to a commit.
  - `release` (only `main`) creates the GitHub Release `installer-v<version>`
    and uploads `dist/release/*`.
- `kernel.yml`, `unit-tests.yml`, `docs-checks.yml` (runs
  `.github/scripts/docs-checks.py`).
- No OCI registry, no cosign, no GHCR: the release is raw artifacts plus a
  GPG-signed manifest consumed by `systemd-sysupdate`.

### 3.9 Rust/Cargo tooling

None as a workspace. `elements/bluefin-server/uutils-coreutils.bst` uses the
`cargo2` source plugin to build uutils coreutils from source. The `cargo2`
source comes from the community plugins junction (declared in `project.conf`).

---

## 4. Comparison

### 4.1 The common Project Bluefin BuildStream pattern

All three are the same skeleton with different payloads:

1. **BuildStream 2.5 project.** `min-version: 2.5`, `element-path: elements`,
   and a `project.conf` that includes
   `gnome-build-meta.bst:freedesktop-sdk.bst:include/runtime.yml` plus a local
   `include/aliases.yml`.
2. **Architecture axis.** An `arch` option (`aarch64`/`x86_64`) bound to
   `%{arch}`, `sandbox.build-arch: "%{arch}"`, and derived `go-arch` variables.
3. **Two upstream junctions.** `elements/freedesktop-sdk.bst` (tracks
   `freedesktop-sdk-26.08*`, carries a `patch_queue`) and
   `elements/gnome-build-meta.bst` (tracks a gnome-50/51 branch, carries a
   `patch_queue`, overrides FSDK and the plugin junctions back to local). The
   gnome-build-meta junction is present even where only FSDK components are
   used, because it supplies the plugin junctions and `collect_initial_scripts`.
4. **Plugin junctions.** `elements/plugins/buildstream-plugins.bst`
   (upstream 2.5.0) and `elements/plugins/buildstream-plugins-community.bst`
   (community 2.3.1), with `sources.git_repo.config.ref-format: git-describe`.
5. **Read-only public CAS.** The same `gbm.gnome.org:11003` and
   `cache.projectbluefin.io:11001` artifact and source caches, with identical
   connection-tuning stanzas. CI adds an authenticated writable
   `cache.projectbluefin.io:11002`.
6. **OCI assembly shape.** `kind: stack` (dependency aggregation) →
   `kind: compose` (chisel/filter, integrate) → `kind: script` calling the FSDK
   `oci-builder`/`build-oci` tool → `collect_initial_scripts` for init scripts.
   Labels and an `index-annotations` `org.opencontainers.image.ref.name` are set
   in the `build-oci` heredoc.
7. **Justfile as orchestrator.** A `just bst *ARGS` wrapper runs `bst` inside
   the FSDK `bst2` container via `podman run --privileged --device /dev/fuse
   --network=host -v <repo>:/src`, and the FSDK version is parsed from the
   junction ref as the single version source.
8. **CI infrastructure reuse.** `projectbluefin/actions`
   (`bootc-build/setup-runner`, `bootc-build/sign-and-publish`,
   `reusable-execute-release`, `reusable-release`, reusable test workflows) and
   the `generate-bst-ci-config` composite action pattern.
9. **Agent-first documentation.** Each repo carries `AGENTS.md`, a
   `.agents/skills/` or `docs/skills/` tree, a domain `CONTEXT.md`/`NOTES.md`,
   and skill-routing tables. `patches/` is the conventional home for
   `patch_queue` queues.

### 4.2 How they differ

- **Output type and publication channel.** dakota publishes a bootc OCI desktop
  image to GHCR; fsdk publishes multiple distroless OCI images to GHCR; server
  publishes raw disk/DDI/sysext assets to GitHub Releases with GPG-signed
  manifests. Only dakota and fsdk use `oci-builder`; server's key script
  elements produce XFS/EROFS images with `systemd-repart`, `mkfs.xfs`, and
  `mkfs.erofs`.
- **Upstream composition.** dakota sits on gnome-build-meta and overrides many
  FSDK components upward; fsdk and server deliberately avoid `platform.bst` and
  compose raw FSDK `components/*` (fsdk's headline rule; server's hard rule 1).
- **Element authoring model.** fsdk generates elements from `catalog/*.yaml`
  and treats hand edits as errors; dakota and server hand-maintain namespaced
  element trees. This is the largest structural divergence.
- **Custom plugins.** Only dakota has a local plugin
  (`plugins/chunkah-ownership.py`) and an export/ownership pipeline. fsdk and
  server have no local plugin and no `plugins/` directory.
- **Verification model.** fsdk encodes per-image verification in catalog records
  and derives gates with `scripts/verify_contract.py`; dakota uses `bootc
  container lint` plus shell/Python audits; server uses pytest/bats unit tests
  and QEMU installer tests.
- **Remote execution.** dakota and fsdk both route heavy builds to remote
  execution (dakota to `cache.projectbluefin.io` via mTLS config; fsdk to the
  ghost cluster's BuildBarn grid via `kubectl port-forward`), while server's CI
  builds locally in the bst2 container and reserves cluster builds for the
  documented `cluster-build` Argo path.
- **Release/version model.** dakota's version axis is its branch streams and the
  gnome-build-meta stream, with `:stable` promoted by digest. fsdk and server
  use the pinned FSDK release as the version; fsdk derives immutable point tags
  and forbids `:latest`, server derives `release-version` and a release tag from
  it. fsdk signs with keyless cosign + SBOM + attestation; dakota signs with
  cosign and promotes; server signs a `SHA256SUMS` manifest with GPG.
- **Architecture coverage.** fsdk is fully multi-arch
  (`x86_64`/`aarch64` native runners); dakota builds `x86_64` as the gate and
  folds in a SHA-pinned aarch64 image into `:stable-multiarch`; server's k0s
  sysext explicitly errors on non-`x86_64`, so it is x86_64-led.
- **Micro-architecture.** dakota has an `x86_64_v3` option (default off); fsdk
  and server ban it to keep the CPU baseline broad.
- **Justfile size and scope.** All three are large, but dakota's (~65 KB, with a
  full VM/Chunkah/export toolkit) and fsdk's (~47 KB, with catalog generation and
  VM/brew lanes) are substantially more than server's (~21 KB).

---

## 5. What a new BuildStream template ("frameless") could reuse

frameless today is a Containerfile-based bootc image template
(`README.md`, `Containerfile`, `build/*.sh`, `custom/`) with no `project.conf`
and no BuildStream elements. If a BuildStream lane is added, the three repos
offer a clear reuse split.

### 5.1 Reusable directly

- **`project.conf` skeleton:** project name, `min-version: 2.5`,
  `element-path: elements`, the `arch` option and `sandbox.build-arch`, the
  `go-arch` mapping, the two read-only CAS stanzas, the two plugin junctions,
  and `sources.git_repo.config.ref-format: git-describe`. All three are nearly
  identical, so this is the most copy-ready artifact.
- **Junction elements:** `elements/freedesktop-sdk.bst`,
  `elements/gnome-build-meta.bst`, `elements/plugins/buildstream-plugins.bst`,
  `elements/plugins/buildstream-plugins-community.bst`. These are short and
  differ mainly in the pinned ref/track; the `patch_queue` wiring is reusable.
- **The `just bst` wrapper** and the FSDK-version-from-junction-ref trick. The
  fsdk/server variants are the cleanest (pinned bst2 digest); dakota's adds
  `BST_RUNNER`/override support worth copying for tests.
- **The `stack` → `compose` → `script(build-oci)` → `collect_initial_scripts`
  OCI assembly pattern**, including the `build-oci` heredoc with image labels
  and `index-annotations` (dakota's `elements/oci/bluefin.bst` or fsdk's
  generated `elements/oci/base.bst` are the references).
- **`include/aliases.yml`** as a starting alias table (fsdk/server keep it small;
  dakota's is the full example).
- **CI plumbing:** the `generate-bst-ci-config` composite action
  (dakota's `.github/actions/generate-bst-ci-config/action.yml`) is a
  self-contained way to emit a mTLS CAS + remote-execution config; fsdk's
  `oci-images.yml` is the reference reusable per-image build/manifest/sign/SBOM
  pipeline; projectbluefin's shared `setup-runner`,
  `sign-and-publish`, `reusable-execute-release`, and `reusable-release`
  workflows.
- **A canonical target manifest + generation pattern.** fsdk's
  `elements/targets.json` + `catalog/*.yaml` + `scripts/generate_image_elements.py`
  + `scripts/verify_contract.py` + `elements/<name>/{stack,runtime,init-script}.bst`
  is the strongest reusable idea for a template that will host more than one
  image: adding a target is one YAML record and no workflow edit, and the PR
  gate can build only the affected targets. The schema and generator are
  repo-neutral enough to lift with a rename.
- **Path-derived CI matrix** (`just changed-targets` / `shared_paths` /
  `canary_image`) is reusable for any multi-target repo.
- **The `stack → compose → script` OCI label set** (Project Bluefin vendor,
  source URL, license, ArtifactHub labels) is a reusable convention.

### 5.2 Reusable with adaptation

- **`kind: stack` composition of FSDK `components/*`** — the fsdk/server
  `base/base-stack.bst` is a good minimal starting point, but the exact
  component list is product-specific.
- **The release-signing workflow shape** — dakota's
  `:sha` → `:testing` → `:stable` promotion with digest checks, and fsdk's
  cosign + SBOM + attestation + ArtifactHub sequence, are patterns a template
  can adopt, but the identities, secrets, and tag policy must be re-derived.
- **Python verification tooling** (`verify_contract.py`, `catalog.py`) — the
  approach is reusable; the concrete gates (distroless no-shell, tzdata/CA
  baseline) are fsdk-specific.

### 5.3 Repo-specific, do not copy wholesale

- **dakota:** the `chunkah-ownership` plugin and the entire Chunkah
  export/chunkify/ownership pipeline; the GNOME/desktop element tree
  (`elements/bluefin/`, `elements/gaming/`, `elements/bluefin-nvidia/`); the
  gaming/NVIDIA variants; the image-stream and `next`/`btw` model; the feedback
  loop. These encode desktop-OS concerns a generic template does not need.
- **fsdk:** the `slim.yml`/`slim-python.yml` recipes and distroless contract
  gates; `podman-vm`; the `brew` nspawn machine image; and the specific
  component-carving knowledge. The *idea* of per-image slim fragments is
  reusable; the removal lists and size ceilings are not.
- **server:** the Flatcar LTS kernel/ZFS elements, the DDI/installer/
  `systemd-repart` pipeline, the k0s `systemd-sysext`, the `systemd-sysupdate`
  transfers and GPG manifest signing, and the `Formula/` Homebrew packaging.
  All are server-OS concerns.
- **The large hand-written Justfiles.** A template should factor the shared
  recipes (`bst`, version/tags, validate, build/export) into a small base and
  leave feature recipes to the adopting repo, rather than copying a 50 KB file.
- **Patches tied to specific upstream versions** (kernel `z000*`, systemd v261,
  glib stage1). These are point-in-time and belong to the consuming repo.

### 5.4 A note on custom plugins

None of the three builds BuildStream plugins in Rust or Cargo; the only custom
plugin is dakota's Python `chunkah-ownership`. If frameless wants custom
BuildStream elements, the established route is a Python module registered with
`origin: local, path: plugins` in `project.conf`, using the BuildStream
`Element` API (as in `dakota/plugins/chunkah-ownership.py`). Rust in these repos
is only ever input software, built through the community `cargo2` source plugin
(plus dakota's `files/scripts/generate_cargo_sources.py` helper for generating
`cargo2` source blocks from a `Cargo.lock`).

---

## Sources

Primary files read for this note:

- dakota: `README.md`, `AGENTS.md`, `project.conf`, `Containerfile`,
  `docs/build.md`, `docs/oci-assembly.md`, `elements/freedesktop-sdk.bst`,
  `elements/gnome-build-meta.bst`, `elements/plugins/*.bst`,
  `elements/oci/bluefin.bst`, `elements/oci/layers/*.bst`,
  `elements/oci/chunkah/*.bst`, `elements/oci/chunkah-metadata-tool.bst`,
  `elements/oci/os-release.bst`, `include/aliases.yml`, `include/os-release.yml`,
  `plugins/chunkah-ownership.py`, `plugins/chunkah-ownership.yaml`,
  `files/scripts/generate_cargo_sources.py`, `elements/bluefin/sudo-rs.bst`,
  `Justfile`, `.github/workflows/{build,publish,execute-release}.yml`,
  `.github/actions/generate-bst-ci-config/action.yml`.
- fsdk-containers: `README.md`, `AGENTS.md`, `project.conf`,
  `elements/freedesktop-sdk.bst`, `elements/gnome-build-meta.bst`,
  `elements/targets.json`, `elements/oci/base.bst`,
  `elements/base/*.bst`, `include/{aliases,slim,slim-python}.yml`,
  `catalog/{base,lab-runner,static,qemu-img}.yaml`, `catalog/schema.json`,
  `scripts/{catalog,verify_contract,generate_image_elements}.py`,
  `Justfile`, `.github/workflows/{build,oci-images}.yml`.
- server: `README.md`, `AGENTS.md`, `CONTEXT.md`, `NOTES.md`, `project.conf`,
  `elements/freedesktop-sdk.bst`, `elements/gnome-build-meta.bst`,
  `elements/base/base-stack.bst`, `elements/bluefin-server/os-stack.bst`,
  `elements/bluefin-server/os-rootfs.bst`,
  `elements/bluefin-server/uutils-coreutils.bst`,
  `elements/oci/{bluefin-server-ddi,bluefin-server-installer,k0s-sysext}.bst`,
  `elements/installer/{installer-stack,installer-repart}.bst`,
  `include/{aliases,arch,flatcar,k0s}.yml`, `Formula/*.rb`, `Justfile`,
  `.github/workflows/build.yml`, `workflows/server-release-watch-and-fix.md`.

No files in the three repositories were modified.
