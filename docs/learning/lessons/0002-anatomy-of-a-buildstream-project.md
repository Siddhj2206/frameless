# Lesson 2: Anatomy of a BuildStream project

**Mission link:** you just locked frameless's skeleton. This is what each piece
is and why it's there.

## The pieces

| Path | What it is |
|---|---|
| `project.conf` | The project's source of truth: identity, junctions, caches, options |
| `elements/*.bst` | The build graph — one file per element |
| `include/*.yml` | Shared YAML fragments, pulled in with `(@)` |
| `plugins/` | Project-local custom plugins (we have none yet) |

## `project.conf` fields we used

- `name` — namespaces every artifact; read by elements as `%{project-name}`
- `min-version` — the minimum BuildStream release (`2.8`)
- `element-path` — where `.bst` files live (`elements`)
- `(@)` — includes `include/aliases.yml` and freedesktop-sdk's `runtime.yml`
- `options.arch` — the architecture axis, read as `%{arch}`
- `sandbox.build-arch` — keeps the sandbox arch consistent
- `variables` — image identity (`image-vendor`, `image-description`)
- `artifacts` / `source-caches` — the public pull-only caches
- `plugins` — where plugin kinds come from (junctioned upstream projects)
- `sources.git_repo.ref-format` — how git refs are recorded

## Junctions

Two windows into other projects: `freedesktop-sdk.bst` (the OS) and
`gnome-build-meta.bst` (the desktop). The consumer **overrides** GBM's own
`freedesktop-sdk.bst` and plugin junctions with ours, so every version in the
graph is the one we pinned — not whatever the upstream happened to carry.

That's the key idea: a junction isn't a copy, it's a *window*, and overrides let
you choose what's seen through it.

## Plugins

BuildStream's core kinds (`import`, `manual`, `stack`, `compose`, `script`,
`filter`, `link`, `junction`) cover composition. Everything else — `autotools`,
`flatpak_image`, `ostree`, `git_repo` — comes from plugin packages, loaded here
through junctions pinned in `elements/plugins/`. `plugins/` is only for plugins
*you* write.

## Check yourself

1. What does `(@)` do, and why does `project.conf` use it?
2. Why does `gnome-build-meta.bst` override `freedesktop-sdk.bst`?
3. Where would a custom element plugin live, and how is it registered?

## Primary source

[Project configuration](https://docs.buildstream.build/master/format_project.html).

Ask me anything this doesn't land.
