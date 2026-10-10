# One shipped shape, one update mechanism

frameless ships the bootable desktop and nothing else, and it updates by bootc
and nothing else. `base` and `container` are named in the vocabulary and
reachable by editing the manifest or writing a target, but neither is carried as
a target CI builds. `projectbluefin/server` is read for what a server image
contains, not for how it updates.

## Considered options

- **Three shapes, all built.** Rejected: it multiplies CI to prove what the
  shapes share — a spine — and a target that loads but is never built is false
  comfort rather than a seam.
- **One shape, documented in prose.** Rejected on a fact rather than a taste:
  `desktop/gnome.bst` depends on `gnomeos-deps/deps.bst`, which carries the OS
  base as well as the desktop, so deleting the desktop line yields an image with
  no glibc and no systemd. The `elements/core/deps.bst` split is what makes the
  one-line edit true, and it has to exist whether or not a second shape ships.
- **bootc and sysupdate.** Rejected: sysupdate asks this template's user for a
  signing key, a signed release manifest, A/B slot management and a boot server
  before their first boot, where bootc asks for a registry and one command. It
  would also double the open question in "does frameless own the boot spine?"
  before that is answered.
