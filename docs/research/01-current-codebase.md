# The current codebase: frameless (formerly finpilot)

Status: scouting pass. Written 2026-09-19, at commit `6611489`
(`docs: use GitHub issues as the development memory layer`) on branch `main`.
The rename `finpilot` → `frameless` is already complete in the working tree and
in history (`a65e55c chore: rename finpilot to frameless`); no `finpilot`
string remains under version control.

This document maps the repository as it stands: how the bootc image is
assembled, what each supporting file does, and — at the end — which parts are
the bootc/RPM core that a BuildStream template would replace and which are
generic scaffolding that would carry over.

---

## 1. Containerfile — the multi-stage image build

File: `Containerfile` (163 lines). It is a single-stage *modification* build
in disguise: a scratch context stage assembles inputs, then a real base image
is extended with `RUN` phases.

### 1.1 The `ctx` scratch stage and the OCI context images

```dockerfile
FROM ghcr.io/projectbluefin/common:latest@sha256:b7e3487c… AS common
FROM ghcr.io/ublue-os/brew:latest@sha256:60ada2d6…     AS brew

FROM scratch AS ctx
COPY build /build
COPY custom /custom
COPY --from=common /system_files /oci/common
COPY --from=brew   /system_files /oci/brew
```

- Both context images are tagged `:latest` but pinned by digest and updated by
  Renovate (custom regex manager in `.github/renovate.json`).
- `ctx` is a build-only scratch stage: it combines the local `build/` and
  `custom/` directories with `/system_files` exported by the two OCI images,
  placed at distinct paths to avoid collisions.
- The scratch stage is never itself an image; it is bind-mounted into the
  build-phase `RUN` blocks (`--mount=type=bind,from=ctx,source=/,target=/ctx`).
- Note that `COPY custom /custom` copies the whole `custom/` tree; only `files/`
  and `config/` and the declaration dirs are consumed (see §2.2).

### 1.2 The base image

```dockerfile
FROM quay.io/fedora-ostree-desktops/silverblue:44@sha256:fac5b1dd…
```

- The unaliased `FROM` line is the *only* place the base is chosen. It is
  pinned by digest; Renovate moves it.
- The comment block above it lists the other supported bases:
  `quay.io/fedora-ostree-desktops/base-main` (Fedora, no desktop),
  `quay.io/centos-bootc/centos-bootc:stream10`,
  `quay.io/hummingbird-community/bootc-os`.
- There is no `ARG BASE_IMAGE_NAME` default: the container build itself cannot
  know it, so `just build` fills it (see §3.3) and `00-image-info.sh`
  hard-fails if empty.

### 1.3 Image identity ARGs

```dockerfile
ARG IMAGE_NAME="frameless"
ARG IMAGE_VENDOR="projectbluefin"
ARG UBLUE_IMAGE_TAG="stable"
ARG BASE_IMAGE_NAME=""   # supplied by `just build` from the FROM line
ARG VERSION=""           # supplied by `just build`
```

- `IMAGE_NAME` is the *local fallback* and metadata value. The authoritative
  published name is the GitHub repository name, which `build-image.yml` passes
  in as a build arg (see §7.1). Three literal sites must agree: the
  Containerfile `# Name:` comment + `ARG IMAGE_NAME`, the Justfile default, and
  `artifacthub-repo.yml repositoryID` — enforced by
  `tests/contract/identity_test.bats`.
- Late metadata ARGs (declared after all build phases, deliberately, so a new
  version/commit invalidates only the label layer): `IMAGE_DESC`,
  `IMAGE_CREATED`, `IMAGE_LOGO_URL`, `IMAGE_KEYWORDS`, `IMAGE_REF`,
  `SHA_HEAD_SHORT`.

### 1.4 Ordered RUN phases

Each phase is its own `RUN` with cache mounts (`/var/cache/libdnf5`,
`/var/cache/rpm-ostree`), tmpfs `/boot` and `/tmp`, and the `ctx` bind mount.
The order and the boundary between phases is a contract tested by the unit
suite.

| Order | RUN block | Script | What it does |
|---|---|---|---|
| 1 | image identity | `build/00-image-info.sh` | Writes `/usr/share/ublue-os/image-info.json` and rewrites `/usr/lib/os-release` identity. |
| 1.5 | dnf defaults | inline | `dnf5 config-manager setopt keepcache=1 install_weak_deps=0`. |
| 2 | runtime overlays | `build/10-overlay.sh` | rsyncs common/brew payloads, `/`-overlay of `custom/files`, seeds `/etc/skel/.config`, copies Brewfiles/ujust/preinstalls, fetches Flathub descriptor, enables units. Installs **no** packages. |
| 3 | packages/services | `build/20-packages-and-services.sh` | `dnf5 install -y just gum fzf jq`, `copr_install_isolated ublue-os/packages uupd`, enables `uupd.timer` / `uupd-resume.timer`. |
| 4 | optional example | an activated `build/NN-*.sh` | No default block; an activated `.example` gets its own block between phase 3 and cleanup. |
| 5 | cleanup | `build/90-cleanup.sh` | Reverts dnf settings, disables third-party repos (fails if any stay enabled), masks `flatpak-add-fedora-repos.service`, prunes `/var`, `/tmp`, `/boot`, `/run`. Deliberately does **not** tmpfs `/run`. |
| 6 | `/opt` | inline | `RUN rm -rf /opt && ln -s /var/opt /opt`. |
| 7 | metadata | inline `LABEL` | OCI + ArtifactHub labels; `containers.bootc="1"`; source/readme/URL derived from `IMAGE_VENDOR`/`IMAGE_NAME`/`IMAGE_REF`. |
| 8 | init | inline | `CMD ["/sbin/init"]`. |
| 9 | lint | inline | `RUN bootc container lint --fatal-warnings`. |

