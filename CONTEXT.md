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
