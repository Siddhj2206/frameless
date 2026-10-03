# Pruning the BuildStream cache to what upstream cannot re-supply

Research note on shrinking the CI artifact cache — `~/.cache/buildstream` — to
the artifacts that cannot be re-pulled from the read-only caches already in
`project.conf`. It exists to record what was measured, which BuildStream
mechanism actually answers "is this artifact available elsewhere?", and why the
obvious answers do not work.

Measured 2026-09-24 against BuildStream 2.8.1 (the pinned `bst2` container and a
local install) and the three configured caches. Nothing was implemented; this is
the design and its evidence.

## The problem, concretely

`build-image.yml` restores and saves `~/.cache/buildstream` with
`actions/cache` under a key derived from `project.conf` and the two junction
pins. The entry is **14.2 GB**; GitHub's default is **10 GB per repository**, so
it is evicted:

```
$ gh api repos/Siddhj2206/frameless/actions/caches
{"entries":[],"total_count":0,"total_size_in_bytes":null}
```

Every run is therefore cold. The cache is dominated by artifacts *pulled* from
the public caches (`freedesktop-sdk` and `gnome`); those are re-pullable. Only
frameless's own ~12 elements are irreplaceable. The goal is to save the delta,
not the whole graph.

## What "available upstream" is allowed to mean

The remote list must be derived from configuration, never hardcoded. BuildStream
resolves the artifact-cache list **per project** with this priority
(`_context.py:_resolve_specs_for_project`):

1. `--artifact-remote` on the command line,
2. the project-specific user override (`~/.config/buildstream.conf` →
   `projects.<name>.artifacts`),
3. the global user config (`~/.config/buildstream.conf` → `artifacts`),

and then, unless `override-projects` is set, **appends** the project's own
recommendations (`project.conf` → `artifacts:`) plus every junction parent's
recommendations, parent-first, deduplicated.

So a fork that adds another read-only cache to its `project.conf` inherits the
benefit with no change to the mechanism, *provided* the mechanism asks
BuildStream for the resolved list rather than parsing YAML itself.

## Measurements

### Which local refs are remotely available

Every artifact ref under `artifacts/refs/` was checked on all three configured
remotes with the Remote Asset `FetchBlob` (the oracle argued below). Local cache
from a partial build, so absolute counts differ from CI; the proportions are the
point.

| project | local refs | remotely available |
|---|---|---|
| `freedesktop-sdk` | 947 | **947** |
| `gnome` | 538 | **538** |
| `frameless` (ours) | 28 | **0** |
| `first-project` (test fixture) | 2 | **0** |
| **total** | **1515** | **1485** |

Every upstream ref is available; none of ours is. That is exactly the partition
we want to act on — and it falls out of the data, not a project-name rule.

### Where the bytes are

Refs are tiny pointers; the bytes are CAS objects (`casdir = <cache>/cas`,
`artifactdir = <cache>/artifacts/refs`; `_context.py:342-344`). A reachability
walk from the ref protos (described below) accounts for essentially all of it:

| root set | reachable |
|---|---|
| `frameless` refs only | **154.2 MB** |
| `frameless` + `first-project` refs | 154.2 MB |
| all artifact refs | 21319.6 MB |
| `frameless`+`first-project` refs + all source-cache refs | 1807.1 MB |
| all artifact refs + all source-cache refs | 22968.4 MB |
| `cas/objects` total | 22980.7 MB / 738 851 objects |

Two conclusions: upstream artifacts are ~21.3 GB of the ~23 GB local CAS, and a
reachability walk from artifact + source refs covers **99.95 %** of it. The walk
is faithful enough to prune with; there is almost no unreferenced garbage to
worry about.

## The oracle that works: Remote Asset `FetchBlob`

BuildStream names an artifact `<project>/<element>/<key>` and resolves it on the
remote **index** with the Remote Asset API:

```
uri = "urn:fdc:buildstream.build:2020:artifact:" + artifact_name
response = index_remote.fetch_blob([uri])          # OK iff the name resolves
```

