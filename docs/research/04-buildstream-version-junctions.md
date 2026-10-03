# BuildStream version and junction tracks for frameless

Research note answering: which `min-version` and which junction streams/refs
(FSDK, gnome-build-meta, plugins) should a new frameless template track?

Written 2026-09-20. Primary sources only: the BuildStream docs, the
freedesktop-sdk and gnome-build-meta project repos (fetched upstream), and the
three local Bluefin repos. URLs and file paths are cited inline. No file in
`frameless` or the local reference repos was modified.

## TL;DR recommendation

| Setting | Value |
| --- | --- |
| `min-version` | `2.8` |
| FSDK junction `track` | `freedesktop-sdk-26.08*` |
| FSDK junction `ref` | `freedesktop-sdk-26.08.1-0-gb02b59ffe19a49a402f357fd5fcb1d552ebc50d7` |
| gnome-build-meta junction `track` | `gnome-51` |
| gnome-build-meta junction `ref` | `51.0-3-ge34f1eb8c12742aedb1ee65b855c5d88741d9f92` |
| `buildstream-plugins` junction | `2.8.0` |
| `buildstream-plugins-community` junction | `2.3.3` |

The Bluefin repos' `min-version: 2.5` is stale and understated: gnome-build-meta
`gnome-51` and `master` already require `2.6`. Nothing forces `2.5`.

---

## 1. `min-version`: 2.5 is stale, use 2.8

### What the field means