The package/overlay split exists so an overlay edit cannot invalidate the
expensive package layer. `tests/template/justfile-build_test.bats` asserts
`ARG SHA_HEAD_SHORT` appears *after* the `### IMAGE METADATA` marker for the
same cache reason.

### 1.5 How `just build` and the container build interact

`just build` (Justfile lines 142–240) is the only supported build entry point;
a bare `podman build .` is unsupported because `BASE_IMAGE_NAME` would be
empty. `just build`:

1. Reads the unaliased `FROM` line from `Containerfile`, extracting the base
   tag (`44`, `stream10`, …) and base image name (`silverblue`).
2. Composes the version string: `<base-tag>.<YYYYMMDD>` when the target tag
   contains `stable`, else `<tag>-<base-tag>.<YYYYMMDD>`. It consults
   `skopeo list-tags` and appends `.N` (`.1`, `.2`, …) to avoid same-day
   collisions.
3. Adds `--build-arg` for `VERSION`, `IMAGE_NAME` (positional target image,
   minus any `localhost/` prefix), `IMAGE_VENDOR` (env or
   `GITHUB_REPOSITORY_OWNER`), `UBLUE_IMAGE_TAG`, `BASE_IMAGE_NAME`,
   `IMAGE_CREATED`, plus optional metadata overrides.
4. Adds `SHA_HEAD_SHORT` only when `git status -s` is clean.
5. Adds `--secret id=GITHUB_TOKEN,env=GITHUB_TOKEN` when the token is set.
6. Adds Podman `--cache-from` (always when reachable) and `--cache-to` (only
   when `REGISTRY_CACHE_WRITE=1`, which CI sets).
7. Runs `${PODMAN} build … --pull=newer --tag "${target_image}:${tag}" .`

CI invokes `just build` via `sudo -E "$(command -v just)" build "${IMAGE_NAME}"
"${DEFAULT_TAG}"` inside `build-image.yml`.

---

## 2. `build/*.sh` — the build scripts

Overview: `build/README.md`. Scripts run as root with the context at `/ctx`;
the Containerfile names each one explicitly, so there is no prefix
auto-discovery.

### 2.1 Phase scripts

- **`build/00-image-info.sh`** (118 lines)
  - Requires `IMAGE_NAME`, `IMAGE_VENDOR`, `UBLUE_IMAGE_TAG`, `BASE_IMAGE_NAME`;
    derives `FEDORA_MAJOR_VERSION` from the base image's `/usr/lib/os-release`
    (`VERSION_ID`) unless overridden.
  - Writes `/usr/share/ublue-os/image-info.json` with fields: `image-name`,
    `image-vendor`, `image-ref` (`ostree-image-signed:docker://ghcr.io/<vendor>/<name>`),
    `image-tag`, `base-image-name`, `fedora-version`, with JSON escaping.
  - Rewrites `/usr/lib/os-release` keys: `VARIANT_ID`, `PRETTY_NAME`, `NAME`,
    `HOME_URL`, `DOCUMENTATION_URL`, `SUPPORT_URL`, `BUG_REPORT_URL`,
    `VERSION`, `OSTREE_VERSION`, `IMAGE_ID`, `IMAGE_VERSION`. It *replaces*
    existing values (Silverblue already ships `VARIANT_ID`); it does not write
    `BUILD_ID`. `ROOT_DIR` is a test seam.
  - URLs default to `https://github.com/<vendor>/<name>` variants; all
    overridable by env.
- **`build/10-overlay.sh`** (138 lines)
  - Order is a contract: `oci/common/shared/` → `oci/brew/` →
    `custom/files/` (mirrors `/`, excludes its own `README.md`) →
    `custom/config/` into `/etc/skel/.config/`.
  - `common/bluefin/` and `common/nvidia/` are imported into the context but
    never overlaid (product opinion / paired hardware feature).
  - Copies `custom/brew/*.Brewfile` to `/usr/share/ublue-os/homebrew/`;
    concatenates every `custom/ujust/**/*.just` (sorted, recursive) into
    `/usr/share/ublue-os/just/60-custom.just`; copies
    `custom/flatpaks/*.preinstall` to `/usr/share/flatpak/preinstall.d/`.
  - Fetches `https://dl.flathub.org/repo/flathub.flatpakrepo` into
    `/etc/flatpak/remotes.d/`.
  - Enables units: `brew-setup.service`, `brew-update.timer`,
    `brew-upgrade.timer`, `brew-preinstall.service` (global),
    `flatpak-preinstall.service`, `flatpak-appstream-refresh.service`,
    `ublue-system-setup.service`, `ublue-user-setup.service` (global),
    `podman.socket`. Empty `custom/brew`/`custom/flatpaks` dirs are build
    failures (nullglob is not enough — regression guard in the tests).
