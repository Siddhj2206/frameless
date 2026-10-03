# Lesson 3: From graph to OCI image

**Mission link:** you just defined frameless's default target. This is how a
BuildStream graph becomes a bootable OCI image.

## The ladder

```
image/deps.bst                    kind: stack   the package manifest
  └─ oci/layers/image-stack.bst   kind: stack   + bootc filesystem layout
       └─ oci/layers/image.bst    kind: compose  filter out devel/debug
            └─ oci/layers/image-init-scripts.bst   collect_initial_scripts
                 └─ oci/image.bst kind: script   post-install + build-oci
```

Each rung does one thing. `stack` groups and produces no content. `compose`
selects a subset of the filesystem by **domain**. `collect_initial_scripts`
gathers the units and sysusers the compose step declared. `script` runs
arbitrary commands — here, the post-install steps and the OCI emitter.

## Integration commands

The bootc filesystem layout lives in `public.bst.integration-commands` on the
stack, not in an element's `install-commands`. Why: integration commands run
*after* all dependencies are staged, so they are the deterministic winner when
two elements touch the same path. Element-level overrides can lose that race.

## Domains

`compose` drops `devel`, `debug`, and `static-blocklist`. Domains are defined by
each element's `split-rules` (project-wide defaults live in `project.conf`).
That's how the same build can yield a runtime image and a development sysroot.

## The OCI emitter

There is no core OCI element. `oci/image.bst` stages the filtered root at
`/layer`, runs `prepare-image.sh`, `systemd-sysusers`, `glib-compile-schemas`,
`dconf update`, and `ldconfig`, then calls freedesktop-sdk's `build-oci`. That
writes an OCI layout with labels and an index annotation —
`org.opencontainers.image.ref.name` is the `bootc upgrade` origin.

## Check yourself

1. Why are the bootc filesystem steps integration commands rather than an
   element's install commands?
2. What does `compose` exclude, and where are those domains defined?
3. What sets the image's `bootc upgrade` origin?

## Primary source

[Building OS images from freedesktop-sdk](https://freedesktop-sdk.gitlab.io/documentation/guides/building-outputs/building-os.html),
and dakota's `docs/oci-assembly.md` (`~/Projects/dakota`).
