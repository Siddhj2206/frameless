# Lesson 4: Identity has one source of truth

**Mission link:** you just wired frameless's identity. This is how a BuildStream
image tells the world who it is — and why it's defined once.

## Where identity lives

`project.conf` holds the name and vendor. Everything else *reads* them:

- `%{project-name}` → the image name
- `%{image-vendor}` → the vendor
- `%{image-description}` → the description

Rename the project in one place and the image, its labels, and its `bootc`
origin all follow.

## What gets written

`include/os-release.yml` generates three things:

- `/usr/lib/os-release` — what bootc, GNOME, and every Linux tool reads
- `/etc/os-release` → symlink to it (standard)
- `/usr/share/ublue-os/image-info.json` — what the ublue runtime (fastfetch,
  `ublue-*`) reads

The ublue fields (`IMAGE_NAME`, `IMAGE_VENDOR`, `IMAGE_REF`, `IMAGE_FLAVOR`,
`IMAGE_TAG`) exist because the bundled runtime expects them. `IMAGE_REF` is the
`bootc upgrade` origin and must match the OCI `ref.name` from the assembly.

## The override pattern

GNOME OS ships its own os-release element. We don't edit it — we **override** it
at the junction:

```yaml
oci/integration/os-release.bst: oci/os-release.bst
```

That's the same lever as the plugin junctions: a junction is a window, and
`overrides` chooses what's seen through it. You can substitute any upstream
element with your own without forking the upstream project.

## The contract

Identity is defined once and consumed by reference. The contract test asserts
exactly that: `project.conf` is the only literal, and the generator uses
`%{project-name}`/`%{image-vendor}` rather than restating them. finpilot needed a
test to police three files; BuildStream needs one to confirm there's still only
one.

## Check yourself

1. Name the three files the identity generator writes, and who reads each.
2. What does the junction `overrides` entry `oci/integration/os-release.bst:
   oci/os-release.bst` do?
3. Why must `IMAGE_REF` agree with the OCI `ref.name`?

## Primary source

[The `os-release` spec](https://www.freedesktop.org/software/systemd/man/latest/os-release.html),
and dakota's `include/os-release.yml` (`~/Projects/dakota`).