- **`build/20-packages-and-services.sh`** (54 lines)
  - `dnf5 install -y just gum fzf jq`; then `copr_install_isolated
    "ublue-os/packages" uupd`; enables `uupd.timer` and `uupd-resume.timer`.
  - Sources `/ctx/build/copr-helpers.sh`. Deliberately performs no overlays.
- **`build/90-cleanup.sh`** (106 lines)
  - `dnf5 config-manager setopt keepcache=0`, `dnf5 versionlock clear`.
  - Disables every `_copr:*`, `_copr_*`, `rpmfusion-*`, `fedora-multimedia`,
    `tailscale`, `fedora-cisco-openh264`, `fedora-coreos-pool` repo file, then
    **fails** if any remains enabled.
  - Disables/masks/removes `flatpak-add-fedora-repos.service`; disables
    `rpm-ostreed-automatic.timer` (guarded with `|| true`).
  - Prunes `/var` (keeps `cache`), keeps `/var/cache/libdnf5` and
    `/var/cache/rpm-ostree`, empties `/tmp` and `/boot` but keeps the dirs,
    clears `/run` while skipping mountpoints (depth-first, avoids Busy
    Buildah bind mounts). `CLEAN_ROOT` is a test seam.

### 2.2 Helpers

- **`build/copr-helpers.sh`** (30 lines): `copr_install_isolated <owner/project>
  <pkg…>` — `dnf5 -y copr enable`, `dnf5 -y copr disable`, then
  `dnf5 install --enablerepo=copr:copr.fedorainfracloud.org:<owner>:<project>`
  in one transaction. Slashes become colons in the repo id.
- **`build/validate-brewfiles.sh`** (121 lines): greps `*.Brewfile` without
  evaluating Ruby; syncs only literal `tap` declarations through `brew bundle`,
  then checks each `brew`/`cask` via `brew info`; rejects computed/non-literal
  lines. Exit 2 for missing dir/empty set, 1 for failures.
- **`build/validate-flatpaks.sh`** (103 lines): validates `*.preinstall` syntax
  (blank/`#`/`[Flatpak Preinstall <id>]`/`key=value`), requires a `Branch=` key
  per section, and checks each app with `flatpak remote-info --user flathub`.
  Adds the Flathub remote with `--user --if-not-exists`.

### 2.3 The `.example` catalogue

Inactive until renamed off `.example` and given a `RUN` block (recipe in
`build/README.md`); they illustrate each class of build-time change:

- **`30-tailscale.sh.example`** — add a vendor `.repo`, install, remove the
  repo; enables `tailscaled.service`. The third-party-repo pattern.
- **`40-gnome-extensions.sh.example`** — install GNOME Shell extensions from
  extensions.gnome.org and a GitHub repo into
  `/usr/share/gnome-shell/extensions/<uuid>/`, compile schemas, and write a
  `zz1-custom-extensions.gschema.override` to enable them.
- **`50-nvidia.sh.example`** — pull prebuilt akmods from
  `ghcr.io/ublue-os/akmods-nvidia-open:<flavor>-<fedora>-<kernel>`, run
  `nvidia-install.sh`, ship blacklist `kargs.d/00-nvidia.toml`, install
  `nvidia-container-toolkit-base`, assert three packages.
- **`60-desktop-swap.sh.example`** — install COSMIC, remove GNOME, enable
  `cosmic-greeter.service`. The destructive example.

### 2.4 Tests for the scripts

Covered in §6. Test seams are deliberate: `ROOT_DIR` (image-info), `CLEAN_ROOT`
(cleanup), and sandbox rewrites of `/ctx/` for overlay/packages tests.

---

## 3. Justfile — every recipe group

File: `Justfile` (658 lines). Top-level exports: `IMAGE_NAME` (env or
`frameless`), `DEFAULT_TAG` (env or `stable`), `PODMAN` (env or `podman`),
`REPO_ORG` (env `GITHUB_REPOSITORY_OWNER` or `projectbluefin`), `bib_image`
(bootc-image-builder pinned digest), `qemu_image` (qemus/qemu pinned digest),
`vm_ram` (8192), `vm_cpus` (4). Aliases: `build-vm`→`build-qcow2`,
`rebuild-vm`→`rebuild-qcow2`, `run-vm`→`run-vm-qcow2`.