Source: `_artifactcache.py:26` (URN template), `_artifactcache.py:_query_remote`
(line 468), `_assetcache.py:AssetRemote.fetch_blob` (line 115). This is the same
call BuildStream makes in `element._cached_remotely()`
(`element.py:1192`), which `bst artifact show` renders as `available`
(`widget.py:1045`).

Direct probes against the three configured caches (empty instance name, TLS,
SHA-256) confirm it:

```
gbm.gnome.org:11003       FetchBlob gnome/…/0652aa62…            -> OK
                          FetchBlob freedesktop-sdk/…/657fee53…  -> OK
                          FetchBlob frameless/…/0652aa62…        -> NOT_FOUND
cache.projectbluefin.io   FetchBlob gnome/…                      -> OK
cache.freedesktop-sdk.io  FetchBlob freedesktop-sdk/…            -> OK
```

### The naming trap is real, and the local ref avoids it

The URN embeds the producing *project's* name. Junctioned elements carry their
own project's name — the local cache stores `gnome/…` and `freedesktop-sdk/…`,
**not** the top-level `frameless/…`, and not the junction element's file name
(`gnome-build-meta` is a `.bst` file; the project it loads is named `gnome`). If
a tool reconstructs the name from the current project (e.g. `frameless/<element>/
<key>`), every cross-project lookup misses. The probe above verifies both
directions: the correct prefix resolves, the `frameless/` prefix is
`NOT_FOUND` for the same element and key.

**Therefore: query the local ref verbatim.** It already contains the right
project name because BuildStream wrote it that way. Do not recompute names from
the graph.

This also explains an earlier observation in this directory's notes that `bst
artifact show` reports local state only. It does query remotes
(`_stream.py:_resolve_cached_remotely`, line 1519), but only for elements that
are **not cached locally**, and it uses each element's **current** cache key as
computed from the loaded graph. `bst artifact show --deps none
freedesktop-sdk.bst:components/linux.bst` printed `not cached` even though the
`freedesktop-sdk` cache holds hundreds of fsdk artifacts — the current key need
not equal the published one. `artifact show` is a graph view; the ref-based
probe is a cache view. For pruning we need the cache view.

## The oracle that does not work: REAPI `FindMissingBlobs`

The artifact ref file is the serialized `Artifact` proto, and the CAS stores
that same blob (`_artifactcache.py:113`, `add_object(...)`; verified: the local
ref's `sha256` equals the digest `gbm.gnome.org` returns for its URN). The
digest is project-independent, so `FindMissingBlobs` looked attractive.

It is unusable: `GetCapabilities` succeeds (SHA-256) but `FindMissingBlobs`
returns **HTTP 404 / UNIMPLEMENTED** on all three caches, with every instance
name tried. These servers expose CAS *fetches* through the local
`buildbox-casd` proxy, not a directly queryable CAS. It is also the wrong layer:
"the blob is in the CAS" is not "the artifact name resolves on the index".
Rejected.

## The reclamation problem (why refs alone are not enough)

Deleting a ref frees nothing. `bst artifact delete` calls `ArtifactCache.remove`
→ `remove_ref` → `utils._remove_path_with_parents` — it unlinks the ref file
only (`_assetcache.py:453-473`). There is no blob-delete RPC in the local CAS
protocol (`local_cas.proto` has Fetch/Upload/Capture, no Remove), so
BuildStream cannot delete a CAS object.

The CAS is pruned only by `buildbox-casd`'s LRU eviction under
`cache.quota`/`low-watermark`/`reserved-disk-space`
(`casdprocessmanager.py:97-107`; `using_config.rst:165-212`). That is
availability-blind, and BuildStream hardcodes `--protect-session-blobs`
(`_context.py:739`), so a run cannot even evict blobs it used. Quota cannot
implement "delete what upstream can re-supply".

So the mechanism has two stages: **decide with `FetchBlob`, reclaim with a
reachability walk**.

### The reachability walk

From the retained refs, collect the digests they reference, then walk the CAS:

- `Artifact.files`, `buildtree`, `sources`, `buildroot`,
  `buildsandbox.subsandbox_digests` are **directory** digests — parse the CAS
  object as `remote_execution_pb2.Directory` and recurse into
  `files[].digest` (file blobs) and `directories[].digest` (more directories).
- `Artifact.logs[].digest`, `low_diversity_meta`, `high_diversity_meta`, and
  **`public_data`** are **file** blobs. Note `artifact.proto` documents
  `public_data` as "digest of a directory", but it is a YAML file in practice
  (parsing it as `Directory` raises `DecodeError`); a walk that trusts the
  comment silently truncates.
- `Source.files` is a directory digest.

Everything in `cas/objects/<hash[:2]>/<hash[2:]>` not reached is dead to the
retained refs and is deleted. The walk above is what produced the size table and
covered 99.95 % of the tree, so it is complete for this version.

## Proposed mechanism

A small Python program run **inside the pinned `bst2` container**, the same
environment `just bst` uses (the host has no usable BuildStream). It reuses
BuildStream's own code for both resolution and query:

```python
# 1. Resolve the configured artifact remotes exactly as a build does.
app = App.create(main_options)          # directory=".", config=<--config>
with app.initialized():                 # loads project.conf + junctions
    app.context.initialize_remotes(connect_artifact_cache=True, connect_source_cache=False)
    specs = app.context.project_artifact_cache_specs   # per project -> [RemoteSpec]
    # unique by url; each spec push=False here (project.conf is read-only)

