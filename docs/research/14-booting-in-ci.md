# Booting in CI: can a GitHub runner start this kernel?

Research note on what it takes to boot the built image inside GitHub Actions
and assert it reached a usable state. It exists because the golden path must be
boot-tested and nothing in CI starts a kernel today: the emergency-mode failure
on the current image reached a VM only because a person ran
`just generate-bootable-image` and `just boot-vm`.

Verified 2026-09-30 against the GitHub-hosted runner documentation,
`actions/runner-images`, bootc's CI, `projectbluefin/testsuite`, dakota's
workflows, systemd's mkosi CI, bootc-image-builder, and the local recipes at
this commit.

## The short answer

- Standard **x86_64 Ubuntu runners expose `/dev/kvm`** — public and private
  repositories, 2-vCPU and 4-vCPU sizes. The runner user cannot open it until
  the documented udev rule is applied. This is not a support contract: GitHub
  closed the documentation request for nested virtualization without promising
  anything (`actions/runner-images#12933`). Treat KVM as present in practice,
  verify it at runtime, and never silently skip the test when it is gone.
- **arm64 runners are not a viable target.** The maintainers say the ARM64
  hosted fleet does not surface a nested KVM device, and macOS does not support
  nested virtualization at all. A public repository does not need larger
  runners.
- The fallback is QEMU with `-accel tcg`: systemd's CI carries a **4× timeout
  multiplier for the QEMU-without-KVM case** (its one no-KVM lane disables
  QEMU entirely), and Microsoft's Quicksand documentation calls TCG **10–50×
  slower** than hardware acceleration. At this image's size, budget roughly
  **10 minutes with KVM** and **25–35 minutes with TCG** for the whole job.
- The assertion that matches the failure is a **login prompt on the serial
  console within a deadline, with no emergency-mode or panic marker**. Once a
  test user can be injected into the deployment, `systemctl is-system-running`
  adds the precise signal: `maintenance` means the rescue or emergency target
  is active.
- The emergency-mode failure **would have been caught**. It died in the
  initramfs, before `multi-user.target`; every candidate assertion fails on a
  system that never reaches it.

## KVM on GitHub-hosted runners

### What is actually available

| Runner label | Arch | `/dev/kvm` | Evidence |
|---|---|---|---|
| `ubuntu-24.04`, `ubuntu-22.04`, `ubuntu-26.04` (standard) | x64 | Yes, after the udev rule | GitHub changelog 2024-04-02 (hardware acceleration on 2-vCPU Linux runners, with the rule); bootc CI runs libvirt/TMT on `ubuntu-26.04` "leveraging the support for nested virtualization in the GHA runners"; testsuite's KVM action runs on `ubuntu-latest` |
| `ubuntu-24.04-arm`, `ubuntu-22.04-arm`, `ubuntu-26.04-arm` | arm64 | Do not rely on it | Maintainer, `actions/runner-images#14062`: "the ARM64 hosted fleet doesn't surface a nested KVM device"; dakota measured no `/dev/kvm` on `ubuntu-24.04-arm` on 2026-07-23; a separate report claims `ubuntu-24.04-arm` has it while `ubuntu-26.04-arm` lost it (`#14549`) — the reports conflict, so the lane is not dependable |
| `ubuntu-slim` | x64 | No | Runs in an unprivileged container; the docs say low-level kernel features are not supported and the job timeout is 15 minutes |
| `macos-*` | Intel/arm64 | No | Docs: nested virtualization is not supported (Apple Virtualization Framework limitation) |
| Larger runners | x64/arm64 | Not needed | Team/Enterprise only and billed per minute; standard runners are free and unlimited on public repositories |

Repository visibility does **not** decide KVM. It decides the standard runner's
size and billing: a public repository gets 4 vCPU / 16 GB / 14 GB SSD, a
private one gets 2 vCPU / 8 GB / 14 GB, and standard runners are free and
unlimited only on public repositories. Instance size does not decide it either:
GitHub added hardware acceleration to the 2-vCPU runners in April 2024; the
4-vCPU runners already had it.

The x86_64 evidence is consistent and independent:

