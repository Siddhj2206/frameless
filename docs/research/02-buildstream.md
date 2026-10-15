# BuildStream 2

Research notes for frameless, a template for building BuildStream-based OS
images. Written 2026-09-19. Primarily from upstream documentation and source;
secondary or example sources are labelled as such.

Canonical upstream at the time of writing:

- Website: <https://buildstream.build/> (Apache BuildStream; also
  <https://buildstream.apache.org/>)
- Source repository: <https://github.com/apache/buildstream> (Apache-2.0)
- Documentation: <https://docs.buildstream.build/> (latest stable 2.8.0, plus
  the `master` snapshot)
- The old GitLab repository <https://gitlab.com/BuildStream/buildstream> is
  **archived and read-only**; development moved to GitHub under the Apache
  Software Foundation.

---

## 1. What BuildStream is, and where it fits

BuildStream is a declarative software integration tool. You describe a stack of
components in YAML, and it fetches sources, builds them in a controlled sandbox,
caches the results, and assembles filesystem images. The official site summarises
it as "a powerful software integration tool that allows developers to automate
the integration of software components including operating systems"
([buildstream.build](https://buildstream.build/)).

The upstream "why" list names the properties that matter for an OS image
template ([main_about](https://docs.buildstream.build/master/main_about.html)):

- **Declarative build definitions** — "a flexible and extensible framework for
  the modelling of software build pipelines in a declarative YAML format",
  manipulating filesystem data "in a controlled, reproducible sandboxed
  environment".
- **Integrator workflows** — "traceability and reproducibility for integrators
  handling stacks of hundreds/thousands of components", plus workspaces for
  developers.
- **Fast and predictable** — caches previous builds and "only rebuilds the
  things that have changed" (tracked via content-addressed cache keys).
- **Extensible** — plugins for build systems and sources.
- **Bootstrap toolchains and bootable systems** — "can create full systems and
  complete toolchains from scratch, for a range of ISAs including x86_32,
  x86_64, ARMv7, ARMv8, MIPS".

### Versus Containerfiles / Dockerfiles

A Containerfile is an imperative sequence of layer instructions; each `RUN` is
opaque and Docker decides whether to reuse a layer by textual diffing. It has no
model of the dependency graph between components, no per-component cache keys,
no source tracking, and no cross-component integration semantics. BuildStream
models a graph of independently cached elements, so changing one low-level
library invalidates exactly the elements that consume it, and parallel
independent branches. It also separates *building* from *deployment*: the same
artifact can be exported as an OCI image, a sysroot, a tarball, or an OSTree
commit ([Codethink introduction, secondary](https://www.codethink.co.uk/articles/2017/introducing-buildstream);
[makes output formats a first-class capability](https://buildstream.build/)).

### Versus bootc

bootc is a deployment/runtime mechanism: it takes an OCI image and installs or
updates a host from it (`bootc switch`, `bootc upgrade`). It says nothing about
how the image is assembled. BuildStream is the *build* side that can produce the
OCI image bootc consumes. In the Bluefin Dakota pipeline the BuildStream OCI
output is loaded into Podman and switched to with bootc — see section 7. (Dakota
is the sibling project this template is modelled on; treated as a secondary
example source.)

### Versus other OS/image builders

Yocto/BitBake, osbuild, and mkosi all build systems or images, but differ in
model. BuildStream's distinguishing traits are: pure YAML graph, per-element
content-addressed caching, a sandbox per element (BuildBox/bubblewrap on Linux),
and REAPI-based remote caching/execution. There is a useful keynote framing of
"building image-based OSes with BuildStream" from GNOME/freedesktop-sdk
developers ([ASG 2023 talk, secondary](https://www.youtube.com/watch?v=Wku7zBCOyCM)).

Real users listed upstream include freedesktop-sdk, GNOME Build Meta
(gnome-build-meta), carbonOS, Librem, and the WebKitGTK SDK
([buildstream.build](https://buildstream.build/)).

---

## 2. Core model

BuildStream's data model is documented in the Reference and Architecture
sections ([main_core](https://docs.buildstream.build/master/main_core.html),
[main_architecture](https://docs.buildstream.build/master/main_architecture.html),
[arch_data_model](https://docs.buildstream.build/master/arch_data_model.html)).

**Elements** — the unit of build work, parsed from `.bst` files. An element has
a *kind* (the plugin that processes it), sources, dependencies, variables,
environment, config, and public data. Elements are identified by their path
relative to the project's `element-path`, ending in `.bst` (for example
`components/glib.bst`). An *element path* addresses across junctions using `:`,
e.g. `gnome-build-meta.bst:freedesktop-sdk.bst:components/glib.bst`
([format_declaring](https://docs.buildstream.build/master/format_declaring.html)).

**Sources** — inputs fetched for an element, each with its own `kind` and a
`ref` that pins content. Core source kinds are `local`, `remote`, and `tar`;
common external kinds include `git`, `patch`, `cargo`, `pip`, `bzr`, and
`docker` ([core_plugins](https://docs.buildstream.build/master/core_plugins.html),
[buildstream-plugins](https://apache.github.io/buildstream-plugins/index.html)).

**Plugins** — elements and sources are both plugins. BuildStream ships a small
core set; the rest are loaded from `pip`, from `local` project directories, or
across `junction` boundaries. Plugin *defaults* (variables/environment/config)
are shipped in a `.yaml` file next to the plugin
([format_project](https://docs.buildstream.build/master/format_project.html#loading-plugins),
[format_intro](https://docs.buildstream.build/master/format_intro.html#composition)).

**Build graph** — the set of target elements plus everything they depend on,
with unique cache keys computed per element. BuildStream loads the graph,
resolves versions/instructions, computes cache keys, then either pulls artifacts
from cache or builds in sandboxes; finally it transforms and/or deploys the target
([main_about](https://docs.buildstream.build/master/main_about.html)).

**Cache keys and the artifact cache** — each element gets a content-addressed
cache key derived from its config, variables, environment, sources, and its
dependencies (per strict/non-strict build plans;
[arch_cachekeys](https://docs.buildstream.build/master/arch_cachekeys.html)).
Build results are *artifacts*, addressed as
`<project-name>/<element-name>/<cache-key>`. Data lives in Content Addressable
Storage (CAS), indexed by SHA-256; directory and file metadata use REAPI protocol
buffers ([arch_caches](https://docs.buildstream.build/master/arch_caches.html),
[using_commands](https://docs.buildstream.build/master/using_commands.html#artifact-names)).
Source caches similarly map a source key to a directory digest.

### Build vs runtime dependencies

This distinction is central ([format_declaring — dependencies](https://docs.buildstream.build/master/format_declaring.html#dependencies)):

- `build` — the dependency's product is **staged to build** the depending
  element. Build dependencies are *not* visible at runtime, and a build
  dependency does not implicitly pull its own dependents at runtime.
- `runtime` — the dependency's product must be **present for the element to
  function**, but is not visible while building it.
- `all` — the default; both build and runtime.
- `strict: true` — forces a rebuild when the dependency changes even if strict
  mode is off (appropriate when a dependency's output is consumed verbatim, e.g.
  static linking).
- `config` — dependency-level configuration understood by select element kinds,
  e.g. `location` (where to stage it) and `digest-environment` (used with REAPI
  clients in the sandbox). Dependency configuration is illegal on runtime
  dependencies.

Convenience shorthands are `build-depends:` and `runtime-depends:` lists.
Junction elements are connectors only: they cannot be depended on, cannot have
dependencies, and produce no artifacts
([junction](https://docs.buildstream.build/master/elements/junction.html)).

---

## 3. Project layout and configuration

A project is a directory containing a `project.conf`, element `.bst` files,
optional user plugins, and an optional `project.refs`
([format_intro — directory structure](https://docs.buildstream.build/master/format_intro.html#directory-structure)):

```
myproject/project.conf
myproject/project.refs
myproject/elements/element1.bst
myproject/elements/element2.bst
myproject/plugins/customelement.py
myproject/plugins/customelement.yaml
```

### project.conf key fields

From [Project configuration](https://docs.buildstream.build/master/format_project.html):

- `name` — unique project symbol; used for artifact namespacing. Must be in
  `project.conf`, cannot be included.
- `min-version` — **required** minimum BuildStream version (e.g. `2.8`). Also
  cannot be included. New projects get `2.8` from `bst init`.
- `element-path` — subdirectory holding `.bst` files (default `.`). Cannot be
  included.
- `ref-storage` — `inline` (default) or `project.refs` (source refs stored
  centrally in `project.refs`/`junction.refs`).
- `aliases` — named URL prefixes used by sources, e.g. `upstream:`, `pypi:`.
- `mirrors` — named sets of alias→URI mirrors, consulted on fetch and
  reverse-order on track.
- `sandbox` — project-wide sandbox options such as `build-uid`/`build-gid`,
  `build-os`/`build-arch`, and `remote-apis-socket` for REAPI clients.
- `artifacts` — *recommended* remote artifact cache servers (list form in
  BuildStream 2).
- `source-caches` — recommended remote source cache servers.
- `plugins` — plugin origins (`local` with `path`, `pip` with `package-name`
  and version constraints, or `junction` with a junction element). Cannot be
  included.
- `variables` / `environment` / `environment-nocache` — project defaults;
  `environment-nocache` lists variables excluded from cache-key calculation
  (e.g. `MAXJOBS`).
- `split-rules` — the project-wide defaults for the devel/debug/doc/locale
  domains used by `filter`/`compose` and packaging.
- `options` — user-settable project parameters (`bool`, `enum`, `flags`,
  `arch`, `os`, `element-mask`), optionally exported to a variable.
- `junctions` — `duplicates` and `internal` declarations, plus
  `disallow-subproject-uris`.
- `defaults.targets` — default target elements.
- `shell` — shell command, host environment passthrough, and `host-files` bind
  mounts for `bst shell`.

The full builtin defaults (variables such as `%{prefix}`, `%{libdir}`,
`%{install-root}`, `%{build-root}`, the base `environment`, and the default
split-rules) are printed in the
[builtin defaults section](https://docs.buildstream.build/master/format_project.html#builtin-defaults).

### Elements tree, junctions, includes

- Elements live under `element-path` and are referred to by relative paths.
- **Junctions** integrate whole subprojects. A junction element's `sources`
  fetch a BuildStream project, and `config` can pass `options`, select a
  subpath (`path`), override elements (`overrides`), and map aliases
  (`aliases`, `map-aliases`). Cross-junction dependencies use element paths
  ([junction](https://docs.buildstream.build/master/elements/junction.html)).
- **Includes** use the `(@)` directive, which can appear in `project.conf`,
  `.bst` files, or recursively in other includes, and can pull across junctions
  (e.g. `(@): junction.bst:includes/environment.bst`). The including fragment
  wins over included files, and later includes win over earlier ones. `name`,
  `element-path`, `min-version`, and `plugins` cannot come from includes
  ([format_intro — directives](https://docs.buildstream.build/master/format_intro.html#directives)).
- Composition order, from lowest to highest priority: builtin defaults →
  `project.conf` defaults → plugin defaults → `project.conf` plugin overrides →
  the `.bst` declaration ([format_intro — composition](https://docs.buildstream.build/master/format_intro.html#composition)).

---

## 4. The `.bst` element format

An annotated element from the docs
([format_declaring](https://docs.buildstream.build/master/format_declaring.html)):

```yaml
kind: autotools

depends:
  - element1.bst
  - element2.bst

sources:
  - kind: git
    url: upstream:modulename.git
    track: master
    ref: d0b38561afb8122a3fc6bafc5a733ec502fcaed6

variables:
  sysconfdir: "%{prefix}/etc"

environment:
  LD_LIBRARY_PATH: /some/custom/path

config:
  configure-commands:
    - "%{configure} --enable-fancy-feature"

public:
  bst:
    integration-commands:
      - /usr/bin/update-fancy-feature-cache

sandbox:
  build-uid: 0
  build-gid: 0
```

Key fields:

- `kind` — the element plugin. Third-party plugins are namespaced, e.g.
  `kind: buildstream-plugins:dpkg_build`.
- `depends` / `build-depends` / `runtime-depends` — dependency graph (section 2).
- `sources` — list of source plugins; an optional `directory:` stages a source
  into a specific sandbox subdir.
- `variables` — `%{...}` substitutions resolved after composition.
- `environment` — sandbox environment for this element.
- `config` — plugin-specific configuration.
- `public` — metadata visible to reverse dependencies (e.g.
  `bst.integration-commands`, `bst.split-rules`, overlap whitelists)
  ([format_public](https://docs.buildstream.build/master/format_public.html)).
- `sandbox` — per-element sandbox uid/gid, OS, arch.

### BuildElement and command phases

The `manual` element and most build-system plugins derive from `BuildElement`,
which runs four command phases ([core_buildelement](https://docs.buildstream.build/master/core_buildelement.html)):

1. `configure-commands` — run once (important for workspaces); move sources,
   generate configs.
2. `build-commands` — the actual build.
3. `install-commands` — install into `%{install-root}`, which is what gets
   cached. Do not clean up sources (the build tree may be cached).
4. `strip-commands` — debug-symbol stripping; uses `%{strip-binaries}`, which is
   empty by default and must be set per project.

Relevant variables include `%{build-root}`, `%{install-root}`, `%{command-subdir}`,
`%{conf-root}` (source dir for autotools/cmake/meson/setuptools/pip), and
`%{max-jobs}`.

### Common core element kinds

Documented under [Plugin specific documentation](https://docs.buildstream.build/master/core_plugins.html):

| Kind | Purpose |
| --- | --- |
| `import` | Produce an artifact directly from sources, no processing (e.g. import an SDK or config overlay). Config `source`/`target`. |
| `manual` | Basic `BuildElement` with no default commands; you supply `configure-`/`build-`/`install-`/`strip-commands`. |
| `stack` | Symbolic grouping. All deps must be both build and runtime. Produces no content; used for intermediate subsystems and as toplevel targets. |
| `compose` | Selective composition of its build dependencies, normally near the end of a pipeline. Config `integrate`, `include`, `exclude`, `include-orphans` (defaults `True`). |
| `script` | Run arbitrary `config.commands`, staging dependencies at chosen `location`s. Build dependencies only. Used for final assembly steps. |
| `filter` | Extract a subset of a parent element's output using its `bst.split-rules` (`include`/`exclude`/`include-orphans`/`pass-integration`). Exactly one build dependency. |
| `link` | Symbolic link to another element or junction (`config.target`), handy for reuse across junctions. |
| `junction` | Window into another BuildStream project (section 3). |

### Common external element kinds

Loaded from plugin packages rather than core
([core_plugins — external](https://docs.buildstream.build/master/core_plugins.html)):

- [buildstream-plugins](https://apache.github.io/buildstream-plugins/) —
  `autotools`, `cmake`, `make`, `meson`, `pip`, `setuptools`; sources `bzr`,
  `cargo`, `docker`, `git`, `patch`, `pip`.
- [buildstream-plugins-community](https://buildstream.gitlab.io/buildstream-plugins-community/)
  (formerly `bst-plugins-experimental`) — `dpkg_build`, `dpkg_deploy`,
  `flatpak_image`, `flatpak_repo`, `ostree`, `oci`, `x86image`, `snap_image`,
  `collect_manifest`, `collect_integration`, `tar_element`, `bazel_build`,
  `pyproject`, and others.
- [bst-plugins-container](https://buildstream.gitlab.io/bst-plugins-container/) —
  `docker_image`.

There is also the older `bst-external` package
([docs](https://buildstream.gitlab.io/bst-external/)) whose `oci` element is an
ancestor of the community one.

---

## 5. CLI commands and workflow

All commands are documented under
[Commands](https://docs.buildstream.build/master/using_commands.html). A typical
flow:

```sh
# 1. Create a project skeleton
bst init --project-name my-project

# 2. Inspect the graph and cache state
bst show target.bst                 # state: cached/buildable/waiting/...
bst show --deps all target.bst
bst show target.bst --format '%{name} %{kind} %{key} %{state}'

# 3. Fetch and pin source refs
bst source fetch --deps all target.bst
bst source track target.bst         # update refs; --cross-junctions, --deps all
bst source checkout --directory src target.bst

# 4. Build (pulls whatever the cache can supply)
bst build target.bst
bst build --deps run target.bst
bst build --retry-failed target.bst

# 5. Debug and inspect
bst shell target.bst                # runtime sysroot
bst shell --build target.bst        # build sandbox
bst artifact log target.bst
bst artifact list-contents target.bst
bst artifact checkout --directory out target.bst
bst artifact checkout --tar image.tar target.bst

# 6. Share via remotes
bst artifact push --deps all target.bst
bst artifact pull target.bst
bst source push --deps all target.bst
```

Command groups: `bst build`, `bst show`, `bst shell`, `bst init`,
`bst artifact` (`checkout`, `delete`, `list-contents`, `log`, `pull`, `push`,
`show`), `bst source` (`checkout`, `fetch`, `push`, `track`), and
`bst workspace` (`open`, `close`, `reset`, `list`).

Developer workspaces let you work on an element's sources in place:
`bst workspace open`, edit, `bst build` (incremental), then `bst workspace close`
or `reset`. Running bst from a workspace directory uses the workspace element by
default.

Useful global flags: `-C/--directory`, `-o/--option`, `--strict/--no-strict`,
`--artifact-remote`, `--source-remote`, `--ignore-project-artifact-remotes`,
`--ignore-project-source-remotes`, `--max-jobs`, `--builders/--fetchers/--pushers`,
`--on-error continue|quit|terminate`.

---

## 6. Remote caches (artifact and source servers)

Because every element has a deterministic cache key, CI can populate a shared
cache once and every later job can *build-avoid* by pulling artifacts instead of
rebuilding. The same mechanism serves local developer machines. Caches are the
reason BuildStream projects with hundreds of elements are tractable.

Mechanics ([arch_caches](https://docs.buildstream.build/master/arch_caches.html),
[Configuring Cache Servers](https://docs.buildstream.build/master/using_configuring_cache_server.html)):

- BuildStream speaks the **REAPI ContentAddressableStorage** protocol, plus the
  **remote asset** protocol for symbolic names (artifact names)
  ([remote_execution.proto](https://github.com/bazelbuild/remote-apis/blob/main/build/bazel/remote/execution/v2/remote_execution.proto),
  [remote_asset.proto](https://github.com/bazelbuild/remote-apis/blob/main/build/bazel/remote/asset/v1/remote_asset.proto)).
  It can therefore use any conforming server.
- A cache server deployment is split into **index** and **storage** services.
  BuildStream requires both to fetch/push. On download it tries each index until
  it finds the reference, then each storage until the data is retrieved; on
  upload it pushes to each storage with `push: true`, then to each index.
- Known tested open-source implementation: **Buildbarn**
  ([bb-storage](https://github.com/buildbarn/bb-storage) and
  [bb-remote-asset](https://github.com/buildbarn/bb-remote-asset)), with a
  Docker Compose example in the upstream docs.
- Remote execution over REAPI is also supported, and there is a sandbox
  `remote-apis-socket` that lets tools like `recc` cache per-compile actions
  ([using_config — remote execution](https://docs.buildstream.build/master/using_config.html#remote-execution),
  [format_declaring — sandbox](https://docs.buildstream.build/master/format_declaring.html#format-sandbox)).

Configuration lives in three layers
([using_config — remote services](https://docs.buildstream.build/master/using_config.html#remote-services)):

```yaml
# ~/.config/buildstream.conf (or buildstream2.conf)
servers:
  - url: https://cache-server.com/cache:11001
    instance-name: main
    type: all          # storage | index | all
    push: true
    auth:
      server-cert: server.crt
      client-cert: client.crt
      client-key: client.key
      access-token: access.token
    connection-config:
      keepalive-time: 60
      retry-limit: 4
      retry-delay: 1000
      request-timeout: 300

artifacts:
  servers:
    - url: https://artifacts.com/artifacts:11001
      push: true

source-caches:
  servers:
    - url: https://sources.com/sources:11001
      push: true
```

Priority, highest first: command-line remotes (replace all config) → project
specific user config (`projects:`) → global user config → project-recommended
servers in `project.conf`. `override-project-caches` controls whether user
config suppresses project recommendations. Local cache behaviour (quota,
`reserved-disk-space`, `low-watermark`, `pull-buildtrees`, `cache-buildtrees`,
and the optional `storage-service`) is set under `cache:`; the local CAS is
managed by `buildbox-casd`.

The Bluefin Dakota project demonstrates the pattern: its `project.conf`
recommends the GNOME and Project Bluefin caches for both artifacts and sources,
so a cold checkout can pull most of GNOME OS instead of rebuilding it
([Dakota project.conf, secondary](https://github.com/projectbluefin/dakota/blob/testing/project.conf)).

---

## 7. OCI/container output and bootable images

**Core BuildStream 2 does not ship an OCI element.** Core filesystem composition
is done with `compose` and `filter`; anything container-shaped comes from plugin
packages or from a script step.

Two upstream-supported routes:

1. **`oci` element** from
   [buildstream-plugins-community](https://buildstream.gitlab.io/buildstream-plugins-community/elements/oci.html)
   (once `bst-external`). Config takes `mode: oci|docker`, `images:` with
   `parent`/`layer`/`architecture`/`os`/`config`, and produces an *un-tared* OCI
   or Docker layout. It must then be wrapped, e.g.
   `bst artifact checkout --tar image.tar element.bst` followed by
   `podman load -i image.tar`. Layers are computed on top of parents; each `oci`
   element adds one layer; it deliberately adds no creation timestamps for
   reproducibility.
2. **`docker_image` element** from
   [bst-plugins-container](https://buildstream.gitlab.io/bst-plugins-container/elements/docker_image.html).

How downstream projects actually turn artifacts into bootable OS images: the
sibling Bluefin Dakota project (the model for frameless) builds the final OCI
with a **`script` element** rather than an OCI plugin. `elements/oci/bluefin.bst`
stages the composed image at `/layer`, runs post-install steps (sysusers,
GLib schema/dconf compilation, `ldconfig -r /layer`), then invokes freedesktop-sdk's
`build-oci` tool to emit an OCI layout with `containers.bootc: "1"` and an image
ref annotation. Layers are ordinary `kind: compose` elements that filter domains
like `devel`, `debug`, and `static-blocklist`
([Dakota `elements/oci/bluefin.bst`, secondary](https://github.com/projectbluefin/dakota/blob/testing/elements/oci/bluefin.bst);
[Dakota `elements/oci/layers/bluefin.bst`, secondary](https://github.com/projectbluefin/dakota/blob/testing/elements/oci/layers/bluefin.bst)).
The resulting image is exported and loaded with Podman, then deployed with
`bootc switch`; an ISO is produced separately for installation
([Dakota README, secondary](https://github.com/projectbluefin/dakota)).

Historically, GNOME OS and freedesktop-sdk also emitted **OSTree** commits and
later moved toward systemd-sysupdate; freedesktop-sdk's docs describe building
OS images from its artifacts
([freedesktop-sdk OS images guide, secondary](https://freedesktop-sdk.gitlab.io/documentation/guides/building-outputs/building-os.html)).
The `ostree` element and `ostree` source live in
buildstream-plugins-community.

Takeaway for frameless: designing the graph so that a final `compose`/`script`
target produces an OCI layout is the established approach. Keep the image
assembly step separate from component builds so those stay cached.

---

## 8. Version status as of 2026

- **Current stable: BuildStream 2.8.0**, released 2026-08-27, with
  `2.8.1.dev0` tagged on 2026-09-17 for development
  ([GitHub releases](https://github.com/apache/buildstream/releases);
  documentation index lists 2.8.0 as the newest stable
  [docs index](https://docs.buildstream.build/)).
- The docs ship per-version trees: 2.0.1, 2.1.0, 2.3.0, 2.4.1, 2.5.0, 2.6.0,
  2.7.0, 2.8.0, plus `master`
  ([docs index](https://docs.buildstream.build/)).
- `bst init` defaults `min-version` to `2.8` and `element-path` to `elements`
  ([using_commands — bst init](https://docs.buildstream.build/master/using_commands.html#bst-init)).
- **BuildStream 2 is the recommended major line**; the site states it "has been
  released and replaces BuildStream 1, which is now end-of-life, and no longer
  works with Python greater than Python 3.11.x"
  ([buildstream.build](https://buildstream.build/)). The reference manual adds
  that 2 is "the latest stable version" and recommends it for all new projects
  ([docs index](https://docs.buildstream.build/)).
- Project managers can also recommend or require BuildStream 2 via
  `min-version` in `project.conf`.

### Differences from BuildStream 1

The [porting guide](https://docs.buildstream.build/master/main_porting.html)
and [project-format porting page](https://docs.buildstream.build/master/porting_project.html)
enumerate the breaking changes. Highlights:

- **Versioning**: `format-version` removed; `min-version` is now required and
  means "minimum BuildStream 2 release".
- **Caches**: rewritten around REAPI (CAS + remote asset); BuildStream 1
  artifact servers are incompatible. Artifact/source server config became lists
  with a separate `auth` block.
- **Plugins**: most core plugins moved out to
  buildstream-plugins / buildstream-plugins-community / bst-plugins-container.
  Plugin loading redesigned; junction-origin plugin loading is recommended for
  determinism.
- **Junctions**: junction names no longer coalesce matching junctions; `link`
  elements and junction `overrides` handle inheritance/conflicts.
- **CLI**: `bst fetch`→`bst source fetch`, `bst track`→`bst source track`,
  `bst checkout`→`bst artifact checkout`, `bst pull`→`bst artifact pull`,
  `bst push`→`bst artifact push`; remote flags became
  `--artifact-remote`/`--source-remote`; tracking flags split out to
  `bst source track`.
- **Core elements**: `stack` deps must be build+runtime; `script` `layout`
  replaced by per-dependency `location`; default strip commands removed in favour
  of `%{strip-binaries}`; element names must end in `.bst`.
- **Runtime**: BuildStream 2 requires Python ≥ 3.10 (2.7 dropped 3.9;
  [NEWS](https://github.com/apache/buildstream/blob/master/NEWS)) and BuildBox
  (`buildbox-casd`, `buildbox-fuse`, `buildbox-run-bubblewrap`) for sandboxing
  ([main_install](https://docs.buildstream.build/master/main_install.html)).

Canonical docs: <https://docs.buildstream.build/> (stable 2.8 plus `master`),
the project format under `/master/core_format.html`, the plugin reference under
`/master/core_plugins.html`, and the Architecture section under
`/master/main_architecture.html`.

---

## 9. Minimal worked example

Straight from the official tutorial
([first-project](https://docs.buildstream.build/master/tutorial/first-project.html)).
This is the smallest meaningful project: one `project.conf` and one element.

Create the skeleton:

```sh
bst init --project-name first-project
```

`project.conf`:

```yaml
# Unique project name
name: first-project

# Required BuildStream version
min-version: 2.8

# Subdirectory where elements are stored
element-path: elements
```

Add a file the element will import, then declare `elements/hello.bst`:

```sh
touch hello.world
```

```yaml
kind: import

# Use a local source to stage our file
sources:
  - kind: local
    path: hello.world

config:
  # Place the content staged by sources at the root of the output artifact
  target: /
```

Build and observe:

```sh
bst build hello.bst
bst show hello.bst                         # state becomes "cached"
bst artifact checkout --directory here hello.bst
ls here                                    # hello.world
```

That is the whole loop: declare a graph, build it, it lands in the artifact
cache. An OS image project scales this up — many `manual`/build-system elements
for components, `stack`/`compose` elements to group them, and a final
`script`/`oci` element to emit the image (section 7). The upstream tutorial
continues through `bst show`, `bst shell`, autotools elements, integration
commands, and directives
([using_tutorial](https://docs.buildstream.build/master/using_tutorial.html)).

A slightly richer "manual" component would look like:

```yaml
kind: manual

depends:
  - base.bst

sources:
  - kind: git
    url: upstream:hello.git
    track: main
    ref: 0000000000000000000000000000000000000000

variables:
  build-root: /buildstream/%{project-name}/%{element-name}

config:
  configure-commands:
    - ./configure --prefix="%{prefix}"
  build-commands:
    - make -j"%{max-jobs}"
  install-commands:
    - make DESTDIR="%{install-root}" install
```

---

## 10. Further reading

Primary upstream documentation:

- BuildStream website — <https://buildstream.build/> (also
  <https://buildstream.apache.org/>)
- Documentation home (version tree) — <https://docs.buildstream.build/>
- Stable 2.8 manual — <https://docs.buildstream.build/2.8/index.html>
- Master manual (newest) — <https://docs.buildstream.build/master/index.html>
- About / why BuildStream —
  <https://docs.buildstream.build/master/main_about.html>
- Installation —
  <https://docs.buildstream.build/master/main_install.html>
- Getting started tutorial —
  <https://docs.buildstream.build/master/using_tutorial.html>
- Project format — <https://docs.buildstream.build/master/core_format.html>
  - Project configuration —
    <https://docs.buildstream.build/master/format_project.html>
  - Declaring elements —
    <https://docs.buildstream.build/master/format_declaring.html>
  - Builtin public data —
    <https://docs.buildstream.build/master/format_public.html>
- Plugin reference —
  <https://docs.buildstream.build/master/core_plugins.html>
- Commands — <https://docs.buildstream.build/master/using_commands.html>
- User configuration —
  <https://docs.buildstream.build/master/using_config.html>
- Configuring cache servers —
  <https://docs.buildstream.build/master/using_configuring_cache_server.html>
- Remote execution servers —
  <https://docs.buildstream.build/master/using_configuring_remote_execution.html>
- Porting from BuildStream 1 —
  <https://docs.buildstream.build/master/main_porting.html>
- Architecture — <https://docs.buildstream.build/master/main_architecture.html>
  - Data model —
    <https://docs.buildstream.build/master/arch_data_model.html>
  - Cache keys — <https://docs.buildstream.build/master/arch_cachekeys.html>
  - Caches — <https://docs.buildstream.build/master/arch_caches.html>
- Source repository — <https://github.com/apache/buildstream>
- Release notes / NEWS — <https://github.com/apache/buildstream/blob/master/NEWS>
- Releases — <https://github.com/apache/buildstream/releases>

Plugin packages:

- buildstream-plugins — <https://apache.github.io/buildstream-plugins/>
- buildstream-plugins-community —
  <https://buildstream.gitlab.io/buildstream-plugins-community/>
  - `oci` element —
    <https://buildstream.gitlab.io/buildstream-plugins-community/elements/oci.html>
- bst-plugins-container —
  <https://buildstream.gitlab.io/bst-plugins-container/>
- bst-external (older) — <https://buildstream.gitlab.io/bst-external/>

Protocols and related tooling:

- REAPI — <https://github.com/bazelbuild/remote-apis>
- Buildbox — <https://gitlab.com/BuildGrid/buildbox>
- Buildbarn — <https://github.com/buildbarn>

Reference projects (secondary examples):

- freedesktop-sdk — <https://gitlab.com/freedesktop-sdk/freedesktop-sdk>
  - Building OS images —
    <https://freedesktop-sdk.gitlab.io/documentation/guides/building-outputs/building-os.html>
- GNOME Build Meta — <https://gitlab.gnome.org/GNOME/gnome-build-meta/>
- Bluefin Dakota (this template's sibling) —
  <https://github.com/projectbluefin/dakota>
  - `project.conf` —
    <https://github.com/projectbluefin/dakota/blob/testing/project.conf>
  - OCI assembly —
    <https://github.com/projectbluefin/dakota/blob/testing/elements/oci/bluefin.bst>
  - OCI assembly notes —
    <https://github.com/projectbluefin/dakota/blob/testing/docs/oci-assembly.md>
- carbonOS — <https://gitlab.com/carbonOS/build-meta>
- "Building image-based OSes with BuildStream" (ASG 2023 talk) —
  <https://www.youtube.com/watch?v=Wku7zBCOyCM>
