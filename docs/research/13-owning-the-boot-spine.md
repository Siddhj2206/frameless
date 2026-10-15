# Owning the boot spine: what moves, and what it costs to keep

Research note on the cost of moving bootc and the initramfs out of
gnome-build-meta and into frameless, written because the plan says a bootable
image must not be a GNOME image in its dependency graph — and today both pieces
arrive as references into the gnome-build-meta junction.

Verified 2026-09-30 against gnome-build-meta at the pinned ref
(`51.0-5-gbe7cb317ee21d45197ba5139c77317f171e20c38`, tag `51.0` plus five
commits), freedesktop-sdk at the pinned ref
(`freedesktop-sdk-26.08.1-0-gb02b59ffe19a49a402f357fd5fcb1d552ebc50d7`),
bootc's release history, freedesktop-sdk's merge-request queue, and
BuildStream 2.8's cache-key code. Commit counts come from the GitLab commits
API, per path, on the `gnome-51` branch, windowed by GNOME release cycle
(`48` = 2024-09-17 → 2025-03-18, `49` → 2025-09-15, `50` → 2026-03-18, `51` →
2026-09-30).

## The short answer

- **bootc** is one 1,721-line `make` element that compiles bootc from source,
  plus a config element and two files. Its crate list is generated from
  bootc's `Cargo.lock` — 416 refs at the pin — and bootc cut 20 releases in the
  eight months to September 2026. This is the expensive half to own.
- **The initramfs** is five elements (plus the already-replaced signed-modules)
  and 28 generator files. The elements barely move; the module files get
  ~6–11 commits per release cycle, and the OCI initramfs layout was
  restructured three times since February 2026. This is the churny half to
  own.
- **Frameless would carry ~7 elements and ~30 files for the minimum move**
  (bootc + the OCI initramfs), or ~15 elements and ~32 files for a full
  de-GNOME of the initramfs closure. Owning the spine also means *building*
  it: the cache key includes the owning project's `fatal-warnings` and
  environment, so a copy in frameless re-keys and bootc compiles from source
  (~416 crates) on the first build and on every bump.
- **Freedesktop-sdk is not a way out yet.** bootc is a *draft* MR against
  `master` (`!32072`, opened 2026-05-12, one commit, unmerged); FSDK's majors
  are yearly (24.08 → 25.08 → 26.08, every September), so a merge today would
  land in ~27.08. FSDK has no `generate-initramfs` equivalent; its own VM
  examples use dracut.
- **Keeping gnome-build-meta as the boot-spine supplier already works
  structurally.** `gnomeos-deps/deps.bst` does not reach bootc or the
  initramfs, so a non-GNOME payload loses no boot functionality by dropping
  the desktop — it only keeps the junction and the override mirror. The choice
  is between maintaining a junction and maintaining a bootc element.

## Method

The element inventory was read from the two repositories at their pinned
commits, via `raw` file fetches and the GitLab tree API. Change rates were
computed by querying the commits API for each path on the `gnome-51` branch
with `since`/`until` windows anchored to the release tags (`48.0` 2025-03-18,
`49.0` 2025-09-15, `50.0` 2026-03-18, `51.0` 2026-09-16). "Commits" counts
include the dependency-bot ref bumps that GBM runs, which is noted where it
matters.

## The inventory at the pinned refs

### bootc, in gnome-build-meta

| Path | Kind | What it is | Sources |
|---|---|---|---|
| `elements/gnomeos-deps/bootc.bst` | `make` | builds bootc v1.16.6 from source with `make install-all` | 1 `git_repo` (`github:bootc-dev/bootc.git`) + 1 `cargo2` with 416 refs: 407 crates.io registries, 9 git crates (bcvk-qemu and eight `composefs-rs` crates) |
| `elements/oci/integration/bootc-config.bst` | `manual` | installs the two bootc config files | 1 `local` (`files/oci`) |
| `files/oci/prepare-root.conf` | config | `[composefs] enabled = yes`, `[sysroot] readonly = true` | — |
| `files/oci/10-bootc.conf` | config | tmpfiles drop-in for `/var` symlink model | — |

The element is 1,721 lines; all but ~30 are the generated crate list. It
build-depends on GBM's own `buildsystems/make.bst` (a RECC wrapper stack) and
`include/gcc-for-recc.yml`, then FSDK's rust/systemd/openssl/zstd/go-md2man.

