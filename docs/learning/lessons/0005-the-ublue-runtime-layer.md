# Lesson 5: The ublue runtime layer

**Mission link:** you just bundled the software that makes a frameless image
behave like a Bluefin-family OS. This is what that layer is, and where the line
between the platform and the product runs.

## What "the ublue runtime" is

Four pieces, each an element under `elements/runtime/`:

| Element | Upstream | Brings |
| --- | --- | --- |
| `common.bst` | `projectbluefin/common` (git) | the ujust base recipes, Homebrew integration, `ublue-system-setup`/`ublue-user-setup` |
| `brew.bst` | `ublue-os/brew` (git) | the brew-setup/update units and helpers |
| `brew-tarball.bst` | `ghcr:ublue-os/brew` (docker) | the prebuilt Homebrew tree, so brew exists on first boot |
| `firstboot.bst` | local `files/` | boot menu timeout, install date, the flatpak-preinstall guard |

`common` and `brew` are **sources**: a git repo or an OCI image whose
`system_files/` are copied into the image. This is the same idea as finpilot's
`COPY --from=common /system_files`, moved into BuildStream.

## `shared/` versus `bluefin/`

`projectbluefin/common` ships two halves. `system_files/shared/` is the
vendor-neutral platform; `system_files/bluefin/` is Bluefin's product opinion
(branding, wallpapers, gschema overrides). finpilot overlaid only `shared/` and
deliberately skipped `bluefin/`; dakota, being Bluefin, installs both. frameless
installs `shared/` only — a template should not bake one distro's taste into
every fork. The `custom/` seam is how a fork opts in.

## The sandbox needs a shell, and 26.08 stopped providing one

FSDK 26.08 slimmed `public-stacks/runtime-minimal.bst` down to libraries.
On 25.08 it also carried bash and coreutils, which is what gave manual
elements a working `sh`. Every element that runs build commands now
build-depends on `core/sandbox-tools.bst` (bash, coreutils, gcc-libs) rather
than relying on its runtime base. Widen *that* stack, not each element.

## Upstream elements that cannot load in a fork

`gnome-build-meta.bst:gnomeos/initramfs/signed-modules.bst` signs every kernel
module with `files/boot-keys/MODULES.key`. That private key is not in the public
repository, so the element fails at load with *"Specified path … does not
exist"* — in any fork. The fix is not to patch it but to **override** it at the
junction with an element that stages the modules unsigned:

```yaml
gnomeos/initramfs/signed-modules.bst: kernel/unsigned-modules.bst
```

That is the junction-override lever from lesson 4, used to replace something
that cannot work rather than something you dislike.

## Check yourself

1. Which half of `projectbluefin/common` does frameless install, and why?
2. Why does every manual element build-depend on `core/sandbox-tools.bst` on
   FSDK 26.08?
3. What is the difference between patching `signed-modules.bst` and overriding
   it?

## Primary source

`~/Projects/dakota/elements/bluefin/{common,brew,brew-tarball,firstboot-*}.bst`
and `elements/core/sandbox-tools.bst`; the upstream projects
`projectbluefin/common` and `ublue-os/brew`.
