# project.conf anatomy

What each field in frameless's `project.conf` does, and when to touch it.
Canonical source: <https://docs.buildstream.build/master/format_project.html>.

| Field | Purpose | Change it when |
|---|---|---|
| `name` | Artifact namespace; `%{project-name}` | You rename the project |
| `min-version` | Minimum BuildStream release | You need newer BuildStream features |
| `element-path` | Where `.bst` files live | Rarely |
| `(@)` | Include shared YAML fragments | You add a shared fragment |
| `options` | User-settable parameters (`arch`, bools, enums) | You add a build axis |
| `sandbox.build-arch` | Sandbox architecture | Follows `%{arch}` |
| `variables` | Project defaults; identity values | You change image identity |
| `artifacts` | Recommended artifact caches (pull) | Rarely; user/CI config overrides |
| `source-caches` | Recommended source caches (pull) | Rarely |
| `plugins` | Plugin origins (`local`, `pip`, `junction`) | You add a plugin source |
| `sources.git_repo.ref-format` | How git refs are recorded | Rarely |

## Composition order (lowest → highest priority)

builtin defaults → `project.conf` defaults → plugin defaults → `project.conf`
plugin overrides → the `.bst` declaration.

## The `(@)` directive

Pulls YAML from another file — including across a junction, e.g.
`gnome-build-meta.bst:freedesktop-sdk.bst:include/runtime.yml`. The including
file wins over the included one; later includes win over earlier. `name`,
`element-path`, `min-version`, and `plugins` cannot come from an include.

## Plugin origins

- `origin: junction` — load a plugin from a junctioned upstream project (what we
  use)
- `origin: local` — load a Python plugin from `plugins/`
- `origin: pip` — load a plugin from a PyPI package