### 3.1 `Just` group (validation and tests)

- `check` → `_format-justfiles "--check"`: runs `just --unstable --fmt --check`
  over `Justfile` and every `*.just` under the repo.
- `test-contract` → `_bats tests/contract` (interfaces a fork keeps).
- `test-template` → `_bats tests/template` (this repo's wiring; a fork may
  delete).
- `test-unit` → `_bats tests` (both; what CI runs).
- `_bats $dir` (private): finds `*_test.bats` recursively and runs
  `bats --print-output-on-failure`.
- `validate-brewfiles` → `bash build/validate-brewfiles.sh`.
- `validate-flatpaks` → `bash build/validate-flatpaks.sh`.
- `fix` → `_format-justfiles` (writes).
- `lint`: `git ls-files '*.sh'` (via private `shell-sources`) → `shellcheck`.
- `format`: same scope → `shfmt --write`.

### 3.2 `Utility` group

- `clean`: deletes top-level `*_build*` entries and `output/`.
- `sudo-clean` (private): `just sudoif just clean`.
- `sudoif command *args` (private): privilege dispatcher; direct exec as root,
  `sudo --askpass` under a GUI, `sudo`, or fail closed.

### 3.3 `Image` group

- `build $target_image=IMAGE_NAME $tag=DEFAULT_TAG` — described in §1.5.
- `tag-images $image_name $default_tag $tags` — inspects
  `localhost/<name>:<default_tag>`, untags it, retags the image Id with each
  whitespace-separated alias (no `localhost/` prefix), then re-applies the
  default tag last.
- `_rootful_load_image` (private): makes a user-built image visible to rootful
  Podman via `podman image scp`, or pulls it, or no-ops as root.
- `_build-bib $target_image $tag $type $config` (private): runs
  bootc-image-builder in a privileged Podman container with the chosen
  `iso/disk.toml` (qcow2/raw) or `iso/iso.toml` (iso). For ISO it reads
  `image-info.json` from the image to tag it with the published
  `image-ref`/`image-tag` so the installed `bootc switch` origin is correct.
- `_rebuild-bib` (private): `build` then `_build-bib`.

### 3.4 `Build Virtual Machine Image` group

`build-qcow2`, `build-raw`, `build-iso` (all default
`target_image=("localhost/" + IMAGE_NAME)`, `tag=DEFAULT_TAG`) and
`rebuild-qcow2`, `rebuild-raw`, `rebuild-iso`.

### 3.5 `Run Virtual Machine` group

- `vm-artifact $type` (private): maps type → artifact path
  (`output/qcow2/disk.qcow2`, `output/image/disk.raw`,
  `output/bootiso/install.iso`).
- `_run-vm` (private): builds the artifact if absent, prefers native
  `qemu-system-x86_64` (KVM/q35, virtio, OVMF from any distro path, host port
  2222+ for ssh, GTK display or serial console), else falls back to
  `_run-vm-container`.
- `_run-vm-container` (private): `ghcr.io/qemus/qemu` web console on port
  8006+, `-snapshot` for disks.
- `run-vm-qcow2`, `run-vm-raw`, `run-vm-iso`.
- `spawn-vm rebuild=0 type=qcow2 ram=6G`: `systemd-vmspawn` path for disk
  images (rejects ISO), checks `qemu-system-x86_64` and `/dev/kvm`.

### 3.6 Derived values

- `IMAGE_NAME` ← env or literal `frameless`.
- `REPO_ORG` ← `GITHUB_REPOSITORY_OWNER` or `projectbluefin`.
- Base tag / base image name ← parsed from the unaliased `Containerfile`
  `FROM` line inside the `build` recipe (not a top-level export).
- Version string ← `[[ "$tag" =~ stable ]]` → `<base>.<date>` else
  `<tag>-<base>.<date>`, with point-release collision handling.
- `_build-bib` reads the image reference from `image-info.json` for ISO builds
  rather than restating it.

---

## 4. `custom/` — the runtime declaration seams

- **`custom/brew/`** — `default.Brewfile` (empty, comments only) and
  `development.Brewfile` (commented catalogue of dev tools). Copied to
  `/usr/share/ublue-os/homebrew/`. Users run them on demand; nothing installs
  at build time. `README.md` explains tap/brew/cask and the no-evaluation
  security rule.
- **`custom/flatpaks/default.preinstall`** — three first-boot apps:
  `org.mozilla.Thunderbird`, `com.github.tchx84.Flatseal`,
  `com.mattjakeman.ExtensionManager`, each `Branch=stable`. Copied to
  `/usr/share/flatpak/preinstall.d/`. `README.md` has the GKeyFile gotchas.
- **`custom/ujust/`** — `custom-apps.just` (`install-default-apps`,
  `install-dev-tools`) and `custom-system.just` (`configure-dev-groups` adds
  the user to docker/libvirt, creating groups as needed; `install-config`
  re-applies `/etc/skel/.config` into `$HOME/.config`, backing up conflicts).
  Concatenated into `60-custom.just`. `README.md` documents the recipe shape
  and the "no package installation in recipes" rule.
