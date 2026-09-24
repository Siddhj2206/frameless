---
name: customize
description: >-
  Decide where a package, app, or command belongs — a BuildStream element, a
  Brewfile, a Flatpak preinstall, or a ujust recipe — and how each is validated.
  Use when adding or removing something from the image.
---

# Customize

## Where does it go?

| The thing is… | Put it in | Installed |
|---|---|---|
| A system package the image needs to boot or run | an element in `elements/image/deps.bst` | at build time |
| A CLI tool a user chooses to have | `custom/brew/*.Brewfile` | on demand, by the user |
| A GUI application | `custom/flatpaks/*.preinstall` | on first boot |
| A command that configures the system | `custom/ujust/*.just` | from first login |
| A system file: unit, preset, tmpfiles.d | `custom/files/` | at build time |
| Per-user config for new accounts | `custom/config/` | at build time, into `/etc/skel` |

The dividing line is who decides and when: build time for what the image must
have, runtime for what the user chooses. `custom/README.md` is the seam map.

## By destination

### Build-time packages

There is no `dnf`. The image is assembled from BuildStream elements; a package
is an element in the `elements/image/deps.bst` stack, or a `kind: manual`
element that installs one. Prefer an element the base already provides:
`gnome-build-meta.bst:gnomeos-deps/…` and `freedesktop-sdk.bst:components/…`
carry most of what a desktop needs. `elements/ublue/` shows the shape of a
manual element that copies an upstream project's files.

Editing the stack is editing `elements/image/deps.bst`; never add content by
patching a built artifact.

### Homebrew

Brewfiles in `custom/brew/`, plus a `ujust` recipe so users install it by name.
[custom/brew/README.md](../../../custom/brew/README.md) has the format.
`just validate-brewfiles` checks them without evaluating Ruby.

### Flatpak

Preinstall declarations in `custom/flatpaks/`. The app must exist on Flathub;
`just validate-flatpaks` checks.
[custom/flatpaks/README.md](../../../custom/flatpaks/README.md) has the format and
the first-boot behaviour.

### ujust

Recipes in `custom/ujust/`. No `dnf5` or `rpm` — the image is immutable.
[custom/ujust/README.md](../../../custom/ujust/README.md) has the recipe shape.

### System files and user config

`custom/files/` mirrors `/`; `custom/config/` seeds `/etc/skel/.config/`. Each
directory's README has the semantics.

## Removing something

The reverse of adding: delete the line or the file, then check nothing still
references it. A package removed from the stack may still arrive as a dependency
of another element; `just bst show <element> --deps all` shows what pulls it in.

## Validate

```bash
just check                 # Justfile and every *.just
just test-unit             # the suite
just validate-brewfiles    # if custom/brew changed
just validate-flatpaks     # if custom/flatpaks changed
just bst build oci/image.bst   # if the image changed
```

CI runs `validate-brewfiles`, `validate-flatpaks`, and `validate-justfiles` on
every pull request, and the build workflow builds the image.