# 2. For each local ref, ask each index remote (BuildStream's own call).
for ref in walk(app.context.artifactdir):          # artifacts/refs/**
    uri = "urn:fdc:buildstream.build:2020:artifact:" + ref
    for remote in index_remotes:
        if remote.fetch_blob([uri]):               # _assetcache.py
            prune.add(ref); break

# 3. Reclaim: keep the retained refs + the reachable object closure; drop the rest.
#    Build the pruned tree with hardlinks (cheap, same filesystem) and swap it in,
#    so a walk bug cannot destroy the original until the swap.
```

Stage 3 is generic and does not depend on the remote list. Stage 2 is the
opposite: it depends only on the resolved spec list, so a fork's extra
`project.conf` cache is picked up automatically.

### Source cache

**Prune it.** Source refs (`source_protos/`, `elementsources/`) point into the
same CAS and hold ~1.65 GB here. Sources are re-fetchable from their upstream
URLs (and the configured source caches), and once our artifacts are retained the
next build has no reason to re-fetch them unless one of *our* elements actually
rebuilds. Keeping them still fits the 10 GB budget (~1.8 GB total), so a fork
that values source-fetch time over size may keep them; dropping them is the
smaller, still-safe default.

## Alternatives rejected

| Option | Why not |
|---|---|
| REAPI `FindMissingBlobs` on the cache key | 404/UNIMPLEMENTED on all three caches; also the wrong layer (CAS presence ≠ index resolution). |
| `FetchBlob` with names recomputed from the current project | Misses every cross-project artifact — verified `NOT_FOUND` for the `frameless/` prefix. Use the local ref. |
| Parse the build log for `Pulled` vs `Built` | Fragile, text-format dependent, and only covers the current invocation; misses everything restored from a previous cache. |
| Pull-then-delete ("pull every element, delete what succeeds") | Downloads the entire graph, defeating the purpose and risking the 6-hour job cap. |
| `cache.quota` / casd LRU | Availability-blind; `--protect-session-blobs` is hardcoded on, so it cannot even prune the current session. |
| Delete refs only | Reclaims nothing; the bytes are in the CAS, and there is no CAS delete. |
| Hardcode the three URLs, or "prune every project except `frameless`" | Violates the genericity requirement: a fork's own read-only or writable cache would be pruned out from under it. |

## Risks and unresolved questions

- **Private API coupling.** `App`, `Context.initialize_remotes`,
  `project_artifact_cache_specs` and `AssetRemote.fetch_blob` are internal. The
  pinned `bst2` digest makes drift a deliberate act, and the note above ties
  each to its source location, but a BuildStream bump must revisit this.
- **Reachability correctness.** A missed reference type deletes a live blob
  (rebuild or re-pull, not corruption, since blobs are content-addressed). The
  `public_data` trap shows the walk cannot be written from the proto comments
  alone. Build with hardlinks and swap, or copy to a fresh directory and save
  that, so the original survives a bug; add a `--dry-run` that prints projected
  bytes first.
- **Index vs storage.** `FetchBlob` proves the *index* resolves the name; a
  read-only cache could in principle have lost the underlying blobs. This is the
  same signal BuildStream trusts when it decides to pull, so the mechanism
  introduces no new risk.
- **Writable caches.** The rule is only correct for caches you can re-pull from.
  If a configured cache is where *you* push your own artifacts (`push: true`),
  deleting the local copy could delete the only copy. Project `artifacts:` here
  are read-only, and the fork in question uses a separate writable cache; a
  hardening pass should skip `push: true` remotes in the availability oracle.
- **Failed builds.** The workflow saves cache `if: always()`. A failed
  element's artifact is not remotely available, so it is retained. That is
  usually desirable (the next run should not repeat it), but it means the saved
  cache can contain failures; decide deliberately.
- **The parallel line of investigation.** This prunes around the 10 GB limit.
  The other approach — a writable remote CAS that holds our delta — removes the
  need to cache the artifact tree on GitHub at all; if it lands, this mechanism
  may still be worth keeping for the second-order win, or may be dropped.

## Sources

- BuildStream 2.8.1 source, pinned `bst2`
  `registry.gitlab.com/freedesktop-sdk/infrastructure/freedesktop-sdk-docker-images/bst2@sha256:99fc77b5…`:
  - `src/buildstream/_artifactcache.py` — `REMOTE_ASSET_ARTIFACT_URN_TEMPLATE`
    (26), `pull` (154), `check_remotes_for_element` (251), `_query_remote` (468).
  - `src/buildstream/_assetcache.py` — `AssetRemote.fetch_blob` (115),
    `get_remotes` (351), `remove_ref` (453-473).
  - `src/buildstream/_context.py` — `casdir`/`artifactdir` (342-344),
    `initialize_remotes` (592), `_resolve_specs_for_project` (771),
    `protect_session_blobs=True` (739).
  - `src/buildstream/_stream.py` — `artifact_show` (794),
    `_resolve_cached_remotely` (1519).
  - `src/buildstream/_frontend/widget.py` — `show_state_of_artifacts` (1007-1052).
  - `src/buildstream/element.py` — `get_artifact_name` (579), `_cached_remotely`
    (1192).
  - `src/buildstream/_cas/cascache.py` — `objpath` (325), no delete.
  - `src/buildstream/_cas/casdprocessmanager.py` — `--quota-high/low`,
    `--protect-session-blobs` (97-107).
  - `src/buildstream/_protos/build/bazel/remote/asset/v1/remote_asset.proto`;
    `src/buildstream/_protos/buildstream/v2/{artifact,source}.proto`.
  - `doc/source/using_config.rst` (cache quota, attributes, 165-212);
    `doc/source/using_commands.rst` (artifact commands, 200-230).
- BuildStream docs: <https://docs.buildstream.build/master/using_config.html>,
  <https://docs.buildstream.build/master/using_commands.html>,
  <https://docs.buildstream.build/master/arch_caches.html>.
- Endpoint probes from the `bst2` container and locally, 2026-09-24: gRPC
  `GetCapabilities` (OK, SHA-256), `FindMissingBlobs` (404 across all instance
  names), Remote Asset `FetchBlob` (OK/NOT_FOUND as quoted).
- CI cache state: `gh api repos/Siddhj2206/frameless/actions/caches`.
- This repo: `project.conf` (`artifacts:`, `source-caches:`),
  `.github/workflows/build-image.yml` (restore/save steps),
  `docs/research/06-ci-caching-personal-account.md`,
  `docs/research/08-writable-remote-cas.md`.