- **`custom/config/environment.d/10-example.conf`** — inert example per-user
  config; seeded into `/etc/skel/.config/`. `README.md` explains the
  precedence and the explicit `ujust install-config` route for existing users.
- **`custom/files/README.md`** — the system-payload seam (tree mirrors `/`);
  currently documentation only, no payloads.

---

## 5. `iso/` — bootc-image-builder config

- **`iso/disk.toml`** — one `[[customizations.filesystem]]` entry,
  `mountpoint = "/"`, `minsize = "20 GiB"`. Used by qcow2 and raw builds.
- **`iso/iso.toml`** — minimal interactive-install config: an
  `[customizations.installer.kickstart]` block whose `contents` is a comment
  only (the table must exist to prevent BIB's unattended `clearpart`),
  `enable = ["org.fedoraproject.Anaconda.Modules.Timezone"]`,
  `disable = ["org.fedoraproject.Anaconda.Modules.Subscription"]`. The image
  reference is deliberately absent; the Justfile reads it from
  `image-info.json`.

---

## 6. `tests/` — contract vs template

Both suites are bats (`*_test.bats`) and are run through `just _bats`, which
discovers files so a fork can add/remove without editing the Justfile. The
split is documented in the Justfile: **contract** = interfaces the image must
satisfy (a fork keeps), **template** = this repository's build wiring (a fork
may delete).

### 6.1 `tests/contract/` (4 files)

- `00-image-info_test.bats` (213 lines) — drives `build/00-image-info.sh`
  against a sandbox `ROOT_DIR`: Bluefin-compatible JSON fields, no `image-flavor`
  derived from the name, os-release rewriting, URL derivation and overrides, no
  `BUILD_ID`, idempotency, works without os-release, JSON escaping, fails
  before writing when identity is missing, Fedora-major derivation/override,
  sed-metacharacter and append branches.
- `identity_test.bats` (51 lines) — enforces one `ARG IMAGE_NAME` and that the
  Containerfile `# Name:` comment, Justfile `IMAGE_NAME` default, and
  `artifacthub-repo.yml repositoryID` all match it. Skips if ArtifactHub file
  is absent.
- `validate-brewfiles_test.bats` (144 lines) — fake `brew`: literal
  formula/cask checks, deduplicated taps first, computed tap lines fail closed
  without reaching `brew bundle`, tap failure fatal and preserves streams, info
  failure diagnostics, malformed declarations accumulate, exit-2 cases,
  no-trailing-newline.
- `validate-flatpaks_test.bats` (151 lines) — fake `flatpak`: well-formed pass,
  missing `Branch=` fail-closed, app-not-on-flathub, empty/missing dir exit 2,
  flathub remote added, `;` comment rejected, bare group header rejected.

### 6.2 `tests/template/` (11 files)

- `10-overlay_test.bats` (290 lines) — sandbox-rewrites the script and stubs
  rsync/systemctl/curl: no host writes, group markers, overlay precedence
  (common → brew → files → config, never bluefin/nvidia), `custom/files`
  root-mirror + README exclusion, Brewfile copies, `.just` consolidation
  (recursive, sorted, idempotent, blank-line separated), preinstall copies,
  `/etc/skel` seeding, missing-config tolerance, exactly nine systemctl calls,
  Flathub descriptor fetch, empty-brew/empty-flatpaks failure guards, empty
  ujust tolerated, nullglob restored.
- `20-packages-and-services_test.bats` (138 lines) — sandbox + stubs; asserts
  the single dnf5 install line, the isolated COPR sequence (4 calls), the two
  timers, no overlays, helper present, missing helper fails fast, nullglob
  restored.
- `90-cleanup_test.bats` (236 lines) — sandbox `CLEAN_ROOT`, stubs; dnf
  restoration/versionlock, flatpak unit disable+mask+remove, repo disabling
  (fails when it cannot disable), `.gitkeep` removal, `/var` pruning with cache
  kept, tmp/boot/run clearing, mountpoint skipping, idempotency.
- `copr-helpers_test.bats` (132 lines) — fake dnf5: enable→disable→install
  order, multi-package single transaction, slash translation, no-package error,
  failure propagation, sourcing is inert.
- `custom-apps-just_test.bats` (108 lines) — extracts recipe bodies and runs
  them against a fake brew; default/dev bundle paths, nonzero exit, referenced
  Brewfiles exist, every recipe grouped.
- `custom-system-just_test.bats` (219 lines) — extracts recipe bodies; group
  creation, partial groups, no-op when complete, cancel path, escalation
  discipline, install-config copy/backup/conflict-list/cancel/missing-seed,
  every recipe grouped.
- `execute-release_test.bats` (55 lines) — reads the promotion pattern out of
  `execute-release.yml`; accepts squash and PR-title subjects, rejects merge
  commits, and asserts the non-promotion push guard exists.
