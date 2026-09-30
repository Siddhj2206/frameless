# Plan

frameless is the bones for building an image, and the map an agent needs to
find them.

This file states what frameless is. The route through what is not yet decided
lives on the tracker, on the map
**[frameless as bones](https://github.com/Siddhj2206/frameless/issues/64)**.

## The bones are a minimum

A **shape** is what you are building. The **bones** are the least an image of
that shape requires to exist. Everything past that minimum is **payload**, and
payload belongs to the adopter.

| Shape              | Bones                                        | Payload                 |
| ------------------ | -------------------------------------------- | ----------------------- |
| Container          | freedesktop-sdk runtime, an entrypoint       | your application        |
| Bootable, headless | the runtime and the boot spine               | services                |
| Bootable, desktop  | the bootable bones and a desktop junction    | the desktop and its apps |

A desktop image is one payload on the bootable spine. "Your own custom dakota"
is the default instantiation of frameless, not a competing product.

## Two spines

A shape either boots or it does not, and that is the only structural divide in
the graph.

The **container spine** is freedesktop-sdk's runtime and an OCI assembly: no
kernel, no initramfs, no bootc, no `/boot`, no composefs.

The **boot spine** adds the kernel, the initramfs, bootc, the boot layout, and
composefs semantics. It is the same for GNOME, for KDE, and for a headless
server. Because it is the same, the desktop is a leaf, and the multi-shape
claim becomes a partition rather than a promise to maintain N images.

## What the thesis obliges

### The boot spine must not belong to a desktop project

Today it does. bootc arrives as `gnomeos-deps/bootc.bst` and the initramfs as
`gnomeos/generate-initramfs.bst` with `oci/initramfs/*`, all inside
gnome-build-meta. Every bootable frameless image is a GNOME image in its
dependency graph, whatever it ships.

frameless owns `boot/`. gnome-build-meta becomes `desktop/gnome/` and nothing
else. dakota already carries its own bootc override, so the shape of the move
is proven.

### The runtime is a payload

`elements/runtime/` bundles ublue's shared half, brew, and firstboot. It is
vendor-neutral, and it is not required to boot. A homelab server fork should
not inherit a desktop distribution's runtime any more than it should inherit
GNOME.

### The golden path must be boot-tested

CI can build, sign, publish, and promote an image without ever knowing whether
it boots. The emergency-mode failure on the current image reached a VM because
nothing in CI starts a kernel. Bones that do not boot are not bones.

### Each shape needs a skill that routes to it

The differentiator is not the graph; an agent can write a Dockerfile. It is
that a fork's agent can find the right answer in the repository. Today every
skill assumes a bootc GNOME image. A shape is not shipped until the skill that
routes to it is shipped.

## The verification ladder

Three tiers, named honestly, because holding every shape to the golden path's
standard would leave all of them worse.

- **Golden path** — the default target. Built, drift-guarded, boot-tested in
  CI, published, promoted.
- **Supported** — built in CI and drift-guarded, documented, not boot-tested.
- **Documented** — the seam and the checklist. Not built in CI.

A shape moves up a tier when someone pays for it.

## Non-goals

- **Not a distribution.** No package manager of its own, no RPM repository, no
  sysupdate. frameless composes; it does not package.
- **Not a fork of freedesktop-sdk.** Junction it; do not patch it.
- **Not a catalog of finished images.** The shapes are templates; the payload
  is the adopter's.
- **Not a promise that every desktop works.** Each desktop is a junction the
  adopter brings and maintains.
- **Not a boot guarantee on hardware nobody tested.** The ladder says which
  tier a shape is on.

## If frameless joins Project Bluefin

Bluefin's org is already multi-payload — bluefin, aurora, bazzite, server —
which is the shape this plan is built for. Two things to keep straight if it
happens.

frameless stays a template. It encodes no distribution's taste; Bluefin's
images are payloads or forks of it.

`projectbluefin/server` updates by sysupdate and sysext, not bootc. That is a
different spine and it is out of scope here. A homelab server on bootc is in
scope; a sysupdate image is a separate effort.

## See also

- `CONTEXT.md` — the glossary. It needs words for the shape, the spine, and
  the payload before this plan is legible.
- `docs/research/12-core-versus-desktop.md` — the first cut of the split this
  plan generalizes.
- `docs/agents/issue-tracker.md` — how the map and its tickets work.
