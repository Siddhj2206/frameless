# Core versus desktop: what a fork loses by swapping GNOME

Research note on which parts of the image come from gnome-build-meta and which
from freedesktop-sdk, written because the template claims "replace the desktop
and nothing else in the graph changes" — and today that claim is false. A fork
that swaps `desktop/gnome.bst` silently loses bootc, flatpak, the Flathub
remote, and a pile of OS plumbing, because they arrive through the desktop
stack.

Verified 2026-09-25 against freedesktop-sdk at the pinned junction ref
(`freedesktop-sdk-26.08.1-0-gb02b59ffe…`) and gnome-build-meta `51.0-5`.

## The claim, and why it is false

`elements/desktop/gnome.bst` is one element on purpose — the seam a fork
replaces. But it depends on `gnome-build-meta.bst:gnomeos-deps/deps.bst`, and
that stack is not a desktop. It is ~90 entries, most of which are the OS.

There are three doors, not one:

1. **`gnomeos-deps/deps.bst`** — the desktop plus most of the OS plumbing.
2. **`elements/freedesktop-sdk.bst`'s `overrides:`** — flatpak, systemd,
   systemd-libs, systemd-ukify and xdg-desktop-portal are freedesktop-sdk
   elements *replaced* by gnome-build-meta's versions. Removing the desktop
   does not remove these; they are a separate lever.
3. **`elements/oci/layers/image-stack.bst`** — bootc, the initramfs,
   linux-firmware, sudo. Already explicit, and already correct.

## Method

Every direct entry of `gnomeos-deps/deps.bst` was checked against
freedesktop-sdk's complete element tree at the pinned ref — 1218 paths,
fetched page by page from the GitLab tree API. A name is "FSDK" only if the
element exists there; "GBM-only" means it exists in no FSDK path.

## Available from freedesktop-sdk (not lost)

A fork that drops the desktop loses the *dependency*, not the *element*. Each
of these is re-added from the FSDK junction without touching gnome-build-meta:

flatpak, systemd, systemd-ukify, xdg-desktop-portal, NetworkManager, upower,
geoclue, pipewire-daemon, wireplumber, mesa-default, linux-firmware, podman,
skopeo, sudo, btrfs-progs, ccid, iio-sensor-proxy, sof-firmware,
wireless-regdb-bin, steam-devices, jq, less, nano, vim, rsync, git, git-lfs,
iproute2, iputils, usbutils, nftables, openssh-systemd, open-iscsi, man-db,
bash-completion, bash-config — plus ostree and composefs.

This is the larger half, and it is the answer to "what does frameless assume?":
it assumes freedesktop-sdk is always there, and for these it is right.

## GBM-only: the residual (the actual loss)

### The boot chain — the hard tie

| Element | Why it matters |
|---|---|
| `gnomeos-deps/bootc.bst` | bootc is the update mechanism; FSDK ships ostree and composefs, not bootc |
| `oci/initramfs/image.bst` | the initramfs the image boots with |
| `gnomeos/linux-module-cert.bst` | the module signing cert the kernel build-depends on |
| `gnomeos/initramfs/signed-modules.bst` | already overridden to `kernel/unsigned-modules.bst` |

**This is the only hard tie.** A fork cannot drop the gnome-build-meta junction
without replacing bootc and the initramfs.

### Config and preset elements

systemd-presets, preset-all, flathub-config, journald-config,
nm-connectivity-config, sysupdate-config, pcrlock-config, disable-iscsi,
udev-hide-usr, hidraw-udev, ld-config, modprobe-config, debuginfod-config,
vte-config, nano-default-editor, gnome-mimeapps.

These are files, not builds. A fork that drops GNOME would need to supply them
(or accept the defaults), but they are small and copyable.

### Packages

fish, fprintd, opensc, pam-pkcs11, nss-mdns, switcheroo-control, uresourced,
zram-generator, boltd, mokutil, sysext-utils, alsa-ucm-conf,
android-udev-rules, distrobox, toolbox, kmscon, uinput, nvme-cli, oo7-cli,
wsdd, bindfs, firewalld.

Hardware and integration conveniences, mostly. Judgement calls among them:
`oo7-cli` and `wsdd` are desktop-adjacent (secret service, gvfs); the rest are
OS-level.

### Desktop-side, and belongs with the desktop