- `justfile-build_test.bats` (404 lines) — sandbox Justfile + stubbed
  podman/skopeo/git/date: version derivation, base-tag parsing (aliased vs
  not, digest-less, non-numeric, missing tag aborts), collision point releases,
  clean-tree SHA stamp, identity build args, vendor fallback/overrides,
  positional target_image and `localhost/` stripping, GITHUB_TOKEN secret,
  minimal dynamic metadata, layer-cache read/write policy, `--pull=newer`,
  plus Containerfile label-schema and late-`SHA_HEAD_SHORT` assertions.
- `justfile-clean_test.bats` (163 lines) — sandbox Justfile; `clean` blast
  radius (top-level only, keeps `output/` gone, keeps unrelated files, safe
  when already clean), `sudoif` fail-closed and `sudo-clean` propagation.
- `justfile-tag-images_test.bats` (225 lines) — sandbox Justfile + stubbed
  podman; argument validation, inspect/untag/retag order, all tags applied,
  default reapplied last, aliases unqualified, whitespace collapse, `PODMAN`
  override, failure paths.
- `precommit-brewfile-hook_test.bats` (76 lines) — the `.pre-commit-config.yaml`
  hook delegates to `build/validate-brewfiles.sh` via `bash`, and no hook feeds
  a repository Brewfile to `brew bundle` or globs `custom/brew/*`.

Total: 15 bats files.

---

## 7. `.github/workflows/` — triggers and roles

Most are thin callers of pinned reusables in `projectbluefin/actions`
(`@ce1d0c6b… # v1`). Pins are updated by Renovate.

### 7.1 Build and release

- **`build-image.yml`** (265 lines) — trigger: push to `main`, plus
  `workflow_dispatch` limited to the default branch; `paths-ignore` docs and
  `*validate*.yml`. Builds, signs, and pushes the image; **PR builds are
  disabled**. Env derives `IMAGE_NAME`/`IMAGE_VENDOR`/`IMAGE_REGISTRY` from the
  repository. A `determine-tag` step makes anything not on `stable` publish
  `stable-testing` and `TAG_STREAM=testing`. Steps: preflight, setup-runner
  (btrfs, installs `just`), DNF cache restore, `just build` under a retry
  action, read the version label, `generate-tags`, `Finalize branch tags`
  (testing → `stable-testing-*`, keeps bare `:testing`), DNF cache save,
  optional rechunk, `just tag-images`, push, sign/attest (keyless OIDC,
  continue-on-error), telemetry summary. It does **not** amend `:stable`.
- **`execute-release.yml`** (117 lines) — trigger: push to `stable` or
  dispatch. `check-trigger` accepts only promotion-shaped commit subjects
  (`chore: promote` / `ci(promote):`) or a manual dispatch and **fails loudly**
  otherwise. `execute` calls `reusable-execute-release.yml` to verify the
  cosign signature and copy the `:testing` digest to `:stable` without
  rebuilding; `source_branch: main` makes it refuse once main has moved.
  `release-notes` calls `reusable-release.yml` for a GitHub release on `stable`
  with inline SBOM.
- **`promote-main-to-stable.yml`** (250 lines) — trigger: daily cron `0 4 * * *`
  or dispatch. Calls `reusable-promote-squash.yml` to open/refresh the squash
  promotion PR (`run_e2e: false`, no merge queue, human merge). Then
  `repair-promotion-branch` rebuilds the branch from main's tree when it
  drifted, `locate-promotion-pr` finds the PR, `unblock-promotion-checks`
  approves GitHub-held bot check runs, and `gate` runs
  `reusable-release-gate.yml` on the PR.
- **`sync-stable-to-main.yml`** (35 lines) — trigger: push to `stable` or
  dispatch. Calls `reusable-sync-branches.yml` to merge stable hotfixes back
  into main; normally a no-op.

### 7.2 Validation (PR linting only, never affects the image)

- **`pr-validation.yml`** (67 lines) — trigger: PR to `main`/`stable`. On the
  promotion branch, verifies the tree matches main; resolves the shellcheck
  glob from `git ls-files '*.sh'`; calls
  `bootc-build/validate-pr` with `Containerfile` and `.github/hadolint.yaml`.
  This is the `validate` status check branch protection requires.
- **`unit-tests.yml`** (51 lines) — trigger: push/PR to `main`/`stable`,
  `paths-ignore: **.md`. Installs a pinned `just` (1.58.0) and `bats`, runs
  `just test-unit`.
- **`validate-brewfiles.yml`** — trigger: PR touching `custom/brew/**`,
  `build/validate-brewfiles.sh`, its test, or itself. Sets up Homebrew and
  runs `just validate-brewfiles` (never `brew bundle check` on a repo
  Brewfile).
- **`validate-flatpaks.yml`** — trigger: PR touching `custom/flatpaks/**`, the
  script, its test, or itself. Installs `flatpak` and runs
  `build/validate-flatpaks.sh`.
