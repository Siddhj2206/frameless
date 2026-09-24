# frameless

A template for building your own bootc operating system image from a
[BuildStream](https://buildstream.build/) graph. You declare what the image is
made of — an OS base, a desktop, a runtime — and BuildStream builds and caches
each piece and composes the result. There is no Containerfile and no shell script
that installs packages.

It composes two junctions: [freedesktop-sdk](https://gitlab.com/freedesktop-sdk/freedesktop-sdk)
(the OS) and [gnome-build-meta](https://gitlab.gnome.org/GNOME/gnome-build-meta)
(the desktop). The desktop is one element you can swap for KDE, niri, or nothing.
The [ublue runtime](https://github.com/projectbluefin/common) — `ujust`, Homebrew,
Flatpak preinstalls — is bundled. The rest is yours.

It is built to be driven by hand or by an agent. **New to BuildStream? Start with
the [`buildstream` skill](.agents/skills/buildstream/SKILL.md).**

## What Makes this Raptor Different?

Here are the changes from [Base Image Name]. This image is based on
[Bluefin/Bazzite/Aurora/etc] and includes these customizations:

### Added Packages (Build-time)

- List the elements you add to `elements/image/deps.bst`

### Added Applications (Runtime)

- **CLI tools (Homebrew)**: list them
- **GUI apps (Flatpak)**: list them

### Removed or Disabled

- List anything removed from the base image

### Configuration Changes

- Desktop environment changes (the `desktop/` element)
- Other notable modifications

_Last updated: [date]_

> This section is what tells your users how your image differs from its base.
> Update it whenever you add or remove a package, app, or service.

## Quick start

1. **Create your repository** — "Use this template" on GitHub.
2. **Rename the project.** The identity is literal only in `project.conf`:
   `name:` is the image name, and `image-vendor`, `image-description`,
   `image-repo-url` and `image-code-name` are under `variables:`. The os-release
   URLs and the OCI source label all derive from `image-repo-url`, so a fork
   changes it once. Everything else reads them by reference, and
   `just test-contract` fails if they drift. Grep for `frameless` afterwards to
   catch the prose and the examples.
3. **Finish setup.** [The `onboarding` skill](.agents/skills/onboarding/SKILL.md)
   carries the rest — enabling Actions, auto-merge and workflow permissions, the
   Renovate token, the `stable` branch, branch protection, and the labels. Every
   step has a `gh` command and a GitHub-website route.

## What's included

**Build**

- A BuildStream graph that builds a bootc OCI image
- A build on every push to `main`, publishing `:stable-testing`
- A graph-load gate (`just bst show`) that fails fast when the graph cannot load
- Renovate through `projectbluefin/actions`, updating pinned actions and
  digests every six hours
- Images older than 90 days pruned automatically
- Keyless OIDC signing on every published image

**Runtime**

- Homebrew, pre-staged at build time and unpacked on first boot
- Flatpaks declared in `custom/flatpaks/`, installed on first boot
- `ujust` shortcuts for the Brewfiles and for re-applying configuration

## Customize

The image is a graph. You change it in three places:

- **Your own declarations** — `custom/` (Brewfiles, ujust, Flatpaks, files,
  config). [The `customize` skill](.agents/skills/customize/SKILL.md) decides
  which.
- **Image content** — a line in `elements/image/deps.bst`.
- **The desktop** — replace `elements/desktop/gnome.bst` for KDE, niri, or a
  no-GUI image.

## Releases

| Branch   | Image tag         | Audience                       |
| -------- | ----------------- | ------------------------------ |
| `main`   | `:stable-testing` | Testers and release candidates |
| `stable` | `:stable`         | Production                     |

Merging to `main` publishes `:stable-testing`; the promotion PR that follows
publishes `:stable` when merged. Promotion verifies the cosign signature on the
testing image before it reports ready, and refuses to promote at all once `main`
has moved past the commit the promotion PR was built from.

> **Known gap:** the promotion gate checks the digest and the signature only. It
> runs no end-to-end tests, so `release/ready` means "signed and unmodified",
> not "functionally validated".

## Image signing

Images are signed with keyless OIDC via Cosign and GitHub Actions. There is no
key to generate or store.

```bash
cosign verify \
  --certificate-identity-regexp="https://github.com/your-username/your-repo-name/.github/workflows/" \
  --certificate-oidc-issuer="https://token.actions.githubusercontent.com" \
  ghcr.io/your-username/your-repo-name:stable
```

Unsigned images fail the promotion gate, so `main → stable` reports
`release/blocked` until signing is restored.

## Using your image

Switch to a built image:

```bash
sudo bootc switch --transport registry ghcr.io/your-username/your-repo-name:stable-testing
sudo systemctl reboot
```

Then, as your user:

```bash
ujust install-default-apps    # Homebrew: the default Brewfile
ujust install-dev-tools       # Homebrew: the development Brewfile
ujust configure-dev-groups    # add yourself to docker and libvirt
ujust install-config          # re-apply the image defaults, backing up yours
```

First boot unpacks Homebrew and installs the declared Flatpaks; both need a
network connection. Check them with `systemctl status brew-setup.service` and
`systemctl status flatpak-preinstall.service`.

## Local testing

`bst` is not installed locally; `just bst` runs it in the pinned container.

```bash
just bst show oci/image.bst --deps none   # load the graph, no build
just build                                # build + load the OCI image into podman
just generate-bootable-image              # install it to bootable.raw via bootc
just boot-vm                              # boot that disk in QEMU
just test-unit                            # run the test suite
```

## Troubleshooting

[The `troubleshooting` skill](.agents/skills/troubleshooting/SKILL.md) covers
build, CI, and runtime failures symptom-first. The two most common first-boot
surprises:

- **No Flatpaks.** `flatpak-preinstall.service` needs a network connection and
  reports success even when it cannot reach Flathub, so a first boot before
  Wi-Fi is configured installs nothing. Reboot once you are online.
- **No `brew`.** `brew-setup.service` unpacks Homebrew on first boot; check its
  status before reaching for a reinstall.

## Learn more

- [BuildStream](https://buildstream.build/) — and the local
  [`buildstream` skill](.agents/skills/buildstream/SKILL.md)
- [freedesktop-sdk](https://gitlab.com/freedesktop-sdk/freedesktop-sdk) and
  [gnome-build-meta](https://gitlab.gnome.org/GNOME/gnome-build-meta) — the two
  junctions
- [bootc](https://containers.github.io/bootc/)
- [Universal Blue](https://universal-blue.org/)

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md).