dnsmasq and phodav (rygel), spice-vdagent, plymouth-gnome-theme,
gnome-mimeapps, the ibus engines, noto-cjk, words,
xdg-desktop-portal-gnome, xdg-desktop-portal-gtk, and the three
`core/meta-gnome-*` stacks with `sdk-platform.bst`.

## What to do about it

Split the manifest so the seam matches the claim:

```
elements/core/deps.bst       OS plumbing: FSDK where FSDK has it, GBM for the residual
elements/desktop/gnome.bst   the GNOME half only
elements/image/deps.bst      core + desktop + runtime + custom
```

Every reference stays a junction reference, so nothing is built here and the
artifacts still come from the public caches. `core/deps.bst` should reach for
**FSDK directly wherever FSDK has the element** — that is what makes the core
desktop-independent rather than merely desktop-adjacent.

### Why it does not invalidate the graph

- FSDK's elements are already in the graph: `gnomeos-deps/deps.bst` reaches
  them through gnome-build-meta's FSDK junction, which frameless overrides to
  ours, so it is the *same node* either way — same key, same artifact.
- gnome-build-meta's elements keep their keys: they are computed inside
  gnome-build-meta's project, and a junction `ref` bump only changes the
  sources of the elements those commits touched (measured: `51.0-3` → `51.0-5`
  processed 9 of 778).
- Only the compose (`oci/layers/image.bst`) and `oci/image.bst` change key.
  They rebuild in seconds, from the same artifacts.
- If the union is the same set, the composed filesystem is identical, and
  `oci/image.bst`'s ownership-basis verify fails loudly if it is not.

### The invariant that makes it safe

`core/deps.bst ∪ desktop/gnome.bst == gnome-build-meta.bst:gnomeos-deps/deps.bst`

Checked by comparing `bst show --deps all` sets. Without it the split silently
freezes the package list at today's gnome-build-meta; with it, upstream drift is
a loud failure. The check belongs to the template, not to forks — a fork that
replaces the desktop *intends* to change the union, and template tests are
deletable.

### The overrides caveat

`core/deps.bst` asking FSDK for flatpak still gets gnome-build-meta's flatpak,
because `elements/freedesktop-sdk.bst` overrides it. That is deliberate for the
default image (coherence with the desktop), but it means "FSDK provides it" and
"we chose gnome-build-meta's" are different statements. The override list should
be commented as the second lever.

## Genericity

The template rule this encodes: **core is what must survive removing the
desktop.** It names no distribution's taste. A fork edits `desktop/gnome.bst`
(and the junction it depends on) and keeps `core/deps.bst`; a fork that wants
KDE adds its own desktop element beside core. Nothing in `core/` should
reference GNOME except the residual above, and that residual should shrink as
FSDK grows — the drift guard is what will tell us.

## Comparison with projectbluefin/server

Filled in 2026-09-25 from a source-reading pass over server's elements and
history.

### Server's shape

- `elements/base/base-stack.bst` is a **sandbox floor, not an OS**:
  `runtime-gnu`, `runtime-minimal`, `ca-certificates`, `tzdata`, `os-release`,
  `integration/extra-fs`, `integration/ldconfig`.
- `elements/bluefin-server/os-stack.bst` on `main` is Flatcar — its only FSDK
  references are the two integration helpers.
- **The real reference is the pre-cutover `os-stack.bst`**, at `6602af0af1`
  (parent of the cutover `83fdee56b8`): `runtime-minimal`, `uutils-coreutils`,
  `bash`, `ca-certificates`, `tzdata`, `extra-fs`, `ldconfig`, `systemd`,
  `dbus`, `dbus-broker`, `kmod`, `shadow`, `openssh-systemd`, `xfsprogs`,
  `gnupg`, `podman`, plus a kernel. Each was added for a demonstrated need —
  dbus for server#67–70, xfsprogs for `/var` growth, gnupg for sysupdate
  signing.
- `elements/installer/installer-stack.bst` is the surviving FSDK userspace:
  14 FSDK components plus a kernel and repart, no dracut.