### The initramfs, in gnome-build-meta

| Path | Kind | What it is | Sources |
|---|---|---|---|
| `elements/gnomeos/generate-initramfs.bst` | `manual` | installs the generator scripts and modules; runtime-depends on `gnomeos-deps/python3-zstd` + FSDK pyelftools/gcc/lvm2 | 1 `local` (`files/gnomeos/generate-initramfs`) |
| `elements/oci/initramfs/deps.bst` | `stack` | the initramfs' runtime closure: 13 FSDK components + 7 GBM elements (below) | — |
| `elements/oci/initramfs/filesystem.bst` | `script` | runs `prepare-image.sh` with `INITRD_MODE=oci`, then `generate-initramfs` | — |
| `elements/oci/initramfs/initial-scripts.bst` | `collect_initial_scripts` | collects `/etc/fdsdk/initial_scripts` for the above | — |
| `elements/oci/initramfs/image.bst` | `manual` | cpio + zstd pack of the generated tree; prepends `microcode.cpio` on x86_64 | — |
| `elements/gnomeos/initramfs/signed-modules.bst` | `manual` | copies `/usr/lib/modules`, unpacks `.ko.zst`, signs each `.ko` with the module key, repacks | 2 `local` (`files/boot-keys/MODULES.key`, `files/boot-keys/modules/linux-module-cert.crt`) |

`files/gnomeos/generate-initramfs/` is 28 files: `generate-initramfs.sh` (15
lines), `run-module.sh` (36), `copy-initramfs.py` (351), and 17 module
directories (`10-dirs`, `20-os-release`, `30-systemd`, `50-android`,
`50-bootc`, `50-confext`, `50-filesystems`, `50-glibc`, `50-kmod`, `50-live`,
`50-persist-dm`, `50-plymouth`, `50-repart`, `50-shell`, `50-sysctl`,
`50-tpm2`, `50-udev`), each with a `module.sh` plus eight rule/service/config
assets. `50-bootc/module.sh` is why the closure cannot omit bootc: it installs
`/usr/lib/bootc/initramfs-setup` and the ostree/bootc systemd units into the
initrd.

There is a sibling `elements/gnomeos/initramfs/{deps,filesystem,image,initial-scripts}.bst`
for GNOME OS's own non-OCI image. Frameless does not use it, but it shares the
generator, so upstream changes to the generator serve both variants.

### The GBM-only periphery the initramfs drags in

`oci/initramfs/deps.bst` is 13 FSDK elements plus these seven GBM references:
`gnomeos-deps/plymouth-gnome-theme.bst` (and `files/plymouth/`, two files),
`gnomeos-deps/udev-hide-usr.bst`, `gnomeos-deps/zram-generator.bst` (a Rust
build with three sources), `gnomeos/initramfs/signed-modules.bst`,
`oci/integration/os-release.bst`, `gnomeos-deps/bootc.bst`, and
`oci/integration/lvm2-enable-activation.bst`. On x86_64, `image.bst` adds
`gnomeos-deps/microcode.bst`, which needs `gnomeos-deps/intel-ucode.bst` and
`gnomeos-deps/iucode-tool.bst`. The generator's runtime deps add
`gnomeos-deps/python3-zstd.bst`. A full de-GNOME of the initramfs therefore
means dealing with up to eight more elements, not two.

### What frameless already carries

| Path | Role |
|---|---|
| `elements/oci/layers/image-stack.bst` | the only consumer of the boot spine: four `gnome-build-meta.bst:` references, plus the integration commands that lay out `/boot`, `/sysroot`, `/ostree`, and the `/var` symlinks |
| `elements/kernel/unsigned-modules.bst` | replaces `gnomeos/initramfs/signed-modules.bst` (the signing key is not in the public repo); stages modules and vmlinuz unsigned |
| `elements/oci/os-release.bst` | replaces `oci/integration/os-release.bst` so the image carries frameless's identity |
| `elements/freedesktop-sdk.bst` line 68 | overrides FSDK's `components/linux-module-cert.bst` with GBM's, to mirror GBM's FSDK override list and keep the kernel's cache key |
| `elements/gnome-build-meta.bst` | the two overrides above plus the patch queue |
| `patches/gnome-build-meta/0001-generate-linux-module-cert.patch` | the module certificate GBM's CI generates but the public repo does not carry |
| `project.conf` lines 32–34 and 171–174 | the `runtime.yml` include and the `collect_initial_scripts` element plugin are registered through the gnome-build-meta junction |

