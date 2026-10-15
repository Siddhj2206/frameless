# The ublue runtime: how the references use projectbluefin/common, and what frameless bundles

Research note for the obligation in `PLAN.md` that "the runtime is a payload".
frameless bundles `projectbluefin/common`'s shared half, `ublue-os/brew`, and
two first-boot units. The open question is whether the default image should
keep carrying that, or whether it becomes something a fork opts into. This
note gathers the facts the decision needs: how each P0 reference treats the
same upstream, what `common` actually contains, what frameless takes today, and
what would make removal expensive.

Verified 2026-09-30 against `projectbluefin/common` at `main` (`528189efc`) and
at the three pins the references use — frameless `v2026.08-163-g3399e477`,
dakota `v2026.08-112-g8df20e80`, server `v2026.08-108-gd46c4df9` — plus the
local checkouts of dakota, server and fsdk-containers, and `ublue-os/brew` at
`373e0ac`. Published-image sizes were read from GHCR the same day.

## What "the ublue runtime" is made of

Three upstream pieces, and only one is `projectbluefin/common`:

| Piece | Source | What it contributes |
|---|---|---|
| `common` | [projectbluefin/common](https://github.com/projectbluefin/common) | ujust and its recipes, Brewfiles, setup hooks, systemd units and presets, udev rules, Flatpak preinstall, OEM hooks |
| Homebrew integration | [ublue-os/brew](https://github.com/ublue-os/brew) | `brew-setup`/`brew-update`/`brew-upgrade` units, the `01-homebrew` preset, shell profile, and the prebuilt Homebrew tarball (`ghcr.io/ublue-os/brew`) |
| First-boot units | dakota, not `common` | `ublue-boot-timeout`, `ublue-firstboot-date`, and the Flatpak-preinstall condition drop-in. `common` ships none of these |

A fourth distinction matters throughout: `common`'s git tree and `common`'s
**OCI image are not the same payload**. The Containerfile builds `umotd` and
`uwelcome` binaries, copies wallpaper art, and fetches udev rule sets into the
image — none of which is in the git checkout. A BuildStream consumer that takes
`common` by `git_repo` (dakota, server, frameless all do) gets the checked-in
files only.

## The three P0 references

| Reference | Consumes `common`? | Mechanism | Takes |
|---|---|---|---|
| [dakota](https://github.com/projectbluefin/dakota) | Yes, nearly all of it | `git_repo` source in `elements/bluefin/common.bst` | `system_files/shared/` **and** `system_files/bluefin/`, plus the branding submodule, with three patches and two removals |
| [projectbluefin/server](https://github.com/projectbluefin/server) | One unit only | `git_repo` source in `elements/bluefin-server/os-countme.bst` | The countme helper, unit, timer and preset |
| [projectbluefin/fsdk-containers](https://github.com/projectbluefin/fsdk-containers) | No | — | Nothing; its Homebrew is a separate nspawn lane built from `Homebrew/brew` |

### dakota — the full consumer

`elements/bluefin/common.bst` is a `git_repo` source at
`v2026.08-112-g8df20e80` ([dakota, elements/bluefin/common.bst](https://github.com/projectbluefin/dakota/blob/main/elements/bluefin/common.bst)).
It installs **both halves**: `system_files/bluefin/usr` + `etc` and
`system_files/shared/usr` + `etc`, then `bluefin-branding/system_files/etc`
from a pinned `git_module` of [projectbluefin/branding](https://github.com/projectbluefin/branding).

Dakota takes common whole and then edits it:

- **Three patches** (`patches/common/`): fastfetch reads dakota's first-boot
  install date, Ghostty gets a dual light/dark theme, and `uwelcome.sh` is
  guarded to interactive shells only.
- **Two removals**: the `rechunker-group-fix` migration aid (dakota is a fresh
  BuildStream image, not a migration) and common's `umotd.sh` hook (dakota
  ships its own MOTD with a double-display guard).
- **In-place sed patches**: the GNOME background path is retargeted, and
  `ublue-image-info.sh` is taught to read `/run/ublue-os/booted-image` written
  by dakota's own `ublue-booted-image.service`.
- **ChairLift integration** (`files/chairlift/install.sh`): replaces common's
  `preinstall.d/chairlift.Brewfile`, rewrites `/usr/bin/brew-preinstall`, and
  swaps the Frostyard policies and icons for `io.projectbluefin.*`. It refuses
  to run unless common's `brew-preinstall --capabilities` reports
  `external-chairlift-v1`, so the two repos are pinned to each other by an API
  check.
- **Recipe overrides** (`elements/bluefin/just-overrides.bst`): common's
  `default.just`, `changelog.just` and `system.just` are replaced wholesale
  (overlap-whitelisted), plus dakota's `flutter.just` and two Brewfiles.

Dakota's Homebrew is the same two-element pattern frameless uses:
`bluefin/brew.bst` (git, `ublue-os/brew`) and `bluefin/brew-tarball.bst`
(`ghcr:ublue-os/brew`, per-arch digests). Its first-boot services are its own
local files (`files/firstboot/`, `files/service-overrides/`), and its Flatpak
preinstalls are local (`files/oci/bluefin-flatpak`), consumed by common's
`flatpak-preinstall.service`.

Two facts worth carrying forward:

- **Common's Containerfile builds the binaries, and git consumers don't get
  them.** Dakota's `elements/bluefin/uwelcome.bst` says it outright: "common
  ships the hooks that invoke it … but builds the binary in its Containerfile,
  which Dakota does not consume, so we ship the release binary ourselves like
  `umotd.bst`." Dakota also re-adds `fastfetch`, Ghostty, wallpapers and
  `uupd` as its own elements.
- **The countme reporter is scoped to dakota at the pin frameless uses.**
  `bluefin-countme` exits 0 unless `image-name` starts with `dakota`; server
  pins an earlier revision where the same script reports for any image.

### server — the countme-only consumer

Server is the counter-example. It takes exactly one thing from common, in
`elements/bluefin-server/os-countme.bst` ([server, os-countme.bst](https://github.com/projectbluefin/server/blob/main/elements/bluefin-server/os-countme.bst)):

- `system_files/shared/usr/libexec/bluefin-countme`
- `system_files/shared/usr/lib/systemd/system/bluefin-countme.service`
- `system_files/shared/usr/lib/systemd/system/bluefin-countme.timer`
- `system_files/shared/usr/lib/systemd/system-preset/03-bluefin-countme.preset`

That is the whole dependency. The element's own description says the reporter
is "the same unit and helper every other image ships, so this image counts
through exactly the same bluefin-countme as the rest of the family." The
element deliberately does **not** apply the preset itself — it relies on the
image's own preset handling.

Server writes the `image-info.json` the reporter reads
(`bluefin-server/os-image-info.bst`, `{"image-name": "server"}`) because a
DM-verity DDI has no OCI identity of its own. It ships a plain system-wide
`justfile` for k0s management (`files/os/justfile` via `os-justfile.bst`) but
no `ujust`, no Homebrew, no Flatpak preinstalls, no first-boot units, and no
`just` element at all.

So the family's one genuinely cross-shape artefact is the countme unit — and
even that arrives through a git pin, not the OCI layer.

### fsdk-containers — no ublue runtime

`fsdk-containers` does not reference `projectbluefin/common` anywhere in its
elements, `project.conf`, `include/`, `Justfile` or `catalog/`. The only
"ublue" strings in the repository are the org's CI callers and the read-only
`ublue-os/*` policy notes.

What it has instead is a **Homebrew nspawn machine image**, built from
upstream, not from the ublue runtime:

- `elements/brew/brew-prefix.bst` stages `Homebrew/brew` 6.0.22 into
  `/home/linuxbrew/.linuxbrew` — "the brew.git checkout IS the install".
- `elements/brew/brew-deps.bst` and `brew-runtime.bst` add the FSDK runtime
  Homebrew needs (ruby, git, curl, gcc, patchelf, make, tar, zstd, shadow…).
- `elements/oci/brew-nspawn.bst` assembles a machinectl-compatible rootfs
  tarball, `homebrew-env-6.0.22.tar.zst`, plus `SHA256SUMS` for
  systemd-sysupdate.
- The Justfile has a `brew` group (`build-brew`, `export-brew`, `verify-brew`,
  `install-brew`) that imports it as a local `machinectl` machine; it is not
  one of the catalog images.

No ujust, no Flatpak preinstalls, no first-boot services. The lesson for
frameless: a container shape that wants Homebrew can take upstream Homebrew
directly; the ublue integration layer is a desktop-distribution convention,
not a container requirement.

## projectbluefin/common — the inventory

### Layout

At `main` the repository is 624 tree entries, 441 of them files. Top level:

| Path | What it is | Size |
|---|---|---|
| `system_files/` | The payload. Two overlay layers at `main` (three at frameless's pin — `nvidia/` was removed), merged later-wins | 359 entries |
| `docs/` | Agent skills (`docs/skills/`, 120 entries), contributing guides, design notes, factory model | 142 entries |
| `tests/` | pytest + ~45 bats suites, registered in the Justfile | 58 entries |
| `.github/` | CI workflows, issue form, CODEOWNERS | 22 entries |
| `specs/` | Epics, product scope, release plan — planning artefacts, not image content | 17 entries |
| `scripts/` | Doc-link, OCI-ref, skill-index and Brewfile validators; a movie renderer | 8 entries |
| `bluefin-branding` | Git submodule → [projectbluefin/branding](https://github.com/projectbluefin/branding) | submodule |
| root files | `Containerfile`, `Justfile`, `README.md`, `AGENTS.md`, `CONTRIBUTING.md`, `LICENSE`, `cosign.pub`, `renovate.json`, `cliff.toml`, `.gitmodules` | — |

`system_files/README.md` is the authoritative description of the split; the
README is the human-facing one.

### The split, and its actual names

The v1 spec's `shared/` and `bluefin/` are real, one level down:

- **`system_files/shared/`** — applied to every Bluefin-family variant:
  "bluefin, bluefin-lts, dakota, knuckle, and any downstream fork." The rule:
  "a file goes in `shared/` if its absence would meaningfully degrade the
  experience on any variant, or if it provides infrastructure consumed by all
  variants."
- **`system_files/bluefin/`** — applied only to the Bluefin GNOME desktop:
  dconf defaults and locks, brand identity, GNOME Shell extensions, Bazaar
  configuration, Bluefin recipes and Flatpak lists. The rule: GNOME desktop,
  Bluefin identity, or meaningless on headless/non-GNOME.
- **`system_files/nvidia/`** — existed at frameless's pin (a Flatpak runtime
  sync unit and script, 3 files); removed from `main` on 2026-09-27 as
  "produced-but-unconsumed" ([common#1263](https://github.com/projectbluefin/common/pull/1263)).
  The README still describes it; the tree no longer has it.

Two submodules also land in the bluefin layer: `bluefin-branding`
(`COPY /bluefin-branding/system_files /system_files/bluefin` in the
Containerfile) and the `custom-command-list` GNOME Shell extension.

### `shared/` — what is in it

119–121 files, **2.0 MiB at `main`, 3.7 MiB at frameless's pin** (the pin also
carries two large ChairLift SVGs that `main` has since dropped). Categories:

| Category | Files | Examples |
|---|---|---|
| ujust | ~9 | `usr/bin/ujust` wrapper; recipes `00-entry.just`, `apps.just`, `default.just`, `shared.just`, `update.just`; `ujust-flags`; bash/zsh/fish completions |
| Brewfiles | 16 | `homebrew/{cli,fonts,fonts-dev,ide,experimental-ide,ai-tools,cncf,k8s-tools,swift,artwork,video-wallpaper,wallpaper-slideshow}.Brewfile`, `preinstall.d/{chairlift,system-cli}.Brewfile`, `oem/{ASUS,Framework}/packages.Brewfile` |
| systemd | ~19 | `flatpak-preinstall.service`, `flatpak-appstream-refresh.service`, `bluefin-countme.{service,timer}`, `ublue-system-setup.service`, `uupd.{timer,service.d}`, `uupd-on-ac.service`, `uupd-resume.timer`, `rechunker-group-fix.service`, user units `brew-preinstall.service` and `ublue-user-setup.service`; presets `00-rechunker`, `01-uupd`, `02-flatpak-appstream`, `03-bluefin-countme`, `01-brew-preinstall` (user) |
| setup hooks | ~9 | `usr/lib/ublue/setup-services/{libsetup.sh,hookrunner.sh}`, the three `ublue-*-setup` dispatchers, `system-setup.hooks.d/{10-framework,11-asus}.sh`, `user-setup.hooks.d/{10-theming,20-oem-brew}.sh` |
| udev rules | 15 | hardware quirks: Wooting, Realtek, Framework 16, ZSA, Steam Horipad, AMD s2idle, Titan Key… |
| shell plumbing | ~10 | `etc/profile.d/{caffeinate,ublue-fastfetch,uwelcome}.sh`, fish `vendor_conf.d`, Ghostty skel config, `sudoers.d/001-bootc` |
| polkit | 4 | ChairLift bootc policy, `org.ublue.privileged.user.setup`, two rules |
| pki | 5 | fulcio, rekor, quay toolbx, `ublue-os.pub`, `ublue-os-backup.pub` |
| containers | 3 | `policy.json`, `registries.d/{ublue-os,quay.io-toolbx-images}.yaml` |
| OEM | 5 | ASUS/Framework logos, Framework desktop conf, Brewfiles |
| wrappers and helpers | ~13 | `ublue-image-info.sh`, `ublue-image-repo`, `bootc-update-stage`, `brew-preinstall` (wrapper + 16 KB libexec), `luks-tpm2-autounlock`, `rechunker-group-fix`, `ublue-bling`, `ublue-bling-fastfetch`, `ublue-fastfetch`, the three `ublue-*-setup` dispatchers |
| bling | 3 | `share/ublue-os/bling/{bling.sh,bling.fish,bash-preexec-rearm.sh}` |
| misc config | ~12 | `etc/ublue-os/tags.json`, `etc/uupd/config.json`, geoclue beacondb, modprobe.d, pipewire/wireplumber snippets, two Framework ICC profiles, ChairLift config and desktop entry, goose config |

### `bluefin/` — what is in it

95–100 files, **3.8 MiB at `main`, 3.5 MiB at the pin**. It is mostly art and
desktop taste:

| Category | Files | Examples |
|---|---|---|
| Branding and art | ~40 | Fedora/Bluefin pixmaps, 15 face avatars, Bluefin logos (png, sixels, symbols), plymouth watermark, wallpaper webm, four SVG icons |
| dconf | 6 | five `distro.d` defaults (folders, keybindings, Ptyxis palette, custom-command menu, searchlight) plus locks |
| Bazaar | 6 | `bazaar.yaml`, `curated.yaml` (10 KB), `blocklist.yaml`, `hooks.py` (5.7 KB), user unit, tmpfiles |
| GNOME desktop | ~8 | gschema override, shell extension submodule, fish prompt, Ptyxis palette, mimeapps, xdg-terminal-exec list, gnome-initial-setup vendor conf |
| Bluefin recipes | 3 | `system.just` (18.7 KB), `changelog.just`, `60-bonedigger.just` |
| Bluefin Brewfiles | 3 | `system-flatpaks.Brewfile`, `system-dx-flatpaks.Brewfile`, `full-desktop.Brewfile` |
| Flatpak overrides | 4 | system and skel overrides for Bazaar, Damask, Chrome, VS Code |
| desktop entries | 5 | bluefin-help, discourse, documentation, system-update, noop |
| zsh and misc | ~14 | zshrc/zprofile/zshenv, dynamic wallpaper, Damask setup, geoclue latitude, libvirt session config, bonedigger report, firefox global config, fastfetch.jsonc, otel config |

### Sizes

| Thing | Files | Content |
|---|---|---|
| `shared/` at `main` | 121 | 2,078,581 bytes (~2.0 MiB) |
| `shared/` at frameless's pin | 119 | 3,842,107 bytes (~3.7 MiB) |
| `bluefin/` at `main` | 100 | 3,995,873 bytes (~3.8 MiB) |
| `bluefin/` at frameless's pin | 95 | 3,631,619 bytes (~3.5 MiB) |
| `nvidia/` at frameless's pin | 3 | 3,538 bytes |
| whole repo at `main` | 441 blobs | — |
| published OCI image, amd64 layer | — | ~80.6 MB compressed (2026-09-30) |

The gap between ~5.8 MiB of checked-in `system_files` and an 80.6 MB published
layer is the Containerfile's build stage: wallpaper art from
`ghcr.io/ublue-os/bluefin-wallpapers-gnome`, the Go-built `umotd` and
`uwelcome` binaries, the game-devices udev rules, the YubiKey U2F rule, and
the ChairLift GSettings schemas. **A git consumer never sees those files.**

### Vendor-neutral, or Bluefin's taste?

`shared/` is "vendor-neutral" only in the family sense — the README says it is
shared with Aurora and that Aurora maintainers may cherry-pick it. It is not
distribution-neutral:

- `etc/ublue-os/tags.json` is `["bluefin", "gnome"]`.
- `bluefin-countme` posts to `https://countme.projectbluefin.io/metalink` and
  is named for Bluefin; at frameless's pin it only counts dakota images.
- `uwelcome`, `ublue-bling`, `ublue-fastfetch` are Bluefin-family branding.
- The OEM hooks are Bluefin's supported-hardware list (Framework, ASUS), and
  the Framework hook speaks `rpm-ostree` where the host has it.
- `rechunker-group-fix` is a Bluefin/LTS migration aid; the ICC profiles are
  Framework panel profiles; the Ghostty skel config picks Bluefin's terminal.
- The `uupd.service.d/10-bluefin.conf` drop-in and the ChairLift policies and
  cask are Bluefin product decisions.

What is genuinely reusable infrastructure: the ujust dispatcher and flags, the
setup-hook dispatcher (`hookrunner.sh` + `libsetup.sh` versioning), the
systemd unit/preset pattern, the Flatpak-preinstall service, the Brewfile
convention, the OEM-hook mechanism, and the container policy/registries
snippets. The recipes themselves sit in between: `default.just` is generic
(BIOS, logs, `clean-system`, `device-info`), `update.just` is ublue-flavoured
(`uupd`/`bootc`/Flatpak/brew in one command), and `apps.just` is a curated
app catalogue (JetBrains, OpenTabletDriver, ASUS tools, CNCF bundles).

### How it is built and published upstream

- **Local build** (`Justfile`): `just build` runs
  `git submodule update --init bluefin-branding` then
  `podman build -f ./Containerfile .`; `just check` lints the Justfile;
  `just test` runs pytest plus ~45 bats suites; `just overlay` composes the
  checkout (or the published image) into an erofs sysext; `just tree` inspects
  the image layout.
- **Containerfile**: Go build stages for `umotd`/`uwelcome`; a build stage
  that copies wallpapers, extracts checksummed ChairLift schemas, fetches 27
  sha256-pinned game-devices udev rules and the Yubico U2F rule; a final
  `FROM scratch AS ctx` stage that lays out `/system_files/shared` and
  `/system_files/bluefin`. There is a "ujust gate" that greps the checked-in
  completions so a `just`-generated shim cannot shadow them.
- **CI** (`.github/workflows/`): `validate.yml` (`just check`, shellcheck,
  pre-commit, submodule drift, registry/dconf guards), `build.yml` (buildah
  multi-arch on push to `main`, push `ghcr.io/projectbluefin/common` with
  `latest`, `YYYYMMDD` and sha tags, keyless cosign signing, Trivy CRITICAL
  scan), `release.yml` (monthly snapshot tag `vYYYY.MM` with git-cliff notes),
  plus skill-drift and downstream e2e callers. The `testsuite` repo runs the
  common behave suite against Bluefin LTS/Stable and Dakota after merge.
- **Consumption modes**: the published layer is consumed by Bluefin with
  `COPY --from=ghcr.io/projectbluefin/common /system_files/…`; dakota, server
  and frameless consume the **git repo**; `just overlay` produces a sysext.
  The content is plain files, so it is usable outside an OCI workflow — the
  BuildStream consumers prove it — but the OCI path is the one that gets the
  build-stage additions.

## What frameless bundles today, exactly

`elements/image/deps.bst` lists four runtime elements and one `just` element:

```
runtime/common.bst
runtime/brew.bst
runtime/brew-tarball.bst
runtime/firstboot.bst
gnome-build-meta.bst:gnomeos-deps/just.bst   # ujust needs `just` at runtime
```

### Mechanism per element

| Element | Source | Takes | Mechanism |
|---|---|---|---|
| `runtime/common.bst` | `github:projectbluefin/common.git` @ `3399e477` | `system_files/shared/usr/.` → `/usr`, `system_files/shared/etc/.` → `/etc` | `kind: git_repo`, `cp -r`; **shared only — the `bluefin/` half is deliberately not installed**; no patches; overlap-whitelists `/etc/environment` and `/etc/containers/policy.json` |
| `runtime/brew.bst` | `github:ublue-os/brew.git` @ `373e0ac` | `system_files/usr/.` and `etc/.` | `kind: git_repo`, `cp -r` |
| `runtime/brew-tarball.bst` | `ghcr:ublue-os/brew` | `system_files/usr/share/homebrew.tar.zst` | `kind: docker`, per-arch manifest digests; `runtime-depends: runtime/brew.bst` |
| `runtime/firstboot.bst` | local `files/firstboot/`, `files/service-overrides/` | `ublue-boot-timeout.service`, `ublue-firstboot-date.service` + `multi-user.target.wants` symlinks, `flatpak-preinstall.service.d/condition-check.conf` | `kind: local` |

`runtime/common.bst` also **generates the ujust completions** with the `just`
binary it build-depends on (`just --completions bash|zsh|fish` piped through
`sed` to rename `just` to `ujust`), rather than shipping common's checked-in
completion files. Everything else is upstream, installed clean.

### Re-derived rather than copied

- The two first-boot units are **not from common** (common has no first-boot
  units at all). They are near-verbatim copies of dakota's
  `files/firstboot/` units — the `ublue-firstboot-date.service` description
  even lost the word "Dakota" in transit.
- The `flatpak-preinstall` condition drop-in is dakota's
  `files/service-overrides/` file, copied. Common ships the service, not the
  guard.
- The ujust completions are regenerated from the `just` binary instead of
  taken from common's git tree.
- The Homebrew integration is `ublue-os/brew`, a different upstream from
  common, exactly as dakota does it.

### What frameless adds that common does not provide

- `custom/` — the adopter seam. `elements/custom/custom.bst` installs
  `custom/brew/*.Brewfile` to `/usr/share/ublue-os/homebrew/`,
  `custom/ujust/**/*.just` concatenated to
  `/usr/share/ublue-os/just/60-custom.just`, `custom/flatpaks/*.preinstall`
  to `/usr/share/flatpak/preinstall.d/`, `custom/files/` over `/`, and
  `custom/config/` into `/etc/skel/.config/`.
- The two first-boot units and the Flatpak-preinstall guard, as above.
- `image-info.json` and `os-release`, from `elements/oci/os-release.bst` —
  frameless writes its own identity, which common's `ublue-image-info.sh`
  reads.
- It drops the whole `bluefin/` half, so none of the Bluefin branding, dconf,
  Bazaar, extension or Bluefin recipe content ships.

### What is dangling in the default image

Because frameless takes common by git and does not re-add what dakota re-adds,
some of the bundled shared content points at things that are not installed:

| Bundled | Missing dependency | Consequence |
|---|---|---|
| `etc/profile.d/uwelcome.sh`, fish greeting | `uwelcome` binary (built in common's Containerfile; dakota ships the release binary) | every non-root interactive shell tries to run `uwelcome` and fails |
| `uupd` units, config and `01-uupd.preset` (enables `uupd.timer`) | `uupd` binary (dakota installs it) | the timer is enabled but has no executable |
| `usr/bin/ublue-fastfetch` and aliases | `fastfetch` (dakota ships it) | the wrapper exits 0 early; harmless |
| `etc/skel/.config/ghostty/config.ghostty` | Ghostty (dakota ships it) | inert skel config |
| `bluefin-countme` unit, timer, preset | the reporter exits unless `image-name` starts with `dakota` at this pin | enabled but a no-op on frameless |
| `etc/ublue-os/tags.json` | — | the image declares `["bluefin", "gnome"]` |
| `rechunker-group-fix` unit | a Bluefin/LTS migration scenario | inert here |
| OEM hooks (`10-framework.sh`, `11-asus.sh`) | Framework/ASUS hardware | exit immediately on other hardware; the ASUS hook installs casks via brew when it matches |

## Coupling: what makes removal expensive

Removal is not hard structurally — nothing outside `elements/image/deps.bst`
and `elements/custom/custom.bst` names the runtime, and nothing in the boot
spine does. The cost is in the seams and in what would silently stop working:

1. **The manifest and `just`.** The four elements are four lines in
   `image/deps.bst`, plus `gnome-build-meta.bst:gnomeos-deps/just.bst`, which
   exists only because ujust needs `just` at runtime. Drop the runtime and
   that element goes too — unless a fork keeps `just` for its own recipes.
2. **The `custom/` seam is wired to ublue paths.** `custom/ujust/*.just` is
   concatenated into `60-custom.just`, which common's `00-entry.just` imports
   with `import?`. Without `runtime/common.bst` there is no `ujust` binary, no
   entry justfile, and no completions, so every recipe under `custom/ujust/`
   becomes a dead file. `custom/flatpaks/*.preinstall` is consumed by
   common's `flatpak-preinstall.service`; `custom/brew/*.Brewfile` are
   declarations that the custom ujust recipes invoke. Only `custom/files/`
   and `custom/config/` are runtime-agnostic.
3. **The first-boot drop-in targets a unit common owns.**
   `runtime/firstboot.bst` installs a drop-in for `flatpak-preinstall.service`
   — a service shipped by common's `shared/` layer. Neither freedesktop-sdk
   nor gnome-build-meta ships a Flatpak-preinstall service (checked at the
   pinned trees), so if the runtime goes, the drop-in is inert and Flatpak
   preinstalls have no service at all until a replacement is provided.
4. **First-boot enablement is already uncertain.** Common's units are enabled
   by presets (`01-uupd`, `03-bluefin-countme`, …) and by systemd's
   first-boot `preset-all`. systemd treats an **empty** `/etc/machine-id` as
   *not* a first boot; frameless seeds exactly that. Whether the presets are
   applied on a fresh deploy therefore depends on how bootc leaves
   `/etc/machine-id` after `bootc install` — which the boot-test lane
   (`docs/research/14-booting-in-ci.md`) is the right place to settle. A
   runtime that is never enabled is already closer to payload than it looks.
5. **Overlap whitelists encode a base dependency.** `runtime/common.bst`
   whitelists `/etc/environment` and `/etc/containers/policy.json` because
   shared ships files the GNOME OS base also ships. Removing the runtime
   removes the overlap rather than creating one; the base versions win. No
   other element reads those files.
6. **No drift guard.** `runtime/common.bst` installs upstream clean and
   asserts nothing about the layout. Dakota guards its sed patches with
   explicit checks; frameless does not. If common moves a directory, the
   failure is a missing file at runtime, not a build error. This is a
   pre-existing risk independent of the payload decision, but it is the
   reason a "keep it but make it optional" answer is not free.
7. **Size.** The Homebrew tarball is the dominant cost: 143 MB uncompressed
   in the image (research 09) and a ~149.5 MB compressed upstream layer. The
   common shared half is ~3.7 MB at the pin. If the runtime becomes optional,
   the bytes saved are almost entirely Homebrew, not common.
8. **CI and tests follow `custom/`, not the bundle.**
   `validate-brewfiles.yml`, `validate-flatpaks.yml`, `validate-justfiles.yml`
   and the unit tests exercise `custom/` content and the template's scripts;
   none asserts the bundled runtime's file list. So a runtime removal would
   not fail CI by construction — only by booting.

## Open questions

- Which preset-driven units actually enable on a fresh frameless deploy, given
  the empty `/etc/machine-id`? The answer decides whether the bundled runtime
  is doing anything at all today, and it is cheap to observe in the boot-test
  lane.
- If the runtime becomes a payload, is it consumed by git (today's mechanism,
  which misses the Containerfile's built binaries) or by the published OCI
  layer (which has them, but needs a BuildStream `docker` source and pins a
  digest)? Dakota answers the gap by re-adding binaries; frameless currently
  does not.
- What happens to `custom/`'s ujust/brew/flatpak seams when the runtime is
  not in the image? The map issue already lists "How `custom/` interacts with
  the runtime once the runtime is a payload" as unspecified
  ([frameless#64](https://github.com/Siddhj2206/frameless/issues/64)).
- Is `shared/` acceptable as the "vendor-neutral" half for a template that
  claims no distribution's taste, given `tags.json`, countme, `uwelcome`,
  bling and the OEM hooks?

## Sources

- `projectbluefin/common` — `README.md`, `system_files/README.md`,
  `AGENTS.md`, `Containerfile`, `Justfile`, `.gitmodules`,
  `.github/workflows/{build,release}.yml`; trees at `main` (`528189efc`) and
  at frameless's pin (`3399e477`); `system_files/shared/usr/bin/ujust`,
  `.../just/{00-entry,default,apps,update,shared}.just`,
  `.../systemd/system/{flatpak-preinstall.service,ublue-system-setup.service}`,
  `.../systemd/system-preset/01-uupd.preset`,
  `.../libexec/bluefin-countme`, `.../lib/ublue/setup-services/{libsetup,hookrunner}.sh`,
  `.../share/ublue-os/system-setup.hooks.d/10-framework.sh`,
  `.../etc/{ublue-os/tags.json,uupd/config.json,profile.d/uwelcome.sh}`,
  `.../usr/bin/{ublue-fastfetch,ublue-system-setup,brew-preinstall}`.
- Commit removing `system_files/nvidia/`:
  [common#1263](https://github.com/projectbluefin/common/pull/1263)
  (`a9ec4541ef`, 2026-09-27).
- `projectbluefin/dakota` — `elements/bluefin/{common,deps,brew,brew-tarball,firstboot-services,firstboot-date,flatpak-apps,just-overrides,uwelcome,umotd,uupd}.bst`,
  `patches/common/*.patch`, `files/{firstboot,service-overrides,chairlift}/*`.
- `projectbluefin/server` — `elements/bluefin-server/{os-countme,os-image-info,os-stack,os-justfile}.bst`,
  `files/os/justfile`.
- `projectbluefin/fsdk-containers` — `elements/brew/{brew-prefix,brew-deps,brew-runtime}.bst`,
  `elements/oci/brew-nspawn.bst`, `Justfile` (`brew` group), `catalog/`.
- `ublue-os/brew` — tree at `373e0ac`, `Containerfile`,
  `system_files/usr/lib/systemd/system/brew-setup.service`.
- `ghcr.io/ublue-os/brew:latest` and `ghcr.io/projectbluefin/common:latest`
  manifest sizes, read 2026-09-30.
- systemd first-boot preset semantics:
  [machine-id(5)](https://www.freedesktop.org/software/systemd/man/latest/machine-id.html)
  and [systemd.preset(5)](https://www.freedesktop.org/software/systemd/man/latest/systemd.preset.html).
- frameless — `elements/runtime/*.bst`, `elements/image/deps.bst`,
  `elements/custom/custom.bst`, `elements/oci/os-release.bst`,
  `include/os-release.yml`, `files/{firstboot,service-overrides}`,
  `docs/research/{09-image-size,12-core-versus-desktop,14-booting-in-ci}.md`.