- **The gnome-build-meta junction is vestigial.** Nothing under `elements/`
  references it; `project.conf` includes FSDK's `include/runtime.yml`
  (resolvable through the junction's own FSDK override) and declares
  `collect_initial_scripts`, which no element uses.

### The finding that matters

Server needs no gnome-build-meta because it does not use bootc: its update path
is sysupdate plus sysext. **The hard tie is the update mechanism, not the
desktop.** frameless is a bootc image, so `gnomeos-deps/bootc.bst` and
`oci/initramfs/image.bst` are intrinsic to what it is. A fork that wants to drop
the junction must replace the boot chain, and that is a different image — worth
saying plainly in the split's comments rather than leaving as a surprise.

### Extras: what a desktop-less FSDK image needs that our list lacks

`runtime-gnu`, `systemd`, `dbus` + `dbus-broker`, `kmod`, `shadow`,
`openssh-systemd`, `sudo`, a network manager, `xfsprogs`, `podman`,
`ca-certificates`, `tzdata`, `integration/extra-fs`, `integration/ldconfig`,
and `gnupg` only for sysupdate.

Most are FSDK elements a fork re-adds directly. Note `openssh-systemd`: it is
reachable today only through `gnomeos-deps/deps.bst`, so it *is* lost with the
desktop unless core names it. That class — FSDK-available but only reachable via
the desktop stack — is the one the split exists to fix.

### Correction to the residual list

Five GBM-only direct entries were missing from the table above:
`wpa-supplicant-config`, `NetworkManager-openconnect`, `NetworkManager-openvpn`,
`NetworkManager-vpnc`, `noise-suppression-for-voice` — plus the
`deps-x86_64` / `deps-aarch64` hardware stacks. All desktop or hardware side.

### Keep, move, drop

- **Keep in core**: bootc and `oci/initramfs/image.bst` (both already explicit
  in `image-stack.bst`), the *mechanism* of `systemd-presets` (server writes its
  own — `os-sshd-preset.bst`), and `linux-module-cert` retargeted at FSDK's
  `components/linux-module-cert.bst`; `signed-modules` is already replaced.
- **Move to the desktop side**: preset-all, udev-hide-usr, hidraw-udev,
  modprobe-config, vte-config, gnome-mimeapps, fprintd, switcheroo-control,
  uresourced, alsa-ucm-conf, android-udev-rules, oo7-cli, wsdd, bindfs,
  nss-mdns — plus the nine already listed as desktop-side.
- **Distribution taste rather than OS**: flathub-config (FSDK has
  `vm/config/flathub.bst`), nm-connectivity-config, sysupdate-config,
  pcrlock-config, disable-iscsi, ld-config (FSDK's `integration/ldconfig`
  covers it), debuginfod-config, nano-default-editor, fish, opensc,
  pam-pkcs11, zram-generator, boltd, mokutil, sysext-utils, distrobox,
  toolbox, kmscon, uinput, nvme-cli, firewalld.

**Move does not mean delete.** The template's default image should not lose
content as a side effect of a refactor: "move" puts the entry on the desktop
side of the split, and "taste" marks it as a candidate to drop *later*,
deliberately, in a change whose whole point is that the image changes.

### Drift-guard amendment

If `core/` ever retargets an element — FSDK's module cert instead of
gnome-build-meta's, say — the literal
`core ∪ desktop == deps.bst` equality fails by design. The guard should compare
the union of the *resolved* elements, and a retarget should relax it
deliberately, with the reason recorded next to it.

## Open questions

- Which of the "distribution taste" entries do we keep in the default image?
  Every one we keep needs a justification, or the split just relocates the
  problem instead of answering it.
- Does the drift guard belong in `validate-bst.yml` or the bats suite? It needs
  a loaded graph, so the workflow.

## Sources

- freedesktop-sdk element tree at `b02b59ffe19a49a402f357fd5fcb1d552ebc50d7`
  (GitLab tree API, 1218 paths)
- gnome-build-meta `elements/gnomeos-deps/deps.bst` at
  `51.0-5-gbe7cb317ee21d45197ba5139c77317f171e20c38`
- gnome-build-meta `elements/core/meta-gnome-core-{apps,shell,os-services}.bst`,
  `elements/sdk-platform.bst`, `elements/core/gnome-software.bst`
- `projectbluefin/server` — `elements/base/base-stack.bst`,
  `elements/bluefin-server/os-stack.bst` on `main` and at `6602af0af1` (the
  pre-Flatcar FSDK userspace), `elements/installer/installer-stack.bst`,
  `elements/gnome-build-meta.bst`, `project.conf`