- **`validate-justfiles.yml`** — trigger: PR touching `**/*.just`, `Justfile`,
  or itself. Runs `just check`.
- **`validate-renovate.yml`** — trigger: PR/push touching `.github/renovate.json`
  or either Renovate workflow. Calls `reusable-validate-renovate.yml`.

### 7.3 Maintenance

- **`renovate.yml`** — schedule every 6 hours, dispatch, or push to main
  touching Renovate config. Calls `reusable-renovate.yml` with the
  `RENOVATE_TOKEN` secret.
- **`clean.yml`** — weekly cron, dispatch. Derives the package name from the
  repository name and calls `bootc-build/ghcr-cleanup` (older than 90 days,
  keep 7 tagged/7 untagged).

---

## 8. `.agents/skills/` — repo-owned procedures

Six skills plus a README. Each is a `SKILL.md` with YAML front matter
(`name`, `description`). The README says: start with `overview`.

| Skill | Covers |
|---|---|
| `overview` | Architecture, file map, and a "which skill do I need" routing table; the OCI-assembly model; upstream dependencies (`projectbluefin/common`, `projectbluefin/actions`, `ublue-os/brew`). |
| `build` | The Containerfile structure, the Justfile command surface, digest pinning and why `BASE_IMAGE_NAME` has no default, and activating `.example` scripts. |
| `ci` | Every workflow's trigger/role, the two-branch release model, the promotion gate's limits, keyless Cosign signing, and Renovate policy (including the deliberate GitHub-Actions automerge trade). |
| `customize` | Where a package/app/command belongs: dnf5 build-time, Homebrew, Flatpak, ujust, `custom/files`, `custom/config`; the validation commands. |
| `onboarding` | Fork → first green build: rename the three identity sites, enable Actions/auto-merge/workflow permissions, the `RENOVATE_TOKEN`, create/protect `main` and `stable`, the squash ruleset, the label vocabulary, and a verify/failure-mode section. |
| `troubleshooting` | Symptom → cause → fix tables for build/CI/runtime plus the pre-PR checklist. |

Separately, the *agent environment* (not this repo) provides a larger global
skill catalogue under `~/.agents/skills/` (`ask-matt`, `code-review`, `tdd`,
`research`, `to-spec`, `to-tickets`, `wayfinder`, `triage`, etc.). Those are not
part of the repository and travel with the harness, not the template.

---

## 9. Image identity end to end

The chain has one authoritative value (`IMAGE_NAME`, ultimately the repository
name) and three representations:

1. **Build-time input.** `build-image.yml` sets
   `IMAGE_NAME=${{ github.event.repository.name }}` and
   `IMAGE_VENDOR=${{ github.repository_owner }}`; local builds use the Justfile
   default `frameless` / `projectbluefin`. `just build` passes both as
   `--build-arg`, plus `VERSION` (the derived version string),
   `UBLUE_IMAGE_TAG`, and `BASE_IMAGE_NAME` parsed from the base `FROM`.
2. **In-image identity** (`build/00-image-info.sh`):
   - `/usr/share/ublue-os/image-info.json` —
     `image-name`, `image-vendor`,
     `image-ref = ostree-image-signed:docker://ghcr.io/<vendor>/<name>`,
     `image-tag`, `base-image-name`, `fedora-version`.
   - `/usr/lib/os-release` — `NAME`, `PRETTY_NAME`, `VARIANT_ID`, `IMAGE_ID`,
     `IMAGE_VERSION`, `VERSION`, `OSTREE_VERSION`, the four URLs. The base's
     `ID`/`ID_LIKE`/`DEFAULT_HOSTNAME` are left alone.
   - Field values are JSON-escaped (script) and sed-escaped (os-release), and
     the script is idempotent.
   - The build commit is deliberately **not** in os-release: `SHA_HEAD_SHORT`
     is declared late for cache reasons, so it ships only as the OCI revision
     label.
3. **Container labels** (Containerfile `LABEL` block):
   `org.opencontainers.image.title/version/revision/description/source/url/vendor/created`,
   `io.artifacthub.package.readme-url/logo-url/keywords/license/deprecated`,
   and `containers.bootc="1"`.
4. **Consumers.**
   - `bootc` and UBlue runtime tools read `image-info.json`/os-release.
   - bootc-image-builder (via `_build-bib`) reads `image-info.json`
     `image-ref`/`image-tag` to tag the image for the ISO's post-install
     `bootc switch` origin, so the ISO config carries no reference.
   - `build-image.yml` reads the OCI version label back
     (`podman inspect … org.opencontainers.image.version`) to feed
     `generate-tags`.
   - The contract test `identity_test.bats` keeps the literal name sites in
     agreement.

---

## 10. bootc/RPM core vs generic scaffolding

This is the distinction that matters for a BuildStream rewrite. "Bootc core"
means code that exists only because the build produces an OSTree/bootc
container image assembled from RPMs and OCI layers. "Generic" means structure
that a BuildStream template could reuse largely as-is.

