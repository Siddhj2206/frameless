# BuildStream cheat sheet

The compressed model. Full notes: `docs/research/02-buildstream.md`. Canonical
source: <https://docs.buildstream.build/>.

## The one idea

A Containerfile is a recipe of opaque layers; BuildStream is a graph of
independently cached **elements**. You declare the graph in YAML and the tool
decides what to run.

## Four nouns

| Noun | What it is |
|---|---|
| **element** | A node, parsed from a `.bst` file, keyed by a plugin `kind` |
| **source** | A pinned input (`git`, `tar`, `docker`, `local`, …) |
| **junction** | A window into another BuildStream project |
| **artifact** | The cached output of an element |

## Cache keys

Each element gets a content-addressed key derived from its config, variables,
environment, sources, and its dependencies. Change an input and exactly the
elements that consume it rebuild. This is why a shared cache makes a
hundreds-of-components project tractable.

## Dependencies

- `build` — staged to build the element; not present at runtime
- `runtime` — present at runtime; not visible while building
- `all` — both (the default)
- `strict: true` — force a rebuild when the dependency changes

## Core element kinds

`import`, `manual`, `stack`, `compose`, `script`, `filter`, `link`, `junction`.
External: `autotools`/`cmake`/`meson`/`make`, `oci`, `dpkg_build`, `ostree`, …

## CLI

```sh
bst show target.bst            # graph + cache state
bst build target.bst           # build (pulls from cache where possible)
bst shell target.bst           # runtime sysroot
bst artifact checkout target.bst --directory out
bst source track target.bst    # update pinned refs
```

## How an image is made

`stack` (group) → `compose` (assemble the filesystem) → `script` calling
freedesktop-sdk's `build-oci` → an OCI layout, loaded with Podman and deployed
with `bootc switch`. There is no core OCI element; the final step is a script.