- GitHub's own changelog documents KVM use on standard Linux runners and
  supplies the udev rule ([changelog](https://github.blog/changelog/2024-04-02-github-actions-hardware-accelerated-android-virtualization-now-available/)).
- GitHub's runner reference says Linux runners support hardware acceleration for
  the Android SDK tools.
- bootc's `bootc-ubuntu-setup` action conditionally writes the same udev rule
  when `libvirt: true`, and its integration tests are TMT + libvirt VMs.
- `projectbluefin/testsuite` boots a bootc image in a KVM-accelerated QEMU VM
  on `ubuntu-latest` and states "Runner must have KVM enabled (ubuntu-latest on
  GHA has it)".
- A `ubuntu-24.04` standard-runner report shows `kvm_amd` holding AMD-V so
  VirtualBox cannot claim it (`actions/runner-images#13202`) — KVM is not just
  present, it is loaded and in use.

Two footnotes matter for planning:

- `/dev/kvm` is `root:kvm`, mode `0660`, and the runner user is not in `kvm`.
  The documented fix, used by GitHub, bootc, and the testsuite, is:

  ```bash
  echo 'KERNEL=="kvm", GROUP="kvm", MODE="0666", OPTIONS+="static_node=kvm"' \
    | sudo tee /etc/udev/rules.d/99-kvm4all.rules
  sudo udevadm control --reload-rules
  sudo udevadm trigger --name-match=kvm
  ```

  GitHub's own documentation and every project above do exactly this. Without
  it QEMU fails to open the device even though it exists.
- The fleet moves. `ubuntu-latest` becomes Ubuntu 26.04 in November 2026
  (`actions/runner-images#14748`); the repository already pins `ubuntu-24.04`
  in `build-image.yml`, so the boot test should pin the same label. Re-verify
  KVM after any runner migration — a missing device must fail the job loudly,
  not turn the check into a no-op.

## The fallback: QEMU with TCG

If `/dev/kvm` is ever absent, the same QEMU invocation runs under TCG:

- `-accel tcg -cpu max` instead of `-accel kvm -cpu host`. `-cpu host` is not
  valid under TCG.
- `-smp 4` still helps: x86 TCG is multi-threaded (MTTCG) by default.
- Nothing else changes; `bootc install to-disk` and the disk image are I/O
  bound and are unaffected.

What it costs, from sources rather than a measurement:

| Source | Figure |
|---|---|
| systemd's mkosi CI | carries `timeout_multiplier=4` for `no_kvm=1` with QEMU; its only no-KVM entry (`ubuntu-24.04-arm`, Debian testing) also sets `no_qemu: 1`, so the lane skips QEMU rather than run TCG |
| Microsoft Quicksand performance guide | "TCG is 10–50× slower"; a small Ubuntu image boots in ~10–30 s under TCG versus under 1 s accelerated |
| projectbluefin/testsuite (KVM) | direct-kernel boot reaches SSH in ~30 s; UEFI/OVMF boot in ~45–60 s |

At frameless's size — 3989 MB compressed, 8314 MB uncompressed (research note
09) — the boot phase under KVM should be a minute or two; under TCG expect
**5–20 minutes for the boot phase alone** and **25–35 minutes for the job**.
That is an estimate extrapolated from a 10× factor, not a measurement of this
image. The first CI run should time each phase and the number should replace
this paragraph. Treat TCG as a fallback lane with a 60-minute timeout, not the
default, and do not let a missing KVM quietly downgrade the gate: either run
the TCG lane deliberately and report the duration, or fail with an explicit
"no `/dev/kvm` on this runner" annotation.

## What the assertion should be

A boot test is only as good as its assertion. The options, weakest to
strongest:

| Assertion | What it proves | Needs | Catches the emergency-mode failure? |
|---|---|---|---|
| QEMU process still running after N seconds | almost nothing | qemu | No |
| Serial console shows the bootloader/kernel started | firmware and kernel load | serial console | No |
| Serial console shows a **login prompt** (`login:`) | the system reached a getty, which is wanted by `multi-user.target` | `console=ttyS0` karg, headless serial | Yes |
| Serial console has **no** emergency/panic marker | rules out the specific failure | same | Yes (as a negative) |
| SSH works | networking and sshd came up | a user and key injected into the deployment | Yes |
| `systemctl is-system-running` is not `maintenance` | systemd did not fall into rescue/emergency; `--wait` blocks until boot completes | SSH (or guest agent) | Yes, with the exact state |
| `systemctl is-active multi-user.target` | the target dakota gates on | SSH | Yes |