### 10.1 bootc/RPM-specific (finpilot's core; likely replaced)

- **`Containerfile`** in its entirety: the `ctx` scratch context stage, the
  `common`/`brew` OCI context images, the bootc base `FROM`, the `bootc
  container lint` gate, `CMD ["/sbin/init"]`, the `/opt → /var/opt` symlink,
  the dnf config layer, and the `containers.bootc="1"` label. BuildStream
  expresses its own element graph, so this file's job disappears.
- **The phase scripts as written**: `00-image-info.sh` (ostree-image-signed
  refs, os-release rewriting), `10-overlay.sh` (rsync OCI payloads and
  `systemctl enable`), `20-packages-and-services.sh` (dnf5 + COPR),
  `90-cleanup.sh` (dnf/rpm-ostree/flatpak cache and repo pruning),
  `copr-helpers.sh`. The *jobs* recur, but the implementations are RPM/OCI
  specific.
- **The `.example` scripts**: tailscale/gnome-extensions/nvidia/desktop-swap
  are all dnf/akmods/gschema operations against a Fedora system.
- **Identity plumbing tied to bootc**: `image-info.json`, the bootc
  os-release fields, `containers.bootc`, and bootc-image-builder's consumption
  of `image-ref`.
- **`iso/disk.toml` and `iso/iso.toml`**: bootc-image-builder configs, and the
  `_build-bib`/`build-qcow2`/`build-iso` recipes built on BIB. The *concept*
  of producing a disk/ISO is generic; the tooling and config are bootc's.
- **`build-image.yml` and `execute-release.yml` internals**: the
  `projectbluefin/actions/bootc-build/*` reusables assume a container-image
  build and digest promotion. (The two-branch *model* is generic; the calls
  are bootc-specific.)
- **`validate-brewfiles.sh` / `validate-flatpaks.sh`**: not bootc-specific per
  se, but they validate ublue/Fedora runtime declarations (Homebrew/Flatpak)
  that a non-ublue BuildStream image may not ship.

### 10.2 Generic scaffolding (would carry over)

- **Repository conventions and memory**: `AGENTS.md` (Conventional Commits,
  validate-before-commit, confirm-before-push, PR comment discipline,
  attribution, self-improvement, GitHub issues as development memory,
  `docs/research/`), `CONTRIBUTING.md`, the issue templates.
- **Justfile *shape***: the recipe groups (`Just` check/test/lint/format,
  `Utility` clean/sudoif, `Image`, VM build/run) and the single-definition
  patterns (`_bats` discovery, `shell-sources`). The bodies of `build` and the
  BIB recipes would be rewritten.
- **Test architecture**: bats, the contract/template split, test seams
  (`ROOT_DIR`, `CLEAN_ROOT`), PATH stubs, sandboxed Justfile copies, and the
  habit of asserting on argument vectors. The tests themselves are mostly
  script-specific and would be replaced, but the harness and discipline
  transfer.
- **CI shape**: the two-branch release model (`main` publishes testing,
  `stable` promotes the exact digest, sync-back), promotion PRs, keyless
  signing, Renovate policy, the `validate`/`unit-tests` check names,
  `clean.yml`, `pr-validation.yml`'s shellcheck+hadolint flow, and the
  thin-caller-to-reusables pattern. The reusable actions and the build job
  internals would change.
- **`custom/` seams**: the *structure* (Brewfiles, Flatpak preinstalls, ujust
  recipes, `/etc/skel` config, `custom/files` mirroring `/`) is generic
  declaration plumbing; whether it survives depends on whether the BuildStream
  image remains a ublue/desktop OS. The seam-reading code in `10-overlay.sh`
  would move into BuildStream elements.
- **`.agents/skills/` structure**: the six-skill layout and the
  README/overview-routes-everything convention. The content of `build` and
  `ci` would be rewritten; `customize`, `onboarding`, `troubleshooting`
  mostly survive in shape.
- **Small configs**: `.pre-commit-config.yaml`, `.github/hadolint.yaml`,
  `.github/renovate.json` (the regex managers would change, the policy shape
  would not), `artifacthub-repo.yml`, `.dockerignore`/`.gitignore`,
  `docs/research/`.

### 10.3 Open questions for the rewrite

- Does the BuildStream image stay a bootc/OSTree image (so `image-info.json`,
  os-release identity, and bootc-image-builder still apply), or is it a
  different artifact class? This decides whether §10.1's identity plumbing is
  replaced or re-implemented.
- Do the ublue runtime layers (Homebrew, Flatpak, ujust, `ublue-*` services)
  remain part of the product? If yes, `custom/` survives almost unchanged and
  only its *delivery* (overlay script → BuildStream element) changes.
- Does the release model keep digest promotion on `stable`, and can
  `projectbluefin/actions` reusables be reused or must they be forked for a
  non-container build?
- Which parts of the identity contract (`identity_test.bats`,
  `image-info.json` schema) are external interfaces that downstream tooling
  depends on, and therefore must outlive the build-system swap?