## What frameless would carry

Three scopes, from the smallest useful move to a clean cut:

| Scope | Elements | Files | Sources | Generated |
|---|---|---|---|---|
| **A. bootc only** (dakota's move) | `gnomeos-deps/bootc.bst`, `oci/integration/bootc-config.bst` | `files/oci/prepare-root.conf`, `files/oci/10-bootc.conf` | 1 git + 1 cargo2 (416 crate refs) | the cargo2 ref, regenerated from `Cargo.lock` |
| **B. A + the OCI initramfs** | + `gnomeos/generate-initramfs.bst`, `oci/initramfs/{deps,filesystem,initial-scripts,image}.bst` (7 total) | + 28 generator files (~30 total) | + 1 local | the initramfs image itself, built per image |
| **C. B + the peripheral closure** | + up to 8 elements (plymouth theme, udev-hide-usr, zram-generator, microcode, intel-ucode, iucode-tool, lvm2 activation, python3-zstd) | + `files/plymouth/` (2) | + 4 git sources | microcode.cpio |

Two qualifications on the counts:

- Scope A copied *verbatim* also needs GBM's `elements/buildsystems/make.bst`,
  `elements/buildsystems/recc-wrapper.bst`, `files/recc-wrapper/recc-wrapper`
  and `include/gcc-for-recc.yml`, or a swap to FSDK's
  `public-stacks/buildsystem-make.bst`. The swap is smaller; either way the
  element re-keys (below).
- Scope C can shrink by replacement rather than copying: FSDK already ships
  `components/plymouth.bst`, `udev-hide-usr` is one script's worth of udev
  rule, and microcode and zram are droppable from an initramfs at some cost to
  boot speed and swap behaviour. The initramfs needs *a* plymouth only because
  the GBM theme is in the closure; it does not need GBM's.

### The cache key is the hidden cost

BuildStream's strong cache key is a SHA256 over the element's base key, its
plugin key, public data, sources, its dependencies' keys, the owning project's
`fatal-warnings` list, and — for elements that run commands — the resolved
sandbox environment (`element.py`, `_calculate_cache_key`; `_project.py` for
the project inputs). A junction reference is computed inside the junction's
project, which is why frameless pulls gnome-build-meta's and freedesktop-sdk's
artifacts today (note 12: a `51.0-3` → `51.0-5` bump re-sourced 9 of 778
elements). A local copy is computed inside frameless's project, and the two
projects' project-level configuration differs in inputs that sit in every key:

| Key input | gnome-build-meta | frameless |
|---|---|---|
| `fatal-warnings` | `overlaps`, `unaliased-url`, `unstaged-files` | empty |
| project `environment` | `LC_ALL: en_US.UTF-8` (plus an aarch64 block) | none |

So a copied `gnomeos-deps/bootc.bst` does **not** inherit GBM's key. The first
frameless build compiles bootc's ~416 crates from source and lands in
frameless's own cache; every bootc bump compiles again until frameless's cache
holds the new key. The initramfs script elements re-key too, but rebuilding
them is cheap — the re-key matters almost entirely for bootc. "Copy the
element verbatim" buys the maintenance pattern, not the artifact.

## How fast upstream moves

Commits touching each path, per release cycle, on the `gnome-51` branch:

| Path | 48 | 49 | 50 | 51 |
|---|---|---|---|---|
| `gnomeos-deps/bootc.bst` | — | — | 5 | 5 |
| `oci/integration/bootc-config.bst` | — | — | 1 | 1 |
| `gnomeos/generate-initramfs.bst` | 1 | 4 | 0 | 1 |
| `files/gnomeos/generate-initramfs` | 4 | 8 | 11 | 6 |
| `oci/initramfs/*` | — | — | 5 | 7 |
| `gnomeos/initramfs/*` | 1 | 7 | 3 | 5 |
| `gnomeos-deps/zram-generator.bst` | 48 | 53 | 6 | 11 |
| `gnomeos-deps/plymouth-gnome-theme.bst` | 1 | 3 | 0 | 1 |
| `gnomeos-deps/microcode.bst` | — | — | — | 2 |

Reading the table:

- **bootc did not exist in GBM before the 50 cycle.** The element and the OCI
  initramfs were created on 2025-11-18 ("oci: Make the gnomeos images bootc
  compatible"). It has been touched ~10 times in ten months.
- **bootc upstream is much faster than GBM's pin.** Upstream cut 20 releases
  between v1.12.1 (2026-01-16) and v1.16.13 (2026-09-15), about 2.5 a month.
  GBM 50.0 shipped v1.12.1; 51.0 shipped v1.16.6 — four minor versions in one
  cycle; the gnome-50 branch has since been updated to v1.16.11. A frameless
  that owns bootc chooses its own cadence, but it also owns the `Cargo.lock`
  regeneration on every bump. Dakota's copy is 1,753 lines and 424 crate refs
  at v1.16.13 — seven patch releases ahead of GBM's pin.
- **The generator element is stable; its modules are not.** The element itself
  has 7 commits in its lifetime; the module directory takes 4–11 commits per
  cycle, mostly adding services, udev rules and PCR handling to the initrd.
- **The OCI initramfs layout was restructured three times since February 2026**:
  "Restructure the files a bit" (2026-02-19), "Move secure boot stuff to a new
  element" (2026-03-16), "Split initramfs into filesystem+image elements"
  (2026-06-21), plus the 26.08 fixes (2026-08-14). A pin bump is a boot-spine
  review, not a mechanical one.
- The zram-generator numbers are the dependency bot ("Update element refs"),
  not human churn. It is in the closure but not really part of the spine.

## What breaks when gnome-build-meta stops providing them

| Element | How it reaches the spine | What happens |
|---|---|---|
| `oci/layers/image-stack.bst` | four direct `gnome-build-meta.bst:` references | fails to load: element not found |
| `oci/layers/image.bst` | build-depends on `image-stack` | propagates |
| `oci/layers/image-init-scripts.bst` | build-depends on `image-stack` | propagates |
| `oci/chunkah/image.bst` | build-depends on `image-stack` and `image` | propagates |
| `oci/image.bst` (the default target) | build-depends on the three above | propagates |
| `elements/freedesktop-sdk.bst` line 68 | override: `components/linux-module-cert.bst` → `gnome-build-meta.bst:gnomeos/linux-module-cert.bst` | FSDK's kernel strictly build-depends on the cert element; a missing target breaks the kernel's load |
| `project.conf` | `collect_initial_scripts` plugin and `runtime.yml` include come through the GBM junction | only if the junction itself goes; FSDK also ships `collect_initial_scripts` and `runtime.yml`, so both are portable |

Two things that do **not** break: `desktop/gnome.bst` and `image/deps.bst`.
`gnomeos-deps/deps.bst` has no bootc or initramfs references — checked
directly — so replacing the desktop never touched the spine, and a non-GNOME
payload already loses no boot capability today. The spine's only consumer is
`image-stack.bst`.

Also worth naming: `elements/gnome-build-meta.bst`'s overrides for
`signed-modules` and `os-release` become dead code if their targets disappear,
and frameless's own `kernel/unsigned-modules.bst` and `oci/os-release.bst`
would need to be re-pointed at frameless's own spine elements.

## Is freedesktop-sdk growing any of this?

**bootc: yes, but as a draft example, not a boot spine.**

- Work item [#1975 "Create example using bootc"](https://gitlab.com/freedesktop-sdk/freedesktop-sdk/-/work_items/1975)
  (opened 2026-04-26) asks for one VM example per update technology — ostree,
  sysupdate, bootc — tested in CI, and names projectbluefin/dakota as a
  downstream using bootc.
- Draft MR [!32072 "Add bootc to oci"](https://gitlab.com/freedesktop-sdk/freedesktop-sdk/-/merge_requests/32072)
  (opened 2026-05-12, author `tpollard`, one commit on 2026-07-07, pipeline
  green, no conflicts, still draft, no milestone) adds
  `elements/components/bootc.bst` (bootc v1.15.2, behind GBM's v1.16.6),
  `elements/oci/bootc-integration/bootc-config.bst` with the same two files as
  GBM, `oci/layers/bootc{,-init-script,-stack}.bst`, and `oci/bootc-oci.bst`.
- It is an *example*: `bootc-oci.bst` builds an OCI image on top of
  `oci/sdk-oci.bst` (the SDK image) and marks it `containers.bootc=1`. It
  contains no initramfs generator, and nothing in the MR replaces
  `generate-initramfs`.

Timing: FSDK cuts a major stream every September (21.08 → 26.08, all on
September 1). A merge to `master` after 26.08 would ship in the next major,
~27.08 — about a year away — unless it is deliberately backported to a stable
stream. Even then, FSDK's bootc would still need an initramfs story before it
could replace GBM's.

**The initramfs: no.** FSDK's own bootable examples (`elements/vm/boot/efi*`,
`efi-ostree`, `efi-secure`) build dracut-based initrds from
`components/dracut.bst`; there is no `generate-initramfs` equivalent and no
work item proposing one. FSDK does already ship pieces the spine needs:
`components/ostree.bst`, `components/composefs.bst`, `components/plymouth.bst`,
and `components/linux-module-cert.bst` — the last explicitly documented as
"should be overridden in the junction by downstream projects", with an empty
`files/boot-keys/modules` in the repo.

## The alternative: keep taking them from gnome-build-meta

The structure already supports a non-GNOME payload; what it costs is the
junction, not the payload:

1. **Keep the junction and its overrides.** The pin, the patch queue
   (`patches/gnome-build-meta`), and the two element overrides stay. Frameless
   must also keep `elements/freedesktop-sdk.bst`'s override list byte-for-byte
   in sync with GBM's own list, or the graph diverges from the public caches
   and rebuilds — that requirement predates this question but it is the real
   long-term tax.
2. **Keep `image-stack.bst` the only consumer.** Do not let a non-GNOME
   payload reference `gnomeos-deps/deps.bst`; reference the four boot-spine
   elements directly, as the stack already does. A non-GNOME desktop then
   contains no GNOME packages; the graph still contains GBM's boot elements
   and the GBM junction, but not the desktop.
3. **Accept the initramfs closure.** GBM's plymouth theme, udev-hide-usr,
   zram-generator, microcode and python3-zstd come with the initramfs. They are
   OS plumbing, not GNOME apps, but they are GBM-maintained.
4. **Review pin bumps as boot-spine changes.** The path moves of the last two
   cycles are the hazard; a bump that renames or restructures the initramfs
   elements fails loudly at load time, which is acceptable, but it should be
   caught in review with the diff, not by a red build.
5. **Note the override-mirror caveat.** "FSDK provides it" and "frameless uses
   FSDK's build" are different statements: the override list replaces FSDK's
   glib, systemd, cairo, pango, gtk3, flatpak and more with GBM's builds. A
   payload that wants zero GBM code in its closure cannot get there while the
   list mirrors GBM's — even FSDK's plymouth would pull GBM's gtk3 through the
   `components/gtk3.bst` override.

The middle path is dakota's, and it is proven: own **bootc only** (a local
element overriding `gnomeos-deps/bootc.bst`, tracking v1.16.13 against GBM's
v1.16.6) and keep taking the initramfs from GBM. That removes the bootc
element dependency and buys release cadence, but keeps the junction, and it
means re-vendoring the 400+ crate refs on every bootc bump.

## What this means for the move

- The minimum credible "own the boot spine" is scope B: bootc, its config, the
  generator, and the four OCI initramfs elements — ~7 elements and ~30 files.
  The peripheral closure (scope C) is separable and can be deferred by
  keeping GBM's small OS elements or replacing them one at a time.
- The expensive item is bootc's crate list, not the code: 1,721 lines,
  regenerated on every upstream bump, with upstream cutting a release every
  couple of weeks. A frameless that owns bootc needs a tracking recipe
  (`bst source track`) and a policy for how far behind to run.
- The initramfs is cheap to build and expensive to *track*: five small
  elements and 28 files, but ~10 changes a cycle across them, and the layout
  is still moving.
- Owning the spine means building it. The copy-verbatim idea does not avoid
  the build: frameless's project-level `fatal-warnings` and environment are in
  the key, so the copied bootc re-keys and compiles from source. Budget a bootc
  build (416 crates) in frameless CI, not a cache pull.
- FSDK is not a near-term exit. Treat "FSDK ships bootc" as a 2027
  possibility, and the initramfs generator as not coming at all.

## Open questions

- How long does bootc take to compile on frameless's runners, and does
  frameless's own artifact cache serve the second build? The key analysis says
  the first build is from source; the number to measure is the build time and
  where it is cached.
- Does frameless want to track bootc ahead of GBM (dakota does) or behind it?
  Ahead means owning the crate-list regeneration on a ~2–3/month cadence.
- Which peripheral elements does the initramfs really need? Plymouth is a boot
  splash, microcode is CPU errata fixes, zram is swap policy. Dropping any of
  them shrinks scope C but changes the image; each is a deliberate decision,
  not a mechanical copy.
- Where does the `collect_initial_scripts` plugin live after the move — the
  FSDK junction (which ships it) or a local plugin? Either works; the FSDK
  junction keeps frameless's plugin count at zero.
- Does the module-signing cert need to stay overridden at all? FSDK's
  `components/linux-module-cert.bst` is designed to be overridden, and
  frameless stages modules unsigned; pointing the kernel at FSDK's empty cert
  element would remove the boot chain's second tie to GBM (the first being
  `image-stack.bst`) — but it re-keys the kernel and rebuilds it.

## Sources

- gnome-build-meta at `be7cb317ee21d45197ba5139c77317f171e20c38` (branch
  `gnome-51`, tag `51.0`+5): `elements/gnomeos-deps/bootc.bst`,
  `elements/oci/integration/bootc-config.bst`, `elements/oci/initramfs/*`,
  `elements/gnomeos/generate-initramfs.bst`,
  `elements/gnomeos/initramfs/*`, `files/gnomeos/generate-initramfs/` (28
  files), `files/oci/{prepare-root.conf,10-bootc.conf}` — fetched via
  `https://gitlab.gnome.org/GNOME/gnome-build-meta/-/raw/<ref>/<path>` and the
  project's tree/commits API —
  <https://gitlab.gnome.org/GNOME/gnome-build-meta>
- gnome-build-meta release tags and branch tips (`48.0` 2025-03-18, `49.0`
  2025-09-15, `50.0` 2026-03-18, `51.0` 2026-09-16) —
  <https://gitlab.gnome.org/GNOME/gnome-build-meta/-/tags>
- freedesktop-sdk at `b02b59ffe19a49a402f357fd5fcb1d552ebc50d7`: absence of a
  bootc element, `elements/components/dracut.bst`,
  `elements/components/plymouth.bst`,
  `elements/components/linux-module-cert.bst`,
  `elements/vm/boot/efi*/deps.bst`, `plugins/elements/collect_initial_scripts.py`
  — <https://gitlab.com/freedesktop-sdk/freedesktop-sdk>
- freedesktop-sdk work item #1975, "Create example using bootc" (opened
  2026-04-26, names dakota as a bootc downstream) —
  <https://gitlab.com/freedesktop-sdk/freedesktop-sdk/-/work_items/1975>
- freedesktop-sdk draft MR !32072, "Add bootc to oci" (opened 2026-05-12,
  one commit 2026-07-07, draft, targets `master`) and its 12 changed files —
  <https://gitlab.com/freedesktop-sdk/freedesktop-sdk/-/merge_requests/32072>
- freedesktop-sdk release tags (21.08 → 26.08, September 1 each year) —
  <https://gitlab.com/freedesktop-sdk/freedesktop-sdk/-/tags>
- bootc release history, v1.12.1 (2026-01-16) → v1.16.13 (2026-09-15) —
  <https://github.com/bootc-dev/bootc/releases>
- BuildStream architecture, "Cache keys" (SHA256 over environment, element
  configuration, sources, dependencies) —
  <https://docs.buildstream.build/master/arch_cachekeys.html>
- BuildStream 2.8 source: `src/buildstream/element.py`
  `_calculate_cache_key()` (fatal-warnings and the resolved environment in the
  key) and `src/buildstream/_project.py` (`fatal-warnings`, `base_environment`)
  — <https://github.com/apache/buildstream/blob/2.8.0/src/buildstream/element.py>,
  <https://github.com/apache/buildstream/blob/2.8.0/src/buildstream/_project.py>
- dakota, `elements/gnomeos-deps/bootc.bst` (local bootc v1.16.13, 1,753
  lines, 424 crate refs) and `elements/gnome-build-meta.bst` (the override) —
  `~/Projects/dakota`
- frameless, `elements/oci/layers/image-stack.bst`,
  `elements/kernel/unsigned-modules.bst`, `elements/oci/os-release.bst`,
  `elements/freedesktop-sdk.bst`, `elements/gnome-build-meta.bst`,
  `patches/gnome-build-meta/0001-generate-linux-module-cert.patch`,
  `project.conf` — this repository
- `docs/research/12-core-versus-desktop.md` — the earlier pass that identified
  bootc plus the initramfs as the hard tie