`min-version` is a lower bound, not a pin. The BuildStream project-format docs
state the format "is guaranteed to be backwards compatible with any earlier
minor point releases … Projects are required to specify the minimum version of
BuildStream which it requires" — a useful error message, not an exact match
(<https://docs.buildstream.build/master/format_project.html#minimum-version>).

`bst init` defaults the field to the current stable line; the CLI reference
lists `--min-version` `Default: '2.8'`
(<https://docs.buildstream.build/master/using_commands.html#bst-init>). The
current stable release is 2.8: docs ship the 2.8.0 tree
(<https://docs.buildstream.build/>), and the GitHub releases feed shows
`2.8.0` plus a `2.8.1.dev0` tag dated 2026-09-17
(<https://github.com/apache/buildstream/releases>).

### What upstream actually declares

| Project / ref | `min-version` | Source |
| --- | --- | --- |
| freedesktop-sdk `master` | `2.5` | <https://gitlab.com/freedesktop-sdk/freedesktop-sdk/-/raw/master/project.conf> |
| freedesktop-sdk tag `freedesktop-sdk-26.08.1` | `2.5` | <https://gitlab.com/freedesktop-sdk/freedesktop-sdk/-/raw/freedesktop-sdk-26.08.1/project.conf> |
| gnome-build-meta `gnome-50` | `2.5` | <https://raw.githubusercontent.com/GNOME/gnome-build-meta/gnome-50/project.conf> |
| gnome-build-meta `gnome-51` | `2.6` | <https://raw.githubusercontent.com/GNOME/gnome-build-meta/gnome-51/project.conf> |
| gnome-build-meta `master` | `2.6` | <https://raw.githubusercontent.com/GNOME/gnome-build-meta/master/project.conf> |

The three local Bluefin repos all declare `min-version: 2.5`:
`dakota/project.conf:4`, `fsdk-containers/project.conf:4`,
`server/project.conf:4`.

### Does any junction force 2.5?

No. Nothing requires exactly 2.5, and no junction raises or lowers the parent's
floor:

- **gnome-build-meta does not force 2.5 — it forces ≥ 2.6.** Any graph that
  junctions `gnome-51` or `master` cannot load under BuildStream 2.5, because
  the subproject's `min-version: 2.6` is enforced when the junction is resolved.
  A parent declaring 2.5 is therefore inaccurate; 2.6 is the effective floor.
- **freedesktop-sdk keeps 2.5** for backward compatibility, but that is a floor
  for FSDK alone.
- **Plugin packages carry no project `min-version`.** `buildstream-plugins`
  has no BuildStream dependency pin in its metadata, and
  `buildstream-plugins-community` only declares `buildstream>=2.0`
  (<https://pypi.org/pypi/buildstream-plugins-community/json>).

### Recommendation

`min-version: 2.8`. It is what `bst init` emits, it matches the current stable
line and the toolchain the FSDK `bst2` container will run, and it is a strict
superset of FSDK's 2.5 and GBM's 2.6. `min-version` does not participate in
cache-key computation, so raising it cannot break cache hits.

Caveat worth recording: declaring 2.8 does **not** guarantee cache-key parity
with artifacts in `gbm.gnome.org:11003` or `cache.projectbluefin.io:11001`,
which were produced by whatever bst version upstream CI used. A version gap
shows up as cache misses (rebuilds), not load errors.

---

## 2. Junction streams and refs

### freedesktop-sdk

Use `track: freedesktop-sdk-26.08*`, pinned at the 26.08.1 point release.

- gnome-build-meta `gnome-51` pins exactly
  `ref: freedesktop-sdk-26.08.1-0-gb02b59ffe19a49a402f357fd5fcb1d552ebc50d7`
  with `track: freedesktop-sdk-26.08*`
  (<https://raw.githubusercontent.com/GNOME/gnome-build-meta/gnome-51/elements/freedesktop-sdk.bst>).
  `master` pins the identical ref
  (<https://raw.githubusercontent.com/GNOME/gnome-build-meta/master/elements/freedesktop-sdk.bst>).
- The tags `freedesktop-sdk-26.08.0` and `freedesktop-sdk-26.08.1` exist
  (GitLab tags API:
  <https://gitlab.com/api/v4/projects/freedesktop-sdk%2Ffreedesktop-sdk/repository/tags?search=freedesktop-sdk-26.08>).
- The local repos already track `freedesktop-sdk-26.08*`:
  `dakota/elements/freedesktop-sdk.bst:6` (ref 26.08.1),
  `fsdk-containers/elements/freedesktop-sdk.bst:6` and
  `server/elements/freedesktop-sdk.bst:6` (ref 26.08.0).

The 26.08 line is the current stable stream; 26.08.1 is the newest point
release. Fresh pins should be produced with `bst source track`.

### gnome-build-meta

Use `track: gnome-51`.

- `gnome-51` is the current stable GNOME branch (`variables.branch: '51'`,
  `min-version: 2.6`):
  <https://raw.githubusercontent.com/GNOME/gnome-build-meta/gnome-51/project.conf>.
- Its HEAD is `e34f1eb8c12742aedb1ee65b855c5d88741d9f92` (GitHub mirror branch
  API, fetched 2026-09-20:
  <https://api.github.com/repos/GNOME/gnome-build-meta/branches/gnome-51>).
  With `ref-format: git-describe` that is `51.0-3-ge34f1eb8...` — the exact ref
  dakota already carries at `dakota/elements/gnome-build-meta.bst:7`.
- `gnome-50` (HEAD `fc40697d81202fc2fd113e5e59faefec8ad1a22b`) is the previous
  stable branch and, importantly, still tracks FSDK `25.08*`, not 26.08
  (<https://raw.githubusercontent.com/GNOME/gnome-build-meta/gnome-50/elements/freedesktop-sdk.bst>).
- Prefer `gnome-51` over `gnome-50` precisely for that reason: gnome-51 and
  master both track FSDK 26.08, so frameless stays on one FSDK stream. Tracking
  gnome-50 while pinning FSDK 26.08 is what forces fsdk-containers/server to
  keep FSDK's own `systemd` (their `elements/freedesktop-sdk.bst` comments
  explain that gnome-50 still depends on `components/systemd-base.bst`, which
  FSDK 26.08 dropped).

For a rolling/nightly stream, `master` is the alternative; it also tracks FSDK
`26.08*` and requires 2.6.

---

## 3. Plugin junctions and where they come from

Both plugin origins are `kind: junction` elements registered in `project.conf`,
with `sources` that fetch a release artifact:

- **`buildstream-plugins`** — upstream repo
  <https://github.com/apache/buildstream-plugins>, published to PyPI as the
  `buildstream-plugins` sdist. Usual junction source is `kind: tar` against the
  PyPI artifact (`pypi:` alias → `https://files.pythonhosted.org/packages/`, see
  `dakota/include/aliases.yml:53` and `fsdk-containers/include/aliases.yml:3`).
  FSDK instead junctions the git repo directly at a tag.
- **`buildstream-plugins-community`** — upstream
  <https://gitlab.com/BuildStream/buildstream-plugins-community>, published to
  PyPI as `buildstream-plugins-community`; junction source is the PyPI sdist.

### Versions in the wild

| Source | `buildstream-plugins` | `buildstream-plugins-community` |
| --- | --- | --- |
| PyPI latest | **2.8.0** (2026-08-27) | **2.3.3** (2026-09-04) |
| freedesktop-sdk `26.08.1` | 2.8.0 (git tag, `track: "*.*.*"`) | 2.3.3 |
| gnome-build-meta `gnome-51` | 2.7.0 | 2.3.1 |
| gnome-build-meta `master` | 2.7.0 | 2.3.3 |
| gnome-build-meta `gnome-50` | 2.5.0 (see note) | 2.3.1 |
| local dakota / fsdk / server | 2.5.0 | 2.3.1 |

Sources: PyPI JSON for both packages
(<https://pypi.org/pypi/buildstream-plugins/json>,
<https://pypi.org/pypi/buildstream-plugins-community/json>); FSDK
`elements/plugins/buildstream-plugins.bst` and
`elements/plugins/buildstream-plugins-community.bst` at tag
`freedesktop-sdk-26.08.1`; GBM branch files
`elements/plugins/buildstream-plugins.bst` and
`elements/plugins/buildstream-plugins-community.bst` for `gnome-51`, `master`,
`gnome-50`; local `dakota/elements/plugins/*.bst`,
`fsdk-containers/elements/plugins/*.bst`, `server/elements/plugins/*.bst`.

### Recommendation

Use **buildstream-plugins 2.8.0** and **buildstream-plugins-community 2.3.3**.
They are the current releases, they match FSDK 26.08.1 (the base frameless
composes), and 2.8.0 is the plugin release published alongside BuildStream
2.8.0. The Bluefin repos' 2.5.0/2.3.1 predate this.

Note on dakota's local patch: `dakota/elements/plugins/buildstream-plugins.bst`
pins 2.5.0 *and* carries `patches/buildstream-plugins` for
`apache/buildstream-plugins#91` (the `docker` source rejecting OCI media
types). Before porting that patch, re-check whether it is still needed at
2.8.0; a template without the `docker` source does not need it at all.

---

## 4. Junction compatibility constraints

1. **The consumer overrides gnome-build-meta's FSDK junction.** GBM ships its
   own `elements/freedesktop-sdk.bst`, but every Bluefin repo replaces it with
   the local one via `config.overrides` on the GBM junction:
   `dakota/elements/gnome-build-meta.bst:18`,
   `fsdk-containers/elements/gnome-build-meta.bst:17`,
   `server/elements/gnome-build-meta.bst:18`. This keeps a single FSDK instance
   and lets the parent choose the stream. The override must match the stream the
   GBM branch expects (gnome-51/master → 26.08; gnome-50 → 25.08) or element
   overrides can fail to load.

2. **gnome-build-meta supplies the plugin junctions; the consumer overrides
   them.** GBM's own `project.conf` loads plugins from
   `plugins/buildstream-plugins.bst` and
   `plugins/buildstream-plugins-community.bst`
   (<https://raw.githubusercontent.com/GNOME/gnome-build-meta/gnome-51/project.conf>).
   The Bluefin repos override both onto their local junction elements
   (`dakota/elements/gnome-build-meta.bst:35-36`,
   `fsdk-containers/elements/gnome-build-meta.bst:19-20`,
   `server/elements/gnome-build-meta.bst:20-21`), so the parent controls exact
   plugin versions and patches — including for GBM's elements.

3. **freedesktop-sdk marks its plugin junctions `internal`.** FSDK's
   `project.conf` lists `plugins/buildstream-plugins.bst` and
   `plugins/buildstream-plugins-community.bst` under `junctions.internal`
   (FSDK `project.conf`, tag 26.08.1). Internal junctions never raise
   conflicting-junction errors in dependants, so FSDK's own elements keep using
   FSDK's plugin versions (2.8.0 / 2.3.3) while the consumer's plugins apply to
   the consumer and GBM's elements.

4. **Plugin versions must agree across the graph.** Junction plugin defaults
   from the subproject are ignored and plugins load "in the context of your
   project"; the docs warn that "all projects connected through junction
   elements agree on which versions of API unstable plugin packages to use"
   (<https://docs.buildstream.build/master/format_project.html#loading-plugins>).
   Overriding GBM's plugin junctions with the consumer's is the mechanism that
   keeps this agreement under the consumer's control.

5. **`collect_initial_scripts` comes from GBM.** GBM provides it as a *local*
   plugin; consumers load it across the junction with
   `origin: junction, junction: gnome-build-meta.bst, elements: [collect_initial_scripts]`
   (`dakota/project.conf:120-123`, `fsdk-containers/project.conf:68-71`,
   `server/project.conf:67-70`). This is why the GBM junction is kept even in
   pure-FSDK projects such as fsdk-containers and server.

6. **GBM's fatal warnings are stricter on 51/master**: `overlaps`,
   `unaliased-url`, `unstaged-files` (gnome-51 `project.conf`). Consider
   mirroring these in a new template as a quality gate.

### Suggested `project.conf` fragments

```yaml
name: frameless
min-version: 2.8
element-path: elements

(@):
  - gnome-build-meta.bst:freedesktop-sdk.bst:include/runtime.yml
  - include/aliases.yml

plugins:
  - origin: junction
    junction: plugins/buildstream-plugins.bst
    elements: [autotools, meson, cmake, make]
    sources: [patch]
  - origin: junction
    junction: plugins/buildstream-plugins-community.bst
    elements: [collect_manifest, flatpak_image, flatpak_repo, ostree, pyproject]
    sources: [cargo2, git_module, git_repo, go_module, patch_queue, zip]
  - origin: junction
    junction: gnome-build-meta.bst
    elements: [collect_initial_scripts]

sources:
  git_repo:
    config:
      ref-format: git-describe
```

`elements/freedesktop-sdk.bst`:

```yaml
kind: junction
sources:
- kind: git_repo
  url: gitlab:freedesktop-sdk/freedesktop-sdk.git
  track: freedesktop-sdk-26.08*
  ref: freedesktop-sdk-26.08.1-0-gb02b59ffe19a49a402f357fd5fcb1d552ebc50d7
```

`elements/gnome-build-meta.bst`:

```yaml
kind: junction
sources:
- kind: git_repo
  url: gnome:gnome-build-meta.git
  track: gnome-51
  ref: 51.0-3-ge34f1eb8c12742aedb1ee65b855c5d88741d9f92
config:
  options:
    arch: '%{arch}'
  overrides:
    freedesktop-sdk.bst: freedesktop-sdk.bst
    plugins/buildstream-plugins.bst: plugins/buildstream-plugins.bst
    plugins/buildstream-plugins-community.bst: plugins/buildstream-plugins-community.bst
```

`elements/plugins/buildstream-plugins.bst` and
`elements/plugins/buildstream-plugins-community.bst` are `kind: junction` +
`kind: tar` against the 2.8.0 and 2.3.3 PyPI sdists. Derive `ref` with
`bst source track` (the current Bluefin files show the exact sdist SHA-256
values for the older versions).

---

## Sources

BuildStream primary:

- Minimum version / project config —
  <https://docs.buildstream.build/master/format_project.html#minimum-version>
- `bst init` default `2.8` —
  <https://docs.buildstream.build/master/using_commands.html#bst-init>
- Loading plugins / junction plugin conflicts —
  <https://docs.buildstream.build/master/format_project.html#loading-plugins>
- Documentation index (current stable 2.8) — <https://docs.buildstream.build/>
- Releases / NEWS — <https://github.com/apache/buildstream/releases>,
  <https://raw.githubusercontent.com/apache/buildstream/master/NEWS>

Project upstreams:

- freedesktop-sdk `project.conf` (`master`, tag `26.08.1`) —
  <https://gitlab.com/freedesktop-sdk/freedesktop-sdk/-/raw/master/project.conf>,
  <https://gitlab.com/freedesktop-sdk/freedesktop-sdk/-/raw/freedesktop-sdk-26.08.1/project.conf>
- freedesktop-sdk plugin junctions (tag `26.08.1`) —
  `elements/plugins/buildstream-plugins.bst` (git tag 2.8.0),
  `elements/plugins/buildstream-plugins-community.bst` (2.3.3)
- freedesktop-sdk tags —
  <https://gitlab.com/api/v4/projects/freedesktop-sdk%2Ffreedesktop-sdk/repository/tags?search=freedesktop-sdk-26.08>
- gnome-build-meta `gnome-51`, `gnome-50`, `master` `project.conf`,
  `elements/freedesktop-sdk.bst`, `elements/plugins/*.bst` —
  <https://raw.githubusercontent.com/GNOME/gnome-build-meta/gnome-51/…>
  (same paths for `gnome-50` and `master`)
- gnome-build-meta branch pointers —
  <https://api.github.com/repos/GNOME/gnome-build-meta/branches/gnome-51>,
  <https://api.github.com/repos/GNOME/gnome-build-meta/branches/gnome-50>
- Plugin packages — <https://pypi.org/pypi/buildstream-plugins/json>,
  <https://pypi.org/pypi/buildstream-plugins-community/json>,
  <https://github.com/apache/buildstream-plugins>,
  <https://gitlab.com/BuildStream/buildstream-plugins-community>

Local files read:

- `dakota/project.conf`, `dakota/elements/{freedesktop-sdk,gnome-build-meta}.bst`,
  `dakota/elements/plugins/*.bst`, `dakota/include/aliases.yml`
- `fsdk-containers/project.conf`,
  `fsdk-containers/elements/{freedesktop-sdk,gnome-build-meta}.bst`,
  `fsdk-containers/elements/plugins/*.bst`, `fsdk-containers/include/aliases.yml`
- `server/project.conf`, `server/elements/{freedesktop-sdk,gnome-build-meta}.bst`,
  `server/elements/plugins/*.bst`

No files in the local reference repos or in `frameless` were modified.