The semantics that make `is-system-running` the right long-term assertion are
in systemd's own table: `running` (fully operational, exit 0), `degraded`
(operational, one or more units failed, exit non-zero), `maintenance` ("the
rescue or emergency target is active"), plus `initializing`/`starting` before
boot completes. `--wait` blocks until the boot finishes. So a gate of "the
state is never `maintenance`, and the failed-unit list is empty or allow-listed"
is precise. Note that a login prompt already implies `multi-user.target`:
systemd's getty generator starts `serial-getty@ttyS0` for every `console=` on
the kernel command line, and that unit is pulled in by `multi-user.target`.

Recommendation:

1. **Gate on the serial login prompt.** Boot the installed disk headless, add
   `console=ttyS0,115200` to the kernel arguments, drop `quiet` and `splash` so
   the log is diagnosable, capture the serial output to a file, and require a
   `login:` prompt before a deadline with no `emergency mode`, `Kernel panic`,
   `dracut-initqueue timeout`, or `Failed to start` markers. This needs no
   credentials, no image change, and no SSH — only the karg and a headless
   QEMU invocation.
2. **Add the systemd check as soon as it is cheap.** The testsuite gets SSH by
   mounting the deployment and injecting a user, key, and `sshd` enablement
   before boot; the same ~50 lines of shell would let frameless assert
   `systemctl is-system-running` and dump `systemctl list-units --state=failed`
   and `journalctl -b` into artifacts. Until then, the serial gate is the gate.
3. **Do not gate on `degraded` yet.** The image's baseline failed-unit list is
   unknown; failing on any failed unit would make the test red on day one.
   Report it, then tighten once the baseline is recorded.
4. **Always upload the serial log and the install log**, pass or fail. Both
   dakota and the testsuite treat the serial log as the primary debugging
   artifact; a red boot test without it is not actionable.

`bootc container lint` is not a substitute. Its own manual calls it
"relatively inexpensive static analysis checks" — it inspects the image, it
does not start it. For the composefs backend, bootc's own failure-detection
document says `bootc-root-setup.service` runs in the initramfs and "if this
service fails, the system will not boot at all (emergency mode or hang)", and
that composefs does not yet configure systemd boot entry counting. There is no
post-boot stamp to inspect; watching the console is the available signal.

## The existing local path, and what CI changes

`just generate-bootable-image` and `just boot-vm` already do the right thing:

- `generate-bootable-image` requires the image in rootful podman, allocates a
  30 GB sparse raw disk, and runs `bootc install to-disk --via-loopback` with
  `--filesystem btrfs --wipe --composefs-backend --bootloader systemd` and
  `--karg systemd.firstboot=no --karg splash --karg quiet`.
- `boot-vm` prefers native `qemu-system-x86_64` with `-enable-kvm -cpu host`,
  8 GB RAM, 4 vCPUs, OVMF pflash, virtio-vga, a GTK display, and user
  networking with `hostfwd tcp:127.0.0.1:2222-:22`. Its fallback container
  (`ghcr.io/qemus/qemu`) also requires `/dev/kvm` and serves an interactive web
  console — useless in CI.

The CI deltas are mechanical:

| Local | CI |
|---|---|
| `-display gtk` | `-display none` (or `-nographic`) |
| no serial | `-serial file:serial.log` |
| `--karg splash --karg quiet` | `--karg console=ttyS0,115200`, no `quiet`/`splash` |
| `-enable-kvm -cpu host` | `-accel kvm -cpu host` when `test -c /dev/kvm`, else `-accel tcg -cpu max` |
| OVMF from the host | `sudo apt-get install -y qemu-system-x86 ovmf`; prefer the 4 MB pflash variants (`OVMF_CODE_4M.fd` / `OVMF_VARS_4M.fd`) — the testsuite's UEFI skill found systemd-boot needs the larger variable store |
| human watches GTK | deadline loop over the serial file; fail and dump on timeout |

Disk space needs care. GitHub documents 14 GB SSD for a standard runner; the
testsuite's action says `ubuntu-latest` ships with ~25 GB free and that
`bootc install to-disk` plus the QEMU disk needs ~12 GB, so it runs
`ublue-os/remove-unwanted-software` first to free ~10 GB. bootc-image-builder
takes the other route: it bind-mounts container storage onto `/mnt`, "on GH
runners /mnt has 70G free space". Either is enough; the podman image plus the
installed disk image will not fit the documented 14 GB without one of them.

Where it should run:

- **A separate `boot-test` job in `build-image.yml`, `needs: build`,** pulling
  the pushed digest back from GHCR and booting that. Testing the pushed bytes
  is the point: a same-job test of the local podman store skips the registry
  round trip but cannot catch a publish-path mutation. The build job already
  has `steps.push.outputs.digest`; expose it as a job output.
- Or the same job after `just chunkify`, which is cheaper (no pull, no second
  runner) but lengthens the build job, competes for its disk, and a boot
  failure then blocks the publish rather than the promotion.
- Either way the boot test is a required check on `main`, and the promotion
  gate should refuse to promote without it. The README already names the gap:
  "the promotion gate checks the digest and the signature only ... `release/ready`
  means 'signed and unmodified', not 'functionally validated'." The
  projectbluefin reusable the gate calls exposes `run_release_gate` and
  `gate_suites` (default `smoke,common`, which run the Bluefin testsuite);
  frameless's own boot test is the better fit for a template, but the gate
  needs to learn about it either way.

## Would it have caught the emergency-mode failure?

Yes, and that is the design constraint. The failure was initrd units
(`systemd-journald`, `systemd-udevd`, `systemd-tmpfiles-*`,
`initrd-parse-etc.service`) failing, so the system never switched root and
never reached `multi-user.target`. Every assertion above fails on it:

- the serial console never prints a getty `login:` prompt;
- it prints the emergency banner, or hangs until the deadline;
- SSH never comes up;
- `systemctl is-system-running` would answer `maintenance`, or never answer.

The local reproduction was `generate-bootable-image` + `boot-vm`, so a CI test
built from the same two steps boots the same environment. A direct-kernel boot
(the bcvk style) would also catch it, because it runs the same initramfs; the
UEFI disk path is preferred only because it additionally covers the bootloader
and `bootc install to-disk`.

What a boot test still cannot catch:

- **Hardware and firmware**: secure boot, TPM, real GPUs, Wi-Fi, suspend,
  firmware blobs for machines nobody has.
- **The publish path**, unless it boots the pushed digest rather than the local
  store — hence the recommendation above.
- **Updates and rollbacks**: `bootc upgrade`/`switch`, staged deployment
  finalization, rollback. The testsuite has a lifecycle suite that does this;
  frameless's first boot test should not.
- **The desktop session**: a login prompt says the OS came up, not that GDM,
  GNOME, or a Flatpak works. dakota's testsuite asserts a Wayland socket; that
  is the next tier, not the first.
- **Failure modes that only appear on real installs**: partitioning choices,
  GRUB vs systemd-boot, LUKS, install-alongside. The UEFI path covers the
  default install only.

## Prior art

| Project | What runs | Posture |
|---|---|---|
| dakota | Local `just boot-fast`/`boot-test` boot the OCI image in an ephemeral VM via **bcvk** (qemu + virtiofs, KVM-only) and assert `graphical.target`, `gdm`, `bootc status`. `boot-test-aarch64.yml` does the same in CI but is manual and skips without `/dev/kvm`; `publish-smoke.yml` runs the testsuite `smoke` suite after publish | Boot tests exist, do not gate promotion today; the arm64 lane is parked because ARM runners lack KVM |
| projectbluefin/testsuite | KVM QEMU on `ubuntu-latest`; direct-kernel boot, SSH with an injected user/key, asserts a Wayland socket for GUI suites and runs behave via qecore; a UEFI/OVMF spike boots the installed disk, runs `bootc switch`, reboots, and confirms the new deployment; `common` suite runs in SSH mode in ~15 min | The closest thing to a production boot harness in this ecosystem; Bluefin-specific content |
| Bluefin / ublue-os/main | Build workflows do a **secureboot signature check** only — extract `vmlinuz`, verify with `sbverify`. No VM starts | Boot testing lives in projectbluefin/common's post-merge e2e and a weekly promotion-candidate run, not the image repos |
| bootc | CI integration tests run **TMT against libvirt VMs on `ubuntu-26.04`**, "leveraging the support for nested virtualization in the GHA runners"; the older install-tests job is disabled; local development uses bcvk | The upstream project treats nested virt on standard runners as normal |
| bootc-image-builder | Pytest integration builds qcow2 images and boots them via osbuild's `vmtest`, logging in over SSH with user/password and root/key; documents GH-runner disk workarounds (`/mnt` has 70 GB) | Boot assertions are login + `bootc status` + kernel args |
| systemd | mkosi CI boots VMs on GitHub runners; the ARM/no-KVM lane sets `no_kvm: 1` **and** `no_qemu: 1`, and the workflow carries a 4× timeout multiplier for the QEMU-without-KVM case | ARM runners are treated as too slow to run QEMU at all |

## Recommendation

1. Add a `boot-test` job to `build-image.yml`: `ubuntu-24.04`, `needs: build`,
   pulls `ghcr.io/<owner>/frameless@<digest>` (expose the digest from the build
   job), runs the local install + headless boot, asserts the serial login
   prompt, uploads the serial and install logs. Budget 45 minutes for the KVM
   lane.
2. Add the udev rule and `test -c /dev/kvm` as the first step; if the device is
   missing, run the TCG lane with `-cpu max` and a 60-minute timeout and say so
   in the job summary. Never let the test pass without having booted.
3. Record the wall clock per phase on the first run. Expected with KVM: ~1–3
   min to pull, ~2–5 min to install, ~1–2 min to boot, ~10–15 min total.
   Expected under TCG: boot phase 5–20 min, ~25–35 min total. Replace these
   estimates with measurements.
4. Make it a required check on `main`, and extend the promotion gate so
   `release/ready` means "signed, unmodified, and booted". The current gate
   cannot: `execute-release.yml` passes `run_release_gate: false`.
5. Keep the first iteration to boot only. Add SSH + `systemctl
   is-system-running` once a test user injection exists, then an upgrade or
   rollback phase only if the boot test proves stable.

## Open questions

- Is `degraded` acceptable for the golden path? Needs a recorded baseline of
  failed units from the first successful run before the gate can tighten.
- Does the image's getty generator produce a serial getty from `console=ttyS0`
  alone, or does the image need a `serial-getty@ttyS0` preset? The first run
  answers it; if the prompt does not appear on a healthy image, assert
  `Reached target multi-user.target` instead and fix the getty separately.
- Should the boot test live in `build-image.yml` (gates the testing image) or
  in a separate workflow a fork can delete? The template-versus-fork boundary
  matters: `test-template` is deletable, `test-contract` is not.
- Does the aarch64 shape need its own lane? With no KVM on ARM runners, it is a
  self-hosted runner or a slow TCG lane; decide when the shape exists.
- Should frameless adopt bcvk for a fast per-PR lane? It is the shortest path
  from OCI image to running kernel, but it is KVM-only, needs a cargo install
  (or a pinned binary) on the runner, and skips the install and bootloader
  paths.

## Sources

- GitHub changelog, "Hardware accelerated Android virtualization now
  available" (2024-04-02), including the KVM udev rule —
  <https://github.blog/changelog/2024-04-02-github-actions-hardware-accelerated-android-virtualization-now-available/>
- GitHub docs, GitHub-hosted runners reference — hardware acceleration,
  standard runner sizes for public/private repositories, free standard runners
  on public repos, `ubuntu-slim` limits —
  <https://docs.github.com/en/actions/reference/runners/github-hosted-runners>
- GitHub docs, larger runners reference (billing, macOS nested-virtualization
  limitation) — <https://docs.github.com/en/actions/reference/runners/larger-runners>
- `actions/runner-images#12933`, documentation request for nested
  virtualization (closed without docs) —
  <https://github.com/actions/runner-images/issues/12933>
- `actions/runner-images#14062`, "Please support KVM on ARM runners" —
  maintainer: ARM64 fleet does not surface KVM, nested virt not officially
  supported — <https://github.com/actions/runner-images/issues/14062>
- `actions/runner-images#14549`, `/dev/kvm` missing on `ubuntu-26.04-arm`
  (and the conflicting claim that `ubuntu-24.04-arm` has it) —
  <https://github.com/actions/runner-images/issues/14549>
- `actions/runner-images#13202`, VirtualBox cannot enable AMD-V because
  `kvm_amd` holds it on `ubuntu-24.04` —
  <https://github.com/actions/runner-images/issues/13202>
- `actions/runner-images#14748`, `ubuntu-latest` migrates to 26.04 in November
  2026 — <https://github.com/actions/runner-images/issues/14748>
- bootc CI workflow, `test-integration` (TMT + libvirt on `ubuntu-26.04`,
  "leveraging the support for nested virtualization in the GHA runners"; the
  install-tests job is disabled) —
  <https://github.com/bootc-dev/bootc/blob/main/.github/workflows/ci.yml>
- `bootc-dev/actions`, `bootc-ubuntu-setup` (conditional `/dev/kvm` udev rule,
  `libvirt: true` stack) —
  <https://github.com/bootc-dev/actions/blob/main/bootc-ubuntu-setup/action.yml>
- bootc docs, "Upgrade/rollback failure detection" (composefs
  `bootc-root-setup.service`; no boot entry counting) —
  <https://github.com/bootc-dev/bootc/blob/main/docs/src/bootc-boot-failure-detection.7.md>
- bootc manual, `bootc container lint` ("relatively inexpensive static
  analysis checks") —
  <https://github.com/bootc-dev/bootc/blob/main/docs/src/man/bootc-container-lint.8.md>
- `projectbluefin/testsuite`, `gnome-e2e` composite action (KVM on
  `ubuntu-latest`, udev rule, q35 `accel=kvm`, SSH wait, disk-space note) —
  <https://github.com/projectbluefin/testsuite/blob/main/.github/actions/gnome-e2e/action.yml>
- `projectbluefin/testsuite`, UEFI boot skill (OVMF 4 MB pflash, direct-kernel
  vs UEFI boot times, `bootc switch` + reboot) —
  <https://github.com/projectbluefin/testsuite/blob/main/docs/skills/test-authoring/uefi-boot/SKILL.md>
- `projectbluefin/testsuite`, e2e workflow skill (SSH-mode `common` suite ~15
  min vs ~60 min GUI; 900 s SSH deadline; screenshot/`systemd-analyze`
  capture) —
  <https://github.com/projectbluefin/testsuite/blob/main/docs/skills/ci-ops/e2e-workflow/SKILL.md>
- `projectbluefin/testsuite`, UEFI boot spike workflow —
  <https://github.com/projectbluefin/testsuite/blob/main/.github/workflows/spike-uefi-boot.yml>
- `projectbluefin/common`, post-merge e2e (common suite in SSH mode) —
  <https://github.com/projectbluefin/common/blob/main/.github/workflows/e2e.yml>
- `projectbluefin/actions`, `reusable-execute-release.yml` (`run_release_gate`,
  `gate_suites` default `smoke,common`) —
  <https://github.com/projectbluefin/actions/blob/main/.github/workflows/reusable-execute-release.yml>
- dakota, `boot-test-aarch64.yml` (bcvk, KVM-only, manual, skip without KVM,
  `multi-user.target` gate, serial/journal artifacts) —
  <https://github.com/projectbluefin/dakota/blob/main/.github/workflows/boot-test-aarch64.yml>
- dakota, `publish-smoke.yml` and `run-testsuite.yml` (observational smoke via
  the testsuite reusable) —
  <https://github.com/projectbluefin/dakota/blob/main/.github/workflows/publish-smoke.yml>,
  <https://github.com/projectbluefin/dakota/blob/main/.github/workflows/run-testsuite.yml>
- dakota, local `boot-fast` / `boot-test` / `debug-session` recipes (bcvk,
  KVM-only) — `~/Projects/dakota/Justfile`
- ublue-os/main and ublue-os/bluefin build workflows (secureboot signature
  check, no VM) —
  <https://github.com/ublue-os/main/blob/main/.github/workflows/reusable-build.yml>,
  <https://github.com/ublue-os/bluefin/blob/main/.github/workflows/reusable-build.yml>
- bootc-image-builder integration tests (qcow2 boot via `vmtest`, `/mnt` disk
  workaround) —
  <https://github.com/osbuild/bootc-image-builder/blob/main/.github/workflows/tests.yml>,
  <https://github.com/osbuild/bootc-image-builder/blob/main/test/test_build_disk.py>
- systemd mkosi CI (`no_kvm: 1` lane, `timeout_multiplier=4`) —
  <https://github.com/systemd/systemd/blob/main/.github/workflows/mkosi.yml>
- systemctl manual, `is-system-running` states and `--wait` (maintenance =
  rescue/emergency) — <https://man7.org/linux/man-pages/man1/systemctl.1.html>
- systemd-getty-generator manual (serial getty for `console=`) —
  <https://www.freedesktop.org/software/systemd/man/latest/systemd-getty-generator.html>
- Microsoft Quicksand performance guide (TCG 10–50× slower) —
  <https://microsoft.github.io/quicksand/user-guide/08-performance.html>
- frameless, `Justfile` (`generate-bootable-image`, `boot-vm`), README
  (promotion-gate known gap), and `docs/research/09-image-size.md` (image size)
  — this repository
