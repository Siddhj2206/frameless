# frameless

frameless is a BuildStream template for building your own OS image — to dakota
what finpilot is to Bluefin. This glossary fixes the vocabulary the skills and
docs use. It is a glossary, not a spec.

## Language

**frameless**:
This project. A minimal, forkable BuildStream template for building your own OS
image.
_Avoid_: the image (that belongs to the adopter), finpilot (the predecessor)

**finpilot**:
The bootc/OCI/RPM template frameless replaces. Legacy reference for feature
scope only.
_Avoid_: the base, the parent

**dakota**:
Project Bluefin's BuildStream desktop image; the pattern frameless follows.
_Avoid_: bluefin (ambiguous with the product line)

**element**:
BuildStream's unit of build work, parsed from a `.bst` file and keyed by a
plugin `kind`.
_Avoid_: node, layer, package

**source**:
A pinned input to an element (`git`, `tar`, `docker`, `local`, …).
_Avoid_: dependency (that is a graph edge, not an input)

**junction**:
A window into another BuildStream project, addressed as
`name.bst:path/element.bst`.
_Avoid_: submodule, include

**artifact**:
The cached output of an element.
_Avoid_: layer, image

**cache key**:
The content-addressed identity of an element's inputs; what decides whether it
rebuilds.
_Avoid_: hash, checksum

**scaffold**:
frameless's product shape — a minimal, forkable starting point with one default
target, not a finished image.
_Avoid_: skeleton, boilerplate

**shape**:
What you are building, named. A shape is a spine, a payload and a target taken
together. frameless ships one: the bootable desktop.
_Avoid_: variant, flavour, profile

**spine**:
The elements that make an image bootable — kernel modules, initramfs, bootc, and
the filesystem layout bootc expects. A container has no spine.
_Avoid_: boot layer, boot chain, base

**payload**:
What an image carries past the minimum its shape requires: a desktop, a runtime,
services, an application. The payload list is `elements/image/deps.bst`.
_Avoid_: content, packages

**target**:
The element that assembles an image and labels it. A target that depends on a
spine is bootable; one that does not, is not.
_Avoid_: top-level element, output

**container**, **base**, **desktop**:
The three shapes the vocabulary names. `desktop` is what frameless builds.
`base` is the same target with the desktop line removed from the manifest.
`container` is the only shape that needs a target of its own, because it has no
spine.
_Avoid_: server (a use of `base`), headless (how `base` looks, not what it is)

**ublue runtime**:
The common/brew/flatpak/ujust content, re-derived as BuildStream elements rather
than layered OCI images.
_Avoid_: ublue layer

**custom/ seam**:
The adopter-facing declaration point for runtime bits — Brewfiles, Flatpaks,
ujust recipes.
_Avoid_: custom layer

**default target**:
The single image frameless builds by default.
_Avoid_: base image (that is the base stack)

**promotion**:
Moving the exact tested digest from `main` to `stable`.
_Avoid_: release, deploy
